import 'dart:async';
import 'dart:io';
import 'dart:math' as math;
import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:network_suite_shared/network_suite_shared.dart';
import '../../core/app_theme.dart';
import '../../core/constants.dart';
import '../../data/repositories/topology_repository.dart';
import '../../data/services/arp_service.dart';
import '../../data/services/demo_data_generator.dart';
import '../../data/services/export_service.dart';
import '../../data/services/icmp_service.dart';
import '../../data/services/network_adapter_service.dart';
import '../../data/services/shared_device_service.dart';
import '../../data/services/traceroute_service.dart';
import '../../data/services/inter_app_launcher.dart';
import '../../domain/models/cancellation_token.dart';
import '../../domain/models/inter_app_arguments.dart';
import '../../domain/models/network_adapter_info.dart';
import '../../domain/models/network_edge.dart';
import '../../domain/models/network_node.dart';
import '../../domain/models/scan_progress.dart';
import '../../domain/models/trace_hop.dart';
import '../../domain/models/trace_result.dart';

enum TopologyViewMode {
  graph,
  table,
  split,
}

class TopologyViewModel extends ChangeNotifier {
  final TopologyRepository _repository;
  final TracerouteService _tracerouteService;
  final ArpService _arpService;
  final IcmpService _icmpService;
  final SharedDeviceService _sharedDeviceService;

  StreamSubscription<void>? _dbSubscription;
  CancellationToken? _currentScanToken;
  bool _disposed = false;
  Timer? _throttleTimer;
  bool _needsNotify = false;
  InterAppArguments? _initialArgs;

  // View State
  List<NetworkAdapterInfo> _adapters = [];
  NetworkAdapterInfo? _selectedAdapter;
  String _targetInput = '';
  int _concurrency = AppConstants.defaultConcurrency;
  int _maxHops = AppConstants.defaultMaxHops;
  ScanProgress _scanProgress = const ScanProgress();
  TopologyViewMode _viewMode = TopologyViewMode.graph;
  String _searchQuery = '';
  String? _statusBannerText;
  bool _isSharedDbConnected = false;
  Map<String, ArpDeviceEntry> _cachedArp = {};

  // Getters
  List<NetworkAdapterInfo> get adapters => List.unmodifiable(_adapters);
  NetworkAdapterInfo? get selectedAdapter => _selectedAdapter;
  Map<String, NetworkNode> get nodes => _repository.nodes;
  Map<String, NetworkEdge> get edges => _repository.edges;
  List<TraceResult> get traces => _repository.traces;
  String get localHostIp => _repository.localHostIp;
  String? get gatewayIp => _repository.gatewayIp;
  String? get selectedNodeId => _repository.selectedNodeId;
  NetworkNode? get selectedNode => _repository.selectedNode;
  String get targetInput => _targetInput;
  int get concurrency => _concurrency;
  int get maxHops => _maxHops;
  ScanProgress get scanProgress => _scanProgress;
  TopologyViewMode get viewMode => _viewMode;
  String get searchQuery => _searchQuery;
  String? get statusBannerText => _statusBannerText;
  bool get isSharedDbConnected => _isSharedDbConnected;
  bool get isScanning => _scanProgress.isScanning;

  Set<String> get activePathNodeIds => _repository.getActivePathNodeIds();
  Set<String> get activePathEdgeIds => _repository.getActivePathEdgeIds();

  List<NetworkNode> get selectedPathBreadcrumbs =>
      selectedNodeId != null ? _repository.getPathBreadcrumbs(selectedNodeId!) : const [];

  List<NetworkNode> getPathBreadcrumbs(String targetId) =>
      _repository.getPathBreadcrumbs(targetId);

  List<NetworkNode> get filteredNodes {
    final list = _repository.nodes.values.toList();
    if (_searchQuery.trim().isEmpty) return list;
    final q = _searchQuery.toLowerCase().trim();
    return list.where((n) {
      return n.ip.toLowerCase().contains(q) ||
          (n.hostname?.toLowerCase().contains(q) ?? false) ||
          (n.sharedDeviceName?.toLowerCase().contains(q) ?? false) ||
          (n.macAddress?.toLowerCase().contains(q) ?? false) ||
          (n.vendor?.toLowerCase().contains(q) ?? false) ||
          (n.deviceCategoryKey?.toLowerCase().contains(q) ?? false);
    }).toList();
  }

  TopologyViewModel({
    TopologyRepository? repository,
    TracerouteService? tracerouteService,
    ArpService? arpService,
    IcmpService? icmpService,
    SharedDeviceService? sharedDeviceService,
    InterAppArguments? initialArgs,
    bool autoInit = true,
  })  : _repository = repository ?? TopologyRepository(),
        _tracerouteService = tracerouteService ?? TracerouteService(),
        _arpService = arpService ?? ArpService(),
        _icmpService = icmpService ?? IcmpService(),
        _sharedDeviceService = sharedDeviceService ?? SharedDeviceService(),
        // ignore: prefer_initializing_formals
        _initialArgs = initialArgs {
    if (autoInit) {
      _initServices();
    }
  }

  /// Safe notifyListener calls that guard against disposed state.
  void _notify() {
    if (!_disposed) {
      _throttleTimer?.cancel();
      _needsNotify = false;
      notifyListeners();
    }
  }

  /// Throttled notify to prevent hundreds of rebuilds/sec during high-concurrency sweeps.
  void _notifyThrottled([Duration interval = const Duration(milliseconds: 60)]) {
    if (_disposed) return;
    if (_throttleTimer?.isActive ?? false) {
      _needsNotify = true;
      return;
    }
    notifyListeners();
    _throttleTimer = Timer(interval, () {
      if (_disposed) return;
      if (_needsNotify) {
        _needsNotify = false;
        notifyListeners();
      }
    });
  }

  Future<void> _initServices() async {
    try {
      await _sharedDeviceService.init();
      _isSharedDbConnected = SharedDeviceDatabase.instance.isInitialized;
      _dbSubscription = _sharedDeviceService.onDatabaseChanged.listen((_) {
        _syncSharedMetadata();
      });
    } catch (_) {}

    // Read initial ARP cache
    _cachedArp = await _arpService.readSystemArpCache();

    // Discover network adapters and auto-select primary adapter
    await refreshAdapters();

    // If no adapters were discovered, fallback to default detection
    if (_adapters.isEmpty) {
      final localIp = await _arpService.detectLocalHostIp();
      final gwIp = await _arpService.detectDefaultGateway();
      _repository.setLocalHost(localIp, gatewayIp: gwIp);

      if (_targetInput.isEmpty) {
        final parts = localIp.split('.');
        if (parts.length == 4 && localIp != '127.0.0.1') {
          _targetInput = '${parts[0]}.${parts[1]}.${parts[2]}.0/24';
        } else {
          _targetInput = '192.168.1.0/24';
        }
      }
    }

    _repository.enrichNodes(
      arpCache: _cachedArp,
      sharedDeviceService: _sharedDeviceService,
    );

    // If initial launch arguments were provided (CLI cold launch), process them
    if (_initialArgs != null) {
      final args = _initialArgs!;
      _initialArgs = null;
      await handleIncomingCommand(
        target: args.target,
        adapterIp: args.adapterIp,
        adapterName: args.adapterName,
        autoStart: args.autoStart,
      );
    }

    _notify();
  }

  /// Refreshes network adapter list and retains/picks current selection.
  Future<void> refreshAdapters() async {
    try {
      _adapters = await NetworkAdapterService.getAvailableAdapters();
      if (_adapters.isNotEmpty) {
        // Select best adapter: non-loopback with valid IP and gateway, or first non-loopback
        NetworkAdapterInfo? best;
        if (_selectedAdapter != null) {
          best = _adapters.firstWhere(
            (a) => a.id == _selectedAdapter!.id || a.name == _selectedAdapter!.name,
            orElse: () => _adapters.first,
          );
        } else {
          best = _adapters.firstWhere(
            (a) => !a.isLoopback && a.ipAddress != '127.0.0.1' && a.ipAddress != '0.0.0.0' && a.gatewayIp != null,
            orElse: () => _adapters.firstWhere(
              (a) => !a.isLoopback && a.ipAddress != '127.0.0.1' && a.ipAddress != '0.0.0.0',
              orElse: () => _adapters.first,
            ),
          );
        }
        selectAdapter(best, autoPopulateTarget: _targetInput.isEmpty);
      }
    } catch (_) {}
    _notify();
  }

  /// Selects the network adapter to carry out discovery and sets local host attributes.
  void selectAdapter(NetworkAdapterInfo adapter, {bool autoPopulateTarget = true}) {
    _selectedAdapter = adapter;

    String? localSharedName;
    if (adapter.macAddress != null && adapter.macAddress!.isNotEmpty) {
      final resolved = _sharedDeviceService.resolveDeviceInfo(adapter.macAddress!);
      if (resolved != null) {
        localSharedName = resolved.friendlyName;
      }
    }

    _repository.setLocalHost(
      adapter.ipAddress,
      gatewayIp: adapter.gatewayIp,
      macAddress: adapter.macAddress,
      vendor: adapter.vendor,
      sharedName: localSharedName,
    );

    if (autoPopulateTarget && adapter.subnetCidr.isNotEmpty) {
      _targetInput = adapter.subnetCidr;
    }

    _repository.enrichNodes(
      arpCache: _cachedArp,
      sharedDeviceService: _sharedDeviceService,
    );
    _notify();
  }

  /// Matches a network adapter by exact IP match first (primary key),
  /// followed by case-insensitive interface name or id match (secondary fallback).
  static NetworkAdapterInfo? matchAdapter(
    List<NetworkAdapterInfo> adapters, {
    String? adapterIp,
    String? adapterName,
  }) {
    if (adapters.isEmpty) return null;

    // 1. Primary match: exact physical IP address match
    if (adapterIp != null && adapterIp.trim().isNotEmpty) {
      final targetIp = adapterIp.trim();
      for (final a in adapters) {
        if (a.ipAddress == targetIp) {
          return a;
        }
      }
    }

    // 2. Secondary match: case-insensitive interface name or id match
    if (adapterName != null && adapterName.trim().isNotEmpty) {
      final targetName = adapterName.trim().toLowerCase();
      for (final a in adapters) {
        if (a.name.toLowerCase() == targetName || a.id.toLowerCase() == targetName) {
          return a;
        }
      }
    }

    return null;
  }

  /// Selects the matching network adapter if found in the available adapters.
  void selectMatchingAdapter({
    String? adapterIp,
    String? adapterName,
    bool autoPopulateTarget = false,
  }) {
    if (_adapters.isEmpty) return;
    final matched = matchAdapter(
      _adapters,
      adapterIp: adapterIp,
      adapterName: adapterName,
    );
    if (matched != null) {
      selectAdapter(matched, autoPopulateTarget: autoPopulateTarget);
    }
  }

  /// Handles incoming commands from CLI arguments or warm handoff loopback IPC socket.
  Future<void> handleIncomingCommand({
    String? target,
    String? adapterIp,
    String? adapterName,
    bool autoStart = false,
  }) async {
    // 1. Ensure adapters are loaded if not ready
    if (_adapters.isEmpty) {
      await refreshAdapters();
    }

    // 2. Select matching adapter if provided
    if (adapterIp != null || adapterName != null) {
      selectMatchingAdapter(
        adapterIp: adapterIp,
        adapterName: adapterName,
        autoPopulateTarget: false,
      );
    }

    // 3. Set incoming target if provided
    if (target != null && target.trim().isNotEmpty) {
      setTargetInput(target.trim());
    }

    // 4. Trigger sweep if autoStart is true
    if (autoStart) {
      if (_scanProgress.isScanning) {
        await cancelSweep();
      }
      await startSweep();
    }
  }

  /// Derives the appropriate CIDR subnet to scan in ARP Scout for [node].
  ///
  /// Returns an empty string if the node is unresponsive or has an anonymous hop IP.
  /// If the node is on the local adapter's subnet, returns the adapter's CIDR.
  /// For routed remote hops/endpoints, defaults to a /24 subnet.
  String deriveSubnetForNode(NetworkNode node) {
    if (node.isUnresponsive || node.ip.isEmpty || node.ip.startsWith('anon:')) {
      return '';
    }

    if (node.isLocalHost && _selectedAdapter != null && _selectedAdapter!.subnetCidr.isNotEmpty) {
      return _selectedAdapter!.subnetCidr;
    }

    if (_selectedAdapter != null && _selectedAdapter!.subnetCidr.isNotEmpty) {
      final calc = NetworkAdapterInfo.calculateSubnetCidr(
        node.ip,
        _selectedAdapter!.prefixLength,
      );
      if (calc == _selectedAdapter!.subnetCidr) {
        return _selectedAdapter!.subnetCidr;
      }
    }

    return NetworkAdapterInfo.calculateSubnetCidr(node.ip, 24);
  }

  /// Outbound integration: Launches ARP Scout to scan the subnet associated with [node].
  Future<void> launchArpScoutForNode(BuildContext context, NetworkNode node) async {
    final subnet = deriveSubnetForNode(node);
    if (subnet.isEmpty) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Cannot scan subnet for unresponsive hop.'),
            duration: Duration(seconds: 2),
          ),
        );
      }
      return;
    }

    try {
      await InterAppLauncher.launchSubnetScan(
        subnetCidr: subnet,
        currentAdapter: _selectedAdapter,
        autoStart: true,
      );
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Triggered ARP Scout scan on $subnet'),
            duration: const Duration(seconds: 2),
            backgroundColor: const Color(0xFF10B981),
          ),
        );
      }
    } catch (e) {
      if (context.mounted) {
        if (e.toString().contains('not found')) {
          _promptUserToLocateArpScout(context, subnet);
          return;
        }

        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Could not launch ARP Scout: $e'),
            duration: const Duration(seconds: 3),
            backgroundColor: const Color(0xFFEF4444),
          ),
        );
      }
    }
  }

  void _promptUserToLocateArpScout(BuildContext context, String subnet) {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: AppTheme.surfaceContainerHigh,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(12),
          side: const BorderSide(color: AppTheme.border),
        ),
        title: const Row(
          children: [
            Icon(Icons.radar, color: AppTheme.primaryAccent, size: 22),
            SizedBox(width: 10),
            Text('Locate ARP Scout', style: TextStyle(color: Colors.white, fontSize: 16)),
          ],
        ),
        content: const Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Net Route Scout could not automatically locate the ARP Scout application on this system.',
              style: TextStyle(color: Colors.white70, fontSize: 13),
            ),
            SizedBox(height: 10),
            Text(
              'Please locate the ARP Scout executable (arp_scout.exe on Windows, arp_scout on Linux/macOS). Net Route Scout will remember this location for all future launches.',
              style: TextStyle(color: Colors.white60, fontSize: 12),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(),
            child: const Text('Cancel', style: TextStyle(color: Colors.white60)),
          ),
          ElevatedButton.icon(
            style: ElevatedButton.styleFrom(
              backgroundColor: AppTheme.primaryAccent,
              foregroundColor: Colors.white,
            ),
            onPressed: () async {
              Navigator.of(ctx).pop();
              try {
                final result = await FilePicker.pickFiles(
                  dialogTitle: 'Select ARP Scout Executable or Application',
                  type: Platform.isWindows ? FileType.custom : FileType.any,
                  allowedExtensions: Platform.isWindows ? ['exe'] : null,
                );
                if (result.isNotEmpty) {
                  final pickedPath = result.first.path;
                  if (pickedPath != null && (await File(pickedPath).exists() || await Directory(pickedPath).exists())) {
                    await InterAppLauncher.saveCustomArpScoutPath(pickedPath);
                    if (context.mounted) {
                      ScaffoldMessenger.of(context).showSnackBar(
                        SnackBar(
                          content: Text('Saved ARP Scout path: $pickedPath'),
                          backgroundColor: const Color(0xFF10B981),
                          duration: const Duration(seconds: 2),
                        ),
                      );
                      await InterAppLauncher.launchSubnetScan(
                        subnetCidr: subnet,
                        currentAdapter: _selectedAdapter,
                        autoStart: true,
                      );
                    }
                  }
                }
              } catch (err) {
                if (context.mounted) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(
                      content: Text('Error selecting ARP Scout: $err'),
                      backgroundColor: const Color(0xFFEF4444),
                    ),
                  );
                }
              }
            },
            icon: const Icon(Icons.folder_open, size: 16),
            label: const Text('Browse for Executable...'),
          ),
        ],
      ),
    );
  }

  void setTargetInput(String value) {
    _targetInput = value;
    _notify();
  }

  void setConcurrency(int value) {
    _concurrency = value.clamp(1, 16);
    _notify();
  }

  void setMaxHops(int value) {
    _maxHops = value.clamp(1, 30);
    _notify();
  }

  void setViewMode(TopologyViewMode mode) {
    _viewMode = mode;
    _notify();
  }

  void setSearchQuery(String query) {
    _searchQuery = query;
    _notify();
  }

  void selectNode(String? nodeId) {
    _repository.selectNode(nodeId);
    _notify();
  }

  void clearSelection() {
    _repository.selectNode(null);
    _notify();
  }

  void clearGraph() {
    _repository.clear();
    _scanProgress = const ScanProgress();
    _statusBannerText = null;
    _notify();
  }

  /// Cancels any running scan immediately.
  Future<void> cancelSweep() async {
    _currentScanToken?.cancel();
    _icmpService.cancel();
    _tracerouteService.cancel();
    _scanProgress = _scanProgress.copyWith(
      phase: 'Scan Cancelled by User',
      isScanning: false,
    );
    _statusBannerText = 'Sweep cancelled by user.';
    _notify();
  }

  /// Starts the 2-phase discovery pipeline:
  /// Phase 1: Pre-flight ICMP ping sweep with queue worker pool
  /// Phase 2: Multi-hop OS native traceroute sweep with sequential live hop ingestion
  Future<void> startSweep() async {
    if (_scanProgress.isScanning) return;

    final targetIps = IcmpService.expandTargetSpec(_targetInput, maxHosts: AppConstants.maxSweepHosts);
    if (targetIps.isEmpty) {
      _statusBannerText = 'Invalid target specification. Enter a valid IPv4, CIDR (e.g. 192.168.1.0/24), or range.';
      _notify();
      return;
    }

    final totalExpected = IcmpService.calculateTargetCount(_targetInput);
    if (totalExpected > AppConstants.maxSweepHosts) {
      _statusBannerText = 'Target range expanded to $totalExpected hosts. Capped to first ${AppConstants.maxSweepHosts} hosts for performance.';
    } else {
      _statusBannerText = null;
    }

    final token = CancellationToken();
    _currentScanToken = token;

    _scanProgress = ScanProgress(
      phase: 'Phase 1: Pre-Flight ICMP Sweep (Pinging ${targetIps.length} hosts)...',
      totalTargets: targetIps.length,
      completedTargets: 0,
      activeWorkers: _concurrency,
      isScanning: true,
    );
    _notify();

    // Harvest ARP cache in parallel
    _cachedArp = await _arpService.readSystemArpCache();

    // Phase 1: ICMP Ping Sweep (if single IP, skip sweep and trace directly)
    List<String> liveHosts;
    if (targetIps.length == 1) {
      liveHosts = targetIps;
    } else {
      liveHosts = await _icmpService.sweepActiveHosts(
        targetIps,
        concurrency: 16,
        timeoutMs: 350,
        sourceIp: _selectedAdapter?.ipAddress,
        cancelToken: token,
        onProgress: (completed, total, currentIp, reached) {
          if (_disposed || token.isCancelled) return;
          _scanProgress = _scanProgress.copyWith(
            completedTargets: completed,
            currentTarget: currentIp,
          );
          _notifyThrottled();
        },
      );
    }

    if (_disposed || token.isCancelled) return;

    // Refresh ARP table to catch all newly probed MACs
    _cachedArp = await _arpService.readSystemArpCache();

    // Fallback if ICMP ping got no responses (e.g. Windows Firewall blocks ICMP echo)
    if (liveHosts.isEmpty) {
      final targetSet = targetIps.toSet();
      final arpDiscovered = _cachedArp.keys.where((ip) => targetSet.contains(ip)).toList();
      if (arpDiscovered.isNotEmpty) {
        liveHosts = arpDiscovered;
      } else if (targetIps.length <= 16) {
        liveHosts = targetIps;
      }
    }

    if (liveHosts.isEmpty) {
      _scanProgress = const ScanProgress(
        phase: 'No responsive hosts found in target range',
        isScanning: false,
      );
      _statusBannerText = 'No responsive hosts answered ICMP ping or ARP in the specified range.';
      _notify();
      return;
    }

    // Phase 2: OS Traceroute Sweep
    _scanProgress = ScanProgress(
      phase: 'Phase 2: Tracing Multi-Hop Network Routes (${liveHosts.length} active targets)...',
      totalTargets: liveHosts.length,
      completedTargets: 0,
      activeWorkers: _concurrency,
      isScanning: true,
    );
    _notify();

    // Track cumulative in-flight hops to prevent fake star edges and false target markings
    final inFlightHops = <String, List<TraceHop>>{};

    await _tracerouteService.sweepTargets(
      liveHosts,
      concurrency: _concurrency,
      maxHops: _maxHops,
      timeoutMs: 1000,
      sourceIp: _selectedAdapter?.ipAddress,
      cancelToken: token,
      onHopDiscovered: (targetIp, hop) {
        if (_disposed || token.isCancelled) return;
        final list = inFlightHops.putIfAbsent(targetIp, () => []);
        final idx = list.indexWhere((h) => h.depth == hop.depth);
        if (idx >= 0) {
          list[idx] = hop;
        } else {
          list.add(hop);
        }
        list.sort((a, b) => a.depth.compareTo(b.depth));
        _repository.ingestPartialHops(targetIp, list);
        _notifyThrottled();
      },
      onTargetCompleted: (completed, total, currentIp, result) {
        if (_disposed || token.isCancelled) return;
        inFlightHops.remove(currentIp);
        _repository.ingestTraceResult(result);
        _scanProgress = _scanProgress.copyWith(
          completedTargets: completed,
          currentTarget: currentIp,
        );
        _repository.enrichNodes(
          arpCache: _cachedArp,
          sharedDeviceService: _sharedDeviceService,
        );
        _notify();
      },
    );

    if (_disposed || token.isCancelled) return;

    // Final ARP and reverse DNS enrichment
    _cachedArp = await _arpService.readSystemArpCache();
    _repository.enrichNodes(
      arpCache: _cachedArp,
      sharedDeviceService: _sharedDeviceService,
    );

    // Resolve reverse-DNS in background using a bounded worker pool (up to 8 concurrent lookups)
    final nodesToResolve = _repository.nodes.values
        .where((n) => !n.isLocalHost && !n.isUnresponsive && (n.hostname == null || n.hostname!.isEmpty))
        .toList();

    if (nodesToResolve.isNotEmpty && !token.isCancelled && !_disposed) {
      var dnsIdx = 0;
      Future<void> dnsWorker() async {
        while (dnsIdx < nodesToResolve.length && !token.isCancelled && !_disposed) {
          final node = nodesToResolve[dnsIdx++];
          try {
            final host = await _arpService.reverseDns(
              node.ip,
              timeout: const Duration(milliseconds: 1500),
            );
            if (host != null && !_disposed && !token.isCancelled) {
              _repository.updateNodeHostname(node.ip, host);
              _notifyThrottled();
            }
          } catch (_) {}
        }
      }

      final poolSize = math.min(8, nodesToResolve.length);
      await Future.wait(List.generate(poolSize, (_) => dnsWorker()));
    }

    if (_disposed || token.isCancelled) return;

    _scanProgress = ScanProgress(
      phase: 'Discovery Complete (${_repository.nodes.length} nodes, ${_repository.edges.length} edges)',
      totalTargets: liveHosts.length,
      completedTargets: liveHosts.length,
      isScanning: false,
    );
    _notify();
  }

  /// Syncs shared device metadata when `shared_devices.db` changes.
  void _syncSharedMetadata() {
    _repository.enrichNodes(
      arpCache: _cachedArp,
      sharedDeviceService: _sharedDeviceService,
    );
    _notify();
  }

  /// Updates or creates friendly device name and metadata in `shared_devices.db`.
  void updateDeviceDetails({
    required String ip,
    required String rawMac,
    required String name,
    String? category,
    String? vendor,
    String? notes,
  }) {
    final existing = _sharedDeviceService.getDeviceByMac(rawMac);
    if (existing != null) {
      _sharedDeviceService.updateDeviceDetails(
        rawMac,
        name: name,
        deviceType: category,
        vendor: vendor,
        notes: notes,
      );
    } else {
      _sharedDeviceService.registerDevice(
        rawMac: rawMac,
        name: name,
        vendor: vendor,
        deviceType: category,
        notes: notes,
      );
    }

    _repository.updateNodeSharedMetadata(
      ip,
      name: name,
      category: category,
      vendor: vendor,
      notes: notes,
      macAddress: rawMac,
    );

    _notify();
  }

  /// Loads realistic enterprise demo topology with rich multi-hop structure.
  void loadDemoTopology() {
    _repository.clear();
    _repository.setLocalHost(DemoDataGenerator.localHostIp, gatewayIp: DemoDataGenerator.gatewayIp);

    // Ingest all demo traces
    final demoTraces = DemoDataGenerator.generateDemoTraces();
    for (final trace in demoTraces) {
      _repository.ingestTraceResult(trace);
    }

    // Populate demo devices into shared device database if database is open
    for (final entry in DemoDataGenerator.demoDeviceCatalog.entries) {
      final ip = entry.key;
      final data = entry.value;
      final mac = data['mac']!;
      final name = data['name']!;
      final vendor = data['vendor']!;
      final type = data['type']!;
      final notes = data['notes']!;

      if (_isSharedDbConnected) {
        _sharedDeviceService.registerDevice(
          rawMac: mac,
          name: name,
          vendor: vendor,
          deviceType: type,
          notes: notes,
        );
      }

      _repository.updateNodeSharedMetadata(
        ip,
        name: name,
        category: type,
        vendor: vendor,
        notes: notes,
        macAddress: mac,
      );
    }

    _scanProgress = ScanProgress(
      phase: 'Demo Topology Loaded (${_repository.nodes.length} nodes, ${_repository.edges.length} edges)',
      totalTargets: demoTraces.length,
      completedTargets: demoTraces.length,
      isScanning: false,
    );
    _statusBannerText = null;
    _notify();
  }

  /// Exports current topology to JSON file.
  Future<String?> exportTopologyJson() async {
    return ExportService.exportToJsonFile(
      nodes: _repository.nodes,
      edges: _repository.edges,
      traces: _repository.traces,
      localHostIp: _repository.localHostIp,
    );
  }

  /// Copies JSON to clipboard.
  Future<void> copyJsonToClipboard() async {
    await ExportService.copyJsonToClipboard(
      nodes: _repository.nodes,
      edges: _repository.edges,
      traces: _repository.traces,
      localHostIp: _repository.localHostIp,
    );
  }

  @override
  void dispose() {
    _disposed = true;
    _throttleTimer?.cancel();
    _currentScanToken?.cancel();
    _dbSubscription?.cancel();
    _tracerouteService.cancel();
    _icmpService.cancel();
    _sharedDeviceService.dispose();
    super.dispose();
  }
}
