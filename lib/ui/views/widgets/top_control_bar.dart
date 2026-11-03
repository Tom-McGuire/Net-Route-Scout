import 'package:flutter/material.dart';
import 'package:net_route_scout/core/app_theme.dart';
import 'package:net_route_scout/core/constants.dart';
import 'package:net_route_scout/ui/view_models/topology_view_model.dart';
import 'package:provider/provider.dart';

class TopControlBar extends StatelessWidget {
  const TopControlBar({super.key});

  @override
  Widget build(BuildContext context) {
    final vm = context.watch<TopologyViewModel>();

    return Container(
      height: 48,
      padding: const EdgeInsets.symmetric(horizontal: 14),
      decoration: const BoxDecoration(
        color: AppTheme.surface,
        border: Border(
          bottom: BorderSide(color: AppTheme.border, width: 1),
        ),
      ),
      child: Row(
        children: [
          // App Icon
          ClipRRect(
            borderRadius: BorderRadius.circular(6),
            child: Image.asset(
              'assets/app_icon.png',
              width: 28,
              height: 28,
              fit: BoxFit.cover,
              errorBuilder: (_, _, _) => Container(
                width: 28,
                height: 28,
                decoration: BoxDecoration(
                  color: AppTheme.primaryAccent.withValues(alpha: 0.2),
                  borderRadius: BorderRadius.circular(6),
                ),
                child: const Icon(Icons.alt_route, color: AppTheme.primaryAccent, size: 18),
              ),
            ),
          ),
          const SizedBox(width: 8),

          // Title
          const Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Text(
                AppConstants.appTitle,
                style: TextStyle(
                  fontSize: 13.5,
                  fontWeight: FontWeight.bold,
                  color: Colors.white,
                  letterSpacing: 0.3,
                ),
              ),
              Text(
                'Visual Network Topology Mapper',
                style: TextStyle(
                  fontSize: 9.5,
                  color: Colors.white54,
                ),
              ),
            ],
          ),

          const Spacer(),

          // Local Host Info
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 3.5),
            decoration: BoxDecoration(
              color: AppTheme.surfaceContainerLowest,
              borderRadius: BorderRadius.circular(5),
              border: Border.all(color: AppTheme.border),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Icon(Icons.laptop, size: 12, color: AppTheme.hostLocal),
                const SizedBox(width: 4),
                Text(
                  'Host: ${vm.localHostIp}${vm.selectedAdapter?.macAddress != null && vm.selectedAdapter!.macAddress!.isNotEmpty ? '  [${vm.selectedAdapter!.macAddress}]' : ''}',
                  style: const TextStyle(
                    fontSize: 10,
                    fontFamily: 'monospace',
                    color: Colors.white70,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(width: 6),

          // Shared Device Database Status Pill
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 3.5),
            decoration: BoxDecoration(
              color: vm.isSharedDbConnected
                  ? const Color(0xFF10B981).withValues(alpha: 0.15)
                  : const Color(0xFFF59E0B).withValues(alpha: 0.15),
              borderRadius: BorderRadius.circular(5),
              border: Border.all(
                color: vm.isSharedDbConnected
                    ? const Color(0xFF10B981).withValues(alpha: 0.4)
                    : const Color(0xFFF59E0B).withValues(alpha: 0.4),
              ),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(
                  vm.isSharedDbConnected ? Icons.storage : Icons.storage_outlined,
                  size: 11,
                  color: vm.isSharedDbConnected ? const Color(0xFF10B981) : const Color(0xFFF59E0B),
                ),
                const SizedBox(width: 4),
                Text(
                  vm.isSharedDbConnected ? 'SHARED DB' : 'STANDALONE',
                  style: TextStyle(
                    fontSize: 9,
                    fontWeight: FontWeight.bold,
                    letterSpacing: 0.5,
                    color: vm.isSharedDbConnected ? const Color(0xFF10B981) : const Color(0xFFF59E0B),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(width: 6),

          // View Mode Selector (Graph, Table, Split)
          Container(
            height: 26,
            decoration: BoxDecoration(
              color: AppTheme.surfaceContainerLowest,
              borderRadius: BorderRadius.circular(5),
              border: Border.all(color: AppTheme.border),
            ),
            child: Row(
              children: [
                _buildViewModeButton(
                  context,
                  mode: TopologyViewMode.graph,
                  icon: Icons.hub_outlined,
                  tooltip: 'Topology Graph',
                  isSelected: vm.viewMode == TopologyViewMode.graph,
                ),
                _buildViewModeButton(
                  context,
                  mode: TopologyViewMode.table,
                  icon: Icons.table_rows_outlined,
                  tooltip: 'Route Table',
                  isSelected: vm.viewMode == TopologyViewMode.table,
                ),
                _buildViewModeButton(
                  context,
                  mode: TopologyViewMode.split,
                  icon: Icons.vertical_split_outlined,
                  tooltip: 'Split View',
                  isSelected: vm.viewMode == TopologyViewMode.split,
                ),
              ],
            ),
          ),
          const SizedBox(width: 6),

          // Demo Data Button
          OutlinedButton.icon(
            onPressed: vm.isScanning ? null : vm.loadDemoTopology,
            icon: const Icon(Icons.auto_awesome, size: 12, color: Color(0xFFF59E0B)),
            label: const Text('Demo Network', style: TextStyle(fontSize: 10)),
            style: OutlinedButton.styleFrom(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 5),
              side: const BorderSide(color: Color(0xFF4A4A4A)),
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(5)),
            ),
          ),
          const SizedBox(width: 6),

          // Export JSON Button
          PopupMenuButton<String>(
            tooltip: 'Export Topology',
            onSelected: (val) {
              if (val == 'file') {
                vm.exportTopologyJson().then((path) {
                  if (path != null && context.mounted) {
                    ScaffoldMessenger.of(context).showSnackBar(
                      SnackBar(content: Text('Topology exported to $path')),
                    );
                  }
                });
              } else if (val == 'clipboard') {
                vm.copyJsonToClipboard().then((_) {
                  if (context.mounted) {
                    ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(content: Text('JSON copied to clipboard')),
                    );
                  }
                });
              }
            },
            itemBuilder: (ctx) => [
              const PopupMenuItem(
                value: 'file',
                child: Row(
                  children: [
                    Icon(Icons.file_download, size: 16),
                    SizedBox(width: 8),
                    Text('Save JSON File...', style: TextStyle(fontSize: 12)),
                  ],
                ),
              ),
              const PopupMenuItem(
                value: 'clipboard',
                child: Row(
                  children: [
                    Icon(Icons.copy, size: 16),
                    SizedBox(width: 8),
                    Text('Copy JSON to Clipboard', style: TextStyle(fontSize: 12)),
                  ],
                ),
              ),
            ],
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 4.5),
              decoration: BoxDecoration(
                color: AppTheme.surfaceContainerLowest,
                borderRadius: BorderRadius.circular(5),
                border: Border.all(color: AppTheme.border),
              ),
              child: const Row(
                children: [
                  Icon(Icons.share, size: 12, color: Colors.white70),
                  SizedBox(width: 4),
                  Text('Export', style: TextStyle(fontSize: 10, color: Colors.white70)),
                  Icon(Icons.arrow_drop_down, size: 12, color: Colors.white54),
                ],
              ),
            ),
          ),
          const SizedBox(width: 4),

          // Clear Graph Button
          IconButton(
            onPressed: vm.isScanning ? null : vm.clearGraph,
            icon: const Icon(Icons.delete_sweep_outlined, size: 16),
            tooltip: 'Clear Topology Graph',
            splashRadius: 15,
            constraints: const BoxConstraints(minWidth: 26, minHeight: 26),
            padding: const EdgeInsets.all(4),
          ),
        ],
      ),
    );
  }

  Widget _buildViewModeButton(
    BuildContext context, {
    required TopologyViewMode mode,
    required IconData icon,
    required String tooltip,
    required bool isSelected,
  }) {
    final vm = context.read<TopologyViewModel>();
    return Tooltip(
      message: tooltip,
      child: InkWell(
        onTap: () => vm.setViewMode(mode),
        borderRadius: BorderRadius.circular(4),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 3),
          color: isSelected ? AppTheme.primaryAccent.withValues(alpha: 0.25) : Colors.transparent,
          child: Icon(
            icon,
            size: 14,
            color: isSelected ? Colors.white : Colors.white54,
          ),
        ),
      ),
    );
  }
}
