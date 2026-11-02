import 'dart:async';
import 'dart:io';

class IcmpPingResult {
  final String ip;
  final bool reachable;
  final double? rttMs;
  final int? ttl;

  const IcmpPingResult({
    required this.ip,
    required this.reachable,
    this.rttMs,
    this.ttl,
  });
}

class IcmpService {
  final Set<Process> _activeProcesses = {};
  bool _isCancelled = false;

  bool get isCancelled => _isCancelled;

  void cancel() {
    _isCancelled = true;
    for (final p in _activeProcesses.toList()) {
      try {
        p.kill();
      } catch (_) {}
    }
    _activeProcesses.clear();
  }

  /// Resolves the absolute path to ping on Windows to avoid DLL hijacking.
  static String _resolvePingBinary() {
    if (Platform.isWindows) {
      final sysRoot = Platform.environment['SystemRoot'] ?? r'C:\Windows';
      final candidate = '$sysRoot\\System32\\ping.exe';
      if (File(candidate).existsSync()) return candidate;
    }
    return 'ping';
  }

  /// Validates IPv4 address string.
  static bool isValidIpv4(String ip) {
    final parts = ip.trim().split('.');
    if (parts.length != 4) return false;
    for (final p in parts) {
      final n = int.tryParse(p);
      if (n == null || n < 0 || n > 255) return false;
    }
    return true;
  }

  /// Converts IPv4 to 32-bit unsigned integer.
  static int ipv4ToInt(String ip) {
    final parts = ip.split('.').map(int.parse).toList();
    return (parts[0] << 24) | (parts[1] << 16) | (parts[2] << 8) | parts[3];
  }

  /// Converts 32-bit integer to IPv4 address string.
  static String intToIpv4(int num) {
    return '${(num >> 24) & 0xFF}.${(num >> 16) & 0xFF}.${(num >> 8) & 0xFF}.${num & 0xFF}';
  }

  /// Expands CIDR (192.168.1.0/24), range (10.0.0.1-50 or 10.0.0.1-10.0.0.50), or single IP.
  static List<String> expandTargetSpec(String input, {int maxHosts = 1024}) {
    final trimmed = input.trim();
    if (trimmed.isEmpty) return const [];

    // 1. CIDR notation: 192.168.1.0/24
    if (trimmed.contains('/')) {
      final parts = trimmed.split('/');
      if (parts.length != 2) return const [];
      final baseIp = parts[0].trim();
      final prefix = int.tryParse(parts[1].trim());
      if (!isValidIpv4(baseIp) || prefix == null || prefix < 16 || prefix > 32) {
        return const [];
      }
      if (prefix == 32) return [baseIp];

      final ipNum = ipv4ToInt(baseIp);
      final hostBits = 32 - prefix;
      final mask = (0xFFFFFFFF << hostBits) & 0xFFFFFFFF;
      final network = ipNum & mask;
      final broadcast = network | ((1 << hostBits) - 1);

      final startIp = prefix >= 31 ? network : network + 1;
      final endIp = prefix >= 31 ? broadcast : broadcast - 1;
      final count = (endIp - startIp + 1).clamp(0, maxHosts);

      return List<String>.generate(count, (i) => intToIpv4(startIp + i));
    }

    // 2. Hyphenated range: 192.168.1.1-192.168.1.50 or 192.168.1.1-50
    if (trimmed.contains('-')) {
      final parts = trimmed.split('-');
      if (parts.length != 2) return const [];
      final startStr = parts[0].trim();
      final endStr = parts[1].trim();
      if (!isValidIpv4(startStr)) return const [];
      final startNum = ipv4ToInt(startStr);

      int endNum;
      if (endStr.contains('.')) {
        if (!isValidIpv4(endStr)) return const [];
        endNum = ipv4ToInt(endStr);
      } else {
        final lastOctet = int.tryParse(endStr);
        if (lastOctet == null || lastOctet < 0 || lastOctet > 255) return const [];
        final octets = startStr.split('.');
        endNum = ipv4ToInt('${octets[0]}.${octets[1]}.${octets[2]}.$lastOctet');
      }

      if (endNum < startNum) return const [];
      final count = (endNum - startNum + 1).clamp(0, maxHosts);
      return List<String>.generate(count, (i) => intToIpv4(startNum + i));
    }

    // 3. Single IPv4
    if (isValidIpv4(trimmed)) {
      return [trimmed];
    }

    return const [];
  }

  /// Sends a single ICMP echo probe to [ip].
  Future<IcmpPingResult> pingHost(String ip, {int timeoutMs = 400}) async {
    if (_isCancelled || !isValidIpv4(ip)) {
      return IcmpPingResult(ip: ip, reachable: false);
    }

    Process? proc;
    try {
      final bin = _resolvePingBinary();
      final args = Platform.isWindows
          ? ['-n', '1', '-w', '$timeoutMs', ip]
          : ['-c', '1', '-W', Platform.isMacOS ? '$timeoutMs' : '1', ip];

      final sw = Stopwatch()..start();
      proc = await Process.start(bin, args);
      _activeProcesses.add(proc);

      final stdoutFuture = proc.stdout.transform(const SystemEncoding().decoder).join();
      final exitCode = await proc.exitCode.timeout(
        Duration(milliseconds: timeoutMs + 600),
        onTimeout: () {
          proc?.kill();
          return -1;
        },
      );
      sw.stop();
      _activeProcesses.remove(proc);

      if (_isCancelled || exitCode != 0) {
        return IcmpPingResult(ip: ip, reachable: false);
      }

      final output = await stdoutFuture;
      // Windows ping returns exitCode 0 even when "Destination host unreachable"
      final ttlMatch = RegExp(r'ttl[=<](\d+)', caseSensitive: false).firstMatch(output);
      if (ttlMatch == null && Platform.isWindows) {
        return IcmpPingResult(ip: ip, reachable: false);
      }

      final ttl = ttlMatch != null ? int.tryParse(ttlMatch.group(1)!) : null;
      final timeMatch = RegExp(r'time[=<](\d+(?:\.\d+)?)\s*ms', caseSensitive: false).firstMatch(output);
      final rtt = timeMatch != null
          ? double.tryParse(timeMatch.group(1)!)
          : sw.elapsedMilliseconds.toDouble();

      return IcmpPingResult(ip: ip, reachable: true, rttMs: rtt, ttl: ttl);
    } catch (_) {
      if (proc != null) _activeProcesses.remove(proc);
      return IcmpPingResult(ip: ip, reachable: false);
    }
  }

  /// Sweeps [targetIps] with a concurrency worker pool.
  /// Calls [onProgress] as results arrive.
  Future<List<String>> sweepActiveHosts(
    List<String> targetIps, {
    int concurrency = 16,
    int timeoutMs = 350,
    void Function(int completed, int total, String currentIp, bool reached)? onProgress,
  }) async {
    _isCancelled = false;
    final activeHosts = <String>[];
    var completed = 0;
    final total = targetIps.length;

    for (var i = 0; i < targetIps.length; i += concurrency) {
      if (_isCancelled) break;
      final end = (i + concurrency < targetIps.length) ? i + concurrency : targetIps.length;
      final batch = targetIps.sublist(i, end);

      final results = await Future.wait(
        batch.map((ip) => pingHost(ip, timeoutMs: timeoutMs)),
      );

      for (final res in results) {
        completed++;
        if (res.reachable) {
          activeHosts.add(res.ip);
        }
        onProgress?.call(completed, total, res.ip, res.reachable);
      }
    }

    return activeHosts;
  }
}
