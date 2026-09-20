/// "Just now" / "5 minutes ago" / "3 hours ago" / a short date - kept as a
/// single shared function so every screen's "last updated" text reads
/// consistently, and so it's computed at render time rather than baked into
/// stored data (section 24: "Never make old data look current").
String formatRelativeTime(DateTime? time, {DateTime? now}) {
  if (time == null) return 'Not yet synchronized';
  final reference = now ?? DateTime.now();
  final diff = reference.difference(time);

  if (diff.isNegative || diff.inSeconds < 45) return 'Just now';
  if (diff.inMinutes < 60) {
    final m = diff.inMinutes;
    return '$m minute${m == 1 ? '' : 's'} ago';
  }
  if (diff.inHours < 24) {
    final h = diff.inHours;
    return '$h hour${h == 1 ? '' : 's'} ago';
  }
  final d = diff.inDays;
  if (d < 7) return '$d day${d == 1 ? '' : 's'} ago';
  return '${time.day}/${time.month}/${time.year}';
}

String formatClockTime(DateTime time) {
  final hour24 = time.hour;
  final period = hour24 >= 12 ? 'PM' : 'AM';
  final hour12 = hour24 % 12 == 0 ? 12 : hour24 % 12;
  final minute = time.minute.toString().padLeft(2, '0');
  return '$hour12:$minute $period';
}

String formatDuration(Duration d) {
  final hours = d.inHours;
  final minutes = d.inMinutes.remainder(60);
  if (hours == 0) return '${minutes}m';
  if (minutes == 0) return '${hours}h';
  return '${hours}h ${minutes}m';
}
