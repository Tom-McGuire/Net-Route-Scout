import 'network_edge.dart';
import 'network_node.dart';

enum DiffChangeType {
  unchanged,
  added,
  missing,
  roleChanged,
  stpStateChanged,
  linkDegraded,
}

class TopologyDiffItem {
  final DiffChangeType type;
  final String targetId;
  final String title;
  final String baselineValue;
  final String currentValue;
  final bool isCritical;
  final bool isEdge;

  const TopologyDiffItem({
    required this.type,
    required this.targetId,
    required this.title,
    required this.baselineValue,
    required this.currentValue,
    this.isCritical = true,
    this.isEdge = false,
  });
}

class TopologyDiffResult {
  final List<TopologyDiffItem> items;
  final Map<String, DiffChangeType> nodeStatuses;
  final Map<String, DiffChangeType> edgeStatuses;
  final List<NetworkNode> ghostNodes;
  final List<NetworkEdge> ghostEdges;

  bool get hasDrift => items.isNotEmpty;
  int get criticalCount => items.where((i) => i.isCritical).length;

  const TopologyDiffResult({
    this.items = const [],
    this.nodeStatuses = const {},
    this.edgeStatuses = const {},
    this.ghostNodes = const [],
    this.ghostEdges = const [],
  });
}
