import 'package:material_ui/material_ui.dart';
import 'igmp_vlan_status.dart';
import 'interface_health_stats.dart';
import 'port_vlan_config.dart';
import 'stp_port_info.dart';
import 'switch_poe_status.dart';

enum NodeType {
  localHost,
  intermediateRouter,
  targetEndpoint,
  unresponsiveHop,
  switchDevice,
}

class NetworkNode {
  final String id;
  final String ip;
  final String? hostname;
  final String? macAddress;
  final String? vendor;
  final int hopDepth;
  final bool isTarget;
  final bool isLocalHost;
  final bool isUnresponsive;
  final bool isSwitchNode;
  final String? connectedSwitchId;
  final String? switchPort;
  final String? switchModel;
  final double? rttMs;
  final Set<String> associatedTargets;

  // Shared Device Database integration
  final String? sharedDeviceName;
  final String? deviceCategoryKey;
  final String? sharedNotes;
  final Color? customCategoryColor;
  final IconData? customCategoryIcon;

  // STP / RSTP & IGMP Querier telemetry
  final bool isStpRootBridge;
  final int? stpPriority;
  final String? stpBridgeId;
  final String? stpDesignatedRootId;
  final int? stpRootCost;
  final List<StpPortInfo> stpPorts;
  final bool isIgmpQuerier;
  final String? igmpQuerierVersion;
  final bool igmpSnoopingEnabled;
  final List<IgmpVlanStatus> igmpVlans;

  // VLAN, Interface Health & PoE telemetry
  final Map<int, String> vlanNames;
  final List<PortVlanConfig> portVlans;
  final List<InterfaceHealthStats> interfaceHealth;
  final SwitchPoeStatus? poeStatus;

  NetworkNode({
    required this.id,
    required this.ip,
    this.hostname,
    this.macAddress,
    this.vendor,
    required this.hopDepth,
    this.isTarget = false,
    this.isLocalHost = false,
    this.isUnresponsive = false,
    this.isSwitchNode = false,
    this.connectedSwitchId,
    this.switchPort,
    this.switchModel,
    this.rttMs,
    Set<String>? associatedTargets,
    this.sharedDeviceName,
    this.deviceCategoryKey,
    this.sharedNotes,
    this.customCategoryColor,
    this.customCategoryIcon,
    this.isStpRootBridge = false,
    this.stpPriority,
    this.stpBridgeId,
    this.stpDesignatedRootId,
    this.stpRootCost,
    this.stpPorts = const [],
    this.isIgmpQuerier = false,
    this.igmpQuerierVersion,
    this.igmpSnoopingEnabled = false,
    this.igmpVlans = const [],
    this.vlanNames = const {},
    this.portVlans = const [],
    this.interfaceHealth = const [],
    this.poeStatus,
  }) : associatedTargets = associatedTargets ?? <String>{};

  NodeType get nodeType {
    if (isLocalHost) return NodeType.localHost;
    if (isSwitchNode || deviceCategoryKey == 'switch') return NodeType.switchDevice;
    if (isUnresponsive) return NodeType.unresponsiveHop;
    if (isTarget) return NodeType.targetEndpoint;
    return NodeType.intermediateRouter;
  }

  bool get isSwitch => nodeType == NodeType.switchDevice;

  /// Returns user-assigned friendly name from SharedDeviceDatabase if available,
  /// otherwise reverse-DNS hostname, or finally raw IP.
  String get displayName {
    if (sharedDeviceName != null && sharedDeviceName!.trim().isNotEmpty) {
      return sharedDeviceName!.trim();
    }
    if (hostname != null && hostname!.trim().isNotEmpty && hostname != ip) {
      return hostname!.trim();
    }
    return ip;
  }

  bool get hasSharedName =>
      sharedDeviceName != null &&
      sharedDeviceName!.trim().isNotEmpty &&
      sharedDeviceName != ip;

  NetworkNode copyWith({
    String? id,
    String? ip,
    String? hostname,
    String? macAddress,
    String? vendor,
    int? hopDepth,
    bool? isTarget,
    bool? isLocalHost,
    bool? isUnresponsive,
    bool? isSwitchNode,
    String? connectedSwitchId,
    bool clearConnectedSwitch = false,
    String? switchPort,
    bool clearSwitchPort = false,
    String? switchModel,
    double? rttMs,
    Set<String>? associatedTargets,
    String? sharedDeviceName,
    String? deviceCategoryKey,
    String? sharedNotes,
    Color? customCategoryColor,
    IconData? customCategoryIcon,
    bool? isStpRootBridge,
    int? stpPriority,
    String? stpBridgeId,
    String? stpDesignatedRootId,
    int? stpRootCost,
    List<StpPortInfo>? stpPorts,
    bool? isIgmpQuerier,
    String? igmpQuerierVersion,
    bool? igmpSnoopingEnabled,
    List<IgmpVlanStatus>? igmpVlans,
    Map<int, String>? vlanNames,
    List<PortVlanConfig>? portVlans,
    List<InterfaceHealthStats>? interfaceHealth,
    SwitchPoeStatus? poeStatus,
  }) {
    return NetworkNode(
      id: id ?? this.id,
      ip: ip ?? this.ip,
      hostname: hostname ?? this.hostname,
      macAddress: macAddress ?? this.macAddress,
      vendor: vendor ?? this.vendor,
      hopDepth: hopDepth ?? this.hopDepth,
      isTarget: isTarget ?? this.isTarget,
      isLocalHost: isLocalHost ?? this.isLocalHost,
      isUnresponsive: isUnresponsive ?? this.isUnresponsive,
      isSwitchNode: isSwitchNode ?? this.isSwitchNode,
      connectedSwitchId: clearConnectedSwitch ? null : (connectedSwitchId ?? this.connectedSwitchId),
      switchPort: clearSwitchPort ? null : (switchPort ?? this.switchPort),
      switchModel: switchModel ?? this.switchModel,
      rttMs: rttMs ?? this.rttMs,
      associatedTargets: associatedTargets ?? Set<String>.from(this.associatedTargets),
      sharedDeviceName: sharedDeviceName ?? this.sharedDeviceName,
      deviceCategoryKey: deviceCategoryKey ?? this.deviceCategoryKey,
      sharedNotes: sharedNotes ?? this.sharedNotes,
      customCategoryColor: customCategoryColor ?? this.customCategoryColor,
      customCategoryIcon: customCategoryIcon ?? this.customCategoryIcon,
      isStpRootBridge: isStpRootBridge ?? this.isStpRootBridge,
      stpPriority: stpPriority ?? this.stpPriority,
      stpBridgeId: stpBridgeId ?? this.stpBridgeId,
      stpDesignatedRootId: stpDesignatedRootId ?? this.stpDesignatedRootId,
      stpRootCost: stpRootCost ?? this.stpRootCost,
      stpPorts: stpPorts ?? this.stpPorts,
      isIgmpQuerier: isIgmpQuerier ?? this.isIgmpQuerier,
      igmpQuerierVersion: igmpQuerierVersion ?? this.igmpQuerierVersion,
      igmpSnoopingEnabled: igmpSnoopingEnabled ?? this.igmpSnoopingEnabled,
      igmpVlans: igmpVlans ?? this.igmpVlans,
      vlanNames: vlanNames ?? this.vlanNames,
      portVlans: portVlans ?? this.portVlans,
      interfaceHealth: interfaceHealth ?? this.interfaceHealth,
      poeStatus: poeStatus ?? this.poeStatus,
    );
  }

  Map<String, dynamic> toJson() => {
    'id': id,
    'ip': ip,
    'hostname': hostname,
    'mac_address': macAddress,
    'vendor': vendor,
    'hop_depth': hopDepth,
    'is_target': isTarget,
    'is_local_host': isLocalHost,
    'is_unresponsive': isUnresponsive,
    'is_switch_node': isSwitchNode,
    'connected_switch_id': connectedSwitchId,
    'switch_port': switchPort,
    'switch_model': switchModel,
    'rtt_ms': rttMs,
    'associated_targets': associatedTargets.toList(),
    'shared_device_name': sharedDeviceName,
    'device_category': deviceCategoryKey,
    'shared_notes': sharedNotes,
    'is_stp_root_bridge': isStpRootBridge,
    'stp_priority': stpPriority,
    'stp_bridge_id': stpBridgeId,
    'stp_designated_root_id': stpDesignatedRootId,
    'stp_root_cost': stpRootCost,
    'stp_ports': stpPorts.map((p) => p.toJson()).toList(),
    'is_igmp_querier': isIgmpQuerier,
    'igmp_querier_version': igmpQuerierVersion,
    'igmp_snooping_enabled': igmpSnoopingEnabled,
    'igmp_vlans': igmpVlans.map((v) => v.toJson()).toList(),
    'vlan_names': vlanNames.map((k, v) => MapEntry(k.toString(), v)),
    'port_vlans': portVlans.map((p) => p.toJson()).toList(),
    'interface_health': interfaceHealth.map((h) => h.toJson()).toList(),
    'poe_status': poeStatus?.toJson(),
  };

  factory NetworkNode.fromJson(Map<String, dynamic> json) {
    final rawTargets = json['associated_targets'];
    final rawStpPorts = json['stp_ports'];
    final rawIgmpVlans = json['igmp_vlans'];
    final rawVlanNames = json['vlan_names'];
    final rawPortVlans = json['port_vlans'];
    final rawHealth = json['interface_health'];
    final rawPoe = json['poe_status'];

    final parsedVlanNames = <int, String>{};
    if (rawVlanNames is Map) {
      for (final e in rawVlanNames.entries) {
        final k = int.tryParse(e.key.toString());
        if (k != null && e.value != null) {
          parsedVlanNames[k] = e.value.toString();
        }
      }
    }

    return NetworkNode(
      id: json['id'] as String? ?? json['ip'] as String? ?? '',
      ip: json['ip'] as String? ?? '',
      hostname: json['hostname'] as String?,
      macAddress: json['mac_address'] as String?,
      vendor: json['vendor'] as String?,
      hopDepth: json['hop_depth'] as int? ?? 1,
      isTarget: json['is_target'] as bool? ?? false,
      isLocalHost: json['is_local_host'] as bool? ?? false,
      isUnresponsive: json['is_unresponsive'] as bool? ?? false,
      isSwitchNode: json['is_switch_node'] as bool? ?? false,
      connectedSwitchId: json['connected_switch_id'] as String?,
      switchPort: json['switch_port'] as String?,
      switchModel: json['switch_model'] as String?,
      rttMs: (json['rtt_ms'] as num?)?.toDouble(),
      associatedTargets: rawTargets is List ? rawTargets.whereType<String>().toSet() : <String>{},
      sharedDeviceName: json['shared_device_name'] as String?,
      deviceCategoryKey: json['device_category'] as String?,
      sharedNotes: json['shared_notes'] as String?,
      isStpRootBridge: json['is_stp_root_bridge'] as bool? ?? false,
      stpPriority: json['stp_priority'] as int?,
      stpBridgeId: json['stp_bridge_id'] as String?,
      stpDesignatedRootId: json['stp_designated_root_id'] as String?,
      stpRootCost: json['stp_root_cost'] as int?,
      stpPorts: rawStpPorts is List
          ? rawStpPorts.whereType<Map<String, dynamic>>().map(StpPortInfo.fromJson).toList()
          : const [],
      isIgmpQuerier: json['is_igmp_querier'] as bool? ?? false,
      igmpQuerierVersion: json['igmp_querier_version'] as String?,
      igmpSnoopingEnabled: json['igmp_snooping_enabled'] as bool? ?? false,
      igmpVlans: rawIgmpVlans is List
          ? rawIgmpVlans.whereType<Map<String, dynamic>>().map(IgmpVlanStatus.fromJson).toList()
          : const [],
      vlanNames: parsedVlanNames,
      portVlans: rawPortVlans is List
          ? rawPortVlans.whereType<Map<String, dynamic>>().map(PortVlanConfig.fromJson).toList()
          : const [],
      interfaceHealth: rawHealth is List
          ? rawHealth.whereType<Map<String, dynamic>>().map(InterfaceHealthStats.fromJson).toList()
          : const [],
      poeStatus: rawPoe is Map<String, dynamic> ? SwitchPoeStatus.fromJson(rawPoe) : null,
    );
  }
}
