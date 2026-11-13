# Specification: PoE Budget & Per-Port Draw Overlay for Net Route Scout

## 1. Overview & Goal
Add **Power over Ethernet (PoE) Budget & Per-Port Power Draw Monitoring** to **Net Route Scout**.

Compact edge switches powering sACN DMX nodes, PoE panels, NDI converters, and APs can exceed their wattage ceiling or experience port faults. This feature monitors total PoE utilization and per-port delivery.

---

## 2. SNMP Data Acquisition (`POWER-ETHERNET-MIB`)

Extend `SnmpSwitchService` (`lib/data/services/snmp_switch_service.dart`) to poll standard `POWER-ETHERNET-MIB` tables:

| MIB Object | OID | ASN.1 Type | Purpose |
| :--- | :--- | :--- | :--- |
| `pethMainPsePower` | `1.3.6.1.2.1.105.1.3.1.1.2.<groupIndex>` | Gauge32 | Nominal total PoE budget in **Watts** |
| `pethMainPseOperStatus` | `1.3.6.1.2.1.105.1.3.1.1.3.<groupIndex>` | Integer | PSE main status (`1` = on, `2` = off, `3` = faulty) |
| `pethMainPseConsumptionPower` | `1.3.6.1.2.1.105.1.3.1.1.4.<groupIndex>` | Gauge32 | Current total PoE power drawn in **Watts** |
| `pethPsePortDetectionStatus` | `1.3.6.1.2.1.105.1.1.1.6.<group>.<port>` | Integer | Port PD status (`deliveringPower`, `fault`, etc.) |
| `pethPsePortPowerClassifications` | `1.3.6.1.2.1.105.1.1.1.10.<group>.<port>` | Integer | Negotiated PoE class |

---

## 3. Architecture & Domain Models

```
lib/
├── data/
│   └── services/
│       └── snmp_switch_service.dart        <-- Walk POWER-ETHERNET-MIB OIDs
├── domain/
│   └── models/
│       ├── switch_poe_status.dart          <-- [NEW] Chassis PoE budget & per-port states
│       └── network_node.dart               <-- Attach optional SwitchPoeStatus? poeStatus
└── ui/
    └── views/
        └── widgets/
            ├── node_card_widget.dart       <-- Render compact PoE progress bar on switch card
            ├── detail_inspector_panel.dart <-- Per-port PoE class, status & wattage table
            └── alert_banner.dart           <-- Warn when PoE load > 80% or port fault occurs
```

### 3.1 `SwitchPoeStatus` (`lib/domain/models/switch_poe_status.dart`)
```dart
enum PoePortState {
  disabled(1, 'Disabled'),
  searching(2, 'Searching'),
  deliveringPower(3, 'Delivering'),
  fault(4, 'Fault'),
  test(5, 'Testing'),
  otherFault(6, 'Overload / Fault');

  final int code;
  final String label;
  const PoePortState(this.code, this.label);
}

class PoePortDetail {
  final int portIndex;
  final String interfaceName;
  final PoePortState state;
  final String? powerClass;
  final double? drawWatts;

  const PoePortDetail({
    required this.portIndex,
    required this.interfaceName,
    required this.state,
    this.powerClass,
    this.drawWatts,
  });
}

class SwitchPoeStatus {
  final int totalBudgetWatts;
  final int consumedWatts;
  final List<PoePortDetail> ports;

  double get utilizationPercent =>
      totalBudgetWatts > 0 ? (consumedWatts / totalBudgetWatts) * 100.0 : 0.0;

  bool get isNearCapacity => utilizationPercent >= 80.0;
  bool get hasPortFaults =>
      ports.any((p) => p.state == PoePortState.fault || p.state == PoePortState.otherFault);

  const SwitchPoeStatus({
    required this.totalBudgetWatts,
    required this.consumedWatts,
    this.ports = const [],
  });
}
```

---

## 4. UI & Alert Specification

1. **`NodeCardWidget` Overlay Bar**:
   - `⚡ PoE: 142W / 195W (73%)` with color coding (cyan <75%, amber 75-89%, crimson >=90%).
2. **`DetailInspectorPanel`**:
   - Total budget, remaining headroom, and per-port breakdown cross-referenced with LLDP connected device names.
3. **`AlertBanner` Diagnostics**:
   - Alert when PoE load exceeds 80% capacity or when a port reports a PoE fault.

---

## 5. Implementation Checklist for Agent
1. Create `SwitchPoeStatus` and `PoePortDetail` models.
2. Add `POWER-ETHERNET-MIB` polling to `SnmpSwitchService`.
3. Add the compact PoE gauge bar to `NodeCardWidget`.
4. Add per-port breakdown to `DetailInspectorPanel` and capacity alerts to `AlertBanner`.
5. Add unit tests for PoE calculation and fault detection. Verify with `flutter analyze` and `flutter test`.
