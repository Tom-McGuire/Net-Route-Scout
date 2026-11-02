import 'trace_hop.dart';

class TraceResult {
  final String targetIp;
  final List<TraceHop> hops;
  final bool isReachable;
  final double? finalRttMs;
  final DateTime completedAt;
  final String? error;

  const TraceResult({
    required this.targetIp,
    required this.hops,
    required this.isReachable,
    this.finalRttMs,
    required this.completedAt,
    this.error,
  });

  int get hopCount => hops.length;

  Map<String, dynamic> toJson() => {
    'target_ip': targetIp,
    'hops': hops.map((h) => h.toJson()).toList(),
    'is_reachable': isReachable,
    'final_rtt_ms': finalRttMs,
    'completed_at': completedAt.toIso8601String(),
    'error': error,
  };
}
