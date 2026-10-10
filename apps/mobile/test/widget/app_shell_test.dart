import 'dart:ui' show Locale, Size;

import 'package:flutter/material.dart' show Scrollable, Text;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';

import 'package:farmly_mobile/ui/farm_scaffold.dart';
import 'package:farmly_mobile/ui/zone_explorer.dart';
import 'package:farmly_mobile/features/demo/demo_models.dart';
import 'package:farmly_mobile/features/demo/demo_providers.dart';
import 'package:farmly_mobile/features/home/home_screen.dart';

import '../support/farmly_shell_harness.dart';

void main() {
  Finder bottomBarLabel(String label) => find.descendant(
    of: find.byType(AdaptiveBottomBar),
    matching: find.text(label),
  );

  int activeBranch(WidgetTester tester) => tester
      .widget<StatefulNavigationShell>(find.byType(StatefulNavigationShell))
      .currentIndex;

  testWidgets('shell renders exactly five localized tabs', (tester) async {
    await pumpFarmlyShell(tester);

    for (final label in const [
      'Trang chủ',
      'Nông trại',
      'Phân tích',
      'Thu hoạch',
      'Cá nhân',
    ]) {
      expect(bottomBarLabel(label), findsOneWidget, reason: label);
    }
    expect(bottomBarLabel('Farmly AI'), findsNothing);
    expect(activeBranch(tester), 0);
  });

  testWidgets('five navigator branches switch while retaining the shell', (
    tester,
  ) async {
    await pumpFarmlyShell(tester);
    expect(find.textContaining('Chào'), findsWidgets);

    await tester.tap(bottomBarLabel('Nông trại'));
    await tester.pumpAndSettle();
    expect(activeBranch(tester), 1);
    expect(find.byType(ZoneScene), findsOneWidget);

    await tester.tap(bottomBarLabel('Phân tích'));
    await tester.pumpAndSettle();
    expect(activeBranch(tester), 2);
    expect(find.text('7 ngày'), findsOneWidget);

    await tester.tap(bottomBarLabel('Thu hoạch'));
    await tester.pumpAndSettle();
    expect(activeBranch(tester), 3);
    expect(find.text('Kỳ này (7 ngày)'), findsOneWidget);

    await tester.tap(bottomBarLabel('Cá nhân'));
    await tester.pumpAndSettle();
    expect(activeBranch(tester), 4);
    expect(find.text('Đổi tổ chức'), findsOneWidget);
    expect(find.text('Đổi nông trại'), findsOneWidget);

    await tester.tap(bottomBarLabel('Trang chủ'));
    await tester.pumpAndSettle();
    expect(activeBranch(tester), 0);
    expect(find.textContaining('Chào'), findsWidgets);

    await tester.tap(bottomBarLabel('Cá nhân'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Đổi nông trại'));
    await tester.pumpAndSettle();
    expect(find.text('Chọn nông trại'), findsOneWidget);
  });

  testWidgets('tablet shell keeps the selected farm branch visible', (
    tester,
  ) async {
    await pumpFarmlyShell(tester, viewport: const Size(800, 600));

    await tester.tap(bottomBarLabel('Nông trại'));
    await tester.pumpAndSettle();

    expect(activeBranch(tester), 1);
    expect(find.byType(ZoneScene), findsOneWidget);
  });

  testWidgets('localized tabs fit supported widths, landscape and 200% text', (
    tester,
  ) async {
    const phoneHeights = <Size>[
      Size(360, 844),
      Size(375, 844),
      Size(390, 844),
      Size(412, 844),
    ];
    const labels = <String>[
      'Trang chủ',
      'Nông trại',
      'Phân tích',
      'Thu hoạch',
      'Cá nhân',
    ];

    await pumpFarmlyShell(tester, viewport: phoneHeights.first);
    for (final textScale in const [1.0, 2.0]) {
      tester.binding.platformDispatcher.textScaleFactorTestValue = textScale;
      for (final viewport in phoneHeights) {
        tester.view.physicalSize = viewport;
        await tester.pumpAndSettle();

        for (final label in labels) {
          expect(
            bottomBarLabel(label),
            findsOneWidget,
            reason: '$viewport / $textScale',
          );
        }
        if (textScale == 2.0 && viewport == phoneHeights.first) {
          expect(
            find.descendant(
              of: find.byType(FarmTopBar),
              matching: find.text('Trang chủ'),
            ),
            findsOneWidget,
          );
          expect(find.text('Chào buổi sáng, Test Farmer'), findsOneWidget);
        }
        final exception = tester.takeException();
        expect(exception, isNull, reason: '$viewport / $textScale: $exception');
      }
    }

    tester.binding.platformDispatcher.textScaleFactorTestValue = 1;
    tester.view.physicalSize = const Size(640, 360);
    await tester.pumpAndSettle();
    expect(bottomBarLabel('Nông trại'), findsOneWidget);
    expect(tester.takeException(), isNull, reason: '640x360 landscape');
  });

  testWidgets('shell tab labels and profile actions are localized in English', (
    tester,
  ) async {
    await pumpFarmlyShell(tester, locale: const Locale('en'));
    for (final label in const [
      'Home',
      'My Farm',
      'Insights',
      'Harvest',
      'Profile',
    ]) {
      expect(bottomBarLabel(label), findsOneWidget, reason: label);
    }

    await tester.tap(bottomBarLabel('Profile'));
    await tester.pumpAndSettle();
    expect(find.text('Change organization'), findsOneWidget);
    expect(find.text('Change farm'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('English Profile has no Vietnamese sync or settings copy', (
    tester,
  ) async {
    await pumpFarmlyShell(tester, locale: const Locale('en'));
    await tester.tap(bottomBarLabel('Profile'));
    await tester.pumpAndSettle();

    expect(find.text('Sync Center'), findsOneWidget);
    expect(
      find.text('You have not chosen a conversation mode.'),
      findsOneWidget,
    );
    expect(
      find.text(
        'This month: 1240 input tokens and 3860 output tokens (illustrative demo figures).',
      ),
      findsOneWidget,
    );

    final vietText = RegExp(r'[\u00C0-\u024F]');
    final visibleText = tester
        .widgetList<Text>(find.byType(Text))
        .map((text) => text.data ?? text.textSpan?.toPlainText() ?? '')
        .where(vietText.hasMatch)
        .toList();
    expect(visibleText, isEmpty, reason: 'Visible English copy: $visibleText');

    final semantics = tester.ensureSemantics();
    try {
      expect(
        find.bySemanticsLabel(vietText),
        findsNothing,
        reason: 'English Profile semantics must not contain Vietnamese copy.',
      );

      await tester.scrollUntilVisible(
        find.text('Language'),
        180,
        scrollable: find.byType(Scrollable).last,
      );
      await tester.pumpAndSettle();
      expect(find.text('Language'), findsOneWidget);
      expect(
        find.text('Vietnamese is the current default in this demo.'),
        findsOneWidget,
      );
      expect(find.text('Text size and motion'), findsOneWidget);
      expect(
        find.text(
          'Follows system settings; the app does not shrink text to fit.',
        ),
        findsOneWidget,
      );
      final settingsText = tester
          .widgetList<Text>(find.byType(Text))
          .map((text) => text.data ?? text.textSpan?.toPlainText() ?? '')
          .where(vietText.hasMatch)
          .toList();
      expect(
        settingsText,
        isEmpty,
        reason: 'Visible English copy: $settingsText',
      );
      expect(
        find.bySemanticsLabel(vietText),
        findsNothing,
        reason: 'English Profile semantics must not contain Vietnamese copy.',
      );
      expect(tester.takeException(), isNull);
    } finally {
      semantics.dispose();
    }
  });

  testWidgets('Home and scope recovery copy are localized in English', (
    tester,
  ) async {
    await pumpFarmlyShell(tester, locale: const Locale('en'));

    expect(find.text('Test Organization'), findsOneWidget);
    expect(find.text('No farm selected'), findsOneWidget);
    expect(
      find.text(
        'Preview data only. These figures are examples, not live farm records.',
      ),
      findsOneWidget,
    );
    expect(find.text('Operations health'), findsOneWidget);
    expect(find.text('Sức khỏe vận hành'), findsNothing);

    final container = ProviderScope.containerOf(
      tester.element(find.byType(HomeScreen)),
    );
    container
        .read(demoScreenStateProvider.notifier)
        .set('home', DemoLoadState.recoverableError);
    await tester.pumpAndSettle();
    expect(find.text('Couldn’t load data'), findsOneWidget);
    expect(find.text('Đã có lỗi khi tải.'), findsNothing);

    await tester.tap(find.text('Change scope'));
    await tester.pumpAndSettle();
    expect(find.text('Choose a farm'), findsOneWidget);
    expect(
      find.text('To change organization, open Profile → Organizations.'),
      findsOneWidget,
    );
    expect(tester.takeException(), isNull);
  });
}
