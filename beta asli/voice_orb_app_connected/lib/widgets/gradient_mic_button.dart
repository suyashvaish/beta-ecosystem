import 'package:flutter/material.dart';

import '../theme/beta_theme.dart';

/// The circular gradient microphone (or stop) button from the redesign:
/// purple -> pink -> blue gradient with a soft matching glow.
///
/// Shows [active] state as a stop square while listening (per the
/// reference listening screen); otherwise shows the mic glyph.
class GradientMicButton extends StatelessWidget {
  const GradientMicButton({
    super.key,
    required this.onTap,
    this.active = false,
    this.size = 74,
  });

  final VoidCallback onTap;
  final bool active;
  final double size;

  @override
  Widget build(BuildContext context) {
    return AnimatedContainer(
      duration: const Duration(milliseconds: 220),
      curve: Curves.easeOut,
      width: size,
      height: size,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        gradient: BetaColors.micGradient,
        boxShadow: [
          BoxShadow(
            color: (active ? BetaColors.pink : BetaColors.purple)
                .withValues(alpha: 0.45),
            blurRadius: active ? 34 : 26,
            spreadRadius: active ? 4 : 1,
          ),
        ],
      ),
      child: Material(
        color: Colors.transparent,
        shape: const CircleBorder(),
        child: InkWell(
          customBorder: const CircleBorder(),
          onTap: onTap,
          child: Icon(
            active ? Icons.stop_rounded : Icons.mic_rounded,
            color: Colors.white,
            size: size * 0.42,
          ),
        ),
      ),
    );
  }
}
