import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:farmly_mobile/main_explorer_preview.dart' as preview;
import 'package:farmly_mobile/core/sync/sync_providers.dart';
import 'package:farmly_mobile/core/auth/auth_session_controller.dart';
import 'package:farmly_mobile/core/network/farmly_api_client.dart';
import 'package:farmly_mobile/ui/zone_explorer.dart';
import 'package:farmly_mobile/features/sync/sync_center_screen.dart';

void main() {
  testWidgets(
    'native clay preview disables disk sync and uses local API adapters',
    (tester) async {
      preview.main();
      await tester.pump();
      await tester.pump(const Duration(seconds: 1));
      final context = tester.element(find.byType(ZoneScene));
      final container = ProviderScope.containerOf(context);
      expect(await container.read(farmlySyncScopeProvider.future), isNull);
      final dio = container.read(farmlyApiDioProvider);
      expect(
        dio.httpClientAdapter.runtimeType.toString(),
        '_PreviewApiAdapter',
      );
      expect(container.read(betterAuthClientProvider), isNotNull);
      GoRouter.of(context).push('/sync');
      await tester.pump();
      await tester.pump(const Duration(seconds: 1));
      expect(find.byType(SyncCenterScreen), findsOneWidget);
      expect(await container.read(farmlySyncScopeProvider.future), isNull);
      await expectLater(
        container.read(syncEngineProvider.future),
        throwsStateError,
      );
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pump();
    },
  );
}
