import 'dart:io';
import 'package:dart_snmp/dart_snmp.dart';
import '../../domain/models/switch_discovery_info.dart';

class SnmpSwitchService {
  static const Duration defaultTimeout = Duration(seconds: 4);

  /// Probes and queries a switch via SNMP v2c (or v1) to retrieve system info,
  /// bridge forwarding database (MAC -> Port), and LLDP neighbor links.
  static Future<SwitchDiscoveryResult> discoverSwitchTopology({
    required String targetIp,
    String community = 'public',
    int port = 161,
    SnmpVersion version = SnmpVersion.v2c,
  }) async {
    final target = InternetAddress(targetIp);
    final session = await Snmp.createSession(
      target,
      community: community,
      port: port,
      version: version,
      retries: 1,
    );

    String sysName = targetIp;
    String? sysDescr;
    final ports = <int, SwitchPortEntry>{};
    final ifIndexToPort = <int, int>{};
    final ifIndexToName = <int, String>{};
    final neighbors = <SwitchNeighborLink>[];

    try {
      // 1. System info: sysName.0 (1.3.6.1.2.1.1.5.0) and sysDescr.0 (1.3.6.1.2.1.1.1.0)
      try {
        final sysNameMsg = await session.get(Oid.fromString('1.3.6.1.2.1.1.5.0'));
        if (sysNameMsg.pdu.varbinds.isNotEmpty) {
          final val = sysNameMsg.pdu.varbinds.first.value.toString().trim();
          if (val.isNotEmpty) sysName = val;
        }
      } catch (_) {}

      try {
        final sysDescrMsg = await session.get(Oid.fromString('1.3.6.1.2.1.1.1.0'));
        if (sysDescrMsg.pdu.varbinds.isNotEmpty) {
          final val = sysDescrMsg.pdu.varbinds.first.value.toString().trim();
          if (val.isNotEmpty) sysDescr = val;
        }
      } catch (_) {}

      // 2. Map dot1dBasePort to ifIndex (1.3.6.1.2.1.17.1.4.1.2)
      try {
        final basePortStream = session.walk(oid: Oid.fromString('1.3.6.1.2.1.17.1.4.1.2'));
        await for (final msg in basePortStream) {
          for (final vb in msg.pdu.varbinds) {
            final oidStr = vb.oid.toString();
            final portNum = int.tryParse(oidStr.split('.').last);
            final ifIdx = int.tryParse(vb.value.toString());
            if (portNum != null && ifIdx != null) {
              ifIndexToPort[ifIdx] = portNum;
              ports[portNum] = SwitchPortEntry(
                portNumber: portNum,
                ifIndex: ifIdx,
                portName: 'Port $portNum',
              );
            }
          }
        }
      } catch (_) {}

      // 3. Interface names / descriptions (1.3.6.1.2.1.31.1.1.1.1 for ifName)
      try {
        final ifNameStream = session.walk(oid: Oid.fromString('1.3.6.1.2.1.31.1.1.1.1'));
        await for (final msg in ifNameStream) {
          for (final vb in msg.pdu.varbinds) {
            final ifIdx = int.tryParse(vb.oid.toString().split('.').last);
            final name = vb.value.toString().trim();
            if (ifIdx != null && name.isNotEmpty) {
              ifIndexToName[ifIdx] = name;
              final portNum = ifIndexToPort[ifIdx];
              if (portNum != null && ports.containsKey(portNum)) {
                ports[portNum] = SwitchPortEntry(
                  portNumber: portNum,
                  ifIndex: ifIdx,
                  portName: name,
                  connectedMacs: ports[portNum]?.connectedMacs,
                );
              }
            }
          }
        }
      } catch (_) {}

      // 4. Forwarding Database (FDB): dot1dTpFdbPort (1.3.6.1.2.1.17.4.3.1.2)
      // OID: 1.3.6.1.2.1.17.4.3.1.2.m1.m2.m3.m4.m5.m6 = <dot1dBasePort>
      try {
        final fdbStream = session.walk(oid: Oid.fromString('1.3.6.1.2.1.17.4.3.1.2'));
        await for (final msg in fdbStream) {
          for (final vb in msg.pdu.varbinds) {
            final parts = vb.oid.toString().split('.');
            if (parts.length >= 6) {
              final macBytes = parts.sublist(parts.length - 6).map((s) => int.tryParse(s) ?? 0).toList();
              final macStr = macBytes.map((b) => b.toRadixString(16).padLeft(2, '0').toUpperCase()).join(':');
              final portNum = int.tryParse(vb.value.toString());

              if (portNum != null && portNum > 0) {
                if (!ports.containsKey(portNum)) {
                  ports[portNum] = SwitchPortEntry(
                    portNumber: portNum,
                    portName: 'Port $portNum',
                  );
                }
                ports[portNum]!.connectedMacs.add(macStr);
              }
            }
          }
        }
      } catch (_) {}

      // 5. LLDP-MIB Remote Neighbors: lldpRemSysName (1.0.8802.1.1.2.1.4.1.1.9)
      try {
        final lldpStream = session.walk(oid: Oid.fromString('1.0.8802.1.1.2.1.4.1.1.9'));
        await for (final msg in lldpStream) {
          for (final vb in msg.pdu.varbinds) {
            final remoteSys = vb.value.toString().trim();
            if (remoteSys.isNotEmpty) {
              final oidParts = vb.oid.toString().split('.');
              final localPortIdx = oidParts.length > 2 ? oidParts[oidParts.length - 2] : '1';
              final localPortName = ifIndexToName[int.tryParse(localPortIdx)] ?? 'Port $localPortIdx';

              neighbors.add(SwitchNeighborLink(
                localPort: localPortName,
                remoteSysName: remoteSys,
                remotePort: 'Uplink',
              ));
            }
          }
        }
      } catch (_) {}

    } finally {
      session.close();
    }

    return SwitchDiscoveryResult(
      switchIp: targetIp,
      sysName: sysName,
      sysDescr: sysDescr,
      ports: ports.values.toList()..sort((a, b) => a.portNumber.compareTo(b.portNumber)),
      neighbors: neighbors,
    );
  }
}
