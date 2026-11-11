import 'package:material_ui/material_ui.dart';

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
  };
}
