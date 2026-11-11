import 'package:material_ui/material_ui.dart';
import 'package:network_suite_shared/network_suite_shared.dart';
import 'package:provider/provider.dart';
import 'package:net_route_scout/domain/models/unknown_device_entry.dart';
import 'package:net_route_scout/ui/view_models/topology_view_model.dart';
import 'edit_device_dialog.dart';

/// Modal dialog allowing users to manage devices in the Custom Library,
/// edit device details, and show/hide devices as filter options in the filter bar.
class DeviceLibraryDialog extends StatefulWidget {
  const DeviceLibraryDialog({super.key});

  static Future<void> show(BuildContext context) async {
    final vm = Provider.of<TopologyViewModel>(context, listen: false);
    await showDialog<void>(
      context: context,
      builder: (ctx) => ChangeNotifierProvider<TopologyViewModel>.value(
        value: vm,
        child: const DeviceLibraryDialog(),
      ),
    );
  }

  @override
  State<DeviceLibraryDialog> createState() => _DeviceLibraryDialogState();
}

class _DeviceLibraryDialogState extends State<DeviceLibraryDialog>
    with SingleTickerProviderStateMixin {
  late final TabController _tabController;
  final TextEditingController _searchCtrl = TextEditingController();
  String _searchQuery = '';

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 2, vsync: this);
  }

  @override
  void dispose() {
    _tabController.dispose();
    _searchCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final vm = context.watch<TopologyViewModel>();
    final theme = Theme.of(context);

    // Fetch all known devices (devices in database with custom names)
    final allKnown = vm.allKnownCustomDevices;
    final matchingKnown = allKnown.where((d) {
      if (_searchQuery.isEmpty) return true;
      final q = _searchQuery.toLowerCase();
      return d.name.toLowerCase().contains(q) ||
          d.macAddress.toLowerCase().contains(q) ||
          (d.vendor?.toLowerCase().contains(q) ?? false) ||
          (d.notes?.toLowerCase().contains(q) ?? false);
    }).toList();

    // Fetch all unknown devices (devices in database without custom names, and auto-detected nodes)
    final allUnknown = vm.allUnknownDevices;
    final matchingUnknown = allUnknown.where((d) {
      if (_searchQuery.isEmpty) return true;
      final q = _searchQuery.toLowerCase();
      return d.displayName.toLowerCase().contains(q) ||
          (d.macAddress?.toLowerCase().contains(q) ?? false) ||
          (d.ip?.toLowerCase().contains(q) ?? false) ||
          (d.vendor?.toLowerCase().contains(q) ?? false);
    }).toList();

    return Dialog(
      backgroundColor: const Color(0xFF1E1E1E),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      insetPadding: const EdgeInsets.symmetric(horizontal: 40, vertical: 24),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 720, maxHeight: 660),
        child: Padding(
          padding: const EdgeInsets.all(20),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              // Header
              Row(
                children: [
                  Container(
                    padding: const EdgeInsets.all(8),
                    decoration: BoxDecoration(
                      color: theme.colorScheme.primary.withValues(alpha: 0.15),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Icon(Icons.menu_book, color: theme.colorScheme.primary, size: 20),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Text(
                          'Custom Library',
                          style: TextStyle(
                            fontSize: 16,
                            fontWeight: FontWeight.bold,
                            color: Colors.white,
                          ),
                        ),
                        Text(
                          'Manage known and unknown devices in the shared database and configure filter visibility.',
                          style: TextStyle(fontSize: 12, color: Colors.grey.shade400),
                        ),
                      ],
                    ),
                  ),
                  FilledButton.tonalIcon(
                    icon: const Icon(Icons.add, size: 16),
                    label: const Text('Add Device'),
                    style: FilledButton.styleFrom(
                      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                    ),
                    onPressed: () {
                      _showEditDialog(
                        context: context,
                        vm: vm,
                        macAddress: '',
                        initialName: '',
                        initialCategory: 'other',
                      );
                    },
                  ),
                  const SizedBox(width: 8),
                  if (vm.hiddenDeviceMacs.isNotEmpty || vm.explicitlyShownMacs.isNotEmpty) ...[
                    TextButton.icon(
                      icon: const Icon(Icons.refresh, size: 16),
                      label: const Text('Reset Visibility', style: TextStyle(fontSize: 12)),
                      onPressed: () => vm.unhideAllDevices(),
                    ),
                    const SizedBox(width: 8),
                  ],
                  IconButton(
                    icon: const Icon(Icons.close, size: 20),
                    tooltip: 'Close',
                    onPressed: () => Navigator.of(context).pop(),
                  ),
                ],
              ),
              const SizedBox(height: 14),

              // Search Bar
              SizedBox(
                height: 36,
                child: TextField(
                  controller: _searchCtrl,
                  style: const TextStyle(fontSize: 12),
                  onChanged: (val) => setState(() => _searchQuery = val.trim()),
                  decoration: InputDecoration(
                    hintText: 'Search devices by name, MAC, IP, vendor, or notes...',
                    prefixIcon: const Icon(Icons.search, size: 16),
                    suffixIcon: _searchQuery.isNotEmpty
                        ? IconButton(
                            icon: const Icon(Icons.clear, size: 14),
                            onPressed: () {
                              _searchCtrl.clear();
                              setState(() => _searchQuery = '');
                            },
                          )
                        : null,
                    filled: true,
                    fillColor: const Color(0xFF252526),
                    contentPadding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(8),
                      borderSide: const BorderSide(color: Color(0xFF3E3E42)),
                    ),
                    enabledBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(8),
                      borderSide: const BorderSide(color: Color(0xFF3E3E42)),
                    ),
                  ),
                ),
              ),
              const SizedBox(height: 12),

              // Tabs
              TabBar(
                controller: _tabController,
                indicatorColor: theme.colorScheme.primary,
                tabs: [
                  Tab(
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        const Icon(Icons.verified_outlined, size: 16),
                        const SizedBox(width: 8),
                        Text('Known Devices (${matchingKnown.length})'),
                      ],
                    ),
                  ),
                  Tab(
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        const Icon(Icons.help_outline, size: 16),
                        const SizedBox(width: 8),
                        Text('Unknown Devices (${matchingUnknown.length})'),
                      ],
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 10),

              // Tab Views
              Expanded(
                child: TabBarView(
                  controller: _tabController,
                  children: [
                    _buildKnownDeviceList(context, vm, matchingKnown),
                    _buildUnknownDeviceList(context, vm, matchingUnknown),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildKnownDeviceList(
    BuildContext context,
    TopologyViewModel vm,
    List<SharedDevice> devices,
  ) {
    if (devices.isEmpty) {
      return Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.devices, size: 40, color: Colors.grey.shade600),
            const SizedBox(height: 10),
            Text(
              _searchQuery.isNotEmpty
                  ? 'No matching known devices found.'
                  : 'No known devices with custom names in database.',
              style: TextStyle(color: Colors.grey.shade400, fontSize: 13),
            ),
          ],
        ),
      );
    }

    final hiddenMacs = vm.hiddenDeviceMacs;
    final deviceCounts = vm.deviceCounts;

    return ListView.separated(
      itemCount: devices.length,
      separatorBuilder: (_, _) => const SizedBox(height: 6),
      itemBuilder: (context, index) {
        final device = devices[index];
        final normMac = SharedDevice.normalizeMac(device.macAddress);
        final isHidden = hiddenMacs.contains(normMac);
        final isVisible = !isHidden;
        final count = deviceCounts[normMac] ?? 0;

        return Opacity(
          opacity: isVisible ? 1.0 : 0.55,
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
            decoration: BoxDecoration(
              color: const Color(0xFF252526),
              borderRadius: BorderRadius.circular(8),
              border: Border.all(
                color: isVisible
                    ? Theme.of(context).colorScheme.primary.withValues(alpha: 0.35)
                    : const Color(0xFF3E3E42),
              ),
            ),
            child: Row(
              children: [
                // Category Icon
                CircleAvatar(
                  radius: 16,
                  backgroundColor: isVisible
                      ? Theme.of(context).colorScheme.primary.withValues(alpha: 0.2)
                      : Colors.grey.withValues(alpha: 0.2),
                  child: Icon(
                    device.category.icon,
                    size: 16,
                    color: isVisible ? Theme.of(context).colorScheme.primary : Colors.grey,
                  ),
                ),
                const SizedBox(width: 12),

                // Device Info
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Flexible(
                            child: Text(
                              device.name,
                              style: const TextStyle(
                                fontWeight: FontWeight.bold,
                                fontSize: 13,
                                color: Colors.white,
                              ),
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                          const SizedBox(width: 6),
                          Container(
                            padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1),
                            decoration: BoxDecoration(
                              color: const Color(0xFF10B981).withValues(alpha: 0.2),
                              borderRadius: BorderRadius.circular(4),
                            ),
                            child: const Text(
                              'Custom Name',
                              style: TextStyle(
                                fontSize: 10,
                                color: Color(0xFF10B981),
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                          ),
                          if (isHidden) ...[
                            const SizedBox(width: 6),
                            Container(
                              padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1),
                              decoration: BoxDecoration(
                                color: Colors.grey.withValues(alpha: 0.2),
                                borderRadius: BorderRadius.circular(4),
                              ),
                              child: const Text(
                                'Hidden from Filters',
                                style: TextStyle(
                                  fontSize: 10,
                                  color: Colors.grey,
                                  fontWeight: FontWeight.bold,
                                ),
                              ),
                            ),
                          ],
                          if (count > 0) ...[
                            const SizedBox(width: 6),
                            Container(
                              padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1),
                              decoration: BoxDecoration(
                                color: Colors.blueAccent.withValues(alpha: 0.2),
                                borderRadius: BorderRadius.circular(4),
                              ),
                              child: Text(
                                '$count in trace',
                                style: const TextStyle(
                                  fontSize: 10,
                                  color: Colors.blueAccent,
                                  fontWeight: FontWeight.bold,
                                ),
                              ),
                            ),
                          ],
                        ],
                      ),
                      const SizedBox(height: 2),
                      Text(
                        '${device.macAddress} • ${device.vendor ?? "Unknown Vendor"} • ${device.category.label}',
                        style: const TextStyle(
                          fontSize: 11,
                          fontFamily: 'monospace',
                          color: Colors.grey,
                        ),
                      ),
                      if (device.notes != null && device.notes!.trim().isNotEmpty) ...[
                        const SizedBox(height: 2),
                        Text(
                          device.notes!,
                          style: TextStyle(
                            fontSize: 11,
                            fontStyle: FontStyle.italic,
                            color: Colors.grey.shade400,
                          ),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ],
                    ],
                  ),
                ),

                // Visibility Toggle Button
                IconButton(
                  icon: Icon(
                    isVisible ? Icons.visibility : Icons.visibility_off,
                    size: 18,
                    color: isVisible ? Theme.of(context).colorScheme.primary : Colors.grey,
                  ),
                  tooltip: isVisible
                      ? 'Visible in filter bar (Click to hide)'
                      : 'Hidden from filter bar (Click to show)',
                  onPressed: () {
                    vm.toggleDeviceVisibility(normMac);
                  },
                ),

                // Edit Details Button
                IconButton(
                  icon: const Icon(Icons.edit_outlined, size: 18),
                  tooltip: 'Edit Device Details in Shared Library',
                  onPressed: () {
                    _showEditDialog(
                      context: context,
                      vm: vm,
                      macAddress: device.macAddress,
                      initialName: device.name,
                      initialCategory: device.deviceType,
                      initialVendor: device.vendor,
                      initialNotes: device.notes,
                    );
                  },
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  Widget _buildUnknownDeviceList(
    BuildContext context,
    TopologyViewModel vm,
    List<UnknownDeviceEntry> devices,
  ) {
    if (devices.isEmpty) {
      return Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.device_unknown, size: 40, color: Colors.grey.shade600),
            const SizedBox(height: 10),
            Text(
              _searchQuery.isNotEmpty
                  ? 'No matching unknown devices found.'
                  : 'No unknown devices found in database or scan.',
              style: TextStyle(color: Colors.grey.shade400, fontSize: 13),
            ),
          ],
        ),
      );
    }

    final deviceCounts = vm.deviceCounts;

    return ListView.separated(
      itemCount: devices.length,
      separatorBuilder: (_, _) => const SizedBox(height: 6),
      itemBuilder: (context, index) {
        final device = devices[index];
        final isVisible = !device.isHidden;
        final count = deviceCounts[device.key] ?? 0;

        return Opacity(
          opacity: isVisible ? 1.0 : 0.55,
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
            decoration: BoxDecoration(
              color: const Color(0xFF252526),
              borderRadius: BorderRadius.circular(8),
              border: Border.all(
                color: isVisible
                    ? Theme.of(context).colorScheme.primary.withValues(alpha: 0.35)
                    : const Color(0xFF3E3E42),
              ),
            ),
            child: Row(
              children: [
                // Category Icon
                CircleAvatar(
                  radius: 16,
                  backgroundColor: isVisible
                      ? Theme.of(context).colorScheme.primary.withValues(alpha: 0.2)
                      : Colors.grey.withValues(alpha: 0.2),
                  child: Icon(
                    Icons.help_outline,
                    size: 16,
                    color: isVisible ? Theme.of(context).colorScheme.primary : Colors.grey,
                  ),
                ),
                const SizedBox(width: 12),

                // Device Info
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Flexible(
                            child: Text(
                              device.displayName,
                              style: const TextStyle(
                                fontWeight: FontWeight.bold,
                                fontSize: 13,
                                color: Colors.white,
                              ),
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                          const SizedBox(width: 6),
                          Container(
                            padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1),
                            decoration: BoxDecoration(
                              color: Colors.amber.withValues(alpha: 0.2),
                              borderRadius: BorderRadius.circular(4),
                            ),
                            child: const Text(
                              'No Custom Name',
                              style: TextStyle(
                                fontSize: 10,
                                color: Colors.amber,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                          ),
                          if (!isVisible) ...[
                            const SizedBox(width: 6),
                            Container(
                              padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1),
                              decoration: BoxDecoration(
                                color: Colors.grey.withValues(alpha: 0.2),
                                borderRadius: BorderRadius.circular(4),
                              ),
                              child: const Text(
                                'Hidden from Filters',
                                style: TextStyle(
                                  fontSize: 10,
                                  color: Colors.grey,
                                  fontWeight: FontWeight.bold,
                                ),
                              ),
                            ),
                          ],
                          if (count > 0) ...[
                            const SizedBox(width: 6),
                            Container(
                              padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1),
                              decoration: BoxDecoration(
                                color: Colors.blueAccent.withValues(alpha: 0.2),
                                borderRadius: BorderRadius.circular(4),
                              ),
                              child: Text(
                                '$count in trace',
                                style: const TextStyle(
                                  fontSize: 10,
                                  color: Colors.blueAccent,
                                  fontWeight: FontWeight.bold,
                                ),
                              ),
                            ),
                          ],
                        ],
                      ),
                      const SizedBox(height: 2),
                      Text(
                        '${device.macAddress ?? "No MAC"} • ${device.ip ?? "No IP"} • ${device.vendor ?? "Unknown Vendor"}',
                        style: const TextStyle(
                          fontSize: 11,
                          fontFamily: 'monospace',
                          color: Colors.grey,
                        ),
                      ),
                    ],
                  ),
                ),

                // Visibility Toggle Button
                IconButton(
                  icon: Icon(
                    isVisible ? Icons.visibility : Icons.visibility_off,
                    size: 18,
                    color: isVisible ? Theme.of(context).colorScheme.primary : Colors.grey,
                  ),
                  tooltip: isVisible
                      ? 'Visible in filter bar (Click to hide)'
                      : 'Hidden from filter bar (Click to show)',
                  onPressed: () {
                    vm.toggleDeviceVisibility(device.key);
                  },
                ),

                // Edit / Name Details Button
                IconButton(
                  icon: const Icon(Icons.edit_outlined, size: 18),
                  tooltip: 'Give Custom Name & Details in Shared Library',
                  onPressed: () {
                    _showEditDialog(
                      context: context,
                      vm: vm,
                      macAddress: device.macAddress ?? '',
                      initialName: device.displayName.startsWith('Device ') ? '' : device.displayName,
                      initialIp: device.ip,
                      initialVendor: device.vendor,
                    );
                  },
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  void _showEditDialog({
    required BuildContext context,
    required TopologyViewModel vm,
    required String macAddress,
    String? initialName,
    String? initialCategory,
    String? initialVendor,
    String? initialNotes,
    String? initialIp,
  }) {
    showDialog<void>(
      context: context,
      builder: (_) => EditDeviceDialog(
        macAddress: macAddress,
        initialName: initialName,
        initialCategory: initialCategory ?? 'other',
        initialVendor: initialVendor,
        initialNotes: initialNotes,
        initialIp: initialIp,
        onSave: ({
          required String ip,
          required String rawMac,
          required String name,
          String? category,
          String? vendor,
          String? notes,
        }) {
          vm.updateDeviceMetadata(
            macAddress: rawMac,
            name: name,
            category: category,
            vendor: vendor,
            notes: notes,
            ip: ip.isNotEmpty ? ip : (initialIp ?? ''),
          );
        },
      ),
    );
  }
}
