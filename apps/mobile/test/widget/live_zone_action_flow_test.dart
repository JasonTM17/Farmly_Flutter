import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:farmly_mobile/core/auth/auth_session_controller.dart';
import 'package:farmly_mobile/core/auth/farmly_auth_models.dart';
import 'package:farmly_mobile/core/sync/farmly_mutation.dart';
import 'package:farmly_mobile/core/sync/farmly_task_schedule.dart';
import 'package:farmly_mobile/generated/farmly_api_types.dart';
import 'package:farmly_mobile/core/sync/local_domain_store.dart';
import 'package:farmly_mobile/core/sync/outbox_store.dart';
import 'package:farmly_mobile/core/sync/sync_engine.dart';
import 'package:farmly_mobile/core/sync/sync_models.dart';
import 'package:farmly_mobile/core/sync/sync_providers.dart';
import 'package:farmly_mobile/core/sync/sync_transport.dart';
import 'package:farmly_mobile/core/theme/farm_theme.dart';
import 'package:farmly_mobile/features/demo/demo_providers.dart';
import 'package:farmly_mobile/features/farm/farm_overview_screen.dart';
import 'package:farmly_mobile/features/farm/live_farm_zones.dart';
import 'package:farmly_mobile/features/organizations/organization_repository.dart';
import 'package:farmly_mobile/features/organizations/organization_scope_controller.dart';
import 'package:farmly_mobile/l10n/generated/app_localizations.dart';
import 'package:farmly_mobile/ui/form_fields.dart';

const _accountId = '11111111-1111-4111-8111-111111111111';
const _organizationAId = '22222222-2222-4222-8222-222222222222';
const _farmAId = '33333333-3333-4333-8333-333333333333';
const _farmAOtherId = '44444444-4444-4444-8444-444444444444';
const _organizationBId = '55555555-5555-4555-8555-555555555555';
const _farmBId = '66666666-6666-4666-8666-666666666666';
const _cropPlotZoneAId = '77777777-7777-4777-8777-777777777777';
const _cropPlotZoneBId = '88888888-8888-4888-8888-888888888888';
const _cropSpeciesAId = '99999999-9999-4999-8999-999999999999';
const _cropSpeciesBId = 'aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa';
const _plantingAId = 'bbbbbbbb-bbbb-4bbb-8bbb-bbbbbbbbbbbb';
const _plantingBId = 'cccccccc-cccc-4ccc-8ccc-cccccccccccc';
const _plantingCreateOperationId = 'd1d1d1d1-d1d1-41d1-81d1-d1d1d1d1d1d1';
const _harvestAId = 'eeeeeeee-eeee-4eee-8eee-eeeeeeeeeeee';
const _harvestProposalAId = 'efefefef-efef-4fef-8fef-efefefefefef';
const _harvestOperationId = 'f0f0f0f0-f0f0-40f0-80f0-f0f0f0f0f0f0';
const _harvestOtherId = 'f1f1f1f1-f1f1-41f1-81f1-f1f1f1f1f1f1';
const _appliedHarvestCorrectionOperationId =
    'f2f2f2f2-f2f2-42f2-82f2-f2f2f2f2f2f2';
const _cropSpeciesArchiveOperationId = 'f3f3f3f3-f3f3-43f3-83f3-f3f3f3f3f3f3';
const _cropSpeciesArchiveDuplicateOperationId =
    'f4f4f4f4-f4f4-44f4-84f4-f4f4f4f4f4f4';
const _waterZoneAId = '12121212-1212-4121-8121-121212121212';
const _waterTankAId = '13131313-1313-4131-8131-131313131313';
const _taskTemplateAId = '14141414-1414-4141-8141-141414141414';
const _taskTemplateBId = '15151515-1515-4151-8151-151515151515';
const _taskTemplateArchivedId = '16161616-1616-4161-8161-161616161616';
const _taskTemplateOperationId = '17171717-1717-4171-8171-171717171717';
const _membershipId = '18181818-1818-4181-8181-181818181818';

const _session = FarmlyAuthSession(
  user: FarmlyAuthUser(
    id: _accountId,
    name: 'Test Farmer',
    email: 'farmer@farmly.test',
  ),
);

const _liveZoneCreateKey = ValueKey('live-zone-create');
const _liveZoneNameKey = ValueKey('live-zone-name');
const _liveZoneSaveKey = ValueKey('live-zone-save');
const _liveZoneEditNameKey = ValueKey('live-zone-edit-name');
const _liveZoneEditNameFieldKey = ValueKey('live-zone-edit-name-field');
const _liveZoneEditNameSaveKey = ValueKey('live-zone-edit-name-save');
const _liveFarmNoCacheKey = ValueKey('live-farm-no-cache');
const _liveZoneDetailsKey = ValueKey('live-zone-details');
const _liveCropSpeciesListKey = ValueKey('live-crop-species-list');
const _livePlantingsListKey = ValueKey('live-plantings-list');
const _liveCropSpeciesCreateKey = ValueKey('live-crop-species-create');
const _liveCropSpeciesNameKey = ValueKey('live-crop-species-name');
const _liveCropSpeciesUnitKey = ValueKey('live-crop-species-unit');
const _liveCropSpeciesSaveKey = ValueKey('live-crop-species-save');
const _liveCropSpeciesEditNameKey = ValueKey('live-crop-species-edit-name');
const _liveCropSpeciesEditSaveKey = ValueKey('live-crop-species-edit-save');
const _liveCropSpeciesArchiveDialogKey = ValueKey(
  'live-crop-species-archive-dialog',
);
const _liveCropSpeciesArchiveConfirmKey = ValueKey(
  'live-crop-species-archive-confirm',
);
const _liveCropSpeciesArchiveCancelKey = ValueKey(
  'live-crop-species-archive-cancel',
);
const _livePlantingCreateKey = ValueKey('live-planting-create');
const _livePlantingSpeciesKey = ValueKey('live-planting-species');
const _livePlantingSowingDateKey = ValueKey('live-planting-sowing-date');
const _livePlantingExpectedHarvestDateKey = ValueKey(
  'live-planting-expected-harvest-date',
);
const _livePlantingAreaKey = ValueKey('live-planting-area-m2');
const _livePlantingSaveKey = ValueKey('live-planting-save');
const _livePlantingEditStatusKey = ValueKey('live-planting-edit-status');
const _livePlantingEditSowingDateKey = ValueKey(
  'live-planting-edit-sowing-date',
);
const _livePlantingEditExpectedHarvestDateKey = ValueKey(
  'live-planting-edit-expected-harvest-date',
);
const _livePlantingEditAreaKey = ValueKey('live-planting-edit-area-m2');
const _livePlantingEditSaveKey = ValueKey('live-planting-edit-save');
const _livePlantingArchiveDialogKey = ValueKey('live-planting-archive-dialog');
const _livePlantingArchiveConfirmKey = ValueKey(
  'live-planting-archive-confirm',
);
const _livePlantingArchiveCancelKey = ValueKey('live-planting-archive-cancel');
const _liveTaskOccurrencesListKey = ValueKey('live-task-occurrences-list');
const _liveMoistureCreateKey = ValueKey('live-moisture-create');
const _liveMoistureValueKey = ValueKey('live-moisture-value');
const _liveMoistureMethodKey = ValueKey('live-moisture-method');
const _liveMoistureMethodVwcKey = ValueKey('live-moisture-method-vwc_percent');
const _liveMoistureSaveKey = ValueKey('live-moisture-save');
const _livePlantingEventTypeKey = ValueKey('live-planting-event-type');
const _livePlantingEventNoteKey = ValueKey('live-planting-event-note');
const _livePlantingEventDateKey = ValueKey('live-planting-event-date');
const _livePlantingEventSaveKey = ValueKey('live-planting-event-save');
const _liveHarvestQuantityKey = ValueKey('live-harvest-quantity-kg');
const _liveHarvestDateKey = ValueKey('live-harvest-date');
const _liveHarvestSaveKey = ValueKey('live-harvest-save');
const _liveWaterTankCreateKey = ValueKey('live-water-tank-create');
const _liveWaterReadingCreateKey = ValueKey(
  'live-water-reading-create-$_waterTankAId',
);
const _liveWaterUsageCreateKey = ValueKey(
  'live-water-usage-create-$_waterTankAId',
);
const _liveWaterTankNameKey = ValueKey('live-water-tank-name');
const _liveWaterTankCapacityKey = ValueKey('live-water-tank-capacity-litres');
const _liveWaterTankEditNameKey = ValueKey('live-water-tank-edit-name');
const _liveWaterTankEditSaveKey = ValueKey('live-water-tank-edit-save');
const _liveWaterReadingAmountKey = ValueKey('live-water-reading-stored-litres');
const _liveWaterUsageAmountKey = ValueKey('live-water-usage-litres');
const _liveWaterUsageDateKey = ValueKey('live-water-usage-date');
const _liveWaterUsageNoteKey = ValueKey('live-water-usage-note');
const _liveWaterActionSaveKey = ValueKey('live-water-action-save');
const _liveTaskTemplateTitleKey = ValueKey('live-task-template-title');
const _liveTaskTemplateKindKey = ValueKey('live-task-template-kind');
const _liveTaskTemplateFrequencyKey = ValueKey('live-task-template-frequency');
const _liveTaskTemplateSaveKey = ValueKey('live-task-template-save');
const _savedPendingCopy = 'Đã lưu trên thiết bị · Chờ đồng bộ';

ValueKey<String> _liveHarvestCreateKey(String plantingId) =>
    ValueKey('live-harvest-create-$plantingId');

ValueKey<String> _livePlantingEventCreateKey(String plantingId) =>
    ValueKey('live-planting-event-create-$plantingId');

ValueKey<String> _livePlantingEventRowKey(String eventId) =>
    ValueKey('live-planting-event-row-$eventId');

ValueKey<String> _livePlantingEditKey(String plantingId) =>
    ValueKey('live-planting-edit-$plantingId');

ValueKey<String> _livePlantingArchiveKey(String plantingId) =>
    ValueKey('live-planting-archive-$plantingId');

ValueKey<String> _liveCropSpeciesEditKey(String speciesId) =>
    ValueKey('live-crop-species-edit-$speciesId');

ValueKey<String> _liveCropSpeciesArchiveKey(String speciesId) =>
    ValueKey('live-crop-species-archive-$speciesId');

ValueKey<String> _liveWaterTankEditKey(String tankId) =>
    ValueKey('live-water-tank-edit-$tankId');

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
    throw StateError('widget test must not send live mutations');
  }

  @override
  Future<List<OperationStatusEntry>> operationStatus({
    required String accountId,
    required List<String> operationIds,
  }) {
    calls++;
    throw StateError('widget test must not query operation status');
  }

  @override
  Future<ChangeFeedPage> fetchChanges({
    required FarmlyMutationScope scope,
    required String cursor,
  }) {
    calls++;
    throw StateError('widget test must not fetch live changes');
  }

  @override
  Future<BootstrapManifest> createBootstrap({
    required FarmlyMutationScope scope,
    required String operationId,
  }) {
    calls++;
    throw StateError('widget test must not bootstrap from the network');
  }

  @override
  Future<BootstrapPage> fetchBootstrapPage({
    required FarmlyMutationScope scope,
    required String snapshotId,
    String? pageCursor,
  }) {
    calls++;
    throw StateError('widget test must not fetch bootstrap pages');
  }
}

final class _OverviewHarness {
  const _OverviewHarness({
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

final class _DelayedEnqueueOutboxStore implements OutboxStore {
  const _DelayedEnqueueOutboxStore(
    this._delegate,
    this._enqueueDelay, {
    this._enqueueStarted,
  });

  final OutboxStore _delegate;
  final Future<void> _enqueueDelay;
  final Completer<void>? _enqueueStarted;

  @override
  Future<OutboxEntry> enqueue(FarmlyScopedMutation mutation) async {
    final enqueueStarted = _enqueueStarted;
    if (enqueueStarted != null && !enqueueStarted.isCompleted) {
      enqueueStarted.complete();
    }
    await _enqueueDelay;
    return _delegate.enqueue(mutation);
  }

  @override
  Future<List<OutboxEntry>> entries({
    required String accountId,
    required String organizationId,
  }) => _delegate.entries(accountId: accountId, organizationId: organizationId);

  @override
  Future<OutboxEntry?> find({
    required String accountId,
    required String organizationId,
    required String operationId,
  }) => _delegate.find(
    accountId: accountId,
    organizationId: organizationId,
    operationId: operationId,
  );

  @override
  Future<void> update(OutboxEntry entry) => _delegate.update(entry);
}

FarmlyOrganizationScope _scope({
  required String organizationId,
  required String organizationName,
  required String farmId,
  required String farmName,
  required String continuityEpoch,
  required int selectionEpoch,
  FarmlyOrganizationRole organizationRole = FarmlyOrganizationRole.owner,
  String? membershipId = _membershipId,
  FarmlyFarmGrantRole selectedFarmRole = FarmlyFarmGrantRole.owner,
  List<(String, String)> otherFarms = const [],
}) => FarmlyOrganizationScope(
  organization: FarmlyOrganization(
    id: organizationId,
    name: organizationName,
    status: FarmlyOrganizationStatus.active,
    policyVersion: '3',
    role: organizationRole,
    membershipVersion: 1,
    membershipId: membershipId,
  ),
  directory: FarmlyFarmDirectory(
    scopePolicyVersion: '3',
    continuityEpoch: continuityEpoch,
    farms: [
      FarmlyDirectoryFarm(
        id: farmId,
        name: farmName,
        status: FarmlyFarmStatus.active,
        grantRole: selectedFarmRole,
      ),
      for (final (id, name) in otherFarms)
        FarmlyDirectoryFarm(
          id: id,
          name: name,
          status: FarmlyFarmStatus.active,
          grantRole: FarmlyFarmGrantRole.manager,
        ),
    ],
  ),
  epoch: selectionEpoch,
  selectedFarmId: farmId,
);

FarmlyOrganizationScope get _scopeA => _scope(
  organizationId: _organizationAId,
  organizationName: 'Tổ chức A',
  farmId: _farmAId,
  farmName: 'Nông trại A',
  continuityEpoch: '37',
  selectionEpoch: 11,
  otherFarms: const [(_farmAOtherId, 'Nông trại A2')],
);

FarmlyOrganizationScope get _scopeB => _scope(
  organizationId: _organizationBId,
  organizationName: 'Tổ chức B',
  farmId: _farmBId,
  farmName: 'Nông trại B',
  continuityEpoch: '52',
  selectionEpoch: 18,
);

String _scopeKey(FarmlyOrganizationScope scope) =>
    '$_accountId|${scope.organization.id}|${scope.selectedFarmId}';

Future<void> _installEmptyBootstrap(
  InMemoryDomainStore domain,
  FarmlyOrganizationScope scope,
) => domain.installBootstrap(
  scopeKey: _scopeKey(scope),
  blocks: const [BootstrapBlock(entity: 'zone', records: [])],
  cursor: SyncCursorState(
    cursor: 'cursor-${scope.directory.continuityEpoch}',
    highWatermark: '0',
    continuityEpoch: scope.directory.continuityEpoch,
    scopePolicyVersion: scope.directory.scopePolicyVersion,
  ),
);

Future<void> _installCropPlotSnapshot(
  InMemoryDomainStore domain,
  FarmlyOrganizationScope scope, {
  required String zoneId,
  required String zoneName,
  int zoneVersion = 1,
  List<Map<String, Object?>> cropSpecies = const [],
  List<Map<String, Object?>> plantings = const [],
  List<Map<String, Object?>> plantingEvents = const [],
  List<Map<String, Object?>> harvests = const [],
  List<Map<String, Object?>> correctionProposals = const [],
  List<Map<String, Object?>> moistureReadings = const [],
  List<Map<String, Object?>> taskTemplates = const [],
  List<Map<String, Object?>> taskOccurrences = const [],
  String? timezone,
}) => domain.installBootstrap(
  scopeKey: _scopeKey(scope),
  blocks: [
    if (timezone != null)
      BootstrapBlock(
        entity: 'farm',
        records: [
          {
            'farmId': scope.selectedFarmId,
            'name': 'Nông trại kiểm thử',
            'timezone': timezone,
            'status': 'active',
            'version': 1,
          },
        ],
      ),
    BootstrapBlock(
      entity: 'zone',
      records: [
        {
          'id': zoneId,
          'version': zoneVersion,
          'type': 'crop_plot',
          'name': zoneName,
          'geometry': {
            'points': [
              {'x': '0.1', 'y': '0.1'},
              {'x': '0.8', 'y': '0.1'},
              {'x': '0.8', 'y': '0.8'},
            ],
          },
          'status': 'active',
        },
      ],
    ),
    BootstrapBlock(entity: 'cropSpecies', records: cropSpecies),
    BootstrapBlock(entity: 'planting', records: plantings),
    BootstrapBlock(entity: 'plantingEvent', records: plantingEvents),
    BootstrapBlock(entity: 'harvest', records: harvests),
    BootstrapBlock(entity: 'correctionProposal', records: correctionProposals),
    BootstrapBlock(entity: 'moistureReading', records: moistureReadings),
    BootstrapBlock(entity: 'taskTemplate', records: taskTemplates),
    BootstrapBlock(entity: 'taskOccurrence', records: taskOccurrences),
  ],
  cursor: SyncCursorState(
    cursor: 'cursor-${scope.directory.continuityEpoch}',
    highWatermark: '1',
    continuityEpoch: scope.directory.continuityEpoch,
    scopePolicyVersion: scope.directory.scopePolicyVersion,
  ),
);

Future<void> _expectMalformedTaskTemplateSnapshot(
  WidgetTester tester,
  Map<String, Object?> taskTemplate,
) async {
  final domain = InMemoryDomainStore();
  await _installCropPlotSnapshot(
    domain,
    _scopeA,
    zoneId: _cropPlotZoneAId,
    zoneName: 'Luống A',
    taskTemplates: [taskTemplate],
  );
  await _pumpOverview(tester, scope: _scopeA, domain: domain);
  final overview = find.byType(FarmOverviewScreen);
  expect(
    find.text(AppLocalizations.of(tester.element(overview)).loadErrorTitle),
    findsOneWidget,
  );
  expect(tester.takeException(), isNull);
}

FarmlyOrganizationScope get _plantingManagerScope => _scope(
  organizationId: _organizationAId,
  organizationName: 'Tổ chức A',
  farmId: _farmAId,
  farmName: 'Nông trại A',
  continuityEpoch: '37',
  selectionEpoch: 11,
  organizationRole: FarmlyOrganizationRole.member,
  selectedFarmRole: FarmlyFarmGrantRole.manager,
);

Future<void> _installPlantingUpdateFixture(
  InMemoryDomainStore domain,
  FarmlyOrganizationScope scope, {
  int version = 5,
  String status = 'active',
  String sowingDate = '2026-09-10',
  String expectedHarvestDate = '2026-10-30',
  String areaM2 = '80.00',
  List<Map<String, Object?>> plantingEvents = const [],
  List<Map<String, Object?>> harvests = const [],
}) => _installCropPlotSnapshot(
  domain,
  scope,
  zoneId: _cropPlotZoneAId,
  zoneName: 'Luống A',
  cropSpecies: const [
    {
      'id': _cropSpeciesAId,
      'version': 2,
      'name': 'Cà chua bi',
      'harvestUnit': 'kg',
      'status': 'active',
    },
  ],
  plantings: [
    {
      'id': _plantingAId,
      'version': version,
      'cropSpeciesId': _cropSpeciesAId,
      'plotId': _cropPlotZoneAId,
      'status': status,
      'sowingDate': sowingDate,
      'expectedHarvestDate': expectedHarvestDate,
      'areaM2': areaM2,
    },
  ],
  plantingEvents: plantingEvents,
  harvests: harvests,
);

Future<OutboxEntry> _queuePlantingUpdate(
  InMemoryOutboxStore outbox,
  FarmlyOrganizationScope scope, {
  required String operationId,
  required int baseVersion,
  String plantingId = _plantingAId,
  String? status,
  String? sowingDate,
  String? expectedHarvestDate,
  String? areaM2,
}) => outbox.enqueue(
  FarmlyScopedMutation(
    scope: FarmlyMutationScope.farm(
      accountId: _accountId,
      organizationId: scope.organization.id,
      farmId: scope.selectedFarmId!,
      continuityEpoch: scope.directory.continuityEpoch,
    ),
    intent: FarmlyUpdatePlantingIntent(
      operationId: operationId,
      continuityEpoch: scope.directory.continuityEpoch,
      resourceId: plantingId,
      baseVersion: baseVersion,
      status: status,
      sowingDate: sowingDate,
      expectedHarvestDate: expectedHarvestDate,
      areaM2: areaM2,
    ),
  ),
);

Future<OutboxEntry> _queuePlantingArchive(
  InMemoryOutboxStore outbox,
  FarmlyOrganizationScope scope, {
  required String operationId,
  required int baseVersion,
  String plantingId = _plantingAId,
}) => outbox.enqueue(
  FarmlyScopedMutation(
    scope: FarmlyMutationScope.farm(
      accountId: _accountId,
      organizationId: scope.organization.id,
      farmId: scope.selectedFarmId!,
      continuityEpoch: scope.directory.continuityEpoch,
    ),
    intent: FarmlyArchivePlantingIntent(
      operationId: operationId,
      continuityEpoch: scope.directory.continuityEpoch,
      resourceId: plantingId,
      baseVersion: baseVersion,
    ),
  ),
);

Future<OutboxEntry> _queueCropSpeciesArchive(
  InMemoryOutboxStore outbox,
  FarmlyOrganizationScope scope, {
  required String operationId,
  required int baseVersion,
  String speciesId = _cropSpeciesAId,
}) => outbox.enqueue(
  FarmlyScopedMutation(
    scope: FarmlyMutationScope.farm(
      accountId: _accountId,
      organizationId: scope.organization.id,
      farmId: scope.selectedFarmId!,
      continuityEpoch: scope.directory.continuityEpoch,
    ),
    intent: FarmlyArchiveCropSpeciesIntent(
      operationId: operationId,
      continuityEpoch: scope.directory.continuityEpoch,
      resourceId: speciesId,
      baseVersion: baseVersion,
    ),
  ),
);

Future<void> _installHarvestActionFixture(
  InMemoryDomainStore domain,
  FarmlyOrganizationScope scope, {
  String harvestStatus = 'active',
  int harvestVersion = 7,
  List<Map<String, Object?>> correctionProposals = const [],
  bool includeHarvest = true,
}) => _installCropPlotSnapshot(
  domain,
  scope,
  zoneId: _cropPlotZoneAId,
  zoneName: 'Luống thu hoạch A',
  cropSpecies: const [
    {
      'id': _cropSpeciesAId,
      'version': 1,
      'name': 'Cà chua bi',
      'harvestUnit': 'kg',
      'status': 'active',
    },
  ],
  plantings: const [
    {
      'id': _plantingAId,
      'version': 2,
      'cropSpeciesId': _cropSpeciesAId,
      'plotId': _cropPlotZoneAId,
      'status': 'active',
      'sowingDate': '2026-09-10',
    },
  ],
  harvests: includeHarvest
      ? [
          {
            'id': _harvestAId,
            'version': harvestVersion,
            'plantingId': _plantingAId,
            'quantityKg': '5.25',
            'harvestDate': '2026-10-02',
            'status': harvestStatus,
          },
        ]
      : const [],
  correctionProposals: correctionProposals,
);

Future<OutboxEntry> _queueLiveHarvestCreate(
  InMemoryOutboxStore outbox,
  FarmlyOrganizationScope scope, {
  OutboxEntryStatus status = OutboxEntryStatus.pending,
}) async {
  final entry = await outbox.enqueue(
    FarmlyScopedMutation(
      scope: FarmlyMutationScope.farm(
        accountId: _accountId,
        organizationId: scope.organization.id,
        farmId: scope.selectedFarmId!,
        continuityEpoch: scope.directory.continuityEpoch,
      ),
      intent: FarmlyCreateHarvestIntent(
        operationId: _harvestOperationId,
        continuityEpoch: scope.directory.continuityEpoch,
        resourceId: _harvestAId,
        plantingId: _plantingAId,
        quantityKg: FarmlyDecimal.parse('5.25'),
        harvestDate: '2026-10-02',
      ),
    ),
  );
  if (status == OutboxEntryStatus.pending) return entry;
  final updated = entry.copyWith(status: status);
  await outbox.update(updated);
  return updated;
}

Future<OutboxEntry> _queueAppliedHarvestCorrection(
  InMemoryOutboxStore outbox,
  FarmlyOrganizationScope scope,
) async {
  final entry = await outbox.enqueue(
    FarmlyScopedMutation(
      scope: FarmlyMutationScope.farm(
        accountId: _accountId,
        organizationId: scope.organization.id,
        farmId: scope.selectedFarmId!,
        continuityEpoch: scope.directory.continuityEpoch,
      ),
      intent: FarmlyApplyHarvestCorrectionIntent(
        operationId: _appliedHarvestCorrectionOperationId,
        continuityEpoch: scope.directory.continuityEpoch,
        resourceId: _harvestAId,
        baseVersion: 7,
        proposedQuantityKg: FarmlyDecimal.parse('6.25'),
      ),
    ),
  );
  final applied = entry.copyWith(
    status: OutboxEntryStatus.applied,
    appliedRevision: '2',
  );
  await outbox.update(applied);
  return applied;
}

Future<void> _installWaterZoneSnapshot(
  InMemoryDomainStore domain,
  FarmlyOrganizationScope scope, {
  int zoneVersion = 1,
  List<Map<String, Object?>> tanks = const [],
  List<Map<String, Object?>> readings = const [],
  List<Map<String, Object?>> usages = const [],
}) => domain.installBootstrap(
  scopeKey: _scopeKey(scope),
  blocks: [
    BootstrapBlock(
      entity: 'zone',
      records: [
        {
          'id': _waterZoneAId,
          'version': zoneVersion,
          'type': 'water',
          'name': 'Bồn nước A',
          'geometry': {
            'points': [
              {'x': '0.1', 'y': '0.1'},
              {'x': '0.8', 'y': '0.1'},
              {'x': '0.8', 'y': '0.8'},
            ],
          },
          'status': 'active',
        },
      ],
    ),
    BootstrapBlock(entity: 'waterTank', records: tanks),
    BootstrapBlock(entity: 'waterReading', records: readings),
    BootstrapBlock(entity: 'waterUsage', records: usages),
  ],
  cursor: SyncCursorState(
    cursor: 'cursor-${scope.directory.continuityEpoch}',
    highWatermark: '1',
    continuityEpoch: scope.directory.continuityEpoch,
    scopePolicyVersion: scope.directory.scopePolicyVersion,
  ),
);

FarmlyOrganizationScope get _waterTankManagerScope => _scope(
  organizationId: _organizationAId,
  organizationName: 'Tổ chức A',
  farmId: _farmAId,
  farmName: 'Nông trại A',
  continuityEpoch: '37',
  selectionEpoch: 11,
  organizationRole: FarmlyOrganizationRole.member,
  selectedFarmRole: FarmlyFarmGrantRole.manager,
);

Map<String, Object?> _waterTankRecord({
  String id = _waterTankAId,
  int version = 4,
  String name = 'Bồn chứa A',
  String status = 'active',
}) => {
  'id': id,
  'version': version,
  'name': name,
  'zoneId': _waterZoneAId,
  'capacityLitres': '1000',
  'storedLitres': '800',
  'status': status,
};

Future<OutboxEntry> _queueWaterTankRename(
  InMemoryOutboxStore outbox,
  FarmlyOrganizationScope scope, {
  required String operationId,
  required String name,
  int baseVersion = 4,
  String tankId = _waterTankAId,
}) => outbox.enqueue(
  FarmlyScopedMutation(
    scope: FarmlyMutationScope.farm(
      accountId: _accountId,
      organizationId: scope.organization.id,
      farmId: scope.selectedFarmId!,
      continuityEpoch: scope.directory.continuityEpoch,
    ),
    intent: FarmlyUpdateWaterTankNameIntent(
      operationId: operationId,
      continuityEpoch: scope.directory.continuityEpoch,
      resourceId: tankId,
      baseVersion: baseVersion,
      name: name,
    ),
  ),
);

Future<OutboxEntry> _queueZoneRename(
  InMemoryOutboxStore outbox,
  FarmlyOrganizationScope scope, {
  required String operationId,
  required String name,
  int baseVersion = 1,
  String zoneId = _cropPlotZoneAId,
}) => outbox.enqueue(
  FarmlyScopedMutation(
    scope: FarmlyMutationScope.farm(
      accountId: _accountId,
      organizationId: scope.organization.id,
      farmId: scope.selectedFarmId!,
      continuityEpoch: scope.directory.continuityEpoch,
    ),
    intent: FarmlyUpdateZoneNameIntent(
      operationId: operationId,
      continuityEpoch: scope.directory.continuityEpoch,
      resourceId: zoneId,
      baseVersion: baseVersion,
      name: name,
    ),
  ),
);

Future<_OverviewHarness> _pumpOverview(
  WidgetTester tester, {
  required FarmlyOrganizationScope? scope,
  InMemoryDomainStore? domain,
  InMemoryOutboxStore? outbox,
  DateTime Function()? utcNow,
  Future<void>? enqueueDelay,
  Completer<void>? enqueueStarted,
  Size viewportSize = const Size(390, 844),
  double textScaleFactor = 1,
  int overviewCopies = 1,
}) async {
  final localDomain = domain ?? InMemoryDomainStore();
  final localOutbox = outbox ?? InMemoryOutboxStore();
  final engineOutbox = enqueueDelay == null
      ? localOutbox
      : _DelayedEnqueueOutboxStore(
          localOutbox,
          enqueueDelay,
          enqueueStarted: enqueueStarted,
        );
  final transport = _OfflineOnlyTransport();
  final engine = FarmlySyncEngine(
    outbox: engineOutbox,
    transport: transport,
    domain: localDomain,
  );
  late final _MutableSelectedScopeController scopeController;
  final container = ProviderContainer(
    overrides: [
      farmlyAuthSessionProvider.overrideWith(_SignedInSessionController.new),
      selectedOrganizationScopeProvider.overrideWith(() {
        scopeController = _MutableSelectedScopeController(scope);
        return scopeController;
      }),
      syncEngineProvider.overrideWith((ref) async => engine),
      if (utcNow != null) farmlyUtcNowProvider.overrideWith((ref) => utcNow),
    ],
  );
  container.read(selectedOrganizationScopeProvider);
  addTearDown(container.dispose);
  final Widget home = overviewCopies == 1
      ? const FarmOverviewScreen()
      : Row(
          children: List.generate(
            overviewCopies,
            (_) => Expanded(
              child: Navigator(
                onGenerateRoute: (settings) => MaterialPageRoute<void>(
                  settings: settings,
                  builder: (_) => const FarmOverviewScreen(),
                ),
              ),
            ),
          ),
        );
  tester.view.physicalSize = viewportSize;
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
          data: MediaQuery.of(context).copyWith(
            disableAnimations: true,
            textScaler: TextScaler.linear(textScaleFactor),
          ),
          child: child!,
        ),
        home: home,
      ),
    ),
  );
  await tester.pumpAndSettle();
  return _OverviewHarness(
    container: container,
    domain: localDomain,
    outbox: localOutbox,
    transport: transport,
    scopeController: scopeController,
  );
}

Future<void> _openLiveZoneForm(WidgetTester tester) async {
  await tester.tap(find.byKey(_liveZoneCreateKey));
  await tester.pumpAndSettle();
  expect(find.byKey(_liveZoneNameKey), findsOneWidget);
  expect(find.byKey(_liveZoneSaveKey), findsOneWidget);
}

Future<void> _submitLiveZone(WidgetTester tester, String name) async {
  await tester.enterText(find.byKey(_liveZoneNameKey), name);
  await tester.tap(find.byKey(_liveZoneSaveKey));
  await tester.pumpAndSettle();
}

Future<void> _openLiveCropPlotDetails(
  WidgetTester tester, {
  required String zoneId,
  int overviewIndex = 0,
}) async {
  await tester.tap(
    find.byKey(ValueKey('live-zone-row-$zoneId')).at(overviewIndex),
  );
  await tester.pumpAndSettle();
  expect(find.byKey(_liveZoneDetailsKey), findsNWidgets(overviewIndex + 1));
}

Future<void> _openLiveHarvestActions(WidgetTester tester) async {
  await _openLiveCropPlotDetails(tester, zoneId: _cropPlotZoneAId);
  final harvestRow = find.byKey(
    const ValueKey('live-harvest-row-$_harvestAId'),
  );
  expect(harvestRow, findsOneWidget);
  await tester.ensureVisible(harvestRow);
  await tester.tap(harvestRow);
  await tester.pumpAndSettle();
}

Future<void> _openLiveWaterDetails(WidgetTester tester) async {
  await tester.tap(find.byKey(const ValueKey('live-zone-row-$_waterZoneAId')));
  await tester.pumpAndSettle();
  expect(find.byKey(_liveZoneDetailsKey), findsOneWidget);
}

Future<void> _createLiveCropSpecies(
  WidgetTester tester, {
  required String name,
}) async {
  await tester.tap(find.byKey(_liveCropSpeciesCreateKey));
  await tester.pumpAndSettle();
  await tester.enterText(find.byKey(_liveCropSpeciesNameKey), name);
  await tester.tap(find.byKey(_liveCropSpeciesUnitKey));
  await tester.pumpAndSettle();
  await tester.tap(find.text('kg').last);
  await tester.pumpAndSettle();
  await tester.tap(find.byKey(_liveCropSpeciesSaveKey));
  await tester.pumpAndSettle();
}

Future<void> _createLivePlanting(
  WidgetTester tester, {
  required String speciesName,
  required String sowingDate,
  required String expectedHarvestDate,
  required String areaM2,
}) async {
  await tester.tap(find.byKey(_livePlantingCreateKey));
  await tester.pumpAndSettle();
  await tester.tap(find.byKey(_livePlantingSpeciesKey));
  await tester.pumpAndSettle();
  await tester.tap(find.text(speciesName).last);
  await tester.pumpAndSettle();
  await _selectCivilDate(
    tester,
    find.byKey(_livePlantingSowingDateKey),
    DateTime.parse(sowingDate),
  );
  await _selectCivilDate(
    tester,
    find.byKey(_livePlantingExpectedHarvestDateKey),
    DateTime.parse(expectedHarvestDate),
  );
  await tester.enterText(find.byKey(_livePlantingAreaKey), areaM2);
  await tester.tap(find.byKey(_livePlantingSaveKey));
  await tester.pumpAndSettle();
}

Future<void> _createLiveHarvest(
  WidgetTester tester, {
  required String plantingId,
  required String quantityKg,
  required String harvestDate,
}) async {
  final createButton = find.byKey(_liveHarvestCreateKey(plantingId));
  await tester.ensureVisible(createButton);
  await tester.tap(createButton);
  await tester.pumpAndSettle();
  await tester.enterText(find.byKey(_liveHarvestQuantityKey), quantityKg);
  await tester.enterText(find.byKey(_liveHarvestDateKey), harvestDate);
  await tester.tap(find.byKey(_liveHarvestSaveKey));
  await tester.pumpAndSettle();
}

Future<void> _selectCivilDate(
  WidgetTester tester,
  Finder field,
  DateTime date,
) async {
  await tester.tap(field);
  await tester.pumpAndSettle();
  final dialog = find.byType(DatePickerDialog);
  expect(dialog, findsOneWidget);
  final localizations = MaterialLocalizations.of(tester.element(dialog));
  await tester.tap(find.byTooltip(localizations.inputDateModeButtonLabel));
  await tester.pumpAndSettle();
  await tester.enterText(
    find.descendant(of: dialog, matching: find.byType(TextField)),
    localizations.formatCompactDate(date),
  );
  await tester.pumpAndSettle();
  await tester.tap(
    find.descendant(of: dialog, matching: find.byType(TextButton)).last,
  );
  await tester.pumpAndSettle();
}

void main() {
  testWidgets('active planting exposes its planting event action', (
    tester,
  ) async {
    final domain = InMemoryDomainStore();
    await _installCropPlotSnapshot(
      domain,
      _scopeA,
      zoneId: _cropPlotZoneAId,
      zoneName: 'Luống A',
      cropSpecies: const [
        {
          'id': _cropSpeciesAId,
          'version': 1,
          'name': 'Cà chua bi',
          'harvestUnit': 'kg',
          'status': 'active',
        },
      ],
      plantings: const [
        {
          'id': _plantingAId,
          'version': 1,
          'cropSpeciesId': _cropSpeciesAId,
          'plotId': _cropPlotZoneAId,
          'status': 'active',
          'sowingDate': '2026-10-12',
        },
      ],
    );
    await _pumpOverview(tester, scope: _scopeA, domain: domain);

    await _openLiveCropPlotDetails(tester, zoneId: _cropPlotZoneAId);

    final action = find.byKey(
      const ValueKey('live-planting-event-create-$_plantingAId'),
    );
    expect(action, findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('planting event action follows same-farm writer roles', (
    tester,
  ) async {
    FarmlyOrganizationScope roleScope({
      required FarmlyOrganizationRole organizationRole,
      required FarmlyFarmGrantRole farmRole,
      required int selectionEpoch,
    }) => _scope(
      organizationId: _organizationAId,
      organizationName: 'Tổ chức A',
      farmId: _farmAId,
      farmName: 'Nông trại A',
      continuityEpoch: '37',
      selectionEpoch: selectionEpoch,
      organizationRole: organizationRole,
      selectedFarmRole: farmRole,
    );

    final cases = <(String, FarmlyOrganizationScope, bool)>[
      ('owner', _scopeA, true),
      (
        'admin',
        roleScope(
          organizationRole: FarmlyOrganizationRole.admin,
          farmRole: FarmlyFarmGrantRole.admin,
          selectionEpoch: 12,
        ),
        true,
      ),
      (
        'manager',
        roleScope(
          organizationRole: FarmlyOrganizationRole.member,
          farmRole: FarmlyFarmGrantRole.manager,
          selectionEpoch: 13,
        ),
        true,
      ),
      (
        'worker',
        roleScope(
          organizationRole: FarmlyOrganizationRole.member,
          farmRole: FarmlyFarmGrantRole.worker,
          selectionEpoch: 14,
        ),
        true,
      ),
      (
        'viewer with stale manager grant',
        roleScope(
          organizationRole: FarmlyOrganizationRole.viewer,
          farmRole: FarmlyFarmGrantRole.manager,
          selectionEpoch: 15,
        ),
        false,
      ),
    ];

    for (final (roleName, scope, canCreate) in cases) {
      final domain = InMemoryDomainStore();
      await _installCropPlotSnapshot(
        domain,
        scope,
        zoneId: _cropPlotZoneAId,
        zoneName: 'Luống A',
        cropSpecies: const [
          {
            'id': _cropSpeciesAId,
            'version': 1,
            'name': 'Cà chua bi',
            'harvestUnit': 'kg',
            'status': 'active',
          },
        ],
        plantings: const [
          {
            'id': _plantingAId,
            'version': 1,
            'cropSpeciesId': _cropSpeciesAId,
            'plotId': _cropPlotZoneAId,
            'status': 'active',
            'sowingDate': '2026-10-12',
          },
        ],
      );
      await _pumpOverview(tester, scope: scope, domain: domain);
      await _openLiveCropPlotDetails(tester, zoneId: _cropPlotZoneAId);

      expect(
        find.byKey(_livePlantingEventCreateKey(_plantingAId)),
        canCreate ? findsOneWidget : findsNothing,
        reason: 'event authoring must honor $roleName access',
      );
      Navigator.of(tester.element(find.byKey(_liveZoneDetailsKey))).pop();
      await tester.pumpAndSettle();
    }
    expect(tester.takeException(), isNull);
  });

  testWidgets('archived plantings do not expose event authoring', (
    tester,
  ) async {
    final domain = InMemoryDomainStore();
    await _installCropPlotSnapshot(
      domain,
      _scopeA,
      zoneId: _cropPlotZoneAId,
      zoneName: 'Luống A',
      cropSpecies: const [
        {
          'id': _cropSpeciesAId,
          'version': 1,
          'name': 'Cà chua bi',
          'harvestUnit': 'kg',
          'status': 'active',
        },
      ],
      plantings: const [
        {
          'id': _plantingAId,
          'version': 1,
          'cropSpeciesId': _cropSpeciesAId,
          'plotId': _cropPlotZoneAId,
          'status': 'archived',
          'sowingDate': '2026-10-12',
        },
      ],
    );
    await _pumpOverview(tester, scope: _scopeA, domain: domain);
    await _openLiveCropPlotDetails(tester, zoneId: _cropPlotZoneAId);

    expect(find.byKey(_livePlantingEventCreateKey(_plantingAId)), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets(
    'planting event saves offline with parent dependency and deduplicates projection',
    (tester) async {
      final workerScope = _scope(
        organizationId: _organizationAId,
        organizationName: 'Tổ chức A',
        farmId: _farmAId,
        farmName: 'Nông trại A',
        continuityEpoch: '37',
        selectionEpoch: 16,
        organizationRole: FarmlyOrganizationRole.member,
        selectedFarmRole: FarmlyFarmGrantRole.worker,
      );
      final domain = InMemoryDomainStore();
      await _installCropPlotSnapshot(
        domain,
        workerScope,
        zoneId: _cropPlotZoneAId,
        zoneName: 'Luống A',
        cropSpecies: const [
          {
            'id': _cropSpeciesAId,
            'version': 1,
            'name': 'Cà chua bi',
            'harvestUnit': 'kg',
            'status': 'active',
          },
        ],
      );
      final outbox = InMemoryOutboxStore();
      final planting = await outbox.enqueue(
        FarmlyScopedMutation(
          scope: FarmlyMutationScope.farm(
            accountId: _accountId,
            organizationId: _organizationAId,
            farmId: _farmAId,
            continuityEpoch: '37',
          ),
          intent: FarmlyCreatePlantingIntent(
            operationId: _plantingCreateOperationId,
            continuityEpoch: '37',
            resourceId: _plantingAId,
            cropSpeciesId: _cropSpeciesAId,
            plotId: _cropPlotZoneAId,
            sowingDate: '2026-10-12',
            status: 'active',
          ),
        ),
      );
      final harness = await _pumpOverview(
        tester,
        scope: workerScope,
        domain: domain,
        outbox: outbox,
      );

      await _openLiveCropPlotDetails(tester, zoneId: _cropPlotZoneAId);
      await tester.ensureVisible(
        find.byKey(_livePlantingEventCreateKey(_plantingAId)),
      );
      await tester.tap(find.byKey(_livePlantingEventCreateKey(_plantingAId)));
      await tester.pumpAndSettle();
      await tester.enterText(find.byKey(_livePlantingEventTypeKey), 'scouting');
      await tester.enterText(
        find.byKey(_livePlantingEventNoteKey),
        'Kiểm tra sâu bệnh',
      );
      await _selectCivilDate(
        tester,
        find.byKey(_livePlantingEventDateKey),
        DateTime(2026, 10, 18),
      );
      await tester.tap(find.byKey(_livePlantingEventSaveKey));
      await tester.pumpAndSettle();

      expect(find.text(_savedPendingCopy), findsOneWidget);
      final entries = await harness.outbox.entries(
        accountId: _accountId,
        organizationId: _organizationAId,
      );
      expect(entries, hasLength(2));
      final event = entries.singleWhere(
        (entry) => entry.mutation.intent.type == 'plantingEvent.create',
      );
      expect(event.status, OutboxEntryStatus.pending);
      expect(event.mutation.scope.kind, FarmlyMutationScopeKind.farm);
      expect(event.mutation.scope.organizationId, _organizationAId);
      expect(event.mutation.scope.farmId, _farmAId);
      expect(event.mutation.scope.continuityEpoch, '37');
      expect(event.mutation.intent.continuityEpoch, '37');
      expect(event.mutation.intent.payload, {
        'plantingId': _plantingAId,
        'eventType': 'scouting',
        'note': 'Kiểm tra sâu bệnh',
        'occurredOn': '2026-10-18',
      });
      expect(event.mutation.intent.dependsOn, [planting.operationId]);
      final eventRow = find.byKey(
        _livePlantingEventRowKey(event.mutation.intent.resourceId),
      );
      expect(eventRow, findsOneWidget);
      expect(
        find.descendant(of: eventRow, matching: find.text('Chờ đồng bộ')),
        findsOneWidget,
      );
      expect(harness.transport.calls, 0);

      await harness.outbox.update(
        event.copyWith(status: OutboxEntryStatus.applied, appliedRevision: '2'),
      );
      await _installCropPlotSnapshot(
        domain,
        workerScope,
        zoneId: _cropPlotZoneAId,
        zoneName: 'Luống A',
        cropSpecies: const [
          {
            'id': _cropSpeciesAId,
            'version': 1,
            'name': 'Cà chua bi',
            'harvestUnit': 'kg',
            'status': 'active',
          },
        ],
        plantings: const [
          {
            'id': _plantingAId,
            'version': 1,
            'cropSpeciesId': _cropSpeciesAId,
            'plotId': _cropPlotZoneAId,
            'status': 'active',
            'sowingDate': '2026-10-12',
          },
        ],
        plantingEvents: [
          {
            'id': event.mutation.intent.resourceId,
            'version': 1,
            'plantingId': _plantingAId,
            'eventType': 'scouting',
            'note': 'Kiểm tra sâu bệnh',
            'occurredOn': '2026-10-18',
          },
        ],
      );
      harness.container.invalidate(syncStatusProvider);
      await tester.pumpAndSettle();

      expect(eventRow, findsOneWidget);
      expect(
        find.descendant(of: eventRow, matching: find.text('Chờ đồng bộ')),
        findsNothing,
      );
      expect(harness.transport.calls, 0);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets('farm change locks the open planting event form', (tester) async {
    final managerScope = _scope(
      organizationId: _organizationAId,
      organizationName: 'Tổ chức A',
      farmId: _farmAId,
      farmName: 'Nông trại A',
      continuityEpoch: '37',
      selectionEpoch: 17,
      organizationRole: FarmlyOrganizationRole.member,
      selectedFarmRole: FarmlyFarmGrantRole.manager,
    );
    final domain = InMemoryDomainStore();
    await _installCropPlotSnapshot(
      domain,
      managerScope,
      zoneId: _cropPlotZoneAId,
      zoneName: 'Luống A',
      cropSpecies: const [
        {
          'id': _cropSpeciesAId,
          'version': 1,
          'name': 'Cà chua bi',
          'harvestUnit': 'kg',
          'status': 'active',
        },
      ],
      plantings: const [
        {
          'id': _plantingAId,
          'version': 1,
          'cropSpeciesId': _cropSpeciesAId,
          'plotId': _cropPlotZoneAId,
          'status': 'active',
          'sowingDate': '2026-10-12',
        },
      ],
    );
    await _installEmptyBootstrap(domain, _scopeB);
    final harness = await _pumpOverview(
      tester,
      scope: managerScope,
      domain: domain,
    );

    await _openLiveCropPlotDetails(tester, zoneId: _cropPlotZoneAId);
    await tester.ensureVisible(
      find.byKey(_livePlantingEventCreateKey(_plantingAId)),
    );
    await tester.tap(find.byKey(_livePlantingEventCreateKey(_plantingAId)));
    await tester.pumpAndSettle();
    await tester.enterText(find.byKey(_livePlantingEventTypeKey), 'watering');
    harness.scopeController.replace(_scopeB);
    await tester.pumpAndSettle();

    expect(
      tester
          .widget<FilledButton>(find.byKey(_livePlantingEventSaveKey))
          .onPressed,
      isNull,
    );
    await tester.tap(find.byKey(_livePlantingEventSaveKey));
    await tester.pumpAndSettle();
    expect(
      await harness.outbox.entries(
        accountId: _accountId,
        organizationId: _organizationAId,
      ),
      isEmpty,
    );
    expect(
      await harness.outbox.entries(
        accountId: _accountId,
        organizationId: _organizationBId,
      ),
      isEmpty,
    );
    expect(harness.transport.calls, 0);
    expect(tester.takeException(), isNull);
  });

  testWidgets('failed planting parent keeps event creation fail-closed', (
    tester,
  ) async {
    final workerScope = _scope(
      organizationId: _organizationAId,
      organizationName: 'Tổ chức A',
      farmId: _farmAId,
      farmName: 'Nông trại A',
      continuityEpoch: '37',
      selectionEpoch: 18,
      organizationRole: FarmlyOrganizationRole.member,
      selectedFarmRole: FarmlyFarmGrantRole.worker,
    );
    final domain = InMemoryDomainStore();
    await _installCropPlotSnapshot(
      domain,
      workerScope,
      zoneId: _cropPlotZoneAId,
      zoneName: 'Luống A',
      cropSpecies: const [
        {
          'id': _cropSpeciesAId,
          'version': 1,
          'name': 'Cà chua bi',
          'harvestUnit': 'kg',
          'status': 'active',
        },
      ],
    );
    final outbox = InMemoryOutboxStore();
    final pendingPlanting = await outbox.enqueue(
      FarmlyScopedMutation(
        scope: FarmlyMutationScope.farm(
          accountId: _accountId,
          organizationId: _organizationAId,
          farmId: _farmAId,
          continuityEpoch: '37',
        ),
        intent: FarmlyCreatePlantingIntent(
          operationId: _plantingCreateOperationId,
          continuityEpoch: '37',
          resourceId: _plantingAId,
          cropSpeciesId: _cropSpeciesAId,
          plotId: _cropPlotZoneAId,
          sowingDate: '2026-10-12',
          status: 'active',
        ),
      ),
    );
    await outbox.update(
      pendingPlanting.copyWith(
        status: OutboxEntryStatus.blocked,
        lastFailureCode: 'DEPENDENCY_FAILED',
      ),
    );
    final harness = await _pumpOverview(
      tester,
      scope: workerScope,
      domain: domain,
      outbox: outbox,
    );

    await _openLiveCropPlotDetails(tester, zoneId: _cropPlotZoneAId);
    final action = find.byKey(_livePlantingEventCreateKey(_plantingAId));
    if (action.evaluate().isNotEmpty) {
      await tester.tap(action);
      await tester.pumpAndSettle();
    }

    expect(find.byKey(_livePlantingEventTypeKey), findsNothing);
    expect(
      await harness.outbox.entries(
        accountId: _accountId,
        organizationId: _organizationAId,
      ),
      hasLength(1),
    );
    expect(harness.transport.calls, 0);
    expect(tester.takeException(), isNull);
  });

  testWidgets('water zone exposes its live tank actions', (tester) async {
    final domain = InMemoryDomainStore();
    await _installWaterZoneSnapshot(
      domain,
      _scopeA,
      tanks: const [
        {
          'id': _waterTankAId,
          'version': 1,
          'name': 'Bồn chứa A',
          'zoneId': _waterZoneAId,
          'capacityLitres': '1000',
          'storedLitres': '800',
          'status': 'active',
        },
      ],
    );
    final harness = await _pumpOverview(tester, scope: _scopeA, domain: domain);

    await _openLiveWaterDetails(tester);

    expect(find.byKey(_liveWaterTankCreateKey), findsOneWidget);
    expect(find.byKey(_liveWaterReadingCreateKey), findsOneWidget);
    expect(find.byKey(_liveWaterUsageCreateKey), findsOneWidget);
    expect(find.text('Bồn chứa A'), findsOneWidget);
    expect(find.textContaining('800'), findsWidgets);
    expect(harness.transport.calls, 0);
    expect(tester.takeException(), isNull);
  });

  testWidgets('water tank, reading, and usage save offline with dependencies', (
    tester,
  ) async {
    final domain = InMemoryDomainStore();
    await _installEmptyBootstrap(domain, _scopeA);
    const zoneOperationId = '14141414-1414-4141-8141-141414141414';
    final outbox = InMemoryOutboxStore();
    await outbox.enqueue(
      FarmlyScopedMutation(
        scope: FarmlyMutationScope.farm(
          accountId: _accountId,
          organizationId: _organizationAId,
          farmId: _farmAId,
          continuityEpoch: '37',
        ),
        intent: FarmlyCreateZoneIntent(
          operationId: zoneOperationId,
          continuityEpoch: '37',
          resourceId: _waterZoneAId,
          name: 'Bồn nước A',
          type: 'water',
          geometry: const [
            {'x': '0.1', 'y': '0.1'},
            {'x': '0.8', 'y': '0.1'},
            {'x': '0.8', 'y': '0.8'},
          ],
        ),
      ),
    );
    final harness = await _pumpOverview(
      tester,
      scope: _scopeA,
      domain: domain,
      outbox: outbox,
    );

    await _openLiveWaterDetails(tester);
    await tester.ensureVisible(find.byKey(_liveWaterTankCreateKey));
    await tester.tap(find.byKey(_liveWaterTankCreateKey));
    await tester.pumpAndSettle();
    await tester.enterText(find.byKey(_liveWaterTankNameKey), 'Bồn chứa A');
    await tester.enterText(find.byKey(_liveWaterTankCapacityKey), '1000');
    await tester.tap(find.byKey(_liveWaterActionSaveKey));
    await tester.pumpAndSettle();

    var entries = await harness.outbox.entries(
      accountId: _accountId,
      organizationId: _organizationAId,
    );
    final tankEntry = entries.singleWhere(
      (entry) => entry.mutation.intent.type == 'waterTank.create',
    );
    final tankId = tankEntry.mutation.intent.resourceId;
    expect(tankEntry.status, OutboxEntryStatus.pending);
    expect(tankEntry.mutation.intent.type, 'waterTank.create');
    expect(tankEntry.mutation.intent.payload, {
      'name': 'Bồn chứa A',
      'zoneId': _waterZoneAId,
      'capacityLitres': '1000',
    });
    expect(tankEntry.mutation.intent.dependsOn, [zoneOperationId]);

    final readingKey = ValueKey('live-water-reading-create-$tankId');
    await tester.ensureVisible(find.byKey(readingKey));
    await tester.tap(find.byKey(readingKey));
    await tester.pumpAndSettle();
    await tester.enterText(find.byKey(_liveWaterReadingAmountKey), '800');
    await tester.tap(find.byKey(_liveWaterActionSaveKey));
    await tester.pumpAndSettle();

    entries = await harness.outbox.entries(
      accountId: _accountId,
      organizationId: _organizationAId,
    );
    final readingEntry = entries.singleWhere(
      (entry) => entry.mutation.intent.type == 'waterReading.create',
    );
    expect(readingEntry.mutation.intent.payload['tankId'], tankId);
    expect(readingEntry.mutation.intent.payload['storedLitres'], '800');
    expect(readingEntry.mutation.intent.payload['source'], 'manual');
    expect(readingEntry.mutation.intent.payload['measuredAt'], isA<String>());
    expect(readingEntry.mutation.intent.dependsOn, [tankEntry.operationId]);
    expect(
      find.byKey(
        ValueKey(
          'live-water-reading-row-${readingEntry.mutation.intent.resourceId}',
        ),
      ),
      findsOneWidget,
    );

    final usageKey = ValueKey('live-water-usage-create-$tankId');
    await tester.ensureVisible(find.byKey(usageKey));
    await tester.tap(find.byKey(usageKey));
    await tester.pumpAndSettle();
    await tester.enterText(find.byKey(_liveWaterUsageAmountKey), '12.5');
    await tester.enterText(find.byKey(_liveWaterUsageDateKey), '2026-10-19');
    await tester.enterText(find.byKey(_liveWaterUsageNoteKey), 'Tưới luống A');
    await tester.tap(find.byKey(_liveWaterActionSaveKey));
    await tester.pumpAndSettle();

    entries = await harness.outbox.entries(
      accountId: _accountId,
      organizationId: _organizationAId,
    );
    final usageEntry = entries.singleWhere(
      (entry) => entry.mutation.intent.type == 'waterUsage.create',
    );
    expect(usageEntry.mutation.intent.payload, {
      'tankId': tankId,
      'usageLitres': '12.5',
      'usageDate': '2026-10-19',
      'note': 'Tưới luống A',
    });
    expect(usageEntry.mutation.intent.dependsOn, [tankEntry.operationId]);
    expect(harness.transport.calls, 0);
    expect(tester.takeException(), isNull);
  });

  testWidgets('workers can record water facts but cannot create tanks', (
    tester,
  ) async {
    final workerScope = _scope(
      organizationId: _organizationAId,
      organizationName: 'Tổ chức A',
      farmId: _farmAId,
      farmName: 'Nông trại A',
      continuityEpoch: '37',
      selectionEpoch: 11,
      organizationRole: FarmlyOrganizationRole.member,
      selectedFarmRole: FarmlyFarmGrantRole.worker,
    );
    final domain = InMemoryDomainStore();
    await _installWaterZoneSnapshot(
      domain,
      workerScope,
      tanks: const [
        {
          'id': _waterTankAId,
          'version': 1,
          'name': 'Bồn chứa A',
          'zoneId': _waterZoneAId,
          'capacityLitres': '1000',
          'storedLitres': '500',
          'status': 'active',
        },
      ],
    );
    final harness = await _pumpOverview(
      tester,
      scope: workerScope,
      domain: domain,
    );

    await _openLiveWaterDetails(tester);

    expect(find.byKey(_liveWaterTankCreateKey), findsNothing);
    expect(find.byKey(_liveWaterReadingCreateKey), findsOneWidget);
    expect(find.byKey(_liveWaterUsageCreateKey), findsOneWidget);
    await tester.ensureVisible(find.byKey(_liveWaterReadingCreateKey));
    await tester.tap(find.byKey(_liveWaterReadingCreateKey));
    await tester.pumpAndSettle();
    await tester.enterText(find.byKey(_liveWaterReadingAmountKey), '450');
    await tester.tap(find.byKey(_liveWaterActionSaveKey));
    await tester.pumpAndSettle();

    final entries = await harness.outbox.entries(
      accountId: _accountId,
      organizationId: _organizationAId,
    );
    expect(entries.single.mutation.intent.type, 'waterReading.create');
    expect(harness.transport.calls, 0);
    expect(tester.takeException(), isNull);
  });

  testWidgets('organization viewers cannot record or manage water tanks', (
    tester,
  ) async {
    final viewerScope = _scope(
      organizationId: _organizationAId,
      organizationName: 'Tổ chức A',
      farmId: _farmAId,
      farmName: 'Nông trại A',
      continuityEpoch: '37',
      selectionEpoch: 11,
      organizationRole: FarmlyOrganizationRole.viewer,
      selectedFarmRole: FarmlyFarmGrantRole.manager,
    );
    final domain = InMemoryDomainStore();
    await _installWaterZoneSnapshot(
      domain,
      viewerScope,
      tanks: const [
        {
          'id': _waterTankAId,
          'version': 1,
          'name': 'Bồn chứa A',
          'zoneId': _waterZoneAId,
          'capacityLitres': '1000',
          'storedLitres': '500',
          'status': 'active',
        },
      ],
    );
    final harness = await _pumpOverview(
      tester,
      scope: viewerScope,
      domain: domain,
    );

    await _openLiveWaterDetails(tester);

    expect(find.byKey(_liveWaterTankCreateKey), findsNothing);
    expect(find.byKey(_liveWaterReadingCreateKey), findsNothing);
    expect(find.byKey(_liveWaterUsageCreateKey), findsNothing);
    expect(harness.transport.calls, 0);
    expect(tester.takeException(), isNull);
  });

  testWidgets('farm change locks an open water-use form', (tester) async {
    final domain = InMemoryDomainStore();
    await _installWaterZoneSnapshot(
      domain,
      _scopeA,
      tanks: const [
        {
          'id': _waterTankAId,
          'version': 1,
          'name': 'Bồn chứa A',
          'zoneId': _waterZoneAId,
          'capacityLitres': '1000',
          'storedLitres': '500',
          'status': 'active',
        },
      ],
    );
    await _installEmptyBootstrap(domain, _scopeB);
    final harness = await _pumpOverview(tester, scope: _scopeA, domain: domain);

    await _openLiveWaterDetails(tester);
    await tester.tap(find.byKey(_liveWaterUsageCreateKey));
    await tester.pumpAndSettle();
    await tester.enterText(find.byKey(_liveWaterUsageAmountKey), '12.5');
    await tester.enterText(find.byKey(_liveWaterUsageDateKey), '2026-10-19');
    harness.scopeController.replace(_scopeB);
    await tester.pumpAndSettle();

    expect(
      tester
          .widget<FilledButton>(find.byKey(_liveWaterActionSaveKey))
          .onPressed,
      isNull,
    );
    expect(
      await harness.outbox.entries(
        accountId: _accountId,
        organizationId: _organizationAId,
      ),
      isEmpty,
    );
    expect(harness.transport.calls, 0);
    expect(tester.takeException(), isNull);
  });

  testWidgets('cold live farm is not presented as an empty farm', (
    tester,
  ) async {
    final harness = await _pumpOverview(tester, scope: _scopeA);

    expect(await harness.domain.cursorFor(_scopeKey(_scopeA)), isNull);
    expect(find.byKey(_liveFarmNoCacheKey), findsOneWidget);
    expect(find.text('Chưa tải dữ liệu nông trại'), findsOneWidget);
    expect(find.text('Chưa có vùng nào'), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets('live snapshot only shows zones from the selected farm', (
    tester,
  ) async {
    final domain = InMemoryDomainStore();
    Future<void> installZone(
      FarmlyOrganizationScope scope,
      String id,
      String name,
    ) => domain.installBootstrap(
      scopeKey: _scopeKey(scope),
      blocks: [
        BootstrapBlock(
          entity: 'zone',
          records: [
            {
              'id': id,
              'version': 1,
              'type': 'crop_plot',
              'name': name,
              'geometry': {
                'points': [
                  {'x': '0.1', 'y': '0.1'},
                  {'x': '0.8', 'y': '0.1'},
                  {'x': '0.8', 'y': '0.8'},
                ],
              },
              'status': 'active',
            },
          ],
        ),
      ],
      cursor: SyncCursorState(
        cursor: 'cursor-${scope.directory.continuityEpoch}',
        highWatermark: '1',
        continuityEpoch: scope.directory.continuityEpoch,
        scopePolicyVersion: scope.directory.scopePolicyVersion,
      ),
    );

    await installZone(
      _scopeA,
      '77777777-7777-4777-8777-777777777777',
      'Luống A',
    );
    await installZone(
      _scopeB,
      '88888888-8888-4888-8888-888888888888',
      'Luống B',
    );
    await _pumpOverview(tester, scope: _scopeA, domain: domain);

    expect(find.text('Luống A'), findsOneWidget);
    expect(find.text('Luống B'), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets('tapping a live zone opens its live details', (tester) async {
    const zoneId = '77777777-7777-4777-8777-777777777777';
    final domain = InMemoryDomainStore();
    await domain.installBootstrap(
      scopeKey: _scopeKey(_scopeA),
      blocks: const [
        BootstrapBlock(
          entity: 'zone',
          records: [
            {
              'id': zoneId,
              'version': 2,
              'type': 'crop_plot',
              'name': 'Luống A',
              'geometry': {
                'points': [
                  {'x': '0.1', 'y': '0.1'},
                  {'x': '0.8', 'y': '0.1'},
                  {'x': '0.8', 'y': '0.8'},
                ],
              },
              'status': 'active',
            },
          ],
        ),
      ],
      cursor: const SyncCursorState(
        cursor: 'cursor-37',
        highWatermark: '1',
        continuityEpoch: '37',
        scopePolicyVersion: '3',
      ),
    );
    await _pumpOverview(tester, scope: _scopeA, domain: domain);

    await tester.tap(find.byKey(const ValueKey('live-zone-row-$zoneId')));
    await tester.pumpAndSettle();

    expect(find.byKey(_liveZoneDetailsKey), findsOneWidget);
    expect(find.text('Chi tiết vùng'), findsOneWidget);
    expect(find.text('Luống A'), findsWidgets);
    expect(
      find.descendant(
        of: find.byKey(_liveZoneDetailsKey),
        matching: find.text('Trồng trọt'),
      ),
      findsOneWidget,
    );
    expect(tester.takeException(), isNull);
  });

  testWidgets('demo preview zone creation never enters the live outbox', (
    tester,
  ) async {
    final harness = await _pumpOverview(tester, scope: null);

    await tester.tap(find.bySemanticsLabel('Tạo vùng mới'));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField).last, 'Luống demo');
    await tester.tap(find.text('Lưu trên thiết bị'));
    await tester.pumpAndSettle();

    expect(
      harness.container
          .read(demoDataProvider)
          .syncItems
          .any((item) => item.localSummary == 'Tạo vùng Luống demo'),
      isTrue,
    );
    expect(
      await harness.outbox.entries(
        accountId: _accountId,
        organizationId: _organizationAId,
      ),
      isEmpty,
    );
    expect(tester.takeException(), isNull);
  });

  testWidgets('switching scope before save cannot enqueue into either scope', (
    tester,
  ) async {
    final domain = InMemoryDomainStore();
    await _installEmptyBootstrap(domain, _scopeA);
    await _installEmptyBootstrap(domain, _scopeB);
    final harness = await _pumpOverview(tester, scope: _scopeA, domain: domain);
    await _openLiveZoneForm(tester);
    await tester.enterText(find.byKey(_liveZoneNameKey), 'Không được lưu');

    harness.scopeController.replace(_scopeB);
    await tester.pumpAndSettle();
    if (find.byKey(_liveZoneSaveKey).evaluate().isNotEmpty) {
      await tester.tap(find.byKey(_liveZoneSaveKey));
      await tester.pumpAndSettle();
    }

    expect(
      await harness.outbox.entries(
        accountId: _accountId,
        organizationId: _organizationAId,
      ),
      isEmpty,
    );
    expect(
      await harness.outbox.entries(
        accountId: _accountId,
        organizationId: _organizationBId,
      ),
      isEmpty,
    );
    expect(tester.takeException(), isNull);
  });

  testWidgets(
    'create stays isolated to the selected farm and current organization epoch',
    (tester) async {
      final domain = InMemoryDomainStore();
      await _installEmptyBootstrap(domain, _scopeA);
      await _installEmptyBootstrap(domain, _scopeB);
      final harness = await _pumpOverview(
        tester,
        scope: _scopeA,
        domain: domain,
      );

      await _openLiveZoneForm(tester);
      await _submitLiveZone(tester, 'Luống A');
      expect(find.text(_savedPendingCopy), findsOneWidget);
      expect(find.text('Luống A'), findsOneWidget);
      expect(find.text('Chờ đồng bộ'), findsOneWidget);

      final organizationAEntries = await harness.outbox.entries(
        accountId: _accountId,
        organizationId: _organizationAId,
      );
      expect(organizationAEntries, hasLength(1));
      final zoneA = organizationAEntries.single;
      expect(zoneA.status, OutboxEntryStatus.pending);
      expect(zoneA.mutation.intent.type, 'zone.create');
      expect(zoneA.mutation.scope.kind, FarmlyMutationScopeKind.farm);
      expect(zoneA.mutation.scope.organizationId, _organizationAId);
      expect(zoneA.mutation.scope.farmId, _farmAId);
      expect(zoneA.mutation.scope.continuityEpoch, '37');
      expect(zoneA.mutation.intent.continuityEpoch, '37');
      expect(zoneA.mutation.intent.payload['name'], 'Luống A');
      expect(
        zoneA.mutation.intent.payload['geometry'],
        isA<Map<String, Object?>>(),
      );
      expect(
        organizationAEntries.where(
          (entry) => entry.mutation.scope.farmId == _farmAOtherId,
        ),
        isEmpty,
      );
      expect(
        await harness.outbox.entries(
          accountId: _accountId,
          organizationId: _organizationBId,
        ),
        isEmpty,
      );
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets('a worker without manager grant cannot create a zone', (
    tester,
  ) async {
    final viewerScope = _scope(
      organizationId: _organizationAId,
      organizationName: 'Tổ chức A',
      farmId: _farmAId,
      farmName: 'Nông trại A',
      continuityEpoch: '37',
      selectionEpoch: 11,
      organizationRole: FarmlyOrganizationRole.member,
      selectedFarmRole: FarmlyFarmGrantRole.worker,
    );
    final domain = InMemoryDomainStore();
    await _installEmptyBootstrap(domain, viewerScope);
    final harness = await _pumpOverview(
      tester,
      scope: viewerScope,
      domain: domain,
    );

    expect(find.byKey(_liveZoneCreateKey), findsNothing);
    expect(
      find.text('Bạn chỉ có quyền xem các vùng trong nông trại này.'),
      findsOneWidget,
    );
    expect(
      await harness.outbox.entries(
        accountId: _accountId,
        organizationId: _organizationAId,
      ),
      isEmpty,
    );
    expect(tester.takeException(), isNull);
  });

  testWidgets(
    'manager can create weekly task template offline with pending zone dependency',
    (tester) async {
      final managerScope = _scope(
        organizationId: _organizationAId,
        organizationName: 'Tổ chức A',
        farmId: _farmAId,
        farmName: 'Nông trại A',
        continuityEpoch: '37',
        selectionEpoch: 11,
        organizationRole: FarmlyOrganizationRole.member,
        selectedFarmRole: FarmlyFarmGrantRole.manager,
        otherFarms: const [(_farmAOtherId, 'Nông trại A2')],
      );
      final domain = InMemoryDomainStore();
      await _installEmptyBootstrap(domain, managerScope);
      final harness = await _pumpOverview(
        tester,
        scope: managerScope,
        domain: domain,
      );

      await _openLiveZoneForm(tester);
      await _submitLiveZone(tester, 'Khu chăm sóc');
      final zoneEntries = await harness.outbox.entries(
        accountId: _accountId,
        organizationId: _organizationAId,
      );
      final zoneEntry = zoneEntries.singleWhere(
        (entry) => entry.mutation.intent.type == 'zone.create',
      );
      final zoneId = zoneEntry.mutation.intent.resourceId;
      await _openLiveCropPlotDetails(tester, zoneId: zoneId);

      final createButton = find.byKey(
        ValueKey('live-task-template-create-$zoneId'),
      );
      expect(createButton, findsOneWidget);
      await tester.ensureVisible(createButton);
      await tester.tap(createButton);
      await tester.pumpAndSettle();
      expect(find.byKey(_liveTaskTemplateTitleKey), findsOneWidget);

      await tester.enterText(
        find.byKey(_liveTaskTemplateTitleKey),
        'Cho bò ăn cỏ',
      );
      await tester.tap(find.byKey(_liveTaskTemplateKindKey));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Cho ăn').last);
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(_liveTaskTemplateFrequencyKey));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Hằng tuần').last);
      await tester.pumpAndSettle();
      await tester.ensureVisible(find.byKey(_liveTaskTemplateSaveKey));
      await tester.tap(find.byKey(_liveTaskTemplateSaveKey));
      await tester.pumpAndSettle();
      expect(find.text('Chọn ít nhất một ngày trong tuần.'), findsOneWidget);
      expect(
        (await harness.outbox.entries(
          accountId: _accountId,
          organizationId: _organizationAId,
        )).where(
          (entry) => entry.mutation.intent.type == 'taskTemplate.create',
        ),
        isEmpty,
      );
      await tester.tap(find.byKey(const ValueKey('live-task-weekday-1')));
      await tester.tap(find.byKey(const ValueKey('live-task-weekday-4')));
      await tester.pumpAndSettle();
      await tester.ensureVisible(find.byKey(_liveTaskTemplateSaveKey));
      await tester.tap(find.byKey(_liveTaskTemplateSaveKey));
      await tester.pumpAndSettle();

      final entries = await harness.outbox.entries(
        accountId: _accountId,
        organizationId: _organizationAId,
      );
      final taskEntry = entries.singleWhere(
        (entry) => entry.mutation.intent.type == 'taskTemplate.create',
      );
      expect(taskEntry.mutation.scope.farmId, _farmAId);
      expect(taskEntry.mutation.intent.dependsOn, [zoneEntry.operationId]);
      expect(taskEntry.mutation.intent.baseVersion, isNull);
      expect(taskEntry.mutation.intent.payload, {
        'title': 'Cho bò ăn cỏ',
        'kind': 'feeding',
        'zoneId': zoneId,
        'recurrence': {
          'freq': 'weekly',
          'timeOfDay': '07:00',
          'daysOfWeek': [1, 4],
        },
      });
      expect(harness.transport.calls, 0);
      expect(
        find.byKey(
          ValueKey(
            'live-task-template-row-${taskEntry.mutation.intent.resourceId}',
          ),
        ),
        findsOneWidget,
      );
      expect(find.text(_savedPendingCopy), findsOneWidget);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets('workers and viewers cannot create live task templates', (
    tester,
  ) async {
    for (final role in [
      FarmlyFarmGrantRole.worker,
      FarmlyFarmGrantRole.viewer,
    ]) {
      final scope = _scope(
        organizationId: _organizationAId,
        organizationName: 'Tổ chức A',
        farmId: _farmAId,
        farmName: 'Nông trại A',
        continuityEpoch: '37',
        selectionEpoch: 11,
        organizationRole: FarmlyOrganizationRole.member,
        selectedFarmRole: role,
      );
      final domain = InMemoryDomainStore();
      await _installCropPlotSnapshot(
        domain,
        scope,
        zoneId: _cropPlotZoneAId,
        zoneName: 'Luống A',
      );
      final harness = await _pumpOverview(tester, scope: scope, domain: domain);

      await _openLiveCropPlotDetails(tester, zoneId: _cropPlotZoneAId);
      expect(
        find.byKey(
          const ValueKey('live-task-template-create-$_cropPlotZoneAId'),
        ),
        findsNothing,
      );
      expect(
        await harness.outbox.entries(
          accountId: _accountId,
          organizationId: _organizationAId,
        ),
        isEmpty,
      );
      expect(harness.transport.calls, 0);
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pumpAndSettle();
    }
  });

  testWidgets(
    'legacy weekly template with null weekdays remains visible for repair',
    (tester) async {
      final domain = InMemoryDomainStore();
      await _installCropPlotSnapshot(
        domain,
        _scopeA,
        zoneId: _cropPlotZoneAId,
        zoneName: 'Luống A',
        timezone: 'Asia/Ho_Chi_Minh',
        taskTemplates: const [
          {
            'id': _taskTemplateAId,
            'version': 1,
            'title': 'Lịch tưới cũ',
            'kind': 'irrigation',
            'zoneId': _cropPlotZoneAId,
            'startsOn': '2026-10-19',
            'recurrence': {
              'freq': 'weekly',
              'timeOfDay': '07:30',
              'daysOfWeek': null,
            },
            'status': 'active',
          },
        ],
      );
      final harness = await _pumpOverview(
        tester,
        scope: _scopeA,
        domain: domain,
        utcNow: () => DateTime.utc(2026, 10, 18, 17, 30),
      );

      await _openLiveCropPlotDetails(tester, zoneId: _cropPlotZoneAId);

      expect(find.text('Lịch tưới cũ'), findsOneWidget);
      expect(
        find.textContaining('Cần cập nhật ngày trong tuần'),
        findsOneWidget,
      );
      expect(find.byKey(_liveTaskOccurrencesListKey), findsOneWidget);
      final unscheduledOccurrenceId = farmlyTaskOccurrenceResourceId(
        farmId: _farmAId,
        templateId: _taskTemplateAId,
        occurrenceDate: '2026-10-19',
        slot: 'default',
      );
      expect(
        find.byKey(
          ValueKey('live-task-occurrence-row-$unscheduledOccurrenceId'),
        ),
        findsNothing,
      );
      expect(harness.transport.calls, 0);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets('manager repairs a legacy weekly schedule offline', (
    tester,
  ) async {
    final domain = InMemoryDomainStore();
    await _installCropPlotSnapshot(
      domain,
      _scopeA,
      zoneId: _cropPlotZoneAId,
      zoneName: 'Luống A',
      timezone: 'Asia/Ho_Chi_Minh',
      taskTemplates: const [
        {
          'id': _taskTemplateAId,
          'version': 4,
          'title': 'Lịch tưới cũ',
          'kind': 'irrigation',
          'zoneId': _cropPlotZoneAId,
          'startsOn': '2026-10-19',
          'recurrence': {
            'freq': 'weekly',
            'timeOfDay': '07:30',
            'daysOfWeek': null,
          },
          'status': 'active',
        },
      ],
    );
    final harness = await _pumpOverview(
      tester,
      scope: _scopeA,
      domain: domain,
      utcNow: () => DateTime.utc(2026, 10, 18, 17, 30),
    );

    await _openLiveCropPlotDetails(tester, zoneId: _cropPlotZoneAId);
    final repairButton = find.byKey(
      const ValueKey('live-task-template-repair-$_taskTemplateAId'),
    );
    await tester.ensureVisible(repairButton);
    await tester.tap(repairButton);
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('live-task-repair-weekday-1')));
    await tester.ensureVisible(
      find.byKey(const ValueKey('live-task-template-repair-save')),
    );
    await tester.tap(
      find.byKey(const ValueKey('live-task-template-repair-save')),
    );
    await tester.pumpAndSettle();

    final update =
        (await harness.outbox.entries(
          accountId: _accountId,
          organizationId: _organizationAId,
        )).singleWhere(
          (entry) => entry.mutation.intent.type == 'taskTemplate.update',
        );
    expect(update.mutation.intent.resourceId, _taskTemplateAId);
    expect(update.mutation.intent.baseVersion, 4);
    expect(update.mutation.intent.payload, {
      'recurrence': {
        'freq': 'weekly',
        'timeOfDay': '07:30',
        'daysOfWeek': [1],
      },
    });
    expect(update.status, OutboxEntryStatus.pending);
    expect(find.textContaining('Hằng tuần · T2 · 07:30'), findsOneWidget);
    expect(harness.transport.calls, 0);
    expect(tester.takeException(), isNull);
  });

  testWidgets('unknown task template recurrence fields fail closed', (
    tester,
  ) async {
    await _expectMalformedTaskTemplateSnapshot(tester, {
      'id': _taskTemplateAId,
      'version': 1,
      'title': 'Lịch tưới',
      'kind': 'irrigation',
      'zoneId': _cropPlotZoneAId,
      'recurrence': {
        'freq': 'weekly',
        'timeOfDay': '07:30',
        'unexpected': true,
      },
      'status': 'active',
    });
  });

  testWidgets(
    'task templates stay zone-scoped and confirmed snapshot wins duplicate outbox row',
    (tester) async {
      final domain = InMemoryDomainStore();
      await _installCropPlotSnapshot(
        domain,
        _scopeA,
        zoneId: _cropPlotZoneAId,
        zoneName: 'Luống A',
        taskTemplates: [
          {
            'id': _taskTemplateAId,
            'version': 2,
            'title': 'Bản đã xác nhận',
            'kind': 'feeding',
            'zoneId': _cropPlotZoneAId,
            'recurrence': {'freq': 'daily', 'timeOfDay': '06:00'},
            'status': 'active',
          },
          {
            'id': _taskTemplateBId,
            'version': 1,
            'title': 'Lịch ở vùng khác',
            'kind': 'general',
            'zoneId': _cropPlotZoneBId,
            'recurrence': {'freq': 'weekly', 'timeOfDay': '08:00'},
            'status': 'active',
          },
          {
            'id': _taskTemplateArchivedId,
            'version': 3,
            'title': 'Lịch đã lưu trữ',
            'kind': 'general',
            'zoneId': _cropPlotZoneAId,
            'recurrence': {'freq': 'daily', 'timeOfDay': '09:00'},
            'status': 'archived',
          },
        ],
      );
      final outbox = InMemoryOutboxStore();
      final duplicate = await outbox.enqueue(
        FarmlyScopedMutation(
          scope: FarmlyMutationScope.farm(
            accountId: _accountId,
            organizationId: _organizationAId,
            farmId: _farmAId,
            continuityEpoch: '37',
          ),
          intent: FarmlyCreateTaskTemplateIntent(
            operationId: _taskTemplateOperationId,
            continuityEpoch: '37',
            resourceId: _taskTemplateAId,
            title: 'Bản outbox trùng',
            zoneId: _cropPlotZoneAId,
            frequency: 'daily',
            timeOfDay: '06:00',
          ),
        ),
      );
      await outbox.update(
        duplicate.copyWith(
          status: OutboxEntryStatus.applied,
          appliedRevision: '2',
        ),
      );
      final harness = await _pumpOverview(
        tester,
        scope: _scopeA,
        domain: domain,
        outbox: outbox,
      );

      await _openLiveCropPlotDetails(tester, zoneId: _cropPlotZoneAId);

      expect(
        find.byKey(const ValueKey('live-task-template-row-$_taskTemplateAId')),
        findsOneWidget,
      );
      expect(find.text('Bản đã xác nhận'), findsOneWidget);
      expect(find.text('Bản outbox trùng'), findsNothing);
      expect(find.text('Lịch ở vùng khác'), findsNothing);
      expect(find.text('Lịch đã lưu trữ'), findsNothing);
      expect(harness.transport.calls, 0);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'derives today from the farm timezone and enqueues a deterministic default occurrence',
    (tester) async {
      final domain = InMemoryDomainStore();
      await _installCropPlotSnapshot(
        domain,
        _scopeA,
        zoneId: _cropPlotZoneAId,
        zoneName: 'Luống A',
        timezone: 'Asia/Ho_Chi_Minh',
        taskTemplates: const [
          {
            'id': _taskTemplateAId,
            'version': 1,
            'title': 'Cho bò ăn',
            'kind': 'feeding',
            'zoneId': _cropPlotZoneAId,
            'startsOn': '2026-10-19',
            'recurrence': {'freq': 'daily', 'timeOfDay': '06:00'},
            'status': 'active',
          },
        ],
      );
      final harness = await _pumpOverview(
        tester,
        scope: _scopeA,
        domain: domain,
        utcNow: () => DateTime.utc(2026, 10, 18, 17, 30),
      );

      await _openLiveCropPlotDetails(tester, zoneId: _cropPlotZoneAId);

      final resourceId = farmlyTaskOccurrenceResourceId(
        farmId: _farmAId,
        templateId: _taskTemplateAId,
        occurrenceDate: '2026-10-19',
        slot: 'default',
      );
      await tester.ensureVisible(
        find.byKey(ValueKey('live-task-occurrence-$resourceId-complete')),
      );
      await tester.tap(
        find.byKey(ValueKey('live-task-occurrence-$resourceId-complete')),
      );
      await tester.pumpAndSettle();

      expect(
        find.byKey(ValueKey('live-task-occurrence-$resourceId-complete')),
        findsNothing,
      );
      expect(find.text('Đã hoàn thành'), findsOneWidget);

      final entries = await harness.outbox.entries(
        accountId: _accountId,
        organizationId: _organizationAId,
      );
      final occurrence = entries.singleWhere(
        (entry) => entry.mutation.intent.type == 'taskOccurrence.transition',
      );
      expect(occurrence.mutation.intent.resourceId, resourceId);
      expect(occurrence.mutation.intent.baseVersion, isNull);
      expect(occurrence.mutation.intent.payload, {
        'templateId': _taskTemplateAId,
        'occurrenceDate': '2026-10-19',
        'slot': 'default',
        'transition': 'complete',
      });
      expect(occurrence.status, OutboxEntryStatus.pending);
      expect(harness.transport.calls, 0);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'preserves the materialized server slot and current occurrence version',
    (tester) async {
      final date = '2026-10-19';
      final resourceId = farmlyTaskOccurrenceResourceId(
        farmId: _farmAId,
        templateId: _taskTemplateAId,
        occurrenceDate: date,
        slot: 'morning',
      );
      final domain = InMemoryDomainStore();
      await _installCropPlotSnapshot(
        domain,
        _scopeA,
        zoneId: _cropPlotZoneAId,
        zoneName: 'Luống A',
        timezone: 'Asia/Ho_Chi_Minh',
        taskTemplates: [
          {
            'id': _taskTemplateAId,
            'version': 2,
            'title': 'Tưới luống',
            'kind': 'irrigation',
            'zoneId': _cropPlotZoneAId,
            'startsOn': date,
            'recurrence': {
              'freq': 'weekly',
              'timeOfDay': '07:00',
              'daysOfWeek': [2],
            },
            'status': 'active',
          },
        ],
        taskOccurrences: [
          {
            'id': resourceId,
            'version': 3,
            'templateId': _taskTemplateAId,
            'occurrenceDate': date,
            'slot': 'morning',
            'status': 'done',
          },
        ],
      );
      final harness = await _pumpOverview(
        tester,
        scope: _scopeA,
        domain: domain,
        utcNow: () => DateTime.utc(2026, 10, 18, 17, 30),
      );

      await _openLiveCropPlotDetails(tester, zoneId: _cropPlotZoneAId);
      await tester.ensureVisible(
        find.byKey(ValueKey('live-task-occurrence-$resourceId-reopen')),
      );
      final defaultId = farmlyTaskOccurrenceResourceId(
        farmId: _farmAId,
        templateId: _taskTemplateAId,
        occurrenceDate: date,
        slot: 'default',
      );
      expect(
        find.byKey(ValueKey('live-task-occurrence-row-$defaultId')),
        findsNothing,
      );
      await tester.tap(
        find.byKey(ValueKey('live-task-occurrence-$resourceId-reopen')),
      );
      await tester.pumpAndSettle();

      final occurrence =
          (await harness.outbox.entries(
            accountId: _accountId,
            organizationId: _organizationAId,
          )).singleWhere(
            (entry) =>
                entry.mutation.intent.type == 'irrigationTask.transition',
          );
      expect(occurrence.mutation.intent.resourceId, resourceId);
      expect(occurrence.mutation.intent.baseVersion, 3);
      expect(occurrence.mutation.intent.payload['slot'], 'morning');
      expect(occurrence.mutation.intent.payload['transition'], 'reopen');
      expect(harness.transport.calls, 0);
    },
  );

  testWidgets(
    'keeps a materialized occurrence visible but blocks it outside the template date window',
    (tester) async {
      const occurrenceDate = '2026-10-19';
      final resourceId = farmlyTaskOccurrenceResourceId(
        farmId: _farmAId,
        templateId: _taskTemplateAId,
        occurrenceDate: occurrenceDate,
        slot: 'morning',
      );
      final domain = InMemoryDomainStore();
      await _installCropPlotSnapshot(
        domain,
        _scopeA,
        zoneId: _cropPlotZoneAId,
        zoneName: 'Luống A',
        timezone: 'Asia/Ho_Chi_Minh',
        taskTemplates: const [
          {
            'id': _taskTemplateAId,
            'version': 2,
            'title': 'Lịch đã đổi ngày bắt đầu',
            'kind': 'general',
            'zoneId': _cropPlotZoneAId,
            'startsOn': '2026-10-20',
            'recurrence': {'freq': 'daily', 'timeOfDay': '08:00'},
            'status': 'active',
          },
        ],
        taskOccurrences: [
          {
            'id': resourceId,
            'version': 3,
            'templateId': _taskTemplateAId,
            'occurrenceDate': occurrenceDate,
            'slot': 'morning',
            'status': 'done',
          },
        ],
      );
      final harness = await _pumpOverview(
        tester,
        scope: _scopeA,
        domain: domain,
        utcNow: () => DateTime.utc(2026, 10, 18, 17, 30),
      );

      await _openLiveCropPlotDetails(tester, zoneId: _cropPlotZoneAId);

      expect(
        find.byKey(ValueKey('live-task-occurrence-row-$resourceId')),
        findsOneWidget,
      );
      expect(find.text('Đã hoàn thành'), findsOneWidget);
      expect(
        find.byKey(ValueKey('live-task-occurrence-$resourceId-reopen')),
        findsNothing,
      );
      expect(
        find.byKey(ValueKey('live-task-occurrence-$resourceId-cancel')),
        findsNothing,
      );
      expect(
        await harness.outbox.entries(
          accountId: _accountId,
          organizationId: _organizationAId,
        ),
        isEmpty,
      );
      expect(harness.transport.calls, 0);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'rechecks a materialized occurrence against the latest template window',
    (tester) async {
      const occurrenceDate = '2026-10-19';
      final resourceId = farmlyTaskOccurrenceResourceId(
        farmId: _farmAId,
        templateId: _taskTemplateAId,
        occurrenceDate: occurrenceDate,
        slot: 'morning',
      );
      final domain = InMemoryDomainStore();
      Future<void> installSnapshot({required String startsOn}) =>
          _installCropPlotSnapshot(
            domain,
            _scopeA,
            zoneId: _cropPlotZoneAId,
            zoneName: 'Luống A',
            timezone: 'Asia/Ho_Chi_Minh',
            taskTemplates: [
              {
                'id': _taskTemplateAId,
                'version': 2,
                'title': 'Lịch tưới luống',
                'kind': 'general',
                'zoneId': _cropPlotZoneAId,
                'startsOn': startsOn,
                'recurrence': {'freq': 'daily', 'timeOfDay': '08:00'},
                'status': 'active',
              },
            ],
            taskOccurrences: [
              {
                'id': resourceId,
                'version': 3,
                'templateId': _taskTemplateAId,
                'occurrenceDate': occurrenceDate,
                'slot': 'morning',
                'status': 'done',
              },
            ],
          );

      await installSnapshot(startsOn: occurrenceDate);
      final harness = await _pumpOverview(
        tester,
        scope: _scopeA,
        domain: domain,
        utcNow: () => DateTime.utc(2026, 10, 18, 17, 30),
      );

      await _openLiveCropPlotDetails(tester, zoneId: _cropPlotZoneAId);
      final reopenButton = find.byKey(
        ValueKey('live-task-occurrence-$resourceId-reopen'),
      );
      expect(reopenButton, findsOneWidget);
      await tester.ensureVisible(reopenButton);
      await tester.pumpAndSettle();

      await installSnapshot(startsOn: '2026-10-20');
      await tester.tap(reopenButton);
      await tester.pumpAndSettle();

      expect(
        await harness.outbox.entries(
          accountId: _accountId,
          organizationId: _organizationAId,
        ),
        isEmpty,
      );
      expect(harness.transport.calls, 0);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets('assigned farm workers can complete their task offline', (
    tester,
  ) async {
    final workerScope = _scope(
      organizationId: _organizationAId,
      organizationName: 'Tổ chức A',
      farmId: _farmAId,
      farmName: 'Nông trại A',
      continuityEpoch: '37',
      selectionEpoch: 11,
      organizationRole: FarmlyOrganizationRole.member,
      membershipId: _membershipId,
      selectedFarmRole: FarmlyFarmGrantRole.worker,
    );
    final domain = InMemoryDomainStore();
    await _installCropPlotSnapshot(
      domain,
      workerScope,
      zoneId: _cropPlotZoneAId,
      zoneName: 'Luống A',
      timezone: 'Asia/Ho_Chi_Minh',
      taskTemplates: const [
        {
          'id': _taskTemplateAId,
          'version': 1,
          'title': 'Cho bò ăn',
          'kind': 'feeding',
          'zoneId': _cropPlotZoneAId,
          'assigneeMembershipId': _membershipId,
          'startsOn': '2026-10-19',
          'recurrence': {'freq': 'daily', 'timeOfDay': '06:00'},
          'status': 'active',
        },
      ],
    );
    final harness = await _pumpOverview(
      tester,
      scope: workerScope,
      domain: domain,
      utcNow: () => DateTime.utc(2026, 10, 18, 17, 30),
    );

    await _openLiveCropPlotDetails(tester, zoneId: _cropPlotZoneAId);
    final resourceId = farmlyTaskOccurrenceResourceId(
      farmId: _farmAId,
      templateId: _taskTemplateAId,
      occurrenceDate: '2026-10-19',
      slot: 'default',
    );
    await tester.ensureVisible(
      find.byKey(ValueKey('live-task-occurrence-$resourceId-complete')),
    );
    expect(
      find.byKey(ValueKey('live-task-occurrence-$resourceId-cancel')),
      findsNothing,
    );
    await tester.tap(
      find.byKey(ValueKey('live-task-occurrence-$resourceId-complete')),
    );
    await tester.pumpAndSettle();

    final occurrence =
        (await harness.outbox.entries(
          accountId: _accountId,
          organizationId: _organizationAId,
        )).singleWhere(
          (entry) => entry.mutation.intent.type == 'taskOccurrence.transition',
        );
    expect(occurrence.mutation.intent.baseVersion, isNull);
    expect(occurrence.mutation.intent.payload['transition'], 'complete');
    expect(harness.transport.calls, 0);
  });

  testWidgets(
    'legacy weekly template without selected days is visible but not expanded',
    (tester) async {
      final domain = InMemoryDomainStore();
      await _installCropPlotSnapshot(
        domain,
        _scopeA,
        zoneId: _cropPlotZoneAId,
        zoneName: 'Luống A',
        timezone: 'Asia/Ho_Chi_Minh',
        taskTemplates: const [
          {
            'id': _taskTemplateAId,
            'version': 1,
            'title': 'Lịch cũ chưa chọn ngày',
            'kind': 'general',
            'zoneId': _cropPlotZoneAId,
            'startsOn': '2026-10-19',
            'recurrence': {'freq': 'weekly', 'timeOfDay': '08:00'},
            'status': 'active',
          },
        ],
      );
      final harness = await _pumpOverview(
        tester,
        scope: _scopeA,
        domain: domain,
        utcNow: () => DateTime.utc(2026, 10, 18, 17, 30),
      );

      await _openLiveCropPlotDetails(tester, zoneId: _cropPlotZoneAId);

      expect(
        find.textContaining('Cần cập nhật ngày trong tuần'),
        findsOneWidget,
      );
      expect(find.byKey(_liveTaskOccurrencesListKey), findsOneWidget);
      expect(
        find.text('Hôm nay không có công việc đến hạn trong khu vực này.'),
        findsOneWidget,
      );
      expect(harness.transport.calls, 0);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'crop plot details list only crop species and plantings from selected farm',
    (tester) async {
      final domain = InMemoryDomainStore();
      await _installCropPlotSnapshot(
        domain,
        _scopeA,
        zoneId: _cropPlotZoneAId,
        zoneName: 'Luống A',
        cropSpecies: const [
          {
            'id': _cropSpeciesAId,
            'version': 2,
            'name': 'Cà chua bi',
            'harvestUnit': 'kg',
            'status': 'active',
          },
        ],
        plantings: const [
          {
            'id': _plantingAId,
            'version': 1,
            'cropSpeciesId': _cropSpeciesAId,
            'plotId': _cropPlotZoneAId,
            'status': 'active',
            'sowingDate': '2026-09-10',
            'expectedHarvestDate': '2026-10-10',
          },
        ],
        harvests: const [
          {
            'id': _harvestAId,
            'version': 1,
            'plantingId': _plantingAId,
            'quantityKg': '5.25',
            'harvestDate': '2026-10-02',
            'status': 'active',
          },
        ],
      );
      await _installCropPlotSnapshot(
        domain,
        _scopeB,
        zoneId: _cropPlotZoneBId,
        zoneName: 'Luống B',
        cropSpecies: const [
          {
            'id': _cropSpeciesBId,
            'version': 3,
            'name': 'Khoai tây',
            'harvestUnit': 'kg',
            'status': 'active',
          },
        ],
        plantings: const [
          {
            'id': _plantingBId,
            'version': 2,
            'cropSpeciesId': _cropSpeciesBId,
            'plotId': _cropPlotZoneBId,
            'status': 'active',
            'sowingDate': '2026-08-01',
          },
        ],
      );
      await _pumpOverview(tester, scope: _scopeA, domain: domain);

      await _openLiveCropPlotDetails(tester, zoneId: _cropPlotZoneAId);

      expect(find.byKey(_liveCropSpeciesListKey), findsOneWidget);
      expect(find.byKey(_livePlantingsListKey), findsOneWidget);
      expect(
        find.byKey(const ValueKey('live-crop-species-row-$_cropSpeciesAId')),
        findsOneWidget,
      );
      expect(
        find.byKey(const ValueKey('live-crop-species-row-$_cropSpeciesBId')),
        findsNothing,
      );
      expect(
        find.byKey(const ValueKey('live-planting-row-$_plantingAId')),
        findsOneWidget,
      );
      expect(
        find.byKey(const ValueKey('live-planting-row-$_plantingBId')),
        findsNothing,
      );
      expect(find.text('Cà chua bi'), findsWidgets);
      expect(find.text('Khoai tây'), findsNothing);
      expect(
        find.byKey(const ValueKey('live-harvest-row-$_harvestAId')),
        findsOneWidget,
      );
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets('farm manager edits confirmed planting locally', (tester) async {
    final managerScope = _plantingManagerScope;
    final domain = InMemoryDomainStore();
    await _installPlantingUpdateFixture(domain, managerScope);
    final harness = await _pumpOverview(
      tester,
      scope: managerScope,
      domain: domain,
    );

    await _openLiveCropPlotDetails(tester, zoneId: _cropPlotZoneAId);
    final editButton = _livePlantingEditKey(_plantingAId);
    expect(find.byKey(editButton), findsOneWidget);
    await tester.ensureVisible(find.byKey(editButton));
    await tester.tap(find.byKey(editButton));
    await tester.pumpAndSettle();
    expect(find.byKey(_livePlantingEditStatusKey), findsOneWidget);
    expect(find.byKey(_livePlantingEditSowingDateKey), findsOneWidget);
    expect(find.byKey(_livePlantingEditExpectedHarvestDateKey), findsOneWidget);
    expect(find.byKey(_livePlantingEditAreaKey), findsOneWidget);

    await tester.enterText(find.byKey(_livePlantingEditAreaKey), '125.50');
    await tester.tap(find.byKey(_livePlantingEditSaveKey));
    await tester.pumpAndSettle();

    expect(find.text(_savedPendingCopy), findsOneWidget);
    expect(find.textContaining('125'), findsOneWidget);
    expect(find.byKey(editButton), findsNothing);
    final entries = await harness.outbox.entries(
      accountId: _accountId,
      organizationId: _organizationAId,
    );
    expect(entries, hasLength(1));
    final update = entries.single;
    expect(update.status, OutboxEntryStatus.pending);
    expect(update.mutation.scope.organizationId, _organizationAId);
    expect(update.mutation.scope.farmId, _farmAId);
    expect(update.mutation.scope.continuityEpoch, '37');
    expect(update.mutation.intent.type, 'planting.update');
    expect(update.mutation.intent.resourceId, _plantingAId);
    expect(update.mutation.intent.baseVersion, 5);
    expect(update.mutation.intent.payload, {'areaM2': '125.50'});
    expect(update.mutation.intent.payload, isNot(contains('cropSpeciesId')));
    expect(update.mutation.intent.payload, isNot(contains('plotId')));
    expect(harness.transport.calls, 0);
    expect(tester.takeException(), isNull);
  });

  testWidgets(
    'manager confirms planting archive locally and retains the confirmed history',
    (tester) async {
      final managerScope = _plantingManagerScope;
      final domain = InMemoryDomainStore();
      await _installPlantingUpdateFixture(
        domain,
        managerScope,
        plantingEvents: const [
          {
            'id': 'dddddddd-dddd-4ddd-8ddd-dddddddddddd',
            'version': 1,
            'plantingId': _plantingAId,
            'eventType': 'watering',
            'note': 'Tưới luống',
            'occurredOn': '2026-10-18',
          },
        ],
        harvests: const [
          {
            'id': _harvestAId,
            'version': 1,
            'plantingId': _plantingAId,
            'quantityKg': '5.25',
            'harvestDate': '2026-10-19',
            'status': 'active',
          },
        ],
      );
      final harness = await _pumpOverview(
        tester,
        scope: managerScope,
        domain: domain,
        viewportSize: const Size(320, 844),
        textScaleFactor: 1,
      );

      await _openLiveCropPlotDetails(tester, zoneId: _cropPlotZoneAId);
      final archiveButton = _livePlantingArchiveKey(_plantingAId);
      expect(find.byKey(archiveButton), findsOneWidget);
      await tester.ensureVisible(find.byKey(archiveButton));
      await tester.tap(find.byKey(archiveButton));
      await tester.pumpAndSettle();
      expect(find.byKey(_livePlantingArchiveDialogKey), findsOneWidget);
      expect(
        find.text(
          'Đợt gieo sẽ rời danh sách đang hoạt động. Nhật ký hoạt động và lịch sử thu hoạch vẫn được giữ lại.',
        ),
        findsOneWidget,
      );

      await tester.tap(find.byKey(_livePlantingArchiveConfirmKey));
      await tester.pumpAndSettle();

      expect(find.byKey(_livePlantingArchiveDialogKey), findsNothing);
      expect(
        find.byKey(const ValueKey('live-planting-row-$_plantingAId')),
        findsNothing,
      );
      expect(find.text(_savedPendingCopy), findsOneWidget);
      final entries = await harness.outbox.entries(
        accountId: _accountId,
        organizationId: _organizationAId,
      );
      expect(entries, hasLength(1));
      final archive = entries.single;
      expect(archive.status, OutboxEntryStatus.pending);
      expect(archive.mutation.scope.organizationId, _organizationAId);
      expect(archive.mutation.scope.farmId, _farmAId);
      expect(archive.mutation.scope.continuityEpoch, '37');
      expect(archive.mutation.intent.type, 'planting.archive');
      expect(archive.mutation.intent.resourceId, _plantingAId);
      expect(archive.mutation.intent.baseVersion, 5);
      expect(archive.mutation.intent.payload, isEmpty);
      final scopeKey = _scopeKey(managerScope);
      expect(domain.recordsOf(scopeKey, 'planting'), contains(_plantingAId));
      expect(
        domain.recordsOf(scopeKey, 'planting')[_plantingAId],
        containsPair('status', 'active'),
      );
      expect(
        domain.recordsOf(scopeKey, 'plantingEvent'),
        contains('dddddddd-dddd-4ddd-8ddd-dddddddddddd'),
      );
      expect(domain.recordsOf(scopeKey, 'harvest'), contains(_harvestAId));
      expect(harness.transport.calls, 0);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets('canceling planting archive confirmation enqueues nothing', (
    tester,
  ) async {
    final managerScope = _plantingManagerScope;
    final domain = InMemoryDomainStore();
    await _installPlantingUpdateFixture(domain, managerScope);
    final harness = await _pumpOverview(
      tester,
      scope: managerScope,
      domain: domain,
    );

    await _openLiveCropPlotDetails(tester, zoneId: _cropPlotZoneAId);
    await tester.tap(find.byKey(_livePlantingArchiveKey(_plantingAId)));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(_livePlantingArchiveCancelKey));
    await tester.pumpAndSettle();

    expect(find.byKey(_livePlantingArchiveDialogKey), findsNothing);
    expect(
      find.byKey(const ValueKey('live-planting-row-$_plantingAId')),
      findsOneWidget,
    );
    expect(
      await harness.outbox.entries(
        accountId: _accountId,
        organizationId: _organizationAId,
      ),
      isEmpty,
    );
    expect(harness.transport.calls, 0);
    expect(tester.takeException(), isNull);
  });

  testWidgets(
    'duplicate archive confirmation while enqueue is pending is blocked',
    (tester) async {
      final managerScope = _plantingManagerScope;
      final domain = InMemoryDomainStore();
      await _installPlantingUpdateFixture(domain, managerScope);
      final enqueueDelay = Completer<void>();
      final enqueueStarted = Completer<void>();
      final harness = await _pumpOverview(
        tester,
        scope: managerScope,
        domain: domain,
        enqueueDelay: enqueueDelay.future,
        enqueueStarted: enqueueStarted,
      );

      await _openLiveCropPlotDetails(tester, zoneId: _cropPlotZoneAId);
      await tester.tap(find.byKey(_livePlantingArchiveKey(_plantingAId)));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(_livePlantingArchiveConfirmKey));
      await enqueueStarted.future.timeout(const Duration(seconds: 2));
      await tester.pump();

      await tester.tap(find.byKey(_livePlantingArchiveKey(_plantingAId)));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(_livePlantingArchiveConfirmKey));
      await tester.pumpAndSettle();
      enqueueDelay.complete();
      await tester.pumpAndSettle();

      expect(
        await harness.outbox.entries(
          accountId: _accountId,
          organizationId: _organizationAId,
        ),
        hasLength(1),
      );
      expect(harness.transport.calls, 0);
      expect(tester.takeException(), isNull);
    },
  );

  for (final (roleName, organizationRole, farmRole, canEdit) in [
    (
      'organization owner',
      FarmlyOrganizationRole.owner,
      FarmlyFarmGrantRole.viewer,
      true,
    ),
    (
      'organization admin',
      FarmlyOrganizationRole.admin,
      FarmlyFarmGrantRole.viewer,
      true,
    ),
    (
      'farm owner',
      FarmlyOrganizationRole.member,
      FarmlyFarmGrantRole.owner,
      true,
    ),
    (
      'farm admin',
      FarmlyOrganizationRole.member,
      FarmlyFarmGrantRole.admin,
      true,
    ),
    (
      'farm manager',
      FarmlyOrganizationRole.member,
      FarmlyFarmGrantRole.manager,
      true,
    ),
    (
      'farm worker',
      FarmlyOrganizationRole.member,
      FarmlyFarmGrantRole.worker,
      false,
    ),
    (
      'organization viewer',
      FarmlyOrganizationRole.viewer,
      FarmlyFarmGrantRole.manager,
      false,
    ),
  ]) {
    testWidgets('$roleName planting mutation affordance is correct', (
      tester,
    ) async {
      final roleScope = _scope(
        organizationId: _organizationAId,
        organizationName: 'Tổ chức A',
        farmId: _farmAId,
        farmName: 'Nông trại A',
        continuityEpoch: '37',
        selectionEpoch: 11,
        organizationRole: organizationRole,
        selectedFarmRole: farmRole,
      );
      final domain = InMemoryDomainStore();
      await _installPlantingUpdateFixture(domain, roleScope);
      final harness = await _pumpOverview(
        tester,
        scope: roleScope,
        domain: domain,
      );

      await _openLiveCropPlotDetails(tester, zoneId: _cropPlotZoneAId);

      expect(
        find.byKey(_livePlantingEditKey(_plantingAId)),
        canEdit ? findsOneWidget : findsNothing,
      );
      expect(
        find.byKey(_livePlantingArchiveKey(_plantingAId)),
        canEdit ? findsOneWidget : findsNothing,
      );
      expect(harness.transport.calls, 0);
      expect(tester.takeException(), isNull);
    });
  }

  testWidgets('archived planting has no edit or archive action', (
    tester,
  ) async {
    final managerScope = _plantingManagerScope;
    final domain = InMemoryDomainStore();
    await _installPlantingUpdateFixture(
      domain,
      managerScope,
      status: 'archived',
    );
    final harness = await _pumpOverview(
      tester,
      scope: managerScope,
      domain: domain,
    );

    await _openLiveCropPlotDetails(tester, zoneId: _cropPlotZoneAId);

    expect(find.byKey(_livePlantingEditKey(_plantingAId)), findsNothing);
    expect(find.byKey(_livePlantingArchiveKey(_plantingAId)), findsNothing);
    expect(harness.transport.calls, 0);
    expect(tester.takeException(), isNull);
  });

  testWidgets('changing planting version after confirmation blocks archive', (
    tester,
  ) async {
    final managerScope = _plantingManagerScope;
    final domain = InMemoryDomainStore();
    await _installPlantingUpdateFixture(domain, managerScope, version: 5);
    final harness = await _pumpOverview(
      tester,
      scope: managerScope,
      domain: domain,
    );

    await _openLiveCropPlotDetails(tester, zoneId: _cropPlotZoneAId);
    await tester.tap(find.byKey(_livePlantingArchiveKey(_plantingAId)));
    await tester.pumpAndSettle();
    await _installPlantingUpdateFixture(domain, managerScope, version: 6);
    harness.container.invalidate(farmlyLiveZoneCollectionProvider);
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(_livePlantingArchiveConfirmKey));
    await tester.pumpAndSettle();

    expect(
      await harness.outbox.entries(
        accountId: _accountId,
        organizationId: _organizationAId,
      ),
      isEmpty,
    );
    expect(
      find.byKey(const ValueKey('live-planting-row-$_plantingAId')),
      findsOneWidget,
    );
    expect(find.textContaining('Đang trồng'), findsOneWidget);
    expect(harness.transport.calls, 0);
    expect(tester.takeException(), isNull);
  });

  testWidgets('planting archive from another farm cannot project here', (
    tester,
  ) async {
    final managerScope = _plantingManagerScope;
    final foreignScope = _scope(
      organizationId: _organizationAId,
      organizationName: 'Tổ chức A',
      farmId: _farmAOtherId,
      farmName: 'Nông trại A2',
      continuityEpoch: '37',
      selectionEpoch: 12,
      organizationRole: FarmlyOrganizationRole.member,
      selectedFarmRole: FarmlyFarmGrantRole.manager,
    );
    final domain = InMemoryDomainStore();
    await _installPlantingUpdateFixture(domain, managerScope);
    final outbox = InMemoryOutboxStore();
    await _queuePlantingArchive(
      outbox,
      foreignScope,
      operationId: 'd4d4d4d4-d4d4-44d4-84d4-d4d4d4d4d4d4',
      baseVersion: 5,
    );
    final harness = await _pumpOverview(
      tester,
      scope: managerScope,
      domain: domain,
      outbox: outbox,
    );

    await _openLiveCropPlotDetails(tester, zoneId: _cropPlotZoneAId);

    expect(find.byKey(_livePlantingArchiveKey(_plantingAId)), findsOneWidget);
    expect(find.textContaining('Đang trồng'), findsOneWidget);
    expect(harness.transport.calls, 0);
    expect(tester.takeException(), isNull);
  });

  for (final entryStatus in [
    OutboxEntryStatus.blocked,
    OutboxEntryStatus.conflict,
  ]) {
    testWidgets('$entryStatus planting archive fails closed', (tester) async {
      final managerScope = _plantingManagerScope;
      final domain = InMemoryDomainStore();
      await _installPlantingUpdateFixture(domain, managerScope);
      final outbox = InMemoryOutboxStore();
      final pending = await _queuePlantingArchive(
        outbox,
        managerScope,
        operationId: entryStatus == OutboxEntryStatus.blocked
            ? 'd5d5d5d5-d5d5-45d5-85d5-d5d5d5d5d5d5'
            : 'd6d6d6d6-d6d6-46d6-86d6-d6d6d6d6d6d6',
        baseVersion: 5,
      );
      await outbox.update(pending.copyWith(status: entryStatus));
      final harness = await _pumpOverview(
        tester,
        scope: managerScope,
        domain: domain,
        outbox: outbox,
      );

      await _openLiveCropPlotDetails(tester, zoneId: _cropPlotZoneAId);

      expect(
        find.byKey(const ValueKey('live-planting-row-$_plantingAId')),
        findsOneWidget,
      );
      expect(find.textContaining('Đang trồng'), findsOneWidget);
      expect(find.byKey(_livePlantingEditKey(_plantingAId)), findsNothing);
      expect(find.byKey(_livePlantingArchiveKey(_plantingAId)), findsNothing);
      expect(
        find.text('Máy chủ chưa chấp nhận thao tác; bản lưu vẫn được giữ'),
        findsOneWidget,
      );
      expect(harness.transport.calls, 0);
      expect(tester.takeException(), isNull);
    });
  }

  testWidgets('stale planting archive leaves the confirmed row visible', (
    tester,
  ) async {
    final managerScope = _plantingManagerScope;
    final domain = InMemoryDomainStore();
    await _installPlantingUpdateFixture(domain, managerScope, version: 6);
    final outbox = InMemoryOutboxStore();
    await _queuePlantingArchive(
      outbox,
      managerScope,
      operationId: 'd7d7d7d7-d7d7-47d7-87d7-d7d7d7d7d7d7',
      baseVersion: 5,
    );
    final harness = await _pumpOverview(
      tester,
      scope: managerScope,
      domain: domain,
      outbox: outbox,
    );

    await _openLiveCropPlotDetails(tester, zoneId: _cropPlotZoneAId);

    expect(
      find.byKey(const ValueKey('live-planting-row-$_plantingAId')),
      findsOneWidget,
    );
    expect(find.textContaining('Đang trồng'), findsOneWidget);
    expect(find.byKey(_livePlantingArchiveKey(_plantingAId)), findsNothing);
    expect(
      find.text('Máy chủ chưa chấp nhận thao tác; bản lưu vẫn được giữ'),
      findsOneWidget,
    );
    expect(harness.transport.calls, 0);
    expect(tester.takeException(), isNull);
  });

  testWidgets('pending planting update blocks a concurrent archive', (
    tester,
  ) async {
    final managerScope = _plantingManagerScope;
    final domain = InMemoryDomainStore();
    await _installPlantingUpdateFixture(domain, managerScope);
    final outbox = InMemoryOutboxStore();
    await _queuePlantingUpdate(
      outbox,
      managerScope,
      operationId: 'd8d8d8d8-d8d8-48d8-88d8-d8d8d8d8d8d8',
      baseVersion: 5,
      areaM2: '99.00',
    );
    final harness = await _pumpOverview(
      tester,
      scope: managerScope,
      domain: domain,
      outbox: outbox,
    );

    await _openLiveCropPlotDetails(tester, zoneId: _cropPlotZoneAId);

    expect(
      find.byKey(const ValueKey('live-planting-row-$_plantingAId')),
      findsOneWidget,
    );
    expect(find.textContaining('99'), findsOneWidget);
    expect(find.byKey(_livePlantingEditKey(_plantingAId)), findsNothing);
    expect(find.byKey(_livePlantingArchiveKey(_plantingAId)), findsNothing);
    expect(harness.transport.calls, 0);
    expect(tester.takeException(), isNull);
  });

  testWidgets('multiple pending planting archives fail closed', (tester) async {
    final managerScope = _plantingManagerScope;
    final domain = InMemoryDomainStore();
    await _installPlantingUpdateFixture(domain, managerScope);
    final outbox = InMemoryOutboxStore();
    await _queuePlantingArchive(
      outbox,
      managerScope,
      operationId: 'dadadada-dada-4ada-8ada-dadadadadada',
      baseVersion: 5,
    );
    await _queuePlantingArchive(
      outbox,
      managerScope,
      operationId: 'dbdbdbdb-dbdb-4bdb-8bdb-dbdbdbdbdbdb',
      baseVersion: 5,
    );
    final harness = await _pumpOverview(
      tester,
      scope: managerScope,
      domain: domain,
      outbox: outbox,
    );

    await _openLiveCropPlotDetails(tester, zoneId: _cropPlotZoneAId);

    expect(
      find.byKey(const ValueKey('live-planting-row-$_plantingAId')),
      findsOneWidget,
    );
    expect(find.textContaining('Đang trồng'), findsOneWidget);
    expect(find.byKey(_livePlantingArchiveKey(_plantingAId)), findsNothing);
    expect(harness.transport.calls, 0);
    expect(tester.takeException(), isNull);
  });

  testWidgets('rejected archive history does not block a new archive', (
    tester,
  ) async {
    final managerScope = _plantingManagerScope;
    final domain = InMemoryDomainStore();
    await _installPlantingUpdateFixture(domain, managerScope);
    final outbox = InMemoryOutboxStore();
    final rejected = await _queuePlantingArchive(
      outbox,
      managerScope,
      operationId: 'dcdcdcdc-dcdc-4cdc-8cdc-dcdcdcdcdcdc',
      baseVersion: 5,
    );
    await outbox.update(rejected.copyWith(status: OutboxEntryStatus.rejected));
    final harness = await _pumpOverview(
      tester,
      scope: managerScope,
      domain: domain,
      outbox: outbox,
    );

    await _openLiveCropPlotDetails(tester, zoneId: _cropPlotZoneAId);

    expect(find.byKey(_livePlantingArchiveKey(_plantingAId)), findsOneWidget);
    expect(find.textContaining('Đang trồng'), findsOneWidget);
    expect(harness.transport.calls, 0);
    expect(tester.takeException(), isNull);
  });

  testWidgets('pending planting update projects and blocks a second edit', (
    tester,
  ) async {
    final managerScope = _plantingManagerScope;
    final domain = InMemoryDomainStore();
    await _installPlantingUpdateFixture(domain, managerScope);
    final outbox = InMemoryOutboxStore();
    await _queuePlantingUpdate(
      outbox,
      managerScope,
      operationId: '28282828-2828-4828-8828-282828282828',
      baseVersion: 5,
      areaM2: '140.25',
    );
    final harness = await _pumpOverview(
      tester,
      scope: managerScope,
      domain: domain,
      outbox: outbox,
    );

    await _openLiveCropPlotDetails(tester, zoneId: _cropPlotZoneAId);

    expect(find.textContaining('140'), findsOneWidget);
    expect(find.textContaining('80'), findsNothing);
    expect(find.byKey(_livePlantingEditKey(_plantingAId)), findsNothing);
    expect(harness.transport.calls, 0);
    expect(tester.takeException(), isNull);
  });

  testWidgets(
    'pending planting create row cannot be edited before confirmation',
    (tester) async {
      final managerScope = _plantingManagerScope;
      final domain = InMemoryDomainStore();
      await _installPlantingUpdateFixture(domain, managerScope);
      final outbox = InMemoryOutboxStore();
      await outbox.enqueue(
        FarmlyScopedMutation(
          scope: FarmlyMutationScope.farm(
            accountId: _accountId,
            organizationId: _organizationAId,
            farmId: _farmAId,
            continuityEpoch: '37',
          ),
          intent: FarmlyCreatePlantingIntent(
            operationId: '29292929-2929-4929-8929-292929292929',
            continuityEpoch: '37',
            resourceId: _plantingBId,
            cropSpeciesId: _cropSpeciesAId,
            plotId: _cropPlotZoneAId,
            sowingDate: '2026-10-01',
            areaM2: '25.0',
          ),
        ),
      );
      final harness = await _pumpOverview(
        tester,
        scope: managerScope,
        domain: domain,
        outbox: outbox,
      );

      await _openLiveCropPlotDetails(tester, zoneId: _cropPlotZoneAId);

      expect(find.byKey(_livePlantingEditKey(_plantingBId)), findsNothing);
      expect(find.byKey(_livePlantingArchiveKey(_plantingBId)), findsNothing);
      expect(harness.transport.calls, 0);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets('planting update from another farm cannot project here', (
    tester,
  ) async {
    final managerScope = _plantingManagerScope;
    final foreignScope = _scope(
      organizationId: _organizationAId,
      organizationName: 'Tổ chức A',
      farmId: _farmAOtherId,
      farmName: 'Nông trại A2',
      continuityEpoch: '37',
      selectionEpoch: 12,
      organizationRole: FarmlyOrganizationRole.member,
      selectedFarmRole: FarmlyFarmGrantRole.manager,
    );
    final domain = InMemoryDomainStore();
    await _installPlantingUpdateFixture(domain, managerScope);
    final outbox = InMemoryOutboxStore();
    await _queuePlantingUpdate(
      outbox,
      foreignScope,
      operationId: '30303030-3030-4030-8030-303030303030',
      baseVersion: 5,
      areaM2: '333.0',
    );
    final harness = await _pumpOverview(
      tester,
      scope: managerScope,
      domain: domain,
      outbox: outbox,
    );

    await _openLiveCropPlotDetails(tester, zoneId: _cropPlotZoneAId);

    expect(find.textContaining('333'), findsNothing);
    expect(find.byKey(_livePlantingEditKey(_plantingAId)), findsOneWidget);
    expect(harness.transport.calls, 0);
    expect(tester.takeException(), isNull);
  });

  for (final entryStatus in [
    OutboxEntryStatus.blocked,
    OutboxEntryStatus.conflict,
  ]) {
    testWidgets('$entryStatus planting update fails closed', (tester) async {
      final managerScope = _plantingManagerScope;
      final domain = InMemoryDomainStore();
      await _installPlantingUpdateFixture(domain, managerScope);
      final outbox = InMemoryOutboxStore();
      final pending = await _queuePlantingUpdate(
        outbox,
        managerScope,
        operationId: entryStatus == OutboxEntryStatus.blocked
            ? '31313131-3131-4131-8131-313131313131'
            : '32323232-3232-4232-8232-323232323232',
        baseVersion: 5,
        areaM2: '155.0',
      );
      await outbox.update(pending.copyWith(status: entryStatus));
      final harness = await _pumpOverview(
        tester,
        scope: managerScope,
        domain: domain,
        outbox: outbox,
      );

      await _openLiveCropPlotDetails(tester, zoneId: _cropPlotZoneAId);

      expect(find.textContaining('155'), findsNothing);
      expect(find.byKey(_livePlantingEditKey(_plantingAId)), findsNothing);
      expect(harness.transport.calls, 0);
      expect(tester.takeException(), isNull);
    });
  }

  testWidgets('multiple unresolved planting updates fail closed', (
    tester,
  ) async {
    final managerScope = _plantingManagerScope;
    final domain = InMemoryDomainStore();
    await _installPlantingUpdateFixture(domain, managerScope);
    final outbox = InMemoryOutboxStore();
    for (final (operationId, areaM2) in [
      ('33333333-3333-4333-8333-333333333333', '145.0'),
      ('34343434-3434-4434-8434-343434343434', '146.0'),
    ]) {
      await _queuePlantingUpdate(
        outbox,
        managerScope,
        operationId: operationId,
        baseVersion: 5,
        areaM2: areaM2,
      );
    }
    final harness = await _pumpOverview(
      tester,
      scope: managerScope,
      domain: domain,
      outbox: outbox,
    );

    await _openLiveCropPlotDetails(tester, zoneId: _cropPlotZoneAId);

    expect(find.textContaining('145'), findsNothing);
    expect(find.textContaining('146'), findsNothing);
    expect(find.byKey(_livePlantingEditKey(_plantingAId)), findsNothing);
    expect(harness.transport.calls, 0);
    expect(tester.takeException(), isNull);
  });

  testWidgets('stale planting update does not project and locks edit', (
    tester,
  ) async {
    final managerScope = _plantingManagerScope;
    final domain = InMemoryDomainStore();
    await _installPlantingUpdateFixture(domain, managerScope, version: 6);
    final outbox = InMemoryOutboxStore();
    await _queuePlantingUpdate(
      outbox,
      managerScope,
      operationId: '35353535-3535-4535-8535-353535353535',
      baseVersion: 5,
      areaM2: '175.0',
    );
    final harness = await _pumpOverview(
      tester,
      scope: managerScope,
      domain: domain,
      outbox: outbox,
    );

    await _openLiveCropPlotDetails(tester, zoneId: _cropPlotZoneAId);

    expect(find.textContaining('175'), findsNothing);
    expect(find.byKey(_livePlantingEditKey(_plantingAId)), findsNothing);
    expect(harness.transport.calls, 0);
    expect(tester.takeException(), isNull);
  });

  testWidgets('planting edit save rejects a stale confirmed version', (
    tester,
  ) async {
    final managerScope = _plantingManagerScope;
    final domain = InMemoryDomainStore();
    await _installPlantingUpdateFixture(domain, managerScope, version: 5);
    final harness = await _pumpOverview(
      tester,
      scope: managerScope,
      domain: domain,
    );
    await _openLiveCropPlotDetails(tester, zoneId: _cropPlotZoneAId);
    await tester.tap(find.byKey(_livePlantingEditKey(_plantingAId)));
    await tester.pumpAndSettle();
    await tester.enterText(find.byKey(_livePlantingEditAreaKey), '125.0');
    await _installPlantingUpdateFixture(domain, managerScope, version: 6);
    harness.container.invalidate(farmlyLiveZoneCollectionProvider);
    await tester.pumpAndSettle();

    final editForm = find.byKey(_livePlantingEditSaveKey);
    final l10n = AppLocalizations.of(tester.element(editForm));
    expect(find.text(l10n.livePlantingChanged), findsOneWidget);
    expect(find.text(l10n.liveFarmScopeChanged), findsNothing);

    await tester.tap(find.byKey(_livePlantingEditSaveKey));
    await tester.pumpAndSettle();

    expect(find.text(_savedPendingCopy), findsNothing);
    expect(
      await harness.outbox.entries(
        accountId: _accountId,
        organizationId: _organizationAId,
      ),
      isEmpty,
    );
    expect(harness.transport.calls, 0);
    expect(tester.takeException(), isNull);
  });

  testWidgets('planting edit form locks when the selected farm changes', (
    tester,
  ) async {
    final managerScope = _plantingManagerScope;
    final domain = InMemoryDomainStore();
    await _installPlantingUpdateFixture(domain, managerScope);
    final harness = await _pumpOverview(
      tester,
      scope: managerScope,
      domain: domain,
    );
    await _openLiveCropPlotDetails(tester, zoneId: _cropPlotZoneAId);
    await tester.tap(find.byKey(_livePlantingEditKey(_plantingAId)));
    await tester.pumpAndSettle();

    harness.scopeController.replace(_scopeB);
    await tester.pumpAndSettle();

    final editForm = find.byKey(_livePlantingEditSaveKey);
    final l10n = AppLocalizations.of(tester.element(editForm));
    expect(find.text(l10n.liveFarmScopeChanged), findsWidgets);
    expect(find.text(l10n.livePlantingChanged), findsNothing);

    expect(
      tester.widget<DecimalField>(find.byKey(_livePlantingEditAreaKey)).enabled,
      isFalse,
    );
    expect(
      tester
          .widget<FilledButton>(find.byKey(_livePlantingEditSaveKey))
          .onPressed,
      isNull,
    );
    expect(
      await harness.outbox.entries(
        accountId: _accountId,
        organizationId: _organizationAId,
      ),
      isEmpty,
    );
    expect(harness.transport.calls, 0);
    expect(tester.takeException(), isNull);
  });

  testWidgets('farm manager renames a confirmed zone locally', (tester) async {
    final managerScope = _waterTankManagerScope;
    final domain = InMemoryDomainStore();
    await _installCropPlotSnapshot(
      domain,
      managerScope,
      zoneId: _cropPlotZoneAId,
      zoneName: 'Luống A',
      zoneVersion: 4,
    );
    final harness = await _pumpOverview(
      tester,
      scope: managerScope,
      domain: domain,
    );

    await _openLiveCropPlotDetails(tester, zoneId: _cropPlotZoneAId);
    expect(find.byKey(_liveZoneEditNameKey), findsOneWidget);
    await tester.tap(find.byKey(_liveZoneEditNameKey));
    await tester.pumpAndSettle();
    expect(find.byKey(_liveZoneEditNameFieldKey), findsOneWidget);

    await tester.enterText(
      find.byKey(_liveZoneEditNameFieldKey),
      'Luống hữu cơ',
    );
    await tester.tap(find.byKey(_liveZoneEditNameSaveKey));
    await tester.pumpAndSettle();

    expect(find.text('Luống hữu cơ'), findsWidgets);
    expect(find.text('Luống A'), findsNothing);
    expect(find.byKey(_liveZoneEditNameKey), findsNothing);
    final entries = await harness.outbox.entries(
      accountId: _accountId,
      organizationId: _organizationAId,
    );
    expect(entries, hasLength(1));
    final update = entries.single;
    expect(update.status, OutboxEntryStatus.pending);
    expect(update.mutation.scope.farmId, _farmAId);
    expect(update.mutation.scope.continuityEpoch, '37');
    expect(update.mutation.intent.type, 'zone.update');
    expect(update.mutation.intent.resourceId, _cropPlotZoneAId);
    expect(update.mutation.intent.baseVersion, 4);
    expect(update.mutation.intent.payload, {'name': 'Luống hữu cơ'});
    expect(harness.transport.calls, 0);
    expect(tester.takeException(), isNull);
  });

  testWidgets('concurrent zone renames enqueue only one update', (
    tester,
  ) async {
    final managerScope = _waterTankManagerScope;
    final domain = InMemoryDomainStore();
    await _installCropPlotSnapshot(
      domain,
      managerScope,
      zoneId: _cropPlotZoneAId,
      zoneName: 'Luống A',
      zoneVersion: 4,
    );
    final releaseEnqueue = Completer<void>();
    final enqueueStarted = Completer<void>();
    final harness = await _pumpOverview(
      tester,
      scope: managerScope,
      domain: domain,
      enqueueDelay: releaseEnqueue.future,
      enqueueStarted: enqueueStarted,
      viewportSize: const Size(800, 844),
      overviewCopies: 2,
    );

    await _openLiveCropPlotDetails(
      tester,
      zoneId: _cropPlotZoneAId,
      overviewIndex: 0,
    );
    await tester.tap(find.byKey(_liveZoneEditNameKey).at(0));
    await tester.pumpAndSettle();
    await _openLiveCropPlotDetails(
      tester,
      zoneId: _cropPlotZoneAId,
      overviewIndex: 1,
    );
    await tester.tap(find.byKey(_liveZoneEditNameKey).at(1));
    await tester.pumpAndSettle();

    final nameFields = find.byKey(_liveZoneEditNameFieldKey);
    final saveButtons = find.byKey(_liveZoneEditNameSaveKey);
    expect(nameFields, findsNWidgets(2));
    await tester.enterText(nameFields.at(0), 'Luống A một');
    await tester.enterText(nameFields.at(1), 'Luống A hai');
    await tester.tap(saveButtons.at(0));
    await tester.pump();
    await enqueueStarted.future;

    await tester.tap(saveButtons.at(1));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 350));
    expect(
      await harness.outbox.entries(
        accountId: _accountId,
        organizationId: _organizationAId,
      ),
      isEmpty,
    );

    releaseEnqueue.complete();
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 350));

    final entries = await harness.outbox.entries(
      accountId: _accountId,
      organizationId: _organizationAId,
    );
    expect(entries, hasLength(1));
    expect(entries.single.mutation.intent.payload, {'name': 'Luống A một'});
    expect(harness.transport.calls, 0);
    expect(tester.takeException(), isNull);
  });

  for (final (roleName, organizationRole, farmRole, canRename) in [
    (
      'organization owner',
      FarmlyOrganizationRole.owner,
      FarmlyFarmGrantRole.viewer,
      true,
    ),
    (
      'organization admin',
      FarmlyOrganizationRole.admin,
      FarmlyFarmGrantRole.viewer,
      true,
    ),
    (
      'farm owner',
      FarmlyOrganizationRole.member,
      FarmlyFarmGrantRole.owner,
      true,
    ),
    (
      'farm admin',
      FarmlyOrganizationRole.member,
      FarmlyFarmGrantRole.admin,
      true,
    ),
    (
      'farm manager',
      FarmlyOrganizationRole.member,
      FarmlyFarmGrantRole.manager,
      true,
    ),
    (
      'farm worker',
      FarmlyOrganizationRole.member,
      FarmlyFarmGrantRole.worker,
      false,
    ),
    (
      'organization viewer',
      FarmlyOrganizationRole.viewer,
      FarmlyFarmGrantRole.manager,
      false,
    ),
  ]) {
    testWidgets('$roleName zone rename permission is correct', (tester) async {
      final roleScope = _scope(
        organizationId: _organizationAId,
        organizationName: 'Tổ chức A',
        farmId: _farmAId,
        farmName: 'Nông trại A',
        continuityEpoch: '37',
        selectionEpoch: 11,
        organizationRole: organizationRole,
        selectedFarmRole: farmRole,
      );
      final domain = InMemoryDomainStore();
      await _installCropPlotSnapshot(
        domain,
        roleScope,
        zoneId: _cropPlotZoneAId,
        zoneName: 'Luống A',
        zoneVersion: 1,
      );
      final harness = await _pumpOverview(
        tester,
        scope: roleScope,
        domain: domain,
      );

      await _openLiveCropPlotDetails(tester, zoneId: _cropPlotZoneAId);

      expect(
        find.byKey(_liveZoneEditNameKey),
        canRename ? findsOneWidget : findsNothing,
      );
      expect(harness.transport.calls, 0);
      expect(tester.takeException(), isNull);
    });
  }

  testWidgets('pending zone rename projects and blocks another edit', (
    tester,
  ) async {
    final managerScope = _waterTankManagerScope;
    final domain = InMemoryDomainStore();
    await _installCropPlotSnapshot(
      domain,
      managerScope,
      zoneId: _cropPlotZoneAId,
      zoneName: 'Luống A',
      zoneVersion: 4,
    );
    const operationId = 'd4d4d4d4-d4d4-44d4-84d4-d4d4d4d4d4d4';
    final outbox = InMemoryOutboxStore();
    await _queueZoneRename(
      outbox,
      managerScope,
      operationId: operationId,
      baseVersion: 4,
      name: 'Luống chờ đồng bộ',
    );
    final harness = await _pumpOverview(
      tester,
      scope: managerScope,
      domain: domain,
      outbox: outbox,
    );

    await _openLiveCropPlotDetails(tester, zoneId: _cropPlotZoneAId);

    expect(find.text('Luống chờ đồng bộ'), findsWidgets);
    expect(find.byKey(_liveZoneEditNameKey), findsNothing);
    expect(harness.transport.calls, 0);
    expect(tester.takeException(), isNull);
  });

  testWidgets('multiple unresolved zone renames fail closed', (tester) async {
    final managerScope = _waterTankManagerScope;
    final domain = InMemoryDomainStore();
    await _installCropPlotSnapshot(
      domain,
      managerScope,
      zoneId: _cropPlotZoneAId,
      zoneName: 'Luống A',
      zoneVersion: 4,
    );
    final outbox = InMemoryOutboxStore();
    await _queueZoneRename(
      outbox,
      managerScope,
      operationId: 'd4d4d4d4-d4d4-44d4-84d4-d4d4d4d4d4d4',
      baseVersion: 4,
      name: 'Luống một',
    );
    await _queueZoneRename(
      outbox,
      managerScope,
      operationId: 'd5d5d5d5-d5d5-45d5-85d5-d5d5d5d5d5d5',
      baseVersion: 4,
      name: 'Luống hai',
    );
    final harness = await _pumpOverview(
      tester,
      scope: managerScope,
      domain: domain,
      outbox: outbox,
    );

    await _openLiveCropPlotDetails(tester, zoneId: _cropPlotZoneAId);

    expect(find.text('Luống A'), findsWidgets);
    expect(find.text('Luống một'), findsNothing);
    expect(find.text('Luống hai'), findsNothing);
    expect(find.byKey(_liveZoneEditNameKey), findsNothing);
    expect(harness.transport.calls, 0);
    expect(tester.takeException(), isNull);
  });

  for (final status in [
    OutboxEntryStatus.blocked,
    OutboxEntryStatus.conflict,
  ]) {
    testWidgets('$status zone rename keeps confirmed data and locks edit', (
      tester,
    ) async {
      final managerScope = _waterTankManagerScope;
      final domain = InMemoryDomainStore();
      await _installCropPlotSnapshot(
        domain,
        managerScope,
        zoneId: _cropPlotZoneAId,
        zoneName: 'Luống A',
        zoneVersion: 4,
      );
      final outbox = InMemoryOutboxStore();
      final pending = await _queueZoneRename(
        outbox,
        managerScope,
        operationId: status == OutboxEntryStatus.blocked
            ? 'd6d6d6d6-d6d6-46d6-86d6-d6d6d6d6d6d6'
            : 'd7d7d7d7-d7d7-47d7-87d7-d7d7d7d7d7d7',
        baseVersion: 4,
        name: 'Tên cần xem lại',
      );
      await outbox.update(pending.copyWith(status: status));
      final harness = await _pumpOverview(
        tester,
        scope: managerScope,
        domain: domain,
        outbox: outbox,
      );

      await _openLiveCropPlotDetails(tester, zoneId: _cropPlotZoneAId);

      expect(find.text('Luống A'), findsWidgets);
      expect(find.text('Tên cần xem lại'), findsNothing);
      expect(find.byKey(_liveZoneEditNameKey), findsNothing);
      expect(harness.transport.calls, 0);
      expect(tester.takeException(), isNull);
    });
  }

  testWidgets('stale pending zone rename keeps confirmed name and locks edit', (
    tester,
  ) async {
    final managerScope = _waterTankManagerScope;
    final domain = InMemoryDomainStore();
    await _installCropPlotSnapshot(
      domain,
      managerScope,
      zoneId: _cropPlotZoneAId,
      zoneName: 'Luống A',
      zoneVersion: 4,
    );
    final outbox = InMemoryOutboxStore();
    await _queueZoneRename(
      outbox,
      managerScope,
      operationId: 'd8d8d8d8-d8d8-48d8-88d8-d8d8d8d8d8d8',
      baseVersion: 3,
      name: 'Tên phiên bản cũ',
    );
    final harness = await _pumpOverview(
      tester,
      scope: managerScope,
      domain: domain,
      outbox: outbox,
    );

    await _openLiveCropPlotDetails(tester, zoneId: _cropPlotZoneAId);

    expect(find.text('Luống A'), findsWidgets);
    expect(find.text('Tên phiên bản cũ'), findsNothing);
    expect(find.byKey(_liveZoneEditNameKey), findsNothing);
    expect(harness.transport.calls, 0);
    expect(tester.takeException(), isNull);
  });

  testWidgets('zone rename from another farm cannot project here', (
    tester,
  ) async {
    final managerScope = _waterTankManagerScope;
    final foreignScope = _scope(
      organizationId: _organizationAId,
      organizationName: 'Tổ chức A',
      farmId: _farmAOtherId,
      farmName: 'Nông trại A2',
      continuityEpoch: '37',
      selectionEpoch: 12,
      organizationRole: FarmlyOrganizationRole.member,
      selectedFarmRole: FarmlyFarmGrantRole.manager,
    );
    final domain = InMemoryDomainStore();
    await _installCropPlotSnapshot(
      domain,
      managerScope,
      zoneId: _cropPlotZoneAId,
      zoneName: 'Luống A',
      zoneVersion: 4,
    );
    final outbox = InMemoryOutboxStore();
    await _queueZoneRename(
      outbox,
      foreignScope,
      operationId: 'd9d9d9d9-d9d9-49d9-89d9-d9d9d9d9d9d9',
      baseVersion: 4,
      name: 'Tên từ nông trại khác',
    );
    final harness = await _pumpOverview(
      tester,
      scope: managerScope,
      domain: domain,
      outbox: outbox,
    );

    await _openLiveCropPlotDetails(tester, zoneId: _cropPlotZoneAId);

    expect(find.text('Luống A'), findsWidgets);
    expect(find.text('Tên từ nông trại khác'), findsNothing);
    expect(find.byKey(_liveZoneEditNameKey), findsOneWidget);
    expect(harness.transport.calls, 0);
    expect(tester.takeException(), isNull);
  });

  testWidgets('zone rename rejects a stale confirmed version on save', (
    tester,
  ) async {
    final managerScope = _waterTankManagerScope;
    final domain = InMemoryDomainStore();
    await _installCropPlotSnapshot(
      domain,
      managerScope,
      zoneId: _cropPlotZoneAId,
      zoneName: 'Luống A',
      zoneVersion: 4,
    );
    final harness = await _pumpOverview(
      tester,
      scope: managerScope,
      domain: domain,
    );
    await _openLiveCropPlotDetails(tester, zoneId: _cropPlotZoneAId);
    await tester.tap(find.byKey(_liveZoneEditNameKey));
    await tester.pumpAndSettle();
    await tester.enterText(find.byKey(_liveZoneEditNameFieldKey), 'Tên đã cũ');
    await _installCropPlotSnapshot(
      domain,
      managerScope,
      zoneId: _cropPlotZoneAId,
      zoneName: 'Tên mới khác',
      zoneVersion: 5,
    );

    await tester.tap(find.byKey(_liveZoneEditNameSaveKey));
    await tester.pumpAndSettle();

    expect(find.textContaining('Chưa lưu được tên vùng'), findsOneWidget);
    expect(
      await harness.outbox.entries(
        accountId: _accountId,
        organizationId: _organizationAId,
      ),
      isEmpty,
    );
    expect(harness.transport.calls, 0);
    expect(tester.takeException(), isNull);
  });

  testWidgets('zone rename form locks when the selected farm changes', (
    tester,
  ) async {
    final managerScope = _waterTankManagerScope;
    final domain = InMemoryDomainStore();
    await _installCropPlotSnapshot(
      domain,
      managerScope,
      zoneId: _cropPlotZoneAId,
      zoneName: 'Luống A',
      zoneVersion: 4,
    );
    await _installCropPlotSnapshot(
      domain,
      _scopeB,
      zoneId: _cropPlotZoneBId,
      zoneName: 'Luống B',
      zoneVersion: 4,
    );
    final harness = await _pumpOverview(
      tester,
      scope: managerScope,
      domain: domain,
    );
    await _openLiveCropPlotDetails(tester, zoneId: _cropPlotZoneAId);
    await tester.tap(find.byKey(_liveZoneEditNameKey));
    await tester.pumpAndSettle();

    harness.scopeController.replace(_scopeB);
    await tester.pumpAndSettle();

    expect(
      tester.widget<TextField>(find.byKey(_liveZoneEditNameFieldKey)).enabled,
      isFalse,
    );
    expect(
      tester
          .widget<FilledButton>(find.byKey(_liveZoneEditNameSaveKey))
          .onPressed,
      isNull,
    );
    expect(
      await harness.outbox.entries(
        accountId: _accountId,
        organizationId: _organizationAId,
      ),
      isEmpty,
    );
    expect(harness.transport.calls, 0);
    expect(tester.takeException(), isNull);
  });

  testWidgets('farm manager renames a confirmed water tank locally', (
    tester,
  ) async {
    final managerScope = _waterTankManagerScope;
    final domain = InMemoryDomainStore();
    await _installWaterZoneSnapshot(
      domain,
      managerScope,
      tanks: [_waterTankRecord()],
    );
    final harness = await _pumpOverview(
      tester,
      scope: managerScope,
      domain: domain,
    );

    await _openLiveWaterDetails(tester);
    final editButton = _liveWaterTankEditKey(_waterTankAId);
    expect(find.byKey(editButton), findsOneWidget);
    await tester.tap(find.byKey(editButton));
    await tester.pumpAndSettle();
    expect(find.byKey(_liveWaterTankEditNameKey), findsOneWidget);

    await tester.enterText(
      find.byKey(_liveWaterTankEditNameKey),
      'Bồn tưới phía đông',
    );
    await tester.tap(find.byKey(_liveWaterTankEditSaveKey));
    await tester.pumpAndSettle();

    expect(find.text(_savedPendingCopy), findsOneWidget);
    expect(find.textContaining('Bồn tưới phía đông'), findsOneWidget);
    expect(find.textContaining('Bồn chứa A'), findsNothing);
    expect(find.byKey(editButton), findsNothing);
    final entries = await harness.outbox.entries(
      accountId: _accountId,
      organizationId: _organizationAId,
    );
    expect(entries, hasLength(1));
    final update = entries.single;
    expect(update.status, OutboxEntryStatus.pending);
    expect(update.mutation.scope.organizationId, _organizationAId);
    expect(update.mutation.scope.farmId, _farmAId);
    expect(update.mutation.scope.continuityEpoch, '37');
    expect(update.mutation.intent.type, 'waterTank.update');
    expect(update.mutation.intent.resourceId, _waterTankAId);
    expect(update.mutation.intent.baseVersion, 4);
    expect(update.mutation.intent.payload, {'name': 'Bồn tưới phía đông'});
    expect(harness.transport.calls, 0);
    expect(tester.takeException(), isNull);
  });

  for (final (roleName, organizationRole, farmRole, canRename) in [
    (
      'organization owner',
      FarmlyOrganizationRole.owner,
      FarmlyFarmGrantRole.viewer,
      true,
    ),
    (
      'organization admin',
      FarmlyOrganizationRole.admin,
      FarmlyFarmGrantRole.viewer,
      true,
    ),
    (
      'farm manager',
      FarmlyOrganizationRole.member,
      FarmlyFarmGrantRole.manager,
      true,
    ),
    (
      'farm worker',
      FarmlyOrganizationRole.member,
      FarmlyFarmGrantRole.worker,
      false,
    ),
    (
      'organization viewer',
      FarmlyOrganizationRole.viewer,
      FarmlyFarmGrantRole.manager,
      false,
    ),
  ]) {
    testWidgets('$roleName water-tank rename permission is correct', (
      tester,
    ) async {
      final roleScope = _scope(
        organizationId: _organizationAId,
        organizationName: 'Tổ chức A',
        farmId: _farmAId,
        farmName: 'Nông trại A',
        continuityEpoch: '37',
        selectionEpoch: 11,
        organizationRole: organizationRole,
        selectedFarmRole: farmRole,
      );
      final domain = InMemoryDomainStore();
      await _installWaterZoneSnapshot(
        domain,
        roleScope,
        tanks: [_waterTankRecord()],
      );
      final harness = await _pumpOverview(
        tester,
        scope: roleScope,
        domain: domain,
      );

      await _openLiveWaterDetails(tester);

      expect(
        find.byKey(_liveWaterTankEditKey(_waterTankAId)),
        canRename ? findsOneWidget : findsNothing,
      );
      expect(harness.transport.calls, 0);
      expect(tester.takeException(), isNull);
    });
  }

  testWidgets('pending tank rename projects and blocks a second update', (
    tester,
  ) async {
    final managerScope = _waterTankManagerScope;
    final domain = InMemoryDomainStore();
    await _installWaterZoneSnapshot(
      domain,
      managerScope,
      tanks: [_waterTankRecord(version: 2)],
    );
    final outbox = InMemoryOutboxStore();
    await _queueWaterTankRename(
      outbox,
      managerScope,
      operationId: '20202020-2020-4020-8020-202020202020',
      name: 'Bồn đã đổi tên',
      baseVersion: 2,
    );
    final harness = await _pumpOverview(
      tester,
      scope: managerScope,
      domain: domain,
      outbox: outbox,
    );

    await _openLiveWaterDetails(tester);

    expect(find.textContaining('Bồn đã đổi tên'), findsOneWidget);
    expect(find.textContaining('Bồn chứa A'), findsNothing);
    expect(find.byKey(_liveWaterTankEditKey(_waterTankAId)), findsNothing);
    expect(harness.transport.calls, 0);
    expect(tester.takeException(), isNull);
  });

  testWidgets('pending tank-create row cannot be renamed before confirmation', (
    tester,
  ) async {
    final managerScope = _waterTankManagerScope;
    final domain = InMemoryDomainStore();
    await _installWaterZoneSnapshot(domain, managerScope);
    final outbox = InMemoryOutboxStore();
    await outbox.enqueue(
      FarmlyScopedMutation(
        scope: FarmlyMutationScope.farm(
          accountId: _accountId,
          organizationId: _organizationAId,
          farmId: _farmAId,
          continuityEpoch: '37',
        ),
        intent: FarmlyCreateWaterTankIntent(
          operationId: '21212121-2121-4121-8121-212121212121',
          continuityEpoch: '37',
          resourceId: '23232323-2323-4323-8323-232323232323',
          name: 'Bồn mới đang chờ',
          zoneId: _waterZoneAId,
          capacityLitres: '500',
        ),
      ),
    );
    final harness = await _pumpOverview(
      tester,
      scope: managerScope,
      domain: domain,
      outbox: outbox,
    );

    await _openLiveWaterDetails(tester);

    expect(find.textContaining('Bồn mới đang chờ'), findsOneWidget);
    expect(
      find.byKey(
        const ValueKey(
          'live-water-tank-edit-23232323-2323-4323-8323-232323232323',
        ),
      ),
      findsNothing,
    );
    expect(harness.transport.calls, 0);
    expect(tester.takeException(), isNull);
  });

  testWidgets('rename for another farm does not project into this tank row', (
    tester,
  ) async {
    final managerScope = _waterTankManagerScope;
    final foreignScope = _scope(
      organizationId: _organizationAId,
      organizationName: 'Tổ chức A',
      farmId: _farmAOtherId,
      farmName: 'Nông trại A2',
      continuityEpoch: '37',
      selectionEpoch: 12,
      organizationRole: FarmlyOrganizationRole.member,
      selectedFarmRole: FarmlyFarmGrantRole.manager,
    );
    final domain = InMemoryDomainStore();
    await _installWaterZoneSnapshot(
      domain,
      managerScope,
      tanks: [_waterTankRecord(version: 2)],
    );
    final outbox = InMemoryOutboxStore();
    await _queueWaterTankRename(
      outbox,
      foreignScope,
      operationId: '24242424-2424-4424-8424-242424242424',
      name: 'Tên ở nông trại khác',
      baseVersion: 2,
    );
    final harness = await _pumpOverview(
      tester,
      scope: managerScope,
      domain: domain,
      outbox: outbox,
    );

    await _openLiveWaterDetails(tester);

    expect(find.textContaining('Bồn chứa A'), findsOneWidget);
    expect(find.textContaining('Tên ở nông trại khác'), findsNothing);
    expect(find.byKey(_liveWaterTankEditKey(_waterTankAId)), findsOneWidget);
    expect(harness.transport.calls, 0);
    expect(tester.takeException(), isNull);
  });

  testWidgets('conflicted tank rename keeps confirmed name and locks edit', (
    tester,
  ) async {
    final managerScope = _waterTankManagerScope;
    final domain = InMemoryDomainStore();
    await _installWaterZoneSnapshot(
      domain,
      managerScope,
      tanks: [_waterTankRecord(version: 2)],
    );
    final outbox = InMemoryOutboxStore();
    final pending = await _queueWaterTankRename(
      outbox,
      managerScope,
      operationId: '25252525-2525-4525-8525-252525252525',
      name: 'Bồn bị xung đột',
      baseVersion: 2,
    );
    await outbox.update(pending.copyWith(status: OutboxEntryStatus.conflict));
    final harness = await _pumpOverview(
      tester,
      scope: managerScope,
      domain: domain,
      outbox: outbox,
    );

    await _openLiveWaterDetails(tester);

    expect(find.textContaining('Bồn chứa A'), findsOneWidget);
    expect(find.textContaining('Bồn bị xung đột'), findsNothing);
    expect(find.byKey(_liveWaterTankEditKey(_waterTankAId)), findsNothing);
    expect(harness.transport.calls, 0);
    expect(tester.takeException(), isNull);
  });

  testWidgets('multiple unresolved tank renames fail closed', (tester) async {
    final managerScope = _waterTankManagerScope;
    final domain = InMemoryDomainStore();
    await _installWaterZoneSnapshot(
      domain,
      managerScope,
      tanks: [_waterTankRecord(version: 2)],
    );
    final outbox = InMemoryOutboxStore();
    for (final (operationId, proposedName) in [
      ('26262626-2626-4626-8626-262626262626', 'Bồn đổi tên thứ nhất'),
      ('27272727-2727-4727-8727-272727272727', 'Bồn đổi tên thứ hai'),
    ]) {
      await _queueWaterTankRename(
        outbox,
        managerScope,
        operationId: operationId,
        name: proposedName,
        baseVersion: 2,
      );
    }
    final harness = await _pumpOverview(
      tester,
      scope: managerScope,
      domain: domain,
      outbox: outbox,
    );

    await _openLiveWaterDetails(tester);

    expect(find.textContaining('Bồn chứa A'), findsOneWidget);
    expect(find.textContaining('Bồn đổi tên thứ nhất'), findsNothing);
    expect(find.textContaining('Bồn đổi tên thứ hai'), findsNothing);
    expect(find.byKey(_liveWaterTankEditKey(_waterTankAId)), findsNothing);
    expect(harness.transport.calls, 0);
    expect(tester.takeException(), isNull);
  });

  testWidgets('tank rename rejects a stale confirmed version on save', (
    tester,
  ) async {
    final managerScope = _waterTankManagerScope;
    final domain = InMemoryDomainStore();
    await _installWaterZoneSnapshot(
      domain,
      managerScope,
      tanks: [_waterTankRecord(version: 2)],
    );
    final harness = await _pumpOverview(
      tester,
      scope: managerScope,
      domain: domain,
    );
    await _openLiveWaterDetails(tester);
    await tester.tap(find.byKey(_liveWaterTankEditKey(_waterTankAId)));
    await tester.pumpAndSettle();
    await tester.enterText(
      find.byKey(_liveWaterTankEditNameKey),
      'Bồn nhập tên cũ',
    );
    await _installWaterZoneSnapshot(
      domain,
      managerScope,
      tanks: [
        _waterTankRecord(version: 3, name: 'Bồn vừa cập nhật trên máy chủ'),
      ],
    );

    await tester.tap(find.byKey(_liveWaterTankEditSaveKey));
    await tester.pumpAndSettle();

    expect(find.text(_savedPendingCopy), findsNothing);
    expect(
      await harness.outbox.entries(
        accountId: _accountId,
        organizationId: _organizationAId,
      ),
      isEmpty,
    );
    expect(harness.transport.calls, 0);
    expect(tester.takeException(), isNull);
  });

  testWidgets('tank rename rejects a stale water-zone version on save', (
    tester,
  ) async {
    final managerScope = _waterTankManagerScope;
    final domain = InMemoryDomainStore();
    await _installWaterZoneSnapshot(
      domain,
      managerScope,
      tanks: [_waterTankRecord(version: 2)],
    );
    final harness = await _pumpOverview(
      tester,
      scope: managerScope,
      domain: domain,
    );
    await _openLiveWaterDetails(tester);
    await tester.tap(find.byKey(_liveWaterTankEditKey(_waterTankAId)));
    await tester.pumpAndSettle();
    await tester.enterText(
      find.byKey(_liveWaterTankEditNameKey),
      'Bồn theo vùng cũ',
    );
    await _installWaterZoneSnapshot(
      domain,
      managerScope,
      zoneVersion: 2,
      tanks: [_waterTankRecord(version: 2)],
    );

    await tester.tap(find.byKey(_liveWaterTankEditSaveKey));
    await tester.pumpAndSettle();

    expect(find.text(_savedPendingCopy), findsNothing);
    expect(
      await harness.outbox.entries(
        accountId: _accountId,
        organizationId: _organizationAId,
      ),
      isEmpty,
    );
    expect(harness.transport.calls, 0);
    expect(tester.takeException(), isNull);
  });

  testWidgets('water-tank rename form locks when the selected farm changes', (
    tester,
  ) async {
    final managerScope = _waterTankManagerScope;
    final domain = InMemoryDomainStore();
    await _installWaterZoneSnapshot(
      domain,
      managerScope,
      tanks: [_waterTankRecord(version: 2)],
    );
    final harness = await _pumpOverview(
      tester,
      scope: managerScope,
      domain: domain,
    );
    await _openLiveWaterDetails(tester);
    await tester.tap(find.byKey(_liveWaterTankEditKey(_waterTankAId)));
    await tester.pumpAndSettle();

    harness.scopeController.replace(_scopeB);
    await tester.pumpAndSettle();

    expect(
      tester.widget<TextField>(find.byKey(_liveWaterTankEditNameKey)).enabled,
      isFalse,
    );
    expect(
      tester
          .widget<FilledButton>(find.byKey(_liveWaterTankEditSaveKey))
          .onPressed,
      isNull,
    );
    expect(
      await harness.outbox.entries(
        accountId: _accountId,
        organizationId: _organizationAId,
      ),
      isEmpty,
    );
    expect(harness.transport.calls, 0);
    expect(tester.takeException(), isNull);
  });

  testWidgets('farm manager renames confirmed crop species locally', (
    tester,
  ) async {
    final managerScope = _scope(
      organizationId: _organizationAId,
      organizationName: 'Tổ chức A',
      farmId: _farmAId,
      farmName: 'Nông trại A',
      continuityEpoch: '37',
      selectionEpoch: 11,
      organizationRole: FarmlyOrganizationRole.member,
      selectedFarmRole: FarmlyFarmGrantRole.manager,
    );
    final domain = InMemoryDomainStore();
    await _installCropPlotSnapshot(
      domain,
      managerScope,
      zoneId: _cropPlotZoneAId,
      zoneName: 'Luống A',
      cropSpecies: const [
        {
          'id': _cropSpeciesAId,
          'version': 4,
          'name': 'Cà chua bi',
          'harvestUnit': 'kg',
          'status': 'active',
        },
      ],
    );
    final harness = await _pumpOverview(
      tester,
      scope: managerScope,
      domain: domain,
    );

    await _openLiveCropPlotDetails(tester, zoneId: _cropPlotZoneAId);
    final editButton = _liveCropSpeciesEditKey(_cropSpeciesAId);
    expect(find.byKey(editButton), findsOneWidget);
    await tester.tap(find.byKey(editButton));
    await tester.pumpAndSettle();
    expect(find.byKey(_liveCropSpeciesEditNameKey), findsOneWidget);

    await tester.enterText(
      find.byKey(_liveCropSpeciesEditNameKey),
      'Cà chua hữu cơ',
    );
    await tester.tap(find.byKey(_liveCropSpeciesEditSaveKey));
    await tester.pumpAndSettle();

    expect(find.text(_savedPendingCopy), findsOneWidget);
    expect(find.textContaining('Cà chua hữu cơ'), findsOneWidget);
    expect(find.textContaining('Cà chua bi'), findsNothing);
    expect(find.byKey(editButton), findsNothing);
    final entries = await harness.outbox.entries(
      accountId: _accountId,
      organizationId: _organizationAId,
    );
    expect(entries, hasLength(1));
    final update = entries.single;
    expect(update.status, OutboxEntryStatus.pending);
    expect(update.mutation.scope.farmId, _farmAId);
    expect(update.mutation.intent.type, 'cropSpecies.update');
    expect(update.mutation.intent.resourceId, _cropSpeciesAId);
    expect(update.mutation.intent.baseVersion, 4);
    expect(update.mutation.intent.payload, {'name': 'Cà chua hữu cơ'});
    expect(harness.transport.calls, 0);
    expect(tester.takeException(), isNull);
  });

  testWidgets(
    'crop species archive requires confirmation and enqueues locally',
    (tester) async {
      final managerScope = _scope(
        organizationId: _organizationAId,
        organizationName: 'Tổ chức A',
        farmId: _farmAId,
        farmName: 'Nông trại A',
        continuityEpoch: '37',
        selectionEpoch: 11,
        organizationRole: FarmlyOrganizationRole.member,
        selectedFarmRole: FarmlyFarmGrantRole.manager,
      );
      final domain = InMemoryDomainStore();
      await _installCropPlotSnapshot(
        domain,
        managerScope,
        zoneId: _cropPlotZoneAId,
        zoneName: 'Luống A',
        cropSpecies: const [
          {
            'id': _cropSpeciesAId,
            'version': 4,
            'name': 'Cà chua bi',
            'harvestUnit': 'kg',
            'status': 'active',
          },
        ],
        plantings: const [
          {
            'id': _plantingAId,
            'version': 2,
            'cropSpeciesId': _cropSpeciesAId,
            'plotId': _cropPlotZoneAId,
            'status': 'active',
            'sowingDate': '2026-10-01',
          },
        ],
      );
      final harness = await _pumpOverview(
        tester,
        scope: managerScope,
        domain: domain,
      );

      await _openLiveCropPlotDetails(tester, zoneId: _cropPlotZoneAId);
      await tester.tap(find.byKey(_liveCropSpeciesArchiveKey(_cropSpeciesAId)));
      await tester.pumpAndSettle();

      expect(find.byKey(_liveCropSpeciesArchiveDialogKey), findsOneWidget);
      expect(find.text('Lưu trữ loại cây này?'), findsOneWidget);
      expect(find.textContaining('Cà chua bi'), findsWidgets);
      expect(find.byKey(_liveCropSpeciesArchiveCancelKey), findsOneWidget);
      expect(find.byKey(_liveCropSpeciesArchiveConfirmKey), findsOneWidget);

      await tester.tap(find.byKey(_liveCropSpeciesArchiveConfirmKey));
      await tester.pumpAndSettle();

      final entries = await harness.outbox.entries(
        accountId: _accountId,
        organizationId: _organizationAId,
      );
      expect(entries, hasLength(1));
      final archive = entries.single;
      expect(archive.status, OutboxEntryStatus.pending);
      expect(archive.mutation.scope.accountId, _accountId);
      expect(archive.mutation.scope.organizationId, _organizationAId);
      expect(archive.mutation.scope.farmId, _farmAId);
      expect(archive.mutation.intent.type, 'cropSpecies.archive');
      expect(archive.mutation.intent.resourceId, _cropSpeciesAId);
      expect(archive.mutation.intent.baseVersion, 4);
      expect(archive.mutation.intent.payload, isEmpty);
      expect(find.text('Đang chờ lưu trữ'), findsOneWidget);
      expect(
        find.byKey(_liveCropSpeciesArchiveKey(_cropSpeciesAId)),
        findsNothing,
      );
      expect(
        find.byKey(_liveCropSpeciesEditKey(_cropSpeciesAId)),
        findsNothing,
      );
      expect(
        find.byKey(const ValueKey('live-planting-row-$_plantingAId')),
        findsOneWidget,
      );
      expect(find.textContaining('Cà chua bi'), findsWidgets);
      expect(
        tester
            .widget<FilledButton>(
              find.byKey(const ValueKey('live-planting-create')),
            )
            .onPressed,
        isNull,
      );
      expect(harness.transport.calls, 0);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets('cancelled crop species archive creates no outbox intent', (
    tester,
  ) async {
    final domain = InMemoryDomainStore();
    await _installCropPlotSnapshot(
      domain,
      _scopeA,
      zoneId: _cropPlotZoneAId,
      zoneName: 'Luống A',
      cropSpecies: const [
        {
          'id': _cropSpeciesAId,
          'version': 1,
          'name': 'Cà chua bi',
          'harvestUnit': 'kg',
          'status': 'active',
        },
      ],
    );
    final harness = await _pumpOverview(tester, scope: _scopeA, domain: domain);

    await _openLiveCropPlotDetails(tester, zoneId: _cropPlotZoneAId);
    await tester.tap(find.byKey(_liveCropSpeciesArchiveKey(_cropSpeciesAId)));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(_liveCropSpeciesArchiveCancelKey));
    await tester.pumpAndSettle();

    expect(find.byKey(_liveCropSpeciesArchiveDialogKey), findsNothing);
    expect(
      find.byKey(_liveCropSpeciesArchiveKey(_cropSpeciesAId)),
      findsOneWidget,
    );
    expect(
      await harness.outbox.entries(
        accountId: _accountId,
        organizationId: _organizationAId,
      ),
      isEmpty,
    );
    expect(harness.transport.calls, 0);
    expect(tester.takeException(), isNull);
  });

  testWidgets('archived species remains in planting history, not new choices', (
    tester,
  ) async {
    final domain = InMemoryDomainStore();
    await _installCropPlotSnapshot(
      domain,
      _scopeA,
      zoneId: _cropPlotZoneAId,
      zoneName: 'Luống A',
      cropSpecies: const [
        {
          'id': _cropSpeciesAId,
          'version': 5,
          'name': 'Cà chua bi',
          'harvestUnit': 'kg',
          'status': 'archived',
        },
      ],
      plantings: const [
        {
          'id': _plantingAId,
          'version': 2,
          'cropSpeciesId': _cropSpeciesAId,
          'plotId': _cropPlotZoneAId,
          'status': 'active',
          'sowingDate': '2026-10-01',
        },
      ],
    );
    final harness = await _pumpOverview(tester, scope: _scopeA, domain: domain);

    await _openLiveCropPlotDetails(tester, zoneId: _cropPlotZoneAId);

    expect(find.textContaining('Cà chua bi'), findsNWidgets(2));
    expect(find.text('Đã lưu trữ'), findsOneWidget);
    expect(
      find.byKey(_liveCropSpeciesArchiveKey(_cropSpeciesAId)),
      findsNothing,
    );
    expect(find.byKey(_liveCropSpeciesEditKey(_cropSpeciesAId)), findsNothing);
    expect(
      tester
          .widget<FilledButton>(
            find.byKey(const ValueKey('live-planting-create')),
          )
          .onPressed,
      isNull,
    );
    expect(harness.transport.calls, 0);
    expect(tester.takeException(), isNull);
  });

  for (final (roleName, organizationRole, farmRole, canArchive) in [
    (
      'organization owner',
      FarmlyOrganizationRole.owner,
      FarmlyFarmGrantRole.viewer,
      true,
    ),
    (
      'organization admin',
      FarmlyOrganizationRole.admin,
      FarmlyFarmGrantRole.viewer,
      true,
    ),
    (
      'farm manager',
      FarmlyOrganizationRole.member,
      FarmlyFarmGrantRole.manager,
      true,
    ),
    (
      'farm worker',
      FarmlyOrganizationRole.member,
      FarmlyFarmGrantRole.worker,
      false,
    ),
    (
      'organization viewer',
      FarmlyOrganizationRole.viewer,
      FarmlyFarmGrantRole.manager,
      false,
    ),
  ]) {
    testWidgets('$roleName crop-species archive permission is correct', (
      tester,
    ) async {
      final roleScope = _scope(
        organizationId: _organizationAId,
        organizationName: 'Tổ chức A',
        farmId: _farmAId,
        farmName: 'Nông trại A',
        continuityEpoch: '37',
        selectionEpoch: 11,
        organizationRole: organizationRole,
        selectedFarmRole: farmRole,
      );
      final domain = InMemoryDomainStore();
      await _installCropPlotSnapshot(
        domain,
        roleScope,
        zoneId: _cropPlotZoneAId,
        zoneName: 'Luống A',
        cropSpecies: const [
          {
            'id': _cropSpeciesAId,
            'version': 1,
            'name': 'Cà chua bi',
            'harvestUnit': 'kg',
            'status': 'active',
          },
        ],
      );
      final harness = await _pumpOverview(
        tester,
        scope: roleScope,
        domain: domain,
      );

      await _openLiveCropPlotDetails(tester, zoneId: _cropPlotZoneAId);

      expect(
        find.byKey(_liveCropSpeciesArchiveKey(_cropSpeciesAId)),
        canArchive ? findsOneWidget : findsNothing,
      );
      expect(harness.transport.calls, 0);
      expect(tester.takeException(), isNull);
    });
  }

  testWidgets('stale crop species archive is rejected after confirmation', (
    tester,
  ) async {
    final managerScope = _scope(
      organizationId: _organizationAId,
      organizationName: 'Tổ chức A',
      farmId: _farmAId,
      farmName: 'Nông trại A',
      continuityEpoch: '37',
      selectionEpoch: 11,
      organizationRole: FarmlyOrganizationRole.member,
      selectedFarmRole: FarmlyFarmGrantRole.manager,
    );
    final domain = InMemoryDomainStore();
    await _installCropPlotSnapshot(
      domain,
      managerScope,
      zoneId: _cropPlotZoneAId,
      zoneName: 'Luống A',
      cropSpecies: const [
        {
          'id': _cropSpeciesAId,
          'version': 4,
          'name': 'Cà chua bi',
          'harvestUnit': 'kg',
          'status': 'active',
        },
      ],
    );
    final harness = await _pumpOverview(
      tester,
      scope: managerScope,
      domain: domain,
    );

    await _openLiveCropPlotDetails(tester, zoneId: _cropPlotZoneAId);
    await tester.tap(find.byKey(_liveCropSpeciesArchiveKey(_cropSpeciesAId)));
    await tester.pumpAndSettle();
    await _installCropPlotSnapshot(
      domain,
      managerScope,
      zoneId: _cropPlotZoneAId,
      zoneName: 'Luống A',
      cropSpecies: const [
        {
          'id': _cropSpeciesAId,
          'version': 5,
          'name': 'Cà chua mới',
          'harvestUnit': 'kg',
          'status': 'active',
        },
      ],
    );

    await tester.tap(find.byKey(_liveCropSpeciesArchiveConfirmKey));
    await tester.pumpAndSettle();

    expect(find.textContaining('Chưa lưu trữ được loại cây'), findsOneWidget);
    expect(
      await harness.outbox.entries(
        accountId: _accountId,
        organizationId: _organizationAId,
      ),
      isEmpty,
    );
    expect(harness.transport.calls, 0);
    expect(tester.takeException(), isNull);
  });

  testWidgets('crop species archive confirmation rejects a farm switch', (
    tester,
  ) async {
    final managerScope = _scope(
      organizationId: _organizationAId,
      organizationName: 'Tổ chức A',
      farmId: _farmAId,
      farmName: 'Nông trại A',
      continuityEpoch: '37',
      selectionEpoch: 11,
      organizationRole: FarmlyOrganizationRole.member,
      selectedFarmRole: FarmlyFarmGrantRole.manager,
    );
    final domain = InMemoryDomainStore();
    await _installCropPlotSnapshot(
      domain,
      managerScope,
      zoneId: _cropPlotZoneAId,
      zoneName: 'Luống A',
      cropSpecies: const [
        {
          'id': _cropSpeciesAId,
          'version': 3,
          'name': 'Cà chua bi',
          'harvestUnit': 'kg',
          'status': 'active',
        },
      ],
    );
    final harness = await _pumpOverview(
      tester,
      scope: managerScope,
      domain: domain,
    );
    await _openLiveCropPlotDetails(tester, zoneId: _cropPlotZoneAId);
    await tester.tap(find.byKey(_liveCropSpeciesArchiveKey(_cropSpeciesAId)));
    await tester.pumpAndSettle();

    harness.scopeController.replace(_scopeB);
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(_liveCropSpeciesArchiveConfirmKey));
    await tester.pumpAndSettle();

    expect(find.textContaining('Chưa lưu trữ được loại cây'), findsOneWidget);
    expect(
      await harness.outbox.entries(
        accountId: _accountId,
        organizationId: _organizationAId,
      ),
      isEmpty,
    );
    expect(harness.transport.calls, 0);
    expect(tester.takeException(), isNull);
  });

  testWidgets('unresolved species archive states fail closed', (tester) async {
    for (final scenario in [
      (
        name: 'stale base',
        baseVersion: 2,
        count: 1,
        status: OutboxEntryStatus.pending,
      ),
      (
        name: 'conflict',
        baseVersion: 3,
        count: 1,
        status: OutboxEntryStatus.conflict,
      ),
      (
        name: 'blocked',
        baseVersion: 3,
        count: 1,
        status: OutboxEntryStatus.blocked,
      ),
      (
        name: 'duplicate intents',
        baseVersion: 3,
        count: 2,
        status: OutboxEntryStatus.pending,
      ),
    ]) {
      final domain = InMemoryDomainStore();
      await _installCropPlotSnapshot(
        domain,
        _scopeA,
        zoneId: _cropPlotZoneAId,
        zoneName: 'Luống A',
        cropSpecies: const [
          {
            'id': _cropSpeciesAId,
            'version': 3,
            'name': 'Cà chua bi',
            'harvestUnit': 'kg',
            'status': 'active',
          },
        ],
      );
      final outbox = InMemoryOutboxStore();
      final firstEntry = await _queueCropSpeciesArchive(
        outbox,
        _scopeA,
        operationId: _cropSpeciesArchiveOperationId,
        baseVersion: scenario.baseVersion,
      );
      if (scenario.status != OutboxEntryStatus.pending) {
        await outbox.update(firstEntry.copyWith(status: scenario.status));
      }
      if (scenario.count == 2) {
        final duplicate = await _queueCropSpeciesArchive(
          outbox,
          _scopeA,
          operationId: _cropSpeciesArchiveDuplicateOperationId,
          baseVersion: scenario.baseVersion,
        );
        if (scenario.status != OutboxEntryStatus.pending) {
          await outbox.update(duplicate.copyWith(status: scenario.status));
        }
      }
      final harness = await _pumpOverview(
        tester,
        scope: _scopeA,
        domain: domain,
        outbox: outbox,
      );

      await _openLiveCropPlotDetails(tester, zoneId: _cropPlotZoneAId);

      expect(
        find.textContaining('Cà chua bi'),
        findsOneWidget,
        reason: scenario.name,
      );
      expect(find.text('Đã lưu trữ'), findsNothing, reason: scenario.name);
      expect(
        find.byKey(_liveCropSpeciesArchiveKey(_cropSpeciesAId)),
        findsNothing,
      );
      expect(
        find.byKey(_liveCropSpeciesEditKey(_cropSpeciesAId)),
        findsNothing,
      );
      expect(harness.transport.calls, 0, reason: scenario.name);
      expect(tester.takeException(), isNull, reason: scenario.name);
      await tester.pumpWidget(const SizedBox.shrink());
    }
  });

  testWidgets(
    'concurrent species rename and archive enqueue only one mutation',
    (tester) async {
      final managerScope = _scope(
        organizationId: _organizationAId,
        organizationName: 'Tổ chức A',
        farmId: _farmAId,
        farmName: 'Nông trại A',
        continuityEpoch: '37',
        selectionEpoch: 11,
        organizationRole: FarmlyOrganizationRole.member,
        selectedFarmRole: FarmlyFarmGrantRole.manager,
      );
      final domain = InMemoryDomainStore();
      await _installCropPlotSnapshot(
        domain,
        managerScope,
        zoneId: _cropPlotZoneAId,
        zoneName: 'Luống A',
        cropSpecies: const [
          {
            'id': _cropSpeciesAId,
            'version': 4,
            'name': 'Cà chua bi',
            'harvestUnit': 'kg',
            'status': 'active',
          },
        ],
      );
      final releaseEnqueue = Completer<void>();
      final enqueueStarted = Completer<void>();
      final harness = await _pumpOverview(
        tester,
        scope: managerScope,
        domain: domain,
        enqueueDelay: releaseEnqueue.future,
        enqueueStarted: enqueueStarted,
        viewportSize: const Size(800, 844),
        overviewCopies: 2,
      );

      await _openLiveCropPlotDetails(
        tester,
        zoneId: _cropPlotZoneAId,
        overviewIndex: 0,
      );
      await tester.tap(
        find.byKey(_liveCropSpeciesArchiveKey(_cropSpeciesAId)).at(0),
      );
      await tester.pumpAndSettle();
      await _openLiveCropPlotDetails(
        tester,
        zoneId: _cropPlotZoneAId,
        overviewIndex: 1,
      );
      await tester.tap(
        find.byKey(_liveCropSpeciesEditKey(_cropSpeciesAId)).at(1),
      );
      await tester.pumpAndSettle();
      await tester.enterText(
        find.byKey(_liveCropSpeciesEditNameKey),
        'Cà chua mới',
      );
      await tester.tap(find.byKey(_liveCropSpeciesArchiveConfirmKey));
      await tester.pump();
      await enqueueStarted.future;

      await tester.tap(find.byKey(_liveCropSpeciesEditSaveKey));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 350));
      expect(
        await harness.outbox.entries(
          accountId: _accountId,
          organizationId: _organizationAId,
        ),
        isEmpty,
      );

      releaseEnqueue.complete();
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 350));

      final entries = await harness.outbox.entries(
        accountId: _accountId,
        organizationId: _organizationAId,
      );
      expect(entries, hasLength(1));
      expect(entries.single.mutation.intent.type, 'cropSpecies.archive');
      expect(entries.single.mutation.intent.baseVersion, 4);
      expect(entries.single.mutation.intent.payload, isEmpty);
      expect(harness.transport.calls, 0);
      expect(tester.takeException(), isNull);
    },
  );

  for (final (roleName, organizationRole, farmRole, canRename) in [
    (
      'organization owner',
      FarmlyOrganizationRole.owner,
      FarmlyFarmGrantRole.viewer,
      true,
    ),
    (
      'organization admin',
      FarmlyOrganizationRole.admin,
      FarmlyFarmGrantRole.viewer,
      true,
    ),
    (
      'farm manager',
      FarmlyOrganizationRole.member,
      FarmlyFarmGrantRole.manager,
      true,
    ),
    (
      'farm worker',
      FarmlyOrganizationRole.member,
      FarmlyFarmGrantRole.worker,
      false,
    ),
    (
      'organization viewer',
      FarmlyOrganizationRole.viewer,
      FarmlyFarmGrantRole.manager,
      false,
    ),
  ]) {
    testWidgets('$roleName crop-species rename permission is correct', (
      tester,
    ) async {
      final roleScope = _scope(
        organizationId: _organizationAId,
        organizationName: 'Tổ chức A',
        farmId: _farmAId,
        farmName: 'Nông trại A',
        continuityEpoch: '37',
        selectionEpoch: 11,
        organizationRole: organizationRole,
        selectedFarmRole: farmRole,
      );
      final domain = InMemoryDomainStore();
      await _installCropPlotSnapshot(
        domain,
        roleScope,
        zoneId: _cropPlotZoneAId,
        zoneName: 'Luống A',
        cropSpecies: const [
          {
            'id': _cropSpeciesAId,
            'version': 1,
            'name': 'Cà chua bi',
            'harvestUnit': 'kg',
            'status': 'active',
          },
        ],
      );
      final harness = await _pumpOverview(
        tester,
        scope: roleScope,
        domain: domain,
      );

      await _openLiveCropPlotDetails(tester, zoneId: _cropPlotZoneAId);

      expect(
        find.byKey(_liveCropSpeciesEditKey(_cropSpeciesAId)),
        canRename ? findsOneWidget : findsNothing,
      );
      expect(harness.transport.calls, 0);
      expect(tester.takeException(), isNull);
    });
  }

  testWidgets('unresolved species rename projects locally and blocks another', (
    tester,
  ) async {
    final managerScope = _scope(
      organizationId: _organizationAId,
      organizationName: 'Tổ chức A',
      farmId: _farmAId,
      farmName: 'Nông trại A',
      continuityEpoch: '37',
      selectionEpoch: 11,
      organizationRole: FarmlyOrganizationRole.member,
      selectedFarmRole: FarmlyFarmGrantRole.manager,
    );
    final domain = InMemoryDomainStore();
    await _installCropPlotSnapshot(
      domain,
      managerScope,
      zoneId: _cropPlotZoneAId,
      zoneName: 'Luống A',
      cropSpecies: const [
        {
          'id': _cropSpeciesAId,
          'version': 2,
          'name': 'Cà chua bi',
          'harvestUnit': 'kg',
          'status': 'active',
        },
      ],
    );
    const operationId = 'd2d2d2d2-d2d2-42d2-82d2-d2d2d2d2d2d2';
    final outbox = InMemoryOutboxStore();
    await outbox.enqueue(
      FarmlyScopedMutation(
        scope: FarmlyMutationScope.farm(
          accountId: _accountId,
          organizationId: _organizationAId,
          farmId: _farmAId,
          continuityEpoch: '37',
        ),
        intent: FarmlyUpdateCropSpeciesNameIntent(
          operationId: operationId,
          continuityEpoch: '37',
          resourceId: _cropSpeciesAId,
          baseVersion: 2,
          name: 'Cà chua đỏ',
        ),
      ),
    );
    final harness = await _pumpOverview(
      tester,
      scope: managerScope,
      domain: domain,
      outbox: outbox,
    );

    await _openLiveCropPlotDetails(tester, zoneId: _cropPlotZoneAId);

    expect(find.textContaining('Cà chua đỏ'), findsOneWidget);
    expect(find.textContaining('Cà chua bi'), findsNothing);
    expect(find.byKey(_liveCropSpeciesEditKey(_cropSpeciesAId)), findsNothing);
    expect(harness.transport.calls, 0);
    expect(tester.takeException(), isNull);
  });

  testWidgets('species rename from another farm cannot affect this list', (
    tester,
  ) async {
    final managerScope = _scope(
      organizationId: _organizationAId,
      organizationName: 'Tổ chức A',
      farmId: _farmAId,
      farmName: 'Nông trại A',
      continuityEpoch: '37',
      selectionEpoch: 11,
      organizationRole: FarmlyOrganizationRole.member,
      selectedFarmRole: FarmlyFarmGrantRole.manager,
    );
    final domain = InMemoryDomainStore();
    await _installCropPlotSnapshot(
      domain,
      managerScope,
      zoneId: _cropPlotZoneAId,
      zoneName: 'Luống A',
      cropSpecies: const [
        {
          'id': _cropSpeciesAId,
          'version': 2,
          'name': 'Cà chua bi',
          'harvestUnit': 'kg',
          'status': 'active',
        },
      ],
    );
    final outbox = InMemoryOutboxStore();
    await outbox.enqueue(
      FarmlyScopedMutation(
        scope: FarmlyMutationScope.farm(
          accountId: _accountId,
          organizationId: _organizationAId,
          farmId: _farmAOtherId,
          continuityEpoch: '37',
        ),
        intent: FarmlyUpdateCropSpeciesNameIntent(
          operationId: 'd3d3d3d3-d3d3-43d3-83d3-d3d3d3d3d3d3',
          continuityEpoch: '37',
          resourceId: _cropSpeciesAId,
          baseVersion: 2,
          name: 'Tên thuộc nông trại khác',
        ),
      ),
    );
    final harness = await _pumpOverview(
      tester,
      scope: managerScope,
      domain: domain,
      outbox: outbox,
    );

    await _openLiveCropPlotDetails(tester, zoneId: _cropPlotZoneAId);

    expect(find.textContaining('Cà chua bi'), findsOneWidget);
    expect(find.textContaining('Tên thuộc nông trại khác'), findsNothing);
    expect(
      find.byKey(_liveCropSpeciesEditKey(_cropSpeciesAId)),
      findsOneWidget,
    );
    expect(harness.transport.calls, 0);
    expect(tester.takeException(), isNull);
  });

  testWidgets('multiple unresolved species renames fail closed', (
    tester,
  ) async {
    final managerScope = _scope(
      organizationId: _organizationAId,
      organizationName: 'Tổ chức A',
      farmId: _farmAId,
      farmName: 'Nông trại A',
      continuityEpoch: '37',
      selectionEpoch: 11,
      organizationRole: FarmlyOrganizationRole.member,
      selectedFarmRole: FarmlyFarmGrantRole.manager,
    );
    final domain = InMemoryDomainStore();
    await _installCropPlotSnapshot(
      domain,
      managerScope,
      zoneId: _cropPlotZoneAId,
      zoneName: 'Luống A',
      cropSpecies: const [
        {
          'id': _cropSpeciesAId,
          'version': 2,
          'name': 'Cà chua bi',
          'harvestUnit': 'kg',
          'status': 'active',
        },
      ],
    );
    final outbox = InMemoryOutboxStore();
    for (final (operationId, proposedName) in [
      ('d4d4d4d4-d4d4-44d4-84d4-d4d4d4d4d4d4', 'Cà chua đỏ'),
      ('d5d5d5d5-d5d5-45d5-85d5-d5d5d5d5d5d5', 'Cà chua vàng'),
    ]) {
      await outbox.enqueue(
        FarmlyScopedMutation(
          scope: FarmlyMutationScope.farm(
            accountId: _accountId,
            organizationId: _organizationAId,
            farmId: _farmAId,
            continuityEpoch: '37',
          ),
          intent: FarmlyUpdateCropSpeciesNameIntent(
            operationId: operationId,
            continuityEpoch: '37',
            resourceId: _cropSpeciesAId,
            baseVersion: 2,
            name: proposedName,
          ),
        ),
      );
    }
    final harness = await _pumpOverview(
      tester,
      scope: managerScope,
      domain: domain,
      outbox: outbox,
    );

    await _openLiveCropPlotDetails(tester, zoneId: _cropPlotZoneAId);

    expect(find.textContaining('Cà chua bi'), findsOneWidget);
    expect(find.textContaining('Cà chua đỏ'), findsNothing);
    expect(find.textContaining('Cà chua vàng'), findsNothing);
    expect(find.byKey(_liveCropSpeciesEditKey(_cropSpeciesAId)), findsNothing);
    expect(harness.transport.calls, 0);
    expect(tester.takeException(), isNull);
  });

  testWidgets('conflicted species rename keeps confirmed data and locks edit', (
    tester,
  ) async {
    final managerScope = _scope(
      organizationId: _organizationAId,
      organizationName: 'Tổ chức A',
      farmId: _farmAId,
      farmName: 'Nông trại A',
      continuityEpoch: '37',
      selectionEpoch: 11,
      organizationRole: FarmlyOrganizationRole.member,
      selectedFarmRole: FarmlyFarmGrantRole.manager,
    );
    final domain = InMemoryDomainStore();
    await _installCropPlotSnapshot(
      domain,
      managerScope,
      zoneId: _cropPlotZoneAId,
      zoneName: 'Luống A',
      cropSpecies: const [
        {
          'id': _cropSpeciesAId,
          'version': 2,
          'name': 'Cà chua bi',
          'harvestUnit': 'kg',
          'status': 'active',
        },
      ],
    );
    final outbox = InMemoryOutboxStore();
    final entry = await outbox.enqueue(
      FarmlyScopedMutation(
        scope: FarmlyMutationScope.farm(
          accountId: _accountId,
          organizationId: _organizationAId,
          farmId: _farmAId,
          continuityEpoch: '37',
        ),
        intent: FarmlyUpdateCropSpeciesNameIntent(
          operationId: 'd6d6d6d6-d6d6-46d6-86d6-d6d6d6d6d6d6',
          continuityEpoch: '37',
          resourceId: _cropSpeciesAId,
          baseVersion: 2,
          name: 'Cà chua đã xung đột',
        ),
      ),
    );
    await outbox.update(entry.copyWith(status: OutboxEntryStatus.conflict));
    final harness = await _pumpOverview(
      tester,
      scope: managerScope,
      domain: domain,
      outbox: outbox,
    );

    await _openLiveCropPlotDetails(tester, zoneId: _cropPlotZoneAId);

    expect(find.textContaining('Cà chua bi'), findsOneWidget);
    expect(find.textContaining('Cà chua đã xung đột'), findsNothing);
    expect(find.byKey(_liveCropSpeciesEditKey(_cropSpeciesAId)), findsNothing);
    expect(harness.transport.calls, 0);
    expect(tester.takeException(), isNull);
  });

  testWidgets('species rename save rejects a stale confirmed version', (
    tester,
  ) async {
    final managerScope = _scope(
      organizationId: _organizationAId,
      organizationName: 'Tổ chức A',
      farmId: _farmAId,
      farmName: 'Nông trại A',
      continuityEpoch: '37',
      selectionEpoch: 11,
      organizationRole: FarmlyOrganizationRole.member,
      selectedFarmRole: FarmlyFarmGrantRole.manager,
    );
    final domain = InMemoryDomainStore();
    await _installCropPlotSnapshot(
      domain,
      managerScope,
      zoneId: _cropPlotZoneAId,
      zoneName: 'Luống A',
      cropSpecies: const [
        {
          'id': _cropSpeciesAId,
          'version': 2,
          'name': 'Cà chua bi',
          'harvestUnit': 'kg',
          'status': 'active',
        },
      ],
    );
    final harness = await _pumpOverview(
      tester,
      scope: managerScope,
      domain: domain,
    );
    await _openLiveCropPlotDetails(tester, zoneId: _cropPlotZoneAId);
    await tester.tap(find.byKey(_liveCropSpeciesEditKey(_cropSpeciesAId)));
    await tester.pumpAndSettle();
    await tester.enterText(
      find.byKey(_liveCropSpeciesEditNameKey),
      'Cà chua đổi tên',
    );
    await _installCropPlotSnapshot(
      domain,
      managerScope,
      zoneId: _cropPlotZoneAId,
      zoneName: 'Luống A',
      cropSpecies: const [
        {
          'id': _cropSpeciesAId,
          'version': 3,
          'name': 'Cà chua mới trên máy chủ',
          'harvestUnit': 'kg',
          'status': 'active',
        },
      ],
    );

    await tester.tap(find.byKey(_liveCropSpeciesEditSaveKey));
    await tester.pumpAndSettle();

    expect(
      find.text(
        'Chưa lưu được tên loại cây trên thiết bị. Dữ liệu có thể đã thay đổi; hãy tải lại rồi thử lại.',
      ),
      findsOneWidget,
    );
    expect(
      await harness.outbox.entries(
        accountId: _accountId,
        organizationId: _organizationAId,
      ),
      isEmpty,
    );
    expect(harness.transport.calls, 0);
    expect(tester.takeException(), isNull);
  });

  testWidgets('species rename form locks when the selected farm changes', (
    tester,
  ) async {
    final managerScope = _scope(
      organizationId: _organizationAId,
      organizationName: 'Tổ chức A',
      farmId: _farmAId,
      farmName: 'Nông trại A',
      continuityEpoch: '37',
      selectionEpoch: 11,
      organizationRole: FarmlyOrganizationRole.member,
      selectedFarmRole: FarmlyFarmGrantRole.manager,
    );
    final domain = InMemoryDomainStore();
    await _installCropPlotSnapshot(
      domain,
      managerScope,
      zoneId: _cropPlotZoneAId,
      zoneName: 'Luống A',
      cropSpecies: const [
        {
          'id': _cropSpeciesAId,
          'version': 2,
          'name': 'Cà chua bi',
          'harvestUnit': 'kg',
          'status': 'active',
        },
      ],
    );
    final harness = await _pumpOverview(
      tester,
      scope: managerScope,
      domain: domain,
    );
    await _openLiveCropPlotDetails(tester, zoneId: _cropPlotZoneAId);
    await tester.tap(find.byKey(_liveCropSpeciesEditKey(_cropSpeciesAId)));
    await tester.pumpAndSettle();

    harness.scopeController.replace(_scopeB);
    await tester.pumpAndSettle();

    expect(
      tester.widget<TextField>(find.byKey(_liveCropSpeciesEditNameKey)).enabled,
      isFalse,
    );
    expect(
      tester
          .widget<FilledButton>(find.byKey(_liveCropSpeciesEditSaveKey))
          .onPressed,
      isNull,
    );
    expect(
      await harness.outbox.entries(
        accountId: _accountId,
        organizationId: _organizationAId,
      ),
      isEmpty,
    );
    expect(harness.transport.calls, 0);
    expect(tester.takeException(), isNull);
  });

  testWidgets(
    'harvest create uses the pending planting dependency and stays local',
    (tester) async {
      final domain = InMemoryDomainStore();
      await _installCropPlotSnapshot(
        domain,
        _scopeA,
        zoneId: _cropPlotZoneAId,
        zoneName: 'Luống A',
        cropSpecies: const [
          {
            'id': _cropSpeciesAId,
            'version': 1,
            'name': 'Cà chua bi',
            'harvestUnit': 'kg',
            'status': 'active',
          },
        ],
      );
      const plantingOperationId = 'dddddddd-dddd-4ddd-8ddd-dddddddddddd';
      final outbox = InMemoryOutboxStore();
      await outbox.enqueue(
        FarmlyScopedMutation(
          scope: FarmlyMutationScope.farm(
            accountId: _accountId,
            organizationId: _organizationAId,
            farmId: _farmAId,
            continuityEpoch: '37',
          ),
          intent: FarmlyCreatePlantingIntent(
            operationId: plantingOperationId,
            continuityEpoch: '37',
            resourceId: _plantingAId,
            cropSpeciesId: _cropSpeciesAId,
            plotId: _cropPlotZoneAId,
            sowingDate: '2026-10-12',
            status: 'active',
          ),
        ),
      );
      final harness = await _pumpOverview(
        tester,
        scope: _scopeA,
        domain: domain,
        outbox: outbox,
      );

      await _openLiveCropPlotDetails(tester, zoneId: _cropPlotZoneAId);
      await _createLiveHarvest(
        tester,
        plantingId: _plantingAId,
        quantityKg: '12.375',
        harvestDate: '2026-10-19',
      );

      expect(find.text(_savedPendingCopy), findsOneWidget);
      final entries = await harness.outbox.entries(
        accountId: _accountId,
        organizationId: _organizationAId,
      );
      expect(entries, hasLength(2));
      final harvest = entries.singleWhere(
        (entry) => entry.mutation.intent.type == 'harvest.create',
      );
      expect(harvest.status, OutboxEntryStatus.pending);
      expect(harvest.mutation.scope.farmId, _farmAId);
      expect(harvest.mutation.intent.payload, {
        'plantingId': _plantingAId,
        'quantityKg': '12.375',
        'harvestDate': '2026-10-19',
      });
      expect(harvest.mutation.intent.dependsOn, [plantingOperationId]);
      expect(harness.transport.calls, 0);
      expect(
        find.byKey(
          ValueKey('live-harvest-row-${harvest.mutation.intent.resourceId}'),
        ),
        findsOneWidget,
      );
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'workers propose a correction locally without changing confirmed harvest',
    (tester) async {
      final workerScope = _scope(
        organizationId: _organizationAId,
        organizationName: 'Tổ chức A',
        farmId: _farmAId,
        farmName: 'Nông trại A',
        continuityEpoch: '37',
        selectionEpoch: 11,
        organizationRole: FarmlyOrganizationRole.member,
        selectedFarmRole: FarmlyFarmGrantRole.worker,
      );
      final domain = InMemoryDomainStore();
      await _installHarvestActionFixture(domain, workerScope);
      final harness = await _pumpOverview(
        tester,
        scope: workerScope,
        domain: domain,
      );

      await _openLiveHarvestActions(tester);
      expect(find.text('Gửi đề xuất'), findsOneWidget);
      expect(find.text('Điều chỉnh'), findsNothing);
      expect(find.text('Huỷ bản ghi'), findsNothing);
      await tester.enterText(
        find.bySemanticsLabel('Khối lượng mới (kg)'),
        '8.75',
      );
      await tester.enterText(
        find.bySemanticsLabel('Lý do chỉnh sửa'),
        'Cân lại sau khi làm khô',
      );
      await tester.tap(find.text('Gửi đề xuất'));
      await tester.pumpAndSettle();

      final entries = await harness.outbox.entries(
        accountId: _accountId,
        organizationId: _organizationAId,
      );
      expect(entries, hasLength(1));
      final proposal = entries.single;
      expect(proposal.status, OutboxEntryStatus.pending);
      expect(proposal.mutation.scope.kind, FarmlyMutationScopeKind.farm);
      expect(proposal.mutation.scope.accountId, _accountId);
      expect(proposal.mutation.scope.organizationId, _organizationAId);
      expect(proposal.mutation.scope.farmId, _farmAId);
      expect(proposal.mutation.scope.continuityEpoch, '37');
      expect(proposal.mutation.intent.type, 'harvest.correction.propose');
      expect(proposal.mutation.intent.resourceId, _harvestAId);
      expect(proposal.mutation.intent.baseVersion, isNull);
      expect(proposal.mutation.intent.payload, {
        'proposedQuantityKg': '8.75',
        'reason': 'Cân lại sau khi làm khô',
      });
      expect(find.textContaining('5,25 kg'), findsWidgets);
      expect(harness.transport.calls, 0);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets('manager applies only a proposal included in the farm snapshot', (
    tester,
  ) async {
    final managerScope = _scope(
      organizationId: _organizationAId,
      organizationName: 'Tổ chức A',
      farmId: _farmAId,
      farmName: 'Nông trại A',
      continuityEpoch: '37',
      selectionEpoch: 11,
      organizationRole: FarmlyOrganizationRole.member,
      selectedFarmRole: FarmlyFarmGrantRole.manager,
    );
    final domain = InMemoryDomainStore();
    await _installHarvestActionFixture(
      domain,
      managerScope,
      correctionProposals: const [
        {
          'id': _harvestProposalAId,
          'version': 1,
          'harvestId': _harvestAId,
          'proposedQuantityKg': '8.75',
          'reason': 'Cân lại sau khi làm khô',
          'status': 'pending',
        },
      ],
    );
    final harness = await _pumpOverview(
      tester,
      scope: managerScope,
      domain: domain,
    );

    await _openLiveHarvestActions(tester);
    expect(find.textContaining('Cân lại sau khi làm khô'), findsOneWidget);
    expect(find.text('Áp dụng'), findsOneWidget);
    await tester.tap(find.text('Áp dụng'));
    await tester.pumpAndSettle();

    final entries = await harness.outbox.entries(
      accountId: _accountId,
      organizationId: _organizationAId,
    );
    expect(entries, hasLength(1));
    final correction = entries.single;
    expect(correction.status, OutboxEntryStatus.pending);
    expect(correction.mutation.scope.farmId, _farmAId);
    expect(correction.mutation.scope.continuityEpoch, '37');
    expect(correction.mutation.intent.type, 'harvest.correction.apply');
    expect(correction.mutation.intent.resourceId, _harvestAId);
    expect(correction.mutation.intent.baseVersion, 7);
    expect(correction.mutation.intent.payload, {
      'proposedQuantityKg': '8.75',
      'proposalId': _harvestProposalAId,
    });
    expect(harness.transport.calls, 0);
    expect(tester.takeException(), isNull);
  });

  testWidgets('manager can directly correct a confirmed harvest head', (
    tester,
  ) async {
    final domain = InMemoryDomainStore();
    await _installHarvestActionFixture(domain, _scopeA);
    final harness = await _pumpOverview(tester, scope: _scopeA, domain: domain);

    await _openLiveHarvestActions(tester);
    expect(find.text('Điều chỉnh'), findsOneWidget);
    await tester.tap(find.text('Điều chỉnh'));
    await tester.pumpAndSettle();
    await tester.enterText(
      find.bySemanticsLabel('Khối lượng mới (kg)'),
      '6.75',
    );
    await tester.tap(find.text('Áp dụng'));
    await tester.pumpAndSettle();

    final entries = await harness.outbox.entries(
      accountId: _accountId,
      organizationId: _organizationAId,
    );
    expect(entries, hasLength(1));
    final correction = entries.single;
    expect(correction.mutation.scope.farmId, _farmAId);
    expect(correction.mutation.scope.continuityEpoch, '37');
    expect(correction.mutation.intent.type, 'harvest.correction.apply');
    expect(correction.mutation.intent.resourceId, _harvestAId);
    expect(correction.mutation.intent.baseVersion, 7);
    expect(correction.mutation.intent.payload, {'proposedQuantityKg': '6.75'});
    expect(harness.transport.calls, 0);
    expect(tester.takeException(), isNull);
  });

  testWidgets(
    'applied correction releases manager actions after head version advances',
    (tester) async {
      final domain = InMemoryDomainStore();
      await _installHarvestActionFixture(domain, _scopeA, harvestVersion: 8);
      final outbox = InMemoryOutboxStore();
      await _queueAppliedHarvestCorrection(outbox, _scopeA);
      final harness = await _pumpOverview(
        tester,
        scope: _scopeA,
        domain: domain,
        outbox: outbox,
      );

      await _openLiveHarvestActions(tester);
      expect(find.text('Điều chỉnh'), findsOneWidget);
      await tester.tap(find.text('Điều chỉnh'));
      await tester.pumpAndSettle();
      await tester.enterText(
        find.bySemanticsLabel('Khối lượng mới (kg)'),
        '7.25',
      );
      await tester.tap(find.text('Áp dụng'));
      await tester.pumpAndSettle();

      final entries = await harness.outbox.entries(
        accountId: _accountId,
        organizationId: _organizationAId,
      );
      expect(entries, hasLength(2));
      final nextCorrection = entries.singleWhere(
        (entry) =>
            entry.mutation.intent.operationId !=
            _appliedHarvestCorrectionOperationId,
      );
      expect(nextCorrection.status, OutboxEntryStatus.pending);
      expect(nextCorrection.mutation.intent.type, 'harvest.correction.apply');
      expect(nextCorrection.mutation.intent.resourceId, _harvestAId);
      expect(nextCorrection.mutation.intent.baseVersion, 8);
      expect(nextCorrection.mutation.intent.payload, {
        'proposedQuantityKg': '7.25',
      });
      expect(harness.transport.calls, 0);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'applied correction keeps manager actions blocked until head advances',
    (tester) async {
      final domain = InMemoryDomainStore();
      await _installHarvestActionFixture(domain, _scopeA, harvestVersion: 7);
      final outbox = InMemoryOutboxStore();
      await _queueAppliedHarvestCorrection(outbox, _scopeA);
      final harness = await _pumpOverview(
        tester,
        scope: _scopeA,
        domain: domain,
        outbox: outbox,
      );

      await _openLiveHarvestActions(tester);

      expect(find.text('Điều chỉnh'), findsNothing);
      expect(find.text('Huỷ bản ghi'), findsNothing);
      expect(
        await harness.outbox.entries(
          accountId: _accountId,
          organizationId: _organizationAId,
        ),
        hasLength(1),
      );
      expect(harness.transport.calls, 0);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets('manager voids a confirmed harvest with reason and head CAS', (
    tester,
  ) async {
    final domain = InMemoryDomainStore();
    await _installHarvestActionFixture(domain, _scopeA);
    final harness = await _pumpOverview(tester, scope: _scopeA, domain: domain);

    await _openLiveHarvestActions(tester);
    expect(find.text('Huỷ bản ghi'), findsOneWidget);
    await tester.enterText(
      find.bySemanticsLabel('Lý do huỷ bản ghi'),
      'Nhập trùng phiếu cân',
    );
    await tester.tap(find.text('Huỷ bản ghi'));
    await tester.pumpAndSettle();

    final entries = await harness.outbox.entries(
      accountId: _accountId,
      organizationId: _organizationAId,
    );
    expect(entries, hasLength(1));
    final voidIntent = entries.single;
    expect(voidIntent.mutation.scope.farmId, _farmAId);
    expect(voidIntent.mutation.scope.continuityEpoch, '37');
    expect(voidIntent.mutation.intent.type, 'harvest.void');
    expect(voidIntent.mutation.intent.resourceId, _harvestAId);
    expect(voidIntent.mutation.intent.baseVersion, 7);
    expect(voidIntent.mutation.intent.payload, {
      'reason': 'Nhập trùng phiếu cân',
    });
    expect(harness.transport.calls, 0);
    expect(tester.takeException(), isNull);
  });

  testWidgets(
    'an empty or unrelated proposal snapshot never offers apply for this head',
    (tester) async {
      final domain = InMemoryDomainStore();
      await _installHarvestActionFixture(
        domain,
        _scopeA,
        correctionProposals: const [
          {
            'id': _harvestProposalAId,
            'version': 1,
            'harvestId': _harvestOtherId,
            'proposedQuantityKg': '99',
            'reason': 'Thuộc bản ghi khác',
            'status': 'pending',
          },
        ],
      );
      await _pumpOverview(tester, scope: _scopeA, domain: domain);

      await _openLiveHarvestActions(tester);

      expect(find.text('Áp dụng'), findsNothing);
      expect(find.textContaining('Thuộc bản ghi khác'), findsNothing);
      expect(find.text('Điều chỉnh'), findsOneWidget);
      expect(find.text('Huỷ bản ghi'), findsOneWidget);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets('voided harvest exposes no correction actions', (tester) async {
    final domain = InMemoryDomainStore();
    await _installHarvestActionFixture(
      domain,
      _scopeA,
      harvestStatus: 'voided',
    );
    await _pumpOverview(tester, scope: _scopeA, domain: domain);

    await _openLiveHarvestActions(tester);

    expect(find.text('Gửi đề xuất'), findsNothing);
    expect(find.text('Điều chỉnh'), findsNothing);
    expect(find.text('Huỷ bản ghi'), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets('pending harvest parent exposes no correction actions', (
    tester,
  ) async {
    final domain = InMemoryDomainStore();
    await _installHarvestActionFixture(domain, _scopeA, includeHarvest: false);
    final outbox = InMemoryOutboxStore();
    await _queueLiveHarvestCreate(outbox, _scopeA);
    final harness = await _pumpOverview(
      tester,
      scope: _scopeA,
      domain: domain,
      outbox: outbox,
    );

    await _openLiveHarvestActions(tester);

    expect(find.text('Gửi đề xuất'), findsNothing);
    expect(find.text('Điều chỉnh'), findsNothing);
    expect(find.text('Huỷ bản ghi'), findsNothing);
    expect(harness.transport.calls, 0);
    expect(tester.takeException(), isNull);
  });

  testWidgets('needs-attention harvest parent exposes no correction actions', (
    tester,
  ) async {
    final domain = InMemoryDomainStore();
    await _installHarvestActionFixture(domain, _scopeA, includeHarvest: false);
    final outbox = InMemoryOutboxStore();
    await _queueLiveHarvestCreate(
      outbox,
      _scopeA,
      status: OutboxEntryStatus.rejected,
    );
    final harness = await _pumpOverview(
      tester,
      scope: _scopeA,
      domain: domain,
      outbox: outbox,
    );

    await _openLiveHarvestActions(tester);

    expect(find.text('Gửi đề xuất'), findsNothing);
    expect(find.text('Điều chỉnh'), findsNothing);
    expect(find.text('Huỷ bản ghi'), findsNothing);
    expect(harness.transport.calls, 0);
    expect(tester.takeException(), isNull);
  });

  testWidgets('workers can propose but cannot apply or void harvests', (
    tester,
  ) async {
    final workerScope = _scope(
      organizationId: _organizationAId,
      organizationName: 'Tổ chức A',
      farmId: _farmAId,
      farmName: 'Nông trại A',
      continuityEpoch: '37',
      selectionEpoch: 11,
      organizationRole: FarmlyOrganizationRole.member,
      selectedFarmRole: FarmlyFarmGrantRole.worker,
    );
    final workerDomain = InMemoryDomainStore();
    await _installHarvestActionFixture(workerDomain, workerScope);
    await _pumpOverview(tester, scope: workerScope, domain: workerDomain);
    await _openLiveHarvestActions(tester);
    expect(find.text('Gửi đề xuất'), findsOneWidget);
    expect(find.text('Điều chỉnh'), findsNothing);
    expect(find.text('Áp dụng'), findsNothing);
    expect(find.text('Huỷ bản ghi'), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets('organization viewer cannot propose, apply, or void harvests', (
    tester,
  ) async {
    final viewerScope = _scope(
      organizationId: _organizationAId,
      organizationName: 'Tổ chức A',
      farmId: _farmAId,
      farmName: 'Nông trại A',
      continuityEpoch: '37',
      selectionEpoch: 11,
      organizationRole: FarmlyOrganizationRole.viewer,
      selectedFarmRole: FarmlyFarmGrantRole.manager,
    );
    final viewerDomain = InMemoryDomainStore();
    await _installHarvestActionFixture(viewerDomain, viewerScope);
    final viewerHarness = await _pumpOverview(
      tester,
      scope: viewerScope,
      domain: viewerDomain,
    );
    await _openLiveHarvestActions(tester);
    expect(find.text('Gửi đề xuất'), findsNothing);
    expect(find.text('Điều chỉnh'), findsNothing);
    expect(find.text('Áp dụng'), findsNothing);
    expect(find.text('Huỷ bản ghi'), findsNothing);
    expect(viewerHarness.transport.calls, 0);
    expect(tester.takeException(), isNull);
  });

  testWidgets('farm switch locks an open direct harvest correction', (
    tester,
  ) async {
    final domain = InMemoryDomainStore();
    await _installHarvestActionFixture(domain, _scopeA);
    await _installEmptyBootstrap(domain, _scopeB);
    final harness = await _pumpOverview(tester, scope: _scopeA, domain: domain);

    await _openLiveHarvestActions(tester);
    await tester.tap(find.text('Điều chỉnh'));
    await tester.pumpAndSettle();
    await tester.enterText(
      find.bySemanticsLabel('Khối lượng mới (kg)'),
      '6.75',
    );
    harness.scopeController.replace(_scopeB);
    await tester.pumpAndSettle();
    await tester.tap(find.text('Áp dụng'));
    await tester.pumpAndSettle();

    expect(
      await harness.outbox.entries(
        accountId: _accountId,
        organizationId: _organizationAId,
      ),
      isEmpty,
    );
    expect(
      await harness.outbox.entries(
        accountId: _accountId,
        organizationId: _organizationBId,
      ),
      isEmpty,
    );
    expect(harness.transport.calls, 0);
    expect(tester.takeException(), isNull);
  });

  testWidgets('farm workers may record harvest but cannot author crops', (
    tester,
  ) async {
    final workerScope = _scope(
      organizationId: _organizationAId,
      organizationName: 'Tổ chức A',
      farmId: _farmAId,
      farmName: 'Nông trại A',
      continuityEpoch: '37',
      selectionEpoch: 11,
      organizationRole: FarmlyOrganizationRole.member,
      selectedFarmRole: FarmlyFarmGrantRole.worker,
    );
    final domain = InMemoryDomainStore();
    await _installCropPlotSnapshot(
      domain,
      workerScope,
      zoneId: _cropPlotZoneAId,
      zoneName: 'Luống A',
      cropSpecies: const [
        {
          'id': _cropSpeciesAId,
          'version': 1,
          'name': 'Cà chua bi',
          'harvestUnit': 'kg',
          'status': 'active',
        },
      ],
      plantings: const [
        {
          'id': _plantingAId,
          'version': 1,
          'cropSpeciesId': _cropSpeciesAId,
          'plotId': _cropPlotZoneAId,
          'status': 'active',
          'sowingDate': '2026-10-12',
        },
      ],
    );
    final harness = await _pumpOverview(
      tester,
      scope: workerScope,
      domain: domain,
    );

    await _openLiveCropPlotDetails(tester, zoneId: _cropPlotZoneAId);

    expect(find.byKey(_liveCropSpeciesCreateKey), findsNothing);
    expect(find.byKey(_livePlantingCreateKey), findsNothing);
    expect(find.byKey(_liveHarvestCreateKey(_plantingAId)), findsOneWidget);
    await _createLiveHarvest(
      tester,
      plantingId: _plantingAId,
      quantityKg: '3.5',
      harvestDate: '2026-10-19',
    );

    final entries = await harness.outbox.entries(
      accountId: _accountId,
      organizationId: _organizationAId,
    );
    expect(entries, hasLength(1));
    expect(entries.single.mutation.intent.type, 'harvest.create');
    expect(harness.transport.calls, 0);
    expect(tester.takeException(), isNull);
  });

  testWidgets('farm change locks the open harvest form', (tester) async {
    final domain = InMemoryDomainStore();
    await _installCropPlotSnapshot(
      domain,
      _scopeA,
      zoneId: _cropPlotZoneAId,
      zoneName: 'Luống A',
      cropSpecies: const [
        {
          'id': _cropSpeciesAId,
          'version': 1,
          'name': 'Cà chua bi',
          'harvestUnit': 'kg',
          'status': 'active',
        },
      ],
      plantings: const [
        {
          'id': _plantingAId,
          'version': 1,
          'cropSpeciesId': _cropSpeciesAId,
          'plotId': _cropPlotZoneAId,
          'status': 'active',
          'sowingDate': '2026-10-12',
        },
      ],
    );
    await _installEmptyBootstrap(domain, _scopeB);
    final harness = await _pumpOverview(tester, scope: _scopeA, domain: domain);

    await _openLiveCropPlotDetails(tester, zoneId: _cropPlotZoneAId);
    final createButton = find.byKey(_liveHarvestCreateKey(_plantingAId));
    await tester.ensureVisible(createButton);
    await tester.tap(createButton);
    await tester.pumpAndSettle();
    await tester.enterText(find.byKey(_liveHarvestQuantityKey), '3.5');
    harness.scopeController.replace(_scopeB);
    await tester.pumpAndSettle();

    expect(
      tester.widget<FilledButton>(find.byKey(_liveHarvestSaveKey)).onPressed,
      isNull,
    );
    await tester.tap(find.byKey(_liveHarvestSaveKey));
    await tester.pumpAndSettle();
    expect(
      await harness.outbox.entries(
        accountId: _accountId,
        organizationId: _organizationAId,
      ),
      isEmpty,
    );
    expect(
      await harness.outbox.entries(
        accountId: _accountId,
        organizationId: _organizationBId,
      ),
      isEmpty,
    );
    expect(harness.transport.calls, 0);
    expect(tester.takeException(), isNull);
  });

  testWidgets(
    'creating a crop species saves locally as pending without transport calls',
    (tester) async {
      final domain = InMemoryDomainStore();
      await _installCropPlotSnapshot(
        domain,
        _scopeA,
        zoneId: _cropPlotZoneAId,
        zoneName: 'Luống A',
      );
      final harness = await _pumpOverview(
        tester,
        scope: _scopeA,
        domain: domain,
      );

      await _openLiveCropPlotDetails(tester, zoneId: _cropPlotZoneAId);
      await _createLiveCropSpecies(tester, name: 'Dưa lưới');

      expect(find.text(_savedPendingCopy), findsOneWidget);
      expect(
        find.descendant(
          of: find.byKey(_liveCropSpeciesListKey),
          matching: find.text('Chờ đồng bộ'),
        ),
        findsOneWidget,
      );
      final entries = await harness.outbox.entries(
        accountId: _accountId,
        organizationId: _organizationAId,
      );
      expect(entries, hasLength(1));
      final species = entries.single;
      expect(species.status, OutboxEntryStatus.pending);
      expect(species.mutation.intent.type, 'cropSpecies.create');
      expect(species.mutation.scope.kind, FarmlyMutationScopeKind.farm);
      expect(species.mutation.scope.organizationId, _organizationAId);
      expect(species.mutation.scope.farmId, _farmAId);
      expect(species.mutation.scope.continuityEpoch, '37');
      expect(species.mutation.intent.continuityEpoch, '37');
      expect(species.mutation.intent.payload, {
        'name': 'Dưa lưới',
        'harvestUnit': 'kg',
      });
      expect(harness.transport.calls, 0);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets('farm change locks the open crop species form', (tester) async {
    final domain = InMemoryDomainStore();
    await _installCropPlotSnapshot(
      domain,
      _scopeA,
      zoneId: _cropPlotZoneAId,
      zoneName: 'Luống A',
    );
    await _installEmptyBootstrap(domain, _scopeB);
    final harness = await _pumpOverview(tester, scope: _scopeA, domain: domain);

    await _openLiveCropPlotDetails(tester, zoneId: _cropPlotZoneAId);
    await tester.tap(find.byKey(_liveCropSpeciesCreateKey));
    await tester.pumpAndSettle();
    await tester.enterText(find.byKey(_liveCropSpeciesNameKey), 'Cây thử');
    harness.scopeController.replace(_scopeB);
    await tester.pumpAndSettle();

    expect(
      find.text(
        'Nông trại hoặc quyền đã thay đổi. Hãy đóng biểu mẫu và mở lại ở phạm vi hiện tại.',
      ),
      findsWidgets,
    );
    expect(
      tester
          .widget<FilledButton>(find.byKey(_liveCropSpeciesSaveKey))
          .onPressed,
      isNull,
    );
    await tester.tap(find.byKey(_liveCropSpeciesSaveKey));
    await tester.pumpAndSettle();
    expect(
      await harness.outbox.entries(
        accountId: _accountId,
        organizationId: _organizationAId,
      ),
      isEmpty,
    );
    expect(
      await harness.outbox.entries(
        accountId: _accountId,
        organizationId: _organizationBId,
      ),
      isEmpty,
    );
    expect(harness.transport.calls, 0);
    expect(tester.takeException(), isNull);
  });

  testWidgets(
    'planting create captures crop plot and pending species dependencies',
    (tester) async {
      final domain = InMemoryDomainStore();
      await _installEmptyBootstrap(domain, _scopeA);
      final harness = await _pumpOverview(
        tester,
        scope: _scopeA,
        domain: domain,
      );

      await _openLiveZoneForm(tester);
      await _submitLiveZone(tester, 'Luống mới');
      expect(find.text(_savedPendingCopy), findsOneWidget);
      final zoneEntriesBeforePlanting = await harness.outbox.entries(
        accountId: _accountId,
        organizationId: _organizationAId,
      );
      expect(zoneEntriesBeforePlanting, hasLength(1));
      final zone = zoneEntriesBeforePlanting.single;
      expect(zone.mutation.intent.type, 'zone.create');
      expect(zone.mutation.intent.payload['type'], 'crop_plot');

      await _openLiveCropPlotDetails(
        tester,
        zoneId: zone.mutation.intent.resourceId,
      );
      await _createLiveCropSpecies(tester, name: 'Dưa lưới');
      expect(find.text(_savedPendingCopy), findsOneWidget);
      final entriesBeforePlanting = await harness.outbox.entries(
        accountId: _accountId,
        organizationId: _organizationAId,
      );
      expect(entriesBeforePlanting, hasLength(2));
      final species = entriesBeforePlanting.singleWhere(
        (entry) => entry.mutation.intent.type == 'cropSpecies.create',
      );

      await _createLivePlanting(
        tester,
        speciesName: 'Dưa lưới',
        sowingDate: '2026-10-12',
        expectedHarvestDate: '2027-01-10',
        areaM2: '12.5',
      );

      expect(find.text(_savedPendingCopy), findsOneWidget);
      final entries = await harness.outbox.entries(
        accountId: _accountId,
        organizationId: _organizationAId,
      );
      expect(entries, hasLength(3));
      final planting = entries.singleWhere(
        (entry) => entry.mutation.intent.type == 'planting.create',
      );
      expect(planting.status, OutboxEntryStatus.pending);
      expect(planting.mutation.scope.kind, FarmlyMutationScopeKind.farm);
      expect(planting.mutation.scope.organizationId, _organizationAId);
      expect(planting.mutation.scope.farmId, _farmAId);
      expect(planting.mutation.scope.continuityEpoch, '37');
      expect(planting.mutation.intent.continuityEpoch, '37');
      expect(
        planting.mutation.intent.payload['cropSpeciesId'],
        species.mutation.intent.resourceId,
      );
      expect(
        planting.mutation.intent.payload['plotId'],
        zone.mutation.intent.resourceId,
      );
      expect(planting.mutation.intent.payload['sowingDate'], '2026-10-12');
      expect(
        planting.mutation.intent.payload['expectedHarvestDate'],
        '2027-01-10',
      );
      expect(planting.mutation.intent.payload['areaM2'], '12.5');
      expect(
        planting.mutation.intent.payload.keys,
        everyElement(
          isIn({
            'cropSpeciesId',
            'plotId',
            'sowingDate',
            'status',
            'expectedHarvestDate',
            'areaM2',
          }),
        ),
      );
      expect(
        planting.mutation.intent.dependsOn,
        unorderedEquals([
          zone.mutation.intent.operationId,
          species.mutation.intent.operationId,
        ]),
      );
      expect(harness.transport.calls, 0);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets('farm change locks the open planting form', (tester) async {
    final domain = InMemoryDomainStore();
    await _installCropPlotSnapshot(
      domain,
      _scopeA,
      zoneId: _cropPlotZoneAId,
      zoneName: 'Luống A',
      cropSpecies: const [
        {
          'id': _cropSpeciesAId,
          'version': 1,
          'name': 'Cà chua bi',
          'harvestUnit': 'kg',
          'status': 'active',
        },
      ],
    );
    await _installEmptyBootstrap(domain, _scopeB);
    final harness = await _pumpOverview(tester, scope: _scopeA, domain: domain);

    await _openLiveCropPlotDetails(tester, zoneId: _cropPlotZoneAId);
    await tester.tap(find.byKey(_livePlantingCreateKey));
    await tester.pumpAndSettle();
    harness.scopeController.replace(_scopeB);
    await tester.pumpAndSettle();

    expect(
      tester.widget<FilledButton>(find.byKey(_livePlantingSaveKey)).onPressed,
      isNull,
    );
    await tester.tap(find.byKey(_livePlantingSaveKey));
    await tester.pumpAndSettle();
    expect(
      await harness.outbox.entries(
        accountId: _accountId,
        organizationId: _organizationAId,
      ),
      isEmpty,
    );
    expect(
      await harness.outbox.entries(
        accountId: _accountId,
        organizationId: _organizationBId,
      ),
      isEmpty,
    );
    expect(harness.transport.calls, 0);
    expect(tester.takeException(), isNull);
  });

  testWidgets('worker cannot create crop species or plantings', (tester) async {
    final workerScope = _scope(
      organizationId: _organizationAId,
      organizationName: 'Tổ chức A',
      farmId: _farmAId,
      farmName: 'Nông trại A',
      continuityEpoch: '37',
      selectionEpoch: 11,
      organizationRole: FarmlyOrganizationRole.member,
      selectedFarmRole: FarmlyFarmGrantRole.worker,
    );
    final domain = InMemoryDomainStore();
    await _installCropPlotSnapshot(
      domain,
      workerScope,
      zoneId: _cropPlotZoneAId,
      zoneName: 'Luống A',
      cropSpecies: const [
        {
          'id': _cropSpeciesAId,
          'version': 2,
          'name': 'Cà chua bi',
          'harvestUnit': 'kg',
          'status': 'active',
        },
      ],
    );
    final harness = await _pumpOverview(
      tester,
      scope: workerScope,
      domain: domain,
    );

    await _openLiveCropPlotDetails(tester, zoneId: _cropPlotZoneAId);

    expect(find.byKey(_liveCropSpeciesCreateKey), findsNothing);
    expect(find.byKey(_livePlantingCreateKey), findsNothing);
    expect(
      await harness.outbox.entries(
        accountId: _accountId,
        organizationId: _organizationAId,
      ),
      isEmpty,
    );
    expect(harness.transport.calls, 0);
    expect(tester.takeException(), isNull);
  });

  testWidgets(
    'shows the latest separate confirmed moisture reading for each method',
    (tester) async {
      final domain = InMemoryDomainStore();
      await _installCropPlotSnapshot(
        domain,
        _scopeA,
        zoneId: _cropPlotZoneAId,
        zoneName: 'Luống A',
        timezone: 'Asia/Ho_Chi_Minh',
        moistureReadings: const [
          {
            'id': '19191919-1919-4191-8191-191919191901',
            'version': 1,
            'zoneId': _cropPlotZoneAId,
            'value': '88',
            'method': 'relative_percent',
            'source': 'manual',
            'measuredAt': '2026-10-17T01:00:00Z',
          },
          {
            'id': '19191919-1919-4191-8191-191919191902',
            'version': 1,
            'zoneId': _cropPlotZoneAId,
            'value': '32.5',
            'method': 'relative_percent',
            'source': 'manual',
            'measuredAt': '2026-10-18T01:00:00Z',
          },
          {
            'id': '19191919-1919-4191-8191-191919191903',
            'version': 1,
            'zoneId': _cropPlotZoneAId,
            'value': '54',
            'method': 'vwc_percent',
            'source': 'manual',
            'measuredAt': '2026-10-18T02:00:00Z',
          },
        ],
      );
      final harness = await _pumpOverview(
        tester,
        scope: _scopeA,
        domain: domain,
      );

      await _openLiveCropPlotDetails(tester, zoneId: _cropPlotZoneAId);

      expect(
        find.byKey(const ValueKey('live-zone-moisture-section')),
        findsOneWidget,
      );
      expect(find.textContaining('32,5%'), findsOneWidget);
      expect(find.textContaining('54%'), findsOneWidget);
      expect(find.textContaining('88%'), findsNothing);
      expect(find.byKey(_liveMoistureCreateKey), findsOneWidget);
      expect(harness.transport.calls, 0);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'keeps moisture projection in the exact farm scope and prefers snapshot duplicates',
    (tester) async {
      const confirmedId = '19191919-1919-4191-8191-191919191911';
      const foreignId = '19191919-1919-4191-8191-191919191912';
      const measuredAt = '2026-10-18T01:00:00Z';
      final domain = InMemoryDomainStore();
      await _installCropPlotSnapshot(
        domain,
        _scopeA,
        zoneId: _cropPlotZoneAId,
        zoneName: 'Luống A',
        timezone: 'Asia/Ho_Chi_Minh',
        moistureReadings: const [
          {
            'id': confirmedId,
            'version': 1,
            'zoneId': _cropPlotZoneAId,
            'value': '32',
            'method': 'relative_percent',
            'source': 'manual',
            'measuredAt': measuredAt,
          },
        ],
      );
      final outbox = InMemoryOutboxStore();
      final duplicate = await outbox.enqueue(
        FarmlyScopedMutation(
          scope: FarmlyMutationScope.farm(
            accountId: _accountId,
            organizationId: _organizationAId,
            farmId: _farmAId,
            continuityEpoch: '37',
          ),
          intent: FarmlyCreateMoistureReadingIntent(
            operationId: '19191919-1919-4191-8191-191919191913',
            continuityEpoch: '37',
            resourceId: confirmedId,
            zoneId: _cropPlotZoneAId,
            value: '90',
            method: 'relative_percent',
            measuredAt: measuredAt,
            nowUtc: DateTime.utc(2026, 10, 18, 1),
          ),
        ),
      );
      await outbox.update(
        duplicate.copyWith(
          status: OutboxEntryStatus.applied,
          appliedRevision: '2',
        ),
      );
      await outbox.enqueue(
        FarmlyScopedMutation(
          scope: FarmlyMutationScope.farm(
            accountId: _accountId,
            organizationId: _organizationAId,
            farmId: _farmAOtherId,
            continuityEpoch: '37',
          ),
          intent: FarmlyCreateMoistureReadingIntent(
            operationId: '19191919-1919-4191-8191-191919191914',
            continuityEpoch: '37',
            resourceId: foreignId,
            zoneId: _cropPlotZoneAId,
            value: '99',
            method: 'relative_percent',
            measuredAt: measuredAt,
            nowUtc: DateTime.utc(2026, 10, 18, 1),
          ),
        ),
      );
      final harness = await _pumpOverview(
        tester,
        scope: _scopeA,
        domain: domain,
        outbox: outbox,
      );

      await _openLiveCropPlotDetails(tester, zoneId: _cropPlotZoneAId);

      expect(
        find.byKey(const ValueKey('live-moisture-reading-$confirmedId')),
        findsOneWidget,
      );
      expect(
        find.byKey(const ValueKey('live-moisture-reading-$foreignId')),
        findsNothing,
      );
      expect(find.textContaining('32%'), findsOneWidget);
      expect(find.textContaining('90%'), findsNothing);
      expect(find.textContaining('99%'), findsNothing);
      expect(harness.transport.calls, 0);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'worker records manual moisture locally with the selected method and farm time',
    (tester) async {
      final workerScope = _scope(
        organizationId: _organizationAId,
        organizationName: 'Tổ chức A',
        farmId: _farmAId,
        farmName: 'Nông trại A',
        continuityEpoch: '37',
        selectionEpoch: 11,
        organizationRole: FarmlyOrganizationRole.member,
        selectedFarmRole: FarmlyFarmGrantRole.worker,
      );
      final domain = InMemoryDomainStore();
      await _installCropPlotSnapshot(
        domain,
        workerScope,
        zoneId: _cropPlotZoneAId,
        zoneName: 'Luống A',
        timezone: 'Asia/Ho_Chi_Minh',
      );
      final harness = await _pumpOverview(
        tester,
        scope: workerScope,
        domain: domain,
        utcNow: () => DateTime.utc(2026, 10, 19, 1, 2, 3),
      );

      await _openLiveCropPlotDetails(tester, zoneId: _cropPlotZoneAId);
      expect(find.byKey(_liveMoistureCreateKey), findsOneWidget);
      expect(find.text('Chưa có số đo độ ẩm cho vùng này.'), findsOneWidget);
      expect(find.textContaining('0%'), findsNothing);
      await tester.ensureVisible(find.byKey(_liveMoistureCreateKey));
      await tester.tap(find.byKey(_liveMoistureCreateKey));
      await tester.pumpAndSettle();
      await tester.enterText(find.byKey(_liveMoistureValueKey), '56,25');
      await tester.tap(find.byKey(_liveMoistureMethodKey));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(_liveMoistureMethodVwcKey));
      await tester.pumpAndSettle();
      await tester.ensureVisible(find.byKey(_liveMoistureSaveKey));
      await tester.tap(find.byKey(_liveMoistureSaveKey));
      await tester.pumpAndSettle();

      final entries = await harness.outbox.entries(
        accountId: _accountId,
        organizationId: _organizationAId,
      );
      final reading = entries.singleWhere(
        (entry) => entry.mutation.intent.type == 'moistureReading.create',
      );
      expect(reading.mutation.scope.farmId, _farmAId);
      expect(reading.mutation.intent.baseVersion, isNull);
      expect(reading.mutation.intent.payload, {
        'zoneId': _cropPlotZoneAId,
        'value': '56.25',
        'method': 'vwc_percent',
        'measuredAt': '2026-10-19T01:02:03.000Z',
      });
      expect(reading.mutation.intent.payload, isNot(contains('source')));
      expect(reading.status, OutboxEntryStatus.pending);
      expect(find.text(_savedPendingCopy), findsOneWidget);
      expect(
        find.byKey(
          ValueKey(
            'live-moisture-reading-${reading.mutation.intent.resourceId}',
          ),
        ),
        findsOneWidget,
      );
      expect(harness.transport.calls, 0);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'locks moisture value and keeps the submitted value while saving',
    (tester) async {
      final enqueueGate = Completer<void>();
      final domain = InMemoryDomainStore();
      await _installCropPlotSnapshot(
        domain,
        _scopeA,
        zoneId: _cropPlotZoneAId,
        zoneName: 'Luống A',
      );
      final harness = await _pumpOverview(
        tester,
        scope: _scopeA,
        domain: domain,
        utcNow: () => DateTime.utc(2026, 10, 19, 1, 2, 3),
        enqueueDelay: enqueueGate.future,
      );

      try {
        await _openLiveCropPlotDetails(tester, zoneId: _cropPlotZoneAId);
        await tester.ensureVisible(find.byKey(_liveMoistureCreateKey));
        await tester.tap(find.byKey(_liveMoistureCreateKey));
        await tester.pumpAndSettle();
        await tester.enterText(find.byKey(_liveMoistureValueKey), '56,25');
        await tester.ensureVisible(find.byKey(_liveMoistureSaveKey));
        await tester.tap(find.byKey(_liveMoistureSaveKey));
        await tester.pump();

        final field = tester.widget<DecimalField>(
          find.byKey(_liveMoistureValueKey),
        );
        expect(field.enabled, isFalse);
        field.controller.text = '82';
        enqueueGate.complete();
        await tester.pumpAndSettle();

        final entry =
            (await harness.outbox.entries(
              accountId: _accountId,
              organizationId: _organizationAId,
            )).singleWhere(
              (candidate) =>
                  candidate.mutation.intent.type == 'moistureReading.create',
            );
        expect(entry.mutation.intent.payload['value'], '56.25');
        expect(harness.transport.calls, 0);
        expect(tester.takeException(), isNull);
      } finally {
        if (!enqueueGate.isCompleted) enqueueGate.complete();
      }
    },
  );

  testWidgets('farm change locks an open manual moisture form', (tester) async {
    final domain = InMemoryDomainStore();
    await _installCropPlotSnapshot(
      domain,
      _scopeA,
      zoneId: _cropPlotZoneAId,
      zoneName: 'Luống A',
      timezone: 'Asia/Ho_Chi_Minh',
    );
    await _installEmptyBootstrap(domain, _scopeB);
    final harness = await _pumpOverview(tester, scope: _scopeA, domain: domain);

    await _openLiveCropPlotDetails(tester, zoneId: _cropPlotZoneAId);
    await tester.ensureVisible(find.byKey(_liveMoistureCreateKey));
    await tester.tap(find.byKey(_liveMoistureCreateKey));
    await tester.pumpAndSettle();
    await tester.enterText(find.byKey(_liveMoistureValueKey), '25');
    harness.scopeController.replace(_scopeB);
    await tester.pumpAndSettle();

    expect(
      tester.widget<FilledButton>(find.byKey(_liveMoistureSaveKey)).onPressed,
      isNull,
    );
    await tester.tap(find.byKey(_liveMoistureSaveKey));
    await tester.pumpAndSettle();
    expect(
      await harness.outbox.entries(
        accountId: _accountId,
        organizationId: _organizationAId,
      ),
      isEmpty,
    );
    expect(
      await harness.outbox.entries(
        accountId: _accountId,
        organizationId: _organizationBId,
      ),
      isEmpty,
    );
    expect(harness.transport.calls, 0);
    expect(tester.takeException(), isNull);
  });

  testWidgets('organization viewers cannot record manual moisture', (
    tester,
  ) async {
    final viewerScope = _scope(
      organizationId: _organizationAId,
      organizationName: 'Tổ chức A',
      farmId: _farmAId,
      farmName: 'Nông trại A',
      continuityEpoch: '37',
      selectionEpoch: 11,
      organizationRole: FarmlyOrganizationRole.viewer,
      selectedFarmRole: FarmlyFarmGrantRole.manager,
    );
    final domain = InMemoryDomainStore();
    await _installCropPlotSnapshot(
      domain,
      viewerScope,
      zoneId: _cropPlotZoneAId,
      zoneName: 'Luống A',
      timezone: 'Asia/Ho_Chi_Minh',
    );
    final harness = await _pumpOverview(
      tester,
      scope: viewerScope,
      domain: domain,
    );

    await _openLiveCropPlotDetails(tester, zoneId: _cropPlotZoneAId);

    expect(find.byKey(_liveMoistureCreateKey), findsNothing);
    expect(find.text('Chưa có số đo độ ẩm cho vùng này.'), findsOneWidget);
    expect(harness.transport.calls, 0);
    expect(tester.takeException(), isNull);
  });
}
