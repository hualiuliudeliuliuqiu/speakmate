import 'package:flutter/material.dart';

/// SpeakMate Design System
/// Style: Clean Minimalist with warm, encouraging feel
/// Inspired by modern language learning apps (Duolingo's friendliness + Swiss minimalism)
class AppTheme {
  AppTheme._();

  // ─── Color Tokens ───
  static const Color primary = Color(0xFF0D9488);       // Teal 600
  static const Color primaryLight = Color(0xFF14B8A6);   // Teal 500
  static const Color primarySurface = Color(0xFFCCFBF1); // Teal 100
  static const Color primaryMuted = Color(0xFFF0FDFA);   // Teal 50

  static const Color accent = Color(0xFFF59E0B);         // Amber 500 - for highlights
  static const Color accentSurface = Color(0xFFFEF3C7);  // Amber 100

  static const Color danger = Color(0xFFEF4444);          // Red 500
  static const Color dangerSurface = Color(0xFFFEE2E2);   // Red 100

  static const Color success = Color(0xFF10B981);          // Emerald 500

  // Neutrals
  static const Color textPrimary = Color(0xFF1E293B);     // Slate 800
  static const Color textSecondary = Color(0xFF64748B);   // Slate 500
  static const Color textMuted = Color(0xFF94A3B8);       // Slate 400
  static const Color border = Color(0xFFE2E8F0);          // Slate 200
  static const Color surface = Color(0xFFFFFFFF);
  static const Color background = Color(0xFFF8FAFC);      // Slate 50
  static const Color backgroundAlt = Color(0xFFF1F5F9);   // Slate 100

  // ─── Typography ───
  static const String fontFamily = 'SF Pro Display';

  static const TextStyle headingLg = TextStyle(
    fontSize: 28,
    fontWeight: FontWeight.w700,
    color: textPrimary,
    height: 1.2,
    letterSpacing: -0.5,
  );

  static const TextStyle headingMd = TextStyle(
    fontSize: 20,
    fontWeight: FontWeight.w600,
    color: textPrimary,
    height: 1.3,
  );

  static const TextStyle headingSm = TextStyle(
    fontSize: 16,
    fontWeight: FontWeight.w600,
    color: textPrimary,
    height: 1.4,
  );

  static const TextStyle bodyLg = TextStyle(
    fontSize: 16,
    fontWeight: FontWeight.w400,
    color: textSecondary,
    height: 1.5,
  );

  static const TextStyle bodySm = TextStyle(
    fontSize: 14,
    fontWeight: FontWeight.w400,
    color: textSecondary,
    height: 1.5,
  );

  static const TextStyle caption = TextStyle(
    fontSize: 12,
    fontWeight: FontWeight.w500,
    color: textMuted,
    height: 1.4,
  );

  static const TextStyle label = TextStyle(
    fontSize: 11,
    fontWeight: FontWeight.w600,
    color: textMuted,
    letterSpacing: 0.5,
  );

  // ─── Spacing ───
  static const double spacingXs = 4;
  static const double spacingSm = 8;
  static const double spacingMd = 16;
  static const double spacingLg = 24;
  static const double spacingXl = 32;
  static const double spacingXxl = 48;

  // ─── Radius ───
  static const double radiusSm = 8;
  static const double radiusMd = 12;
  static const double radiusLg = 16;
  static const double radiusXl = 20;
  static const double radiusFull = 999;

  // ─── Shadows ───
  static List<BoxShadow> shadowSm = [
    BoxShadow(
      color: Colors.black.withValues(alpha: 0.04),
      blurRadius: 6,
      offset: const Offset(0, 2),
    ),
  ];

  static List<BoxShadow> shadowMd = [
    BoxShadow(
      color: Colors.black.withValues(alpha: 0.06),
      blurRadius: 12,
      offset: const Offset(0, 4),
    ),
  ];

  static List<BoxShadow> shadowLg = [
    BoxShadow(
      color: Colors.black.withValues(alpha: 0.08),
      blurRadius: 20,
      offset: const Offset(0, 8),
    ),
  ];

  static List<BoxShadow> shadowPrimary = [
    BoxShadow(
      color: primary.withValues(alpha: 0.25),
      blurRadius: 16,
      offset: const Offset(0, 6),
    ),
  ];

  // ─── Scenario Card Colors ───
  static const List<Color> scenarioColors = [
    Color(0xFF0D9488), // Teal
    Color(0xFF6366F1), // Indigo
    Color(0xFFF59E0B), // Amber
    Color(0xFFEC4899), // Pink
    Color(0xFF8B5CF6), // Violet
    Color(0xFF06B6D4), // Cyan
  ];

  static const List<Color> scenarioLightColors = [
    Color(0xFFF0FDFA), // Teal 50
    Color(0xFFEEF2FF), // Indigo 50
    Color(0xFFFFFBEB), // Amber 50
    Color(0xFFFDF2F8), // Pink 50
    Color(0xFFF5F3FF), // Violet 50
    Color(0xFFECFEFF), // Cyan 50
  ];

  // ─── ThemeData ───
  static ThemeData get lightTheme => ThemeData(
    useMaterial3: true,
    colorScheme: ColorScheme.fromSeed(
      seedColor: primary,
      brightness: Brightness.light,
    ),
    scaffoldBackgroundColor: background,
    appBarTheme: const AppBarTheme(
      backgroundColor: surface,
      elevation: 0,
      scrolledUnderElevation: 0.5,
      centerTitle: false,
      titleTextStyle: headingSm,
      iconTheme: IconThemeData(color: textSecondary),
    ),
    cardTheme: CardThemeData(
      elevation: 0,
      color: surface,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(radiusLg),
      ),
    ),
    elevatedButtonTheme: ElevatedButtonThemeData(
      style: ElevatedButton.styleFrom(
        elevation: 0,
        backgroundColor: primary,
        foregroundColor: Colors.white,
        padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 14),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(radiusMd),
        ),
        textStyle: const TextStyle(
          fontSize: 15,
          fontWeight: FontWeight.w600,
        ),
      ),
    ),
    inputDecorationTheme: InputDecorationTheme(
      filled: true,
      fillColor: backgroundAlt,
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(radiusMd),
        borderSide: BorderSide.none,
      ),
      contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
      hintStyle: const TextStyle(color: textMuted, fontSize: 15),
    ),
    dividerTheme: const DividerThemeData(
      color: border,
      thickness: 1,
    ),
    snackBarTheme: SnackBarThemeData(
      behavior: SnackBarBehavior.floating,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(radiusMd),
      ),
    ),
  );
}
