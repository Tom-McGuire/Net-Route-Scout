# Specification: Baseline Snapshot & Live Diff Mode for Net Route Scout

## 1. Overview & Goal
Add **Baseline Topology Snapshot & Live Show Diffing** to **Net Route Scout**.

During load-in and rehearsals, technicians verify switches, trunk links, STP splits, and IGMP queriers. Re-scanning mid-show only helps if you can immediately see **what changed** compared to the known-good baseline.

This feature allows saving the current graph as a **Signed-Off Baseline Snapshot** (`.json`) and toggling **"Compare to Baseline"** mode to highlight missing devices, moved STP splits, changed IGMP queriers, or degraded link speeds.

---

## 2. Architecture & File Structure

```
lib/
├── data/
│   └── services/
│       ├── baseline_storage_service.dart     <-- [NEW] Save/Load JSON baseline snapshots
│       └── topology_diff_engine.dart         <-- [NEW] Graph comparison & delta classifier
├── domain/
│   └── models/
│       ├── topology_snapshot.dart            <-- [NEW] Serializable graph snapshot wrapper
│       └── topology_diff_result.dart         <-- [NEW] Node/Edge diff status annotations
└── ui/
    ├── view_models/
    │   └── topology_view_model.dart          <-- Manage active baseline & run diff pass
    └── views/
        └── widgets/
            ├── top_control_bar.dart          <-- [Save Baseline] & [Compare Mode] toggle
            ├── topology_canvas.dart          <-- Ghost missing nodes/links & badge changes
            └── diff_summary_drawer.dart      <-- [NEW] Filterable checklist of all changes
```

---

## 3. Domain Models & Serialization

### 3.1 `TopologySnapshot` (`lib/domain/models/topology_snapshot.dart`)
```dart
class TopologySnapshot {
  final String id;
  final String name;
  final DateTime createdAt;
  final String adapterName;
  final List<NetworkNode> nodes;
  final List<NetworkEdge> edges;

  const TopologySnapshot({
    required this.id,
    required this.name,
    required this.createdAt,
    required this.adapterName,
    required this.nodes,
    required this.edges,
  });

  Map<String, dynamic> toJson() => {
        'id': id,
        'name': name,
        'createdAt': createdAt.toIso8601String(),
        'adapterName': adapterName,
        'nodes': nodes.map((n) => n.toJson()).toList(),
        'edges': edges.map((e) => e.toJson()).toList(),
      };
}
```

### 3.2 `TopologyDiffResult` (`lib/domain/models/topology_diff_result.dart`)
```dart
enum DiffChangeType {
  unchanged,
  added,           // New unexpected device or link appeared
  missing,         // Baseline device or link disappeared (offline/unplugged)
  roleChanged,     // STP Root Bridge or IGMP Querier moved
  stpStateChanged, // Ring split moved (blocking <-> forwarding)
  linkDegraded,    // Link speed dropped
}

class TopologyDiffItem {
  final DiffChangeType type;
  final String targetId;
  final String title;
  final String baselineValue;
  final String currentValue;
  final bool isCritical;

  const TopologyDiffItem({
    required this.type,
    required this.targetId,
    required this.title,
    required this.baselineValue,
    required this.currentValue,
    this.isCritical = true,
  });
}
```

---

## 4. Graph Comparison Engine (`TopologyDiffEngine`)

Match nodes by Chassis MAC / Management IP and edges by normalized endpoint pair:
1. **Missing Nodes & Links (Critical)**: Re-inject missing baseline nodes with `DiffChangeType.missing` (ghosted red card).
2. **New / Rogue Devices (Warning)**: Badge new elements with `+ NEW`.
3. **STP Root & Ring Split Shifts (Critical)**: Highlight old and new blocking links.
4. **IGMP Querier Shifts (Critical)**: Alert when querier moves or disappears.
5. **Link Speed Regressions**: Flag downgrades (e.g. 1G -> 100M).

---

## 5. Implementation Checklist for Agent
1. Implement `toJson()` / `fromJson()` on `NetworkNode` and `NetworkEdge`.
2. Create `TopologySnapshot` and `BaselineStorageService`.
3. Build `TopologyDiffEngine` comparison logic.
4. Add top bar baseline buttons, canvas ghosting overlays, and `DiffSummaryDrawer`.
5. Add unit tests for snapshot serialization and diff detection. Verify with `flutter analyze` and `flutter test`.
