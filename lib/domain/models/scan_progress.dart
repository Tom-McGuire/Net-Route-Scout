class ScanProgress {
  final String phase;
  final int totalTargets;
  final int completedTargets;
  final int activeWorkers;
  final String? currentTarget;
  final bool isScanning;

  const ScanProgress({
    this.phase = 'Idle',
    this.totalTargets = 0,
    this.completedTargets = 0,
    this.activeWorkers = 0,
    this.currentTarget,
    this.isScanning = false,
  });

  double get fraction =>
      totalTargets > 0 ? (completedTargets / totalTargets).clamp(0.0, 1.0) : 0.0;

  int get percentage => (fraction * 100).round();

  ScanProgress copyWith({
    String? phase,
    int? totalTargets,
    int? completedTargets,
    int? activeWorkers,
    String? currentTarget,
    bool? isScanning,
  }) {
    return ScanProgress(
      phase: phase ?? this.phase,
      totalTargets: totalTargets ?? this.totalTargets,
      completedTargets: completedTargets ?? this.completedTargets,
      activeWorkers: activeWorkers ?? this.activeWorkers,
      currentTarget: currentTarget ?? this.currentTarget,
      isScanning: isScanning ?? this.isScanning,
    );
  }
}
