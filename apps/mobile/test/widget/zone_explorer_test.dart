import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:farmly_mobile/core/theme/farm_theme.dart';
import 'package:farmly_mobile/features/demo/demo_models.dart';
import 'package:farmly_mobile/features/farm/farm_overview_screen.dart';
import 'package:farmly_mobile/features/farm/zone_detail_screen.dart';
import 'package:farmly_mobile/ui/farm_scaffold.dart';
import 'package:farmly_mobile/ui/zone_explorer.dart';

import '../support/farmly_shell_harness.dart';

/// V-03 (spec06): the My Farm explorer must show real zone chips, an
/// illustrated zoomable scene with hotspots, and an accessible list exposing
/// the SAME zone IDs — no fabricated aerial map.
void main() {
  const zones = [
    DemoZone(
      id: 'zone-crop',
      farmId: 'farm-1',
      name: 'Luống rau',
      kind: DemoZoneKind.crop,
      x: 0.3,
      y: 0.4,
      subtitle: 'Luống A',
    ),
    DemoZone(
      id: 'zone-barn',
      farmId: 'farm-1',
      name: 'Chuồng gà',
      kind: DemoZoneKind.livestock,
      x: 0.7,
      y: 0.6,
    ),
    DemoZone(
      id: 'zone-tank',
      farmId: 'farm-1',
      name: 'Bồn nước',
      kind: DemoZoneKind.water,
      x: 0.5,
      y: 0.75,
    ),
  ];

  Finder hotspotOf(String name) => find.bySemanticsLabel(
    RegExp('Vùng $name\\. Chạm để chọn'),
  );

  Widget explorerHarness({
    String? selectedId,
    ValueChanged<String>? onSelect,
    ValueChanged<DemoZone>? onOpenDetail,
  }) {
    return MaterialApp(
      theme: buildFarmTheme(),
      home: Scaffold(
        body: Column(
          children: [
            ZoneChipStrip(
              zones: zones,
              selectedZoneId: selectedId,
              onSelect: onSelect ?? (_) {},
            ),
            Expanded(
              child: ZoneScene(
                zones: zones,
                selectedZoneId: selectedId,
                onSelect: onSelect ?? (_) {},
                onOpenDetail: onOpenDetail ?? (_) {},
              ),
            ),
          ],
        ),
      ),
    );
  }

  testWidgets('chip strip exposes every zone id and reports selection', (
    tester,
  ) async {
    String? selected;
    await tester.pumpWidget(explorerHarness(onSelect: (id) => selected = id));

    for (final zone in zones) {
      expect(
        find.descendant(
          of: find.byType(ZoneChipStrip),
          matching: find.text(zone.name),
        ),
        findsOneWidget,
      );
    }

    await tester.tap(find.text(zones[1].name));
    await tester.pump();
    expect(selected, zones[1].id);
  });

  testWidgets('scene renders one semantic hotspot per zone id', (tester) async {
    await tester.pumpWidget(explorerHarness());

    for (final zone in zones) {
      expect(hotspotOf(zone.name), findsOneWidget);
    }
  });

  testWidgets('hotspot tap selects, zooms in, and reset restores 48dp control', (
    tester,
  ) async {
    String? selected;
    await tester.pumpWidget(explorerHarness(onSelect: (id) => selected = id));

    final hotspotInk = find.descendant(
      of: hotspotOf(zones[1].name),
      matching: find.byType(InkWell),
    );
    await tester.tap(hotspotInk);
    // InkWell defers onTap until the double-tap timeout (~300ms) elapses.
    await tester.pump(const Duration(milliseconds: 400));
    await tester.pumpAndSettle();
    expect(selected, zones[1].id);

    final viewer = tester.widget<InteractiveViewer>(
      find.byType(InteractiveViewer),
    );
    final scale = viewer.transformationController?.value.getMaxScaleOnAxis();
    expect(scale, isNotNull);
    expect(scale!, greaterThan(1.0));

    final reset = find.byTooltip('Đặt lại khung nhìn');
    expect(reset, findsOneWidget);
    final resetSize = tester.getSize(reset);
    expect(resetSize.width, greaterThanOrEqualTo(48));
    expect(resetSize.height, greaterThanOrEqualTo(48));
    await tester.tap(reset);
    await tester.pumpAndSettle();
    expect(
      viewer.transformationController?.value.getMaxScaleOnAxis(),
      closeTo(1.0, 0.001),
    );
  });

  testWidgets('accessible list exposes the same ids and opens detail', (
    tester,
  ) async {
    DemoZone? opened;
    await tester.pumpWidget(
      MaterialApp(
        theme: buildFarmTheme(),
        home: Scaffold(
          body: AccessibleZoneList(
            zones: zones,
            selectedZoneId: zones[0].id,
            onOpenDetail: (zone) => opened = zone,
          ),
        ),
      ),
    );

    for (final zone in zones) {
      expect(find.text(zone.name), findsOneWidget);
    }

    await tester.tap(find.text(zones[2].name));
    await tester.pump();
    expect(opened?.id, zones[2].id);
  });

  testWidgets('overview screen wires chips, scene and list with same ids', (
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

    expect(find.byType(ZoneScene), findsOneWidget);
    expect(find.byType(ZoneChipStrip), findsOneWidget);

    // Capture on-screen widgets before scrolling: the lazy ListView recycles
    // the strip/scene once they move above the fold.
    final strip = tester.widget<ZoneChipStrip>(find.byType(ZoneChipStrip));
    final scene = tester.widget<ZoneScene>(find.byType(ZoneScene));

    // The semantic list lives below the fold in the farm screen's vertical
    // Scrollable (not the horizontal chip strip) — scroll it to reach the list.
    final farmScrollable = find.descendant(
      of: find.byType(FarmOverviewScreen),
      matching: find.byWidgetPredicate(
        (widget) =>
            widget is Scrollable && widget.axisDirection == AxisDirection.down,
      ),
    );
    await tester.scrollUntilVisible(
      find.byType(AccessibleZoneList),
      400,
      scrollable: farmScrollable,
    );
    await tester.pumpAndSettle();
    expect(find.byType(AccessibleZoneList), findsOneWidget);

    final list = tester.widget<AccessibleZoneList>(
      find.byType(AccessibleZoneList),
    );
    final chipIds = strip.zones.map((z) => z.id).toSet();
    expect(scene.zones.map((z) => z.id).toSet(), equals(chipIds));
    expect(list.zones.map((z) => z.id).toSet(), equals(chipIds));
    expect(chipIds, isNotEmpty);

    // List navigation reaches the zone detail for the tapped zone.
    await tester.tap(
      find.descendant(
        of: find.byType(AccessibleZoneList),
        matching: find.text(list.zones.first.name),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.byType(ZoneDetailScreen), findsOneWidget);
    expect(find.text(list.zones.first.name), findsWidgets);
  });
}
