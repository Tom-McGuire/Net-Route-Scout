import 'dart:async';
import 'dart:io';
import 'package:network_suite_shared/network_suite_shared.dart';

class ArpDeviceEntry {
  final String ip;
  final String macAddress;
  final String vendor;
  final String? interfaceName;

  const ArpDeviceEntry({
    required this.ip,
    required this.macAddress,
    required this.vendor,
    this.interfaceName,
  });
}

class ArpService {
  static String normalizeMac(String raw) {
    return SharedDevice.normalizeMac(raw);
  }

  /// Parses `ip neigh show` (Linux) or `arp -a` (Windows/macOS) into IP -> ArpDeviceEntry.
  static Map<String, ArpDeviceEntry> parseArpOutput(String rawOutput) {
    final results = <String, ArpDeviceEntry>{};
    final lines = rawOutput.split(RegExp(r'\r?\n'));

    // 1. Linux `ip neigh show` format:
    // 10.101.1.1 dev enp1s0 lladdr 24:e5:0f:31:4b:73 REACHABLE
    final ipNeighRegex = RegExp(
      r'^\s*(\d{1,3}(?:\.\d{1,3}){3})\s+(?:dev\s+(\S+)\s+)?lladdr\s+([0-9a-fA-F]{2}(?::[0-9a-fA-F]{2}){5})',
      caseSensitive: false,
    );

    // 2. Windows `arp -a` format:
    // 192.168.1.1       00-1b-54-11-22-33     dynamic
    final winArpRegex = RegExp(
      r'^\s*(\d{1,3}(?:\.\d{1,3}){3})\s+([0-9a-fA-F]{2}(?:[:-][0-9a-fA-F]{2}){5})\s+(\S+)',
    );

    // 3. macOS / BSD `arp -an` format:
    // ? (192.168.1.1) at 00:1b:54:11:22:33 on en0 ifscope [ethernet]
    final bsdArpRegex = RegExp(
      r'\((?:[a-zA-Z0-9.-]+\s+)?(\d{1,3}(?:\.\d{1,3}){3})\)\s+at\s+([0-9a-fA-F]{1,2}(?::[0-9a-fA-F]{1,2}){5})\s+.*?on\s+(\S+)',
      caseSensitive: false,
    );

    for (final line in lines) {
      final trimmed = line.trim();
      if (trimmed.isEmpty) continue;

      final neighMatch = ipNeighRegex.firstMatch(trimmed);
      if (neighMatch != null) {
        final ip = neighMatch.group(1)!;
        final dev = neighMatch.group(2);
        final rawMac = neighMatch.group(3)!;
        final mac = normalizeMac(rawMac);
        if (_isUsableMac(mac)) {
          results[ip] = ArpDeviceEntry(
            ip: ip,
            macAddress: mac,
            vendor: OuiLookup.lookupVendor(mac),
            interfaceName: dev,
          );
        }
        continue;
      }

      final winMatch = winArpRegex.firstMatch(trimmed);
      if (winMatch != null) {
        final ip = winMatch.group(1)!;
        final rawMac = winMatch.group(2)!;
        final mac = normalizeMac(rawMac);
        if (_isUsableMac(mac)) {
          results[ip] = ArpDeviceEntry(
            ip: ip,
            macAddress: mac,
            vendor: OuiLookup.lookupVendor(mac),
          );
        }
        continue;
      }

      final bsdMatch = bsdArpRegex.firstMatch(trimmed);
      if (bsdMatch != null) {
        final ip = bsdMatch.group(1)!;
        final rawMac = bsdMatch.group(2)!;
        final dev = bsdMatch.group(3);
        final mac = normalizeMac(rawMac);
        if (_isUsableMac(mac)) {
          results[ip] = ArpDeviceEntry(
            ip: ip,
            macAddress: mac,
            vendor: OuiLookup.lookupVendor(mac),
            interfaceName: dev,
          );
        }
      }
    }

    return results;
  }

  static bool _isUsableMac(String mac) {
    if (mac == 'FF:FF:FF:FF:FF:FF' || mac == '00:00:00:00:00:00') return false;
    if (mac.startsWith('01:00:5E')) return false; // IPv4 multicast
    if (mac.startsWith('33:33:')) return false; // IPv6 multicast
    return true;
  }

  /// Queries the operating system ARP cache and returns all IP -> ArpDeviceEntry mappings.
  Future<Map<String, ArpDeviceEntry>> readSystemArpCache() async {
    if (Platform.isLinux) {
      try {
        final ipRes = await Process.run('ip', ['neigh', 'show']);
        if (ipRes.exitCode == 0) {
          final entries = parseArpOutput(ipRes.stdout.toString());
          if (entries.isNotEmpty) return entries;
        }
      } catch (_) {}
    }

    try {
      final bin = Platform.isWindows ? 'arp.exe' : 'arp';
      final args = Platform.isWindows ? ['-a'] : ['-an'];
      final res = await Process.run(bin, args);
      if (res.exitCode == 0) {
        return parseArpOutput(res.stdout.toString());
      }
    } catch (_) {}

    return const {};
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
  Future<String?> reverseDns(String ip, {Duration timeout = const Duration(milliseconds: 180)}) async {
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
