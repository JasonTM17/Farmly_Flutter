import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../core/theme/farmly_colors.dart';
import '../features/demo/demo_models.dart';
import 'clay_shapes.dart';

enum FarmAnimalForm { cow, chicken, sheep, goat, generic }

/// Local, deterministic clay-style 3D illustrations shared by map and cards.
/// Volume is shaded on Canvas; all motion comes from the existing scene phase.
abstract final class FarmLifePainter {
  static const _tau = math.pi * 2;
  static final _cream = ClayShapes.light(FarmlyColors.semanticWarning, 0.91);
  static final _pink = ClayShapes.light(FarmlyColors.illustrationBarn, 0.68);
  static final _ochre = ClayShapes.light(FarmlyColors.semanticWarning, 0.38);
  static final _wool = ClayShapes.light(FarmlyColors.brandSage, 0.88);
  static final _patch = ClayShapes.dark(FarmlyColors.brandSage, 0.62);

  static Rect _oval(Offset center, double width, double height) =>
      Rect.fromCenter(center: center, width: width, height: height);

  static void _stroke(Canvas canvas, Path path, Color color, double width) {
    canvas.drawPath(
      path,
      Paint()
        ..color = color
        ..strokeWidth = width
        ..strokeCap = StrokeCap.round
        ..strokeJoin = StrokeJoin.round
        ..style = PaintingStyle.stroke,
    );
  }

  static FarmAnimalForm formForZoneName(String name) {
    final value = name.toLowerCase();
    if (value.contains('gà') || value.contains('chicken')) {
      return FarmAnimalForm.chicken;
    }
    if (value.contains('bò') || value.contains('cow')) {
      return FarmAnimalForm.cow;
    }
    if (value.contains('cừu') || value.contains('sheep')) {
      return FarmAnimalForm.sheep;
    }
    if (value.contains('dê') || value.contains('goat')) {
      return FarmAnimalForm.goat;
    }
    return FarmAnimalForm.generic;
  }

  static void drawTree(
    Canvas canvas, {
    required Offset ground,
    required double scale,
    required double phase,
    required int seed,
  }) {
    canvas.save();
    canvas.translate(ground.dx, ground.dy);
    canvas.scale(scale);
    ClayShapes.shadow(canvas, const Offset(3, 1.6), 31, 7);
    final wind = math.sin(_tau * phase + seed * 1.31) * 0.045;
    final trunk = Path()
      ..moveTo(-3.2, 0)
      ..quadraticBezierTo(-1.4, -8, -2, -19)
      ..lineTo(2, -19)
      ..quadraticBezierTo(1, -7, 3, 0)
      ..close();
    ClayShapes.form(
      canvas,
      trunk,
      ClayShapes.light(FarmlyColors.semanticWarning, 0.18),
    );
    _stroke(
      canvas,
      Path()
        ..moveTo(0, -7)
        ..quadraticBezierTo(-5, -11, -7, -16),
      FarmlyColors.semanticWarning,
      1.8,
    );
    canvas.translate(0, -11);
    canvas.rotate(wind);
    final green = Color.lerp(
      FarmlyColors.brandAction,
      FarmlyColors.brandSage,
      0.3,
    )!;
    // Back lobes first; foreground lobes overlap with their own contour shade.
    for (final (x, y, w, h, light) in const [
      (-7.0, -8.0, 17.0, 18.0, 0.02),
      (6.0, -10.0, 18.0, 20.0, 0.06),
      (-1.0, -17.0, 20.0, 18.0, 0.12),
      (-1.0, -6.0, 24.0, 17.0, 0.03),
    ]) {
      ClayShapes.oval(
        canvas,
        _oval(Offset(x, y), w, h),
        ClayShapes.light(green, light),
      );
    }
    // Small leaf pairs break the silhouette without visual noise at map scale.
    for (var i = 0; i < 3; i++) {
      final root = Offset(-7 + i * 6, -10 - (i.isEven ? 2 : 0));
      ClayShapes.leaf(
        canvas,
        root,
        root + const Offset(3, -3.5),
        1.7,
        ClayShapes.light(green, 0.26),
      );
    }
    canvas.restore();
  }

  static void drawLeafyPlant(
    Canvas canvas, {
    required Offset ground,
    required double scale,
    required double phase,
    required int seed,
  }) {
    canvas.save();
    canvas.translate(ground.dx, ground.dy);
    canvas.scale(scale);
    ClayShapes.shadow(canvas, const Offset(1, 1), 15, 4);
    canvas.rotate(math.sin(_tau * phase + seed * 0.83) * 0.055);
    // Outer leaves cradle the raised central heart of the rosette.
    for (final (x, y, width) in const [
      (-7.0, -5.0, 4.3),
      (7.0, -5.5, 4.4),
      (-5.2, -10.5, 4.0),
      (5.2, -11.0, 4.0),
      (-1.5, -13.0, 3.6),
      (2.2, -9.0, 3.4),
    ]) {
      final color = Color.lerp(
        FarmlyColors.brandAction,
        FarmlyColors.brandSage,
        y < -9 ? 0.45 : 0.16,
      )!;
      ClayShapes.leaf(
        canvas,
        const Offset(0, -0.5),
        Offset(x, y),
        width,
        color,
      );
    }
    canvas.restore();
  }

  static void drawTomatoPlant(
    Canvas canvas, {
    required Offset ground,
    required double scale,
    required double phase,
    required int seed,
  }) {
    canvas.save();
    canvas.translate(ground.dx, ground.dy);
    canvas.scale(scale);
    ClayShapes.shadow(canvas, const Offset(1, 1), 15, 3.5);
    canvas.rotate(math.sin(_tau * phase + seed * 0.71) * 0.04);
    _stroke(
      canvas,
      Path()
        ..moveTo(0, 0)
        ..quadraticBezierTo(-1, -7, 0.8, -17),
      FarmlyColors.brandAction,
      1.2,
    );
    for (var i = 0; i < 4; i++) {
      final side = i.isEven ? -1.0 : 1.0;
      final root = Offset(0, -4 - (i ~/ 2) * 6.0);
      ClayShapes.leaf(
        canvas,
        root,
        root + Offset(side * 7, -4.5),
        3.2,
        ClayShapes.light(FarmlyColors.brandAction, i.isEven ? 0.12 : 0.25),
      );
    }
    for (var i = 0; i < 2; i++) {
      final fruit = Offset(i == 0 ? -4.7 : 4.3, -5.4 - i * 3.0);
      ClayShapes.oval(
        canvas,
        _oval(fruit, 5.8, 5.5),
        ClayShapes.light(FarmlyColors.illustrationBarn, 0.08),
      );
      for (var petal = 0; petal < 3; petal++) {
        final a = -math.pi + petal * math.pi / 3;
        _stroke(
          canvas,
          Path()
            ..moveTo(fruit.dx, fruit.dy - 2.3)
            ..lineTo(
              fruit.dx + math.cos(a) * 1.7,
              fruit.dy - 2.3 + math.sin(a) * 1.1,
            ),
          FarmlyColors.brandAction,
          0.55,
        );
      }
    }
    canvas.restore();
  }

  static void drawCornStalk(
    Canvas canvas, {
    required Offset ground,
    required double scale,
    required double phase,
    required int seed,
  }) {
    canvas.save();
    canvas.translate(ground.dx, ground.dy);
    canvas.scale(scale);
    ClayShapes.shadow(canvas, const Offset(1, 1), 12, 3);
    canvas.rotate(math.sin(_tau * phase + seed * 0.91) * 0.055);
    ClayShapes.capsule(
      canvas,
      const Rect.fromLTWH(-0.9, -18, 1.8, 18),
      FarmlyColors.brandAction,
    );
    for (var i = 0; i < 4; i++) {
      final side = i.isEven ? -1.0 : 1.0;
      final root = Offset(0, -4.0 - i * 2.8);
      ClayShapes.leaf(
        canvas,
        root,
        root + Offset(side * (8 - i * 0.5), -5),
        2.8,
        ClayShapes.light(FarmlyColors.brandAction, i.isEven ? 0.06 : 0.28),
      );
    }
    if (seed.isEven) {
      ClayShapes.oval(canvas, const Rect.fromLTWH(0.6, -12, 3.8, 6.5), _ochre);
      for (var row = 0; row < 3; row++) {
        _stroke(
          canvas,
          Path()
            ..moveTo(1.3, -10.5 + row * 1.4)
            ..lineTo(3.5, -10.5 + row * 1.4),
          ClayShapes.light(_ochre, 0.35),
          0.45,
        );
      }
    }
    for (final side in const [-1.0, 0.0, 1.0]) {
      _stroke(
        canvas,
        Path()
          ..moveTo(0, -17)
          ..quadraticBezierTo(side * 2, -20, side * 3, -20),
        _ochre,
        0.7,
      );
    }
    canvas.restore();
  }

  /// A short loop inside each decorative animal's own pasture lane.
  /// Velocity reaches zero before a turn; four foot cycles avoid skating.
  static ({Offset offset, double stride, double facing, double speed})
  pastureWalk(double phase, int seed) {
    final angle = _tau * (phase + seed * 0.067);
    final velocity = math.cos(angle);
    return (
      offset: Offset(5 * math.sin(angle), 1.4 * math.sin(angle * 2)),
      stride: math.sin(_tau * phase * 4 + seed * 1.17) * 1.8 * velocity.abs(),
      facing: (velocity * 5).clamp(-1.0, 1.0),
      speed: velocity.abs(),
    );
  }

  /// Wind bends the tips while every blade remains attached to its root.
  static void drawGrassTuft(
    Canvas canvas, {
    required Offset ground,
    required double scale,
    required double phase,
    required int seed,
  }) {
    canvas.save();
    canvas.translate(ground.dx, ground.dy);
    canvas.scale(scale);
    ClayShapes.shadow(canvas, const Offset(0.5, 0.7), 12, 2.4);
    final wind = math.sin(_tau * phase + seed * 0.83) * 2.4;
    for (var blade = 0; blade < 5; blade++) {
      final side = blade - 2;
      final root = Offset(side * 0.65, 0);
      final tip = Offset(side * 2.3 + wind, -11 + side.abs() * 1.8);
      ClayShapes.leaf(
        canvas,
        root,
        tip,
        1.1,
        blade.isEven ? FarmlyColors.brandAction : FarmlyColors.brandSage,
      );
    }
    canvas.restore();
  }

  static void drawPastureAnimal(
    Canvas canvas, {
    required Offset ground,
    required double scale,
    required double phase,
    required int seed,
    required FarmAnimalForm form,
    double travel = 1,
  }) {
    canvas.save();
    canvas.translate(ground.dx, ground.dy);
    canvas.scale(scale);
    final walk = pastureWalk(phase, seed);
    canvas.translate(walk.offset.dx * travel, walk.offset.dy);
    final angle = _tau * phase + seed * 1.17;
    final bob = math.sin(angle * 8) * 0.3 * walk.speed;
    final chicken = form == FarmAnimalForm.chicken;
    ClayShapes.shadow(canvas, const Offset(1.8, 1.5), chicken ? 18 : 29, 5);
    // Keep the full clay silhouette readable even at the slowest turn.
    final facing = walk.facing < 0 ? -1.0 : 1.0;
    canvas.scale(facing * (0.8 + 0.2 * walk.facing.abs()), 1);
    final coat = switch (form) {
      FarmAnimalForm.sheep => _wool,
      FarmAnimalForm.goat => _cream,
      _ => FarmlyColors.surface,
    };
    // Opposite feet alternate contact and lift while the body advances.
    final legCount = chicken ? 2 : 4;
    for (var i = 0; i < legCount; i++) {
      final x = chicken
          ? -2.5 + i * 6
          : (i < 2 ? -7.0 : 7.0) + (i.isEven ? -1 : 1);
      final far = !chicken && i.isEven;
      final step = walk.stride * (i.isEven ? 1 : -1);
      final lift = math.max(0.0, step) * 0.65;
      final foot = Offset(x + step, 1 + (far ? -1.0 : 0) - lift);
      _stroke(
        canvas,
        Path()
          ..moveTo(x + bob * 0.3, -6 + bob)
          ..quadraticBezierTo(x + step * 0.6, -2 - lift, foot.dx, foot.dy),
        chicken ? _ochre : ClayShapes.dark(coat, far ? 0.42 : 0.28),
        chicken ? 1.0 : 2.3,
      );
      ClayShapes.oval(
        canvas,
        _oval(foot, chicken ? 3 : 3.4, 1.7),
        chicken ? _ochre : FarmlyColors.textSecondary,
      );
    }
    if (chicken) {
      _pastureChicken(canvas, bob, angle);
      canvas.restore();
      return;
    }
    final tail = Path()
      ..moveTo(-10, -9 + bob)
      ..quadraticBezierTo(-17, -13 + bob, -14 + math.sin(angle) * 1.5, -5);
    _stroke(canvas, tail, ClayShapes.dark(coat, 0.32), 1.2);
    ClayShapes.oval(
      canvas,
      _oval(Offset(-14 + math.sin(angle) * 1.5, -4.8), 2.4, 3),
      form == FarmAnimalForm.cow ? _patch : coat,
    );
    ClayShapes.oval(canvas, _oval(Offset(0, -8 + bob), 24, 13), coat);
    if (form == FarmAnimalForm.cow) {
      ClayShapes.oval(canvas, _oval(Offset(-4, -10 + bob), 7.5, 7), _patch);
      ClayShapes.oval(canvas, _oval(Offset(5, -6.5 + bob), 4, 4.6), _patch);
    } else if (form == FarmAnimalForm.sheep) {
      for (var i = 0; i < 7; i++) {
        final a = i * _tau / 7;
        ClayShapes.oval(
          canvas,
          _oval(Offset(math.cos(a) * 8, -8 + bob + math.sin(a) * 3.6), 7, 6.2),
          _wool,
        );
      }
    }
    final dip = math.sin(angle + 1.3) * 0.6;
    final head = Offset(10.5, -10 + bob + dip);
    final face = form == FarmAnimalForm.sheep
        ? ClayShapes.light(_patch, 0.14)
        : coat;
    // Far ear, round head, near ear: overlap gives a readable three-quarter face.
    ClayShapes.oval(
      canvas,
      _oval(head + const Offset(1, -4), 3.2, 4),
      ClayShapes.dark(face, 0.15),
    );
    ClayShapes.oval(canvas, _oval(head, 9.5, 10), face);
    ClayShapes.oval(
      canvas,
      _oval(head + const Offset(-3.8, -2.3), 5, 2.8),
      face,
    );
    if (form == FarmAnimalForm.cow || form == FarmAnimalForm.goat) {
      for (final side in const [-1.0, 1.0]) {
        _stroke(
          canvas,
          Path()
            ..moveTo(head.dx + side * 2, head.dy - 4)
            ..quadraticBezierTo(
              head.dx + side * 4,
              head.dy - 6,
              head.dx + side * 3,
              head.dy - 7,
            ),
          _ochre,
          1.2,
        );
      }
    }
    ClayShapes.oval(
      canvas,
      _oval(head + const Offset(3.2, 2), 5.6, 4.5),
      form == FarmAnimalForm.cow ? _pink : ClayShapes.light(face, 0.15),
    );
    _eye(canvas, head + const Offset(1.6, -0.8), 1.15, 1);
    if (form == FarmAnimalForm.goat) {
      ClayShapes.leaf(
        canvas,
        head + const Offset(1.8, 3.5),
        head + const Offset(2.5, 7),
        1.8,
        _ochre,
      );
    }
    canvas.restore();
  }

  static void _pastureChicken(Canvas canvas, double bob, double angle) {
    final body = Offset(0, -6 + bob);
    for (var feather = 0; feather < 3; feather++) {
      ClayShapes.leaf(
        canvas,
        body + const Offset(-4, 0),
        body +
            Offset(
              -10 + feather * 2,
              -5 - feather * 1.6 + math.sin(angle) * 0.4,
            ),
        2.4,
        ClayShapes.light(_ochre, feather * 0.12),
      );
    }
    ClayShapes.oval(canvas, _oval(body, 16, 11), _cream);
    ClayShapes.oval(
      canvas,
      _oval(body + const Offset(-1.3, 1), 8.4, 6.8),
      ClayShapes.light(_ochre, 0.65),
    );
    final peck = math.pow((1 + math.sin(angle + 1.1)) / 2, 3).toDouble();
    final head = body + Offset(6.2 + peck * 0.5, -5 + peck * 2);
    ClayShapes.oval(canvas, _oval(head, 7.5, 8), _cream);
    for (var i = 0; i < 3; i++) {
      ClayShapes.oval(
        canvas,
        _oval(head + Offset(-2 + i * 1.8, -3.5), 2.5, 3),
        FarmlyColors.illustrationBarn,
      );
    }
    final beak = Path()
      ..moveTo(head.dx + 2.7, head.dy - 0.4)
      ..quadraticBezierTo(head.dx + 7, head.dy + 1, head.dx + 2.8, head.dy + 2)
      ..close();
    ClayShapes.form(canvas, beak, _ochre);
    ClayShapes.oval(
      canvas,
      _oval(head + const Offset(2, 3), 2.1, 3),
      FarmlyColors.illustrationBarn,
    );
    _eye(canvas, head + const Offset(1, -0.5), 1.05, 1);
  }

  static void drawAnimalPortrait(
    Canvas canvas, {
    required Size size,
    required DemoAnimalCategory category,
    required double phase,
  }) {
    final unit = math.min(size.width, size.height);
    canvas.save();
    canvas.translate((size.width - unit) / 2, (size.height - unit) / 2);
    canvas.scale(unit / 100);
    ClayShapes.shadow(canvas, const Offset(51, 89), 62, 10);
    final angle = _tau * phase;
    final offset = category.index * 0.48;
    canvas.translate(50, 51);
    canvas.rotate(math.sin(angle + offset) * 0.025);
    final breath = 1 + math.sin(angle + offset) * 0.012;
    canvas.scale(breath, breath);
    canvas.translate(-50, -51);
    final ear = math.sin(angle + offset + 0.8) * 1.8;
    // A periodic smooth blink avoids random timers and closes the loop at 1.
    final blink =
        1 - math.pow(math.max(0.0, math.cos(angle - 4.5)), 24).toDouble() * 0.9;
    switch (category) {
      case DemoAnimalCategory.cows:
        _ears(canvas, _cream, _pink, ear);
        _horns(canvas, false);
        ClayShapes.oval(
          canvas,
          const Rect.fromLTWH(22, 22, 57, 59),
          FarmlyColors.surface,
        );
        final patch = Path()
          ..moveTo(25, 37)
          ..cubicTo(29, 24, 45, 22, 47, 30)
          ..cubicTo(51, 40, 39, 42, 41, 52)
          ..cubicTo(35, 58, 22, 50, 25, 37)
          ..close();
        ClayShapes.form(canvas, patch, _patch);
        ClayShapes.oval(canvas, const Rect.fromLTWH(63, 29, 10, 13), _patch);
        _eyes(canvas, 37, 63, 51, blink);
        ClayShapes.oval(canvas, const Rect.fromLTWH(25, 60, 51, 24), _pink);
        for (final x in const [39.0, 62.0]) {
          ClayShapes.oval(
            canvas,
            _oval(Offset(x, 70), 4.5, 6),
            ClayShapes.dark(_pink, 0.42),
          );
        }
        _smile(canvas, const Offset(46, 77), 10, ClayShapes.dark(_pink, 0.3));
      case DemoAnimalCategory.chickens:
        ClayShapes.oval(canvas, const Rect.fromLTWH(25, 34, 51, 50), _cream);
        ClayShapes.oval(
          canvas,
          const Rect.fromLTWH(19, 54, 14, 22),
          ClayShapes.light(_ochre, 0.7),
        );
        ClayShapes.oval(
          canvas,
          const Rect.fromLTWH(69, 54, 13, 22),
          ClayShapes.light(_ochre, 0.7),
        );
        for (final (x, y, w, h) in const [
          (34.0, 23.0, 14.0, 20.0),
          (44.0, 18.0, 16.0, 24.0),
          (56.0, 25.0, 13.0, 17.0),
        ]) {
          ClayShapes.oval(
            canvas,
            Rect.fromLTWH(x, y, w, h),
            FarmlyColors.illustrationBarn,
          );
        }
        _eyes(canvas, 38, 63, 52, blink);
        ClayShapes.oval(
          canvas,
          const Rect.fromLTWH(46, 67, 10, 15),
          FarmlyColors.illustrationBarn,
        );
        final beak = Path()
          ..moveTo(39, 59)
          ..quadraticBezierTo(50, 55, 62, 59)
          ..quadraticBezierTo(59, 68, 51, 71)
          ..quadraticBezierTo(43, 67, 39, 59)
          ..close();
        ClayShapes.form(canvas, beak, _ochre);
      case DemoAnimalCategory.sheep:
        _ears(canvas, _wool, ClayShapes.light(_patch, 0.2), ear);
        ClayShapes.oval(canvas, const Rect.fromLTWH(18, 23, 66, 60), _wool);
        for (var i = 0; i < 9; i++) {
          final a = _tau * i / 9;
          ClayShapes.oval(
            canvas,
            _oval(Offset(50 + math.cos(a) * 24, 49 + math.sin(a) * 22), 23, 23),
            _wool,
          );
        }
        ClayShapes.oval(
          canvas,
          const Rect.fromLTWH(33, 39, 35, 43),
          ClayShapes.light(_patch, 0.13),
        );
        for (final x in const [37.0, 49.0, 61.0]) {
          ClayShapes.oval(canvas, _oval(Offset(x, 34), 19, 19), _wool);
        }
        _eyes(canvas, 41, 60, 55, blink);
        ClayShapes.oval(canvas, const Rect.fromLTWH(46, 65, 9, 6), _pink);
        _smile(canvas, const Offset(46, 73), 9, ClayShapes.light(_patch, 0.55));
      case DemoAnimalCategory.goats:
        _ears(canvas, _cream, _pink, ear);
        _horns(canvas, true);
        ClayShapes.leaf(
          canvas,
          const Offset(50, 71),
          const Offset(50, 89),
          9,
          _ochre,
        );
        ClayShapes.oval(canvas, const Rect.fromLTWH(29, 26, 43, 53), _cream);
        ClayShapes.oval(
          canvas,
          const Rect.fromLTWH(40, 26, 20, 25),
          ClayShapes.light(_ochre, 0.54),
        );
        _eyes(canvas, 38, 63, 51, blink);
        ClayShapes.oval(
          canvas,
          const Rect.fromLTWH(36, 61, 29, 18),
          ClayShapes.light(_ochre, 0.78),
        );
        ClayShapes.oval(
          canvas,
          const Rect.fromLTWH(46, 63, 9, 5),
          ClayShapes.dark(_pink, 0.27),
        );
        _smile(canvas, const Offset(46, 72), 9, ClayShapes.dark(_cream, 0.45));
    }
    canvas.restore();
  }

  static void _ears(Canvas canvas, Color coat, Color inner, double flutter) {
    for (final side in const [-1.0, 1.0]) {
      final root = Offset(50 + side * 19, 43);
      final tip = Offset(50 + side * 44, 35 + side * flutter);
      ClayShapes.leaf(canvas, root, tip, 16, coat);
      ClayShapes.leaf(
        canvas,
        root + Offset(side * 3, 0),
        tip + Offset(-side * 6, 1),
        7,
        inner,
      );
    }
  }

  static void _horns(Canvas canvas, bool goat) {
    for (final side in const [-1.0, 1.0]) {
      final x = 50 + side * 17;
      final horn = Path()
        ..moveTo(x - 4, 32)
        ..quadraticBezierTo(
          x - side * 4,
          goat ? 14 : 20,
          x + side * (goat ? 9 : 10),
          goat ? 8 : 18,
        )
        ..quadraticBezierTo(x + side * 1, 22, x + 4, 33)
        ..close();
      ClayShapes.form(canvas, horn, ClayShapes.light(_ochre, 0.48));
    }
  }

  static void _eyes(
    Canvas canvas,
    double left,
    double right,
    double y,
    double openness,
  ) {
    for (final x in [left, right]) {
      _eye(canvas, Offset(x, y), 4.6, openness);
    }
  }

  static void _eye(
    Canvas canvas,
    Offset center,
    double width,
    double openness,
  ) {
    ClayShapes.oval(
      canvas,
      _oval(center, width, width * 1.3 * openness),
      FarmlyColors.textPrimary,
    );
    if (openness > 0.45) {
      canvas.drawCircle(
        center + Offset(-width * 0.16, -width * 0.23),
        width * 0.17,
        Paint()..color = FarmlyColors.surface,
      );
    }
  }

  static void _smile(Canvas canvas, Offset start, double width, Color color) {
    _stroke(
      canvas,
      Path()
        ..moveTo(start.dx, start.dy)
        ..quadraticBezierTo(
          start.dx + width / 2,
          start.dy + 3,
          start.dx + width,
          start.dy,
        ),
      color,
      1.2,
    );
  }
}
