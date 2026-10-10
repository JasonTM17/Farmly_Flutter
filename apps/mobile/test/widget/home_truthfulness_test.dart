import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:farmly_mobile/core/theme/farm_theme.dart';
import 'package:farmly_mobile/features/analytics/analytics_screen.dart';
import 'package:farmly_mobile/features/demo/demo_providers.dart';
import 'package:farmly_mobile/features/home/home_screen.dart';
import 'package:farmly_mobile/l10n/generated/app_localizations.dart';

/// Phase-07 home truthfulness (spec 06 D-14/D-15): weather renders only from
/// a cached snapshot with provenance, the livestock stat counts herd
/// headcount (not animal rows), and the health ring is unknown below the
/// five-eligible-occurrence minimum.
void main() {
  void tallViewport(WidgetTester tester) {
    tester.view.physicalSize = const Size(900, 2400);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
  }

  Widget harness({Widget? home}) {
    return ProviderScope(
      child: MaterialApp(
        theme: buildFarmTheme(),
        // Deterministic frames: ambient loops render statically
        // so pumpAndSettle terminates.
        builder: (context, child) => MediaQuery(
          data: MediaQuery.of(context).copyWith(disableAnimations: true),
          child: child ?? const SizedBox.shrink(),
        ),
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        home: home ?? const HomeScreen(),
      ),
    );
  }

  testWidgets('home renders the cached weather snapshot with provenance', (
    tester,
  ) async {
    tallViewport(tester);
    await tester.pumpWidget(harness());
    await tester.pumpAndSettle();

    // WeatherCard displays the rounded whole-degree reading.
    expect(find.text('27°C'), findsOneWidget);
    expect(find.text('Nhiều mây'), findsOneWidget);
    expect(
      find.textContaining('Open-Meteo (bộ nhớ đệm demo)'),
      findsOneWidget,
    );
    expect(find.textContaining('cập nhật 06:45'), findsOneWidget);
  });

  testWidgets('farm without a snapshot shows the unavailable card', (
    tester,
  ) async {
    tallViewport(tester);
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          demoDataProvider.overrideWith(_NoWeatherDemoData.new),
        ],
        child: MaterialApp(
          theme: buildFarmTheme(),
          // Deterministic frames: ambient loops render statically
          // so pumpAndSettle terminates.
          builder: (context, child) => MediaQuery(
            data: MediaQuery.of(context).copyWith(disableAnimations: true),
            child: child ?? const SizedBox.shrink(),
          ),
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          home: const HomeScreen(),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('Chưa có dữ liệu thời tiết'), findsOneWidget);
    // No fabricated reading leaks.
    expect(find.textContaining('°C'), findsNothing);
  });

  testWidgets('livestock stat counts headcount, not animal rows', (
    tester,
  ) async {
    tallViewport(tester);
    await tester.pumpWidget(harness());
    await tester.pumpAndSettle();

    // Batch herd (120) has zero animal rows — the stat must still show the
    // farm headcount 123, not the 4 tracked animal rows.
    expect(find.text('123'), findsWidgets);
  });

  testWidgets('health ring crosses the ≥5 eligible threshold at 4/5', (
    tester,
  ) async {
    tallViewport(tester);
    await tester.pumpWidget(harness());
    await tester.pumpAndSettle();

    final container = ProviderScope.containerOf(
      tester.element(find.byType(HomeScreen)),
    );
    final state = container.read(demoDataProvider);
    // 4 done + 1 skipped occurrences = 80% per D-14.
    expect(operationsHealthOf(state), 0.8);
    // A farm with fewer than 5 eligible occurrences stays unknown.
    expect(
      operationsHealthOf(
        state.copyWith(selectedFarmId: 'farm-moi'),
      ),
      isNull,
    );
  });

  testWidgets('voided harvests are excluded from analytics totals', (
    tester,
  ) async {
    final container = ProviderContainer();
    addTearDown(container.dispose);
    final notifier = container.read(demoDataProvider.notifier);
    notifier.voidHarvest('harvest-1', reason: 'Nhập nhầm');

    final state = container.read(demoDataProvider);
    final records = state.harvestsByFarm[farmBaViId]!;
    final voided = records.firstWhere((r) => r.id == 'harvest-1');
    expect(voided.countsTowardTotals, isFalse);
  });

  testWidgets('analytics CSV export mirrors the table with ISO dates', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(900, 2400);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
      ProviderScope(
        child: MaterialApp(
          theme: buildFarmTheme(),
          // Deterministic frames: ambient loops render statically
          // so pumpAndSettle terminates.
          builder: (context, child) => MediaQuery(
            data: MediaQuery.of(context).copyWith(disableAnimations: true),
            child: child ?? const SizedBox.shrink(),
          ),
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          home: const AnalyticsScreen(),
        ),
      ),
    );
    await tester.pumpAndSettle();

    await tester.scrollUntilVisible(
      find.text('Xuất CSV'),
      200,
      scrollable: find.byType(Scrollable).first,
    );
    await tester.tap(find.text('Xuất CSV'));
    await tester.pumpAndSettle();

    // The sheet renders the exact CSV: header labels plus ISO-date rows, no
    // dd/MM display labels leaking into the export (spec 02 §5 safe CSV).
    final preview = tester.widget<SelectableText>(
      find.byType(SelectableText),
    );
    expect(preview.data, contains('"ngay","thu_hoach_kg","cho_an_hoan_tat_pct"'));
    expect(preview.data, contains('"2026-'));
    expect(preview.data, isNot(contains('/')));

    // The widget test's platform channel doesn't persist clipboard content —
    // stub Clipboard.setData/getData so the button's await resolves inside
    // fake-async and the copied payload is observable.
    Object? clipboardContent;
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(SystemChannels.platform, (call) async {
      if (call.method == 'Clipboard.setData') {
        clipboardContent = (call.arguments as Map)['text'];
        return null;
      }
      if (call.method == 'Clipboard.getData') {
        return <String, Object?>{'text': clipboardContent};
      }
      return null;
    });
    addTearDown(
      () => TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(SystemChannels.platform, null),
    );

    await tester.tap(find.text('Sao chép CSV'));
    await tester.pump();
    expect(find.text('Đã sao chép CSV.'), findsOneWidget);
    expect(clipboardContent, equals(preview.data));
  });
}

class _NoWeatherDemoData extends DemoDataNotifier {
  @override
  DemoDataState build() {
    final seeded = super.build();
    return seeded.copyWith(weatherByFarm: const {});
  }
}
