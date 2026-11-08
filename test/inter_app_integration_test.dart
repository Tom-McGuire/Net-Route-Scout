import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:net_route_scout/data/services/inter_app_ipc_service.dart';
import 'package:net_route_scout/data/services/inter_app_launcher.dart';
import 'package:net_route_scout/domain/models/inter_app_arguments.dart';
import 'package:net_route_scout/domain/models/network_adapter_info.dart';
import 'package:net_route_scout/domain/models/network_node.dart';
import 'package:net_route_scout/ui/view_models/topology_view_model.dart';

void main() {
  group('InterAppArguments Tests', () {
    test('Parses full CLI arguments correctly', () {
      final args = [
        '--target',
        '192.168.1.100',
        '--adapter-ip',
        '192.168.1.15',
        '--adapter-name',
        'eth0',
        '--auto-start',
      ];

      final parsed = InterAppArguments.fromArgs(args);
      expect(parsed.target, '192.168.1.100');
      expect(parsed.adapterIp, '192.168.1.15');
      expect(parsed.adapterName, 'eth0');
      expect(parsed.autoStart, isTrue);
    });

    test('Parses subnet CLI argument', () {
      final args = ['--subnet', '10.0.0.0/24'];
      final parsed = InterAppArguments.fromArgs(args);
      expect(parsed.subnet, '10.0.0.0/24');
      expect(parsed.target, isNull);
      expect(parsed.autoStart, isFalse);
    });

    test('Handles missing flag values gracefully without crashing', () {
      final args = ['--target', '--adapter-ip', '--adapter-name'];
      final parsed = InterAppArguments.fromArgs(args);
      expect(parsed.target, '--adapter-ip');
      expect(parsed.adapterIp, isNull);
      expect(parsed.autoStart, isFalse);
    });

    test('JSON serialization round-trip', () {
      const original = InterAppArguments(
        target: '8.8.8.8',
        subnet: '192.168.0.0/24',
        adapterIp: '192.168.0.105',
        adapterName: 'wlan0',
        autoStart: true,
      );

      final json = original.toJson();
      expect(json['target'], '8.8.8.8');
      expect(json['subnet'], '192.168.0.0/24');
      expect(json['adapterIp'], '192.168.0.105');
      expect(json['adapterName'], 'wlan0');
      expect(json['autoStart'], isTrue);

      final restored = InterAppArguments.fromJson(json);
      expect(restored.target, original.target);
      expect(restored.subnet, original.subnet);
      expect(restored.adapterIp, original.adapterIp);
      expect(restored.adapterName, original.adapterName);
      expect(restored.autoStart, original.autoStart);
    });
  });

  group('Adapter Matching Algorithm Tests', () {
    final testAdapters = [
      const NetworkAdapterInfo(
        id: 'eth0',
        name: 'Ethernet 1',
        ipAddress: '192.168.1.150',
        subnetCidr: '192.168.1.0/24',
        prefixLength: 24,
      ),
      const NetworkAdapterInfo(
        id: 'wlan0',
        name: 'Wi-Fi Adapter',
        ipAddress: '10.0.0.45',
        subnetCidr: '10.0.0.0/24',
        prefixLength: 24,
      ),
      const NetworkAdapterInfo(
        id: 'tun0',
        name: 'VPN Tunnel',
        ipAddress: '172.16.0.2',
        subnetCidr: '172.16.0.0/16',
        prefixLength: 16,
      ),
    ];

    test('Primary match: exact IP address takes precedence over mismatched name', () {
      final matched = TopologyViewModel.matchAdapter(
        testAdapters,
        adapterIp: '10.0.0.45',
        adapterName: 'Ethernet 1',
      );
      expect(matched, isNotNull);
      expect(matched!.id, 'wlan0');
      expect(matched.ipAddress, '10.0.0.45');
    });

    test('Secondary match: case-insensitive name match when IP is absent', () {
      final matched = TopologyViewModel.matchAdapter(
        testAdapters,
        adapterName: 'wi-fi adapter',
      );
      expect(matched, isNotNull);
      expect(matched!.id, 'wlan0');
      expect(matched.ipAddress, '10.0.0.45');
    });

    test('Secondary match: matches by interface ID', () {
      final matched = TopologyViewModel.matchAdapter(
        testAdapters,
        adapterName: 'TUN0',
      );
      expect(matched, isNotNull);
      expect(matched!.id, 'tun0');
      expect(matched.ipAddress, '172.16.0.2');
    });

    test('Returns null when no adapter matches IP or name', () {
      final matched = TopologyViewModel.matchAdapter(
        testAdapters,
        adapterIp: '192.168.99.99',
        adapterName: 'non_existent',
      );
      expect(matched, isNull);
    });

    test('Returns null when adapter list is empty', () {
      final matched = TopologyViewModel.matchAdapter(
        [],
        adapterIp: '192.168.1.1',
      );
      expect(matched, isNull);
    });
  });

  group('Subnet Derivation for Node Tests', () {
    test('Derives local adapter subnet for localhost and local subnet nodes', () {
      final vm = TopologyViewModel(autoInit: false);
      const adapter = NetworkAdapterInfo(
        id: 'eth0',
        name: 'eth0',
        ipAddress: '192.168.1.100',
        subnetCidr: '192.168.1.0/24',
        prefixLength: 24,
      );
      vm.selectAdapter(adapter, autoPopulateTarget: false);

      final localNode = NetworkNode(
        id: '192.168.1.100',
        ip: '192.168.1.100',
        hopDepth: 0,
        isLocalHost: true,
      );
      expect(vm.deriveSubnetForNode(localNode), '192.168.1.0/24');

      final neighborNode = NetworkNode(
        id: '192.168.1.50',
        ip: '192.168.1.50',
        hopDepth: 1,
      );
      expect(vm.deriveSubnetForNode(neighborNode), '192.168.1.0/24');
    });

    test('Derives /24 subnet for remote routed hops and endpoints', () {
      final vm = TopologyViewModel(autoInit: false);
      const adapter = NetworkAdapterInfo(
        id: 'eth0',
        name: 'eth0',
        ipAddress: '192.168.1.100',
        subnetCidr: '192.168.1.0/24',
        prefixLength: 24,
      );
      vm.selectAdapter(adapter, autoPopulateTarget: false);

      final remoteHop = NetworkNode(
        id: '10.120.99.68',
        ip: '10.120.99.68',
        hopDepth: 2,
      );
      expect(vm.deriveSubnetForNode(remoteHop), '10.120.99.0/24');

      final externalEndpoint = NetworkNode(
        id: '142.250.190.46',
        ip: '142.250.190.46',
        hopDepth: 8,
      );
      expect(vm.deriveSubnetForNode(externalEndpoint), '142.250.190.0/24');
    });

    test('Returns empty string for unresponsive or anonymous hops', () {
      final vm = TopologyViewModel(autoInit: false);

      final unresponsiveNode = NetworkNode(
        id: '10.0.0.1',
        ip: '10.0.0.1',
        hopDepth: 3,
        isUnresponsive: true,
      );
      expect(vm.deriveSubnetForNode(unresponsiveNode), '');

      final anonHop = NetworkNode(
        id: 'anon:hop4',
        ip: 'anon:hop4',
        hopDepth: 4,
      );
      expect(vm.deriveSubnetForNode(anonHop), '');
    });
  });

  group('InterAppIpcService Loopback Socket Tests', () {
    test('Starts listener, exchanges payload, and stops cleanly', () async {
      const testPort = 44199;
      Map<String, dynamic>? receivedPayload;

      final server = await InterAppIpcService.startListener(testPort, (payload) {
        receivedPayload = payload;
      });
      expect(server, isNotNull);

      final sentPayload = {
        'target': '1.1.1.1',
        'adapterIp': '192.168.1.5',
        'adapterName': 'en0',
        'autoStart': false,
      };

      final delivered = await InterAppIpcService.sendCommand(
        port: testPort,
        payload: sentPayload,
        timeout: const Duration(seconds: 1),
      );
      expect(delivered, isTrue);

      // Allow event loop to process message
      await Future<void>.delayed(const Duration(milliseconds: 50));
      expect(receivedPayload, isNotNull);
      expect(receivedPayload!['target'], '1.1.1.1');
      expect(receivedPayload!['adapterIp'], '192.168.1.5');
      expect(receivedPayload!['adapterName'], 'en0');
      expect(receivedPayload!['autoStart'], isFalse);

      await InterAppIpcService.stopListener();
    });

    test('sendCommand returns false when port is not listening', () async {
      final delivered = await InterAppIpcService.sendCommand(
        port: 44198,
        payload: {'test': true},
        timeout: const Duration(milliseconds: 100),
      );
      expect(delivered, isFalse);
    });
  });

  group('InterAppLauncher Executable Resolution Tests', () {
    test('Resolves candidate path override when file exists', () async {
      // Create a temporary mock file to act as the executable
      final tempDir = Directory.systemTemp.createTempSync('scout_test_');
      final mockExe = File('${tempDir.path}/mock_arp_scout')..createSync();

      try {
        final resolved = await InterAppLauncher.resolveArpScoutExecutable(
          candidatePathsOverride: [mockExe.path],
        );
        expect(resolved, mockExe.path);
      } finally {
        tempDir.deleteSync(recursive: true);
      }
    });

    test('Returns null when candidate paths do not exist', () async {
      final resolved = await InterAppLauncher.resolveArpScoutExecutable(
        candidatePathsOverride: ['/non/existent/path/to/arp_scout_binary'],
      );
      expect(resolved, isNull);
    });

    test('Saves and retrieves custom ARP Scout path', () async {
      final tempDir = Directory.systemTemp.createTempSync('custom_scout_');
      final mockExe = File('${tempDir.path}/custom_arp_scout.exe')..createSync();
      try {
        await InterAppLauncher.saveCustomArpScoutPath(mockExe.path);
        final retrieved = await InterAppLauncher.getCustomArpScoutPath();
        expect(retrieved, mockExe.path);
      } finally {
        tempDir.deleteSync(recursive: true);
      }
    });
  });

  group('TopologyViewModel Incoming Command Handling Tests', () {
    test('handleIncomingCommand sets target and autoStart state', () async {
      final vm = TopologyViewModel(autoInit: false);
      expect(vm.targetInput, isEmpty);

      await vm.handleIncomingCommand(
        target: '192.168.50.1',
        autoStart: false,
      );

      expect(vm.targetInput, '192.168.50.1');
    });
  });
}
