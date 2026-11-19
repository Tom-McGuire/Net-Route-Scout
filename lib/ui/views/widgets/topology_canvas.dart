import 'dart:math' as math;
import 'package:material_ui/material_ui.dart';
import 'package:net_route_scout/core/app_theme.dart';
import 'package:net_route_scout/data/services/icmp_service.dart';
import 'package:net_route_scout/domain/models/network_edge.dart';
import 'package:net_route_scout/domain/models/network_node.dart';
import 'package:net_route_scout/domain/models/topology_diff_result.dart';
import 'package:net_route_scout/ui/view_models/topology_view_model.dart';
import 'package:provider/provider.dart';
import 'node_card_widget.dart';
import 'node_context_menu.dart';

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
    final diffResult = vm.activeDiffResult;
    final nodes = <String, NetworkNode>{
      ...vm.nodes,
      if (diffResult != null)
        for (final g in diffResult.ghostNodes) g.id: g,
    };
    final edges = <String, NetworkEdge>{
      ...vm.edges,
      if (diffResult != null)
        for (final g in diffResult.ghostEdges) g.edgeId: g,
    };
    final selectedNodeId = vm.selectedNodeId;
    final activeNodeIds = vm.activePathNodeIds;
    final activeEdgeIds = vm.activePathEdgeIds;
    final hasDeviceFilter = vm.selectedDeviceKeys.isNotEmpty;
    final hasSelection = selectedNodeId != null || hasDeviceFilter;

    if (nodes.isEmpty) {
      return _buildEmptyState(context, vm);
    }

    // 1. Group nodes by layer/depth using a single memoized topological depth pass (I2)
    final effectiveDepths = vm.getEffectiveNodeDepths();
    final layers = <int, List<NetworkNode>>{};
    for (final node in nodes.values) {
      final isGhost = diffResult?.nodeStatuses[node.id] == DiffChangeType.missing;
      final depth = isGhost ? node.hopDepth : (effectiveDepths[node.id] ?? node.hopDepth);
      layers.putIfAbsent(depth, () => []).add(node);
    }

    final parentsByTarget = <String, Set<String>>{};
    for (final edge in edges.values) {
      parentsByTarget.putIfAbsent(edge.targetIp, () => <String>{}).add(edge.sourceIp);
    }

    final sortedDepths = layers.keys.toList()..sort();

    final hasSearch = vm.searchQuery.trim().isNotEmpty;
    final matchingNodeIds = hasSearch ? vm.filteredNodes.map((n) => n.id).toSet() : const <String>{};

    // 2. Compute (x, y) coordinates using parent-barycenter + numerical IPv4 ordering (I3)
    final nodePositions = <String, Offset>{};
    var maxDepth = 0;
    var maxNodesInLayer = 0;

    double? parentBarycenter(String nodeId) {
      final parents = parentsByTarget[nodeId];
      if (parents == null || parents.isEmpty) return null;
      double sum = 0;
      int count = 0;
      for (final pId in parents) {
        final pos = nodePositions[pId];
        if (pos != null) {
          sum += pos.dy;
          count++;
        }
      }
      return count > 0 ? sum / count : null;
    }

    int compareIpOrId(NetworkNode a, NetworkNode b) {
      if (IcmpService.isValidIpv4(a.ip) && IcmpService.isValidIpv4(b.ip)) {
        final cmp = IcmpService.ipv4ToInt(a.ip).compareTo(IcmpService.ipv4ToInt(b.ip));
        if (cmp != 0) return cmp;
      }
      return a.ip.compareTo(b.ip);
    }

    for (final depth in sortedDepths) {
      final list = layers[depth]!;
      list.sort((a, b) {
        if (a.isLocalHost) return -1;
        if (b.isLocalHost) return 1;
        final baryA = parentBarycenter(a.id);
        final baryB = parentBarycenter(b.id);
        if (baryA != null && baryB != null) {
          final diff = baryA.compareTo(baryB);
          if (diff != 0) return diff;
        } else if (baryA != null) {
          return -1;
        } else if (baryB != null) {
          return 1;
        }
        return compareIpOrId(a, b);
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
                    edgeDiffStatuses: diffResult?.edgeStatuses ?? const {},
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
                      final diffStatus = diffResult?.nodeStatuses[node.id];
                      final isBaselineDimmed = diffResult != null &&
                          diffResult.hasDrift &&
                          (diffStatus == null || diffStatus == DiffChangeType.unchanged);

                      return Positioned(
                        left: nodePositions[node.id]!.dx,
                        top: nodePositions[node.id]!.dy,
                        child: NodeCardWidget(
                          node: node,
                          isSelected: selectedNodeId == node.id,
                          isOnActivePath: activeNodeIds.contains(node.id),
                          isDimmed: isDimmedBySelection || isDimmedBySearch,
                          isBaselineDimmed: isBaselineDimmed,
                          isSearchMatch: isSearchMatch,
                          diffStatus: diffStatus,
                          onTap: () {
                            if (selectedNodeId == node.id) {
                              vm.clearSelection();
                            } else {
                              vm.selectNode(node.id);
                            }
                          },
                          onSecondaryTapUp: (details) {
                            showNodeActionsContextMenu(context, vm, node, details.globalPosition);
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
  final Map<String, DiffChangeType> edgeDiffStatuses;
  final bool hasSelection;
  final double cardWidth;
  final double cardHeight;

  _TopologyEdgesPainter({
    required this.edges,
    required this.nodePositions,
    required this.activeEdgeIds,
    this.commonEdgeIds = const {},
    this.edgeDiffStatuses = const {},
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

      final isMissingDiff = edgeDiffStatuses[edge.edgeId] == DiffChangeType.missing;
      final reverseFlow = edge.trafficDirectionTargetNodeId == edge.sourceIp;

      if (isMissingDiff || edge.stpState == LinkStpState.blocking) {
        // STP Ring Split or Missing Baseline Edge: dashed crimson/amber line with midpoint pill
        const splitColor = Color(0xFFEF4444);
        paint
          ..color = isDimmed ? splitColor.withValues(alpha: 0.25) : splitColor.withValues(alpha: 0.85)
          ..strokeWidth = 2.2;

        _drawDashedPath(canvas, path, paint, dashWidth: 7, dashSpace: 5);
      } else if (edge.hasActiveErrors || edge.isDegradedSpeed || edge.isHalfDuplex || edge.hasVlanMismatch) {
        // Amber/warning edge highlight for degraded trunk speed, CRC errors, or VLAN mismatch
        const warnColor = Color(0xFFF59E0B);
        paint
          ..color = isDimmed ? warnColor.withValues(alpha: 0.25) : warnColor.withValues(alpha: 0.9)
          ..strokeWidth = isDimmed ? 1.5 : 2.6;

        if (!isDimmed && edge.hasActiveErrors) {
          final pulsePaint = Paint()
            ..style = PaintingStyle.stroke
            ..color = warnColor.withValues(alpha: 0.45)
            ..strokeWidth = 7.0
            ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 4.0);
          canvas.drawPath(path, pulsePaint);
        }
        canvas.drawPath(path, paint);
        if (!isDimmed) {
          _drawEdgeFlowDecoration(canvas, start, end, warnColor, 7.5, 2.5, reverse: reverseFlow);
        }
      } else if (isCommon) {
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

        _drawEdgeFlowDecoration(canvas, start, end, amberColor, 9.0, 3.0, reverse: reverseFlow);
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

        _drawEdgeFlowDecoration(canvas, start, end, AppTheme.activeHighlight, 8.0, 2.5, reverse: reverseFlow);
      } else {
        paint
          ..color = isDimmed
              ? const Color(0xFF2E3440).withValues(alpha: 0.3)
              : const Color(0xFF38BDF8).withValues(alpha: 0.4)
          ..strokeWidth = isDimmed ? 1.0 : 1.5;

        canvas.drawPath(path, paint);
        if (!isDimmed) {
          _drawEdgeFlowDecoration(
            canvas,
            start,
            end,
            const Color(0xFF38BDF8).withValues(alpha: 0.6),
            6.5,
            2.0,
            reverse: reverseFlow,
          );
        }
      }

      if (!isDimmed) {
        final midPoint = _getCurveMidpoint(start, controlPoint1, controlPoint2, end);
        final badges = <({String text, Color textColor, Color bg, Color border})>[];
        if (isMissingDiff) {
          badges.add((
            text: 'MISSING LINK',
            textColor: const Color(0xFFFCA5A5),
            bg: const Color(0xFF1F1418),
            border: const Color(0xFFEF4444).withValues(alpha: 0.85),
          ));
        }
        if (edge.stpState == LinkStpState.blocking) {
          badges.add((
            text: '✂ STP SPLIT (BLK)',
            textColor: const Color(0xFFFCA5A5),
            bg: const Color(0xFF1F1418),
            border: const Color(0xFFEF4444).withValues(alpha: 0.85),
          ));
        }
        if (edge.hasVlanMismatch) {
          badges.add((
            text: '⚠ VLAN MISMATCH',
            textColor: const Color(0xFFFDE68A),
            bg: const Color(0xFF231C10),
            border: const Color(0xFFF59E0B).withValues(alpha: 0.85),
          ));
        }
        final speedLabel = edge.speedBadgeLabel;
        if (speedLabel != null) {
          final isWarnSpeed = edge.isDegradedSpeed || edge.isHalfDuplex || edge.hasActiveErrors;
          final errSuffix = edge.hasActiveErrors ? ' (+${edge.inErrorsDelta} ERR)' : '';
          badges.add((
            text: '$speedLabel$errSuffix',
            textColor: isWarnSpeed ? const Color(0xFFFDE68A) : const Color(0xFF6EE7B7),
            bg: isWarnSpeed ? const Color(0xFF231C10) : const Color(0xFF0F201B),
            border: (isWarnSpeed ? const Color(0xFFF59E0B) : const Color(0xFF10B981)).withValues(alpha: 0.7),
          ));
        }

        if (badges.isNotEmpty) {
          const stepY = 18.0;
          final startY = midPoint.dy - ((badges.length - 1) * stepY) / 2;
          for (var i = 0; i < badges.length; i++) {
            final b = badges[i];
            _drawEdgeBadge(
              canvas,
              Offset(midPoint.dx, startY + i * stepY),
              b.text,
              textColor: b.textColor,
              bgColor: b.bg,
              borderColor: b.border,
            );
          }
        }
      }
    }
  }

  void _drawEdgeFlowDecoration(
    Canvas canvas,
    Offset start,
    Offset end,
    Color color,
    double arrowSize,
    double dotRadius, {
    bool reverse = false,
  }) {
    final dotPaint = Paint()
      ..color = color
      ..style = PaintingStyle.fill;
    canvas.drawCircle(reverse ? end : start, dotRadius, dotPaint);
    _drawHorizontalArrowhead(
      canvas,
      reverse ? start : end,
      color,
      arrowSize,
      pointLeft: reverse,
    );
  }

  void _drawHorizontalArrowhead(
    Canvas canvas,
    Offset tip,
    Color color,
    double arrowSize, {
    bool pointLeft = false,
  }) {
    final arrowPaint = Paint()
      ..color = color
      ..style = PaintingStyle.fill;

    final dir = pointLeft ? 1.0 : -1.0;
    final path = Path();
    path.moveTo(tip.dx, tip.dy);
    path.lineTo(tip.dx + dir * arrowSize, tip.dy - (arrowSize * 0.5));
    path.lineTo(tip.dx + dir * (arrowSize * 0.7), tip.dy);
    path.lineTo(tip.dx + dir * arrowSize, tip.dy + (arrowSize * 0.5));
    path.close();

    canvas.drawPath(path, arrowPaint);
  }

  void _drawDashedPath(Canvas canvas, Path path, Paint paint, {double dashWidth = 6, double dashSpace = 4}) {
    for (final metric in path.computeMetrics()) {
      double distance = 0;
      while (distance < metric.length) {
        final next = math.min(distance + dashWidth, metric.length);
        canvas.drawPath(metric.extractPath(distance, next), paint);
        distance += dashWidth + dashSpace;
      }
    }
  }

  Offset _getCurveMidpoint(Offset p0, Offset p1, Offset p2, Offset p3) {
    const t = 0.5;
    const u = 1.0 - t;
    final x = u * u * u * p0.dx + 3 * u * u * t * p1.dx + 3 * u * t * t * p2.dx + t * t * t * p3.dx;
    final y = u * u * u * p0.dy + 3 * u * u * t * p1.dy + 3 * u * t * t * p2.dy + t * t * t * p3.dy;
    return Offset(x, y);
  }

  void _drawEdgeBadge(
    Canvas canvas,
    Offset center,
    String text, {
    required Color textColor,
    required Color bgColor,
    required Color borderColor,
  }) {
    final textPainter = TextPainter(
      text: TextSpan(
        text: text,
        style: TextStyle(
          fontSize: 8.5,
          fontWeight: FontWeight.bold,
          color: textColor,
          letterSpacing: 0.35,
        ),
      ),
      textDirection: TextDirection.ltr,
    )..layout();

    const padH = 6.0;
    const padV = 2.5;
    final rect = RRect.fromRectAndRadius(
      Rect.fromCenter(
        center: center,
        width: textPainter.width + padH * 2,
        height: textPainter.height + padV * 2,
      ),
      const Radius.circular(4),
    );

    canvas.drawRRect(rect, Paint()..color = bgColor);
    canvas.drawRRect(
      rect,
      Paint()
        ..color = borderColor
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1.0,
    );

    textPainter.paint(
      canvas,
      Offset(center.dx - textPainter.width / 2, center.dy - textPainter.height / 2),
    );
  }

  @override
  bool shouldRepaint(covariant _TopologyEdgesPainter oldDelegate) {
    return oldDelegate.edges != edges ||
        oldDelegate.hasSelection != hasSelection ||
        oldDelegate.activeEdgeIds != activeEdgeIds ||
        oldDelegate.edgeDiffStatuses != edgeDiffStatuses;
  }
}
