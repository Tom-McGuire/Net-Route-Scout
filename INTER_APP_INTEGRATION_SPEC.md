# Inter-App Integration Specification: Net Route Scout ↔ ARP Scout

> **Target Audience**: AI Agent / Developer managing **Net Route Scout** (`net_route_scout`, project folder `route-tracer`)  
> **Companion Application**: **ARP Scout** (`arp_scout`, located at `../ARP-Scout`)  
> **Goal**: Allow Net Route Scout to (1) accept incoming trace targets from ARP Scout with the matching network adapter pre-selected, and (2) launch or command ARP Scout to sweep a discovered subnet directly from any node on the topology diagram.

---

## 1. Protocol & Contract Overview

The two applications communicate via:
1. **Command Line Arguments** (cold launch when companion is closed).
2. **Local Loopback Socket IPC** (warm handoff when companion is already open).
3. **Custom URI Scheme** (optional deep linking: `netroutescout://` and `arpscout://`).

### Well-Known Loopback IPC Ports
* **Net Route Scout Listener Port**: `44101`
* **ARP Scout Listener Port**: `44102`

### Shared Parameter Specification

| Parameter | CLI Flag | JSON IPC Key | URI Query Param | Description | Example |
| :--- | :--- | :--- | :--- | :--- | :--- |
| **Target Host** | `--target <ip>` | `"target"` | `target` | Destination IPv4 for Route Scout to trace | `192.168.1.50` |
| **Subnet CIDR** | `--subnet <cidr>` | `"subnet"` | `subnet` | Subnet for ARP Scout to sweep | `192.168.1.0/24` |
| **Network Adapter IP** | `--adapter-ip <ip>` | `"adapterIp"` | `adapterIp` | **Primary matching key** for the local interface | `192.168.1.150` |
| **Network Adapter Name**| `--adapter-name <name>`| `"adapterName"`| `adapterName`| Secondary fallback matching key | `eth0`, `en0`, `Wi-Fi` |
| **Auto-Execute** | `--auto-start` | `"autoStart"` | `autoStart=true`| If true, trigger scan/trace immediately | Flag present / `true` |

---

## 2. Inbound: Accepting Trace Commands in Net Route Scout

When ARP Scout launches Net Route Scout (e.g. user right-clicks a host and clicks *"Trace Route in Net Route Scout"*):
1. Parse `--target`, `--adapter-ip`, `--adapter-name`, and `--auto-start`.
2. Match the exact physical network adapter from `NetworkAdapterService.getAvailableAdapters()`.
3. Set the target IP into the input bar.
4. If `--auto-start` is true, immediately trigger `tracerouteViewModel.startTrace(target)`.

### 2.1 Main Entrypoint Argument Handling (`lib/main.dart`)
Update `main()` in `lib/main.dart`:

```dart
void main(List<String> args) async {
  WidgetsFlutterBinding.ensureInitialized();

  String? initialTarget;
  String? targetAdapterIp;
  String? targetAdapterName;
  bool autoStart = false;

  for (int i = 0; i < args.length; i++) {
    if (args[i] == '--target' && i + 1 < args.length) initialTarget = args[++i];
    if (args[i] == '--adapter-ip' && i + 1 < args.length) targetAdapterIp = args[++i];
    if (args[i] == '--adapter-name' && i + 1 < args.length) targetAdapterName = args[++i];
    if (args[i] == '--auto-start') autoStart = true;
  }

  // Single-instance loopback IPC listener on port 44101
  InterAppIpcService.startListener(44101, (payload) {
    final routeViewModel = getIt<TracerouteViewModel>();
    routeViewModel.handleIncomingCommand(
      target: payload['target'] as String?,
      adapterIp: payload['adapterIp'] as String?,
      adapterName: payload['adapterName'] as String?,
      autoStart: payload['autoStart'] == true,
    );
  });

  runApp(MyApp(
    initialTarget: initialTarget,
    initialAdapterIp: targetAdapterIp,
    initialAdapterName: targetAdapterName,
    autoStart: autoStart,
  ));
}
```

### 2.2 Adapter Matching Algorithm in `TracerouteViewModel`

```dart
void selectMatchingAdapter({String? adapterIp, String? adapterName}) {
  if (availableAdapters.isEmpty) return;

  // 1. Primary match: by IP address (exact physical interface match)
  if (adapterIp != null && adapterIp.isNotEmpty) {
    final match = availableAdapters.firstWhere(
      (a) => a.ipAddress == adapterIp,
      orElse: () => availableAdapters.first,
    );
    selectedAdapter = match;
    notifyListeners();
    return;
  }

  // 2. Secondary match: by Interface Name (e.g. "eth0")
  if (adapterName != null && adapterName.isNotEmpty) {
    final match = availableAdapters.firstWhere(
      (a) => a.name.toLowerCase() == adapterName.toLowerCase(),
      orElse: () => availableAdapters.first,
    );
    selectedAdapter = match;
    notifyListeners();
    return;
  }
}
```

---

## 3. Outbound: Launching ARP Scout from Net Route Scout

### 3.1 UI Entrypoint
On the **Topology Canvas** ([`lib/ui/views/widgets/topology_canvas.dart`](lib/ui/views/widgets/topology_canvas.dart)):
* When clicking on a gateway, hop node, or destination endpoint:
  * In the **Node Inspector Card**, add an action button:
    * **"Scan Subnet in ARP Scout"** (with `Icons.radar` or `Icons.travel_explore`).
  * On right-click context menu of any node:
    * **"Scan Subnet with ARP Scout"**.

### 3.2 Executable Resolution Order
When launching ARP Scout (`arp_scout`), look up the binary in this order:
1. **Development Sibling Path**:
   * Linux: `../ARP-Scout/build/linux/x64/release/bundle/arp_scout` (or `debug/bundle/arp_scout`)
   * Windows: `..\ARP-Scout\build\windows\x64\runner\Release\arp_scout.exe`
   * macOS: `../ARP-Scout/build/macos/Build/Products/Release/ARP Scout.app`
2. **Production Suite Directory**:
   * Linux: `/usr/local/bin/arp-scout` or `/opt/NetworkSuite/arp-scout`
   * Windows: `%LOCALAPPDATA%\NetworkSuite\arp-scout.exe`
   * macOS: `/Applications/ARP Scout.app/Contents/MacOS/arp_scout`
3. **System `$PATH`**: `arp-scout` / `arp_scout`.

### 3.3 Dart Implementation Snippet (`inter_app_launcher.dart`)

```dart
import 'dart:convert';
import 'dart:io';
import '../../domain/models/network_adapter_info.dart';

class InterAppLauncher {
  static const int arpScoutIpcPort = 44102; // ARP Scout loopback listener

  /// Launches or commands ARP Scout to scan [subnetCidr] using [currentAdapter].
  static Future<void> launchSubnetScan({
    required String subnetCidr,
    required NetworkAdapterInfo currentAdapter,
    bool autoStart = true,
  }) async {
    // 1. Warm handoff: Check if ARP Scout is already running
    try {
      final socket = await Socket.connect('127.0.0.1', arpScoutIpcPort, timeout: const Duration(milliseconds: 300));
      final payload = jsonEncode({
        'action': 'scan',
        'subnet': subnetCidr,
        'adapterIp': currentAdapter.ipAddress,
        'adapterName': currentAdapter.name,
        'autoStart': autoStart,
      });
      socket.write('$payload\n');
      await socket.flush();
      await socket.close();
      return; // Handed off cleanly
    } catch (_) {
      // ARP Scout is not running; fall back to cold launch
    }

    // 2. Cold process launch
    final exePath = await _resolveArpScoutExecutable();
    if (exePath == null) {
      throw Exception('ARP Scout executable not found on system.');
    }

    final args = [
      '--subnet', subnetCidr,
      '--adapter-ip', currentAdapter.ipAddress,
      '--adapter-name', currentAdapter.name,
      if (autoStart) '--auto-start',
    ];

    await Process.start(exePath, args, mode: ProcessStartMode.detached);
  }

  static Future<String?> _resolveArpScoutExecutable() async {
    final candidatePaths = <String>[
      if (Platform.isLinux) ...[
        '../ARP-Scout/build/linux/x64/release/bundle/arp_scout',
        '../ARP-Scout/build/linux/x64/debug/bundle/arp_scout',
        '/usr/local/bin/arp-scout',
        '/opt/NetworkSuite/arp-scout',
      ],
      if (Platform.isWindows) ...[
        r'..\ARP-Scout\build\windows\x64\runner\Release\arp_scout.exe',
        r'..\ARP-Scout\build\windows\x64\runner\Debug\arp_scout.exe',
        '${Platform.environment['LOCALAPPDATA']}\\NetworkSuite\\arp-scout.exe',
      ],
      if (Platform.isMacOS) ...[
        '../ARP-Scout/build/macos/Build/Products/Release/ARP Scout.app/Contents/MacOS/arp_scout',
        '/Applications/ARP Scout.app/Contents/MacOS/arp_scout',
      ],
    ];

    for (final p in candidatePaths) {
      if (await File(p).exists()) return p;
    }
    return null;
  }
}
```

---

## 4. Verification & Testing Checklist

- [ ] **Warm Handoff**: Open ARP Scout, then click "Scan Subnet in ARP Scout" from a node in Net Route Scout. Confirm ARP Scout updates the subnet and triggers scan without spawning a new window.
- [ ] **Cold Handoff**: Close Net Route Scout. Send command from ARP Scout to trace an IP. Confirm Net Route Scout launches, selects the exact network adapter, and begins tracing.
- [ ] **Adapter Parity**: Ensure that whether the adapter is matched by IP (`192.168.1.150`) or by name (`eth0` / `Wi-Fi`), both applications never diverge onto different physical NICs.
