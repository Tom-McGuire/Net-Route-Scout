import 'dart:async';
import 'dart:io';
import 'package:network_suite_shared/network_suite_shared.dart';

class ArpService {
  ArpService({ArpCacheParser? parser}) : _parser = parser ?? ArpCacheParser();

  final ArpCacheParser _parser;

  static String normalizeMac(String raw) {
    return ArpCacheParser.normalizeVariableHexMac(raw);
  }

  /// Parses `ip neigh show`, `/proc/net/arp`, `arp -a`, or `arp -an`
  /// into IP -> [ArpCacheEntry] using the consolidated `ArpCacheParser`.
  static Map<String, ArpCacheEntry> parseArpOutput(String rawOutput) {
    return ArpCacheParser.parseToMap(rawOutput);
  }

  /// Queries the operating system ARP cache and returns all IP -> [ArpCacheEntry] mappings.
  Future<Map<String, ArpCacheEntry>> readSystemArpCache() {
    return _parser.readSystemArpMap();
  }

  /// Detects the local host default gateway IPv4 address.
  Future<String?> detectDefaultGateway() async {
    if (Platform.isLinux) {
      try {
        final res = await Process.run('ip', ['route', 'show', 'default']);
        if (res.exitCode == 0) {
          // "default via 10.101.1.1 dev enp1s0 proto dhcp src 10.101.1.100 metric 100"
          final match = RegExp(r'default\s+via\s+(\d{1,3}(?:\.\d{1,3}){3})').firstMatch(res.stdout.toString());
          if (match != null) return match.group(1);
        }
      } catch (_) {}
    } else if (Platform.isWindows) {
      try {
        final res = await Process.run('route', ['print', '0.0.0.0']);
        if (res.exitCode == 0) {
          // "0.0.0.0          0.0.0.0      192.168.1.1     192.168.1.50     25"
          final lines = res.stdout.toString().split(RegExp(r'\r?\n'));
          for (final line in lines) {
            final parts = line.trim().split(RegExp(r'\s+'));
            if (parts.length >= 4 && parts[0] == '0.0.0.0' && parts[1] == '0.0.0.0') {
              return parts[2];
            }
          }
        }
      } catch (_) {}
    } else if (Platform.isMacOS) {
      try {
        final res = await Process.run('route', ['-n', 'get', 'default']);
        if (res.exitCode == 0) {
          final match = RegExp(r'gateway:\s*(\d{1,3}(?:\.\d{1,3}){3})').firstMatch(res.stdout.toString());
          if (match != null) return match.group(1);
        }
      } catch (_) {}
    }
    return null;
  }

  /// Detects the primary local IPv4 address of this machine.
  Future<String> detectLocalHostIp() async {
    try {
      final interfaces = await NetworkInterface.list(
        includeLoopback: false,
        type: InternetAddressType.IPv4,
      );
      for (final iface in interfaces) {
        for (final addr in iface.addresses) {
          if (!addr.isLoopback && !addr.isLinkLocal && addr.type == InternetAddressType.IPv4) {
            return addr.address;
          }
        }
      }
    } catch (_) {}
    return '127.0.0.1';
  }

  /// Performs asynchronous reverse DNS lookup on [ip].
  Future<String?> reverseDns(String ip, {Duration timeout = const Duration(milliseconds: 1500)}) async {
    try {
      final addr = InternetAddress(ip);
      final rev = await addr.reverse().timeout(timeout);
      if (rev.host.isNotEmpty && rev.host != ip) {
        return rev.host;
      }
    } catch (_) {}
    return null;
  }
}
