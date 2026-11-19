import 'dart:async';
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

  static String _oidString(Oid oid) {
    final raw = oid.identifier ??
        oid.toString().replaceFirst('Oid(', '').replaceFirst(RegExp(r'\)$'), '');
    return raw.startsWith('.') ? raw.substring(1) : raw;
  }

  static bool _isReadableVarbind(Varbind vb) {
    return vb.tag != VarbindType.noSuchObject.value &&
        vb.tag != VarbindType.noSuchInstance.value &&
        vb.tag != VarbindType.endOfMibView.value;
  }

  static Future<Message?> _safeGet(Snmp session, String oidStr) async {
    try {
      return await session.get(Oid.fromString(oidStr)).timeout(defaultTimeout);
    } catch (_) {
      return null;
    }
  }

  static Future<void> _safeWalk(
    Snmp session,
    String baseOid,
    void Function(String oidStr, Varbind vb) onVarbind,
  ) async {
    try {
      final stream = session
          .walk(oid: Oid.fromString(baseOid))
          .timeout(defaultTimeout * 2);
      await for (final msg in stream) {
        for (final vb in msg.pdu.varbinds) {
          final oidStr = _oidString(vb.oid);
          if (oidStr != baseOid && !oidStr.startsWith('$baseOid.')) {
            return;
          }
          if (!_isReadableVarbind(vb)) continue;
          onVarbind(oidStr, vb);
        }
      }
    } catch (_) {}
  }

  static ({String key, int localPortNum})? _extractLldpKey(String oidStr) {
    final oidParts = oidStr.split('.');
    if (oidParts.length < 2) return null;
    final localPortNum = int.tryParse(oidParts[oidParts.length - 2]);
    final remIdx = oidParts[oidParts.length - 1];
    if (localPortNum == null || remIdx.isEmpty) return null;
    return (key: '$localPortNum.$remIdx', localPortNum: localPortNum);
  }

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
      timeout: defaultTimeout,
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

    bool sessionClosed = false;
    try {
      // 1. System info: sysName.0 (1.3.6.1.2.1.1.5.0) and sysDescr.0 (1.3.6.1.2.1.1.1.0)
      bool sysResponded = false;
      final sysNameMsg = await _safeGet(session, '1.3.6.1.2.1.1.5.0');
      if (sysNameMsg != null) {
        sysResponded = true;
        if (sysNameMsg.pdu.varbinds.isNotEmpty &&
            _isReadableVarbind(sysNameMsg.pdu.varbinds.first)) {
          final val = sysNameMsg.pdu.varbinds.first.value?.toString().trim() ?? '';
          if (val.isNotEmpty) sysName = val;
        }
      }

      final sysDescrMsg = await _safeGet(session, '1.3.6.1.2.1.1.1.0');
      if (sysDescrMsg != null) {
        sysResponded = true;
        if (sysDescrMsg.pdu.varbinds.isNotEmpty &&
            _isReadableVarbind(sysDescrMsg.pdu.varbinds.first)) {
          final val = sysDescrMsg.pdu.varbinds.first.value?.toString().trim() ?? '';
          if (val.isNotEmpty) sysDescr = val;
        }
      }

      if (!sysResponded) {
        session.close();
        sessionClosed = true;
        throw TimeoutException(
          'SNMP host $targetIp:$port did not respond to sysName/sysDescr',
          defaultTimeout,
        );
      }

      // 2. Map dot1dBasePort to ifIndex (1.3.6.1.2.1.17.1.4.1.2)
      await _safeWalk(session, '1.3.6.1.2.1.17.1.4.1.2', (oidStr, vb) {
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
      });

      // 3. Interface names / descriptions (1.3.6.1.2.1.31.1.1.1.1 for ifName)
      await _safeWalk(session, '1.3.6.1.2.1.31.1.1.1.1', (oidStr, vb) {
        final ifIdx = int.tryParse(oidStr.split('.').last);
        final name = vb.value?.toString().trim() ?? '';
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
      });

      // 4. Forwarding Database (FDB): dot1dTpFdbPort (1.3.6.1.2.1.17.4.3.1.2)
      // OID: 1.3.6.1.2.1.17.4.3.1.2.m1.m2.m3.m4.m5.m6 = <dot1dBasePort>
      await _safeWalk(session, '1.3.6.1.2.1.17.4.3.1.2', (oidStr, vb) {
        final parts = oidStr.split('.');
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
      });

      // 5. LLDP-MIB Remote Neighbors: lldpRemSysName (.9), lldpRemPortId (.7), lldpRemPortDesc (.8)
      final lldpRemSysNames = <String, String>{};
      final lldpRemPortIds = <String, String>{};
      final lldpRemPortDescs = <String, String>{};
      final lldpLocalPorts = <String, int>{};

      await _safeWalk(session, '1.0.8802.1.1.2.1.4.1.1.9', (oidStr, vb) {
        final remoteSys = vb.value?.toString().trim() ?? '';
        if (remoteSys.isEmpty) return;
        final parsed = _extractLldpKey(oidStr);
        if (parsed == null) return;
        lldpLocalPorts[parsed.key] = parsed.localPortNum;
        lldpRemSysNames[parsed.key] = remoteSys;
      });

      await _safeWalk(session, '1.0.8802.1.1.2.1.4.1.1.7', (oidStr, vb) {
        final portId = vb.value?.toString().trim() ?? '';
        if (portId.isEmpty) return;
        final parsed = _extractLldpKey(oidStr);
        if (parsed == null) return;
        lldpRemPortIds[parsed.key] = portId;
      });

      await _safeWalk(session, '1.0.8802.1.1.2.1.4.1.1.8', (oidStr, vb) {
        final portDesc = vb.value?.toString().trim() ?? '';
        if (portDesc.isEmpty) return;
        final parsed = _extractLldpKey(oidStr);
        if (parsed == null) return;
        lldpRemPortDescs[parsed.key] = portDesc;
      });

      for (final entry in lldpRemSysNames.entries) {
        final key = entry.key;
        final remoteSys = entry.value;
        final localPortNum = lldpLocalPorts[key]!;
        final localPortName = ports[localPortNum]?.portName ??
            ifIndexToName[localPortNum] ??
            'Port $localPortNum';
        final remoteDesc = lldpRemPortDescs[key];
        final remotePortId = lldpRemPortIds[key];

        neighbors.add(SwitchNeighborLink(
          localPort: localPortName,
          remoteSysName: remoteSys,
          remotePort: remoteDesc ?? remotePortId ?? 'Uplink',
        ));
      }

      // 6. BRIDGE-MIB STP / RSTP Status
      final bridgeAddrMsg = await _safeGet(session, '1.3.6.1.2.1.17.1.1.0');
      if (bridgeAddrMsg != null && bridgeAddrMsg.pdu.varbinds.isNotEmpty) {
        stpBridgeMac = formatMacString(bridgeAddrMsg.pdu.varbinds.first.value.toString());
      }

      final stpPrioMsg = await _safeGet(session, '1.3.6.1.2.1.17.2.2.0');
      if (stpPrioMsg != null && stpPrioMsg.pdu.varbinds.isNotEmpty) {
        stpPriority = int.tryParse(stpPrioMsg.pdu.varbinds.first.value.toString());
      }

      final rootMsg = await _safeGet(session, '1.3.6.1.2.1.17.2.5.0');
      if (rootMsg != null && rootMsg.pdu.varbinds.isNotEmpty) {
        final parsed = parseBridgeId(rootMsg.pdu.varbinds.first.value.toString());
        if (parsed != null) {
          stpDesignatedRootId = parsed.formattedId;
          stpDesignatedRootMac = parsed.mac;
        }
      }

      final rootCostMsg = await _safeGet(session, '1.3.6.1.2.1.17.2.6.0');
      if (rootCostMsg != null && rootCostMsg.pdu.varbinds.isNotEmpty) {
        stpRootCost = int.tryParse(rootCostMsg.pdu.varbinds.first.value.toString());
      }

      final rootPortMsg = await _safeGet(session, '1.3.6.1.2.1.17.2.7.0');
      if (rootPortMsg != null && rootPortMsg.pdu.varbinds.isNotEmpty) {
        stpRootPort = int.tryParse(rootPortMsg.pdu.varbinds.first.value.toString());
      }

      // dot1dStpPortState (1.3.6.1.2.1.17.2.15.1.3)
      await _safeWalk(session, '1.3.6.1.2.1.17.2.15.1.3', (oidStr, vb) {
        final pNum = int.tryParse(oidStr.split('.').last);
        final code = int.tryParse(vb.value.toString());
        if (pNum != null && code != null) {
          stpPortStates[pNum] = StpPortState.fromCode(code);
        }
      });

      // dot1dStpPortDesignatedBridge (1.3.6.1.2.1.17.2.15.1.8)
      await _safeWalk(session, '1.3.6.1.2.1.17.2.15.1.8', (oidStr, vb) {
        final pNum = int.tryParse(oidStr.split('.').last);
        final parsed = parseBridgeId(vb.value.toString());
        if (pNum != null && parsed != null) {
          stpPortDesignatedBridges[pNum] = parsed.formattedId;
        }
      });

      // 7. IGMP Snooping & Querier MIBs (MGMD-STD-MIB + Cisco fallback)
      final snoopingStatusMsg = await _safeGet(session, '1.3.6.1.4.1.9.9.263.1.1.1.1.1');
      if (snoopingStatusMsg != null &&
          snoopingStatusMsg.pdu.varbinds.isNotEmpty &&
          _isReadableVarbind(snoopingStatusMsg.pdu.varbinds.first)) {
        igmpSnoopingEnabled = snoopingStatusMsg.pdu.varbinds.first.value.toString().trim() == '1';
      } else {
        final cbsMsg = await _safeGet(session, '1.3.6.1.4.1.9.6.1.101.55.1.1.0');
        if (cbsMsg != null &&
            cbsMsg.pdu.varbinds.isNotEmpty &&
            _isReadableVarbind(cbsMsg.pdu.varbinds.first)) {
          igmpSnoopingEnabled = cbsMsg.pdu.varbinds.first.value.toString().trim() == '1';
        }
      }

      await _safeWalk(session, '1.3.6.1.2.1.85.1.1.1.9', (oidStr, vb) {
        final ifIdx = int.tryParse(oidStr.split('.').last) ?? 1;
        final querierIp = vb.value?.toString().trim() ?? '';
        if (querierIp.isNotEmpty && querierIp != '0.0.0.0') {
          igmpVlans.add(IgmpVlanStatus(
            vlanId: ifIdx,
            snoopingEnabled: igmpSnoopingEnabled,
            activeQuerierIp: querierIp,
            isLocalSwitchQuerier: querierIp == targetIp,
          ));
        }
      });

      if (igmpVlans.isEmpty) {
        await _safeWalk(session, '1.3.6.1.4.1.9.9.263.1.1.1.1.3', (oidStr, vb) {
          final vlan = int.tryParse(oidStr.split('.').last) ?? 1;
          final querierIp = vb.value?.toString().trim() ?? '';
          if (querierIp.isNotEmpty && querierIp != '0.0.0.0') {
            igmpVlans.add(IgmpVlanStatus(
              vlanId: vlan,
              snoopingEnabled: true,
              activeQuerierIp: querierIp,
              isLocalSwitchQuerier: querierIp == targetIp,
            ));
          }
        });
      }

      // 8. Q-BRIDGE-MIB VLAN Membership & PVIDs (Issue #4)
      await _safeWalk(session, '1.3.6.1.2.1.17.7.1.4.5.1.1', (oidStr, vb) {
        final bPort = int.tryParse(oidStr.split('.').last);
        final pvid = int.tryParse(vb.value.toString());
        if (bPort != null && pvid != null && pvid > 0) {
          bridgePortPvid[bPort] = pvid;
        }
      });

      await _safeWalk(session, '1.3.6.1.2.1.17.7.1.4.3.1.1', (oidStr, vb) {
        final vid = int.tryParse(oidStr.split('.').last);
        final name = vb.value?.toString().trim() ?? '';
        if (vid != null && name.isNotEmpty) {
          vlanNames[vid] = name;
        }
      });

      await _safeWalk(session, '1.3.6.1.2.1.17.7.1.4.2.1.4', (oidStr, vb) {
        final vid = int.tryParse(oidStr.split('.').last);
        final bytes = extractSnmpOctetBytes(vb.value);
        if (vid != null && bytes.isNotEmpty) {
          vlanEgressPorts
              .putIfAbsent(vid, () => <int>{})
              .addAll(decodePortListBitmask(bytes));
        }
      });

      await _safeWalk(session, '1.3.6.1.2.1.17.7.1.4.2.1.5', (oidStr, vb) {
        final vid = int.tryParse(oidStr.split('.').last);
        final bytes = extractSnmpOctetBytes(vb.value);
        if (vid != null && bytes.isNotEmpty) {
          vlanUntaggedPorts
              .putIfAbsent(vid, () => <int>{})
              .addAll(decodePortListBitmask(bytes));
        }
      });

      // 9. IF-MIB & EtherLike-MIB Speed, Duplex & Errors (Issue #5)
      await _safeWalk(session, '1.3.6.1.2.1.31.1.1.1.15', (oidStr, vb) {
        final ifIdx = int.tryParse(oidStr.split('.').last);
        final speed = int.tryParse(vb.value.toString());
        if (ifIdx != null && speed != null) {
          ifHighSpeedMbps[ifIdx] = speed;
        }
      });

      await _safeWalk(session, '1.3.6.1.2.1.2.2.1.8', (oidStr, vb) {
        final ifIdx = int.tryParse(oidStr.split('.').last);
        final status = int.tryParse(vb.value.toString());
        if (ifIdx != null && status != null) {
          ifOperUp[ifIdx] = status == 1;
        }
      });

      await _safeWalk(session, '1.3.6.1.2.1.2.2.1.13', (oidStr, vb) {
        final ifIdx = int.tryParse(oidStr.split('.').last);
        final val = int.tryParse(vb.value.toString());
        if (ifIdx != null && val != null) ifInDiscards[ifIdx] = val;
      });

      await _safeWalk(session, '1.3.6.1.2.1.2.2.1.14', (oidStr, vb) {
        final ifIdx = int.tryParse(oidStr.split('.').last);
        final val = int.tryParse(vb.value.toString());
        if (ifIdx != null && val != null) ifInErrors[ifIdx] = val;
      });

      await _safeWalk(session, '1.3.6.1.2.1.2.2.1.19', (oidStr, vb) {
        final ifIdx = int.tryParse(oidStr.split('.').last);
        final val = int.tryParse(vb.value.toString());
        if (ifIdx != null && val != null) ifOutDiscards[ifIdx] = val;
      });

      await _safeWalk(session, '1.3.6.1.2.1.2.2.1.20', (oidStr, vb) {
        final ifIdx = int.tryParse(oidStr.split('.').last);
        final val = int.tryParse(vb.value.toString());
        if (ifIdx != null && val != null) ifOutErrors[ifIdx] = val;
      });

      await _safeWalk(session, '1.3.6.1.2.1.10.7.2.1.19', (oidStr, vb) {
        final ifIdx = int.tryParse(oidStr.split('.').last);
        final code = int.tryParse(vb.value.toString());
        if (ifIdx != null && code != null) {
          ifDuplexModes[ifIdx] = DuplexMode.fromCode(code);
        }
      });

      // 10. POWER-ETHERNET-MIB Chassis & Per-Port PoE Telemetry (Issue #7)
      await _safeWalk(session, '1.3.6.1.2.1.105.1.3.1.1.2', (_, vb) {
        final watts = int.tryParse(vb.value.toString());
        if (watts != null && watts > 0) poeTotalBudgetWatts += watts;
      });

      await _safeWalk(session, '1.3.6.1.2.1.105.1.3.1.1.4', (_, vb) {
        final watts = int.tryParse(vb.value.toString());
        if (watts != null && watts >= 0) poeConsumedWatts += watts;
      });

      await _safeWalk(session, '1.3.6.1.2.1.105.1.1.1.6', (oidStr, vb) {
        final pNum = int.tryParse(oidStr.split('.').last);
        final code = int.tryParse(vb.value.toString());
        if (pNum != null && code != null) {
          poePortStates[pNum] = PoePortState.fromCode(code);
        }
      });

      await _safeWalk(session, '1.3.6.1.2.1.105.1.1.1.10', (oidStr, vb) {
        final pNum = int.tryParse(oidStr.split('.').last);
        final classCode = int.tryParse(vb.value.toString());
        if (pNum != null && classCode != null) {
          poePortClasses[pNum] = 'Class ${classCode - 1}';
        }
      });

      await _safeWalk(session, '1.3.6.1.4.1.9.9.402.1.2.1.9', (oidStr, vb) {
        final pNum = int.tryParse(oidStr.split('.').last);
        final mw = int.tryParse(vb.value.toString());
        if (pNum != null && mw != null && mw >= 0) {
          poePortWatts[pNum] = mw / 1000.0;
        }
      });
    } finally {
      if (!sessionClosed) {
        session.close();
      }
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
