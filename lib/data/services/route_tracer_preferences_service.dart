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
    this.customSwitchNodeIds = const {},
    this.customSwitchLinks = const {},
    this.customSwitchPorts = const {},
    this.lastSnmpCommunity = 'public',
  });

  final bool showAutoDetected;
  final Set<String> hiddenDeviceMacs;
  final Set<String> explicitlyShownMacs;
  final Set<String> selectedDeviceKeys;
  final Set<String> customSwitchNodeIds;
  final Map<String, String> customSwitchLinks;
  final Map<String, String> customSwitchPorts;
  final String lastSnmpCommunity;

  RouteTracerPreferences copyWith({
    bool? showAutoDetected,
    Set<String>? hiddenDeviceMacs,
    Set<String>? explicitlyShownMacs,
    Set<String>? selectedDeviceKeys,
    Set<String>? customSwitchNodeIds,
    Map<String, String>? customSwitchLinks,
    Map<String, String>? customSwitchPorts,
    String? lastSnmpCommunity,
  }) {
    return RouteTracerPreferences(
      showAutoDetected: showAutoDetected ?? this.showAutoDetected,
      hiddenDeviceMacs: hiddenDeviceMacs ?? this.hiddenDeviceMacs,
      explicitlyShownMacs: explicitlyShownMacs ?? this.explicitlyShownMacs,
      selectedDeviceKeys: selectedDeviceKeys ?? this.selectedDeviceKeys,
      customSwitchNodeIds: customSwitchNodeIds ?? this.customSwitchNodeIds,
      customSwitchLinks: customSwitchLinks ?? this.customSwitchLinks,
      customSwitchPorts: customSwitchPorts ?? this.customSwitchPorts,
      lastSnmpCommunity: lastSnmpCommunity ?? this.lastSnmpCommunity,
    );
  }

  Map<String, dynamic> toJson() => {
        'showAutoDetected': showAutoDetected,
        'hiddenDeviceMacs': hiddenDeviceMacs.toList(),
        'explicitlyShownMacs': explicitlyShownMacs.toList(),
        'selectedDeviceKeys': selectedDeviceKeys.toList(),
        'customSwitchNodeIds': customSwitchNodeIds.toList(),
        'customSwitchLinks': customSwitchLinks,
        'customSwitchPorts': customSwitchPorts,
        'lastSnmpCommunity': lastSnmpCommunity,
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

    final rawSwitches = json['customSwitchNodeIds'];
    final switchSet = rawSwitches is List ? rawSwitches.whereType<String>().toSet() : <String>{};

    final rawLinks = json['customSwitchLinks'];
    final switchLinks = rawLinks is Map
        ? rawLinks.map((k, v) => MapEntry(k.toString(), v.toString()))
        : <String, String>{};

    final rawPorts = json['customSwitchPorts'];
    final switchPorts = rawPorts is Map
        ? rawPorts.map((k, v) => MapEntry(k.toString(), v.toString()))
        : <String, String>{};

    final snmpCommunity = json['lastSnmpCommunity'] is String
        ? json['lastSnmpCommunity'] as String
        : 'public';

    return RouteTracerPreferences(
      showAutoDetected: showAuto,
      hiddenDeviceMacs: hiddenSet,
      explicitlyShownMacs: shownSet,
      selectedDeviceKeys: selectedSet,
      customSwitchNodeIds: switchSet,
      customSwitchLinks: switchLinks,
      customSwitchPorts: switchPorts,
      lastSnmpCommunity: snmpCommunity,
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
