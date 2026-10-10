import 'package:flutter/material.dart';

/// Spacing, radius and motion constants (spec 02 §2).
abstract final class FarmSpacing {
  static const double xs = 4;
  static const double sm = 8;
  static const double md = 12;
  static const double lg = 16;
  static const double xl = 20;
  static const double xxl = 24;
  static const double xxxl = 32;
  static const double huge = 48;

  static const double cardRadius = 20;
  static const double sheetTopRadius = 28;
  static const double inputRadius = 12;
  static const double minTouchTarget = 48;

  /// Press feedback.
  static const Duration press = Duration(milliseconds: 100);

  /// State / menu transitions.
  static const Duration state = Duration(milliseconds: 200);

  /// Zone zoom / shared element transition, bounded.
  static const Duration zoneZoom = Duration(milliseconds: 300);

  /// Screen/element entrance — fade + short rise.
  static const Duration entrance = Duration(milliseconds: 350);

  /// Ambient loop period (cloud drift, water ripple) — slow and subtle.
  static const Duration ambient = Duration(seconds: 9);
}

/// Motion helpers honoring the platform reduced-motion setting: durations
/// collapse to zero and shimmers render as static placeholders.
extension FarmMotionContext on BuildContext {
  bool farmReducedMotion() => MediaQuery.maybeDisableAnimationsOf(this) ?? false;

  Duration farmPressDuration() =>
      farmReducedMotion() ? Duration.zero : FarmSpacing.press;

  Duration farmStateDuration() =>
      farmReducedMotion() ? Duration.zero : FarmSpacing.state;

  Duration farmZoneZoomDuration() =>
      farmReducedMotion() ? Duration.zero : FarmSpacing.zoneZoom;
}
