import 'package:flutter_test/flutter_test.dart';
import 'package:net_route_scout/domain/models/interface_health_stats.dart';
import 'package:net_route_scout/domain/models/network_edge.dart';

void main() {
  final sampleTime = DateTime.utc(2026, 11, 18, 12, 0, 0);

  group('InterfaceHealthStats', () {
    test('computeCounterDelta handles normal increments and zero delta', () {
      expect(InterfaceHealthStats.computeCounterDelta(100, 145), 45);
      expect(InterfaceHealthStats.computeCounterDelta(100, 100), 0);
      expect(InterfaceHealthStats.computeCounterDelta(0, 256), 256);
    });

    test('computeCounterDelta handles 32-bit Counter32 rollover', () {
      expect(InterfaceHealthStats.computeCounterDelta(0xFFFFFFFE, 5), 7);
      expect(InterfaceHealthStats.computeCounterDelta(0xFFFFFFFF, 0), 1);
      expect(InterfaceHealthStats.computeCounterDelta(0xFFFFFFFF, 10), 11);
    });

    test('withPreviousSample computes inErrorsDelta and outDiscardsDelta', () {
      final previous = InterfaceHealthStats(
        ifIndex: 1,
        interfaceName: 'Gi1/0/1',
        speedMbps: 1000,
        duplex: DuplexMode.fullDuplex,
        inErrors: 0xFFFFFFFE,
        outDiscards: 120,
        sampledAt: sampleTime,
      );

      final current = InterfaceHealthStats(
        ifIndex: 1,
        interfaceName: 'Gi1/0/1',
        speedMbps: 1000,
        duplex: DuplexMode.fullDuplex,
        inErrors: 5,
        outDiscards: 135,
        sampledAt: sampleTime.add(const Duration(seconds: 30)),
      );

      final unchanged = current.withPreviousSample(null);
      expect(unchanged.inErrorsDelta, 0);
      expect(unchanged.outDiscardsDelta, 0);

      final withDelta = current.withPreviousSample(previous);
      expect(withDelta.inErrorsDelta, 7);
      expect(withDelta.outDiscardsDelta, 15);
      expect(withDelta.hasActiveErrors, isTrue);
      expect(withDelta.hasHistoricalErrors, isTrue);
      expect(withDelta.ifIndex, 1);
      expect(withDelta.interfaceName, 'Gi1/0/1');
    });

    test('hasActiveErrors and hasHistoricalErrors distinguish live vs cumulative errors', () {
      final historicalOnly = InterfaceHealthStats(
        ifIndex: 2,
        interfaceName: 'Gi1/0/2',
        speedMbps: 1000,
        inErrors: 50,
        inErrorsDelta: 0,
        outDiscardsDelta: 0,
        sampledAt: sampleTime,
      );

      expect(historicalOnly.hasHistoricalErrors, isTrue);
      expect(historicalOnly.hasActiveErrors, isFalse);

      final clean = InterfaceHealthStats(
        ifIndex: 3,
        interfaceName: 'Gi1/0/3',
        speedMbps: 1000,
        sampledAt: sampleTime,
      );

      expect(clean.hasHistoricalErrors, isFalse);
      expect(clean.hasActiveErrors, isFalse);
    });

    test('isDegradedSpeed detects sub-gigabit active links only', () {
      InterfaceHealthStats statsWithSpeed(int speedMbps) => InterfaceHealthStats(
            ifIndex: 1,
            interfaceName: 'Gi1/0/1',
            speedMbps: speedMbps,
            sampledAt: sampleTime,
          );

      expect(statsWithSpeed(100).isDegradedSpeed, isTrue);
      expect(statsWithSpeed(10).isDegradedSpeed, isTrue);
      expect(statsWithSpeed(1000).isDegradedSpeed, isFalse);
      expect(statsWithSpeed(2500).isDegradedSpeed, isFalse);
      expect(statsWithSpeed(10000).isDegradedSpeed, isFalse);
      expect(statsWithSpeed(0).isDegradedSpeed, isFalse);
    });

    test('isHalfDuplex and DuplexMode.fromCode handle duplex states', () {
      final half = InterfaceHealthStats(
        ifIndex: 1,
        interfaceName: 'Gi1/0/1',
        speedMbps: 100,
        duplex: DuplexMode.halfDuplex,
        sampledAt: sampleTime,
      );
      final full = InterfaceHealthStats(
        ifIndex: 1,
        interfaceName: 'Gi1/0/1',
        speedMbps: 1000,
        duplex: DuplexMode.fullDuplex,
        sampledAt: sampleTime,
      );
      final unknown = InterfaceHealthStats(
        ifIndex: 1,
        interfaceName: 'Gi1/0/1',
        speedMbps: 1000,
        duplex: DuplexMode.unknown,
        sampledAt: sampleTime,
      );

      expect(half.isHalfDuplex, isTrue);
      expect(full.isHalfDuplex, isFalse);
      expect(unknown.isHalfDuplex, isFalse);

      expect(DuplexMode.fromCode(1), DuplexMode.unknown);
      expect(DuplexMode.fromCode(2), DuplexMode.halfDuplex);
      expect(DuplexMode.fromCode(3), DuplexMode.fullDuplex);
      expect(DuplexMode.fromCode(null), DuplexMode.unknown);
      expect(DuplexMode.fromCode(99), DuplexMode.unknown);
    });

    test('formattedSpeed formats 10G, 2.5G, 1G, 100M, and unknown speeds', () {
      String formatFor(int speedMbps) => InterfaceHealthStats(
            ifIndex: 1,
            interfaceName: 'Port',
            speedMbps: speedMbps,
            sampledAt: sampleTime,
          ).formattedSpeed;

      expect(formatFor(10000), '10G');
      expect(formatFor(40000), '40G');
      expect(formatFor(2500), '2.5G');
      expect(formatFor(1000), '1G');
      expect(formatFor(100), '100M');
      expect(formatFor(10), '10M');
      expect(formatFor(0), '—');
    });

    test('toJson and fromJson round-trip preserves interface health stats', () {
      final original = InterfaceHealthStats(
        ifIndex: 24,
        interfaceName: 'Te1/0/1',
        speedMbps: 10000,
        isOperUp: true,
        duplex: DuplexMode.fullDuplex,
        inErrors: 42,
        outErrors: 3,
        inDiscards: 7,
        outDiscards: 19,
        inErrorsDelta: 2,
        outDiscardsDelta: 4,
        sampledAt: sampleTime,
      );

      final json = original.toJson();
      final restored = InterfaceHealthStats.fromJson(json);

      expect(restored.ifIndex, 24);
      expect(restored.interfaceName, 'Te1/0/1');
      expect(restored.speedMbps, 10000);
      expect(restored.isOperUp, isTrue);
      expect(restored.duplex, DuplexMode.fullDuplex);
      expect(restored.inErrors, 42);
      expect(restored.outErrors, 3);
      expect(restored.inDiscards, 7);
      expect(restored.outDiscards, 19);
      expect(restored.inErrorsDelta, 2);
      expect(restored.outDiscardsDelta, 4);
      expect(restored.sampledAt, sampleTime);
    });
  });

  group('NetworkEdge Link Health & Speed Badge', () {
    test('speedBadgeLabel renders expected labels and prioritizes half-duplex warning', () {
      expect(
        NetworkEdge(
          sourceIp: '10.0.0.1',
          targetIp: '10.0.0.2',
          linkSpeedMbps: 10000,
          linkDuplex: DuplexMode.fullDuplex,
        ).speedBadgeLabel,
        '10G',
      );
      expect(
        NetworkEdge(
          sourceIp: '10.0.0.1',
          targetIp: '10.0.0.2',
          linkSpeedMbps: 2500,
          linkDuplex: DuplexMode.fullDuplex,
        ).speedBadgeLabel,
        '2.5G',
      );
      expect(
        NetworkEdge(
          sourceIp: '10.0.0.1',
          targetIp: '10.0.0.2',
          linkSpeedMbps: 1000,
          linkDuplex: DuplexMode.fullDuplex,
        ).speedBadgeLabel,
        '1G',
      );
      expect(
        NetworkEdge(
          sourceIp: '10.0.0.1',
          targetIp: '10.0.0.2',
          linkSpeedMbps: 100,
          linkDuplex: DuplexMode.fullDuplex,
        ).speedBadgeLabel,
        '100M ⚠',
      );
      expect(
        NetworkEdge(
          sourceIp: '10.0.0.1',
          targetIp: '10.0.0.2',
          linkSpeedMbps: 100,
          linkDuplex: DuplexMode.halfDuplex,
        ).speedBadgeLabel,
        'HALF-DUPLEX ⚠',
      );
      expect(
        NetworkEdge(
          sourceIp: '10.0.0.1',
          targetIp: '10.0.0.2',
          linkSpeedMbps: 1000,
          linkDuplex: DuplexMode.halfDuplex,
        ).speedBadgeLabel,
        'HALF-DUPLEX ⚠',
      );
      expect(
        NetworkEdge(
          sourceIp: '10.0.0.1',
          targetIp: '10.0.0.2',
        ).speedBadgeLabel,
        isNull,
      );
      expect(
        NetworkEdge(
          sourceIp: '10.0.0.1',
          targetIp: '10.0.0.2',
          linkSpeedMbps: 0,
        ).speedBadgeLabel,
        isNull,
      );
    });

    test('toJson and fromJson round-trip preserves speed, duplex, and error deltas', () {
      final edge = NetworkEdge(
        sourceIp: '10.0.0.1',
        targetIp: '10.0.0.2',
        sourcePortName: 'Gi1/0/24',
        targetPortName: 'Gi1/0/1',
        linkSpeedMbps: 100,
        linkDuplex: DuplexMode.halfDuplex,
        inErrorsDelta: 5,
        outDiscardsDelta: 2,
      );

      final restored = NetworkEdge.fromJson(edge.toJson());
      expect(restored.sourcePortName, 'Gi1/0/24');
      expect(restored.targetPortName, 'Gi1/0/1');
      expect(restored.linkSpeedMbps, 100);
      expect(restored.linkDuplex, DuplexMode.halfDuplex);
      expect(restored.inErrorsDelta, 5);
      expect(restored.outDiscardsDelta, 2);
      expect(restored.isDegradedSpeed, isTrue);
      expect(restored.isHalfDuplex, isTrue);
      expect(restored.hasActiveErrors, isTrue);
      expect(restored.speedBadgeLabel, 'HALF-DUPLEX ⚠');
    });
  });
}
