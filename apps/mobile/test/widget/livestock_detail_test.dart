import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:farmly_mobile/core/theme/farm_theme.dart';
import 'package:farmly_mobile/features/demo/demo_models.dart';
import 'package:farmly_mobile/features/livestock/livestock_screen.dart';
import 'package:farmly_mobile/features/livestock/live_livestock.dart';
import 'package:farmly_mobile/l10n/generated/app_localizations.dart';
import 'package:farmly_mobile/ui/illustrations.dart';
import 'package:farmly_mobile/ui/livestock_components.dart';

/// Phase 05 step 4 / D-05 (spec 02 §5 Livestock, spec06): herds group into
/// batch vs tracked modes; headcount counts tracked-alive plus batch
/// quantities without double counting; sold/deceased records stay visible
/// but excluded; no fabricated clinical/health metric.
void main() {
  void tallViewport(WidgetTester tester) {
    tester.view.physicalSize = const Size(900, 2600);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
  }

  Widget harness({bool reducedMotion = true}) {
    return ProviderScope(
      overrides: [farmlyLivestockDemoPreviewProvider.overrideWithValue(true)],
      child: MaterialApp(
        theme: buildFarmTheme(),
        // Existing screen tests stay deterministic by default. Animation
        // regressions opt in and advance the shared loop with pump().
        builder: (context, child) => MediaQuery(
          data: MediaQuery.of(
            context,
          ).copyWith(disableAnimations: reducedMotion),
          child: child ?? const SizedBox.shrink(),
        ),
        locale: const Locale('vi'),
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        home: const LivestockScreen(),
      ),
    );
  }

  double portraitPhase(WidgetTester tester, Finder portrait) {
    final paint = tester.widget<CustomPaint>(
      find.descendant(of: portrait, matching: find.byType(CustomPaint)),
    );
    // The phase is a public painter field; dynamic keeps the assertions
    // compatible with the current static painter until P13 adds it.
    return (paint.painter as dynamic).phase as double;
  }

  testWidgets(
    'category portraits share one ambient phase at 44dp; records stay still',
    (tester) async {
      tallViewport(tester);
      await tester.pumpWidget(harness(reducedMotion: false));
      await tester.pump(const Duration(milliseconds: 400));

      final categoryCards = tester.widgetList<AnimalCategoryCard>(
        find.byType(AnimalCategoryCard),
      );
      expect(categoryCards, hasLength(DemoAnimalCategory.values.length));
      final categoryPhases = <double>[];
      for (final category in DemoAnimalCategory.values) {
        final card = find.byWidgetPredicate(
          (widget) =>
              widget is AnimalCategoryCard && widget.category == category,
        );
        final portrait = find.descendant(
          of: card,
          matching: find.byType(AnimalPortrait),
        );
        expect(portrait, findsOneWidget);
        expect(tester.getSize(portrait), const Size(44, 44));
        categoryPhases.add(portraitPhase(tester, portrait));
      }
      expect(categoryPhases.toSet(), hasLength(1));
      expect(categoryPhases.first, greaterThan(0));

      final recordPortraits = find.descendant(
        of: find.byType(AnimalCard),
        matching: find.byType(AnimalPortrait),
      );
      expect(recordPortraits, findsWidgets);
      for (final portrait in recordPortraits.evaluate()) {
        final finder = find.byWidget(portrait.widget);
        expect(portraitPhase(tester, finder), 0);
      }
    },
  );

  testWidgets(
    'reduced motion keeps all livestock category portraits at phase zero',
    (tester) async {
      tallViewport(tester);
      await tester.pumpWidget(harness(reducedMotion: true));
      await tester.pump(const Duration(milliseconds: 500));

      for (final category in DemoAnimalCategory.values) {
        final card = find.byWidgetPredicate(
          (widget) =>
              widget is AnimalCategoryCard && widget.category == category,
        );
        final portrait = find.descendant(
          of: card,
          matching: find.byType(AnimalPortrait),
        );
        expect(portraitPhase(tester, portrait), 0);
      }
    },
  );

  testWidgets('herds render grouped with mode labels and true headcounts', (
    tester,
  ) async {
    tallViewport(tester);
    await tester.pumpWidget(harness());
    await tester.pumpAndSettle();

    // Tracked herds: header + per-animal cards.
    expect(find.text('Bò lai Sind · Theo dõi từng con'), findsOneWidget);
    expect(find.text('Bò Mai'), findsOneWidget);
    expect(find.text('Bò Hồng'), findsOneWidget);
    // Batch herd: one quantity card, no fabricated per-animal records.
    expect(find.text('Gà ri thả vườn · Đàn theo lô'), findsOneWidget);
    expect(find.textContaining('không có hồ sơ từng con'), findsOneWidget);
  });

  testWidgets('farm headcount sums batch quantity and tracked-alive only', (
    tester,
  ) async {
    tallViewport(tester);
    await tester.pumpWidget(harness());
    await tester.pumpAndSettle();

    // bò: 2 alive (BO-03 sold) + cừu: 1 alive (CUU-02 deceased) + gà batch 120
    // → 123 total; no animal row is double-counted and sold/deceased are out.
    expect(find.textContaining('Tổng đàn: 123 con'), findsOneWidget);
    expect(find.textContaining('Theo dõi từng con: 3'), findsOneWidget);
    expect(find.textContaining('Đàn theo lô: 120'), findsOneWidget);
  });

  testWidgets('sold and deceased records stay visible but excluded', (
    tester,
  ) async {
    tallViewport(tester);
    await tester.pumpWidget(harness());
    await tester.pumpAndSettle();

    await tester.ensureVisible(find.text('Bò Đen'));
    expect(find.text('Đã bán'), findsOneWidget);
    await tester.ensureVisible(find.text('Cừu bé'));
    expect(find.text('Đã chết'), findsOneWidget);
    // Herd header still reports the alive-only count for bò.
    expect(find.text('Bò lai Sind · Theo dõi từng con'), findsOneWidget);
    expect(find.text('2 con'), findsWidgets);
  });

  testWidgets('category cards count headcount, not animal rows', (
    tester,
  ) async {
    tallViewport(tester);
    await tester.pumpWidget(harness());
    await tester.pumpAndSettle();

    // Chickens are a 120-head batch herd with zero animal records.
    final cards = find.byType(AnimalCategoryCard);
    expect(cards, findsNWidgets(DemoAnimalCategory.values.length));
    int countOf(DemoAnimalCategory category) => tester
        .widgetList<AnimalCategoryCard>(cards)
        .firstWhere((card) => card.category == category)
        .count;

    expect(countOf(DemoAnimalCategory.chickens), 120);
    expect(countOf(DemoAnimalCategory.cows), 2);
    expect(countOf(DemoAnimalCategory.sheep), 1);
  });

  testWidgets('no fictional clinical or health metric is rendered', (
    tester,
  ) async {
    tallViewport(tester);
    await tester.pumpWidget(harness());
    await tester.pumpAndSettle();

    expect(find.textContaining('sức khỏe'), findsNothing);
    expect(find.textContaining('Sức khỏe'), findsNothing);
    expect(find.textContaining('% khỏe'), findsNothing);
    expect(find.textContaining('health'), findsNothing);
  });
}
