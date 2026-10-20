import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:farmly_mobile/features/demo/demo_models.dart';
import 'package:farmly_mobile/ui/farm_scene_accents.dart';
import 'package:farmly_mobile/ui/farm_life_painter.dart';
import 'package:farmly_mobile/ui/farm_structure_painter.dart';
import 'package:farmly_mobile/ui/zone_explorer.dart';

typedef _Draw = void Function(Canvas canvas, double phase);
const _frame = 360;
const _bounds = Rect.fromLTWH(70, 85, 220, 180);

Future<Uint8List> _render(_Draw draw, double phase) async {
  final recorder = ui.PictureRecorder();
  draw(Canvas(recorder), phase);
  final picture = recorder.endRecording();
  final image = await picture.toImage(_frame, _frame);
  final data = await image.toByteData(format: ui.ImageByteFormat.rawRgba);
  image.dispose();
  picture.dispose();
  return data!.buffer.asUint8List();
}

void _meadow(Canvas canvas, double phase) {
  canvas.translate(30, 35);
  FarmMeadowPainter(phase: phase).paint(canvas, const Size(300, 216));
}

void main() {
  final accents = <String, _Draw>{
    'swimming fish': (canvas, phase) =>
        FarmSceneAccents.pondFish(canvas, bounds: _bounds, phase: phase),
    'full lettuce': (canvas, phase) => FarmSceneAccents.lettuce(
      canvas,
      ground: const Offset(180, 250),
      scale: 6,
      phase: phase,
      seed: 2,
    ),
    'full tomato': (canvas, phase) => FarmSceneAccents.tomato(
      canvas,
      ground: const Offset(180, 250),
      scale: 6,
      phase: phase,
      seed: 2,
    ),
    for (final kind in FarmStructureKind.values)
      '${kind.name} life': (canvas, phase) => FarmSceneAccents.buildingLife(
        canvas,
        bounds: _bounds,
        kind: kind,
        phase: phase,
      ),
    for (final golden in [false, true])
      golden ? 'golden butterfly' : 'butterfly': (canvas, phase) =>
          FarmSceneAccents.butterfly(
            canvas,
            bounds: _bounds,
            phase: phase,
            golden: golden,
          ),
    'lily': (canvas, phase) => FarmSceneAccents.lily(
      canvas,
      center: const Offset(180, 180),
      phase: phase,
      seed: 2,
    ),
    'meadow': _meadow,
  };

  for (final accent in accents.entries) {
    testWidgets(
      '${accent.key} is deterministic, visibly animated and seamless',
      (tester) async {
        await tester.runAsync(() async {
          final first = await _render(accent.value, 0);
          final repeated = await _render(accent.value, 0);
          final moved = await _render(accent.value, 0.125);
          final end = await _render(accent.value, 1);
          expect(repeated, orderedEquals(first));
          var visible = 0;
          var changed = 0;
          var seamError = 0;
          for (var i = 0; i < first.length; i++) {
            if (i % 4 == 3 && first[i] > 0) visible++;
            if (first[i] != moved[i]) changed++;
            seamError += (first[i] - end[i]).abs();
          }
          expect(
            visible,
            greaterThan(20),
            reason: 'The accent must draw geometry',
          );
          expect(
            changed,
            greaterThan(20),
            reason: 'Motion must affect its pixels',
          );
          expect(seamError / first.length, lessThan(0.01));
        });
      },
    );
  }

  testWidgets(
    'all accent silhouettes stay inside their scene frame at 24 poses',
    (tester) async {
      await tester.runAsync(() async {
        for (final accent in accents.entries) {
          for (var frame = 0; frame < 24; frame++) {
            final pixels = await _render(accent.value, frame / 24);
            var edgeAlpha = 0;
            for (var p = 0; p < _frame * _frame; p++) {
              final x = p % _frame;
              final y = p ~/ _frame;
              if (x < 12 || x >= _frame - 12 || y < 12 || y >= _frame - 12) {
                edgeAlpha += pixels[p * 4 + 3];
              }
            }
            expect(edgeAlpha, 0, reason: '${accent.key} pose $frame clips');
          }
        }
      });
    },
  );

  testWidgets('actual meadow retains two visible cows and both travel', (
    tester,
  ) async {
    await tester.runAsync(() async {
      // Neutral bright coat pixels distinguish cows from green terrain and
      // grass. The front fence is below these two separate animal lanes.
      final centers = <List<double>>[[], []];
      for (var frame = 0; frame < 24; frame++) {
        final pixels = await _render(_meadow, frame / 24);
        for (var lane = 0; lane < 2; lane++) {
          final region = lane == 0
              ? const Rect.fromLTWH(42, 88, 147, 70)
              : const Rect.fromLTWH(185, 122, 139, 68);
          var count = 0;
          var sumX = 0.0;
          for (var y = region.top.toInt(); y < region.bottom; y++) {
            for (var x = region.left.toInt(); x < region.right; x++) {
              final p = (y * _frame + x) * 4;
              final r = pixels[p];
              final g = pixels[p + 1];
              final b = pixels[p + 2];
              if (r > 190 &&
                  g > 185 &&
                  b > 175 &&
                  (r - g).abs() < 25 &&
                  (g - b).abs() < 25 &&
                  pixels[p + 3] > 220) {
                count++;
                sumX += x;
              }
            }
          }
          expect(
            count,
            greaterThan(180),
            reason: 'Cow $lane visible at $frame',
          );
          centers[lane].add(sumX / count);
        }
      }
      for (var lane = 0; lane < 2; lane++) {
        centers[lane].sort();
        expect(
          centers[lane].last - centers[lane].first,
          greaterThan(30),
          reason: 'Cow $lane must visibly travel, not merely breathe',
        );
      }
    });
  });

  test('meadow repaints only for a changed ambient phase', () {
    expect(
      const FarmMeadowPainter(
        phase: 0,
      ).shouldRepaint(const FarmMeadowPainter(phase: 0)),
      isFalse,
    );
    expect(
      const FarmMeadowPainter(
        phase: 0.25,
      ).shouldRepaint(const FarmMeadowPainter(phase: 0)),
      isTrue,
    );
  });

  testWidgets('fitted meadow preserves full cow proportions and bounds', (
    tester,
  ) async {
    await tester.runAsync(() async {
      bool coat(Uint8List pixels, int p) =>
          pixels[p] > 190 &&
          pixels[p + 1] > 185 &&
          pixels[p + 2] > 175 &&
          (pixels[p] - pixels[p + 1]).abs() < 25 &&
          (pixels[p + 1] - pixels[p + 2]).abs() < 25 &&
          pixels[p + 3] > 220;

      void fitted(Canvas canvas, double phase) {
        canvas.translate(30, 35);
        FarmMeadowPainter(phase: phase).paint(canvas, const Size(300, 154));
      }

      for (var frame = 0; frame < 24; frame++) {
        final phase = frame / 24;
        final pixels = await _render(fitted, phase);
        for (var lane = 0; lane < 2; lane++) {
          // Independent isotropic actor reference: terrain may be shallow,
          // but a cow's opaque body must retain the same horizontal AND
          // vertical silhouette. Sample only its expected coat, avoiding
          // contamination by the other cow, grass or the fence.
          final reference = await _render((canvas, phase) {
            FarmLifePainter.drawPastureAnimal(
              canvas,
              ground: Offset(
                30 + (29 + lane * 43) * 3,
                35 + (39 + lane * 12) * 154 / 72,
              ),
              scale: 3 * (lane == 0 ? 1.1 : 0.92),
              phase: phase,
              seed: lane + 5,
              form: FarmAnimalForm.cow,
              travel: 2,
            );
          }, phase);
          var expected = 0;
          var retained = 0;
          for (var p = 0; p < reference.length; p += 4) {
            if (coat(reference, p)) {
              expected++;
              if (coat(pixels, p)) retained++;
            }
          }
          expect(expected, greaterThan(180));
          expect(
            retained / expected,
            greaterThan(0.94),
            reason: 'Cow $lane retains natural full height at phase $phase',
          );
          if (frame == 0) {
            // Negative control reproduces the former terrain-inherited Y
            // compression without changing production source or baselines.
            final compressed = await _render((canvas, phase) {
              canvas.translate(
                30 + (29 + lane * 43) * 3,
                35 + (39 + lane * 12) * 154 / 72,
              );
              canvas.scale(3, 154 / 72);
              FarmLifePainter.drawPastureAnimal(
                canvas,
                ground: Offset.zero,
                scale: lane == 0 ? 1.1 : 0.92,
                phase: phase,
                seed: lane + 5,
                form: FarmAnimalForm.cow,
                travel: 2,
              );
            }, phase);
            var oldRetained = 0;
            for (var p = 0; p < reference.length; p += 4) {
              if (coat(reference, p) && coat(compressed, p)) oldRetained++;
            }
            expect(
              oldRetained / expected,
              lessThan(0.8),
              reason: 'The oracle must reject the former flattened cow',
            );
          }
        }
        var borderAlpha = 0;
        for (var p = 0; p < _frame * _frame; p++) {
          final x = p % _frame;
          final y = p ~/ _frame;
          if (x < 12 || x >= 348 || y < 12 || y >= 348) {
            borderAlpha += pixels[p * 4 + 3];
          }
        }
        expect(borderAlpha, 0, reason: 'Fitted silhouettes stay fully framed');
      }
    });
  });

  testWidgets('optional all-seven-zone and meadow phase contact sheet', (
    tester,
  ) async {
    if (Platform.environment['FARMLY_EXPORT_LIVING_PREVIEW'] != 'true') return;
    await (FontLoader('Be Vietnam Pro')
          ..addFont(rootBundle.load('assets/fonts/BeVietnamPro-Regular.ttf')))
        .load();
    await tester.runAsync(() async {
      const zones = <(String, DemoZoneKind)>[
        ('Rau ăn lá', DemoZoneKind.crop),
        ('Cà chua giàn', DemoZoneKind.crop),
        ('Chuồng gà', DemoZoneKind.livestock),
        ('Bồn nước', DemoZoneKind.water),
        ('Ruộng ngô', DemoZoneKind.crop),
        ('Kho nông cụ', DemoZoneKind.storage),
        ('Nhà xưởng', DemoZoneKind.house),
      ];
      final recorder = ui.PictureRecorder();
      final canvas = Canvas(recorder)
        ..drawColor(const Color(0xfffffbf2), BlendMode.src);
      for (final (phaseIndex, phase) in [0.0, 0.25, 0.5].indexed) {
        for (var index = 0; index < 8; index++) {
          final x = 22.0 + (index % 4) * 330;
          final y = 20.0 + phaseIndex * 580 + (index ~/ 4) * 280;
          final text = TextPainter(
            text: TextSpan(
              text: '${index < 7 ? zones[index].$1 : 'Đồng cỏ'} · phase $phase',
              style: const TextStyle(
                color: Colors.black,
                fontSize: 16,
                fontFamily: 'Be Vietnam Pro',
              ),
            ),
            textDirection: TextDirection.ltr,
          )..layout();
          text.paint(canvas, Offset(x, y));
          canvas.save();
          canvas.translate(x, y + 35);
          if (index < 7) {
            IsoZoneTilePainter(
              kind: zones[index].$2,
              selected: false,
              name: zones[index].$1,
              phase: phase,
            ).paint(canvas, const Size(300, 230));
          } else {
            FarmMeadowPainter(phase: phase).paint(canvas, const Size(300, 216));
          }
          canvas.restore();
        }
      }
      final picture = recorder.endRecording();
      final image = await picture.toImage(1340, 1760);
      final png = await image.toByteData(format: ui.ImageByteFormat.png);
      final exportDirectory =
          Platform.environment['FARMLY_LIVING_PREVIEW_DIR'] ??
          '../../plans/261018-1949-living-farm-polish/reports';
      final file = File('$exportDirectory/living-all-zones-phases.png');
      await file.parent.create(recursive: true);
      await file.writeAsBytes(png!.buffer.asUint8List());
      image.dispose();
      picture.dispose();
    });
  });
}
