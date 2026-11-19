import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../theme/beta_theme.dart';

/// The five assistant states the waveform reflects.
enum WaveformState { idle, listening, processing, speaking, error }

/// Replaces the old VoiceOrb with a layered, multicoloured audio
/// waveform - the visual centrepiece of the redesign.
///
/// Three translucent wave layers (purple, pink, blue) drift smoothly
/// and respond to [audioLevel]:
///   - listening: layers track the real microphone dB level reported
///     by VoiceController.onSoundLevelChange (no fake animation).
///   - speaking: layers track a synthetic TTS playback envelope.
///   - processing: slow gentle breathing while Beta thinks.
///   - idle/error: near-flat calm line.
///
/// All animation is driven by one AnimationController so the cost is
/// one painter repaint per frame - same order as the old orb's pulse
/// controller.
class VoiceWaveform extends StatefulWidget {
  const VoiceWaveform({
    super.key,
    required this.state,
    this.audioLevel = 0.0,
    this.size = const Size(320, 150),
  });

  final WaveformState state;
  final double audioLevel; // 0.0 .. 1.0, real mic or TTS envelope
  final Size size;

  @override
  State<VoiceWaveform> createState() => _VoiceWaveformState();
}

class _VoiceWaveformState extends State<VoiceWaveform>
    with SingleTickerProviderStateMixin {
  late final AnimationController _drift;

  @override
  void initState() {
    super.initState();
    _drift = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 2400),
    )..repeat();
  }

  @override
  void dispose() {
    _drift.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _drift,
      builder: (context, _) {
        return CustomPaint(
          painter: _WavePainter(
            t: _drift.value,
            level: widget.audioLevel.clamp(0.0, 1.0),
            state: widget.state,
          ),
          size: widget.size,
        );
      },
    );
  }
}

class _WavePainter extends CustomPainter {
  _WavePainter({required this.t, required this.level, required this.state});

  final double t; // 0..1 loop position
  final double level; // 0..1 real audio level
  final WaveformState state;

  @override
  void paint(Canvas canvas, Size size) {
    final double amplitude =
        (size.height / 2) * (0.08 + 0.92 * _effectiveLevel());

    // Back layer: blue, most translucent, fastest drift.
    _drawLayer(
      canvas,
      size,
      color: BetaColors.blue,
      opacity: 0.14,
      phase: t * 2.0 * math.pi,
      speed: 1.6,
      amplitudeScale: 0.55,
    );

    // Middle layer: pink.
    _drawLayer(
      canvas,
      size,
      color: BetaColors.pink,
      opacity: 0.20,
      phase: t * 2.0 * math.pi + 0.5,
      speed: 1.2,
      amplitudeScale: 0.75,
    );

    // Front layer: purple, most opaque.
    _drawLayer(
      canvas,
      size,
      color: BetaColors.purple,
      opacity: 0.85,
      phase: t * 2.0 * math.pi + 1.0,
      speed: 1.0,
      amplitudeScale: 1.0,
    );
  }

  double _effectiveLevel() {
    switch (state) {
      case WaveformState.listening:
      case WaveformState.speaking:
        return level;
      case WaveformState.processing:
        // Slow breathing while Beta thinks.
        return 0.18 + 0.10 * math.sin(t * 2.0 * math.pi);
      case WaveformState.idle:
      case WaveformState.error:
        return 0.08;
    }
  }

  void _drawLayer(
    Canvas canvas,
    Size size, {
    required Color color,
    required double opacity,
    required double phase,
    required double speed,
    required double amplitudeScale,
  }) {
    final double midY = size.height / 2;

    // Sum of three sines of different speeds - organic-looking without
    // being computationally expensive.
    final Path path = Path();
    final double step = size.width / 48;
    double prevX = 0.0;
    double prevY = midY;
    for (double x = 0.0; x <= size.width + step; x += step) {
      final double u = x / size.width;
      final double wave =
          math.sin(u * 2.0 * math.pi * speed + phase) * 0.55 +
              math.sin(u * 2.0 * math.pi * speed * 2.3 + phase * 1.3) * 0.25 +
              math.sin(u * 2.0 * math.pi * speed * 0.7 + phase * 0.7) * 0.20;
      final double y = midY - wave * amplitude * amplitudeScale;
      if (x == 0.0) {
        path.moveTo(x, y);
      } else {
        path.quadraticBezierTo(prevX + step / 2, prevY, x, y);
      }
      prevX = x;
      prevY = y;
    }

    // Close the shape downward so each layer is a translucent ribbon,
    // not just a line - the layered look from the reference design.
    path.lineTo(size.width, size.height);
    path.lineTo(0, size.height);
    path.close();

    final Paint paint = Paint()
      ..color = color.withValues(alpha: opacity)
      ..style = PaintingStyle.fill
      ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 6);

    canvas.drawPath(path, paint);
  }

  @override
  bool shouldRepaint(covariant _WavePainter oldDelegate) =>
      oldDelegate.t != t ||
      oldDelegate.level != level ||
      oldDelegate.state != state;
}
