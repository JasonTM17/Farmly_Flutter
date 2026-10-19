import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:farmly_mobile/core/theme/farm_theme.dart';
import 'package:farmly_mobile/features/demo/demo_models.dart';
import 'package:farmly_mobile/l10n/generated/app_localizations.dart';
import 'package:farmly_mobile/ui/zone_explorer.dart';

/// Golden coverage for the navigation-polish slice only: the accessible zone
/// directory's static clay previews and the adaptive chip strip, at 360dp in
/// normal and 200% text. Existing goldens are not regenerated here.
void main() {
  setUpAll(() async {
    final fontLoader = FontLoader('Be Vietnam Pro')
      ..addFont(rootBundle.load('assets/fonts/BeVietnamPro-Regular.ttf'))
      ..addFont(rootBundle.load('assets/fonts/BeVietnamPro-Medium.ttf'))
      ..addFont(rootBundle.load('assets/fonts/BeVietnamPro-SemiBold.ttf'))
      ..addFont(rootBundle.load('assets/fonts/BeVietnamPro-Bold.ttf'));
    await fontLoader.load();
    await (FontLoader(
      'MaterialIcons',
    )..addFont(rootBundle.load('fonts/MaterialIcons-Regular.otf'))).load();
  });

  const zones = [
    DemoZone(
      id: 'zone-rau',
      farmId: 'farm-1',
      name: 'Luống rau cải xanh hữu cơ',
      kind: DemoZoneKind.crop,
      x: 0.3,
      y: 0.4,
      subtitle: 'Luống A',
    ),
    DemoZone(
      id: 'zone-chuong-ga',
      farmId: 'farm-1',
      name: 'Chuồng gà ta thả vườn',
      kind: DemoZoneKind.livestock,
      x: 0.7,
      y: 0.6,
    ),
    DemoZone(
      id: 'zone-bon-nuoc',
      farmId: 'farm-1',
      name: 'Bồn nước tưới tiêu',
      kind: DemoZoneKind.water,
      x: 0.5,
      y: 0.75,
    ),
    DemoZone(
      id: 'zone-kho',
      farmId: 'farm-1',
      name: 'Kho nông cụ và vật tư',
      kind: DemoZoneKind.storage,
      x: 0.6,
      y: 0.2,
      subtitle: 'Tầng trệt',
    ),
    DemoZone(
      id: 'zone-nha',
      farmId: 'farm-1',
      name: 'Nhà xưởng chế biến nông sản sạch',
      kind: DemoZoneKind.house,
      x: 0.4,
      y: 0.9,
    ),
  ];

  Widget app(Widget home, {double textScale = 1}) => MaterialApp(
    theme: buildFarmTheme(),
    locale: const Locale('vi'),
    localizationsDelegates: AppLocalizations.localizationsDelegates,
    supportedLocales: AppLocalizations.supportedLocales,
    builder: (context, child) => MediaQuery(
      data: MediaQuery.of(context).copyWith(
        disableAnimations: true,
        textScaler: TextScaler.linear(textScale),
      ),
      child: child ?? const SizedBox.shrink(),
    ),
    home: home,
  );

  void use360Viewport(WidgetTester tester, {double height = 800}) {
    tester.view.physicalSize = Size(360, height);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
  }

  for (final (scale, name) in const [
    (1.0, 'zone-directory-polish-360-vi'),
    (2.0, 'zone-directory-polish-360-text200-vi'),
  ]) {
    testWidgets('accessible zone directory at ${scale}x text', (tester) async {
      use360Viewport(tester);
      await tester.pumpWidget(
        app(
          Scaffold(
            body: ListView(
              children: [
                AccessibleZoneList(
                  zones: zones,
                  selectedZoneId: 'zone-chuong-ga',
                  onOpenDetail: (_) {},
                ),
              ],
            ),
          ),
          textScale: scale,
        ),
      );
      await tester.pump();

      expect(find.byType(AccessibleZoneList), findsOneWidget);
      expect(tester.takeException(), isNull);
      await expectLater(
        find.byType(AccessibleZoneList),
        matchesGoldenFile('goldens/$name.png'),
      );
    });
  }

  for (final (scale, name) in const [
    (1.0, 'zone-chip-strip-polish-360-vi'),
    (2.0, 'zone-chip-strip-polish-360-text200-vi'),
  ]) {
    testWidgets('zone chip strip at ${scale}x text', (tester) async {
      use360Viewport(tester);
      await tester.pumpWidget(
        app(
          Scaffold(
            body: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                ZoneChipStrip(
                  zones: zones,
                  selectedZoneId: 'zone-rau',
                  onSelect: (_) {},
                  overviewLabel: 'Toàn cảnh',
                ),
              ],
            ),
          ),
          textScale: scale,
        ),
      );
      await tester.pump();

      expect(find.byType(ZoneChipStrip), findsOneWidget);
      expect(tester.takeException(), isNull);
      await expectLater(
        find.byType(ZoneChipStrip),
        matchesGoldenFile('goldens/$name.png'),
      );
    });
  }
}
