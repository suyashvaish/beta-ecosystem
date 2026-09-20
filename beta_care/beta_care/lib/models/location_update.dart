/// Section 11. Whatever the real reason is that a caregiver can't see a
/// location right now, Beta Care shows it plainly instead of a blank map.
enum LocationSharingState { on, off, permissionDenied, deviceOffline, unknown }

LocationSharingState locationSharingStateFromString(String value) {
  return LocationSharingState.values.firstWhere(
    (s) => s.name == value,
    orElse: () => LocationSharingState.unknown,
  );
}

extension LocationSharingStateX on LocationSharingState {
  String get label {
    switch (this) {
      case LocationSharingState.on:
        return 'ON';
      case LocationSharingState.off:
        return 'OFF';
      case LocationSharingState.permissionDenied:
        return 'Permission denied';
      case LocationSharingState.deviceOffline:
        return 'Device offline';
      case LocationSharingState.unknown:
        return 'Unknown';
    }
  }
}

class LocationUpdate {
  final LocationSharingState sharingState;
  final double? latitude;
  final double? longitude;
  final String? address;
  final DateTime? updatedAt;

  const LocationUpdate({
    required this.sharingState,
    this.latitude,
    this.longitude,
    this.address,
    this.updatedAt,
  });

  bool get hasCoordinates => latitude != null && longitude != null;

  factory LocationUpdate.fromJson(Map<String, dynamic> json) => LocationUpdate(
        sharingState: locationSharingStateFromString(json['sharingState'] as String),
        latitude: (json['latitude'] as num?)?.toDouble(),
        longitude: (json['longitude'] as num?)?.toDouble(),
        address: json['address'] as String?,
        updatedAt: json['updatedAt'] != null ? DateTime.parse(json['updatedAt'] as String) : null,
      );
}
