import '../../domain/models/igmp_vlan_status.dart';
import '../../domain/models/interface_health_stats.dart';
import '../../domain/models/network_edge.dart';
import '../../domain/models/port_vlan_config.dart';
import '../../domain/models/stp_port_info.dart';
import '../../domain/models/switch_poe_status.dart';
import '../../domain/models/trace_hop.dart';
import '../../domain/models/trace_result.dart';
import '../repositories/topology_repository.dart';

class DemoDataGenerator {
  static const String localHostIp = '192.168.1.105';
  static const String gatewayIp = '192.168.1.1';

  static List<TraceResult> generateDemoTraces() {
    final now = DateTime.now();

    return [
      // Target 1: Accounting Server (via 192.168.1.1 -> 10.0.1.1 -> 10.0.1.45)
      TraceResult(
        targetIp: '10.0.1.45',
        isReachable: true,
        finalRttMs: 3.2,
        completedAt: now,
        hops: const [
          TraceHop(depth: 1, ip: '192.168.1.1', rttMs: 0.8),
          TraceHop(depth: 2, ip: '10.0.1.1', rttMs: 1.9),
          TraceHop(depth: 3, ip: '10.0.1.45', rttMs: 3.2),
        ],
      ),
      // Target 2: HR Executive PC (via 192.168.1.1 -> 10.0.1.1 -> 10.0.1.80)
      TraceResult(
        targetIp: '10.0.1.80',
        isReachable: true,
        finalRttMs: 4.1,
        completedAt: now,
        hops: const [
          TraceHop(depth: 1, ip: '192.168.1.1', rttMs: 0.9),
          TraceHop(depth: 2, ip: '10.0.1.1', rttMs: 2.1),
          TraceHop(depth: 3, ip: '10.0.1.80', rttMs: 4.1),
        ],
      ),
      // Target 3: Office MFP Printer (via 192.168.1.1 -> 10.0.1.1 -> 10.0.1.112)
      TraceResult(
        targetIp: '10.0.1.112',
        isReachable: true,
        finalRttMs: 5.4,
        completedAt: now,
        hops: const [
          TraceHop(depth: 1, ip: '192.168.1.1', rttMs: 0.8),
          TraceHop(depth: 2, ip: '10.0.1.1', rttMs: 2.0),
          TraceHop(depth: 3, ip: '10.0.1.112', rttMs: 5.4),
        ],
      ),
      // Target 4: DevOps CI/CD Runner (via 192.168.1.1 -> 10.0.2.1 -> 10.0.2.20)
      TraceResult(
        targetIp: '10.0.2.20',
        isReachable: true,
        finalRttMs: 2.8,
        completedAt: now,
        hops: const [
          TraceHop(depth: 1, ip: '192.168.1.1', rttMs: 0.8),
          TraceHop(depth: 2, ip: '10.0.2.1', rttMs: 1.5),
          TraceHop(depth: 3, ip: '10.0.2.20', rttMs: 2.8),
        ],
      ),
      // Target 5: TrueNAS Storage Cluster (via 192.168.1.1 -> 10.0.2.1 -> 10.0.2.55)
      TraceResult(
        targetIp: '10.0.2.55',
        isReachable: true,
        finalRttMs: 2.1,
        completedAt: now,
        hops: const [
          TraceHop(depth: 1, ip: '192.168.1.1', rttMs: 0.7),
          TraceHop(depth: 2, ip: '10.0.2.1', rttMs: 1.4),
          TraceHop(depth: 3, ip: '10.0.2.55', rttMs: 2.1),
        ],
      ),
      // Target 6: Tech Lead MacBook Pro (via 192.168.1.1 -> 10.0.2.1 -> 10.0.2.101)
      TraceResult(
        targetIp: '10.0.2.101',
        isReachable: true,
        finalRttMs: 6.8,
        completedAt: now,
        hops: const [
          TraceHop(depth: 1, ip: '192.168.1.1', rttMs: 0.8),
          TraceHop(depth: 2, ip: '10.0.2.1', rttMs: 1.6),
          TraceHop(depth: 3, ip: '10.0.2.101', rttMs: 6.8),
        ],
      ),
      // Target 7: Smart Conference TV (via 192.168.1.1 -> 10.0.2.1 -> 10.0.2.215)
      TraceResult(
        targetIp: '10.0.2.215',
        isReachable: true,
        finalRttMs: 7.2,
        completedAt: now,
        hops: const [
          TraceHop(depth: 1, ip: '192.168.1.1', rttMs: 0.9),
          TraceHop(depth: 2, ip: '10.0.2.1', rttMs: 1.5),
          TraceHop(depth: 3, ip: '10.0.2.215', rttMs: 7.2),
        ],
      ),
      // Target 8: Public Web Gateway (via 192.168.1.1 -> anon:192.168.1.1:2 -> 10.0.3.50)
      TraceResult(
        targetIp: '10.0.3.50',
        isReachable: true,
        finalRttMs: 14.5,
        completedAt: now,
        hops: const [
          TraceHop(depth: 1, ip: '192.168.1.1', rttMs: 0.8),
          TraceHop(depth: 2, ip: 'anon:192.168.1.1:2', isTimeout: true),
          TraceHop(depth: 3, ip: '10.0.3.50', rttMs: 14.5),
        ],
      ),
      // Target 9: Corporate VPN Concentrator (via 192.168.1.1 -> anon:192.168.1.1:2 -> 10.0.3.88)
      TraceResult(
        targetIp: '10.0.3.88',
        isReachable: true,
        finalRttMs: 16.2,
        completedAt: now,
        hops: const [
          TraceHop(depth: 1, ip: '192.168.1.1', rttMs: 0.9),
          TraceHop(depth: 2, ip: 'anon:192.168.1.1:2', isTimeout: true),
          TraceHop(depth: 3, ip: '10.0.3.88', rttMs: 16.2),
        ],
      ),
    ];
  }

  /// Metadata matching devices to MACs and friendly names for the demo topology.
  static final Map<String, Map<String, String>> demoDeviceCatalog = {
    '192.168.1.1': {
      'mac': '24:E5:0F:31:4B:73',
      'name': 'Main Gateway Router',
      'vendor': 'Cisco Systems',
      'type': 'router',
      'notes': 'Cisco ISR 4431 Dual-WAN Gateway',
    },
    '10.0.1.1': {
      'mac': '70:69:79:A1:B2:C3',
      'name': 'Corp Firewall (FortiGate)',
      'vendor': 'Fortinet, Inc.',
      'type': 'firewall',
      'notes': 'FortiGate 100F UTM Appliance',
    },
    '10.0.2.1': {
      'mac': 'AC:16:2D:33:44:55',
      'name': 'Engineering Distribution Switch',
      'vendor': 'Hewlett Packard Enterprise / Aruba',
      'type': 'switch',
      'notes': 'Aruba 3810M 48G PoE+ Core',
    },
    '10.0.1.45': {
      'mac': '00:50:56:A1:10:01',
      'name': 'Accounting Server (SQL)',
      'vendor': 'VMware, Inc.',
      'type': 'server',
      'notes': 'Production MS SQL 2022 Cluster',
    },
    '10.0.1.80': {
      'mac': 'B4:6B:FC:DB:6E:A6',
      'name': 'HR Executive PC',
      'vendor': 'Lenovo Group Ltd.',
      'type': 'desktop',
      'notes': 'ThinkCentre M90q Tiny Gen 4',
    },
    '10.0.1.112': {
      'mac': '00:1E:8F:22:33:44',
      'name': 'Office Color LaserJet',
      'vendor': 'HP Inc.',
      'type': 'printer',
      'notes': 'HP Color LaserJet Enterprise M555',
    },
    '10.0.2.20': {
      'mac': '52:54:00:12:34:56',
      'name': 'DevOps CI/CD Runner',
      'vendor': 'QEMU / KVM Virtual Machine',
      'type': 'server',
      'notes': 'Ubuntu 24.04 LTS Docker Host',
    },
    '10.0.2.55': {
      'mac': '00:25:90:77:88:99',
      'name': 'TrueNAS Storage Pool',
      'vendor': 'Super Micro Computer, Inc.',
      'type': 'nas',
      'notes': 'ZFS RAID-Z2 8x16TB Enterprise Storage',
    },
    '10.0.2.101': {
      'mac': 'F4:6D:3F:AB:17:6A',
      'name': 'Lead Dev MacBook Pro',
      'vendor': 'Apple, Inc.',
      'type': 'laptop',
      'notes': '16" MacBook Pro M3 Max (Wi-Fi 6E)',
    },
    '10.0.2.215': {
      'mac': 'E4:58:B8:33:22:11',
      'name': 'Boardroom Smart TV',
      'vendor': 'LG Electronics',
      'type': 'smart_tv',
      'notes': 'LG OLED 77" 4K Commercial Display',
    },
    '10.0.3.50': {
      'mac': '00:15:5D:88:99:AA',
      'name': 'DMZ Web Reverse Proxy',
      'vendor': 'Microsoft Corporation',
      'type': 'server',
      'notes': 'NGINX reverse proxy with TLS offloading',
    },
    '10.0.3.88': {
      'mac': '00:0C:29:44:55:66',
      'name': 'AnyConnect VPN Gateway',
      'vendor': 'Cisco Systems',
      'type': 'router',
      'notes': 'Cisco ASA 5525-X Remote Access Headend',
    },
  };

  /// Populates [repository] with the full enterprise demo topology (traces,
  /// catalog metadata, switches/links, STP, IGMP, VLAN, Interface Health, PoE,
  /// and ring split correlation) and returns the number of ingested traces.
  static int populateDemoRepository(TopologyRepository repository) {
    repository.clear();
    repository.setLocalHost(localHostIp, gatewayIp: gatewayIp);

    // Ingest all demo traces
    final demoTraces = generateDemoTraces();
    for (final trace in demoTraces) {
      repository.ingestTraceResult(trace);
    }

    // Populate local node metadata for demo presentation (isolated from SharedDeviceDatabase)
    for (final entry in demoDeviceCatalog.entries) {
      final ip = entry.key;
      final data = entry.value;
      repository.updateNodeSharedMetadata(
        ip,
        name: data['name']!,
        category: data['type']!,
        vendor: data['vendor']!,
        notes: data['notes']!,
        macAddress: data['mac']!,
      );
    }

    // Configure demo switch hierarchy (Core/Distribution switch -> Access switch -> Endpoints)
    repository.defineNodeAsSwitch('10.0.2.1', isSwitch: true, name: 'Engineering Distribution Switch');
    repository.connectNodeToSwitch('10.0.2.20', '10.0.2.1', portLabel: 'Port 1 (DevOps)');
    repository.connectNodeToSwitch('10.0.2.55', '10.0.2.1', portLabel: 'Port 10 (10GbE NAS)');

    final accessSwitch = repository.addStandaloneSwitch(
      name: 'Floor 2 Access Switch',
      ip: '10.0.2.2',
      model: 'Aruba 2930F 24G PoE+',
      upstreamNodeId: '10.0.2.1',
    );
    repository.connectNodeToSwitch(accessSwitch.id, '10.0.2.1', portLabel: 'Uplink 1/24');
    repository.connectNodeToSwitch('10.0.2.101', accessSwitch.id, portLabel: 'Port 5 (MacBook)');
    repository.connectNodeToSwitch('10.0.2.215', accessSwitch.id, portLabel: 'Port 12 (Conf TV)');

    final ringEdgeSwitch = repository.addStandaloneSwitch(
      name: 'Stage Left AV Switch',
      ip: '10.0.2.3',
      model: 'Luminex GigaCore 16RFO',
      upstreamNodeId: '10.0.2.1',
    );
    repository.connectNodeToSwitch(ringEdgeSwitch.id, '10.0.2.1', portLabel: 'Fiber Trunk 1/26');

    // Enrich Demo Switches with STP Root Bridge, Ring Split, IGMP Querier, VLAN, Health & PoE telemetry
    final demoSampleTime = DateTime.now();
    final distNode = repository.nodes['10.0.2.1'];
    if (distNode != null) {
      repository.updateNodeDirect(distNode.copyWith(
        isStpRootBridge: true,
        stpPriority: 4096,
        stpBridgeId: '4096 / AA:BB:CC:11:22:01',
        stpDesignatedRootId: '4096 / AA:BB:CC:11:22:01',
        stpRootCost: 0,
        isIgmpQuerier: true,
        igmpQuerierVersion: 'IGMPv3',
        igmpSnoopingEnabled: true,
        igmpVlans: const [
          IgmpVlanStatus(
            vlanId: 1,
            vlanName: 'Default / AV Control',
            snoopingEnabled: true,
            localQuerierEnabled: true,
            activeQuerierIp: '10.0.2.1',
            igmpVersion: 3,
            isLocalSwitchQuerier: true,
          ),
        ],
        stpPorts: const [
          StpPortInfo(bridgePort: 1, ifIndex: 1, interfaceName: 'Gi1/0/1', state: StpPortState.forwarding, role: StpPortRole.designated),
          StpPortInfo(bridgePort: 24, ifIndex: 24, interfaceName: 'Gi1/0/24', state: StpPortState.forwarding, role: StpPortRole.designated),
          StpPortInfo(bridgePort: 26, ifIndex: 26, interfaceName: 'Te1/0/26', state: StpPortState.forwarding, role: StpPortRole.designated),
        ],
        vlanNames: const {1: 'MGMT', 10: 'CONTROL', 20: 'DANTE_AUDIO'},
        portVlans: const [
          PortVlanConfig(bridgePort: 24, ifIndex: 24, interfaceName: 'Uplink 1/24', nativePvid: 1, allowedVlans: {1, 10, 20}, untaggedVlans: {1}),
          PortVlanConfig(bridgePort: 26, ifIndex: 26, interfaceName: 'Fiber Trunk 1/26', nativePvid: 1, allowedVlans: {1, 10, 20}, untaggedVlans: {1}),
        ],
        interfaceHealth: [
          InterfaceHealthStats(ifIndex: 24, interfaceName: 'Uplink 1/24', speedMbps: 1000, duplex: DuplexMode.fullDuplex, sampledAt: demoSampleTime),
          InterfaceHealthStats(ifIndex: 26, interfaceName: 'Fiber Trunk 1/26', speedMbps: 10000, duplex: DuplexMode.fullDuplex, sampledAt: demoSampleTime),
        ],
      ));
    }

    final accessNode = repository.nodes[accessSwitch.id];
    if (accessNode != null) {
      repository.updateNodeDirect(accessNode.copyWith(
        stpPriority: 32768,
        stpBridgeId: '32768 / AA:BB:CC:11:22:02',
        stpDesignatedRootId: '4096 / AA:BB:CC:11:22:01',
        stpRootCost: 4,
        igmpSnoopingEnabled: true,
        igmpVlans: const [
          IgmpVlanStatus(
            vlanId: 1,
            vlanName: 'Default / AV Control',
            snoopingEnabled: true,
            activeQuerierIp: '10.0.2.1',
            igmpVersion: 3,
          ),
        ],
        stpPorts: const [
          StpPortInfo(bridgePort: 24, ifIndex: 24, interfaceName: 'Uplink 1/24', state: StpPortState.forwarding, role: StpPortRole.root),
          StpPortInfo(bridgePort: 25, ifIndex: 25, interfaceName: 'Ring 1/25', state: StpPortState.blocking, role: StpPortRole.alternate),
        ],
        vlanNames: const {1: 'MGMT', 10: 'CONTROL', 20: 'DANTE_AUDIO'},
        portVlans: const [
          PortVlanConfig(bridgePort: 24, ifIndex: 24, interfaceName: 'Uplink 1/24', nativePvid: 1, allowedVlans: {1, 10, 20}, untaggedVlans: {1}),
          PortVlanConfig(bridgePort: 25, ifIndex: 25, interfaceName: 'Ring 1/25', nativePvid: 1, allowedVlans: {1, 10}, untaggedVlans: {1}),
        ],
        interfaceHealth: [
          InterfaceHealthStats(ifIndex: 24, interfaceName: 'Uplink 1/24', speedMbps: 1000, duplex: DuplexMode.fullDuplex, sampledAt: demoSampleTime),
          InterfaceHealthStats(ifIndex: 25, interfaceName: 'Ring 1/25', speedMbps: 100, duplex: DuplexMode.fullDuplex, inErrors: 14, inErrorsDelta: 3, sampledAt: demoSampleTime),
        ],
        poeStatus: const SwitchPoeStatus(
          totalBudgetWatts: 195,
          consumedWatts: 162,
          ports: [
            PoePortDetail(portIndex: 5, interfaceName: 'Port 5 (MacBook)', state: PoePortState.searching),
            PoePortDetail(portIndex: 12, interfaceName: 'Port 12 (Conf TV)', state: PoePortState.deliveringPower, powerClass: 'Class 4', drawWatts: 24.5),
          ],
        ),
      ));
    }

    final ringNode = repository.nodes[ringEdgeSwitch.id];
    if (ringNode != null) {
      repository.updateNodeDirect(ringNode.copyWith(
        stpPriority: 32768,
        stpBridgeId: '32768 / AA:BB:CC:11:22:03',
        stpDesignatedRootId: '4096 / AA:BB:CC:11:22:01',
        stpRootCost: 4,
        igmpSnoopingEnabled: true,
        stpPorts: const [
          StpPortInfo(bridgePort: 26, ifIndex: 26, interfaceName: 'Fiber 1/26', state: StpPortState.forwarding, role: StpPortRole.root),
        ],
        vlanNames: const {1: 'MGMT', 10: 'CONTROL'},
        portVlans: const [
          // Intentionally prune VLAN 20 on Stage Left switch to demonstrate Issue #4 alert & badge
          PortVlanConfig(bridgePort: 26, ifIndex: 26, interfaceName: 'Fiber 1/26', nativePvid: 1, allowedVlans: {1, 10}, untaggedVlans: {1}),
        ],
        interfaceHealth: [
          InterfaceHealthStats(ifIndex: 26, interfaceName: 'Fiber 1/26', speedMbps: 10000, duplex: DuplexMode.fullDuplex, sampledAt: demoSampleTime),
        ],
        poeStatus: const SwitchPoeStatus(
          totalBudgetWatts: 150,
          consumedWatts: 68,
          ports: [
            PoePortDetail(portIndex: 1, interfaceName: 'Port 1 (sACN Node)', state: PoePortState.deliveringPower, powerClass: 'Class 3', drawWatts: 12.4),
          ],
        ),
      ));
    }

    // Populate port names on demo switch-to-switch trunks for VLAN & speed correlation
    final distToAccess = repository.edges['10.0.2.1->${accessSwitch.id}'];
    if (distToAccess != null) {
      repository.updateEdgeDirect(distToAccess.copyWith(
        sourcePortName: 'Uplink 1/24',
        targetPortName: 'Uplink 1/24',
      ));
    }
    final distToRing = repository.edges['10.0.2.1->${ringEdgeSwitch.id}'];
    if (distToRing != null) {
      repository.updateEdgeDirect(distToRing.copyWith(
        sourcePortName: 'Fiber Trunk 1/26',
        targetPortName: 'Fiber 1/26',
      ));
    }

    // Add blocked ring split edge between Stage Left AV Switch <-> Floor 2 Access Switch
    repository.updateEdgeDirect(NetworkEdge(
      sourceIp: ringEdgeSwitch.id,
      targetIp: accessSwitch.id,
      stpState: LinkStpState.blocking,
      blockingSwitchId: accessSwitch.id,
      blockingPortName: 'Ring 1/25',
      sourcePortName: 'Fiber 1/26',
      targetPortName: 'Ring 1/25',
    ));
    repository.correlateStpEdges();

    return demoTraces.length;
  }
}
