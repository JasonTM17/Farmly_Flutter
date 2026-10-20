import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../core/theme/farmly_colors.dart';
import '../features/demo/demo_models.dart';
import 'farm_life_painter.dart';
import 'clay_shapes.dart';
import 'farm_structure_painter.dart';

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
      canvas.drawLine(
        Offset(w * 0.04, y),
        Offset(w * 0.62, y + h * 0.02),
        rowPaint,
      );
    }

    if (showBarn) {
      _paintSilo(
        canvas,
        Offset(w * 0.8, horizon - h * 0.02),
        h * 0.34,
        w * 0.07,
      );
      _paintBarn(canvas, Offset(w * 0.66, horizon), h * 0.3, w * 0.22);
    }
    _paintTree(canvas, Offset(w * 0.1, horizon - h * 0.01), h * 0.16, w * 0.1);
    _paintTree(canvas, Offset(w * 0.92, horizon), h * 0.14, w * 0.09);
    _paintPine(
      canvas,
      Offset(w * 0.36, horizon + h * 0.01),
      h * 0.14,
      w * 0.06,
    );
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
    final cloud = Paint()..color = FarmlyColors.surface.withValues(alpha: 0.9);
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
        ..quadraticBezierTo(
          c.dx + s * 0.2,
          c.dy - s * 0.55,
          c.dx + s * 0.5,
          c.dy,
        );
      canvas.drawPath(path, bird);
    }
  }

  void _paintTree(Canvas canvas, Offset base, double height, double width) {
    FarmLifePainter.drawTree(
      canvas,
      ground: base,
      scale: height / 38,
      phase: phase,
      seed: base.dx.round(),
    );
  }

  void _paintPine(Canvas canvas, Offset base, double height, double width) {
    // Layered evergreen clusters share the rounded clay leaf material.
    ClayShapes.shadow(
      canvas,
      base + Offset(width * 0.1, 1),
      width,
      height * 0.12,
    );
    ClayShapes.capsule(
      canvas,
      Rect.fromLTWH(
        base.dx - width * 0.06,
        base.dy - height * 0.5,
        width * 0.12,
        height * 0.5,
      ),
      FarmlyColors.semanticWarning,
    );
    for (var i = 0; i < 3; i++) {
      final y = base.dy - height * (0.38 + i * 0.22);
      final half = width * (0.5 - i * 0.1);
      final path = Path()
        ..moveTo(base.dx - half, y + height * 0.14)
        ..quadraticBezierTo(
          base.dx - half * 0.4,
          y - height * 0.06,
          base.dx,
          y - height * 0.3,
        )
        ..quadraticBezierTo(
          base.dx + half * 0.4,
          y - height * 0.06,
          base.dx + half,
          y + height * 0.14,
        )
        ..quadraticBezierTo(
          base.dx,
          y + height * 0.24,
          base.dx - half,
          y + height * 0.14,
        )
        ..close();
      ClayShapes.form(
        canvas,
        path,
        ClayShapes.light(FarmlyColors.brandAction, i * 0.06),
      );
    }
  }

  void _paintSilo(Canvas canvas, Offset base, double height, double width) {
    FarmStructurePainter.tank(
      canvas,
      bounds: Rect.fromLTWH(
        base.dx - width * 0.8,
        base.dy - height,
        width * 1.6,
        height,
      ),
    );
  }

  void _paintBarn(Canvas canvas, Offset base, double height, double width) {
    FarmStructurePainter.building(
      canvas,
      bounds: Rect.fromLTWH(
        base.dx - width * 0.55,
        base.dy - height * 1.15,
        width * 1.15,
        height * 1.2,
      ),
      kind: FarmStructureKind.barn,
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
      ..strokeWidth = h * 0.08
      ..strokeCap = StrokeCap.round
      ..style = PaintingStyle.stroke;
    canvas.drawPath(
      Path()
        ..moveTo(w * 0.5, h * 0.94)
        ..quadraticBezierTo(w * 0.57, h * 0.56, w * 0.48, h * 0.43),
      stem,
    );
    ClayShapes.leaf(
      canvas,
      Offset(w * 0.5, h * 0.58),
      Offset(w * 0.07, h * 0.18),
      h * 0.3,
      FarmlyColors.brandSage,
    );
    ClayShapes.leaf(
      canvas,
      Offset(w * 0.51, h * 0.48),
      Offset(w * 0.92, h * 0.08),
      h * 0.28,
      ClayShapes.light(FarmlyColors.brandAction, 0.16),
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
      Paint()..color = FarmlyColors.illustrationSky.withValues(alpha: 0.22),
    );
    ClayShapes.shadow(canvas, Offset(w * 0.51, h * 0.87), w * 0.86, h * 0.15);
    final bed = Rect.fromLTWH(w * 0.08, h * 0.4, w * 0.84, h * 0.43);
    canvas.drawRRect(
      RRect.fromRectAndRadius(
        bed.shift(Offset(0, h * 0.06)),
        Radius.circular(h * 0.07),
      ),
      ClayShapes.material(bed, FarmlyColors.semanticWarning),
    );
    canvas.drawRRect(
      RRect.fromRectAndRadius(bed, Radius.circular(h * 0.07)),
      ClayShapes.material(
        bed,
        ClayShapes.light(FarmlyColors.semanticWarning, 0.25),
      ),
    );
    for (var row = 0; row < 2; row++) {
      for (var i = 0; i < 5; i++) {
        FarmLifePainter.drawLeafyPlant(
          canvas,
          ground: Offset(w * (0.17 + i * 0.16), h * (0.59 + row * 0.2)),
          scale: h / 90,
          phase: 0,
          seed: row * 5 + i,
        );
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
      Paint()..color = FarmlyColors.illustrationSky.withValues(alpha: 0.22),
    );
    FarmStructurePainter.tank(
      canvas,
      bounds: Rect.fromLTWH(w * 0.22, h * 0.05, w * 0.56, h * 0.92),
    );
  }

  @override
  bool shouldRepaint(WaterTankPainter oldDelegate) => false;
}

/// Faceted animal portrait drawn from geometry only (no photography).
class AnimalPortraitPainter extends CustomPainter {
  const AnimalPortraitPainter({required this.category, this.phase = 0});

  final DemoAnimalCategory category;
  final double phase;

  @override
  void paint(Canvas canvas, Size size) => FarmLifePainter.drawAnimalPortrait(
    canvas,
    size: size,
    category: category,
    phase: phase,
  );

  @override
  bool shouldRepaint(AnimalPortraitPainter oldDelegate) =>
      oldDelegate.category != category || oldDelegate.phase != phase;
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
    return Semantics(label: semanticLabel, child: content);
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
    this.phase = 0,
    super.key,
  });

  final DemoAnimalCategory category;
  final double size;
  final double phase;

  @override
  Widget build(BuildContext context) {
    return ExcludeSemantics(
      child: SizedBox.square(
        dimension: size,
        child: CustomPaint(
          painter: AnimalPortraitPainter(category: category, phase: phase),
        ),
      ),
    );
  }
}
