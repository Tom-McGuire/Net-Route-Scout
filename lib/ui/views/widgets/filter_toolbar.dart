import 'dart:async';
import 'package:material_ui/material_ui.dart';
import 'package:flutter/services.dart';
import 'package:network_suite_shared/network_suite_shared.dart';
import 'package:provider/provider.dart';
import 'package:net_route_scout/domain/models/unknown_device_entry.dart';
import 'package:net_route_scout/ui/view_models/topology_view_model.dart';
import 'device_library_dialog.dart';
import 'edit_device_dialog.dart';

class FilterToolbar extends StatefulWidget {
  const FilterToolbar({super.key});

  @override
  State<FilterToolbar> createState() => _FilterToolbarState();
}

class _FilterToolbarState extends State<FilterToolbar> {
  final TextEditingController _searchController = TextEditingController();
  final TextEditingController _ipController = TextEditingController();
  final TextEditingController _macController = TextEditingController();

  Timer? _searchDebounce;
  Timer? _ipDebounce;
  Timer? _macDebounce;

  @override
  void initState() {
    super.initState();
    final vm = context.read<TopologyViewModel>();
    _searchController.text = vm.searchQuery;
    _ipController.text = vm.ipFilter;
    _macController.text = vm.macFilter;
  }

  @override
  void dispose() {
    _searchDebounce?.cancel();
    _ipDebounce?.cancel();
    _macDebounce?.cancel();
    _searchController.dispose();
    _ipController.dispose();
    _macController.dispose();
    super.dispose();
  }

  void _syncControllersWithFilter(TopologyViewModel vm) {
    if (_searchController.text != vm.searchQuery && !(_searchDebounce?.isActive ?? false)) {
      _searchController.text = vm.searchQuery;
    }
    if (_ipController.text != vm.ipFilter && !(_ipDebounce?.isActive ?? false)) {
      _ipController.text = vm.ipFilter;
    }
    if (_macController.text != vm.macFilter && !(_macDebounce?.isActive ?? false)) {
      _macController.text = vm.macFilter;
    }
  }

  @override
  Widget build(BuildContext context) {
    final vm = context.watch<TopologyViewModel>();
    _syncControllersWithFilter(vm);

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.surfaceContainer,
        border: Border(
          bottom: BorderSide(color: Theme.of(context).dividerColor),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Row 1: Unified Search + Dedicated IP Filter + Dedicated MAC Filter + Auto-Detected Switch
          Row(
            children: [
              // 1. Unified Search Input
              Expanded(
                flex: 3,
                child: SizedBox(
                  height: 34,
                  child: TextField(
                    controller: _searchController,
                    onChanged: (val) {
                      setState(() {});
                      _searchDebounce?.cancel();
                      _searchDebounce = Timer(
                        const Duration(milliseconds: 180),
                        () => vm.setSearchQuery(val),
                      );
                    },
                    style: const TextStyle(fontSize: 12),
                    decoration: InputDecoration(
                      hintText: 'Filter nodes / devices...',
                      prefixIcon: const Icon(Icons.search, size: 16),
                      suffixIcon: _searchController.text.isNotEmpty
                          ? IconButton(
                              icon: const Icon(Icons.clear, size: 14),
                              onPressed: () {
                                _searchDebounce?.cancel();
                                _searchController.clear();
                                vm.setSearchQuery('');
                              },
                            )
                          : null,
                    ),
                  ),
                ),
              ),
              const SizedBox(width: 10),

              // 2. Dedicated IP Address Filter (Monospace)
              Expanded(
                flex: 2,
                child: SizedBox(
                  height: 34,
                  child: TextField(
                    controller: _ipController,
                    onChanged: (val) {
                      setState(() {});
                      _ipDebounce?.cancel();
                      _ipDebounce = Timer(
                        const Duration(milliseconds: 180),
                        () => vm.setIpFilter(val),
                      );
                    },
                    style: const TextStyle(
                      fontSize: 12,
                      fontFamily: 'monospace',
                    ),
                    decoration: InputDecoration(
                      hintText: 'Search IP (e.g. 192.168.1.1)...',
                      prefixIcon: const Icon(Icons.lan_outlined, size: 15),
                      suffixIcon: _ipController.text.isNotEmpty
                          ? IconButton(
                              icon: const Icon(Icons.clear, size: 14),
                              onPressed: () {
                                _ipDebounce?.cancel();
                                _ipController.clear();
                                vm.setIpFilter('');
                              },
                            )
                          : null,
                    ),
                  ),
                ),
              ),
              const SizedBox(width: 10),

              // 3. Dedicated MAC / OUI Filter (Monospace)
              Expanded(
                flex: 2,
                child: SizedBox(
                  height: 34,
                  child: TextField(
                    controller: _macController,
                    onChanged: (val) {
                      setState(() {});
                      _macDebounce?.cancel();
                      _macDebounce = Timer(
                        const Duration(milliseconds: 180),
                        () => vm.setMacFilter(val),
                      );
                    },
                    style: const TextStyle(
                      fontSize: 12,
                      fontFamily: 'monospace',
                    ),
                    decoration: InputDecoration(
                      hintText: 'Search MAC / OUI (e.g. 00:50:56)...',
                      prefixIcon: const Icon(Icons.memory, size: 16),
                      suffixIcon: _macController.text.isNotEmpty
                          ? IconButton(
                              icon: const Icon(Icons.clear, size: 14),
                              onPressed: () {
                                _macDebounce?.cancel();
                                _macController.clear();
                                vm.setMacFilter('');
                              },
                            )
                          : null,
                    ),
                  ),
                ),
              ),
              const SizedBox(width: 10),

              // 4. Auto-Detected Switch
              _buildAutoDetectedSwitch(context, vm),

              // 5. Clear All Filters Button
              if (vm.hasActiveFilter) ...[
                const SizedBox(width: 10),
                TextButton.icon(
                  onPressed: () {
                    _searchDebounce?.cancel();
                    _ipDebounce?.cancel();
                    _macDebounce?.cancel();
                    _searchController.clear();
                    _ipController.clear();
                    _macController.clear();
                    vm.resetFilters();
                  },
                  icon: const Icon(Icons.filter_alt_off, size: 15),
                  label: const Text(
                    'Clear All Filters',
                    style: TextStyle(fontSize: 12),
                  ),
                  style: TextButton.styleFrom(
                    foregroundColor: Theme.of(context).colorScheme.primary,
                  ),
                ),
              ],
            ],
          ),
          const SizedBox(height: 8),

          // Row 2: Devices Quick-Filter Row
          _buildDevicesRow(context, vm),
        ],
      ),
    );
  }

  Widget _buildAutoDetectedSwitch(BuildContext context, TopologyViewModel vm) {
    return Container(
      height: 34,
      padding: const EdgeInsets.symmetric(horizontal: 10),
      decoration: BoxDecoration(
        color: vm.showAutoDetected
            ? Theme.of(context).colorScheme.primaryContainer.withValues(alpha: 0.3)
            : const Color(0xFF252526),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(
          color: vm.showAutoDetected
              ? Theme.of(context).colorScheme.primary.withValues(alpha: 0.5)
              : const Color(0xFF3E3E42),
        ),
      ),
      child: Tooltip(
        message: vm.showAutoDetected
            ? 'Auto-detected devices are visible (Toggle to hide)'
            : 'Auto-detected devices are hidden by default (Toggle to show)',
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              Icons.sensors,
              size: 14,
              color: vm.showAutoDetected
                  ? Theme.of(context).colorScheme.primary
                  : Colors.grey,
            ),
            const SizedBox(width: 6),
            const Text(
              'Auto-Detected',
              style: TextStyle(fontWeight: FontWeight.bold, fontSize: 11),
            ),
            const SizedBox(width: 6),
            SizedBox(
              height: 20,
              width: 32,
              child: FittedBox(
                fit: BoxFit.contain,
                child: Switch(
                  value: vm.showAutoDetected,
                  onChanged: (val) => vm.setShowAutoDetected(val),
                  materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildDevicesRow(BuildContext context, TopologyViewModel vm) {
    final knownCustom = vm.knownCustomDevices;
    final visibleUnknown = vm.visibleUnknownDevices;
    final selectedKeys = vm.selectedDeviceKeys;
    final deviceCounts = vm.deviceCounts;

    return Row(
      children: [
        const Padding(
          padding: EdgeInsets.only(right: 8.0),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(Icons.devices, size: 14, color: Colors.blueAccent),
              SizedBox(width: 4),
              Text(
                'DEVICES:',
                style: TextStyle(
                  fontSize: 10,
                  fontWeight: FontWeight.bold,
                  color: Colors.grey,
                  letterSpacing: 0.5,
                ),
              ),
            ],
          ),
        ),
        Expanded(
          child: SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: Row(
              children: [
                // 1. Known Custom Library Devices (Shown by default)
                ...knownCustom.map((device) {
                  final normMac = SharedDevice.normalizeMac(device.macAddress);
                  final isSelected = selectedKeys.contains(normMac);
                  final count = deviceCounts[normMac] ?? 0;
                  final catColor = _getCategoryColor(device.deviceType);

                  return Padding(
                    padding: const EdgeInsets.only(right: 6.0),
                    child: GestureDetector(
                      onSecondaryTapDown: (details) =>
                          _showDeviceMenu(details, device, vm),
                      child: FilterChip(
                        selected: isSelected,
                        showCheckmark: false,
                        labelPadding: const EdgeInsets.symmetric(horizontal: 4),
                        materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
                        visualDensity: VisualDensity.compact,
                        avatar: CircleAvatar(
                          radius: 5,
                          backgroundColor: catColor,
                        ),
                        label: Text(
                          '${device.name} ($count)',
                          style: TextStyle(
                            fontSize: 11,
                            fontWeight: isSelected ? FontWeight.bold : FontWeight.normal,
                            color: isSelected ? Colors.white : Colors.grey.shade400,
                          ),
                        ),
                        selectedColor: catColor.withValues(alpha: 0.35),
                        backgroundColor: const Color(0xFF252526),
                        side: BorderSide(
                          color: isSelected ? catColor : const Color(0xFF3E3E42),
                          width: 1,
                        ),
                        onSelected: (_) => vm.toggleDevicePill(device.macAddress),
                        tooltip: 'MAC: ${device.macAddress}\nRight-click for options',
                      ),
                    ),
                  );
                }),

                // 2. Unknown / Auto-Detected Devices (Shown if unhidden or toggle enabled)
                if (visibleUnknown.isNotEmpty) ...[
                  if (knownCustom.isNotEmpty) ...[
                    const SizedBox(width: 4),
                    Container(
                      height: 18,
                      width: 1,
                      color: Theme.of(context).dividerColor.withValues(alpha: 0.3),
                    ),
                    const SizedBox(width: 8),
                  ],

                  ...visibleUnknown.map((entry) {
                    final isSelected = selectedKeys.contains(entry.key);
                    final count = deviceCounts[entry.key] ?? 1;

                    return Padding(
                      padding: const EdgeInsets.only(right: 6.0),
                      child: GestureDetector(
                        onSecondaryTapDown: (details) =>
                            _showUnknownDeviceMenu(details, entry, vm),
                        child: FilterChip(
                          selected: isSelected,
                          showCheckmark: false,
                          labelPadding: const EdgeInsets.symmetric(horizontal: 4),
                          materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
                          visualDensity: VisualDensity.compact,
                          avatar: const CircleAvatar(
                            radius: 5,
                            backgroundColor: Colors.grey,
                          ),
                          label: Text(
                            '${entry.displayName} ($count)',
                            style: TextStyle(
                              fontSize: 11,
                              fontWeight: isSelected ? FontWeight.bold : FontWeight.normal,
                              color: isSelected ? Colors.white : Colors.grey.shade400,
                            ),
                          ),
                          selectedColor: Colors.blueAccent.withValues(alpha: 0.35),
                          backgroundColor: const Color(0xFF252526),
                          side: BorderSide(
                            color: isSelected ? Colors.blueAccent : const Color(0xFF3E3E42),
                            width: 1,
                          ),
                          onSelected: (_) => vm.toggleDevicePill(entry.key),
                          tooltip: 'Unknown device (${entry.ip ?? entry.macAddress ?? entry.key})\nRight-click to name or hide',
                        ),
                      ),
                    );
                  }),
                ],

                // 3. Manage ActionChip
                Padding(
                  padding: const EdgeInsets.only(right: 6.0),
                  child: ActionChip(
                    avatar: const Icon(Icons.settings_outlined, size: 13),
                    label: const Text('Manage', style: TextStyle(fontSize: 11)),
                    materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
                    visualDensity: VisualDensity.compact,
                    backgroundColor: const Color(0xFF252526),
                    side: const BorderSide(color: Color(0xFF3E3E42), width: 1),
                    tooltip: 'Manage device library and visibility in Net Route Scout',
                    onPressed: () => DeviceLibraryDialog.show(context),
                  ),
                ),

                // 4. Common Path Indicator Pill when 2+ devices are selected
                if (vm.selectedDeviceKeys.length >= 2) ...[
                  const SizedBox(width: 4),
                  Container(
                    height: 24,
                    padding: const EdgeInsets.symmetric(horizontal: 8),
                    decoration: BoxDecoration(
                      color: const Color(0xFFF59E0B).withValues(alpha: 0.18),
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(
                        color: const Color(0xFFF59E0B).withValues(alpha: 0.5),
                      ),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        const Icon(Icons.alt_route, size: 13, color: Color(0xFFF59E0B)),
                        const SizedBox(width: 4),
                        Text(
                          'Common Path: ${vm.commonPathNodeIds.length} hops',
                          style: const TextStyle(
                            fontSize: 11,
                            fontWeight: FontWeight.bold,
                            color: Color(0xFFF59E0B),
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
      ],
    );
  }

  Future<void> _showDeviceMenu(
    TapDownDetails details,
    SharedDevice device,
    TopologyViewModel vm,
  ) async {
    final overlay = Overlay.of(context).context.findRenderObject() as RenderBox?;
    if (overlay == null) return;
    final pos = details.globalPosition;
    final choice = await showMenu<String>(
      context: context,
      position: RelativeRect.fromRect(
        Rect.fromLTWH(pos.dx, pos.dy, 1, 1),
        Offset.zero & overlay.size,
      ),
      items: [
        PopupMenuItem(
          value: 'filter',
          child: Row(
            children: [
              const Icon(Icons.filter_alt, size: 16),
              const SizedBox(width: 8),
              Text('Toggle Filter (${device.name})'),
            ],
          ),
        ),
        const PopupMenuItem(
          value: 'edit',
          child: Row(
            children: [
              Icon(Icons.edit, size: 16),
              SizedBox(width: 8),
              Text('Edit Device in Shared Library'),
            ],
          ),
        ),
        const PopupMenuItem(
          value: 'hide',
          child: Row(
            children: [
              Icon(Icons.visibility_off, size: 16),
              SizedBox(width: 8),
              Text('Hide from Device Filters'),
            ],
          ),
        ),
        const PopupMenuDivider(),
        PopupMenuItem(
          value: 'copy_mac',
          child: Row(
            children: [
              const Icon(Icons.copy, size: 16),
              const SizedBox(width: 8),
              Text('Copy MAC (${device.macAddress})'),
            ],
          ),
        ),
      ],
    );
    if (choice == null || !mounted) return;
    switch (choice) {
      case 'filter':
        vm.toggleDevicePill(device.macAddress);
        break;
      case 'edit':
        showDialog(
          context: context,
          builder: (_) => EditDeviceDialog(
            macAddress: device.macAddress,
            initialName: device.name,
            initialCategory: device.deviceType,
            initialVendor: device.vendor,
            initialNotes: device.notes,
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
              );
            },
          ),
        );
        break;
      case 'hide':
        vm.toggleDeviceVisibility(device.macAddress);
        break;
      case 'copy_mac':
        await Clipboard.setData(ClipboardData(text: device.macAddress));
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('Copied MAC ${device.macAddress}')),
          );
        }
        break;
    }
  }

  Future<void> _showUnknownDeviceMenu(
    TapDownDetails details,
    UnknownDeviceEntry entry,
    TopologyViewModel vm,
  ) async {
    final overlay = Overlay.of(context).context.findRenderObject() as RenderBox?;
    if (overlay == null) return;
    final pos = details.globalPosition;
    final choice = await showMenu<String>(
      context: context,
      position: RelativeRect.fromRect(
        Rect.fromLTWH(pos.dx, pos.dy, 1, 1),
        Offset.zero & overlay.size,
      ),
      items: [
        PopupMenuItem(
          value: 'filter',
          child: Row(
            children: [
              const Icon(Icons.filter_alt, size: 16),
              const SizedBox(width: 8),
              Text('Toggle Filter (${entry.displayName})'),
            ],
          ),
        ),
        const PopupMenuItem(
          value: 'edit',
          child: Row(
            children: [
              Icon(Icons.save, size: 16),
              SizedBox(width: 8),
              Text('Save & Name in Shared Library'),
            ],
          ),
        ),
        const PopupMenuItem(
          value: 'hide',
          child: Row(
            children: [
              Icon(Icons.visibility_off, size: 16),
              SizedBox(width: 8),
              Text('Hide from Device Filters'),
            ],
          ),
        ),
        const PopupMenuDivider(),
        if (entry.macAddress != null && entry.macAddress!.isNotEmpty)
          PopupMenuItem(
            value: 'copy_mac',
            child: Row(
              children: [
                const Icon(Icons.copy, size: 16),
                const SizedBox(width: 8),
                Text('Copy MAC (${entry.macAddress})'),
              ],
            ),
          ),
        if (entry.ip != null && entry.ip!.isNotEmpty)
          PopupMenuItem(
            value: 'copy_ip',
            child: Row(
              children: [
                const Icon(Icons.copy, size: 16),
                const SizedBox(width: 8),
                Text('Copy IP (${entry.ip})'),
              ],
            ),
          ),
      ],
    );
    if (choice == null || !mounted) return;
    switch (choice) {
      case 'filter':
        vm.toggleDevicePill(entry.key);
        break;
      case 'edit':
        showDialog(
          context: context,
          builder: (_) => EditDeviceDialog(
            macAddress: entry.macAddress ?? '',
            initialName: entry.displayName.startsWith('Device ') ? '' : entry.displayName,
            initialCategory: 'other',
            initialVendor: entry.vendor,
            initialIp: entry.ip,
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
                ip: ip.isNotEmpty ? ip : (entry.ip ?? ''),
              );
            },
          ),
        );
        break;
      case 'hide':
        vm.toggleDeviceVisibility(entry.key);
        break;
      case 'copy_mac':
        if (entry.macAddress != null) {
          await Clipboard.setData(ClipboardData(text: entry.macAddress!));
          if (mounted) {
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(content: Text('Copied MAC ${entry.macAddress}')),
            );
          }
        }
        break;
      case 'copy_ip':
        if (entry.ip != null) {
          await Clipboard.setData(ClipboardData(text: entry.ip!));
          if (mounted) {
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(content: Text('Copied IP ${entry.ip}')),
            );
          }
        }
        break;
    }
  }

  Color _getCategoryColor(String? catKey) {
    if (catKey == null) return Colors.blueAccent;
    switch (catKey.toLowerCase()) {
      case 'router':
      case 'gateway':
        return const Color(0xFFF59E0B);
      case 'switch':
        return const Color(0xFF38BDF8);
      case 'server':
        return const Color(0xFF818CF8);
      case 'workstation':
      case 'pc':
        return const Color(0xFF10B981);
      case 'printer':
        return const Color(0xFFA855F7);
      case 'mobile':
      case 'phone':
        return const Color(0xFFEC4899);
      default:
        return const Color(0xFF007ACC);
    }
  }
}
