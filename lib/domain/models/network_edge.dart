class NetworkEdge {
  final String sourceIp;
  final String targetIp;
  final Set<String> targetRoutes;

  NetworkEdge({
    required this.sourceIp,
    required this.targetIp,
    Set<String>? targetRoutes,
  }) : targetRoutes = targetRoutes ?? <String>{};

  String get edgeId => '$sourceIp->$targetIp';

  NetworkEdge copyWith({
    String? sourceIp,
    String? targetIp,
    Set<String>? targetRoutes,
  }) {
    return NetworkEdge(
      sourceIp: sourceIp ?? this.sourceIp,
      targetIp: targetIp ?? this.targetIp,
      targetRoutes: targetRoutes ?? Set<String>.from(this.targetRoutes),
    );
  }

  Map<String, dynamic> toJson() => {
    'source_ip': sourceIp,
    'target_ip': targetIp,
    'target_routes': targetRoutes.toList(),
  };
}
