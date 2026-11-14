import 'dart:io';
import 'package:flutter/services.dart';
import 'package:material_ui/material_ui.dart';
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
      backgroundColor: const Color(0xFF1E293B),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
        side: const BorderSide(color: Color(0xFFF59E0B), width: 1),
      ),
      title: const Row(
        children: [
          Icon(Icons.shield_outlined, color: Color(0xFFF59E0B), size: 22),
          SizedBox(width: 10),
          Expanded(
            child: Text(
              'Packet Capture Permission Required',
              style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600),
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
                style: const TextStyle(fontSize: 13, color: Color(0xFFE2E8F0)),
              ),
              const SizedBox(height: 6),
              const Text(
                'ICMP/traceroute sweeps still work normally; only passive STP Root '
                '& IGMP Querier sniffing is skipped.',
                style: TextStyle(fontSize: 12, color: Color(0xFF94A3B8)),
              ),
              if (errorLines.isNotEmpty) ...[
                const SizedBox(height: 12),
                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.all(10),
                  decoration: BoxDecoration(
                    color: const Color(0xFF0F172A),
                    borderRadius: BorderRadius.circular(6),
                    border: Border.all(color: const Color(0xFF334155)),
                  ),
                  child: SelectableText(
                    errorLines.join('\n'),
                    style: const TextStyle(
                      fontFamily: 'monospace',
                      fontSize: 11,
                      color: Color(0xFFFCA5A5),
                    ),
                  ),
                ),
              ],
              const SizedBox(height: 16),
              const Text(
                'How to resolve:',
                style: TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w600,
                  color: Color(0xFFF8FAFC),
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
            style: const TextStyle(fontSize: 12, color: Color(0xFFCBD5E1)),
          ),
          const SizedBox(height: 4),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
            decoration: BoxDecoration(
              color: const Color(0xFF0F172A),
              borderRadius: BorderRadius.circular(6),
              border: Border.all(color: const Color(0xFF334155)),
            ),
            child: Row(
              children: [
                Expanded(
                  child: SelectableText(
                    command,
                    style: const TextStyle(
                      fontFamily: 'monospace',
                      fontSize: 11.5,
                      color: Color(0xFF67E8F9),
                    ),
                  ),
                ),
                IconButton(
                  tooltip: 'Copy command',
                  icon: const Icon(Icons.copy, size: 15, color: Color(0xFF94A3B8)),
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
        style: const TextStyle(fontSize: 12, color: Color(0xFFCBD5E1)),
      ),
    );
  }
}
