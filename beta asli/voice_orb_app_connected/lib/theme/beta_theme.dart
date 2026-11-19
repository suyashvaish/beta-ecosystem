import 'package:flutter/material.dart';

/// Beta Asli design system.
///
/// Palette and visual language from the approved redesign spec:
/// dark navy base, purple/pink/blue gradients, soft glows,
/// premium-minimalist styling. UI widgets read these constants instead
/// of hardcoding colors, so the whole app can be re-tuned from here.
abstract final class BetaColors {
  /// App background.
  static const Color background = Color(0xFF08091D);

  /// Secondary surfaces (sheets, input pills).
  static const Color backgroundSecondary = Color(0xFF101329);

  /// Cards and bubbles.
  static const Color card = Color(0xFF19182F);

  static const Color purple = Color(0xFF8755FF);
  static const Color pink = Color(0xFFFF75C8);
  static const Color blue = Color(0xFF478BFF);

  static const Color textPrimary = Color(0xFFFFFFFF);
  static const Color textSecondary = Color(0xFFA5A2B8);

  /// Error states - warm so it reads clearly against the navy.
  static const Color error = Color(0xFFFF7A8A);

  /// Signature gradient for the microphone button and accents.
  static const LinearGradient micGradient = LinearGradient(
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
    colors: [purple, pink, blue],
  );

  /// Quieter gradient for pills and secondary accents.
  static const LinearGradient pillGradient = LinearGradient(
    begin: Alignment.centerLeft,
    end: Alignment.centerRight,
    colors: [purple, blue],
  );

  /// Subtle card border used on bubbles and input pills.
  static const Color cardBorder = Color(0x14FFFFFF);
}

/// Text styles for the redesign.
abstract final class BetaText {
  static const TextStyle greeting = TextStyle(
    color: BetaColors.textPrimary,
    fontSize: 32,
    fontWeight: FontWeight.w600,
    height: 1.15,
  );

  static const TextStyle greetingSub = TextStyle(
    color: BetaColors.textSecondary,
    fontSize: 16,
    fontWeight: FontWeight.w400,
    height: 1.4,
  );

  static const TextStyle body = TextStyle(
    color: BetaColors.textPrimary,
    fontSize: 15.5,
    height: 1.4,
  );

  static const TextStyle bodySecondary = TextStyle(
    color: BetaColors.textSecondary,
    fontSize: 13,
    height: 1.4,
  );

  static const TextStyle timestamp = TextStyle(
    color: BetaColors.textSecondary,
    fontSize: 11,
    fontWeight: FontWeight.w400,
  );

  static const TextStyle status = TextStyle(
    color: BetaColors.textPrimary,
    fontSize: 15,
    fontWeight: FontWeight.w600,
  );
}

/// The dark [ThemeData] used app-wide. Widgets in the redesigned screens
/// still pin exact colors from [BetaColors] (like the previous code did)
/// so the visual result is deterministic; this theme keeps Material
/// chrome (dialogs, snackbars, switches) consistent with the palette.
class BetaTheme {
  static ThemeData dark() {
    final ColorScheme scheme = ColorScheme.fromSeed(
      seedColor: BetaColors.purple,
      brightness: Brightness.dark,
      surface: BetaColors.backgroundSecondary,
      onSurface: BetaColors.textPrimary,
    );

    return ThemeData(
      useMaterial3: true,
      brightness: Brightness.dark,
      colorScheme: scheme,
      scaffoldBackgroundColor: BetaColors.background,
      snackBarTheme: const SnackBarThemeData(
        backgroundColor: BetaColors.card,
        contentTextStyle: TextStyle(color: BetaColors.textPrimary),
        behavior: SnackBarBehavior.floating,
      ),
      dividerColor: BetaColors.cardBorder,
    );
  }
}
