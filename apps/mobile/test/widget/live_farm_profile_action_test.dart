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
import 'package:farmly_mobile/features/farm/farm_overview_screen.dart';
import 'package:farmly_mobile/features/organizations/organization_repository.dart';
import 'package:farmly_mobile/features/organizations/organization_scope_controller.dart';
import 'package:farmly_mobile/l10n/generated/app_localizations.dart';

const _accountId = '11111111-1111-4111-8111-111111111111';
const _otherAccountId = '12121212-1212-4121-8121-121212121212';
const _organizationId = '22222222-2222-4222-8222-222222222222';
const _otherOrganizationId = '23232323-2323-4232-8232-232323232323';
const _farmId = '33333333-3333-4333-8333-333333333333';
const _otherFarmId = '34343434-3434-4343-8343-343434343434';
const _operationId = '44444444-4444-4444-8444-444444444444';
const _rejectedFarmOperationIdA = '49494949-4949-4494-8949-494949494941';
const _rejectedFarmOperationIdB = '49494949-4949-4494-8949-494949494942';
const _rejectedFarmOperationIdC = '49494949-4949-4494-8949-494949494943';
const _otherFarmOperationId = '45454545-4545-4545-8545-454545454545';
const _otherEpochOperationId = '46464646-4646-4646-8646-464646464646';
const _otherOrganizationOperationId = '47474747-4747-4747-8747-474747474747';
const _otherAccountOperationId = '48484848-4848-4848-8848-484848484848';

const _farmEditKey = ValueKey('farm-overview-edit-farm');
const _farmNameKey = ValueKey('farm-edit-name');
const _farmSaveKey = ValueKey('farm-edit-save');

const _session = FarmlyAuthSession(
  user: FarmlyAuthUser(
    id: _accountId,
    name: 'Test Farmer',
    email: 'farmer@farmly.test',
  ),
);

const _pendingCopy = 'Đã lưu trên thiết bị · Chờ đồng bộ';

class _SignedInSessionController extends FarmlyAuthSessionController {
  @override
  Future<FarmlyAuthSession?> build() async => _session;
}

class _MutableSelectedScopeController
    extends SelectedOrganizationScopeController {
  _MutableSelectedScopeController(this.initialScope);

  final FarmlyOrganizationScope? initialScope;

  @override
  FarmlyOrganizationScope? build() => initialScope;

  void replace(FarmlyOrganizationScope? scope) => state = scope;
}

class _OfflineOnlyTransport implements SyncTransport {
  int calls = 0;

  @override
  Future<MutationBatchResult> submitMutations({
    required FarmlyMutationScope scope,
    required List<FarmlyMutationIntent> operations,
  }) {
    calls++;
    throw StateError('farm profile tests must not send live mutations');
  }

  @override
  Future<List<OperationStatusEntry>> operationStatus({
    required String accountId,
    required List<String> operationIds,
  }) {
    calls++;
    throw StateError('farm profile tests must not query operation status');
  }

  @override
  Future<ChangeFeedPage> fetchChanges({
    required FarmlyMutationScope scope,
    required String cursor,
  }) {
    calls++;
    throw StateError('farm profile tests must not fetch live changes');
  }

  @override
  Future<BootstrapManifest> createBootstrap({
    required FarmlyMutationScope scope,
    required String operationId,
  }) {
    calls++;
    throw StateError('farm profile tests must not bootstrap from the network');
  }

  @override
  Future<BootstrapPage> fetchBootstrapPage({
    required FarmlyMutationScope scope,
    required String snapshotId,
    String? pageCursor,
  }) {
    calls++;
    throw StateError('farm profile tests must not fetch bootstrap pages');
  }
}

final class _FarmOverviewHarness {
  const _FarmOverviewHarness({
    required this.container,
    required this.domain,
    required this.outbox,
    required this.transport,
    required this.scopeController,
  });

  final ProviderContainer container;
  final InMemoryDomainStore domain;
  final InMemoryOutboxStore outbox;
  final _OfflineOnlyTransport transport;
  final _MutableSelectedScopeController scopeController;
}

FarmlyOrganizationScope _scope({
  String organizationId = _organizationId,
  String organizationName = 'Tổ chức kiểm thử',
  String farmId = _farmId,
  String farmName = 'Tên trong danh bạ',
  String continuityEpoch = '37',
  int selectionEpoch = 11,
  FarmlyOrganizationRole organizationRole = FarmlyOrganizationRole.owner,
  FarmlyFarmGrantRole farmRole = FarmlyFarmGrantRole.owner,
}) => FarmlyOrganizationScope(
  organization: FarmlyOrganization(
    id: organizationId,
    name: organizationName,
    status: FarmlyOrganizationStatus.active,
    policyVersion: '9',
    role: organizationRole,
    membershipVersion: 2,
  ),
  directory: FarmlyFarmDirectory(
    scopePolicyVersion: '9',
    continuityEpoch: continuityEpoch,
    farms: [
      FarmlyDirectoryFarm(
        id: farmId,
        name: farmName,
        status: FarmlyFarmStatus.active,
        grantRole: farmRole,
      ),
    ],
  ),
  epoch: selectionEpoch,
  selectedFarmId: farmId,
);

String _scopeKey({
  String accountId = _accountId,
  String organizationId = _organizationId,
  String farmId = _farmId,
}) => '$accountId|$organizationId|$farmId';

Future<void> _installFarmSnapshot(
  InMemoryDomainStore domain,
  FarmlyOrganizationScope scope, {
  String name = 'Tên đã xác nhận',
  int version = 7,
  String status = 'active',
}) => domain.installBootstrap(
  scopeKey: _scopeKey(
    accountId: _accountId,
    organizationId: scope.organization.id,
    farmId: scope.selectedFarmId!,
  ),
  blocks: [
    BootstrapBlock(
      entity: 'farm',
      records: [
        {
          'farmId': scope.selectedFarmId,
          'name': name,
          'areaM2': '12500',
          'timezone': 'Asia/Ho_Chi_Minh',
          'status': status,
          'version': version,
        },
      ],
    ),
    const BootstrapBlock(entity: 'zone', records: []),
  ],
  cursor: SyncCursorState(
    cursor: 'cursor-${scope.directory.continuityEpoch}',
    highWatermark: '12',
    continuityEpoch: scope.directory.continuityEpoch,
    scopePolicyVersion: scope.directory.scopePolicyVersion,
  ),
);

FarmlyMutationIntent _restoredFarmUpdate({
  required String operationId,
  required String farmId,
  required String continuityEpoch,
  required String name,
  int baseVersion = 7,
}) => FarmlyMutationIntent.fromJson({
  'schemaVersion': FarmlyMutationIntent.schemaVersion,
  'continuityEpoch': continuityEpoch,
  'operationId': operationId,
  'type': 'farm.update',
  'resourceId': farmId,
  'baseVersion': baseVersion,
  'dependsOn': const <String>[],
  'payload': {'name': name},
});

Future<_FarmOverviewHarness> _pumpOverview(
  WidgetTester tester, {
  FarmlyOrganizationScope? scope,
  InMemoryDomainStore? domain,
  InMemoryOutboxStore? outbox,
  bool bootstrap = true,
  String confirmedName = 'Tên đã xác nhận',
  int confirmedVersion = 7,
  String farmStatus = 'active',
}) async {
  final localDomain = domain ?? InMemoryDomainStore();
  final localOutbox = outbox ?? InMemoryOutboxStore();
  final selectedScope = scope ?? _scope();
  if (bootstrap) {
    await _installFarmSnapshot(
      localDomain,
      selectedScope,
      name: confirmedName,
      version: confirmedVersion,
      status: farmStatus,
    );
  }
  final transport = _OfflineOnlyTransport();
  final engine = FarmlySyncEngine(
    outbox: localOutbox,
    transport: transport,
    domain: localDomain,
  );
  late final _MutableSelectedScopeController scopeController;
  final container = ProviderContainer(
    overrides: [
      farmlyAuthSessionProvider.overrideWith(_SignedInSessionController.new),
      selectedOrganizationScopeProvider.overrideWith(() {
        scopeController = _MutableSelectedScopeController(selectedScope);
        return scopeController;
      }),
      syncEngineProvider.overrideWith((ref) async => engine),
    ],
  );
  container.read(selectedOrganizationScopeProvider);
  addTearDown(container.dispose);
  tester.view.physicalSize = const Size(390, 844);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  await tester.pumpWidget(
    UncontrolledProviderScope(
      container: container,
      child: MaterialApp(
        theme: buildFarmTheme(),
        locale: const Locale('vi'),
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        builder: (context, child) => MediaQuery(
          data: MediaQuery.of(context).copyWith(disableAnimations: true),
          child: child!,
        ),
        home: const FarmOverviewScreen(),
      ),
    ),
  );
  await tester.pumpAndSettle();
  return _FarmOverviewHarness(
    container: container,
    domain: localDomain,
    outbox: localOutbox,
    transport: transport,
    scopeController: scopeController,
  );
}

Future<void> _openFarmEdit(WidgetTester tester) async {
  await tester.tap(find.byKey(_farmEditKey));
  await tester.pumpAndSettle();
  expect(find.byKey(_farmNameKey), findsOneWidget);
  expect(find.byKey(_farmSaveKey), findsOneWidget);
}

void main() {
  testWidgets('owner opens an edit form prefilled from confirmed farm data', (
    tester,
  ) async {
    final harness = await _pumpOverview(tester);

    expect(find.byKey(_farmEditKey), findsOneWidget);
    await _openFarmEdit(tester);
    expect(
      tester.widget<TextField>(find.byKey(_farmNameKey)).controller?.text,
      'Tên đã xác nhận',
    );
    expect(harness.transport.calls, 0);
    expect(tester.takeException(), isNull);
  });

  testWidgets('organization admin can open the selected farm editor', (
    tester,
  ) async {
    await _pumpOverview(
      tester,
      scope: _scope(
        organizationRole: FarmlyOrganizationRole.admin,
        farmRole: FarmlyFarmGrantRole.admin,
      ),
    );

    expect(find.byKey(_farmEditKey), findsOneWidget);
    await _openFarmEdit(tester);
    expect(
      tester.widget<TextField>(find.byKey(_farmNameKey)).controller?.text,
      'Tên đã xác nhận',
    );
    expect(tester.takeException(), isNull);
  });

  for (final (label, farmRole) in <(String, FarmlyFarmGrantRole)>[
    ('manager', FarmlyFarmGrantRole.manager),
    ('worker', FarmlyFarmGrantRole.worker),
    ('viewer', FarmlyFarmGrantRole.viewer),
  ]) {
    testWidgets('$label farm grant cannot edit a farm profile', (tester) async {
      await _pumpOverview(
        tester,
        scope: _scope(
          organizationRole: FarmlyOrganizationRole.member,
          farmRole: farmRole,
        ),
      );

      expect(find.byKey(_farmEditKey), findsNothing);
      expect(tester.takeException(), isNull);
    });
  }

  testWidgets('organization viewer cannot edit a farm profile', (tester) async {
    await _pumpOverview(
      tester,
      scope: _scope(
        organizationRole: FarmlyOrganizationRole.viewer,
        farmRole: FarmlyFarmGrantRole.viewer,
      ),
    );

    expect(find.byKey(_farmEditKey), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets(
    'owner saves one scoped farm.update with CAS and sees its pending name',
    (tester) async {
      final harness = await _pumpOverview(tester);
      await _openFarmEdit(tester);
      await tester.enterText(find.byKey(_farmNameKey), 'Nông trại mới');
      await tester.tap(find.byKey(_farmSaveKey));
      await tester.pumpAndSettle();

      final entries = await harness.outbox.entries(
        accountId: _accountId,
        organizationId: _organizationId,
      );
      expect(entries, hasLength(1));
      final entry = entries.single;
      final intent = entry.mutation.intent;
      expect(intent.type, 'farm.update');
      expect(intent.resourceId, _farmId);
      expect(intent.baseVersion, 7);
      expect(intent.continuityEpoch, '37');
      expect(intent.dependsOn, isEmpty);
      expect(intent.payload, {'name': 'Nông trại mới'});
      expect(entry.mutation.scope.accountId, _accountId);
      expect(entry.mutation.scope.organizationId, _organizationId);
      expect(entry.mutation.scope.farmId, _farmId);
      expect(entry.mutation.scope.continuityEpoch, '37');
      expect(entry.mutation.scope.kind, FarmlyMutationScopeKind.farm);
      expect(harness.transport.calls, 0);

      expect(find.text('Nông trại mới'), findsOneWidget);
      expect(find.text('Tên đã xác nhận'), findsNothing);
      expect(find.text(_pendingCopy), findsOneWidget);
      await _openFarmEdit(tester);
      expect(
        tester.widget<TextField>(find.byKey(_farmNameKey)).controller?.text,
        'Nông trại mới',
      );
      expect(
        tester.widget<TextField>(find.byKey(_farmNameKey)).enabled,
        isFalse,
      );
      expect(
        tester.widget<FilledButton>(find.byKey(_farmSaveKey)).onPressed,
        isNull,
      );
      expect(harness.transport.calls, 0);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'pending name overlay is exact-scope and does not duplicate the farm',
    (tester) async {
      final scope = _scope();
      final outbox = InMemoryOutboxStore();
      Future<void> queue({
        required String operationId,
        required String accountId,
        required String organizationId,
        required String farmId,
        required String continuityEpoch,
        required String name,
      }) async {
        await outbox.enqueue(
          FarmlyScopedMutation(
            scope: FarmlyMutationScope.farm(
              accountId: accountId,
              organizationId: organizationId,
              farmId: farmId,
              continuityEpoch: continuityEpoch,
            ),
            intent: _restoredFarmUpdate(
              operationId: operationId,
              farmId: farmId,
              continuityEpoch: continuityEpoch,
              name: name,
            ),
          ),
        );
      }

      await queue(
        operationId: _operationId,
        accountId: _accountId,
        organizationId: _organizationId,
        farmId: _farmId,
        continuityEpoch: '37',
        name: 'Tên đang chờ',
      );
      await queue(
        operationId: _otherFarmOperationId,
        accountId: _accountId,
        organizationId: _organizationId,
        farmId: _otherFarmId,
        continuityEpoch: '37',
        name: 'Tên sai nông trại',
      );
      await queue(
        operationId: _otherEpochOperationId,
        accountId: _accountId,
        organizationId: _organizationId,
        farmId: _farmId,
        continuityEpoch: '38',
        name: 'Tên sai epoch',
      );
      await queue(
        operationId: _otherOrganizationOperationId,
        accountId: _accountId,
        organizationId: _otherOrganizationId,
        farmId: _farmId,
        continuityEpoch: '37',
        name: 'Tên sai tổ chức',
      );
      await queue(
        operationId: _otherAccountOperationId,
        accountId: _otherAccountId,
        organizationId: _organizationId,
        farmId: _farmId,
        continuityEpoch: '37',
        name: 'Tên sai tài khoản',
      );

      final harness = await _pumpOverview(tester, scope: scope, outbox: outbox);

      expect(find.text('Tên đang chờ'), findsOneWidget);
      expect(find.text('Tên đã xác nhận'), findsNothing);
      expect(find.text('Tên sai nông trại'), findsNothing);
      expect(find.text('Tên sai epoch'), findsNothing);
      expect(find.text('Tên sai tổ chức'), findsNothing);
      expect(find.text('Tên sai tài khoản'), findsNothing);
      expect(find.byKey(_farmEditKey), findsOneWidget);
      await _openFarmEdit(tester);
      expect(
        tester.widget<TextField>(find.byKey(_farmNameKey)).controller?.text,
        'Tên đang chờ',
      );
      expect(harness.transport.calls, 0);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets('multiple rejected farm name updates leave editing available', (
    tester,
  ) async {
    final outbox = InMemoryOutboxStore();
    for (final (operationId, name) in <(String, String)>[
      (_rejectedFarmOperationIdA, 'Tên bị từ chối 1'),
      (_rejectedFarmOperationIdB, 'Tên bị từ chối 2'),
      (_rejectedFarmOperationIdC, 'Tên bị từ chối 3'),
    ]) {
      final rejected = await outbox.enqueue(
        FarmlyScopedMutation(
          scope: FarmlyMutationScope.farm(
            accountId: _accountId,
            organizationId: _organizationId,
            farmId: _farmId,
            continuityEpoch: '37',
          ),
          intent: _restoredFarmUpdate(
            operationId: operationId,
            farmId: _farmId,
            continuityEpoch: '37',
            name: name,
          ),
        ),
      );
      await outbox.update(
        rejected.copyWith(
          status: OutboxEntryStatus.rejected,
          rejectionCode: 'FIELD_VALIDATION_FAILED',
        ),
      );
    }

    final harness = await _pumpOverview(tester, outbox: outbox);

    expect(find.text(_pendingCopy), findsNothing);
    expect(find.byKey(_farmEditKey), findsOneWidget);
    await _openFarmEdit(tester);
    expect(tester.widget<TextField>(find.byKey(_farmNameKey)).enabled, isTrue);
    await tester.enterText(find.byKey(_farmNameKey), 'Tên thử lại');
    await tester.tap(find.byKey(_farmSaveKey));
    await tester.pumpAndSettle();

    final entries = await outbox.entries(
      accountId: _accountId,
      organizationId: _organizationId,
    );
    expect(entries, hasLength(4));
    expect(
      entries.where((entry) => entry.status == OutboxEntryStatus.pending),
      hasLength(1),
    );
    expect(harness.transport.calls, 0);
    expect(find.text(_pendingCopy), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('edit is unavailable before the farm has a confirmed snapshot', (
    tester,
  ) async {
    await _pumpOverview(tester, bootstrap: false);

    expect(find.byKey(_farmEditKey), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets('archived farm row cannot open the profile editor', (
    tester,
  ) async {
    await _pumpOverview(tester, farmStatus: 'archived');

    expect(find.byKey(_farmEditKey), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets('farm switch while editor is open rejects the stale save', (
    tester,
  ) async {
    final domain = InMemoryDomainStore();
    final scopeA = _scope();
    final scopeB = _scope(
      organizationId: _otherOrganizationId,
      organizationName: 'Tổ chức khác',
      farmId: _otherFarmId,
      farmName: 'Nông trại khác',
      continuityEpoch: '52',
      selectionEpoch: 18,
    );
    await _installFarmSnapshot(domain, scopeA);
    await _installFarmSnapshot(
      domain,
      scopeB,
      name: 'Bản ghi khác',
      version: 4,
    );
    final harness = await _pumpOverview(tester, scope: scopeA, domain: domain);
    await _openFarmEdit(tester);
    await tester.enterText(find.byKey(_farmNameKey), 'Tên cũ');

    harness.scopeController.replace(scopeB);
    await tester.pumpAndSettle();
    final save = find.byKey(_farmSaveKey);
    if (save.evaluate().isNotEmpty) {
      await tester.tap(save);
      await tester.pumpAndSettle();
    }

    expect(
      await harness.outbox.entries(
        accountId: _accountId,
        organizationId: _organizationId,
      ),
      isEmpty,
    );
    expect(
      await harness.outbox.entries(
        accountId: _accountId,
        organizationId: _otherOrganizationId,
      ),
      isEmpty,
    );
    expect(harness.transport.calls, 0);
    expect(tester.takeException(), isNull);
  });

  testWidgets('changed confirmed farm version rejects a stale form save', (
    tester,
  ) async {
    final domain = InMemoryDomainStore();
    final scope = _scope();
    await _installFarmSnapshot(domain, scope, version: 7);
    final harness = await _pumpOverview(tester, scope: scope, domain: domain);
    await _openFarmEdit(tester);
    await tester.enterText(find.byKey(_farmNameKey), 'Tên trên phiên bản cũ');

    await _installFarmSnapshot(
      domain,
      scope,
      name: 'Tên mới từ thiết bị khác',
      version: 8,
    );
    await tester.tap(find.byKey(_farmSaveKey));
    await tester.pumpAndSettle();

    expect(
      await harness.outbox.entries(
        accountId: _accountId,
        organizationId: _organizationId,
      ),
      isEmpty,
    );
    expect(harness.transport.calls, 0);
    expect(tester.takeException(), isNull);
  });

  testWidgets('role loss while editor is open rejects the stale save', (
    tester,
  ) async {
    final harness = await _pumpOverview(tester);
    await _openFarmEdit(tester);
    await tester.enterText(find.byKey(_farmNameKey), 'Tên không được lưu');
    harness.scopeController.replace(
      _scope(
        organizationRole: FarmlyOrganizationRole.member,
        farmRole: FarmlyFarmGrantRole.manager,
        selectionEpoch: 12,
      ),
    );
    await tester.pumpAndSettle();
    final save = find.byKey(_farmSaveKey);
    if (save.evaluate().isNotEmpty) {
      await tester.tap(save);
      await tester.pumpAndSettle();
    }

    expect(
      await harness.outbox.entries(
        accountId: _accountId,
        organizationId: _organizationId,
      ),
      isEmpty,
    );
    expect(harness.transport.calls, 0);
    expect(tester.takeException(), isNull);
  });
}
