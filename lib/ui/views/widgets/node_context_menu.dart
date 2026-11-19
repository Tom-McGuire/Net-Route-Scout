import 'package:flutter/services.dart';
import 'package:material_ui/material_ui.dart';
import 'package:net_route_scout/core/app_theme.dart';
import 'package:net_route_scout/domain/models/network_node.dart';
import 'package:net_route_scout/ui/view_models/topology_view_model.dart';
import 'connect_switch_dialog.dart';
import 'edit_device_dialog.dart';
import 'snmp_discovery_dialog.dart';

/// Displays the shared node actions context menu at [globalPosition].
Future<void> showNodeActionsContextMenu(
  BuildContext context,
  TopologyViewModel vm,
  NetworkNode node,
  Offset globalPosition,
) async {
  final subnet = vm.deriveSubnetForNode(node);
  final hasValidSubnet = subnet.isNotEmpty;

  final overlay = Overlay.of(context).context.findRenderObject() as RenderBox?;
  final position = RelativeRect.fromRect(
    Rect.fromLTWH(globalPosition.dx, globalPosition.dy, 1, 1),
    Offset.zero & (overlay?.size ?? const Size(1920, 1080)),
  );

  final choice = await showMenu<String>(
    context: context,
    position: position,
    color: AppTheme.surfaceContainerHigh,
    shape: RoundedRectangleBorder(
      borderRadius: BorderRadius.circular(8),
      side: const BorderSide(color: AppTheme.border),
    ),
    items: [
      if (hasValidSubnet)
        PopupMenuItem<String>(
          value: 'scan_arp',
          child: Row(
            children: [
              const Icon(Icons.radar, size: 16, color: AppTheme.primaryAccent),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  'Scan Subnet with ARP Scout ($subnet)',
                  style: const TextStyle(fontSize: 12.5, color: Colors.white),
                ),
              ),
            ],
          ),
        ),
      PopupMenuItem<String>(
        value: 'select_path',
        child: Row(
          children: [
            const Icon(Icons.alt_route, size: 16, color: AppTheme.activeHighlight),
            const SizedBox(width: 10),
            Text(
              vm.selectedNodeId == node.id ? 'Deselect Node' : 'Focus / Select Node Path',
              style: const TextStyle(fontSize: 12.5, color: Colors.white),
            ),
          ],
        ),
      ),
      if (!node.isLocalHost) ...[
        if (!node.isSwitch)
          const PopupMenuItem<String>(
            value: 'define_switch',
            child: Row(
              children: [
                Icon(Icons.hub, size: 16, color: Color(0xFF06B6D4)),
                SizedBox(width: 10),
                Text(
                  'Define as Switch Node',
                  style: TextStyle(fontSize: 12.5, color: Colors.white),
                ),
              ],
            ),
          )
        else ...[
          const PopupMenuItem<String>(
            value: 'revert_switch',
            child: Row(
              children: [
                Icon(Icons.undo, size: 16, color: Colors.white70),
                SizedBox(width: 10),
                Text(
                  'Revert to Standard Node',
                  style: TextStyle(fontSize: 12.5, color: Colors.white),
                ),
              ],
            ),
          ),
          if (!node.isUnresponsive)
            const PopupMenuItem<String>(
              value: 'query_snmp',
              child: Row(
                children: [
                  Icon(Icons.sensors, size: 16, color: Color(0xFF06B6D4)),
                  SizedBox(width: 10),
                  Text(
                    'Query Switch via SNMP...',
                    style: TextStyle(fontSize: 12.5, color: Colors.white),
                  ),
                ],
              ),
            ),
        ],
        PopupMenuItem<String>(
          value: 'connect_switch',
          child: Row(
            children: [
              const Icon(Icons.cable, size: 16, color: Color(0xFF06B6D4)),
              const SizedBox(width: 10),
              Text(
                node.connectedSwitchId != null ? 'Change Connected Switch...' : 'Connect to Switch...',
                style: const TextStyle(fontSize: 12.5, color: Colors.white),
              ),
            ],
          ),
        ),
        if (node.connectedSwitchId != null)
          const PopupMenuItem<String>(
            value: 'disconnect_switch',
            child: Row(
              children: [
                Icon(Icons.link_off, size: 16, color: Colors.redAccent),
                SizedBox(width: 10),
                Text(
                  'Disconnect from Switch',
                  style: TextStyle(fontSize: 12.5, color: Colors.redAccent),
                ),
              ],
            ),
          ),
      ],
      const PopupMenuItem<String>(
        value: 'edit_shared',
        child: Row(
          children: [
            Icon(Icons.edit, size: 16, color: Colors.white70),
            SizedBox(width: 10),
            Text(
              'Edit Shared Device Identity',
              style: TextStyle(fontSize: 12.5, color: Colors.white),
            ),
          ],
        ),
      ),
      if (!node.isUnresponsive)
        const PopupMenuItem<String>(
          value: 'copy_ip',
          child: Row(
            children: [
              Icon(Icons.copy, size: 16, color: Colors.white70),
              SizedBox(width: 10),
              Text(
                'Copy IP Address',
                style: TextStyle(fontSize: 12.5, color: Colors.white),
              ),
            ],
          ),
        ),
    ],
  );

  if (!context.mounted || choice == null) return;
  switch (choice) {
    case 'scan_arp':
      vm.launchArpScoutForNode(context, node);
      break;
    case 'select_path':
      if (vm.selectedNodeId == node.id) {
        vm.clearSelection();
      } else {
        vm.selectNode(node.id);
      }
      break;
    case 'define_switch':
      vm.defineNodeAsSwitch(node.id, isSwitch: true);
      break;
    case 'revert_switch':
      vm.defineNodeAsSwitch(node.id, isSwitch: false);
      break;
    case 'connect_switch':
      ConnectSwitchDialog.show(context, vm, node);
      break;
    case 'disconnect_switch':
      vm.disconnectNodeFromSwitch(node.id);
      break;
    case 'query_snmp':
      SnmpDiscoveryDialog.show(context, vm, node: node);
      break;
    case 'edit_shared':
      showDialog(
        context: context,
        builder: (ctx) => EditDeviceDialog(
          node: node,
          onSave: vm.updateDeviceDetails,
        ),
      );
      break;
    case 'copy_ip':
      Clipboard.setData(ClipboardData(text: node.ip));
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Copied ${node.ip} to clipboard'),
          duration: const Duration(seconds: 2),
        ),
      );
      break;
  }
}
