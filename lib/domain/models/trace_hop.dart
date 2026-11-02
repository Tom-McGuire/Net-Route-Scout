class TraceHop {
  final int depth;
  final String ip;
  final double? rttMs;
  final bool isTimeout;
  final String? rawText;

  const TraceHop({
    required this.depth,
    required this.ip,
    this.rttMs,
    this.isTimeout = false,
    this.rawText,
  });

  bool get isAnonymous => ip.startsWith('Anon-Hop-') || ip == '*';

  Map<String, dynamic> toJson() => {
    'depth': depth,
    'ip': ip,
    'rtt_ms': rttMs,
    'is_timeout': isTimeout,
    'raw_text': rawText,
  };

  factory TraceHop.fromJson(Map<String, dynamic> json) => TraceHop(
    depth: json['depth'] as int? ?? 1,
    ip: json['ip'] as String? ?? '?',
    rttMs: (json['rtt_ms'] as num?)?.toDouble(),
    isTimeout: json['is_timeout'] as bool? ?? false,
    rawText: json['raw_text'] as String?,
  );

  @override
  String toString() => 'Hop $depth: $ip (${rttMs != null ? "${rttMs!.toStringAsFixed(1)} ms" : "timeout"})';
}
