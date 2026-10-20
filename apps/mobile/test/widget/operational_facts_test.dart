import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:farmly_mobile/core/theme/farm_theme.dart';
import 'package:farmly_mobile/features/demo/demo_models.dart';
import 'package:farmly_mobile/features/demo/demo_providers.dart';
import 'package:farmly_mobile/features/farm/zone_detail_screen.dart';
import 'package:farmly_mobile/features/harvest/harvest_screen.dart';
import 'package:farmly_mobile/features/livestock/livestock_screen.dart';
import 'package:farmly_mobile/features/livestock/live_livestock.dart';
import 'package:farmly_mobile/l10n/generated/app_localizations.dart';
import 'package:farmly_mobile/ui/form_fields.dart';

/// Phase-06 mobile surfaces (spec02 task/harvest-correction/readings rows):
/// occurrence transitions with outbox intents, harvest correction lifecycle
/// gated by farm role, manual moisture/water/production facts, and batch
/// headcount deltas. All writes stay local-pending — nothing hits network.
void main() {
  void tallViewport(WidgetTester tester) {
    tester.view.physicalSize = const Size(900, 2200);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
  }

  Widget harness(Widget child) {
    return ProviderScope(
      overrides: [farmlyLivestockDemoPreviewProvider.overrideWithValue(true)],
      child: MaterialApp(
        theme: buildFarmTheme(),
        // Detail widgets read arb strings — pin the vi locale the assertions
        // below expect.
        locale: const Locale('vi'),
        // Deterministic frames: ambient loops render statically
        // so pumpAndSettle terminates.
        builder: (context, child) => MediaQuery(
          data: MediaQuery.of(context).copyWith(disableAnimations: true),
          child: child ?? const SizedBox.shrink(),
        ),
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        home: child,
      ),
    );
  }

  Future<void> scrollTo(
    WidgetTester tester,
    String text, {
    bool first = false,
  }) async {
    final finder = find.text(text);
    await tester.scrollUntilVisible(
      first ? finder.first : finder,
      200,
      scrollable: find.byType(Scrollable).last,
    );
    await tester.pumpAndSettle();
  }

  group('task occurrences', () {
    testWidgets(
      'completing a task enqueues a taskOccurrence.transition intent',
      (tester) async {
        tallViewport(tester);
        await tester.pumpWidget(
          harness(const ZoneDetailScreen(zoneId: 'zone-rau-an-la')),
        );
        await tester.pumpAndSettle();

        await scrollTo(tester, 'Bón phân bổ sung');
        final checkboxFinder = find.descendant(
          of: find
              .ancestor(
                of: find.text('Bón phân bổ sung'),
                matching: find.byType(Row),
              )
              .first,
          matching: find.byType(Checkbox),
        );
        expect(tester.widget<Checkbox>(checkboxFinder).value, isFalse);

        await tester.tap(checkboxFinder);
        await tester.pumpAndSettle();

        final container = ProviderScope.containerOf(
          tester.element(find.byType(ZoneDetailScreen)),
        );
        final items = container.read(demoDataProvider).syncItems;
        expect(
          items.any(
            (i) =>
                i.operationType == 'taskOccurrence.transition' &&
                i.localSummary.contains('Bón phân bổ sung'),
          ),
          isTrue,
        );
      },
    );

    testWidgets('overdue and assignee states render non-color indicators', (
      tester,
    ) async {
      tallViewport(tester);
      await tester.pumpWidget(
        harness(const ZoneDetailScreen(zoneId: 'zone-rau-an-la')),
      );
      await tester.pumpAndSettle();

      await scrollTo(tester, 'Kiểm tra rệp luống 2');
      expect(find.textContaining('Quá hạn'), findsWidgets);
      expect(find.textContaining('Minh'), findsWidgets);
      expect(find.textContaining('Chưa phân công'), findsWidgets);
    });
  });

  group('harvest corrections', () {
    testWidgets('worker proposes a correction; manager applies it', (
      tester,
    ) async {
      tallViewport(tester);
      await tester.pumpWidget(harness(const HarvestScreen()));
      await tester.pumpAndSettle();

      // Worker role: proposal only.
      final container = ProviderScope.containerOf(
        tester.element(find.byType(HarvestScreen)),
      );
      container.read(demoFarmRoleProvider.notifier).set(DemoFarmRole.worker);
      await tester.pumpAndSettle();

      await tester.tap(find.text('Cải ngọt').first);
      await tester.pumpAndSettle();
      expect(find.text('Gửi đề xuất'), findsOneWidget);
      expect(
        find.textContaining('đề xuất chỉnh sửa để quản lý'),
        findsOneWidget,
      );

      await tester.enterText(
        find.widgetWithText(DecimalField, 'Khối lượng mới (kg)'),
        '13.0',
      );
      await tester.enterText(
        find.widgetWithText(TextField, 'Lý do chỉnh sửa'),
        'Cân lại đúng là 13.0',
      );
      await tester.tap(find.text('Gửi đề xuất'));
      await tester.pumpAndSettle();

      final state = container.read(demoDataProvider);
      final record = state.harvestsByFarm[farmBaViId]!.firstWhere(
        (r) => r.cropLabel == 'Cải ngọt',
      );
      expect(record.status, DemoHarvestStatus.correctionPending);
      expect(record.correction?.proposedQuantityKg, '13.0');
      // Original quantity still counts — the proposal is not effective yet.
      expect(record.quantityKg, '12.5');
      expect(
        state.syncItems.any(
          (i) => i.operationType == 'harvest.correction.propose',
        ),
        isTrue,
      );

      // Manager role: apply the proposal.
      container.read(demoFarmRoleProvider.notifier).set(DemoFarmRole.manager);
      await tester.pumpAndSettle();
      await tester.tap(find.text('Cải ngọt').first);
      await tester.pumpAndSettle();
      expect(find.text('Áp dụng'), findsOneWidget);
      await tester.tap(find.text('Áp dụng'));
      await tester.pumpAndSettle();

      final applied = container
          .read(demoDataProvider)
          .harvestsByFarm[farmBaViId]!
          .firstWhere((r) => r.cropLabel == 'Cải ngọt');
      expect(applied.status, DemoHarvestStatus.confirmed);
      expect(applied.quantityKg, '13.0');
      expect(
        container
            .read(demoDataProvider)
            .syncItems
            .any((i) => i.operationType == 'harvest.correction.apply'),
        isTrue,
      );
    });

    testWidgets('manager voids a record with a reason; totals exclude it', (
      tester,
    ) async {
      tallViewport(tester);
      await tester.pumpWidget(harness(const HarvestScreen()));
      await tester.pumpAndSettle();

      final container = ProviderScope.containerOf(
        tester.element(find.byType(HarvestScreen)),
      );
      final before = container
          .read(demoDataProvider)
          .harvestsByFarm[farmBaViId]!
          .where((r) => r.countsTowardTotals)
          .fold<double>(0, (s, r) => s + double.parse(r.quantityKg));

      await tester.tap(find.text('Cải ngọt').first);
      await tester.pumpAndSettle();
      await tester.enterText(
        find.widgetWithText(TextField, 'Lý do huỷ bản ghi'),
        'Nhập nhầm lô hàng',
      );
      await tester.tap(find.text('Huỷ bản ghi'));
      await tester.pumpAndSettle();

      final records = container
          .read(demoDataProvider)
          .harvestsByFarm[farmBaViId]!;
      final voided = records.firstWhere((r) => r.cropLabel == 'Cải ngọt');
      expect(voided.status, DemoHarvestStatus.voided);
      final after = records
          .where((r) => r.countsTowardTotals)
          .fold<double>(0, (s, r) => s + double.parse(r.quantityKg));
      expect(after, before - 12.5);
      expect(
        container
            .read(demoDataProvider)
            .syncItems
            .any((i) => i.operationType == 'harvest.void'),
        isTrue,
      );
    });

    testWidgets('viewer role sees no correction or void controls', (
      tester,
    ) async {
      tallViewport(tester);
      await tester.pumpWidget(harness(const HarvestScreen()));
      await tester.pumpAndSettle();

      final container = ProviderScope.containerOf(
        tester.element(find.byType(HarvestScreen)),
      );
      container.read(demoFarmRoleProvider.notifier).set(DemoFarmRole.viewer);
      await tester.pumpAndSettle();

      await tester.tap(find.text('Cải ngọt').first);
      await tester.pumpAndSettle();
      expect(find.text('Gửi đề xuất'), findsNothing);
      expect(find.text('Huỷ bản ghi'), findsNothing);
    });
  });

  group('manual facts', () {
    testWidgets('moisture reading lands on the zone and the outbox', (
      tester,
    ) async {
      tallViewport(tester);
      await tester.pumpWidget(
        harness(const ZoneDetailScreen(zoneId: 'zone-rau-an-la')),
      );
      await tester.pumpAndSettle();

      // Two crops in the zone each render a moisture entry — use the first.
      await scrollTo(tester, 'Đo độ ẩm', first: true);
      await tester.tap(find.text('Đo độ ẩm').first);
      await tester.pumpAndSettle();
      await tester.enterText(find.byType(TextField).last, '47.5');
      await tester.tap(find.text('Lưu số đo'));
      await tester.pumpAndSettle();

      final container = ProviderScope.containerOf(
        tester.element(find.byType(ZoneDetailScreen)),
      );
      final state = container.read(demoDataProvider);
      expect(
        state.moistureByZone['zone-rau-an-la']?.first.valuePercent,
        '47.5',
      );
      expect(
        state.syncItems.any((i) => i.operationType == 'moistureReading.create'),
        isTrue,
      );
    });

    testWidgets(
      'water usage updates usedToday and enqueues waterUsage.create',
      (tester) async {
        tallViewport(tester);
        await tester.pumpWidget(
          harness(const ZoneDetailScreen(zoneId: 'zone-bon-nuoc')),
        );
        await tester.pumpAndSettle();

        await scrollTo(tester, 'Ghi đã dùng');
        await tester.tap(find.text('Ghi đã dùng'));
        await tester.pumpAndSettle();
        await tester.enterText(find.byType(TextField).last, '300');
        await tester.tap(find.text('Lưu'));
        await tester.pumpAndSettle();

        final container = ProviderScope.containerOf(
          tester.element(find.byType(ZoneDetailScreen)),
        );
        final state = container.read(demoDataProvider);
        final tank = state.tanksByZone['zone-bon-nuoc']!.first;
        expect(tank.usedTodayLitres, '750'); // 450 seeded + 300 new
        expect(
          state.syncItems.any((i) => i.operationType == 'waterUsage.create'),
          isTrue,
        );
      },
    );

    testWidgets('production record appends to a herd with its own unit', (
      tester,
    ) async {
      tallViewport(tester);
      await tester.pumpWidget(harness(const LivestockScreen()));
      await tester.pumpAndSettle();

      final container = ProviderScope.containerOf(
        tester.element(find.byType(LivestockScreen)),
      );
      container
          .read(demoDataProvider.notifier)
          .recordProduction(
            'herd-bo',
            product: 'milk',
            quantity: '14.25',
            unit: 'lít',
          );
      final state = container.read(demoDataProvider);
      expect(state.productionByHerd['herd-bo']?.first.quantity, '14.25');
      expect(state.productionByHerd['herd-bo']?.first.unit, 'lít');
      expect(
        state.syncItems.any(
          (i) => i.operationType == 'productionRecord.create',
        ),
        isTrue,
      );
    });

    testWidgets('batch movement adjusts headcount by signed delta', (
      tester,
    ) async {
      tallViewport(tester);
      await tester.pumpWidget(harness(const LivestockScreen()));
      await tester.pumpAndSettle();

      final container = ProviderScope.containerOf(
        tester.element(find.byType(LivestockScreen)),
      );
      container
          .read(demoDataProvider.notifier)
          .recordBatchMovement('herd-ga', -8, 'Bán ra chợ');
      final herd = container
          .read(demoDataProvider)
          .herdsByFarm[farmBaViId]!
          .firstWhere((h) => h.id == 'herd-ga');
      expect(herd.batchQuantity, 112); // 120 - 8
      expect(
        container
            .read(demoDataProvider)
            .syncItems
            .any((i) => i.operationType == 'livestockMovement.create'),
        isTrue,
      );
    });
  });
}
