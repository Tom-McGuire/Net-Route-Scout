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
    String? defaultDev;

    try {
      final gwRes = await Process.run('ip', ['route', 'show', 'default']);
      if (gwRes.exitCode == 0) {
        final parsedRoute = parseLinuxDefaultRoute(gwRes.stdout.toString());
        defaultGw = parsedRoute.gateway;
        defaultDev = parsedRoute.device;
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
            prefix = parseLinuxAddrPrefix(addrRes.stdout.toString(), addr.address);
          }
        } catch (_) {}

        final cidr = NetworkAdapterInfo.calculateSubnetCidr(addr.address, prefix);
        final vendor = mac != null ? OuiLookup.lookupVendor(mac) : null;
        final isDefaultAdapter = defaultDev == null || iface.name == defaultDev;

        list.add(
          NetworkAdapterInfo(
            id: iface.name,
            name: iface.name,
            ipAddress: addr.address,
            macAddress: mac,
            vendor: vendor != 'Unknown Vendor' ? vendor : null,
            subnetCidr: cidr,
            prefixLength: prefix,
            gatewayIp: isDefaultAdapter ? defaultGw : null,
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
        final parsed = parseWindowsIpconfig(res.stdout.toString());
        if (parsed.isNotEmpty) return parsed;
      }
    } catch (_) {}

    return list;
  }

  /// Parses Windows `ipconfig /all` console output.
  static List<NetworkAdapterInfo> parseWindowsIpconfig(String output) {
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
        final prefix = maskToPrefix(currentMask ?? '255.255.255.0');
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
      final lower = line.toLowerCase();
      if (!line.startsWith(' ') && (lower.contains('adapter') || lower.contains('adaptador') || lower.contains('carte')) && line.contains(':')) {
        flush();
        final match = RegExp(r'(?:adapter|adaptador|carte)\s+(.+)', caseSensitive: false).firstMatch(line);
        currentName = match != null ? match.group(1)!.replaceAll(':', '').trim() : line.replaceAll(':', '').trim();
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

  /// Converts dotted-decimal subnet mask (e.g. 255.255.255.0) to CIDR prefix length (e.g. 24).
  static int maskToPrefix(String mask) {
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

  /// Extracts default gateway and interface device from Linux `ip route show default` output.
  static ({String? gateway, String? device}) parseLinuxDefaultRoute(String output) {
    final match = RegExp(r'default\s+via\s+(\d{1,3}(?:\.\d{1,3}){3})(?:\s+dev\s+([^\s]+))?').firstMatch(output);
    if (match != null) {
      return (gateway: match.group(1), device: match.group(2));
    }
    return (gateway: null, device: null);
  }

  /// Extracts CIDR prefix from Linux `ip -o -4 addr show` output for a specific IP.
  static int parseLinuxAddrPrefix(String output, String ipAddress) {
    final match = RegExp('inet\\s+${RegExp.escape(ipAddress)}/(\\d{1,2})').firstMatch(output);
    if (match != null) {
      return int.tryParse(match.group(1)!) ?? 24;
    }
    final anyMatch = RegExp(r'inet\s+\d{1,3}(?:\.\d{1,3}){3}/(\d{1,2})').firstMatch(output);
    if (anyMatch != null) return int.tryParse(anyMatch.group(1)!) ?? 24;
    return 24;
  }

  /// Extracts default gateway and interface device from macOS `route -n get default` output.
  static ({String? gateway, String? device}) parseMacDefaultRoute(String output) {
    String? defaultGw;
    String? defaultDev;
    final gwMatch = RegExp(r'gateway:\s*(\d{1,3}(?:\.\d{1,3}){3})').firstMatch(output);
    if (gwMatch != null) defaultGw = gwMatch.group(1);
    final devMatch = RegExp(r'interface:\s*([^\s]+)').firstMatch(output);
    if (devMatch != null) defaultDev = devMatch.group(1);
    return (gateway: defaultGw, device: defaultDev);
  }

  /// Extracts MAC address and subnet prefix from macOS `ifconfig <interface>` output.
  static ({String? mac, int prefix}) parseMacIfconfig(String output, String ipAddress) {
    String? mac;
    int prefix = 24;
    final match = RegExp(r'ether\s+([0-9a-fA-F:]{17})').firstMatch(output);
    if (match != null) {
      mac = NetworkAdapterInfo.normalizeMac(match.group(1)!);
    }
    final maskMatch = RegExp('inet\\s+${RegExp.escape(ipAddress)}\\s+netmask\\s+0x([0-9a-fA-F]{8})').firstMatch(output);
    if (maskMatch != null) {
      final hex = int.tryParse(maskMatch.group(1)!, radix: 16);
      if (hex != null) {
        var count = 0;
        var n = hex;
        while (n > 0) {
          if ((n & 1) == 1) count++;
          n >>= 1;
        }
        if (count > 0 && count <= 32) prefix = count;
      }
    }
    return (mac: mac, prefix: prefix);
  }

  /// macOS discovery
  static Future<List<NetworkAdapterInfo>> _discoverMacAdapters() async {
    final list = <NetworkAdapterInfo>[];
    String? defaultGw;
    String? defaultDev;

    try {
      final gwRes = await Process.run('route', ['-n', 'get', 'default']);
      if (gwRes.exitCode == 0) {
        final parsed = parseMacDefaultRoute(gwRes.stdout.toString());
        defaultGw = parsed.gateway;
        defaultDev = parsed.device;
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
        int prefix = 24;
        try {
          final res = await Process.run('ifconfig', [iface.name]);
          if (res.exitCode == 0) {
            final parsed = parseMacIfconfig(res.stdout.toString(), addr.address);
            mac = parsed.mac;
            prefix = parsed.prefix;
          }
        } catch (_) {}

        final cidr = NetworkAdapterInfo.calculateSubnetCidr(addr.address, prefix);
        final vendor = mac != null ? OuiLookup.lookupVendor(mac) : null;
        final isDefaultAdapter = defaultDev == null || iface.name == defaultDev;

        list.add(
          NetworkAdapterInfo(
            id: iface.name,
            name: iface.name,
            ipAddress: addr.address,
            macAddress: mac,
            vendor: vendor != 'Unknown Vendor' ? vendor : null,
            subnetCidr: cidr,
            prefixLength: prefix,
            gatewayIp: isDefaultAdapter ? defaultGw : null,
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
