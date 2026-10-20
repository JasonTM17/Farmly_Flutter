import 'package:flutter/material.dart';

import '../core/theme/farmly_colors.dart';

/// Matte, orthographic clay volumes. A shared upper-left light keeps the
/// small Canvas actors cohesive without textures, blur layers or a 3D engine.
abstract final class ClayShapes {
  static Color light(Color base, double amount) =>
      Color.lerp(base, FarmlyColors.surface, amount)!;

  static Color dark(Color base, double amount) =>
      Color.lerp(base, FarmlyColors.textPrimary, amount)!;

  static Paint material(Rect bounds, Color base) =>
      Paint()
        ..shader = RadialGradient(
          center: const Alignment(-0.42, -0.55),
          radius: 1.12,
          colors: [light(base, 0.35), base, dark(base, 0.28)],
          stops: const [0, 0.48, 1],
        ).createShader(bounds);

  static void oval(Canvas canvas, Rect bounds, Color base) {
    canvas.drawOval(bounds, material(bounds, base));
  }

  static void capsule(Canvas canvas, Rect bounds, Color base) {
    canvas.drawRRect(
      RRect.fromRectAndRadius(bounds, Radius.circular(bounds.shortestSide / 2)),
      material(bounds, base),
    );
  }

  static void form(Canvas canvas, Path path, Color base) {
    canvas.drawPath(path, material(path.getBounds(), base));
  }

  /// Three nested translucent ellipses keep the contact tight and the outer
  /// penumbra soft without a GPU blur for every tree or plant.
  static void shadow(
    Canvas canvas,
    Offset ground,
    double width,
    double height,
  ) {
    for (var layer = 0; layer < 3; layer++) {
      final factor = 1 - layer * 0.23;
      canvas.drawOval(
        Rect.fromCenter(
          center: ground,
          width: width * factor,
          height: height * factor,
        ),
        Paint()
          ..color = FarmlyColors.textPrimary.withValues(
            alpha: 0.035 + layer * 0.025,
          ),
      );
    }
  }

  /// Curved leaf with a raised midrib. The two Beziers form a plump almond,
  /// with a single shaded underside rather than a flat diamond.
  static void leaf(
    Canvas canvas,
    Offset root,
    Offset tip,
    double width,
    Color base,
  ) {
    final delta = tip - root;
    final normal = Offset(-delta.dy, delta.dx) / delta.distance;
    final middle = root + delta * 0.48;
    final path = Path()
      ..moveTo(root.dx, root.dy)
      ..quadraticBezierTo(
        middle.dx + normal.dx * width,
        middle.dy + normal.dy * width,
        tip.dx,
        tip.dy,
      )
      ..quadraticBezierTo(
        middle.dx - normal.dx * width * 0.7,
        middle.dy - normal.dy * width * 0.7,
        root.dx,
        root.dy,
      )
      ..close();
    form(canvas, path, base);
    canvas.drawLine(
      root + delta * 0.12,
      root + delta * 0.83,
      Paint()
        ..color = light(base, 0.35)
        ..strokeWidth = width * 0.08
        ..strokeCap = StrokeCap.round,
    );
  }
}
