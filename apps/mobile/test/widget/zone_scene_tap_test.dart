import 'dart:ui' show Size;

import 'package:flutter_test/flutter_test.dart';

import 'package:farmly_mobile/ui/farm_scaffold.dart';
import 'package:farmly_mobile/ui/zone_explorer.dart';

import '../support/farmly_shell_harness.dart';

void main() {
  testWidgets('tapping a zone tile opens detail without sliver assertion', (
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

    // Tap the first zone tile (its semantics label).
    await tester.tap(
      find.bySemanticsLabel('Vùng Rau ăn lá. Chạm để mở chi tiết.'),
    );
    await tester.pumpAndSettle();

    expect(tester.takeException(), isNull);
  });
}
