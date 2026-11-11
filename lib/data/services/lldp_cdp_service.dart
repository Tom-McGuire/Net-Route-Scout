import 'dart:convert';
import 'dart:io';
import '../../domain/models/switch_discovery_info.dart';

class LldpCdpService {
  /// Attempts to discover the upstream physical switch connected to [interfaceName].
  /// Uses system LLDP agents where available, falling back to passive capture.
  static Future<LldpDiscoveryResult?> discoverLocalUpstreamSwitch({
    String? interfaceName,
    Duration timeout = const Duration(seconds: 15),
  }) async {
    if (Platform.isLinux) {
      // 1. Try lldpctl
      final lldpctlResult = await _queryLldpctl(interfaceName);
      if (lldpctlResult != null) return lldpctlResult;

      // 2. Fallback to short passive tcpdump if interface is known
      if (interfaceName != null && interfaceName.isNotEmpty) {
        final captureResult = await _captureLldpTcpdump(interfaceName, timeout);
        if (captureResult != null) return captureResult;
      }
    } else if (Platform.isWindows) {
      final winResult = await _queryWindowsLldp(interfaceName);
      if (winResult != null) return winResult;
    }

    return null;
  }

  static Future<LldpDiscoveryResult?> _queryLldpctl(String? iface) async {
    try {
      final args = ['-f', 'json'];
      if (iface != null && iface.isNotEmpty) {
        args.add(iface);
      }
      final res = await Process.run('lldpctl', args).timeout(const Duration(seconds: 2));
      if (res.exitCode == 0 && res.stdout.toString().trim().isNotEmpty) {
        final data = jsonDecode(res.stdout.toString());
        if (data is Map && data.containsKey('lldp')) {
          final lldp = data['lldp'];
          if (lldp is Map && lldp.containsKey('interface')) {
            final ifaces = lldp['interface'];
            Map? targetIface;
            if (ifaces is Map) {
              targetIface = ifaces.values.firstOrNull as Map?;
            } else if (ifaces is List && ifaces.isNotEmpty) {
              targetIface = ifaces.first as Map?;
            }

            if (targetIface != null && targetIface.containsKey('chassis')) {
              final chassis = targetIface['chassis'] as Map? ?? {};
              final port = targetIface['port'] as Map? ?? {};

              final chassisId = chassis.values.firstOrNull?['id']?.toString() ?? 'Unknown Chassis';
              final sysName = chassis.values.firstOrNull?['name']?.toString() ?? 'Managed Switch';
              final portId = port.values.firstOrNull?['id']?.toString() ?? 'Port 1';
              final portDescr = port.values.firstOrNull?['descr']?.toString();
              final mgmtIp = chassis.values.firstOrNull?['mgmt-ip']?.toString();

              return LldpDiscoveryResult(
                chassisId: chassisId,
                sysName: sysName,
                portId: portId,
                portDescr: portDescr,
                mgmtAddress: mgmtIp,
                capabilities: ['Bridge'],
              );
            }
          }
        }
      }
    } catch (_) {}
    return null;
  }

  static Future<LldpDiscoveryResult?> _captureLldpTcpdump(String iface, Duration timeout) async {
    try {
      final proc = await Process.start('tcpdump', [
        '-c', '1',
        '-i', iface,
        '-nn', '-v',
        '-s', '1500',
        'ether proto 0x88cc or ether[20:2] == 0x2000',
      ]);

      final lines = <String>[];
      final lineStream = proc.stdout.transform(utf8.decoder).transform(const LineSplitter());

      final sub = lineStream.listen((line) => lines.add(line));
      final exitCode = await proc.exitCode.timeout(timeout, onTimeout: () {
        proc.kill();
        return -1;
      });
      await sub.cancel();

      if (exitCode == 0 && lines.isNotEmpty) {
        String sysName = 'Upstream Switch';
        String portId = 'Port 1';
        String chassisId = '00:00:00:00:00:00';
        String? mgmtIp;

        for (final line in lines) {
          final trimmed = line.trim();
          if (trimmed.contains('System Name TLV') || trimmed.contains('Device ID')) {
            final parts = trimmed.split(':');
            if (parts.length > 1) sysName = parts.sublist(1).join(':').trim();
          } else if (trimmed.contains('Port Description TLV') || trimmed.contains('Port ID TLV')) {
            final parts = trimmed.split(':');
            if (parts.length > 1) portId = parts.sublist(1).join(':').trim();
          } else if (trimmed.contains('Chassis ID TLV')) {
            final parts = trimmed.split(':');
            if (parts.length > 1) chassisId = parts.sublist(1).join(':').trim();
          } else if (trimmed.contains('Management Address')) {
            final parts = trimmed.split(':');
            if (parts.length > 1) mgmtIp = parts.sublist(1).join(':').trim();
          }
        }

        return LldpDiscoveryResult(
          chassisId: chassisId,
          sysName: sysName,
          portId: portId,
          mgmtAddress: mgmtIp,
          capabilities: ['Bridge'],
        );
      }
    } catch (_) {}
    return null;
  }

  static Future<LldpDiscoveryResult?> _queryWindowsLldp(String? iface) async {
    try {
      final cmd = 'Get-NetLldpAgent | Select-Object -First 1 ChassisId,SysName,PortId,PortDescription | ConvertTo-Json';
      final res = await Process.run('powershell', ['-Command', cmd]).timeout(const Duration(seconds: 3));
      if (res.exitCode == 0 && res.stdout.toString().trim().isNotEmpty) {
        final data = jsonDecode(res.stdout.toString());
        if (data is Map) {
          return LldpDiscoveryResult(
            chassisId: data['ChassisId']?.toString() ?? 'Chassis',
            sysName: data['SysName']?.toString() ?? 'Managed Switch',
            portId: data['PortId']?.toString() ?? 'Port',
            portDescr: data['PortDescription']?.toString(),
            capabilities: ['Bridge'],
          );
        }
      }
    } catch (_) {}
    return null;
  }
}
