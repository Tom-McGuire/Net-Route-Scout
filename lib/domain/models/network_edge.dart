import 'interface_health_stats.dart';
import 'port_vlan_config.dart';

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

  // Trunk VLAN & Physical Link Telemetry (Issues #4 & #5)
  final String? sourcePortName;
  final String? targetPortName;
  final VlanMismatchReport? vlanMismatch;
  final int? linkSpeedMbps;
  final DuplexMode linkDuplex;
  final int inErrorsDelta;
  final int outDiscardsDelta;

  NetworkEdge({
    required this.sourceIp,
    required this.targetIp,
    Set<String>? targetRoutes,
    this.stpState = LinkStpState.unknown,
    this.blockingSwitchId,
    this.blockingPortName,
    this.trafficDirectionTargetNodeId,
    this.sourcePortName,
    this.targetPortName,
    this.vlanMismatch,
    this.linkSpeedMbps,
    this.linkDuplex = DuplexMode.unknown,
    this.inErrorsDelta = 0,
    this.outDiscardsDelta = 0,
  }) : targetRoutes = targetRoutes ?? <String>{};

  String get edgeId => '$sourceIp->$targetIp';

  bool get hasVlanMismatch => vlanMismatch?.hasAnyMismatch ?? false;
  bool get isDegradedSpeed => linkSpeedMbps != null && linkSpeedMbps! > 0 && linkSpeedMbps! < 1000;
  bool get isHalfDuplex => linkDuplex == DuplexMode.halfDuplex;
  bool get hasActiveErrors => inErrorsDelta > 0 || outDiscardsDelta > 0;

  String? get speedBadgeLabel {
    if (isHalfDuplex) return 'HALF-DUPLEX ⚠';
    if (isDegradedSpeed) return '${linkSpeedMbps}M ⚠';
    if (linkSpeedMbps != null && linkSpeedMbps! >= 10000) return '${linkSpeedMbps! ~/ 1000}G';
    if (linkSpeedMbps == 2500) return '2.5G';
    if (linkSpeedMbps != null && linkSpeedMbps! >= 1000) return '${linkSpeedMbps! ~/ 1000}G';
    return null;
  }

  NetworkEdge copyWith({
    String? sourceIp,
    String? targetIp,
    Set<String>? targetRoutes,
    LinkStpState? stpState,
    String? blockingSwitchId,
    String? blockingPortName,
    String? trafficDirectionTargetNodeId,
    String? sourcePortName,
    String? targetPortName,
    VlanMismatchReport? vlanMismatch,
    int? linkSpeedMbps,
    DuplexMode? linkDuplex,
    int? inErrorsDelta,
    int? outDiscardsDelta,
  }) {
    return NetworkEdge(
      sourceIp: sourceIp ?? this.sourceIp,
      targetIp: targetIp ?? this.targetIp,
      targetRoutes: targetRoutes ?? Set<String>.from(this.targetRoutes),
      stpState: stpState ?? this.stpState,
      blockingSwitchId: blockingSwitchId ?? this.blockingSwitchId,
      blockingPortName: blockingPortName ?? this.blockingPortName,
      trafficDirectionTargetNodeId: trafficDirectionTargetNodeId ?? this.trafficDirectionTargetNodeId,
      sourcePortName: sourcePortName ?? this.sourcePortName,
      targetPortName: targetPortName ?? this.targetPortName,
      vlanMismatch: vlanMismatch ?? this.vlanMismatch,
      linkSpeedMbps: linkSpeedMbps ?? this.linkSpeedMbps,
      linkDuplex: linkDuplex ?? this.linkDuplex,
      inErrorsDelta: inErrorsDelta ?? this.inErrorsDelta,
      outDiscardsDelta: outDiscardsDelta ?? this.outDiscardsDelta,
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
        'source_port_name': sourcePortName,
        'target_port_name': targetPortName,
        'vlan_mismatch': vlanMismatch?.toJson(),
        'link_speed_mbps': linkSpeedMbps,
        'link_duplex': linkDuplex.name,
        'in_errors_delta': inErrorsDelta,
        'out_discards_delta': outDiscardsDelta,
      };

  factory NetworkEdge.fromJson(Map<String, dynamic> json) {
    final rawRoutes = json['target_routes'];
    final stpName = json['stp_state'] as String?;
    final duplexName = json['link_duplex'] as String?;
    final rawVlan = json['vlan_mismatch'];

    return NetworkEdge(
      sourceIp: json['source_ip'] as String? ?? '',
      targetIp: json['target_ip'] as String? ?? '',
      targetRoutes: rawRoutes is List ? rawRoutes.whereType<String>().toSet() : <String>{},
      stpState: LinkStpState.values.firstWhere(
        (s) => s.name == stpName,
        orElse: () => LinkStpState.unknown,
      ),
      blockingSwitchId: json['blocking_switch_id'] as String?,
      blockingPortName: json['blocking_port_name'] as String?,
      trafficDirectionTargetNodeId: json['traffic_direction_target_node_id'] as String?,
      sourcePortName: json['source_port_name'] as String?,
      targetPortName: json['target_port_name'] as String?,
      vlanMismatch: rawVlan is Map<String, dynamic> ? VlanMismatchReport.fromJson(rawVlan) : null,
      linkSpeedMbps: json['link_speed_mbps'] as int?,
      linkDuplex: DuplexMode.values.firstWhere(
        (d) => d.name == duplexName,
        orElse: () => DuplexMode.unknown,
      ),
      inErrorsDelta: json['in_errors_delta'] as int? ?? 0,
      outDiscardsDelta: json['out_discards_delta'] as int? ?? 0,
    );
  }
}
