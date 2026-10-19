import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:farmly_mobile/core/theme/farm_theme.dart';
import 'package:farmly_mobile/features/demo/demo_models.dart';
import 'package:farmly_mobile/l10n/generated/app_localizations.dart';
import 'package:farmly_mobile/ui/zone_explorer.dart';

/// Navigation-polish slice: the accessible zone directory renders a static
/// clay preview per kind, and the chip strip stays usable at 200% text.
void main() {
  const zones = [
    DemoZone(
      id: 'zone-crop',
      farmId: 'farm-1',
      name: 'Luống rau cải xanh hữu cơ',
      kind: DemoZoneKind.crop,
      x: 0.3,
      y: 0.4,
      subtitle: 'Luống A',
    ),
    DemoZone(
      id: 'zone-barn',
      farmId: 'farm-1',
      name: 'Chuồng gà ta thả vườn',
      kind: DemoZoneKind.livestock,
      x: 0.7,
      y: 0.6,
    ),
    DemoZone(
      id: 'zone-tank',
      farmId: 'farm-1',
      name: 'Bồn nước tưới tiêu',
      kind: DemoZoneKind.water,
      x: 0.5,
      y: 0.75,
      subtitle: '',
    ),
    DemoZone(
      id: 'zone-barn-store',
      farmId: 'farm-1',
      name: 'Kho nông cụ và vật tư',
      kind: DemoZoneKind.storage,
      x: 0.6,
      y: 0.2,
    ),
    DemoZone(
      id: 'zone-house',
      farmId: 'farm-1',
      name: 'Nhà xưởng chế biến nông sản sạch',
      kind: DemoZoneKind.house,
      x: 0.4,
      y: 0.9,
      subtitle: 'Tầng trệt',
    ),
  ];

  Widget directoryHarness({
    String? selectedId,
    ValueChanged<DemoZone>? onOpenDetail,
    double textScale = 1,
  }) {
    return MaterialApp(
      theme: buildFarmTheme(),
      locale: const Locale('vi'),
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      supportedLocales: AppLocalizations.supportedLocales,
      builder: (context, child) => MediaQuery(
        data: MediaQuery.of(
          context,
        ).copyWith(textScaler: TextScaler.linear(textScale)),
        child: child ?? const SizedBox.shrink(),
      ),
      home: Scaffold(
        body: ListView(
          children: [
            AccessibleZoneList(
              zones: zones,
              selectedZoneId: selectedId,
              onOpenDetail: onOpenDetail ?? (_) {},
            ),
          ],
        ),
      ),
    );
  }

  Widget stripHarness({
    String? selectedId,
    ValueChanged<String?>? onSelect,
    double textScale = 1,
  }) {
    return MaterialApp(
      theme: buildFarmTheme(),
      locale: const Locale('vi'),
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      supportedLocales: AppLocalizations.supportedLocales,
      builder: (context, child) => MediaQuery(
        data: MediaQuery.of(
          context,
        ).copyWith(textScaler: TextScaler.linear(textScale)),
        child: child ?? const SizedBox.shrink(),
      ),
      home: Scaffold(
        body: Column(
          children: [
            ZoneChipStrip(
              zones: zones,
              selectedZoneId: selectedId,
              onSelect: onSelect ?? (_) {},
              overviewLabel: 'Toàn cảnh',
            ),
          ],
        ),
      ),
    );
  }

  void use360Viewport(WidgetTester tester) {
    tester.view.physicalSize = const Size(360, 800);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
  }

  List<IsoZoneTilePainter> directoryPainters(WidgetTester tester) => tester
      .widgetList<CustomPaint>(
        find.descendant(
          of: find.byType(AccessibleZoneList),
          matching: find.byType(CustomPaint),
        ),
      )
      .map((paint) => paint.painter)
      .whereType<IsoZoneTilePainter>()
      .toList();

  testWidgets('directory renders a named static preview for every kind', (
    tester,
  ) async {
    use360Viewport(tester);
    await tester.pumpWidget(directoryHarness());
    await tester.pump();

    expect(directoryPainters(tester), hasLength(zones.length));
    for (final zone in zones) {
      final preview = directoryPainters(
        tester,
      ).where((painter) => painter.name == zone.name).single;
      expect(preview.kind, zone.kind, reason: zone.name);
      expect(preview.selected, isFalse);
      expect(preview.phase, 0);
      expect(find.text(zone.name), findsOneWidget);
    }
  });

  testWidgets('selected row exposes explicit selected state and label', (
    tester,
  ) async {
    use360Viewport(tester);
    await tester.pumpWidget(directoryHarness(selectedId: zones[1].id));
    await tester.pump();

    final selectedNode = tester.getSemantics(
      find.bySemanticsLabel(
        RegExp('^Vùng Chuồng gà ta thả vườn, đang chọn\\. Mở chi tiết vùng\\.'),
      ),
    );
    expect(selectedNode.flagsCollection.isSelected, ui.Tristate.isTrue);

    // The explicit label keeps the pre-polish string byte-identical,
    // including the empty-subtitle comma.
    expect(
      find.bySemanticsLabel(
        RegExp('^Vùng Bồn nước tưới tiêu, \\. Mở chi tiết vùng\\.'),
      ),
      findsOneWidget,
    );
    expect(
      find.bySemanticsLabel(
        RegExp('^Vùng Kho nông cụ và vật tư\\. Mở chi tiết vùng\\.'),
      ),
      findsOneWidget,
    );
  });

  testWidgets('rows without a subtitle leave no blank subtitle gap', (
    tester,
  ) async {
    use360Viewport(tester);
    await tester.pumpWidget(directoryHarness());
    await tester.pump();

    for (final zone in zones) {
      final rowSemantics = find.bySemanticsLabel(RegExp('^Vùng ${zone.name}'));
      expect(rowSemantics, findsOneWidget);
      final texts = tester.widgetList<Text>(
        find.descendant(of: rowSemantics, matching: find.byType(Text)),
      );
      final expectedCount =
          1 + (zone.subtitle?.isNotEmpty ?? false ? 1 : 0) + 1;
      expect(
        texts,
        hasLength(expectedCount),
        reason: '${zone.name}: title + subtitle? + kind label',
      );
    }
  });

  testWidgets('directory tap reports the exact zone object', (tester) async {
    use360Viewport(tester);
    DemoZone? opened;
    await tester.pumpWidget(
      directoryHarness(onOpenDetail: (zone) => opened = zone),
    );
    await tester.pump();

    await tester.tap(find.text(zones[3].name));
    await tester.pump();
    expect(identical(opened, zones[3]), isTrue);

    await tester.tap(find.text(zones[0].name));
    await tester.pump();
    expect(identical(opened, zones[0]), isTrue);
  });

  for (final scale in [1.0, 2.0]) {
    testWidgets('directory fits 360dp at ${scale}x text with long names', (
      tester,
    ) async {
      use360Viewport(tester);
      await tester.pumpWidget(directoryHarness(textScale: scale));
      await tester.pump();
      expect(tester.takeException(), isNull);
      expect(find.byType(AccessibleZoneList), findsOneWidget);
    });

    testWidgets('chip strip keeps >=48dp targets at ${scale}x text', (
      tester,
    ) async {
      use360Viewport(tester);
      String? selected;
      await tester.pumpWidget(
        stripHarness(
          textScale: scale,
          selectedId: zones[0].id,
          onSelect: (id) => selected = id,
        ),
      );
      await tester.pump();
      expect(tester.takeException(), isNull);

      // The overview chip is always the first laid-out item — verify its
      // grid avatar and tap routing without scrolling.
      final overviewChip = find.ancestor(
        of: find.text('Toàn cảnh'),
        matching: find.byType(ChoiceChip),
      );
      expect(overviewChip, findsOneWidget);
      expect(
        find.descendant(
          of: overviewChip,
          matching: find.byIcon(Icons.grid_view_rounded),
        ),
        findsOneWidget,
      );
      await tester.tap(find.text('Toàn cảnh'));
      await tester.pump();
      expect(selected, isNull);

      // The strip is a lazy horizontal list — scroll each chip into view to
      // measure its touch target instead of asserting a fixed built count.
      final stripScrollable = find.descendant(
        of: find.byType(ZoneChipStrip),
        matching: find.byType(Scrollable),
      );
      final labels = ['Toàn cảnh', ...zones.map((zone) => zone.name)];
      for (final label in labels) {
        await tester.scrollUntilVisible(
          find.descendant(
            of: find.byType(ZoneChipStrip),
            matching: find.text(label),
          ),
          60,
          scrollable: stripScrollable,
        );
        final chipFinder = find.ancestor(
          of: find.text(label),
          matching: find.byType(ChoiceChip),
        );
        final chip = tester.widget<ChoiceChip>(chipFinder);
        expect(chip.showCheckmark, isFalse, reason: label);
        final size = tester.getSize(chipFinder);
        expect(size.height, greaterThanOrEqualTo(48), reason: label);
      }
      expect(
        find.descendant(
          of: find.byType(ZoneChipStrip),
          matching: find.byIcon(Icons.check),
        ),
        findsNothing,
      );
    });
  }

  testWidgets('chip strip height grows with scaled text', (tester) async {
    use360Viewport(tester);
    await tester.pumpWidget(stripHarness());
    await tester.pump();
    final normal = tester.getSize(find.byType(ZoneChipStrip)).height;
    expect(normal, greaterThanOrEqualTo(48));

    await tester.pumpWidget(stripHarness(textScale: 2));
    await tester.pump();
    final doubled = tester.getSize(find.byType(ZoneChipStrip)).height;
    expect(doubled, greaterThan(normal));
    expect(tester.takeException(), isNull);
  });

  testWidgets('directory creates no animation ticker', (tester) async {
    use360Viewport(tester);
    await tester.pumpWidget(directoryHarness());
    await tester.pump();
    expect(tester.binding.transientCallbackCount, 0);
    await tester.pump(const Duration(seconds: 1));
    expect(tester.binding.transientCallbackCount, 0);
  });
}
