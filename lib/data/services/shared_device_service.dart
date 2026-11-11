import 'dart:async';
import 'package:material_ui/material_ui.dart';
import 'package:network_suite_shared/network_suite_shared.dart';

class SharedDeviceResolvedInfo {
  final SharedDevice device;
  final String friendlyName;
  final String categoryKey;
  final String categoryLabel;
  final IconData categoryIcon;
  final Color? categoryColor;

  const SharedDeviceResolvedInfo({
    required this.device,
    required this.friendlyName,
    required this.categoryKey,
    required this.categoryLabel,
    required this.categoryIcon,
    this.categoryColor,
  });
}

class SharedDeviceService {
  StreamSubscription<void>? _dbSubscription;
  final StreamController<void> _changeNotifier = StreamController<void>.broadcast();

  Stream<void> get onDatabaseChanged => _changeNotifier.stream;

  Future<void> init() async {
    try {
      if (!SharedDeviceDatabase.instance.isInitialized) {
        await SharedDeviceDatabase.instance.init();
      }
      _dbSubscription = SharedDeviceDatabase.instance.onDatabaseChanged.listen((_) {
        _changeNotifier.add(null);
      });
    } catch (e) {
      debugPrint('SharedDeviceDatabase init warning: $e');
    }
  }

  void dispose() {
    _dbSubscription?.cancel();
    _changeNotifier.close();
  }

  /// Looks up a device in `shared_devices.db` by MAC address.
  SharedDevice? getDeviceByMac(String rawMac) {
    if (!SharedDeviceDatabase.instance.isInitialized) return null;
    final normalized = SharedDevice.normalizeMac(rawMac);
    try {
      return SharedDeviceDatabase.instance.getDeviceByMac(normalized);
    } catch (_) {
      return null;
    }
  }

  /// Resolves unified category, friendly name, and icon/color for a MAC address.
  SharedDeviceResolvedInfo? resolveDeviceInfo(String rawMac) {
    final dev = getDeviceByMac(rawMac);
    if (dev == null) return null;

    final customCats = SharedDeviceDatabase.instance.getCustomCategories();
    final unified = dev.getUnifiedCategory(customCats);

    return SharedDeviceResolvedInfo(
      device: dev,
      friendlyName: dev.name,
      categoryKey: dev.deviceType ?? unified.key,
      categoryLabel: unified.label,
      categoryIcon: unified.icon,
      categoryColor: unified.color,
    );
  }

  /// Updates or inserts a device friendly name in `shared_devices.db`.
  void updateDeviceName(String rawMac, String newName) {
    if (!SharedDeviceDatabase.instance.isInitialized) return;
    final normalized = SharedDevice.normalizeMac(rawMac);
    SharedDeviceDatabase.instance.updateDeviceName(normalized, newName.trim());
    _changeNotifier.add(null);
  }

  /// Updates full metadata (name, device type, vendor, notes).
  void updateDeviceDetails(
    String rawMac, {
    String? name,
    String? deviceType,
    String? vendor,
    String? notes,
  }) {
    if (!SharedDeviceDatabase.instance.isInitialized) return;
    final normalized = SharedDevice.normalizeMac(rawMac);
    SharedDeviceDatabase.instance.updateDeviceDetails(
      normalized,
      name: name?.trim(),
      deviceType: deviceType,
      vendor: vendor?.trim(),
      notes: notes?.trim(),
    );
    _changeNotifier.add(null);
  }

  /// Registers a newly discovered device in `shared_devices.db`.
  void registerDevice({
    required String rawMac,
    required String name,
    String? vendor,
    String? deviceType,
    String? notes,
    String sourceApp = 'net-route-scout',
  }) {
    if (!SharedDeviceDatabase.instance.isInitialized) return;
    final normalized = SharedDevice.normalizeMac(rawMac);
    final now = DateTime.now();
    final device = SharedDevice(
      macAddress: normalized,
      name: name.trim().isNotEmpty ? name.trim() : 'Device $normalized',
      vendor: vendor,
      deviceType: deviceType ?? 'other',
      notes: notes,
      sourceApp: sourceApp,
      createdAt: now,
      updatedAt: now,
    );
    SharedDeviceDatabase.instance.upsertDevice(device);
    _changeNotifier.add(null);
  }

  /// Returns all available unified categories for selection dropdowns.
  List<UnifiedDeviceCategory> getCategories() {
    if (!SharedDeviceDatabase.instance.isInitialized) return const [];
    return SharedDeviceDatabase.instance.getUnifiedCategories();
  }
}
