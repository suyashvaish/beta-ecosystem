import 'dart:math';
import 'package:flutter/material.dart';

/// Which of Beta's states the orb should visually reflect.
enum OrbVisualState { idle, listening, processing, speaking, error }

/// The animated orb - Beta's visual identity across every screen it
/// appears on, from the full-size hero orb down to the small badge in
/// the top bar once a conversation is underway.
///
/// Idle, listening, and speaking all share Beta's signature blue and are
/// distinguished from each other by [audioLevel] plus surrounding
/// context (caption text, icon, animation speed) - not by separate
/// colors. Processing and error each get their own quieter palette so
/// the orb never looks like it's just idling when something else is
/// actually happening.
class VoiceOrb extends StatelessWidget {
  const VoiceOrb({
    super.key,
    required this.audioLevel,
    this.state = OrbVisualState.idle,
    this.size = 260,
  });

  final double audioLevel; // 0.0 (silent) .. 1.0 (loud)
  final OrbVisualState state;
  final double size;

  @override
  Widget build(BuildContext context) {
    late final Color restTop;
    late final Color restBottom;
    late final Color activeTop;
    late final Color activeBottom;

    switch (state) {
      case OrbVisualState.error:
        restTop = const Color(0xFFBDB6AE);
        restBottom = const Color(0xFFEFEAE3);
        activeTop = restTop;
        activeBottom = restBottom;
        break;
      case OrbVisualState.processing:
        restTop = const Color(0xFFD9DCE8);
        restBottom = const Color(0xFFF6F7FB);
        activeTop = restTop;
        activeBottom = restBottom;
        break;
      case OrbVisualState.idle:
      case OrbVisualState.listening:
      case OrbVisualState.speaking:
        restTop = const Color(0xFFB9C4F2); // soft periwinkle-blue
        restBottom = const Color(0xFFF3F5FF); // near-white
        activeTop = const Color(0xFF4E7CFF); // vivid sky/indigo blue
        activeBottom = const Color(0xFFDCE6FF); // lighter blue base
        break;
    }

    final level = (state == OrbVisualState.listening ||
            state == OrbVisualState.speaking)
        ? audioLevel.clamp(0.0, 1.0)
        : 0.0;

    final topColor = Color.lerp(restTop, activeTop, level)!;
    final bottomColor = Color.lerp(restBottom, activeBottom, level)!;

    final glow = Color.lerp(
      const Color(0x334E7CFF),
      const Color(0x995B8CFF),
      level,
    )!;

    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        boxShadow: [
          BoxShadow(
            color: glow,
            blurRadius: size * (0.23 + level * 0.23),
            spreadRadius: size * (0.02 + level * 0.06),
          ),
        ],
        gradient: LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [topColor, bottomColor],
        ),
      ),
      // The internal cloud texture only reads at larger sizes - skip it
      // for the small top-bar badge so it doesn't just render as mush.
      child: size >= 100
          ? ClipOval(
              child: CustomPaint(
                painter: _CloudPainter(audioLevel: level),
              ),
            )
          : null,
    );
  }
}

/// Soft, cloud-like internal texture so the orb doesn't look like a flat
/// gradient circle — subtle drifting blobs.
class _CloudPainter extends CustomPainter {
  _CloudPainter({required this.audioLevel});

  final double audioLevel;

  @override
  void paint(Canvas canvas, Size size) {
    final center = Offset(size.width / 2, size.height / 2);
    final rand = Random(7); // fixed seed for stable layout

    for (int i = 0; i < 5; i++) {
      final dx = (rand.nextDouble() - 0.5) * size.width * 0.8;
      final dy = (rand.nextDouble() - 0.5) * size.height * 0.5 +
          size.height * 0.15;
      final radius = size.width * (0.25 + rand.nextDouble() * 0.2);

      final paint = Paint()
        ..color = Colors.white.withValues(alpha: 0.10 + audioLevel * 0.08)
        ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 40);

      canvas.drawCircle(center + Offset(dx, dy), radius, paint);
    }
  }

  @override
  bool shouldRepaint(covariant _CloudPainter oldDelegate) =>
      oldDelegate.audioLevel != audioLevel;
}
