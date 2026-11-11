import 'package:material_ui/material_ui.dart';
import 'package:net_route_scout/core/app_theme.dart';
import 'package:net_route_scout/core/constants.dart';
import 'package:net_route_scout/domain/models/network_adapter_info.dart';
import 'package:net_route_scout/ui/view_models/topology_view_model.dart';
import 'package:provider/provider.dart';
import 'device_library_dialog.dart';
import 'snmp_discovery_dialog.dart';

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
      height: 52,
      decoration: const BoxDecoration(
        color: Color(0xFF1E1E1E),
        border: Border(
          bottom: BorderSide(color: Color(0xFF2C2C2C), width: 1),
        ),
      ),
      child: LayoutBuilder(
        builder: (context, constraints) {
          return SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: ConstrainedBox(
              constraints: BoxConstraints(minWidth: constraints.maxWidth),
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    // Left Cluster: Zone 1 (Branding), Zone 2 (Interface & Target), Zone 3 (Primary Actions)
                    Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        // ==================== ZONE 1: BRANDING ====================
                        ClipRRect(
                          borderRadius: BorderRadius.circular(6),
                          child: Image.asset(
                            'assets/app_icon.png',
                            width: 32,
                            height: 32,
                            fit: BoxFit.cover,
                            errorBuilder: (_, _, _) => Container(
                              width: 32,
                              height: 32,
                              decoration: BoxDecoration(
                                color: AppTheme.primaryAccent.withValues(alpha: 0.2),
                                borderRadius: BorderRadius.circular(6),
                              ),
                              child: const Icon(Icons.alt_route, color: AppTheme.primaryAccent, size: 18),
                            ),
                          ),
                        ),
                        const SizedBox(width: 10),
                        Column(
                          mainAxisAlignment: MainAxisAlignment.center,
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              AppConstants.appTitle.toUpperCase(),
                              style: const TextStyle(
                                fontSize: 13,
                                fontWeight: FontWeight.bold,
                                letterSpacing: 0.8,
                                color: Colors.white,
                              ),
                            ),
                            const Text(
                              'Visual Network Topology Mapper',
                              style: TextStyle(fontSize: 10, color: Colors.white54),
                            ),
                          ],
                        ),
                        const SizedBox(width: 16),

                        // ==================== ZONE 2: INTERFACE & TARGET ====================
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
                        const SizedBox(width: 4),
                        IconButton(
                          tooltip: 'Refresh Interfaces',
                          icon: const Icon(Icons.refresh, size: 16),
                          padding: EdgeInsets.zero,
                          constraints: const BoxConstraints(minWidth: 26, minHeight: 26),
                          onPressed: isScanning ? null : vm.refreshAdapters,
                        ),
                        const SizedBox(width: 10),

                        // Target Input Field
                        const Text(
                          'Target:',
                          style: TextStyle(fontSize: 12, color: Colors.grey),
                        ),
                        const SizedBox(width: 6),
                        Container(
                          height: 32,
                          width: 190,
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
                              if (!isScanning) {
                                if (_targetController.text.trim().isNotEmpty) {
                                  vm.setTargetInput(_targetController.text.trim());
                                }
                                vm.startSweep();
                              }
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
                        const SizedBox(width: 6),

                        // Preset Chips
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
                        const SizedBox(width: 8),

                        // Concurrency Selector (Workers)
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

                        // Max Hops Selector
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

                        // ==================== ZONE 3: PRIMARY ACTIONS ====================
                        FilledButton.icon(
                          onPressed: () {
                            if (isScanning) {
                              vm.cancelSweep();
                            } else {
                              if (_targetController.text.trim().isNotEmpty) {
                                vm.setTargetInput(_targetController.text.trim());
                              }
                              vm.startSweep();
                            }
                          },
                          style: FilledButton.styleFrom(
                            backgroundColor: isScanning
                                ? const Color(0xFFEF4444) // Active Red
                                : const Color(0xFF10B981), // Idle Emerald Green (from ARP Scout)
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
                      ],
                    ),

                    const SizedBox(width: 24),

                    // Right Cluster: Zone 4 (Ecosystem & Demo), Zone 5 (Clear & Export)
                    Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        // ==================== ZONE 4: ECOSYSTEM & DEMO ====================
                        OutlinedButton.icon(
                          onPressed: () => SnmpDiscoveryDialog.show(context, vm),
                          icon: const Icon(Icons.sensors, size: 15, color: Color(0xFF06B6D4)),
                          label: const Text('SNMP Switch', style: TextStyle(fontSize: 11, color: Color(0xFF06B6D4))),
                          style: OutlinedButton.styleFrom(
                            side: const BorderSide(color: Color(0xFF06B6D4)),
                            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
                            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(6)),
                          ),
                        ),
                        const SizedBox(width: 8),

                        OutlinedButton.icon(
                          onPressed: () => DeviceLibraryDialog.show(context),
                          icon: const Icon(Icons.devices, size: 15),
                          label: const Text('Device Library', style: TextStyle(fontSize: 11)),
                          style: OutlinedButton.styleFrom(
                            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
                            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(6)),
                          ),
                        ),
                        const SizedBox(width: 8),

                        OutlinedButton.icon(
                          onPressed: isScanning ? null : vm.loadDemoTopology,
                          icon: const Icon(Icons.play_circle_outline, size: 15),
                          label: const Text('Load Demo', style: TextStyle(fontSize: 11)),
                          style: OutlinedButton.styleFrom(
                            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
                            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(6)),
                          ),
                        ),
                        const SizedBox(width: 8),

                        // ==================== ZONE 5: CLEAR & EXPORT ====================
                        OutlinedButton.icon(
                          onPressed: (isScanning || vm.nodes.length <= 1) ? null : vm.clearGraph,
                          icon: const Icon(Icons.delete_sweep_outlined, size: 15),
                          label: const Text('Clear', style: TextStyle(fontSize: 11)),
                          style: OutlinedButton.styleFrom(
                            foregroundColor: Colors.red.shade300,
                            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
                            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(6)),
                          ),
                        ),
                        const SizedBox(width: 8),

                        // Export Menu (Styled as bordered chip per specification)
                        PopupMenuButton<String>(
                          tooltip: 'Export',
                          enabled: vm.nodes.isNotEmpty,
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
                          child: Container(
                            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 7),
                            decoration: BoxDecoration(
                              borderRadius: BorderRadius.circular(6),
                              border: Border.all(color: const Color(0xFF3E3E42)),
                            ),
                            child: const Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Icon(Icons.download, size: 15, color: Colors.white70),
                                SizedBox(width: 6),
                                Text('Export', style: TextStyle(fontSize: 11, color: Colors.white70)),
                                Icon(Icons.arrow_drop_down, size: 14, color: Colors.white70),
                              ],
                            ),
                          ),
                        ),
                        const SizedBox(width: 8),

                        // View Mode Selector (Graph, Table, Split)
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
                      ],
                    ),
                  ],
                ),
              ),
            ),
          );
        },
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
