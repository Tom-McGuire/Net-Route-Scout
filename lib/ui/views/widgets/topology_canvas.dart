import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'package:net_route_scout/core/app_theme.dart';
import 'package:net_route_scout/domain/models/network_edge.dart';
import 'package:net_route_scout/domain/models/network_node.dart';
import 'package:net_route_scout/ui/view_models/topology_view_model.dart';
import 'package:provider/provider.dart';
import 'node_card_widget.dart';

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
    final hasSelection = selectedNodeId != null;

    if (nodes.isEmpty) {
      return _buildEmptyState(context, vm);
    }

    // 1. Group nodes by layer/depth
    final layers = <int, List<NetworkNode>>{};
    for (final node in nodes.values) {
      final depth = node.hopDepth;
      layers.putIfAbsent(depth, () => []).add(node);
    }

    final sortedDepths = layers.keys.toList()..sort();

    // 2. Compute (x, y) coordinates for each node
    final nodePositions = <String, Offset>{};
    var maxDepth = 0;
    var maxNodesInLayer = 0;

    for (final depth in sortedDepths) {
      final list = layers[depth]!;
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
                    hasSelection: hasSelection,
                    cardWidth: cardWidth,
                    cardHeight: cardHeight,
                  ),
                ),

                // Node Cards
                for (final node in nodes.values) ...[
                  if (nodePositions.containsKey(node.id))
                    Positioned(
                      left: nodePositions[node.id]!.dx,
                      top: nodePositions[node.id]!.dy,
                      child: NodeCardWidget(
                        node: node,
                        isSelected: selectedNodeId == node.id,
                        isOnActivePath: activeNodeIds.contains(node.id),
                        isDimmed: hasSelection && !activeNodeIds.contains(node.id),
                        onTap: () {
                          if (selectedNodeId == node.id) {
                            vm.clearSelection();
                          } else {
                            vm.selectNode(node.id);
                          }
                        },
                      ),
                    ),
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
                border: Border.all(color: AppTheme.activeHighlight.withValues(alpha: 0.6)),
                boxShadow: [
                  BoxShadow(
                    color: AppTheme.activeHighlight.withValues(alpha: 0.2),
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
                    decoration: const BoxDecoration(
                      color: AppTheme.activeHighlight,
                      shape: BoxShape.circle,
                    ),
                  ),
                  const SizedBox(width: 8),
                  Text(
                    'Active Path Highlight: ${vm.selectedNode?.displayName ?? ""}',
                    style: const TextStyle(
                      fontSize: 11,
                      fontWeight: FontWeight.bold,
                      color: Colors.white,
                    ),
                  ),
                  const SizedBox(width: 8),
                  InkWell(
                    onTap: vm.clearSelection,
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
  final bool hasSelection;
  final double cardWidth;
  final double cardHeight;

  _TopologyEdgesPainter({
    required this.edges,
    required this.nodePositions,
    required this.activeEdgeIds,
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

      final isActive = activeEdgeIds.contains(edge.edgeId);
      final isDimmed = hasSelection && !isActive;

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

      if (isActive) {
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
