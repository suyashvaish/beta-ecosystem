import "package:flutter/foundation.dart";
import 'dart:math';

import 'package:flutter/material.dart';

import '../theme/beta_theme.dart';

/// Layered translucent waveform that REPLACES the old voice orb.
///
/// Design (reference screenshot 2):
///   - 3 stacked smooth wave shapes in purple, pink and blue
///   - translucent fills, soft glow
///   - animated continuously; amplitude scales with [levelListenable]
///     (the REAL microphone dB reading from VoiceController - not a
///     fake pulse). When silent the waves settle to a low breathing
///     state so the screen never looks frozen.
///
/// Implementation notes:
///   - Each wave layer is drawn by one CustomPainter: a smooth sine with
///     a second harmonic, distinct speed/phase/offset per layer so the
///     three waves drift past each other fluidly.
///   - One repeating AnimationController drives motion; the parent
///     passes the level via a ValueListenable so high-frequency level
///     updates repaint the waveform without rebuilding the screen.
class AudioWaveform extends StatefulWidget {
  const AudioWaveform({
    super.key,
    required this.levelListenable,
    this.height = 240,
  });

  /// Real-time 0..1 audio level from VoiceController.onLevelChanged.
  final ValueListenable<double> levelListenable;

  final double height;

  @override
  State<AudioWaveform> createState() => _AudioWaveformState();
}

class _AudioWaveformState extends State<AudioWaveform>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 3800),
    )..repeat();
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: Listenable.merge([_controller, widget.levelListenable]),
      builder: (context, _) {
        return CustomPaint(
          painter: _WaveformPainter(
            t: _controller.value,
            level: widget.levelListenable.value,
          ),
          size: Size(double.infinity, widget.height),
        );
      },
    );
  }
}

class _WaveformPainter extends CustomPainter {
  _WaveformPainter({required this.t, required this.level});

  /// Normalized animation phase 0..1.
  final double t;

  /// Real mic level 0..1 (0 = silent/idle).
  final double level;

  static const List<Color> _layerColors = [
    BetaColors.purple,
    BetaColors.pink,
    BetaColors.blue,
  ];

  @override
  void paint(Canvas canvas, Size size) {
    final double w = size.width;
    final double h = size.height;

    // Target amplitude: breathing baseline when silent, driven by the
    // real level when the mic is live.
    final double target = 0.16 + (level.clamp(0.0, 1.0) * 0.84);
    final double halfH = h / 2;

    for (int layer = 0; layer < 3; layer++) {
      final Color color = _layerColors[layer];

      // Layer-specific motion: different speeds and phases so the three
      // waves drift past each other fluidly, like the reference.
      final double speed = 1.0 + layer * 0.45;
      final double phase = (t * speed + layer * 0.33) % 1.0;
      final double amp = target * halfH * (0.10 + 0.08 * layer);
      final double offset = halfH * (layer == 1 ? 0.06 : -0.05 * layer);

      final Path path = Path();
      path.moveTo(0, halfH + offset);

      // Smooth wave: base sine + second harmonic for organic,
      // non-uniform motion (reference waves are not a pure sine).
      for (double x = 0; x <= w; x += 4) {
        final double p = x / w;
        final double wave =
            sin((2 * pi * (1.4 * p + phase)) + layer) * amp;
        final double wave2 =
            sin((2 * pi * (2.9 * p + phase * 1.7)) + layer * 2) * amp * 0.4;
        path.lineTo(x, halfH + offset + wave + wave2);
      }

      path.lineTo(w, halfH + offset);
      path.close();

      final Paint fill = Paint()
        ..color = color.withValues(alpha: 0.08 + 0.05 * layer)
        ..style = PaintingStyle.fill;
      canvas.drawPath(path, fill);

      // Soft glowing stroke.
      final Paint stroke = Paint()
        ..color = color.withValues(alpha: 0.55)
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1.6
        ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 4);
      canvas.drawPath(path, stroke);
    }
  }

  @override
  bool shouldRepaint(_WaveformPainter old) =>
      old.t != t || old.level != level;
}
