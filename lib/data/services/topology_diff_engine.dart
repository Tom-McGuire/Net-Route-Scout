import 'package:network_suite_shared/network_suite_shared.dart';
import '../../domain/models/interface_health_stats.dart';
import '../../domain/models/network_edge.dart';
import '../../domain/models/network_node.dart';
import '../../domain/models/topology_diff_result.dart';
import '../../domain/models/topology_snapshot.dart';

class TopologyDiffEngine {
  static TopologyDiffResult compare({
    required TopologySnapshot baseline,
    required Map<String, NetworkNode> currentNodes,
    required Map<String, NetworkEdge> currentEdges,
  }) {
    final items = <TopologyDiffItem>[];
    final nodeStatuses = <String, DiffChangeType>{};
    final edgeStatuses = <String, DiffChangeType>{};
    final ghostNodes = <NetworkNode>[];
    final ghostEdges = <NetworkEdge>[];

    // Index current nodes by normalized MAC, ID, and IP.
    final currentByMac = <String, List<NetworkNode>>{};
    final currentByIp = <String, List<NetworkNode>>{};
    for (final node in currentNodes.values) {
      final mac = _normalizeMac(node.macAddress);
      if (mac != null) {
        currentByMac.putIfAbsent(mac, () => []).add(node);
      }
      final ip = node.ip.trim();
      if (ip.isNotEmpty) {
        currentByIp.putIfAbsent(ip, () => []).add(node);
      }
    }

    final matchedCurrentNodeIds = <String>{};
    final baselineToCurrentNodeId = <String, String>{};
    final matchedPairs = <(NetworkNode, NetworkNode)>[];
    final matchedBaselineIds = <String>{};

    // Pass 1: Match nodes by normalized MAC address first.
    for (final bNode in baseline.nodes) {
      final bMac = _normalizeMac(bNode.macAddress);
      if (bMac == null) continue;

      final candidates = currentByMac[bMac]
          ?.where((c) => !matchedCurrentNodeIds.contains(c.id))
          .toList();
      if (candidates == null || candidates.isEmpty) continue;

      final chosen = _pickBestCandidate(bNode, candidates);
      matchedCurrentNodeIds.add(chosen.id);
      matchedBaselineIds.add(bNode.id);
      baselineToCurrentNodeId[bNode.id] = chosen.id;
      matchedPairs.add((bNode, chosen));
    }

    // Pass 2: Match remaining baseline nodes by ID or IP (when MACs are absent or equal).
    final unmatchedBaselineNodes = <NetworkNode>[];
    for (final bNode in baseline.nodes) {
      if (matchedBaselineIds.contains(bNode.id)) continue;

      final bMac = _normalizeMac(bNode.macAddress);
      NetworkNode? chosen;

      final idCandidate = currentNodes[bNode.id];
      if (idCandidate != null &&
          !matchedCurrentNodeIds.contains(idCandidate.id) &&
          _macsCompatible(bMac, _normalizeMac(idCandidate.macAddress))) {
        chosen = idCandidate;
      } else {
        final bIp = bNode.ip.trim();
        if (bIp.isNotEmpty) {
          final ipCandidates = currentByIp[bIp]
              ?.where(
                (c) =>
                    !matchedCurrentNodeIds.contains(c.id) &&
                    _macsCompatible(bMac, _normalizeMac(c.macAddress)),
              )
              .toList();
          if (ipCandidates != null && ipCandidates.isNotEmpty) {
            chosen = ipCandidates.first;
          }
        }
      }

      if (chosen != null) {
        matchedCurrentNodeIds.add(chosen.id);
        matchedBaselineIds.add(bNode.id);
        baselineToCurrentNodeId[bNode.id] = chosen.id;
        matchedPairs.add((bNode, chosen));
      } else {
        unmatchedBaselineNodes.add(bNode);
      }
    }

    // Evaluate matched nodes for L2 control-plane role shifts.
    for (final (bNode, cNode) in matchedPairs) {
      var hasRoleDrift = false;

      if (bNode.isStpRootBridge != cNode.isStpRootBridge) {
        hasRoleDrift = true;
        nodeStatuses[cNode.id] = DiffChangeType.roleChanged;
        items.add(
          TopologyDiffItem(
            type: DiffChangeType.roleChanged,
            targetId: cNode.id,
            title: bNode.isStpRootBridge
                ? 'STP Root Bridge Lost: ${cNode.displayName}'
                : 'STP Root Bridge Shifted: ${cNode.displayName}',
            baselineValue: _formatStpRole(bNode),
            currentValue: _formatStpRole(cNode),
            isCritical: true,
            isEdge: false,
          ),
        );
      }

      if (bNode.isIgmpQuerier != cNode.isIgmpQuerier) {
        hasRoleDrift = true;
        nodeStatuses[cNode.id] = DiffChangeType.roleChanged;
        items.add(
          TopologyDiffItem(
            type: DiffChangeType.roleChanged,
            targetId: cNode.id,
            title: bNode.isIgmpQuerier
                ? 'IGMP Querier Lost: ${cNode.displayName}'
                : 'IGMP Querier Shifted: ${cNode.displayName}',
            baselineValue: _formatIgmpRole(bNode),
            currentValue: _formatIgmpRole(cNode),
            isCritical: true,
            isEdge: false,
          ),
        );
      }

      if (!hasRoleDrift) {
        nodeStatuses[cNode.id] = DiffChangeType.unchanged;
      }
    }

    // Flag missing baseline nodes and emit ghost nodes.
    for (final bNode in unmatchedBaselineNodes) {
      ghostNodes.add(bNode);
      nodeStatuses[bNode.id] = DiffChangeType.missing;

      final baselineRoles = <String>[
        if (bNode.isStpRootBridge) 'STP Root',
        if (bNode.isIgmpQuerier) 'IGMP Querier',
      ];
      final roleSuffix = baselineRoles.isNotEmpty ? ' • ${baselineRoles.join(', ')}' : '';

      items.add(
        TopologyDiffItem(
          type: DiffChangeType.missing,
          targetId: bNode.id,
          title: 'Missing ${bNode.isSwitch ? 'Switch' : 'Device'}: ${bNode.displayName}',
          baselineValue: 'Online (${bNode.ip})$roleSuffix',
          currentValue: 'Offline / Missing',
          isCritical: true,
          isEdge: false,
        ),
      );
    }

    // Flag newly discovered non-unresponsive current nodes.
    for (final cNode in currentNodes.values) {
      if (matchedCurrentNodeIds.contains(cNode.id)) continue;
      if (cNode.isUnresponsive) continue;

      nodeStatuses[cNode.id] = DiffChangeType.added;
      final mac = _normalizeMac(cNode.macAddress);
      items.add(
        TopologyDiffItem(
          type: DiffChangeType.added,
          targetId: cNode.id,
          title: 'New ${cNode.isSwitch ? 'Switch' : 'Device'}: ${cNode.displayName}',
          baselineValue: 'Not in baseline',
          currentValue: mac != null ? '${cNode.ip} ($mac)' : cNode.ip,
          isCritical: false,
          isEdge: false,
        ),
      );
    }

    // Index baseline nodes and current edges for link comparison.
    final baselineNodeById = {for (final n in baseline.nodes) n.id: n};
    final currentByEdgeId = <String, NetworkEdge>{
      for (final edge in currentEdges.values) edge.edgeId: edge,
    };
    final matchedCurrentEdgeIds = <String>{};

    for (final bEdge in baseline.edges) {
      final srcMatched = baselineToCurrentNodeId[bEdge.sourceIp];
      final dstMatched = baselineToCurrentNodeId[bEdge.targetIp];
      final srcMissing = baselineNodeById.containsKey(bEdge.sourceIp) && srcMatched == null;
      final dstMissing = baselineNodeById.containsKey(bEdge.targetIp) && dstMatched == null;

      final mappedSrc = srcMatched ?? bEdge.sourceIp;
      final mappedDst = dstMatched ?? bEdge.targetIp;

      NetworkEdge? cEdge;
      if (!srcMissing && !dstMissing) {
        final direct = currentByEdgeId['$mappedSrc->$mappedDst'];
        if (direct != null && !matchedCurrentEdgeIds.contains(direct.edgeId)) {
          cEdge = direct;
        } else {
          final reverse = currentByEdgeId['$mappedDst->$mappedSrc'];
          if (reverse != null &&
              !matchedCurrentEdgeIds.contains(reverse.edgeId) &&
              _isUndirectedSwitchLink(
                bEdge: bEdge,
                cEdge: reverse,
                bSrc: baselineNodeById[bEdge.sourceIp],
                bDst: baselineNodeById[bEdge.targetIp],
                cSrc: currentNodes[mappedSrc],
                cDst: currentNodes[mappedDst],
              )) {
            cEdge = reverse;
          }
        }
      }

      if (cEdge != null) {
        matchedCurrentEdgeIds.add(cEdge.edgeId);

        final srcLabel = _nodeLabel(currentNodes[cEdge.sourceIp] ?? baselineNodeById[bEdge.sourceIp], cEdge.sourceIp);
        final dstLabel = _nodeLabel(currentNodes[cEdge.targetIp] ?? baselineNodeById[bEdge.targetIp], cEdge.targetIp);
        final edgeLabel = '$srcLabel ↔ $dstLabel';

        final stpChanged = _isStpBlockingForwardingChange(bEdge.stpState, cEdge.stpState);
        if (stpChanged) {
          edgeStatuses[cEdge.edgeId] = DiffChangeType.stpStateChanged;
          items.add(
            TopologyDiffItem(
              type: DiffChangeType.stpStateChanged,
              targetId: cEdge.edgeId,
              title: 'STP State Changed: $edgeLabel',
              baselineValue: _formatStpEdgeState(bEdge),
              currentValue: _formatStpEdgeState(cEdge),
              isCritical: true,
              isEdge: true,
            ),
          );
        }

        final bSpeed = bEdge.linkSpeedMbps;
        final cSpeed = cEdge.linkSpeedMbps;
        final speedDegraded =
            bSpeed != null && cSpeed != null && bSpeed > 0 && cSpeed > 0 && cSpeed < bSpeed;
        final duplexDegraded =
            bEdge.linkDuplex == DuplexMode.fullDuplex && cEdge.linkDuplex == DuplexMode.halfDuplex;

        if (speedDegraded || duplexDegraded) {
          if (!stpChanged) {
            edgeStatuses[cEdge.edgeId] = DiffChangeType.linkDegraded;
          }
          items.add(
            TopologyDiffItem(
              type: DiffChangeType.linkDegraded,
              targetId: cEdge.edgeId,
              title: 'Link Degraded: $edgeLabel',
              baselineValue: _formatLinkMetrics(bSpeed, bEdge.linkDuplex),
              currentValue: _formatLinkMetrics(cSpeed, cEdge.linkDuplex),
              isCritical: false,
              isEdge: true,
            ),
          );
        }

        if (!stpChanged && !speedDegraded && !duplexDegraded) {
          edgeStatuses[cEdge.edgeId] = DiffChangeType.unchanged;
        }
      } else {
        final ghostEdge = (mappedSrc == bEdge.sourceIp && mappedDst == bEdge.targetIp)
            ? bEdge
            : bEdge.copyWith(sourceIp: mappedSrc, targetIp: mappedDst);
        ghostEdges.add(ghostEdge);
        edgeStatuses[ghostEdge.edgeId] = DiffChangeType.missing;

        final srcLabel = _nodeLabel(
          currentNodes[mappedSrc] ?? baselineNodeById[bEdge.sourceIp],
          mappedSrc,
        );
        final dstLabel = _nodeLabel(
          currentNodes[mappedDst] ?? baselineNodeById[bEdge.targetIp],
          mappedDst,
        );

        items.add(
          TopologyDiffItem(
            type: DiffChangeType.missing,
            targetId: ghostEdge.edgeId,
            title: 'Missing Link: $srcLabel → $dstLabel',
            baselineValue: bEdge.stpState != LinkStpState.unknown
                ? 'Connected (${_stpStateLabel(bEdge.stpState)})'
                : 'Connected',
            currentValue: 'Link Missing / Down',
            isCritical: true,
            isEdge: true,
          ),
        );
      }
    }

    // Flag newly observed edges not present in baseline.
    for (final cEdge in currentEdges.values) {
      if (matchedCurrentEdgeIds.contains(cEdge.edgeId)) continue;
      if ((currentNodes[cEdge.sourceIp]?.isUnresponsive ?? false) ||
          (currentNodes[cEdge.targetIp]?.isUnresponsive ?? false)) {
        continue;
      }

      edgeStatuses[cEdge.edgeId] = DiffChangeType.added;
      final srcLabel = _nodeLabel(currentNodes[cEdge.sourceIp], cEdge.sourceIp);
      final dstLabel = _nodeLabel(currentNodes[cEdge.targetIp], cEdge.targetIp);

      items.add(
        TopologyDiffItem(
          type: DiffChangeType.added,
          targetId: cEdge.edgeId,
          title: 'New Link: $srcLabel → $dstLabel',
          baselineValue: 'Not in baseline',
          currentValue: cEdge.stpState != LinkStpState.unknown
              ? 'Connected (${_stpStateLabel(cEdge.stpState)})'
              : 'Connected',
          isCritical: false,
          isEdge: true,
        ),
      );
    }

    final orderedItems = <TopologyDiffItem>[
      ...items.where((i) => i.isCritical),
      ...items.where((i) => !i.isCritical),
    ];

    return TopologyDiffResult(
      items: orderedItems,
      nodeStatuses: nodeStatuses,
      edgeStatuses: edgeStatuses,
      ghostNodes: ghostNodes,
      ghostEdges: ghostEdges,
    );
  }

  static String? _normalizeMac(String? rawMac) {
    if (rawMac == null) return null;
    final trimmed = rawMac.trim();
    if (trimmed.isEmpty) return null;
    if (SharedDevice.isValidMac(trimmed)) {
      return SharedDevice.normalizeMac(trimmed);
    }
    final clean = trimmed.replaceAll(RegExp(r'[^0-9A-Fa-f]'), '');
    if (clean == '000000000000') return null;
    return trimmed.toUpperCase();
  }

  static bool _macsCompatible(String? bMac, String? cMac) {
    if (bMac == null || cMac == null) return true;
    return bMac == cMac;
  }

  static NetworkNode _pickBestCandidate(
    NetworkNode bNode,
    List<NetworkNode> candidates,
  ) {
    for (final c in candidates) {
      if (c.id == bNode.id) return c;
    }
    for (final c in candidates) {
      if (c.ip == bNode.ip) return c;
    }
    return candidates.first;
  }

  static bool _isUndirectedSwitchLink({
    required NetworkEdge bEdge,
    required NetworkEdge cEdge,
    NetworkNode? bSrc,
    NetworkNode? bDst,
    NetworkNode? cSrc,
    NetworkNode? cDst,
  }) {
    final srcIsSwitch = (bSrc?.isSwitch ?? false) || (cSrc?.isSwitch ?? false);
    final dstIsSwitch = (bDst?.isSwitch ?? false) || (cDst?.isSwitch ?? false);
    if (srcIsSwitch && dstIsSwitch) return true;
    return bEdge.stpState != LinkStpState.unknown || cEdge.stpState != LinkStpState.unknown;
  }

  static bool _isStpBlockingForwardingChange(LinkStpState a, LinkStpState b) {
    return (a == LinkStpState.blocking && b == LinkStpState.forwarding) ||
        (a == LinkStpState.forwarding && b == LinkStpState.blocking);
  }

  static String _nodeLabel(NetworkNode? node, String fallback) {
    if (node == null) return fallback;
    return node.displayName;
  }

  static String _formatStpRole(NetworkNode node) {
    final prio = node.stpPriority != null ? ' (Prio ${node.stpPriority})' : '';
    return node.isStpRootBridge ? 'STP Root Bridge$prio' : 'Non-Root$prio';
  }

  static String _formatIgmpRole(NetworkNode node) {
    if (!node.isIgmpQuerier) return 'Non-Querier';
    final ver = node.igmpQuerierVersion;
    return (ver != null && ver.isNotEmpty) ? 'Active Querier ($ver)' : 'Active Querier';
  }

  static String _stpStateLabel(LinkStpState state) {
    return switch (state) {
      LinkStpState.forwarding => 'Forwarding',
      LinkStpState.blocking => 'Blocking',
      LinkStpState.unknown => 'Unknown',
    };
  }

  static String _formatStpEdgeState(NetworkEdge edge) {
    final base = _stpStateLabel(edge.stpState);
    if (edge.stpState == LinkStpState.blocking &&
        edge.blockingPortName != null &&
        edge.blockingPortName!.isNotEmpty) {
      return '$base (${edge.blockingPortName})';
    }
    return base;
  }

  static String _formatLinkMetrics(int? speedMbps, DuplexMode duplex) {
    final speedPart = (speedMbps != null && speedMbps > 0) ? '$speedMbps Mbps' : 'Unknown speed';
    if (duplex != DuplexMode.unknown) {
      return '$speedPart (${duplex.label})';
    }
    return speedPart;
  }
}
