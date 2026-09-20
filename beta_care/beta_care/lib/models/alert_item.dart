enum AlertType { health, medication, emergency, device, location, general }

AlertType alertTypeFromString(String value) {
  return AlertType.values.firstWhere((t) => t.name == value, orElse: () => AlertType.general);
}

enum AlertStatus { unacknowledged, acknowledged }

/// One notification-worthy event. Emergency alerts are just a distinctly
/// flagged AlertType, not a separate model - the UI is what makes them
/// impossible to miss (section 12).
class AlertItem {
  final String id;
  final AlertType type;
  final AlertStatus status;
  final String title;
  final String message;
  final DateTime occurredAt;
  final bool locationAvailable;

  const AlertItem({
    required this.id,
    required this.type,
    required this.status,
    required this.title,
    required this.message,
    required this.occurredAt,
    this.locationAvailable = false,
  });

  bool get isEmergency => type == AlertType.emergency;

  factory AlertItem.fromJson(Map<String, dynamic> json) => AlertItem(
        id: json['id'] as String,
        type: alertTypeFromString(json['type'] as String),
        status: (json['status'] as String) == 'acknowledged'
            ? AlertStatus.acknowledged
            : AlertStatus.unacknowledged,
        title: json['title'] as String,
        message: json['message'] as String,
        occurredAt: DateTime.parse(json['occurredAt'] as String),
        locationAvailable: json['locationAvailable'] as bool? ?? false,
      );

  AlertItem copyWith({AlertStatus? status}) => AlertItem(
        id: id,
        type: type,
        status: status ?? this.status,
        title: title,
        message: message,
        occurredAt: occurredAt,
        locationAvailable: locationAvailable,
      );
}
