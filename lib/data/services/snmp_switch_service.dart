import 'dart:io';
import 'package:dart_snmp/dart_snmp.dart';
import '../../domain/models/igmp_vlan_status.dart';
import '../../domain/models/stp_port_info.dart';
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

    String? stpBridgeMac;
    int? stpPriority;
    String? stpDesignatedRootId;
    String? stpDesignatedRootMac;
    int? stpRootCost;
    int? stpRootPort;
    final stpPortStates = <int, StpPortState>{};
    final stpPortDesignatedBridges = <int, String>{};
    bool igmpSnoopingEnabled = false;
    final igmpVlans = <IgmpVlanStatus>[];

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

      // 6. BRIDGE-MIB STP / RSTP Status
      try {
        final bridgeAddrMsg = await session.get(Oid.fromString('1.3.6.1.2.1.17.1.1.0'));
        if (bridgeAddrMsg.pdu.varbinds.isNotEmpty) {
          stpBridgeMac = formatMacString(bridgeAddrMsg.pdu.varbinds.first.value.toString());
        }
      } catch (_) {}

      try {
        final stpPrioMsg = await session.get(Oid.fromString('1.3.6.1.2.1.17.2.2.0'));
        if (stpPrioMsg.pdu.varbinds.isNotEmpty) {
          stpPriority = int.tryParse(stpPrioMsg.pdu.varbinds.first.value.toString());
        }
      } catch (_) {}

      try {
        final rootMsg = await session.get(Oid.fromString('1.3.6.1.2.1.17.2.5.0'));
        if (rootMsg.pdu.varbinds.isNotEmpty) {
          final parsed = parseBridgeId(rootMsg.pdu.varbinds.first.value.toString());
          if (parsed != null) {
            stpDesignatedRootId = parsed.formattedId;
            stpDesignatedRootMac = parsed.mac;
          }
        }
      } catch (_) {}

      try {
        final rootCostMsg = await session.get(Oid.fromString('1.3.6.1.2.1.17.2.6.0'));
        if (rootCostMsg.pdu.varbinds.isNotEmpty) {
          stpRootCost = int.tryParse(rootCostMsg.pdu.varbinds.first.value.toString());
        }
      } catch (_) {}

      try {
        final rootPortMsg = await session.get(Oid.fromString('1.3.6.1.2.1.17.2.7.0'));
        if (rootPortMsg.pdu.varbinds.isNotEmpty) {
          stpRootPort = int.tryParse(rootPortMsg.pdu.varbinds.first.value.toString());
        }
      } catch (_) {}

      // dot1dStpPortState (1.3.6.1.2.1.17.2.15.1.3)
      try {
        final stpPortStream = session.walk(oid: Oid.fromString('1.3.6.1.2.1.17.2.15.1.3'));
        await for (final msg in stpPortStream) {
          for (final vb in msg.pdu.varbinds) {
            final pNum = int.tryParse(vb.oid.toString().split('.').last);
            final code = int.tryParse(vb.value.toString());
            if (pNum != null && code != null) {
              stpPortStates[pNum] = StpPortState.fromCode(code);
            }
          }
        }
      } catch (_) {}

      // dot1dStpPortDesignatedBridge (1.3.6.1.2.1.17.2.15.1.8)
      try {
        final desigStream = session.walk(oid: Oid.fromString('1.3.6.1.2.1.17.2.15.1.8'));
        await for (final msg in desigStream) {
          for (final vb in msg.pdu.varbinds) {
            final pNum = int.tryParse(vb.oid.toString().split('.').last);
            final parsed = parseBridgeId(vb.value.toString());
            if (pNum != null && parsed != null) {
              stpPortDesignatedBridges[pNum] = parsed.formattedId;
            }
          }
        }
      } catch (_) {}

      // 7. IGMP Snooping & Querier MIBs (MGMD-STD-MIB + Cisco fallback)
      try {
        final snoopingStatusMsg = await session.get(Oid.fromString('1.3.6.1.4.1.9.9.263.1.1.1.1.1'));
        if (snoopingStatusMsg.pdu.varbinds.isNotEmpty) {
          igmpSnoopingEnabled = snoopingStatusMsg.pdu.varbinds.first.value.toString().trim() == '1';
        }
      } catch (_) {
        try {
          final cbsMsg = await session.get(Oid.fromString('1.3.6.1.4.1.9.6.1.101.55.1.1.0'));
          if (cbsMsg.pdu.varbinds.isNotEmpty) {
            igmpSnoopingEnabled = cbsMsg.pdu.varbinds.first.value.toString().trim() == '1';
          }
        } catch (_) {}
      }

      try {
        final igmpQuerierStream = session.walk(oid: Oid.fromString('1.3.6.1.2.1.85.1.1.1.9'));
        await for (final msg in igmpQuerierStream) {
          for (final vb in msg.pdu.varbinds) {
            final ifIdx = int.tryParse(vb.oid.toString().split('.').last) ?? 1;
            final querierIp = vb.value.toString().trim();
            if (querierIp.isNotEmpty && querierIp != '0.0.0.0') {
              igmpVlans.add(IgmpVlanStatus(
                vlanId: ifIdx,
                snoopingEnabled: igmpSnoopingEnabled,
                activeQuerierIp: querierIp,
                isLocalSwitchQuerier: querierIp == targetIp,
              ));
            }
          }
        }
      } catch (_) {}

      if (igmpVlans.isEmpty) {
        try {
          final ciscoQuerierStream = session.walk(oid: Oid.fromString('1.3.6.1.4.1.9.9.263.1.1.1.1.3'));
          await for (final msg in ciscoQuerierStream) {
            for (final vb in msg.pdu.varbinds) {
              final vlan = int.tryParse(vb.oid.toString().split('.').last) ?? 1;
              final querierIp = vb.value.toString().trim();
              if (querierIp.isNotEmpty && querierIp != '0.0.0.0') {
                igmpVlans.add(IgmpVlanStatus(
                  vlanId: vlan,
                  snoopingEnabled: true,
                  activeQuerierIp: querierIp,
                  isLocalSwitchQuerier: querierIp == targetIp,
                ));
              }
            }
          }
        } catch (_) {}
      }

    } finally {
      session.close();
    }

    final stpPorts = <StpPortInfo>[];
    for (final entry in stpPortStates.entries) {
      final bPort = entry.key;
      final state = entry.value;
      final ifIdx = ports[bPort]?.ifIndex ?? bPort;
      final ifName = ports[bPort]?.portName ?? 'Port $bPort';

      StpPortRole role = StpPortRole.unknown;
      if (state == StpPortState.disabled || state == StpPortState.broken) {
        role = StpPortRole.disabled;
      } else if (state == StpPortState.blocking) {
        role = StpPortRole.alternate;
      } else if (stpRootPort != null && bPort == stpRootPort) {
        role = StpPortRole.root;
      } else if (state == StpPortState.forwarding) {
        role = StpPortRole.designated;
      }

      stpPorts.add(StpPortInfo(
        bridgePort: bPort,
        ifIndex: ifIdx,
        interfaceName: ifName,
        state: state,
        role: role,
        designatedBridgeId: stpPortDesignatedBridges[bPort],
      ));
    }
    stpPorts.sort((a, b) => a.bridgePort.compareTo(b.bridgePort));

    return SwitchDiscoveryResult(
      switchIp: targetIp,
      sysName: sysName,
      sysDescr: sysDescr,
      ports: ports.values.toList()..sort((a, b) => a.portNumber.compareTo(b.portNumber)),
      neighbors: neighbors,
      stpBridgeMac: stpBridgeMac,
      stpPriority: stpPriority,
      stpDesignatedRootId: stpDesignatedRootId,
      stpDesignatedRootMac: stpDesignatedRootMac,
      stpRootCost: stpRootCost,
      stpRootPort: stpRootPort,
      stpPorts: stpPorts,
      igmpSnoopingEnabled: igmpSnoopingEnabled,
      igmpVlans: igmpVlans,
    );
  }

  /// Parses an 8-byte STP Bridge ID (e.g. "0x8000001122334455" or "80 00 00 11 22 33 44 55").
  static ({int priority, String mac, String formattedId})? parseBridgeId(String raw) {
    final clean = raw.replaceAll(RegExp(r'[^0-9A-Fa-f]'), '');
    if (clean.length != 16) return null;
    final priority = int.tryParse(clean.substring(0, 4), radix: 16);
    if (priority == null) return null;
    final macHex = clean.substring(4, 16).toUpperCase();
    final mac = List.generate(6, (i) => macHex.substring(i * 2, i * 2 + 2)).join(':');
    return (priority: priority, mac: mac, formattedId: '$priority / $mac');
  }

  static String? formatMacString(String raw) {
    final clean = raw.replaceAll(RegExp(r'[^0-9A-Fa-f]'), '').toUpperCase();
    if (clean.length != 12) return null;
    return List.generate(6, (i) => clean.substring(i * 2, i * 2 + 2)).join(':');
  }
}
