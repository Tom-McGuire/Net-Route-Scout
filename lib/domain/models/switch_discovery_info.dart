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

  SwitchDiscoveryResult({
    required this.switchIp,
    required this.sysName,
    this.sysDescr,
    this.ports = const [],
    this.neighbors = const [],
  });

  Map<String, dynamic> toJson() => {
    'switch_ip': switchIp,
    'sys_name': sysName,
    'sys_descr': sysDescr,
    'ports': ports.map((p) => p.toJson()).toList(),
    'neighbors': neighbors.map((n) => n.toJson()).toList(),
  };
}
