import 'package:flutter/material.dart';

import 'design/tokens.dart';

/// Legacy aliases kept so existing screens compile; new code should use [AppColors] / `context.palette`.
abstract final class JolayColors {
  static const midnight = AppColors.midnight;
  static const yellow = AppColors.yellow;
  static const cloud = AppColors.cloud;
  static const white = AppColors.white;
  static const textSecondary = AppColors.textSecondary;
  static const success = AppColors.success;
  static const error = AppColors.error;
  static const border = AppColors.border;
}

abstract final class JolayRadius {
  static const sm = AppRadius.sm, md = AppRadius.button, lg = AppRadius.card;
}

ThemeData jolayTheme() => _build(JolayPalette.light, Brightness.light);
ThemeData jolayDarkTheme() => _build(JolayPalette.dark, Brightness.dark);

ThemeData _build(JolayPalette p, Brightness b) {
  final scheme = ColorScheme(
    brightness: b,
    primary: p.accent,
    onPrimary: p.onAccent,
    secondary: p.isDark ? p.accent : AppColors.midnight,
    onSecondary: p.isDark ? p.onAccent : AppColors.white,
    error: p.error,
    onError: p.isDark ? AppColors.midnight : AppColors.white,
    surface: p.surface,
    onSurface: p.textPrimary,
    surfaceContainerLowest: p.background,
    surfaceContainerLow: p.surface,
    surfaceContainer: p.surface,
    surfaceContainerHigh: p.elevated,
    surfaceContainerHighest: p.elevated,
    onSurfaceVariant: p.textSecondary,
    outline: p.border,
    outlineVariant: p.divider,
    inverseSurface: p.inverse,
    onInverseSurface: p.onInverse,
    scrim: Colors.black,
    primaryContainer: p.selected,
    onPrimaryContainer: p.textPrimary,
  );
  final text = AppTypography.textTheme(p.textPrimary, p.textSecondary);
  final shape = RoundedRectangleBorder(borderRadius: AppRadius.buttonR);
  OutlineInputBorder border(Color c, [double w = 1]) => OutlineInputBorder(
    borderRadius: AppRadius.inputR,
    borderSide: BorderSide(color: c, width: w),
  );

  return ThemeData(
    useMaterial3: true,
    brightness: b,
    colorScheme: scheme,
    fontFamily: AppTypography.family,
    package: AppTypography.package,
    textTheme: text,
    primaryTextTheme: text,
    scaffoldBackgroundColor: p.background,
    canvasColor: p.background,
    dividerColor: p.divider,
    dividerTheme: DividerThemeData(color: p.divider, thickness: 1, space: 1),
    splashFactory: InkRipple.splashFactory,
    visualDensity: VisualDensity.standard,
    extensions: [p],
    appBarTheme: AppBarTheme(
      backgroundColor: p.background,
      foregroundColor: p.textPrimary,
      elevation: 0,
      scrolledUnderElevation: 0,
      centerTitle: false,
      titleTextStyle: text.titleLarge,
      iconTheme: IconThemeData(color: p.textPrimary),
    ),
    cardTheme: CardThemeData(
      color: p.surface,
      elevation: 0,
      margin: EdgeInsets.zero,
      shape: RoundedRectangleBorder(
        borderRadius: AppRadius.cardR,
        side: BorderSide(color: p.border),
      ),
    ),
    inputDecorationTheme: InputDecorationTheme(
      filled: true,
      fillColor: p.surface,
      contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
      labelStyle: text.bodyMedium?.copyWith(color: p.textSecondary),
      hintStyle: text.bodyMedium?.copyWith(color: p.textSecondary),
      errorStyle: text.bodySmall?.copyWith(
        color: p.error,
        fontWeight: FontWeight.w500,
      ),
      border: border(p.border),
      enabledBorder: border(p.border),
      disabledBorder: border(p.divider),
      focusedBorder: border(p.isDark ? p.accent : AppColors.midnight, 2),
      errorBorder: border(p.error),
      focusedErrorBorder: border(p.error, 2),
    ),
    filledButtonTheme: FilledButtonThemeData(
      style: FilledButton.styleFrom(
        backgroundColor: p.accent,
        foregroundColor: p.onAccent,
        disabledBackgroundColor: p.divider,
        disabledForegroundColor: p.textSecondary,
        minimumSize: const Size.fromHeight(AppSizes.buttonL),
        padding: const EdgeInsets.symmetric(horizontal: 20),
        textStyle: text.labelLarge,
        shape: shape,
      ),
    ),
    outlinedButtonTheme: OutlinedButtonThemeData(
      style: OutlinedButton.styleFrom(
        foregroundColor: p.textPrimary,
        disabledForegroundColor: p.textSecondary,
        minimumSize: const Size.fromHeight(AppSizes.buttonL),
        padding: const EdgeInsets.symmetric(horizontal: 20),
        side: BorderSide(color: p.border),
        textStyle: text.labelLarge,
        shape: shape,
      ),
    ),
    textButtonTheme: TextButtonThemeData(
      style: TextButton.styleFrom(
        foregroundColor: p.textPrimary,
        minimumSize: const Size(AppSizes.minTap, AppSizes.buttonM),
        textStyle: text.labelLarge,
        shape: shape,
      ),
    ),
    iconButtonTheme: IconButtonThemeData(
      style: IconButton.styleFrom(
        minimumSize: const Size(AppSizes.minTap, AppSizes.minTap),
        foregroundColor: p.textPrimary,
      ),
    ),
    chipTheme: ChipThemeData(
      backgroundColor: p.surface,
      selectedColor: p.selected,
      side: BorderSide(color: p.border),
      labelStyle: text.labelMedium,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(AppRadius.pill),
      ),
      showCheckmark: false,
    ),
    listTileTheme: ListTileThemeData(
      iconColor: p.textPrimary,
      textColor: p.textPrimary,
      minVerticalPadding: 10,
      contentPadding: const EdgeInsets.symmetric(horizontal: 16),
    ),
    navigationBarTheme: NavigationBarThemeData(
      backgroundColor: p.surface,
      indicatorColor: p.accent,
      height: AppSizes.navBar,
      elevation: 0,
      surfaceTintColor: Colors.transparent,
      labelTextStyle: WidgetStateProperty.resolveWith(
        (s) => text.labelSmall?.copyWith(
          color: s.contains(WidgetState.selected)
              ? p.textPrimary
              : p.textSecondary,
          fontWeight: s.contains(WidgetState.selected)
              ? FontWeight.w700
              : FontWeight.w500,
        ),
      ),
      iconTheme: WidgetStateProperty.resolveWith(
        (s) => IconThemeData(
          size: 24,
          color: s.contains(WidgetState.selected)
              ? p.onAccent
              : p.textSecondary,
        ),
      ),
    ),
    bottomSheetTheme: BottomSheetThemeData(
      backgroundColor: p.surface,
      surfaceTintColor: Colors.transparent,
      shape: RoundedRectangleBorder(borderRadius: AppRadius.sheetR),
      showDragHandle: false,
      clipBehavior: Clip.antiAlias,
    ),
    dialogTheme: DialogThemeData(
      backgroundColor: p.surface,
      surfaceTintColor: Colors.transparent,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(AppRadius.sheet - 4),
      ),
      titleTextStyle: text.titleLarge,
      contentTextStyle: text.bodyMedium,
    ),
    snackBarTheme: SnackBarThemeData(
      behavior: SnackBarBehavior.floating,
      backgroundColor: p.inverse,
      contentTextStyle: text.bodyMedium?.copyWith(
        color: p.onInverse,
        fontWeight: FontWeight.w500,
      ),
      actionTextColor: p.isDark ? AppColors.midnight : AppColors.yellow,
      shape: RoundedRectangleBorder(borderRadius: AppRadius.buttonR),
      insetPadding: const EdgeInsets.all(16),
    ),
    progressIndicatorTheme: ProgressIndicatorThemeData(
      color: p.isDark ? p.accent : AppColors.midnight,
      linearTrackColor: p.divider,
      circularTrackColor: Colors.transparent,
    ),
    switchTheme: SwitchThemeData(
      thumbColor: WidgetStateProperty.resolveWith(
        (s) => s.contains(WidgetState.selected)
            ? AppColors.midnight
            : p.textSecondary,
      ),
      trackColor: WidgetStateProperty.resolveWith(
        (s) => s.contains(WidgetState.selected) ? p.accent : p.divider,
      ),
      trackOutlineColor: WidgetStateProperty.resolveWith(
        (s) => s.contains(WidgetState.selected) ? p.accent : p.border,
      ),
    ),
    checkboxTheme: CheckboxThemeData(
      fillColor: WidgetStateProperty.resolveWith(
        (s) => s.contains(WidgetState.selected) ? p.accent : null,
      ),
      checkColor: WidgetStateProperty.all(AppColors.midnight),
      side: BorderSide(color: p.textSecondary, width: 1.5),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(5)),
    ),
    segmentedButtonTheme: SegmentedButtonThemeData(
      style: SegmentedButton.styleFrom(
        backgroundColor: p.surface,
        foregroundColor: p.textPrimary,
        selectedBackgroundColor: p.accent,
        selectedForegroundColor: p.onAccent,
        side: BorderSide(color: p.border),
        textStyle: text.labelMedium,
        shape: shape,
      ),
    ),
    tabBarTheme: TabBarThemeData(
      labelColor: p.textPrimary,
      unselectedLabelColor: p.textSecondary,
      indicatorColor: p.accent,
      dividerColor: p.divider,
      labelStyle: text.labelLarge,
      unselectedLabelStyle: text.labelLarge?.copyWith(
        fontWeight: FontWeight.w500,
      ),
      indicatorSize: TabBarIndicatorSize.label,
    ),
    focusColor: p.accent.withValues(alpha: .25),
  );
}
