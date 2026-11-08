import 'dart:collection';
import 'package:flutter/material.dart';
import '../../domain/models/network_edge.dart';
import '../../domain/models/network_node.dart';
import '../../domain/models/trace_hop.dart';
import '../../domain/models/trace_result.dart';
import '../services/arp_service.dart';
import '../services/shared_device_service.dart';

class TopologyRepository {
  final Map<String, NetworkNode> _nodes = HashMap<String, NetworkNode>();
  final Map<String, NetworkEdge> _edges = HashMap<String, NetworkEdge>();
  final List<TraceResult> _traces = [];

  String _localHostIp = '127.0.0.1';
  String? _localHostMac;
  String? _localHostVendor;
  String? _localHostSharedName;
  String? _gatewayIp;
  String? _selectedNodeId;

  Map<String, NetworkNode> get nodes => UnmodifiableMapView(_nodes);
  Map<String, NetworkEdge> get edges => UnmodifiableMapView(_edges);
  List<TraceResult> get traces => List.unmodifiable(_traces);
  String get localHostIp => _localHostIp;
  String? get localHostMac => _localHostMac;
  String? get gatewayIp => _gatewayIp;
  String? get selectedNodeId => _selectedNodeId;
  NetworkNode? get selectedNode => _selectedNodeId != null ? _nodes[_selectedNodeId] : null;

  void setLocalHost(
    String ip, {
    String? gatewayIp,
    String? macAddress,
    String? vendor,
    String? sharedName,
  }) {
    final oldIp = _localHostIp;
    _localHostIp = ip;
    _gatewayIp = gatewayIp;
    if (macAddress != null && macAddress.isNotEmpty) _localHostMac = macAddress;
    if (vendor != null && vendor.isNotEmpty) _localHostVendor = vendor;
    if (sharedName != null && sharedName.isNotEmpty) _localHostSharedName = sharedName;

    // If host IP changed, remove the old host node so it doesn't linger as an orphan
    Set<String> associatedTargets = {};
    if (oldIp != ip && _nodes.containsKey(oldIp)) {
      final oldNode = _nodes.remove(oldIp);
      associatedTargets = oldNode?.associatedTargets ?? {};

      // Re-anchor any edges that originated from the old host IP
      final edgesToReanchor = _edges.entries.where((e) => e.value.sourceIp == oldIp).toList();
      for (final e in edgesToReanchor) {
        _edges.remove(e.key);
        final newKey = '$ip->${e.value.targetIp}';
        _edges[newKey] = NetworkEdge(
          sourceIp: ip,
          targetIp: e.value.targetIp,
          targetRoutes: e.value.targetRoutes,
        );
      }
    } else if (_nodes.containsKey(ip)) {
      associatedTargets = _nodes[ip]?.associatedTargets ?? {};
    }

    _nodes[ip] = NetworkNode(
      id: ip,
      ip: ip,
      hostname: 'Local PC (Host)',
      sharedDeviceName: _localHostSharedName,
      macAddress: _localHostMac,
      vendor: _localHostVendor,
      hopDepth: 0,
      isLocalHost: true,
      associatedTargets: associatedTargets,
    );
  }

  void clear() {
    _nodes.clear();
    _edges.clear();
    _traces.clear();
    _selectedNodeId = null;

    // Re-create root host node
    _nodes[_localHostIp] = NetworkNode(
      id: _localHostIp,
      ip: _localHostIp,
      hostname: 'Local PC (Host)',
      sharedDeviceName: _localHostSharedName,
      macAddress: _localHostMac,
      vendor: _localHostVendor,
      hopDepth: 0,
      isLocalHost: true,
      associatedTargets: {},
    );
  }

  void selectNode(String? nodeId) {
    _selectedNodeId = nodeId;
  }

  /// Ingests streamed partial hops for an in-flight trace.
  /// Chains nodes sequentially from previous hop without marking intermediate hops as targets.
  void ingestPartialHops(String targetIp, List<TraceHop> hops) {
    if (hops.isEmpty) return;
    var previousIp = _localHostIp;

    for (var i = 0; i < hops.length; i++) {
      final hop = hops[i];
      final hopId = hop.ip;

      // Skip self-loop if router repeated the same hop
      if (hopId == previousIp) continue;

      final existingNode = _nodes[hopId];
      if (existingNode == null) {
        _nodes[hopId] = NetworkNode(
          id: hopId,
          ip: hop.ip,
          hopDepth: hop.depth,
          isTarget: false, // Intermediate streaming hops are never marked as target
          isUnresponsive: hop.isTimeout,
          rttMs: hop.rttMs,
          associatedTargets: {targetIp},
        );
      } else {
        existingNode.associatedTargets.add(targetIp);
        var updated = existingNode;
        if (hop.rttMs != null && (updated.rttMs == null || hop.rttMs! < updated.rttMs!)) {
          updated = updated.copyWith(rttMs: hop.rttMs);
        }
        if (!hop.isTimeout && updated.isUnresponsive) {
          updated = updated.copyWith(isUnresponsive: false);
        }
        if (hop.depth < updated.hopDepth) {
          updated = updated.copyWith(hopDepth: hop.depth);
        }
        _nodes[hopId] = updated;
      }

      // Sequential edge: previousIp -> hopId
      final edgeKey = '$previousIp->$hopId';
      final existingEdge = _edges[edgeKey];
      if (existingEdge == null) {
        _edges[edgeKey] = NetworkEdge(
          sourceIp: previousIp,
          targetIp: hopId,
          targetRoutes: {targetIp},
        );
      } else {
        existingEdge.targetRoutes.add(targetIp);
      }

      previousIp = hopId;
    }

    _nodes[_localHostIp]?.associatedTargets.add(targetIp);
  }

  /// Ingests a new complete trace result into the DAG.
  void ingestTraceResult(TraceResult trace) {
    _traces.removeWhere((t) => t.targetIp == trace.targetIp);
    _traces.add(trace);

    var previousIp = _localHostIp;

    for (var i = 0; i < trace.hops.length; i++) {
      final hop = trace.hops[i];
      final isDestinationTarget = (i == trace.hops.length - 1) && (hop.ip == trace.targetIp);
      final hopId = hop.ip;

      // Prevent self-loops (e.g. repeated pmtu hops from tracepath)
      if (hopId == previousIp) continue;

      // 1. Register or update node
      final existingNode = _nodes[hopId];
      if (existingNode == null) {
        _nodes[hopId] = NetworkNode(
          id: hopId,
          ip: hop.ip,
          hopDepth: hop.depth,
          isTarget: isDestinationTarget,
          isUnresponsive: hop.isTimeout,
          rttMs: hop.rttMs,
          associatedTargets: {trace.targetIp},
        );
      } else {
        existingNode.associatedTargets.add(trace.targetIp);
        var updated = existingNode;
        if (isDestinationTarget && !updated.isTarget) {
          updated = updated.copyWith(isTarget: true);
        }
        if (hop.rttMs != null && (updated.rttMs == null || hop.rttMs! < updated.rttMs!)) {
          updated = updated.copyWith(rttMs: hop.rttMs);
        }
        if (!hop.isTimeout && updated.isUnresponsive) {
          updated = updated.copyWith(isUnresponsive: false);
        }
        if (hop.depth < updated.hopDepth) {
          updated = updated.copyWith(hopDepth: hop.depth);
        }
        _nodes[hopId] = updated;
      }

      // 2. Register or update edge
      final edgeKey = '$previousIp->$hopId';
      final existingEdge = _edges[edgeKey];
      if (existingEdge == null) {
        _edges[edgeKey] = NetworkEdge(
          sourceIp: previousIp,
          targetIp: hopId,
          targetRoutes: {trace.targetIp},
        );
      } else {
        existingEdge.targetRoutes.add(trace.targetIp);
      }

      previousIp = hopId;
    }

    // Add target to root local host targets set
    _nodes[_localHostIp]?.associatedTargets.add(trace.targetIp);
  }

  /// Updates node details with ARP cache information and Shared Device Database data.
  void enrichNodes({
    required Map<String, ArpDeviceEntry> arpCache,
    required SharedDeviceService sharedDeviceService,
  }) {
    for (final entry in _nodes.entries) {
      final ip = entry.key;
      var node = entry.value;

      // Skip local host or anonymous hops for ARP match
      if (node.isLocalHost || node.isUnresponsive) continue;

      // Match in ARP cache
      final arp = arpCache[ip];
      if (arp != null && node.macAddress == null) {
        node = node.copyWith(
          macAddress: arp.macAddress,
          vendor: arp.vendor,
        );
      }

      // Check Shared Device Database if MAC is present
      if (node.macAddress != null) {
        final resolved = sharedDeviceService.resolveDeviceInfo(node.macAddress!);
        if (resolved != null) {
          node = node.copyWith(
            sharedDeviceName: resolved.friendlyName,
            deviceCategoryKey: resolved.categoryKey,
            customCategoryColor: resolved.categoryColor,
            customCategoryIcon: resolved.categoryIcon,
            sharedNotes: resolved.device.notes,
          );
        }
      }

      _nodes[ip] = node;
    }
  }

  /// Updates a single node's reverse-DNS hostname.
  void updateNodeHostname(String ip, String hostname) {
    final node = _nodes[ip];
    if (node != null && (node.hostname == null || node.hostname!.isEmpty)) {
      _nodes[ip] = node.copyWith(hostname: hostname);
    }
  }

  /// Updates node metadata directly when edited in the UI.
  void updateNodeSharedMetadata(
    String ip, {
    String? name,
    String? category,
    Color? categoryColor,
    IconData? categoryIcon,
    String? notes,
    String? macAddress,
    String? vendor,
  }) {
    final node = _nodes[ip];
    if (node != null) {
      _nodes[ip] = node.copyWith(
        sharedDeviceName: name,
        deviceCategoryKey: category,
        customCategoryColor: categoryColor,
        customCategoryIcon: categoryIcon,
        sharedNotes: notes,
        macAddress: macAddress ?? node.macAddress,
        vendor: vendor ?? node.vendor,
      );
    }
  }

  /// Returns the set of node IDs involved in the active highlighted path.
  Set<String> getActivePathNodeIds() {
    if (_selectedNodeId == null) return const {};
    final selected = _nodes[_selectedNodeId];
    if (selected == null) return const {};

    final activeNodes = <String>{_selectedNodeId!};

    // If selected is a target or intermediate node, find upstream path back to host
    _collectUpstreamNodes(_selectedNodeId!, activeNodes);

    // If selected is an intermediate node traversed by targets, also include downstream edges/nodes for those targets
    for (final targetIp in selected.associatedTargets) {
      activeNodes.add(targetIp);
    }

    return activeNodes;
  }

  /// Returns all upstream node IDs reaching back to local host for a given node.
  Set<String> getUpstreamNodeIds(String nodeId) {
    final collected = <String>{};
    _collectUpstreamNodes(nodeId, collected);
    return collected;
  }

  /// Returns all downstream target node IDs traversed through a given node.
  Set<String> getDownstreamNodeIds(String nodeId) {
    final collected = <String>{};
    final node = _nodes[nodeId];
    if (node != null) {
      for (final targetIp in node.associatedTargets) {
        collected.add(targetIp);
      }
    }
    return collected;
  }

  void _collectUpstreamNodes(String currentId, Set<String> collected) {
    if (currentId == _localHostIp) return;
    for (final edge in _edges.values) {
      if (edge.targetIp == currentId) {
        if (collected.add(edge.sourceIp)) {
          _collectUpstreamNodes(edge.sourceIp, collected);
        }
      }
    }
  }

  /// Returns the set of edge IDs (`source->target`) on the active highlighted route.
  Set<String> getActivePathEdgeIds() {
    if (_selectedNodeId == null) return const {};
    final activeNodeIds = getActivePathNodeIds();
    final activeEdges = <String>{};

    for (final edge in _edges.values) {
      if (activeNodeIds.contains(edge.sourceIp) && activeNodeIds.contains(edge.targetIp)) {
        activeEdges.add(edge.edgeId);
      }
    }

    return activeEdges;
  }

  /// Returns an ordered step-by-step breadcrumb chain from Local Host to the target:
  /// `[Local PC, Gateway, Distribution Switch, Target]`
  List<NetworkNode> getPathBreadcrumbs(String targetId) {
    if (!_nodes.containsKey(targetId)) return const [];
    if (targetId == _localHostIp) return [_nodes[_localHostIp]!];

    // Find the trace that matches targetId if it's a target
    final matchingTrace = _traces.where((t) => t.targetIp == targetId).firstOrNull;
    if (matchingTrace != null) {
      final list = <NetworkNode>[];
      if (_nodes.containsKey(_localHostIp)) {
        list.add(_nodes[_localHostIp]!);
      }
      for (final hop in matchingTrace.hops) {
        final node = _nodes[hop.ip];
        if (node != null && !list.contains(node)) {
          list.add(node);
        }
      }
      return list;
    }

    // Otherwise reconstruct shortest path from root via edges
    final path = <String>[];
    String current = targetId;
    path.add(current);

    while (current != _localHostIp) {
      String? parent;
      for (final edge in _edges.values) {
        if (edge.targetIp == current) {
          parent = edge.sourceIp;
          break;
        }
      }
      if (parent == null || path.contains(parent)) break;
      path.add(parent);
      current = parent;
    }

    final reversed = path.reversed.toList();
    return reversed.map((id) => _nodes[id]).whereType<NetworkNode>().toList();
  }
}
