# Specification: Port Link Speed, Duplex & Error Counters for Net Route Scout

## 1. Overview & Goal
Add **Physical Link Speed, Duplex & Interface Error Telemetry** to **Net Route Scout**.

On live show networks, a damaged etherCON barrel, poorly terminated Cat6A patch, or dirty SFP transceiver frequently causes a 1 Gbps trunk to auto-negotiate down to **100 Mbps** (or Half-Duplex), or silently drop packets due to **FCS/CRC frame errors** (`ifInErrors`). Because the link technically stays "Up," standard ping or LLDP checks miss the bottleneck until high-bandwidth streams (Dante, NDI, sACN) stutter.

This feature extends `SnmpSwitchService` to poll standard `IF-MIB` (`1.3.6.1.2.1.2.2` / `1.3.6.1.2.1.31.1.1`) and `EtherLike-MIB` (`1.3.6.1.2.1.10.7.2`) counters, computing real-time error deltas between scans and visually highlighting degraded links on `TopologyCanvas`.

---

## 2. SNMP Data Acquisition (`IF-MIB` & `EtherLike-MIB`)

Extend `SnmpSwitchService` (`lib/data/services/snmp_switch_service.dart`) to collect interface health metrics per `ifIndex`:

| MIB Object | OID | ASN.1 Type | Purpose |
| :--- | :--- | :--- | :--- |
| `ifHighSpeed` | `1.3.6.1.2.1.31.1.1.1.15.<ifIndex>` | Gauge32 | Link speed in **Mbps** (`100`, `1000`, `2500`, `10000`) |
| `ifOperStatus` | `1.3.6.1.2.1.2.2.1.8.<ifIndex>` | Integer | Operational status (`1` = up, `2` = down) |
| `ifInErrors` | `1.3.6.1.2.1.2.2.1.14.<ifIndex>` | Counter32 | Inbound packets discarded due to CRC/alignment/FCS errors |
| `ifOutErrors` | `1.3.6.1.2.1.2.2.1.20.<ifIndex>` | Counter32 | Outbound transmission errors |
| `ifInDiscards` | `1.3.6.1.2.1.2.2.1.13.<ifIndex>` | Counter32 | Inbound packets dropped due to buffer congestion |
| `ifOutDiscards` | `1.3.6.1.2.1.2.2.1.19.<ifIndex>` | Counter32 | Outbound queue drops (e.g., QoS/shaping saturation) |
| `dot3StatsDuplexStatus` | `1.3.6.1.2.1.10.7.2.1.19.<ifIndex>` | Integer | Duplex mode (`1` = unknown, `2` = halfDuplex, `3` = fullDuplex) |

---

## 3. Architecture & Domain Models

```
lib/
├── data/
│   └── services/
│       └── snmp_switch_service.dart        <-- Walk IF-MIB & EtherLike-MIB counters
├── domain/
│   └── models/
│       ├── interface_health_stats.dart     <-- [NEW] Speed, duplex, errors & delta tracking
│       ├── network_node.dart               <-- Store Map<int, InterfaceHealthStats>
│       └── network_edge.dart               <-- Attach LinkHealthSummary to edges
└── ui/
    └── views/
        └── widgets/
            ├── topology_canvas.dart        <-- Speed pill (1G/10G/100M) & amber warning color
            ├── detail_inspector_panel.dart <-- Interface error counters & delta rate card
            └── alert_banner.dart           <-- Warn on 100M/Half-Duplex or rising CRC errors
```

### 3.1 `InterfaceHealthStats` (`lib/domain/models/interface_health_stats.dart`)
```dart
enum DuplexMode { unknown, halfDuplex, fullDuplex }

class InterfaceHealthStats {
  final int ifIndex;
  final String interfaceName;
  final int speedMbps;
  final DuplexMode duplex;
  final int inErrors;
  final int outErrors;
  final int inDiscards;
  final int outDiscards;
  
  final int inErrorsDelta;
  final int outDiscardsDelta;
  final DateTime sampledAt;

  bool get isDegradedSpeed => speedMbps > 0 && speedMbps < 1000;
  bool get isHalfDuplex => duplex == DuplexMode.halfDuplex;
  bool get hasActiveErrors => inErrorsDelta > 0 || outDiscardsDelta > 0;

  const InterfaceHealthStats({
    required this.ifIndex,
    required this.interfaceName,
    required this.speedMbps,
    this.duplex = DuplexMode.unknown,
    this.inErrors = 0,
    this.outErrors = 0,
    this.inDiscards = 0,
    this.outDiscards = 0,
    this.inErrorsDelta = 0,
    this.outDiscardsDelta = 0,
    required this.sampledAt,
  });
}
```

### 3.2 Delta Calculation Rules
```dart
int computeCounterDelta(int previous, int current) {
  if (current >= previous) return current - previous;
  return (0xFFFFFFFF - previous) + current + 1;
}
```

---

## 4. Visual Canvas & Alert Rules

1. **Speed Badges on `TopologyCanvas`**:
   - `10G` / `2.5G` / `1G` in slate/emerald.
   - `100M ⚠` or `HALF-DUPLEX ⚠` in high-contrast amber/orange (`#F59E0B`).
2. **Error Counter Warnings**:
   - Highlight active error edges with an amber pulse when `inErrorsDelta > 0`.
3. **AlertBanner Diagnostics**:
   - Warn on degraded 100M trunks and active frame error bursts.

---

## 5. Implementation Checklist for Agent
1. Create `InterfaceHealthStats` model with 32-bit counter delta logic.
2. Extend `SnmpSwitchService` to query speed, status, errors, discards, and duplex.
3. Compute error deltas between consecutive polls in `TopologyRepository`.
4. Render speed badges on `TopologyCanvas` and error tables in `DetailInspectorPanel`.
5. Add unit tests for counter wrap-around and degraded link detection. Verify with `flutter analyze` and `flutter test`.
