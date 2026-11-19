import 'package:flutter/material.dart';

import '../theme/beta_theme.dart';

/// The large circular gradient microphone / stop button from the
/// reference design. Renders [icon] over the signature gradient with a
/// soft glow; [active] swaps the glow color (used for the stop state).
class GradientMicButton extends StatelessWidget {
  const GradientMicButton({
    super.key,
    required this.icon,
    required this.onTap,
    this.size = 76,
    this.active = false,
    this.activeColor,
  });

  final IconData icon;
  final VoidCallback? onTap;
  final double size;
  final bool active;

  /// Glow colour while [active] (defaults to the error colour, which the
  /// stop button uses).
  final Color? activeColor;

  @override
  Widget build(BuildContext context) {
    final Color glow = activeColor ?? BetaColors.error;

    return GestureDetector(
      onTap: onTap,
      child: Container(
        width: size,
        height: size,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          gradient:
              active ? null : BetaColors.micGradient,
          color: active ? glow.withOpacity(0.16) : null,
          border: active ? Border.all(color: glow, width: 1.4) : null,
          boxShadow: [
            BoxShadow(
              color: (active ? glow : BetaColors.purple)
                  .withOpacity(active ? 0.35 : 0.45),
              blurRadius: 34,
              spreadRadius: 2,
            ),
          ],
        ),
        child: Icon(
          icon,
          color: BetaColors.textPrimary,
          size: size * 0.38,
        ),
      ),
    );
  }
}

/// Small circular icon button (top bar, input row) using the card
/// surface colour from the design system.
class CircleIconButton extends StatelessWidget {
  const CircleIconButton({
    super.key,
    required this.icon,
    required this.onTap,
    this.iconColor,
    this.size = 44,
    this.tooltip,
  });

  final IconData icon;
  final VoidCallback? onTap;
  final Color? iconColor;
  final double size;
  final String? tooltip;

  @override
  Widget build(BuildContext context) {
    final Widget button = Material(
      color: BetaColors.backgroundSecondary,
      shape: const CircleBorder(
        side: BorderSide(color: BetaColors.cardBorder),
      ),
      child: InkWell(
        customBorder: const CircleBorder(),
        onTap: onTap,
        child: SizedBox(
          width: size,
          height: size,
          child: Icon(
            icon,
            color: iconColor ?? BetaColors.textSecondary,
            size: size * 0.5,
          ),
        ),
      ),
    );

    if (tooltip == null) return button;
    return Tooltip(message: tooltip!, child: button);
  }
}

/// The "Live / Thinking / Speaking" status pill. Gradient border,
/// translucent gradient fill, small dot indicator.
class StatusPill extends StatelessWidget {
  const StatusPill({super.key, required this.label, required this.active});

  final String label;

  /// When true the pill lights up (gradient + dot); when false it rests
  /// on the secondary surface.
  final bool active;

  @override
  Widget build(BuildContext context) {
    return Container(
      height: 36,
      padding: const EdgeInsets.symmetric(horizontal: 16),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(18),
        gradient: active ? BetaColors.pillGradient : null,
        color: active ? null : BetaColors.backgroundSecondary,
        border: Border.all(color: BetaColors.cardBorder),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 7,
            height: 7,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: active
                  ? BetaColors.textPrimary
                  : BetaColors.textSecondary,
            ),
          ),
          const SizedBox(width: 8),
          Text(
            label,
            style: TextStyle(
              color: active
                  ? BetaColors.textPrimary
                  : BetaColors.textSecondary,
              fontSize: 13,
              fontWeight: FontWeight.w600,
            ),
          ),
        ],
      ),
    );
  }
}
