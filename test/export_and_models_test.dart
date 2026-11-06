import 'package:flutter_test/flutter_test.dart';
import 'package:net_route_scout/data/services/export_service.dart';
import 'package:net_route_scout/domain/models/network_edge.dart';
import 'package:net_route_scout/domain/models/network_node.dart';
import 'package:net_route_scout/domain/models/scan_progress.dart';
import 'package:net_route_scout/domain/models/trace_hop.dart';
import 'package:net_route_scout/domain/models/trace_result.dart';

void main() {
  group('ExportService Tests', () {
    test('buildTopologyExportData constructs complete structured payload with stats', () {
      final node1 = NetworkNode(
        id: '192.168.1.5',
        ip: '192.168.1.5',
        hopDepth: 0,
        isLocalHost: true,
        macAddress: '00:1A:2B:3C:4D:5E',
        vendor: 'Intel Corporate',
        sharedDeviceName: 'Dev Workstation',
      );

      final node2 = NetworkNode(
        id: '192.168.1.1',
        ip: '192.168.1.1',
        hopDepth: 1,
        isTarget: false,
        rttMs: 1.2,
      );

      final edge = NetworkEdge(
        sourceIp: '192.168.1.5',
        targetIp: '192.168.1.1',
        targetRoutes: const {'8.8.8.8'},
      );

      final trace = TraceResult(
        targetIp: '8.8.8.8',
        hops: const [
          TraceHop(depth: 1, ip: '192.168.1.1', rttMs: 1.2),
          TraceHop(depth: 2, ip: '8.8.8.8', rttMs: 14.5),
        ],
        isReachable: true,
        completedAt: DateTime.utc(2026, 11, 6, 12, 0, 0),
      );

      final payload = ExportService.buildTopologyExportData(
        nodes: {'192.168.1.5': node1, '192.168.1.1': node2},
        edges: {'192.168.1.5->192.168.1.1': edge},
        traces: [trace],
        localHostIp: '192.168.1.5',
      );

      expect(payload['app'], 'Net Route Scout');
      expect(payload['local_host_ip'], '192.168.1.5');
      expect(payload.containsKey('exported_at'), isTrue);

      final stats = payload['statistics'] as Map<String, dynamic>;
      expect(stats['total_nodes'], 2);
      expect(stats['total_edges'], 1);
      expect(stats['total_targets'], 1);

      final nodesList = payload['nodes'] as List;
      expect(nodesList.length, 2);
      expect(nodesList.first['ip'], '192.168.1.5');
      expect(nodesList.first['is_local_host'], isTrue);

      final edgesList = payload['edges'] as List;
      expect(edgesList.length, 1);
      expect(edgesList.first['source_ip'], '192.168.1.5');
      expect(edgesList.first['target_ip'], '192.168.1.1');

      final tracesList = payload['traces'] as List;
      expect(tracesList.length, 1);
      expect(tracesList.first['target_ip'], '8.8.8.8');
      expect(tracesList.first['is_reachable'], isTrue);
      expect((tracesList.first['hops'] as List).length, 2);
    });
  });

  group('Domain Models Serialization & Helper Tests', () {
    test('NetworkNode nodeType, displayName, and copyWith', () {
      final hostNode = NetworkNode(
        id: '192.168.1.5',
        ip: '192.168.1.5',
        hopDepth: 0,
        isLocalHost: true,
        sharedDeviceName: 'Local PC (Host)',
      );
      expect(hostNode.nodeType, NodeType.localHost);
      expect(hostNode.displayName, 'Local PC (Host)');

      final routerNode = NetworkNode(
        id: '192.168.1.1',
        ip: '192.168.1.1',
        hopDepth: 1,
        deviceCategoryKey: 'router',
      );
      expect(routerNode.nodeType, NodeType.intermediateRouter);
      expect(routerNode.displayName, '192.168.1.1');

      final anonNode = NetworkNode(
        id: 'anon:192.168.1.1:2',
        ip: 'anon:192.168.1.1:2',
        hopDepth: 2,
        isUnresponsive: true,
      );
      expect(anonNode.nodeType, NodeType.unresponsiveHop);

      final targetNode = NetworkNode(
        id: '8.8.8.8',
        ip: '8.8.8.8',
        hopDepth: 4,
        isTarget: true,
        hostname: 'dns.google',
      );
      expect(targetNode.nodeType, NodeType.targetEndpoint);
      expect(targetNode.displayName, 'dns.google');

      final copy = targetNode.copyWith(rttMs: 11.2);
      expect(copy.rttMs, 11.2);
      expect(copy.isTarget, isTrue);
      expect(copy.hostname, 'dns.google');

      final json = copy.toJson();
      expect(json['id'], '8.8.8.8');
      expect(json['is_target'], isTrue);
      expect(json['rtt_ms'], 11.2);
    });

    test('NetworkEdge serialization and copyWith', () {
      final edge = NetworkEdge(
        sourceIp: '10.0.0.1',
        targetIp: '10.0.0.2',
        targetRoutes: const {'10.0.0.50'},
      );
      expect(edge.edgeId, '10.0.0.1->10.0.0.2');

      final updated = edge.copyWith(targetRoutes: {'10.0.0.50', '10.0.0.60'});
      expect(updated.targetRoutes.length, 2);

      final json = updated.toJson();
      expect(json['source_ip'], '10.0.0.1');
      expect(json['target_ip'], '10.0.0.2');
      expect(json['target_routes'], containsAll(['10.0.0.50', '10.0.0.60']));
    });

    test('TraceHop and TraceResult serialization', () {
      const hop = TraceHop(
        depth: 1,
        ip: '192.168.1.1',
        rttMs: 2.5,
        isTimeout: false,
      );
      final hopJson = hop.toJson();
      expect(hopJson['depth'], 1);
      expect(hopJson['ip'], '192.168.1.1');
      expect(hopJson['rtt_ms'], 2.5);

      final result = TraceResult(
        targetIp: '192.168.1.1',
        hops: const [hop],
        isReachable: true,
        completedAt: DateTime.utc(2026, 11, 6),
      );
      final resJson = result.toJson();
      expect(resJson['target_ip'], '192.168.1.1');
      expect(resJson['is_reachable'], isTrue);
      expect((resJson['hops'] as List).length, 1);
    });

    test('ScanProgress defaults and copyWith', () {
      const initial = ScanProgress();
      expect(initial.isScanning, isFalse);
      expect(initial.totalTargets, 0);

      final active = initial.copyWith(
        phase: 'Tracing',
        totalTargets: 10,
        completedTargets: 5,
        isScanning: true,
      );
      expect(active.isScanning, isTrue);
      expect(active.phase, 'Tracing');
      expect(active.totalTargets, 10);
      expect(active.completedTargets, 5);
      expect(active.fraction, 0.5);
      expect(active.percentage, 50);
    });
  });
}
