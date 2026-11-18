import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';
import 'package:dart_snmp/dart_snmp.dart';
import '../../domain/models/igmp_vlan_status.dart';
import '../../domain/models/interface_health_stats.dart';
import '../../domain/models/port_vlan_config.dart';
import '../../domain/models/stp_port_info.dart';
import '../../domain/models/switch_discovery_info.dart';
import '../../domain/models/switch_poe_status.dart';

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

    // Q-BRIDGE-MIB VLAN state (Issue #4)
    final bridgePortPvid = <int, int>{};
    final vlanNames = <int, String>{};
    final vlanEgressPorts = <int, Set<int>>{};
    final vlanUntaggedPorts = <int, Set<int>>{};

    // IF-MIB & EtherLike-MIB state (Issue #5)
    final ifHighSpeedMbps = <int, int>{};
    final ifOperUp = <int, bool>{};
    final ifInErrors = <int, int>{};
    final ifOutErrors = <int, int>{};
    final ifInDiscards = <int, int>{};
    final ifOutDiscards = <int, int>{};
    final ifDuplexModes = <int, DuplexMode>{};

    // POWER-ETHERNET-MIB PoE state (Issue #7)
    int poeTotalBudgetWatts = 0;
    int poeConsumedWatts = 0;
    final poePortStates = <int, PoePortState>{};
    final poePortClasses = <int, String>{};
    final poePortWatts = <int, double>{};

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

      // 8. Q-BRIDGE-MIB VLAN Membership & PVIDs (Issue #4)
      try {
        final pvidStream = session.walk(oid: Oid.fromString('1.3.6.1.2.1.17.7.1.4.5.1.1'));
        await for (final msg in pvidStream) {
          for (final vb in msg.pdu.varbinds) {
            final bPort = int.tryParse(vb.oid.toString().split('.').last);
            final pvid = int.tryParse(vb.value.toString());
            if (bPort != null && pvid != null && pvid > 0) {
              bridgePortPvid[bPort] = pvid;
            }
          }
        }
      } catch (_) {}

      try {
        final vlanNameStream = session.walk(oid: Oid.fromString('1.3.6.1.2.1.17.7.1.4.3.1.1'));
        await for (final msg in vlanNameStream) {
          for (final vb in msg.pdu.varbinds) {
            final vid = int.tryParse(vb.oid.toString().split('.').last);
            final name = vb.value.toString().trim();
            if (vid != null && name.isNotEmpty) {
              vlanNames[vid] = name;
            }
          }
        }
      } catch (_) {}

      try {
        final egressStream = session.walk(oid: Oid.fromString('1.3.6.1.2.1.17.7.1.4.2.1.4'));
        await for (final msg in egressStream) {
          for (final vb in msg.pdu.varbinds) {
            final vid = int.tryParse(vb.oid.toString().split('.').last);
            final bytes = extractSnmpOctetBytes(vb.value);
            if (vid != null && bytes.isNotEmpty) {
              vlanEgressPorts
                  .putIfAbsent(vid, () => <int>{})
                  .addAll(decodePortListBitmask(bytes));
            }
          }
        }
      } catch (_) {}

      try {
        final untaggedStream = session.walk(oid: Oid.fromString('1.3.6.1.2.1.17.7.1.4.2.1.5'));
        await for (final msg in untaggedStream) {
          for (final vb in msg.pdu.varbinds) {
            final vid = int.tryParse(vb.oid.toString().split('.').last);
            final bytes = extractSnmpOctetBytes(vb.value);
            if (vid != null && bytes.isNotEmpty) {
              vlanUntaggedPorts
                  .putIfAbsent(vid, () => <int>{})
                  .addAll(decodePortListBitmask(bytes));
            }
          }
        }
      } catch (_) {}

      // 9. IF-MIB & EtherLike-MIB Speed, Duplex & Errors (Issue #5)
      try {
        final speedStream = session.walk(oid: Oid.fromString('1.3.6.1.2.1.31.1.1.1.15'));
        await for (final msg in speedStream) {
          for (final vb in msg.pdu.varbinds) {
            final ifIdx = int.tryParse(vb.oid.toString().split('.').last);
            final speed = int.tryParse(vb.value.toString());
            if (ifIdx != null && speed != null) {
              ifHighSpeedMbps[ifIdx] = speed;
            }
          }
        }
      } catch (_) {}

      try {
        final operStream = session.walk(oid: Oid.fromString('1.3.6.1.2.1.2.2.1.8'));
        await for (final msg in operStream) {
          for (final vb in msg.pdu.varbinds) {
            final ifIdx = int.tryParse(vb.oid.toString().split('.').last);
            final status = int.tryParse(vb.value.toString());
            if (ifIdx != null && status != null) {
              ifOperUp[ifIdx] = status == 1;
            }
          }
        }
      } catch (_) {}

      try {
        final inDiscardsStream = session.walk(oid: Oid.fromString('1.3.6.1.2.1.2.2.1.13'));
        await for (final msg in inDiscardsStream) {
          for (final vb in msg.pdu.varbinds) {
            final ifIdx = int.tryParse(vb.oid.toString().split('.').last);
            final val = int.tryParse(vb.value.toString());
            if (ifIdx != null && val != null) ifInDiscards[ifIdx] = val;
          }
        }
      } catch (_) {}

      try {
        final inErrStream = session.walk(oid: Oid.fromString('1.3.6.1.2.1.2.2.1.14'));
        await for (final msg in inErrStream) {
          for (final vb in msg.pdu.varbinds) {
            final ifIdx = int.tryParse(vb.oid.toString().split('.').last);
            final val = int.tryParse(vb.value.toString());
            if (ifIdx != null && val != null) ifInErrors[ifIdx] = val;
          }
        }
      } catch (_) {}

      try {
        final outDiscardsStream = session.walk(oid: Oid.fromString('1.3.6.1.2.1.2.2.1.19'));
        await for (final msg in outDiscardsStream) {
          for (final vb in msg.pdu.varbinds) {
            final ifIdx = int.tryParse(vb.oid.toString().split('.').last);
            final val = int.tryParse(vb.value.toString());
            if (ifIdx != null && val != null) ifOutDiscards[ifIdx] = val;
          }
        }
      } catch (_) {}

      try {
        final outErrStream = session.walk(oid: Oid.fromString('1.3.6.1.2.1.2.2.1.20'));
        await for (final msg in outErrStream) {
          for (final vb in msg.pdu.varbinds) {
            final ifIdx = int.tryParse(vb.oid.toString().split('.').last);
            final val = int.tryParse(vb.value.toString());
            if (ifIdx != null && val != null) ifOutErrors[ifIdx] = val;
          }
        }
      } catch (_) {}

      try {
        final duplexStream = session.walk(oid: Oid.fromString('1.3.6.1.2.1.10.7.2.1.19'));
        await for (final msg in duplexStream) {
          for (final vb in msg.pdu.varbinds) {
            final ifIdx = int.tryParse(vb.oid.toString().split('.').last);
            final code = int.tryParse(vb.value.toString());
            if (ifIdx != null && code != null) {
              ifDuplexModes[ifIdx] = DuplexMode.fromCode(code);
            }
          }
        }
      } catch (_) {}

      // 10. POWER-ETHERNET-MIB Chassis & Per-Port PoE Telemetry (Issue #7)
      try {
        final budgetStream = session.walk(oid: Oid.fromString('1.3.6.1.2.1.105.1.3.1.1.2'));
        await for (final msg in budgetStream) {
          for (final vb in msg.pdu.varbinds) {
            final watts = int.tryParse(vb.value.toString());
            if (watts != null && watts > 0) poeTotalBudgetWatts += watts;
          }
        }
      } catch (_) {}

      try {
        final drawStream = session.walk(oid: Oid.fromString('1.3.6.1.2.1.105.1.3.1.1.4'));
        await for (final msg in drawStream) {
          for (final vb in msg.pdu.varbinds) {
            final watts = int.tryParse(vb.value.toString());
            if (watts != null && watts >= 0) poeConsumedWatts += watts;
          }
        }
      } catch (_) {}

      try {
        final portStateStream = session.walk(oid: Oid.fromString('1.3.6.1.2.1.105.1.1.1.6'));
        await for (final msg in portStateStream) {
          for (final vb in msg.pdu.varbinds) {
            final pNum = int.tryParse(vb.oid.toString().split('.').last);
            final code = int.tryParse(vb.value.toString());
            if (pNum != null && code != null) {
              poePortStates[pNum] = PoePortState.fromCode(code);
            }
          }
        }
      } catch (_) {}

      try {
        final portClassStream = session.walk(oid: Oid.fromString('1.3.6.1.2.1.105.1.1.1.10'));
        await for (final msg in portClassStream) {
          for (final vb in msg.pdu.varbinds) {
            final pNum = int.tryParse(vb.oid.toString().split('.').last);
            final classCode = int.tryParse(vb.value.toString());
            if (pNum != null && classCode != null) {
              poePortClasses[pNum] = 'Class ${classCode - 1}';
            }
          }
        }
      } catch (_) {}

      try {
        final ciscoMwStream = session.walk(oid: Oid.fromString('1.3.6.1.4.1.9.9.402.1.2.1.9'));
        await for (final msg in ciscoMwStream) {
          for (final vb in msg.pdu.varbinds) {
            final pNum = int.tryParse(vb.oid.toString().split('.').last);
            final mw = int.tryParse(vb.value.toString());
            if (pNum != null && mw != null && mw >= 0) {
              poePortWatts[pNum] = mw / 1000.0;
            }
          }
        }
      } catch (_) {}

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

    // Assemble PortVlanConfig entries
    final allBridgePorts = <int>{
      ...bridgePortPvid.keys,
      ...ports.keys,
      for (final s in vlanEgressPorts.values) ...s,
    };
    final portVlans = <PortVlanConfig>[];
    for (final bPort in allBridgePorts) {
      final allowed = <int>{
        if (bridgePortPvid.containsKey(bPort)) bridgePortPvid[bPort]!,
        for (final e in vlanEgressPorts.entries)
          if (e.value.contains(bPort)) e.key,
      };
      final untagged = <int>{
        if (bridgePortPvid.containsKey(bPort)) bridgePortPvid[bPort]!,
        for (final e in vlanUntaggedPorts.entries)
          if (e.value.contains(bPort)) e.key,
      };
      if (allowed.isEmpty && !bridgePortPvid.containsKey(bPort)) continue;
      final ifIdx = ports[bPort]?.ifIndex ?? bPort;
      final ifName = ports[bPort]?.portName ?? ifIndexToName[ifIdx] ?? 'Port $bPort';
      portVlans.add(PortVlanConfig(
        bridgePort: bPort,
        ifIndex: ifIdx,
        interfaceName: ifName,
        nativePvid: bridgePortPvid[bPort] ?? (untagged.isNotEmpty ? untagged.first : 1),
        allowedVlans: allowed,
        untaggedVlans: untagged,
      ));
    }
    portVlans.sort((a, b) => a.bridgePort.compareTo(b.bridgePort));

    // Assemble InterfaceHealthStats entries
    final now = DateTime.now();
    final allIfIndices = <int>{
      ...ifHighSpeedMbps.keys,
      ...ifOperUp.keys,
      ...ifInErrors.keys,
      ...ifInDiscards.keys,
    };
    final interfaceHealth = <InterfaceHealthStats>[];
    for (final ifIdx in allIfIndices) {
      final bPort = ifIndexToPort[ifIdx];
      final ifName = ifIndexToName[ifIdx] ??
          (bPort != null ? ports[bPort]?.portName : null) ??
          'Port $ifIdx';
      interfaceHealth.add(InterfaceHealthStats(
        ifIndex: ifIdx,
        interfaceName: ifName,
        speedMbps: ifHighSpeedMbps[ifIdx] ?? 0,
        isOperUp: ifOperUp[ifIdx] ?? true,
        duplex: ifDuplexModes[ifIdx] ?? DuplexMode.unknown,
        inErrors: ifInErrors[ifIdx] ?? 0,
        outErrors: ifOutErrors[ifIdx] ?? 0,
        inDiscards: ifInDiscards[ifIdx] ?? 0,
        outDiscards: ifOutDiscards[ifIdx] ?? 0,
        sampledAt: now,
      ));
    }
    interfaceHealth.sort((a, b) => a.ifIndex.compareTo(b.ifIndex));

    // Assemble SwitchPoeStatus if PSE reported
    SwitchPoeStatus? poeStatus;
    if (poeTotalBudgetWatts > 0 || poePortStates.isNotEmpty) {
      final poePorts = poePortStates.entries.map((e) {
        final pIdx = e.key;
        final ifName = ports[pIdx]?.portName ?? ifIndexToName[pIdx] ?? 'Port $pIdx';
        return PoePortDetail(
          portIndex: pIdx,
          interfaceName: ifName,
          state: e.value,
          powerClass: poePortClasses[pIdx],
          drawWatts: poePortWatts[pIdx],
        );
      }).toList()
        ..sort((a, b) => a.portIndex.compareTo(b.portIndex));
      poeStatus = SwitchPoeStatus(
        totalBudgetWatts: poeTotalBudgetWatts,
        consumedWatts: poeConsumedWatts,
        ports: poePorts,
      );
    }

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
      vlanNames: vlanNames,
      portVlans: portVlans,
      interfaceHealth: interfaceHealth,
      poeStatus: poeStatus,
    );
  }

  /// Decodes IEEE 802.1Q PortList bitmask into 1-based bridge port IDs.
  static Set<int> decodePortListBitmask(Uint8List bytes) =>
      PortVlanConfig.decodePortListBitmask(bytes);

  /// Extracts raw bytes from a `dart_snmp` OCTET_STRING varbind value
  /// (which base64-encodes values containing bytes > 127).
  static Uint8List extractSnmpOctetBytes(dynamic value) {
    if (value is Uint8List) return value;
    if (value is List<int>) return Uint8List.fromList(value);
    if (value is String && value.isNotEmpty) {
      try {
        final decoded = base64Decode(value);
        if (base64Encode(decoded) == value && decoded.any((b) => b > 127)) {
          return Uint8List.fromList(decoded);
        }
      } catch (_) {}
      return Uint8List.fromList(value.codeUnits.map((c) => c & 0xFF).toList());
    }
    return Uint8List(0);
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
