import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:net_route_scout/domain/models/network_edge.dart';
import 'package:net_route_scout/domain/models/port_vlan_config.dart';

void main() {
  group('PortVlanConfig', () {
    test('decodePortListBitmask decodes empty and zero-filled bytes', () {
      expect(PortVlanConfig.decodePortListBitmask(Uint8List(0)), isEmpty);
      expect(
        PortVlanConfig.decodePortListBitmask(Uint8List.fromList([0x00, 0x00])),
        isEmpty,
      );
    });

    test('decodePortListBitmask decodes single-byte big-endian bitmasks', () {
      expect(
        PortVlanConfig.decodePortListBitmask(Uint8List.fromList([0x80])),
        equals({1}),
      );
      expect(
        PortVlanConfig.decodePortListBitmask(Uint8List.fromList([0xA0])),
        equals({1, 3}),
      );
      expect(
        PortVlanConfig.decodePortListBitmask(Uint8List.fromList([0x01])),
        equals({8}),
      );
      expect(
        PortVlanConfig.decodePortListBitmask(Uint8List.fromList([0xFF])),
        equals({1, 2, 3, 4, 5, 6, 7, 8}),
      );
    });

    test('decodePortListBitmask decodes multi-byte big-endian bitmasks', () {
      expect(
        PortVlanConfig.decodePortListBitmask(Uint8List.fromList([0x00, 0x01])),
        equals({16}),
      );
      expect(
        PortVlanConfig.decodePortListBitmask(Uint8List.fromList([0x80, 0x01])),
        equals({1, 16}),
      );
      expect(
        PortVlanConfig.decodePortListBitmask(Uint8List.fromList([0xFF, 0xFF])),
        equals({for (int port = 1; port <= 16; port++) port}),
      );
    });

    test('isTrunk returns true only when more than one VLAN is allowed', () {
      const emptyPort = PortVlanConfig(
        bridgePort: 1,
        ifIndex: 101,
        interfaceName: 'Gi1/0/1',
        nativePvid: 1,
        allowedVlans: {},
        untaggedVlans: {},
      );
      const accessPort = PortVlanConfig(
        bridgePort: 2,
        ifIndex: 102,
        interfaceName: 'Gi1/0/2',
        nativePvid: 10,
        allowedVlans: {10},
        untaggedVlans: {10},
      );
      const trunkPort = PortVlanConfig(
        bridgePort: 24,
        ifIndex: 124,
        interfaceName: 'Gi1/0/24',
        nativePvid: 1,
        allowedVlans: {1, 10, 20},
        untaggedVlans: {1},
      );

      expect(emptyPort.isTrunk, isFalse);
      expect(accessPort.isTrunk, isFalse);
      expect(trunkPort.isTrunk, isTrue);
    });

    test('toJson and fromJson round-trip preserves fields and sorts VLAN sets', () {
      const original = PortVlanConfig(
        bridgePort: 24,
        ifIndex: 10124,
        interfaceName: 'Gi1/0/24',
        nativePvid: 99,
        allowedVlans: {30, 10, 99, 20},
        untaggedVlans: {99, 1},
      );

      final json = original.toJson();
      expect(json['bridge_port'], 24);
      expect(json['if_index'], 10124);
      expect(json['interface_name'], 'Gi1/0/24');
      expect(json['native_pvid'], 99);
      expect(json['allowed_vlans'], [10, 20, 30, 99]);
      expect(json['untagged_vlans'], [1, 99]);

      final restored = PortVlanConfig.fromJson(json);
      expect(restored.bridgePort, 24);
      expect(restored.ifIndex, 10124);
      expect(restored.interfaceName, 'Gi1/0/24');
      expect(restored.nativePvid, 99);
      expect(restored.allowedVlans, equals({10, 20, 30, 99}));
      expect(restored.untaggedVlans, equals({1, 99}));
      expect(restored.isTrunk, isTrue);
    });

    test('fromJson uses safe defaults when fields are absent', () {
      final restored = PortVlanConfig.fromJson(const {});
      expect(restored.bridgePort, 0);
      expect(restored.ifIndex, 0);
      expect(restored.interfaceName, 'Port');
      expect(restored.nativePvid, 1);
      expect(restored.allowedVlans, isEmpty);
      expect(restored.untaggedVlans, isEmpty);
      expect(restored.isTrunk, isFalse);
    });
  });

  group('VlanMismatchReport', () {
    test('hasAnyMismatch returns true on native PVID mismatch', () {
      const report = VlanMismatchReport(
        hasNativeVlanMismatch: true,
        sideANativeVlan: 1,
        sideBNativeVlan: 10,
        sideAPortName: 'Gi1/0/24',
        sideBPortName: 'Gi1/0/1',
      );

      expect(report.hasAnyMismatch, isTrue);
    });

    test('hasAnyMismatch returns true when VLANs are missing on side A', () {
      const report = VlanMismatchReport(
        hasNativeVlanMismatch: false,
        sideANativeVlan: 1,
        sideBNativeVlan: 1,
        missingOnSideA: {20, 30},
        sideAPortName: 'Gi1/0/24',
        sideBPortName: 'Gi1/0/1',
      );

      expect(report.hasAnyMismatch, isTrue);
    });

    test('hasAnyMismatch returns true when VLANs are missing on side B', () {
      const report = VlanMismatchReport(
        hasNativeVlanMismatch: false,
        sideANativeVlan: 1,
        sideBNativeVlan: 1,
        missingOnSideB: {40},
        sideAPortName: 'Gi1/0/24',
        sideBPortName: 'Gi1/0/1',
      );

      expect(report.hasAnyMismatch, isTrue);
    });

    test('hasAnyMismatch returns false for clean symmetric trunk match', () {
      const report = VlanMismatchReport(
        hasNativeVlanMismatch: false,
        sideANativeVlan: 10,
        sideBNativeVlan: 10,
        missingOnSideA: {},
        missingOnSideB: {},
        sideAPortName: 'Gi1/0/24',
        sideBPortName: 'Gi1/0/1',
      );

      expect(report.hasAnyMismatch, isFalse);
      expect(const VlanMismatchReport().hasAnyMismatch, isFalse);
    });

    test('toJson/fromJson round-trip and NetworkEdge.hasVlanMismatch integration', () {
      const report = VlanMismatchReport(
        hasNativeVlanMismatch: true,
        sideANativeVlan: 1,
        sideBNativeVlan: 99,
        missingOnSideA: {30, 20},
        missingOnSideB: {50, 40},
        sideAPortName: 'Te1/0/1',
        sideBPortName: 'Te1/0/2',
      );

      final reportJson = report.toJson();
      expect(reportJson['missing_on_side_a'], [20, 30]);
      expect(reportJson['missing_on_side_b'], [40, 50]);

      final restoredReport = VlanMismatchReport.fromJson(reportJson);
      expect(restoredReport.hasAnyMismatch, isTrue);
      expect(restoredReport.hasNativeVlanMismatch, isTrue);
      expect(restoredReport.sideANativeVlan, 1);
      expect(restoredReport.sideBNativeVlan, 99);
      expect(restoredReport.missingOnSideA, equals({20, 30}));
      expect(restoredReport.missingOnSideB, equals({40, 50}));
      expect(restoredReport.sideAPortName, 'Te1/0/1');
      expect(restoredReport.sideBPortName, 'Te1/0/2');

      final edgeWithoutVlan = NetworkEdge(sourceIp: '10.0.0.1', targetIp: '10.0.0.2');
      expect(edgeWithoutVlan.hasVlanMismatch, isFalse);

      final cleanEdge = NetworkEdge(
        sourceIp: '10.0.0.1',
        targetIp: '10.0.0.2',
        vlanMismatch: const VlanMismatchReport(sideANativeVlan: 1, sideBNativeVlan: 1),
      );
      expect(cleanEdge.hasVlanMismatch, isFalse);

      final mismatchEdge = NetworkEdge(
        sourceIp: '10.0.0.1',
        targetIp: '10.0.0.2',
        vlanMismatch: report,
      );
      expect(mismatchEdge.hasVlanMismatch, isTrue);

      final restoredEdge = NetworkEdge.fromJson(mismatchEdge.toJson());
      expect(restoredEdge.hasVlanMismatch, isTrue);
      expect(restoredEdge.vlanMismatch?.missingOnSideA, equals({20, 30}));
    });
  });
}
