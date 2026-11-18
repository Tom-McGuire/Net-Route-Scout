import 'package:flutter_test/flutter_test.dart';
import 'package:net_route_scout/domain/models/switch_poe_status.dart';

void main() {
  group('SwitchPoeStatus', () {
    test('calculates utilizationPercent and remainingWatts accurately', () {
      const status = SwitchPoeStatus(
        totalBudgetWatts: 370,
        consumedWatts: 185,
      );

      expect(status.utilizationPercent, closeTo(50.0, 0.001));
      expect(status.remainingWatts, 185);
      expect(status.isNearCapacity, isFalse);
      expect(status.isCriticalCapacity, isFalse);

      const oversubscribed = SwitchPoeStatus(
        totalBudgetWatts: 100,
        consumedWatts: 125,
      );
      expect(oversubscribed.remainingWatts, 0);
    });

    test('isNearCapacity triggers at >= 80% and isCriticalCapacity triggers at >= 90%', () {
      const belowWarning = SwitchPoeStatus(totalBudgetWatts: 100, consumedWatts: 79);
      expect(belowWarning.utilizationPercent, closeTo(79.0, 0.001));
      expect(belowWarning.isNearCapacity, isFalse);
      expect(belowWarning.isCriticalCapacity, isFalse);

      const atNearThreshold = SwitchPoeStatus(totalBudgetWatts: 100, consumedWatts: 80);
      expect(atNearThreshold.utilizationPercent, closeTo(80.0, 0.001));
      expect(atNearThreshold.isNearCapacity, isTrue);
      expect(atNearThreshold.isCriticalCapacity, isFalse);

      const belowCritical = SwitchPoeStatus(totalBudgetWatts: 100, consumedWatts: 89);
      expect(belowCritical.isNearCapacity, isTrue);
      expect(belowCritical.isCriticalCapacity, isFalse);

      const atCriticalThreshold = SwitchPoeStatus(totalBudgetWatts: 100, consumedWatts: 90);
      expect(atCriticalThreshold.utilizationPercent, closeTo(90.0, 0.001));
      expect(atCriticalThreshold.isNearCapacity, isTrue);
      expect(atCriticalThreshold.isCriticalCapacity, isTrue);

      const fullBudget = SwitchPoeStatus(totalBudgetWatts: 370, consumedWatts: 370);
      expect(fullBudget.utilizationPercent, closeTo(100.0, 0.001));
      expect(fullBudget.remainingWatts, 0);
      expect(fullBudget.isNearCapacity, isTrue);
      expect(fullBudget.isCriticalCapacity, isTrue);
    });

    test('handles zero budget safely without division by zero', () {
      const zeroZero = SwitchPoeStatus(totalBudgetWatts: 0, consumedWatts: 0);
      expect(zeroZero.utilizationPercent, 0.0);
      expect(zeroZero.remainingWatts, 0);
      expect(zeroZero.isNearCapacity, isFalse);
      expect(zeroZero.isCriticalCapacity, isFalse);

      const zeroBudgetWithDraw = SwitchPoeStatus(totalBudgetWatts: 0, consumedWatts: 15);
      expect(zeroBudgetWithDraw.utilizationPercent, 0.0);
      expect(zeroBudgetWithDraw.remainingWatts, 0);
      expect(zeroBudgetWithDraw.isNearCapacity, isFalse);
      expect(zeroBudgetWithDraw.isCriticalCapacity, isFalse);
    });

    test('hasPortFaults detects PoePortState.fault and PoePortState.otherFault', () {
      const noPorts = SwitchPoeStatus(totalBudgetWatts: 370, consumedWatts: 0);
      expect(noPorts.hasPortFaults, isFalse);

      const healthyPorts = SwitchPoeStatus(
        totalBudgetWatts: 370,
        consumedWatts: 45,
        ports: [
          PoePortDetail(
            portIndex: 1,
            interfaceName: 'Gi1/0/1',
            state: PoePortState.deliveringPower,
            powerClass: 'Class 4',
            drawWatts: 15.4,
          ),
          PoePortDetail(
            portIndex: 2,
            interfaceName: 'Gi1/0/2',
            state: PoePortState.searching,
          ),
          PoePortDetail(
            portIndex: 3,
            interfaceName: 'Gi1/0/3',
            state: PoePortState.disabled,
          ),
          PoePortDetail(
            portIndex: 4,
            interfaceName: 'Gi1/0/4',
            state: PoePortState.test,
          ),
        ],
      );
      expect(healthyPorts.hasPortFaults, isFalse);

      const withFault = SwitchPoeStatus(
        totalBudgetWatts: 370,
        consumedWatts: 30,
        ports: [
          PoePortDetail(
            portIndex: 1,
            interfaceName: 'Gi1/0/1',
            state: PoePortState.deliveringPower,
          ),
          PoePortDetail(
            portIndex: 5,
            interfaceName: 'Gi1/0/5',
            state: PoePortState.fault,
          ),
        ],
      );
      expect(withFault.ports[1].isFault, isTrue);
      expect(withFault.hasPortFaults, isTrue);

      const withOtherFault = SwitchPoeStatus(
        totalBudgetWatts: 370,
        consumedWatts: 30,
        ports: [
          PoePortDetail(
            portIndex: 6,
            interfaceName: 'Gi1/0/6',
            state: PoePortState.otherFault,
          ),
        ],
      );
      expect(withOtherFault.ports.single.isFault, isTrue);
      expect(withOtherFault.hasPortFaults, isTrue);
    });

    test('PoePortState.fromCode decodes RFC 3621 port detection status codes', () {
      expect(PoePortState.fromCode(1), PoePortState.disabled);
      expect(PoePortState.fromCode(2), PoePortState.searching);
      expect(PoePortState.fromCode(3), PoePortState.deliveringPower);
      expect(PoePortState.fromCode(4), PoePortState.fault);
      expect(PoePortState.fromCode(5), PoePortState.test);
      expect(PoePortState.fromCode(6), PoePortState.otherFault);
      expect(PoePortState.fromCode(null), PoePortState.disabled);
      expect(PoePortState.fromCode(99), PoePortState.disabled);
    });

    test('toJson and fromJson round-trip preserves budget and port details', () {
      const original = SwitchPoeStatus(
        totalBudgetWatts: 370,
        consumedWatts: 310,
        ports: [
          PoePortDetail(
            portIndex: 1,
            interfaceName: 'Gi1/0/1',
            state: PoePortState.deliveringPower,
            powerClass: 'Class 4',
            drawWatts: 25.5,
          ),
          PoePortDetail(
            portIndex: 2,
            interfaceName: 'Gi1/0/2',
            state: PoePortState.otherFault,
            powerClass: null,
            drawWatts: null,
          ),
        ],
      );

      final json = original.toJson();
      expect(json['total_budget_watts'], 370);
      expect(json['consumed_watts'], 310);
      expect((json['ports'] as List).length, 2);

      final restored = SwitchPoeStatus.fromJson(json);
      expect(restored.totalBudgetWatts, 370);
      expect(restored.consumedWatts, 310);
      expect(restored.remainingWatts, 60);
      expect(restored.isNearCapacity, isTrue);
      expect(restored.isCriticalCapacity, isFalse);
      expect(restored.hasPortFaults, isTrue);
      expect(restored.ports.length, 2);

      expect(restored.ports[0].portIndex, 1);
      expect(restored.ports[0].interfaceName, 'Gi1/0/1');
      expect(restored.ports[0].state, PoePortState.deliveringPower);
      expect(restored.ports[0].powerClass, 'Class 4');
      expect(restored.ports[0].drawWatts, 25.5);
      expect(restored.ports[0].isFault, isFalse);

      expect(restored.ports[1].portIndex, 2);
      expect(restored.ports[1].interfaceName, 'Gi1/0/2');
      expect(restored.ports[1].state, PoePortState.otherFault);
      expect(restored.ports[1].powerClass, isNull);
      expect(restored.ports[1].drawWatts, isNull);
      expect(restored.ports[1].isFault, isTrue);

      final empty = SwitchPoeStatus.fromJson(const {});
      expect(empty.totalBudgetWatts, 0);
      expect(empty.consumedWatts, 0);
      expect(empty.utilizationPercent, 0.0);
      expect(empty.ports, isEmpty);
    });
  });
}
