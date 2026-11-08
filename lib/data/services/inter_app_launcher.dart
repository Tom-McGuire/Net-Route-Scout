import 'dart:convert';
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

    // On macOS, if the resolved target is an application bundle (.app), launch via `open -a`
    if (Platform.isMacOS && exePath.endsWith('.app')) {
      final openArgs = [
        '-a',
        exePath,
        '--args',
        ...args,
      ];
      await Process.start('open', openArgs, mode: ProcessStartMode.detached);
      return;
    }

    // Windows, Linux, or raw executable binary
    await Process.start(
      exePath,
      args,
      mode: ProcessStartMode.detached,
      workingDirectory: File(exePath).parent.path,
    );
  }

  /// Helper to check if a file or macOS app bundle directory exists.
  static Future<bool> _isPathValid(String path) async {
    if (path.isEmpty) return false;
    if (path.endsWith('.app')) {
      return await Directory(path).exists();
    }
    return await File(path).exists();
  }

  /// Returns the suite configuration file used to store custom user preferences.
  static File _getConfigFile() {
    final baseDir = Platform.isWindows
        ? (Platform.environment['LOCALAPPDATA'] ??
            Platform.environment['APPDATA'] ??
            Platform.environment['USERPROFILE'] ??
            '.')
        : (Platform.environment['HOME'] ?? '.');
    final dir = Directory('$baseDir${Platform.pathSeparator}.net_route_scout');
    if (!dir.existsSync()) {
      try {
        dir.createSync(recursive: true);
      } catch (_) {}
    }
    return File('${dir.path}${Platform.pathSeparator}suite_config.json');
  }

  /// Retrieves previously saved custom path to ARP Scout executable if valid.
  static Future<String?> getCustomArpScoutPath() async {
    try {
      final file = _getConfigFile();
      if (await file.exists()) {
        final content = await file.readAsString();
        final decoded = jsonDecode(content);
        if (decoded is Map && decoded['arpScoutPath'] is String) {
          final p = decoded['arpScoutPath'] as String;
          if (await _isPathValid(p)) {
            return p;
          }
        }
      }
    } catch (_) {}
    return null;
  }

  /// Persists user-selected custom path to ARP Scout executable.
  static Future<void> saveCustomArpScoutPath(String path) async {
    try {
      final file = _getConfigFile();
      Map<String, dynamic> data = {};
      if (await file.exists()) {
        try {
          final content = await file.readAsString();
          final decoded = jsonDecode(content);
          if (decoded is Map<String, dynamic>) {
            data = decoded;
          }
        } catch (_) {}
      }
      data['arpScoutPath'] = path;
      await file.writeAsString(jsonEncode(data));
    } catch (_) {}
  }

  /// Resolves the file path for the ARP Scout executable based on development sibling
  /// paths, production suite install paths, desktop entries, Spotlight, Registry, or system PATH.
  static Future<String?> resolveArpScoutExecutable({
    List<String>? candidatePathsOverride,
  }) async {
    // 0. Explicit candidate overrides (e.g. testing)
    if (candidatePathsOverride != null) {
      for (final p in candidatePathsOverride) {
        if (await _isPathValid(p)) return p;
      }
      return null;
    }

    // 1. Saved custom user configuration
    final customPath = await getCustomArpScoutPath();
    if (customPath != null && await _isPathValid(customPath)) {
      return customPath;
    }

    // 2. Dynamic sibling & ancestor scanning relative to running executable and working dir
    final siblingPaths = _getSiblingCandidatePaths();
    for (final p in siblingPaths) {
      if (await _isPathValid(p)) return p;
    }

    // 3. Platform-specific candidate installation directories
    final systemPaths = _getSystemCandidatePaths();
    for (final p in systemPaths) {
      if (await _isPathValid(p)) return p;
    }

    // 4. Linux desktop launcher (.desktop) entries
    if (Platform.isLinux) {
      final desktopPath = await _queryLinuxDesktopFile();
      if (desktopPath != null) return desktopPath;
    }

    // 5. macOS Spotlight LaunchServices lookup
    if (Platform.isMacOS) {
      final macPath = await _queryMacOsSpotlight();
      if (macPath != null) return macPath;
    }

    // 6. Windows Registry query
    if (Platform.isWindows) {
      final regKeys = const [
        r'HKCU\Software\Microsoft\Windows\CurrentVersion\App Paths\arp_scout.exe',
        r'HKLM\Software\Microsoft\Windows\CurrentVersion\App Paths\arp_scout.exe',
        r'HKCU\Software\Microsoft\Windows\CurrentVersion\App Paths\arp-scout.exe',
        r'HKLM\Software\Microsoft\Windows\CurrentVersion\App Paths\arp-scout.exe',
        r'HKCR\arpscout\shell\open\command',
        r'HKCU\Software\Classes\arpscout\shell\open\command',
      ];
      for (final key in regKeys) {
        final regPath = await _queryWindowsRegistry(key);
        if (regPath != null) return regPath;
      }
    }

    // 7. System PATH check
    try {
      final whichCmd = Platform.isWindows ? 'where' : 'which';
      final names = Platform.isWindows
          ? const ['arp_scout.exe', 'arp-scout.exe', 'arp_scout', 'arp-scout']
          : const ['arp_scout', 'arp-scout'];
      for (final name in names) {
        final res = await Process.run(whichCmd, [name]);
        if (res.exitCode == 0) {
          final lines = (res.stdout as String).trim().split('\n');
          for (final line in lines) {
            final trimmed = line.trim();
            if (await _isPathValid(trimmed)) {
              return trimmed;
            }
          }
        }
      }
    } catch (_) {}

    return null;
  }

  static List<String> _getSiblingCandidatePaths() {
    final results = <String>[];
    final sep = Platform.pathSeparator;

    final exeNames = [
      if (Platform.isWindows) ...const [
        'arp_scout.exe',
        'arp-scout.exe',
        'ARP Scout.exe',
        'ARP-Scout.exe',
      ],
      if (Platform.isLinux) ...const [
        'arp_scout',
        'arp-scout',
        'ARP-Scout',
        'ARP_Scout',
      ],
      if (Platform.isMacOS) ...const [
        'ARP & Subnet Scout.app',
        'ARP Scout.app',
        'ARP-Scout.app',
        'arp_scout.app',
        'Contents/MacOS/ARP & Subnet Scout',
        'Contents/MacOS/ARP Scout',
        'Contents/MacOS/arp_scout',
      ],
    ];

    final siblingFolders = const [
      'ARP-Scout',
      'ARP Scout',
      'ARP & Subnet Scout',
      'ARP-Scout_windows_x64',
      'ARP-Scout_linux_x64',
      'ARP-Scout_macos',
      'arp_scout',
      'arp-scout',
      'arp_scout_windows_x64',
      'arp_scout_linux_x64',
    ];

    // Search from Platform.resolvedExecutable parent and walk up ancestor directories
    try {
      final resolved = File(Platform.resolvedExecutable);
      var current = resolved.parent;

      // Same directory as currently running executable
      for (final name in exeNames) {
        results.add('${current.path}$sep$name');
      }

      // Check up to 6 parent levels for sibling folders
      for (var level = 0; level < 6; level++) {
        for (final folder in siblingFolders) {
          final dirPath = '${current.path}$sep$folder';
          for (final name in exeNames) {
            results.add('$dirPath$sep$name');
            // Check build directories within sibling project
            results.add('$dirPath${sep}build${sep}windows${sep}x64${sep}runner${sep}Release$sep$name');
            results.add('$dirPath${sep}build${sep}windows${sep}x64${sep}runner${sep}Debug$sep$name');
            results.add('$dirPath${sep}build${sep}linux${sep}x64${sep}release${sep}bundle$sep$name');
            results.add('$dirPath${sep}build${sep}linux${sep}x64${sep}debug${sep}bundle$sep$name');
            results.add('$dirPath${sep}build${sep}macos${sep}Build${sep}Products${sep}Release$sep$name');
            results.add('$dirPath${sep}build${sep}macos${sep}Build${sep}Products${sep}Debug$sep$name');
          }
        }
        if (current.parent.path == current.path) break;
        current = current.parent;
      }
    } catch (_) {}

    // Search from Directory.current
    try {
      var current = Directory.current;
      for (var level = 0; level < 4; level++) {
        for (final folder in siblingFolders) {
          final dirPath = '${current.path}$sep$folder';
          for (final name in exeNames) {
            results.add('$dirPath$sep$name');
            results.add('$dirPath${sep}build${sep}windows${sep}x64${sep}runner${sep}Release$sep$name');
            results.add('$dirPath${sep}build${sep}windows${sep}x64${sep}runner${sep}Debug$sep$name');
            results.add('$dirPath${sep}build${sep}linux${sep}x64${sep}release${sep}bundle$sep$name');
            results.add('$dirPath${sep}build${sep}linux${sep}x64${sep}debug${sep}bundle$sep$name');
            results.add('$dirPath${sep}build${sep}macos${sep}Build${sep}Products${sep}Release$sep$name');
            results.add('$dirPath${sep}build${sep}macos${sep}Build${sep}Products${sep}Debug$sep$name');
          }
        }
        if (current.parent.path == current.path) break;
        current = current.parent;
      }
    } catch (_) {}

    return results;
  }

  static List<String> _getSystemCandidatePaths() {
    final candidatePaths = <String>[];

    if (Platform.isLinux) {
      candidatePaths.addAll(const [
        '../ARP-Scout/build/linux/x64/release/bundle/arp_scout',
        '../ARP-Scout/build/linux/x64/debug/bundle/arp_scout',
        '/usr/local/bin/arp_scout',
        '/usr/local/bin/arp-scout',
        '/usr/bin/arp_scout',
        '/usr/bin/arp-scout',
        '/opt/NetworkSuite/arp_scout',
        '/opt/NetworkSuite/arp-scout',
        '/opt/NetworkSuite/bin/arp_scout',
        '/opt/NetworkSuite/bin/arp-scout',
        '/opt/ARP-Scout/arp_scout',
        '/opt/arp_scout/arp_scout',
      ]);
      final home = Platform.environment['HOME'] ?? '';
      if (home.isNotEmpty) {
        candidatePaths.add('$home/.local/bin/arp_scout');
        candidatePaths.add('$home/.local/bin/arp-scout');
        candidatePaths.add('$home/bin/arp_scout');
        candidatePaths.add('$home/bin/arp-scout');
        candidatePaths.add('$home/Downloads/ARP-Scout/arp_scout');
        candidatePaths.add('$home/Downloads/ARP-Scout_linux_x64/arp_scout');
        candidatePaths.add('$home/Downloads/arp_scout/arp_scout');
        candidatePaths.add('$home/Desktop/ARP-Scout/arp_scout');
      }
    }

    if (Platform.isWindows) {
      final localAppData = Platform.environment['LOCALAPPDATA'] ?? '';
      final appData = Platform.environment['APPDATA'] ?? '';
      final programFiles = Platform.environment['PROGRAMFILES'] ?? '';
      final programFilesX86 = Platform.environment['ProgramFiles(x86)'] ?? '';
      final userProfile = Platform.environment['USERPROFILE'] ?? '';

      final baseDirs = <String>[
        if (localAppData.isNotEmpty) ...[
          '$localAppData\\NetworkSuite',
          '$localAppData\\ARP Scout',
          '$localAppData\\ARP-Scout',
          '$localAppData\\arp_scout',
          '$localAppData\\arp-scout',
          '$localAppData\\Programs\\ARP Scout',
          '$localAppData\\Programs\\ARP-Scout',
          '$localAppData\\Programs\\arp_scout',
          '$localAppData\\Programs\\NetworkSuite',
        ],
        if (appData.isNotEmpty) ...[
          '$appData\\NetworkSuite',
          '$appData\\ARP Scout',
          '$appData\\ARP-Scout',
        ],
        if (programFiles.isNotEmpty) ...[
          '$programFiles\\NetworkSuite',
          '$programFiles\\ARP Scout',
          '$programFiles\\ARP-Scout',
          '$programFiles\\arp_scout',
        ],
        if (programFilesX86.isNotEmpty) ...[
          '$programFilesX86\\NetworkSuite',
          '$programFilesX86\\ARP Scout',
          '$programFilesX86\\ARP-Scout',
          '$programFilesX86\\arp_scout',
        ],
        if (userProfile.isNotEmpty) ...[
          '$userProfile\\Downloads\\ARP-Scout',
          '$userProfile\\Downloads\\ARP-Scout_windows_x64',
          '$userProfile\\Downloads\\arp_scout',
          '$userProfile\\Desktop\\ARP-Scout',
          '$userProfile\\Desktop\\ARP Scout',
          '$userProfile\\Desktop\\arp_scout',
        ],
      ];

      for (final dir in baseDirs) {
        for (final exe in const ['arp_scout.exe', 'arp-scout.exe', 'ARP Scout.exe', 'ARP-Scout.exe']) {
          candidatePaths.add('$dir\\$exe');
        }
      }
    }

    if (Platform.isMacOS) {
      candidatePaths.addAll(const [
        '../ARP-Scout/build/macos/Build/Products/Release/ARP & Subnet Scout.app',
        '../ARP-Scout/build/macos/Build/Products/Release/ARP Scout.app',
        '../ARP-Scout/build/macos/Build/Products/Debug/ARP & Subnet Scout.app',
        '../ARP-Scout/build/macos/Build/Products/Debug/ARP Scout.app',
        '/Applications/ARP & Subnet Scout.app',
        '/Applications/ARP Scout.app',
        '/Applications/ARP-Scout.app',
        '/Applications/arp_scout.app',
        '/Applications/NetworkSuite/ARP & Subnet Scout.app',
        '/Applications/NetworkSuite/ARP Scout.app',
      ]);
      final home = Platform.environment['HOME'] ?? '';
      if (home.isNotEmpty) {
        candidatePaths.add('$home/Applications/ARP & Subnet Scout.app');
        candidatePaths.add('$home/Applications/ARP Scout.app');
        candidatePaths.add('$home/Applications/arp_scout.app');
        candidatePaths.add('$home/Downloads/ARP-Scout/ARP & Subnet Scout.app');
        candidatePaths.add('$home/Downloads/ARP-Scout_macos/ARP & Subnet Scout.app');
        candidatePaths.add('$home/Downloads/ARP-Scout_macos/ARP Scout.app');
      }
    }

    return candidatePaths;
  }

  static Future<String?> _queryLinuxDesktopFile() async {
    try {
      final home = Platform.environment['HOME'] ?? '';
      final appDirs = [
        '/usr/share/applications',
        '/usr/local/share/applications',
        if (home.isNotEmpty) '$home/.local/share/applications',
      ];
      final desktopNames = [
        'arp-scout.desktop',
        'arp_scout.desktop',
        'io.github.tommcguire.arpScout.desktop',
      ];
      for (final dir in appDirs) {
        for (final name in desktopNames) {
          final file = File('$dir/$name');
          if (await file.exists()) {
            final lines = await file.readAsLines();
            for (final line in lines) {
              if (line.startsWith('Exec=')) {
                var execPath = line.substring(5).trim();
                execPath = execPath.split(RegExp(r'\s+%[a-zA-Z]')).first.trim();
                if (execPath.startsWith('"') && execPath.endsWith('"')) {
                  execPath = execPath.substring(1, execPath.length - 1);
                }
                if (execPath.isNotEmpty && await _isPathValid(execPath)) {
                  return execPath;
                }
              }
            }
          }
        }
      }
    } catch (_) {}
    return null;
  }

  static Future<String?> _queryMacOsSpotlight() async {
    try {
      final queries = [
        "kMDItemCFBundleIdentifier == 'io.github.tommcguire.arpScout'",
        "kMDItemFSName == 'ARP & Subnet Scout.app'",
        "kMDItemFSName == 'ARP Scout.app'",
        "kMDItemFSName == 'arp_scout.app'",
      ];
      for (final query in queries) {
        final res = await Process.run('mdfind', [query]);
        if (res.exitCode == 0) {
          final lines = (res.stdout as String).trim().split('\n');
          for (final line in lines) {
            final trimmed = line.trim();
            if (await _isPathValid(trimmed)) {
              return trimmed;
            }
          }
        }
      }
    } catch (_) {}
    return null;
  }

  static Future<String?> _queryWindowsRegistry(String command) async {
    try {
      final res = await Process.run('reg', ['query', command, '/ve']);
      if (res.exitCode == 0) {
        final output = res.stdout as String;
        final match = RegExp(r'REG_SZ\s+(.+)$', multiLine: true).firstMatch(output);
        if (match != null) {
          var p = match.group(1)?.trim();
          if (p != null) {
            if (p.startsWith('"')) {
              final closeQuote = p.indexOf('"', 1);
              if (closeQuote > 0) {
                p = p.substring(1, closeQuote);
              }
            }
            if (await _isPathValid(p)) {
              return p;
            }
          }
        }
      }
    } catch (_) {}
    return null;
  }
}
