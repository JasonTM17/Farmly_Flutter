import 'package:flutter/material.dart';

import '../core/theme/farmly_colors.dart';
import '../features/demo/demo_models.dart';

/// Lawful, hand-drawn Farmly artwork. Everything is painted with the canonical
/// token palette via [FarmlyColors]; no licensed imagery and no emoji glyphs.
/// Illustrations are decorative: callers exclude them from the semantics tree.

/// Rolling hills + barn + sky scene (splash, login header, empty farm, explorer).
class FarmScenePainter extends CustomPainter {
  const FarmScenePainter({this.showBarn = true, this.showSun = true});

  final bool showBarn;
  final bool showSun;

  @override
  void paint(Canvas canvas, Size size) {
    final w = size.width;
    final h = size.height;

    // Sky band.
    final sky = Paint()..color = FarmlyColors.illustrationSky;
    canvas.drawRect(Rect.fromLTWH(0, 0, w, h * 0.62), sky);

    if (showSun) {
      final sun = Paint()..color = FarmlyColors.illustrationBarn;
      canvas.drawCircle(Offset(w * 0.82, h * 0.18), h * 0.09, sun);
    }

    // Far hill (slightly darkened sage).
    final farHill = Paint()
      ..color = Color.lerp(FarmlyColors.brandSage, FarmlyColors.textPrimary, 0.18)!;
    canvas.drawArc(
      Rect.fromCenter(
        center: Offset(w * 0.28, h * 0.62),
        width: w * 0.95,
        height: h * 0.55,
      ),
      3.14159,
      3.14159,
      true,
      farHill,
    );

    // Near hill.
    final nearHill = Paint()..color = FarmlyColors.brandSage;
    canvas.drawArc(
      Rect.fromCenter(
        center: Offset(w * 0.72, h * 0.66),
        width: w * 1.05,
        height: h * 0.6,
      ),
      3.14159,
      3.14159,
      true,
      nearHill,
    );

    // Ground.
    final ground = Paint()..color = FarmlyColors.background;
    canvas.drawRect(Rect.fromLTWH(0, h * 0.72, w, h * 0.28), ground);

    // Field rows.
    final row = Paint()
      ..color = Color.lerp(FarmlyColors.brandSage, FarmlyColors.background, 0.35)!
      ..strokeWidth = h * 0.03
      ..strokeCap = StrokeCap.round;
    for (var i = 0; i < 3; i++) {
      final y = h * (0.8 + i * 0.07);
      canvas.drawLine(Offset(w * 0.06, y), Offset(w * 0.94, y), row);
    }

    if (showBarn) {
      _paintBarn(canvas, Offset(w * 0.68, h * 0.72), h * 0.3, w * 0.2);
    }
  }

  void _paintBarn(Canvas canvas, Offset base, double height, double width) {
    final body = Paint()..color = FarmlyColors.illustrationBarn;
    final bodyRect = Rect.fromCenter(
      center: Offset(base.dx, base.dy - height * 0.4),
      width: width,
      height: height * 0.8,
    );
    canvas.drawRRect(
      RRect.fromRectAndRadius(bodyRect, Radius.circular(height * 0.05)),
      body,
    );

    final roof = Path()
      ..moveTo(base.dx - width * 0.62, base.dy - height * 0.78)
      ..lineTo(base.dx, base.dy - height * 1.15)
      ..lineTo(base.dx + width * 0.62, base.dy - height * 0.78)
      ..close();
    canvas.drawPath(
      roof,
      Paint()
        ..color = Color.lerp(
          FarmlyColors.illustrationBarn,
          FarmlyColors.textPrimary,
          0.25,
        )!,
    );

    final door = Paint()..color = FarmlyColors.surface;
    canvas.drawRRect(
      RRect.fromRectAndRadius(
        Rect.fromCenter(
          center: Offset(base.dx, base.dy - height * 0.28),
          width: width * 0.34,
          height: height * 0.56,
        ),
        Radius.circular(height * 0.04),
      ),
      door,
    );
  }

  @override
  bool shouldRepaint(FarmScenePainter oldDelegate) =>
      oldDelegate.showBarn != showBarn || oldDelegate.showSun != showSun;
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
