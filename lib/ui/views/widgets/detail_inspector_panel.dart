import 'package:material_ui/material_ui.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import 'package:net_route_scout/core/app_theme.dart';
import 'package:net_route_scout/core/constants.dart';
import 'package:net_route_scout/domain/models/interface_health_stats.dart';
import 'package:net_route_scout/domain/models/network_edge.dart';
import 'package:net_route_scout/domain/models/network_node.dart';
import 'package:net_route_scout/domain/models/switch_poe_status.dart';
import 'package:net_route_scout/ui/view_models/topology_view_model.dart';
import 'edit_device_dialog.dart';

class DetailInspectorPanel extends StatelessWidget {
  const DetailInspectorPanel({super.key});

  @override
  Widget build(BuildContext context) {
    final vm = context.watch<TopologyViewModel>();
    final selectedNode = vm.selectedNode;

    return Container(
      decoration: const BoxDecoration(
        color: AppTheme.surfaceContainer,
        border: Border(
          top: BorderSide(color: AppTheme.border, width: 1),
        ),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          // Inspector Content (Rendered when node is selected)
          if (selectedNode != null)
            _buildInspectorBody(context, vm, selectedNode),

          // Persistent Bottom Status Bar
          _buildStatusBar(context, vm),
        ],
      ),
    );
  }

  Widget _buildInspectorBody(BuildContext context, TopologyViewModel vm, NetworkNode node) {
    final breadcrumbs = vm.selectedPathBreadcrumbs;
    final routedTargets = node.associatedTargets.toList();

    return Container(
      constraints: const BoxConstraints(maxHeight: 270),
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Section 1: Device Summary Card
          SizedBox(
            width: 320,
            child: SingleChildScrollView(
              physics: const ClampingScrollPhysics(),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                Row(
                  children: [
                    Container(
                      padding: const EdgeInsets.all(5),
                      decoration: BoxDecoration(
                        color: AppTheme.activeHighlight.withValues(alpha: 0.18),
                        borderRadius: BorderRadius.circular(6),
                      ),
                      child: const Icon(Icons.hub, size: 16, color: AppTheme.activeHighlight),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            children: [
                              Flexible(
                                child: Text(
                                  node.displayName,
                                  style: const TextStyle(
                                    fontSize: 13,
                                    fontWeight: FontWeight.bold,
                                    color: Colors.white,
                                  ),
                                  overflow: TextOverflow.ellipsis,
                                ),
                              ),
                              if (node.hasSharedName) ...[
                                const SizedBox(width: 6),
                                Container(
                                  padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1),
                                  decoration: BoxDecoration(
                                    color: const Color(0xFF10B981).withValues(alpha: 0.2),
                                    borderRadius: BorderRadius.circular(3),
                                  ),
                                  child: const Text(
                                    'SHARED DB',
                                    style: TextStyle(
                                      fontSize: 8.5,
                                      fontWeight: FontWeight.bold,
                                      color: Color(0xFF10B981),
                                    ),
                                  ),
                                ),
                              ],
                            ],
                          ),
                          Text(
                            node.ip,
                            style: const TextStyle(
                              fontSize: 11,
                              fontFamily: 'monospace',
                              color: Colors.white60,
                            ),
                          ),
                        ],
                      ),
                    ),
                    // Edit Device Button
                    IconButton(
                      icon: const Icon(Icons.edit, size: 16, color: AppTheme.primaryAccent),
                      tooltip: 'Edit Device Identity in Shared Database',
                      splashRadius: 16,
                      onPressed: () {
                        showDialog(
                          context: context,
                          builder: (ctx) => EditDeviceDialog(
                            node: node,
                            onSave: vm.updateDeviceDetails,
                          ),
                        );
                      },
                    ),
                    // Close Button
                    IconButton(
                      icon: const Icon(Icons.close, size: 16, color: Colors.white54),
                      tooltip: 'Deselect',
                      splashRadius: 16,
                      onPressed: vm.clearSelection,
                    ),
                  ],
                ),
                const SizedBox(height: 8),
                const Divider(height: 1),
                const SizedBox(height: 8),

                // Metadata Details Grid
                _buildMetaRow('Hop Depth', node.isLocalHost ? 'Host Machine' : (node.isSwitch ? 'Switch (Effective Depth ${vm.getEffectiveNodeDepth(node.id)})' : 'Hop ${node.hopDepth}')),
                if (node.isSwitch) ...[
                  _buildMetaRow('Device Type', 'Layer 2 Network Switch'),
                  if (node.switchModel != null && node.switchModel!.isNotEmpty)
                    _buildMetaRow('Hardware Model', node.switchModel!),
                  _buildMetaRow(
                    'Downstream Ports',
                    '${vm.nodes.values.where((n) => n.connectedSwitchId == node.id).length} devices connected',
                  ),
                ],
                if (node.connectedSwitchId != null) ...[
                  _buildMetaRow(
                    'Connected Switch',
                    vm.nodes[node.connectedSwitchId]?.displayName ?? node.connectedSwitchId!,
                  ),
                  if (node.switchPort != null && node.switchPort!.isNotEmpty)
                    _buildMetaRow('Physical Port', node.switchPort!),
                ],
                _buildMetaRow('MAC Address', node.macAddress ?? 'Unresolved (L3 Routed)'),
                _buildMetaRow('Vendor / OUI', node.vendor ?? 'Unknown Vendor'),
                _buildMetaRow(
                  'Round Trip Time',
                  node.rttMs != null ? '${node.rttMs!.toStringAsFixed(2)} ms' : (node.isUnresponsive ? 'Timed out' : '—'),
                ),
                if (node.hostname != null && node.hostname != node.ip)
                  _buildMetaRow('Reverse DNS', node.hostname!),
                if (node.sharedNotes != null && node.sharedNotes!.isNotEmpty)
                  _buildMetaRow('Notes', node.sharedNotes!),
                if (node.isStpRootBridge || node.stpPriority != null || node.stpPorts.isNotEmpty) ...[
                  const SizedBox(height: 6),
                  _buildMetaRow(
                    'STP Role',
                    node.isStpRootBridge
                        ? '👑 Root Bridge${node.stpPriority != null ? ' (Prio ${node.stpPriority})' : ''}'
                        : 'Non-Root${node.stpPriority != null ? ' (Prio ${node.stpPriority}, Cost ${node.stpRootCost ?? 0})' : ''}',
                  ),
                ],
                if (node.isIgmpQuerier || node.igmpSnoopingEnabled) ...[
                  _buildMetaRow(
                    'IGMP Querier',
                    node.isIgmpQuerier
                        ? '📡 Active Querier (${node.igmpQuerierVersion ?? 'IGMPv2'})'
                        : 'Snooping Enabled (Querier elsewhere)',
                  ),
                ],
                if (node.stpPorts.isNotEmpty) ...[
                  const SizedBox(height: 6),
                  const Text(
                    'STP PORTS',
                    style: TextStyle(fontSize: 9.5, fontWeight: FontWeight.bold, color: Colors.white54, letterSpacing: 0.6),
                  ),
                  const SizedBox(height: 4),
                  Wrap(
                    spacing: 4,
                    runSpacing: 4,
                    children: node.stpPorts.map((p) {
                      final isBlk = p.isBlocking;
                      final isFwd = p.isForwarding;
                      final badgeColor = isBlk
                          ? const Color(0xFFEF4444)
                          : (isFwd ? const Color(0xFF10B981) : Colors.grey);
                      return Container(
                        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                        decoration: BoxDecoration(
                          color: badgeColor.withValues(alpha: 0.14),
                          borderRadius: BorderRadius.circular(4),
                          border: Border.all(color: badgeColor.withValues(alpha: 0.45)),
                        ),
                        child: Text(
                          '${p.interfaceName}: ${isBlk ? 'BLK' : (isFwd ? 'FWD' : p.state.label)}',
                          style: TextStyle(fontSize: 9.5, fontWeight: FontWeight.w600, color: badgeColor),
                        ),
                      );
                    }).toList(),
                  ),
                ],
                ..._buildPoeSection(vm, node),
                ..._buildInterfaceHealthSection(node),
                ..._buildVlanSection(vm, node),

                // Scan Subnet in ARP Scout Action Button
                Builder(
                  builder: (context) {
                    final subnet = vm.deriveSubnetForNode(node);
                    if (subnet.isEmpty) return const SizedBox.shrink();
                    return Padding(
                      padding: const EdgeInsets.only(top: 8.0),
                      child: SizedBox(
                        width: double.infinity,
                        height: 28,
                        child: OutlinedButton.icon(
                          onPressed: () => vm.launchArpScoutForNode(context, node),
                          icon: const Icon(Icons.radar, size: 14, color: AppTheme.primaryAccent),
                          label: Text(
                            'Scan Subnet in ARP Scout ($subnet)',
                            style: const TextStyle(
                              fontSize: 11,
                              fontWeight: FontWeight.w600,
                              color: Colors.white,
                            ),
                            overflow: TextOverflow.ellipsis,
                          ),
                          style: OutlinedButton.styleFrom(
                            side: const BorderSide(color: AppTheme.primaryAccent, width: 1),
                            padding: const EdgeInsets.symmetric(horizontal: 8),
                            visualDensity: VisualDensity.compact,
                            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(5)),
                          ),
                        ),
                      ),
                    );
                  },
                ),
              ],
            ),
          ),
        ),

        const SizedBox(width: 16),
          const VerticalDivider(width: 1),
          const SizedBox(width: 16),

          // Section 2: Path Traversal Hierarchy Breadcrumb
          Expanded(
            flex: 3,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Row(
                  children: [
                    const Icon(Icons.alt_route, size: 14, color: AppTheme.activeHighlight),
                    const SizedBox(width: 6),
                    const Text(
                      'PATH TRAVERSAL HIERARCHY',
                      style: TextStyle(
                        fontSize: 11,
                        fontWeight: FontWeight.bold,
                        color: Colors.white70,
                        letterSpacing: 0.5,
                      ),
                    ),
                    const Spacer(),
                    TextButton.icon(
                      onPressed: () {
                        final str = breadcrumbs.map((b) => '${b.displayName} (${b.ip})').join(' ➔ ');
                        Clipboard.setData(ClipboardData(text: str));
                        ScaffoldMessenger.of(context).showSnackBar(
                          const SnackBar(content: Text('Path copied to clipboard')),
                        );
                      },
                      icon: const Icon(Icons.copy, size: 12),
                      label: const Text('Copy Path', style: TextStyle(fontSize: 10.5)),
                      style: TextButton.styleFrom(
                        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                        visualDensity: VisualDensity.compact,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 6),

                // Linear Breadcrumb Chain
                SingleChildScrollView(
                  scrollDirection: Axis.horizontal,
                  child: Row(
                    children: [
                      for (int i = 0; i < breadcrumbs.length; i++) ...[
                        _buildBreadcrumbNode(breadcrumbs[i], isLast: i == breadcrumbs.length - 1),
                        if (i < breadcrumbs.length - 1)
                          const Padding(
                            padding: EdgeInsets.symmetric(horizontal: 6),
                            child: Icon(Icons.arrow_forward, size: 13, color: AppTheme.activeHighlight),
                          ),
                      ],
                    ],
                  ),
                ),

                const SizedBox(height: 12),

                // Section 3: Traversing Routes List (if router has multiple targets)
                Row(
                  children: [
                    const Icon(Icons.fork_right, size: 14, color: AppTheme.router),
                    const SizedBox(width: 6),
                    Text(
                      'TRAVERSING TARGETS (${routedTargets.length})',
                      style: const TextStyle(
                        fontSize: 11,
                        fontWeight: FontWeight.bold,
                        color: Colors.white70,
                        letterSpacing: 0.5,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 6),
                Expanded(
                  child: routedTargets.isEmpty
                      ? const Text('Terminal endpoint; no downstream routes.', style: TextStyle(color: Colors.white38, fontSize: 11))
                      : Wrap(
                          spacing: 6,
                          runSpacing: 4,
                          children: routedTargets.map((targetIp) {
                            final targetNode = vm.nodes[targetIp];
                            final label = targetNode?.displayName ?? targetIp;
                            return Container(
                              padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                              decoration: BoxDecoration(
                                color: AppTheme.surfaceContainerHighest,
                                borderRadius: BorderRadius.circular(4),
                                border: Border.all(color: AppTheme.border),
                              ),
                              child: Text(
                                label,
                                style: const TextStyle(
                                  fontSize: 10.5,
                                  fontFamily: 'monospace',
                                  color: Colors.white70,
                                ),
                              ),
                            );
                          }).toList(),
                        ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  List<Widget> _buildPoeSection(TopologyViewModel vm, NetworkNode node) {
    final poe = node.poeStatus;
    if (poe == null) return const [];

    final connectedChildren = vm.nodes.values
        .where((c) => c.connectedSwitchId == node.id && c.switchPort != null)
        .toList();

    return [
      const SizedBox(height: 8),
      const Text(
        'POE BUDGET & PORT DRAW',
        style: TextStyle(fontSize: 9.5, fontWeight: FontWeight.bold, color: Colors.white54, letterSpacing: 0.6),
      ),
      const SizedBox(height: 4),
      _buildMetaRow(
        'Total Budget',
        '${poe.consumedWatts}W / ${poe.totalBudgetWatts}W (${poe.utilizationPercent.toStringAsFixed(0)}%)',
      ),
      _buildMetaRow('Headroom', '${poe.remainingWatts}W remaining'),
      if (poe.ports.isNotEmpty) ...[
        const SizedBox(height: 4),
        Wrap(
          spacing: 4,
          runSpacing: 4,
          children: poe.ports.map((p) {
            final color = p.isFault
                ? const Color(0xFFEF4444)
                : (p.state == PoePortState.deliveringPower
                    ? const Color(0xFF06B6D4)
                    : Colors.white54);
            final child = connectedChildren.where((c) =>
                c.switchPort!.toLowerCase().contains(p.interfaceName.toLowerCase()) ||
                c.switchPort!.contains('Port ${p.portIndex}')).firstOrNull;
            final wattsStr = p.drawWatts != null ? ' ${p.drawWatts!.toStringAsFixed(1)}W' : '';
            final classStr = p.powerClass != null ? ' (${p.powerClass})' : '';
            final peerStr = child != null ? ' → ${child.displayName}' : '';
            return Container(
              padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
              decoration: BoxDecoration(
                color: color.withValues(alpha: 0.14),
                borderRadius: BorderRadius.circular(4),
                border: Border.all(color: color.withValues(alpha: 0.45)),
              ),
              child: Text(
                '${p.interfaceName}: ${p.state.label}$wattsStr$classStr$peerStr',
                style: TextStyle(fontSize: 9.5, fontWeight: FontWeight.w600, color: color),
              ),
            );
          }).toList(),
        ),
      ],
    ];
  }

  List<Widget> _buildInterfaceHealthSection(NetworkNode node) {
    if (node.interfaceHealth.isEmpty) return const [];
    return [
      const SizedBox(height: 8),
      const Text(
        'INTERFACE SPEED & ERROR COUNTERS',
        style: TextStyle(fontSize: 9.5, fontWeight: FontWeight.bold, color: Colors.white54, letterSpacing: 0.6),
      ),
      const SizedBox(height: 4),
      Wrap(
        spacing: 4,
        runSpacing: 4,
        children: node.interfaceHealth.map((h) {
          final isWarn = h.isDegradedSpeed ||
              h.isHalfDuplex ||
              h.hasHistoricalErrors ||
              h.hasActiveErrors;
          final color = isWarn ? const Color(0xFFF59E0B) : const Color(0xFF10B981);
          final duplexShort = h.duplex == DuplexMode.halfDuplex
              ? ' HDX'
              : (h.duplex == DuplexMode.fullDuplex ? ' FDX' : '');
          final errStr = (h.inErrors > 0 || h.inErrorsDelta > 0)
              ? ' | CRC ${h.inErrors}${h.inErrorsDelta > 0 ? ' (+${h.inErrorsDelta}Δ)' : ''}'
              : '';
          final outErrStr = h.outErrors > 0 ? ' | OutErr ${h.outErrors}' : '';
          final inDiscStr = h.inDiscards > 0 ? ' | InDrop ${h.inDiscards}' : '';
          final discStr = (h.outDiscards > 0 || h.outDiscardsDelta > 0)
              ? ' | Drop ${h.outDiscards}${h.outDiscardsDelta > 0 ? ' (+${h.outDiscardsDelta}Δ)' : ''}'
              : '';
          return Container(
            padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
            decoration: BoxDecoration(
              color: color.withValues(alpha: 0.14),
              borderRadius: BorderRadius.circular(4),
              border: Border.all(color: color.withValues(alpha: 0.45)),
            ),
            child: Text(
              '${h.interfaceName}: ${h.formattedSpeed}$duplexShort$errStr$outErrStr$inDiscStr$discStr',
              style: TextStyle(fontSize: 9.5, fontWeight: FontWeight.w600, color: color),
            ),
          );
        }).toList(),
      ),
    ];
  }

  List<Widget> _buildVlanSection(TopologyViewModel vm, NetworkNode node) {
    final relatedMismatches = vm.edges.values
        .where((e) => (e.sourceIp == node.id || e.targetIp == node.id) && e.hasVlanMismatch)
        .toList();
    if (node.portVlans.isEmpty && relatedMismatches.isEmpty) return const [];

    return [
      const SizedBox(height: 8),
      const Text(
        'VLAN TRUNK & PVID STATUS',
        style: TextStyle(fontSize: 9.5, fontWeight: FontWeight.bold, color: Colors.white54, letterSpacing: 0.6),
      ),
      const SizedBox(height: 4),
      if (node.portVlans.isNotEmpty)
        Wrap(
          spacing: 4,
          runSpacing: 4,
          children: node.portVlans.map((p) {
            final vlans = p.allowedVlans.toList()..sort();
            return Container(
              padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
              decoration: BoxDecoration(
                color: const Color(0xFF38BDF8).withValues(alpha: 0.12),
                borderRadius: BorderRadius.circular(4),
                border: Border.all(color: const Color(0xFF38BDF8).withValues(alpha: 0.35)),
              ),
              child: Text(
                '${p.interfaceName}: PVID ${p.nativePvid} | [${vlans.join(',')}]',
                style: const TextStyle(fontSize: 9.5, color: Color(0xFF7DD3FC), fontFamily: 'monospace'),
              ),
            );
          }).toList(),
        ),
      for (final edge in relatedMismatches) ...[
        const SizedBox(height: 4),
        _buildVlanDiffCard(vm, edge),
      ],
    ];
  }

  Widget _buildVlanDiffCard(TopologyViewModel vm, NetworkEdge edge) {
    final rep = edge.vlanMismatch!;
    final srcName = vm.nodes[edge.sourceIp]?.displayName ?? edge.sourceIp;
    final dstName = vm.nodes[edge.targetIp]?.displayName ?? edge.targetIp;
    final issues = <String>[
      if (rep.hasNativeVlanMismatch)
        'Native PVID mismatch (${rep.sideANativeVlan} ≠ ${rep.sideBNativeVlan})',
      if (rep.missingOnSideA.isNotEmpty)
        'Pruned on $srcName: VLAN ${rep.missingOnSideA.join(', ')} ✗',
      if (rep.missingOnSideB.isNotEmpty)
        'Pruned on $dstName: VLAN ${rep.missingOnSideB.join(', ')} ✗',
    ];
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(6),
      decoration: BoxDecoration(
        color: const Color(0xFFF59E0B).withValues(alpha: 0.14),
        borderRadius: BorderRadius.circular(5),
        border: Border.all(color: const Color(0xFFF59E0B).withValues(alpha: 0.55)),
      ),
      child: Text(
        '⚠ $srcName ↔ $dstName: ${issues.join(' | ')}',
        style: const TextStyle(fontSize: 10, color: Color(0xFFFBBF24)),
      ),
    );
  }

  Widget _buildBreadcrumbNode(NetworkNode node, {required bool isLast}) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: isLast
            ? AppTheme.activeHighlight.withValues(alpha: 0.18)
            : AppTheme.surfaceContainerHighest,
        borderRadius: BorderRadius.circular(6),
        border: Border.all(
          color: isLast ? AppTheme.activeHighlight : AppTheme.border,
          width: isLast ? 1.5 : 1,
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            node.displayName,
            style: TextStyle(
              fontSize: 11,
              fontWeight: FontWeight.bold,
              color: isLast ? Colors.white : Colors.white70,
            ),
          ),
          Text(
            node.ip,
            style: const TextStyle(
              fontSize: 9.5,
              fontFamily: 'monospace',
              color: Colors.white54,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildMetaRow(String label, String value) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 3),
      child: Row(
        children: [
          SizedBox(
            width: 100,
            child: Text(
              label,
              style: const TextStyle(fontSize: 10.5, color: Colors.white38),
            ),
          ),
          Expanded(
            child: Text(
              value,
              style: const TextStyle(
                fontSize: 10.5,
                fontFamily: 'monospace',
                color: Colors.white70,
              ),
              overflow: TextOverflow.ellipsis,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildStatusBar(BuildContext context, TopologyViewModel vm) {
    return Container(
      height: 26,
      padding: const EdgeInsets.symmetric(horizontal: 16),
      color: AppTheme.surfaceContainerLowest,
      child: Row(
        children: [
          Flexible(
            child: Text(
              'Discovered: ${vm.nodes.length} nodes, ${vm.edges.length} edges across ${vm.traces.length} targets',
              style: const TextStyle(fontSize: 11, color: Colors.white54),
              overflow: TextOverflow.ellipsis,
            ),
          ),
          const SizedBox(width: 12),
          if (vm.selectedNode != null)
            Expanded(
              child: Align(
                alignment: Alignment.centerRight,
                child: Text(
                  'Selected: ${vm.selectedNode!.displayName} (${vm.selectedNode!.ip})',
                  style: const TextStyle(
                    fontSize: 11,
                    fontFamily: 'monospace',
                    color: AppTheme.activeHighlight,
                    fontWeight: FontWeight.bold,
                  ),
                  overflow: TextOverflow.ellipsis,
                ),
              ),
            )
          else
            const Spacer(),
          const SizedBox(width: 12),
          Text(
            vm.isSharedDbConnected ? 'Shared DB: Synced' : 'Shared DB: Offline',
            style: TextStyle(
              fontSize: 11,
              color: vm.isSharedDbConnected ? const Color(0xFF10B981) : const Color(0xFFF59E0B),
            ),
          ),
          const SizedBox(width: 10),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1),
            decoration: BoxDecoration(
              color: AppTheme.surfaceContainerHighest,
              borderRadius: BorderRadius.circular(4),
              border: Border.all(color: AppTheme.border),
            ),
            child: const Text(
              AppConstants.appVersion,
              style: TextStyle(
                fontSize: 10,
                fontFamily: 'monospace',
                color: Colors.white54,
              ),
            ),
          ),
        ],
      ),
    );
  }
}
