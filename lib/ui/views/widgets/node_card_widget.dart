import 'package:flutter/material.dart';
import 'package:net_route_scout/core/app_theme.dart';
import 'package:net_route_scout/domain/models/network_node.dart';

class NodeCardWidget extends StatelessWidget {
  final NetworkNode node;
  final bool isSelected;
  final bool isOnActivePath;
  final bool isDimmed;
  final bool isSearchMatch;
  final VoidCallback onTap;
  final void Function(TapUpDetails details)? onSecondaryTapUp;

  const NodeCardWidget({
    super.key,
    required this.node,
    required this.isSelected,
    required this.isOnActivePath,
    required this.isDimmed,
    this.isSearchMatch = false,
    required this.onTap,
    this.onSecondaryTapUp,
  });

  @override
  Widget build(BuildContext context) {
    final themeColor = _getNodeColor(node);
    final badgeLabel = _getNodeBadgeLabel(node);
    final iconData = _getNodeIcon(node);
    final displayIp = node.ip.startsWith('anon:') ? 'Anon-Hop-${node.hopDepth}' : node.ip;

    final borderColor = isSelected || isOnActivePath
        ? AppTheme.activeHighlight
        : isSearchMatch
            ? const Color(0xFFF59E0B)
            : themeColor.withValues(alpha: node.isUnresponsive ? 0.3 : 0.6);

    final borderWidth = isSelected ? 2.5 : ((isOnActivePath || isSearchMatch) ? 2.0 : 1.2);

    return AnimatedOpacity(
      duration: const Duration(milliseconds: 200),
      opacity: isDimmed ? 0.15 : 1.0,
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
                    ] else ...[
                      Text(
                        'Hop ${node.hopDepth}',
                        style: const TextStyle(
                          fontSize: 9.5,
                          fontFamily: 'monospace',
                          color: Colors.white38,
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
                              style: const TextStyle(
                                fontSize: 11.5,
                                fontWeight: FontWeight.bold,
                                color: Colors.white,
                              ),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                          const SizedBox(width: 4),
                          Container(
                            padding: const EdgeInsets.symmetric(horizontal: 3.5, vertical: 0.5),
                            decoration: BoxDecoration(
                              color: const Color(0xFF10B981).withValues(alpha: 0.2),
                              borderRadius: BorderRadius.circular(2.5),
                            ),
                            child: const Text(
                              'SHARED',
                              style: TextStyle(
                                fontSize: 7.5,
                                fontWeight: FontWeight.bold,
                                color: Color(0xFF10B981),
                              ),
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 1),
                      Text(
                        displayIp,
                        style: const TextStyle(
                          fontSize: 10.5,
                          fontFamily: 'monospace',
                          color: Colors.white70,
                        ),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ] else if (node.hostname != null && node.hostname!.isNotEmpty && node.hostname != node.ip) ...[
                      Text(
                        node.hostname!,
                        style: const TextStyle(
                          fontSize: 11,
                          fontWeight: FontWeight.w600,
                          color: Colors.white,
                        ),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                      const SizedBox(height: 1),
                      Text(
                        displayIp,
                        style: const TextStyle(
                          fontSize: 10.5,
                          fontFamily: 'monospace',
                          color: Colors.white70,
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
                          color: node.isUnresponsive ? Colors.white38 : Colors.white,
                        ),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ],
                  ],
                ),

                // 3. Bottom Row: MAC & Vendor / Subtitle Details
                if (node.macAddress != null) ...[
                  Row(
                    children: [
                      const Icon(Icons.fingerprint, size: 10, color: Colors.white38),
                      const SizedBox(width: 3),
                      Text(
                        node.macAddress!,
                        style: const TextStyle(
                          fontSize: 9,
                          fontFamily: 'monospace',
                          color: Colors.white54,
                        ),
                        maxLines: 1,
                      ),
                      if (node.vendor != null && node.vendor!.isNotEmpty) ...[
                        const SizedBox(width: 5),
                        Expanded(
                          child: Text(
                            node.vendor!,
                            style: const TextStyle(
                              fontSize: 8.5,
                              color: Colors.white38,
                            ),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                      ],
                    ],
                  ),
                ] else if (node.isUnresponsive) ...[
                  const Text(
                    'No ICMP / Hop response',
                    style: TextStyle(
                      fontSize: 8.5,
                      color: Colors.white30,
                    ),
                    maxLines: 1,
                  ),
                ] else if (node.isLocalHost) ...[
                  const Text(
                    'Local Discovery Gateway',
                    style: TextStyle(
                      fontSize: 8.5,
                      color: Colors.white38,
                    ),
                    maxLines: 1,
                  ),
                ] else if (node.isSwitch) ...[
                  Row(
                    children: [
                      const Icon(Icons.hub, size: 9, color: Color(0xFF06B6D4)),
                      const SizedBox(width: 3),
                      Expanded(
                        child: Text(
                          node.switchModel ?? 'Layer 2 Switch',
                          style: const TextStyle(
                            fontSize: 8.5,
                            color: Color(0xFF06B6D4),
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
                      const Icon(Icons.cable, size: 9, color: Color(0xFF06B6D4)),
                      const SizedBox(width: 3),
                      Expanded(
                        child: Text(
                          'Port: ${node.switchPort!}',
                          style: const TextStyle(
                            fontSize: 8.5,
                            color: Color(0xFF06B6D4),
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
                      const Icon(Icons.alt_route, size: 9, color: AppTheme.router),
                      const SizedBox(width: 3),
                      Text(
                        'Routes ${node.associatedTargets.length} targets',
                        style: const TextStyle(
                          fontSize: 8.5,
                          color: Colors.white54,
                        ),
                        maxLines: 1,
                      ),
                    ],
                  ),
                ] else ...[
                  Text(
                    'Hop ${node.hopDepth} Gateway',
                    style: const TextStyle(
                      fontSize: 8.5,
                      color: Colors.white30,
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

  static Color _getNodeColor(NetworkNode node) {
    if (node.isLocalHost) return AppTheme.hostLocal;
    if (node.isSwitch) return const Color(0xFF06B6D4);
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
