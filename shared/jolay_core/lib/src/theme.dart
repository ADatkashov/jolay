import 'package:flutter/material.dart';

/// JOLAY design tokens (mirrors shared/design-tokens/tokens.json).
class JolayColors {
  static const midnight = Color(0xFF171717);
  static const yellow = Color(0xFFF5BD35);
  static const cloud = Color(0xFFF7F7F4);
  static const white = Color(0xFFFFFFFF);
  static const textSecondary = Color(0xFF777777);
  static const success = Color(0xFF20A46B);
  static const error = Color(0xFFE5484D);
  static const border = Color(0xFFEAEAEA);
}

class JolayRadius {
  static const sm = 8.0, md = 14.0, lg = 20.0;
}

ThemeData jolayTheme() {
  const font = 'Manrope'; // falls back to the platform font if the font asset is not bundled
  final scheme = ColorScheme.fromSeed(seedColor: JolayColors.yellow, brightness: Brightness.light).copyWith(
    primary: JolayColors.yellow, onPrimary: JolayColors.midnight, secondary: JolayColors.midnight, onSecondary: Colors.white,
    surface: JolayColors.white, onSurface: JolayColors.midnight, error: JolayColors.error,
  );
  return ThemeData(
    useMaterial3: true,
    colorScheme: scheme,
    fontFamily: font,
    fontFamilyFallback: const ['Inter', 'Roboto'],
    scaffoldBackgroundColor: JolayColors.cloud,
    appBarTheme: const AppBarTheme(backgroundColor: JolayColors.cloud, foregroundColor: JolayColors.midnight, elevation: 0, scrolledUnderElevation: 0),
    cardTheme: CardThemeData(color: Colors.white, elevation: 0, margin: EdgeInsets.zero,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(JolayRadius.md), side: const BorderSide(color: JolayColors.border))),
    inputDecorationTheme: InputDecorationTheme(
      filled: true, fillColor: Colors.white,
      contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
      border: OutlineInputBorder(borderRadius: BorderRadius.circular(JolayRadius.md), borderSide: const BorderSide(color: JolayColors.border)),
      enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(JolayRadius.md), borderSide: const BorderSide(color: JolayColors.border)),
      focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(JolayRadius.md), borderSide: const BorderSide(color: JolayColors.midnight, width: 1.5)),
    ),
    filledButtonTheme: FilledButtonThemeData(
      style: FilledButton.styleFrom(
        backgroundColor: JolayColors.yellow, foregroundColor: JolayColors.midnight, minimumSize: const Size.fromHeight(54),
        textStyle: const TextStyle(fontWeight: FontWeight.w800, fontSize: 16),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(JolayRadius.md)),
      ),
    ),
    outlinedButtonTheme: OutlinedButtonThemeData(
      style: OutlinedButton.styleFrom(
        foregroundColor: JolayColors.midnight, minimumSize: const Size.fromHeight(54), side: const BorderSide(color: JolayColors.border),
        textStyle: const TextStyle(fontWeight: FontWeight.w700, fontSize: 16),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(JolayRadius.md)),
      ),
    ),
    navigationBarTheme: NavigationBarThemeData(
      backgroundColor: Colors.white, indicatorColor: JolayColors.yellow,
      labelTextStyle: WidgetStateProperty.all(const TextStyle(fontWeight: FontWeight.w600, fontSize: 12)),
    ),
    snackBarTheme: SnackBarThemeData(behavior: SnackBarBehavior.floating, backgroundColor: JolayColors.midnight,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(JolayRadius.sm))),
  );
}
