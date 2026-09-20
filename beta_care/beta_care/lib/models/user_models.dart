/// The elderly person being cared for, as Beta Care is allowed to know them.
/// Beta Care never receives more about this person than their public profile
/// fields plus whatever categories the caregiver has been granted (see
/// [PermissionSet]) - never raw account credentials or private data.
class ElderlyUser {
  final String id;
  final String displayName;
  final String? photoUrl;
  final String? phoneNumber;

  const ElderlyUser({
    required this.id,
    required this.displayName,
    this.photoUrl,
    this.phoneNumber,
  });

  factory ElderlyUser.fromJson(Map<String, dynamic> json) => ElderlyUser(
        id: json['id'] as String,
        displayName: json['displayName'] as String,
        photoUrl: json['photoUrl'] as String?,
        phoneNumber: json['phoneNumber'] as String?,
      );

  Map<String, dynamic> toJson() => {
        'id': id,
        'displayName': displayName,
        'photoUrl': photoUrl,
        'phoneNumber': phoneNumber,
      };
}

/// The signed-in caregiver's own profile (GET /users/me).
class CaregiverProfile {
  final String id;
  final String name;
  final String email;
  final String? photoUrl;

  const CaregiverProfile({
    required this.id,
    required this.name,
    required this.email,
    this.photoUrl,
  });

  factory CaregiverProfile.fromJson(Map<String, dynamic> json) => CaregiverProfile(
        id: json['id'] as String,
        name: json['name'] as String,
        email: json['email'] as String,
        photoUrl: json['photoUrl'] as String?,
      );

  Map<String, dynamic> toJson() => {
        'id': id,
        'name': name,
        'email': email,
        'photoUrl': photoUrl,
      };
}
