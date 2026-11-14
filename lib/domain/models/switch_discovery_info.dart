import 'igmp_vlan_status.dart';
import 'stp_port_info.dart';

class SwitchPortEntry {
  final int portNumber;
  final int? ifIndex;
  final String portName;
  final Set<String> connectedMacs;
  final int? vlanId;

  SwitchPortEntry({
    required this.portNumber,
    this.ifIndex,
    required this.portName,
    Set<String>? connectedMacs,
    this.vlanId,
  }) : connectedMacs = connectedMacs ?? <String>{};

  Map<String, dynamic> toJson() => {
    'port_number': portNumber,
    'if_index': ifIndex,
    'port_name': portName,
    'connected_macs': connectedMacs.toList(),
    'vlan_id': vlanId,
  };
}

class SwitchNeighborLink {
  final String localPort;
  final String remoteSysName;
  final String? remoteChassisId;
  final String remotePort;
  final String? remoteMgmtIp;

  SwitchNeighborLink({
    required this.localPort,
    required this.remoteSysName,
    this.remoteChassisId,
    required this.remotePort,
    this.remoteMgmtIp,
  });

  Map<String, dynamic> toJson() => {
    'local_port': localPort,
    'remote_sys_name': remoteSysName,
    'remote_chassis_id': remoteChassisId,
    'remote_port': remotePort,
    'remote_mgmt_ip': remoteMgmtIp,
  };
}

class LldpDiscoveryResult {
  final String chassisId;
  final String sysName;
  final String portId;
  final String? portDescr;
  final String? mgmtAddress;
  final int? vlanId;
  final List<String> capabilities;

  LldpDiscoveryResult({
    required this.chassisId,
    required this.sysName,
    required this.portId,
    this.portDescr,
    this.mgmtAddress,
    this.vlanId,
    this.capabilities = const [],
  });

  Map<String, dynamic> toJson() => {
    'chassis_id': chassisId,
    'sys_name': sysName,
    'port_id': portId,
    'port_descr': portDescr,
    'mgmt_address': mgmtAddress,
    'vlan_id': vlanId,
    'capabilities': capabilities,
  };
}

class SwitchDiscoveryResult {
  final String switchIp;
  final String sysName;
  final String? sysDescr;
  final List<SwitchPortEntry> ports;
  final List<SwitchNeighborLink> neighbors;

  // BRIDGE-MIB STP telemetry
  final String? stpBridgeMac;
  final int? stpPriority;
  final String? stpDesignatedRootId;
  final String? stpDesignatedRootMac;
  final int? stpRootCost;
  final int? stpRootPort;
  final List<StpPortInfo> stpPorts;

  // IGMP Snooping & Querier telemetry
  final bool igmpSnoopingEnabled;
  final List<IgmpVlanStatus> igmpVlans;

  SwitchDiscoveryResult({
    required this.switchIp,
    required this.sysName,
    this.sysDescr,
    this.ports = const [],
    this.neighbors = const [],
    this.stpBridgeMac,
    this.stpPriority,
    this.stpDesignatedRootId,
    this.stpDesignatedRootMac,
    this.stpRootCost,
    this.stpRootPort,
    this.stpPorts = const [],
    this.igmpSnoopingEnabled = false,
    this.igmpVlans = const [],
  });

  bool get isStpRootBridge {
    if (stpRootCost == 0 && stpRootPort == 0) return true;
    if (stpBridgeMac != null && stpDesignatedRootMac != null) {
      return stpBridgeMac!.toUpperCase() == stpDesignatedRootMac!.toUpperCase();
    }
    return false;
  }

  Map<String, dynamic> toJson() => {
    'switch_ip': switchIp,
    'sys_name': sysName,
    'sys_descr': sysDescr,
    'ports': ports.map((p) => p.toJson()).toList(),
    'neighbors': neighbors.map((n) => n.toJson()).toList(),
    'stp_bridge_mac': stpBridgeMac,
    'stp_priority': stpPriority,
    'stp_designated_root_id': stpDesignatedRootId,
    'stp_designated_root_mac': stpDesignatedRootMac,
    'stp_root_cost': stpRootCost,
    'stp_root_port': stpRootPort,
    'stp_ports': stpPorts.map((p) => p.toJson()).toList(),
    'igmp_snooping_enabled': igmpSnoopingEnabled,
    'igmp_vlans': igmpVlans.map((v) => v.toJson()).toList(),
  };
}

class StpPassiveResult {
  final String rootBridgeMac;
  final int? rootPriority;
  final String? sourceBridgeMac;

  const StpPassiveResult({
    required this.rootBridgeMac,
    this.rootPriority,
    this.sourceBridgeMac,
  });
}

class IgmpPassiveResult {
  final String querierIp;
  final String igmpVersion; // "IGMPv2" or "IGMPv3"
  final DateTime observedAt;

  IgmpPassiveResult({
    required this.querierIp,
    required this.igmpVersion,
    DateTime? observedAt,
  }) : observedAt = observedAt ?? DateTime.now();
}
