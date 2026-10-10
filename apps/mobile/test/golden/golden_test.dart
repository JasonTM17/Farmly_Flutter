import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:farmly_mobile/core/auth/auth_session_controller.dart';
import 'package:farmly_mobile/core/auth/farmly_auth_models.dart';
import 'package:farmly_mobile/core/theme/farm_theme.dart';
import 'package:farmly_mobile/features/auth/login_screen.dart';
import 'package:farmly_mobile/features/livestock/livestock_screen.dart';
import 'package:farmly_mobile/features/auth/splash_screen.dart';
import 'package:farmly_mobile/features/demo/demo_models.dart';
import 'package:farmly_mobile/features/demo/demo_providers.dart';
import 'package:farmly_mobile/l10n/generated/app_localizations.dart';
import 'package:farmly_mobile/ui/farm_scaffold.dart';
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

// Golden frames are deterministic: disableAnimations makes every ambient
// loop render its phase-0 layout and every entrance its resting state.
Widget _localizedApp(Widget home) => MaterialApp(
  theme: buildFarmTheme(),
  locale: const Locale('vi'),
  localizationsDelegates: AppLocalizations.localizationsDelegates,
  supportedLocales: AppLocalizations.supportedLocales,
  builder: (context, child) => MediaQuery(
    data: MediaQuery.of(context).copyWith(disableAnimations: true),
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
      const ProviderScope(child: _LivestockApp()),
    );
    await tester.pumpAndSettle();

    expect(find.text('Cho ăn hôm nay'), findsOneWidget);
    expect(find.text('Nhóm vật nuôi'), findsOneWidget);
    await expectLater(
      find.byType(LivestockScreen),
      matchesGoldenFile('goldens/livestock-vi.png'),
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
    home: const LivestockScreen(),
  );
}
