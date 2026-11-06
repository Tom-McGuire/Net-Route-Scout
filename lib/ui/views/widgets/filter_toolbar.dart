import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:net_route_scout/core/app_theme.dart';
import 'package:net_route_scout/domain/models/network_adapter_info.dart';
import 'package:net_route_scout/ui/view_models/topology_view_model.dart';

class FilterToolbar extends StatefulWidget {
  const FilterToolbar({super.key});

  @override
  State<FilterToolbar> createState() => _FilterToolbarState();
}

class _FilterToolbarState extends State<FilterToolbar> {
  late final TextEditingController _targetController;
  late final TextEditingController _searchController;
  String _lastSyncedTarget = '';

  @override
  void initState() {
    super.initState();
    final vm = context.read<TopologyViewModel>();
    _lastSyncedTarget = vm.targetInput;
    _targetController = TextEditingController(text: vm.targetInput);
    _searchController = TextEditingController(text: vm.searchQuery);
  }

  @override
  void dispose() {
    _targetController.dispose();
    _searchController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final vm = context.watch<TopologyViewModel>();

    // Synchronize controller only when ViewModel targetInput changed externally (e.g. preset or adapter change)
    if (vm.targetInput != _lastSyncedTarget) {
      _lastSyncedTarget = vm.targetInput;
      if (_targetController.text != vm.targetInput) {
        _targetController.text = vm.targetInput;
      }
    }

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      decoration: const BoxDecoration(
        color: AppTheme.surfaceContainerLow,
        border: Border(
          bottom: BorderSide(color: AppTheme.border, width: 1),
        ),
      ),
      child: Row(
        children: [
          // Network Adapter Selector
          Container(
            height: 34,
            padding: const EdgeInsets.symmetric(horizontal: 8),
            decoration: BoxDecoration(
              color: AppTheme.inputFill,
              borderRadius: BorderRadius.circular(6),
              border: Border.all(color: const Color(0xFF3E3E42)),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Icon(Icons.settings_ethernet, size: 14, color: AppTheme.hostLocal),
                const SizedBox(width: 6),
                DropdownButtonHideUnderline(
                  child: DropdownButton<NetworkAdapterInfo>(
                    value: vm.selectedAdapter,
                    dropdownColor: AppTheme.surfaceContainerHigh,
                    style: const TextStyle(fontSize: 11, color: Colors.white),
                    hint: const Text('Select Adapter', style: TextStyle(fontSize: 11, color: Colors.white38)),
                    onChanged: vm.isScanning
                        ? null
                        : (adapter) {
                            if (adapter != null) {
                              vm.selectAdapter(adapter);
                              _lastSyncedTarget = adapter.subnetCidr;
                              _targetController.text = adapter.subnetCidr;
                            }
                          },
                    items: vm.adapters.map((adapter) {
                      return DropdownMenuItem<NetworkAdapterInfo>(
                        value: adapter,
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Text(
                              adapter.name,
                              style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w600, color: Colors.white),
                            ),
                            const SizedBox(width: 6),
                            Text(
                              adapter.ipAddress,
                              style: const TextStyle(fontSize: 10.5, fontFamily: 'monospace', color: Colors.white70),
                            ),
                            if (adapter.macAddress != null && adapter.macAddress!.isNotEmpty) ...[
                              const SizedBox(width: 6),
                              Text(
                                '[${adapter.macAddress}]',
                                style: const TextStyle(fontSize: 9.5, fontFamily: 'monospace', color: Colors.white38),
                              ),
                            ],
                          ],
                        ),
                      );
                    }).toList(),
                  ),
                ),
                const SizedBox(width: 4),
                IconButton(
                  icon: const Icon(Icons.refresh, size: 13, color: Colors.white54),
                  tooltip: 'Refresh network interfaces',
                  splashRadius: 14,
                  padding: EdgeInsets.zero,
                  constraints: const BoxConstraints(minWidth: 20, minHeight: 20),
                  onPressed: vm.isScanning ? null : vm.refreshAdapters,
                ),
              ],
            ),
          ),
          const SizedBox(width: 8),

          // Target Input Field
          Expanded(
            flex: 4,
            child: SizedBox(
              height: 34,
              child: TextField(
                controller: _targetController,
                enabled: !vm.isScanning,
                onChanged: vm.setTargetInput,
                onSubmitted: (_) {
                  if (!vm.isScanning) vm.startSweep();
                },
                style: const TextStyle(
                  fontSize: 12,
                  fontFamily: 'monospace',
                  color: Colors.white,
                ),
                decoration: InputDecoration(
                  hintText: 'Target CIDR (e.g. 192.168.1.0/24), Range, or IP',
                  hintStyle: const TextStyle(fontSize: 11, color: Colors.white38),
                  prefixIcon: const Icon(Icons.radar, size: 16, color: AppTheme.primaryAccent),
                  suffixIcon: _targetController.text.isNotEmpty && !vm.isScanning
                      ? IconButton(
                          icon: const Icon(Icons.clear, size: 14),
                          onPressed: () {
                            _targetController.clear();
                            vm.setTargetInput('');
                          },
                        )
                      : null,
                ),
              ),
            ),
          ),
          const SizedBox(width: 8),

          // Preset Chips
          _buildPresetChip(
            label: 'Local /24',
            tooltip: 'Trace local subnet',
            onTap: vm.isScanning
                ? null
                : () {
                    final ip = vm.localHostIp;
                    final parts = ip.split('.');
                    if (parts.length == 4) {
                      final cidr = '${parts[0]}.${parts[1]}.${parts[2]}.0/24';
                      _targetController.text = cidr;
                      vm.setTargetInput(cidr);
                    }
                  },
          ),
          const SizedBox(width: 4),
          if (vm.gatewayIp != null) ...[
            _buildPresetChip(
              label: 'Gateway',
              tooltip: 'Trace to Default Gateway',
              onTap: vm.isScanning
                  ? null
                  : () {
                      _targetController.text = vm.gatewayIp!;
                      vm.setTargetInput(vm.gatewayIp!);
                    },
            ),
            const SizedBox(width: 4),
          ],
          _buildPresetChip(
            label: '8.8.8.8',
            tooltip: 'Trace to Google DNS',
            onTap: vm.isScanning
                ? null
                : () {
                    _targetController.text = '8.8.8.8';
                    vm.setTargetInput('8.8.8.8');
                  },
          ),
          const SizedBox(width: 4),
          _buildPresetChip(
            label: '1.1.1.1',
            tooltip: 'Trace to Cloudflare DNS',
            onTap: vm.isScanning
                ? null
                : () {
                    _targetController.text = '1.1.1.1';
                    vm.setTargetInput('1.1.1.1');
                  },
          ),

          const SizedBox(width: 12),

          // Concurrency Selector Dropdown
          Container(
            height: 34,
            padding: const EdgeInsets.symmetric(horizontal: 8),
            decoration: BoxDecoration(
              color: AppTheme.inputFill,
              borderRadius: BorderRadius.circular(6),
              border: Border.all(color: const Color(0xFF3E3E42)),
            ),
            child: DropdownButtonHideUnderline(
              child: DropdownButton<int>(
                value: vm.concurrency,
                dropdownColor: AppTheme.surfaceContainerHigh,
                style: const TextStyle(fontSize: 11, color: Colors.white70),
                onChanged: vm.isScanning ? null : (v) => v != null ? vm.setConcurrency(v) : null,
                items: const [
                  DropdownMenuItem(value: 2, child: Text('2 Workers')),
                  DropdownMenuItem(value: 4, child: Text('4 Workers')),
                  DropdownMenuItem(value: 8, child: Text('8 Workers')),
                  DropdownMenuItem(value: 16, child: Text('16 Workers')),
                ],
              ),
            ),
          ),
          const SizedBox(width: 8),

          // Max Hops Dropdown
          Container(
            height: 34,
            padding: const EdgeInsets.symmetric(horizontal: 8),
            decoration: BoxDecoration(
              color: AppTheme.inputFill,
              borderRadius: BorderRadius.circular(6),
              border: Border.all(color: const Color(0xFF3E3E42)),
            ),
            child: DropdownButtonHideUnderline(
              child: DropdownButton<int>(
                value: vm.maxHops,
                dropdownColor: AppTheme.surfaceContainerHigh,
                style: const TextStyle(fontSize: 11, color: Colors.white70),
                onChanged: vm.isScanning ? null : (v) => v != null ? vm.setMaxHops(v) : null,
                items: const [
                  DropdownMenuItem(value: 8, child: Text('Max 8 Hops')),
                  DropdownMenuItem(value: 15, child: Text('Max 15 Hops')),
                  DropdownMenuItem(value: 25, child: Text('Max 25 Hops')),
                ],
              ),
            ),
          ),

          const SizedBox(width: 12),

          // Start / Stop Action Button
          SizedBox(
            height: 34,
            child: vm.isScanning
                ? FilledButton.icon(
                    onPressed: vm.cancelSweep,
                    icon: const Icon(Icons.stop, size: 16),
                    label: const Text('Cancel Sweep', style: TextStyle(fontSize: 12)),
                    style: FilledButton.styleFrom(
                      backgroundColor: const Color(0xFFEF4444),
                      foregroundColor: Colors.white,
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(6)),
                    ),
                  )
                : FilledButton.icon(
                    onPressed: vm.startSweep,
                    icon: const Icon(Icons.play_arrow, size: 16),
                    label: const Text('Start Sweep', style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold)),
                    style: FilledButton.styleFrom(
                      backgroundColor: AppTheme.primaryAccent,
                      foregroundColor: Colors.white,
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(6)),
                    ),
                  ),
          ),

          const SizedBox(width: 16),

          // Instant Search Filter Field
          Expanded(
            flex: 2,
            child: SizedBox(
              height: 34,
              child: TextField(
                controller: _searchController,
                onChanged: (text) {
                  setState(() {});
                  vm.setSearchQuery(text);
                },
                style: const TextStyle(fontSize: 11, color: Colors.white),
                decoration: InputDecoration(
                  hintText: 'Filter nodes / devices...',
                  hintStyle: const TextStyle(fontSize: 11, color: Colors.white38),
                  prefixIcon: const Icon(Icons.search, size: 15, color: Colors.white54),
                  suffixIcon: _searchController.text.isNotEmpty
                      ? InkWell(
                          onTap: () {
                            _searchController.clear();
                            setState(() {});
                            vm.setSearchQuery('');
                          },
                          child: const Icon(Icons.clear, size: 14),
                        )
                      : null,
                ),
              ),
            ),
          ),
        ],
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
          padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 6),
          decoration: BoxDecoration(
            color: AppTheme.surfaceContainer,
            borderRadius: BorderRadius.circular(4),
            border: Border.all(color: AppTheme.border),
          ),
          child: Text(
            label,
            style: const TextStyle(
              fontSize: 10.5,
              fontWeight: FontWeight.w500,
              color: Colors.white70,
            ),
          ),
        ),
      ),
    );
  }
}
