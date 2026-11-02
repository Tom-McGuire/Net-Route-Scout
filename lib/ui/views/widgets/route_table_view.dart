import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:net_route_scout/core/app_theme.dart';
import 'package:net_route_scout/domain/models/network_node.dart';
import 'package:net_route_scout/ui/view_models/topology_view_model.dart';

class RouteTableView extends StatefulWidget {
  const RouteTableView({super.key});

  @override
  State<RouteTableView> createState() => _RouteTableViewState();
}

class _RouteTableViewState extends State<RouteTableView> {
  int _sortColumnIndex = 1;
  bool _sortAscending = true;

  @override
  Widget build(BuildContext context) {
    final vm = context.watch<TopologyViewModel>();
    final nodes = vm.filteredNodes;
    final selectedNodeId = vm.selectedNodeId;

    if (nodes.isEmpty) {
      return const Center(
        child: Text(
          'No devices found matching filter.',
          style: TextStyle(color: Colors.white54, fontSize: 13),
        ),
      );
    }

    final sortedNodes = List<NetworkNode>.from(nodes);
    sortedNodes.sort((a, b) {
      int cmp = 0;
      switch (_sortColumnIndex) {
        case 0:
          cmp = a.hopDepth.compareTo(b.hopDepth);
          break;
        case 1:
          cmp = a.displayName.compareTo(b.displayName);
          break;
        case 2:
          cmp = a.ip.compareTo(b.ip);
          break;
        case 3:
          cmp = (a.macAddress ?? '').compareTo(b.macAddress ?? '');
          break;
        case 4:
          cmp = (a.vendor ?? '').compareTo(b.vendor ?? '');
          break;
        case 5:
          cmp = (a.rttMs ?? 9999).compareTo(b.rttMs ?? 9999);
          break;
      }
      return _sortAscending ? cmp : -cmp;
    });

    return Container(
      color: AppTheme.surfaceContainerLowest,
      child: Column(
        children: [
          // Table Header
          Container(
            height: 32,
            color: AppTheme.surfaceContainerHighest,
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: Row(
              children: [
                _buildHeaderCell('HOP', 60, 0),
                _buildHeaderCell('DEVICE NAME (SHARED)', 200, 1),
                _buildHeaderCell('IP ADDRESS', 140, 2),
                _buildHeaderCell('MAC ADDRESS', 160, 3),
                _buildHeaderCell('VENDOR / OUI', 160, 4),
                _buildHeaderCell('RTT (LATENCY)', 100, 5),
                const Expanded(
                  child: Text(
                    'PATH TRAVERSAL ROUTE',
                    style: TextStyle(
                      fontSize: 10,
                      fontWeight: FontWeight.bold,
                      color: Colors.white70,
                      letterSpacing: 0.5,
                    ),
                  ),
                ),
              ],
            ),
          ),
          const Divider(height: 1),

          // Virtualized List
          Expanded(
            child: ListView.separated(
              itemCount: sortedNodes.length,
              separatorBuilder: (_, _) => const Divider(height: 1),
              itemBuilder: (context, index) {
                final node = sortedNodes[index];
                final isSelected = selectedNodeId == node.id;
                final breadcrumbs = vm.getPathBreadcrumbs(node.id);
                final pathStr = breadcrumbs.map((n) => n.displayName).join(' ➔ ');

                return InkWell(
                  onTap: () => vm.selectNode(node.id),
                  child: Container(
                    height: 38,
                    padding: const EdgeInsets.symmetric(horizontal: 16),
                    color: isSelected
                        ? AppTheme.primaryAccent.withValues(alpha: 0.18)
                        : (index % 2 == 0 ? Colors.transparent : Colors.white.withValues(alpha: 0.02)),
                    child: Row(
                      children: [
                        // Hop Depth Badge
                        SizedBox(
                          width: 60,
                          child: Text(
                            node.isLocalHost ? 'Host' : 'Hop ${node.hopDepth}',
                            style: const TextStyle(
                              fontSize: 11,
                              fontFamily: 'monospace',
                              color: Colors.white70,
                            ),
                          ),
                        ),

                        // Device Friendly Name
                        SizedBox(
                          width: 200,
                          child: Row(
                            children: [
                              if (node.hasSharedName) ...[
                                Container(
                                  width: 6,
                                  height: 6,
                                  margin: const EdgeInsets.only(right: 6),
                                  decoration: const BoxDecoration(
                                    color: Color(0xFF10B981),
                                    shape: BoxShape.circle,
                                  ),
                                ),
                              ],
                              Expanded(
                                child: Text(
                                  node.displayName,
                                  style: TextStyle(
                                    fontSize: 11.5,
                                    fontWeight: node.hasSharedName ? FontWeight.bold : FontWeight.normal,
                                    color: node.hasSharedName ? Colors.white : Colors.white70,
                                  ),
                                  overflow: TextOverflow.ellipsis,
                                ),
                              ),
                            ],
                          ),
                        ),

                        // IP Address
                        SizedBox(
                          width: 140,
                          child: Text(
                            node.ip,
                            style: const TextStyle(
                              fontSize: 11,
                              fontFamily: 'monospace',
                              color: Colors.white,
                            ),
                          ),
                        ),

                        // MAC Address
                        SizedBox(
                          width: 160,
                          child: Text(
                            node.macAddress ?? '—',
                            style: TextStyle(
                              fontSize: 10.5,
                              fontFamily: 'monospace',
                              color: node.macAddress != null ? Colors.white70 : Colors.white30,
                            ),
                          ),
                        ),

                        // Vendor
                        SizedBox(
                          width: 160,
                          child: Text(
                            node.vendor ?? '—',
                            style: const TextStyle(
                              fontSize: 11,
                              color: Colors.white60,
                            ),
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),

                        // RTT
                        SizedBox(
                          width: 100,
                          child: Text(
                            node.rttMs != null ? '${node.rttMs!.toStringAsFixed(1)} ms' : '—',
                            style: const TextStyle(
                              fontSize: 11,
                              fontFamily: 'monospace',
                              color: Colors.white70,
                            ),
                          ),
                        ),

                        // Path Traversal String
                        Expanded(
                          child: Text(
                            pathStr.isNotEmpty ? pathStr : node.ip,
                            style: const TextStyle(
                              fontSize: 10.5,
                              color: Colors.white54,
                            ),
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                      ],
                    ),
                  ),
                );
              },
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildHeaderCell(String label, double width, int columnIndex) {
    final isCurrent = _sortColumnIndex == columnIndex;
    return SizedBox(
      width: width,
      child: InkWell(
        onTap: () {
          setState(() {
            if (_sortColumnIndex == columnIndex) {
              _sortAscending = !_sortAscending;
            } else {
              _sortColumnIndex = columnIndex;
              _sortAscending = true;
            }
          });
        },
        child: Row(
          children: [
            Text(
              label,
              style: TextStyle(
                fontSize: 10,
                fontWeight: FontWeight.bold,
                color: isCurrent ? AppTheme.primaryAccent : Colors.white70,
                letterSpacing: 0.5,
              ),
            ),
            if (isCurrent) ...[
              const SizedBox(width: 4),
              Icon(
                _sortAscending ? Icons.arrow_upward : Icons.arrow_downward,
                size: 11,
                color: AppTheme.primaryAccent,
              ),
            ],
          ],
        ),
      ),
    );
  }
}
