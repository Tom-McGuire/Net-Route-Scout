import 'package:flutter_test/flutter_test.dart';
import 'package:net_route_scout/data/repositories/topology_repository.dart';
import 'package:net_route_scout/data/services/demo_data_generator.dart';
import 'package:net_route_scout/domain/models/trace_hop.dart';
import 'package:net_route_scout/domain/models/trace_result.dart';

void main() {
  group('TopologyRepository Tests', () {
    late TopologyRepository repo;

    setUp(() {
      repo = TopologyRepository();
      repo.setLocalHost('192.168.1.100', gatewayIp: '192.168.1.1');
    });

    test('Initializes with Local Host node at depth 0', () {
      expect(repo.nodes.containsKey('192.168.1.100'), isTrue);
      final hostNode = repo.nodes['192.168.1.100']!;
      expect(hostNode.isLocalHost, isTrue);
      expect(hostNode.hopDepth, 0);
    });

    test('Ingests single trace and deduplicates common gateway', () {
      final now = DateTime.now();

      // Trace 1: Target A
      repo.ingestTraceResult(
        TraceResult(
          targetIp: '10.0.1.50',
          hops: const [
            TraceHop(depth: 1, ip: '192.168.1.1', rttMs: 1.2),
            TraceHop(depth: 2, ip: '10.0.1.1', rttMs: 2.5),
            TraceHop(depth: 3, ip: '10.0.1.50', rttMs: 4.0),
          ],
          isReachable: true,
          completedAt: now,
        ),
      );

      // Trace 2: Target B (shares 192.168.1.1 and 10.0.1.1)
      repo.ingestTraceResult(
        TraceResult(
          targetIp: '10.0.1.80',
          hops: const [
            TraceHop(depth: 1, ip: '192.168.1.1', rttMs: 1.1),
            TraceHop(depth: 2, ip: '10.0.1.1', rttMs: 2.3),
            TraceHop(depth: 3, ip: '10.0.1.80', rttMs: 4.2),
          ],
          isReachable: true,
          completedAt: now,
        ),
      );

      // Gateway 192.168.1.1 must only appear once
      expect(repo.nodes.keys.where((k) => k == '192.168.1.1').length, 1);
      final gw = repo.nodes['192.168.1.1']!;
      expect(gw.associatedTargets, containsAll(['10.0.1.50', '10.0.1.80']));

      // Total nodes: Local Host + GW (192.168.1.1) + Switch (10.0.1.1) + Target A + Target B = 5
      expect(repo.nodes.length, 5);

      // Edges: Host->GW, GW->Switch, Switch->Target A, Switch->Target B = 4 edges
      expect(repo.edges.length, 4);
      final gwEdge = repo.edges['192.168.1.100->192.168.1.1'];
      expect(gwEdge, isNotNull);
      expect(gwEdge!.targetRoutes, containsAll(['10.0.1.50', '10.0.1.80']));
    });

    test('Reconstructs linear breadcrumb path correctly', () {
      final now = DateTime.now();
      repo.ingestTraceResult(
        TraceResult(
          targetIp: '10.0.1.50',
          hops: const [
            TraceHop(depth: 1, ip: '192.168.1.1', rttMs: 1.2),
            TraceHop(depth: 2, ip: '10.0.1.1', rttMs: 2.5),
            TraceHop(depth: 3, ip: '10.0.1.50', rttMs: 4.0),
          ],
          isReachable: true,
          completedAt: now,
        ),
      );

      final breadcrumbs = repo.getPathBreadcrumbs('10.0.1.50');
      expect(breadcrumbs.length, 4);
      expect(breadcrumbs[0].ip, '192.168.1.100');
      expect(breadcrumbs[1].ip, '192.168.1.1');
      expect(breadcrumbs[2].ip, '10.0.1.1');
      expect(breadcrumbs[3].ip, '10.0.1.50');
    });

    test('Active path selection correctly gathers upstream nodes', () {
      final now = DateTime.now();
      repo.ingestTraceResult(
        TraceResult(
          targetIp: '10.0.1.50',
          hops: const [
            TraceHop(depth: 1, ip: '192.168.1.1', rttMs: 1.2),
            TraceHop(depth: 2, ip: '10.0.1.1', rttMs: 2.5),
            TraceHop(depth: 3, ip: '10.0.1.50', rttMs: 4.0),
          ],
          isReachable: true,
          completedAt: now,
        ),
      );

      repo.selectNode('10.0.1.50');
      final activeNodes = repo.getActivePathNodeIds();
      expect(activeNodes, containsAll(['192.168.1.100', '192.168.1.1', '10.0.1.1', '10.0.1.50']));

      final activeEdges = repo.getActivePathEdgeIds();
      expect(activeEdges, contains('192.168.1.100->192.168.1.1'));
      expect(activeEdges, contains('192.168.1.1->10.0.1.1'));
      expect(activeEdges, contains('10.0.1.1->10.0.1.50'));
    });

    test('Demo topology loads properly with multi-hop branches', () {
      final demoTraces = DemoDataGenerator.generateDemoTraces();
      expect(demoTraces.isNotEmpty, isTrue);

      for (final trace in demoTraces) {
        repo.ingestTraceResult(trace);
      }

      // Check that all demo targets are present
      expect(repo.nodes.containsKey('10.0.1.45'), isTrue);
      expect(repo.nodes.containsKey('10.0.2.55'), isTrue);
      expect(repo.nodes.containsKey('10.0.3.50'), isTrue);

      // Check anonymous hop handling
      expect(repo.nodes.containsKey('Anon-Hop-Depth-2'), isTrue);
      final anon = repo.nodes['Anon-Hop-Depth-2']!;
      expect(anon.isUnresponsive, isTrue);
    });
  });
}
