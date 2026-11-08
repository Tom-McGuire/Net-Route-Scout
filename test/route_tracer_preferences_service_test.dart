import 'package:flutter_test/flutter_test.dart';
import 'package:net_route_scout/data/services/route_tracer_preferences_service.dart';

void main() {
  group('RouteTracerPreferences Tests', () {
    test('Default constructor values', () {
      const prefs = RouteTracerPreferences();
      expect(prefs.showAutoDetected, isFalse);
      expect(prefs.hiddenDeviceMacs, isEmpty);
    });

    test('copyWith updates fields correctly', () {
      const prefs = RouteTracerPreferences();
      final updated = prefs.copyWith(
        showAutoDetected: true,
        hiddenDeviceMacs: {'AA:BB:CC:DD:EE:FF'},
      );

      expect(updated.showAutoDetected, isTrue);
      expect(updated.hiddenDeviceMacs, contains('AA:BB:CC:DD:EE:FF'));
    });

    test('JSON serialization round-trip', () {
      final original = RouteTracerPreferences(
        showAutoDetected: true,
        hiddenDeviceMacs: {'AA:BB:CC:DD:EE:FF', '00:11:22:33:44:55'},
      );

      final json = original.toJson();
      final restored = RouteTracerPreferences.fromJson(json);

      expect(restored.showAutoDetected, isTrue);
      expect(restored.hiddenDeviceMacs.length, 2);
      expect(restored.hiddenDeviceMacs.contains('AA:BB:CC:DD:EE:FF'), isTrue);
      expect(restored.hiddenDeviceMacs.contains('00:11:22:33:44:55'), isTrue);
    });

    test('fromJson handles empty and corrupted maps safely', () {
      final empty = RouteTracerPreferences.fromJson({});
      expect(empty.showAutoDetected, isFalse);
      expect(empty.hiddenDeviceMacs, isEmpty);

      final corrupted = RouteTracerPreferences.fromJson({
        'showAutoDetected': 'not_a_bool',
        'hiddenDeviceMacs': 12345,
      });
      expect(corrupted.showAutoDetected, isFalse);
      expect(corrupted.hiddenDeviceMacs, isEmpty);
    });
  });
}
