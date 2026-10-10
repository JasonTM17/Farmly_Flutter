import 'dart:ui' show Size;

import 'package:flutter_test/flutter_test.dart';

import 'package:farmly_mobile/ui/farm_scaffold.dart';
import 'package:farmly_mobile/ui/zone_explorer.dart';

import '../support/farmly_shell_harness.dart';

void main() {
  testWidgets('farm overview renders at a 500dp phone viewport', (
    tester,
  ) async {
    await pumpFarmlyShell(tester, viewport: const Size(500, 900));

    final farmTab = find.descendant(
      of: find.byType(AdaptiveBottomBar),
      matching: find.text('Nông trại'),
    );
    await tester.tap(farmTab);
    await tester.pumpAndSettle();

    expect(find.byType(ZoneScene), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}
