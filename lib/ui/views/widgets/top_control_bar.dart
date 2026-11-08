import 'package:flutter/material.dart';
import 'package:net_route_scout/core/app_theme.dart';
import 'package:net_route_scout/core/constants.dart';
import 'package:net_route_scout/domain/models/network_adapter_info.dart';
import 'package:net_route_scout/ui/view_models/topology_view_model.dart';
import 'package:provider/provider.dart';

class TopControlBar extends StatefulWidget {
  const TopControlBar({super.key});

  @override
  State<TopControlBar> createState() => _TopControlBarState();
}

class _TopControlBarState extends State<TopControlBar> {
  late final TextEditingController _targetController;
  String _lastSyncedTarget = '';

  @override
  void initState() {
    super.initState();
    final vm = context.read<TopologyViewModel>();
    _lastSyncedTarget = vm.targetInput;
    _targetController = TextEditingController(text: vm.targetInput);
  }

  @override
  void dispose() {
    _targetController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final vm = context.watch<TopologyViewModel>();
    final isScanning = vm.isScanning;

    // Synchronize controller only when ViewModel targetInput changed externally
    if (vm.targetInput != _lastSyncedTarget) {
      _lastSyncedTarget = vm.targetInput;
      if (_targetController.text != vm.targetInput) {
        _targetController.text = vm.targetInput;
      }
    }

    return Container(
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.surfaceContainerHigh,
        border: Border(
          bottom: BorderSide(color: Theme.of(context).dividerColor),
        ),
      ),
      child: SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
        child: Row(
          children: [
            // 1. App Icon & Title
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
            const SizedBox(width: 10),
            const Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  AppConstants.appTitle,
                  style: TextStyle(
                    fontSize: 15,
                    fontWeight: FontWeight.bold,
                    height: 1.1,
                  ),
                ),
                Text(
                  'Visual Network Topology Mapper',
                  style: TextStyle(fontSize: 10, color: Colors.grey),
                ),
              ],
            ),
            const SizedBox(width: 18),

            // 2. Primary Action: Start / Stop Sweep (ON THE LEFT)
            FilledButton.icon(
              onPressed: () {
                if (isScanning) {
                  vm.cancelSweep();
                } else {
                  vm.startSweep();
                }
              },
              style: FilledButton.styleFrom(
                backgroundColor: isScanning
                    ? const Color(0xFFEF4444)
                    : const Color(0xFF10B981),
                foregroundColor: Colors.white,
                padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(6)),
              ),
              icon: Icon(
                isScanning ? Icons.stop : Icons.radar,
                size: 17,
              ),
              label: Text(
                isScanning ? 'Stop Sweep' : 'Start Sweep',
                style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 12),
              ),
            ),
            const SizedBox(width: 14),

            // 3. Network Interface Selector
            const Text(
              'Interface:',
              style: TextStyle(fontSize: 12, color: Colors.grey),
            ),
            const SizedBox(width: 6),
            Container(
              height: 32,
              padding: const EdgeInsets.symmetric(horizontal: 8),
              decoration: BoxDecoration(
                color: const Color(0xFF252526),
                borderRadius: BorderRadius.circular(6),
                border: Border.all(color: const Color(0xFF3E3E42)),
              ),
              child: DropdownButtonHideUnderline(
                child: DropdownButton<NetworkAdapterInfo>(
                  value: vm.adapters.contains(vm.selectedAdapter)
                      ? vm.selectedAdapter
                      : (vm.adapters.isNotEmpty ? vm.adapters.first : null),
                  isDense: true,
                  icon: const Icon(Icons.arrow_drop_down, size: 18),
                  style: const TextStyle(fontSize: 12, color: Colors.white),
                  dropdownColor: const Color(0xFF252526),
                  hint: const Text('Select Adapter', style: TextStyle(fontSize: 11, color: Colors.white38)),
                  onChanged: isScanning
                      ? null
                      : (adapter) {
                          if (adapter != null) {
                            vm.selectAdapter(adapter);
                            _lastSyncedTarget = adapter.subnetCidr;
                            _targetController.text = adapter.subnetCidr;
                          }
                        },
                  items: vm.adapters.map((adapter) {
                    IconData icon = Icons.lan_outlined;
                    if (adapter.isLoopback) {
                      icon = Icons.public;
                    } else if (adapter.name.toLowerCase().contains('wi-fi') ||
                        adapter.name.toLowerCase().contains('wlan')) {
                      icon = Icons.wifi;
                    }
                    return DropdownMenuItem<NetworkAdapterInfo>(
                      value: adapter,
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(icon, size: 14, color: Theme.of(context).colorScheme.primary),
                          const SizedBox(width: 6),
                          Text(adapter.displayName),
                        ],
                      ),
                    );
                  }).toList(),
                ),
              ),
            ),
            IconButton(
              tooltip: 'Refresh network interfaces',
              icon: const Icon(Icons.refresh, size: 14),
              padding: EdgeInsets.zero,
              constraints: const BoxConstraints(minWidth: 26, minHeight: 26),
              onPressed: isScanning ? null : vm.refreshAdapters,
            ),
            const SizedBox(width: 12),

            // 4. Target Input Field
            const Text(
              'Target:',
              style: TextStyle(fontSize: 12, color: Colors.grey),
            ),
            const SizedBox(width: 6),
            Container(
              height: 32,
              width: 210,
              decoration: BoxDecoration(
                color: const Color(0xFF252526),
                borderRadius: BorderRadius.circular(6),
                border: Border.all(color: const Color(0xFF3E3E42)),
              ),
              child: TextField(
                controller: _targetController,
                enabled: !isScanning,
                onChanged: (val) {
                  _lastSyncedTarget = val;
                  vm.setTargetInput(val);
                },
                onSubmitted: (_) {
                  if (!isScanning) vm.startSweep();
                },
                style: const TextStyle(
                  fontSize: 12,
                  fontFamily: 'monospace',
                  color: Colors.white,
                ),
                decoration: InputDecoration(
                  isDense: true,
                  hintText: 'Target CIDR, IP, or Range...',
                  hintStyle: const TextStyle(fontSize: 11, color: Colors.white38),
                  contentPadding: const EdgeInsets.symmetric(horizontal: 8, vertical: 8),
                  border: InputBorder.none,
                  enabledBorder: InputBorder.none,
                  focusedBorder: InputBorder.none,
                  prefixIcon: const Icon(Icons.hub_outlined, size: 14, color: AppTheme.primaryAccent),
                  suffixIcon: _targetController.text.isNotEmpty && !isScanning
                      ? IconButton(
                          icon: const Icon(Icons.clear, size: 14),
                          padding: EdgeInsets.zero,
                          constraints: const BoxConstraints(minWidth: 20, minHeight: 20),
                          onPressed: () {
                            _targetController.clear();
                            _lastSyncedTarget = '';
                            vm.setTargetInput('');
                          },
                        )
                      : null,
                ),
              ),
            ),
            const SizedBox(width: 8),

            // 5. Preset Chips
            _buildPresetChip(
              label: 'Local /24',
              tooltip: 'Trace local subnet',
              onTap: isScanning
                  ? null
                  : () {
                      final ip = vm.localHostIp;
                      final parts = ip.split('.');
                      if (parts.length == 4) {
                        final cidr = '${parts[0]}.${parts[1]}.${parts[2]}.0/24';
                        _targetController.text = cidr;
                        _lastSyncedTarget = cidr;
                        vm.setTargetInput(cidr);
                      }
                    },
            ),
            const SizedBox(width: 4),
            if (vm.gatewayIp != null) ...[
              _buildPresetChip(
                label: 'Gateway',
                tooltip: 'Trace to Default Gateway',
                onTap: isScanning
                    ? null
                    : () {
                        _targetController.text = vm.gatewayIp!;
                        _lastSyncedTarget = vm.gatewayIp!;
                        vm.setTargetInput(vm.gatewayIp!);
                      },
              ),
              const SizedBox(width: 4),
            ],
            _buildPresetChip(
              label: '8.8.8.8',
              tooltip: 'Trace to Google DNS',
              onTap: isScanning
                  ? null
                  : () {
                      _targetController.text = '8.8.8.8';
                      _lastSyncedTarget = '8.8.8.8';
                      vm.setTargetInput('8.8.8.8');
                    },
            ),
            const SizedBox(width: 4),
            _buildPresetChip(
              label: '1.1.1.1',
              tooltip: 'Trace to Cloudflare DNS',
              onTap: isScanning
                  ? null
                  : () {
                      _targetController.text = '1.1.1.1';
                      _lastSyncedTarget = '1.1.1.1';
                      vm.setTargetInput('1.1.1.1');
                    },
            ),
            const SizedBox(width: 12),

            // 6. Concurrency Selector (Workers)
            Container(
              height: 32,
              padding: const EdgeInsets.symmetric(horizontal: 8),
              decoration: BoxDecoration(
                color: const Color(0xFF252526),
                borderRadius: BorderRadius.circular(6),
                border: Border.all(color: const Color(0xFF3E3E42)),
              ),
              child: DropdownButtonHideUnderline(
                child: DropdownButton<int>(
                  value: vm.concurrency,
                  dropdownColor: const Color(0xFF252526),
                  isDense: true,
                  style: const TextStyle(fontSize: 11, color: Colors.white70),
                  onChanged: isScanning ? null : (v) => v != null ? vm.setConcurrency(v) : null,
                  items: const [
                    DropdownMenuItem(value: 2, child: Text('2 Workers')),
                    DropdownMenuItem(value: 4, child: Text('4 Workers')),
                    DropdownMenuItem(value: 8, child: Text('8 Workers')),
                    DropdownMenuItem(value: 16, child: Text('16 Workers')),
                  ],
                ),
              ),
            ),
            const SizedBox(width: 6),

            // 7. Max Hops Selector
            Container(
              height: 32,
              padding: const EdgeInsets.symmetric(horizontal: 8),
              decoration: BoxDecoration(
                color: const Color(0xFF252526),
                borderRadius: BorderRadius.circular(6),
                border: Border.all(color: const Color(0xFF3E3E42)),
              ),
              child: DropdownButtonHideUnderline(
                child: DropdownButton<int>(
                  value: vm.maxHops,
                  dropdownColor: const Color(0xFF252526),
                  isDense: true,
                  style: const TextStyle(fontSize: 11, color: Colors.white70),
                  onChanged: isScanning ? null : (v) => v != null ? vm.setMaxHops(v) : null,
                  items: const [
                    DropdownMenuItem(value: 8, child: Text('Max 8 Hops')),
                    DropdownMenuItem(value: 15, child: Text('Max 15 Hops')),
                    DropdownMenuItem(value: 25, child: Text('Max 25 Hops')),
                    DropdownMenuItem(value: 30, child: Text('Max 30 Hops')),
                  ],
                ),
              ),
            ),
            const SizedBox(width: 12),

            // 8. Demo Network Button
            OutlinedButton.icon(
              onPressed: isScanning ? null : vm.loadDemoTopology,
              icon: const Icon(Icons.auto_awesome, size: 14, color: Color(0xFFF59E0B)),
              label: const Text('Demo Network', style: TextStyle(fontSize: 12)),
              style: OutlinedButton.styleFrom(
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
                side: const BorderSide(color: Color(0xFF3E3E42)),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(6)),
              ),
            ),
            const SizedBox(width: 6),

            // 9. Clear Button
            OutlinedButton.icon(
              onPressed: (isScanning || vm.nodes.length <= 1) ? null : vm.clearGraph,
              icon: const Icon(Icons.delete_outline, size: 15),
              label: const Text('Clear', style: TextStyle(fontSize: 12)),
              style: OutlinedButton.styleFrom(
                foregroundColor: Colors.red.shade300,
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
                side: const BorderSide(color: Color(0xFF3E3E42)),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(6)),
              ),
            ),
            const SizedBox(width: 6),

            // 10. Export Menu
            PopupMenuButton<String>(
              tooltip: 'Export Topology',
              enabled: vm.nodes.isNotEmpty,
              icon: const Icon(Icons.file_download_outlined, size: 19),
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
              itemBuilder: (ctx) => const [
                PopupMenuItem(
                  value: 'file',
                  child: Row(
                    children: [
                      Icon(Icons.file_download, size: 16),
                      SizedBox(width: 8),
                      Text('Save JSON File...', style: TextStyle(fontSize: 12)),
                    ],
                  ),
                ),
                PopupMenuItem(
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
            ),
            const SizedBox(width: 10),

            // 11. View Mode Selector (Graph, Table, Split)
            Container(
              height: 28,
              decoration: BoxDecoration(
                color: const Color(0xFF252526),
                borderRadius: BorderRadius.circular(6),
                border: Border.all(color: const Color(0xFF3E3E42)),
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
            const SizedBox(width: 10),

            // 12. Local Host Info Pill
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 4),
              decoration: BoxDecoration(
                color: const Color(0xFF252526),
                borderRadius: BorderRadius.circular(6),
                border: Border.all(color: const Color(0xFF3E3E42)),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Icon(Icons.laptop, size: 13, color: AppTheme.hostLocal),
                  const SizedBox(width: 5),
                  Text(
                    'Host: ${vm.localHostIp}${vm.selectedAdapter?.macAddress != null && vm.selectedAdapter!.macAddress!.isNotEmpty ? '  [${vm.selectedAdapter!.macAddress}]' : ''}',
                    style: const TextStyle(
                      fontSize: 10.5,
                      fontFamily: 'monospace',
                      color: Colors.white70,
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(width: 6),

            // 13. Shared Device Database Status Pill
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 4),
              decoration: BoxDecoration(
                color: vm.isSharedDbConnected
                    ? const Color(0xFF10B981).withValues(alpha: 0.15)
                    : const Color(0xFFF59E0B).withValues(alpha: 0.15),
                borderRadius: BorderRadius.circular(6),
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
                    size: 12,
                    color: vm.isSharedDbConnected ? const Color(0xFF10B981) : const Color(0xFFF59E0B),
                  ),
                  const SizedBox(width: 5),
                  Text(
                    vm.isSharedDbConnected ? 'SHARED DB' : 'STANDALONE',
                    style: TextStyle(
                      fontSize: 9.5,
                      fontWeight: FontWeight.bold,
                      letterSpacing: 0.5,
                      color: vm.isSharedDbConnected ? const Color(0xFF10B981) : const Color(0xFFF59E0B),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildPresetChip({
    required String label,
    required String tooltip,
    required VoidCallback? onTap,
  }) {
    return Tooltip(
      message: tooltip,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(4),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 5),
          decoration: BoxDecoration(
            color: const Color(0xFF252526),
            borderRadius: BorderRadius.circular(5),
            border: Border.all(color: const Color(0xFF3E3E42)),
          ),
          child: Text(
            label,
            style: const TextStyle(
              fontSize: 10.5,
              fontFamily: 'monospace',
              fontWeight: FontWeight.w600,
              color: Colors.white70,
            ),
          ),
        ),
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
