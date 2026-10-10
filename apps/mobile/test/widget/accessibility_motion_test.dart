import 'dart:ui' show Tristate;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:farmly_mobile/core/theme/farm_theme.dart';
import 'package:farmly_mobile/ui/farm_scaffold.dart';
import 'package:farmly_mobile/ui/screen_states.dart';

import '../support/farmly_shell_harness.dart';

LinearGradient _skeletonGradient(WidgetTester tester) {
  final surface = tester.widget<Container>(
    find.descendant(
      of: find.byType(SkeletonSurface),
      matching: find.byType(Container),
    ),
  );
  return (surface.decoration! as BoxDecoration).gradient! as LinearGradient;
}

void main() {
  testWidgets('reduced motion freezes skeleton and stops its ticker', (
    tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        theme: buildFarmTheme(),
        home: const MediaQuery(
          data: MediaQueryData(disableAnimations: true),
          child: Scaffold(
            body: Center(child: SkeletonSurface(width: 200, height: 24)),
          ),
        ),
      ),
    );
    await tester.pump();
    final before = _skeletonGradient(tester).begin;

    await tester.pump(const Duration(seconds: 2));

    expect(_skeletonGradient(tester).begin, before);
    expect(tester.binding.transientCallbackCount, 0);
  });

  testWidgets('skeleton shimmer animates when reduced motion is off', (
    tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        theme: buildFarmTheme(),
        home: const Scaffold(
          body: Center(child: SkeletonSurface(width: 200, height: 24)),
        ),
      ),
    );
    await tester.pump();
    final before = _skeletonGradient(tester).begin;

    await tester.pump(const Duration(milliseconds: 300));

    expect(_skeletonGradient(tester).begin, isNot(before));
  });

  testWidgets('bottom tabs expose selected button semantics and 48dp targets', (
    tester,
  ) async {
    final semantics = tester.ensureSemantics();

    await pumpFarmlyShell(tester);
    const labels = <String>[
      'Trang chủ',
      'Nông trại',
      'Phân tích',
      'Thu hoạch',
      'Cá nhân',
    ];
    for (var index = 0; index < labels.length; index++) {
      final label = labels[index];
      final tab = find.bySemanticsLabel(label);
      final data = tester.getSemantics(tab).getSemanticsData();
      expect(data.label, label);
      expect(data.flagsCollection.isButton, isTrue);
      expect(
        data.flagsCollection.isSelected,
        index == 0 ? Tristate.isTrue : Tristate.isFalse,
      );

      final visibleLabel = find.descendant(
        of: find.byType(AdaptiveBottomBar),
        matching: find.text(label),
      );
      final target = find.ancestor(
        of: visibleLabel,
        matching: find.byType(InkWell),
      );
      final targetSize = tester.getSize(target.first);
      expect(targetSize.width, greaterThanOrEqualTo(48), reason: label);
      expect(targetSize.height, greaterThanOrEqualTo(48), reason: label);
    }

    await tester.tap(find.bySemanticsLabel('Nông trại'));
    await tester.pumpAndSettle();
    final selectedFarm = tester
        .getSemantics(find.bySemanticsLabel('Nông trại'))
        .getSemanticsData();
    expect(selectedFarm.flagsCollection.isSelected, Tristate.isTrue);
    semantics.dispose();
  });
}
