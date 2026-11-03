import 'dart:async';
import 'dart:convert';
import 'dart:io';
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
    void Function(TraceHop hop)? onHopDiscovered,
  }) async {
    if (_isCancelled) {
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

    if (Platform.isWindows) {
      executable = 'tracert';
      args = ['-d', '-h', '$maxHops', '-w', '$timeoutMs'];
      if (sourceIp != null && sourceIp.isNotEmpty && sourceIp != '0.0.0.0') {
        args.addAll(['-S', sourceIp]);
      }
      args.add(targetIp);
    } else if (Platform.isMacOS) {
      executable = 'traceroute';
      args = ['-n', '-m', '$maxHops', '-w', '$timeoutMs', '-q', '1'];
      if (sourceIp != null && sourceIp.isNotEmpty && sourceIp != '0.0.0.0') {
        args.addAll(['-s', sourceIp]);
      }
      args.add(targetIp);
    } else {
      // Linux
      final bin = await _resolveLinuxTracerouteBin();
      executable = bin;
      if (bin == 'tracepath') {
        args = ['-n', '-m', '$maxHops', targetIp];
      } else {
        args = ['-n', '-m', '$maxHops', '-w', '1', '-q', '1'];
        if (sourceIp != null && sourceIp.isNotEmpty && sourceIp != '0.0.0.0') {
          args.addAll(['-s', sourceIp]);
        }
        args.add(targetIp);
      }
    }

    Process? proc;
    final hops = <TraceHop>[];
    double? lastRtt;
    bool reached = false;

    try {
      proc = await Process.start(executable, args);
      _activeProcesses.add(proc);

      final lineStream = proc.stdout
          .transform(utf8.decoder)
          .transform(const LineSplitter());

      await for (final line in lineStream) {
        if (_isCancelled) break;
        final hop = _parseHopLine(line, executable);
        if (hop != null) {
          hops.add(hop);
          if (hop.rttMs != null) lastRtt = hop.rttMs;
          if (hop.ip == targetIp) reached = true;
          onHopDiscovered?.call(hop);
        }
      }

      await proc.exitCode.timeout(
        Duration(seconds: maxHops * 2 + 5),
        onTimeout: () {
          proc?.kill();
          return -1;
        },
      );
    } catch (e) {
      // If process fails or cancelled
    } finally {
      if (proc != null) _activeProcesses.remove(proc);
    }

    // If last hop matches target, mark reachable
    if (hops.isNotEmpty && hops.last.ip == targetIp) {
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
  TraceHop? _parseHopLine(String rawLine, String binary) {
    final line = rawLine.trim();
    if (line.isEmpty) return null;

    // 1. Linux `tracepath` format:
    // " 1?: [LOCALHOST]                      pmtu 1500" -> ignore header
    // " 1:  10.101.1.1                                            4.616ms"
    // " 2:  no reply"
    if (binary == 'tracepath') {
      if (line.contains('?:') || line.contains('Resume:') || line.contains('Too many hops')) {
        return null;
      }
      final tracepathMatch = RegExp(r'^(\d+):\s+(?:([0-9.]+)\s+.*?(\d+(?:\.\d+)?)\s*ms|(no reply))', caseSensitive: false)
          .firstMatch(line);
      if (tracepathMatch != null) {
        final depth = int.tryParse(tracepathMatch.group(1)!) ?? 1;
        final ip = tracepathMatch.group(2);
        final rttStr = tracepathMatch.group(3);
        final isNoReply = tracepathMatch.group(4) != null;

        if (isNoReply || ip == null) {
          return TraceHop(
            depth: depth,
            ip: 'Anon-Hop-Depth-$depth',
            isTimeout: true,
            rawText: line,
          );
        }
        return TraceHop(
          depth: depth,
          ip: ip,
          rttMs: double.tryParse(rttStr ?? ''),
          rawText: line,
        );
      }
    }

    // 2. Linux / macOS `traceroute` format:
    // " 1  10.101.1.1  0.512 ms"
    // " 2  * * *" or " 2  *"
    final tracerouteMatch = RegExp(r'^(\d+)\s+([0-9.*]+)(?:\s+(\d+(?:\.\d+)?)\s*ms)?').firstMatch(line);
    if (tracerouteMatch != null) {
      final depth = int.tryParse(tracerouteMatch.group(1)!) ?? 1;
      final ipOrStar = tracerouteMatch.group(2)!;
      final rttStr = tracerouteMatch.group(3);

      if (ipOrStar.contains('*')) {
        return TraceHop(
          depth: depth,
          ip: 'Anon-Hop-Depth-$depth',
          isTimeout: true,
          rawText: line,
        );
      }

      if (_isValidIpv4(ipOrStar)) {
        return TraceHop(
          depth: depth,
          ip: ipOrStar,
          rttMs: rttStr != null ? double.tryParse(rttStr) : null,
          rawText: line,
        );
      }
    }

    // 3. Windows `tracert` format:
    // "  1    <1 ms    <1 ms    <1 ms  192.168.1.1"
    // "  2     *        *        *     Request timed out."
    final winMatch = RegExp(r'^\s*(\d+)\s+(.+)$').firstMatch(line);
    if (winMatch != null) {
      final depth = int.tryParse(winMatch.group(1)!) ?? 1;
      final remainder = winMatch.group(2)!;

      if (remainder.contains('Request timed out') || !RegExp(r'\d{1,3}(?:\.\d{1,3}){3}').hasMatch(remainder)) {
        return TraceHop(
          depth: depth,
          ip: 'Anon-Hop-Depth-$depth',
          isTimeout: true,
          rawText: line,
        );
      }

      final ipMatch = RegExp(r'(\d{1,3}(?:\.\d{1,3}){3})').firstMatch(remainder);
      if (ipMatch != null) {
        final ip = ipMatch.group(1)!;
        // Find RTT in ms
        final rttMatch = RegExp(r'(\d+(?:\.\d+)?)\s*ms').firstMatch(remainder);
        final rtt = rttMatch != null ? double.tryParse(rttMatch.group(1)!) : null;
        return TraceHop(
          depth: depth,
          ip: ip,
          rttMs: rtt,
          rawText: line,
        );
      }
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

  /// Traces multiple target IPs concurrently using a worker pool.
  Future<List<TraceResult>> sweepTargets(
    List<String> targetIps, {
    int concurrency = 4,
    int maxHops = 15,
    int timeoutMs = 1000,
    String? sourceIp,
    void Function(int completed, int total, String currentIp, TraceResult result)? onTargetCompleted,
    void Function(String targetIp, TraceHop hop)? onHopDiscovered,
  }) async {
    _isCancelled = false;
    final results = <TraceResult>[];
    var completed = 0;
    final total = targetIps.length;

    for (var i = 0; i < targetIps.length; i += concurrency) {
      if (_isCancelled) break;
      final end = (i + concurrency < targetIps.length) ? i + concurrency : targetIps.length;
      final chunk = targetIps.sublist(i, end);

      final chunkFutures = chunk.map((targetIp) async {
        final res = await traceTarget(
          targetIp,
          maxHops: maxHops,
          timeoutMs: timeoutMs,
          sourceIp: sourceIp,
          onHopDiscovered: (hop) => onHopDiscovered?.call(targetIp, hop),
        );
        completed++;
        onTargetCompleted?.call(completed, total, targetIp, res);
        return res;
      });

      final chunkResults = await Future.wait(chunkFutures);
      results.addAll(chunkResults);
    }

    return results;
  }
}
