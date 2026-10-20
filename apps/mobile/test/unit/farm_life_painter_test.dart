import 'dart:io';
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:farmly_mobile/features/demo/demo_models.dart';
import 'package:farmly_mobile/ui/farm_life_painter.dart';
import 'package:farmly_mobile/ui/clay_shapes.dart';

typedef _Actor = void Function(Canvas canvas, double phase);
typedef _Plant =
    void Function(
      Canvas canvas, {
      required Offset ground,
      required double scale,
      required double phase,
      required int seed,
    });

Future<Uint8List> _pixels(_Actor actor, double phase) async {
  final recorder = ui.PictureRecorder();
  actor(Canvas(recorder), phase);
  final picture = recorder.endRecording();
  final image = await picture.toImage(256, 256);
  final data = await image.toByteData(format: ui.ImageByteFormat.rawRgba);
  image.dispose();
  picture.dispose();
  return data!.buffer.asUint8List();
}

final _plants = <String, _Plant>{
  'tree': FarmLifePainter.drawTree,
  'lettuce': FarmLifePainter.drawLeafyPlant,
  'tomatoes': FarmLifePainter.drawTomatoPlant,
  'corn': FarmLifePainter.drawCornStalk,
  'grass': FarmLifePainter.drawGrassTuft,
};

void main() {
  final actors = <String, _Actor>{
    for (final category in DemoAnimalCategory.values)
      'portrait ${category.name}': (canvas, phase) {
        canvas.translate(40, 40);
        FarmLifePainter.drawAnimalPortrait(
          canvas,
          size: const Size(176, 176),
          category: category,
          phase: phase,
        );
      },
    for (final plant in _plants.entries)
      plant.key: (canvas, phase) => plant.value(
        canvas,
        ground: const Offset(128, 190),
        scale: 4,
        phase: phase,
        seed: 2,
      ),
    for (final form in FarmAnimalForm.values)
      'pasture ${form.name}': (canvas, phase) =>
          FarmLifePainter.drawPastureAnimal(
            canvas,
            ground: const Offset(128, 190),
            scale: 4,
            phase: phase,
            seed: 2,
            form: form,
          ),
  };

  for (final entry in actors.entries) {
    testWidgets('${entry.key} deterministic, bounded, animated and seamless', (
      tester,
    ) async {
      await tester.runAsync(() async {
        final zero = await _pixels(entry.value, 0);
        final repeat = await _pixels(entry.value, 0);
        final quarter = await _pixels(entry.value, 0.25);
        final end = await _pixels(entry.value, 1);
        expect(
          repeat,
          orderedEquals(zero),
          reason: 'Identical phase must be stable',
        );
        var changed = 0;
        var seamError = 0;
        var opaque = 0;
        var borderAlpha = 0;
        for (var i = 0; i < zero.length; i++) {
          if (zero[i] != quarter[i]) changed++;
          seamError += (zero[i] - end[i]).abs();
          if (i % 4 == 3) {
            final pixel = i ~/ 4;
            final x = pixel % 256;
            final y = pixel ~/ 256;
            if (zero[i] > 0) opaque++;
            if (x < 8 || x >= 248 || y < 8 || y >= 248) {
              borderAlpha += zero[i] + quarter[i] + end[i];
            }
          }
        }
        expect(opaque, greaterThan(100), reason: 'Actor must actually render');
        expect(
          changed,
          greaterThan(20),
          reason: 'Phase must visibly affect actor',
        );
        expect(
          seamError / zero.length,
          lessThan(0.01),
          reason: 'A 0/1 loop seam may differ only by tiny raster rounding',
        );
        expect(
          borderAlpha,
          0,
          reason: 'Keep actor inside its frame across phases',
        );
      });
    });
  }

  testWidgets('walking animals and grass stay bounded through 48 loop poses', (
    tester,
  ) async {
    await tester.runAsync(() async {
      for (final entry in actors.entries.where(
        (entry) => entry.key.startsWith('pasture ') || entry.key == 'grass',
      )) {
        for (var frame = 0; frame < 48; frame++) {
          final pixels = await _pixels(entry.value, frame / 48);
          var edgeAlpha = 0;
          for (var y = 0; y < 256; y++) {
            for (var x = 0; x < 256; x++) {
              if (x < 8 || x >= 248 || y < 8 || y >= 248) {
                edgeAlpha += pixels[(y * 256 + x) * 4 + 3];
              }
            }
          }
          expect(edgeAlpha, 0, reason: '${entry.key} frame $frame clips');
        }
      }
    });
  });

  test(
    'pasture lane travels, slows before turning and closes at all seeds',
    () {
      for (var seed = 0; seed < 8; seed++) {
        final start = FarmLifePainter.pastureWalk(0, seed);
        final end = FarmLifePainter.pastureWalk(1, seed);
        expect((start.offset - end.offset).distance, lessThan(1e-10));
        expect((start.stride - end.stride).abs(), lessThan(1e-10));
        for (var frame = 0; frame < 96; frame++) {
          final pose = FarmLifePainter.pastureWalk(frame / 96, seed);
          expect(pose.offset.dx.abs(), lessThanOrEqualTo(5));
          expect(pose.offset.dy.abs(), lessThanOrEqualTo(1.4));
          if (pose.speed < 0.05) {
            expect(pose.stride.abs(), lessThan(0.1));
          }
        }
      }
      expect(FarmLifePainter.pastureWalk(0.25, 0).offset.dx, closeTo(5, 1e-9));
      expect(FarmLifePainter.pastureWalk(0.75, 0).offset.dx, closeTo(-5, 1e-9));
    },
  );

  testWidgets('every pasture species actually translates on Canvas', (
    tester,
  ) async {
    await tester.runAsync(() async {
      Offset centroid(Uint8List pixels) {
        var mass = 0.0;
        var sumX = 0.0;
        var sumY = 0.0;
        for (var p = 0; p < 256 * 256; p++) {
          final alpha = pixels[p * 4 + 3].toDouble();
          mass += alpha;
          sumX += (p % 256) * alpha;
          sumY += (p ~/ 256) * alpha;
        }
        return Offset(sumX / mass, sumY / mass);
      }

      for (final form in FarmAnimalForm.values) {
        void draw(Canvas canvas, double phase) =>
            FarmLifePainter.drawPastureAnimal(
              canvas,
              ground: const Offset(128, 190),
              scale: 4,
              phase: phase,
              seed: 0,
              form: form,
            );
        final first = centroid(await _pixels(draw, 0.125));
        final opposite = centroid(await _pixels(draw, 0.625));
        expect(
          (first.dx - opposite.dx).abs(),
          greaterThan(10),
          reason: '${form.name} must move across its lane, not only bob',
        );
      }
    });
  });

  testWidgets('turning preserves every species readable opaque silhouette', (
    tester,
  ) async {
    await tester.runAsync(() async {
      int opaqueWidth(Uint8List bytes) {
        var left = 256;
        var right = -1;
        for (var p = 0; p < 256 * 256; p++) {
          // Contact shadows remain translucent; only actual animal geometry
          // determines readable width at the turnaround.
          if (bytes[p * 4 + 3] > 220) {
            final x = p % 256;
            if (x < left) left = x;
            if (x > right) right = x;
          }
        }
        return right - left + 1;
      }

      for (final form in FarmAnimalForm.values) {
        void draw(Canvas canvas, double phase) =>
            FarmLifePainter.drawPastureAnimal(
              canvas,
              ground: const Offset(128, 190),
              scale: 4,
              phase: phase,
              seed: 0,
              form: form,
            );
        final fullWidth = opaqueWidth(await _pixels(draw, 0));
        for (final phase in const [0.25, 0.75]) {
          final turnWidth = opaqueWidth(await _pixels(draw, phase));
          expect(
            turnWidth / fullWidth,
            greaterThan(0.65),
            reason:
                '${form.name} must remain recognizable while turning at $phase',
          );
        }
      }
    });
  });

  testWidgets('chicken feet alternate relative to the moving body', (
    tester,
  ) async {
    await tester.runAsync(() async {
      Future<(double, double)> feet(double phase) async {
        void draw(Canvas canvas, double t) => FarmLifePainter.drawPastureAnimal(
          canvas,
          ground: const Offset(128, 190),
          scale: 4,
          phase: t,
          seed: 0,
          form: FarmAnimalForm.chicken,
        );
        final bytes = await _pixels(draw, phase);
        final offset = FarmLifePainter.pastureWalk(phase, 0).offset;
        final centers = <double>[];
        for (final range in const [(-7.0, 0.0), (0.0, 10.0)]) {
          var mass = 0.0;
          var xSum = 0.0;
          for (var y = 0; y < 256; y++) {
            final localY = (y - 190) / 4 - offset.dy;
            if (localY < 0.35 || localY > 2) continue;
            for (var x = 0; x < 256; x++) {
              final localX = (x - 128) / 4 - offset.dx;
              final alpha = bytes[(y * 256 + x) * 4 + 3];
              if (localX >= range.$1 && localX < range.$2 && alpha > 220) {
                mass += alpha;
                xSum += localX * alpha;
              }
            }
          }
          expect(
            mass,
            greaterThan(0),
            reason: 'visible ${range.$1} foot at $phase',
          );
          centers.add(xSum / mass);
        }
        return (centers[0], centers[1]);
      }

      final forward = await feet(1 / 32);
      final backward = await feet(5 / 32);
      expect(forward.$1 - backward.$1, greaterThan(0.5));
      expect(forward.$2 - backward.$2, lessThan(-0.5));
    });
  });

  testWidgets(
    'grass blades remain attached to five ground roots while swaying',
    (tester) async {
      await tester.runAsync(() async {
        void draw(Canvas canvas, double phase) => FarmLifePainter.drawGrassTuft(
          canvas,
          ground: const Offset(128, 190),
          scale: 4,
          phase: phase,
          seed: 2,
        );
        // Tapered Bezier roots can cover less than half a pixel at 4x.
        // Compare against the contact shadow so anti-aliased blade geometry,
        // rather than an arbitrary opacity threshold, proves root contact.
        final shadow = await _pixels((canvas, phase) {
          canvas.translate(128, 190);
          canvas.scale(4);
          ClayShapes.shadow(canvas, const Offset(0.5, 0.7), 12, 2.4);
        }, 0);
        for (var frame = 0; frame < 24; frame++) {
          final pixels = await _pixels(draw, frame / 24);
          for (var blade = 0; blade < 5; blade++) {
            final rootX = (128 + (blade - 2) * 0.65 * 4).round();
            var rootAlpha = 0;
            for (var y = 187; y < 190; y++) {
              for (var x = rootX - 1; x <= rootX + 1; x++) {
                final channel = (y * 256 + x) * 4 + 3;
                final alpha = pixels[channel] - shadow[channel];
                if (alpha > rootAlpha) rootAlpha = alpha;
              }
            }
            expect(
              rootAlpha,
              greaterThan(16),
              reason: 'blade $blade retains root at frame $frame',
            );
          }
        }
      });
    },
  );

  testWidgets('optional clay artwork export', (tester) async {
    if (Platform.environment['FARMLY_EXPORT_CLAY_PREVIEW'] != 'true') return;
    await tester.runAsync(() async {
      final directory = Directory(
        Platform.environment['FARMLY_CLAY_PREVIEW_DIR'] ??
            '../../plans/261018-1744-farm-life-clay-3d/reports/clay-preview',
      );
      await directory.create(recursive: true);
      for (var frame = 0; frame < 24; frame++) {
        final phase = frame / 24;
        final recorder = ui.PictureRecorder();
        final canvas = Canvas(recorder);
        canvas.drawColor(const Color(0xfffffbf2), BlendMode.src);
        canvas.drawRRect(
          RRect.fromRectAndRadius(
            const Rect.fromLTWH(24, 24, 752, 214),
            const Radius.circular(28),
          ),
          Paint()..color = const Color(0xfff1efe3),
        );
        for (final category in DemoAnimalCategory.values) {
          canvas.save();
          canvas.translate(68 + category.index * 178, 43);
          FarmLifePainter.drawAnimalPortrait(
            canvas,
            size: const Size(132, 132),
            category: category,
            phase: phase,
          );
          canvas.restore();
        }
        for (final plant in _plants.entries.indexed) {
          plant.$2.value(
            canvas,
            ground: Offset(85 + plant.$1 * 150, 354),
            scale: 2.8,
            phase: phase,
            seed: 2,
          );
        }
        for (final form in FarmAnimalForm.values.take(4)) {
          FarmLifePainter.drawPastureAnimal(
            canvas,
            ground: Offset(110 + form.index * 180, 444),
            scale: 2.7,
            phase: phase,
            seed: form.index,
            form: form,
          );
        }
        final picture = recorder.endRecording();
        final image = await picture.toImage(800, 480);
        final png = await image.toByteData(format: ui.ImageByteFormat.png);
        await File(
          '${directory.path}/clay-frame-${frame.toString().padLeft(3, '0')}.png',
        ).writeAsBytes(png!.buffer.asUint8List());
        image.dispose();
        picture.dispose();
      }
      final recorder = ui.PictureRecorder();
      final canvas = Canvas(recorder)
        ..drawColor(const Color(0xfffffbf2), BlendMode.src);
      FarmLifePainter.drawGrassTuft(
        canvas,
        ground: const Offset(160, 220),
        scale: 12,
        phase: 0,
        seed: 2,
      );
      final picture = recorder.endRecording();
      final grass = await picture.toImage(320, 260);
      final png = await grass.toByteData(format: ui.ImageByteFormat.png);
      await File(
        '${directory.path}/grass-frame-000.png',
      ).writeAsBytes(png!.buffer.asUint8List());
      grass.dispose();
      picture.dispose();
    });
  });
}
