import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';

import 'package:farmly_mobile/app/farmly_app.dart';
import 'package:farmly_mobile/core/auth/auth_session_controller.dart';
import 'package:farmly_mobile/core/auth/farmly_auth_models.dart';
import 'package:farmly_mobile/core/config/app_config.dart';
import 'package:farmly_mobile/features/app/app_router.dart';
import 'package:farmly_mobile/features/app/app_routes.dart';
import 'package:farmly_mobile/l10n/locale_controller.dart';

class _SignedOutController extends FarmlyAuthSessionController {
  @override
  Future<FarmlyAuthSession?> build() async => null;
}

class _HeldSignInController extends _SignedOutController {
  final completion = Completer<void>();
  int signInCalls = 0;

  @override
  Future<void> signIn({
    required String email,
    required String password,
    required bool keepSignedIn,
  }) {
    signInCalls += 1;
    return completion.future;
  }
}

Future<(ProviderContainer, GoRouter)> pumpApp(
  WidgetTester tester, {
  FarmlyAuthSessionController Function()? authController,
}) async {
  final config = FarmlyAppConfig.fromEnvironment(
    flavorOverride: 'development',
    apiBaseUrlOverride: 'http://127.0.0.1:3000',
  );
  final container = ProviderContainer(
    overrides: [
      farmlyAppConfigProvider.overrideWithValue(config),
      farmlyAuthSessionProvider.overrideWith(
        authController ?? _SignedOutController.new,
      ),
      // These cases assert EN copy; the app default is vi-VN (spec 01).
      farmlyLocaleProvider.overrideWith(
        () => FarmlyLocaleController(const Locale('en')),
      ),
    ],
  );
  addTearDown(container.dispose);
  final router = container.read(farmlyRouterProvider);
  await tester.pumpWidget(
    UncontrolledProviderScope(
      container: container,
      child: FarmlyApp(config: config),
    ),
  );
  await tester.pumpAndSettle();
  return (container, router);
}

void main() {
  testWidgets(
    'protected routes return to sign-in with the local target intact',
    (tester) async {
      final (_, router) = await pumpApp(tester);
      expect(find.text('Sign in to Farmly'), findsOneWidget);

      router.go(AppRoutes.profile);
      await tester.pumpAndSettle();

      expect(find.text('Sign in to Farmly'), findsOneWidget);
      expect(router.routeInformationProvider.value.uri.path, AppRoutes.login);
      expect(
        router.routeInformationProvider.value.uri.queryParameters['returnTo'],
        AppRoutes.profile,
      );
    },
  );

  testWidgets('password reset app links render without requiring a session', (
    tester,
  ) async {
    final (_, router) = await pumpApp(tester);
    router.go('${AppRoutes.resetPassword}?token=one-time-test-token');
    await tester.pumpAndSettle();

    expect(find.text('Choose a new password'), findsOneWidget);
    expect(
      find.text('Choose a new password for your Farmly account.'),
      findsOneWidget,
    );
    expect(find.text('Save new password'), findsOneWidget);
  });

  testWidgets('empty password-reset token is rejected before form rendering', (
    tester,
  ) async {
    final (_, router) = await pumpApp(tester);
    router.go('${AppRoutes.resetPassword}?token=');
    await tester.pumpAndSettle();

    expect(find.byType(TextField), findsNothing);
    expect(find.text('Save new password'), findsNothing);
    expect(
      find.text(
        'It may have expired or already been used. Request a new link and try again.',
      ),
      findsOneWidget,
    );
    expect(find.text('This link can’t be used'), findsOneWidget);
    expect(
      find.text('Choose a new password for your Farmly account.'),
      findsNothing,
    );
    expect(tester.takeException(), isNull);
  });

  testWidgets('login stays reachable with safe areas and the keyboard open', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1;
    tester.view.padding = const FakeViewPadding(top: 48, bottom: 24);
    addTearDown(tester.view.reset);

    final (_, router) = await pumpApp(tester);
    router.go(AppRoutes.login);
    await tester.pumpAndSettle();

    final password = find.byType(TextField).at(1);
    await tester.tap(password);
    expect(FocusManager.instance.primaryFocus?.hasFocus, isTrue);

    tester.view.viewInsets = const FakeViewPadding(bottom: 320);
    await tester.pumpAndSettle();

    final submit = find.widgetWithText(FilledButton, 'Sign in');
    await tester.ensureVisible(submit);
    await tester.pumpAndSettle();

    expect(find.text('Sign in'), findsOneWidget);
    expect(
      tester.getTopLeft(find.byType(TextField).first).dy,
      greaterThanOrEqualTo(48),
    );
    expect(tester.getBottomRight(submit).dy, lessThanOrEqualTo(844 - 320));
    expect(tester.takeException(), isNull);
  });

  testWidgets('login fits supported widths, landscape and 200% text', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(360, 844);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    final dispatcher = tester.binding.platformDispatcher;
    dispatcher.textScaleFactorTestValue = 1;
    addTearDown(dispatcher.clearTextScaleFactorTestValue);

    await pumpApp(tester);
    const phoneSizes = <Size>[
      Size(360, 844),
      Size(375, 844),
      Size(390, 844),
      Size(412, 844),
    ];
    final submit = find.widgetWithText(FilledButton, 'Sign in');
    for (final scale in const <double>[1, 2]) {
      dispatcher.textScaleFactorTestValue = scale;
      for (final viewport in phoneSizes) {
        tester.view.physicalSize = viewport;
        await tester.pumpAndSettle();
        await tester.ensureVisible(submit);
        await tester.pumpAndSettle();
        expect(submit, findsOneWidget, reason: '$viewport / $scale');
        expect(tester.takeException(), isNull, reason: '$viewport / $scale');
      }
    }

    tester.view.physicalSize = const Size(640, 360);
    await tester.pumpAndSettle();
    await tester.ensureVisible(submit);
    await tester.pumpAndSettle();
    expect(submit, findsOneWidget, reason: '640x360 landscape');
    expect(tester.takeException(), isNull, reason: '640x360 landscape');
  });

  testWidgets('keyboard submit is ignored while sign-in is already pending', (
    tester,
  ) async {
    final controller = _HeldSignInController();
    final (_, router) = await pumpApp(tester, authController: () => controller);
    router.go(AppRoutes.login);
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField).at(0), 'farmer@example.test');
    await tester.enterText(find.byType(TextField).at(1), 'valid-password');

    await tester.tap(find.widgetWithText(FilledButton, 'Sign in'));
    await tester.pump();
    expect(controller.signInCalls, 1);

    await tester.testTextInput.receiveAction(TextInputAction.done);
    await tester.pump();
    expect(controller.signInCalls, 1);

    controller.completion.complete();
    await tester.pumpAndSettle();
  });

  testWidgets('signup rejects an empty form with a local accessible message', (
    tester,
  ) async {
    final (_, router) = await pumpApp(tester);
    router.go(AppRoutes.signup);
    await tester.pumpAndSettle();

    await tester.enterText(find.byType(TextField).at(1), 'farmer@example.test');
    final submit = find.widgetWithText(FilledButton, 'Create account');
    await tester.ensureVisible(submit);
    await tester.tap(submit);
    await tester.pumpAndSettle();

    expect(find.text('Enter your name.'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('verification resend validates email before calling the API', (
    tester,
  ) async {
    final (_, router) = await pumpApp(tester);
    router.go(AppRoutes.verifyEmail);
    await tester.pumpAndSettle();

    final resend = find.widgetWithText(
      OutlinedButton,
      'Send the verification link again',
    );
    await tester.ensureVisible(resend);
    await tester.tap(resend);
    await tester.pumpAndSettle();

    expect(find.text('Enter your email address.'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('forgot-password form rejects malformed email locally', (
    tester,
  ) async {
    final (_, router) = await pumpApp(tester);
    router.go(AppRoutes.forgotPassword);
    await tester.pumpAndSettle();

    await tester.enterText(find.byType(TextField), 'not-an-email');
    final submit = find.widgetWithText(FilledButton, 'Send reset link');
    await tester.ensureVisible(submit);
    await tester.tap(submit);
    await tester.pumpAndSettle();

    expect(find.text('Enter a valid email address.'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('reset-password form rejects mismatched confirmation locally', (
    tester,
  ) async {
    final (_, router) = await pumpApp(tester);
    router.go('${AppRoutes.resetPassword}?token=synthetic-token');
    await tester.pumpAndSettle();

    await tester.enterText(find.byType(TextField).at(0), 'farmly-pass-1');
    await tester.enterText(find.byType(TextField).at(1), 'farmly-pass-2');
    final submit = find.widgetWithText(FilledButton, 'Save new password');
    await tester.ensureVisible(submit);
    await tester.tap(submit);
    await tester.pumpAndSettle();

    expect(find.text('The passwords do not match.'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  test('return-to validation rejects external and protocol-relative URLs', () {
    expect(
      safeFarmlyReturnTo('/invite?token=example'),
      '/invite?token=example',
    );
    expect(safeFarmlyReturnTo('//evil.example/'), isNull);
    expect(safeFarmlyReturnTo('https://evil.example/'), isNull);
  });
}
