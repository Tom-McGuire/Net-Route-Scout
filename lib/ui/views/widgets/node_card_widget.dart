import 'package:flutter/material.dart';
import 'package:net_route_scout/core/app_theme.dart';
import 'package:net_route_scout/domain/models/network_node.dart';

class NodeCardWidget extends StatelessWidget {
  final NetworkNode node;
  final bool isSelected;
  final bool isOnActivePath;
  final bool isDimmed;
  final VoidCallback onTap;

  const NodeCardWidget({
    super.key,
    required this.node,
    required this.isSelected,
    required this.isOnActivePath,
    required this.isDimmed,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final themeColor = _getNodeColor(node);
    final badgeLabel = _getNodeBadgeLabel(node);
    final iconData = _getNodeIcon(node);

    final borderColor = isSelected || isOnActivePath
        ? AppTheme.activeHighlight
        : themeColor.withValues(alpha: node.isUnresponsive ? 0.3 : 0.6);

    final borderWidth = isSelected ? 2.5 : (isOnActivePath ? 2.0 : 1.2);

    return AnimatedOpacity(
      duration: const Duration(milliseconds: 200),
      opacity: isDimmed ? 0.15 : 1.0,
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(8),
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 180),
            width: 215,
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
            decoration: BoxDecoration(
              color: node.isUnresponsive
                  ? const Color(0xFF161A22)
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
                        color: Colors.black.withValues(alpha: 0.3),
                        blurRadius: 4,
                        offset: const Offset(0, 2),
                      ),
                    ],
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                // Top Header Row: Icon + Type Badge + Depth / RTT
                Row(
                  children: [
                    Container(
                      padding: const EdgeInsets.all(4),
                      decoration: BoxDecoration(
                        color: themeColor.withValues(alpha: 0.18),
                        borderRadius: BorderRadius.circular(5),
                      ),
                      child: Icon(iconData, size: 13, color: themeColor),
                    ),
                    const SizedBox(width: 6),
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
                          fontSize: 9,
                          fontWeight: FontWeight.bold,
                          color: themeColor,
                          letterSpacing: 0.5,
                        ),
                      ),
                    ),
                    const Spacer(),
                    if (node.rttMs != null) ...[
                      Text(
                        '${node.rttMs!.toStringAsFixed(1)} ms',
                        style: const TextStyle(
                          fontSize: 10,
                          fontWeight: FontWeight.w600,
                          fontFamily: 'monospace',
                          color: Colors.white70,
                        ),
                      ),
                    ] else if (node.isUnresponsive) ...[
                      const Text(
                        '* * *',
                        style: TextStyle(
                          fontSize: 10,
                          fontFamily: 'monospace',
                          color: Colors.white38,
                        ),
                      ),
                    ],
                  ],
                ),
                const SizedBox(height: 6),

                // Device Friendly Name (from Shared DB) or Hostname
                if (node.hasSharedName) ...[
                  Row(
                    children: [
                      Expanded(
                        child: Text(
                          node.sharedDeviceName!,
                          style: const TextStyle(
                            fontSize: 12,
                            fontWeight: FontWeight.bold,
                            color: Colors.white,
                          ),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                      const SizedBox(width: 4),
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 1),
                        decoration: BoxDecoration(
                          color: const Color(0xFF10B981).withValues(alpha: 0.2),
                          borderRadius: BorderRadius.circular(3),
                        ),
                        child: const Text(
                          'SHARED',
                          style: TextStyle(
                            fontSize: 8,
                            fontWeight: FontWeight.bold,
                            color: Color(0xFF10B981),
                          ),
                        ),
                      ),
                    ],
                  ),
                ] else if (node.hostname != null && node.hostname!.isNotEmpty && node.hostname != node.ip) ...[
                  Text(
                    node.hostname!,
                    style: const TextStyle(
                      fontSize: 11.5,
                      fontWeight: FontWeight.w600,
                      color: Colors.white,
                    ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ],

                // IP Address (Monospace)
                Row(
                  children: [
                    Expanded(
                      child: Text(
                        node.ip,
                        style: TextStyle(
                          fontSize: 11.5,
                          fontWeight: FontWeight.w600,
                          fontFamily: 'monospace',
                          color: node.isUnresponsive ? Colors.white38 : (node.hasSharedName ? Colors.white70 : Colors.white),
                        ),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                    const SizedBox(width: 6),
                    Text(
                      'Hop ${node.hopDepth}',
                      style: const TextStyle(
                        fontSize: 9.5,
                        color: Colors.white38,
                        fontFamily: 'monospace',
                      ),
                    ),
                  ],
                ),

                // MAC Address & Vendor (if resolved via ARP)
                if (node.macAddress != null) ...[
                  const SizedBox(height: 3),
                  Row(
                    children: [
                      const Icon(Icons.fingerprint, size: 10, color: Colors.white38),
                      const SizedBox(width: 4),
                      Expanded(
                        child: Text(
                          node.macAddress!,
                          style: const TextStyle(
                            fontSize: 9.5,
                            fontFamily: 'monospace',
                            color: Colors.white54,
                          ),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                    ],
                  ),
                ],

                if (node.vendor != null && node.vendor!.isNotEmpty) ...[
                  Text(
                    node.vendor!,
                    style: const TextStyle(
                      fontSize: 9,
                      color: Colors.white38,
                    ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ],

                // Traversed Target Count Badge (for intermediate routers)
                if (!node.isLocalHost && node.associatedTargets.length > 1) ...[
                  const SizedBox(height: 4),
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 2),
                    decoration: BoxDecoration(
                      color: Colors.white.withValues(alpha: 0.06),
                      borderRadius: BorderRadius.circular(4),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        const Icon(Icons.alt_route, size: 10, color: AppTheme.router),
                        const SizedBox(width: 4),
                        Text(
                          'Routes ${node.associatedTargets.length} targets',
                          style: const TextStyle(
                            fontSize: 9,
                            fontWeight: FontWeight.w500,
                            color: Colors.white70,
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }

  static Color _getNodeColor(NetworkNode node) {
    if (node.isLocalHost) return AppTheme.hostLocal;
    if (node.isUnresponsive) return AppTheme.unresponsive;
    if (node.isTarget) return AppTheme.target;
    return AppTheme.router;
  }

  static String _getNodeBadgeLabel(NetworkNode node) {
    if (node.isLocalHost) return 'LOCAL HOST';
    if (node.isUnresponsive) return 'FILTERED';
    if (node.isTarget) return 'ENDPOINT';
    return 'ROUTER';
  }

  static IconData _getNodeIcon(NetworkNode node) {
    if (node.isLocalHost) return Icons.laptop_chromebook;
    if (node.isUnresponsive) return Icons.shield_outlined;
    if (node.isTarget) return Icons.device_hub;
    return Icons.router;
  }
}
