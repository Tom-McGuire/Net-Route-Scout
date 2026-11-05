import 'package:flutter_test/flutter_test.dart';
import 'package:net_route_scout/data/services/arp_service.dart';
import 'package:net_route_scout/data/services/icmp_service.dart';
import 'package:net_route_scout/data/services/traceroute_service.dart';
import 'package:net_route_scout/domain/models/cancellation_token.dart';

void main() {
  group('Traceroute Output Parsers Tests', () {
    test('Windows tracert: parses normal hop with sub-millisecond RTT', () {
      const line = '  1    <1 ms    <1 ms    <1 ms  192.168.1.1';
      final hop = TracerouteService.parseWindowsTracertLine(line);
      expect(hop, isNotNull);
      expect(hop!.depth, 1);
      expect(hop.ip, '192.168.1.1');
      expect(hop.rttMs, 0.5);
      expect(hop.isTimeout, isFalse);
    });

    test('Windows tracert: parses partial loss line with IP correctly (Bug 8 regression)', () {
      const line = '  2     *        5 ms     4 ms  10.0.0.1';
      final hop = TracerouteService.parseWindowsTracertLine(line);
      expect(hop, isNotNull);
      expect(hop!.depth, 2);
      expect(hop.ip, '10.0.0.1');
      expect(hop.rttMs, 4.0);
      expect(hop.isTimeout, isFalse);
    });

    test('Windows tracert: parses complete timeout hop with contextual anon ID (Bug 2 regression)', () {
      const line = '  3     *        *        *     Request timed out.';
      final hop = TracerouteService.parseWindowsTracertLine(line, previousIp: '10.0.0.1');
      expect(hop, isNotNull);
      expect(hop!.depth, 3);
      expect(hop.ip, 'anon:10.0.0.1:3');
      expect(hop.isTimeout, isTrue);
    });

    test('Linux traceroute: parses regular hop', () {
      const line = ' 1  10.101.1.1  0.512 ms  0.421 ms  0.399 ms';
      final hop = TracerouteService.parseLinuxTracerouteLine(line);
      expect(hop, isNotNull);
      expect(hop!.depth, 1);
      expect(hop.ip, '10.101.1.1');
      expect(hop.rttMs, 0.399);
      expect(hop.isTimeout, isFalse);
    });

    test('Linux traceroute: parses timeout hop with contextual anon ID', () {
      const line = ' 2  * * *';
      final hop = TracerouteService.parseLinuxTracerouteLine(line, previousIp: '10.101.1.1');
      expect(hop, isNotNull);
      expect(hop!.depth, 2);
      expect(hop.ip, 'anon:10.101.1.1:2');
      expect(hop.isTimeout, isTrue);
    });

    test('Linux tracepath: parses regular hop and ignores headers', () {
      const header = ' 1?: [LOCALHOST]                      pmtu 1500';
      expect(TracerouteService.parseLinuxTracepathLine(header), isNull);

      const line = ' 1:  10.101.1.1                                            4.616ms';
      final hop = TracerouteService.parseLinuxTracepathLine(line);
      expect(hop, isNotNull);
      expect(hop!.depth, 1);
      expect(hop.ip, '10.101.1.1');
      expect(hop.rttMs, 4.616);
      expect(hop.isTimeout, isFalse);
    });

    test('Linux tracepath: parses no reply as timeout', () {
      const line = ' 2:  no reply';
      final hop = TracerouteService.parseLinuxTracepathLine(line, previousIp: '10.101.1.1');
      expect(hop, isNotNull);
      expect(hop!.depth, 2);
      expect(hop.ip, 'anon:10.101.1.1:2');
      expect(hop.isTimeout, isTrue);
    });

    test('Anonymous hops do NOT merge across unrelated paths (Bug 2 regression)', () {
      // Path A timed out at depth 2 after 10.0.0.1
      final hopA = TracerouteService.parseWindowsTracertLine('  2  *  *  * Request timed out.', previousIp: '10.0.0.1');
      // Path B timed out at depth 2 after 172.16.0.1
      final hopB = TracerouteService.parseWindowsTracertLine('  2  *  *  * Request timed out.', previousIp: '172.16.0.1');

      expect(hopA!.ip, 'anon:10.0.0.1:2');
      expect(hopB!.ip, 'anon:172.16.0.1:2');
      expect(hopA.ip, isNot(equals(hopB.ip)));
    });
  });

  group('Target Specification & Subnet Tests', () {
    test('Expands single IP', () {
      final res = IcmpService.expandTargetSpec('192.168.1.5');
      expect(res, ['192.168.1.5']);
      expect(IcmpService.calculateTargetCount('192.168.1.5'), 1);
    });

    test('Expands CIDR /24 accurately', () {
      final res = IcmpService.expandTargetSpec('192.168.1.0/24');
      expect(res.length, 254);
      expect(res.first, '192.168.1.1');
      expect(res.last, '192.168.1.254');
      expect(IcmpService.calculateTargetCount('192.168.1.0/24'), 254);
    });

    test('Expands hyphenated range accurately', () {
      final res = IcmpService.expandTargetSpec('10.0.0.1-10');
      expect(res.length, 10);
      expect(res.first, '10.0.0.1');
      expect(res.last, '10.0.0.10');
      expect(IcmpService.calculateTargetCount('10.0.0.1-10'), 10);
    });

    test('Caps CIDR /16 expansion at maxHosts and reports uncapped count', () {
      final uncappedCount = IcmpService.calculateTargetCount('10.0.0.0/16');
      expect(uncappedCount, 65534);

      final res = IcmpService.expandTargetSpec('10.0.0.0/16', maxHosts: 1024);
      expect(res.length, 1024);
    });
  });

  group('CancellationToken Tests', () {
    test('Starts active, triggers listeners on cancel, stays cancelled', () {
      final token = CancellationToken();
      expect(token.isCancelled, isFalse);

      var notified = false;
      token.onCancel(() {
        notified = true;
      });

      token.cancel();
      expect(token.isCancelled, isTrue);
      expect(notified, isTrue);

      // Subsequent listener on cancelled token fires immediately
      var secondNotified = false;
      token.onCancel(() {
        secondNotified = true;
      });
      expect(secondNotified, isTrue);
    });
  });

  group('ARP Parsing Tests', () {
    test('Parses Linux ip neigh show', () {
      const output = '10.101.1.1 dev enp1s0 lladdr 24:e5:0f:31:4b:73 REACHABLE\n'
          '10.101.1.100 dev enp1s0 lladdr 00:1a:2b:3c:4d:5e STALE';
      final table = ArpService.parseArpOutput(output);
      expect(table.length, 2);
      expect(table['10.101.1.1']?.macAddress, '24:E5:0F:31:4B:73');
      expect(table['10.101.1.100']?.macAddress, '00:1A:2B:3C:4D:5E');
    });

    test('Parses Windows arp -a', () {
      const output = '  Internet Address      Physical Address      Type\n'
          '  192.168.1.1           00-1b-54-11-22-33     dynamic\n'
          '  192.168.1.255         ff-ff-ff-ff-ff-ff     static';
      final table = ArpService.parseArpOutput(output);
      expect(table.containsKey('192.168.1.1'), isTrue);
      expect(table['192.168.1.1']?.macAddress, '00:1B:54:11:22:33');
      // Broadcast MAC ff:ff:ff:ff:ff:ff should be ignored
      expect(table.containsKey('192.168.1.255'), isFalse);
    });
  });
}
