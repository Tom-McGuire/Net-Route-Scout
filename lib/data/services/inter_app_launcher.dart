import 'dart:io';
import '../../domain/models/network_adapter_info.dart';
import 'inter_app_ipc_service.dart';

class InterAppLauncher {
  static const int arpScoutIpcPort = InterAppIpcService.arpScoutIpcPort; // 44102

  /// Launches or commands ARP Scout to scan [subnetCidr] using [currentAdapter].
  ///
  /// First attempts a warm handoff via loopback IPC port 44102.
  /// If ARP Scout is not currently running, performs a cold process launch.
  static Future<void> launchSubnetScan({
    required String subnetCidr,
    NetworkAdapterInfo? currentAdapter,
    bool autoStart = true,
    List<String>? candidatePathsOverride,
  }) async {
    // 1. Warm handoff: Check if ARP Scout is already running
    final payload = {
      'action': 'scan',
      'subnet': subnetCidr,
      if (currentAdapter?.ipAddress != null && currentAdapter!.ipAddress.isNotEmpty)
        'adapterIp': currentAdapter.ipAddress,
      if (currentAdapter?.name != null && currentAdapter!.name.isNotEmpty)
        'adapterName': currentAdapter.name,
      'autoStart': autoStart,
    };

    final warmHandoffDelivered = await InterAppIpcService.sendCommand(
      port: arpScoutIpcPort,
      payload: payload,
    );

    if (warmHandoffDelivered) {
      return; // Handed off cleanly to existing instance
    }

    // 2. Cold process launch
    final exePath = await resolveArpScoutExecutable(
      candidatePathsOverride: candidatePathsOverride,
    );
    if (exePath == null) {
      throw Exception('ARP Scout executable not found on system.');
    }

    final args = [
      '--subnet',
      subnetCidr,
      if (currentAdapter?.ipAddress != null && currentAdapter!.ipAddress.isNotEmpty) ...[
        '--adapter-ip',
        currentAdapter.ipAddress,
      ],
      if (currentAdapter?.name != null && currentAdapter!.name.isNotEmpty) ...[
        '--adapter-name',
        currentAdapter.name,
      ],
      if (autoStart) '--auto-start',
    ];

    await Process.start(exePath, args, mode: ProcessStartMode.detached);
  }

  /// Resolves the file path for the ARP Scout executable based on development sibling
  /// paths, production suite install paths, or system PATH.
  static Future<String?> resolveArpScoutExecutable({
    List<String>? candidatePathsOverride,
  }) async {
    final candidatePaths = <String>[
      ...?candidatePathsOverride,
      if (Platform.isLinux) ...[
        '../ARP-Scout/build/linux/x64/release/bundle/arp_scout',
        '../ARP-Scout/build/linux/x64/debug/bundle/arp_scout',
        '/usr/local/bin/arp-scout',
        '/opt/NetworkSuite/arp-scout',
      ],
      if (Platform.isWindows) ...[
        r'..\ARP-Scout\build\windows\x64\runner\Release\arp_scout.exe',
        r'..\ARP-Scout\build\windows\x64\runner\Debug\arp_scout.exe',
        '${Platform.environment['LOCALAPPDATA'] ?? ''}\\NetworkSuite\\arp-scout.exe',
      ],
      if (Platform.isMacOS) ...[
        '../ARP-Scout/build/macos/Build/Products/Release/ARP Scout.app/Contents/MacOS/arp_scout',
        '/Applications/ARP Scout.app/Contents/MacOS/arp_scout',
      ],
    ];

    for (final p in candidatePaths) {
      if (p.isNotEmpty && await File(p).exists()) {
        return p;
      }
    }

    // Fallback: Check system PATH
    try {
      final whichCmd = Platform.isWindows ? 'where' : 'which';
      for (final name in const ['arp-scout', 'arp_scout']) {
        final res = await Process.run(whichCmd, [name]);
        if (res.exitCode == 0) {
          final lines = (res.stdout as String).trim().split('\n');
          for (final line in lines) {
            final trimmed = line.trim();
            if (trimmed.isNotEmpty && await File(trimmed).exists()) {
              return trimmed;
            }
          }
        }
      }
    } catch (_) {}

    return null;
  }
}
