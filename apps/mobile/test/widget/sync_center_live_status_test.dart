import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:farmly_mobile/core/auth/auth_session_controller.dart';
import 'package:farmly_mobile/core/auth/farmly_auth_models.dart';
import 'package:farmly_mobile/core/network/farmly_api_client.dart';
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
import 'package:farmly_mobile/features/sync/sync_center_screen.dart';
import 'package:farmly_mobile/l10n/generated/app_localizations.dart';

const _accountId = '11111111-1111-4111-8111-111111111111';
const _organizationId = '22222222-2222-4222-8222-222222222222';
const _farmId = '33333333-3333-4333-8333-333333333333';
const _unlistedFarmId = '99999999-9999-4999-8999-999999999999';
const _provisionalFarmId = '88888888-8888-4888-8888-888888888888';
const _rejectedFarmOperationId = 'abababab-abab-4bab-8bab-abababababab';
const _rejectedFarmChildOperationId = 'cdcdcdcd-cdcd-4dcd-8dcd-cdcdcdcdcdcd';
const _rejectedFarmGrandchildOperationId =
    'dddddddd-dddd-4ddd-8ddd-0000efefefef';
final _farmScope = FarmlyMutationScope.farm(
  accountId: _accountId,
  organizationId: _organizationId,
  farmId: _farmId,
  continuityEpoch: '1',
);
final _organizationMutationScope = FarmlyMutationScope.organization(
  accountId: _accountId,
  organizationId: _organizationId,
  continuityEpoch: '1',
);
final _provisionalFarmScope = FarmlyMutationScope.farm(
  accountId: _accountId,
  organizationId: _organizationId,
  farmId: _provisionalFarmId,
  continuityEpoch: '1',
);

const _session = FarmlyAuthSession(
  user: FarmlyAuthUser(
    id: _accountId,
    name: 'Test Farmer',
    email: 'farmer@farmly.test',
  ),
);

const _organizationScope = FarmlyOrganizationScope(
  organization: FarmlyOrganization(
    id: _organizationId,
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
        id: _farmId,
        name: 'Test Farm',
        status: FarmlyFarmStatus.active,
        grantRole: FarmlyFarmGrantRole.owner,
      ),
    ],
  ),
  epoch: 1,
  selectedFarmId: _farmId,
);

class _SignedInSessionController extends FarmlyAuthSessionController {
  @override
  Future<FarmlyAuthSession?> build() async => _session;
}

class _SelectedScopeController extends SelectedOrganizationScopeController {
  @override
  FarmlyOrganizationScope? build() => _organizationScope;
}

class _UnusedTransport implements SyncTransport {
  @override
  Future<MutationBatchResult> submitMutations({
    required FarmlyMutationScope scope,
    required List<FarmlyMutationIntent> operations,
  }) => throw StateError('transport should not be called by this widget test');

  @override
  Future<List<OperationStatusEntry>> operationStatus({
    required String accountId,
    required List<String> operationIds,
  }) => throw StateError('transport should not be called by this widget test');

  @override
  Future<ChangeFeedPage> fetchChanges({
    required FarmlyMutationScope scope,
    required String cursor,
  }) => throw StateError('transport should not be called by this widget test');

  @override
  Future<BootstrapManifest> createBootstrap({
    required FarmlyMutationScope scope,
    required String operationId,
  }) => throw StateError('transport should not be called by this widget test');

  @override
  Future<BootstrapPage> fetchBootstrapPage({
    required FarmlyMutationScope scope,
    required String snapshotId,
    String? pageCursor,
  }) => throw StateError('transport should not be called by this widget test');
}

const _versionedTypes = {
  'farm.update',
  'zone.update',
  'cropSpecies.update',
  'cropSpecies.archive',
  'waterTank.update',
  'planting.update',
  'planting.archive',
};

FarmlyScopedMutation _mutation({
  required String operationId,
  required String type,
  FarmlyMutationScope? scope,
  String resourceId = '44444444-4444-4444-8444-444444444444',
  List<String> dependsOn = const <String>[],
  String payloadMarker = 'private-payload-must-not-render',
}) {
  final versioned = _versionedTypes.contains(type);
  final payload = versioned
      ? <String, Object?>{'name': payloadMarker}
      : type == 'animal.create'
      ? <String, Object?>{'herdId': resourceId, 'tag': payloadMarker}
      : <String, Object?>{'marker': payloadMarker};
  return FarmlyScopedMutation(
    scope: scope ?? _farmScope,
    intent: FarmlyMutationIntent.fromJson({
      'schemaVersion': FarmlyMutationIntent.schemaVersion,
      'operationId': operationId,
      'continuityEpoch': '1',
      'type': type,
      'resourceId': resourceId,
      'baseVersion': versioned ? 1 : null,
      'dependsOn': dependsOn,
      'payload': payload,
    }),
  );
}

Future<FarmlySyncEngine> _engineWithStatuses() async {
  final outbox = InMemoryOutboxStore();
  final fixtures =
      <
        ({
          String id,
          String type,
          OutboxEntryStatus status,
          String? failure,
          String? rejection,
        })
      >[
        (
          id: '55555555-5555-4555-8555-555555555555',
          type: 'zone.create',
          status: OutboxEntryStatus.pending,
          failure: null,
          rejection: null,
        ),
        (
          id: '66666666-6666-4666-8666-666666666666',
          type: 'harvest.create',
          status: OutboxEntryStatus.blocked,
          failure: 'DEPENDENCY_MISSING',
          rejection: null,
        ),
        (
          id: '77777777-7777-4777-8777-777777777777',
          type: 'zone.update',
          status: OutboxEntryStatus.blocked,
          failure: 'DEPENDENCY_CYCLE',
          rejection: null,
        ),
        (
          id: 'aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa',
          type: 'taskOccurrence.transition',
          status: OutboxEntryStatus.rejected,
          failure: null,
          rejection: 'PRIVATE_SERVER_DETAIL_42',
        ),
        (
          id: 'bbbbbbbb-bbbb-4bbb-8bbb-bbbbbbbbbbbb',
          type: 'waterTank.update',
          status: OutboxEntryStatus.rejected,
          failure: null,
          rejection: 'FIELD_VALIDATION_FAILED',
        ),
        (
          id: 'cccccccc-cccc-4ccc-8ccc-cccccccccccc',
          type: 'harvest.create',
          status: OutboxEntryStatus.conflict,
          failure: null,
          rejection: null,
        ),
        (
          id: 'dddddddd-dddd-4ddd-8ddd-dddddddddddd',
          type: 'waterUsage.create',
          status: OutboxEntryStatus.inFlight,
          failure: 'TRANSPORT',
          rejection: null,
        ),
        (
          id: 'eeeeeeee-eeee-4eee-8eee-eeeeeeeeeeee',
          type: 'farm.update',
          status: OutboxEntryStatus.rejected,
          failure: null,
          rejection: 'PERMISSION_DENIED',
        ),
        (
          id: 'abcdefab-abcd-4abc-8abc-abcdefabcdef',
          type: 'cropSpecies.create',
          status: OutboxEntryStatus.applied,
          failure: null,
          rejection: null,
        ),
      ];
  for (final fixture in fixtures) {
    final entry = await outbox.enqueue(
      _mutation(
        operationId: fixture.id,
        type: fixture.type,
        resourceId: fixture.type == 'farm.update'
            ? _farmId
            : '44444444-4444-4444-8444-444444444444',
      ),
    );
    await outbox.update(
      entry.copyWith(
        status: fixture.status,
        lastFailureCode: fixture.failure,
        rejectionCode: fixture.rejection,
      ),
    );
  }
  final unlistedScope = FarmlyMutationScope.farm(
    accountId: _accountId,
    organizationId: _organizationId,
    farmId: _unlistedFarmId,
    continuityEpoch: '1',
  );
  await outbox.enqueue(
    _mutation(
      operationId: 'ffffffff-ffff-4fff-8fff-ffffffffffff',
      type: 'animal.create',
      scope: unlistedScope,
      payloadMarker: 'unlisted-farm-payload-must-not-render',
    ),
  );
  final rejectedFarm = await outbox.enqueue(
    _mutation(
      operationId: _rejectedFarmOperationId,
      type: 'farm.create',
      scope: _organizationMutationScope,
      resourceId: _provisionalFarmId,
      payloadMarker: 'rejected-farm-private-payload-must-not-render',
    ),
  );
  await outbox.update(
    rejectedFarm.copyWith(
      status: OutboxEntryStatus.rejected,
      rejectionCode: 'ACCESS_REVOKED',
    ),
  );
  final rejectedFarmChild = await outbox.enqueue(
    _mutation(
      operationId: _rejectedFarmChildOperationId,
      type: 'planting.create',
      scope: _provisionalFarmScope,
      dependsOn: const <String>[_rejectedFarmOperationId],
      payloadMarker: 'rejected-child-private-payload-must-not-render',
    ),
  );
  await outbox.update(
    rejectedFarmChild.copyWith(
      status: OutboxEntryStatus.blocked,
      lastFailureCode: 'DEPENDENCY_FAILED',
    ),
  );
  final rejectedFarmGrandchild = await outbox.enqueue(
    _mutation(
      operationId: _rejectedFarmGrandchildOperationId,
      type: 'harvest.create',
      scope: _provisionalFarmScope,
      dependsOn: const <String>[_rejectedFarmChildOperationId],
      payloadMarker: 'rejected-grandchild-private-payload-must-not-render',
    ),
  );
  await outbox.update(
    rejectedFarmGrandchild.copyWith(
      status: OutboxEntryStatus.blocked,
      lastFailureCode: 'DEPENDENCY_BLOCKED',
    ),
  );
  return FarmlySyncEngine(
    outbox: outbox,
    transport: _UnusedTransport(),
    domain: InMemoryDomainStore(),
  );
}

void main() {
  testWidgets(
    'live queue explains durable states without payloads or raw error codes',
    (tester) async {
      tester.view.physicalSize = const Size(900, 1800);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      final engine = await _engineWithStatuses();

      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            farmlyAuthSessionProvider.overrideWith(
              _SignedInSessionController.new,
            ),
            selectedOrganizationScopeProvider.overrideWith(
              _SelectedScopeController.new,
            ),
            farmlySyncScopeProvider.overrideWith((ref) async => _farmScope),
            syncEngineProvider.overrideWith((ref) async => engine),
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
            home: const SyncCenterScreen(),
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(tester.takeException(), isNull);
      expect(find.text('Đã lưu trên thiết bị'), findsWidgets);
      expect(find.text('Đã đồng bộ'), findsOneWidget);
      expect(find.textContaining('Đang xác minh kết quả'), findsOneWidget);
      expect(
        find.textContaining('thao tác phụ thuộc được khôi phục'),
        findsOneWidget,
      );
      expect(
        find.textContaining('vòng phụ thuộc; cần kiểm tra'),
        findsOneWidget,
      );
      expect(find.textContaining('xung đột cần bạn chọn'), findsOneWidget);
      expect(
        find.textContaining(
          'Máy chủ chưa chấp nhận thao tác; bản lưu vẫn được giữ',
        ),
        findsOneWidget,
      );
      expect(
        find.textContaining('dữ liệu đã lưu trước khi đồng bộ lại'),
        findsOneWidget,
      );
      expect(find.textContaining('Máy chủ từ chối quyền'), findsNWidgets(2));
      expect(find.textContaining('55555555'), findsOneWidget);
      expect(
        find.textContaining('private-payload-must-not-render'),
        findsNothing,
      );
      expect(
        find.textContaining('Thao tác phụ thuộc đã bị máy chủ từ chối'),
        findsOneWidget,
      );
      expect(find.textContaining('efefefef'), findsOneWidget);
      expect(find.textContaining('4 bị chặn'), findsOneWidget);
      expect(
        find.textContaining('rejected-farm-private-payload-must-not-render'),
        findsNothing,
      );
      expect(
        find.textContaining('rejected-child-private-payload-must-not-render'),
        findsNothing,
      );
      expect(
        find.textContaining('rejected-grandchild-private-payload-must-not-render'),
        findsNothing,
      );
      expect(find.textContaining('PRIVATE_SERVER_DETAIL_42'), findsNothing);
      expect(
        find.textContaining('unlisted-farm-payload-must-not-render'),
        findsNothing,
      );
      expect(find.textContaining('ffffffff'), findsNothing);
      // This online preview has no connectivity observation, so it must not
      // claim that the live entry is waiting for a network.
      expect(find.text('Chờ mạng'), findsNothing);
    },
  );

  test('sync failure presentation only trusts typed failure codes', () {
    expect(
      classifySyncStatusFailure(
        const FarmlyApiFailure(FarmlyApiFailureCode.permissionDenied),
      ),
      SyncStatusFailureKind.permissionDenied,
    );
    expect(
      classifySyncStatusFailure(
        const FarmlyApiFailure(FarmlyApiFailureCode.unavailable),
      ),
      SyncStatusFailureKind.serviceUnavailable,
    );
    expect(
      classifySyncStatusFailure(
        StateError('PRIVATE_PROVIDER_TOKEN must never be shown'),
      ),
      SyncStatusFailureKind.unknown,
    );
  });
}
