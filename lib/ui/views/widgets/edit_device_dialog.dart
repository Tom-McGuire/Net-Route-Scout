import 'package:flutter/material.dart';
import 'package:network_suite_shared/network_suite_shared.dart';
import 'package:net_route_scout/core/app_theme.dart';
import 'package:net_route_scout/domain/models/network_node.dart';

class EditDeviceDialog extends StatefulWidget {
  final NetworkNode node;
  final Function({
    required String ip,
    required String rawMac,
    required String name,
    String? category,
    String? vendor,
    String? notes,
  }) onSave;

  const EditDeviceDialog({
    super.key,
    required this.node,
    required this.onSave,
  });

  @override
  State<EditDeviceDialog> createState() => _EditDeviceDialogState();
}

class _EditDeviceDialogState extends State<EditDeviceDialog> {
  late final TextEditingController _nameController;
  late final TextEditingController _macController;
  late final TextEditingController _vendorController;
  late final TextEditingController _notesController;

  String? _selectedCategory;
  List<UnifiedDeviceCategory> _categories = [];

  @override
  void initState() {
    super.initState();
    final n = widget.node;
    _nameController = TextEditingController(text: n.sharedDeviceName ?? n.hostname ?? '');
    _macController = TextEditingController(text: n.macAddress ?? '');
    _vendorController = TextEditingController(text: n.vendor ?? '');
    _notesController = TextEditingController(text: n.sharedNotes ?? '');
    _selectedCategory = n.deviceCategoryKey;

    try {
      if (SharedDeviceDatabase.instance.isInitialized) {
        _categories = SharedDeviceDatabase.instance.getUnifiedCategories();
      }
    } catch (_) {}

    // Safeguard against label vs key mismatch or missing category keys
    if (_selectedCategory != null && _categories.isNotEmpty) {
      final hasKey = _categories.any((c) => c.key == _selectedCategory);
      if (!hasKey) {
        final byLabel = _categories.where(
          (c) => c.label.toLowerCase() == _selectedCategory!.toLowerCase(),
        );
        if (byLabel.isNotEmpty) {
          _selectedCategory = byLabel.first.key;
        } else {
          _selectedCategory = null;
        }
      }
    }
  }

  @override
  void dispose() {
    _nameController.dispose();
    _macController.dispose();
    _vendorController.dispose();
    _notesController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Dialog(
      backgroundColor: AppTheme.surfaceContainer,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(10),
        side: const BorderSide(color: AppTheme.border),
      ),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 480),
        child: Padding(
          padding: const EdgeInsets.all(20),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Header
              Row(
                children: [
                  Container(
                    padding: const EdgeInsets.all(6),
                    decoration: BoxDecoration(
                      color: AppTheme.primaryAccent.withValues(alpha: 0.2),
                      borderRadius: BorderRadius.circular(6),
                    ),
                    child: const Icon(Icons.edit_note, color: AppTheme.primaryAccent, size: 20),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Text(
                          'Edit Shared Device Identity',
                          style: TextStyle(
                            fontSize: 15,
                            fontWeight: FontWeight.bold,
                            color: Colors.white,
                          ),
                        ),
                        Text(
                          'IP: ${widget.node.ip} (Hop ${widget.node.hopDepth})',
                          style: const TextStyle(
                            fontSize: 11,
                            fontFamily: 'monospace',
                            color: Colors.white54,
                          ),
                        ),
                      ],
                    ),
                  ),
                  IconButton(
                    onPressed: () => Navigator.of(context).pop(),
                    icon: const Icon(Icons.close, size: 18),
                    splashRadius: 18,
                  ),
                ],
              ),
              const SizedBox(height: 16),
              const Divider(height: 1),
              const SizedBox(height: 16),

              // Friendly Name
              const Text('Device Friendly Name', style: TextStyle(fontSize: 11, color: Colors.white70)),
              const SizedBox(height: 5),
              TextField(
                controller: _nameController,
                autofocus: true,
                style: const TextStyle(fontSize: 13, color: Colors.white),
                decoration: const InputDecoration(
                  hintText: 'e.g. Core Switch, CEO MacBook, Office Printer',
                ),
              ),
              const SizedBox(height: 12),

              // MAC Address
              const Text('MAC Address (Hardware Identity Key)', style: TextStyle(fontSize: 11, color: Colors.white70)),
              const SizedBox(height: 5),
              TextField(
                controller: _macController,
                style: const TextStyle(fontSize: 12, fontFamily: 'monospace', color: Colors.white),
                decoration: const InputDecoration(
                  hintText: 'XX:XX:XX:XX:XX:XX',
                ),
              ),
              const SizedBox(height: 12),

              // Device Category Dropdown
              const Text('Device Category', style: TextStyle(fontSize: 11, color: Colors.white70)),
              const SizedBox(height: 5),
              Container(
                height: 38,
                padding: const EdgeInsets.symmetric(horizontal: 12),
                decoration: BoxDecoration(
                  color: AppTheme.inputFill,
                  borderRadius: BorderRadius.circular(6),
                  border: Border.all(color: const Color(0xFF3E3E42)),
                ),
                child: DropdownButtonHideUnderline(
                  child: DropdownButton<String>(
                    isExpanded: true,
                    value: _selectedCategory,
                    dropdownColor: AppTheme.surfaceContainerHighest,
                    hint: const Text('Select Category', style: TextStyle(fontSize: 12, color: Colors.white38)),
                    style: const TextStyle(fontSize: 12, color: Colors.white),
                    onChanged: (val) {
                      setState(() {
                        _selectedCategory = val;
                      });
                    },
                    items: _categories.map((cat) {
                      return DropdownMenuItem<String>(
                        value: cat.key,
                        child: Row(
                          children: [
                            Icon(cat.icon, size: 15, color: cat.color),
                            const SizedBox(width: 8),
                            Text(cat.label),
                          ],
                        ),
                      );
                    }).toList(),
                  ),
                ),
              ),
              const SizedBox(height: 12),

              // Hardware Vendor
              const Text('Hardware Vendor / OUI', style: TextStyle(fontSize: 11, color: Colors.white70)),
              const SizedBox(height: 5),
              TextField(
                controller: _vendorController,
                style: const TextStyle(fontSize: 12, color: Colors.white),
                decoration: const InputDecoration(
                  hintText: 'e.g. Cisco Systems, Apple, Lenovo',
                ),
              ),
              const SizedBox(height: 12),

              // Notes
              const Text('Notes', style: TextStyle(fontSize: 11, color: Colors.white70)),
              const SizedBox(height: 5),
              TextField(
                controller: _notesController,
                maxLines: 2,
                style: const TextStyle(fontSize: 12, color: Colors.white),
                decoration: const InputDecoration(
                  hintText: 'Physical location, connected switchport, purpose...',
                ),
              ),
              const SizedBox(height: 20),

              // Actions
              Wrap(
                alignment: WrapAlignment.end,
                spacing: 10,
                runSpacing: 8,
                children: [
                  OutlinedButton(
                    onPressed: () => Navigator.of(context).pop(),
                    style: OutlinedButton.styleFrom(
                      side: const BorderSide(color: Color(0xFF4A4A4A)),
                    ),
                    child: const Text('Cancel'),
                  ),
                  FilledButton.icon(
                    onPressed: () {
                      final rawMac = _macController.text.trim();
                      if (rawMac.isEmpty) {
                        ScaffoldMessenger.of(context).hideCurrentSnackBar();
                        ScaffoldMessenger.of(context).showSnackBar(
                          const SnackBar(content: Text('MAC address is required to store in Shared Device DB')),
                        );
                        return;
                      }

                      if (!SharedDevice.isValidMac(rawMac)) {
                        ScaffoldMessenger.of(context).hideCurrentSnackBar();
                        ScaffoldMessenger.of(context).showSnackBar(
                          const SnackBar(content: Text('Invalid MAC address format. Expected 6 hex pairs, e.g. 00:1A:2B:3C:4D:5E')),
                        );
                        return;
                      }

                      widget.onSave(
                        ip: widget.node.ip,
                        rawMac: rawMac,
                        name: _nameController.text.trim(),
                        category: _selectedCategory,
                        vendor: _vendorController.text.trim(),
                        notes: _notesController.text.trim(),
                      );

                      Navigator.of(context).pop();
                    },
                    icon: const Icon(Icons.save, size: 16),
                    label: const Text('Save to Shared Database'),
                    style: FilledButton.styleFrom(
                      backgroundColor: AppTheme.primaryAccent,
                    ),
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
