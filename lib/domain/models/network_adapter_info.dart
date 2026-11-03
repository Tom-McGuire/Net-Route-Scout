import 'package:network_suite_shared/network_suite_shared.dart';

class NetworkAdapterInfo {
  final String id;
  final String name;
  final String ipAddress;
  final String? macAddress;
  final String? vendor;
  final String subnetCidr;
  final int prefixLength;
  final String? gatewayIp;
  final bool isUp;

  const NetworkAdapterInfo({
    required this.id,
    required this.name,
    required this.ipAddress,
    this.macAddress,
    this.vendor,
    required this.subnetCidr,
    this.prefixLength = 24,
    this.gatewayIp,
    this.isUp = true,
  });

  String get displayName {
    final macPart = macAddress != null && macAddress!.isNotEmpty ? ' • $macAddress' : '';
    return '$name ($ipAddress$macPart)';
  }

  String get shortDisplayName {
    return '$name: $ipAddress';
  }

  bool get isLoopback =>
      ipAddress.startsWith('127.') ||
      name.toLowerCase().contains('loopback') ||
      name.toLowerCase() == 'lo';

  static String calculateSubnetCidr(String ip, int prefix) {
    try {
      final parts = ip.trim().split('.');
      if (parts.length != 4) return '192.168.1.0/24';
      final ipNum = (int.parse(parts[0]) << 24) |
          (int.parse(parts[1]) << 16) |
          (int.parse(parts[2]) << 8) |
          int.parse(parts[3]);

      final clampedPrefix = prefix.clamp(8, 30);
      final hostBits = 32 - clampedPrefix;
      final mask = (0xFFFFFFFF << hostBits) & 0xFFFFFFFF;
      final netNum = ipNum & mask;

      final netIp =
          '${(netNum >> 24) & 0xFF}.${(netNum >> 16) & 0xFF}.${(netNum >> 8) & 0xFF}.${netNum & 0xFF}';
      return '$netIp/$clampedPrefix';
    } catch (_) {
      final parts = ip.trim().split('.');
      if (parts.length == 4) {
        return '${parts[0]}.${parts[1]}.${parts[2]}.0/24';
      }
      return '192.168.1.0/24';
    }
  }

  static String? normalizeMac(String? raw) {
    if (raw == null || raw.trim().isEmpty) return null;
    try {
      return SharedDevice.normalizeMac(raw);
    } catch (_) {
      return raw.toUpperCase().replaceAll('-', ':');
    }
  }

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is NetworkAdapterInfo &&
          runtimeType == other.runtimeType &&
          id == other.id &&
          ipAddress == other.ipAddress;

  @override
  int get hashCode => Object.hash(id, ipAddress);
}
