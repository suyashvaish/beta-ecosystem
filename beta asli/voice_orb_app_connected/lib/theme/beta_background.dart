import 'dart:ui' as ui;

import 'package:flutter/material.dart';

import 'beta_theme.dart';

/// Beta's signature backdrop: near-black navy with three very subtle
/// radial glows (purple top-left, blue top-right, pink bottom-centre).
///
/// Painted once per screen behind the content - static by design so it
/// costs one paint and never animates (the voice waveform provides all
/// the motion). Wraps any screen body.
class BetaBackground extends StatelessWidget {
  const BetaBackground({super.key, required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    return CustomPaint(
      foregroundPainter: _GlowPainter(),
      child: child,
    );
  }
}

class _GlowPainter extends CustomPainter {
  // Low enough to stay behind content; high enough to kill the "flat
  // black screen" feel on OLED devices.
  static const double _alpha = 0.09;

  @override
  void paint(Canvas canvas, Size size) {
    void glow(Offset center, double radius, Color color) {
      final paint = Paint()
        ..shader = ui.Gradient.radial(
          center,
          radius,
          <Color>[
            color.withValues(alpha: _alpha),
            color.withValues(alpha: 0.0),
          ],
        );
      canvas.drawCircle(center, radius, paint);
    }

    glow(
      Offset(size.width * 0.12, size.height * 0.10),
      size.width * 0.75,
      BetaColors.purple,
    );
    glow(
      Offset(size.width * 0.90, size.height * 0.16),
      size.width * 0.60,
      BetaColors.blue,
    );
    glow(
      Offset(size.width * 0.50, size.height * 0.98),
      size.width * 0.80,
      BetaColors.pink,
    );
  }

  @override
  bool shouldRepaint(covariant _GlowPainter oldDelegate) => false;
}
