enum StpPortState {
  disabled(1, 'Disabled'),
  blocking(2, 'Blocking / Discarding'),
  listening(3, 'Listening'),
  learning(4, 'Learning'),
  forwarding(5, 'Forwarding'),
  broken(6, 'Broken'),
  unknown(0, 'Unknown');

  final int code;
  final String label;
  const StpPortState(this.code, this.label);

  static StpPortState fromCode(int? code) {
    if (code == null) return StpPortState.unknown;
    return StpPortState.values.firstWhere(
      (e) => e.code == code,
      orElse: () => StpPortState.unknown,
    );
  }
}

enum StpPortRole {
  root('Root'),
  designated('Designated'),
  alternate('Alternate / Blocking'),
  disabled('Disabled'),
  unknown('Unknown');

  final String label;
  const StpPortRole(this.label);
}

class StpPortInfo {
  final int bridgePort;
  final int ifIndex;
  final String interfaceName;
  final StpPortState state;
  final StpPortRole role;
  final String? designatedBridgeId;

  const StpPortInfo({
    required this.bridgePort,
    required this.ifIndex,
    required this.interfaceName,
    required this.state,
    this.role = StpPortRole.unknown,
    this.designatedBridgeId,
  });

  bool get isBlocking => state == StpPortState.blocking;
  bool get isForwarding => state == StpPortState.forwarding;

  Map<String, dynamic> toJson() => {
        'bridge_port': bridgePort,
        'if_index': ifIndex,
        'interface_name': interfaceName,
        'state': state.code,
        'role': role.name,
        'designated_bridge_id': designatedBridgeId,
      };

  factory StpPortInfo.fromJson(Map<String, dynamic> json) {
    return StpPortInfo(
      bridgePort: json['bridge_port'] as int? ?? 0,
      ifIndex: json['if_index'] as int? ?? 0,
      interfaceName: json['interface_name'] as String? ?? 'Port',
      state: StpPortState.fromCode(json['state'] as int?),
      role: StpPortRole.values.firstWhere(
        (r) => r.name == json['role'],
        orElse: () => StpPortRole.unknown,
      ),
      designatedBridgeId: json['designated_bridge_id'] as String?,
    );
  }
}
