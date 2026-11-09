import 'package:flutter/material.dart';

/// JOLAY design tokens. The single source of truth for colour, type, spacing, shape, elevation,
/// sizes and motion. Mirrors `shared/design-tokens/tokens.json` (web) — change both together.
///
/// Brand colours are constants; everything a *screen* paints with must come from [JolayPalette]
/// (`context.palette`) so light and dark themes stay in sync.
abstract final class AppColors {
  // Brand
  static const midnight = Color(0xFF171717);
  static const yellow = Color(0xFFF5BD35);
  static const cloud = Color(0xFFF7F7F4);
  static const white = Color(0xFFFFFFFF);

  // Light-theme semantics
  static const textPrimary = Color(0xFF171717);

  /// Brief asks for #777777; that is 4.48:1 on white and ~4.1:1 on Cloud (below WCAG AA 4.5:1 for body text),
  /// so the secondary text is nudged to #6B6B6B (≥ 4.9:1 on both). Documented in JOLAY_DESIGN_SYSTEM.md.
  static const textSecondary = Color(0xFF6B6B6B);
  static const border = Color(0xFFE8E8E5);
  static const success = Color(0xFF198754);
  static const warning = Color(0xFFE9A23B);
  static const error = Color(0xFFDC3545);
  static const info = Color(0xFF2878D0);

  // Dark-theme semantics (not an inversion: warmer neutrals, lifted status colours)
  static const darkBackground = Color(0xFF171717);
  static const darkSurface = Color(0xFF1F1F1F);
  static const darkElevated = Color(0xFF242424);
  static const darkTextPrimary = Color(0xFFF7F7F4);
  static const darkTextSecondary = Color(0xFFA6A6A6);
  static const darkBorder = Color(0xFF333333);
  static const darkSuccess = Color(0xFF36C995);
  static const darkWarning = Color(0xFFF0B45A);
  static const darkError = Color(0xFFF16D7D);
  static const darkInfo = Color(0xFF6AAEF0);
}

/// Semantic colours resolved per brightness. Read with `context.palette`.
@immutable
class JolayPalette extends ThemeExtension<JolayPalette> {
  final Color background,
      surface,
      elevated,
      textPrimary,
      textSecondary,
      border,
      divider;
  final Color accent, onAccent, selected, selectedBorder;
  final Color success, warning, error, info;
  final Color successSoft, warningSoft, errorSoft, infoSoft;
  final Color scrim, inverse, onInverse;
  final bool isDark;

  const JolayPalette({
    required this.background,
    required this.surface,
    required this.elevated,
    required this.textPrimary,
    required this.textSecondary,
    required this.border,
    required this.divider,
    required this.accent,
    required this.onAccent,
    required this.selected,
    required this.selectedBorder,
    required this.success,
    required this.warning,
    required this.error,
    required this.info,
    required this.successSoft,
    required this.warningSoft,
    required this.errorSoft,
    required this.infoSoft,
    required this.scrim,
    required this.inverse,
    required this.onInverse,
    required this.isDark,
  });

  static const light = JolayPalette(
    background: AppColors.cloud,
    surface: AppColors.white,
    elevated: AppColors.white,
    textPrimary: AppColors.textPrimary,
    textSecondary: AppColors.textSecondary,
    border: AppColors.border,
    divider: Color(0xFFEFEFEB),
    accent: AppColors.yellow,
    onAccent: AppColors.midnight,
    selected: Color(0xFFFDF3D6),
    selectedBorder: AppColors.yellow,
    success: AppColors.success,
    warning: Color(0xFF9A6200),
    error: AppColors.error,
    info: AppColors.info,
    // Soft fills keep text at ≥ 4.5:1: the foreground of a badge is the *strong* status colour on its soft fill.
    successSoft: Color(0xFFDDF3E7),
    warningSoft: Color(0xFFFCEFD2),
    errorSoft: Color(0xFFFBE2E5),
    infoSoft: Color(0xFFE0EDFB),
    scrim: Color(0x66000000),
    inverse: AppColors.midnight,
    onInverse: AppColors.white,
    isDark: false,
  );

  static const dark = JolayPalette(
    background: AppColors.darkBackground,
    surface: AppColors.darkSurface,
    elevated: AppColors.darkElevated,
    textPrimary: AppColors.darkTextPrimary,
    textSecondary: AppColors.darkTextSecondary,
    border: AppColors.darkBorder,
    divider: Color(0xFF2B2B2B),
    accent: AppColors.yellow,
    onAccent: AppColors.midnight,
    selected: Color(0xFF33291A),
    selectedBorder: AppColors.yellow,
    success: AppColors.darkSuccess,
    warning: AppColors.darkWarning,
    error: AppColors.darkError,
    info: AppColors.darkInfo,
    successSoft: Color(0xFF14302A),
    warningSoft: Color(0xFF3A2D12),
    errorSoft: Color(0xFF3A1C22),
    infoSoft: Color(0xFF14283D),
    scrim: Color(0x99000000),
    inverse: AppColors.darkTextPrimary,
    onInverse: AppColors.midnight,
    isDark: true,
  );

  @override
  JolayPalette copyWith({Color? background}) => JolayPalette(
    background: background ?? this.background,
    surface: surface,
    elevated: elevated,
    textPrimary: textPrimary,
    textSecondary: textSecondary,
    border: border,
    divider: divider,
    accent: accent,
    onAccent: onAccent,
    selected: selected,
    selectedBorder: selectedBorder,
    success: success,
    warning: warning,
    error: error,
    info: info,
    successSoft: successSoft,
    warningSoft: warningSoft,
    errorSoft: errorSoft,
    infoSoft: infoSoft,
    scrim: scrim,
    inverse: inverse,
    onInverse: onInverse,
    isDark: isDark,
  );

  @override
  JolayPalette lerp(ThemeExtension<JolayPalette>? other, double t) =>
      t < .5 ? this : (other as JolayPalette? ?? this);
}

extension PaletteX on BuildContext {
  /// Semantic colours for the current theme brightness.
  JolayPalette get palette =>
      Theme.of(this).extension<JolayPalette>() ?? JolayPalette.light;
}

/// 4/8 spacing scale.
abstract final class AppSpacing {
  static const double s4 = 4,
      s8 = 8,
      s12 = 12,
      s16 = 16,
      s20 = 20,
      s24 = 24,
      s32 = 32,
      s40 = 40,
      s48 = 48;

  /// Standard horizontal screen gutter.
  static const double gutter = 20;
}

abstract final class AppRadius {
  static const double xs = 6,
      sm = 10,
      button = 14,
      input = 14,
      card = 18,
      sheet = 28,
      pill = 999;
  static BorderRadius get buttonR => BorderRadius.circular(button);
  static BorderRadius get inputR => BorderRadius.circular(input);
  static BorderRadius get cardR => BorderRadius.circular(card);
  static BorderRadius get sheetR =>
      const BorderRadius.vertical(top: Radius.circular(sheet));
}

/// Shadows are used sparingly: cards sit on borders, only floating map UI and sheets get a shadow.
abstract final class AppElevation {
  static const none = <BoxShadow>[];
  static const floating = [
    BoxShadow(color: Color(0x1F000000), blurRadius: 16, offset: Offset(0, 4)),
  ];
  static const sheet = [
    BoxShadow(color: Color(0x26000000), blurRadius: 28, offset: Offset(0, -6)),
  ];
  static const card = [
    BoxShadow(color: Color(0x0F000000), blurRadius: 8, offset: Offset(0, 2)),
  ];
}

abstract final class AppIconSize {
  static const double sm = 16, md = 20, lg = 24, xl = 32, hero = 48;
}

abstract final class AppSizes {
  static const double buttonL = 52,
      buttonM = 44,
      buttonS = 36,
      input = 52,
      minTap = 48,
      navBar = 68,
      grabber = 4;
}

/// Minimum comfortable touch target and layout constants shared by both apps.
abstract final class AppLayout {
  /// Android/Material minimum; driver-facing primary actions use [driverAction].
  static const double minTouch = 48;
  static const double driverAction = 60;
  static const double mapControl = 48;
}

abstract final class AppDurations {
  static const fast = Duration(milliseconds: 120);
  static const base = Duration(milliseconds: 200);
  static const slow = Duration(milliseconds: 320);
  static const ambient = Duration(milliseconds: 1600);
}

/// Honours the OS "reduce motion" setting: returns zero when animations are disabled.
extension MotionX on BuildContext {
  bool get reduceMotion => MediaQuery.maybeDisableAnimationsOf(this) ?? false;
  Duration motion(Duration d) => reduceMotion ? Duration.zero : d;
}

/// Type scale (Inter — it covers Kazakh Ә Ғ Қ Ң Ө Ұ Ү Һ І, Cyrillic, Latin and ₸).
abstract final class AppTypography {
  static const family = 'Inter';
  static const package = 'jolay_core';

  static TextTheme textTheme(Color primary, Color secondary) {
    TextStyle s(
      double size,
      FontWeight w, {
      double h = 1.3,
      double ls = 0,
      Color? c,
    }) => TextStyle(
      fontFamily: family,
      package: package,
      fontSize: size,
      fontWeight: w,
      height: h,
      letterSpacing: ls,
      color: c ?? primary,
    );
    return TextTheme(
      displayLarge: s(36, FontWeight.w800, h: 1.12, ls: -.8), // Display
      displayMedium: s(32, FontWeight.w800, h: 1.15, ls: -.6),
      headlineLarge: s(28, FontWeight.w800, h: 1.18, ls: -.4), // H1
      headlineMedium: s(24, FontWeight.w700, h: 1.22, ls: -.3), // H2
      headlineSmall: s(22, FontWeight.w700, h: 1.25, ls: -.2),
      titleLarge: s(20, FontWeight.w700, h: 1.25), // H3
      titleMedium: s(17, FontWeight.w600, h: 1.3),
      titleSmall: s(15, FontWeight.w600, h: 1.3),
      bodyLarge: s(16, FontWeight.w400, h: 1.45),
      bodyMedium: s(14, FontWeight.w400, h: 1.45), // Body
      bodySmall: s(12.5, FontWeight.w400, h: 1.35, c: secondary), // Caption
      labelLarge: s(15, FontWeight.w600, h: 1.2), // Button
      labelMedium: s(13, FontWeight.w600, h: 1.2),
      labelSmall: s(12, FontWeight.w600, h: 1.2, c: secondary),
    );
  }
}
