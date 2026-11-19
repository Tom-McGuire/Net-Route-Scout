import 'dart:collection';
import 'dart:math' as math;
import 'package:material_ui/material_ui.dart';
import '../../domain/models/interface_health_stats.dart';
import '../../domain/models/network_edge.dart';
import '../../domain/models/network_node.dart';
import '../../domain/models/port_vlan_config.dart';
import '../../domain/models/stp_port_info.dart';
import '../../domain/models/switch_discovery_info.dart';
import '../../domain/models/trace_hop.dart';
import '../../domain/models/trace_result.dart';
import '../services/arp_service.dart';
import '../services/shared_device_service.dart';

class TopologyRepository {
  final Map<String, NetworkNode> _nodes = HashMap<String, NetworkNode>();
  final Map<String, NetworkEdge> _edges = HashMap<String, NetworkEdge>();
  final List<TraceResult> _traces = [];

  // Custom Switch State & Overrides
  final Set<String> _customSwitchNodeIds = <String>{};
  final Map<String, String> _customSwitchLinks = <String, String>{}; // childNodeId -> parentSwitchId
  final Map<String, String> _customSwitchPorts = <String, String>{}; // childNodeId -> portLabel

  String _localHostIp = '127.0.0.1';
  String? _localHostMac;
  String? _localHostVendor;
  String? _localHostSharedName;
  String? _gatewayIp;
  String? _selectedNodeId;

  Map<String, NetworkNode> get nodes => UnmodifiableMapView(_nodes);
  Map<String, NetworkEdge> get edges => UnmodifiableMapView(_edges);
  List<TraceResult> get traces => List.unmodifiable(_traces);
  Set<String> get customSwitchNodeIds => UnmodifiableSetView(_customSwitchNodeIds);
  Map<String, String> get customSwitchLinks => UnmodifiableMapView(_customSwitchLinks);
  Map<String, String> get customSwitchPorts => UnmodifiableMapView(_customSwitchPorts);
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

    // Ensure custom switch edges remain applied over incoming trace hops
    if (_customSwitchLinks.isNotEmpty) {
      reapplyCustomSwitchEdges();
    }
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
          final isSwitchCat = resolved.categoryKey == 'switch';
          if (isSwitchCat) {
            _customSwitchNodeIds.add(node.id);
          }
          node = node.copyWith(
            sharedDeviceName: resolved.friendlyName,
            deviceCategoryKey: resolved.categoryKey,
            isSwitchNode: isSwitchCat ? true : node.isSwitchNode,
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

  // ==========================================
  // SWITCH TOPOLOGY MANIPULATION & REDRAW
  // ==========================================

  void restoreCustomSwitches({
    required Set<String> switchNodeIds,
    required Map<String, String> switchLinks,
    required Map<String, String> switchPorts,
  }) {
    _customSwitchNodeIds.clear();
    _customSwitchNodeIds.addAll(switchNodeIds);
    _customSwitchLinks.clear();
    _customSwitchLinks.addAll(switchLinks);
    _customSwitchPorts.clear();
    _customSwitchPorts.addAll(switchPorts);

    // Apply isSwitchNode and ports to existing nodes
    for (final id in _customSwitchNodeIds) {
      final node = _nodes[id];
      if (node != null) {
        _nodes[id] = node.copyWith(isSwitchNode: true, deviceCategoryKey: 'switch');
      }
    }

    for (final entry in _customSwitchLinks.entries) {
      final childId = entry.key;
      final switchId = entry.value;
      final node = _nodes[childId];
      if (node != null) {
        _nodes[childId] = node.copyWith(
          connectedSwitchId: switchId,
          switchPort: _customSwitchPorts[childId],
        );
      }
    }

    reapplyCustomSwitchEdges();
  }

  void defineNodeAsSwitch(String nodeId, {bool isSwitch = true, String? name}) {
    final node = _nodes[nodeId];
    if (node == null) return;

    if (isSwitch) {
      _customSwitchNodeIds.add(nodeId);
      _nodes[nodeId] = node.copyWith(
        isSwitchNode: true,
        deviceCategoryKey: 'switch',
        sharedDeviceName: name ?? node.sharedDeviceName,
      );
    } else {
      _customSwitchNodeIds.remove(nodeId);
      // Disconnect any children that were attached to this switch
      final childrenToDisconnect = _customSwitchLinks.entries
          .where((e) => e.value == nodeId)
          .map((e) => e.key)
          .toList();
      for (final childId in childrenToDisconnect) {
        disconnectNodeFromSwitch(childId);
      }
      _nodes[nodeId] = node.copyWith(
        isSwitchNode: false,
        deviceCategoryKey: node.deviceCategoryKey == 'switch' ? 'other' : node.deviceCategoryKey,
      );
    }

    reapplyCustomSwitchEdges();
  }

  NetworkNode addStandaloneSwitch({
    required String name,
    String? ip,
    String? mac,
    String? model,
    String? upstreamNodeId,
  }) {
    final switchId = ip ?? 'switch_${DateTime.now().millisecondsSinceEpoch}';
    final switchIp = ip ?? switchId;

    final switchNode = NetworkNode(
      id: switchId,
      ip: switchIp,
      hostname: model ?? name,
      sharedDeviceName: name,
      macAddress: mac,
      vendor: model,
      hopDepth: 2,
      isSwitchNode: true,
      deviceCategoryKey: 'switch',
      switchModel: model,
      associatedTargets: {},
    );

    _nodes[switchId] = switchNode;
    _customSwitchNodeIds.add(switchId);

    // Determine upstream anchor
    final upstream = upstreamNodeId ?? (_gatewayIp != null && _nodes.containsKey(_gatewayIp) ? _gatewayIp! : _localHostIp);
    _edges['$upstream->$switchId'] = NetworkEdge(
      sourceIp: upstream,
      targetIp: switchId,
      targetRoutes: {},
    );

    reapplyCustomSwitchEdges();
    return switchNode;
  }

  void connectNodeToSwitch(String childNodeId, String switchNodeId, {String? portLabel}) {
    if (!_nodes.containsKey(childNodeId) || !_nodes.containsKey(switchNodeId)) return;
    if (childNodeId == switchNodeId) return; // Prevent self-loop

    _customSwitchLinks[childNodeId] = switchNodeId;
    if (portLabel != null && portLabel.isNotEmpty) {
      _customSwitchPorts[childNodeId] = portLabel;
    } else {
      _customSwitchPorts.remove(childNodeId);
    }

    final child = _nodes[childNodeId]!;
    _nodes[childNodeId] = child.copyWith(
      connectedSwitchId: switchNodeId,
      switchPort: portLabel,
    );

    reapplyCustomSwitchEdges();
  }

  void disconnectNodeFromSwitch(String childNodeId) {
    _customSwitchLinks.remove(childNodeId);
    _customSwitchPorts.remove(childNodeId);

    final child = _nodes[childNodeId];
    if (child != null) {
      _nodes[childNodeId] = child.copyWith(
        clearConnectedSwitch: true,
        clearSwitchPort: true,
      );
    }

    // Reconstruct default traceroute edge for childNodeId
    _rebuildDefaultInboundEdge(childNodeId);
    reapplyCustomSwitchEdges();
  }

  void _rebuildDefaultInboundEdge(String targetId) {
    // Remove existing inbound edges to targetId
    _edges.removeWhere((_, e) => e.targetIp == targetId);

    // Try finding predecessor from traces
    for (final trace in _traces) {
      var prev = _localHostIp;
      for (final hop in trace.hops) {
        if (hop.ip == targetId) {
          _edges['$prev->$targetId'] = NetworkEdge(
            sourceIp: prev,
            targetIp: targetId,
            targetRoutes: {trace.targetIp},
          );
          return;
        }
        prev = hop.ip;
      }
    }

    // Fallback: connect to gateway or host
    final fallback = (_gatewayIp != null && _nodes.containsKey(_gatewayIp)) ? _gatewayIp! : _localHostIp;
    if (targetId != fallback) {
      _edges['$fallback->$targetId'] = NetworkEdge(
        sourceIp: fallback,
        targetIp: targetId,
        targetRoutes: {targetId},
      );
    }
  }

  void reapplyCustomSwitchEdges() {
    for (final entry in _customSwitchLinks.entries) {
      final childId = entry.key;
      final switchId = entry.value;

      if (!_nodes.containsKey(childId) || !_nodes.containsKey(switchId)) continue;

      // Ensure switch has an upstream connection if orphan
      if (!_edges.values.any((e) => e.targetIp == switchId) && switchId != _localHostIp) {
        final upstream = (_gatewayIp != null && _nodes.containsKey(_gatewayIp) && _gatewayIp != switchId)
            ? _gatewayIp!
            : _localHostIp;
        _edges['$upstream->$switchId'] = NetworkEdge(
          sourceIp: upstream,
          targetIp: switchId,
          targetRoutes: {},
        );
      }

      // Collect existing target routes of child
      final existingRoutes = <String>{childId};
      final oldInbounds = _edges.entries.where((e) => e.value.targetIp == childId).toList();
      for (final e in oldInbounds) {
        existingRoutes.addAll(e.value.targetRoutes);
        _edges.remove(e.key);
      }

      // Add edge switchId -> childId
      _edges['$switchId->$childId'] = NetworkEdge(
        sourceIp: switchId,
        targetIp: childId,
        targetRoutes: existingRoutes,
      );

      // Propagate target route upwards
      var curr = switchId;
      while (curr != _localHostIp) {
        String? parent;
        for (final edge in _edges.values) {
          if (edge.targetIp == curr) {
            edge.targetRoutes.addAll(existingRoutes);
            parent = edge.sourceIp;
            break;
          }
        }
        if (parent == null || parent == curr) break;
        curr = parent;
      }
    }
  }

  /// Calculates dynamic topological depths so parent nodes always render
  /// to the left of their child nodes in the visual layout.
  Map<String, int> computeTopologicalDepths() {
    final depths = <String, int>{};
    if (_nodes.containsKey(_localHostIp)) {
      depths[_localHostIp] = 0;
    }

    // Multi-pass longest-path calculation for DAG
    bool changed = true;
    int iterations = 0;
    const maxIterations = 50;

    while (changed && iterations < maxIterations) {
      changed = false;
      iterations++;

      for (final edge in _edges.values) {
        final srcDepth = depths[edge.sourceIp] ?? (_nodes[edge.sourceIp]?.hopDepth ?? 0);
        final currentTargetDepth = depths[edge.targetIp];
        final newTargetDepth = srcDepth + 1;

        if (currentTargetDepth == null || newTargetDepth > currentTargetDepth) {
          depths[edge.targetIp] = newTargetDepth;
          changed = true;
        }
      }
    }

    // For any unvisited nodes, fallback to their default hopDepth
    for (final node in _nodes.values) {
      depths.putIfAbsent(node.id, () => node.hopDepth);
    }

    return depths;
  }

  int getEffectiveDepth(String nodeId) {
    final allDepths = computeTopologicalDepths();
    return allDepths[nodeId] ?? (_nodes[nodeId]?.hopDepth ?? 1);
  }

  // ==========================================
  // STP RING & IGMP QUERIER CORRELATION
  // ==========================================

  void updateNodeDirect(NetworkNode updatedNode) {
    _nodes[updatedNode.id] = updatedNode;
  }

  void updateEdgeDirect(NetworkEdge updatedEdge) {
    _edges[updatedEdge.edgeId] = updatedEdge;
  }

  /// Applies BRIDGE-MIB STP, IGMP, Q-BRIDGE-MIB VLAN, IF-MIB health, and PoE
  /// telemetry discovered via SNMP to [switchNodeId] and correlates edges.
  void applyStpAndIgmpFromSnmp(String switchNodeId, SwitchDiscoveryResult result) {
    final node = _nodes[switchNodeId];
    if (node == null) return;

    final isLocalQuerier = result.igmpVlans.any((v) => v.isLocalSwitchQuerier);
    final querierVer = result.igmpVlans.isNotEmpty
        ? 'IGMPv${result.igmpVlans.first.igmpVersion}'
        : node.igmpQuerierVersion;

    // Compute delta counters against previous poll sample for InterfaceHealthStats
    final mergedHealth = <InterfaceHealthStats>[];
    if (result.interfaceHealth.isNotEmpty) {
      final prevByIdx = {for (final h in node.interfaceHealth) h.ifIndex: h};
      for (final h in result.interfaceHealth) {
        mergedHealth.add(h.withPreviousSample(prevByIdx[h.ifIndex]));
      }
    } else {
      mergedHealth.addAll(node.interfaceHealth);
    }

    _nodes[switchNodeId] = node.copyWith(
      isStpRootBridge: result.isStpRootBridge || node.isStpRootBridge,
      stpPriority: result.stpPriority ?? node.stpPriority,
      stpBridgeId: result.stpBridgeMac != null
          ? '${result.stpPriority ?? 32768} / ${result.stpBridgeMac}'
          : node.stpBridgeId,
      stpDesignatedRootId: result.stpDesignatedRootId ?? node.stpDesignatedRootId,
      stpRootCost: result.stpRootCost ?? node.stpRootCost,
      stpPorts: result.stpPorts.isNotEmpty ? result.stpPorts : node.stpPorts,
      igmpSnoopingEnabled: result.igmpSnoopingEnabled || node.igmpSnoopingEnabled,
      igmpVlans: result.igmpVlans.isNotEmpty ? result.igmpVlans : node.igmpVlans,
      isIgmpQuerier: isLocalQuerier || node.isIgmpQuerier,
      igmpQuerierVersion: isLocalQuerier ? querierVer : node.igmpQuerierVersion,
      vlanNames: result.vlanNames.isNotEmpty ? result.vlanNames : node.vlanNames,
      portVlans: result.portVlans.isNotEmpty ? result.portVlans : node.portVlans,
      interfaceHealth: mergedHealth,
      poeStatus: result.poeStatus ?? node.poeStatus,
    );

    // Cross-correlate active Querier IP with any other switch/host node
    for (final vlan in result.igmpVlans) {
      final qIp = vlan.activeQuerierIp;
      if (qIp != null && _nodes.containsKey(qIp)) {
        final qNode = _nodes[qIp]!;
        _nodes[qIp] = qNode.copyWith(
          isIgmpQuerier: true,
          igmpQuerierVersion: 'IGMPv${vlan.igmpVersion}',
        );
      }
    }

    correlateStpEdges();
  }

  /// Correlates passive 4s STP BPDU Root Bridge MAC with discovered nodes.
  bool applyPassiveStpRoot(StpPassiveResult result) {
    final targetMac = result.rootBridgeMac.toUpperCase();
    bool matched = false;

    for (final entry in _nodes.entries) {
      final node = entry.value;
      final nodeMac = node.macAddress?.toUpperCase();
      final matchesBridgeId = node.stpBridgeId?.toUpperCase().contains(targetMac) ?? false;

      if (nodeMac == targetMac || matchesBridgeId) {
        _nodes[entry.key] = node.copyWith(
          isStpRootBridge: true,
          stpPriority: result.rootPriority ?? node.stpPriority,
        );
        matched = true;
      } else if (node.isStpRootBridge) {
        // Clear stale root flag if a different Root Bridge MAC was newly observed
        _nodes[entry.key] = node.copyWith(isStpRootBridge: false);
      }
    }
    return matched;
  }

  /// Correlates passive ~130s IGMP General Query IP with discovered nodes.
  bool applyPassiveIgmpQuerier(IgmpPassiveResult result) {
    final targetIp = result.querierIp.trim();
    bool matched = false;

    for (final entry in _nodes.entries) {
      final node = entry.value;
      if (node.ip == targetIp) {
        _nodes[entry.key] = node.copyWith(
          isIgmpQuerier: true,
          igmpQuerierVersion: result.igmpVersion,
        );
        matched = true;
      } else if (node.isIgmpQuerier) {
        _nodes[entry.key] = node.copyWith(isIgmpQuerier: false);
      }
    }
    return matched;
  }

  StpPortInfo? _findStpPort(NetworkNode node, String? portName) {
    if (node.stpPorts.isEmpty || portName == null || portName.isEmpty) return null;
    final norm = portName.toLowerCase();
    for (final p in node.stpPorts) {
      if (p.interfaceName.toLowerCase() == norm) {
        return p;
      }
    }
    for (final p in node.stpPorts) {
      final pNorm = p.interfaceName.toLowerCase();
      if (pNorm.isNotEmpty && (norm.contains(pNorm) || pNorm.contains(norm))) {
        return p;
      }
    }
    return null;
  }

  /// Links two switches discovered via LLDP/CDP without inverting existing
  /// upstream hierarchy or deleting peer ring edges.
  void linkSwitchNeighbor({
    required String switchId,
    required String neighborId,
    required String localPort,
    required String remotePort,
  }) {
    if (!_nodes.containsKey(switchId) || !_nodes.containsKey(neighborId)) return;
    if (switchId == neighborId) return;

    final isAncestorOrShallower =
        getUpstreamNodeIds(switchId).contains(neighborId) ||
        getEffectiveDepth(neighborId) < getEffectiveDepth(switchId);

    if (isAncestorOrShallower) {
      final existingKey = '$neighborId->$switchId';
      final existing = _edges[existingKey];
      _edges[existingKey] = existing != null
          ? existing.copyWith(sourcePortName: remotePort, targetPortName: localPort)
          : NetworkEdge(
              sourceIp: neighborId,
              targetIp: switchId,
              sourcePortName: remotePort,
              targetPortName: localPort,
            );
    } else if (_edges.containsKey('$switchId->$neighborId')) {
      final edgeKey = '$switchId->$neighborId';
      _edges[edgeKey] = _edges[edgeKey]!.copyWith(
        sourcePortName: localPort,
        targetPortName: remotePort,
      );
    } else if (_edges.values.any((e) =>
        e.targetIp == neighborId &&
        e.sourceIp != _localHostIp &&
        e.sourceIp != _gatewayIp)) {
      final edgeKey = '$switchId->$neighborId';
      _edges[edgeKey] = NetworkEdge(
        sourceIp: switchId,
        targetIp: neighborId,
        sourcePortName: localPort,
        targetPortName: remotePort,
      );
    } else {
      connectNodeToSwitch(neighborId, switchId, portLabel: localPort);
      final edgeKey = '$switchId->$neighborId';
      final edge = _edges[edgeKey];
      if (edge != null) {
        _edges[edgeKey] = edge.copyWith(
          sourcePortName: localPort,
          targetPortName: remotePort,
        );
      }
    }

    correlateStpEdges();
  }

  /// Evaluates switch-to-switch edges against STP port states to mark
  /// blocking ring splits and forwarding traffic directions.
  void correlateStpEdges() {
    final switchEdgeCounts = <String, int>{};
    for (final edge in _edges.values) {
      final srcNode = _nodes[edge.sourceIp];
      final dstNode = _nodes[edge.targetIp];
      if (srcNode == null || dstNode == null) continue;
      if (!srcNode.isSwitch || !dstNode.isSwitch) continue;
      switchEdgeCounts[srcNode.id] = (switchEdgeCounts[srcNode.id] ?? 0) + 1;
      switchEdgeCounts[dstNode.id] = (switchEdgeCounts[dstNode.id] ?? 0) + 1;
    }

    for (final edgeKey in _edges.keys.toList()) {
      final edge = _edges[edgeKey]!;
      final srcNode = _nodes[edge.sourceIp];
      final dstNode = _nodes[edge.targetIp];
      if (srcNode == null || dstNode == null) continue;
      if (!srcNode.isSwitch || !dstNode.isSwitch) continue;

      final srcPortHint = edge.sourcePortName ??
          (dstNode.connectedSwitchId == srcNode.id ? dstNode.switchPort : null);
      final dstPortHint = edge.targetPortName ??
          edge.blockingPortName ??
          (dstNode.connectedSwitchId == srcNode.id ? dstNode.switchPort : null);

      final dstStp = _findStpPort(dstNode, dstPortHint);
      final srcStp = _findStpPort(srcNode, srcPortHint);

      StpPortInfo? blockingPort;
      String? blockingSwitchId;

      if (dstStp != null && dstStp.isBlocking) {
        blockingPort = dstStp;
        blockingSwitchId = dstNode.id;
      } else if (srcStp != null && srcStp.isBlocking) {
        blockingPort = srcStp;
        blockingSwitchId = srcNode.id;
      } else if (edge.sourcePortName == null &&
          edge.targetPortName == null &&
          edge.blockingPortName == null) {
        if ((switchEdgeCounts[dstNode.id] ?? 0) <= 1) {
          for (final p in dstNode.stpPorts) {
            if (p.isBlocking) {
              blockingPort = p;
              blockingSwitchId = dstNode.id;
              break;
            }
          }
        }
        if (blockingPort == null && (switchEdgeCounts[srcNode.id] ?? 0) <= 1) {
          for (final p in srcNode.stpPorts) {
            if (p.isBlocking) {
              blockingPort = p;
              blockingSwitchId = srcNode.id;
              break;
            }
          }
        }
      }

      if (blockingPort != null) {
        _edges[edgeKey] = edge.copyWith(
          stpState: LinkStpState.blocking,
          blockingSwitchId: blockingSwitchId,
          blockingPortName: blockingPort.interfaceName,
        );
      } else if ((dstStp?.isForwarding ?? false) ||
          (srcStp?.isForwarding ?? false) ||
          ((dstStp == null && srcStp == null) &&
              (dstNode.stpPorts.isNotEmpty || srcNode.stpPorts.isNotEmpty))) {
        final srcCost = srcNode.stpRootCost ?? 0;
        final dstCost = dstNode.stpRootCost ?? 1;
        _edges[edgeKey] = edge.copyWith(
          stpState: LinkStpState.forwarding,
          trafficDirectionTargetNodeId: srcCost <= dstCost ? dstNode.id : srcNode.id,
        );
      }
    }

    correlateSwitchEdges();
  }

  /// Compares two trunk port VLAN configs for native PVID or allowed VLAN mismatches.
  static VlanMismatchReport compareTrunkPortVlans(
    PortVlanConfig portA,
    PortVlanConfig portB,
  ) {
    final nativeMismatch = portA.nativePvid != portB.nativePvid;
    final missingOnB = portA.allowedVlans.difference(portB.allowedVlans);
    final missingOnA = portB.allowedVlans.difference(portA.allowedVlans);
    return VlanMismatchReport(
      hasNativeVlanMismatch: nativeMismatch,
      sideANativeVlan: portA.nativePvid,
      sideBNativeVlan: portB.nativePvid,
      missingOnSideA: missingOnA,
      missingOnSideB: missingOnB,
      sideAPortName: portA.interfaceName,
      sideBPortName: portB.interfaceName,
    );
  }

  PortVlanConfig? _findPortVlan(NetworkNode node, String? portName, {bool fallbackTrunk = false}) {
    if (node.portVlans.isEmpty) return null;
    if (portName != null && portName.isNotEmpty) {
      final norm = portName.toLowerCase();
      for (final p in node.portVlans) {
        if (p.interfaceName.toLowerCase() == norm || norm.contains(p.interfaceName.toLowerCase())) {
          return p;
        }
      }
    }
    if (fallbackTrunk) {
      return node.portVlans.where((p) => p.isTrunk).firstOrNull;
    }
    return null;
  }

  InterfaceHealthStats? _findPortHealth(NetworkNode node, String? portName) {
    if (node.interfaceHealth.isEmpty || portName == null || portName.isEmpty) return null;
    final norm = portName.toLowerCase();
    for (final h in node.interfaceHealth) {
      if (h.interfaceName.toLowerCase() == norm || norm.contains(h.interfaceName.toLowerCase())) {
        return h;
      }
    }
    return null;
  }

  /// Correlates VLAN trunk mismatches and interface speed/duplex/errors onto switch edges.
  void correlateSwitchEdges() {
    for (final edgeKey in _edges.keys.toList()) {
      var edge = _edges[edgeKey]!;
      final srcNode = _nodes[edge.sourceIp];
      final dstNode = _nodes[edge.targetIp];
      if (srcNode == null || dstNode == null) continue;
      if (!srcNode.isSwitch || !dstNode.isSwitch) continue;

      final srcPortName = edge.sourcePortName ?? dstNode.switchPort;
      final dstPortName = edge.targetPortName ?? edge.blockingPortName;

      // 1. VLAN trunk mismatch correlation (only when both sides have matching port configs)
      final portA = _findPortVlan(srcNode, srcPortName, fallbackTrunk: srcNode.portVlans.length == 1);
      final portB = _findPortVlan(dstNode, dstPortName, fallbackTrunk: dstNode.portVlans.length == 1);
      VlanMismatchReport? report = edge.vlanMismatch;
      if (portA != null && portB != null) {
        report = compareTrunkPortVlans(portA, portB);
      }

      // 2. Link speed, duplex & error delta correlation
      final healthA = _findPortHealth(srcNode, srcPortName);
      final healthB = _findPortHealth(dstNode, dstPortName);

      int? effectiveSpeed = edge.linkSpeedMbps;
      if (healthA != null && healthB != null && healthA.speedMbps > 0 && healthB.speedMbps > 0) {
        effectiveSpeed = math.min(healthA.speedMbps, healthB.speedMbps);
      } else if (healthA != null && healthA.speedMbps > 0) {
        effectiveSpeed = healthA.speedMbps;
      } else if (healthB != null && healthB.speedMbps > 0) {
        effectiveSpeed = healthB.speedMbps;
      }

      DuplexMode duplex = edge.linkDuplex;
      if (healthA?.duplex == DuplexMode.halfDuplex || healthB?.duplex == DuplexMode.halfDuplex) {
        duplex = DuplexMode.halfDuplex;
      } else if (healthA?.duplex == DuplexMode.fullDuplex || healthB?.duplex == DuplexMode.fullDuplex) {
        duplex = DuplexMode.fullDuplex;
      }

      final inErrDelta = (healthA?.inErrorsDelta ?? 0) + (healthB?.inErrorsDelta ?? 0);
      final outDiscDelta = (healthA?.outDiscardsDelta ?? 0) + (healthB?.outDiscardsDelta ?? 0);

      _edges[edgeKey] = edge.copyWith(
        sourcePortName: srcPortName ?? edge.sourcePortName,
        targetPortName: dstPortName ?? edge.targetPortName,
        vlanMismatch: report,
        linkSpeedMbps: effectiveSpeed,
        linkDuplex: duplex,
        inErrorsDelta: inErrDelta > 0 ? inErrDelta : edge.inErrorsDelta,
        outDiscardsDelta: outDiscDelta > 0 ? outDiscDelta : edge.outDiscardsDelta,
      );
    }
  }
}
