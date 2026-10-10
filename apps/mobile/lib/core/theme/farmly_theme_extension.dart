import 'package:flutter/material.dart';

/// Farmly semantic tokens exposed to widgets through the theme, so screens
/// never hard-code hex values (spec 02 §4).
@immutable
class FarmThemeExtension extends ThemeExtension<FarmThemeExtension> {
  const FarmThemeExtension({
    required this.background,
    required this.surface,
    required this.textPrimary,
    required this.textSecondary,
    required this.brandAction,
    required this.brandSage,
    required this.illustrationSky,
    required this.illustrationBarn,
    required this.semanticWarning,
    required this.semanticError,
    required this.divider,
    required this.onAction,
    required this.cardRadius,
    required this.sheetTopRadius,
    required this.pressDuration,
    required this.stateDuration,
    required this.zoneZoomDuration,
  });

  final Color background;
  final Color surface;
  final Color textPrimary;
  final Color textSecondary;
  final Color brandAction;
  final Color brandSage;
  final Color illustrationSky;
  final Color illustrationBarn;
  final Color semanticWarning;
  final Color semanticError;
  final Color divider;
  final Color onAction;
  final double cardRadius;
  final double sheetTopRadius;
  final Duration pressDuration;
  final Duration stateDuration;
  final Duration zoneZoomDuration;

  static FarmThemeExtension of(BuildContext context) =>
      Theme.of(context).extension<FarmThemeExtension>()!;

  @override
  FarmThemeExtension copyWith({
    Color? background,
    Color? surface,
    Color? textPrimary,
    Color? textSecondary,
    Color? brandAction,
    Color? brandSage,
    Color? illustrationSky,
    Color? illustrationBarn,
    Color? semanticWarning,
    Color? semanticError,
    Color? divider,
    Color? onAction,
    double? cardRadius,
    double? sheetTopRadius,
    Duration? pressDuration,
    Duration? stateDuration,
    Duration? zoneZoomDuration,
  }) {
    return FarmThemeExtension(
      background: background ?? this.background,
      surface: surface ?? this.surface,
      textPrimary: textPrimary ?? this.textPrimary,
      textSecondary: textSecondary ?? this.textSecondary,
      brandAction: brandAction ?? this.brandAction,
      brandSage: brandSage ?? this.brandSage,
      illustrationSky: illustrationSky ?? this.illustrationSky,
      illustrationBarn: illustrationBarn ?? this.illustrationBarn,
      semanticWarning: semanticWarning ?? this.semanticWarning,
      semanticError: semanticError ?? this.semanticError,
      divider: divider ?? this.divider,
      onAction: onAction ?? this.onAction,
      cardRadius: cardRadius ?? this.cardRadius,
      sheetTopRadius: sheetTopRadius ?? this.sheetTopRadius,
      pressDuration: pressDuration ?? this.pressDuration,
      stateDuration: stateDuration ?? this.stateDuration,
      zoneZoomDuration: zoneZoomDuration ?? this.zoneZoomDuration,
    );
  }

  @override
  FarmThemeExtension lerp(FarmThemeExtension? other, double t) {
    if (other == null) return this;
    double radius(double a, double b) => a + (b - a) * t;
    Duration duration(Duration a, Duration b) => Duration(
      milliseconds: (a.inMilliseconds + (b.inMilliseconds - a.inMilliseconds) * t)
          .round(),
    );
    return FarmThemeExtension(
      background: Color.lerp(background, other.background, t)!,
      surface: Color.lerp(surface, other.surface, t)!,
      textPrimary: Color.lerp(textPrimary, other.textPrimary, t)!,
      textSecondary: Color.lerp(textSecondary, other.textSecondary, t)!,
      brandAction: Color.lerp(brandAction, other.brandAction, t)!,
      brandSage: Color.lerp(brandSage, other.brandSage, t)!,
      illustrationSky: Color.lerp(illustrationSky, other.illustrationSky, t)!,
      illustrationBarn: Color.lerp(
        illustrationBarn,
        other.illustrationBarn,
        t,
      )!,
      semanticWarning: Color.lerp(
        semanticWarning,
        other.semanticWarning,
        t,
      )!,
      semanticError: Color.lerp(semanticError, other.semanticError, t)!,
      divider: Color.lerp(divider, other.divider, t)!,
      onAction: Color.lerp(onAction, other.onAction, t)!,
      cardRadius: radius(cardRadius, other.cardRadius),
      sheetTopRadius: radius(sheetTopRadius, other.sheetTopRadius),
      pressDuration: duration(pressDuration, other.pressDuration),
      stateDuration: duration(stateDuration, other.stateDuration),
      zoneZoomDuration: duration(zoneZoomDuration, other.zoneZoomDuration),
    );
  }

  @override
  bool operator ==(Object other) {
    return other is FarmThemeExtension &&
        other.background == background &&
        other.surface == surface &&
        other.textPrimary == textPrimary &&
        other.textSecondary == textSecondary &&
        other.brandAction == brandAction &&
        other.brandSage == brandSage &&
        other.illustrationSky == illustrationSky &&
        other.illustrationBarn == illustrationBarn &&
        other.semanticWarning == semanticWarning &&
        other.semanticError == semanticError &&
        other.divider == divider &&
        other.onAction == onAction &&
        other.cardRadius == cardRadius &&
        other.sheetTopRadius == sheetTopRadius &&
        other.pressDuration == pressDuration &&
        other.stateDuration == stateDuration &&
        other.zoneZoomDuration == zoneZoomDuration;
  }

  @override
  int get hashCode => Object.hash(
    background,
    surface,
    textPrimary,
    textSecondary,
    brandAction,
    brandSage,
    illustrationSky,
    illustrationBarn,
    semanticWarning,
    semanticError,
    divider,
    onAction,
    cardRadius,
    sheetTopRadius,
    pressDuration,
    stateDuration,
    zoneZoomDuration,
  );
}
