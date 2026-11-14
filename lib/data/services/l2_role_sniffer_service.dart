import 'dart:async';
import 'dart:convert';
import 'dart:io';
import '../../domain/models/switch_discovery_info.dart';

/// Describes a packet-capture permission failure when `tcpdump` or `tshark`
/// is installed on the host, but lacks privileges to sniff on [interfaceName].
class L2CapturePermissionIssue {
  final String interfaceName;
  final bool tcpdumpFound;
  final bool tsharkFound;
  final String? tcpdumpError;
  final String? tsharkError;

  const L2CapturePermissionIssue({
    required this.interfaceName,
    required this.tcpdumpFound,
    required this.tsharkFound,
    this.tcpdumpError,
    this.tsharkError,
  });

  String get detectedToolsLabel {
    if (tcpdumpFound && tsharkFound) return 'tcpdump & tshark';
    if (tcpdumpFound) return 'tcpdump';
    if (tsharkFound) return 'tshark';
    return 'packet sniffer';
  }
}

/// Passive Layer 2/3 control-frame sniffer using `tcpdump` (primary) with
/// automatic fallback to `tshark` (Wireshark CLI).
///
/// Uses a decoupled two-phase capture architecture:
/// 1. Fast 4s bounded capture for STP BPDUs (`01:80:C2:00:00:00`).
/// 2. Background ~130s listener for IGMP General Queries (`224.0.0.1`, Type `0x11`).
class L2RoleSnifferService {
  /// Returns true if [stderr] indicates a packet-capture permission or privilege error.
  static bool isPermissionError(String stderr) {
    final lower = stderr.toLowerCase();
    return lower.contains('permission') ||
        lower.contains('not permitted') ||
        lower.contains('cap_net_raw') ||
        lower.contains('access is denied') ||
        lower.contains("you don't have permission") ||
        lower.contains('could not open device') ||
        lower.contains('/dev/bpf');
  }

  /// Phase 1: Bounded 4-second passive capture for STP Root Bridge BPDU.
  static Future<StpPassiveResult?> captureStpRoot({
    required String interfaceName,
    Duration timeout = const Duration(seconds: 4),
    void Function(L2CapturePermissionIssue issue)? onPermissionIssue,
  }) async {
    if (interfaceName.trim().isEmpty) return null;

    final hasTcpdump = await _isCommandAvailable('tcpdump');
    final hasTshark = await _isCommandAvailable('tshark');

    String? tcpdumpErr;
    String? tsharkErr;

    // 1. Try tcpdump first
    if (hasTcpdump) {
      final tcpdumpResult = await _runTcpdumpStp(
        interfaceName,
        timeout,
        onError: (err) => tcpdumpErr = err,
      );
      if (tcpdumpResult != null) return tcpdumpResult;
    }

    // 2. Fallback to tshark
    if (hasTshark) {
      final tsharkResult = await _runTsharkStp(
        interfaceName,
        timeout,
        onError: (err) => tsharkErr = err,
      );
      if (tsharkResult != null) return tsharkResult;
    }

    final tcpdumpDenied = tcpdumpErr != null && isPermissionError(tcpdumpErr!);
    final tsharkDenied = tsharkErr != null && isPermissionError(tsharkErr!);
    if ((tcpdumpDenied || tsharkDenied) && onPermissionIssue != null) {
      onPermissionIssue(
        L2CapturePermissionIssue(
          interfaceName: interfaceName,
          tcpdumpFound: hasTcpdump,
          tsharkFound: hasTshark,
          tcpdumpError: tcpdumpErr?.trim(),
          tsharkError: tsharkErr?.trim(),
        ),
      );
    }

    return null;
  }

  /// Phase 2: Background stream for IGMP General Queries (`224.0.0.1`, Type `0x11`).
  /// In single-sweep mode, runs up to [timeout] (~130s) and stops on first match.
  /// In [continuous] mode, keeps emitting updates across sweep intervals until cancelled.
  static Stream<IgmpPassiveResult> listenForIgmpQuerier({
    required String interfaceName,
    Duration timeout = const Duration(seconds: 130),
    bool continuous = false,
  }) async* {
    if (interfaceName.trim().isEmpty) return;

    // Try tcpdump first; if it fails due to permissions or is not installed, fall back to tshark
    final useTcpdump = await _isCommandAvailable('tcpdump');
    var tcpdumpPermissionFailed = false;
    if (useTcpdump) {
      yield* _streamTcpdumpIgmp(
        interfaceName,
        timeout: timeout,
        continuous: continuous,
        onPermissionError: () => tcpdumpPermissionFailed = true,
      );
      if (!tcpdumpPermissionFailed) return;
    }

    final useTshark = await _isCommandAvailable('tshark');
    if (useTshark) {
      yield* _streamTsharkIgmp(interfaceName, timeout: timeout, continuous: continuous);
    }
  }

  static Future<bool> _isCommandAvailable(String binary) async {
    try {
      final cmd = Platform.isWindows ? 'where' : 'which';
      final res = await Process.run(cmd, [binary]).timeout(const Duration(seconds: 1));
      return res.exitCode == 0;
    } catch (_) {
      return false;
    }
  }

  static Future<StpPassiveResult?> _runTcpdumpStp(
    String iface,
    Duration timeout, {
    void Function(String stderr)? onError,
  }) async {
    Process? proc;
    try {
      proc = await Process.start('tcpdump', [
        '-c', '1',
        '-i', iface,
        '-nn', '-e',
        '-s', '1500',
        'ether dst 01:80:c2:00:00:00 or ether[14:4] == 0x42420300',
      ]);

      final lines = <String>[];
      final errLines = <String>[];
      final sub = proc.stdout.transform(utf8.decoder).transform(const LineSplitter()).listen(lines.add);
      final errSub = proc.stderr.transform(utf8.decoder).transform(const LineSplitter()).listen(errLines.add);

      final exitCode = await proc.exitCode.timeout(timeout, onTimeout: () {
        proc?.kill();
        return -1;
      });
      await sub.cancel();
      await errSub.cancel();

      if (exitCode == 0 && lines.isNotEmpty) {
        return parseTcpdumpStpOutput(lines.join('\n'));
      }
      if (exitCode != 0 && exitCode != -1 && errLines.isNotEmpty) {
        onError?.call(errLines.join('\n'));
      }
    } catch (e) {
      proc?.kill();
      onError?.call(e.toString());
    }
    return null;
  }

  static Future<StpPassiveResult?> _runTsharkStp(
    String iface,
    Duration timeout, {
    void Function(String stderr)? onError,
  }) async {
    Process? proc;
    try {
      final durationSec = timeout.inSeconds.clamp(1, 30);
      proc = await Process.start('tshark', [
        '-i', iface,
        '-a', 'duration:$durationSec',
        '-c', '1',
        '-Y', 'stp',
        '-T', 'fields',
        '-e', 'eth.src',
        '-e', 'stp.root.hw',
        '-e', 'stp.root.prio',
      ]);

      final lines = <String>[];
      final errLines = <String>[];
      final sub = proc.stdout.transform(utf8.decoder).transform(const LineSplitter()).listen(lines.add);
      final errSub = proc.stderr.transform(utf8.decoder).transform(const LineSplitter()).listen(errLines.add);

      final exitCode = await proc.exitCode.timeout(timeout + const Duration(seconds: 2), onTimeout: () {
        proc?.kill();
        return -1;
      });
      await sub.cancel();
      await errSub.cancel();

      if (exitCode == 0 && lines.isNotEmpty) {
        return parseTsharkStpOutput(lines.join('\n'));
      }
      if (exitCode != 0 && exitCode != -1 && errLines.isNotEmpty) {
        onError?.call(errLines.join('\n'));
      }
    } catch (e) {
      proc?.kill();
      onError?.call(e.toString());
    }
    return null;
  }

  static Stream<IgmpPassiveResult> _streamTcpdumpIgmp(
    String iface, {
    required Duration timeout,
    required bool continuous,
    void Function()? onPermissionError,
  }) async* {
    Process? proc;
    try {
      final args = <String>[
        if (!continuous) ...['-c', '1'],
        '-l', // Line-buffered output
        '-i', iface,
        '-nn', '-v',
        '-s', '1500',
        'igmp and dst 224.0.0.1 and ip[20] == 0x11',
      ];
      proc = await Process.start('tcpdump', args);

      final controller = StreamController<IgmpPassiveResult>();
      Timer? timeoutTimer;
      if (!continuous) {
        timeoutTimer = Timer(timeout, () {
          proc?.kill();
          if (!controller.isClosed) controller.close();
        });
      }

      final buffer = StringBuffer();
      final errBuffer = StringBuffer();
      final errSub = proc.stderr.transform(utf8.decoder).transform(const LineSplitter()).listen((line) {
        errBuffer.writeln(line);
      });

      final sub = proc.stdout.transform(utf8.decoder).transform(const LineSplitter()).listen(
        (line) {
          buffer.writeln(line);
          final parsed = parseTcpdumpIgmpOutput(buffer.toString());
          if (parsed != null) {
            if (!controller.isClosed) controller.add(parsed);
            buffer.clear();
            if (!continuous) {
              timeoutTimer?.cancel();
              proc?.kill();
              if (!controller.isClosed) controller.close();
            }
          }
        },
        onDone: () {
          timeoutTimer?.cancel();
          if (isPermissionError(errBuffer.toString())) {
            onPermissionError?.call();
          }
          if (!controller.isClosed) controller.close();
        },
        onError: (_) {
          timeoutTimer?.cancel();
          if (!controller.isClosed) controller.close();
        },
      );

      yield* controller.stream;
      await sub.cancel();
      await errSub.cancel();
    } catch (_) {
      proc?.kill();
    } finally {
      proc?.kill();
    }
  }

  static Stream<IgmpPassiveResult> _streamTsharkIgmp(
    String iface, {
    required Duration timeout,
    required bool continuous,
  }) async* {
    Process? proc;
    try {
      final durationSec = timeout.inSeconds.clamp(10, 600);
      final args = <String>[
        '-l',
        '-i', iface,
        if (!continuous) ...['-a', 'duration:$durationSec', '-c', '1'],
        '-Y', 'igmp.type == 0x11 and ip.dst == 224.0.0.1',
        '-T', 'fields',
        '-e', 'ip.src',
        '-e', 'igmp.version',
      ];
      proc = await Process.start('tshark', args);

      final controller = StreamController<IgmpPassiveResult>();
      Timer? timeoutTimer;
      if (!continuous) {
        timeoutTimer = Timer(timeout + const Duration(seconds: 2), () {
          proc?.kill();
          if (!controller.isClosed) controller.close();
        });
      }

      final sub = proc.stdout.transform(utf8.decoder).transform(const LineSplitter()).listen(
        (line) {
          final parsed = parseTsharkIgmpOutput(line);
          if (parsed != null && !controller.isClosed) {
            controller.add(parsed);
            if (!continuous) {
              timeoutTimer?.cancel();
              proc?.kill();
              if (!controller.isClosed) controller.close();
            }
          }
        },
        onDone: () {
          timeoutTimer?.cancel();
          if (!controller.isClosed) controller.close();
        },
        onError: (_) {
          timeoutTimer?.cancel();
          if (!controller.isClosed) controller.close();
        },
      );

      yield* controller.stream;
      await sub.cancel();
    } catch (_) {
      proc?.kill();
    } finally {
      proc?.kill();
    }
  }

  /// Parses `tcpdump -nn -e` STP BPDU output.
  /// Example: `12:00:00.000000 aa:bb:cc:dd:ee:01 > 01:80:c2:00:00:00, 802.3, length 60: STP 802.1w, Rapid STP, Flags [Proposal], bridge-id 8000.aa:bb:cc:dd:ee:01.8001, ... root-id 1000.00:11:22:33:44:55`
  static StpPassiveResult? parseTcpdumpStpOutput(String output) {
    String? rootMac;
    int? rootPrio;
    String? srcMac;

    // Try matching "root-id <hexprio>.<mac>" or "root-id <prio>/<mac>"
    final rootIdMatch = RegExp(
      r'root-id\s+([0-9a-fA-F]+)\.([0-9a-fA-F]{2}(?::[0-9a-fA-F]{2}){5})',
      caseSensitive: false,
    ).firstMatch(output);

    if (rootIdMatch != null) {
      rootPrio = int.tryParse(rootIdMatch.group(1)!, radix: 16);
      rootMac = rootIdMatch.group(2)!.toUpperCase();
    }

    // Fallback: match bridge-id if root-id isn't explicitly printed (common on root bridge itself)
    if (rootMac == null) {
      final bridgeMatch = RegExp(
        r'bridge-id\s+([0-9a-fA-F]+)\.([0-9a-fA-F]{2}(?::[0-9a-fA-F]{2}){5})',
        caseSensitive: false,
      ).firstMatch(output);
      if (bridgeMatch != null) {
        rootPrio = int.tryParse(bridgeMatch.group(1)!, radix: 16);
        rootMac = bridgeMatch.group(2)!.toUpperCase();
      }
    }

    // Extract source MAC from Ethernet header: "<src_mac> > 01:80:c2:00:00:00"
    final srcMatch = RegExp(
      r'([0-9a-fA-F]{2}(?::[0-9a-fA-F]{2}){5})\s*>\s*01:80:c2:00:00:00',
      caseSensitive: false,
    ).firstMatch(output);
    if (srcMatch != null) {
      srcMac = srcMatch.group(1)!.toUpperCase();
    }

    if (rootMac == null && srcMac == null) return null;

    return StpPassiveResult(
      rootBridgeMac: rootMac ?? srcMac!,
      rootPriority: rootPrio,
      sourceBridgeMac: srcMac,
    );
  }

  /// Parses `tshark -T fields -e eth.src -e stp.root.hw -e stp.root.prio` output.
  /// Example: `aa:bb:cc:dd:ee:01\t00:11:22:33:44:55\t4096`
  static StpPassiveResult? parseTsharkStpOutput(String output) {
    for (final rawLine in output.split('\n')) {
      final line = rawLine.trim();
      if (line.isEmpty) continue;
      final parts = line.split('\t');
      if (parts.length >= 2) {
        final srcMac = parts[0].trim().toUpperCase();
        final rootMac = parts[1].trim().toUpperCase();
        final prio = parts.length >= 3 ? int.tryParse(parts[2].trim()) : null;
        if (rootMac.isNotEmpty) {
          return StpPassiveResult(
            rootBridgeMac: rootMac,
            rootPriority: prio,
            sourceBridgeMac: srcMac.isNotEmpty ? srcMac : null,
          );
        }
      }
    }
    return null;
  }

  /// Parses `tcpdump -nn -v` IGMP General Query output.
  /// Example: `12:00:01.123456 IP (...) 10.201.100.1 > 224.0.0.1: igmp query v3`
  static IgmpPassiveResult? parseTcpdumpIgmpOutput(String output) {
    final match = RegExp(
      r'(\d{1,3}(?:\.\d{1,3}){3})\s*>\s*224\.0\.0\.1:\s*igmp\s+query(?:\s+(v[23]))?',
      caseSensitive: false,
    ).firstMatch(output);

    if (match != null) {
      final querierIp = match.group(1)!;
      final verRaw = match.group(2)?.toLowerCase();
      final version = verRaw == 'v3' ? 'IGMPv3' : 'IGMPv2';
      return IgmpPassiveResult(querierIp: querierIp, igmpVersion: version);
    }
    return null;
  }

  /// Parses `tshark -T fields -e ip.src -e igmp.version` output.
  /// Example: `10.201.100.1\t3`
  static IgmpPassiveResult? parseTsharkIgmpOutput(String output) {
    for (final rawLine in output.split('\n')) {
      final line = rawLine.trim();
      if (line.isEmpty) continue;
      final parts = line.split('\t');
      final ip = parts[0].trim();
      if (RegExp(r'^\d{1,3}(?:\.\d{1,3}){3}$').hasMatch(ip)) {
        final verNum = parts.length >= 2 ? parts[1].trim() : '2';
        final version = verNum == '3' ? 'IGMPv3' : 'IGMPv2';
        return IgmpPassiveResult(querierIp: ip, igmpVersion: version);
      }
    }
    return null;
  }
}
