import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../core/theme/farmly_colors.dart';
import 'clay_shapes.dart';
import 'farm_life_painter.dart';
import 'farm_structure_painter.dart';

/// Small scene details driven exclusively by the farm's shared ambient phase.
abstract final class FarmSceneAccents {
  static const _tau = math.pi * 2;

  /// Small ornamental swimmers, clipped to the water surface. These are art,
  /// never inventory records or a claim about the tank's operational contents.
  static void pondFish(
    Canvas canvas, {
    required Rect bounds,
    required double phase,
  }) {
    canvas.save();
    canvas.clipPath(Path()..addOval(bounds));
    canvas.translate(bounds.left, bounds.top);
    canvas.scale(bounds.width / 100, bounds.height / 100);
    for (var i = 0; i < 3; i++) {
      final angle = _tau * phase + i * _tau / 3;
      final center = Offset(
        50 + 27 * math.cos(angle),
        50 + 25 * math.sin(angle),
      );
      final heading = math.atan2(25 * math.cos(angle), -27 * math.sin(angle));
      canvas.save();
      canvas.translate(center.dx, center.dy);
      canvas.rotate(heading);
      final color = i == 1 ? const Color(0xfff5d48b) : const Color(0xffed9472);
      final tail = math.sin(_tau * phase * 4 + i) * 2;
      ClayShapes.form(
        canvas,
        Path()
          ..moveTo(-5, 0)
          ..lineTo(-14, -7 + tail)
          ..quadraticBezierTo(-10, tail, -14, 7 + tail)
          ..close(),
        ClayShapes.dark(color, 0.12),
      );
      ClayShapes.oval(canvas, const Rect.fromLTWH(-7, -5, 19, 10), color);
      ClayShapes.leaf(
        canvas,
        const Offset(0, -1),
        const Offset(-3, -7),
        2.3,
        ClayShapes.light(color, 0.3),
      );
      canvas.drawOval(
        const Rect.fromLTWH(5, -2.5, 2.5, 2.5),
        Paint()..color = FarmlyColors.textPrimary,
      );
      canvas.drawOval(
        const Rect.fromLTWH(5.5, -2.4, 0.8, 0.8),
        Paint()..color = FarmlyColors.surface,
      );
      canvas.restore();
    }
    canvas.restore();
  }

  static void lettuce(
    Canvas canvas, {
    required Offset ground,
    required double scale,
    required double phase,
    required int seed,
  }) {
    FarmLifePainter.drawLeafyPlant(
      canvas,
      ground: ground,
      scale: scale,
      phase: phase,
      seed: seed,
    );
    canvas.save();
    canvas.translate(ground.dx, ground.dy);
    canvas.scale(scale);
    canvas.rotate(math.sin(_tau * phase + seed * 0.83) * 0.055);
    for (final side in [-1.0, 1.0]) {
      ClayShapes.oval(
        canvas,
        Rect.fromCenter(center: Offset(side * 3, -5.5), width: 8, height: 8),
        ClayShapes.light(FarmlyColors.brandAction, 0.19),
      );
    }
    ClayShapes.oval(
      canvas,
      const Rect.fromLTWH(-4, -11, 8, 9),
      ClayShapes.light(FarmlyColors.brandSage, 0.17),
    );
    ClayShapes.leaf(
      canvas,
      const Offset(-1, -3),
      const Offset(1, -10),
      2.5,
      ClayShapes.light(FarmlyColors.brandAction, 0.38),
    );
    canvas.restore();
  }

  static void tomato(
    Canvas canvas, {
    required Offset ground,
    required double scale,
    required double phase,
    required int seed,
  }) {
    FarmLifePainter.drawTomatoPlant(
      canvas,
      ground: ground,
      scale: scale,
      phase: phase,
      seed: seed,
    );
    canvas.save();
    canvas.translate(ground.dx, ground.dy);
    canvas.scale(scale);
    canvas.rotate(math.sin(_tau * phase + seed * 0.71) * 0.04);
    ClayShapes.leaf(
      canvas,
      const Offset(0, -10),
      const Offset(-8, -17),
      4,
      ClayShapes.light(FarmlyColors.brandAction, 0.22),
    );
    ClayShapes.leaf(
      canvas,
      const Offset(0, -12),
      const Offset(7, -20),
      3.6,
      FarmlyColors.brandSage,
    );
    ClayShapes.oval(
      canvas,
      const Rect.fromLTWH(-2.5, -15, 5.6, 5.8),
      FarmlyColors.illustrationBarn,
    );
    ClayShapes.leaf(
      canvas,
      const Offset(0, -13),
      const Offset(2, -16),
      1,
      FarmlyColors.brandAction,
    );
    canvas.restore();
  }

  static void _line(
    Canvas canvas,
    Offset a,
    Offset b,
    Color color,
    double width,
  ) {
    canvas.drawLine(
      a,
      b,
      Paint()
        ..color = color
        ..strokeWidth = width
        ..strokeCap = StrokeCap.round,
    );
  }

  static void buildingLife(
    Canvas canvas, {
    required Rect bounds,
    required FarmStructureKind kind,
    required double phase,
  }) {
    canvas.save();
    canvas.translate(bounds.left, bounds.top);
    canvas.scale(bounds.width / 100, bounds.height / 100);
    if (kind == FarmStructureKind.house) {
      // Soft chimney wisps stay inside the plot's reserved sky margin.
      for (var i = 0; i < 3; i++) {
        final t = (phase + i / 3) % 1;
        final alpha = math.sin(math.pi * t) * 0.32;
        canvas.drawOval(
          Rect.fromCenter(
            center: Offset(69 + t * 10 + math.sin(t * math.pi) * 2, 7 - t * 13),
            width: 4 + t * 8,
            height: 3 + t * 5,
          ),
          Paint()..color = FarmlyColors.surface.withValues(alpha: alpha),
        );
      }
      // A warm window glimmer decorates glass, never represents occupancy data.
      canvas.drawOval(
        const Rect.fromLTWH(32, 34, 5, 5),
        Paint()
          ..color = FarmlyColors.semanticWarning.withValues(
            alpha: 0.3 + 0.15 * math.sin(_tau * phase),
          ),
      );
    } else {
      // A little four-blade ventilation wheel, attached to the round gable vent.
      canvas.save();
      canvas.translate(35, 37);
      canvas.rotate(_tau * phase);
      for (var blade = 0; blade < 4; blade++) {
        canvas.rotate(math.pi / 2);
        ClayShapes.leaf(
          canvas,
          Offset.zero,
          const Offset(0, -4),
          1.3,
          ClayShapes.light(FarmlyColors.brandSage, 0.7),
        );
      }
      canvas.restore();
      _line(
        canvas,
        const Offset(85, 26),
        const Offset(85, 5),
        FarmlyColors.textSecondary,
        1.2,
      );
      final wave = math.sin(_tau * phase + 0.8) * 2;
      final flag = Path()
        ..moveTo(85, 5)
        ..cubicTo(89, 2 + wave, 93, 8 - wave, 98, 5 + wave)
        ..lineTo(98, 12 + wave)
        ..cubicTo(93, 15 - wave, 89, 9 + wave, 85, 12)
        ..close();
      ClayShapes.form(canvas, flag, FarmlyColors.semanticWarning);
    }
    canvas.restore();
  }

  static void butterfly(
    Canvas canvas, {
    required Rect bounds,
    required double phase,
    bool golden = false,
  }) {
    canvas.save();
    canvas.translate(
      bounds.left + bounds.width * (0.52 + 0.27 * math.cos(_tau * phase)),
      bounds.top + bounds.height * (0.4 + 0.22 * math.sin(_tau * phase * 2)),
    );
    final flap = 0.35 + 0.65 * math.pow(math.cos(_tau * phase * 6), 2);
    for (final side in [-1.0, 1.0]) {
      ClayShapes.oval(
        canvas,
        Rect.fromCenter(
          center: Offset(side * 2.4 * flap, -1),
          width: 5 * flap,
          height: 6,
        ),
        golden
            ? FarmlyColors.semanticWarning
            : ClayShapes.light(FarmlyColors.illustrationBarn, 0.35),
      );
    }
    ClayShapes.capsule(
      canvas,
      const Rect.fromLTWH(-0.7, -3, 1.4, 5),
      FarmlyColors.textPrimary,
    );
    canvas.restore();
  }

  static void lily(
    Canvas canvas, {
    required Offset center,
    required double phase,
    required int seed,
  }) {
    final drift = Offset(
      math.sin(_tau * phase + seed) * 2.5,
      math.cos(_tau * phase + seed) * 1.1,
    );
    final c = center + drift;
    ClayShapes.shadow(canvas, c + const Offset(1, 1.2), 11, 4);
    ClayShapes.oval(
      canvas,
      Rect.fromCenter(center: c, width: 10, height: 5.8),
      FarmlyColors.brandAction,
    );
    for (var petal = 0; petal < 5; petal++) {
      final a = petal * _tau / 5;
      ClayShapes.oval(
        canvas,
        Rect.fromCenter(
          center: c + Offset(math.cos(a) * 1.7, -2 + math.sin(a) * 1.2),
          width: 3.2,
          height: 2.5,
        ),
        ClayShapes.light(FarmlyColors.illustrationBarn, 0.74),
      );
    }
    ClayShapes.oval(
      canvas,
      Rect.fromCenter(center: c + const Offset(0, -2), width: 2.4, height: 2),
      FarmlyColors.semanticWarning,
    );
  }
}

/// A labelled illustration in an unused board cell; never a livestock record.
class FarmMeadowPainter extends CustomPainter {
  const FarmMeadowPainter({required this.phase});
  final double phase;

  @override
  void paint(Canvas canvas, Size size) {
    canvas.save();
    canvas.scale(size.width / 100, size.height / 72);
    final patch = RRect.fromRectAndRadius(
      const Rect.fromLTWH(1, 8, 98, 61),
      const Radius.circular(18),
    );
    canvas.drawRRect(
      patch.shift(const Offset(0, 3)),
      Paint()..color = FarmlyColors.brandAction.withValues(alpha: 0.2),
    );
    canvas.drawRRect(
      patch,
      Paint()
        ..shader = LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [
            ClayShapes.light(FarmlyColors.brandSage, 0.38),
            ClayShapes.light(FarmlyColors.brandAction, 0.38),
          ],
        ).createShader(patch.outerRect),
    );
    for (var i = 0; i < 9; i++) {
      FarmLifePainter.drawGrassTuft(
        canvas,
        ground: Offset(8 + i * 10.0, 62 - i % 3 * 4),
        scale: 0.65,
        phase: phase,
        seed: i + 20,
      );
    }
    // Independent lanes retain full silhouettes and clear contact shadows.
    for (var i = 0; i < 2; i++) {
      canvas.save();
      canvas.translate(29 + i * 43, 39 + i * 12);
      // Terrain is projected into a shallow patch, but animals retain their
      // own proportions rather than inheriting its vertical compression.
      canvas.scale(1, (size.width / 100) / (size.height / 72));
      FarmLifePainter.drawPastureAnimal(
        canvas,
        ground: Offset.zero,
        scale: i == 0 ? 1.1 : 0.92,
        phase: phase,
        seed: i + 5,
        form: FarmAnimalForm.cow,
        travel: 2,
      );
      canvas.restore();
    }
    FarmStructurePainter.fence(
      canvas,
      bounds: const Rect.fromLTWH(8, 53, 82, 17),
    );
    canvas.restore();
  }

  @override
  bool shouldRepaint(FarmMeadowPainter oldDelegate) =>
      phase != oldDelegate.phase;
}
