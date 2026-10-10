import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:farmly_mobile/core/theme/farm_theme.dart';
import 'package:farmly_mobile/features/livestock/livestock_screen.dart';
import 'package:farmly_mobile/l10n/generated/app_localizations.dart';

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

  Widget harness() {
    return ProviderScope(
      child: MaterialApp(
        theme: buildFarmTheme(),
        locale: const Locale('vi'),
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        home: const LivestockScreen(),
      ),
    );
  }

  testWidgets('herds render grouped with mode labels and true headcounts', (
    tester,
  ) async {
    tallViewport(tester);
    await tester.pumpWidget(harness());
    await tester.pumpAndSettle();

    // Tracked herds: header + per-animal cards.
    expect(
      find.text('Bò lai Sind · Theo dõi từng con'),
      findsOneWidget,
    );
    expect(find.text('Bò Mai'), findsOneWidget);
    expect(find.text('Bò Hồng'), findsOneWidget);
    // Batch herd: one quantity card, no fabricated per-animal records.
    expect(find.text('Gà ri thả vườn · Đàn theo lô'), findsOneWidget);
    expect(
      find.textContaining('không có hồ sơ từng con'),
      findsOneWidget,
    );
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
    expect(
      find.textContaining('Theo dõi từng con: 3'),
      findsOneWidget,
    );
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

  testWidgets('category chips count headcount, not animal rows', (
    tester,
  ) async {
    tallViewport(tester);
    await tester.pumpWidget(harness());
    await tester.pumpAndSettle();

    // Chickens are a 120-head batch herd with zero animal records.
    expect(find.text('Gà (120)'), findsOneWidget);
    expect(find.text('Bò (2)'), findsOneWidget);
    expect(find.text('Cừu (1)'), findsOneWidget);
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
