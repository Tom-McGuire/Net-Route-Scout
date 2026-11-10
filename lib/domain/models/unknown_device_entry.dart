/// Represents an unknown/unnamed device in the Shared Database or detected in active network traffic.
///
/// Devices without a custom name (e.g. "Device 00:1A:2B:3C:4D:5E", "Unknown Device",
/// or raw MAC/IP) belong to this category and are automatically hidden from the filter
/// bar by default unless the user explicitly unhides them or enables Auto-Detected view.
class UnknownDeviceEntry {
  final String key;
  final String? macAddress;
  final String? ip;
  final String displayName;
  final String? vendor;
  final bool isInDatabase;
  final bool isHidden;

  const UnknownDeviceEntry({
    required this.key,
    this.macAddress,
    this.ip,
    required this.displayName,
    this.vendor,
    this.isInDatabase = false,
    this.isHidden = true,
  });

  UnknownDeviceEntry copyWith({
    String? key,
    String? macAddress,
    String? ip,
    String? displayName,
    String? vendor,
    bool? isInDatabase,
    bool? isHidden,
  }) {
    return UnknownDeviceEntry(
      key: key ?? this.key,
      macAddress: macAddress ?? this.macAddress,
      ip: ip ?? this.ip,
      displayName: displayName ?? this.displayName,
      vendor: vendor ?? this.vendor,
      isInDatabase: isInDatabase ?? this.isInDatabase,
      isHidden: isHidden ?? this.isHidden,
    );
  }

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is UnknownDeviceEntry &&
          runtimeType == other.runtimeType &&
          key == other.key;

  @override
  int get hashCode => key.hashCode;
}
