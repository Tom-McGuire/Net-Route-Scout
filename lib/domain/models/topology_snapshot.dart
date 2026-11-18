import 'network_edge.dart';
import 'network_node.dart';

class TopologySnapshot {
  final String id;
  final String name;
  final DateTime createdAt;
  final String adapterName;
  final List<NetworkNode> nodes;
  final List<NetworkEdge> edges;

  const TopologySnapshot({
    required this.id,
    required this.name,
    required this.createdAt,
    required this.adapterName,
    required this.nodes,
    required this.edges,
  });

  Map<String, dynamic> toJson() => {
        'id': id,
        'name': name,
        'createdAt': createdAt.toIso8601String(),
        'adapterName': adapterName,
        'nodes': nodes.map((n) => n.toJson()).toList(),
        'edges': edges.map((e) => e.toJson()).toList(),
      };

  factory TopologySnapshot.fromJson(Map<String, dynamic> json) {
    final rawNodes = json['nodes'];
    final rawEdges = json['edges'];
    return TopologySnapshot(
      id: json['id'] as String? ?? 'snapshot_${DateTime.now().millisecondsSinceEpoch}',
      name: json['name'] as String? ?? 'Baseline Snapshot',
      createdAt: DateTime.tryParse(json['createdAt'] as String? ?? '') ?? DateTime.now(),
      adapterName: json['adapterName'] as String? ?? '',
      nodes: rawNodes is List
          ? rawNodes.whereType<Map<String, dynamic>>().map(NetworkNode.fromJson).toList()
          : const [],
      edges: rawEdges is List
          ? rawEdges.whereType<Map<String, dynamic>>().map(NetworkEdge.fromJson).toList()
          : const [],
    );
  }
}
