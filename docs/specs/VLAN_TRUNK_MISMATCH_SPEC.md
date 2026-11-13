# Specification: Trunk & Access VLAN Mismatch Detection for Net Route Scout

## 1. Overview & Goal
Add **Automated Layer 2 VLAN Mismatch & Pruning Verification** to **Net Route Scout**.

In live AV, entertainment lighting, and broadcast environments, a single misconfigured trunk port—such as forgetting to allow `VLAN 20` (sACN/Dante) on one side of an uplink or leaving a native VLAN (`PVID`) mismatched—can silently blackhole multicast streams or cause cross-VLAN bleed without dropping the physical link.

This feature extends `SnmpSwitchService` and `TopologyViewModel` to query standard `Q-BRIDGE-MIB` (`1.3.6.1.2.1.17.7`) VLAN membership tables across discovered switches, compare both sides of every LLDP-connected switch-to-switch edge, and highlight mismatches directly on `TopologyCanvas` and `AlertBanner`.

---

## 2. SNMP Data Acquisition (`Q-BRIDGE-MIB`)

Extend `SnmpSwitchService` (`lib/data/services/snmp_switch_service.dart`) to walk standard IEEE 802.1Q `Q-BRIDGE-MIB` OIDs alongside existing `IF-MIB` and `BRIDGE-MIB` walks:

| MIB Object | OID | ASN.1 Type | Purpose |
| :--- | :--- | :--- | :--- |
| `dot1qPvid` | `1.3.6.1.2.1.17.7.1.4.5.1.1.<bridgePort>` | Unsigned32 | Native / Untagged VLAN ID assigned to the port |
| `dot1qVlanStaticName` | `1.3.6.1.2.1.17.7.1.4.3.1.1.<vlanId>` | OctetString | Human-readable VLAN name (e.g., `AUDIO_DANTE`) |
| `dot1qVlanCurrentEgressPorts` | `1.3.6.1.2.1.17.7.1.4.2.1.4.<timeFilter>.<vlanId>` | PortList (Bitmask) | Bitmask of bridge ports allowed to transmit traffic for `<vlanId>` |
| `dot1qVlanCurrentUntaggedPorts` | `1.3.6.1.2.1.17.7.1.4.2.1.5.<timeFilter>.<vlanId>` | PortList (Bitmask) | Bitmask of bridge ports transmitting `<vlanId>` untagged |

### PortList Bitmask Decoding Logic
```dart
Set<int> decodePortListBitmask(Uint8List bytes) {
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
```

---

## 3. Architecture & Domain Models

```
lib/
├── data/
│   └── services/
│       └── snmp_switch_service.dart        <-- Add Q-BRIDGE-MIB walker & bitmask decoder
├── domain/
│   └── models/
│       ├── port_vlan_config.dart           <-- [NEW] Per-port PVID & allowed VLAN set
│       ├── network_node.dart               <-- Add Map<int, String> vlanNames & portVlans
│       └── network_edge.dart               <-- Add VlanMismatchReport on inter-switch links
└── ui/
    └── views/
        └── widgets/
            ├── topology_canvas.dart        <-- Draw amber warning pill on mismatched trunks
            ├── detail_inspector_panel.dart <-- Show Side-A vs Side-B VLAN diff table
            └── alert_banner.dart           <-- Emit native VLAN & missing trunk VLAN alerts
```

### 3.1 `PortVlanConfig` (`lib/domain/models/port_vlan_config.dart`)
```dart
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
}
```

### 3.2 `VlanMismatchReport` (`lib/domain/models/network_edge.dart`)
```dart
class VlanMismatchReport {
  final bool hasNativeVlanMismatch;
  final int? sideANativeVlan;
  final int? sideBNativeVlan;
  final Set<int> missingOnSideA; // Allowed on B, blocked on A
  final Set<int> missingOnSideB; // Allowed on A, blocked on B

  bool get hasAnyMismatch =>
      hasNativeVlanMismatch || missingOnSideA.isNotEmpty || missingOnSideB.isNotEmpty;

  const VlanMismatchReport({
    this.hasNativeVlanMismatch = false,
    this.sideANativeVlan,
    this.sideBNativeVlan,
    this.missingOnSideA = const {},
    this.missingOnSideB = const {},
  });
}
```

---

## 4. Correlation & Alert Rules

When `TopologyViewModel` correlates an LLDP edge between `Switch A (Port X)` and `Switch B (Port Y)`:

1. **Native VLAN (`PVID`) Check**:
   - Flag if `PortX.nativePvid != PortY.nativePvid`.
2. **Symmetric Allowed VLAN Check**:
   - Compute `missingOnSideB = PortX.allowedVlans.difference(PortY.allowedVlans)`.
   - Compute `missingOnSideA = PortY.allowedVlans.difference(PortX.allowedVlans)`.
3. **Alert Banner Messages**:
   - Native mismatch warnings.
   - Missing/pruned VLAN warnings.

---

## 5. Implementation Checklist for Agent
1. Create `PortVlanConfig` and `VlanMismatchReport` models.
2. Add `Q-BRIDGE-MIB` walking and bitmask decoder to `SnmpSwitchService`.
3. Add symmetric edge comparison logic in `TopologyViewModel`.
4. Render `⚠ VLAN MISMATCH` badge on `TopologyCanvas` and diff table in `DetailInspectorPanel`.
5. Add unit tests for bitmask decoding and asymmetric trunk detection. Verify with `flutter analyze` and `flutter test`.
