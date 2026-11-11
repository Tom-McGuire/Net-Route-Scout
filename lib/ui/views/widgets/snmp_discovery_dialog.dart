import 'package:dart_snmp/dart_snmp.dart';
import 'package:flutter/material.dart';
import 'package:net_route_scout/core/app_theme.dart';
import 'package:net_route_scout/domain/models/network_node.dart';
import 'package:net_route_scout/domain/models/switch_discovery_info.dart';
import 'package:net_route_scout/ui/view_models/topology_view_model.dart';
import 'package:net_route_scout/data/services/snmp_switch_service.dart';

class SnmpDiscoveryDialog extends StatefulWidget {
  final NetworkNode? initialNode;
  final TopologyViewModel viewModel;

  const SnmpDiscoveryDialog({
    super.key,
    this.initialNode,
    required this.viewModel,
  });

  static Future<void> show(BuildContext context, TopologyViewModel vm, {NetworkNode? node}) {
    return showDialog<void>(
      context: context,
      builder: (ctx) => SnmpDiscoveryDialog(
        initialNode: node,
        viewModel: vm,
      ),
    );
  }

  @override
  State<SnmpDiscoveryDialog> createState() => _SnmpDiscoveryDialogState();
}

class _SnmpDiscoveryDialogState extends State<SnmpDiscoveryDialog> {
  final _ipController = TextEditingController();
  final _communityController = TextEditingController(text: 'public');
  final _portController = TextEditingController(text: '161');
  SnmpVersion _version = SnmpVersion.v2c;

  bool _isQuerying = false;
  String? _errorMessage;
  SwitchDiscoveryResult? _discoveryResult;

  @override
  void initState() {
    super.initState();
    if (widget.initialNode != null) {
      _ipController.text = widget.initialNode!.ip;
    } else {
      // Pick the first switch or first gateway node
      final firstSwitch = widget.viewModel.availableSwitches.firstOrNull;
      if (firstSwitch != null) {
        _ipController.text = firstSwitch.ip;
      }
    }
  }

  @override
  void dispose() {
    _ipController.dispose();
    _communityController.dispose();
    _portController.dispose();
    super.dispose();
  }

  Future<void> _runSnmpQuery() async {
    final ip = _ipController.text.trim();
    if (ip.isEmpty) {
      setState(() => _errorMessage = 'Please enter a valid IP address.');
      return;
    }

    final port = int.tryParse(_portController.text.trim()) ?? 161;
    final community = _communityController.text.trim().isNotEmpty
        ? _communityController.text.trim()
        : 'public';

    setState(() {
      _isQuerying = true;
      _errorMessage = null;
      _discoveryResult = null;
    });

    try {
      final result = await SnmpSwitchService.discoverSwitchTopology(
        targetIp: ip,
        community: community,
        port: port,
        version: _version,
      );

      if (mounted) {
        setState(() {
          _isQuerying = false;
          _discoveryResult = result;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _isQuerying = false;
          _errorMessage = 'SNMP Query failed: $e\nEnsure SNMP is enabled on switch with community "$community".';
        });
      }
    }
  }

  void _applyToTopology() {
    if (_discoveryResult == null) return;
    final res = _discoveryResult!;

    // 1. Ensure target switch node is defined
    var switchNode = widget.viewModel.nodes[res.switchIp];
    if (switchNode == null) {
      switchNode = widget.viewModel.addStandaloneSwitch(
        name: res.sysName,
        ip: res.switchIp,
        model: res.sysDescr,
      );
    } else if (!switchNode.isSwitch) {
      widget.viewModel.defineNodeAsSwitch(switchNode.id, isSwitch: true, name: res.sysName);
    }

    // 2. Correlate MAC addresses of active nodes to switch ports
    final activeNodes = widget.viewModel.nodes.values.toList();
    int mappedCount = 0;

    for (final port in res.ports) {
      for (final mac in port.connectedMacs) {
        final normMac = mac.toUpperCase();
        for (final node in activeNodes) {
          if (node.id == switchNode.id) continue;
          final nodeMac = node.macAddress?.toUpperCase();
          if (nodeMac == normMac) {
            widget.viewModel.connectNodeToSwitch(
              node.id,
              switchNode.id,
              portLabel: port.portName,
            );
            mappedCount++;
          }
        }
      }
    }

    // 3. Connect discovered neighbor switches
    for (final neighbor in res.neighbors) {
      // Check if neighbor already exists
      final existingNeighbor = widget.viewModel.availableSwitches
          .where((s) => s.displayName.toLowerCase() == neighbor.remoteSysName.toLowerCase())
          .firstOrNull;

      if (existingNeighbor != null && existingNeighbor.id != switchNode.id) {
        widget.viewModel.connectNodeToSwitch(
          existingNeighbor.id,
          switchNode.id,
          portLabel: neighbor.localPort,
        );
      }
    }

    Navigator.of(context).pop();

    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          'Applied switch "${res.sysName}": mapped $mappedCount connected devices${res.neighbors.isNotEmpty ? ' and ${res.neighbors.length} neighbor switches' : ''}.',
        ),
        duration: const Duration(seconds: 4),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      backgroundColor: AppTheme.surfaceContainerHigh,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(10),
        side: const BorderSide(color: AppTheme.border),
      ),
      title: Row(
        children: [
          Container(
            padding: const EdgeInsets.all(6),
            decoration: BoxDecoration(
              color: const Color(0xFF06B6D4).withValues(alpha: 0.15),
              borderRadius: BorderRadius.circular(6),
            ),
            child: const Icon(Icons.sensors, color: Color(0xFF06B6D4), size: 18),
          ),
          const SizedBox(width: 10),
          const Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                'SNMP Bridge MIB Discovery',
                style: TextStyle(fontSize: 15, fontWeight: FontWeight.bold, color: Colors.white),
              ),
              Text(
                'Query Switch Forwarding Database & LLDP Neighbors',
                style: TextStyle(fontSize: 10.5, color: Colors.white60),
              ),
            ],
          ),
        ],
      ),
      content: SizedBox(
        width: 500,
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Connection parameters row
              Row(
                children: [
                  Expanded(
                    flex: 3,
                    child: TextField(
                      controller: _ipController,
                      style: const TextStyle(fontSize: 12, color: Colors.white),
                      decoration: const InputDecoration(
                        labelText: 'Switch IP Address',
                        hintText: '192.168.1.2',
                        isDense: true,
                        filled: true,
                        fillColor: Color(0xFF252526),
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    flex: 2,
                    child: TextField(
                      controller: _communityController,
                      style: const TextStyle(fontSize: 12, color: Colors.white),
                      decoration: const InputDecoration(
                        labelText: 'Community',
                        hintText: 'public',
                        isDense: true,
                        filled: true,
                        fillColor: Color(0xFF252526),
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),
                  SizedBox(
                    width: 70,
                    child: TextField(
                      controller: _portController,
                      style: const TextStyle(fontSize: 12, color: Colors.white),
                      decoration: const InputDecoration(
                        labelText: 'Port',
                        hintText: '161',
                        isDense: true,
                        filled: true,
                        fillColor: Color(0xFF252526),
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 12),

              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Row(
                    children: [
                      const Text('SNMP Version: ', style: TextStyle(fontSize: 11, color: Colors.white70)),
                      DropdownButton<SnmpVersion>(
                        value: _version,
                        isDense: true,
                        dropdownColor: const Color(0xFF252526),
                        style: const TextStyle(fontSize: 11, color: Colors.white),
                        onChanged: (v) {
                          if (v != null) setState(() => _version = v);
                        },
                        items: const [
                          DropdownMenuItem(value: SnmpVersion.v2c, child: Text('v2c (Standard)')),
                          DropdownMenuItem(value: SnmpVersion.v1, child: Text('v1 (Legacy)')),
                        ],
                      ),
                    ],
                  ),
                  FilledButton.icon(
                    onPressed: _isQuerying ? null : _runSnmpQuery,
                    icon: _isQuerying
                        ? const SizedBox(
                            width: 12,
                            height: 12,
                            child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                          )
                        : const Icon(Icons.search, size: 14),
                    label: Text(_isQuerying ? 'Querying...' : 'Query Switch'),
                    style: FilledButton.styleFrom(
                      backgroundColor: const Color(0xFF06B6D4),
                      foregroundColor: Colors.black,
                      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(6)),
                    ),
                  ),
                ],
              ),

              if (_errorMessage != null) ...[
                const SizedBox(height: 12),
                Container(
                  padding: const EdgeInsets.all(10),
                  decoration: BoxDecoration(
                    color: Colors.red.withValues(alpha: 0.15),
                    borderRadius: BorderRadius.circular(6),
                    border: Border.all(color: Colors.red.withValues(alpha: 0.4)),
                  ),
                  child: Row(
                    children: [
                      const Icon(Icons.error_outline, size: 16, color: Colors.redAccent),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          _errorMessage!,
                          style: const TextStyle(fontSize: 11, color: Colors.redAccent),
                        ),
                      ),
                    ],
                  ),
                ),
              ],

              if (_discoveryResult != null) ...[
                const SizedBox(height: 14),
                const Divider(height: 1),
                const SizedBox(height: 12),

                // Switch details
                Container(
                  padding: const EdgeInsets.all(10),
                  decoration: BoxDecoration(
                    color: const Color(0xFF252526),
                    borderRadius: BorderRadius.circular(6),
                    border: Border.all(color: const Color(0xFF3E3E42)),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          const Icon(Icons.hub, size: 16, color: Color(0xFF06B6D4)),
                          const SizedBox(width: 8),
                          Expanded(
                            child: Text(
                              _discoveryResult!.sysName,
                              style: const TextStyle(fontSize: 13, fontWeight: FontWeight.bold, color: Colors.white),
                            ),
                          ),
                          Text(
                            _discoveryResult!.switchIp,
                            style: const TextStyle(fontSize: 11, color: Colors.white54, fontFamily: 'monospace'),
                          ),
                        ],
                      ),
                      if (_discoveryResult!.sysDescr != null) ...[
                        const SizedBox(height: 4),
                        Text(
                          _discoveryResult!.sysDescr!,
                          style: const TextStyle(fontSize: 10, color: Colors.white60),
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ],
                    ],
                  ),
                ),
                const SizedBox(height: 12),

                // Ports summary
                Text(
                  'Forwarding Database (${_discoveryResult!.ports.fold<int>(0, (sum, p) => sum + p.connectedMacs.length)} learned MAC addresses across ${_discoveryResult!.ports.length} ports):',
                  style: const TextStyle(fontSize: 11.5, fontWeight: FontWeight.w600, color: Colors.white),
                ),
                const SizedBox(height: 6),
                Container(
                  constraints: const BoxConstraints(maxHeight: 180),
                  decoration: BoxDecoration(
                    color: const Color(0xFF1E1E1E),
                    borderRadius: BorderRadius.circular(6),
                    border: Border.all(color: const Color(0xFF2C2C2C)),
                  ),
                  child: ListView.separated(
                    shrinkWrap: true,
                    itemCount: _discoveryResult!.ports.length,
                    separatorBuilder: (_, _) => const Divider(height: 1),
                    itemBuilder: (ctx, idx) {
                      final port = _discoveryResult!.ports[idx];
                      return Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                        child: Row(
                          children: [
                            const Icon(Icons.cable, size: 12, color: Color(0xFF06B6D4)),
                            const SizedBox(width: 8),
                            SizedBox(
                              width: 140,
                              child: Text(
                                port.portName,
                                style: const TextStyle(fontSize: 11, color: Colors.white, fontWeight: FontWeight.w600),
                              ),
                            ),
                            Expanded(
                              child: Text(
                                port.connectedMacs.isEmpty
                                    ? 'No active MAC'
                                    : port.connectedMacs.join(', '),
                                style: TextStyle(
                                  fontSize: 10,
                                  fontFamily: 'monospace',
                                  color: port.connectedMacs.isEmpty ? Colors.white24 : Colors.white70,
                                ),
                                overflow: TextOverflow.ellipsis,
                              ),
                            ),
                          ],
                        ),
                      );
                    },
                  ),
                ),

                if (_discoveryResult!.neighbors.isNotEmpty) ...[
                  const SizedBox(height: 12),
                  Text(
                    'LLDP / CDP Neighbors (${_discoveryResult!.neighbors.length}):',
                    style: const TextStyle(fontSize: 11.5, fontWeight: FontWeight.w600, color: Colors.white),
                  ),
                  const SizedBox(height: 6),
                  Column(
                    children: _discoveryResult!.neighbors.map((n) {
                      return Container(
                        margin: const EdgeInsets.only(bottom: 4),
                        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                        decoration: BoxDecoration(
                          color: const Color(0xFF252526),
                          borderRadius: BorderRadius.circular(6),
                        ),
                        child: Row(
                          children: [
                            const Icon(Icons.alt_route, size: 13, color: AppTheme.activeHighlight),
                            const SizedBox(width: 8),
                            Text('${n.localPort} ➔ ', style: const TextStyle(fontSize: 11, color: Colors.white60)),
                            Text(n.remoteSysName, style: const TextStyle(fontSize: 11, fontWeight: FontWeight.bold, color: Colors.white)),
                          ],
                        ),
                      );
                    }).toList(),
                  ),
                ],
              ],
            ],
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Cancel', style: TextStyle(color: Colors.white70, fontSize: 12)),
        ),
        if (_discoveryResult != null)
          FilledButton.icon(
            onPressed: _applyToTopology,
            icon: const Icon(Icons.check, size: 14),
            label: const Text('Apply to Topology'),
            style: FilledButton.styleFrom(
              backgroundColor: const Color(0xFF10B981),
              foregroundColor: Colors.white,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(6)),
            ),
          ),
      ],
    );
  }
}
