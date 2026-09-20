/// The four states Beta Care ever shows for "how is this doing right now".
///
/// Kept deliberately small (section 5 of the spec: "Do not create a
/// complicated medical dashboard"). Every screen maps its own domain data
/// down to one of these four before rendering a [StatusIndicator].
enum StatusLevel { normal, attention, emergency, unknown }

extension StatusLevelLabel on StatusLevel {
  String get label {
    switch (this) {
      case StatusLevel.normal:
        return 'Normal';
      case StatusLevel.attention:
        return 'Needs attention';
      case StatusLevel.emergency:
        return 'Emergency';
      case StatusLevel.unknown:
        return 'Unknown';
    }
  }

  /// Worst-first ordering, used when combining several signals into one
  /// overall dashboard status (e.g. one unconfirmed dose plus a healthy
  /// heart rate should still surface as "attention", not "normal").
  int get severity {
    switch (this) {
      case StatusLevel.unknown:
        return 0;
      case StatusLevel.normal:
        return 1;
      case StatusLevel.attention:
        return 2;
      case StatusLevel.emergency:
        return 3;
    }
  }
}

/// Combines several statuses into the single worst one, so a screen that
/// tracks multiple sub-signals can report one headline level.
StatusLevel combineStatusLevels(Iterable<StatusLevel> levels) {
  var worst = StatusLevel.unknown;
  for (final level in levels) {
    if (level.severity > worst.severity) worst = level;
  }
  return worst;
}
