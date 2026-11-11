import 'dart:math' as math;
import 'package:material_ui/material_ui.dart';
import 'package:flutter/services.dart';
import 'package:net_route_scout/core/app_theme.dart';
import 'package:net_route_scout/domain/models/network_edge.dart';
import 'package:net_route_scout/domain/models/network_node.dart';
import 'package:net_route_scout/ui/view_models/topology_view_model.dart';
import 'package:provider/provider.dart';
import 'connect_switch_dialog.dart';
import 'edit_device_dialog.dart';
import 'node_card_widget.dart';
import 'snmp_discovery_dialog.dart';

class TopologyCanvas extends StatefulWidget {
  const TopologyCanvas({super.key});

  @override
  State<TopologyCanvas> createState() => _TopologyCanvasState();
}

class _TopologyCanvasState extends State<TopologyCanvas> {
  final TransformationController _transformController = TransformationController();

  static const double cardWidth = 220.0;
  static const double cardHeight = 96.0;
  static const double layerSpacingX = 310.0;
  static const double nodeSpacingY = 130.0;
  static const double paddingX = 60.0;
  static const double paddingY = 60.0;

  void _zoomIn() {
    final matrix = _transformController.value.clone();
    matrix.scaleByDouble(1.25, 1.25, 1.0, 1.0);
    _transformController.value = matrix;
  }

  void _zoomOut() {
    final matrix = _transformController.value.clone();
    matrix.scaleByDouble(0.8, 0.8, 1.0, 1.0);
    _transformController.value = matrix;
  }

  void _resetZoom() {
    _transformController.value = Matrix4.identity();
  }

  void _showNodeContextMenu(
    BuildContext context,
    TopologyViewModel vm,
    NetworkNode node,
    Offset globalPosition,
  ) {
    final subnet = vm.deriveSubnetForNode(node);
    final hasValidSubnet = subnet.isNotEmpty;

    final overlay = Overlay.of(context).context.findRenderObject() as RenderBox?;
    final position = RelativeRect.fromRect(
      Rect.fromLTWH(globalPosition.dx, globalPosition.dy, 1, 1),
      Offset.zero & (overlay?.size ?? const Size(1920, 1080)),
    );

    showMenu<String>(
      context: context,
      position: position,
      color: AppTheme.surfaceContainerHigh,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(8),
        side: const BorderSide(color: AppTheme.border),
      ),
      items: [
        if (hasValidSubnet)
          PopupMenuItem<String>(
            value: 'scan_arp',
            child: Row(
              children: [
                const Icon(Icons.radar, size: 16, color: AppTheme.primaryAccent),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(
                    'Scan Subnet with ARP Scout ($subnet)',
                    style: const TextStyle(fontSize: 12.5, color: Colors.white),
                  ),
                ),
              ],
            ),
          ),
        PopupMenuItem<String>(
          value: 'select_path',
          child: Row(
            children: [
              const Icon(Icons.alt_route, size: 16, color: AppTheme.activeHighlight),
              const SizedBox(width: 10),
              Text(
                vm.selectedNodeId == node.id ? 'Deselect Node' : 'Focus / Select Node Path',
                style: const TextStyle(fontSize: 12.5, color: Colors.white),
              ),
            ],
          ),
        ),
        if (!node.isLocalHost) ...[
          if (!node.isSwitch)
            const PopupMenuItem<String>(
              value: 'define_switch',
              child: Row(
                children: [
                  Icon(Icons.hub, size: 16, color: Color(0xFF06B6D4)),
                  SizedBox(width: 10),
                  Text(
                    'Define as Switch Node',
                    style: TextStyle(fontSize: 12.5, color: Colors.white),
                  ),
                ],
              ),
            )
          else ...[
            const PopupMenuItem<String>(
              value: 'revert_switch',
              child: Row(
                children: [
                  Icon(Icons.undo, size: 16, color: Colors.white70),
                  SizedBox(width: 10),
                  Text(
                    'Revert to Standard Node',
                    style: TextStyle(fontSize: 12.5, color: Colors.white),
                  ),
                ],
              ),
            ),
            if (!node.isUnresponsive)
              const PopupMenuItem<String>(
                value: 'query_snmp',
                child: Row(
                  children: [
                    Icon(Icons.sensors, size: 16, color: Color(0xFF06B6D4)),
                    SizedBox(width: 10),
                    Text(
                      'Query Switch via SNMP...',
                      style: TextStyle(fontSize: 12.5, color: Colors.white),
                    ),
                  ],
                ),
              ),
          ],
          PopupMenuItem<String>(
            value: 'connect_switch',
            child: Row(
              children: [
                const Icon(Icons.cable, size: 16, color: Color(0xFF06B6D4)),
                const SizedBox(width: 10),
                Text(
                  node.connectedSwitchId != null ? 'Change Connected Switch...' : 'Connect to Switch...',
                  style: const TextStyle(fontSize: 12.5, color: Colors.white),
                ),
              ],
            ),
          ),
          if (node.connectedSwitchId != null)
            const PopupMenuItem<String>(
              value: 'disconnect_switch',
              child: Row(
                children: [
                  Icon(Icons.link_off, size: 16, color: Colors.redAccent),
                  SizedBox(width: 10),
                  Text(
                    'Disconnect from Switch',
                    style: TextStyle(fontSize: 12.5, color: Colors.redAccent),
                  ),
                ],
              ),
            ),
        ],
        PopupMenuItem<String>(
          value: 'edit_shared',
          child: const Row(
            children: [
              Icon(Icons.edit, size: 16, color: Colors.white70),
              SizedBox(width: 10),
              Text(
                'Edit Shared Device Identity',
                style: TextStyle(fontSize: 12.5, color: Colors.white),
              ),
            ],
          ),
        ),
        if (!node.isUnresponsive)
          PopupMenuItem<String>(
            value: 'copy_ip',
            child: const Row(
              children: [
                Icon(Icons.copy, size: 16, color: Colors.white70),
                SizedBox(width: 10),
                Text(
                  'Copy IP Address',
                  style: TextStyle(fontSize: 12.5, color: Colors.white),
                ),
              ],
            ),
          ),
      ],
    ).then((choice) {
      if (!context.mounted || choice == null) return;
      switch (choice) {
        case 'scan_arp':
          vm.launchArpScoutForNode(context, node);
          break;
        case 'select_path':
          if (vm.selectedNodeId == node.id) {
            vm.clearSelection();
          } else {
            vm.selectNode(node.id);
          }
          break;
        case 'define_switch':
          vm.defineNodeAsSwitch(node.id, isSwitch: true);
          break;
        case 'revert_switch':
          vm.defineNodeAsSwitch(node.id, isSwitch: false);
          break;
        case 'connect_switch':
          ConnectSwitchDialog.show(context, vm, node);
          break;
        case 'disconnect_switch':
          vm.disconnectNodeFromSwitch(node.id);
          break;
        case 'query_snmp':
          SnmpDiscoveryDialog.show(context, vm, node: node);
          break;
        case 'edit_shared':
          showDialog(
            context: context,
            builder: (ctx) => EditDeviceDialog(
              node: node,
              onSave: vm.updateDeviceDetails,
            ),
          );
          break;
        case 'copy_ip':
          Clipboard.setData(ClipboardData(text: node.ip));
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text('Copied ${node.ip} to clipboard'),
              duration: const Duration(seconds: 2),
            ),
          );
          break;
      }
    });
  }

  @override
  void dispose() {
    _transformController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final vm = context.watch<TopologyViewModel>();
    final nodes = vm.nodes;
    final edges = vm.edges;
    final selectedNodeId = vm.selectedNodeId;
    final activeNodeIds = vm.activePathNodeIds;
    final activeEdgeIds = vm.activePathEdgeIds;
    final hasDeviceFilter = vm.selectedDeviceKeys.isNotEmpty;
    final hasSelection = selectedNodeId != null || hasDeviceFilter;

    if (nodes.isEmpty) {
      return _buildEmptyState(context, vm);
    }

    // 1. Group nodes by layer/depth using dynamic topological depth
    final layers = <int, List<NetworkNode>>{};
    for (final node in nodes.values) {
      final depth = vm.getEffectiveNodeDepth(node.id);
      layers.putIfAbsent(depth, () => []).add(node);
    }

    final sortedDepths = layers.keys.toList()..sort();

    final hasSearch = vm.searchQuery.trim().isNotEmpty;
    final matchingNodeIds = hasSearch ? vm.filteredNodes.map((n) => n.id).toSet() : const <String>{};

    // 2. Compute (x, y) coordinates for each node with stable deterministic ordering
    final nodePositions = <String, Offset>{};
    var maxDepth = 0;
    var maxNodesInLayer = 0;

    for (final depth in sortedDepths) {
      final list = layers[depth]!;
      // Sort deterministically to prevent cards jumping around when HashMap rehashes
      list.sort((a, b) {
        if (a.isLocalHost) return -1;
        if (b.isLocalHost) return 1;
        return a.ip.compareTo(b.ip);
      });

      if (depth > maxDepth) maxDepth = depth;
      if (list.length > maxNodesInLayer) maxNodesInLayer = list.length;

      final x = paddingX + (depth * layerSpacingX);

      for (var i = 0; i < list.length; i++) {
        final node = list[i];
        final y = paddingY + (i * nodeSpacingY);
        nodePositions[node.id] = Offset(x, y);
      }
    }

    final canvasWidth = math.max(1200.0, paddingX * 2 + (maxDepth + 1) * layerSpacingX);
    final canvasHeight = math.max(700.0, paddingY * 2 + maxNodesInLayer * nodeSpacingY + 100);

    return Stack(
      children: [
        // Interactive Canvas with Pan & Zoom
        InteractiveViewer(
          transformationController: _transformController,
          constrained: false,
          boundaryMargin: const EdgeInsets.all(800),
          minScale: 0.1,
          maxScale: 3.5,
          child: Container(
            width: canvasWidth,
            height: canvasHeight,
            color: AppTheme.windowBg,
            child: Stack(
              clipBehavior: Clip.none,
              children: [
                // Background subtle dot grid
                CustomPaint(
                  size: Size(canvasWidth, canvasHeight),
                  painter: _GridBackgroundPainter(),
                ),

                // Connecting Edges (Bezier curves with arrows)
                CustomPaint(
                  size: Size(canvasWidth, canvasHeight),
                  painter: _TopologyEdgesPainter(
                    edges: edges.values.toList(),
                    nodePositions: nodePositions,
                    activeEdgeIds: activeEdgeIds,
                    commonEdgeIds: vm.commonPathEdgeIds,
                    hasSelection: hasSelection,
                    cardWidth: cardWidth,
                    cardHeight: cardHeight,
                  ),
                ),

                // Node Cards
                for (final node in nodes.values) ...[
                  if (nodePositions.containsKey(node.id)) ...[
                    Builder(builder: (context) {
                      final isSearchMatch = hasSearch && matchingNodeIds.contains(node.id);
                      final isDimmedBySearch = hasSearch && !isSearchMatch;
                      final isDimmedBySelection = hasSelection && !activeNodeIds.contains(node.id);

                      return Positioned(
                        left: nodePositions[node.id]!.dx,
                        top: nodePositions[node.id]!.dy,
                        child: NodeCardWidget(
                          node: node,
                          isSelected: selectedNodeId == node.id,
                          isOnActivePath: activeNodeIds.contains(node.id),
                          isDimmed: isDimmedBySelection || isDimmedBySearch,
                          isSearchMatch: isSearchMatch,
                          onTap: () {
                            if (selectedNodeId == node.id) {
                              vm.clearSelection();
                            } else {
                              vm.selectNode(node.id);
                            }
                          },
                          onSecondaryTapUp: (details) {
                            _showNodeContextMenu(context, vm, node, details.globalPosition);
                          },
                        ),
                      );
                    }),
                  ],
                ],
              ],
            ),
          ),
        ),

        // Floating Viewport Controls (Bottom Right)
        Positioned(
          right: 20,
          bottom: 20,
          child: Container(
            decoration: BoxDecoration(
              color: AppTheme.surfaceContainerHighest.withValues(alpha: 0.9),
              borderRadius: BorderRadius.circular(8),
              border: Border.all(color: AppTheme.border),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withValues(alpha: 0.4),
                  blurRadius: 8,
                ),
              ],
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                IconButton(
                  onPressed: _zoomIn,
                  icon: const Icon(Icons.add, size: 18),
                  tooltip: 'Zoom In',
                  splashRadius: 18,
                ),
                const Divider(height: 1),
                IconButton(
                  onPressed: _zoomOut,
                  icon: const Icon(Icons.remove, size: 18),
                  tooltip: 'Zoom Out',
                  splashRadius: 18,
                ),
                const Divider(height: 1),
                IconButton(
                  onPressed: _resetZoom,
                  icon: const Icon(Icons.center_focus_strong, size: 18),
                  tooltip: 'Reset Fit',
                  splashRadius: 18,
                ),
              ],
            ),
          ),
        ),

        // Path Highlight Legend Indicator (Top Left when active)
        if (hasSelection)
          Positioned(
            left: 20,
            top: 20,
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
              decoration: BoxDecoration(
                color: AppTheme.surfaceContainer.withValues(alpha: 0.95),
                borderRadius: BorderRadius.circular(6),
                border: Border.all(
                  color: hasDeviceFilter
                      ? const Color(0xFFF59E0B).withValues(alpha: 0.7)
                      : AppTheme.activeHighlight.withValues(alpha: 0.6),
                ),
                boxShadow: [
                  BoxShadow(
                    color: (hasDeviceFilter ? const Color(0xFFF59E0B) : AppTheme.activeHighlight)
                        .withValues(alpha: 0.2),
                    blurRadius: 8,
                  ),
                ],
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Container(
                    width: 8,
                    height: 8,
                    decoration: BoxDecoration(
                      color: hasDeviceFilter ? const Color(0xFFF59E0B) : AppTheme.activeHighlight,
                      shape: BoxShape.circle,
                    ),
                  ),
                  const SizedBox(width: 8),
                  Text(
                    hasDeviceFilter
                        ? (vm.selectedDeviceKeys.length >= 2
                            ? 'Multi-Device Filter (${vm.selectedDeviceKeys.length} devices) • Common Path: ${vm.commonPathNodeIds.length} hops'
                            : 'Device Path Filter (${vm.selectedDeviceKeys.length} selected)')
                        : 'Active Path Highlight: ${vm.selectedNode?.displayName ?? ""}',
                    style: const TextStyle(
                      fontSize: 11,
                      fontWeight: FontWeight.bold,
                      color: Colors.white,
                    ),
                  ),
                  const SizedBox(width: 8),
                  InkWell(
                    onTap: hasDeviceFilter ? vm.clearDeviceFilters : vm.clearSelection,
                    child: const Icon(Icons.close, size: 14, color: Colors.white54),
                  ),
                ],
              ),
            ),
          ),
      ],
    );
  }

  Widget _buildEmptyState(BuildContext context, TopologyViewModel vm) {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            padding: const EdgeInsets.all(20),
            decoration: BoxDecoration(
              color: AppTheme.primaryAccent.withValues(alpha: 0.1),
              shape: BoxShape.circle,
            ),
            child: const Icon(
              Icons.radar,
              size: 56,
              color: AppTheme.primaryAccent,
            ),
          ),
          const SizedBox(height: 18),
          const Text(
            'No Network Routes Traced',
            style: TextStyle(
              fontSize: 18,
              fontWeight: FontWeight.bold,
              color: Colors.white,
            ),
          ),
          const SizedBox(height: 8),
          const Text(
            'Enter a CIDR subnet (e.g. 192.168.1.0/24) or target IP above and click Start Sweep,\nor load the demo enterprise network.',
            textAlign: TextAlign.center,
            style: TextStyle(
              fontSize: 12,
              color: Colors.white60,
              height: 1.4,
            ),
          ),
          const SizedBox(height: 20),
          Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              FilledButton.icon(
                onPressed: vm.loadDemoTopology,
                icon: const Icon(Icons.auto_awesome, size: 16),
                label: const Text('Load Demo Enterprise Network'),
                style: FilledButton.styleFrom(
                  backgroundColor: AppTheme.primaryAccent,
                  padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _GridBackgroundPainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = const Color(0xFF22262E)
      ..strokeWidth = 1.0;

    const step = 40.0;
    for (double x = 0; x < size.width; x += step) {
      for (double y = 0; y < size.height; y += step) {
        canvas.drawCircle(Offset(x, y), 0.8, paint);
      }
    }
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}

class _TopologyEdgesPainter extends CustomPainter {
  final List<NetworkEdge> edges;
  final Map<String, Offset> nodePositions;
  final Set<String> activeEdgeIds;
  final Set<String> commonEdgeIds;
  final bool hasSelection;
  final double cardWidth;
  final double cardHeight;

  _TopologyEdgesPainter({
    required this.edges,
    required this.nodePositions,
    required this.activeEdgeIds,
    this.commonEdgeIds = const {},
    required this.hasSelection,
    required this.cardWidth,
    required this.cardHeight,
  });

  @override
  void paint(Canvas canvas, Size size) {
    for (final edge in edges) {
      final startPos = nodePositions[edge.sourceIp];
      final endPos = nodePositions[edge.targetIp];
      if (startPos == null || endPos == null) continue;

      // Exact center of right edge of source card
      final start = Offset(startPos.dx + cardWidth, startPos.dy + (cardHeight / 2));
      // Exact center of left edge of target card
      final end = Offset(endPos.dx, endPos.dy + (cardHeight / 2));

      final isCommon = commonEdgeIds.contains(edge.edgeId);
      final isActive = activeEdgeIds.contains(edge.edgeId);
      final isDimmed = hasSelection && !isActive && !isCommon;

      final dx = end.dx - start.dx;
      // Tangents are strictly horizontal at start and end points for smooth edge-to-edge alignment
      final controlPoint1 = Offset(start.dx + dx * 0.45, start.dy);
      final controlPoint2 = Offset(end.dx - dx * 0.45, end.dy);

      final path = Path();
      path.moveTo(start.dx, start.dy);
      path.cubicTo(
        controlPoint1.dx,
        controlPoint1.dy,
        controlPoint2.dx,
        controlPoint2.dy,
        end.dx,
        end.dy,
      );

      final paint = Paint()
        ..style = PaintingStyle.stroke
        ..strokeCap = StrokeCap.round;

      if (isCommon) {
        // Glowing prominent common network path edge (Amber)
        const amberColor = Color(0xFFF59E0B);
        paint
          ..color = amberColor
          ..strokeWidth = 3.4;

        final glowPaint = Paint()
          ..style = PaintingStyle.stroke
          ..color = amberColor.withValues(alpha: 0.5)
          ..strokeWidth = 8.0
          ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 5.0);

        canvas.drawPath(path, glowPaint);
        canvas.drawPath(path, paint);

        final dotPaint = Paint()
          ..color = amberColor
          ..style = PaintingStyle.fill;
        canvas.drawCircle(start, 3.0, dotPaint);

        _drawHorizontalArrowhead(canvas, end, amberColor, 9.0);
      } else if (isActive) {
        // Glowing active edge
        paint
          ..color = AppTheme.activeHighlight
          ..strokeWidth = 2.8;

        final glowPaint = Paint()
          ..style = PaintingStyle.stroke
          ..color = AppTheme.activeHighlight.withValues(alpha: 0.4)
          ..strokeWidth = 6.0
          ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 4.0);

        canvas.drawPath(path, glowPaint);
        canvas.drawPath(path, paint);

        // Source anchor dot
        final dotPaint = Paint()
          ..color = AppTheme.activeHighlight
          ..style = PaintingStyle.fill;
        canvas.drawCircle(start, 2.5, dotPaint);

        _drawHorizontalArrowhead(canvas, end, AppTheme.activeHighlight, 8.0);
      } else {
        paint
          ..color = isDimmed
              ? const Color(0xFF2E3440).withValues(alpha: 0.3)
              : const Color(0xFF38BDF8).withValues(alpha: 0.4)
          ..strokeWidth = isDimmed ? 1.0 : 1.5;

        canvas.drawPath(path, paint);
        if (!isDimmed) {
          final dotPaint = Paint()
            ..color = const Color(0xFF38BDF8).withValues(alpha: 0.5)
            ..style = PaintingStyle.fill;
          canvas.drawCircle(start, 2.0, dotPaint);

          _drawHorizontalArrowhead(canvas, end, const Color(0xFF38BDF8).withValues(alpha: 0.6), 6.5);
        }
      }
    }
  }

  void _drawHorizontalArrowhead(Canvas canvas, Offset tip, Color color, double arrowSize) {
    final arrowPaint = Paint()
      ..color = color
      ..style = PaintingStyle.fill;

    final path = Path();
    path.moveTo(tip.dx, tip.dy);
    path.lineTo(tip.dx - arrowSize, tip.dy - (arrowSize * 0.5));
    path.lineTo(tip.dx - (arrowSize * 0.7), tip.dy);
    path.lineTo(tip.dx - arrowSize, tip.dy + (arrowSize * 0.5));
    path.close();

    canvas.drawPath(path, arrowPaint);
  }

  @override
  bool shouldRepaint(covariant _TopologyEdgesPainter oldDelegate) {
    return oldDelegate.edges != edges ||
        oldDelegate.hasSelection != hasSelection ||
        oldDelegate.activeEdgeIds != activeEdgeIds;
  }
}
