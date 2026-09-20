/// Section 9 / 13. Emergency alerts are intentionally not configurable -
/// every other category can be muted, emergencies never are.
class NotificationPreferences {
  final bool medicationAlerts;
  final bool healthAlerts;
  final bool deviceAlerts;
  final bool locationAlerts;

  const NotificationPreferences({
    this.medicationAlerts = true,
    this.healthAlerts = true,
    this.deviceAlerts = true,
    this.locationAlerts = false,
  });

  factory NotificationPreferences.fromJson(Map<String, dynamic> json) => NotificationPreferences(
        medicationAlerts: json['medicationAlerts'] as bool? ?? true,
        healthAlerts: json['healthAlerts'] as bool? ?? true,
        deviceAlerts: json['deviceAlerts'] as bool? ?? true,
        locationAlerts: json['locationAlerts'] as bool? ?? false,
      );

  Map<String, dynamic> toJson() => {
        'medicationAlerts': medicationAlerts,
        'healthAlerts': healthAlerts,
        'deviceAlerts': deviceAlerts,
        'locationAlerts': locationAlerts,
      };

  NotificationPreferences copyWith({
    bool? medicationAlerts,
    bool? healthAlerts,
    bool? deviceAlerts,
    bool? locationAlerts,
  }) =>
      NotificationPreferences(
        medicationAlerts: medicationAlerts ?? this.medicationAlerts,
        healthAlerts: healthAlerts ?? this.healthAlerts,
        deviceAlerts: deviceAlerts ?? this.deviceAlerts,
        locationAlerts: locationAlerts ?? this.locationAlerts,
      );
}
