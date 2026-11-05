import 'dart:async';
import 'dart:convert';
import 'dart:io';
import '../../domain/models/cancellation_token.dart';
import '../../domain/models/trace_hop.dart';
import '../../domain/models/trace_result.dart';

class TracerouteService {
  final Set<Process> _activeProcesses = {};
  bool _isCancelled = false;
  String? _cachedLinuxBinary;

  bool get isCancelled => _isCancelled;

  void cancel() {
    _isCancelled = true;
    for (final p in _activeProcesses.toList()) {
      try {
        p.kill(ProcessSignal.sigkill);
      } catch (_) {}
    }
    _activeProcesses.clear();
  }

  /// Finds the best available traceroute binary on Linux.
  Future<String> _resolveLinuxTracerouteBin() async {
    if (_cachedLinuxBinary != null) return _cachedLinuxBinary!;
    try {
      final res = await Process.run('which', ['traceroute']);
      if (res.exitCode == 0 && res.stdout.toString().trim().isNotEmpty) {
        _cachedLinuxBinary = 'traceroute';
        return 'traceroute';
      }
    } catch (_) {}

    try {
      final res = await Process.run('which', ['tracepath']);
      if (res.exitCode == 0 && res.stdout.toString().trim().isNotEmpty) {
        _cachedLinuxBinary = 'tracepath';
        return 'tracepath';
      }
    } catch (_) {}

    _cachedLinuxBinary = 'traceroute';
    return 'traceroute';
  }

  /// Traces route to a single target IP using the native OS CLI tool.
  Future<TraceResult> traceTarget(
    String targetIp, {
    int maxHops = 15,
    int timeoutMs = 1000,
    String? sourceIp,
    CancellationToken? cancelToken,
    void Function(TraceHop hop)? onHopDiscovered,
  }) async {
    if (_isCancelled || (cancelToken != null && cancelToken.isCancelled)) {
      return TraceResult(
        targetIp: targetIp,
        hops: const [],
        isReachable: false,
        completedAt: DateTime.now(),
        error: 'Cancelled',
      );
    }

    String executable;
    List<String> args;
    final waitSec = (timeoutMs / 1000).ceil().clamp(1, 10);

    if (Platform.isWindows) {
      executable = 'tracert';
      // Windows tracert -w takes milliseconds. Windows routes through the adapter matching the subnet.
      args = ['-d', '-h', '$maxHops', '-w', '$timeoutMs', targetIp];
    } else if (Platform.isMacOS) {
      executable = 'traceroute';
      // macOS traceroute -w takes seconds.
      args = ['-n', '-m', '$maxHops', '-w', '$waitSec', '-q', '1', targetIp];
    } else {
      // Linux
      final bin = await _resolveLinuxTracerouteBin();
      executable = bin;
      if (bin == 'tracepath') {
        args = ['-n', '-m', '$maxHops', targetIp];
      } else {
        args = ['-n', '-m', '$maxHops', '-w', '$waitSec', '-q', '1', targetIp];
      }
    }

    Process? proc;
    Timer? timeoutTimer;
    final hops = <TraceHop>[];
    double? lastRtt;
    bool reached = false;
    String? lastResponsiveIp;

    void onCancel() {
      try {
        proc?.kill(ProcessSignal.sigkill);
      } catch (_) {}
    }

    cancelToken?.onCancel(onCancel);

    try {
      proc = await Process.start(executable, args);
      _activeProcesses.add(proc);

      // Drain stderr to prevent process stall if pipe buffer fills up
      proc.stderr.drain<void>().catchError((_) {});

      // Enforce total trace timeout
      final totalTimeoutSec = (maxHops * waitSec + 6).clamp(10, 120);
      timeoutTimer = Timer(Duration(seconds: totalTimeoutSec), () {
        try {
          proc?.kill(ProcessSignal.sigkill);
        } catch (_) {}
      });

      final lineStream = proc.stdout
          .transform(utf8.decoder)
          .transform(const LineSplitter());

      await for (final line in lineStream) {
        if (_isCancelled || (cancelToken != null && cancelToken.isCancelled)) break;
        final hop = parseHopLine(line, executable, previousIp: lastResponsiveIp);
        if (hop != null) {
          if (!hop.isTimeout) {
            lastResponsiveIp = hop.ip;
            if (hop.rttMs != null) lastRtt = hop.rttMs;
            if (hop.ip == targetIp) reached = true;
          }

          // De-duplicate repeat lines for the same hop depth (e.g. tracepath pmtu updates)
          if (hops.isNotEmpty && hops.last.depth == hop.depth) {
            if (hops.last.isTimeout && !hop.isTimeout) {
              hops.removeLast();
              hops.add(hop);
              onHopDiscovered?.call(hop);
            }
          } else {
            hops.add(hop);
            onHopDiscovered?.call(hop);
          }
        }
      }

      await proc.exitCode;
    } catch (_) {
      // Process was cancelled or failed
    } finally {
      timeoutTimer?.cancel();
      cancelToken?.removeListener(onCancel);
      if (proc != null) _activeProcesses.remove(proc);
    }

    // If last hop matches target, mark reachable
    if (hops.isNotEmpty && hops.last.ip == targetIp && !hops.last.isTimeout) {
      reached = true;
    }

    return TraceResult(
      targetIp: targetIp,
      hops: hops,
      isReachable: reached,
      finalRttMs: lastRtt,
      completedAt: DateTime.now(),
    );
  }

  /// Parses a single line from Windows tracert, Linux traceroute, or Linux tracepath.
  static TraceHop? parseHopLine(String rawLine, String binary, {String? previousIp}) {
    if (Platform.isWindows || binary == 'tracert') {
      return parseWindowsTracertLine(rawLine, previousIp: previousIp);
    } else if (binary == 'tracepath') {
      return parseLinuxTracepathLine(rawLine, previousIp: previousIp);
    } else {
      return parseLinuxTracerouteLine(rawLine, previousIp: previousIp);
    }
  }

  /// Parses a Windows tracert output line.
  /// Handles normal lines, partial loss lines (e.g. `2 * 5 ms 4 ms 10.0.0.1`), and timeouts.
  static TraceHop? parseWindowsTracertLine(String rawLine, {String? previousIp}) {
    final line = rawLine.trim();
    if (line.isEmpty) return null;

    final winMatch = RegExp(r'^\s*(\d+)\s+(.+)$').firstMatch(line);
    if (winMatch == null) return null;

    final depth = int.tryParse(winMatch.group(1)!) ?? 1;
    final remainder = winMatch.group(2)!;

    // Look for IPv4 address
    final ipMatch = RegExp(r'\b(\d{1,3}(?:\.\d{1,3}){3})\b').firstMatch(remainder);
    if (ipMatch != null && _isValidIpv4(ipMatch.group(1)!)) {
      final ip = ipMatch.group(1)!;
      final rttMatches = RegExp(r'(?:<(\d+)|(\d+(?:\.\d+)?))\s*ms').allMatches(remainder);
      double? minRtt;
      for (final m in rttMatches) {
        final val = m.group(1) != null ? 0.5 : double.tryParse(m.group(2)!);
        if (val != null) {
          if (minRtt == null || val < minRtt) minRtt = val;
        }
      }
      return TraceHop(
        depth: depth,
        ip: ip,
        rttMs: minRtt,
        isTimeout: false,
        rawText: line,
      );
    }

    // If no IP found and contains * or "Request timed out"
    if (remainder.contains('*') || remainder.contains('Request timed out')) {
      final prev = previousIp ?? 'root';
      return TraceHop(
        depth: depth,
        ip: 'anon:$prev:$depth',
        isTimeout: true,
        rawText: line,
      );
    }

    return null;
  }

  /// Parses a Linux / macOS traceroute output line.
  static TraceHop? parseLinuxTracerouteLine(String rawLine, {String? previousIp}) {
    final line = rawLine.trim();
    if (line.isEmpty) return null;

    final match = RegExp(r'^\s*(\d+)\s+(.+)$').firstMatch(line);
    if (match == null) return null;

    final depth = int.tryParse(match.group(1)!) ?? 1;
    final remainder = match.group(2)!;

    final ipMatch = RegExp(r'\b(\d{1,3}(?:\.\d{1,3}){3})\b').firstMatch(remainder);
    if (ipMatch != null && _isValidIpv4(ipMatch.group(1)!)) {
      final ip = ipMatch.group(1)!;
      final rttMatches = RegExp(r'(\d+(?:\.\d+)?)\s*ms').allMatches(remainder);
      double? minRtt;
      for (final m in rttMatches) {
        final val = double.tryParse(m.group(1)!);
        if (val != null && (minRtt == null || val < minRtt)) minRtt = val;
      }
      return TraceHop(
        depth: depth,
        ip: ip,
        rttMs: minRtt,
        isTimeout: false,
        rawText: line,
      );
    }

    if (remainder.contains('*')) {
      final prev = previousIp ?? 'root';
      return TraceHop(
        depth: depth,
        ip: 'anon:$prev:$depth',
        isTimeout: true,
        rawText: line,
      );
    }

    return null;
  }

  /// Parses a Linux tracepath output line.
  static TraceHop? parseLinuxTracepathLine(String rawLine, {String? previousIp}) {
    final line = rawLine.trim();
    if (line.isEmpty) return null;
    if (line.contains('?:') || line.contains('Resume:') || line.contains('Too many hops')) {
      return null;
    }

    final match = RegExp(r'^\s*(\d+):\s+(.+)$').firstMatch(line);
    if (match == null) return null;

    final depth = int.tryParse(match.group(1)!) ?? 1;
    final remainder = match.group(2)!;

    if (remainder.contains('no reply')) {
      final prev = previousIp ?? 'root';
      return TraceHop(
        depth: depth,
        ip: 'anon:$prev:$depth',
        isTimeout: true,
        rawText: line,
      );
    }

    final ipMatch = RegExp(r'\b(\d{1,3}(?:\.\d{1,3}){3})\b').firstMatch(remainder);
    if (ipMatch != null && _isValidIpv4(ipMatch.group(1)!)) {
      final ip = ipMatch.group(1)!;
      final rttMatch = RegExp(r'(\d+(?:\.\d+)?)\s*ms').firstMatch(remainder);
      final rtt = rttMatch != null ? double.tryParse(rttMatch.group(1)!) : null;
      return TraceHop(
        depth: depth,
        ip: ip,
        rttMs: rtt,
        isTimeout: false,
        rawText: line,
      );
    }

    return null;
  }

  static bool _isValidIpv4(String s) {
    final parts = s.split('.');
    if (parts.length != 4) return false;
    for (final p in parts) {
      final n = int.tryParse(p);
      if (n == null || n < 0 || n > 255) return false;
    }
    return true;
  }

  /// Traces multiple target IPs concurrently using a queue-based worker pool.
  Future<List<TraceResult>> sweepTargets(
    List<String> targetIps, {
    int concurrency = 4,
    int maxHops = 15,
    int timeoutMs = 1000,
    String? sourceIp,
    CancellationToken? cancelToken,
    void Function(int completed, int total, String currentIp, TraceResult result)? onTargetCompleted,
    void Function(String targetIp, TraceHop hop)? onHopDiscovered,
  }) async {
    final results = <TraceResult>[];
    var completed = 0;
    final total = targetIps.length;
    var currentIndex = 0;

    Future<void> worker() async {
      while (true) {
        if (_isCancelled || (cancelToken != null && cancelToken.isCancelled)) break;
        if (currentIndex >= targetIps.length) break;
        final targetIp = targetIps[currentIndex++];

        final res = await traceTarget(
          targetIp,
          maxHops: maxHops,
          timeoutMs: timeoutMs,
          sourceIp: sourceIp,
          cancelToken: cancelToken,
          onHopDiscovered: (hop) => onHopDiscovered?.call(targetIp, hop),
        );

        results.add(res);
        completed++;
        onTargetCompleted?.call(completed, total, targetIp, res);
      }
    }

    final poolSize = concurrency.clamp(1, targetIps.length);
    final workers = List.generate(poolSize, (_) => worker());
    await Future.wait(workers);

    return results;
  }
}
