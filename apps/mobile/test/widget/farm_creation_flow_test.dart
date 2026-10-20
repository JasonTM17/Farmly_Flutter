import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:farmly_mobile/core/auth/auth_session_controller.dart';
import 'package:farmly_mobile/core/auth/farmly_auth_models.dart';
import 'package:farmly_mobile/core/sync/farmly_mutation.dart';
import 'package:farmly_mobile/core/sync/local_domain_store.dart';
import 'package:farmly_mobile/core/sync/outbox_store.dart';
import 'package:farmly_mobile/core/sync/sync_engine.dart';
import 'package:farmly_mobile/core/sync/sync_models.dart';
import 'package:farmly_mobile/core/sync/sync_providers.dart';
import 'package:farmly_mobile/core/sync/sync_transport.dart';
import 'package:farmly_mobile/core/theme/farm_theme.dart';
import 'package:farmly_mobile/features/organizations/organization_repository.dart';
import 'package:farmly_mobile/features/organizations/organization_scope_controller.dart';
import 'package:farmly_mobile/l10n/generated/app_localizations.dart';
import 'package:farmly_mobile/ui/pickers.dart';

const _accountId = '11111111-1111-4111-8111-111111111111';
const _organizationId = '22222222-2222-4222-8222-222222222222';

const _session = FarmlyAuthSession(
  user: FarmlyAuthUser(
    id: _accountId,
    name: 'Test Farmer',
    email: 'farmer@farmly.test',
  ),
);

const _organization = FarmlyOrganization(
  id: _organizationId,
  name: 'Vườn Nhà',
  status: FarmlyOrganizationStatus.active,
  policyVersion: '1',
  role: FarmlyOrganizationRole.owner,
  membershipVersion: 1,
);

const _scope = FarmlyOrganizationScope(
  organization: _organization,
  directory: FarmlyFarmDirectory(
    scopePolicyVersion: '1',
    continuityEpoch: '1',
    farms: <FarmlyDirectoryFarm>[],
  ),
  epoch: 1,
);

class _SignedInSessionController extends FarmlyAuthSessionController {
  @override
  Future<FarmlyAuthSession?> build() async => _session;
}

class _SelectedScopeController extends SelectedOrganizationScopeController {
  _SelectedScopeController([this.scope = _scope]);

  final FarmlyOrganizationScope scope;

  @override
  FarmlyOrganizationScope? build() => scope;
}

class _UnusedTransport implements SyncTransport {
  @override
  Future<MutationBatchResult> submitMutations({
    required FarmlyMutationScope scope,
    required List<FarmlyMutationIntent> operations,
  }) => throw StateError('transport must not run while creating offline');

  @override
  Future<List<OperationStatusEntry>> operationStatus({
    required String accountId,
    required List<String> operationIds,
  }) => throw StateError('transport must not run while creating offline');

  @override
  Future<ChangeFeedPage> fetchChanges({
    required FarmlyMutationScope scope,
    required String cursor,
  }) => throw StateError('transport must not run while creating offline');

  @override
  Future<BootstrapManifest> createBootstrap({
    required FarmlyMutationScope scope,
    required String operationId,
  }) => throw StateError('transport must not run while creating offline');

  @override
  Future<BootstrapPage> fetchBootstrapPage({
    required FarmlyMutationScope scope,
    required String snapshotId,
    String? pageCursor,
  }) => throw StateError('transport must not run while creating offline');
}

Future<void> _openFarmPicker(
  WidgetTester tester, {
  required InMemoryOutboxStore outbox,
  FarmlyOrganizationScope scope = _scope,
  bool syncEngineAvailable = true,
}) async {
  final engine = FarmlySyncEngine(
    outbox: outbox,
    transport: _UnusedTransport(),
    domain: InMemoryDomainStore(),
  );
  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        farmlyAuthSessionProvider.overrideWith(_SignedInSessionController.new),
        selectedOrganizationScopeProvider.overrideWith(
          () => _SelectedScopeController(scope),
        ),
        syncEngineProvider.overrideWith((ref) async {
          if (!syncEngineAvailable) {
            throw StateError('Persistent sync is unavailable in preview');
          }
          return engine;
        }),
      ],
      child: MaterialApp(
        theme: buildFarmTheme(),
        locale: const Locale('vi'),
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        home: Builder(
          builder: (context) => Scaffold(
            body: TextButton(
              onPressed: () => showFarmPickerSheet(context),
              child: const Text('Chọn trang trại'),
            ),
          ),
        ),
      ),
    ),
  );
  await tester.pumpAndSettle();

  await tester.tap(find.text('Chọn trang trại'));
  await tester.pumpAndSettle();
}

void main() {
  testWidgets('live owner can start creating a farm from the picker', (
    tester,
  ) async {
    final outbox = InMemoryOutboxStore();
    await _openFarmPicker(tester, outbox: outbox);

    expect(find.text('Chưa có nông trại'), findsOneWidget);
    expect(find.text('Tạo nông trại'), findsOneWidget);
    expect(
      await outbox.entries(
        accountId: _accountId,
        organizationId: _organizationId,
      ),
      isEmpty,
    );
  });

  testWidgets('viewer cannot start creating a farm from the live picker', (
    tester,
  ) async {
    final outbox = InMemoryOutboxStore();
    final viewerScope = FarmlyOrganizationScope(
      organization: FarmlyOrganization(
        id: _organizationId,
        name: _organization.name,
        status: FarmlyOrganizationStatus.active,
        policyVersion: '1',
        role: FarmlyOrganizationRole.viewer,
        membershipVersion: 1,
      ),
      directory: _scope.directory,
      epoch: _scope.epoch,
    );
    await _openFarmPicker(tester, outbox: outbox, scope: viewerScope);

    expect(find.text('Tạo nông trại'), findsNothing);
    expect(find.text('Chưa có nông trại'), findsOneWidget);
  });

  testWidgets('preview hides farm creation when durable sync is unavailable', (
    tester,
  ) async {
    final outbox = InMemoryOutboxStore();
    await _openFarmPicker(tester, outbox: outbox, syncEngineAvailable: false);

    expect(find.text('Tạo nông trại'), findsNothing);
    expect(find.byKey(const ValueKey('farm-picker-create-farm')), findsNothing);
    expect(tester.takeException(), isNull);
  });

  Future<void> selectFarmTimeZone(WidgetTester tester) async {
    await tester.tap(find.byKey(const ValueKey('farm-create-timezone')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Asia/Ho_Chi_Minh').last);
    await tester.pumpAndSettle();
  }

  testWidgets('new farm and first zone persist with parent dependency', (
    tester,
  ) async {
    final outbox = InMemoryOutboxStore();
    await _openFarmPicker(tester, outbox: outbox);
    await tester.tap(find.text('Tạo nông trại'));
    await tester.pumpAndSettle();

    await tester.enterText(
      find.byKey(const ValueKey('farm-create-name')),
      'Vườn An',
    );
    await selectFarmTimeZone(tester);
    await tester.enterText(
      find.byKey(const ValueKey('farm-create-area')),
      '1.25',
    );
    await tester.tap(find.byKey(const ValueKey('farm-create-area-unit')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('ha').last);
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('farm-create-seed-zone')));
    await tester.pumpAndSettle();
    await tester.enterText(
      find.byKey(const ValueKey('farm-create-zone-name')),
      'Luống rau A',
    );
    await tester.tap(find.text('Lưu trên thiết bị'));
    await tester.pumpAndSettle();

    final entries = await outbox.entries(
      accountId: _accountId,
      organizationId: _organizationId,
    );
    expect(entries, hasLength(2));
    final farm = entries.singleWhere(
      (entry) => entry.mutation.intent.type == 'farm.create',
    );
    final zone = entries.singleWhere(
      (entry) => entry.mutation.intent.type == 'zone.create',
    );
    expect(farm.mutation.scope.kind, FarmlyMutationScopeKind.organization);
    expect(farm.mutation.intent.payload, {
      'name': 'Vườn An',
      'timezone': 'Asia/Ho_Chi_Minh',
      'areaM2': '12500',
    });
    expect(zone.mutation.scope.farmId, farm.mutation.intent.resourceId);
    expect(zone.dependsOn, [farm.operationId]);
    expect(zone.mutation.intent.payload['name'], 'Luống rau A');
    expect(zone.mutation.intent.payload['type'], 'crop_plot');
    expect(zone.mutation.intent.payload['geometry'], {
      'points': const [
        {'x': '0.28', 'y': '0.28'},
        {'x': '0.72', 'y': '0.28'},
        {'x': '0.72', 'y': '0.72'},
        {'x': '0.28', 'y': '0.72'},
      ],
    });
    expect(tester.takeException(), isNull);
  });

  testWidgets('farm-only creation saves without inventing a zone', (
    tester,
  ) async {
    final outbox = InMemoryOutboxStore();
    await _openFarmPicker(tester, outbox: outbox);
    await tester.tap(find.text('Tạo nông trại'));
    await tester.pumpAndSettle();
    await tester.enterText(
      find.byKey(const ValueKey('farm-create-name')),
      'Vườn Bưởi',
    );
    await selectFarmTimeZone(tester);
    await tester.tap(find.text('Lưu trên thiết bị'));
    await tester.pumpAndSettle();

    final entries = await outbox.entries(
      accountId: _accountId,
      organizationId: _organizationId,
    );
    expect(entries, hasLength(1));
    expect(entries.single.mutation.intent.type, 'farm.create');
    expect(
      entries.single.mutation.scope.kind,
      FarmlyMutationScopeKind.organization,
    );
    expect(
      find.text(
        'Đã lưu nông trại trên thiết bị. Mở Đồng bộ để gửi khi có mạng.',
      ),
      findsOneWidget,
    );
    expect(tester.takeException(), isNull);
  });

  testWidgets('invalid area is explained before anything enters the outbox', (
    tester,
  ) async {
    final outbox = InMemoryOutboxStore();
    await _openFarmPicker(tester, outbox: outbox);
    await tester.tap(find.text('Tạo nông trại'));
    await tester.pumpAndSettle();
    await tester.enterText(
      find.byKey(const ValueKey('farm-create-name')),
      'Vườn An',
    );
    await selectFarmTimeZone(tester);
    await tester.enterText(
      find.byKey(const ValueKey('farm-create-area')),
      '-1.2345678',
    );
    await tester.tap(find.text('Lưu trên thiết bị'));
    await tester.pumpAndSettle();

    expect(find.textContaining('Nhập diện tích hợp lệ'), findsOneWidget);
    expect(
      await outbox.entries(
        accountId: _accountId,
        organizationId: _organizationId,
      ),
      isEmpty,
    );
  });
}
