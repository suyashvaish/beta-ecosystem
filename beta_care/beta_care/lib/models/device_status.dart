enum DeviceConnectionState { connected, disconnected, unknown }

DeviceConnectionState deviceConnectionStateFromString(String value) {
  return DeviceConnectionState.values.firstWhere(
    (s) => s.name == value,
    orElse: () => DeviceConnectionState.unknown,
  );
}

/// Section 14. Beta Care only shows what the backend says is actually
/// supported for this device - it never assumes a caregiver can remotely
/// control a wearable.
class DeviceStatus {
  final String id;
  final String name;
  final DeviceConnectionState connectionState;
  final int? batteryPercent;
  final DateTime? lastSyncedAt;
  final List<String> supportedActions;

  const DeviceStatus({
    required this.id,
    required this.name,
    required this.connectionState,
    this.batteryPercent,
    this.lastSyncedAt,
    this.supportedActions = const [],
  });

  factory DeviceStatus.fromJson(Map<String, dynamic> json) => DeviceStatus(
        id: json['id'] as String,
        name: json['name'] as String,
        connectionState: deviceConnectionStateFromString(json['connectionState'] as String),
        batteryPercent: json['batteryPercent'] as int?,
        lastSyncedAt: json['lastSyncedAt'] != null ? DateTime.parse(json['lastSyncedAt'] as String) : null,
        supportedActions: (json['supportedActions'] as List<dynamic>?)?.cast<String>() ?? const [],
      );
}
