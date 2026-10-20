import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:farmly_mobile/core/theme/farm_theme.dart';
import 'package:farmly_mobile/features/demo/demo_models.dart';
import 'package:farmly_mobile/features/demo/demo_providers.dart';
import 'package:farmly_mobile/features/home/home_screen.dart';
import 'package:farmly_mobile/l10n/generated/app_localizations.dart';
import 'package:farmly_mobile/ui/farm_card.dart';
import 'package:farmly_mobile/ui/illustrations.dart';
import 'package:farmly_mobile/ui/screen_states.dart';
import 'package:farmly_mobile/ui/summary_cards.dart';

void main() {
  Future<void> pumpHome(WidgetTester tester) async {
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
          locale: const Locale('vi'),
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          home: const HomeScreen(),
        ),
      ),
    );
    await tester.pump();
  }

  testWidgets('Home renders the health ring, weather, 2x2 stats and AI CTA', (
    tester,
  ) async {
    await pumpHome(tester);

    expect(find.textContaining('Chào'), findsWidgets);
    expect(find.byType(OperationsHealthRing), findsOneWidget);
    expect(find.byType(WeatherCard), findsOneWidget);
    expect(find.text('Trạng thái demo'), findsOneWidget);

    // The quick-stats grid sits below the first viewport of the home list,
    // so scroll to its heading before asserting (ListView builds children
    // lazily; the grid rows materialize once the heading is in view).
    expect(find.byType(Scrollable), findsOneWidget);
    await tester.scrollUntilVisible(
      find.text('Số liệu nhanh'),
      200,
      scrollable: find.byType(Scrollable),
    );
    expect(find.byType(StatTile), findsNWidgets(4));

    // The AI CTA sits below the first viewport of the home list, so scroll to
    // it before asserting (ListView builds children lazily). Positive delta
    // scrolls a down-axis list forward (controller.dart applies -delta as the
    // drag step).
    expect(find.byType(Scrollable), findsOneWidget);
    await tester.scrollUntilVisible(
      find.text('Hỏi Farmly AI'),
      200,
      scrollable: find.byType(Scrollable),
    );
    expect(find.text('Hỏi Farmly AI'), findsOneWidget);
  });

  testWidgets('Home banner opts into the detailed scene and stays still', (
    tester,
  ) async {
    addTearDown(tester.view.reset);

    for (final width in [360.0, 390.0, 412.0]) {
      tester.view.physicalSize = Size(width, 844);
      tester.view.devicePixelRatio = 1;

      await pumpHome(tester);

      final scene = find.byWidgetPredicate(
        (widget) => widget is CustomPaint && widget.painter is FarmScenePainter,
      );
      expect(scene, findsOneWidget);

      final painter = tester.widget<CustomPaint>(scene).painter!;
      expect(painter, isA<FarmScenePainter>());
      expect((painter as FarmScenePainter).homeBanner, isTrue);
      expect(painter.phase, 0);
      expect(tester.getSize(scene).width, greaterThan(0));
      expect(tester.getSize(scene).height, 150);
      expect(tester.takeException(), isNull);
    }
    expect(
      const FarmScenePainter().shouldRepaint(
        const FarmScenePainter(homeBanner: true),
      ),
      isTrue,
    );
  });

  testWidgets(
    'demo state switcher shows a layout-matching skeleton on loading',
    (tester) async {
      await pumpHome(tester);

      // Bounded pumps only: once a SkeletonSurface mounts, its shimmer keeps
      // scheduling frames forever, so pumpAndSettle would time out.
      await tester.tap(find.text('Trạng thái demo'));
      await tester.pump(); // build the sheet route
      await tester.pump(const Duration(milliseconds: 250)); // entrance done
      await tester.tap(find.text(DemoLoadState.loading.viLabel));
      await tester.pump(const Duration(milliseconds: 350)); // sheet pops

      expect(find.byType(SkeletonSurface), findsWidgets);
      expect(find.byType(OperationsHealthRing), findsNothing);

      // The offline state keeps the content with an explicit cached-data notice.
      await tester.tap(
        find.text('Trạng thái demo: ${DemoLoadState.loading.viLabel}'),
      );
      await tester.pump(); // build the sheet route
      await tester.pump(const Duration(milliseconds: 250)); // entrance done
      await tester.tap(find.text(DemoLoadState.offline.viLabel));
      await tester.pump(const Duration(milliseconds: 350)); // sheet pops
      expect(
        find.textContaining('Ngoại tuyến — đang hiển thị bản lưu'),
        findsOneWidget,
      );
      expect(find.byType(OperationsHealthRing), findsOneWidget);
    },
  );

  testWidgets(
    'compact Home keeps its greeting in loading, error, permission and empty states',
    (tester) async {
      tester.view.physicalSize = const Size(360, 844);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      tester.binding.platformDispatcher.textScaleFactorTestValue = 2;
      addTearDown(
        tester.binding.platformDispatcher.clearTextScaleFactorTestValue,
      );

      await pumpHome(tester);
      final container = ProviderScope.containerOf(
        tester.element(find.byType(HomeScreen)),
      );

      for (final state in const [
        DemoLoadState.loading,
        DemoLoadState.recoverableError,
        DemoLoadState.permissionDenied,
        DemoLoadState.empty,
      ]) {
        container.read(demoScreenStateProvider.notifier).set('home', state);
        await tester.pump();

        expect(find.text('Trang chủ'), findsOneWidget, reason: state.name);
        expect(find.textContaining('Chào'), findsOneWidget, reason: state.name);
        expect(
          tester.takeException(),
          isNull,
          reason: '200% text scale in ${state.name}',
        );
      }
    },
  );
}
