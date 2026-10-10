import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../core/theme/farmly_colors.dart';
import '../features/demo/demo_models.dart';

/// Lawful, hand-drawn Farmly artwork. Everything is painted with the canonical
/// token palette via [FarmlyColors]; no licensed imagery and no emoji glyphs.
/// Illustrations are decorative: callers exclude them from the semantics tree.

/// Rolling hills + barn + silo + trees + sky scene (splash, login header,
/// empty farm, explorer). Composition follows the approved Farmly reference:
/// blue-sky band with sun/clouds/birds, layered green hills, red barn with a
/// gray silo, rounded trees, and cream field rows in the foreground.
class FarmScenePainter extends CustomPainter {
  const FarmScenePainter({
    this.showBarn = true,
    this.showSun = true,
    this.phase = 0,
  });

  final bool showBarn;
  final bool showSun;

  /// Ambient phase 0..1 — clouds drift right-to-left and birds bob. Painted
  /// scenes that pass a changing phase must set [shouldRepaint] accordingly.
  final double phase;

  @override
  void paint(Canvas canvas, Size size) {
    final w = size.width;
    final h = size.height;
    final horizon = h * 0.68;

    // Sky — light blue softening toward the horizon cream.
    final skyPaint = Paint()
      ..shader = LinearGradient(
        begin: Alignment.topCenter,
        end: Alignment.bottomCenter,
        colors: [
          FarmlyColors.illustrationSky,
          Color.lerp(
            FarmlyColors.illustrationSky,
            FarmlyColors.background,
            0.55,
          )!,
        ],
      ).createShader(Rect.fromLTWH(0, 0, w, horizon));
    canvas.drawRect(Rect.fromLTWH(0, 0, w, horizon), skyPaint);

    if (showSun) {
      final breathe = 1 + math.sin(phase * 2 * math.pi) * 0.05;
      _paintSun(canvas, Offset(w * 0.8, h * 0.16), h * 0.075 * breathe);
    }
    // Phase 0 reproduces the static reference layout exactly (goldens stay
    // stable); drift moves clouds right, wrapping past the right edge.
    double wrapX(double base) {
      final x = base + phase * w * 0.22;
      return x > w * 1.15 ? x - w * 1.35 : x;
    }

    _paintCloud(canvas, Offset(wrapX(w * 0.18), h * 0.13), w * 0.16);
    _paintCloud(canvas, Offset(wrapX(w * 0.55), h * 0.08), w * 0.11);
    _paintCloud(canvas, Offset(wrapX(w * 0.9), h * 0.16), w * 0.09);
    _paintBirds(
      canvas,
      Offset(
        w * 0.36 + phase * w * 0.07,
        h * 0.18 + math.sin(phase * 2 * math.pi) * h * 0.012,
      ),
      h * 0.05,
    );

    // Far hill band (lighter sage) then near hill (darker).
    final farHill = Paint()
      ..color = Color.lerp(
        FarmlyColors.brandSage,
        FarmlyColors.background,
        0.3,
      )!;
    canvas.drawOval(
      Rect.fromCenter(
        center: Offset(w * 0.22, horizon + h * 0.1),
        width: w * 1.15,
        height: h * 0.5,
      ),
      farHill,
    );
    final midHill = Paint()..color = FarmlyColors.brandSage;
    canvas.drawOval(
      Rect.fromCenter(
        center: Offset(w * 0.78, horizon + h * 0.12),
        width: w * 1.1,
        height: h * 0.52,
      ),
      midHill,
    );

    // Ground strip + ploughed field rows (reference foreground).
    canvas.drawRect(
      Rect.fromLTWH(0, horizon, w, h - horizon),
      Paint()
        ..color = Color.lerp(
          FarmlyColors.brandSage,
          FarmlyColors.background,
          0.42,
        )!,
    );
    final rowPaint = Paint()
      ..color = Color.lerp(
        FarmlyColors.brandSage,
        FarmlyColors.textPrimary,
        0.12,
      )!
      ..strokeWidth = h * 0.02
      ..strokeCap = StrokeCap.round;
    for (var i = 0; i < 3; i++) {
      final y = horizon + h * (0.09 + i * 0.075);
      canvas.drawLine(Offset(w * 0.04, y), Offset(w * 0.62, y + h * 0.02), rowPaint);
    }

    if (showBarn) {
      _paintSilo(canvas, Offset(w * 0.8, horizon - h * 0.02), h * 0.34, w * 0.07);
      _paintBarn(canvas, Offset(w * 0.66, horizon), h * 0.3, w * 0.22);
    }
    _paintTree(canvas, Offset(w * 0.1, horizon - h * 0.01), h * 0.16, w * 0.1);
    _paintTree(canvas, Offset(w * 0.92, horizon), h * 0.14, w * 0.09);
    _paintPine(canvas, Offset(w * 0.36, horizon + h * 0.01), h * 0.14, w * 0.06);
  }

  void _paintSun(Canvas canvas, Offset center, double r) {
    canvas.drawCircle(
      center,
      r * 1.7,
      Paint()
        ..color = Color.lerp(
          FarmlyColors.semanticWarning,
          FarmlyColors.surface,
          0.75,
        )!.withValues(alpha: 0.4),
    );
    canvas.drawCircle(
      center,
      r,
      Paint()
        ..color = Color.lerp(
          FarmlyColors.semanticWarning,
          FarmlyColors.surface,
          0.75,
        )!,
    );
  }

  void _paintCloud(Canvas canvas, Offset center, double w) {
    final cloud = Paint()
      ..color = FarmlyColors.surface.withValues(alpha: 0.9);
    canvas.drawOval(
      Rect.fromCenter(center: center, width: w, height: w * 0.42),
      cloud,
    );
    canvas.drawOval(
      Rect.fromCenter(
        center: center + Offset(w * 0.24, -w * 0.12),
        width: w * 0.62,
        height: w * 0.34,
      ),
      cloud,
    );
  }

  void _paintBirds(Canvas canvas, Offset origin, double s) {
    final bird = Paint()
      ..color = FarmlyColors.textPrimary.withValues(alpha: 0.55)
      ..style = PaintingStyle.stroke
      ..strokeWidth = s * 0.14
      ..strokeCap = StrokeCap.round;
    for (var i = 0; i < 3; i++) {
      final c = origin + Offset(s * i * 1.7, (i.isOdd ? -s * 0.5 : 0));
      final path = Path()
        ..moveTo(c.dx - s * 0.5, c.dy)
        ..quadraticBezierTo(c.dx - s * 0.2, c.dy - s * 0.55, c.dx, c.dy)
        ..quadraticBezierTo(c.dx + s * 0.2, c.dy - s * 0.55, c.dx + s * 0.5, c.dy);
      canvas.drawPath(path, bird);
    }
  }

  void _paintTree(Canvas canvas, Offset base, double height, double width) {
    final trunk = Paint()
      ..color = Color.lerp(
        FarmlyColors.semanticWarning,
        FarmlyColors.textPrimary,
        0.35,
      )!;
    canvas.drawRect(
      Rect.fromLTWH(
        base.dx - width * 0.07,
        base.dy - height * 0.42,
        width * 0.14,
        height * 0.42,
      ),
      trunk,
    );
    final canopy = Paint()
      ..color = Color.lerp(
        FarmlyColors.brandSage,
        FarmlyColors.brandAction,
        0.3,
      )!;
    canvas.drawCircle(Offset(base.dx, base.dy - height * 0.62), height * 0.32, canopy);
    canvas.drawCircle(
      Offset(base.dx - width * 0.24, base.dy - height * 0.45),
      height * 0.22,
      canopy,
    );
    canvas.drawCircle(
      Offset(base.dx + width * 0.24, base.dy - height * 0.45),
      height * 0.22,
      canopy,
    );
  }

  void _paintPine(Canvas canvas, Offset base, double height, double width) {
    final pine = Paint()
      ..color = Color.lerp(
        FarmlyColors.brandAction,
        FarmlyColors.textPrimary,
        0.18,
      )!;
    for (var i = 0; i < 3; i++) {
      final tierW = width * (1 - i * 0.22);
      final top = base.dy - height * (0.55 + i * 0.18);
      final path = Path()
        ..moveTo(base.dx, top)
        ..lineTo(base.dx - tierW / 2, top + height * 0.32)
        ..lineTo(base.dx + tierW / 2, top + height * 0.32)
        ..close();
      canvas.drawPath(path, pine);
    }
  }

  void _paintSilo(Canvas canvas, Offset base, double height, double width) {
    final silo = Paint()
      ..color = Color.lerp(
        FarmlyColors.textSecondary,
        FarmlyColors.surface,
        0.5,
      )!;
    canvas.drawRect(
      Rect.fromLTWH(base.dx - width / 2, base.dy - height, width, height),
      silo,
    );
    canvas.drawOval(
      Rect.fromCenter(
        center: Offset(base.dx, base.dy - height),
        width: width,
        height: width * 0.9,
      ),
      Paint()
        ..color = Color.lerp(
          FarmlyColors.textSecondary,
          FarmlyColors.surface,
          0.3,
        )!,
    );
  }

  void _paintBarn(Canvas canvas, Offset base, double height, double width) {
    // Gambrel silhouette: roof slope break at ~60% of the wall height.
    final barn = Path()
      ..moveTo(base.dx - width / 2, base.dy)
      ..lineTo(base.dx - width / 2, base.dy - height * 0.52)
      ..lineTo(base.dx - width * 0.3, base.dy - height * 0.88)
      ..lineTo(base.dx, base.dy - height)
      ..lineTo(base.dx + width * 0.3, base.dy - height * 0.88)
      ..lineTo(base.dx + width / 2, base.dy - height * 0.52)
      ..lineTo(base.dx + width / 2, base.dy)
      ..close();
    canvas.drawPath(barn, Paint()..color = FarmlyColors.illustrationBarn);

    // White roof cap following the gambrel peak.
    final roofLine = Paint()
      ..color = FarmlyColors.surface
      ..style = PaintingStyle.stroke
      ..strokeWidth = height * 0.07
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round;
    canvas.drawPath(
      Path()
        ..moveTo(base.dx - width * 0.34, base.dy - height * 0.86)
        ..lineTo(base.dx, base.dy - height * 0.99)
        ..lineTo(base.dx + width * 0.34, base.dy - height * 0.86),
      roofLine,
    );

    // Door with the reference X brace.
    final doorRect = Rect.fromCenter(
      center: Offset(base.dx, base.dy - height * 0.24),
      width: width * 0.34,
      height: height * 0.48,
    );
    canvas.drawRect(doorRect, Paint()..color = FarmlyColors.surface);
    final brace = Paint()
      ..color = FarmlyColors.illustrationBarn
      ..strokeWidth = height * 0.035
      ..strokeCap = StrokeCap.round;
    canvas.drawLine(doorRect.topLeft, doorRect.bottomRight, brace);
    canvas.drawLine(doorRect.topRight, doorRect.bottomLeft, brace);

    // Hayloft opening.
    canvas.drawOval(
      Rect.fromCenter(
        center: Offset(base.dx, base.dy - height * 0.68),
        width: width * 0.16,
        height: width * 0.16,
      ),
      Paint()..color = FarmlyColors.surface,
    );
  }

  @override
  bool shouldRepaint(FarmScenePainter oldDelegate) =>
      oldDelegate.showBarn != showBarn ||
      oldDelegate.showSun != showSun ||
      oldDelegate.phase != phase;
}

/// Sprout logo mark: stem plus two leaves.
class SproutPainter extends CustomPainter {
  const SproutPainter();

  @override
  void paint(Canvas canvas, Size size) {
    final w = size.width;
    final h = size.height;
    final stem = Paint()
      ..color = FarmlyColors.brandAction
      ..strokeWidth = h * 0.09
      ..strokeCap = StrokeCap.round
      ..style = PaintingStyle.stroke;
    final leaf = Paint()..color = FarmlyColors.brandSage;

    canvas.drawLine(Offset(w * 0.5, h * 0.95), Offset(w * 0.5, h * 0.45), stem);

    canvas.drawOval(
      Rect.fromCenter(
        center: Offset(w * 0.28, h * 0.36),
        width: w * 0.46,
        height: h * 0.34,
      ),
      leaf,
    );
    canvas.drawOval(
      Rect.fromCenter(
        center: Offset(w * 0.74, h * 0.26),
        width: w * 0.42,
        height: h * 0.3,
      ),
      leaf,
    );
  }

  @override
  bool shouldRepaint(SproutPainter oldDelegate) => false;
}

/// Focused crop bed with planting rows (crop zone detail).
class BedPainter extends CustomPainter {
  const BedPainter();

  @override
  void paint(Canvas canvas, Size size) {
    final w = size.width;
    final h = size.height;

    canvas.drawRect(
      Rect.fromLTWH(0, 0, w, h),
      Paint()..color = FarmlyColors.illustrationSky.withValues(alpha: 0.35),
    );

    final soil = Paint()..color = FarmlyColors.semanticWarning;
    final bed = RRect.fromRectAndRadius(
      Rect.fromLTWH(w * 0.08, h * 0.4, w * 0.84, h * 0.48),
      Radius.circular(h * 0.1),
    );
    canvas.drawRRect(bed, soil);

    final stem = Paint()
      ..color = FarmlyColors.brandAction
      ..strokeWidth = h * 0.03
      ..strokeCap = StrokeCap.round;
    final leaf = Paint()..color = FarmlyColors.brandSage;
    for (var row = 0; row < 2; row++) {
      for (var i = 0; i < 5; i++) {
        final cx = w * (0.18 + i * 0.16);
        final cy = h * (0.55 + row * 0.22);
        canvas.drawLine(Offset(cx, cy), Offset(cx, cy - h * 0.12), stem);
        canvas.drawCircle(Offset(cx - h * 0.05, cy - h * 0.14), h * 0.045, leaf);
        canvas.drawCircle(Offset(cx + h * 0.05, cy - h * 0.14), h * 0.045, leaf);
      }
    }
  }

  @override
  bool shouldRepaint(BedPainter oldDelegate) => false;
}

/// Water tank illustration for a water zone detail (phase 05 step 5).
/// Lawful redrawn artwork — tank body, water line, pipe.
class WaterTankPainter extends CustomPainter {
  const WaterTankPainter();

  @override
  void paint(Canvas canvas, Size size) {
    final w = size.width;
    final h = size.height;

    canvas.drawRect(
      Rect.fromLTWH(0, 0, w, h),
      Paint()..color = FarmlyColors.illustrationSky.withValues(alpha: 0.35),
    );

    final groundY = h * 0.82;
    canvas.drawOval(
      Rect.fromLTWH(0, groundY - h * 0.08, w, h * 0.16),
      Paint()..color = FarmlyColors.brandSage.withValues(alpha: 0.5),
    );

    // Tank body: rounded cylinder with a visible water line.
    final body = RRect.fromRectAndRadius(
      Rect.fromLTWH(w * 0.3, h * 0.2, w * 0.4, h * 0.6),
      Radius.circular(w * 0.06),
    );
    canvas.drawRRect(body, Paint()..color = FarmlyColors.surface);
    canvas.drawRRect(
      body,
      Paint()
        ..color = FarmlyColors.textSecondary
        ..style = PaintingStyle.stroke
        ..strokeWidth = h * 0.015,
    );
    canvas.drawRRect(
      RRect.fromRectAndRadius(
        Rect.fromLTWH(w * 0.3, h * 0.48, w * 0.4, h * 0.32),
        Radius.circular(w * 0.06),
      ),
      Paint()..color = FarmlyColors.illustrationWater.withValues(alpha: 0.6),
    );
    canvas.drawOval(
      Rect.fromLTWH(w * 0.42, h * 0.1, w * 0.16, h * 0.12),
      Paint()..color = FarmlyColors.textSecondary.withValues(alpha: 0.4),
    );

    // Inlet pipe.
    canvas.drawRect(
      Rect.fromLTWH(w * 0.72, h * 0.32, w * 0.14, h * 0.06),
      Paint()..color = FarmlyColors.textSecondary.withValues(alpha: 0.35),
    );
  }

  @override
  bool shouldRepaint(WaterTankPainter oldDelegate) => false;
}

/// Cartoon animal portrait drawn from geometry only (no photography).
class AnimalPortraitPainter extends CustomPainter {
  const AnimalPortraitPainter({required this.category});

  final DemoAnimalCategory category;

  @override
  void paint(Canvas canvas, Size size) {
    final w = size.width;
    final h = size.height;
    final face = Paint()..color = FarmlyColors.surface;
    final outline = Paint()
      ..color = FarmlyColors.textSecondary
      ..style = PaintingStyle.stroke
      ..strokeWidth = h * 0.03;
    final faceRect = Rect.fromCenter(
      center: Offset(w * 0.5, h * 0.55),
      width: w * 0.62,
      height: h * 0.62,
    );

    switch (category) {
      case DemoAnimalCategory.cows:
        canvas.drawOval(faceRect, face);
        canvas.drawOval(faceRect, outline);
        final patch = Paint()..color = FarmlyColors.brandSage;
        canvas.drawCircle(Offset(w * 0.62, h * 0.45), h * 0.12, patch);
        _ears(canvas, w, h);
        final horn = Paint()
          ..color = FarmlyColors.semanticWarning
          ..strokeWidth = h * 0.05
          ..strokeCap = StrokeCap.round;
        canvas.drawLine(
          Offset(w * 0.34, h * 0.28),
          Offset(w * 0.24, h * 0.14),
          horn,
        );
        canvas.drawLine(
          Offset(w * 0.66, h * 0.28),
          Offset(w * 0.76, h * 0.14),
          horn,
        );
      case DemoAnimalCategory.chickens:
        canvas.drawOval(faceRect, face);
        canvas.drawOval(faceRect, outline);
        final comb = Paint()..color = FarmlyColors.illustrationBarn;
        canvas.drawCircle(Offset(w * 0.42, h * 0.24), h * 0.07, comb);
        canvas.drawCircle(Offset(w * 0.58, h * 0.22), h * 0.07, comb);
        final beak = Paint()..color = FarmlyColors.semanticWarning;
        canvas.drawTriangle(
          Offset(w * 0.5, h * 0.62),
          w * 0.16,
          h * 0.12,
          beak,
        );
      case DemoAnimalCategory.sheep:
        final wool = Paint()..color = FarmlyColors.brandSage;
        canvas.drawCircle(Offset(w * 0.5, h * 0.52), h * 0.36, wool);
        canvas.drawOval(faceRect, face);
        canvas.drawOval(faceRect, outline);
        _ears(canvas, w, h);
      case DemoAnimalCategory.goats:
        canvas.drawOval(faceRect, face);
        canvas.drawOval(faceRect, outline);
        _ears(canvas, w, h);
        final horn = Paint()
          ..color = FarmlyColors.semanticWarning
          ..strokeWidth = h * 0.05
          ..strokeCap = StrokeCap.round;
        canvas.drawLine(
          Offset(w * 0.38, h * 0.3),
          Offset(w * 0.28, h * 0.12),
          horn,
        );
        canvas.drawLine(
          Offset(w * 0.62, h * 0.3),
          Offset(w * 0.72, h * 0.12),
          horn,
        );
    }

    final eye = Paint()..color = FarmlyColors.textPrimary;
    canvas.drawCircle(Offset(w * 0.4, h * 0.5), h * 0.045, eye);
    canvas.drawCircle(Offset(w * 0.6, h * 0.5), h * 0.045, eye);
  }

  void _ears(Canvas canvas, double w, double h) {
    final ear = Paint()..color = FarmlyColors.brandSage;
    canvas.drawOval(
      Rect.fromCenter(
        center: Offset(w * 0.16, h * 0.44),
        width: w * 0.22,
        height: h * 0.12,
      ),
      ear,
    );
    canvas.drawOval(
      Rect.fromCenter(
        center: Offset(w * 0.84, h * 0.44),
        width: w * 0.22,
        height: h * 0.12,
      ),
      ear,
    );
  }

  @override
  bool shouldRepaint(AnimalPortraitPainter oldDelegate) =>
      oldDelegate.category != category;
}

extension on Canvas {
  void drawTriangle(Offset tip, double width, double height, Paint paint) {
    final path = Path()
      ..moveTo(tip.dx - width / 2, tip.dy - height)
      ..lineTo(tip.dx + width / 2, tip.dy - height)
      ..lineTo(tip.dx, tip.dy)
      ..close();
    drawPath(path, paint);
  }
}

/// Decorative wrappers. When [semanticLabel] is null the artwork is excluded
/// from the semantics tree entirely (spec 02 §4).
class FarmIllustration extends StatelessWidget {
  const FarmIllustration({
    required this.painter,
    this.semanticLabel,
    this.aspectRatio = 2,
    super.key,
  });

  final CustomPainter painter;
  final String? semanticLabel;
  final double aspectRatio;

  @override
  Widget build(BuildContext context) {
    final content = AspectRatio(
      aspectRatio: aspectRatio,
      child: CustomPaint(painter: painter),
    );
    if (semanticLabel == null) {
      return ExcludeSemantics(child: content);
    }
    return Semantics(
      label: semanticLabel,
      child: content,
    );
  }
}

/// Empty-farm artwork: quiet scene without animals, plus a sprout.
class EmptyFarmIllustration extends StatelessWidget {
  const EmptyFarmIllustration({this.semanticLabel, super.key});

  final String? semanticLabel;

  @override
  Widget build(BuildContext context) {
    return FarmIllustration(
      painter: const FarmScenePainter(),
      semanticLabel: semanticLabel,
      aspectRatio: 1.9,
    );
  }
}

/// Sprout logo mark.
class SproutMark extends StatelessWidget {
  const SproutMark({this.size = 48, this.semanticLabel, super.key});

  final double size;
  final String? semanticLabel;

  @override
  Widget build(BuildContext context) {
    final content = SizedBox.square(
      dimension: size,
      child: const CustomPaint(painter: SproutPainter()),
    );
    if (semanticLabel == null) {
      return ExcludeSemantics(child: content);
    }
    return Semantics(label: semanticLabel, child: content);
  }
}

/// Cartoon animal portrait card visual.
class AnimalPortrait extends StatelessWidget {
  const AnimalPortrait({
    required this.category,
    this.size = 56,
    super.key,
  });

  final DemoAnimalCategory category;
  final double size;

  @override
  Widget build(BuildContext context) {
    return ExcludeSemantics(
      child: SizedBox.square(
        dimension: size,
        child: CustomPaint(painter: AnimalPortraitPainter(category: category)),
      ),
    );
  }
}
