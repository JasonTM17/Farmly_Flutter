import 'package:flutter/material.dart';

/// The eleven canonical Farmly color tokens (spec `02-ui-ux-screen-contract.md`
/// §2). Screen code must read colors from here or from [FarmThemeExtension];
/// no ad-hoc hex literals inside screens.
abstract final class FarmlyColors {
  /// Cream scaffold background.
  static const Color background = Color(0xFFF7F5E9);

  /// Card / sheet surface.
  static const Color surface = Color(0xFFFFFEF8);

  /// Dark organic ink for primary text.
  static const Color textPrimary = Color(0xFF263B2C);

  /// Secondary labels and as-of metadata; never as an opacity gray.
  static const Color textSecondary = Color(0xFF596859);

  /// CTA and active selection color.
  static const Color brandAction = Color(0xFF306748);

  /// Secondary fill / track only; never body text.
  static const Color brandSage = Color(0xFFA6C2A1);

  /// Hero sky (artwork only).
  static const Color illustrationSky = Color(0xFFB7DDEC);

  /// Artwork only.
  static const Color illustrationBarn = Color(0xFFBB503D);

  /// Artwork only — tank water body.
  static const Color illustrationWater = Color(0xFF4E9CC9);

  /// Warning text / icon.
  static const Color semanticWarning = Color(0xFF77531C);

  /// Error text / icon.
  static const Color semanticError = Color(0xFFA53535);

  /// Surface hairline.
  static const Color divider = Color(0xFFDEDCCD);

  /// Ink on action-colored surfaces; reuses the surface token (6.58:1 on
  /// brand.action) so no fourth neutral hex enters the palette.
  static const Color onAction = surface;
}
