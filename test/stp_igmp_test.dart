import 'package:flutter_test/flutter_test.dart';
import 'package:network_suite_shared/network_suite_shared.dart';
import 'package:net_route_scout/data/repositories/topology_repository.dart';
import 'package:net_route_scout/data/services/l2_role_sniffer_service.dart';
import 'package:net_route_scout/data/services/shared_device_service.dart';
import 'package:net_route_scout/data/services/snmp_switch_service.dart';
import 'package:net_route_scout/domain/models/igmp_vlan_status.dart';
import 'package:net_route_scout/domain/models/network_edge.dart';
import 'package:net_route_scout/domain/models/network_node.dart';
import 'package:net_route_scout/domain/models/stp_port_info.dart';
import 'package:net_route_scout/domain/models/switch_discovery_info.dart';
import 'package:net_route_scout/domain/models/trace_hop.dart';
import 'package:net_route_scout/domain/models/trace_result.dart';

class _FakeSharedDeviceService extends SharedDeviceService {
  final Map<String, SharedDeviceResolvedInfo> _byMac;
  _FakeSharedDeviceService(this._byMac);

  @override
  SharedDeviceResolvedInfo? resolveDeviceInfo(String rawMac) {
    return _byMac[SharedDevice.normalizeMac(rawMac)];
  }
}

void main() {
  group('STP & IGMP Parsing Tests', () {
    test('SnmpSwitchService.parseBridgeId decodes 8-byte Bridge ID correctly', () {
      final parsed = SnmpSwitchService.parseBridgeId('10 00 00 11 22 33 44 55');
      expect(parsed, isNotNull);
      expect(parsed!.priority, 4096);
      expect(parsed.mac, '00:11:22:33:44:55');
      expect(parsed.formattedId, '4096 / 00:11:22:33:44:55');
    });

    test('L2RoleSnifferService parses tcpdump STP BPDU output', () {
      const sample = '12:00:00.000000 aa:bb:cc:dd:ee:01 > 01:80:c2:00:00:00, 802.3, length 60: STP 802.1w, Rapid STP, bridge-id 8000.aa:bb:cc:dd:ee:01.8001, root-id 1000.00:11:22:33:44:55';
      final res = L2RoleSnifferService.parseTcpdumpStpOutput(sample);
      expect(res, isNotNull);
      expect(res!.rootBridgeMac, '00:11:22:33:44:55');
      expect(res.rootPriority, 4096);
      expect(res.sourceBridgeMac, 'AA:BB:CC:DD:EE:01');
    });

    test('L2RoleSnifferService parses tshark STP BPDU output', () {
      const sample = 'aa:bb:cc:dd:ee:01\t00:11:22:33:44:55\t4096\n';
      final res = L2RoleSnifferService.parseTsharkStpOutput(sample);
      expect(res, isNotNull);
      expect(res!.rootBridgeMac, '00:11:22:33:44:55');
      expect(res.rootPriority, 4096);
    });

    test('L2RoleSnifferService parses tcpdump IGMP v2 and v3 General Queries', () {
      const sampleV3 = '12:00:01.123456 IP (tos 0xc0, ttl 1) 10.201.100.1 > 224.0.0.1: igmp query v3';
      final resV3 = L2RoleSnifferService.parseTcpdumpIgmpOutput(sampleV3);
      expect(resV3, isNotNull);
      expect(resV3!.querierIp, '10.201.100.1');
      expect(resV3.igmpVersion, 'IGMPv3');

      const sampleV2 = '12:00:01.123456 IP 192.168.1.1 > 224.0.0.1: igmp query v2';
      final resV2 = L2RoleSnifferService.parseTcpdumpIgmpOutput(sampleV2);
      expect(resV2, isNotNull);
      expect(resV2!.querierIp, '192.168.1.1');
      expect(resV2.igmpVersion, 'IGMPv2');
    });

    test('L2RoleSnifferService parses tshark IGMP General Query output', () {
      const sample = '10.201.100.254\t3\n';
      final res = L2RoleSnifferService.parseTsharkIgmpOutput(sample);
      expect(res, isNotNull);
      expect(res!.querierIp, '10.201.100.254');
      expect(res.igmpVersion, 'IGMPv3');
    });
  });

  group('STP Ring & IGMP Querier Correlation Tests', () {
    test('Correlates SNMP STP blocking port to mark Ring Split edge', () {
      final repo = TopologyRepository();
      repo.setLocalHost('10.0.2.100', gatewayIp: '10.0.2.1');
      final sw1 = repo.addStandaloneSwitch(name: 'Core Switch', ip: '10.0.2.1', upstreamNodeId: '10.0.2.100');
      final sw2 = repo.addStandaloneSwitch(name: 'Edge Switch', ip: '10.0.2.2', upstreamNodeId: sw1.id);
      repo.connectNodeToSwitch(sw2.id, sw1.id, portLabel: 'Gi1/0/24');

      repo.applyStpAndIgmpFromSnmp(
        sw1.id,
        SwitchDiscoveryResult(
          switchIp: '10.0.2.1',
          sysName: 'Core Switch',
          stpBridgeMac: '00:11:22:33:44:01',
          stpPriority: 4096,
          stpRootCost: 0,
          stpRootPort: 0,
          igmpSnoopingEnabled: true,
          igmpVlans: const [
            IgmpVlanStatus(vlanId: 1, snoopingEnabled: true, activeQuerierIp: '10.0.2.1', isLocalSwitchQuerier: true, igmpVersion: 3),
          ],
        ),
      );

      repo.applyStpAndIgmpFromSnmp(
        sw2.id,
        SwitchDiscoveryResult(
          switchIp: '10.0.2.2',
          sysName: 'Edge Switch',
          stpBridgeMac: '00:11:22:33:44:02',
          stpPriority: 32768,
          stpRootCost: 4,
          stpRootPort: 1,
          stpPorts: const [
            StpPortInfo(bridgePort: 24, ifIndex: 24, interfaceName: 'Gi1/0/24', state: StpPortState.blocking, role: StpPortRole.alternate),
          ],
        ),
      );

      expect(repo.nodes[sw1.id]!.isStpRootBridge, isTrue);
      expect(repo.nodes[sw1.id]!.isIgmpQuerier, isTrue);

      final splitEdge = repo.edges['${sw1.id}->${sw2.id}'];
      expect(splitEdge, isNotNull);
      expect(splitEdge!.stpState, LinkStpState.blocking);
      expect(splitEdge.blockingSwitchId, sw2.id);
      expect(splitEdge.blockingPortName, 'Gi1/0/24');
    });

    test('Passive STP and IGMP results update matching nodes', () {
      final repo = TopologyRepository();
      repo.setLocalHost('10.0.2.100');
      final sw1 = repo.addStandaloneSwitch(name: 'Switch A', ip: '10.0.2.1', mac: '00:AA:BB:CC:DD:01', upstreamNodeId: '10.0.2.100');
      final sw2 = repo.addStandaloneSwitch(name: 'Switch B', ip: '10.0.2.2', mac: '00:AA:BB:CC:DD:02', upstreamNodeId: sw1.id);

      final stpMatched = repo.applyPassiveStpRoot(const StpPassiveResult(
        rootBridgeMac: '00:AA:BB:CC:DD:01',
        rootPriority: 4096,
      ));
      expect(stpMatched, isTrue);
      expect(repo.nodes[sw1.id]!.isStpRootBridge, isTrue);
      expect(repo.nodes[sw1.id]!.stpPriority, 4096);

      final igmpMatched = repo.applyPassiveIgmpQuerier(IgmpPassiveResult(
        querierIp: '10.0.2.2',
        igmpVersion: 'IGMPv3',
      ));
      expect(igmpMatched, isTrue);
      expect(repo.nodes[sw2.id]!.isIgmpQuerier, isTrue);
      expect(repo.nodes[sw2.id]!.igmpQuerierVersion, 'IGMPv3');
    });

    test('L2RoleSnifferService detects packet capture permission errors', () {
      expect(
        L2RoleSnifferService.isPermissionError(
          "tcpdump: eth0: You don't have permission to capture on that device (socket: Operation not permitted)",
        ),
        isTrue,
      );
      expect(
        L2RoleSnifferService.isPermissionError(
          'tshark: The capture session could not be initiated on interface "eth0" (You do not have permission to capture).',
        ),
        isTrue,
      );
      expect(
        L2RoleSnifferService.isPermissionError('1 packet captured'),
        isFalse,
      );

      const issue = L2CapturePermissionIssue(
        interfaceName: 'eth0',
        tcpdumpFound: true,
        tsharkFound: true,
        tcpdumpError: 'Operation not permitted',
      );
      expect(issue.detectedToolsLabel, 'tcpdump & tshark');
    });

    test('P1: Multi-trunk correlateStpEdges marks only blocking ring port, keeping uplink forwarding', () {
      final repo = TopologyRepository();
      repo.setLocalHost('10.0.2.100', gatewayIp: '10.0.2.1');
      final core = repo.addStandaloneSwitch(name: 'Core', ip: '10.0.2.1', upstreamNodeId: '10.0.2.100');
      final access = repo.addStandaloneSwitch(name: 'Access', ip: '10.0.2.2', upstreamNodeId: core.id);
      final ring = repo.addStandaloneSwitch(name: 'Ring', ip: '10.0.2.3', upstreamNodeId: core.id);

      repo.connectNodeToSwitch(access.id, core.id, portLabel: 'Uplink 1/24');
      repo.connectNodeToSwitch(ring.id, core.id, portLabel: 'Fiber 1/26');

      // Tag explicit port names on both inter-switch links touching Access
      final uplink = repo.edges['${core.id}->${access.id}']!;
      repo.updateEdgeDirect(uplink.copyWith(sourcePortName: 'Gi1/0/24', targetPortName: 'Uplink 1/24'));
      repo.updateEdgeDirect(NetworkEdge(
        sourceIp: ring.id,
        targetIp: access.id,
        sourcePortName: 'Fiber 1/26',
        targetPortName: 'Ring 1/25',
      ));

      repo.applyStpAndIgmpFromSnmp(
        core.id,
        SwitchDiscoveryResult(
          switchIp: core.ip,
          sysName: 'Core',
          stpBridgeMac: '00:11:22:33:44:01',
          stpPriority: 4096,
          stpRootCost: 0,
          stpRootPort: 0,
          stpPorts: const [
            StpPortInfo(bridgePort: 24, ifIndex: 24, interfaceName: 'Gi1/0/24', state: StpPortState.forwarding),
          ],
        ),
      );

      repo.applyStpAndIgmpFromSnmp(
        access.id,
        SwitchDiscoveryResult(
          switchIp: access.ip,
          sysName: 'Access',
          stpBridgeMac: '00:11:22:33:44:02',
          stpPriority: 32768,
          stpRootCost: 4,
          stpRootPort: 24,
          stpPorts: const [
            StpPortInfo(bridgePort: 24, ifIndex: 24, interfaceName: 'Uplink 1/24', state: StpPortState.forwarding),
            StpPortInfo(bridgePort: 25, ifIndex: 25, interfaceName: 'Ring 1/25', state: StpPortState.blocking),
          ],
        ),
      );

      expect(repo.edges['${core.id}->${access.id}']!.stpState, LinkStpState.forwarding);
      expect(repo.edges['${ring.id}->${access.id}']!.stpState, LinkStpState.blocking);
      expect(repo.edges['${ring.id}->${access.id}']!.blockingPortName, 'Ring 1/25');
    });

    test('P3: linkSwitchNeighbor does not invert upstream core hierarchy', () {
      final repo = TopologyRepository();
      repo.setLocalHost('10.0.2.100', gatewayIp: '10.0.2.1');
      final core = repo.addStandaloneSwitch(name: 'CoreSwitch', ip: '10.0.2.1', upstreamNodeId: '10.0.2.100');
      final access = repo.addStandaloneSwitch(name: 'AccessSwitch', ip: '10.0.2.2', upstreamNodeId: core.id);
      repo.connectNodeToSwitch(access.id, core.id, portLabel: 'Gi1/0/24');

      // Access reports LLDP neighbor pointing back upstream to Core
      repo.linkSwitchNeighbor(
        switchId: access.id,
        neighborId: core.id,
        localPort: 'Te1/0/1',
        remotePort: 'Gi1/0/24',
      );

      // Core remains upstream parent of Access; reverse edge must not overwrite hierarchy
      final edge = repo.edges['${core.id}->${access.id}'];
      expect(edge, isNotNull);
      expect(edge!.sourcePortName, 'Gi1/0/24');
      expect(edge.targetPortName, 'Te1/0/1');
      expect(repo.edges['${access.id}->${core.id}'], isNull);
    });

    test('Issue #8: enrichNodes consumes shared IGMP Querier metadata and lastQuerierSeen', () {
      final seen = DateTime.utc(2026, 11, 21, 18, 30, 0);
      final sharedDev = SharedDevice(
        macAddress: '00:11:22:33:44:55',
        name: 'Core AV Switch',
        vendor: 'Luminex',
        deviceType: 'switch',
        sourceApp: 'igmp-tester',
        createdAt: seen,
        updatedAt: seen,
        isIgmpQuerier: true,
        lastQuerierSeen: seen,
        igmpQuerierVersion: 'IGMPv3',
      );
      final fakeService = _FakeSharedDeviceService({
        '00:11:22:33:44:55': SharedDeviceResolvedInfo(
          device: sharedDev,
          friendlyName: sharedDev.name,
          categoryKey: 'switch',
          categoryLabel: 'Switch',
          categoryIcon: UnifiedDeviceCategory.resolve('switch').icon,
        ),
      });

      final repo = TopologyRepository();
      repo.setLocalHost('10.0.0.5', gatewayIp: '10.0.0.1');
      repo.ingestTraceResult(
        TraceResult(
          targetIp: '10.0.0.2',
          isReachable: true,
          completedAt: seen,
          hops: const [TraceHop(depth: 1, ip: '10.0.0.2', rttMs: 1.0)],
        ),
      );

      repo.enrichNodes(
        arpCache: {
          '10.0.0.2': const ArpCacheEntry(
            ipAddress: '10.0.0.2',
            macAddress: '00:11:22:33:44:55',
            arpType: 'dynamic',
            interfaceName: 'eth0',
            rawLine: '',
          ),
        },
        sharedDeviceService: fakeService,
      );

      final enriched = repo.nodes['10.0.0.2']!;
      expect(enriched.isSwitch, isTrue);
      expect(enriched.isIgmpQuerier, isTrue);
      expect(enriched.igmpQuerierVersion, 'IGMPv3');
      expect(enriched.lastQuerierSeen, seen);

      final roundTripped = NetworkNode.fromJson(enriched.toJson());
      expect(roundTripped.lastQuerierSeen, seen);
      expect(roundTripped.isIgmpQuerier, isTrue);
    });

    test('Issue #8: applyPassiveIgmpQuerier propagates observedAt into lastQuerierSeen', () {
      final observed = DateTime.utc(2026, 11, 21, 19, 0, 0);
      final repo = TopologyRepository();
      repo.setLocalHost('10.0.2.100');
      repo.addStandaloneSwitch(name: 'Switch A', ip: '10.0.2.10', upstreamNodeId: '10.0.2.100');

      final matched = repo.applyPassiveIgmpQuerier(IgmpPassiveResult(
        querierIp: '10.0.2.10',
        igmpVersion: 'IGMPv2',
        observedAt: observed,
      ));
      expect(matched, isTrue);
      expect(repo.nodes['10.0.2.10']!.isIgmpQuerier, isTrue);
      expect(repo.nodes['10.0.2.10']!.lastQuerierSeen, observed);
    });
  });
}
