import 'package:flutter/material.dart';

import '../core/theme/farmly_colors.dart';
import 'clay_shapes.dart';

enum FarmStructureKind { house, barn, storage }

/// Small orthographic clay dioramas. All faces share the actors' upper-left
/// light; local 100-unit geometry can be reused in the hero and farm plots.
abstract final class FarmStructurePainter {
  static Path _face(List<Offset> points) {
    final path = Path()..moveTo(points.first.dx, points.first.dy);
    for (final p in points.skip(1)) {
      path.lineTo(p.dx, p.dy);
    }
    return path..close();
  }

  static void _line(Canvas c, Offset a, Offset b, Color color, double width) {
    c.drawLine(
      a,
      b,
      Paint()
        ..color = color
        ..strokeWidth = width
        ..strokeCap = StrokeCap.round,
    );
  }

  static void building(
    Canvas canvas, {
    required Rect bounds,
    required FarmStructureKind kind,
    bool detailed = false,
  }) {
    canvas.save();
    canvas.translate(bounds.left, bounds.top);
    canvas.scale(bounds.width / 100, bounds.height / 100);
    final house = kind == FarmStructureKind.house;
    final barn = kind == FarmStructureKind.barn;
    final wall = house
        ? ClayShapes.light(FarmlyColors.semanticWarning, 0.88)
        : barn
        ? FarmlyColors.illustrationBarn
        : ClayShapes.light(FarmlyColors.brandAction, 0.46);
    final roof = house
        ? FarmlyColors.illustrationBarn
        : barn
        ? ClayShapes.light(FarmlyColors.textPrimary, 0.22)
        : FarmlyColors.brandAction;
    ClayShapes.shadow(canvas, const Offset(53, 84), 90, 21);
    // Stone plinth: the thin bottom edge anchors both visible wall planes.
    ClayShapes.form(
      canvas,
      _face(const [
        Offset(10, 75),
        Offset(60, 87),
        Offset(90, 69),
        Offset(90, 75),
        Offset(60, 94),
        Offset(10, 81),
      ]),
      ClayShapes.light(FarmlyColors.textSecondary, 0.35),
    );
    ClayShapes.form(
      canvas,
      _face(const [
        Offset(60, 46),
        Offset(88, 29),
        Offset(88, 72),
        Offset(60, 89),
      ]),
      ClayShapes.dark(wall, 0.24),
    );
    ClayShapes.form(
      canvas,
      _face(const [
        Offset(12, 41),
        Offset(36, 17),
        Offset(60, 47),
        Offset(60, 89),
        Offset(12, 77),
      ]),
      wall,
    );
    // Plank joints stay on the facade, clear of the inset openings.
    for (var i = 0; i < 4; i++) {
      final y = 49.0 + i * 8;
      _line(
        canvas,
        Offset(14, y),
        Offset(59, y + 11),
        ClayShapes.dark(wall, 0.12),
        0.55,
      );
    }
    // Chimney behind the roof: capped top, warm side and lit front.
    if (house) {
      ClayShapes.form(
        canvas,
        _face(const [
          Offset(70, 12),
          Offset(78, 7),
          Offset(78, 31),
          Offset(70, 35),
        ]),
        ClayShapes.dark(wall, 0.18),
      );
      ClayShapes.form(
        canvas,
        _face(const [
          Offset(63, 10),
          Offset(70, 12),
          Offset(70, 35),
          Offset(63, 32),
        ]),
        wall,
      );
      ClayShapes.form(
        canvas,
        _face(const [
          Offset(61, 9),
          Offset(69, 4),
          Offset(80, 7),
          Offset(71, 13),
        ]),
        ClayShapes.light(roof, 0.18),
      );
    }
    // Solid overhanging roof planes replace the old hollow roof outline.
    ClayShapes.form(
      canvas,
      _face(const [
        Offset(7, 42),
        Offset(36, 12),
        Offset(65, 1),
        Offset(35, 31),
      ]),
      ClayShapes.light(roof, 0.22),
    );
    ClayShapes.form(
      canvas,
      _face(const [
        Offset(36, 12),
        Offset(65, 1),
        Offset(94, 34),
        Offset(63, 53),
      ]),
      roof,
    );
    ClayShapes.form(
      canvas,
      _face(const [
        Offset(36, 12),
        Offset(63, 49),
        Offset(63, 54),
        Offset(36, 18),
        Offset(8, 46),
        Offset(7, 42),
      ]),
      ClayShapes.dark(roof, 0.2),
    );
    for (var i = 1; i < 5; i++) {
      final t = i / 5;
      _line(
        canvas,
        Offset(36 + t * 29, 12 - t * 11),
        Offset(63 + t * 31, 49 - t * 15),
        ClayShapes.light(roof, 0.15),
        0.7,
      );
    }
    _line(
      canvas,
      const Offset(36, 12),
      const Offset(65, 1),
      ClayShapes.light(roof, 0.4),
      1.6,
    );
    _line(
      canvas,
      const Offset(12, 46),
      const Offset(12, 77),
      ClayShapes.light(wall, 0.45),
      1,
    );

    // Front door is inset, with a lit frame and a deliberately visible reveal.
    final door = _face(
      house
          ? const [
              Offset(38, 58),
              Offset(53, 62),
              Offset(53, 87),
              Offset(38, 83),
            ]
          : const [
              Offset(24, 53),
              Offset(49, 59),
              Offset(49, 86),
              Offset(24, 80),
            ],
    );
    canvas.drawPath(
      door,
      Paint()
        ..color = ClayShapes.dark(wall, 0.36)
        ..style = PaintingStyle.stroke
        ..strokeWidth = 3.6,
    );
    ClayShapes.form(
      canvas,
      door,
      house ? FarmlyColors.brandAction : ClayShapes.light(wall, 0.85),
    );
    if (house) {
      ClayShapes.oval(
        canvas,
        const Rect.fromLTWH(47, 72, 2.3, 2.3),
        ClayShapes.light(FarmlyColors.semanticWarning, 0.55),
      );
      _line(
        canvas,
        const Offset(38, 83),
        const Offset(53, 87),
        FarmlyColors.surface,
        1.6,
      );
    } else {
      _line(
        canvas,
        const Offset(25, 54),
        const Offset(48, 85),
        ClayShapes.dark(wall, 0.15),
        1.8,
      );
      _line(
        canvas,
        const Offset(48, 59),
        const Offset(25, 79),
        ClayShapes.dark(wall, 0.15),
        1.8,
      );
      _line(
        canvas,
        const Offset(36.5, 56),
        const Offset(36.5, 83),
        ClayShapes.dark(wall, 0.2),
        0.7,
      );
    }
    _window(canvas, const [
      Offset(68, 48),
      Offset(80, 41),
      Offset(80, 53),
      Offset(68, 60),
    ]);
    if (house) {
      _window(canvas, const [
        Offset(18, 50),
        Offset(30, 53),
        Offset(30, 65),
        Offset(18, 62),
      ]);
    }
    ClayShapes.oval(
      canvas,
      const Rect.fromLTWH(29, 32, 11, 11),
      ClayShapes.dark(wall, 0.34),
    );
    ClayShapes.oval(
      canvas,
      const Rect.fromLTWH(31, 33, 8, 8),
      ClayShapes.light(FarmlyColors.illustrationSky, 0.24),
    );
    if (detailed) _details(canvas, kind: kind, wall: wall, roof: roof);
    canvas.restore();
  }

  /// Opt-in plot detail: fixtures fit the existing 100-unit silhouette so
  /// compact portraits elsewhere retain their simpler visual density.
  static void _details(
    Canvas c, {
    required FarmStructureKind kind,
    required Color wall,
    required Color roof,
  }) {
    final house = kind == FarmStructureKind.house;
    final wood = ClayShapes.light(FarmlyColors.semanticWarning, 0.25);
    final darkWood = ClayShapes.dark(wood, 0.3);
    final trim = ClayShapes.light(wall, 0.75);
    // Staggered shingles follow the slope and remain inside the roof plane.
    c.save();
    c.clipPath(
      _face(const [
        Offset(36, 12),
        Offset(65, 1),
        Offset(94, 34),
        Offset(63, 49),
      ]),
    );
    for (var row = 1; row <= 4; row++) {
      final t = row / 5;
      _line(
        c,
        Offset(36 + 27 * t, 12 + 37 * t),
        Offset(65 + 29 * t, 1 + 33 * t),
        ClayShapes.dark(roof, 0.14),
        0.7,
      );
      for (var col = 0; col < 5; col++) {
        final u = (col + (row.isEven ? 0.4 : 0)) / 5;
        final a = Offset(36 + 29 * u + 27 * t, 12 - 11 * u + 37 * t);
        _line(
          c,
          a,
          a + const Offset(3.6, 4.3),
          ClayShapes.light(roof, 0.24),
          0.55,
        );
      }
    }
    c.restore();
    // Eave gutter and corner downpipe accent the depth of the side wall.
    _line(
      c,
      const Offset(64, 53),
      const Offset(91, 36),
      ClayShapes.dark(roof, 0.4),
      1.6,
    );
    _line(c, const Offset(86, 41), const Offset(86, 73), trim, 1.6);
    _line(c, const Offset(86, 73), const Offset(89, 75), trim, 1.6);
    // Foundation blocks and door steps anchor the building to its yard.
    for (var i = 0; i < 5; i++) {
      _line(
        c,
        Offset(14 + i * 9, 79 + i * 2.2),
        Offset(14 + i * 9, 83 + i * 2.2),
        ClayShapes.dark(wall, 0.35),
        0.65,
      );
    }
    for (var i = 0; i < 3; i++) {
      final y = 86 + i * 2.5;
      ClayShapes.form(
        c,
        _face([
          Offset(34 - i * 2, y - 2),
          Offset(53 + i * 2, y + 3),
          Offset(48 + i * 2, y + 6),
          Offset(29 - i * 2, y + 1),
        ]),
        ClayShapes.light(FarmlyColors.textSecondary, 0.48 - i * 0.06),
      );
    }
    if (house) {
      // A little workshop awning and lit recessed doorway, rather than a
      // blank house facade. Posts deliberately stay clear of the door.
      ClayShapes.form(
        c,
        _face(const [
          Offset(31, 57),
          Offset(54, 63),
          Offset(58, 58),
          Offset(36, 52),
        ]),
        ClayShapes.light(roof, 0.12),
      );
      _line(c, const Offset(31, 57), const Offset(31, 84), wood, 1.4);
      _line(c, const Offset(54, 63), const Offset(54, 90), wood, 1.4);
      // Window shutters and a flower box with individually shaded leaves.
      ClayShapes.form(
        c,
        _face(const [
          Offset(15, 49),
          Offset(18, 50),
          Offset(18, 63),
          Offset(15, 62),
        ]),
        ClayShapes.dark(roof, 0.06),
      );
      ClayShapes.form(
        c,
        _face(const [
          Offset(30, 53),
          Offset(33, 54),
          Offset(33, 67),
          Offset(30, 66),
        ]),
        ClayShapes.dark(roof, 0.06),
      );
      ClayShapes.form(
        c,
        _face(const [
          Offset(17, 64),
          Offset(31, 68),
          Offset(31, 72),
          Offset(17, 68),
        ]),
        wood,
      );
      for (var i = 0; i < 4; i++) {
        final p = Offset(18 + i * 3.5, 64 + i * 0.9);
        ClayShapes.leaf(
          c,
          p,
          p + const Offset(-2, -4),
          1.6,
          FarmlyColors.brandAction,
        );
        ClayShapes.oval(
          c,
          Rect.fromCenter(
            center: p + const Offset(0, -3),
            width: 2.8,
            height: 2.8,
          ),
          i.isEven
              ? FarmlyColors.illustrationBarn
              : FarmlyColors.semanticWarning,
        );
      }
      // Small side workbench and sacks create a recognizable working yard.
      _line(c, const Offset(72, 76), const Offset(72, 86), darkWood, 1.6);
      _line(c, const Offset(89, 66), const Offset(89, 77), darkWood, 1.6);
      ClayShapes.form(
        c,
        _face(const [
          Offset(68, 75),
          Offset(86, 64),
          Offset(93, 67),
          Offset(74, 79),
        ]),
        wood,
      );
      _crate(c, const Offset(81, 83), 10, wood);
    } else {
      // Open tool bay: dark reveal, lit shelf, handles and a hanging rake.
      ClayShapes.form(
        c,
        _face(const [
          Offset(25, 55),
          Offset(48, 61),
          Offset(48, 85),
          Offset(25, 79),
        ]),
        ClayShapes.dark(FarmlyColors.brandAction, 0.52),
      );
      for (var shelf = 0; shelf < 2; shelf++) {
        final y = 64.0 + shelf * 10;
        _line(c, Offset(27, y), Offset(46, y + 5), wood, 1.7);
        for (var j = 0; j < 3; j++) {
          ClayShapes.capsule(
            c,
            Rect.fromLTWH(28 + j * 5, y - 5 + j * 1.2, 3, 5),
            j.isEven ? ClayShapes.light(wall, 0.7) : wood,
          );
        }
      }
      // Sliding door parked beside the opening, with a roller rail.
      _line(c, const Offset(21, 51), const Offset(58, 60), trim, 1.6);
      ClayShapes.form(
        c,
        _face(const [
          Offset(49, 59),
          Offset(58, 61),
          Offset(58, 87),
          Offset(49, 85),
        ]),
        ClayShapes.light(wall, 0.25),
      );
      _line(
        c,
        const Offset(53, 62),
        const Offset(53, 85),
        ClayShapes.dark(wall, 0.2),
        0.6,
      );
      _line(c, const Offset(55, 72), const Offset(55, 76), trim, 1.4);
      // Rake and spade lean against the visible side wall.
      _line(c, const Offset(69, 77), const Offset(70, 59), wood, 1.1);
      _line(c, const Offset(66, 60), const Offset(74, 56), trim, 1.2);
      for (var j = 0; j < 4; j++) {
        _line(
          c,
          Offset(66 + j * 2.5, 60 - j * 1.2),
          Offset(66 + j * 2.5, 63 - j * 1.2),
          trim,
          0.7,
        );
      }
      _line(c, const Offset(78, 73), const Offset(80, 54), wood, 1.1);
      ClayShapes.form(
        c,
        _face(const [
          Offset(76, 70),
          Offset(81, 68),
          Offset(81, 75),
          Offset(78, 79),
          Offset(75, 75),
        ]),
        ClayShapes.light(FarmlyColors.textSecondary, 0.3),
      );
      // Crates and a planted barrel sit beside the entrance.
      _crate(c, const Offset(15, 84), 13, wood);
      _crate(c, const Offset(20, 76), 10, ClayShapes.light(wood, 0.16));
      _crate(c, const Offset(83, 85), 13, wood);
    }
    // Broad stepping stones lead out through a planted, grounded yard.
    for (var i = 0; i < 3; i++) {
      ClayShapes.oval(
        c,
        Rect.fromCenter(
          center: Offset(40 - i * 6, 96 + i * 1.2),
          width: 8 - i.toDouble(),
          height: 3,
        ),
        ClayShapes.light(FarmlyColors.textSecondary, 0.55),
      );
    }
  }

  static void _crate(Canvas c, Offset ground, double size, Color wood) {
    ClayShapes.shadow(c, ground + const Offset(0, 1), size * 1.4, size * 0.3);
    final x = ground.dx - size / 2, y = ground.dy - size;
    ClayShapes.form(
      c,
      _face([
        Offset(x, y),
        Offset(x + size, y + size * .2),
        Offset(x + size, y + size),
        Offset(x, y + size * .8),
      ]),
      wood,
    );
    ClayShapes.form(
      c,
      _face([
        Offset(x + size, y + size * .2),
        Offset(x + size * 1.3, y),
        Offset(x + size * 1.3, y + size * .8),
        Offset(x + size, y + size),
      ]),
      ClayShapes.dark(wood, 0.24),
    );
    for (var j = 1; j <= 2; j++) {
      _line(
        c,
        Offset(x, y + size * j / 3),
        Offset(x + size, y + size * (j / 3 + .2)),
        ClayShapes.dark(wood, 0.2),
        0.7,
      );
    }
    _line(
      c,
      Offset(x + size * .15, y + size * .2),
      Offset(x + size * .85, y + size * .85),
      ClayShapes.light(wood, 0.38),
      1,
    );
  }

  static void _window(Canvas canvas, List<Offset> p) {
    final path = _face(p);
    canvas.drawPath(
      path,
      Paint()
        ..color = FarmlyColors.surface
        ..style = PaintingStyle.stroke
        ..strokeWidth = 2.5,
    );
    ClayShapes.form(
      canvas,
      path,
      ClayShapes.dark(FarmlyColors.illustrationSky, 0.2),
    );
    _line(
      canvas,
      Offset.lerp(p[0], p[1], 0.5)!,
      Offset.lerp(p[3], p[2], 0.5)!,
      FarmlyColors.surface,
      0.9,
    );
    _line(
      canvas,
      Offset.lerp(p[0], p[3], 0.5)!,
      Offset.lerp(p[1], p[2], 0.5)!,
      FarmlyColors.surface,
      0.9,
    );
  }

  static void tank(Canvas canvas, {required Rect bounds}) {
    canvas.save();
    canvas.translate(bounds.left, bounds.top);
    canvas.scale(bounds.width / 100, bounds.height / 100);
    ClayShapes.shadow(canvas, const Offset(52, 88), 76, 14);
    final body = const Rect.fromLTWH(22, 23, 56, 61);
    canvas.drawRRect(
      RRect.fromRectAndRadius(body, const Radius.circular(9)),
      Paint()
        ..shader = LinearGradient(
          colors: [
            ClayShapes.light(FarmlyColors.brandSage, 0.86),
            FarmlyColors.surface,
            ClayShapes.dark(FarmlyColors.brandSage, 0.04),
          ],
          stops: const [0, 0.33, 1],
        ).createShader(body),
    );
    ClayShapes.oval(
      canvas,
      const Rect.fromLTWH(22, 72, 56, 18),
      ClayShapes.light(FarmlyColors.brandSage, 0.25),
    );
    // Decorative water window; never substitutes for a numeric sensor reading.
    ClayShapes.capsule(
      canvas,
      const Rect.fromLTWH(37, 41, 24, 34),
      FarmlyColors.illustrationWater,
    );
    _line(
      canvas,
      const Offset(41, 47),
      const Offset(41, 66),
      ClayShapes.light(FarmlyColors.illustrationWater, 0.6),
      2,
    );
    ClayShapes.oval(
      canvas,
      const Rect.fromLTWH(20, 16, 60, 22),
      ClayShapes.light(FarmlyColors.textSecondary, 0.45),
    );
    ClayShapes.oval(
      canvas,
      const Rect.fromLTWH(24, 17, 51, 16),
      FarmlyColors.surface,
    );
    ClayShapes.oval(
      canvas,
      const Rect.fromLTWH(41, 10, 18, 10),
      ClayShapes.light(FarmlyColors.textSecondary, 0.35),
    );
    ClayShapes.capsule(
      canvas,
      const Rect.fromLTWH(75, 40, 15, 8),
      ClayShapes.light(FarmlyColors.textSecondary, 0.5),
    );
    _line(
      canvas,
      const Offset(29, 34),
      const Offset(29, 73),
      FarmlyColors.surface.withValues(alpha: 0.7),
      2,
    );
    canvas.restore();
  }

  static void trough(Canvas canvas, {required Rect bounds}) {
    final rim = RRect.fromRectAndRadius(
      bounds,
      Radius.circular(bounds.height * 0.3),
    );
    canvas.drawRRect(
      rim.shift(Offset(0, bounds.height * 0.2)),
      ClayShapes.material(
        bounds,
        ClayShapes.dark(FarmlyColors.brandSage, 0.25),
      ),
    );
    canvas.drawRRect(
      rim,
      ClayShapes.material(
        bounds,
        ClayShapes.light(FarmlyColors.brandSage, 0.65),
      ),
    );
    final water = bounds.deflate(bounds.height * 0.18);
    canvas.drawRRect(
      RRect.fromRectAndRadius(water, Radius.circular(water.height * 0.25)),
      ClayShapes.material(water, FarmlyColors.illustrationWater),
    );
  }

  static void fence(Canvas canvas, {required Rect bounds}) {
    final wood = ClayShapes.light(FarmlyColors.semanticWarning, 0.3);
    for (final y in [
      bounds.top + bounds.height * 0.24,
      bounds.top + bounds.height * 0.7,
    ]) {
      ClayShapes.capsule(
        canvas,
        Rect.fromLTWH(bounds.left, y, bounds.width, 2.8),
        wood,
      );
    }
    for (var i = 0; i < 4; i++) {
      final x = bounds.left + bounds.width * (0.1 + i * 0.267);
      ClayShapes.capsule(
        canvas,
        Rect.fromLTWH(x - 1.6, bounds.top, 3.2, bounds.height),
        wood,
      );
      _line(
        canvas,
        Offset(x - 0.4, bounds.top + 2),
        Offset(x - 0.4, bounds.bottom - 2),
        ClayShapes.light(wood, 0.3),
        0.65,
      );
    }
  }
}
