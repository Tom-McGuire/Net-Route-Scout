import 'dart:io';
import 'package:flutter/services.dart';
import 'package:material_ui/material_ui.dart';
import 'package:net_route_scout/core/app_theme.dart';
import '../../../data/services/l2_role_sniffer_service.dart';

class L2CapturePermissionDialog extends StatelessWidget {
  final L2CapturePermissionIssue issue;

  const L2CapturePermissionDialog({super.key, required this.issue});

  static Future<void> show(
    BuildContext context,
    L2CapturePermissionIssue issue,
  ) {
    return showDialog<void>(
      context: context,
      builder: (_) => L2CapturePermissionDialog(issue: issue),
    );
  }

  @override
  Widget build(BuildContext context) {
    final errorLines = <String>[
      if (issue.tcpdumpError != null && issue.tcpdumpError!.isNotEmpty)
        'tcpdump: ${issue.tcpdumpError}',
      if (issue.tsharkError != null && issue.tsharkError!.isNotEmpty)
        'tshark: ${issue.tsharkError}',
    ];

    return AlertDialog(
      backgroundColor: AppTheme.surface,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
        side: BorderSide(color: AppTheme.warning, width: 1),
      ),
      title: Row(
        children: [
          Icon(Icons.shield_outlined, color: AppTheme.warning, size: 22),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              'Packet Capture Permission Required',
              style: TextStyle(
                fontSize: 16,
                fontWeight: FontWeight.w600,
                color: AppTheme.textPrimary,
              ),
            ),
          ),
        ],
      ),
      content: SizedBox(
        width: 540,
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Net Route Scout detected ${issue.detectedToolsLabel}, but does not '
                'have permission to capture passive STP / IGMP frames on '
                '"${issue.interfaceName}".',
                style: TextStyle(fontSize: 13, color: AppTheme.textPrimary),
              ),
              const SizedBox(height: 6),
              Text(
                'ICMP/traceroute sweeps still work normally; only passive STP Root '
                '& IGMP Querier sniffing is skipped.',
                style: TextStyle(fontSize: 12, color: AppTheme.textSecondary),
              ),
              if (errorLines.isNotEmpty) ...[
                const SizedBox(height: 12),
                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.all(10),
                  decoration: BoxDecoration(
                    color: AppTheme.scaffoldBg,
                    borderRadius: BorderRadius.circular(6),
                    border: Border.all(color: AppTheme.border),
                  ),
                  child: SelectableText(
                    errorLines.join('\n'),
                    style: TextStyle(
                      fontFamily: 'monospace',
                      fontSize: 11,
                      color: AppTheme.error,
                    ),
                  ),
                ),
              ],
              const SizedBox(height: 16),
              Text(
                'How to resolve:',
                style: TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w600,
                  color: AppTheme.textPrimary,
                ),
              ),
              const SizedBox(height: 8),
              ..._buildPlatformSuggestions(context),
            ],
          ),
        ),
      ),
      actions: [
        FilledButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Got it'),
        ),
      ],
    );
  }

  List<Widget> _buildPlatformSuggestions(BuildContext context) {
    if (Platform.isLinux) {
      return [
        if (issue.tcpdumpFound)
          _buildCommandSuggestion(
            context,
            title: 'Option 1 — Grant non-root capture capability to tcpdump:',
            command: 'sudo setcap cap_net_raw,cap_net_admin=eip \$(which tcpdump)',
          ),
        if (issue.tsharkFound)
          _buildCommandSuggestion(
            context,
            title: 'Option 2 — Allow non-root capture for tshark / dumpcap (then log out & back in):',
            command: 'sudo dpkg-reconfigure wireshark-common && sudo usermod -aG wireshark \$USER',
          ),
        if (!issue.tcpdumpFound && !issue.tsharkFound)
          _buildTextSuggestion(
            'Install tcpdump or tshark and grant capture capabilities (cap_net_raw).',
          ),
      ];
    }

    if (Platform.isMacOS) {
      return [
        _buildCommandSuggestion(
          context,
          title: 'Install Wireshark ChmodBPF to allow non-root /dev/bpf capture:',
          command: 'brew install --cask wireshark-chmodbpf',
        ),
      ];
    }

    if (Platform.isWindows) {
      return [
        _buildTextSuggestion(
          'Install Npcap with "Restrict Npcap driver access to Administrators only" unchecked, '
          'or run Net Route Scout as Administrator.',
        ),
      ];
    }

    return [
      _buildTextSuggestion(
        'Grant packet capture privileges to tcpdump or tshark for your user account.',
      ),
    ];
  }

  Widget _buildCommandSuggestion(
    BuildContext context, {
    required String title,
    required String command,
  }) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            title,
            style: TextStyle(fontSize: 12, color: AppTheme.textSecondary),
          ),
          const SizedBox(height: 4),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
            decoration: BoxDecoration(
              color: AppTheme.scaffoldBg,
              borderRadius: BorderRadius.circular(6),
              border: Border.all(color: AppTheme.border),
            ),
            child: Row(
              children: [
                Expanded(
                  child: SelectableText(
                    command,
                    style: TextStyle(
                      fontFamily: 'monospace',
                      fontSize: 11.5,
                      color: AppTheme.cyan,
                    ),
                  ),
                ),
                IconButton(
                  tooltip: 'Copy command',
                  icon: Icon(Icons.copy, size: 15, color: AppTheme.textSecondary),
                  padding: EdgeInsets.zero,
                  constraints: const BoxConstraints(minWidth: 28, minHeight: 28),
                  onPressed: () {
                    Clipboard.setData(ClipboardData(text: command));
                    ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(
                        content: Text('Command copied to clipboard'),
                        duration: Duration(seconds: 2),
                      ),
                    );
                  },
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildTextSuggestion(String text) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Text(
        text,
        style: TextStyle(fontSize: 12, color: AppTheme.textSecondary),
      ),
    );
  }
}
