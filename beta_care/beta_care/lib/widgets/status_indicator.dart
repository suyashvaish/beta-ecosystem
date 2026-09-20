import 'package:flutter/material.dart';

import '../core/theme.dart';
import '../models/status_level.dart';

Color statusColor(StatusLevel level) {
  switch (level) {
    case StatusLevel.normal:
      return AppColors.sage;
    case StatusLevel.attention:
      return AppColors.amber;
    case StatusLevel.emergency:
      return AppColors.coral;
    case StatusLevel.unknown:
      return AppColors.slate;
  }
}

IconData statusIcon(StatusLevel level) {
  switch (level) {
    case StatusLevel.normal:
      return Icons.check_circle_rounded;
    case StatusLevel.attention:
      return Icons.warning_rounded;
    case StatusLevel.emergency:
      return Icons.emergency_rounded;
    case StatusLevel.unknown:
      return Icons.help_rounded;
  }
}

/// The ✓ / ⚠ / 🚨 / ○ shorthand from the spec, rendered as a proper pill.
/// Use [compact] for list rows where only the icon fits.
class StatusIndicator extends StatelessWidget {
  final StatusLevel level;
  final String? label;
  final bool compact;

  const StatusIndicator({super.key, required this.level, this.label, this.compact = false});

  @override
  Widget build(BuildContext context) {
    final color = statusColor(level);
    if (compact) {
      return Icon(statusIcon(level), color: color, size: 22);
    }
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(color: color.withValues(alpha: 0.12), borderRadius: BorderRadius.circular(20)),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(statusIcon(level), color: color, size: 16),
          const SizedBox(width: 6),
          Text(
            label ?? level.label,
            style: TextStyle(color: color, fontWeight: FontWeight.w700, fontSize: 13),
          ),
        ],
      ),
    );
  }
}

/// The dashboard's one deliberate signature flourish (see the design notes
/// in README.md): a colored ring around the elderly person's initial that
/// makes their overall status readable from across the room, before a
/// single word of text is read.
class StatusRingAvatar extends StatelessWidget {
  final String initials;
  final String? photoUrl;
  final StatusLevel level;
  final double size;

  const StatusRingAvatar({
    super.key,
    required this.initials,
    this.photoUrl,
    required this.level,
    this.size = 76,
  });

  @override
  Widget build(BuildContext context) {
    final color = statusColor(level);
    return Container(
      width: size,
      height: size,
      padding: const EdgeInsets.all(3),
      decoration: BoxDecoration(shape: BoxShape.circle, border: Border.all(color: color, width: 3)),
      child: CircleAvatar(
        backgroundColor: color.withValues(alpha: 0.15),
        backgroundImage: photoUrl != null ? NetworkImage(photoUrl!) : null,
        child: photoUrl == null
            ? Text(
                initials,
                style: TextStyle(fontSize: size * 0.32, fontWeight: FontWeight.w700, color: color),
              )
            : null,
      ),
    );
  }
}
