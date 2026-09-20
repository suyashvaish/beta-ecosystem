/// What one caregiver is allowed to see for one elderly user.
///
/// This is READ ONLY from Beta Care's point of view. The elderly person
/// grants and revokes these from their own Beta AI app; Beta Care only
/// displays the "Your Access" screen (section 18) and gates its own UI so a
/// caregiver never even sees a category they haven't been granted - the
/// backend enforces the real boundary (section 4: "Do not rely on the
/// Flutter app to hide unauthorized information"), this is UX, not security.
class PermissionSet {
  final bool health;
  final bool medication;
  final bool location;
  final bool activity;
  final bool device;
  final bool emergency;
  final bool conversations;

  const PermissionSet({
    this.health = false,
    this.medication = false,
    this.location = false,
    this.activity = false,
    this.device = false,
    this.emergency = false,
    this.conversations = false, // privacy-first default, per section 4
  });

  factory PermissionSet.fromJson(Map<String, dynamic> json) => PermissionSet(
        health: json['health'] as bool? ?? false,
        medication: json['medication'] as bool? ?? false,
        location: json['location'] as bool? ?? false,
        activity: json['activity'] as bool? ?? false,
        device: json['device'] as bool? ?? false,
        emergency: json['emergency'] as bool? ?? false,
        conversations: json['conversations'] as bool? ?? false,
      );

  static const PermissionSet none = PermissionSet();
}
