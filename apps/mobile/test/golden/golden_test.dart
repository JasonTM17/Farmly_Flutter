import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:farmly_mobile/core/auth/auth_session_controller.dart';
import 'package:farmly_mobile/core/auth/farmly_auth_models.dart';
import 'package:farmly_mobile/core/theme/farm_theme.dart';
import 'package:farmly_mobile/core/theme/farmly_spacing.dart';
import 'package:farmly_mobile/features/auth/login_screen.dart';
import 'package:farmly_mobile/features/livestock/livestock_screen.dart';
import 'package:farmly_mobile/features/livestock/live_livestock.dart';
import 'package:farmly_mobile/features/auth/splash_screen.dart';
import 'package:farmly_mobile/features/demo/demo_models.dart';
import 'package:farmly_mobile/features/demo/demo_providers.dart';
import 'package:farmly_mobile/l10n/generated/app_localizations.dart';
import 'package:farmly_mobile/ui/farm_scaffold.dart';
import 'package:farmly_mobile/ui/illustrations.dart';
import 'package:farmly_mobile/ui/livestock_components.dart';
import 'package:farmly_mobile/ui/motion.dart';
import 'package:farmly_mobile/ui/zone_explorer.dart';

import '../support/farmly_shell_harness.dart';

class _SignedOutSessionController extends FarmlyAuthSessionController {
  @override
  Future<FarmlyAuthSession?> build() async => null;
}

class _RestoringSessionController extends FarmlyAuthSessionController {
  @override
  Future<FarmlyAuthSession?> build() => Completer<FarmlyAuthSession?>().future;
}

void _usePhoneViewport(WidgetTester tester) {
  tester.view.physicalSize = const Size(390, 844);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
}

// Existing reference frames are deterministic by default. Dedicated P13
// captures opt into the shared ambient loop and advance it by fixed durations.
Widget _localizedApp(Widget home, {bool reducedMotion = true}) => MaterialApp(
  theme: buildFarmTheme(),
  locale: const Locale('vi'),
  localizationsDelegates: AppLocalizations.localizationsDelegates,
  supportedLocales: AppLocalizations.supportedLocales,
  builder: (context, child) => MediaQuery(
    data: MediaQuery.of(context).copyWith(disableAnimations: reducedMotion),
    child: child ?? const SizedBox.shrink(),
  ),
  home: home,
);

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

  testWidgets('splash loading reference', (tester) async {
    _usePhoneViewport(tester);
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          farmlyAuthSessionProvider.overrideWith(
            _RestoringSessionController.new,
          ),
        ],
        child: _localizedApp(const SplashScreen()),
      ),
    );
    await tester.pump();

    expect(find.text('Farmly'), findsOneWidget);
    expect(find.byType(CircularProgressIndicator), findsOneWidget);
    await expectLater(
      find.byType(SplashScreen),
      matchesGoldenFile('goldens/splash-vi.png'),
    );
  });

  testWidgets('login form reference', (tester) async {
    _usePhoneViewport(tester);
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          farmlyAuthSessionProvider.overrideWith(
            _SignedOutSessionController.new,
          ),
        ],
        child: _localizedApp(const LoginScreen()),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('Đăng nhập Farmly'), findsOneWidget);
    expect(find.text('Địa chỉ email'), findsOneWidget);
    expect(find.text('Mật khẩu'), findsOneWidget);
    await expectLater(
      find.byType(LoginScreen),
      matchesGoldenFile('goldens/login-vi.png'),
    );
  });

  testWidgets('home shell reference', (tester) async {
    await pumpFarmlyShell(tester);

    expect(find.byType(AdaptiveBottomBar), findsOneWidget);
    expect(find.text('Trang chủ'), findsOneWidget);
    expect(find.text('Nông trại'), findsOneWidget);
    await expectLater(
      find.byType(FarmScaffold).first,
      matchesGoldenFile('goldens/shell-home-vi.png'),
    );
  });

  testWidgets('farm map reference', (tester) async {
    await pumpFarmlyShell(tester);
    await tester.tap(
      find.descendant(
        of: find.byType(AdaptiveBottomBar),
        matching: find.text('Nông trại'),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.byType(ZoneScene), findsOneWidget);
    await expectLater(
      find.byType(ZoneScene),
      matchesGoldenFile('goldens/farm-map-vi.png'),
    );
  });

  for (final (zoneId, name, probe) in const [
    ('zone-rau-an-la', 'zone-detail-vi', 'Tăng trưởng'),
    ('zone-bon-nuoc', 'zone-detail-water-vi', 'Mực nước'),
    ('zone-chuong-ga', 'zone-detail-livestock-vi', 'Khu chăn nuôi'),
    ('zone-kho', 'zone-detail-storage-vi', 'Không gian dụng cụ & vật tư'),
    (
      'zone-nha-xuong',
      'zone-detail-house-vi',
      'Không gian làm việc của nông trại',
    ),
  ]) {
    testWidgets('zone detail $name reference', (tester) async {
      final router = await pumpFarmlyShell(tester);
      router.go('/farm/zone/$zoneId');
      await tester.pumpAndSettle();

      expect(find.text(probe), findsWidgets);
      await expectLater(
        find.byType(ListView).first,
        matchesGoldenFile('goldens/$name.png'),
      );
    });
  }

  testWidgets('livestock reference', (tester) async {
    _usePhoneViewport(tester);
    await tester.pumpWidget(
      ProviderScope(
        overrides: [farmlyLivestockDemoPreviewProvider.overrideWithValue(true)],
        child: const _LivestockApp(),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('Cho ăn hôm nay'), findsOneWidget);
    expect(find.text('Nhóm vật nuôi'), findsOneWidget);
    await expectLater(
      find.byType(LivestockScreen),
      matchesGoldenFile('goldens/livestock-vi.png'),
    );
  });

  testWidgets('Farm Explorer meadow closeup opens from map', (tester) async {
    await pumpFarmlyShell(tester);
    await tester.tap(
      find.descendant(
        of: find.byType(AdaptiveBottomBar),
        matching: find.text('Nông trại'),
      ),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('farm-meadow-hotspot')));
    await tester.pumpAndSettle();
    await expectLater(
      find.byKey(const ValueKey('farm-meadow-sheet')),
      matchesGoldenFile('goldens/farm-meadow-closeup-vi.png'),
    );
  });

  testWidgets('Farm Explorer fitted low-poly scene at 360dp', (tester) async {
    tester.view.physicalSize = const Size(360, 800);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
      _localizedApp(const _FarmLifeScene(), reducedMotion: false),
    );
    await tester.pump();
    await tester.pump(const Duration(seconds: 3));

    final phases = tester
        .widgetList<CustomPaint>(find.byType(CustomPaint))
        .map((paint) => paint.painter)
        .whereType<IsoZoneTilePainter>()
        .map((painter) => painter.phase)
        .toSet();
    expect(phases, hasLength(1));
    expect(phases.single, greaterThan(0));
    await expectLater(
      find.byType(_FarmLifeScene),
      matchesGoldenFile('goldens/farm-life-fitted-motion-360-vi.png'),
    );
  });

  testWidgets('Farm Explorer reduced-motion still at 360dp', (tester) async {
    tester.view.physicalSize = const Size(360, 800);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(_localizedApp(const _FarmLifeScene()));
    await tester.pump(const Duration(seconds: 1));

    final phases = tester
        .widgetList<CustomPaint>(find.byType(CustomPaint))
        .map((paint) => paint.painter)
        .whereType<IsoZoneTilePainter>()
        .map((painter) => painter.phase)
        .toSet();
    expect(phases, {0.0});
    await expectLater(
      find.byType(_FarmLifeScene),
      matchesGoldenFile('goldens/farm-life-reduced-motion-360-vi.png'),
    );
  });

  testWidgets('Farm Explorer zoomed animal scene at 360dp', (tester) async {
    tester.view.physicalSize = const Size(360, 800);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
      _localizedApp(const _FarmLifeScene(), reducedMotion: false),
    );
    await tester.pump();
    await tester.pump(const Duration(seconds: 3));
    await tester.tap(
      find.bySemanticsLabel(RegExp('Vùng Chuồng gà\\. Chạm để mở chi tiết')),
    );
    await tester.pump();
    expect(
      tester.widget<ZoneScene>(find.byType(ZoneScene)).selectedZoneId,
      'zone-chuong-ga',
    );

    final viewer = tester.widget<InteractiveViewer>(
      find.descendant(
        of: find.byType(ZoneScene),
        matching: find.byType(InteractiveViewer),
      ),
    );
    var scale = viewer.transformationController!.value.getMaxScaleOnAxis();
    for (var frame = 0; frame < 12 && scale <= 2; frame++) {
      await tester.pump(const Duration(milliseconds: 100));
      scale = viewer.transformationController!.value.getMaxScaleOnAxis();
    }
    expect(scale, greaterThan(2));
    await tester.pump(const Duration(milliseconds: 200));
    await expectLater(
      find.byType(_FarmLifeScene),
      matchesGoldenFile('goldens/farm-life-zoomed-motion-360-vi.png'),
    );
  });

  testWidgets('Farm Explorer zoomed crop scene at 360dp', (tester) async {
    tester.view.physicalSize = const Size(360, 800);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
      _localizedApp(const _FarmLifeScene(), reducedMotion: false),
    );
    await tester.pump();
    await tester.pump(const Duration(seconds: 3));
    await tester.tap(
      find.bySemanticsLabel(RegExp('Vùng Cà chua giàn\\. Chạm để mở chi tiết')),
    );
    await tester.pump();
    expect(
      tester.widget<ZoneScene>(find.byType(ZoneScene)).selectedZoneId,
      'zone-ca-chua',
    );

    final viewer = tester.widget<InteractiveViewer>(
      find.descendant(
        of: find.byType(ZoneScene),
        matching: find.byType(InteractiveViewer),
      ),
    );
    var scale = viewer.transformationController!.value.getMaxScaleOnAxis();
    for (var frame = 0; frame < 12 && scale <= 2; frame++) {
      await tester.pump(const Duration(milliseconds: 100));
      scale = viewer.transformationController!.value.getMaxScaleOnAxis();
    }
    expect(scale, greaterThan(2));
    await tester.pump(const Duration(milliseconds: 200));
    await expectLater(
      find.byType(_FarmLifeScene),
      matchesGoldenFile('goldens/farm-life-zoomed-crop-360-vi.png'),
    );
  });

  testWidgets('four low-poly animal portraits remain legible at 44dp', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(360, 260);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
      _localizedApp(const _AnimalPortraitShowcase(), reducedMotion: false),
    );
    await tester.pump();
    await tester.pump(const Duration(seconds: 3));

    expect(find.byType(AnimalCategoryCard), findsNWidgets(4));
    for (final portrait in find.byType(AnimalPortrait).evaluate()) {
      expect(
        tester.getSize(find.byWidget(portrait.widget)),
        const Size(44, 44),
      );
    }
    await expectLater(
      find.byType(_AnimalPortraitShowcase),
      matchesGoldenFile('goldens/farm-life-animal-portraits-360-vi.png'),
    );
  });

  testWidgets('home offline state reference', (tester) async {
    await pumpFarmlyShell(tester);
    final container = ProviderScope.containerOf(
      tester.element(find.byType(FarmScaffold).first),
    );
    container
        .read(demoScreenStateProvider.notifier)
        .set('home', DemoLoadState.offline);
    await tester.pumpAndSettle();

    await expectLater(
      find.byType(MaterialApp),
      matchesGoldenFile('goldens/home-offline-vi.png'),
    );
  });

  testWidgets('sync center reference', (tester) async {
    final router = await pumpFarmlyShell(tester);
    router.go('/sync');
    await tester.pumpAndSettle();

    await expectLater(
      find.byType(MaterialApp),
      matchesGoldenFile('goldens/sync-center-vi.png'),
    );
  });

  for (final (index, name) in const [
    (2, 'analytics'),
    (3, 'harvest'),
    (4, 'profile'),
  ]) {
    testWidgets('$name tab reference', (tester) async {
      await pumpFarmlyShell(tester);
      final bar = find.byType(AdaptiveBottomBar);
      await tester.tap(
        find.descendant(of: bar, matching: find.byType(InkWell)).at(index),
      );
      await tester.pumpAndSettle();
      await expectLater(
        find.byType(MaterialApp),
        matchesGoldenFile('goldens/$name-vi.png'),
      );
    });
  }
}

class _LivestockApp extends StatelessWidget {
  const _LivestockApp();

  @override
  Widget build(BuildContext context) => MaterialApp(
    theme: buildFarmTheme(),
    locale: const Locale('vi'),
    localizationsDelegates: AppLocalizations.localizationsDelegates,
    supportedLocales: AppLocalizations.supportedLocales,
    builder: (context, child) => MediaQuery(
      data: MediaQuery.of(context).copyWith(disableAnimations: true),
      child: child ?? const SizedBox.shrink(),
    ),
    home: const LivestockScreen(),
  );
}

const _farmLifeZones = <DemoZone>[
  DemoZone(
    id: 'zone-rau-an-la',
    farmId: 'farm-1',
    name: 'Rau ăn lá',
    kind: DemoZoneKind.crop,
    x: 0.24,
    y: 0.42,
  ),
  DemoZone(
    id: 'zone-ca-chua',
    farmId: 'farm-1',
    name: 'Cà chua giàn',
    kind: DemoZoneKind.crop,
    x: 0.58,
    y: 0.34,
  ),
  DemoZone(
    id: 'zone-chuong-ga',
    farmId: 'farm-1',
    name: 'Chuồng gà',
    kind: DemoZoneKind.livestock,
    x: 0.78,
    y: 0.62,
  ),
  DemoZone(
    id: 'zone-bon-nuoc',
    farmId: 'farm-1',
    name: 'Bồn nước',
    kind: DemoZoneKind.water,
    x: 0.34,
    y: 0.7,
  ),
  DemoZone(
    id: 'zone-ruong-ngo',
    farmId: 'farm-1',
    name: 'Ruộng ngô',
    kind: DemoZoneKind.crop,
    x: 0.3,
    y: 0.7,
  ),
  DemoZone(
    id: 'zone-kho',
    farmId: 'farm-1',
    name: 'Kho nông cụ',
    kind: DemoZoneKind.storage,
    x: 0.7,
    y: 0.9,
  ),
  DemoZone(
    id: 'zone-nha-xuong',
    farmId: 'farm-1',
    name: 'Nhà xưởng',
    kind: DemoZoneKind.house,
    x: 0.9,
    y: 0.9,
  ),
];

class _FarmLifeScene extends StatefulWidget {
  const _FarmLifeScene();

  @override
  State<_FarmLifeScene> createState() => _FarmLifeSceneState();
}

class _FarmLifeSceneState extends State<_FarmLifeScene> {
  String? _selectedZoneId;

  @override
  Widget build(BuildContext context) => Scaffold(
    body: Column(
      children: [
        ZoneChipStrip(
          zones: _farmLifeZones,
          selectedZoneId: _selectedZoneId,
          onSelect: (id) => setState(() => _selectedZoneId = id),
        ),
        Expanded(
          child: ZoneScene(
            zones: _farmLifeZones,
            selectedZoneId: _selectedZoneId,
            onSelect: (id) => setState(() => _selectedZoneId = id),
            onOpenDetail: (_) {},
          ),
        ),
      ],
    ),
  );
}

class _AnimalPortraitShowcase extends StatelessWidget {
  const _AnimalPortraitShowcase();

  @override
  Widget build(BuildContext context) => Scaffold(
    body: Center(
      child: SizedBox(
        width: 208,
        child: FarmAmbientLoop(
          builder: (context, phase) => Wrap(
            spacing: FarmSpacing.sm,
            runSpacing: FarmSpacing.sm,
            children: [
              for (final category in DemoAnimalCategory.values)
                AnimalCategoryCard(
                  category: category,
                  count: 12,
                  selected: false,
                  onSelected: (_) {},
                  phase: phase,
                ),
            ],
          ),
        ),
      ),
    ),
  );
}
