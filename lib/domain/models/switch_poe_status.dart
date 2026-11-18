enum PoePortState {
  disabled(1, 'Disabled'),
  searching(2, 'Searching'),
  deliveringPower(3, 'Delivering'),
  fault(4, 'Fault'),
  test(5, 'Testing'),
  otherFault(6, 'Overload / Fault');

  final int code;
  final String label;
  const PoePortState(this.code, this.label);

  static PoePortState fromCode(int? code) {
    if (code == null) return PoePortState.disabled;
    return PoePortState.values.firstWhere(
      (e) => e.code == code,
      orElse: () => PoePortState.disabled,
    );
  }
}

class PoePortDetail {
  final int portIndex;
  final String interfaceName;
  final PoePortState state;
  final String? powerClass;
  final double? drawWatts;

  bool get isFault => state == PoePortState.fault || state == PoePortState.otherFault;

  const PoePortDetail({
    required this.portIndex,
    required this.interfaceName,
    required this.state,
    this.powerClass,
    this.drawWatts,
  });

  Map<String, dynamic> toJson() => {
        'port_index': portIndex,
        'interface_name': interfaceName,
        'state': state.code,
        'power_class': powerClass,
        'draw_watts': drawWatts,
      };

  factory PoePortDetail.fromJson(Map<String, dynamic> json) {
    return PoePortDetail(
      portIndex: json['port_index'] as int? ?? 0,
      interfaceName: json['interface_name'] as String? ?? 'Port',
      state: PoePortState.fromCode(json['state'] as int?),
      powerClass: json['power_class'] as String?,
      drawWatts: (json['draw_watts'] as num?)?.toDouble(),
    );
  }
}

class SwitchPoeStatus {
  final int totalBudgetWatts;
  final int consumedWatts;
  final List<PoePortDetail> ports;

  double get utilizationPercent =>
      totalBudgetWatts > 0 ? (consumedWatts / totalBudgetWatts) * 100.0 : 0.0;

  int get remainingWatts => (totalBudgetWatts - consumedWatts).clamp(0, totalBudgetWatts);
  bool get isNearCapacity => utilizationPercent >= 80.0;
  bool get isCriticalCapacity => utilizationPercent >= 90.0;
  bool get hasPortFaults => ports.any((p) => p.isFault);

  const SwitchPoeStatus({
    required this.totalBudgetWatts,
    required this.consumedWatts,
    this.ports = const [],
  });

  Map<String, dynamic> toJson() => {
        'total_budget_watts': totalBudgetWatts,
        'consumed_watts': consumedWatts,
        'ports': ports.map((p) => p.toJson()).toList(),
      };

  factory SwitchPoeStatus.fromJson(Map<String, dynamic> json) {
    final rawPorts = json['ports'];
    return SwitchPoeStatus(
      totalBudgetWatts: json['total_budget_watts'] as int? ?? 0,
      consumedWatts: json['consumed_watts'] as int? ?? 0,
      ports: rawPorts is List
          ? rawPorts.whereType<Map<String, dynamic>>().map(PoePortDetail.fromJson).toList()
          : const [],
    );
  }
}
