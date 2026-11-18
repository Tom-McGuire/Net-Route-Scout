enum DuplexMode {
  unknown(1, 'Unknown'),
  halfDuplex(2, 'Half-Duplex'),
  fullDuplex(3, 'Full-Duplex');

  final int code;
  final String label;
  const DuplexMode(this.code, this.label);

  static DuplexMode fromCode(int? code) {
    if (code == null) return DuplexMode.unknown;
    return DuplexMode.values.firstWhere(
      (e) => e.code == code,
      orElse: () => DuplexMode.unknown,
    );
  }
}

class InterfaceHealthStats {
  final int ifIndex;
  final String interfaceName;
  final int speedMbps;
  final bool isOperUp;
  final DuplexMode duplex;
  final int inErrors;
  final int outErrors;
  final int inDiscards;
  final int outDiscards;
  final int inErrorsDelta;
  final int outDiscardsDelta;
  final DateTime sampledAt;

  bool get isDegradedSpeed => speedMbps > 0 && speedMbps < 1000;
  bool get isHalfDuplex => duplex == DuplexMode.halfDuplex;
  bool get hasActiveErrors => inErrorsDelta > 0 || outDiscardsDelta > 0;
  bool get hasHistoricalErrors =>
      inErrors > 0 || outErrors > 0 || inDiscards > 0 || outDiscards > 0;

  String get formattedSpeed {
    if (speedMbps >= 10000) return '${speedMbps ~/ 1000}G';
    if (speedMbps == 2500) return '2.5G';
    if (speedMbps >= 1000) return '${speedMbps ~/ 1000}G';
    if (speedMbps > 0) return '${speedMbps}M';
    return '—';
  }

  const InterfaceHealthStats({
    required this.ifIndex,
    required this.interfaceName,
    required this.speedMbps,
    this.isOperUp = true,
    this.duplex = DuplexMode.unknown,
    this.inErrors = 0,
    this.outErrors = 0,
    this.inDiscards = 0,
    this.outDiscards = 0,
    this.inErrorsDelta = 0,
    this.outDiscardsDelta = 0,
    required this.sampledAt,
  });

  /// Safe 32-bit Counter32 rollover delta calculation.
  static int computeCounterDelta(int previous, int current) {
    if (current >= previous) return current - previous;
    return (0xFFFFFFFF - previous) + current + 1;
  }

  InterfaceHealthStats withPreviousSample(InterfaceHealthStats? previous) {
    if (previous == null) return this;
    return InterfaceHealthStats(
      ifIndex: ifIndex,
      interfaceName: interfaceName,
      speedMbps: speedMbps,
      isOperUp: isOperUp,
      duplex: duplex,
      inErrors: inErrors,
      outErrors: outErrors,
      inDiscards: inDiscards,
      outDiscards: outDiscards,
      inErrorsDelta: computeCounterDelta(previous.inErrors, inErrors),
      outDiscardsDelta: computeCounterDelta(previous.outDiscards, outDiscards),
      sampledAt: sampledAt,
    );
  }

  Map<String, dynamic> toJson() => {
        'if_index': ifIndex,
        'interface_name': interfaceName,
        'speed_mbps': speedMbps,
        'is_oper_up': isOperUp,
        'duplex': duplex.name,
        'in_errors': inErrors,
        'out_errors': outErrors,
        'in_discards': inDiscards,
        'out_discards': outDiscards,
        'in_errors_delta': inErrorsDelta,
        'out_discards_delta': outDiscardsDelta,
        'sampled_at': sampledAt.toIso8601String(),
      };

  factory InterfaceHealthStats.fromJson(Map<String, dynamic> json) {
    final duplexName = json['duplex'] as String?;
    return InterfaceHealthStats(
      ifIndex: json['if_index'] as int? ?? 0,
      interfaceName: json['interface_name'] as String? ?? 'Port',
      speedMbps: json['speed_mbps'] as int? ?? 0,
      isOperUp: json['is_oper_up'] as bool? ?? true,
      duplex: DuplexMode.values.firstWhere(
        (d) => d.name == duplexName,
        orElse: () => DuplexMode.unknown,
      ),
      inErrors: json['in_errors'] as int? ?? 0,
      outErrors: json['out_errors'] as int? ?? 0,
      inDiscards: json['in_discards'] as int? ?? 0,
      outDiscards: json['out_discards'] as int? ?? 0,
      inErrorsDelta: json['in_errors_delta'] as int? ?? 0,
      outDiscardsDelta: json['out_discards_delta'] as int? ?? 0,
      sampledAt: DateTime.tryParse(json['sampled_at'] as String? ?? '') ?? DateTime.now(),
    );
  }
}
