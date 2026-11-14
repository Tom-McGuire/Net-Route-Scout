enum LinkStpState {
  forwarding, // Active Layer 2 traffic path
  blocking,   // Severed by STP/RSTP (Alternate/Discarding port)
  unknown,    // Unmanaged switch or STP polling unavailable
}

class NetworkEdge {
  final String sourceIp;
  final String targetIp;
  final Set<String> targetRoutes;
  final LinkStpState stpState;
  final String? blockingSwitchId;
  final String? blockingPortName;
  final String? trafficDirectionTargetNodeId;

  NetworkEdge({
    required this.sourceIp,
    required this.targetIp,
    Set<String>? targetRoutes,
    this.stpState = LinkStpState.unknown,
    this.blockingSwitchId,
    this.blockingPortName,
    this.trafficDirectionTargetNodeId,
  }) : targetRoutes = targetRoutes ?? <String>{};

  String get edgeId => '$sourceIp->$targetIp';

  NetworkEdge copyWith({
    String? sourceIp,
    String? targetIp,
    Set<String>? targetRoutes,
    LinkStpState? stpState,
    String? blockingSwitchId,
    String? blockingPortName,
    String? trafficDirectionTargetNodeId,
  }) {
    return NetworkEdge(
      sourceIp: sourceIp ?? this.sourceIp,
      targetIp: targetIp ?? this.targetIp,
      targetRoutes: targetRoutes ?? Set<String>.from(this.targetRoutes),
      stpState: stpState ?? this.stpState,
      blockingSwitchId: blockingSwitchId ?? this.blockingSwitchId,
      blockingPortName: blockingPortName ?? this.blockingPortName,
      trafficDirectionTargetNodeId: trafficDirectionTargetNodeId ?? this.trafficDirectionTargetNodeId,
    );
  }

  Map<String, dynamic> toJson() => {
    'source_ip': sourceIp,
    'target_ip': targetIp,
    'target_routes': targetRoutes.toList(),
    'stp_state': stpState.name,
    'blocking_switch_id': blockingSwitchId,
    'blocking_port_name': blockingPortName,
    'traffic_direction_target_node_id': trafficDirectionTargetNodeId,
  };
}
