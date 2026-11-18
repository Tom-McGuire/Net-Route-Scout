import 'dart:convert';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:net_route_scout/core/app_theme.dart';
import 'package:net_route_scout/data/services/baseline_storage_service.dart';
import 'package:net_route_scout/data/services/topology_diff_engine.dart';
import 'package:net_route_scout/domain/models/igmp_vlan_status.dart';
import 'package:net_route_scout/domain/models/interface_health_stats.dart';
import 'package:net_route_scout/domain/models/network_edge.dart';
import 'package:net_route_scout/domain/models/network_node.dart';
import 'package:net_route_scout/domain/models/port_vlan_config.dart';
import 'package:net_route_scout/domain/models/stp_port_info.dart';
import 'package:net_route_scout/domain/models/switch_poe_status.dart';
import 'package:net_route_scout/domain/models/topology_diff_result.dart';
import 'package:net_route_scout/domain/models/topology_snapshot.dart';
import 'package:net_route_scout/ui/views/widgets/diff_summary_drawer.dart';

void main() {
  group('TopologySnapshot Serialization & Storage Helper Tests', () {
    test('toJson / fromJson round-trip preserves STP, IGMP, VLAN, health, and PoE telemetry', () {
      final createdAt = DateTime.utc(2026, 11, 18, 10, 30, 0);
      final sampledAt = DateTime.utc(2026, 11, 18, 10, 29, 45);

      final coreSwitch = NetworkNode(
        id: '10.0.2.1',
        ip: '10.0.2.1',
        hostname: 'core-sw-01',
        macAddress: 'AA:BB:CC:11:22:01',
        vendor: 'Aruba Networks',
        hopDepth: 1,
        isSwitchNode: true,
        deviceCategoryKey: 'switch',
        sharedDeviceName: 'Core Switch 01',
        switchModel: 'Aruba 3810M',
        isStpRootBridge: true,
        stpPriority: 4096,
        stpBridgeId: '4096 / AA:BB:CC:11:22:01',
        stpDesignatedRootId: '4096 / AA:BB:CC:11:22:01',
        stpRootCost: 0,
        stpPorts: const [
          StpPortInfo(
            bridgePort: 1,
            ifIndex: 101,
            interfaceName: 'Gi1/0/1',
            state: StpPortState.forwarding,
            role: StpPortRole.designated,
            designatedBridgeId: '4096 / AA:BB:CC:11:22:01',
          ),
        ],
        isIgmpQuerier: true,
        igmpQuerierVersion: 'IGMPv3',
        igmpSnoopingEnabled: true,
        igmpVlans: const [
          IgmpVlanStatus(
            vlanId: 10,
            vlanName: 'Voice',
            snoopingEnabled: true,
            localQuerierEnabled: true,
            activeQuerierIp: '10.0.2.1',
            igmpVersion: 3,
            isLocalSwitchQuerier: true,
          ),
        ],
        vlanNames: const {1: 'Default', 10: 'Voice', 20: 'Cameras'},
        portVlans: const [
          PortVlanConfig(
            bridgePort: 1,
            ifIndex: 101,
            interfaceName: 'Gi1/0/1',
            nativePvid: 1,
            allowedVlans: {1, 10, 20},
            untaggedVlans: {1},
          ),
        ],
        interfaceHealth: [
          InterfaceHealthStats(
            ifIndex: 101,
            interfaceName: 'Gi1/0/1',
            speedMbps: 1000,
            isOperUp: true,
            duplex: DuplexMode.fullDuplex,
            inErrors: 4,
            outErrors: 1,
            inDiscards: 2,
            outDiscards: 3,
            inErrorsDelta: 0,
            outDiscardsDelta: 1,
            sampledAt: sampledAt,
          ),
        ],
        poeStatus: const SwitchPoeStatus(
          totalBudgetWatts: 370,
          consumedWatts: 145,
          ports: [
            PoePortDetail(
              portIndex: 12,
              interfaceName: 'Gi1/0/12',
              state: PoePortState.deliveringPower,
              powerClass: 'Class 4',
              drawWatts: 18.5,
            ),
          ],
        ),
      );

      final edge = NetworkEdge(
        sourceIp: '10.0.2.1',
        targetIp: '10.0.2.2',
        targetRoutes: const {'10.0.2.50'},
        stpState: LinkStpState.blocking,
        blockingSwitchId: '10.0.2.2',
        blockingPortName: 'Gi1/0/24',
        trafficDirectionTargetNodeId: '10.0.2.2',
        sourcePortName: 'Gi1/0/24',
        targetPortName: 'Gi1/0/24',
        vlanMismatch: const VlanMismatchReport(
          hasNativeVlanMismatch: true,
          sideANativeVlan: 1,
          sideBNativeVlan: 10,
          missingOnSideA: {30},
          missingOnSideB: {20},
          sideAPortName: 'Gi1/0/24',
          sideBPortName: 'Gi1/0/24',
        ),
        linkSpeedMbps: 1000,
        linkDuplex: DuplexMode.fullDuplex,
        inErrorsDelta: 2,
        outDiscardsDelta: 1,
      );

      final snapshot = TopologySnapshot(
        id: 'snap_001',
        name: 'Pre-Maintenance Golden Baseline',
        createdAt: createdAt,
        adapterName: 'eth0',
        nodes: [coreSwitch],
        edges: [edge],
      );

      final encoded = jsonEncode(snapshot.toJson());
      final decoded = jsonDecode(encoded) as Map<String, dynamic>;
      final restored = TopologySnapshot.fromJson(decoded);

      expect(restored.id, 'snap_001');
      expect(restored.name, 'Pre-Maintenance Golden Baseline');
      expect(restored.createdAt.toUtc(), createdAt);
      expect(restored.adapterName, 'eth0');
      expect(restored.nodes.length, 1);
      expect(restored.edges.length, 1);

      final restoredNode = restored.nodes.first;
      expect(restoredNode.isStpRootBridge, isTrue);
      expect(restoredNode.stpPriority, 4096);
      expect(restoredNode.stpBridgeId, '4096 / AA:BB:CC:11:22:01');
      expect(restoredNode.stpRootCost, 0);
      expect(restoredNode.stpPorts.length, 1);
      expect(restoredNode.stpPorts.first.state, StpPortState.forwarding);
      expect(restoredNode.stpPorts.first.role, StpPortRole.designated);

      expect(restoredNode.isIgmpQuerier, isTrue);
      expect(restoredNode.igmpQuerierVersion, 'IGMPv3');
      expect(restoredNode.igmpSnoopingEnabled, isTrue);
      expect(restoredNode.igmpVlans.length, 1);
      expect(restoredNode.igmpVlans.first.vlanId, 10);
      expect(restoredNode.igmpVlans.first.isLocalSwitchQuerier, isTrue);

      expect(restoredNode.vlanNames, {1: 'Default', 10: 'Voice', 20: 'Cameras'});
      expect(restoredNode.portVlans.length, 1);
      expect(restoredNode.portVlans.first.allowedVlans, {1, 10, 20});
      expect(restoredNode.portVlans.first.nativePvid, 1);

      expect(restoredNode.interfaceHealth.length, 1);
      expect(restoredNode.interfaceHealth.first.speedMbps, 1000);
      expect(restoredNode.interfaceHealth.first.duplex, DuplexMode.fullDuplex);
      expect(restoredNode.interfaceHealth.first.outDiscardsDelta, 1);
      expect(restoredNode.interfaceHealth.first.sampledAt.toUtc(), sampledAt);

      expect(restoredNode.poeStatus, isNotNull);
      expect(restoredNode.poeStatus!.totalBudgetWatts, 370);
      expect(restoredNode.poeStatus!.consumedWatts, 145);
      expect(restoredNode.poeStatus!.ports.first.drawWatts, 18.5);
      expect(restoredNode.poeStatus!.ports.first.state, PoePortState.deliveringPower);

      final restoredEdge = restored.edges.first;
      expect(restoredEdge.stpState, LinkStpState.blocking);
      expect(restoredEdge.blockingSwitchId, '10.0.2.2');
      expect(restoredEdge.blockingPortName, 'Gi1/0/24');
      expect(restoredEdge.linkSpeedMbps, 1000);
      expect(restoredEdge.linkDuplex, DuplexMode.fullDuplex);
      expect(restoredEdge.vlanMismatch, isNotNull);
      expect(restoredEdge.vlanMismatch!.hasNativeVlanMismatch, isTrue);
      expect(restoredEdge.vlanMismatch!.missingOnSideA, {30});
      expect(restoredEdge.vlanMismatch!.missingOnSideB, {20});
    });

    test('BaselineStorageService.getBaselineFile resolves active_baseline_snapshot.json', () {
      final file = BaselineStorageService.getBaselineFile();
      expect(file.path, endsWith('active_baseline_snapshot.json'));
    });
  });

  group('TopologyDiffEngine.compare Scenarios', () {
    TopologySnapshot buildBaseline() {
      final host = NetworkNode(
        id: '10.0.2.100',
        ip: '10.0.2.100',
        macAddress: 'AA:BB:CC:00:00:01',
        hopDepth: 0,
        isLocalHost: true,
        sharedDeviceName: 'Workstation',
      );
      final sw1 = NetworkNode(
        id: '10.0.2.1',
        ip: '10.0.2.1',
        macAddress: '00:11:22:33:44:01',
        hopDepth: 1,
        isSwitchNode: true,
        deviceCategoryKey: 'switch',
        sharedDeviceName: 'Core Switch A',
        isStpRootBridge: true,
        stpPriority: 4096,
        isIgmpQuerier: true,
        igmpQuerierVersion: 'IGMPv3',
      );
      final sw2 = NetworkNode(
        id: '10.0.2.2',
        ip: '10.0.2.2',
        macAddress: '00:11:22:33:44:02',
        hopDepth: 2,
        isSwitchNode: true,
        deviceCategoryKey: 'switch',
        sharedDeviceName: 'Dist Switch B',
        isStpRootBridge: false,
        stpPriority: 32768,
      );
      final sw3 = NetworkNode(
        id: '10.0.2.3',
        ip: '10.0.2.3',
        macAddress: '00:11:22:33:44:03',
        hopDepth: 2,
        isSwitchNode: true,
        deviceCategoryKey: 'switch',
        sharedDeviceName: 'Edge Switch C',
      );

      final eHostSw1 = NetworkEdge(
        sourceIp: '10.0.2.100',
        targetIp: '10.0.2.1',
        linkSpeedMbps: 1000,
        linkDuplex: DuplexMode.fullDuplex,
      );
      final eSw1Sw2 = NetworkEdge(
        sourceIp: '10.0.2.1',
        targetIp: '10.0.2.2',
        stpState: LinkStpState.forwarding,
        linkSpeedMbps: 1000,
      );
      final eSw2Sw3 = NetworkEdge(
        sourceIp: '10.0.2.2',
        targetIp: '10.0.2.3',
        stpState: LinkStpState.blocking,
        blockingSwitchId: '10.0.2.3',
        blockingPortName: 'Gi1/0/24',
        linkSpeedMbps: 1000,
      );
      final eSw1Sw3 = NetworkEdge(
        sourceIp: '10.0.2.1',
        targetIp: '10.0.2.3',
        stpState: LinkStpState.forwarding,
        linkSpeedMbps: 1000,
      );

      return TopologySnapshot(
        id: 'base_1',
        name: 'Golden Ring',
        createdAt: DateTime.utc(2026, 11, 18, 9, 0),
        adapterName: 'eth0',
        nodes: [host, sw1, sw2, sw3],
        edges: [eHostSw1, eSw1Sw2, eSw2Sw3, eSw1Sw3],
      );
    }

    test('Identical topology returns no drift and marks all nodes/edges unchanged', () {
      final baseline = buildBaseline();
      final currentNodes = {for (final n in baseline.nodes) n.id: n};
      final currentEdges = {for (final e in baseline.edges) e.edgeId: e};

      final result = TopologyDiffEngine.compare(
        baseline: baseline,
        currentNodes: currentNodes,
        currentEdges: currentEdges,
      );

      expect(result.hasDrift, isFalse);
      expect(result.criticalCount, 0);
      expect(result.items, isEmpty);
      expect(result.ghostNodes, isEmpty);
      expect(result.ghostEdges, isEmpty);
      for (final node in baseline.nodes) {
        expect(result.nodeStatuses[node.id], DiffChangeType.unchanged);
      }
      for (final edge in baseline.edges) {
        expect(result.edgeStatuses[edge.edgeId], DiffChangeType.unchanged);
      }
    });

    test('Detects missing switch and emits ghost node and ghost edges', () {
      final baseline = buildBaseline();
      final currentNodes = {
        for (final n in baseline.nodes)
          if (n.id != '10.0.2.3') n.id: n,
      };
      final currentEdges = {
        for (final e in baseline.edges)
          if (e.sourceIp != '10.0.2.3' && e.targetIp != '10.0.2.3') e.edgeId: e,
      };

      final result = TopologyDiffEngine.compare(
        baseline: baseline,
        currentNodes: currentNodes,
        currentEdges: currentEdges,
      );

      expect(result.hasDrift, isTrue);
      expect(result.ghostNodes.map((n) => n.id), ['10.0.2.3']);
      expect(
        result.ghostEdges.map((e) => e.edgeId),
        containsAll(['10.0.2.2->10.0.2.3', '10.0.2.1->10.0.2.3']),
      );
      expect(result.nodeStatuses['10.0.2.3'], DiffChangeType.missing);
      expect(result.edgeStatuses['10.0.2.2->10.0.2.3'], DiffChangeType.missing);
      expect(
        result.items.where((i) => i.type == DiffChangeType.missing && i.isCritical).length,
        3,
      );
    });

    test('Detects unexpected added device as non-critical warning and ignores unresponsive hops', () {
      final baseline = buildBaseline();
      final currentNodes = {for (final n in baseline.nodes) n.id: n};
      final currentEdges = {for (final e in baseline.edges) e.edgeId: e};

      final rogueDevice = NetworkNode(
        id: '10.0.2.222',
        ip: '10.0.2.222',
        macAddress: 'DE:AD:BE:EF:00:01',
        hopDepth: 3,
        sharedDeviceName: 'Unknown Laptop',
      );
      final anonHop = NetworkNode(
        id: 'Anon-Hop-Depth-2',
        ip: 'Anon-Hop-Depth-2',
        hopDepth: 2,
        isUnresponsive: true,
      );
      final newEdge = NetworkEdge(
        sourceIp: '10.0.2.2',
        targetIp: '10.0.2.222',
      );

      currentNodes[rogueDevice.id] = rogueDevice;
      currentNodes[anonHop.id] = anonHop;
      currentEdges[newEdge.edgeId] = newEdge;

      final result = TopologyDiffEngine.compare(
        baseline: baseline,
        currentNodes: currentNodes,
        currentEdges: currentEdges,
      );

      expect(result.hasDrift, isTrue);
      expect(result.criticalCount, 0);
      expect(result.nodeStatuses['10.0.2.222'], DiffChangeType.added);
      expect(result.nodeStatuses.containsKey('Anon-Hop-Depth-2'), isFalse);
      expect(result.edgeStatuses['10.0.2.2->10.0.2.222'], DiffChangeType.added);

      final addedItems = result.items.where((i) => i.type == DiffChangeType.added).toList();
      expect(addedItems.length, 2);
      expect(addedItems.every((i) => !i.isCritical), isTrue);
    });

    test('Detects shifted STP Root Bridge and IGMP Querier roles as critical', () {
      final baseline = buildBaseline();
      final currentNodes = {for (final n in baseline.nodes) n.id: n};
      final currentEdges = {for (final e in baseline.edges) e.edgeId: e};

      // Shift STP Root & IGMP Querier from sw1 (10.0.2.1) to sw2 (10.0.2.2).
      currentNodes['10.0.2.1'] = currentNodes['10.0.2.1']!.copyWith(
        isStpRootBridge: false,
        isIgmpQuerier: false,
      );
      currentNodes['10.0.2.2'] = currentNodes['10.0.2.2']!.copyWith(
        isStpRootBridge: true,
        stpPriority: 0,
        isIgmpQuerier: true,
        igmpQuerierVersion: 'IGMPv3',
      );

      final result = TopologyDiffEngine.compare(
        baseline: baseline,
        currentNodes: currentNodes,
        currentEdges: currentEdges,
      );

      expect(result.nodeStatuses['10.0.2.1'], DiffChangeType.roleChanged);
      expect(result.nodeStatuses['10.0.2.2'], DiffChangeType.roleChanged);

      final roleItems = result.items.where((i) => i.type == DiffChangeType.roleChanged).toList();
      expect(roleItems.length, 4);
      expect(roleItems.every((i) => i.isCritical), isTrue);
    });

    test('Detects moved STP ring split (forwarding <-> blocking) as critical', () {
      final baseline = buildBaseline();
      final currentNodes = {for (final n in baseline.nodes) n.id: n};
      final currentEdges = {for (final e in baseline.edges) e.edgeId: e};

      // Ring split moved from 10.0.2.2->10.0.2.3 to 10.0.2.1->10.0.2.3.
      currentEdges['10.0.2.2->10.0.2.3'] = currentEdges['10.0.2.2->10.0.2.3']!.copyWith(
        stpState: LinkStpState.forwarding,
      );
      currentEdges['10.0.2.1->10.0.2.3'] = currentEdges['10.0.2.1->10.0.2.3']!.copyWith(
        stpState: LinkStpState.blocking,
        blockingSwitchId: '10.0.2.3',
        blockingPortName: 'Gi1/0/23',
      );

      final result = TopologyDiffEngine.compare(
        baseline: baseline,
        currentNodes: currentNodes,
        currentEdges: currentEdges,
      );

      expect(result.edgeStatuses['10.0.2.2->10.0.2.3'], DiffChangeType.stpStateChanged);
      expect(result.edgeStatuses['10.0.2.1->10.0.2.3'], DiffChangeType.stpStateChanged);

      final stpItems =
          result.items.where((i) => i.type == DiffChangeType.stpStateChanged).toList();
      expect(stpItems.length, 2);
      expect(stpItems.every((i) => i.isCritical && i.isEdge), isTrue);
    });

    test('Detects link speed degradation from 1000 Mbps to 100 Mbps', () {
      final baseline = buildBaseline();
      final currentNodes = {for (final n in baseline.nodes) n.id: n};
      final currentEdges = {for (final e in baseline.edges) e.edgeId: e};

      currentEdges['10.0.2.1->10.0.2.2'] = currentEdges['10.0.2.1->10.0.2.2']!.copyWith(
        linkSpeedMbps: 100,
      );

      final result = TopologyDiffEngine.compare(
        baseline: baseline,
        currentNodes: currentNodes,
        currentEdges: currentEdges,
      );

      expect(result.edgeStatuses['10.0.2.1->10.0.2.2'], DiffChangeType.linkDegraded);
      final degradedItems =
          result.items.where((i) => i.type == DiffChangeType.linkDegraded).toList();
      expect(degradedItems.length, 1);
      expect(degradedItems.first.targetId, '10.0.2.1->10.0.2.2');
      expect(degradedItems.first.baselineValue, contains('1000 Mbps'));
      expect(degradedItems.first.currentValue, contains('100 Mbps'));
      expect(degradedItems.first.isEdge, isTrue);
    });

    test('Matches nodes by normalized MAC across IP changes and matches reversed switch links', () {
      final baseline = buildBaseline();
      final currentNodes = {
        for (final n in baseline.nodes) n.id: n,
      };
      // Switch 2 changed IP via DHCP & MAC formatting differs, plus edge direction flipped.
      currentNodes.remove('10.0.2.2');
      currentNodes['10.0.2.52'] = NetworkNode(
        id: '10.0.2.52',
        ip: '10.0.2.52',
        macAddress: '00-11-22-33-44-02',
        hopDepth: 2,
        isSwitchNode: true,
        deviceCategoryKey: 'switch',
        sharedDeviceName: 'Dist Switch B',
      );

      final currentEdges = <String, NetworkEdge>{
        '10.0.2.100->10.0.2.1': baseline.edges[0],
        // Reversed switch link + new mapped ID
        '10.0.2.52->10.0.2.1': NetworkEdge(
          sourceIp: '10.0.2.52',
          targetIp: '10.0.2.1',
          stpState: LinkStpState.forwarding,
          linkSpeedMbps: 1000,
        ),
        '10.0.2.52->10.0.2.3': NetworkEdge(
          sourceIp: '10.0.2.52',
          targetIp: '10.0.2.3',
          stpState: LinkStpState.blocking,
          linkSpeedMbps: 1000,
        ),
        '10.0.2.1->10.0.2.3': baseline.edges[3],
      };

      final result = TopologyDiffEngine.compare(
        baseline: baseline,
        currentNodes: currentNodes,
        currentEdges: currentEdges,
      );

      expect(result.hasDrift, isFalse);
      expect(result.nodeStatuses['10.0.2.52'], DiffChangeType.unchanged);
      expect(result.edgeStatuses['10.0.2.52->10.0.2.1'], DiffChangeType.unchanged);
    });
  });

  group('DiffSummaryDrawer Widget Tests', () {
    TopologySnapshot sampleSnapshot() => TopologySnapshot(
          id: 'snap_ui',
          name: 'Lab Core Baseline',
          createdAt: DateTime(2026, 11, 18, 12, 0),
          adapterName: 'eth0',
          nodes: [
            NetworkNode(id: '10.0.2.1', ip: '10.0.2.1', hopDepth: 1),
          ],
          edges: const [],
        );

    testWidgets('Displays All Match chip when no drift exists', (tester) async {
      tester.view.physicalSize = const Size(1200, 800);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(() => tester.view.resetPhysicalSize());

      var closed = false;
      await tester.pumpWidget(
        MaterialApp(
          theme: AppTheme.darkTheme(),
          home: Scaffold(
            body: Align(
              alignment: Alignment.centerRight,
              child: DiffSummaryDrawer(
                baseline: sampleSnapshot(),
                diffResult: const TopologyDiffResult(),
                onFocusTarget: (_) {},
                onClose: () => closed = true,
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('Baseline Diff'), findsOneWidget);
      expect(find.text('Lab Core Baseline'), findsOneWidget);
      expect(find.text('All Match'), findsWidgets);

      await tester.tap(find.byIcon(Icons.close));
      await tester.pumpAndSettle();
      expect(closed, isTrue);
    });

    testWidgets('Displays Critical and Warning chips and triggers Focus and Export callbacks',
        (tester) async {
      tester.view.physicalSize = const Size(1200, 800);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(() => tester.view.resetPhysicalSize());

      String? focusedTarget;
      var exported = false;

      const diff = TopologyDiffResult(
        items: [
          TopologyDiffItem(
            type: DiffChangeType.missing,
            targetId: '10.0.2.3',
            title: 'Missing Switch: Edge Switch C',
            baselineValue: 'Online (10.0.2.3)',
            currentValue: 'Offline / Missing',
            isCritical: true,
          ),
          TopologyDiffItem(
            type: DiffChangeType.linkDegraded,
            targetId: '10.0.2.1->10.0.2.2',
            title: 'Link Degraded: Core ↔ Dist',
            baselineValue: '1000 Mbps',
            currentValue: '100 Mbps',
            isCritical: false,
            isEdge: true,
          ),
        ],
      );

      await tester.pumpWidget(
        MaterialApp(
          theme: AppTheme.darkTheme(),
          home: Scaffold(
            body: Align(
              alignment: Alignment.centerRight,
              child: DiffSummaryDrawer(
                baseline: sampleSnapshot(),
                diffResult: diff,
                onFocusTarget: (id) => focusedTarget = id,
                onClose: () {},
                onExportBaseline: () => exported = true,
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('Critical: 1'), findsOneWidget);
      expect(find.text('Warnings: 1'), findsOneWidget);
      expect(find.text('Missing Switch: Edge Switch C'), findsOneWidget);
      expect(find.text('Link Degraded: Core ↔ Dist'), findsOneWidget);
      expect(find.text('Online (10.0.2.3)'), findsOneWidget);
      expect(find.text('100 Mbps'), findsOneWidget);

      await tester.tap(find.text('Focus').first);
      await tester.pumpAndSettle();
      expect(focusedTarget, '10.0.2.3');

      await tester.tap(find.byIcon(Icons.download_outlined));
      await tester.pumpAndSettle();
      expect(exported, isTrue);
    });
  });
}
