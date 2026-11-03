import 'dart:convert';
import 'dart:io';
import 'package:network_suite_shared/network_suite_shared.dart';
import '../../domain/models/network_adapter_info.dart';

class NetworkAdapterService {
  /// Discovers all available IPv4 network adapters with their IP, MAC, Subnet CIDR, and Gateway.
  static Future<List<NetworkAdapterInfo>> getAvailableAdapters() async {
    final adapters = <NetworkAdapterInfo>[];

    try {
      if (Platform.isWindows) {
        final winAdapters = await _discoverWindowsAdapters();
        if (winAdapters.isNotEmpty) {
          adapters.addAll(winAdapters);
        }
      } else if (Platform.isLinux) {
        final linuxAdapters = await _discoverLinuxAdapters();
        if (linuxAdapters.isNotEmpty) {
          adapters.addAll(linuxAdapters);
        }
      } else if (Platform.isMacOS) {
        final macAdapters = await _discoverMacAdapters();
        if (macAdapters.isNotEmpty) {
          adapters.addAll(macAdapters);
        }
      }
    } catch (_) {}

    // Fallback using Dart NetworkInterface if OS-specific command failed or returned empty
    if (adapters.isEmpty) {
      final fallbackAdapters = await _discoverDartFallbackAdapters();
      adapters.addAll(fallbackAdapters);
    }

    return adapters;
  }

  /// Linux discovery using `/sys/class/net`, `ip route`, and `ip addr`
  static Future<List<NetworkAdapterInfo>> _discoverLinuxAdapters() async {
    final list = <NetworkAdapterInfo>[];
    String? defaultGw;

    try {
      final gwRes = await Process.run('ip', ['route', 'show', 'default']);
      if (gwRes.exitCode == 0) {
        final match = RegExp(r'default\s+via\s+(\d{1,3}(?:\.\d{1,3}){3})').firstMatch(gwRes.stdout.toString());
        if (match != null) defaultGw = match.group(1);
      }
    } catch (_) {}

    final interfaces = await NetworkInterface.list(
      includeLoopback: false,
      type: InternetAddressType.IPv4,
    );

    for (final iface in interfaces) {
      for (final addr in iface.addresses) {
        if (addr.isLoopback || addr.address.startsWith('169.254.')) continue;

        String? mac;
        final macFile = File('/sys/class/net/${iface.name}/address');
        if (macFile.existsSync()) {
          try {
            final raw = macFile.readAsStringSync().trim();
            if (raw.isNotEmpty && raw != '00:00:00:00:00:00') {
              mac = NetworkAdapterInfo.normalizeMac(raw);
            }
          } catch (_) {}
        }

        int prefix = 24;
        try {
          final addrRes = await Process.run('ip', ['-o', '-4', 'addr', 'show', 'dev', iface.name]);
          if (addrRes.exitCode == 0) {
            final match = RegExp(r'inet\s+(\d{1,3}(?:\.\d{1,3}){3})/(\d{1,2})').firstMatch(addrRes.stdout.toString());
            if (match != null) {
              prefix = int.tryParse(match.group(2)!) ?? 24;
            }
          }
        } catch (_) {}

        final cidr = NetworkAdapterInfo.calculateSubnetCidr(addr.address, prefix);
        final vendor = mac != null ? OuiLookup.lookupVendor(mac) : null;

        list.add(
          NetworkAdapterInfo(
            id: iface.name,
            name: iface.name,
            ipAddress: addr.address,
            macAddress: mac,
            vendor: vendor != 'Unknown Vendor' ? vendor : null,
            subnetCidr: cidr,
            prefixLength: prefix,
            gatewayIp: defaultGw,
          ),
        );
      }
    }

    return list;
  }

  /// Windows discovery using PowerShell Get-NetIPAddress + Get-NetAdapter, with fallback to ipconfig
  static Future<List<NetworkAdapterInfo>> _discoverWindowsAdapters() async {
    final list = <NetworkAdapterInfo>[];

    try {
      const psScript = r'''
$ips = Get-NetIPAddress -AddressFamily IPv4 -ErrorAction SilentlyContinue | Where-Object { $_.IPAddress -notlike "127.*" -and $_.IPAddress -notlike "169.254.*" }
$nics = Get-NetAdapter -ErrorAction SilentlyContinue | Group-Object -Property ifIndex -AsHashTable
$routes = Get-NetRoute -DestinationPrefix "0.0.0.0/0" -ErrorAction SilentlyContinue | Group-Object -Property InterfaceIndex -AsHashTable
$out = foreach ($ip in $ips) {
  $nic = if ($nics) { $nics[$ip.InterfaceIndex] | Select-Object -First 1 } else { $null }
  $gw = if ($routes -and $routes[$ip.InterfaceIndex]) { $routes[$ip.InterfaceIndex][0].NextHop } else { $null }
  [PSCustomObject]@{
    Name = if ($nic) { [string]$nic.Name } else { [string]$ip.InterfaceAlias }
    IP = [string]$ip.IPAddress
    Prefix = [int]$ip.PrefixLength
    Mac = if ($nic -and $nic.MacAddress) { ([string]$nic.MacAddress).Replace('-', ':').ToUpper() } else { $null }
    Gateway = [string]$gw
  }
}
$out | ConvertTo-Json -Compress
''';
      final res = await Process.run('powershell.exe', ['-NoProfile', '-NonInteractive', '-Command', psScript]);
      if (res.exitCode == 0 && res.stdout.toString().trim().isNotEmpty) {
        final decoded = jsonDecode(res.stdout.toString().trim());
        final items = decoded is List ? decoded : [decoded];

        for (final item in items) {
          if (item is! Map) continue;
          final name = item['Name']?.toString() ?? 'Network Adapter';
          final ip = item['IP']?.toString();
          if (ip == null || ip.isEmpty || ip.startsWith('127.') || ip.startsWith('169.254.')) continue;

          final prefix = (item['Prefix'] is int) ? item['Prefix'] as int : (int.tryParse(item['Prefix']?.toString() ?? '') ?? 24);
          final rawMac = item['Mac']?.toString();
          final mac = NetworkAdapterInfo.normalizeMac(rawMac);
          final gw = item['Gateway']?.toString();
          final cidr = NetworkAdapterInfo.calculateSubnetCidr(ip, prefix);
          final vendor = mac != null ? OuiLookup.lookupVendor(mac) : null;

          list.add(
            NetworkAdapterInfo(
              id: name,
              name: name,
              ipAddress: ip,
              macAddress: mac,
              vendor: vendor != 'Unknown Vendor' ? vendor : null,
              subnetCidr: cidr,
              prefixLength: prefix,
              gatewayIp: (gw != null && gw.isNotEmpty && gw != '0.0.0.0') ? gw : null,
            ),
          );
        }
      }
    } catch (_) {}

    if (list.isNotEmpty) return list;

    // Fallback to ipconfig /all on Windows
    try {
      final res = await Process.run('ipconfig.exe', ['/all']);
      if (res.exitCode == 0) {
        final parsed = _parseWindowsIpconfig(res.stdout.toString());
        if (parsed.isNotEmpty) return parsed;
      }
    } catch (_) {}

    return list;
  }

  static List<NetworkAdapterInfo> _parseWindowsIpconfig(String output) {
    final list = <NetworkAdapterInfo>[];
    String? currentName;
    String? currentMac;
    String? currentIp;
    String? currentMask;
    String? currentGw;

    void flush() {
      final name = currentName;
      final ip = currentIp;
      final gw = currentGw;
      final mac = currentMac;
      if (name != null && ip != null && !ip.startsWith('127.') && !ip.startsWith('169.254.')) {
        final prefix = _maskToPrefix(currentMask ?? '255.255.255.0');
        final cidr = NetworkAdapterInfo.calculateSubnetCidr(ip, prefix);
        final vendor = mac != null ? OuiLookup.lookupVendor(mac) : null;

        list.add(
          NetworkAdapterInfo(
            id: name,
            name: name,
            ipAddress: ip,
            macAddress: mac,
            vendor: vendor != 'Unknown Vendor' ? vendor : null,
            subnetCidr: cidr,
            prefixLength: prefix,
            gatewayIp: (gw != null && gw.isNotEmpty && gw != '0.0.0.0') ? gw : null,
          ),
        );
      }
    }

    final lines = output.split(RegExp(r'\r?\n'));
    for (final line in lines) {
      final trimmed = line.trim();
      if (!line.startsWith(' ') && line.contains('adapter ')) {
        flush();
        currentName = line.split('adapter ').last.replaceAll(':', '').trim();
        currentMac = null;
        currentIp = null;
        currentMask = null;
        currentGw = null;
        continue;
      }

      if (trimmed.startsWith('Physical Address') || trimmed.contains('Physikalische Adresse')) {
        final parts = trimmed.split(':');
        if (parts.length >= 2) {
          currentMac = NetworkAdapterInfo.normalizeMac(parts.sublist(1).join(':').trim());
        }
      } else if (trimmed.startsWith('IPv4 Address') || trimmed.contains('IPv4-Adresse')) {
        final match = RegExp(r'(\d{1,3}(?:\.\d{1,3}){3})').firstMatch(trimmed);
        if (match != null) currentIp = match.group(1);
      } else if (trimmed.startsWith('Subnet Mask') || trimmed.contains('Subnetzmaske')) {
        final match = RegExp(r'(\d{1,3}(?:\.\d{1,3}){3})').firstMatch(trimmed);
        if (match != null) currentMask = match.group(1);
      } else if (trimmed.startsWith('Default Gateway') || trimmed.contains('Standardgateway')) {
        final match = RegExp(r'(\d{1,3}(?:\.\d{1,3}){3})').firstMatch(trimmed);
        if (match != null) currentGw = match.group(1);
      }
    }
    flush();
    return list;
  }

  static int _maskToPrefix(String mask) {
    try {
      final parts = mask.split('.').map(int.parse).toList();
      var count = 0;
      for (final p in parts) {
        var n = p;
        while (n > 0) {
          if ((n & 1) == 1) count++;
          n >>= 1;
        }
      }
      return count > 0 ? count : 24;
    } catch (_) {
      return 24;
    }
  }

  /// macOS discovery
  static Future<List<NetworkAdapterInfo>> _discoverMacAdapters() async {
    final list = <NetworkAdapterInfo>[];
    String? defaultGw;

    try {
      final gwRes = await Process.run('route', ['-n', 'get', 'default']);
      if (gwRes.exitCode == 0) {
        final match = RegExp(r'gateway:\s*(\d{1,3}(?:\.\d{1,3}){3})').firstMatch(gwRes.stdout.toString());
        if (match != null) defaultGw = match.group(1);
      }
    } catch (_) {}

    final interfaces = await NetworkInterface.list(
      includeLoopback: false,
      type: InternetAddressType.IPv4,
    );

    for (final iface in interfaces) {
      for (final addr in iface.addresses) {
        if (addr.isLoopback || addr.address.startsWith('169.254.')) continue;

        String? mac;
        try {
          final res = await Process.run('ifconfig', [iface.name]);
          if (res.exitCode == 0) {
            final match = RegExp(r'ether\s+([0-9a-fA-F:]{17})').firstMatch(res.stdout.toString());
            if (match != null) {
              mac = NetworkAdapterInfo.normalizeMac(match.group(1)!);
            }
          }
        } catch (_) {}

        final cidr = NetworkAdapterInfo.calculateSubnetCidr(addr.address, 24);
        final vendor = mac != null ? OuiLookup.lookupVendor(mac) : null;

        list.add(
          NetworkAdapterInfo(
            id: iface.name,
            name: iface.name,
            ipAddress: addr.address,
            macAddress: mac,
            vendor: vendor != 'Unknown Vendor' ? vendor : null,
            subnetCidr: cidr,
            prefixLength: 24,
            gatewayIp: defaultGw,
          ),
        );
      }
    }

    return list;
  }

  /// Dart fallback adapters
  static Future<List<NetworkAdapterInfo>> _discoverDartFallbackAdapters() async {
    final list = <NetworkAdapterInfo>[];
    try {
      final interfaces = await NetworkInterface.list(
        includeLoopback: false,
        type: InternetAddressType.IPv4,
      );
      for (final iface in interfaces) {
        for (final addr in iface.addresses) {
          if (!addr.isLoopback && !addr.address.startsWith('169.254.')) {
            list.add(
              NetworkAdapterInfo(
                id: iface.name,
                name: iface.name,
                ipAddress: addr.address,
                subnetCidr: NetworkAdapterInfo.calculateSubnetCidr(addr.address, 24),
              ),
            );
          }
        }
      }
    } catch (_) {}
    return list;
  }
}
