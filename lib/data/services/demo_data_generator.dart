import '../../domain/models/trace_hop.dart';
import '../../domain/models/trace_result.dart';

class DemoDataGenerator {
  static const String localHostIp = '192.168.1.105';
  static const String gatewayIp = '192.168.1.1';

  static List<TraceResult> generateDemoTraces() {
    final now = DateTime.now();

    return [
      // Target 1: Accounting Server (via 192.168.1.1 -> 10.0.1.1 -> 10.0.1.45)
      TraceResult(
        targetIp: '10.0.1.45',
        isReachable: true,
        finalRttMs: 3.2,
        completedAt: now,
        hops: const [
          TraceHop(depth: 1, ip: '192.168.1.1', rttMs: 0.8),
          TraceHop(depth: 2, ip: '10.0.1.1', rttMs: 1.9),
          TraceHop(depth: 3, ip: '10.0.1.45', rttMs: 3.2),
        ],
      ),
      // Target 2: HR Executive PC (via 192.168.1.1 -> 10.0.1.1 -> 10.0.1.80)
      TraceResult(
        targetIp: '10.0.1.80',
        isReachable: true,
        finalRttMs: 4.1,
        completedAt: now,
        hops: const [
          TraceHop(depth: 1, ip: '192.168.1.1', rttMs: 0.9),
          TraceHop(depth: 2, ip: '10.0.1.1', rttMs: 2.1),
          TraceHop(depth: 3, ip: '10.0.1.80', rttMs: 4.1),
        ],
      ),
      // Target 3: Office MFP Printer (via 192.168.1.1 -> 10.0.1.1 -> 10.0.1.112)
      TraceResult(
        targetIp: '10.0.1.112',
        isReachable: true,
        finalRttMs: 5.4,
        completedAt: now,
        hops: const [
          TraceHop(depth: 1, ip: '192.168.1.1', rttMs: 0.8),
          TraceHop(depth: 2, ip: '10.0.1.1', rttMs: 2.0),
          TraceHop(depth: 3, ip: '10.0.1.112', rttMs: 5.4),
        ],
      ),
      // Target 4: DevOps CI/CD Runner (via 192.168.1.1 -> 10.0.2.1 -> 10.0.2.20)
      TraceResult(
        targetIp: '10.0.2.20',
        isReachable: true,
        finalRttMs: 2.8,
        completedAt: now,
        hops: const [
          TraceHop(depth: 1, ip: '192.168.1.1', rttMs: 0.8),
          TraceHop(depth: 2, ip: '10.0.2.1', rttMs: 1.5),
          TraceHop(depth: 3, ip: '10.0.2.20', rttMs: 2.8),
        ],
      ),
      // Target 5: TrueNAS Storage Cluster (via 192.168.1.1 -> 10.0.2.1 -> 10.0.2.55)
      TraceResult(
        targetIp: '10.0.2.55',
        isReachable: true,
        finalRttMs: 2.1,
        completedAt: now,
        hops: const [
          TraceHop(depth: 1, ip: '192.168.1.1', rttMs: 0.7),
          TraceHop(depth: 2, ip: '10.0.2.1', rttMs: 1.4),
          TraceHop(depth: 3, ip: '10.0.2.55', rttMs: 2.1),
        ],
      ),
      // Target 6: Tech Lead MacBook Pro (via 192.168.1.1 -> 10.0.2.1 -> 10.0.2.101)
      TraceResult(
        targetIp: '10.0.2.101',
        isReachable: true,
        finalRttMs: 6.8,
        completedAt: now,
        hops: const [
          TraceHop(depth: 1, ip: '192.168.1.1', rttMs: 0.8),
          TraceHop(depth: 2, ip: '10.0.2.1', rttMs: 1.6),
          TraceHop(depth: 3, ip: '10.0.2.101', rttMs: 6.8),
        ],
      ),
      // Target 7: Smart Conference TV (via 192.168.1.1 -> 10.0.2.1 -> 10.0.2.215)
      TraceResult(
        targetIp: '10.0.2.215',
        isReachable: true,
        finalRttMs: 7.2,
        completedAt: now,
        hops: const [
          TraceHop(depth: 1, ip: '192.168.1.1', rttMs: 0.9),
          TraceHop(depth: 2, ip: '10.0.2.1', rttMs: 1.5),
          TraceHop(depth: 3, ip: '10.0.2.215', rttMs: 7.2),
        ],
      ),
      // Target 8: Public Web Gateway (via 192.168.1.1 -> Anon-Hop-Depth-2 -> 10.0.3.50)
      TraceResult(
        targetIp: '10.0.3.50',
        isReachable: true,
        finalRttMs: 14.5,
        completedAt: now,
        hops: const [
          TraceHop(depth: 1, ip: '192.168.1.1', rttMs: 0.8),
          TraceHop(depth: 2, ip: 'Anon-Hop-Depth-2', isTimeout: true),
          TraceHop(depth: 3, ip: '10.0.3.50', rttMs: 14.5),
        ],
      ),
      // Target 9: Corporate VPN Concentrator (via 192.168.1.1 -> Anon-Hop-Depth-2 -> 10.0.3.88)
      TraceResult(
        targetIp: '10.0.3.88',
        isReachable: true,
        finalRttMs: 16.2,
        completedAt: now,
        hops: const [
          TraceHop(depth: 1, ip: '192.168.1.1', rttMs: 0.9),
          TraceHop(depth: 2, ip: 'Anon-Hop-Depth-2', isTimeout: true),
          TraceHop(depth: 3, ip: '10.0.3.88', rttMs: 16.2),
        ],
      ),
    ];
  }

  /// Metadata matching devices to MACs and friendly names for the demo topology.
  static final Map<String, Map<String, String>> demoDeviceCatalog = {
    '192.168.1.1': {
      'mac': '24:E5:0F:31:4B:73',
      'name': 'Main Gateway Router',
      'vendor': 'Cisco Systems',
      'type': 'router',
      'notes': 'Cisco ISR 4431 Dual-WAN Gateway',
    },
    '10.0.1.1': {
      'mac': '70:69:79:A1:B2:C3',
      'name': 'Corp Firewall (FortiGate)',
      'vendor': 'Fortinet, Inc.',
      'type': 'firewall',
      'notes': 'FortiGate 100F UTM Appliance',
    },
    '10.0.2.1': {
      'mac': 'AC:16:2D:33:44:55',
      'name': 'Engineering Distribution Switch',
      'vendor': 'Hewlett Packard Enterprise / Aruba',
      'type': 'switch',
      'notes': 'Aruba 3810M 48G PoE+ Core',
    },
    '10.0.1.45': {
      'mac': '00:50:56:A1:10:01',
      'name': 'Accounting Server (SQL)',
      'vendor': 'VMware, Inc.',
      'type': 'server',
      'notes': 'Production MS SQL 2022 Cluster',
    },
    '10.0.1.80': {
      'mac': 'B4:6B:FC:DB:6E:A6',
      'name': 'HR Executive PC',
      'vendor': 'Lenovo Group Ltd.',
      'type': 'desktop',
      'notes': 'ThinkCentre M90q Tiny Gen 4',
    },
    '10.0.1.112': {
      'mac': '00:1E:8F:22:33:44',
      'name': 'Office Color LaserJet',
      'vendor': 'HP Inc.',
      'type': 'printer',
      'notes': 'HP Color LaserJet Enterprise M555',
    },
    '10.0.2.20': {
      'mac': '52:54:00:12:34:56',
      'name': 'DevOps CI/CD Runner',
      'vendor': 'QEMU / KVM Virtual Machine',
      'type': 'server',
      'notes': 'Ubuntu 24.04 LTS Docker Host',
    },
    '10.0.2.55': {
      'mac': '00:25:90:77:88:99',
      'name': 'TrueNAS Storage Pool',
      'vendor': 'Super Micro Computer, Inc.',
      'type': 'nas',
      'notes': 'ZFS RAID-Z2 8x16TB Enterprise Storage',
    },
    '10.0.2.101': {
      'mac': 'F4:6D:3F:AB:17:6A',
      'name': 'Lead Dev MacBook Pro',
      'vendor': 'Apple, Inc.',
      'type': 'laptop',
      'notes': '16" MacBook Pro M3 Max (Wi-Fi 6E)',
    },
    '10.0.2.215': {
      'mac': 'E4:58:B8:33:22:11',
      'name': 'Boardroom Smart TV',
      'vendor': 'LG Electronics',
      'type': 'smart_tv',
      'notes': 'LG OLED 77" 4K Commercial Display',
    },
    '10.0.3.50': {
      'mac': '00:15:5D:88:99:AA',
      'name': 'DMZ Web Reverse Proxy',
      'vendor': 'Microsoft Corporation',
      'type': 'server',
      'notes': 'NGINX reverse proxy with TLS offloading',
    },
    '10.0.3.88': {
      'mac': '00:0C:29:44:55:66',
      'name': 'AnyConnect VPN Gateway',
      'vendor': 'Cisco Systems',
      'type': 'router',
      'notes': 'Cisco ASA 5525-X Remote Access Headend',
    },
  };
}
