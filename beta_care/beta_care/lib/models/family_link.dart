import 'user_models.dart';

/// Section 3 of the spec: PENDING -> ACTIVE, or REJECTED / REVOKED.
/// The elderly person is always the one who moves PENDING to ACTIVE or
/// REJECTED, and who can move ACTIVE to REVOKED, from their own Beta AI app.
enum RelationshipStatus { pending, active, rejected, revoked }

RelationshipStatus relationshipStatusFromString(String value) {
  return RelationshipStatus.values.firstWhere(
    (s) => s.name == value,
    orElse: () => RelationshipStatus.pending,
  );
}

extension RelationshipStatusLabel on RelationshipStatus {
  String get label {
    switch (this) {
      case RelationshipStatus.pending:
        return 'Pending approval';
      case RelationshipStatus.active:
        return 'Active';
      case RelationshipStatus.rejected:
        return 'Declined';
      case RelationshipStatus.revoked:
        return 'Access revoked';
    }
  }
}

/// One caregiver's link to one elderly person, from this caregiver's point
/// of view. A caregiver could in principle have more than one of these;
/// Beta Care's monitoring screens default to the first ACTIVE one and the
/// Family screen lists all of them.
class FamilyLink {
  final String id;
  final ElderlyUser elderlyUser;
  final RelationshipStatus status;
  final String relationshipLabel; // "Son", "Daughter", "Caregiver", ...
  final DateTime createdAt;

  const FamilyLink({
    required this.id,
    required this.elderlyUser,
    required this.status,
    required this.relationshipLabel,
    required this.createdAt,
  });

  factory FamilyLink.fromJson(Map<String, dynamic> json) => FamilyLink(
        id: json['id'] as String,
        elderlyUser: ElderlyUser.fromJson(json['elderlyUser'] as Map<String, dynamic>),
        status: relationshipStatusFromString(json['status'] as String),
        relationshipLabel: json['relationshipLabel'] as String? ?? 'Caregiver',
        createdAt: DateTime.parse(json['createdAt'] as String),
      );
}

/// Another caregiver who also has access to the same elderly person
/// (section 15 "Other Caregivers": Mom, Brother, ...). Beta Care only shows
/// this list for elderly users where the signed-in caregiver already has an
/// ACTIVE link; it never reveals who's watching an elderly user the
/// caregiver isn't linked to.
class CoCaregiver {
  final String id;
  final String name;
  final String relationshipLabel;
  final RelationshipStatus status;

  const CoCaregiver({
    required this.id,
    required this.name,
    required this.relationshipLabel,
    required this.status,
  });

  factory CoCaregiver.fromJson(Map<String, dynamic> json) => CoCaregiver(
        id: json['id'] as String,
        name: json['name'] as String,
        relationshipLabel: json['relationshipLabel'] as String? ?? 'Caregiver',
        status: relationshipStatusFromString(json['status'] as String),
      );
}
