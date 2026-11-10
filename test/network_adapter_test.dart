import 'package:flutter_test/flutter_test.dart';
import 'package:net_route_scout/data/services/network_adapter_service.dart';
import 'package:net_route_scout/domain/models/network_adapter_info.dart';

void main() {
  group('NetworkAdapterInfo Model Tests', () {
    test('calculateSubnetCidr handles standard /24 subnet', () {
      expect(
        NetworkAdapterInfo.calculateSubnetCidr('192.168.1.55', 24),
        '192.168.1.0/24',
      );
    });

    test('calculateSubnetCidr handles /16 subnet', () {
      expect(
        NetworkAdapterInfo.calculateSubnetCidr('10.200.45.12', 16),
        '10.200.0.0/16',
      );
    });

    test('calculateSubnetCidr handles non-byte boundary subnets (/26 and /28)', () {
      // 192.168.1.135 with /26 (mask 255.255.255.192, block 128-191) -> network 192.168.1.128/26
      expect(
        NetworkAdapterInfo.calculateSubnetCidr('192.168.1.135', 26),
        '192.168.1.128/26',
      );

      // 10.0.0.19 with /28 (mask 255.255.255.240, block 16-31) -> network 10.0.0.16/28
      expect(
        NetworkAdapterInfo.calculateSubnetCidr('10.0.0.19', 28),
        '10.0.0.16/28',
      );
    });

    test('calculateSubnetCidr clamps prefix limits between 8 and 30', () {
      expect(
        NetworkAdapterInfo.calculateSubnetCidr('10.1.2.3', 4),
        '10.0.0.0/8',
      );
      expect(
        NetworkAdapterInfo.calculateSubnetCidr('192.168.1.1', 32),
        '192.168.1.0/30',
      );
    });

    test('normalizeMac standardizes delimiters and case', () {
      expect(NetworkAdapterInfo.normalizeMac('00-1a-2b-3c-4d-5e'), '00:1A:2B:3C:4D:5E');
      expect(NetworkAdapterInfo.normalizeMac('00:1a:2b:3c:4d:5e'), '00:1A:2B:3C:4D:5E');
      expect(NetworkAdapterInfo.normalizeMac('   '), isNull);
      expect(NetworkAdapterInfo.normalizeMac(null), isNull);
    });

    test('displayName and shortDisplayName format correctly', () {
      const adapterWithMac = NetworkAdapterInfo(
        id: 'eth0',
        name: 'Ethernet',
        ipAddress: '192.168.1.50',
        macAddress: '00:1A:2B:3C:4D:5E',
        subnetCidr: '192.168.1.0/24',
      );
      expect(adapterWithMac.displayName, 'Ethernet (192.168.1.50)');
      expect(adapterWithMac.shortDisplayName, 'Ethernet: 192.168.1.50');

      const adapterWithoutMac = NetworkAdapterInfo(
        id: 'eth1',
        name: 'VirtualNic',
        ipAddress: '10.0.0.2',
        subnetCidr: '10.0.0.0/24',
      );
      expect(adapterWithoutMac.displayName, 'VirtualNic (10.0.0.2)');
    });

    test('Loopback detection', () {
      const loopbackAdapter = NetworkAdapterInfo(
        id: 'lo',
        name: 'Loopback Pseudo-Interface 1',
        ipAddress: '127.0.0.1',
        subnetCidr: '127.0.0.0/8',
      );
      expect(loopbackAdapter.isLoopback, isTrue);

      const normalAdapter = NetworkAdapterInfo(
        id: 'enp1s0',
        name: 'Ethernet',
        ipAddress: '192.168.1.15',
        subnetCidr: '192.168.1.0/24',
      );
      expect(normalAdapter.isLoopback, isFalse);
    });

    test('Equality and hashCode based on id and ipAddress', () {
      const a1 = NetworkAdapterInfo(
        id: 'eth0',
        name: 'Ethernet 1',
        ipAddress: '192.168.1.50',
        subnetCidr: '192.168.1.0/24',
      );
      const a2 = NetworkAdapterInfo(
        id: 'eth0',
        name: 'Ethernet 1 Renamed',
        ipAddress: '192.168.1.50',
        subnetCidr: '192.168.1.0/24',
      );
      const a3 = NetworkAdapterInfo(
        id: 'eth1',
        name: 'Ethernet 1',
        ipAddress: '192.168.1.50',
        subnetCidr: '192.168.1.0/24',
      );

      expect(a1, equals(a2));
      expect(a1.hashCode, equals(a2.hashCode));
      expect(a1, isNot(equals(a3)));
    });
  });

  group('NetworkAdapterService Parser Tests', () {
    test('maskToPrefix correctly calculates bit counts', () {
      expect(NetworkAdapterService.maskToPrefix('255.255.255.0'), 24);
      expect(NetworkAdapterService.maskToPrefix('255.255.0.0'), 16);
      expect(NetworkAdapterService.maskToPrefix('255.0.0.0'), 8);
      expect(NetworkAdapterService.maskToPrefix('255.255.255.128'), 25);
      expect(NetworkAdapterService.maskToPrefix('255.255.255.240'), 28);
      expect(NetworkAdapterService.maskToPrefix('255.255.255.252'), 30);
      expect(NetworkAdapterService.maskToPrefix('invalid-mask'), 24);
    });

    test('parseWindowsIpconfig parses English Windows output', () {
      const ipconfigOutput = '''
Windows IP Configuration

Ethernet adapter Ethernet:

   Connection-specific DNS Suffix  . : localdomain
   Description . . . . . . . . . . . : Intel(R) Ethernet Connection (2) I219-V
   Physical Address. . . . . . . . . : 00-1A-2B-3C-4D-5E
   DHCP Enabled. . . . . . . . . . . : Yes
   IPv4 Address. . . . . . . . . . . : 192.168.1.120(Preferred) 
   Subnet Mask . . . . . . . . . . . : 255.255.255.0
   Default Gateway . . . . . . . . . : 192.168.1.1

Wireless LAN adapter Wi-Fi:

   Media State . . . . . . . . . . . : Media disconnected
   Connection-specific DNS Suffix  . : 

Ethernet adapter vEthernet (WSL):

   Description . . . . . . . . . . . : Hyper-V Virtual Ethernet Adapter
   Physical Address. . . . . . . . . : 00-15-5D-11-22-33
   IPv4 Address. . . . . . . . . . . : 172.28.16.1(Preferred) 
   Subnet Mask . . . . . . . . . . . : 255.255.240.0
   Default Gateway . . . . . . . . . : 
''';

      final adapters = NetworkAdapterService.parseWindowsIpconfig(ipconfigOutput);
      expect(adapters.length, 2);

      final eth = adapters.firstWhere((a) => a.name == 'Ethernet');
      expect(eth.ipAddress, '192.168.1.120');
      expect(eth.macAddress, '00:1A:2B:3C:4D:5E');
      expect(eth.prefixLength, 24);
      expect(eth.subnetCidr, '192.168.1.0/24');
      expect(eth.gatewayIp, '192.168.1.1');

      final wsl = adapters.firstWhere((a) => a.name == 'vEthernet (WSL)');
      expect(wsl.ipAddress, '172.28.16.1');
      expect(wsl.macAddress, '00:15:5D:11:22:33');
      expect(wsl.prefixLength, 20);
      expect(wsl.subnetCidr, '172.28.16.0/20');
      expect(wsl.gatewayIp, isNull);
    });

    test('parseWindowsIpconfig parses German Windows output', () {
      const germanOutput = '''
Ethernet-Adapter Ethernet 2:

   Verbindungsspezifisches DNS-Suffix: fritz.box
   Beschreibung. . . . . . . . . . . : Realtek PCIe GbE Family Controller
   Physikalische Adresse . . . . . . : 34-97-F6-AA-BB-CC
   DHCP aktiviert. . . . . . . . . . : Ja
   IPv4-Adresse  . . . . . . . . . . : 192.168.178.45(Bevorzugt) 
   Subnetzmaske  . . . . . . . . . . : 255.255.255.0
   Standardgateway . . . . . . . . . : 192.168.178.1
''';

      final adapters = NetworkAdapterService.parseWindowsIpconfig(germanOutput);
      expect(adapters.length, 1);
      final adapter = adapters.first;
      expect(adapter.name, 'Ethernet 2');
      expect(adapter.ipAddress, '192.168.178.45');
      expect(adapter.macAddress, '34:97:F6:AA:BB:CC');
      expect(adapter.gatewayIp, '192.168.178.1');
      expect(adapter.subnetCidr, '192.168.178.0/24');
    });

    test('parseLinuxDefaultRoute extracts gateway and device interface', () {
      const output = 'default via 192.168.1.1 dev enp3s0 proto dhcp metric 100';
      final parsed = NetworkAdapterService.parseLinuxDefaultRoute(output);
      expect(parsed.gateway, '192.168.1.1');
      expect(parsed.device, 'enp3s0');
    });

    test('parseLinuxAddrPrefix extracts exact matching interface prefix', () {
      const output = '2: enp3s0    inet 192.168.1.100/24 brd 192.168.1.255 scope global dynamic enp3s0';
      final prefix = NetworkAdapterService.parseLinuxAddrPrefix(output, '192.168.1.100');
      expect(prefix, 24);
    });

    test('parseMacDefaultRoute extracts gateway and device interface', () {
      const output = '''
   route to: default
destination: default
       mask: default
    gateway: 192.168.0.1
  interface: en0
      flags: <UP,GATEWAY,DONE,STATIC,PRCLONING>
''';
      final parsed = NetworkAdapterService.parseMacDefaultRoute(output);
      expect(parsed.gateway, '192.168.0.1');
      expect(parsed.device, 'en0');
    });

    test('parseMacIfconfig extracts MAC and decodes hex netmask into prefix', () {
      const output = '''
en0: flags=8863<UP,BROADCAST,SMART,RUNNING,SIMPLEX,MULTICAST> mtu 1500
	ether a4:83:e7:12:34:56
	inet6 fe80::1035:4851:3a1b:6d57%en0 prefixlen 64 secured scopeid 0x6
	inet 192.168.0.105 netmask 0xffffff00 broadcast 192.168.0.255
	nd6 options=201<PERFORMNUD,DAD>
	media: autoselect
	status: active
''';
      final parsed = NetworkAdapterService.parseMacIfconfig(output, '192.168.0.105');
      expect(parsed.mac, 'A4:83:E7:12:34:56');
      expect(parsed.prefix, 24);
    });
  });
}
