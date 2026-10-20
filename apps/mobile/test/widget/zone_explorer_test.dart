import 'package:flutter/material.dart';
import 'package:flutter/semantics.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:farmly_mobile/core/theme/farm_theme.dart';
import 'package:farmly_mobile/features/demo/demo_models.dart';
import 'package:farmly_mobile/features/farm/farm_overview_screen.dart';
import 'package:farmly_mobile/features/farm/zone_detail_screen.dart';
import 'package:farmly_mobile/l10n/generated/app_localizations.dart';
import 'package:farmly_mobile/ui/farm_scaffold.dart';
import 'package:farmly_mobile/ui/motion.dart';
import 'package:farmly_mobile/ui/zone_explorer.dart';
import 'package:farmly_mobile/ui/farm_scene_accents.dart';

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

  Finder hotspotOf(String name) =>
      find.bySemanticsLabel(RegExp('Vùng $name\\. Chạm để mở chi tiết'));

  Widget explorerHarness({
    List<DemoZone> sceneZones = zones,
    bool reducedMotion = true,
    String? selectedId,
    ValueChanged<String?>? onSelect,
    ValueChanged<DemoZone>? onOpenDetail,
  }) {
    return MaterialApp(
      theme: buildFarmTheme(),
      // Explorer widgets read arb strings — pin the vi locale the assertions
      // below expect.
      locale: const Locale('vi'),
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      supportedLocales: AppLocalizations.supportedLocales,
      // Existing interaction tests stay deterministic by default. Animation
      // regressions opt in to the ambient loop and advance it with pump().
      builder: (context, child) => MediaQuery(
        data: MediaQuery.of(context).copyWith(disableAnimations: reducedMotion),
        child: child ?? const SizedBox.shrink(),
      ),
      home: Scaffold(
        body: Column(
          children: [
            ZoneChipStrip(
              zones: sceneZones,
              selectedZoneId: selectedId,
              onSelect: onSelect ?? (_) {},
            ),
            Expanded(
              child: ZoneScene(
                zones: sceneZones,
                selectedZoneId: selectedId,
                onSelect: (id) => onSelect?.call(id),
                onOpenDetail: onOpenDetail ?? (_) {},
              ),
            ),
          ],
        ),
      ),
    );
  }

  List<IsoZoneTilePainter> zonePainters(WidgetTester tester) => tester
      .widgetList<CustomPaint>(find.byType(CustomPaint))
      .map((paint) => paint.painter)
      .whereType<IsoZoneTilePainter>()
      .toList();

  double groundPhase(WidgetTester tester) {
    final groundPainters = tester
        .widgetList<CustomPaint>(find.byType(CustomPaint))
        .map((paint) => paint.painter)
        .where(
          (painter) =>
              painter.runtimeType.toString().contains('IsoGroundPainter'),
        )
        .toList();
    expect(groundPainters, hasLength(1));
    // The ground painter is intentionally library-private. Its public phase
    // field is inspected dynamically so the test can cover tree motion
    // without widening production visibility just for tests.
    return (groundPainters.single as dynamic).phase as double;
  }

  testWidgets('meadow opens its scene without adding an operational zone', (
    tester,
  ) async {
    var selections = 0;
    await tester.pumpWidget(explorerHarness(onSelect: (_) => selections++));
    await tester.pumpAndSettle();
    final meadow = find.bySemanticsLabel(RegExp('^Đồng cỏ, chạm để xem bò'));
    expect(meadow, findsOneWidget);
    final semantics = tester.getSemantics(meadow).getSemanticsData();
    expect(semantics.hasAction(SemanticsAction.tap), isTrue);
    expect(zonePainters(tester), hasLength(zones.length));
    expect(
      find.bySemanticsLabel(RegExp(r'^Vùng .*Chạm để mở chi tiết')),
      findsNWidgets(3),
    );
    expect(tester.widget<ZoneScene>(find.byType(ZoneScene)).zones, zones);
    await tester.tapAt(tester.getCenter(meadow));
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('farm-meadow-sheet')), findsOneWidget);
    await tester.tap(find.byTooltip('Đóng'));
    await tester.pumpAndSettle();
    expect(selections, 0);
    final meadowPainter = tester
        .widgetList<CustomPaint>(find.byType(CustomPaint))
        .map((paint) => paint.painter)
        .whereType<FarmMeadowPainter>()
        .single;
    expect(meadowPainter.phase, 0, reason: 'Reduced motion freezes cows too');
  });

  testWidgets('meadow only occupies genuinely vacant odd final right cells', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(360, 800);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    for (final count in [1, 2, 3, 4, 6, 7, 8]) {
      final sceneZones = List.generate(
        count,
        (index) => DemoZone(
          id: 'zone-$index',
          farmId: 'farm-1',
          name: 'Khu $index',
          kind: DemoZoneKind.crop,
          x: 0.3,
          y: 0.4,
        ),
      );
      await tester.pumpWidget(explorerHarness(sceneZones: sceneZones));
      await tester.pumpAndSettle();
      expect(
        find.bySemanticsLabel(RegExp('^Đồng cỏ, chạm để xem bò')),
        count >= 3 && count.isOdd ? findsOneWidget : findsNothing,
        reason: '$count real zones',
      );
      expect(zonePainters(tester), hasLength(count));
    }
  });

  testWidgets(
    'wide short viewport omits meadow when previous row cannot clear',
    (tester) async {
      tester.view.physicalSize = const Size(800, 600);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      final sceneZones = List.generate(
        7,
        (index) => DemoZone(
          id: 'zone-$index',
          farmId: 'farm-1',
          name: 'Khu $index',
          kind: DemoZoneKind.crop,
          x: 0.3,
          y: 0.4,
        ),
      );
      await tester.pumpWidget(explorerHarness(sceneZones: sceneZones));
      await tester.pumpAndSettle();
      expect(
        find.bySemanticsLabel(RegExp('^Đồng cỏ, chạm để xem bò')),
        findsNothing,
      );
      expect(zonePainters(tester), hasLength(7));
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'seven-zone fitted meadow clears reset and add controls at 360dp',
    (tester) async {
      tester.view.physicalSize = const Size(360, 800);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      final sceneZones = List.generate(
        7,
        (index) => DemoZone(
          id: 'zone-$index',
          farmId: 'farm-1',
          name: 'Khu $index',
          kind: DemoZoneKind.crop,
          x: 0.3,
          y: 0.4,
        ),
      );
      await tester.pumpWidget(
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
              zones: sceneZones,
              selectedZoneId: null,
              onSelect: (_) {},
              onOpenDetail: (_) {},
              onAdd: () {},
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      final meadowRect = tester.getRect(
        find.bySemanticsLabel(RegExp('^Đồng cỏ, chạm để xem bò')),
      );
      final resetRect = tester.getRect(find.byTooltip('Đặt lại khung nhìn'));
      final addRect = tester.getRect(
        find
            .ancestor(
              of: find.byIcon(Icons.add),
              matching: find.byType(InkWell),
            )
            .first,
      );
      final geometry = 'meadow=$meadowRect reset=$resetRect add=$addRect';
      expect(
        meadowRect.overlaps(resetRect.inflate(8)),
        isFalse,
        reason: 'Keep 8dp clear of reset: $geometry',
      );
      expect(
        meadowRect.overlaps(addRect.inflate(8)),
        isFalse,
        reason: 'Keep 8dp clear of add: $geometry',
      );
      final sceneRect = tester.getRect(find.byType(ZoneScene));
      expect(sceneRect.contains(meadowRect.topLeft), isTrue);
      expect(sceneRect.contains(meadowRect.bottomRight), isTrue);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'crop, tree and livestock art share ambient phase; reduced motion freezes it',
    (tester) async {
      await tester.pumpWidget(explorerHarness(reducedMotion: false));
      await tester.pump(const Duration(milliseconds: 250));

      final animatedTiles = zonePainters(tester);
      expect(animatedTiles, hasLength(zones.length));
      expect(
        animatedTiles.map((painter) => painter.phase).toSet(),
        hasLength(1),
      );
      expect(animatedTiles.first.phase, greaterThan(0));
      expect(groundPhase(tester), animatedTiles.first.phase);

      await tester.pumpWidget(explorerHarness(reducedMotion: true));
      await tester.pump(const Duration(milliseconds: 500));
      expect(zonePainters(tester).map((painter) => painter.phase).toSet(), {
        0.0,
      });
      expect(groundPhase(tester), 0);
    },
  );

  testWidgets('ambient motion advances smoothly at 60 steps per second', (
    tester,
  ) async {
    var phase = 0.0;
    Widget harness({required bool reducedMotion}) => MaterialApp(
      builder: (context, child) => MediaQuery(
        data: MediaQuery.of(context).copyWith(disableAnimations: reducedMotion),
        child: child ?? const SizedBox.shrink(),
      ),
      home: Scaffold(
        body: FarmAmbientLoop(
          period: const Duration(seconds: 1),
          builder: (context, value) {
            phase = value;
            return const SizedBox.expand();
          },
        ),
      ),
    );

    await tester.pumpWidget(harness(reducedMotion: false));
    await tester.pump(const Duration(milliseconds: 17));
    expect(phase, closeTo(1 / 60, 0.001));
    await tester.pump(const Duration(milliseconds: 17));
    expect(phase, closeTo(2 / 60, 0.001));

    await tester.pumpWidget(harness(reducedMotion: true));
    await tester.pump(const Duration(milliseconds: 200));
    expect(phase, 0);
    expect(tester.takeException(), isNull);
  });

  testWidgets('ambient loop keeps a finite still phase for sub-step periods', (
    tester,
  ) async {
    for (final period in [
      Duration.zero,
      const Duration(milliseconds: 8),
      const Duration(milliseconds: 12),
      const Duration(milliseconds: 24),
    ]) {
      var phase = double.nan;
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: FarmAmbientLoop(
              key: ValueKey(period.inMicroseconds),
              period: period,
              builder: (context, value) {
                phase = value;
                return const SizedBox.expand();
              },
            ),
          ),
        ),
      );
      await tester.pump(const Duration(seconds: 1));

      expect(phase, 0);
      expect(phase.isFinite, isTrue);
      expect(tester.binding.transientCallbackCount, 0);
      expect(tester.takeException(), isNull);
    }
  });

  testWidgets('ambient loop stops when its period becomes too short', (
    tester,
  ) async {
    var period = const Duration(seconds: 1);
    var phase = 0.0;
    Widget harness() => MaterialApp(
      home: Scaffold(
        body: FarmAmbientLoop(
          period: period,
          builder: (context, value) {
            phase = value;
            return const SizedBox.expand();
          },
        ),
      ),
    );

    await tester.pumpWidget(harness());
    await tester.pump(const Duration(milliseconds: 17));
    expect(phase, closeTo(1 / 60, 0.001));

    period = const Duration(milliseconds: 12);
    await tester.pumpWidget(harness());
    await tester.pump(const Duration(seconds: 1));

    expect(phase, 0);
    expect(tester.binding.transientCallbackCount, 0);
    expect(tester.takeException(), isNull);
  });

  testWidgets('smallest moving ambient period advances at 60Hz', (
    tester,
  ) async {
    var phase = 0.0;
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: FarmAmbientLoop(
            period: const Duration(milliseconds: 25),
            builder: (context, value) {
              phase = value;
              return const SizedBox.expand();
            },
          ),
        ),
      ),
    );

    await tester.pump(const Duration(milliseconds: 17));

    expect(phase, closeTo(0.5, 0.001));
    expect(tester.binding.transientCallbackCount, 1);
    expect(tester.takeException(), isNull);
  });

  testWidgets('dust puff reuses its ticker across reduced-motion changes', (
    tester,
  ) async {
    Widget harness({required bool reducedMotion}) => MaterialApp(
      builder: (context, child) => MediaQuery(
        data: MediaQuery.of(context).copyWith(disableAnimations: reducedMotion),
        child: child ?? const SizedBox.shrink(),
      ),
      home: const Scaffold(
        body: SizedBox(
          width: 48,
          height: 24,
          child: FarmDustPuff(delay: Duration.zero),
        ),
      ),
    );

    await tester.pumpWidget(harness(reducedMotion: false));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 80));
    await tester.pumpWidget(harness(reducedMotion: true));
    await tester.pump();
    await tester.pumpWidget(harness(reducedMotion: false));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 80));
    await tester.pumpWidget(harness(reducedMotion: true));
    await tester.pump();
    await tester.pumpWidget(harness(reducedMotion: false));
    await tester.pump();

    expect(tester.takeException(), isNull);
  });

  testWidgets('dust puff restarts its pending delay after reduced motion', (
    tester,
  ) async {
    Widget harness({required bool reducedMotion}) => MaterialApp(
      builder: (context, child) => MediaQuery(
        data: MediaQuery.of(context).copyWith(disableAnimations: reducedMotion),
        child: child ?? const SizedBox.shrink(),
      ),
      home: const Scaffold(
        body: SizedBox(
          width: 48,
          height: 24,
          child: FarmDustPuff(delay: Duration(milliseconds: 100)),
        ),
      ),
    );

    double animationValue() =>
        (tester
                    .widget<AnimatedBuilder>(
                      find.descendant(
                        of: find.byType(FarmDustPuff),
                        matching: find.byType(AnimatedBuilder),
                      ),
                    )
                    .animation
                as Animation<double>)
            .value;

    await tester.pumpWidget(harness(reducedMotion: false));
    await tester.pump(const Duration(milliseconds: 40));
    expect(animationValue(), 0);

    await tester.pumpWidget(harness(reducedMotion: true));
    await tester.pump(const Duration(milliseconds: 40));
    await tester.pumpWidget(harness(reducedMotion: false));
    await tester.pump(const Duration(milliseconds: 40));

    // The first delay would have expired now if reduced motion had not
    // canceled it; the resumed puff must wait for a fresh full delay.
    expect(animationValue(), 0);

    await tester.pump(const Duration(milliseconds: 80));
    await tester.pump(const Duration(milliseconds: 17));
    expect(animationValue(), greaterThan(0));
    expect(tester.takeException(), isNull);
  });

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

    await tester.tap(
      find.descendant(
        of: find.byType(ZoneChipStrip),
        matching: find.text(zones[1].name),
      ),
    );
    await tester.pump();
    expect(selected, zones[1].id);
  });

  testWidgets('scene renders one semantic hotspot per zone id', (tester) async {
    await tester.pumpWidget(explorerHarness());

    for (final zone in zones) {
      expect(hotspotOf(zone.name), findsOneWidget);
    }
  });

  testWidgets(
    'hotspot tap selects, zooms in, and reset restores 48dp control',
    (tester) async {
      String? selected;
      // Stateful: the parent echoes selectedZoneId back into ZoneScene, which
      // is the single camera path (didUpdateWidget → focus/reset).
      await tester.pumpWidget(
        StatefulBuilder(
          builder: (context, setState) => explorerHarness(
            selectedId: selected,
            onSelect: (id) => setState(() => selected = id),
          ),
        ),
      );
      // The whole-board fit is applied post-frame — settle before tapping so
      // tiles sit at their transformed positions inside the clipped viewport.
      await tester.pumpAndSettle();

      final viewer = tester.widget<InteractiveViewer>(
        find.byType(InteractiveViewer),
      );
      final restScale = viewer.transformationController?.value
          .getMaxScaleOnAxis();

      await tester.tap(hotspotOf(zones[1].name));
      // InkWell defers onTap until the double-tap timeout (~300ms) elapses.
      await tester.pump(const Duration(milliseconds: 400));
      await tester.pumpAndSettle();
      expect(selected, zones[1].id);

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
      // Reset returns to the fitted board transform, not raw identity.
      expect(
        viewer.transformationController?.value.getMaxScaleOnAxis(),
        closeTo(restScale!, 0.001),
      );
    },
  );

  testWidgets('accessible list exposes the same ids and opens detail', (
    tester,
  ) async {
    DemoZone? opened;
    await tester.pumpWidget(
      MaterialApp(
        theme: buildFarmTheme(),
        locale: const Locale('vi'),
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
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
