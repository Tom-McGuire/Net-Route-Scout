import 'dart:convert';
import 'dart:io';
import 'package:network_suite_shared/network_suite_shared.dart';
import 'package:path/path.dart' as p;

class RouteTracerPreferences {
  const RouteTracerPreferences({
    this.showAutoDetected = false,
    this.hiddenDeviceMacs = const {},
    this.explicitlyShownMacs = const {},
    this.selectedDeviceKeys = const {},
  });

  final bool showAutoDetected;
  final Set<String> hiddenDeviceMacs;
  final Set<String> explicitlyShownMacs;
  final Set<String> selectedDeviceKeys;

  RouteTracerPreferences copyWith({
    bool? showAutoDetected,
    Set<String>? hiddenDeviceMacs,
    Set<String>? explicitlyShownMacs,
    Set<String>? selectedDeviceKeys,
  }) {
    return RouteTracerPreferences(
      showAutoDetected: showAutoDetected ?? this.showAutoDetected,
      hiddenDeviceMacs: hiddenDeviceMacs ?? this.hiddenDeviceMacs,
      explicitlyShownMacs: explicitlyShownMacs ?? this.explicitlyShownMacs,
      selectedDeviceKeys: selectedDeviceKeys ?? this.selectedDeviceKeys,
    );
  }

  Map<String, dynamic> toJson() => {
        'showAutoDetected': showAutoDetected,
        'hiddenDeviceMacs': hiddenDeviceMacs.toList(),
        'explicitlyShownMacs': explicitlyShownMacs.toList(),
        'selectedDeviceKeys': selectedDeviceKeys.toList(),
      };

  factory RouteTracerPreferences.fromJson(Map<String, dynamic> json) {
    final showAuto = json['showAutoDetected'] is bool ? json['showAutoDetected'] as bool : false;

    final rawHidden = json['hiddenDeviceMacs'];
    final hiddenList = rawHidden is List ? rawHidden : null;
    final hiddenSet = hiddenList != null
        ? hiddenList
            .whereType<String>()
            .map((m) => SharedDevice.isValidMac(m) ? SharedDevice.normalizeMac(m) : m)
            .toSet()
        : <String>{};

    final rawShown = json['explicitlyShownMacs'];
    final shownList = rawShown is List ? rawShown : null;
    final shownSet = shownList != null
        ? shownList
            .whereType<String>()
            .map((m) => SharedDevice.isValidMac(m) ? SharedDevice.normalizeMac(m) : m)
            .toSet()
        : <String>{};

    final rawSelected = json['selectedDeviceKeys'];
    final selectedList = rawSelected is List ? rawSelected : null;
    final selectedSet = selectedList != null
        ? selectedList
            .whereType<String>()
            .map((m) => SharedDevice.isValidMac(m) ? SharedDevice.normalizeMac(m) : m)
            .toSet()
        : <String>{};

    return RouteTracerPreferences(
      showAutoDetected: showAuto,
      hiddenDeviceMacs: hiddenSet,
      explicitlyShownMacs: shownSet,
      selectedDeviceKeys: selectedSet,
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
