import 'package:flutter_test/flutter_test.dart';
import 'package:net_route_scout/domain/models/switch_discovery_info.dart';

void main() {
  group('Switch Discovery Models Tests', () {
    test('SwitchPortEntry serializes to JSON correctly', () {
      final port = SwitchPortEntry(
        portNumber: 1,
        ifIndex: 101,
        portName: 'GigabitEthernet1/0/1',
        connectedMacs: {'00:11:22:33:44:55', 'AA:BB:CC:DD:EE:FF'},
        vlanId: 10,
      );

      final json = port.toJson();
      expect(json['port_number'], 1);
      expect(json['if_index'], 101);
      expect(json['port_name'], 'GigabitEthernet1/0/1');
      expect((json['connected_macs'] as List).length, 2);
      expect(json['vlan_id'], 10);
    });

    test('SwitchNeighborLink serializes to JSON correctly', () {
      final neighbor = SwitchNeighborLink(
        localPort: 'GigabitEthernet1/0/24',
        remoteSysName: 'Core-Switch-A',
        remoteChassisId: '00:1A:2B:3C:4D:5E',
        remotePort: 'TenGigabitEthernet1/1/1',
        remoteMgmtIp: '192.168.1.2',
      );

      final json = neighbor.toJson();
      expect(json['local_port'], 'GigabitEthernet1/0/24');
      expect(json['remote_sys_name'], 'Core-Switch-A');
      expect(json['remote_chassis_id'], '00:1A:2B:3C:4D:5E');
      expect(json['remote_port'], 'TenGigabitEthernet1/1/1');
      expect(json['remote_mgmt_ip'], '192.168.1.2');
    });

    test('LldpDiscoveryResult handles fields and JSON output', () {
      final lldp = LldpDiscoveryResult(
        chassisId: '70:69:79:01:02:03',
        sysName: 'USW-Pro-24-PoE',
        portId: 'Port 8',
        portDescr: 'Workstation Link',
        mgmtAddress: '192.168.1.5',
        vlanId: 1,
        capabilities: ['Bridge', 'Router'],
      );

      final json = lldp.toJson();
      expect(json['chassis_id'], '70:69:79:01:02:03');
      expect(json['sys_name'], 'USW-Pro-24-PoE');
      expect(json['port_id'], 'Port 8');
      expect(json['port_descr'], 'Workstation Link');
      expect(json['mgmt_address'], '192.168.1.5');
      expect(json['vlan_id'], 1);
      expect((json['capabilities'] as List).contains('Bridge'), true);
    });

    test('SwitchDiscoveryResult aggregates ports and neighbors cleanly', () {
      final result = SwitchDiscoveryResult(
        switchIp: '192.168.1.2',
        sysName: 'Cisco-Catalyst-3850',
        sysDescr: 'Cisco IOS Software, C3850 Software (CAT3K_CAA-UNIVERSALK9-M)',
        ports: [
          SwitchPortEntry(portNumber: 1, portName: 'Gi1/0/1', connectedMacs: {'00:50:56:A1:10:01'}),
          SwitchPortEntry(portNumber: 24, portName: 'Gi1/0/24', connectedMacs: {'AC:16:2D:33:44:55'}),
        ],
        neighbors: [
          SwitchNeighborLink(
            localPort: 'Gi1/0/24',
            remoteSysName: 'Distribution-Switch-B',
            remotePort: 'Gi1/0/1',
          ),
        ],
      );

      final json = result.toJson();
      expect(json['switch_ip'], '192.168.1.2');
      expect(json['sys_name'], 'Cisco-Catalyst-3850');
      expect((json['ports'] as List).length, 2);
      expect((json['neighbors'] as List).length, 1);
    });
  });
}
