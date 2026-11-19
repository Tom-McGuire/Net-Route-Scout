import '../models/network_edge.dart';
import '../models/network_node.dart';

/// Evaluates L2/STP/IGMP/VLAN/Link-Health/PoE diagnostic alert strings
/// from the current topology graph state.
class DiagnosticAlertEvaluator {
  static List<String> evaluate({
    required Map<String, NetworkNode> nodes,
    required Map<String, NetworkEdge> edges,
    required bool isListeningIgmp,
  }) {
    final alerts = <String>[];
    final switches = nodes.values.where((n) => n.isSwitch).toList();
    if (switches.isEmpty) return alerts;

    final stpRoots = switches.where((s) => s.isStpRootBridge).toList();
    final queriers = nodes.values.where((n) => n.isIgmpQuerier).toList();

    // 1. Ring Split Detection
    for (final edge in edges.values) {
      if (edge.stpState == LinkStpState.blocking) {
        final blkNode = edge.blockingSwitchId != null ? nodes[edge.blockingSwitchId!] : null;
        final swName = blkNode?.displayName ?? edge.blockingSwitchId ?? edge.targetIp;
        final portLabel = edge.blockingPortName != null ? ' (${edge.blockingPortName})' : '';
        alerts.add('STP Ring Split: Link ${edge.sourceIp} ↔ ${edge.targetIp} is Blocking at $swName$portLabel.');
      }
    }

    // 2. Default STP Priority (32768) Warning
    for (final root in stpRoots) {
      if (root.stpPriority == 32768) {
        alerts.add(
          'Default STP Priority (32768) on Root Bridge "${root.displayName}". Lower priority (e.g. 4096) recommended to anchor root.',
        );
      }
    }

    // 3. Missing IGMP Querier when Snooping is Active
    final snoopingActive = switches.any((s) => s.igmpSnoopingEnabled);
    if (snoopingActive && queriers.isEmpty && !isListeningIgmp) {
      alerts.add(
        'IGMP Snooping is active but no IGMP Querier was detected. Multicast streams may flood or timeout.',
      );
    }

    // 4. Misaligned STP Root & IGMP Querier Warning
    if (stpRoots.isNotEmpty && queriers.isNotEmpty) {
      final root = stpRoots.first;
      final querier = queriers.first;
      if (root.id != querier.id) {
        alerts.add(
          'Misaligned STP Root & IGMP Querier: STP Root is "${root.displayName}" while IGMP Querier is "${querier.displayName}". Multicast traffic may traverse suboptimal paths.',
        );
      }
    }

    // 5. Trunk VLAN Mismatches & Link Health (Issues #4 & #5)
    for (final edge in edges.values) {
      final srcName = nodes[edge.sourceIp]?.displayName ?? edge.sourceIp;
      final dstName = nodes[edge.targetIp]?.displayName ?? edge.targetIp;

      final vlanRep = edge.vlanMismatch;
      if (vlanRep != null && vlanRep.hasAnyMismatch) {
        if (vlanRep.hasNativeVlanMismatch) {
          alerts.add(
            'VLAN Native PVID Mismatch: $srcName ↔ $dstName (PVID ${vlanRep.sideANativeVlan} ≠ ${vlanRep.sideBNativeVlan}).',
          );
        }
        final pruned = <int>{...vlanRep.missingOnSideA, ...vlanRep.missingOnSideB}.toList()..sort();
        if (pruned.isNotEmpty) {
          alerts.add('Trunk VLAN Pruned: $srcName ↔ $dstName missing VLAN ${pruned.join(", ")}.');
        }
      }

      if (edge.isHalfDuplex) {
        alerts.add('Half-Duplex Trunk: $srcName ↔ $dstName negotiated Half-Duplex.');
      } else if (edge.isDegradedSpeed) {
        alerts.add('Degraded Trunk Speed: $srcName ↔ $dstName linked at ${edge.linkSpeedMbps} Mbps.');
      }
      if (edge.hasActiveErrors) {
        alerts.add(
          'Active Link Errors: $srcName ↔ $dstName (+${edge.inErrorsDelta} CRC/InErrors, +${edge.outDiscardsDelta} Drops).',
        );
      }
    }

    // 6. PoE Budget & Port Fault Warnings (Issue #7)
    for (final sw in switches) {
      final poe = sw.poeStatus;
      if (poe == null) continue;
      if (poe.isNearCapacity) {
        alerts.add(
          'PoE Budget High (${poe.utilizationPercent.round()}%): "${sw.displayName}" at ${poe.consumedWatts}W / ${poe.totalBudgetWatts}W.',
        );
      }
      if (poe.hasPortFaults) {
        alerts.add('PoE Port Fault on "${sw.displayName}": check powered device cabling/overload.');
      }
    }

    return alerts;
  }
}
