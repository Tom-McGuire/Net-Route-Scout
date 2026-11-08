import 'package:flutter/material.dart';
import 'package:network_suite_shared/network_suite_shared.dart';
import 'package:provider/provider.dart';
import 'package:net_route_scout/ui/view_models/topology_view_model.dart';
import 'edit_device_dialog.dart';

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

class _DeviceLibraryDialogState extends State<DeviceLibraryDialog> {
  final TextEditingController _searchCtrl = TextEditingController();
  String _searchQuery = '';

  @override
  void dispose() {
    _searchCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final vm = context.watch<TopologyViewModel>();
    final hiddenMacs = vm.hiddenDeviceMacs;
    final allDevices = SharedDeviceDatabase.instance.isInitialized
        ? SharedDeviceDatabase.instance.getAllDevices()
        : <SharedDevice>[];

    // Filter by search query
    final filtered = allDevices.where((d) {
      if (_searchQuery.isEmpty) return true;
      final q = _searchQuery.toLowerCase();
      return d.name.toLowerCase().contains(q) ||
          d.macAddress.toLowerCase().contains(q) ||
          (d.vendor?.toLowerCase().contains(q) ?? false);
    }).toList();

    return Dialog(
      backgroundColor: const Color(0xFF1E1E1E),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 620, maxHeight: 680),
        child: Padding(
          padding: const EdgeInsets.all(20.0),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              // Header
              Row(
                children: [
                  const Icon(Icons.devices, size: 20, color: Color(0xFF38BDF8)),
                  const SizedBox(width: 10),
                  Text(
                    'Device Library (${allDevices.length})',
                    style: const TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.bold,
                      color: Colors.white,
                    ),
                  ),
                  const Spacer(),
                  IconButton(
                    icon: const Icon(Icons.close, size: 20),
                    onPressed: () => Navigator.of(context).pop(),
                  ),
                ],
              ),
              const SizedBox(height: 6),
              const Text(
                'Manage known devices registered in the shared library. Toggle the eye icon to show or hide quick-filter pills in Net Route Scout.',
                style: TextStyle(fontSize: 12, color: Colors.white70),
              ),
              const SizedBox(height: 12),

              // Search Bar
              TextField(
                controller: _searchCtrl,
                onChanged: (val) => setState(() => _searchQuery = val.trim()),
                style: const TextStyle(fontSize: 13),
                decoration: InputDecoration(
                  hintText: 'Search devices by name, MAC, or vendor...',
                  prefixIcon: const Icon(Icons.search, size: 16),
                  suffixIcon: _searchCtrl.text.isNotEmpty
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
                  contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(8),
                    borderSide: const BorderSide(color: Color(0xFF3E3E42)),
                  ),
                ),
              ),
              const SizedBox(height: 12),

              // List of Devices
              Expanded(
                child: filtered.isEmpty
                    ? Center(
                        child: Text(
                          _searchQuery.isNotEmpty
                              ? 'No matching devices found.'
                              : 'No devices registered in Shared Library.',
                          style: const TextStyle(color: Colors.grey, fontSize: 13),
                        ),
                      )
                    : ListView.separated(
                        itemCount: filtered.length,
                        separatorBuilder: (_, _) => const SizedBox(height: 6),
                        itemBuilder: (context, index) {
                          final device = filtered[index];
                          final normMac = SharedDevice.normalizeMac(device.macAddress);
                          final isHidden = hiddenMacs.contains(normMac);
                          final cat = device.category;
                          final activeCount = vm.deviceCounts[normMac] ?? 0;

                          return Opacity(
                            opacity: isHidden ? 0.5 : 1.0,
                            child: Container(
                              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                              decoration: BoxDecoration(
                                color: const Color(0xFF252526),
                                borderRadius: BorderRadius.circular(8),
                                border: Border.all(
                                  color: isHidden
                                      ? Colors.grey.withValues(alpha: 0.2)
                                      : const Color(0xFF38BDF8).withValues(alpha: 0.3),
                                ),
                              ),
                              child: Row(
                                children: [
                                  CircleAvatar(
                                    radius: 14,
                                    backgroundColor: const Color(0xFF38BDF8).withValues(alpha: 0.2),
                                    child: Icon(cat.icon, size: 15, color: const Color(0xFF38BDF8)),
                                  ),
                                  const SizedBox(width: 12),
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
                                            if (activeCount > 0) ...[
                                              const SizedBox(width: 6),
                                              Container(
                                                padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1),
                                                decoration: BoxDecoration(
                                                  color: const Color(0xFF10B981).withValues(alpha: 0.2),
                                                  borderRadius: BorderRadius.circular(4),
                                                ),
                                                child: Text(
                                                  '$activeCount in trace',
                                                  style: const TextStyle(
                                                    fontSize: 10,
                                                    color: Color(0xFF10B981),
                                                    fontWeight: FontWeight.bold,
                                                  ),
                                                ),
                                              ),
                                            ],
                                            if (isHidden) ...[
                                              const SizedBox(width: 6),
                                              Container(
                                                padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1),
                                                decoration: BoxDecoration(
                                                  color: Colors.amber.withValues(alpha: 0.2),
                                                  borderRadius: BorderRadius.circular(4),
                                                ),
                                                child: const Text(
                                                  'Hidden in Scout',
                                                  style: TextStyle(
                                                    fontSize: 10,
                                                    color: Colors.amber,
                                                    fontWeight: FontWeight.bold,
                                                  ),
                                                ),
                                              ),
                                            ],
                                          ],
                                        ),
                                        const SizedBox(height: 2),
                                        Text(
                                          '${device.macAddress} • ${device.vendor ?? "Unknown Vendor"}',
                                          style: const TextStyle(
                                            fontSize: 11,
                                            fontFamily: 'monospace',
                                            color: Colors.grey,
                                          ),
                                        ),
                                      ],
                                    ),
                                  ),
                                  // Visibility toggle button
                                  IconButton(
                                    icon: Icon(
                                      isHidden ? Icons.visibility_off : Icons.visibility,
                                      size: 18,
                                      color: isHidden ? Colors.grey : const Color(0xFF38BDF8),
                                    ),
                                    tooltip: isHidden
                                        ? 'Hidden from quick-filter pills (Click to show)'
                                        : 'Visible in quick-filter pills (Click to hide)',
                                    onPressed: () {
                                      vm.toggleDeviceVisibility(device.macAddress);
                                    },
                                  ),
                                  // Edit Button
                                  IconButton(
                                    icon: const Icon(Icons.edit_outlined, size: 18),
                                    tooltip: 'Edit Device Metadata',
                                    onPressed: () {
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
                                    },
                                  ),
                                ],
                              ),
                            ),
                          );
                        },
                      ),
              ),
              const SizedBox(height: 12),

              // Footer
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  OutlinedButton.icon(
                    icon: const Icon(Icons.add, size: 14),
                    label: const Text('Add Device', style: TextStyle(fontSize: 12)),
                    onPressed: () {
                      showDialog(
                        context: context,
                        builder: (_) => EditDeviceDialog(
                          macAddress: '',
                          initialName: '',
                          initialCategory: 'other',
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
                    },
                  ),
                  TextButton(
                    onPressed: () => Navigator.of(context).pop(),
                    child: const Text('Close'),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}
