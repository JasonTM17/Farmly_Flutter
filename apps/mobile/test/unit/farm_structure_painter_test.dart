import 'dart:io';
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:farmly_mobile/ui/farm_structure_painter.dart';

typedef _Draw = void Function(Canvas canvas, Rect bounds);

final _structures = <String, _Draw>{
  for (final kind in [FarmStructureKind.house, FarmStructureKind.storage])
    'detailed ${kind.name}': (canvas, bounds) => FarmStructurePainter.building(
      canvas,
      bounds: bounds,
      kind: kind,
      detailed: true,
    ),
  for (final kind in FarmStructureKind.values)
    kind.name: (canvas, bounds) =>
        FarmStructurePainter.building(canvas, bounds: bounds, kind: kind),
  'tank': (canvas, bounds) => FarmStructurePainter.tank(canvas, bounds: bounds),
  'fence': (canvas, bounds) =>
      FarmStructurePainter.fence(canvas, bounds: bounds),
  'trough': (canvas, bounds) =>
      FarmStructurePainter.trough(canvas, bounds: bounds),
};

Future<Uint8List> _render(_Draw draw) async {
  final recorder = ui.PictureRecorder();
  draw(Canvas(recorder), const Rect.fromLTWH(30, 30, 180, 150));
  final picture = recorder.endRecording();
  final image = await picture.toImage(256, 256);
  final data = await image.toByteData(format: ui.ImageByteFormat.rawRgba);
  image.dispose();
  picture.dispose();
  return data!.buffer.asUint8List();
}

void main() {
  testWidgets('structures render deterministic distinct volumes within frame', (
    tester,
  ) async {
    await tester.runAsync(() async {
      final renders = <String, Uint8List>{};
      for (final structure in _structures.entries) {
        final bytes = await _render(structure.value);
        expect(
          await _render(structure.value),
          orderedEquals(bytes),
          reason: structure.key,
        );
        var drawn = 0;
        var edgeAlpha = 0;
        for (var p = 0; p < 256 * 256; p++) {
          final alpha = bytes[p * 4 + 3];
          if (alpha > 0) drawn++;
          final x = p % 256;
          final y = p ~/ 256;
          if (x < 16 || x >= 240 || y < 16 || y >= 240) edgeAlpha += alpha;
        }
        expect(
          drawn,
          greaterThan(500),
          reason: '${structure.key} has visible geometry',
        );
        expect(
          edgeAlpha,
          0,
          reason: '${structure.key} retains room for contact shadow',
        );
        for (final previous in renders.entries) {
          expect(
            bytes,
            isNot(orderedEquals(previous.value)),
            reason: '${structure.key} differs from ${previous.key}',
          );
        }
        renders[structure.key] = bytes;
      }
    });
  });

  testWidgets('optional large structures contact sheet export', (tester) async {
    if (Platform.environment['FARMLY_EXPORT_STRUCTURE_PREVIEW'] != 'true') {
      return;
    }
    await tester.runAsync(() async {
      final recorder = ui.PictureRecorder();
      final canvas = Canvas(recorder)
        ..drawColor(const Color(0xfffffbf2), BlendMode.src);
      for (final entry in _structures.entries.indexed) {
        final index = entry.$1;
        final x = 34.0 + (index % 3) * 310;
        final y = 24.0 + (index ~/ 3) * 300;
        canvas.drawRRect(
          RRect.fromRectAndRadius(
            Rect.fromLTWH(x, y, 290, 272),
            const Radius.circular(24),
          ),
          Paint()..color = const Color(0xfff1efe3),
        );
        final infrastructure =
            entry.$2.key == 'fence' || entry.$2.key == 'trough';
        entry.$2.value(
          canvas,
          Rect.fromLTWH(
            x + 38,
            y + (infrastructure ? 90 : 18),
            214,
            infrastructure ? 80 : 228,
          ),
        );
      }
      final picture = recorder.endRecording();
      final image = await picture.toImage(1000, 630);
      final data = await image.toByteData(format: ui.ImageByteFormat.png);
      final output = File(
        '../../plans/261018-1810-farmly-clay-app-native/reports/structures-contact-sheet.png',
      );
      await output.parent.create(recursive: true);
      await output.writeAsBytes(data!.buffer.asUint8List());
      image.dispose();
      picture.dispose();
    });
  });
}
