import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:farmly_mobile/core/theme/farm_theme.dart';
import 'package:farmly_mobile/features/demo/demo_models.dart';
import 'package:farmly_mobile/features/demo/demo_providers.dart';
import 'package:farmly_mobile/features/farm/zone_detail_screen.dart';
import 'package:farmly_mobile/l10n/generated/app_localizations.dart';

/// D-17/D-18 (spec06, phase 05 step 5): the water-zone detail shows manual
/// capacity/stored/used/asOf, a deliberate unavailable-reading state, a manual
/// reading entry, and a Smart watering wizard that drafts an irrigation TASK —
/// never actuating a pump.
void main() {
  void tallViewport(WidgetTester tester) {
    tester.view.physicalSize = const Size(900, 1800);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
  }

  Widget harness({bool withoutReading = false}) {
    return ProviderScope(
      overrides: [
        if (withoutReading)
          demoDataProvider.overrideWith(_NoReadingDemoData.new),
      ],
      child: MaterialApp(
        theme: buildFarmTheme(),
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        home: const ZoneDetailScreen(zoneId: 'zone-bon-nuoc'),
      ),
    );
  }

  testWidgets('water zone shows tank capacity, stored, used and source', (
    tester,
  ) async {
    tallViewport(tester);
    await tester.pumpWidget(harness());
    await tester.pumpAndSettle();

    expect(find.text('Bồn nước 5000 lít'), findsOneWidget);
    expect(find.text('Dung tích 5000 lít'), findsOneWidget);
    expect(find.text('3200 L'), findsOneWidget);
    expect(find.text('450 L'), findsOneWidget);
    expect(find.textContaining('đồng hồ đọc tay'), findsWidgets);
    // No crop-assessment copy leaks onto a water zone.
    expect(find.textContaining('Đánh giá thủ công'), findsNothing);
  });

  testWidgets('missing reading shows a deliberate unavailable state', (
    tester,
  ) async {
    tallViewport(tester);
    await tester.pumpWidget(harness(withoutReading: true));
    await tester.pumpAndSettle();

    expect(
      find.textContaining('Chưa có số đo mực nước'),
      findsOneWidget,
    );
    // A fabricated live level must never appear.
    expect(find.text('Mực nước'), findsNothing);
  });

  testWidgets('manual reading updates stored litres with provenance', (
    tester,
  ) async {
    tallViewport(tester);
    await tester.pumpWidget(harness());
    await tester.pumpAndSettle();

    await tester.ensureVisible(find.text('Ghi số đo'));
    await tester.tap(find.text('Ghi số đo'));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField).first, '4100');
    await tester.tap(find.text('Lưu số đo'));
    await tester.pumpAndSettle();

    expect(find.text('4100 L'), findsOneWidget);
  });

  testWidgets('smart watering drafts a task and never actuates a device', (
    tester,
  ) async {
    tallViewport(tester);
    await tester.pumpWidget(harness());
    await tester.pumpAndSettle();

    await tester.ensureVisible(find.text('Smart watering'));
    await tester.tap(find.text('Smart watering'));
    await tester.pumpAndSettle();

    // The wizard states it only plans a task — no pump/device control.
    expect(find.text('Lập việc tưới nước'), findsOneWidget);
    expect(
      find.textContaining('Không bật/tắt máy bơm'),
      findsOneWidget,
    );

    await tester.enterText(find.byType(TextField).first, '250');
    await tester.tap(find.text('Lưu việc tưới'));
    await tester.pumpAndSettle();

    // The drafted irrigation task lands in the zone's task list.
    expect(find.textContaining('Tưới 250 lít'), findsOneWidget);
  });
}

class _NoReadingDemoData extends DemoDataNotifier {
  @override
  DemoDataState build() {
    final seeded = super.build();
    final tank = tankOfZone(seeded, 'zone-bon-nuoc');
    if (tank == null) return seeded;
    return seeded.copyWith(
      tanksByZone: {
        ...seeded.tanksByZone,
        'zone-bon-nuoc': [
          DemoWaterTank(
            id: tank.id,
            zoneId: tank.zoneId,
            name: tank.name,
            capacityLitres: tank.capacityLitres,
            source: tank.source,
          ),
        ],
      },
    );
  }
}
