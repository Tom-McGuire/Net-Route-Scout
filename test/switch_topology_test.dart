import 'package:flutter_test/flutter_test.dart';
import 'package:net_route_scout/data/repositories/topology_repository.dart';
import 'package:net_route_scout/domain/models/network_node.dart';
import 'package:net_route_scout/domain/models/trace_hop.dart';
import 'package:net_route_scout/domain/models/trace_result.dart';
import 'package:net_route_scout/ui/view_models/topology_view_model.dart';

void main() {
  group('Switch Topology Manipulation Tests', () {
    late TopologyRepository repository;

    setUp(() {
      repository = TopologyRepository();
      repository.setLocalHost('192.168.1.100', gatewayIp: '192.168.1.1');

      // Add simple trace: 192.168.1.100 -> 192.168.1.1 (GW) -> 10.0.1.50 (Endpoint)
      repository.ingestTraceResult(
        TraceResult(
          targetIp: '10.0.1.50',
          isReachable: true,
          completedAt: DateTime.now(),
          hops: const [
            TraceHop(depth: 1, ip: '192.168.1.1'),
            TraceHop(depth: 2, ip: '10.0.1.50'),
          ],
        ),
      );
    });

    test('defineNodeAsSwitch marks node as switch and sets switch category', () {
      expect(repository.nodes['192.168.1.1']?.isSwitch, false);

      repository.defineNodeAsSwitch('192.168.1.1', isSwitch: true, name: 'Core Router/Switch');

      final node = repository.nodes['192.168.1.1'];
      expect(node?.isSwitch, true);
      expect(node?.nodeType, NodeType.switchDevice);
      expect(node?.deviceCategoryKey, 'switch');
      expect(node?.displayName, 'Core Router/Switch');
      expect(repository.customSwitchNodeIds.contains('192.168.1.1'), true);

      // Revert back
      repository.defineNodeAsSwitch('192.168.1.1', isSwitch: false);
      expect(repository.nodes['192.168.1.1']?.isSwitch, false);
      expect(repository.customSwitchNodeIds.contains('192.168.1.1'), false);
    });

    test('addStandaloneSwitch creates new switch node anchored upstream', () {
      final sw = repository.addStandaloneSwitch(
        name: 'Desk Switch',
        ip: '192.168.1.10',
        model: 'Netgear GS108E',
      );

      expect(repository.nodes.containsKey('192.168.1.10'), true);
      expect(sw.isSwitch, true);
      expect(sw.nodeType, NodeType.switchDevice);
      expect(sw.displayName, 'Desk Switch');
      expect(repository.edges.containsKey('192.168.1.1->192.168.1.10'), true);
    });

    test('connectNodeToSwitch re-wires edges and updates child switch port', () {
      // Initially, 10.0.1.50 is connected to 192.168.1.1
      expect(repository.edges.containsKey('192.168.1.1->10.0.1.50'), true);

      // Add a switch
      final sw = repository.addStandaloneSwitch(
        name: 'Floor 1 Switch',
        ip: '10.0.1.2',
      );

      // Connect endpoint 10.0.1.50 to Floor 1 Switch Port 8
      repository.connectNodeToSwitch('10.0.1.50', sw.id, portLabel: 'Port 8');

      // The old direct edge from 192.168.1.1 -> 10.0.1.50 should be removed
      expect(repository.edges.containsKey('192.168.1.1->10.0.1.50'), false);

      // The new edge from Floor 1 Switch -> 10.0.1.50 should exist
      expect(repository.edges.containsKey('10.0.1.2->10.0.1.50'), true);

      final endpoint = repository.nodes['10.0.1.50'];
      expect(endpoint?.connectedSwitchId, '10.0.1.2');
      expect(endpoint?.switchPort, 'Port 8');
      expect(repository.customSwitchLinks['10.0.1.50'], '10.0.1.2');
    });

    test('Switch-to-Switch connection correctly computes cascading topological depths', () {
      // 1. Gateway is 192.168.1.1
      // 2. Core Switch is 10.0.0.1 (anchored to Gateway)
      final coreSwitch = repository.addStandaloneSwitch(
        name: 'Core Switch',
        ip: '10.0.0.1',
        upstreamNodeId: '192.168.1.1',
      );

      // 3. Access Switch is 10.0.0.2 (connected to Core Switch)
      final accessSwitch = repository.addStandaloneSwitch(
        name: 'Access Switch',
        ip: '10.0.0.2',
        upstreamNodeId: coreSwitch.id,
      );
      repository.connectNodeToSwitch(accessSwitch.id, coreSwitch.id, portLabel: 'Uplink 1');

      // 4. Endpoint 10.0.1.50 connected to Access Switch
      repository.connectNodeToSwitch('10.0.1.50', accessSwitch.id, portLabel: 'Port 12');

      final depths = repository.computeTopologicalDepths();

      // Host = 0, Gateway = 1, Core Switch = 2, Access Switch = 3, Endpoint = 4
      expect(depths['192.168.1.100'], 0);
      expect(depths['192.168.1.1'], 1);
      expect(depths['10.0.0.1'], 2);
      expect(depths['10.0.0.2'], 3);
      expect(depths['10.0.1.50'], 4);

      expect(repository.getEffectiveDepth('10.0.1.50'), 4);
    });

    test('disconnectNodeFromSwitch restores traceroute predecessor link', () {
      final sw = repository.addStandaloneSwitch(name: 'Temp Switch', ip: '10.0.1.2');
      repository.connectNodeToSwitch('10.0.1.50', sw.id, portLabel: 'Port 1');

      expect(repository.edges.containsKey('10.0.1.2->10.0.1.50'), true);

      // Disconnect
      repository.disconnectNodeFromSwitch('10.0.1.50');

      expect(repository.edges.containsKey('10.0.1.2->10.0.1.50'), false);
      expect(repository.edges.containsKey('192.168.1.1->10.0.1.50'), true);

      final endpoint = repository.nodes['10.0.1.50'];
      expect(endpoint?.connectedSwitchId, isNull);
      expect(endpoint?.switchPort, isNull);
    });

    test('restoreCustomSwitches re-applies persisted switch definitions and links', () {
      repository.restoreCustomSwitches(
        switchNodeIds: {'192.168.1.1'},
        switchLinks: {'10.0.1.50': '192.168.1.1'},
        switchPorts: {'10.0.1.50': 'Port 2'},
      );

      final sw = repository.nodes['192.168.1.1'];
      final endpoint = repository.nodes['10.0.1.50'];

      expect(sw?.isSwitch, true);
      expect(endpoint?.connectedSwitchId, '192.168.1.1');
      expect(endpoint?.switchPort, 'Port 2');
    });
  });

  group('TopologyViewModel Switch Methods Tests', () {
    test('ViewModel exposes availableSwitches and manages switch linking', () {
      final vm = TopologyViewModel(autoInit: false);
      vm.loadDemoTopology();

      // Demo topology includes Distribution Switch and Floor 2 Access Switch
      expect(vm.availableSwitches.length, greaterThanOrEqualTo(2));
      expect(vm.availableSwitches.any((s) => s.displayName.contains('Distribution Switch')), true);
      expect(vm.availableSwitches.any((s) => s.displayName.contains('Access Switch')), true);

      final initialSwitchesCount = vm.availableSwitches.length;

      // Add a standalone switch
      final newSw = vm.addStandaloneSwitch(
        name: 'Lab Test Switch',
        ip: '192.168.1.250',
      );

      expect(vm.availableSwitches.length, initialSwitchesCount + 1);
      expect(newSw.displayName, 'Lab Test Switch');

      // Define an existing node as switch
      vm.defineNodeAsSwitch('10.0.1.45', isSwitch: true);
      expect(vm.nodes['10.0.1.45']?.isSwitch, true);

      // Disconnect
      vm.defineNodeAsSwitch('10.0.1.45', isSwitch: false);
      expect(vm.nodes['10.0.1.45']?.isSwitch, false);
    });
  });
}
