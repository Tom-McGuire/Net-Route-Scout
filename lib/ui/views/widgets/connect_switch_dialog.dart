import 'package:material_ui/material_ui.dart';
import 'package:net_route_scout/core/app_theme.dart';
import 'package:net_route_scout/domain/models/network_node.dart';
import 'package:net_route_scout/ui/view_models/topology_view_model.dart';

class ConnectSwitchDialog extends StatefulWidget {
  final NetworkNode targetNode;
  final TopologyViewModel viewModel;

  const ConnectSwitchDialog({
    super.key,
    required this.targetNode,
    required this.viewModel,
  });

  static Future<void> show(BuildContext context, TopologyViewModel vm, NetworkNode node) {
    return showDialog<void>(
      context: context,
      builder: (ctx) => ConnectSwitchDialog(
        targetNode: node,
        viewModel: vm,
      ),
    );
  }

  @override
  State<ConnectSwitchDialog> createState() => _ConnectSwitchDialogState();
}

class _ConnectSwitchDialogState extends State<ConnectSwitchDialog> {
  String? _selectedSwitchId;
  final _portController = TextEditingController();
  bool _isCreatingNew = false;
  final _newSwitchNameController = TextEditingController();
  final _newSwitchIpController = TextEditingController();
  final _newSwitchModelController = TextEditingController();

  @override
  void initState() {
    super.initState();
    _portController.text = widget.targetNode.switchPort ?? '';
    _selectedSwitchId = widget.targetNode.connectedSwitchId;

    final available = widget.viewModel.availableSwitches
        .where((s) => s.id != widget.targetNode.id)
        .toList();

    if (_selectedSwitchId == null && available.isNotEmpty) {
      _selectedSwitchId = available.first.id;
    }
  }

  @override
  void dispose() {
    _portController.dispose();
    _newSwitchNameController.dispose();
    _newSwitchIpController.dispose();
    _newSwitchModelController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final availableSwitches = widget.viewModel.availableSwitches
        .where((s) => s.id != widget.targetNode.id)
        .toList();

    return AlertDialog(
      backgroundColor: AppTheme.surface,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(10),
        side: BorderSide(color: AppTheme.border),
      ),
      title: Row(
        children: [
          Container(
            padding: const EdgeInsets.all(6),
            decoration: BoxDecoration(
              color: AppTheme.cyan.withValues(alpha: 0.15),
              borderRadius: BorderRadius.circular(6),
            ),
            child: Icon(Icons.hub, color: AppTheme.cyan, size: 18),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  'Connect to Switch',
                  style: TextStyle(fontSize: 15, fontWeight: FontWeight.bold, color: AppTheme.textPrimary),
                ),
                Text(
                  widget.targetNode.displayName,
                  style: TextStyle(fontSize: 11, color: AppTheme.textSecondary),
                ),
              ],
            ),
          ),
        ],
      ),
      content: SizedBox(
        width: 440,
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              if (!_isCreatingNew) ...[
                if (availableSwitches.isEmpty) ...[
                  Container(
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: AppTheme.warning.withValues(alpha: 0.1),
                      borderRadius: BorderRadius.circular(6),
                      border: Border.all(color: AppTheme.warning.withValues(alpha: 0.3)),
                    ),
                    child: Row(
                      children: [
                        Icon(Icons.info_outline, size: 16, color: AppTheme.warning),
                        const SizedBox(width: 8),
                        Expanded(
                          child: Text(
                            'No switch nodes currently exist in this topology. Create a new switch below or right-click any node to define it as a switch.',
                            style: TextStyle(fontSize: 11.5, color: AppTheme.textSecondary),
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 14),
                ] else ...[
                  Text(
                    'Select Target Switch Node:',
                    style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: AppTheme.textPrimary),
                  ),
                  const SizedBox(height: 6),
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 10),
                    decoration: BoxDecoration(
                      color: AppTheme.inputFill,
                      borderRadius: BorderRadius.circular(6),
                      border: Border.all(color: AppTheme.borderSubtle),
                    ),
                    child: DropdownButtonHideUnderline(
                      child: DropdownButton<String>(
                        value: _selectedSwitchId,
                        isExpanded: true,
                        dropdownColor: AppTheme.surfaceElevated,
                        style: TextStyle(fontSize: 12, color: AppTheme.textPrimary),
                        onChanged: (val) {
                          if (val != null) setState(() => _selectedSwitchId = val);
                        },
                        items: availableSwitches.map((sw) {
                          return DropdownMenuItem<String>(
                            value: sw.id,
                            child: Row(
                              children: [
                                Icon(Icons.hub, size: 14, color: AppTheme.cyan),
                                const SizedBox(width: 8),
                                Expanded(
                                  child: Text(
                                    sw.displayName,
                                    overflow: TextOverflow.ellipsis,
                                  ),
                                ),
                                if (sw.ip != sw.displayName) ...[
                                  const SizedBox(width: 6),
                                  Text(
                                    '(${sw.ip})',
                                    style: TextStyle(fontSize: 10, color: AppTheme.textMuted),
                                  ),
                                ],
                              ],
                            ),
                          );
                        }).toList(),
                      ),
                    ),
                  ),
                  const SizedBox(height: 14),
                ],

                // Switch Port Label Input
                Text(
                  'Connected Switch Port (Optional):',
                  style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: AppTheme.textPrimary),
                ),
                const SizedBox(height: 6),
                TextField(
                  controller: _portController,
                  style: TextStyle(fontSize: 12, color: AppTheme.textPrimary),
                  decoration: InputDecoration(
                    hintText: 'e.g. Port 4, GigabitEthernet1/0/12...',
                    hintStyle: TextStyle(fontSize: 11, color: AppTheme.textMuted),
                    prefixIcon: Icon(Icons.cable, size: 14, color: AppTheme.cyan),
                    isDense: true,
                    filled: true,
                    fillColor: AppTheme.inputFill,
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(6),
                      borderSide: BorderSide(color: AppTheme.borderSubtle),
                    ),
                  ),
                ),
                const SizedBox(height: 14),

                // Button to toggle new switch creation
                TextButton.icon(
                  onPressed: () => setState(() => _isCreatingNew = true),
                  icon: Icon(Icons.add_circle_outline, size: 15, color: AppTheme.cyan),
                  label: Text(
                    '+ Create New Standalone Switch Node',
                    style: TextStyle(fontSize: 11.5, color: AppTheme.cyan),
                  ),
                ),
              ] else ...[
                // New Switch Form
                Text(
                  'Create Standalone Switch Node:',
                  style: TextStyle(fontSize: 12.5, fontWeight: FontWeight.bold, color: AppTheme.textPrimary),
                ),
                const SizedBox(height: 10),
                TextField(
                  controller: _newSwitchNameController,
                  style: TextStyle(fontSize: 12, color: AppTheme.textPrimary),
                  decoration: InputDecoration(
                    labelText: 'Switch Name (Required)',
                    hintText: 'e.g. Core Switch, Floor 2 Distribution Switch',
                    isDense: true,
                    filled: true,
                    fillColor: AppTheme.inputFill,
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(6),
                      borderSide: BorderSide(color: AppTheme.borderSubtle),
                    ),
                  ),
                ),
                const SizedBox(height: 10),
                TextField(
                  controller: _newSwitchIpController,
                  style: TextStyle(fontSize: 12, color: AppTheme.textPrimary),
                  decoration: InputDecoration(
                    labelText: 'Management IP (Optional)',
                    hintText: 'e.g. 192.168.1.2',
                    isDense: true,
                    filled: true,
                    fillColor: AppTheme.inputFill,
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(6),
                      borderSide: BorderSide(color: AppTheme.borderSubtle),
                    ),
                  ),
                ),
                const SizedBox(height: 10),
                TextField(
                  controller: _newSwitchModelController,
                  style: TextStyle(fontSize: 12, color: AppTheme.textPrimary),
                  decoration: InputDecoration(
                    labelText: 'Model / Hardware (Optional)',
                    hintText: 'e.g. Cisco Catalyst 3850, Aruba 2930F',
                    isDense: true,
                    filled: true,
                    fillColor: AppTheme.inputFill,
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(6),
                      borderSide: BorderSide(color: AppTheme.borderSubtle),
                    ),
                  ),
                ),
                const SizedBox(height: 8),
                TextButton.icon(
                  onPressed: () => setState(() => _isCreatingNew = false),
                  icon: Icon(Icons.arrow_back, size: 14, color: AppTheme.textSecondary),
                  label: Text('Back to existing switches', style: TextStyle(fontSize: 11, color: AppTheme.textSecondary)),
                ),
              ],
            ],
          ),
        ),
      ),
      actions: [
        if (widget.targetNode.connectedSwitchId != null)
          TextButton(
            onPressed: () {
              widget.viewModel.disconnectNodeFromSwitch(widget.targetNode.id);
              Navigator.of(context).pop();
            },
            child: Text('Disconnect Switch', style: TextStyle(color: AppTheme.error, fontSize: 12)),
          ),
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: Text('Cancel', style: TextStyle(color: AppTheme.textSecondary, fontSize: 12)),
        ),
        FilledButton(
          onPressed: () {
            if (_isCreatingNew) {
              final name = _newSwitchNameController.text.trim();
              if (name.isEmpty) return;
              final sw = widget.viewModel.addStandaloneSwitch(
                name: name,
                ip: _newSwitchIpController.text.trim().isNotEmpty ? _newSwitchIpController.text.trim() : null,
                model: _newSwitchModelController.text.trim().isNotEmpty ? _newSwitchModelController.text.trim() : null,
              );
              widget.viewModel.connectNodeToSwitch(
                widget.targetNode.id,
                sw.id,
                portLabel: _portController.text.trim().isNotEmpty ? _portController.text.trim() : null,
              );
            } else {
              if (_selectedSwitchId != null) {
                widget.viewModel.connectNodeToSwitch(
                  widget.targetNode.id,
                  _selectedSwitchId!,
                  portLabel: _portController.text.trim().isNotEmpty ? _portController.text.trim() : null,
                );
              }
            }
            Navigator.of(context).pop();
          },
          style: FilledButton.styleFrom(
            backgroundColor: AppTheme.cyan,
            foregroundColor: Colors.white,
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(6)),
          ),
          child: const Text('Apply Link', style: TextStyle(fontSize: 12, color: Colors.white, fontWeight: FontWeight.bold)),
        ),
      ],
    );
  }
}
