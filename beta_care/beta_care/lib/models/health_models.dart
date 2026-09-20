import 'status_level.dart';

enum HealthMetricType { heartRate, steps, sleep, bloodOxygen }

extension HealthMetricLabel on HealthMetricType {
  String get label {
    switch (this) {
      case HealthMetricType.heartRate:
        return 'Heart Rate';
      case HealthMetricType.steps:
        return 'Activity';
      case HealthMetricType.sleep:
        return 'Sleep';
      case HealthMetricType.bloodOxygen:
        return 'Blood Oxygen';
    }
  }
}

/// The current health picture, built ONLY from fields the wearable actually
/// reports (section 6: "Do not invent measurements"). Every field is
/// nullable; null means "not provided by this device", not zero.
class HealthSnapshot {
  final int? heartRateBpm;
  final int? steps;
  final Duration? sleepDuration;
  final int? bloodOxygenPercent;
  final DateTime? lastSyncedAt;
  final HealthAlertInfo? activeAlert;

  const HealthSnapshot({
    this.heartRateBpm,
    this.steps,
    this.sleepDuration,
    this.bloodOxygenPercent,
    this.lastSyncedAt,
    this.activeAlert,
  });

  bool get hasAnyReading =>
      heartRateBpm != null || steps != null || sleepDuration != null || bloodOxygenPercent != null;

  StatusLevel get statusLevel {
    if (activeAlert != null) return StatusLevel.attention;
    if (!hasAnyReading) return StatusLevel.unknown;
    return StatusLevel.normal;
  }

  factory HealthSnapshot.fromJson(Map<String, dynamic> json) => HealthSnapshot(
        heartRateBpm: json['heartRateBpm'] as int?,
        steps: json['steps'] as int?,
        sleepDuration: json['sleepMinutes'] != null ? Duration(minutes: json['sleepMinutes'] as int) : null,
        bloodOxygenPercent: json['bloodOxygenPercent'] as int?,
        lastSyncedAt: json['lastSyncedAt'] != null ? DateTime.parse(json['lastSyncedAt'] as String) : null,
        activeAlert: json['activeAlert'] != null
            ? HealthAlertInfo.fromJson(json['activeAlert'] as Map<String, dynamic>)
            : null,
      );
}

/// Section 7: an alert card, never phrased as a diagnosis.
class HealthAlertInfo {
  final String description; // e.g. "Reading outside configured range"
  final DateTime detectedAt;
  final String source; // e.g. "Connected wearable"

  const HealthAlertInfo({
    required this.description,
    required this.detectedAt,
    required this.source,
  });

  factory HealthAlertInfo.fromJson(Map<String, dynamic> json) => HealthAlertInfo(
        description: json['description'] as String,
        detectedAt: DateTime.parse(json['detectedAt'] as String),
        source: json['source'] as String,
      );
}

class HealthHistoryPoint {
  final HealthMetricType type;
  final num value;
  final DateTime recordedAt;

  const HealthHistoryPoint({required this.type, required this.value, required this.recordedAt});

  factory HealthHistoryPoint.fromJson(Map<String, dynamic> json) => HealthHistoryPoint(
        type: HealthMetricType.values.firstWhere((t) => t.name == json['type']),
        value: json['value'] as num,
        recordedAt: DateTime.parse(json['recordedAt'] as String),
      );
}
