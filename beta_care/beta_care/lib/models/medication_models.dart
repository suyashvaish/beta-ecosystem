import 'status_level.dart';

/// Section 8. The system only ever reports a status it can actually
/// substantiate - "taken" always implies a real confirmation or supported
/// evidence, never an assumption.
enum MedicationStatus { pending, taken, skipped, missed, snoozed, unknown }

MedicationStatus medicationStatusFromString(String value) {
  return MedicationStatus.values.firstWhere(
    (s) => s.name == value,
    orElse: () => MedicationStatus.unknown,
  );
}

extension MedicationStatusX on MedicationStatus {
  String get label {
    switch (this) {
      case MedicationStatus.pending:
        return 'Upcoming';
      case MedicationStatus.taken:
        return 'Taken';
      case MedicationStatus.skipped:
        return 'Skipped';
      case MedicationStatus.missed:
        return 'Missed';
      case MedicationStatus.snoozed:
        return 'Snoozed';
      case MedicationStatus.unknown:
        return 'Unknown';
    }
  }

  StatusLevel get statusLevel {
    switch (this) {
      case MedicationStatus.taken:
        return StatusLevel.normal;
      case MedicationStatus.pending:
      case MedicationStatus.snoozed:
        return StatusLevel.unknown;
      case MedicationStatus.skipped:
      case MedicationStatus.missed:
        return StatusLevel.attention;
      case MedicationStatus.unknown:
        return StatusLevel.unknown;
    }
  }
}

/// One dose of one medication, scheduled for one time of day.
class MedicationDose {
  final String id;
  final String medicationName;
  final DateTime scheduledAt;
  final MedicationStatus status;
  final DateTime? confirmedAt;

  const MedicationDose({
    required this.id,
    required this.medicationName,
    required this.scheduledAt,
    required this.status,
    this.confirmedAt,
  });

  factory MedicationDose.fromJson(Map<String, dynamic> json) => MedicationDose(
        id: json['id'] as String,
        medicationName: json['medicationName'] as String,
        scheduledAt: DateTime.parse(json['scheduledAt'] as String),
        status: medicationStatusFromString(json['status'] as String),
        confirmedAt: json['confirmedAt'] != null ? DateTime.parse(json['confirmedAt'] as String) : null,
      );
}

/// One day's worth of doses, for the medication history list.
class MedicationDay {
  final DateTime date;
  final List<MedicationDose> doses;

  const MedicationDay({required this.date, required this.doses});

  factory MedicationDay.fromJson(Map<String, dynamic> json) => MedicationDay(
        date: DateTime.parse(json['date'] as String),
        doses: (json['doses'] as List<dynamic>)
            .map((d) => MedicationDose.fromJson(d as Map<String, dynamic>))
            .toList(),
      );
}
