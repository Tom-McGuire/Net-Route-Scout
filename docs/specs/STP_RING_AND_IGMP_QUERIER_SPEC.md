# Specification: STP Ring Topology, Split & IGMP Querier Detection for Net Route Scout

## 1. Overview & Goal

Add **Spanning Tree Protocol (STP / RSTP) Ring Analysis**, **Split Visualization**, and **Active IGMP Querier Detection** to **Net Route Scout**.

In AV, entertainment lighting, and industrial deployments, two critical Layer 2 mechanisms dictate where traffic flows and whether multicast (sACN, Art-Net, Dante, NDI) works reliably:

1. **STP / RSTP Ring Splits:** Switches wired in a physical ring elect a Root Bridge and place an uplink port on the far side of the loop into a **Blocking / Discarding** state. If switch priorities are left at defaults, the split lands in an unpredictable location, forcing traffic the "long way" around the loop.

2. **Active IGMP Querier Election:** Managed switches running IGMP Snooping require an active **IGMP Querier** (elected by lowest IP address) to maintain multicast group memberships. If no querier is active, multicast streams flood or drop after ~260 seconds. If an edge switch with a lower IP accidentally wins the querier election, all multicast traffic gets pulled across the ring toward that edge switch—potentially crossing suboptimal paths or overloading uplinks.

This feature extends Net Route Scout's existing SNMP switch polling, LLDP/CDP neighbor correlation, and interactive topology canvas to:

1. Query standard `BRIDGE-MIB` (`1.3.6.1.2.1.17.2`) OIDs during switch discovery to map the STP Root Bridge, path costs, and `Blocking` port splits.

2. Query IGMP Snooping & Querier MIBs (plus passive IGMP General Query sniffing) to identify which switch is the elected **Active IGMP Querier** per VLAN, its querier IP, and whether IGMP snooping is enabled.

3. Visually render the STP Root badge, active forwarding arrows, red `STP SPLIT (BLK)` link breaks, and `IGMP QUERIER` badges on `TopologyCanvas`, accompanied by actionable diagnostics in `AlertBanner` and `DetailInspectorPanel`.

## 2. SNMP Data Acquisition (`BRIDGE-MIB` & IGMP MIBs)

Extend `SnmpSwitchService` (`lib/data/services/snmp_switch_service.dart`) to poll standard IEEE 802.1D/802.1w `BRIDGE-MIB` OIDs and IGMP Snooping / Querier OIDs alongside existing `LLDP-MIB` and `IF-MIB` walks.

### 2.1 STP / RSTP Target OIDs (`BRIDGE-MIB`)

| MIB Object | OID | ASN.1 Type | Purpose | 
| ----- | ----- | ----- | ----- | 
| `dot1dBaseBridgeAddress` | `1.3.6.1.2.1.17.1.1.0` | OctetString (6B) | Local switch base MAC address | 
| `dot1dBasePortIfIndex` | `1.3.6.1.2.1.17.1.4.1.2.<bridgePort>` | Integer | Maps STP bridge port index to `IF-MIB` `ifIndex` | 
| `dot1dStpPriority` | `1.3.6.1.2.1.17.2.2.0` | Integer | Local switch STP priority (e.g., `32768`, `4096`) | 
| `dot1dStpDesignatedRoot` | `1.3.6.1.2.1.17.2.5.0` | OctetString (8B) | 2-byte Priority + 6-byte MAC of elected Root Bridge | 
| `dot1dStpRootCost` | `1.3.6.1.2.1.17.2.6.0` | Integer | Cumulative path cost from this switch to Root Bridge | 
| `dot1dStpRootPort` | `1.3.6.1.2.1.17.2.7.0` | Integer | Bridge port number pointing toward the Root Bridge (`0` if local switch is Root) | 
| `dot1dStpPortState` | `1.3.6.1.2.1.17.2.15.1.3.<bridgePort>` | Integer | Port forwarding state (`1`–`6`) | 
| `dot1dStpPortDesignatedBridge` | `1.3.6.1.2.1.17.2.15.1.8.<bridgePort>` | OctetString (8B) | Upstream bridge ID on this segment | 

#### Port State Enumeration (`dot1dStpPortState`)

* `1` — `disabled` (Administratively down or link down)
* `2` — `blocking` (**Discarding / Blocking** — *Ring split point*)
* `3` — `listening` (Transitional state)
* `4` — `learning` (Transitional state)
* `5` — `forwarding` (**Active** — *Forwarding traffic*)
* `6` — `broken` (Fault state)

### 2.2 IGMP Snooping & Active Querier Target OIDs

Because IGMP Snooping MIBs vary slightly across vendor families (Standard `MGMD-STD-MIB` / `IGMP-STD-MIB` vs. Cisco `CISCO-IGMP-SNOOPING-MIB` vs. Cisco Business / D-Link / Broadcom enterprise MIBs), implement a **multi-OID fallback walker** in `SnmpSwitchService`:

| Feature | Standard / Primary OID | Vendor Fallback OIDs (Cisco IOS / CBS / Netgear) | Purpose | 
| ----- | ----- | ----- | ----- | 
| **IGMP Interface Querier IP** | `1.3.6.1.2.1.85.1.1.1.9.<ifIndex>` (`igmpInterfaceQuerier`) | `1.3.6.1.4.1.9.9.263.1.1.1.1.3.<vlan>` (`cisQuerierAddress`) | IP address of the elected active Querier on that VLAN/SVI | 
| **IGMP Interface Version** | `1.3.6.1.2.1.85.1.1.1.4.<ifIndex>` (`igmpInterfaceVersion`) | `1.3.6.1.4.1.9.9.263.1.1.1.1.4.<vlan>` | IGMP version (`2` or `3`) | 
| **Global Snooping Status** | `1.3.6.1.4.1.9.9.263.1.1.1.1.1` (`cisAdminStatus`) | `1.3.6.1.4.1.9.6.1.101.55.1.1.0` (Cisco CBS/C1300) | Whether IGMP Snooping is enabled (`1` = true, `2` = false) | 
| **Local Querier Admin State** | `1.3.6.1.4.1.9.9.263.1.1.1.1.2.<vlan>` | `1.3.6.1.4.1.9.6.1.101.55.2.1.3.<vlan>` | Whether this specific switch has Querier capability enabled | 

#### Passive Fallback: Decoupled 2-Scan Sniffing (STP 4s & IGMP ~130s)

In addition to SNMP polling, Net Route Scout supports fully passive control-frame discovery on the active local adapter using `tcpdump` (with fallback to `tshark`):

1. **Fast STP Detection (4s Bounded Capture):** BPDUs are transmitted every 2s. A 4s capture window reliably identifies the Root Bridge System MAC and priority without delay.
2. **Background IGMP Querier Listener (~130s):** RFC 2236/3376 General Queries (`224.0.0.1`, Type `0x11`) are sent every 125 seconds. A dedicated background listener runs for ~130s (or runs permanently across sweeps in continuous-watch mode), extracting the IPv4 Source Address and dynamically badging the Querier switch node as soon as the query is detected.
3. **Dual Capture Engines:** Uses `tcpdump` (`tcpdump -c 1 -i <iface> -nn -v 'igmp and dst 224.0.0.1 and ip[20] == 0x11'`) as primary and falls back to `tshark` (`tshark -i <iface> -a duration:130 -Y "igmp.type == 0x11 and ip.dst == 224.0.0.1"`).

### 2.3 Port Index Mapping (`bridgePort` -> `ifIndex` -> LLDP Port)

* Walk `dot1dBasePortIfIndex` (`1.3.6.1.2.1.17.1.4.1.2`) to build a `Map<int, int>` (`bridgePort -> ifIndex`).
* Resolve `ifIndex` to `ifName` / `ifDescr` via existing `IF-MIB` data so STP port states align cleanly with LLDP neighbor links.

## 3. Architecture & File Changes

```
lib/
├── data/
│   └── services/
│       ├── snmp_switch_service.dart            <-- Add BRIDGE-MIB & IGMP Querier OID walks
│       ├── igmp_passive_listener.dart          <-- [NEW] Optional passive 224.0.0.1 query sniffer
│       └── demo_data_generator.dart            <-- Add 4-switch ring with STP split & IGMP Querier
├── domain/
│   └── models/
│       ├── network_node.dart                   <-- Add STP Root & IGMP Querier fields
│       ├── network_edge.dart                   <-- Add LinkStpState & blocked port metadata
│       ├── stp_port_info.dart                  <-- [NEW] Per-port STP state & role model
│       └── igmp_vlan_status.dart               <-- [NEW] Per-VLAN snooping & active querier model
└── ui/
    ├── view_models/
    │   └── topology_view_model.dart            <-- Correlate STP splits, Querier election & alerts
    └── views/
        └── widgets/
            ├── topology_canvas.dart            <-- Render Root/Querier badges, flow arrows & red split
            ├── node_card_widget.dart           <-- Display ROOT & QUERIER pills on switch cards
            ├── detail_inspector_panel.dart     <-- Add STP Port Table & IGMP Querier details
            └── alert_banner.dart               <-- Warn on split location, root prio, or rogue querier
```

## 4. Domain Models

### 4.1 `StpPortInfo` (`lib/domain/models/stp_port_info.dart`)

```dart
enum StpPortState {
  disabled(1, 'Disabled'),
  blocking(2, 'Blocking / Discarding'),
  listening(3, 'Listening'),
  learning(4, 'Learning'),
  forwarding(5, 'Forwarding'),
  broken(6, 'Broken'),
  unknown(0, 'Unknown');

  final int code;
  final String label;
  const StpPortState(this.code, this.label);

  static StpPortState fromCode(int? code) {
    return StpPortState.values.firstWhere(
      (e) => e.code == code,
      orElse: () => StpPortState.unknown,
    );
  }
}

enum StpPortRole {
  root,        // Uplink toward Root Bridge
  designated,  // Downstream forwarding port
  alternate,   // Blocking / Backup port (Ring Split)
  disabled,
  unknown,
}

class StpPortInfo {
  final int bridgePort;
  final int ifIndex;
  final String interfaceName;
  final StpPortState state;
  final StpPortRole role;
  final String? designatedBridgeId;

  const StpPortInfo({
    required this.bridgePort,
    required this.ifIndex,
    required this.interfaceName,
    required this.state,
    required this.role,
    this.designatedBridgeId,
  });
}
```

### 4.2 `IgmpVlanStatus` (`lib/domain/models/igmp_vlan_status.dart`)

```dart
class IgmpVlanStatus {
  final int vlanId;
  final String? vlanName;
  final bool snoopingEnabled;
  final bool localQuerierEnabled;
  final String? activeQuerierIp; // Elected querier IP for this VLAN
  final int igmpVersion;         // 2 or 3
  final bool isLocalSwitchQuerier;

  const IgmpVlanStatus({
    required this.vlanId,
    this.vlanName,
    required this.snoopingEnabled,
    this.localQuerierEnabled = false,
    this.activeQuerierIp,
    this.igmpVersion = 2,
    this.isLocalSwitchQuerier = false,
  });
}
```

### 4.3 Extensions to `NetworkNode` (`lib/domain/models/network_node.dart`)

Add optional STP and IGMP telemetry fields to switch nodes:
* `bool isStpRootBridge`
* `int? stpPriority`
* `String? stpBridgeId`
* `String? stpDesignatedRootId`
* `int? stpRootCost`
* `List<StpPortInfo> stpPorts`
* `bool isIgmpQuerier`
* `bool igmpSnoopingEnabled`
* `List<IgmpVlanStatus> igmpVlans`

### 4.4 Extensions to `NetworkEdge` (`lib/domain/models/network_edge.dart`)

```dart
enum LinkStpState {
  forwarding, // Active Layer 2 traffic path
  blocking,   // Severed by STP/RSTP (Alternate/Discarding port)
  unknown,    // Unmanaged switch or STP polling unavailable
}
```
* `LinkStpState stpState`
* `String? blockingSwitchId`
* `String? blockingPortName`
* `String? trafficDirectionTargetNodeId`

## 5. Topology Correlation & Diagnostic Alert Logic

Inside `TopologyRepository` / `TopologyViewModel`:

1. **Match LLDP Edges to STP Ports**: Compare port indices and states.
2. **Detect Ring Split (Blocking Edge)**:
   * If either port reports `StpPortState.blocking`, set `edge.stpState = LinkStpState.blocking`.
3. **Determine Active Traffic Flow Direction**: Point from lower root cost switch toward higher root cost switch.
4. **Correlate Active IGMP Querier**: Match `activeQuerierIp` to `NetworkNode` and set `node.isIgmpQuerier = true`.
5. **Generate Automated Topology Alerts (`AlertBanner`)**:
   * Ring split location info.
   * Default priority (32768) warning on root bridge.
   * Missing IGMP querier warning when snooping is active.
   * Misaligned Root & Querier warning.

## 6. Implementation Checklist for Agent

1. Create models: `stp_port_info.dart`, `igmp_vlan_status.dart`.
2. Update `NetworkNode` and `NetworkEdge`.
3. Extend `SnmpSwitchService` with `BRIDGE-MIB` and IGMP walks + passive query sniffer hook.
4. Update correlation engine in `TopologyViewModel`.
5. Render badges, arrows, and split breaks on `TopologyCanvas` and inspector panels.
6. Add demo ring data and unit tests. Verify with `flutter analyze` and `flutter test`.
