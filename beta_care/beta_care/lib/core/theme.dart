import 'package:flutter/material.dart';

/// A named palette instead of Flutter's default seed-color purple - chosen
/// so the app reads as "calm, trustworthy healthcare-adjacent utility"
/// rather than a generic Material demo (spec section 23).
class AppColors {
  AppColors._();

  static const Color harbor = Color(0xFF2D6A6E); // primary - muted teal
  static const Color harborDark = Color(0xFF1E4A4D);
  static const Color ink = Color(0xFF1C2B2E); // primary text, light mode
  static const Color mist = Color(0xFFF6F8F7); // background, light mode
  static const Color cloud = Color(0xFFFFFFFF); // surface, light mode

  static const Color sage = Color(0xFF4F8A5B); // normal / taken / connected
  static const Color amber = Color(0xFFC77D2E); // attention / not confirmed
  static const Color coral = Color(0xFFC4453A); // emergency
  static const Color slate = Color(0xFF8A9493); // unknown / neutral

  // Dark mode
  static const Color inkOnDark = Color(0xFFEDEFEE);
  static const Color backgroundDark = Color(0xFF12191A);
  static const Color surfaceDark = Color(0xFF1B2426);
}

class AppTheme {
  AppTheme._();

  static ThemeData get light => _base(Brightness.light);
  static ThemeData get dark => _base(Brightness.dark);

  static ThemeData _base(Brightness brightness) {
    final isDark = brightness == Brightness.dark;
    final background = isDark ? AppColors.backgroundDark : AppColors.mist;
    final surface = isDark ? AppColors.surfaceDark : AppColors.cloud;
    final onSurface = isDark ? AppColors.inkOnDark : AppColors.ink;

    final colorScheme = ColorScheme(
      brightness: brightness,
      primary: AppColors.harbor,
      onPrimary: Colors.white,
      secondary: AppColors.sage,
      onSecondary: Colors.white,
      error: AppColors.coral,
      onError: Colors.white,
      surface: surface,
      onSurface: onSurface,
    );

    return ThemeData(
      useMaterial3: true,
      brightness: brightness,
      colorScheme: colorScheme,
      scaffoldBackgroundColor: background,
      appBarTheme: AppBarTheme(
        backgroundColor: background,
        foregroundColor: onSurface,
        elevation: 0,
        scrolledUnderElevation: 1,
        centerTitle: false,
        titleTextStyle: TextStyle(
          color: onSurface,
          fontSize: 20,
          fontWeight: FontWeight.w700,
          letterSpacing: -0.2,
        ),
      ),
      cardTheme: CardThemeData(
        color: surface,
        elevation: 0,
        margin: EdgeInsets.zero,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(16),
          side: BorderSide(color: onSurface.withValues(alpha: 0.06)),
        ),
      ),
      dividerTheme: DividerThemeData(color: onSurface.withValues(alpha: 0.08), space: 1),
      textTheme: _textTheme(onSurface),
      elevatedButtonTheme: ElevatedButtonThemeData(
        style: ElevatedButton.styleFrom(
          backgroundColor: AppColors.harbor,
          foregroundColor: Colors.white,
          padding: const EdgeInsets.symmetric(vertical: 14, horizontal: 20),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
          textStyle: const TextStyle(fontSize: 16, fontWeight: FontWeight.w600),
        ),
      ),
      outlinedButtonTheme: OutlinedButtonThemeData(
        style: OutlinedButton.styleFrom(
          foregroundColor: AppColors.harbor,
          side: const BorderSide(color: AppColors.harbor),
          padding: const EdgeInsets.symmetric(vertical: 14, horizontal: 20),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        ),
      ),
      navigationBarTheme: NavigationBarThemeData(
        backgroundColor: surface,
        indicatorColor: AppColors.harbor.withValues(alpha: 0.14),
        labelTextStyle: WidgetStateProperty.all(
          const TextStyle(fontSize: 12, fontWeight: FontWeight.w600),
        ),
      ),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: surface,
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: BorderSide(color: onSurface.withValues(alpha: 0.12)),
        ),
        contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
      ),
    );
  }

  static TextTheme _textTheme(Color onSurface) {
    return TextTheme(
      displaySmall: TextStyle(fontSize: 40, fontWeight: FontWeight.w700, color: onSurface, letterSpacing: -0.5),
      headlineSmall: TextStyle(fontSize: 24, fontWeight: FontWeight.w700, color: onSurface, letterSpacing: -0.3),
      titleLarge: TextStyle(fontSize: 18, fontWeight: FontWeight.w700, color: onSurface),
      titleMedium: TextStyle(fontSize: 16, fontWeight: FontWeight.w600, color: onSurface),
      bodyLarge: TextStyle(fontSize: 16, fontWeight: FontWeight.w400, color: onSurface, height: 1.4),
      bodyMedium: TextStyle(fontSize: 14, fontWeight: FontWeight.w400, color: onSurface.withValues(alpha: 0.75), height: 1.4),
      labelMedium: TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: onSurface.withValues(alpha: 0.6), letterSpacing: 0.4),
    );
  }
}
