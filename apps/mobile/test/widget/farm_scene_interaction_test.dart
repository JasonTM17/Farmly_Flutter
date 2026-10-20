import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:farmly_mobile/core/theme/farm_theme.dart';
import 'package:farmly_mobile/features/demo/demo_models.dart';
import 'package:farmly_mobile/l10n/generated/app_localizations.dart';
import 'package:farmly_mobile/ui/zone_explorer.dart';
import 'package:farmly_mobile/ui/farm_scene_details.dart';
import 'package:farmly_mobile/ui/farm_scaffold.dart';
import 'package:farmly_mobile/features/farm/farm_overview_screen.dart';
import '../support/farmly_shell_harness.dart';

final _zones = <DemoZone>[
  for (var i = 0; i < 4; i++)
    DemoZone(
      id: 'crop-$i',
      farmId: 'farm',
      name: 'Rau $i',
      kind: DemoZoneKind.crop,
      x: 0.5,
      y: 0.5,
    ),
  const DemoZone(
    id: 'storage',
    farmId: 'farm',
    name: 'Kho nông cụ',
    kind: DemoZoneKind.storage,
    x: 0.5,
    y: 0.5,
  ),
  const DemoZone(
    id: 'house',
    farmId: 'farm',
    name: 'Nhà xưởng',
    kind: DemoZoneKind.house,
    x: 0.5,
    y: 0.5,
  ),
  const DemoZone(
    id: 'water',
    farmId: 'farm',
    name: 'Bồn nước',
    kind: DemoZoneKind.water,
    x: 0.5,
    y: 0.5,
  ),
];

Widget _harness({ValueChanged<DemoZone>? onOpen, List<DemoZone>? zones}) =>
    MaterialApp(
      theme: buildFarmTheme(),
      locale: const Locale('vi'),
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      supportedLocales: AppLocalizations.supportedLocales,
      builder: (context, child) => MediaQuery(
        data: MediaQuery.of(context).copyWith(disableAnimations: true),
        child: child!,
      ),
      home: Scaffold(
        body: ZoneScene(
          zones: zones ?? _zones,
          selectedZoneId: null,
          onSelect: (_) {},
          onOpenDetail: onOpen ?? (_) {},
        ),
      ),
    );

void main() {
  for (final entry in [
    ('Nhà xưởng', 'zone-nha-xuong'),
    ('Kho nông cụ', 'zone-kho'),
  ]) {
    testWidgets('${entry.$1} map tap reaches its real detail and back', (
      tester,
    ) async {
      final router = await pumpFarmlyShell(
        tester,
        viewport: const Size(500, 900),
      );
      await tester.tap(
        find.descendant(
          of: find.byType(AdaptiveBottomBar),
          matching: find.text('Nông trại'),
        ),
      );
      await tester.pumpAndSettle();
      await tester.tap(
        find.bySemanticsLabel('Vùng ${entry.$1}. Chạm để mở chi tiết.'),
      );
      await tester.pumpAndSettle();
      expect(router.state.uri.path, '/farm/zone/${entry.$2}');
      expect(find.byType(FarmBuildingInfo), findsOneWidget);
      expect(
        find.text('Chưa có cây trồng theo dõi trong khu này.'),
        findsNothing,
      );
      // pageBack() searches the English 'Back' tooltip, while this app is vi.
      expect(find.byType(BackButton), findsOneWidget);
      await tester.tap(find.byType(BackButton));
      await tester.pumpAndSettle();
      expect(find.byType(FarmOverviewScreen), findsOneWidget);
      expect(tester.takeException(), isNull);
    });
  }
  for (final name in ['Nhà xưởng', 'Kho nông cụ']) {
    testWidgets('one tap opens existing $name detail', (tester) async {
      tester.view.physicalSize = const Size(360, 800);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      DemoZone? opened;
      await tester.pumpWidget(_harness(onOpen: (zone) => opened = zone));
      await tester.pumpAndSettle();
      await tester.tap(
        find.bySemanticsLabel('Vùng $name. Chạm để mở chi tiết.'),
      );
      await tester.pumpAndSettle();
      expect(opened?.name, name);
      expect(opened?.farmId, 'farm');
    });
  }
  testWidgets('one tap opens crop, livestock, and water details', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(360, 800);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    DemoZone? opened;
    await tester.pumpWidget(
      _harness(
        zones: [
          ..._zones,
          const DemoZone(
            id: 'livestock',
            farmId: 'farm',
            name: 'Đàn bò',
            kind: DemoZoneKind.livestock,
            x: 0.5,
            y: 0.5,
          ),
        ],
        onOpen: (zone) => opened = zone,
      ),
    );
    await tester.pumpAndSettle();

    for (final entry in [
      ('Rau 0', 'crop-0'),
      ('Đàn bò', 'livestock'),
      ('Bồn nước', 'water'),
    ]) {
      await tester.tap(
        find.bySemanticsLabel('Vùng ${entry.$1}. Chạm để mở chi tiết.'),
      );
      await tester.pumpAndSettle();
      expect(opened?.id, entry.$2);
      opened = null;
    }
  });
  testWidgets('meadow has short title and opens a dismissible scene', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(360, 800);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(_harness());
    await tester.pumpAndSettle();
    expect(find.text('Đồng cỏ'), findsOneWidget);
    expect(find.textContaining('minh họa'), findsNothing);
    await tester.tap(find.byKey(const ValueKey('farm-meadow-hotspot')));
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('farm-meadow-sheet')), findsOneWidget);
    await tester.tap(find.byTooltip('Đóng'));
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('farm-meadow-sheet')), findsNothing);
    expect(tester.widget<ZoneScene>(find.byType(ZoneScene)).zones, _zones);
    expect(tester.takeException(), isNull);
  });
}
