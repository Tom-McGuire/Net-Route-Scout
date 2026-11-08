import 'dart:convert';
import 'dart:io';
import 'package:network_suite_shared/network_suite_shared.dart';
import 'package:path/path.dart' as p;

class RouteTracerPreferences {
  const RouteTracerPreferences({
    this.showAutoDetected = false,
    this.hiddenDeviceMacs = const {},
  });

  final bool showAutoDetected;
  final Set<String> hiddenDeviceMacs;

  RouteTracerPreferences copyWith({
    bool? showAutoDetected,
    Set<String>? hiddenDeviceMacs,
  }) {
    return RouteTracerPreferences(
      showAutoDetected: showAutoDetected ?? this.showAutoDetected,
      hiddenDeviceMacs: hiddenDeviceMacs ?? this.hiddenDeviceMacs,
    );
  }

  Map<String, dynamic> toJson() => {
        'showAutoDetected': showAutoDetected,
        'hiddenDeviceMacs': hiddenDeviceMacs.toList(),
      };

  factory RouteTracerPreferences.fromJson(Map<String, dynamic> json) {
    final showAuto = json['showAutoDetected'] is bool ? json['showAutoDetected'] as bool : false;
    final rawHidden = json['hiddenDeviceMacs'];
    final hiddenList = rawHidden is List ? rawHidden : null;
    final hiddenSet = hiddenList != null
        ? hiddenList
            .whereType<String>()
            .map((m) => SharedDevice.normalizeMac(m))
            .toSet()
        : <String>{};
    return RouteTracerPreferences(
      showAutoDetected: showAuto,
      hiddenDeviceMacs: hiddenSet,
    );
  }
}

class RouteTracerPreferencesService {
  static const String preferencesFileName = 'route_tracer_prefs.json';

  static File getPreferencesFile() {
    final dir = SharedDeviceDatabase.getDefaultDirectoryPath();
    return File(p.join(dir, preferencesFileName));
  }

  static Future<RouteTracerPreferences> loadPreferences() async {
    try {
      final file = getPreferencesFile();
      if (!await file.exists()) {
        return const RouteTracerPreferences();
      }
      final raw = await file.readAsString();
      final json = jsonDecode(raw);
      if (json is Map<String, dynamic>) {
        return RouteTracerPreferences.fromJson(json);
      }
    } catch (_) {}
    return const RouteTracerPreferences();
  }

  static Future<void> savePreferences(RouteTracerPreferences prefs) async {
    try {
      final file = getPreferencesFile();
      if (!file.parent.existsSync()) {
        file.parent.createSync(recursive: true);
      }
      await file.writeAsString(jsonEncode(prefs.toJson()));
    } catch (_) {}
  }
}
