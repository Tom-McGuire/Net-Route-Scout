import 'package:material_ui/material_ui.dart';
import 'package:net_route_scout/core/app_theme.dart';
import 'package:net_route_scout/domain/models/network_node.dart';
import 'package:net_route_scout/domain/models/switch_poe_status.dart';
import 'package:net_route_scout/domain/models/topology_diff_result.dart';

class NodeCardWidget extends StatelessWidget {
  final NetworkNode node;
  final bool isSelected;
  final bool isOnActivePath;
  final bool isDimmed;
  final bool isBaselineDimmed;
  final bool isSearchMatch;
  final DiffChangeType? diffStatus;
  final VoidCallback onTap;
  final void Function(TapUpDetails details)? onSecondaryTapUp;

  const NodeCardWidget({
    super.key,
    required this.node,
    required this.isSelected,
    required this.isOnActivePath,
    required this.isDimmed,
    this.isBaselineDimmed = false,
    this.isSearchMatch = false,
    this.diffStatus,
    required this.onTap,
    this.onSecondaryTapUp,
  });

  @override
  Widget build(BuildContext context) {
    final themeColor = _getNodeColor(node);
    final badgeLabel = _getNodeBadgeLabel(node);
    final iconData = _getNodeIcon(node);
    final displayIp = (node.isUnresponsive || node.ip.startsWith('anon:')) ? 'Anon-Hop-${node.hopDepth}' : node.ip;

    final isGhostMissing = diffStatus == DiffChangeType.missing;
    final borderColor = isGhostMissing
        ? AppTheme.error
        : diffStatus == DiffChangeType.added
            ? AppTheme.success
            : (diffStatus == DiffChangeType.roleChanged ||
                    diffStatus == DiffChangeType.stpStateChanged ||
                    diffStatus == DiffChangeType.linkDegraded)
                ? AppTheme.warning
                : isSelected || isOnActivePath
                    ? AppTheme.activeHighlight
                    : isSearchMatch
                        ? AppTheme.warning
                        : themeColor.withValues(alpha: node.isUnresponsive ? 0.3 : 0.6);

    final borderWidth = isSelected ? 2.5 : ((isOnActivePath || isSearchMatch || isGhostMissing) ? 2.0 : 1.2);

    return AnimatedOpacity(
      duration: const Duration(milliseconds: 200),
      opacity: isGhostMissing
          ? 0.55
          : (isDimmed ? 0.15 : (isBaselineDimmed ? 0.75 : 1.0)),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: onTap,
          onSecondaryTapUp: onSecondaryTapUp,
          borderRadius: BorderRadius.circular(8),
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 180),
            width: 220,
            height: 96,
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
            decoration: BoxDecoration(
              color: node.isUnresponsive
                  ? AppTheme.switchCardBg
                  : AppTheme.surfaceContainer,
              borderRadius: BorderRadius.circular(8),
              border: Border.all(
                color: borderColor,
                width: borderWidth,
              ),
              boxShadow: (isSelected || isOnActivePath)
                  ? [
                      BoxShadow(
                        color: AppTheme.activeHighlight.withValues(alpha: isSelected ? 0.45 : 0.25),
                        blurRadius: isSelected ? 12 : 8,
                        spreadRadius: isSelected ? 2 : 1,
                      ),
                    ]
                  : [
                      BoxShadow(
                        color: AppTheme.cardShadow,
                        blurRadius: 4,
                        offset: const Offset(0, 2),
                      ),
                    ],
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                // 1. Top Header Row: Icon + Type Badge + Depth / RTT
                Row(
                  children: [
                    Container(
                      padding: const EdgeInsets.all(3.5),
                      decoration: BoxDecoration(
                        color: themeColor.withValues(alpha: 0.18),
                        borderRadius: BorderRadius.circular(4),
                      ),
                      child: Icon(iconData, size: 12, color: themeColor),
                    ),
                    const SizedBox(width: 6),
                    Expanded(
                      child: SingleChildScrollView(
                        scrollDirection: Axis.horizontal,
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Container(
                              padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1.5),
                              decoration: BoxDecoration(
                                color: themeColor.withValues(alpha: 0.15),
                                borderRadius: BorderRadius.circular(3),
                                border: Border.all(color: themeColor.withValues(alpha: 0.3), width: 0.8),
                              ),
                              child: Text(
                                badgeLabel,
                                style: TextStyle(
                                  fontSize: 8.5,
                                  fontWeight: FontWeight.bold,
                                  color: themeColor,
                                  letterSpacing: 0.4,
                                ),
                              ),
                            ),
                            if (node.isStpRootBridge) ...[
                              const SizedBox(width: 4),
                              Tooltip(
                                message: 'STP Root Bridge${node.stpPriority != null ? ' (Priority ${node.stpPriority})' : ''}',
                                child: Container(
                                  padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 1.5),
                                  decoration: BoxDecoration(
                                    color: AppTheme.warning.withValues(alpha: 0.2),
                                    borderRadius: BorderRadius.circular(3),
                                    border: Border.all(color: AppTheme.warning.withValues(alpha: 0.55), width: 0.8),
                                  ),
                                  child: Text(
                                    'ROOT',
                                    style: TextStyle(
                                      fontSize: 7.5,
                                      fontWeight: FontWeight.bold,
                                      color: AppTheme.warning,
                                      letterSpacing: 0.3,
                                    ),
                                  ),
                                ),
                              ),
                            ],
                            if (node.isIgmpQuerier) ...[
                              const SizedBox(width: 4),
                              Tooltip(
                                message: 'Active IGMP Querier'
                                    '${node.igmpQuerierVersion != null ? ' (${node.igmpQuerierVersion})' : ''}'
                                    '${node.lastQuerierSeen != null ? '\nLast seen: ${node.lastQuerierSeen!.toLocal().toString().split('.').first}' : ''}',
                                child: Container(
                                  padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 1.5),
                                  decoration: BoxDecoration(
                                    color: AppTheme.cyan.withValues(alpha: 0.2),
                                    borderRadius: BorderRadius.circular(3),
                                    border: Border.all(color: AppTheme.cyan.withValues(alpha: 0.55), width: 0.8),
                                  ),
                                  child: Text(
                                    'QUERIER',
                                    style: TextStyle(
                                      fontSize: 7.5,
                                      fontWeight: FontWeight.bold,
                                      color: AppTheme.cyan,
                                      letterSpacing: 0.3,
                                    ),
                                  ),
                                ),
                              ),
                            ],
                            if (diffStatus != null && diffStatus != DiffChangeType.unchanged) ...[
                              const SizedBox(width: 4),
                              _buildDiffBadge(diffStatus!),
                            ],
                          ],
                        ),
                      ),
                    ),
                    const SizedBox(width: 6),
                    if (node.rttMs != null) ...[
                      Text(
                        '${node.rttMs!.toStringAsFixed(1)} ms',
                        style: TextStyle(
                          fontSize: 10,
                          fontWeight: FontWeight.w600,
                          fontFamily: 'monospace',
                          color: AppTheme.textSecondary,
                        ),
                      ),
                    ] else if (node.isUnresponsive) ...[
                      Text(
                        '* * *',
                        style: TextStyle(
                          fontSize: 10,
                          fontFamily: 'monospace',
                          color: AppTheme.textMuted,
                        ),
                      ),
                    ] else ...[
                      Text(
                        'Hop ${node.hopDepth}',
                        style: TextStyle(
                          fontSize: 9.5,
                          fontFamily: 'monospace',
                          color: AppTheme.textMuted,
                        ),
                      ),
                    ],
                  ],
                ),

                // 2. Middle Row: Name & IP
                Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    if (node.hasSharedName) ...[
                      Row(
                        children: [
                          Expanded(
                            child: Text(
                              node.sharedDeviceName!,
                              style: TextStyle(
                                fontSize: 11.5,
                                fontWeight: FontWeight.bold,
                                color: AppTheme.textPrimary,
                              ),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                          const SizedBox(width: 4),
                          Container(
                            padding: const EdgeInsets.symmetric(horizontal: 3.5, vertical: 0.5),
                            decoration: BoxDecoration(
                              color: AppTheme.success.withValues(alpha: 0.2),
                              borderRadius: BorderRadius.circular(2.5),
                            ),
                            child: Text(
                              'SHARED',
                              style: TextStyle(
                                fontSize: 7.5,
                                fontWeight: FontWeight.bold,
                                color: AppTheme.success,
                              ),
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 1),
                      Text(
                        displayIp,
                        style: TextStyle(
                          fontSize: 10.5,
                          fontFamily: 'monospace',
                          color: AppTheme.textSecondary,
                        ),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ] else if (node.hostname != null && node.hostname!.isNotEmpty && node.hostname != node.ip) ...[
                      Text(
                        node.hostname!,
                        style: TextStyle(
                          fontSize: 11,
                          fontWeight: FontWeight.w600,
                          color: AppTheme.textPrimary,
                        ),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                      const SizedBox(height: 1),
                      Text(
                        displayIp,
                        style: TextStyle(
                          fontSize: 10.5,
                          fontFamily: 'monospace',
                          color: AppTheme.textSecondary,
                        ),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ] else ...[
                      Text(
                        displayIp,
                        style: TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.bold,
                          fontFamily: 'monospace',
                          color: node.isUnresponsive ? AppTheme.textMuted : AppTheme.textPrimary,
                        ),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ],
                  ],
                ),

                // 3. Bottom Row: PoE Gauge (for PoE Switches) / MAC & Vendor / Subtitle Details
                if (node.isSwitch && node.poeStatus != null && node.poeStatus!.totalBudgetWatts > 0) ...[
                  _buildPoeGauge(node.poeStatus!),
                ] else if (node.macAddress != null) ...[
                  Row(
                    children: [
                      Icon(Icons.fingerprint, size: 10, color: AppTheme.textMuted),
                      const SizedBox(width: 3),
                      Text(
                        node.macAddress!,
                        style: TextStyle(
                          fontSize: 9,
                          fontFamily: 'monospace',
                          color: AppTheme.textMuted,
                        ),
                        maxLines: 1,
                      ),
                      if (node.vendor != null && node.vendor!.isNotEmpty) ...[
                        const SizedBox(width: 5),
                        Expanded(
                          child: Text(
                            node.vendor!,
                            style: TextStyle(
                              fontSize: 8.5,
                              color: AppTheme.textMuted,
                            ),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                      ],
                    ],
                  ),
                ] else if (node.isUnresponsive) ...[
                  Text(
                    'No ICMP / Hop response',
                    style: TextStyle(
                      fontSize: 8.5,
                      color: AppTheme.textMuted,
                    ),
                    maxLines: 1,
                  ),
                ] else if (node.isLocalHost) ...[
                  Text(
                    'Local Discovery Gateway',
                    style: TextStyle(
                      fontSize: 8.5,
                      color: AppTheme.textMuted,
                    ),
                    maxLines: 1,
                  ),
                ] else if (node.isSwitch) ...[
                  Row(
                    children: [
                      Icon(Icons.hub, size: 9, color: AppTheme.cyan),
                      const SizedBox(width: 3),
                      Expanded(
                        child: Text(
                          node.switchModel ?? 'Layer 2 Switch',
                          style: TextStyle(
                            fontSize: 8.5,
                            color: AppTheme.cyan,
                          ),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                    ],
                  ),
                ] else if (node.switchPort != null && node.switchPort!.isNotEmpty) ...[
                  Row(
                    children: [
                      Icon(Icons.cable, size: 9, color: AppTheme.cyan),
                      const SizedBox(width: 3),
                      Expanded(
                        child: Text(
                          'Port: ${node.switchPort!}',
                          style: TextStyle(
                            fontSize: 8.5,
                            color: AppTheme.cyan,
                          ),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                    ],
                  ),
                ] else if (node.associatedTargets.length > 1) ...[
                  Row(
                    children: [
                      Icon(Icons.alt_route, size: 9, color: AppTheme.router),
                      const SizedBox(width: 3),
                      Text(
                        'Routes ${node.associatedTargets.length} targets',
                        style: TextStyle(
                          fontSize: 8.5,
                          color: AppTheme.textMuted,
                        ),
                        maxLines: 1,
                      ),
                    ],
                  ),
                ] else ...[
                  Text(
                    'Hop ${node.hopDepth} Gateway',
                    style: TextStyle(
                      fontSize: 8.5,
                      color: AppTheme.textMuted,
                    ),
                    maxLines: 1,
                  ),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildPoeGauge(SwitchPoeStatus poe) {
    final pct = poe.utilizationPercent;
    final Color barColor;
    if (poe.isCriticalCapacity || poe.hasPortFaults) {
      barColor = AppTheme.error;
    } else if (pct >= 75.0) {
      barColor = AppTheme.warning;
    } else {
      barColor = AppTheme.cyan;
    }

    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Icon(Icons.bolt, size: 10, color: barColor),
            const SizedBox(width: 2),
            Expanded(
              child: Text(
                'PoE: ${poe.consumedWatts}W/${poe.totalBudgetWatts}W (${pct.round()}%)',
                style: TextStyle(
                  fontSize: 8.5,
                  fontWeight: FontWeight.w600,
                  fontFamily: 'monospace',
                  color: barColor,
                ),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
            ),
          ],
        ),
        const SizedBox(height: 2),
        ClipRRect(
          borderRadius: BorderRadius.circular(2),
          child: LinearProgressIndicator(
            value: (pct / 100.0).clamp(0.0, 1.0),
            minHeight: 3,
            backgroundColor: AppTheme.border,
            valueColor: AlwaysStoppedAnimation<Color>(barColor),
          ),
        ),
      ],
    );
  }

  Widget _buildDiffBadge(DiffChangeType status) {
    final (String label, Color color) = switch (status) {
      DiffChangeType.missing => ('MISSING', AppTheme.error),
      DiffChangeType.added => ('+ NEW', AppTheme.success),
      _ => ('DRIFT', AppTheme.warning),
    };
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 1.5),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.2),
        borderRadius: BorderRadius.circular(3),
        border: Border.all(color: color.withValues(alpha: 0.65), width: 0.8),
      ),
      child: Text(
        label,
        style: TextStyle(
          fontSize: 7.5,
          fontWeight: FontWeight.bold,
          color: color,
          letterSpacing: 0.3,
        ),
      ),
    );
  }

  static Color _getNodeColor(NetworkNode node) {
    if (node.isLocalHost) return AppTheme.hostLocal;
    if (node.isSwitch) return AppTheme.cyan;
    if (node.isUnresponsive) return AppTheme.unresponsive;
    if (node.isTarget) return AppTheme.target;
    return AppTheme.router;
  }

  static String _getNodeBadgeLabel(NetworkNode node) {
    if (node.isLocalHost) return 'LOCAL HOST';
    if (node.isSwitch) return 'SWITCH';
    if (node.isUnresponsive) return 'FILTERED';
    if (node.isTarget) return 'ENDPOINT';
    return 'ROUTER';
  }

  static IconData _getNodeIcon(NetworkNode node) {
    if (node.isLocalHost) return Icons.laptop_chromebook;
    if (node.isSwitch) return Icons.hub;
    if (node.isUnresponsive) return Icons.shield_outlined;
    if (node.isTarget) return Icons.device_hub;
    return Icons.router;
  }
}
