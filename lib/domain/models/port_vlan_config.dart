import 'dart:typed_data';

class PortVlanConfig {
  final int bridgePort;
  final int ifIndex;
  final String interfaceName;
  final int nativePvid;
  final Set<int> allowedVlans;
  final Set<int> untaggedVlans;

  bool get isTrunk => allowedVlans.length > 1;

  const PortVlanConfig({
    required this.bridgePort,
    required this.ifIndex,
    required this.interfaceName,
    required this.nativePvid,
    required this.allowedVlans,
    required this.untaggedVlans,
  });

  /// Decodes an IEEE 802.1Q big-endian PortList bitmask into 1-based bridge port IDs.
  static Set<int> decodePortListBitmask(Uint8List bytes) {
    final ports = <int>{};
    for (int byteIndex = 0; byteIndex < bytes.length; byteIndex++) {
      final byte = bytes[byteIndex];
      if (byte == 0) continue;
      for (int bit = 0; bit < 8; bit++) {
        if ((byte & (0x80 >> bit)) != 0) {
          final bridgePort = (byteIndex * 8) + bit + 1;
          ports.add(bridgePort);
        }
      }
    }
    return ports;
  }

  Map<String, dynamic> toJson() => {
        'bridge_port': bridgePort,
        'if_index': ifIndex,
        'interface_name': interfaceName,
        'native_pvid': nativePvid,
        'allowed_vlans': allowedVlans.toList()..sort(),
        'untagged_vlans': untaggedVlans.toList()..sort(),
      };

  factory PortVlanConfig.fromJson(Map<String, dynamic> json) {
    final rawAllowed = json['allowed_vlans'];
    final rawUntagged = json['untagged_vlans'];
    return PortVlanConfig(
      bridgePort: json['bridge_port'] as int? ?? 0,
      ifIndex: json['if_index'] as int? ?? 0,
      interfaceName: json['interface_name'] as String? ?? 'Port',
      nativePvid: json['native_pvid'] as int? ?? 1,
      allowedVlans: rawAllowed is List ? rawAllowed.whereType<int>().toSet() : <int>{},
      untaggedVlans: rawUntagged is List ? rawUntagged.whereType<int>().toSet() : <int>{},
    );
  }
}

class VlanMismatchReport {
  final bool hasNativeVlanMismatch;
  final int? sideANativeVlan;
  final int? sideBNativeVlan;
  final Set<int> missingOnSideA;
  final Set<int> missingOnSideB;
  final String? sideAPortName;
  final String? sideBPortName;

  bool get hasAnyMismatch =>
      hasNativeVlanMismatch || missingOnSideA.isNotEmpty || missingOnSideB.isNotEmpty;

  const VlanMismatchReport({
    this.hasNativeVlanMismatch = false,
    this.sideANativeVlan,
    this.sideBNativeVlan,
    this.missingOnSideA = const {},
    this.missingOnSideB = const {},
    this.sideAPortName,
    this.sideBPortName,
  });

  Map<String, dynamic> toJson() => {
        'has_native_vlan_mismatch': hasNativeVlanMismatch,
        'side_a_native_vlan': sideANativeVlan,
        'side_b_native_vlan': sideBNativeVlan,
        'missing_on_side_a': missingOnSideA.toList()..sort(),
        'missing_on_side_b': missingOnSideB.toList()..sort(),
        'side_a_port_name': sideAPortName,
        'side_b_port_name': sideBPortName,
      };

  factory VlanMismatchReport.fromJson(Map<String, dynamic> json) {
    final rawA = json['missing_on_side_a'];
    final rawB = json['missing_on_side_b'];
    return VlanMismatchReport(
      hasNativeVlanMismatch: json['has_native_vlan_mismatch'] as bool? ?? false,
      sideANativeVlan: json['side_a_native_vlan'] as int?,
      sideBNativeVlan: json['side_b_native_vlan'] as int?,
      missingOnSideA: rawA is List ? rawA.whereType<int>().toSet() : const {},
      missingOnSideB: rawB is List ? rawB.whereType<int>().toSet() : const {},
      sideAPortName: json['side_a_port_name'] as String?,
      sideBPortName: json['side_b_port_name'] as String?,
    );
  }
}
