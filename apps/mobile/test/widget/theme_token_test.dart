import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:farmly_mobile/core/theme/farm_theme.dart';
import 'package:farmly_mobile/core/theme/farmly_colors.dart';
import 'package:farmly_mobile/core/theme/farmly_spacing.dart';
import 'package:farmly_mobile/core/theme/farmly_theme_extension.dart';

void expectAaContrast(Color foreground, Color background, String label) {
  final foregroundLuminance = foreground.computeLuminance();
  final backgroundLuminance = background.computeLuminance();
  final lighter = foregroundLuminance > backgroundLuminance
      ? foregroundLuminance
      : backgroundLuminance;
  final darker = foregroundLuminance > backgroundLuminance
      ? backgroundLuminance
      : foregroundLuminance;

  expect(
    (lighter + 0.05) / (darker + 0.05),
    greaterThanOrEqualTo(4.5),
    reason: label,
  );
}

void main() {
  test('theme exposes the eleven canonical tokens from spec 02', () {
    final theme = buildFarmTheme();
    final tokens = theme.extension<FarmThemeExtension>();

    expect(tokens, isNotNull);
    expect(tokens!.background, const Color(0xFFF7F5E9));
    expect(tokens.surface, const Color(0xFFFFFEF8));
    expect(tokens.textPrimary, const Color(0xFF263B2C));
    expect(tokens.textSecondary, const Color(0xFF596859));
    expect(tokens.brandAction, const Color(0xFF306748));
    expect(tokens.brandSage, const Color(0xFFA6C2A1));
    expect(tokens.illustrationSky, const Color(0xFFB7DDEC));
    expect(tokens.illustrationBarn, const Color(0xFFBB503D));
    expect(tokens.semanticWarning, const Color(0xFF77531C));
    expect(tokens.semanticError, const Color(0xFFA53535));
    expect(tokens.divider, const Color(0xFFDEDCCD));

    expect(theme.scaffoldBackgroundColor, const Color(0xFFF7F5E9));
    expect(theme.colorScheme.primary, const Color(0xFF306748));
    expect(theme.colorScheme.error, const Color(0xFFA53535));
  });

  test('cards use radius 20, sheets 28 on top and buttons are pill-shaped', () {
    final theme = buildFarmTheme();

    final cardShape = theme.cardTheme.shape! as RoundedRectangleBorder;
    expect(
      cardShape.borderRadius,
      BorderRadius.circular(FarmSpacing.cardRadius),
    );
    // User-approved clay presentation keeps depth subtle and explicit.
    expect(theme.cardTheme.elevation, 2);
    expect(theme.bottomSheetTheme.elevation, 7);
    expect(theme.dialogTheme.elevation, 5);
    expect(
      theme.filledButtonTheme.style!.elevation!.resolve(<WidgetState>{}),
      2,
    );

    final sheetShape = theme.bottomSheetTheme.shape! as RoundedRectangleBorder;
    expect(
      sheetShape.borderRadius,
      const BorderRadius.vertical(
        top: Radius.circular(FarmSpacing.sheetTopRadius),
      ),
    );

    final filledShape = theme.filledButtonTheme.style!.shape!.resolve(
      <WidgetState>{},
    );
    expect(filledShape, isA<StadiumBorder>());
    final minimumSize = theme.filledButtonTheme.style!.minimumSize!.resolve(
      <WidgetState>{},
    );
    expect(
      minimumSize!.height,
      greaterThanOrEqualTo(FarmSpacing.minTouchTarget),
    );
  });

  test('motion tokens match press 100ms, state 200ms, zone zoom 300ms', () {
    final tokens = buildFarmTheme().extension<FarmThemeExtension>()!;
    expect(tokens.pressDuration, const Duration(milliseconds: 100));
    expect(tokens.stateDuration.inMilliseconds, inInclusiveRange(180, 240));
    expect(tokens.zoneZoomDuration.inMilliseconds, inInclusiveRange(280, 360));
  });

  test(
    'type scale is fixed at 12/14/16/20/24/32 with body height 1.45-1.6',
    () {
      final textTheme = buildFarmTheme().textTheme;
      final bodyLarge = textTheme.bodyLarge!;
      final fontFamily = bodyLarge.fontFamily;

      expect(fontFamily, 'Be Vietnam Pro');
      expect(textTheme.bodySmall!.fontSize, 12);
      expect(textTheme.bodyMedium!.fontSize, 14);
      expect(bodyLarge.fontSize, 16);
      expect(textTheme.titleLarge!.fontSize, 20);
      expect(textTheme.headlineMedium!.fontSize, 24);
      expect(textTheme.displaySmall!.fontSize, 32);
      expect(bodyLarge.height!, inInclusiveRange(1.45, 1.6));
      final weights = <int>[
        bodyLarge.fontWeight!.value,
        textTheme.titleMedium!.fontWeight!.value,
        textTheme.labelLarge!.fontWeight!.value,
        textTheme.headlineMedium!.fontWeight!.value,
      ];
      for (final weight in weights) {
        expect(weight, anyOf(400, 500, 600, 700));
      }
    },
  );

  test('semantic text colors meet WCAG AA on both app surfaces', () {
    for (final surface in <Color>[
      FarmlyColors.background,
      FarmlyColors.surface,
    ]) {
      expectAaContrast(FarmlyColors.textPrimary, surface, 'primary text');
      expectAaContrast(FarmlyColors.textSecondary, surface, 'secondary text');
      expectAaContrast(FarmlyColors.brandAction, surface, 'action text');
      expectAaContrast(FarmlyColors.semanticWarning, surface, 'warning text');
      expectAaContrast(FarmlyColors.semanticError, surface, 'error text');
    }
    expectAaContrast(
      FarmlyColors.onAction,
      FarmlyColors.brandAction,
      'text on action controls',
    );
  });
}
