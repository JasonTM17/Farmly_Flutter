import 'package:flutter/material.dart';

import 'farmly_colors.dart';
import 'farmly_spacing.dart';
import 'farmly_theme_extension.dart';

/// Canonical Farmly light theme: token palette, one type family, fixed scale,
/// restrained clay depth, rounded cards / sheets / pill buttons.
ThemeData buildFarmTheme() {
  const scheme = ColorScheme.light(
    primary: FarmlyColors.brandAction,
    onPrimary: FarmlyColors.onAction,
    secondary: FarmlyColors.brandSage,
    onSecondary: FarmlyColors.textPrimary,
    tertiary: FarmlyColors.illustrationSky,
    onTertiary: FarmlyColors.textPrimary,
    error: FarmlyColors.semanticError,
    onError: FarmlyColors.onAction,
    surface: FarmlyColors.surface,
    onSurface: FarmlyColors.textPrimary,
    surfaceContainerHighest: FarmlyColors.brandSage,
    surfaceContainerHigh: FarmlyColors.surface,
    surfaceContainer: FarmlyColors.surface,
    surfaceContainerLow: FarmlyColors.surface,
    surfaceContainerLowest: FarmlyColors.surface,
    surfaceBright: FarmlyColors.surface,
    surfaceDim: FarmlyColors.background,
    onSurfaceVariant: FarmlyColors.textSecondary,
    outline: FarmlyColors.divider,
    outlineVariant: FarmlyColors.divider,
    inverseSurface: FarmlyColors.textPrimary,
    onInverseSurface: FarmlyColors.onAction,
    inversePrimary: FarmlyColors.brandSage,
    surfaceTint: FarmlyColors.brandAction,
    scrim: FarmlyColors.textPrimary,
    shadow: FarmlyColors.textPrimary,
  );

  final base = ThemeData(
    useMaterial3: true,
    colorScheme: scheme,
    fontFamily: 'Be Vietnam Pro',
  );

  const tokens = FarmThemeExtension(
    background: FarmlyColors.background,
    surface: FarmlyColors.surface,
    textPrimary: FarmlyColors.textPrimary,
    textSecondary: FarmlyColors.textSecondary,
    brandAction: FarmlyColors.brandAction,
    brandSage: FarmlyColors.brandSage,
    illustrationSky: FarmlyColors.illustrationSky,
    illustrationBarn: FarmlyColors.illustrationBarn,
    semanticWarning: FarmlyColors.semanticWarning,
    semanticError: FarmlyColors.semanticError,
    divider: FarmlyColors.divider,
    onAction: FarmlyColors.onAction,
    cardRadius: FarmSpacing.cardRadius,
    sheetTopRadius: FarmSpacing.sheetTopRadius,
    pressDuration: FarmSpacing.press,
    stateDuration: FarmSpacing.state,
    zoneZoomDuration: FarmSpacing.zoneZoom,
  );

  return base.copyWith(
    scaffoldBackgroundColor: FarmlyColors.background,
    extensions: <ThemeExtension<dynamic>>[tokens],
    textTheme: _farmTextTheme(base.textTheme),
    appBarTheme: const AppBarTheme(
      backgroundColor: FarmlyColors.background,
      surfaceTintColor: Colors.transparent,
      elevation: 0,
      foregroundColor: FarmlyColors.textPrimary,
      iconTheme: IconThemeData(color: FarmlyColors.textPrimary, size: 24),
      titleTextStyle: TextStyle(
        fontFamily: 'Be Vietnam Pro',
        fontSize: 16,
        fontWeight: FontWeight.w600,
        color: FarmlyColors.textPrimary,
      ),
    ),
    iconTheme: const IconThemeData(color: FarmlyColors.textPrimary, size: 24),
    cardTheme: CardThemeData(
      color: FarmlyColors.surface,
      surfaceTintColor: Colors.transparent,
      elevation: 2,
      shadowColor: FarmlyColors.brandAction.withValues(alpha: 0.16),
      margin: EdgeInsets.zero,
      clipBehavior: Clip.antiAlias,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(FarmSpacing.cardRadius),
        side: const BorderSide(color: FarmlyColors.divider),
      ),
    ),
    bottomSheetTheme: BottomSheetThemeData(
      backgroundColor: FarmlyColors.surface,
      surfaceTintColor: Colors.transparent,
      elevation: 7,
      shadowColor: FarmlyColors.textPrimary.withValues(alpha: 0.18),
      showDragHandle: true,
      dragHandleColor: FarmlyColors.divider,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(
          top: Radius.circular(FarmSpacing.sheetTopRadius),
        ),
      ),
    ),
    dialogTheme: DialogThemeData(
      backgroundColor: FarmlyColors.surface,
      surfaceTintColor: Colors.transparent,
      elevation: 5,
      shadowColor: FarmlyColors.brandAction.withValues(alpha: 0.18),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(FarmSpacing.cardRadius),
        side: const BorderSide(color: FarmlyColors.divider),
      ),
      titleTextStyle: const TextStyle(
        fontFamily: 'Be Vietnam Pro',
        fontSize: 16,
        fontWeight: FontWeight.w600,
        color: FarmlyColors.textPrimary,
      ),
    ),
    filledButtonTheme: FilledButtonThemeData(
      style: FilledButton.styleFrom(
        elevation: 2,
        shadowColor: FarmlyColors.brandAction.withValues(alpha: 0.24),
        backgroundColor: FarmlyColors.brandAction,
        foregroundColor: FarmlyColors.onAction,
        disabledBackgroundColor: FarmlyColors.brandSage,
        disabledForegroundColor: FarmlyColors.textPrimary,
        shape: const StadiumBorder(),
        minimumSize: const Size(64, FarmSpacing.minTouchTarget),
        padding: const EdgeInsets.symmetric(
          horizontal: FarmSpacing.xxl,
          vertical: FarmSpacing.md,
        ),
        textStyle: const TextStyle(
          fontFamily: 'Be Vietnam Pro',
          fontSize: 14,
          fontWeight: FontWeight.w600,
        ),
      ),
    ),
    outlinedButtonTheme: OutlinedButtonThemeData(
      style: OutlinedButton.styleFrom(
        foregroundColor: FarmlyColors.brandAction,
        shape: const StadiumBorder(),
        side: const BorderSide(color: FarmlyColors.brandAction),
        minimumSize: const Size(64, FarmSpacing.minTouchTarget),
        textStyle: const TextStyle(
          fontFamily: 'Be Vietnam Pro',
          fontSize: 14,
          fontWeight: FontWeight.w600,
        ),
      ),
    ),
    textButtonTheme: TextButtonThemeData(
      style: TextButton.styleFrom(
        foregroundColor: FarmlyColors.brandAction,
        minimumSize: const Size(48, FarmSpacing.minTouchTarget),
        textStyle: const TextStyle(
          fontFamily: 'Be Vietnam Pro',
          fontSize: 14,
          fontWeight: FontWeight.w600,
        ),
      ),
    ),
    inputDecorationTheme: InputDecorationTheme(
      filled: true,
      fillColor: FarmlyColors.surface,
      hintStyle: const TextStyle(
        fontFamily: 'Be Vietnam Pro',
        fontSize: 14,
        color: FarmlyColors.textSecondary,
      ),
      labelStyle: const TextStyle(
        fontFamily: 'Be Vietnam Pro',
        fontSize: 14,
        color: FarmlyColors.textSecondary,
      ),
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(FarmSpacing.inputRadius),
        borderSide: const BorderSide(color: FarmlyColors.divider),
      ),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(FarmSpacing.inputRadius),
        borderSide: const BorderSide(color: FarmlyColors.divider),
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(FarmSpacing.inputRadius),
        borderSide: const BorderSide(color: FarmlyColors.brandAction, width: 2),
      ),
      errorBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(FarmSpacing.inputRadius),
        borderSide: const BorderSide(color: FarmlyColors.semanticError),
      ),
      focusedErrorBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(FarmSpacing.inputRadius),
        borderSide: const BorderSide(
          color: FarmlyColors.semanticError,
          width: 2,
        ),
      ),
      contentPadding: const EdgeInsets.symmetric(
        horizontal: FarmSpacing.lg,
        vertical: FarmSpacing.md,
      ),
    ),
    dividerTheme: const DividerThemeData(
      color: FarmlyColors.divider,
      thickness: 1,
      space: 1,
    ),
    checkboxTheme: CheckboxThemeData(
      fillColor: const WidgetStatePropertyAll(FarmlyColors.brandAction),
      checkColor: const WidgetStatePropertyAll(FarmlyColors.onAction),
      side: const BorderSide(color: FarmlyColors.divider, width: 2),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(FarmSpacing.xs),
      ),
    ),
    chipTheme: const ChipThemeData(
      backgroundColor: FarmlyColors.surface,
      selectedColor: FarmlyColors.brandAction,
      secondarySelectedColor: FarmlyColors.brandSage,
      disabledColor: FarmlyColors.background,
      checkmarkColor: FarmlyColors.onAction,
      // M3 chips default to a 32dp height; this SDK derives the chip height
      // from _kChipHeight + label padding, so labelPadding with an 8dp
      // vertical brings every chip to the §8 48dp touch target.
      labelPadding: EdgeInsets.symmetric(
        horizontal: FarmSpacing.sm,
        vertical: FarmSpacing.sm,
      ),
      labelStyle: TextStyle(
        fontFamily: 'Be Vietnam Pro',
        fontSize: 12,
        fontWeight: FontWeight.w500,
        color: FarmlyColors.textPrimary,
      ),
      secondaryLabelStyle: TextStyle(
        fontFamily: 'Be Vietnam Pro',
        fontSize: 12,
        fontWeight: FontWeight.w500,
        color: FarmlyColors.textPrimary,
      ),
      side: BorderSide(color: FarmlyColors.divider),
      shape: StadiumBorder(),
      padding: EdgeInsets.symmetric(
        horizontal: FarmSpacing.md,
        vertical: FarmSpacing.xs,
      ),
    ),
    progressIndicatorTheme: const ProgressIndicatorThemeData(
      color: FarmlyColors.brandAction,
      linearTrackColor: FarmlyColors.brandSage,
      circularTrackColor: FarmlyColors.brandSage,
    ),
    snackBarTheme: SnackBarThemeData(
      backgroundColor: FarmlyColors.textPrimary,
      contentTextStyle: const TextStyle(
        fontFamily: 'Be Vietnam Pro',
        fontSize: 14,
        color: FarmlyColors.surface,
      ),
      // Snackbar body sits on textPrimary (dark ink); the action label uses
      // the light onAction ink. brand.sage is fill/track only, never text
      // (spec 02 §2).
      actionTextColor: FarmlyColors.onAction,
      behavior: SnackBarBehavior.floating,
      elevation: 0,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(FarmSpacing.md),
      ),
    ),
    listTileTheme: const ListTileThemeData(
      iconColor: FarmlyColors.textPrimary,
      textColor: FarmlyColors.textPrimary,
      contentPadding: EdgeInsets.symmetric(horizontal: FarmSpacing.lg),
    ),
  );
}

/// Fixed type scale 12 / 14 / 16 / 20 / 24 / 32 with weights 400-700 only.
/// Heights keep body copy inside the 1.45-1.6 band; no size is ever clamped
/// or downscaled to dodge large text scaling.
TextTheme _farmTextTheme(TextTheme base) {
  TextStyle scale(
    TextStyle? style,
    double fontSize,
    FontWeight weight,
    double height,
  ) => (style ?? const TextStyle()).copyWith(
    fontSize: fontSize,
    fontWeight: weight,
    height: height,
    color: style?.color,
  );

  return base.copyWith(
    displaySmall: scale(base.displaySmall, 32, FontWeight.w600, 1.2),
    headlineMedium: scale(base.headlineMedium, 24, FontWeight.w600, 1.25),
    headlineSmall: scale(base.headlineSmall, 24, FontWeight.w600, 1.25),
    titleLarge: scale(base.titleLarge, 20, FontWeight.w600, 1.3),
    titleMedium: scale(base.titleMedium, 16, FontWeight.w600, 1.35),
    titleSmall: scale(base.titleSmall, 14, FontWeight.w600, 1.4),
    bodyLarge: scale(base.bodyLarge, 16, FontWeight.w400, 1.5),
    bodyMedium: scale(base.bodyMedium, 14, FontWeight.w400, 1.45),
    bodySmall: scale(base.bodySmall, 12, FontWeight.w400, 1.45),
    labelLarge: scale(base.labelLarge, 14, FontWeight.w600, 1.4),
    labelMedium: scale(base.labelMedium, 12, FontWeight.w500, 1.45),
    labelSmall: scale(base.labelSmall, 12, FontWeight.w400, 1.45),
  );
}
