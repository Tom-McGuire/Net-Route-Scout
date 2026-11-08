import 'package:flutter_test/flutter_test.dart';
import 'package:net_route_scout/core/constants.dart';
import 'package:net_route_scout/data/repositories/topology_repository.dart';
import 'package:net_route_scout/data/services/arp_service.dart';
import 'package:net_route_scout/data/services/icmp_service.dart';
import 'package:net_route_scout/data/services/traceroute_service.dart';
import 'package:net_route_scout/domain/models/cancellation_token.dart';
import 'package:net_route_scout/domain/models/network_adapter_info.dart';
import 'package:net_route_scout/domain/models/trace_hop.dart';
import 'package:net_route_scout/domain/models/trace_result.dart';
import 'package:net_route_scout/ui/view_models/topology_view_model.dart';

class FakeIcmpService extends IcmpService {
  final List<String> responsiveHosts;
  FakeIcmpService({this.responsiveHosts = const []});

  @override
  Future<List<String>> sweepActiveHosts(
    List<String> targetIps, {
    int concurrency = 16,
    int timeoutMs = 350,
    String? sourceIp,
    CancellationToken? cancelToken,
    void Function(int completed, int total, String currentIp, bool reachable)? onProgress,
  }) async {
    return responsiveHosts;
  }
}

class FakeArpService extends ArpService {
  @override
  Future<Map<String, ArpDeviceEntry>> readSystemArpCache() async => {};

  @override
  Future<String> detectLocalHostIp() async => '192.168.1.100';

  @override
  Future<String?> detectDefaultGateway() async => '192.168.1.1';
}

class FakeTracerouteService extends TracerouteService {
  final List<TraceResult> results;
  FakeTracerouteService({this.results = const []});

  @override
  Future<List<TraceResult>> sweepTargets(
    List<String> targetIps, {
    int concurrency = 4,
    int maxHops = 15,
    int timeoutMs = 1000,
    String? sourceIp,
    CancellationToken? cancelToken,
    void Function(int completed, int total, String currentIp, TraceResult result)? onTargetCompleted,
    void Function(String targetIp, TraceHop hop)? onHopDiscovered,
  }) async {
    for (var i = 0; i < results.length; i++) {
      onTargetCompleted?.call(i + 1, results.length, results[i].targetIp, results[i]);
    }
    return results;
  }
}

void main() {
  group('TopologyViewModel Unit Tests', () {
    late TopologyRepository repo;
    late TopologyViewModel vm;

    setUp(() {
      repo = TopologyRepository();
      vm = TopologyViewModel(
        repository: repo,
        icmpService: FakeIcmpService(responsiveHosts: ['192.168.1.1', '192.168.1.50']),
        arpService: FakeArpService(),
        tracerouteService: FakeTracerouteService(),
        autoInit: false,
      );
    });

    test('Initializes in clean idle state', () {
      expect(vm.isScanning, isFalse);
      expect(vm.viewMode, TopologyViewMode.graph);
      expect(vm.concurrency, AppConstants.defaultConcurrency);
      expect(vm.maxHops, AppConstants.defaultMaxHops);
      expect(vm.searchQuery, isEmpty);
      expect(vm.selectedNodeId, isNull);
    });

    test('Configuration mutations update state and notify', () {
      var notified = 0;
      vm.addListener(() => notified++);

      vm.setTargetInput('192.168.5.0/24');
      expect(vm.targetInput, '192.168.5.0/24');

      vm.setConcurrency(8);
      expect(vm.concurrency, 8);

      vm.setMaxHops(20);
      expect(vm.maxHops, 20);

      vm.setViewMode(TopologyViewMode.table);
      expect(vm.viewMode, TopologyViewMode.table);

      expect(notified, 4);
    });

    test('selectAdapter updates host and auto-populates subnet CIDR target', () {
      const adapter = NetworkAdapterInfo(
        id: 'wlan0',
        name: 'Wi-Fi Adapter',
        ipAddress: '10.50.1.25',
        macAddress: 'AA:BB:CC:DD:EE:FF',
        vendor: 'Cisco Systems',
        subnetCidr: '10.50.1.0/24',
        gatewayIp: '10.50.1.1',
      );

      vm.selectAdapter(adapter);

      expect(vm.selectedAdapter, adapter);
      expect(vm.targetInput, '10.50.1.0/24');
      expect(vm.localHostIp, '10.50.1.25');
      expect(vm.gatewayIp, '10.50.1.1');

      final hostNode = vm.nodes['10.50.1.25'];
      expect(hostNode, isNotNull);
      expect(hostNode!.macAddress, 'AA:BB:CC:DD:EE:FF');
      expect(hostNode.vendor, 'Cisco Systems');
    });

    test('selectNode, clearSelection, and path breadcrumbs', () {
      vm.loadDemoTopology();
      expect(vm.nodes.isNotEmpty, isTrue);

      final demoTarget = vm.nodes.values.firstWhere((n) => n.isTarget);
      vm.selectNode(demoTarget.id);
      expect(vm.selectedNodeId, demoTarget.id);
      expect(vm.selectedNode, demoTarget);

      final breadcrumbs = vm.selectedPathBreadcrumbs;
      expect(breadcrumbs.isNotEmpty, isTrue);
      expect(breadcrumbs.last.id, demoTarget.id);

      vm.clearSelection();
      expect(vm.selectedNodeId, isNull);
      expect(vm.selectedNode, isNull);
      expect(vm.selectedPathBreadcrumbs, isEmpty);
    });

    test('filteredNodes filters across IP, hostname, shared name, MAC, and vendor', () {
      vm.loadDemoTopology();

      // Search by IP
      vm.setSearchQuery('10.0.1.45');
      expect(vm.filteredNodes.length, 1);
      expect(vm.filteredNodes.first.ip, '10.0.1.45');

      // Search by shared device name
      vm.setSearchQuery('Accounting');
      expect(vm.filteredNodes.any((n) => n.sharedDeviceName?.contains('Accounting') ?? false), isTrue);

      // Search by vendor
      vm.setSearchQuery('Cisco');
      expect(vm.filteredNodes.any((n) => n.vendor?.contains('Cisco') ?? false), isTrue);

      // Empty query returns all nodes
      vm.setSearchQuery('');
      expect(vm.filteredNodes.length, vm.nodes.length);
    });

    test('clearGraph empties non-host nodes and resets progress', () {
      vm.loadDemoTopology();
      expect(vm.nodes.length, greaterThan(1));

      vm.clearGraph();
      expect(vm.nodes.length, 1); // only localhost retained
      expect(vm.edges, isEmpty);
      expect(vm.traces, isEmpty);
      expect(vm.scanProgress.isScanning, isFalse);
    });

    test('cancelSweep marks progress as cancelled and sets status banner', () async {
      await vm.cancelSweep();
      expect(vm.scanProgress.isScanning, isFalse);
      expect(vm.scanProgress.phase, contains('Cancelled'));
      expect(vm.statusBannerText, contains('cancelled'));
    });

    test('startSweep flags invalid target specification', () async {
      vm.setTargetInput('invalid...ip');
      await vm.startSweep();

      expect(vm.isScanning, isFalse);
      expect(vm.statusBannerText, contains('Invalid target specification'));
    });

    test('startSweep warns on targets exceeding maxSweepHosts', () async {
      // /16 subnet has 65534 targets > 1024
      vm.setTargetInput('10.0.0.0/16');
      await vm.startSweep();

      expect(vm.statusBannerText, contains('Capped to first ${AppConstants.maxSweepHosts} hosts'));
    });

    test('startSweep runs full discovery lifecycle with fake services', () async {
      vm.setTargetInput('192.168.1.0/24');
      await vm.startSweep();

      expect(vm.isScanning, isFalse);
      expect(vm.scanProgress.phase, contains('Discovery Complete'));
    });

    test('Device quick-filter pills and auto-detected toggle', () {
      vm.loadDemoTopology();

      // Default showAutoDetected is false, so autoDetectedUnlabeledNodes must be empty
      expect(vm.showAutoDetected, isFalse);
      expect(vm.autoDetectedUnlabeledNodes, isEmpty);

      // Toggle showAutoDetected to true
      vm.setShowAutoDetected(true);
      expect(vm.showAutoDetected, isTrue);

      // Select a device pill
      final targetNode = vm.nodes['10.0.1.45']!;
      final key = (targetNode.macAddress != null && targetNode.macAddress!.isNotEmpty)
          ? targetNode.macAddress!
          : targetNode.ip;

      vm.toggleDevicePill(key);
      expect(vm.selectedDeviceKeys.contains(key), isTrue);

      // Filtering with selected device pill limits filteredNodes
      expect(vm.filteredNodes.any((n) => n.id == targetNode.id), isTrue);

      // Clear device filters
      vm.clearDeviceFilters();
      expect(vm.selectedDeviceKeys, isEmpty);
    });

    test('Multi-select common path calculation', () {
      vm.loadDemoTopology();

      // Select two target nodes from demo data: 10.0.1.45 (Accounting) and 10.0.1.80 (HR PC)
      final n1 = vm.nodes['10.0.1.45']!;
      final n2 = vm.nodes['10.0.1.80']!;

      final k1 = (n1.macAddress != null && n1.macAddress!.isNotEmpty) ? n1.macAddress! : n1.ip;
      final k2 = (n2.macAddress != null && n2.macAddress!.isNotEmpty) ? n2.macAddress! : n2.ip;

      vm.toggleDevicePill(k1);
      vm.toggleDevicePill(k2);

      expect(vm.selectedDeviceKeys.length, 2);
      expect(vm.activePathNodeIds.contains('10.0.1.45'), isTrue);
      expect(vm.activePathNodeIds.contains('10.0.1.80'), isTrue);

      // Common upstream path nodes (shared intermediate hops: 192.168.1.1 and 10.0.1.1)
      expect(vm.commonPathNodeIds.isNotEmpty, isTrue);
      expect(vm.commonPathEdgeIds.isNotEmpty, isTrue);
      expect(vm.commonPathNodeIds.contains('192.168.1.1'), isTrue);
      expect(vm.commonPathNodeIds.contains('10.0.1.1'), isTrue);
    });

    test('Dedicated IP and MAC filters and resetFilters', () {
      vm.loadDemoTopology();

      vm.setIpFilter('10.0.1.');
      expect(vm.filteredNodes.every((n) => n.ip.contains('10.0.1.')), isTrue);

      vm.setIpFilter('');
      vm.setMacFilter('00:50:56');
      expect(vm.filteredNodes.every((n) => (n.macAddress ?? '').toLowerCase().contains('00:50:56')), isTrue);

      vm.resetFilters();
      expect(vm.ipFilter, isEmpty);
      expect(vm.macFilter, isEmpty);
      expect(vm.searchQuery, isEmpty);
      expect(vm.selectedDeviceKeys, isEmpty);
    });

    test('toggleDeviceVisibility hides device from visibleSharedDevices', () {
      const mac = 'AA:BB:CC:DD:EE:FF';
      expect(vm.hiddenDeviceMacs.contains(mac), isFalse);

      vm.toggleDeviceVisibility(mac);
      expect(vm.hiddenDeviceMacs.contains(mac), isTrue);

      vm.toggleDeviceVisibility(mac);
      expect(vm.hiddenDeviceMacs.contains(mac), isFalse);
    });
  });
}
