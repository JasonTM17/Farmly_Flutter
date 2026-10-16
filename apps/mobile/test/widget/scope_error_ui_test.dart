import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:farmly_mobile/core/auth/auth_session_controller.dart';
import 'package:farmly_mobile/core/auth/farmly_auth_models.dart';
import 'package:farmly_mobile/core/theme/farm_theme.dart';
import 'package:farmly_mobile/features/chat/chat_screens.dart';
import 'package:farmly_mobile/features/organizations/organization_repository.dart';
import 'package:farmly_mobile/features/organizations/organization_scope_controller.dart';
import 'package:farmly_mobile/features/sync/sync_center_screen.dart';
import 'package:farmly_mobile/l10n/generated/app_localizations.dart';

/// Regression: an invalid live scope — a non-UUID demo farm id, exactly what
/// the explorer preview seeds — must render translated error UI inside the
/// safe area, never the raw Riverpod provider exception as a full-screen
/// error widget (spec02 §5: error copy is translated and actionable).
const _session = FarmlyAuthSession(
  user: FarmlyAuthUser(
    id: '11111111-1111-4111-8111-111111111111',
    name: 'Test Farmer',
    email: 'farmer@farmly.test',
  ),
);

const _brokenScope = FarmlyOrganizationScope(
  organization: FarmlyOrganization(
    id: '22222222-2222-4222-8222-222222222222',
    name: 'Test Organization',
    status: FarmlyOrganizationStatus.active,
    policyVersion: '1',
    role: FarmlyOrganizationRole.owner,
    membershipVersion: 1,
  ),
  directory: FarmlyFarmDirectory(
    scopePolicyVersion: '1',
    continuityEpoch: '1',
    farms: <FarmlyDirectoryFarm>[
      FarmlyDirectoryFarm(
        // Mirrors the preview seed: a demo id, not a UUIDv4 — the mutation
        // scope validation rejects it.
        id: 'farm-bavi',
        name: 'Nông trại Ba Vì',
        status: FarmlyFarmStatus.active,
        grantRole: FarmlyFarmGrantRole.owner,
      ),
    ],
  ),
  epoch: 1,
  selectedFarmId: 'farm-bavi',
);

class _SignedInSessionController extends FarmlyAuthSessionController {
  @override
  Future<FarmlyAuthSession?> build() async => _session;
}

class _BrokenScopeController extends SelectedOrganizationScopeController {
  @override
  FarmlyOrganizationScope? build() => _brokenScope;
}

Widget _harness(WidgetTester tester, Widget home) {
  tester.view.physicalSize = const Size(900, 1800);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  return ProviderScope(
    overrides: [
      farmlyAuthSessionProvider.overrideWith(_SignedInSessionController.new),
      selectedOrganizationScopeProvider.overrideWith(
        _BrokenScopeController.new,
      ),
    ],
    child: MaterialApp(
      theme: buildFarmTheme(),
      locale: const Locale('vi'),
      builder: (context, child) => MediaQuery(
        data: MediaQuery.of(context).copyWith(disableAnimations: true),
        child: child ?? const SizedBox.shrink(),
      ),
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      supportedLocales: AppLocalizations.supportedLocales,
      home: home,
    ),
  );
}

void main() {
  testWidgets('sync center renders a translated error panel with retry', (
    tester,
  ) async {
    await tester.pumpWidget(
      _harness(tester, const SyncCenterScreen()),
    );
    await tester.pumpAndSettle();

    // No raw exception escapes into the widget tree.
    expect(tester.takeException(), isNull);
    expect(find.textContaining('ProviderException'), findsNothing);
    expect(find.textContaining('must be a UUIDv4'), findsNothing);
    // Translated error panel with an explicit retry action.
    expect(find.text('Lỗi phạm vi đồng bộ máy chủ'), findsOneWidget);
    expect(find.textContaining('dữ liệu vẫn chỉ được lưu trên thiết bị'), findsOneWidget);
    expect(find.text('Thử lại'), findsOneWidget);
  });

  testWidgets('chat conversation renders a compact error banner', (
    tester,
  ) async {
    await tester.pumpWidget(
      _harness(tester, const ChatConversationScreen(contextual: true)),
    );
    await tester.pumpAndSettle();

    expect(tester.takeException(), isNull);
    expect(find.textContaining('ProviderException'), findsNothing);
    expect(find.textContaining('must be a UUIDv4'), findsNothing);
    // Compact banner inside the safe area; the demo conversation stays usable.
    expect(
      find.text('Farmly AI chưa dùng được cho phạm vi này — hãy thử lại.'),
      findsOneWidget,
    );
    expect(find.text('Thử lại'), findsOneWidget);
  });
}
