import 'dart:async';
import 'package:flutter/material.dart';
import 'package:network_suite_shared/network_suite_shared.dart';
import '../../core/constants.dart';
import '../../data/repositories/topology_repository.dart';
import '../../data/services/arp_service.dart';
import '../../data/services/demo_data_generator.dart';
import '../../data/services/export_service.dart';
import '../../data/services/icmp_service.dart';
import '../../data/services/network_adapter_service.dart';
import '../../data/services/shared_device_service.dart';
import '../../data/services/traceroute_service.dart';
import '../../domain/models/network_adapter_info.dart';
import '../../domain/models/network_edge.dart';
import '../../domain/models/network_node.dart';
import '../../domain/models/scan_progress.dart';
import '../../domain/models/trace_result.dart';

enum TopologyViewMode {
  graph,
  table,
  split,
}

class TopologyViewModel extends ChangeNotifier {
  final TopologyRepository _repository = TopologyRepository();
  final TracerouteService _tracerouteService = TracerouteService();
  final ArpService _arpService = ArpService();
  final IcmpService _icmpService = IcmpService();
  final SharedDeviceService _sharedDeviceService = SharedDeviceService();

  StreamSubscription<void>? _dbSubscription;

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

  TopologyViewModel() {
    _initServices();
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

    notifyListeners();
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
    notifyListeners();
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
    notifyListeners();
  }

  void setTargetInput(String value) {
    _targetInput = value;
    notifyListeners();
  }

  void setConcurrency(int value) {
    _concurrency = value.clamp(1, 16);
    notifyListeners();
  }

  void setMaxHops(int value) {
    _maxHops = value.clamp(1, 30);
    notifyListeners();
  }

  void setViewMode(TopologyViewMode mode) {
    _viewMode = mode;
    notifyListeners();
  }

  void setSearchQuery(String query) {
    _searchQuery = query;
    notifyListeners();
  }

  void selectNode(String? nodeId) {
    _repository.selectNode(nodeId);
    notifyListeners();
  }

  void clearSelection() {
    _repository.selectNode(null);
    notifyListeners();
  }

  void clearGraph() {
    _repository.clear();
    _scanProgress = const ScanProgress();
    _statusBannerText = null;
    notifyListeners();
  }

  /// Cancels any running scan immediately.
  Future<void> cancelSweep() async {
    _icmpService.cancel();
    _tracerouteService.cancel();
    _scanProgress = _scanProgress.copyWith(
      phase: 'Scan Cancelled by User',
      isScanning: false,
    );
    _statusBannerText = 'Sweep cancelled by user.';
    notifyListeners();
  }

  /// Starts the 2-phase discovery pipeline:
  /// Phase 1: Pre-flight ICMP ping sweep (filters offline hosts & warms kernel ARP cache)
  /// Phase 2: Multi-hop OS native traceroute sweep with concurrency worker pool
  Future<void> startSweep() async {
    if (_scanProgress.isScanning) return;

    final targetIps = IcmpService.expandTargetSpec(_targetInput, maxHosts: AppConstants.maxSweepHosts);
    if (targetIps.isEmpty) {
      _statusBannerText = 'Invalid target specification. Enter a valid IPv4, CIDR (e.g. 192.168.1.0/24), or range.';
      notifyListeners();
      return;
    }

    _statusBannerText = null;
    _scanProgress = ScanProgress(
      phase: 'Phase 1: Pre-Flight ICMP Sweep (Pinging ${targetIps.length} hosts)...',
      totalTargets: targetIps.length,
      completedTargets: 0,
      activeWorkers: _concurrency,
      isScanning: true,
    );
    notifyListeners();

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
        onProgress: (completed, total, currentIp, reached) {
          _scanProgress = _scanProgress.copyWith(
            completedTargets: completed,
            currentTarget: currentIp,
          );
          notifyListeners();
        },
      );
    }

    if (_icmpService.isCancelled) return;

    // Refresh ARP table to catch all newly probed MACs
    _cachedArp = await _arpService.readSystemArpCache();

    if (liveHosts.isEmpty) {
      _scanProgress = const ScanProgress(
        phase: 'No responsive hosts found in target range',
        isScanning: false,
      );
      _statusBannerText = 'No responsive hosts answered ICMP ping in the specified range.';
      notifyListeners();
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
    notifyListeners();

    await _tracerouteService.sweepTargets(
      liveHosts,
      concurrency: _concurrency,
      maxHops: _maxHops,
      timeoutMs: 1000,
      sourceIp: _selectedAdapter?.ipAddress,
      onHopDiscovered: (targetIp, hop) {
        // Stream live hop into UI
        _repository.ingestTraceResult(
          TraceResult(
            targetIp: targetIp,
            hops: [hop],
            isReachable: false,
            completedAt: DateTime.now(),
          ),
        );
        notifyListeners();
      },
      onTargetCompleted: (completed, total, currentIp, result) {
        _repository.ingestTraceResult(result);
        _scanProgress = _scanProgress.copyWith(
          completedTargets: completed,
          currentTarget: currentIp,
        );
        // Refresh enrichments
        _repository.enrichNodes(
          arpCache: _cachedArp,
          sharedDeviceService: _sharedDeviceService,
        );
        notifyListeners();
      },
    );

    // Final ARP and reverse DNS enrichment
    _cachedArp = await _arpService.readSystemArpCache();
    _repository.enrichNodes(
      arpCache: _cachedArp,
      sharedDeviceService: _sharedDeviceService,
    );

    // Resolve reverse-DNS in background for all discovered IPs
    for (final node in _repository.nodes.values) {
      if (!node.isLocalHost && !node.isUnresponsive) {
        _arpService.reverseDns(node.ip).then((host) {
          if (host != null) {
            _repository.updateNodeHostname(node.ip, host);
            notifyListeners();
          }
        });
      }
    }

    _scanProgress = ScanProgress(
      phase: 'Discovery Complete (${_repository.nodes.length} nodes, ${_repository.edges.length} edges)',
      totalTargets: liveHosts.length,
      completedTargets: liveHosts.length,
      isScanning: false,
    );
    notifyListeners();
  }

  /// Syncs shared device metadata when `shared_devices.db` changes.
  void _syncSharedMetadata() {
    _repository.enrichNodes(
      arpCache: _cachedArp,
      sharedDeviceService: _sharedDeviceService,
    );
    notifyListeners();
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

    notifyListeners();
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
    notifyListeners();
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
    _dbSubscription?.cancel();
    _tracerouteService.cancel();
    _icmpService.cancel();
    _sharedDeviceService.dispose();
    super.dispose();
  }
}
