import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:farmly_mobile/core/theme/farm_theme.dart';
import 'package:farmly_mobile/features/demo/demo_models.dart';
import 'package:farmly_mobile/features/demo/demo_providers.dart';
import 'package:farmly_mobile/features/farm/zone_detail_screen.dart';
import 'package:farmly_mobile/l10n/generated/app_localizations.dart';
import 'package:farmly_mobile/ui/farm_scaffold.dart';

import '../support/farmly_shell_harness.dart';

/// Phase 05 step 3 / D-01..04 (spec 02 §5, spec06): the crop-zone detail shows
/// schedule + manual progress truthfully — missing dates and ended plantings
/// are deliberate states, assessment/task writes land local-pending, and the
/// farm header formats area from canonical square metres.
void main() {
  void tallViewport(WidgetTester tester) {
    tester.view.physicalSize = const Size(900, 2000);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
  }

  Widget harness(String zoneId) {
    return ProviderScope(
      child: MaterialApp(
        theme: buildFarmTheme(),
        locale: const Locale('vi'),
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        home: ZoneDetailScreen(zoneId: zoneId),
      ),
    );
  }

  testWidgets('farm header formats hectares from square metres exactly', (
    tester,
  ) async {
    await pumpFarmlyShell(tester, viewport: const Size(500, 900));
    await tester.tap(
      find.descendant(
        of: find.byType(AdaptiveBottomBar),
        matching: find.text('Nông trại'),
      ),
    );
    await tester.pumpAndSettle();

    // Fixture stores '32000' m² — the header must read exactly 3.2 ha.
    expect(find.textContaining('3.2 ha'), findsOneWidget);
  });

  testWidgets('missing harvest date shows a deliberate unknown state', (
    tester,
  ) async {
    tallViewport(tester);
    await tester.pumpWidget(harness('zone-ca-chua'));
    await tester.pumpAndSettle();

    // Fixture: Cà chua has sowedOn but no expectedHarvestOn (D-04).
    expect(find.text('Cà chua'), findsOneWidget);
    expect(find.textContaining('chưa có ngày thu dự kiến'), findsOneWidget);
    expect(find.textContaining('Chưa có đánh giá tiến độ'), findsOneWidget);
    // No fabricated date ever renders.
    expect(find.textContaining('null'), findsNothing);
  });

  testWidgets('ended planting renders a tombstone and disables assessment', (
    tester,
  ) async {
    tallViewport(tester);
    await tester.pumpWidget(harness('zone-rau-an-la'));
    await tester.pumpAndSettle();

    await tester.ensureVisible(find.text('Cải xanh vụ trước'));
    await tester.pumpAndSettle();

    expect(find.text('Đã kết thúc'), findsWidgets);
    final button = tester.widget<OutlinedButton>(
      find.widgetWithText(OutlinedButton, 'Đã kết thúc'),
    );
    expect(button.onPressed, isNull);
  });

  testWidgets('manual assessment marks the crop local-pending', (
    tester,
  ) async {
    tallViewport(tester);
    await tester.pumpWidget(harness('zone-rau-an-la'));
    await tester.pumpAndSettle();

    await tester.ensureVisible(find.text('Cập nhật đánh giá'));
    await tester.tap(find.text('Cập nhật đánh giá'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Lưu đánh giá'));
    await tester.pumpAndSettle();

    expect(find.text('Chờ đồng bộ'), findsOneWidget);
    final container = ProviderScope.containerOf(
      tester.element(find.byType(ZoneDetailScreen)),
    );
    final state = container.read(demoDataProvider);
    expect(syncItemPending(state, 'sync-assess-crop-cai-ngot'), isTrue);
  });

  testWidgets('task entry adds a local-pending task to the zone', (
    tester,
  ) async {
    tallViewport(tester);
    await tester.pumpWidget(harness('zone-rau-an-la'));
    await tester.pumpAndSettle();

    await tester.ensureVisible(find.text('Thêm việc'));
    await tester.tap(find.text('Thêm việc'));
    await tester.pumpAndSettle();

    expect(find.text('Thêm việc cho vùng'), findsOneWidget);
    await tester.enterText(find.byType(TextField).first, 'Rải vôi đầu luống');
    await tester.tap(find.text('Lưu việc'));
    await tester.pumpAndSettle();

    expect(find.text('Rải vôi đầu luống'), findsOneWidget);
    final container = ProviderScope.containerOf(
      tester.element(find.byType(ZoneDetailScreen)),
    );
    final state = container.read(demoDataProvider);
    expect(
      state.syncItems.any(
        (item) =>
            item.operationType == 'task.create' &&
            item.status == DemoSyncStatus.localPending &&
            item.localSummary == 'Rải vôi đầu luống',
      ),
      isTrue,
    );
  });
}
