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
import 'package:farmly_mobile/features/livestock/live_livestock.dart';
import 'package:farmly_mobile/features/livestock/livestock_screen.dart';
import 'package:farmly_mobile/features/organizations/organization_repository.dart';
import 'package:farmly_mobile/features/organizations/organization_scope_controller.dart';
import 'package:farmly_mobile/l10n/generated/app_localizations.dart';

const _accountId = '11111111-1111-4111-8111-111111111111';
const _organizationId = '22222222-2222-4222-8222-222222222222';
const _farmId = '33333333-3333-4333-8333-333333333333';
const _otherFarmId = '33333333-3333-4333-8333-333333333334';
const _batchHerdId = '44444444-4444-4444-8444-444444444444';
const _trackedHerdId = '55555555-5555-4555-8555-555555555555';
const _animalId = '66666666-6666-4666-8666-666666666666';
const _duplicateAnimalId = '66666666-6666-4666-8666-666666666667';
const _archivedHerdId = '77777777-7777-4777-8777-777777777777';
const _archivedAnimalId = '77777777-7777-4777-8777-777777777778';
const _pendingHerdId = '88888888-8888-4888-8888-888888888881';
const _awaitingHerdId = '88888888-8888-4888-8888-888888888882';
const _failedHerdId = '88888888-8888-4888-8888-888888888883';
const _foreignHerdId = '88888888-8888-4888-8888-888888888884';
const _wrongEpochHerdId = '88888888-8888-4888-8888-888888888885';
const _pendingAnimalId = '88888888-8888-4888-8888-888888888889';
const _failedAnimalId = '88888888-8888-4888-8888-888888888890';

const _session = FarmlyAuthSession(
  user: FarmlyAuthUser(
    id: _accountId,
    name: 'Test Farmer',
    email: 'farmer@farmly.test',
  ),
);

class _SignedOutSessionController extends FarmlyAuthSessionController {
  @override
  Future<FarmlyAuthSession?> build() async => null;
}

class _NoOrganizationScopeController
    extends SelectedOrganizationScopeController {
  @override
  FarmlyOrganizationScope? build() => null;
}

class _SignedInSessionController extends FarmlyAuthSessionController {
  @override
  Future<FarmlyAuthSession?> build() async => _session;
}

class _SelectedScopeController extends SelectedOrganizationScopeController {
  _SelectedScopeController(this.initialScope);

  final FarmlyOrganizationScope? initialScope;

  @override
  FarmlyOrganizationScope? build() => initialScope;

  void replaceScope(FarmlyOrganizationScope? scope) => state = scope;
}

class _NoTransportCalls implements SyncTransport {
  int calls = 0;

  Never _unexpectedCall() {
    calls++;
    throw StateError('livestock widget tests must not call the transport');
  }

  @override
  Future<MutationBatchResult> submitMutations({
    required FarmlyMutationScope scope,
    required List<FarmlyMutationIntent> operations,
  }) async => _unexpectedCall();

  @override
  Future<List<OperationStatusEntry>> operationStatus({
    required String accountId,
    required List<String> operationIds,
  }) async => _unexpectedCall();

  @override
  Future<ChangeFeedPage> fetchChanges({
    required FarmlyMutationScope scope,
    required String cursor,
  }) async => _unexpectedCall();

  @override
  Future<BootstrapManifest> createBootstrap({
    required FarmlyMutationScope scope,
    required String operationId,
  }) async => _unexpectedCall();

  @override
  Future<BootstrapPage> fetchBootstrapPage({
    required FarmlyMutationScope scope,
    required String snapshotId,
    String? pageCursor,
  }) async => _unexpectedCall();
}

final class _LivestockHarness {
  const _LivestockHarness({
    required this.outbox,
    required this.transport,
    required this.container,
  });

  final InMemoryOutboxStore outbox;
  final _NoTransportCalls transport;
  final ProviderContainer container;
}

FarmlyOrganizationScope _scope({
  FarmlyOrganizationRole organizationRole = FarmlyOrganizationRole.member,
  FarmlyFarmGrantRole farmRole = FarmlyFarmGrantRole.worker,
  String? selectedFarmId = _farmId,
  List<FarmlyDirectoryFarm>? farms,
}) => FarmlyOrganizationScope(
  organization: FarmlyOrganization(
    id: _organizationId,
    name: 'Tổ chức kiểm thử',
    status: FarmlyOrganizationStatus.active,
    policyVersion: '3',
    role: organizationRole,
    membershipVersion: 1,
  ),
  directory: FarmlyFarmDirectory(
    scopePolicyVersion: '3',
    continuityEpoch: '37',
    farms:
        farms ??
        [
          FarmlyDirectoryFarm(
            id: _farmId,
            name: 'Nông trại kiểm thử',
            status: FarmlyFarmStatus.active,
            grantRole: farmRole,
          ),
        ],
  ),
  epoch: 11,
  selectedFarmId: selectedFarmId,
);

FarmlyOrganizationScope _twoFarmManagerScope({
  String selectedFarmId = _farmId,
}) => _scope(
  farmRole: FarmlyFarmGrantRole.manager,
  selectedFarmId: selectedFarmId,
  farms: const [
    FarmlyDirectoryFarm(
      id: _farmId,
      name: 'Nông trại kiểm thử',
      status: FarmlyFarmStatus.active,
      grantRole: FarmlyFarmGrantRole.manager,
    ),
    FarmlyDirectoryFarm(
      id: _otherFarmId,
      name: 'Trang trại khác',
      status: FarmlyFarmStatus.active,
      grantRole: FarmlyFarmGrantRole.manager,
    ),
  ],
);

Future<void> _installLivestockSnapshot(
  InMemoryDomainStore domain, {
  List<Map<String, Object?>> observationRecords = const [],
  List<Map<String, Object?>> productionRecords = const [],
  List<Map<String, Object?>> herdRecords = const [
    {
      'id': _batchHerdId,
      'version': 1,
      'mode': 'batch',
      'species': 'Bò lai Sind',
      'status': 'active',
      'headcount': 8,
    },
    {
      'id': _trackedHerdId,
      'version': 1,
      'mode': 'tracked',
      'species': 'Bò sữa',
      'status': 'active',
      'headcount': 1,
    },
    {
      'id': _archivedHerdId,
      'version': 2,
      'mode': 'batch',
      'species': 'Đàn đã lưu trữ',
      'status': 'archived',
      'headcount': 90,
    },
  ],
  List<Map<String, Object?>> animalRecords = const [
    {
      'id': _animalId,
      'version': 1,
      'herdId': _trackedHerdId,
      'tag': 'COW-001',
      'name': 'Mây',
      'birthDate': '2022-05-11',
      'status': 'alive',
      'archived': false,
    },
  ],
}) => domain.installBootstrap(
  scopeKey: '$_accountId|$_organizationId|$_farmId',
  blocks: [
    BootstrapBlock(entity: 'herd', records: herdRecords),
    BootstrapBlock(entity: 'animal', records: animalRecords),
    if (observationRecords.isNotEmpty)
      BootstrapBlock(entity: 'animalObservation', records: observationRecords),
    if (productionRecords.isNotEmpty)
      BootstrapBlock(entity: 'productionRecord', records: productionRecords),
  ],
  cursor: const SyncCursorState(
    cursor: 'cursor-livestock',
    highWatermark: '1',
    continuityEpoch: '37',
    scopePolicyVersion: '3',
  ),
);

Future<OutboxEntry> _seedHerdCreate({
  required InMemoryOutboxStore outbox,
  required FarmlyMutationScope scope,
  required String operationId,
  required String resourceId,
  required String mode,
  required String species,
  OutboxEntryStatus status = OutboxEntryStatus.pending,
}) async {
  final entry = await outbox.enqueue(
    FarmlyScopedMutation(
      scope: scope,
      intent: FarmlyCreateHerdIntent(
        operationId: operationId,
        continuityEpoch: scope.continuityEpoch,
        resourceId: resourceId,
        mode: mode,
        species: species,
      ),
    ),
  );
  if (status == OutboxEntryStatus.pending) return entry;
  final updated = entry.copyWith(status: status);
  await outbox.update(updated);
  return updated;
}

Future<OutboxEntry> _seedAnimalCreate({
  required InMemoryOutboxStore outbox,
  required FarmlyMutationScope scope,
  required String operationId,
  required String resourceId,
  required String herdId,
  required String tag,
  String? name,
  OutboxEntryStatus status = OutboxEntryStatus.pending,
}) async {
  final entry = await outbox.enqueue(
    FarmlyScopedMutation(
      scope: scope,
      intent: FarmlyCreateAnimalIntent(
        operationId: operationId,
        continuityEpoch: scope.continuityEpoch,
        resourceId: resourceId,
        herdId: herdId,
        tag: tag,
        name: name,
      ),
    ),
  );
  if (status == OutboxEntryStatus.pending) return entry;
  final updated = entry.copyWith(status: status);
  await outbox.update(updated);
  return updated;
}

Future<OutboxEntry> _seedAnimalUpdate({
  required InMemoryOutboxStore outbox,
  required FarmlyMutationScope scope,
  required String operationId,
  required String resourceId,
  required int baseVersion,
  required Map<String, Object?> payload,
  required OutboxEntryStatus status,
}) async {
  final intent = FarmlyMutationIntent.fromJson({
    'schemaVersion': FarmlyMutationIntent.schemaVersion,
    'continuityEpoch': scope.continuityEpoch,
    'operationId': operationId,
    'type': 'animal.update',
    'resourceId': resourceId,
    'baseVersion': baseVersion,
    'dependsOn': const <String>[],
    'payload': payload,
  });
  final entry = await outbox.enqueue(
    FarmlyScopedMutation(scope: scope, intent: intent),
  );
  final updated = entry.copyWith(status: status);
  await outbox.update(updated);
  return updated;
}

Future<_LivestockHarness> _pumpLivestock(
  WidgetTester tester, {
  required FarmlyOrganizationScope? scope,
  InMemoryDomainStore? domain,
  InMemoryOutboxStore? outbox,
}) async {
  final outboxStore = outbox ?? InMemoryOutboxStore();
  final transport = _NoTransportCalls();
  final engine = FarmlySyncEngine(
    outbox: outboxStore,
    transport: transport,
    domain: domain ?? InMemoryDomainStore(),
  );
  final container = ProviderContainer(
    overrides: [
      farmlyAuthSessionProvider.overrideWith(_SignedInSessionController.new),
      selectedOrganizationScopeProvider.overrideWith(
        () => _SelectedScopeController(scope),
      ),
      syncEngineProvider.overrideWith((ref) async => engine),
      farmlyLivestockDemoPreviewProvider.overrideWithValue(false),
    ],
  );

  addTearDown(container.dispose);
  tester.view.physicalSize = const Size(390, 844);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  await tester.pumpWidget(
    UncontrolledProviderScope(
      container: container,
      child: MaterialApp(
        theme: buildFarmTheme(),
        builder: (context, child) => MediaQuery(
          data: MediaQuery.of(context).copyWith(disableAnimations: true),
          child: child ?? const SizedBox.shrink(),
        ),
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        locale: const Locale('vi'),
        home: const LivestockScreen(),
      ),
    ),
  );
  await tester.pumpAndSettle();
  return _LivestockHarness(
    outbox: outboxStore,
    transport: transport,
    container: container,
  );
}

Future<void> _createProduction(
  WidgetTester tester, {
  required Finder action,
  required String quantity,
  required DateTime recordedOn,
}) async {
  await tester.ensureVisible(action);
  await tester.tap(action);
  await tester.pumpAndSettle();
  expect(
    find.text('Ngày ghi nhận sản lượng (theo lịch nông trại)'),
    findsOneWidget,
  );
  expect(
    find.text('Chọn ngày dương lịch tại nông trại, không phải ngày UTC.'),
    findsOneWidget,
  );
  await tester.enterText(
    find.byKey(const ValueKey('live-production-quantity')),
    quantity,
  );
  final dateButton = find.byKey(const ValueKey('live-production-recorded-on'));
  await tester.ensureVisible(dateButton);
  await tester.tap(dateButton);
  await tester.pumpAndSettle();
  final dialog = find.byType(DatePickerDialog);
  expect(dialog, findsOneWidget);
  final localizations = MaterialLocalizations.of(tester.element(dialog));
  await tester.tap(find.byTooltip(localizations.inputDateModeButtonLabel));
  await tester.pumpAndSettle();
  await tester.enterText(
    find.descendant(of: dialog, matching: find.byType(TextField)),
    localizations.formatCompactDate(recordedOn),
  );
  await tester.pumpAndSettle();
  await tester.tap(
    find.descendant(of: dialog, matching: find.byType(TextButton)).last,
  );
  await tester.pumpAndSettle();
  await tester.tap(find.byKey(const ValueKey('live-production-save')));
  await tester.pumpAndSettle();
}

Future<void> _createMovement(
  WidgetTester tester, {
  required Finder action,
  required String movementType,
  required String count,
  DateTime? occurredOn,
  bool submit = true,
}) async {
  await tester.ensureVisible(action);
  await tester.tap(action);
  await tester.pumpAndSettle();
  final selector = find.byKey(const ValueKey('live-movement-type'));
  final dropdown = tester.widget<DropdownButton<String>>(
    find.descendant(
      of: selector,
      matching: find.byType(DropdownButton<String>),
    ),
  );
  final selectedItem = dropdown.items!.singleWhere(
    (item) => item.value == movementType,
  );
  final optionLabel = (selectedItem.child as Text).data!;
  await tester.tap(selector);
  await tester.pumpAndSettle();
  await tester.tap(find.text(optionLabel).last);
  await tester.pumpAndSettle();
  await tester.enterText(
    find.byKey(const ValueKey('live-movement-count')),
    count,
  );
  if (occurredOn != null) {
    final dateButton = find.byKey(const ValueKey('live-movement-occurred-on'));
    await tester.ensureVisible(dateButton);
    await tester.tap(dateButton);
    await tester.pumpAndSettle();
    final dialog = find.byType(DatePickerDialog);
    expect(dialog, findsOneWidget);
    final localizations = MaterialLocalizations.of(tester.element(dialog));
    await tester.tap(find.byTooltip(localizations.inputDateModeButtonLabel));
    await tester.pumpAndSettle();
    await tester.enterText(
      find.descendant(of: dialog, matching: find.byType(TextField)),
      localizations.formatCompactDate(occurredOn),
    );
    await tester.pumpAndSettle();
    await tester.tap(
      find.descendant(of: dialog, matching: find.byType(TextButton)).last,
    );
    await tester.pumpAndSettle();
  }
  if (submit) {
    await tester.tap(find.byKey(const ValueKey('live-movement-save')));
    await tester.pumpAndSettle();
  }
}

Future<void> _createObservation(
  WidgetTester tester, {
  required Finder action,
  required String note,
  String? kind,
  DateTime? observedOn,
}) async {
  await tester.ensureVisible(action);
  await tester.tap(action);
  await tester.pumpAndSettle();
  await tester.enterText(
    find.byKey(const ValueKey('live-animal-observation-note')),
    note,
  );
  if (kind != null) {
    final selector = find.byKey(const ValueKey('live-animal-observation-kind'));
    final dropdown = tester.widget<DropdownButton<String>>(
      find.descendant(
        of: selector,
        matching: find.byType(DropdownButton<String>),
      ),
    );
    final selectedItem = dropdown.items!.singleWhere(
      (item) => item.value == kind,
    );
    final optionLabel = (selectedItem.child as Text).data!;
    await tester.tap(selector);
    await tester.pumpAndSettle();
    await tester.tap(find.text(optionLabel).last);
    await tester.pumpAndSettle();
  }
  if (observedOn != null) {
    final dateButton = find.byKey(
      const ValueKey('live-animal-observation-date'),
    );
    await tester.ensureVisible(dateButton);
    await tester.tap(dateButton);
    await tester.pumpAndSettle();
    final dialog = find.byType(DatePickerDialog);
    expect(dialog, findsOneWidget);
    final localizations = MaterialLocalizations.of(tester.element(dialog));
    await tester.tap(find.byTooltip(localizations.inputDateModeButtonLabel));
    await tester.pumpAndSettle();
    await tester.enterText(
      find.descendant(of: dialog, matching: find.byType(TextField)),
      localizations.formatCompactDate(observedOn),
    );
    await tester.pumpAndSettle();
    await tester.tap(
      find.descendant(of: dialog, matching: find.byType(TextButton)).last,
    );
    await tester.pumpAndSettle();
  }
  await tester.tap(find.byKey(const ValueKey('live-animal-observation-save')));
  await tester.pumpAndSettle();
}

Future<void> _createHerd(
  WidgetTester tester, {
  required String mode,
  required String species,
}) async {
  final action = find.byKey(const ValueKey('live-herd-create'));
  await tester.ensureVisible(action);
  await tester.tap(action);
  await tester.pumpAndSettle();
  await tester.tap(find.byKey(ValueKey('live-herd-mode-$mode')));
  await tester.enterText(
    find.byKey(const ValueKey('live-herd-species')),
    species,
  );
  await tester.tap(find.byKey(const ValueKey('live-herd-save')));
  await tester.pumpAndSettle();
}

Future<void> _createAnimal(
  WidgetTester tester, {
  required Finder action,
  required String tag,
  required String name,
}) async {
  await tester.ensureVisible(action);
  await tester.tap(action);
  await tester.pumpAndSettle();
  await tester.enterText(find.byKey(const ValueKey('live-animal-tag')), tag);
  await tester.enterText(find.byKey(const ValueKey('live-animal-name')), name);
  await tester.tap(find.byKey(const ValueKey('live-animal-save')));
  await tester.pumpAndSettle();
}

Future<void> _openAnimalEdit(
  WidgetTester tester, {
  String animalId = _animalId,
}) async {
  final action = find.byKey(ValueKey('live-animal-edit-$animalId'));
  await _scrollLivestockToKey(tester, action);
  expect(action, findsOneWidget);
  await tester.tap(action);
  await tester.pumpAndSettle();
}

Future<void> _saveAnimalEdit(
  WidgetTester tester, {
  required String tag,
  String? name,
}) async {
  await tester.enterText(find.byKey(const ValueKey('live-animal-tag')), tag);
  if (name != null) {
    await tester.enterText(
      find.byKey(const ValueKey('live-animal-name')),
      name,
    );
  }
  await tester.tap(find.byKey(const ValueKey('live-animal-edit-save')));
  await tester.pumpAndSettle();
}

Future<void> _scrollLivestockToKey(WidgetTester tester, Finder finder) async {
  final list = find.byType(ListView).first;
  for (var attempt = 0; attempt < 4; attempt += 1) {
    await tester.drag(list, const Offset(0, 800));
    await tester.pumpAndSettle();
  }
  for (
    var attempt = 0;
    attempt < 8 && finder.evaluate().isEmpty;
    attempt += 1
  ) {
    await tester.drag(list, const Offset(0, -400));
    await tester.pumpAndSettle();
  }
  if (finder.evaluate().isNotEmpty) await tester.ensureVisible(finder);
}

void _expectActionUnavailable(WidgetTester tester, Finder action) {
  if (action.evaluate().isEmpty) return;
  final button = find.descendant(
    of: action,
    matching: find.byType(OutlinedButton),
  );
  expect(button, findsOneWidget);
  expect(tester.widget<OutlinedButton>(button).onPressed, isNull);
}

void main() {
  testWidgets('signed-out livestock screen never falls back to demo herds', (
    tester,
  ) async {
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          farmlyAuthSessionProvider.overrideWith(
            _SignedOutSessionController.new,
          ),
          selectedOrganizationScopeProvider.overrideWith(
            _NoOrganizationScopeController.new,
          ),
          farmlySyncScopeProvider.overrideWith((ref) async => null),
        ],
        child: MaterialApp(
          theme: buildFarmTheme(),
          builder: (context, child) => MediaQuery(
            data: MediaQuery.of(context).copyWith(disableAnimations: true),
            child: child ?? const SizedBox.shrink(),
          ),
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          locale: const Locale('vi'),
          home: const LivestockScreen(),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('Bò lai Sind · Theo dõi từng con'), findsNothing);
    expect(find.text('Gà ri thả vườn · Đàn theo lô'), findsNothing);
    expect(find.textContaining('Tổng đàn: 123 con'), findsNothing);
  });

  testWidgets(
    'worker can save production for a batch herd and tracked animal offline',
    (tester) async {
      final domain = InMemoryDomainStore();
      await _installLivestockSnapshot(domain);
      final harness = await _pumpLivestock(
        tester,
        scope: _scope(),
        domain: domain,
      );
      final herdAction = find.byKey(
        const ValueKey('live-production-create-herd-$_batchHerdId'),
      );
      final animalAction = find.byKey(
        const ValueKey('live-production-create-animal-$_animalId'),
      );

      expect(find.text('Tổng đàn: 9 con'), findsOneWidget);
      expect(find.textContaining('Đàn đã lưu trữ'), findsNothing);
      expect(herdAction, findsOneWidget);
      expect(animalAction, findsOneWidget);
      expect(
        tester
            .widget<OutlinedButton>(
              find.descendant(
                of: herdAction,
                matching: find.byType(OutlinedButton),
              ),
            )
            .onPressed,
        isNotNull,
      );
      expect(
        tester
            .widget<OutlinedButton>(
              find.descendant(
                of: animalAction,
                matching: find.byType(OutlinedButton),
              ),
            )
            .onPressed,
        isNotNull,
      );

      await _createProduction(
        tester,
        action: herdAction,
        quantity: '12.75',
        recordedOn: DateTime(2026, 10, 17),
      );
      final herdEntries = await harness.outbox.entries(
        accountId: _accountId,
        organizationId: _organizationId,
      );
      expect(herdEntries, hasLength(1));
      expect(herdEntries.single.status, OutboxEntryStatus.pending);
      expect(
        herdEntries.single.mutation.intent.type,
        'productionRecord.create',
      );
      expect(herdEntries.single.mutation.intent.payload, {
        'herdId': _batchHerdId,
        'product': 'milk',
        'quantity': '12.75',
        'recordedOn': '2026-10-17',
      });
      expect(harness.transport.calls, 0);

      await _createProduction(
        tester,
        action: animalAction,
        quantity: '3.5',
        recordedOn: DateTime(2026, 10, 16),
      );
      final entries = await harness.outbox.entries(
        accountId: _accountId,
        organizationId: _organizationId,
      );
      expect(entries, hasLength(2));
      final animalEntry = entries.singleWhere(
        (entry) => entry.mutation.intent.payload.containsKey('animalId'),
      );
      expect(animalEntry.status, OutboxEntryStatus.pending);
      expect(animalEntry.mutation.intent.type, 'productionRecord.create');
      expect(animalEntry.mutation.intent.payload, {
        'animalId': _animalId,
        'product': 'milk',
        'quantity': '3.5',
        'recordedOn': '2026-10-16',
      });
      expect(harness.transport.calls, 0);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets('viewer cannot record batch or tracked-animal production', (
    tester,
  ) async {
    final domain = InMemoryDomainStore();
    await _installLivestockSnapshot(domain);
    await _pumpLivestock(
      tester,
      scope: _scope(farmRole: FarmlyFarmGrantRole.viewer),
      domain: domain,
    );
    final herdAction = find.byKey(
      const ValueKey('live-production-create-herd-$_batchHerdId'),
    );
    final animalAction = find.byKey(
      const ValueKey('live-production-create-animal-$_animalId'),
    );

    expect(herdAction, findsOneWidget);
    expect(animalAction, findsOneWidget);
    expect(
      tester
          .widget<OutlinedButton>(
            find.descendant(
              of: herdAction,
              matching: find.byType(OutlinedButton),
            ),
          )
          .onPressed,
      isNull,
    );
    expect(
      tester
          .widget<OutlinedButton>(
            find.descendant(
              of: animalAction,
              matching: find.byType(OutlinedButton),
            ),
          )
          .onPressed,
      isNull,
    );
  });

  testWidgets('production date fields use livestock wording', (tester) async {
    final domain = InMemoryDomainStore();
    await _installLivestockSnapshot(domain);
    await _pumpLivestock(tester, scope: _scope(), domain: domain);
    await tester.tap(
      find.byKey(const ValueKey('live-production-create-herd-$_batchHerdId')),
    );
    await tester.pumpAndSettle();

    expect(
      find.text('Ngày ghi nhận sản lượng (theo lịch nông trại)'),
      findsOneWidget,
    );
    expect(
      find.text('Chọn ngày dương lịch tại nông trại, không phải ngày UTC.'),
      findsOneWidget,
    );
  });

  testWidgets('confirmed observations project only to visible subjects', (
    tester,
  ) async {
    final domain = InMemoryDomainStore();
    await _installLivestockSnapshot(
      domain,
      observationRecords: const [
        {
          'id': '00000000-0000-4000-8000-000000000601',
          'herdId': _batchHerdId,
          'animalId': null,
          'kind': 'vet',
          'note': 'Confirmed herd health check',
          'observedOn': '2026-10-18',
        },
        {
          'id': '00000000-0000-4000-8000-000000000602',
          'herdId': _archivedHerdId,
          'animalId': null,
          'kind': 'note',
          'note': 'Archived herd observation hidden',
          'observedOn': '2026-10-18',
        },
      ],
    );
    await _pumpLivestock(tester, scope: _scope(), domain: domain);

    expect(
      find.byKey(
        const ValueKey(
          'live-animal-observation-00000000-0000-4000-8000-000000000601',
        ),
      ),
      findsOneWidget,
    );
    expect(find.textContaining('Confirmed herd health check'), findsOneWidget);
    expect(
      find.textContaining('Archived herd observation hidden'),
      findsNothing,
    );
    expect(tester.takeException(), isNull);
  });

  testWidgets('confirmed observation suppresses its applied outbox duplicate', (
    tester,
  ) async {
    const observationId = '00000000-0000-4000-8000-000000000603';
    final domain = InMemoryDomainStore();
    await _installLivestockSnapshot(
      domain,
      observationRecords: const [
        {
          'id': observationId,
          'herdId': _batchHerdId,
          'animalId': null,
          'kind': 'vet',
          'note': 'Confirmed snapshot observation',
          'observedOn': null,
        },
      ],
    );
    final outbox = InMemoryOutboxStore();
    final mutationScope = FarmlyMutationScope.farm(
      accountId: _accountId,
      organizationId: _organizationId,
      farmId: _farmId,
      continuityEpoch: '37',
    );
    final applied = await outbox.enqueue(
      FarmlyScopedMutation(
        scope: mutationScope,
        intent: FarmlyCreateAnimalObservationIntent(
          operationId: '00000000-0000-4000-8000-000000000604',
          continuityEpoch: '37',
          resourceId: observationId,
          herdId: _batchHerdId,
          note: 'Applied outbox duplicate',
          kind: 'vet',
        ),
      ),
    );
    await outbox.update(
      applied.copyWith(status: OutboxEntryStatus.applied, appliedRevision: '2'),
    );

    await _pumpLivestock(
      tester,
      scope: _scope(),
      domain: domain,
      outbox: outbox,
    );

    final observation = find.byKey(
      const ValueKey('live-animal-observation-$observationId'),
    );
    expect(observation, findsOneWidget);
    expect(
      find.textContaining('Confirmed snapshot observation'),
      findsOneWidget,
    );
    expect(find.textContaining('Applied outbox duplicate'), findsNothing);
    final rendered = tester.widget<Text>(observation);
    expect(
      rendered.data,
      '${AppLocalizations.of(tester.element(observation)).liveAnimalObservationVeterinary} · Confirmed snapshot observation',
    );
    expect(tester.takeException(), isNull);
  });

  testWidgets('worker can save herd and tracked-animal observations offline', (
    tester,
  ) async {
    final domain = InMemoryDomainStore();
    await _installLivestockSnapshot(domain);
    final harness = await _pumpLivestock(
      tester,
      scope: _scope(farmRole: FarmlyFarmGrantRole.worker),
      domain: domain,
    );
    final herdAction = find.byKey(
      const ValueKey('live-animal-observation-create-herd-$_batchHerdId'),
    );
    final animalAction = find.byKey(
      const ValueKey('live-animal-observation-create-animal-$_animalId'),
    );

    expect(herdAction, findsOneWidget);
    expect(animalAction, findsOneWidget);
    expect(
      tester
          .widget<OutlinedButton>(
            find.descendant(
              of: herdAction,
              matching: find.byType(OutlinedButton),
            ),
          )
          .onPressed,
      isNotNull,
    );
    expect(
      tester
          .widget<OutlinedButton>(
            find.descendant(
              of: animalAction,
              matching: find.byType(OutlinedButton),
            ),
          )
          .onPressed,
      isNotNull,
    );

    await _createObservation(
      tester,
      action: herdAction,
      note: 'Routine herd check',
      kind: 'vet',
      observedOn: DateTime(2026, 10, 18),
    );
    var entries = await harness.outbox.entries(
      accountId: _accountId,
      organizationId: _organizationId,
    );
    expect(entries, hasLength(1));
    final herdEntry = entries.single;
    expect(herdEntry.status, OutboxEntryStatus.pending);
    expect(herdEntry.mutation.intent.type, 'animalObservation.create');
    expect(herdEntry.mutation.scope.kind, FarmlyMutationScopeKind.farm);
    expect(herdEntry.mutation.scope.organizationId, _organizationId);
    expect(herdEntry.mutation.scope.farmId, _farmId);
    expect(herdEntry.mutation.scope.continuityEpoch, '37');
    expect(herdEntry.mutation.intent.payload, {
      'herdId': _batchHerdId,
      'note': 'Routine herd check',
      'kind': 'vet',
      'observedOn': '2026-10-18',
    });
    expect(harness.transport.calls, 0);
    final herdObservationLine = find.byKey(
      ValueKey(
        'live-animal-observation-${herdEntry.mutation.intent.resourceId}',
      ),
    );
    await tester.ensureVisible(herdObservationLine);
    expect(herdObservationLine, findsOneWidget);
    expect(find.textContaining('Routine herd check'), findsOneWidget);

    await _createObservation(tester, action: animalAction, note: 'Mây is calm');
    entries = await harness.outbox.entries(
      accountId: _accountId,
      organizationId: _organizationId,
    );
    expect(entries, hasLength(2));
    final animalEntry = entries.singleWhere(
      (entry) => entry.mutation.intent.payload.containsKey('animalId'),
    );
    expect(animalEntry.status, OutboxEntryStatus.pending);
    expect(animalEntry.mutation.intent.type, 'animalObservation.create');
    expect(animalEntry.mutation.scope.farmId, _farmId);
    expect(animalEntry.mutation.intent.payload, {
      'animalId': _animalId,
      'note': 'Mây is calm',
    });
    expect(harness.transport.calls, 0);
    final animalObservationLine = find.byKey(
      ValueKey(
        'live-animal-observation-${animalEntry.mutation.intent.resourceId}',
      ),
    );
    await tester.ensureVisible(animalObservationLine);
    expect(animalObservationLine, findsOneWidget);
    expect(find.textContaining('Mây is calm'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('manager can create herd and animal observations', (
    tester,
  ) async {
    final domain = InMemoryDomainStore();
    await _installLivestockSnapshot(domain);
    final harness = await _pumpLivestock(
      tester,
      scope: _scope(farmRole: FarmlyFarmGrantRole.manager),
      domain: domain,
    );
    final herdAction = find.byKey(
      const ValueKey('live-animal-observation-create-herd-$_batchHerdId'),
    );
    final animalAction = find.byKey(
      const ValueKey('live-animal-observation-create-animal-$_animalId'),
    );

    expect(herdAction, findsOneWidget);
    expect(animalAction, findsOneWidget);
    expect(
      tester
          .widget<OutlinedButton>(
            find.descendant(
              of: herdAction,
              matching: find.byType(OutlinedButton),
            ),
          )
          .onPressed,
      isNotNull,
    );
    expect(
      tester
          .widget<OutlinedButton>(
            find.descendant(
              of: animalAction,
              matching: find.byType(OutlinedButton),
            ),
          )
          .onPressed,
      isNotNull,
    );
    expect(
      await harness.outbox.entries(
        accountId: _accountId,
        organizationId: _organizationId,
      ),
      isEmpty,
    );
    expect(harness.transport.calls, 0);
  });

  testWidgets('viewer cannot create herd or animal observations', (
    tester,
  ) async {
    final domain = InMemoryDomainStore();
    await _installLivestockSnapshot(domain);
    final harness = await _pumpLivestock(
      tester,
      scope: _scope(
        organizationRole: FarmlyOrganizationRole.viewer,
        farmRole: FarmlyFarmGrantRole.manager,
      ),
      domain: domain,
    );
    _expectActionUnavailable(
      tester,
      find.byKey(
        const ValueKey('live-animal-observation-create-herd-$_batchHerdId'),
      ),
    );
    _expectActionUnavailable(
      tester,
      find.byKey(
        const ValueKey('live-animal-observation-create-animal-$_animalId'),
      ),
    );
    expect(
      await harness.outbox.entries(
        accountId: _accountId,
        organizationId: _organizationId,
      ),
      isEmpty,
    );
    expect(harness.transport.calls, 0);
  });

  testWidgets('manager can save each active batch movement offline', (
    tester,
  ) async {
    final domain = InMemoryDomainStore();
    await _installLivestockSnapshot(domain);
    final harness = await _pumpLivestock(
      tester,
      scope: _scope(farmRole: FarmlyFarmGrantRole.manager),
      domain: domain,
    );
    final activeBatchAction = find.byKey(
      const ValueKey('live-movement-create-herd-$_batchHerdId'),
    );

    expect(activeBatchAction, findsOneWidget);
    expect(
      find.byKey(const ValueKey('live-movement-create-herd-$_trackedHerdId')),
      findsNothing,
    );
    expect(
      find.byKey(const ValueKey('live-movement-create-herd-$_archivedHerdId')),
      findsNothing,
    );

    const movements = <({String type, String count, int delta, String? date})>[
      (type: 'stock_in', count: '2', delta: 2, date: '2026-10-19'),
      (type: 'sold', count: '3', delta: -3, date: null),
      (type: 'loss', count: '2', delta: -2, date: null),
    ];
    for (var index = 0; index < movements.length; index++) {
      final movement = movements[index];
      await _createMovement(
        tester,
        action: activeBatchAction,
        movementType: movement.type,
        count: movement.count,
        occurredOn: movement.date == null
            ? null
            : DateTime.parse(movement.date!),
      );
      final entries = await harness.outbox.entries(
        accountId: _accountId,
        organizationId: _organizationId,
      );
      expect(entries, hasLength(index + 1));
      final entry = entries.last;
      expect(entry.status, OutboxEntryStatus.pending);
      expect(entry.mutation.intent.type, 'livestockMovement.create');
      expect(
        entry.dependsOn,
        index == 0 ? isEmpty : [entries[index - 1].operationId],
      );
      expect(entry.mutation.intent.payload, {
        'herdId': _batchHerdId,
        'movementType': movement.type,
        'delta': movement.delta,
        if (movement.date != null) 'occurredOn': movement.date,
      });
      final pendingBalance = find.byKey(
        const ValueKey('live-movement-pending-herd-$_batchHerdId'),
      );
      expect(pendingBalance, findsOneWidget);
      expect(
        find.text(
          const [
            'Chờ đồng bộ: +2 con · ước tính 10 con',
            'Chờ đồng bộ: -1 con · ước tính 7 con',
            'Chờ đồng bộ: -3 con · ước tính 5 con',
          ][index],
        ),
        findsOneWidget,
      );
      expect(find.text('Đã xác nhận: 8 con'), findsOneWidget);
    }
    expect(harness.transport.calls, 0);
    expect(tester.takeException(), isNull);
  });

  testWidgets('worker cannot create manager-only livestock movements', (
    tester,
  ) async {
    final domain = InMemoryDomainStore();
    await _installLivestockSnapshot(domain);
    final harness = await _pumpLivestock(
      tester,
      scope: _scope(farmRole: FarmlyFarmGrantRole.worker),
      domain: domain,
    );
    _expectActionUnavailable(
      tester,
      find.byKey(const ValueKey('live-movement-create-herd-$_batchHerdId')),
    );
    expect(
      await harness.outbox.entries(
        accountId: _accountId,
        organizationId: _organizationId,
      ),
      isEmpty,
    );
    expect(harness.transport.calls, 0);
  });

  testWidgets('organization viewer cannot move livestock despite farm grant', (
    tester,
  ) async {
    final domain = InMemoryDomainStore();
    await _installLivestockSnapshot(domain);
    final harness = await _pumpLivestock(
      tester,
      scope: _scope(
        organizationRole: FarmlyOrganizationRole.viewer,
        farmRole: FarmlyFarmGrantRole.manager,
      ),
      domain: domain,
    );
    _expectActionUnavailable(
      tester,
      find.byKey(const ValueKey('live-movement-create-herd-$_batchHerdId')),
    );
    expect(
      await harness.outbox.entries(
        accountId: _accountId,
        organizationId: _organizationId,
      ),
      isEmpty,
    );
    expect(harness.transport.calls, 0);
  });

  testWidgets('organization admin can move a herd with a worker farm grant', (
    tester,
  ) async {
    final domain = InMemoryDomainStore();
    await _installLivestockSnapshot(domain);
    await _pumpLivestock(
      tester,
      scope: _scope(
        organizationRole: FarmlyOrganizationRole.admin,
        farmRole: FarmlyFarmGrantRole.worker,
      ),
      domain: domain,
    );

    expect(
      find.byKey(const ValueKey('live-movement-create-herd-$_batchHerdId')),
      findsOneWidget,
    );
  });

  testWidgets('failed movement blocks another and routes to sync center', (
    tester,
  ) async {
    final domain = InMemoryDomainStore();
    await _installLivestockSnapshot(domain);
    final outbox = InMemoryOutboxStore();
    final scope = FarmlyMutationScope.farm(
      accountId: _accountId,
      organizationId: _organizationId,
      farmId: _farmId,
      continuityEpoch: '37',
    );
    final failed = await outbox.enqueue(
      FarmlyScopedMutation(
        scope: scope,
        intent: FarmlyCreateLivestockMovementIntent(
          operationId: '88888888-8888-4888-8888-888888888881',
          continuityEpoch: '37',
          resourceId: '99999999-9999-4999-8999-999999999991',
          herdId: _batchHerdId,
          movementType: 'sold',
          delta: -1,
        ),
      ),
    );
    await outbox.update(failed.copyWith(status: OutboxEntryStatus.rejected));
    final harness = await _pumpLivestock(
      tester,
      scope: _scope(farmRole: FarmlyFarmGrantRole.manager),
      domain: domain,
      outbox: outbox,
    );
    final action = find.byKey(
      const ValueKey('live-movement-create-herd-$_batchHerdId'),
    );

    expect(action, findsOneWidget);
    expect(
      tester
          .widget<OutlinedButton>(
            find.descendant(of: action, matching: find.byType(OutlinedButton)),
          )
          .onPressed,
      isNull,
    );
    expect(
      find.textContaining('cần xử lý trong Trung tâm đồng bộ'),
      findsOneWidget,
    );
    expect(
      await harness.outbox.entries(
        accountId: _accountId,
        organizationId: _organizationId,
      ),
      hasLength(1),
    );
    expect(harness.transport.calls, 0);
  });

  testWidgets('movement cannot reduce active batch headcount below zero', (
    tester,
  ) async {
    final domain = InMemoryDomainStore();
    await _installLivestockSnapshot(domain);
    final harness = await _pumpLivestock(
      tester,
      scope: _scope(farmRole: FarmlyFarmGrantRole.manager),
      domain: domain,
    );
    final activeBatchAction = find.byKey(
      const ValueKey('live-movement-create-herd-$_batchHerdId'),
    );

    await _createMovement(
      tester,
      action: activeBatchAction,
      movementType: 'loss',
      count: '9',
    );
    final save = find.byKey(const ValueKey('live-movement-save'));
    expect(save, findsOneWidget);
    await tester.tap(save);
    await tester.pumpAndSettle();
    expect(find.text('Số đàn ước tính không thể nhỏ hơn 0.'), findsOneWidget);
    expect(
      await harness.outbox.entries(
        accountId: _accountId,
        organizationId: _organizationId,
      ),
      isEmpty,
    );
    expect(find.byKey(const ValueKey('live-movement-save')), findsOneWidget);
    expect(harness.transport.calls, 0);
    expect(tester.takeException(), isNull);
  });

  testWidgets(
    'manager creates batch and tracked herds and a dependent animal offline',
    (tester) async {
      final domain = InMemoryDomainStore();
      await _installLivestockSnapshot(domain);
      final harness = await _pumpLivestock(
        tester,
        scope: _scope(farmRole: FarmlyFarmGrantRole.manager),
        domain: domain,
      );

      expect(find.byKey(const ValueKey('live-herd-create')), findsOneWidget);
      expect(
        find.byKey(const ValueKey('live-animal-create-herd-$_batchHerdId')),
        findsNothing,
      );
      await _createHerd(tester, mode: 'batch', species: 'Bò vàng');
      var entries = await harness.outbox.entries(
        accountId: _accountId,
        organizationId: _organizationId,
      );
      final batchEntry = entries.singleWhere(
        (entry) => entry.mutation.intent.type == 'herd.create',
      );
      final batch = batchEntry.mutation.intent as FarmlyCreateHerdIntent;
      expect(batch.payload, {'mode': 'batch', 'species': 'Bò vàng'});
      expect(batch.payload, isNot(contains('headcount')));
      expect(batchEntry.mutation.scope.farmId, _farmId);
      expect(batchEntry.status, OutboxEntryStatus.pending);
      final batchSync = find.byKey(
        ValueKey('live-herd-sync-${batch.resourceId}'),
      );
      await _scrollLivestockToKey(tester, batchSync);
      expect(
        find.byKey(ValueKey('live-animal-create-herd-${batch.resourceId}')),
        findsNothing,
      );
      expect(
        find.byKey(ValueKey('live-herd-sync-${batch.resourceId}')),
        findsOneWidget,
      );
      expect(
        find.descendant(
          of: find.byKey(ValueKey('live-herd-sync-${batch.resourceId}')),
          matching: find.text(
            AppLocalizations.of(
              tester.element(
                find.byKey(ValueKey('live-herd-sync-${batch.resourceId}')),
              ),
            ).liveLivestockSavedOnDevice,
          ),
        ),
        findsOneWidget,
      );

      await _createHerd(tester, mode: 'tracked', species: 'Bò sữa tơ');
      entries = await harness.outbox.entries(
        accountId: _accountId,
        organizationId: _organizationId,
      );
      final trackedEntry = entries.singleWhere(
        (entry) =>
            entry.mutation.intent.type == 'herd.create' &&
            (entry.mutation.intent.payload['mode'] as String) == 'tracked',
      );
      final tracked = trackedEntry.mutation.intent as FarmlyCreateHerdIntent;
      final addAnimal = find.byKey(
        ValueKey('live-animal-create-herd-${tracked.resourceId}'),
      );
      await _scrollLivestockToKey(tester, addAnimal);
      expect(addAnimal, findsOneWidget);
      await _createAnimal(
        tester,
        action: addAnimal,
        tag: 'COW-NEW',
        name: 'Mây nhỏ',
      );

      entries = await harness.outbox.entries(
        accountId: _accountId,
        organizationId: _organizationId,
      );
      final animalEntry = entries.singleWhere(
        (entry) => entry.mutation.intent.type == 'animal.create',
      );
      final animal = animalEntry.mutation.intent as FarmlyCreateAnimalIntent;
      expect(animal.payload, {
        'herdId': tracked.resourceId,
        'tag': 'COW-NEW',
        'name': 'Mây nhỏ',
      });
      expect(animal.dependsOn, [trackedEntry.operationId]);
      expect(animalEntry.status, OutboxEntryStatus.pending);
      final animalSync = find.byKey(
        ValueKey('live-animal-sync-${animal.resourceId}'),
      );
      await _scrollLivestockToKey(tester, animalSync);
      expect(animalSync, findsOneWidget);
      expect(
        find.descendant(
          of: animalSync,
          matching: find.text(
            AppLocalizations.of(
              tester.element(animalSync),
            ).liveLivestockSavedOnDevice,
          ),
        ),
        findsOneWidget,
      );
      expect(entries, hasLength(3));
      expect(harness.transport.calls, 0);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'manager edits a confirmed tracked animal offline and preserves its history',
    (tester) async {
      const productionId = '00000000-0000-4000-8000-000000000701';
      const observationId = '00000000-0000-4000-8000-000000000702';
      final domain = InMemoryDomainStore();
      await _installLivestockSnapshot(
        domain,
        productionRecords: const [
          {
            'id': productionId,
            'animalId': _animalId,
            'herdId': null,
            'product': 'milk',
            'quantity': '3.5',
            'unit': 'litre',
            'recordedOn': '2026-10-18',
          },
        ],
        observationRecords: const [
          {
            'id': observationId,
            'animalId': _animalId,
            'herdId': null,
            'kind': 'vet',
            'note': 'Khám sức khỏe đã xác nhận',
            'observedOn': '2026-10-18',
          },
        ],
      );
      final harness = await _pumpLivestock(
        tester,
        scope: _scope(farmRole: FarmlyFarmGrantRole.manager),
        domain: domain,
      );

      await _openAnimalEdit(tester);
      await _saveAnimalEdit(tester, tag: 'COW-009', name: 'Mây mới');

      final entries = await harness.outbox.entries(
        accountId: _accountId,
        organizationId: _organizationId,
      );
      expect(entries, hasLength(1));
      final update = entries.single.mutation.intent as FarmlyUpdateAnimalIntent;
      expect(update.type, 'animal.update');
      expect(update.resourceId, _animalId);
      expect(update.baseVersion, 1);
      expect(update.payload, {'tag': 'COW-009', 'name': 'Mây mới'});
      expect(entries.single.mutation.scope.farmId, _farmId);
      expect(entries.single.status, OutboxEntryStatus.pending);

      final collection = await harness.container.read(
        farmlyLiveLivestockProvider.future,
      );
      final animal = collection.herds
          .singleWhere((herd) => herd.id == _trackedHerdId)
          .animals
          .singleWhere((row) => row.id == _animalId);
      expect(animal.id, _animalId);
      expect(animal.herdId, _trackedHerdId);
      expect(animal.tag, 'COW-009');
      expect(animal.name, 'Mây mới');
      expect(animal.birthDate, '2022-05-11');
      expect(animal.productionRecords.map((row) => row.id), [productionId]);
      expect(animal.observations.map((row) => row.id), [observationId]);
      expect(harness.transport.calls, 0);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets('canceling an animal edit leaves the outbox unchanged', (
    tester,
  ) async {
    final domain = InMemoryDomainStore();
    await _installLivestockSnapshot(domain);
    final harness = await _pumpLivestock(
      tester,
      scope: _scope(farmRole: FarmlyFarmGrantRole.manager),
      domain: domain,
    );

    await _openAnimalEdit(tester);
    await tester.enterText(
      find.byKey(const ValueKey('live-animal-tag')),
      'COW-CANCELLED',
    );
    await tester.binding.handlePopRoute();
    await tester.pumpAndSettle();

    expect(find.byKey(const ValueKey('live-animal-edit-save')), findsNothing);
    expect(
      await harness.outbox.entries(
        accountId: _accountId,
        organizationId: _organizationId,
      ),
      isEmpty,
    );
    final collection = await harness.container.read(
      farmlyLiveLivestockProvider.future,
    );
    expect(
      collection.herds
          .singleWhere((row) => row.id == _trackedHerdId)
          .animals
          .singleWhere((row) => row.id == _animalId)
          .tag,
      'COW-001',
    );
    expect(harness.transport.calls, 0);
    expect(tester.takeException(), isNull);
  });

  testWidgets('workers and viewers cannot edit confirmed animals', (
    tester,
  ) async {
    for (final scope in [
      _scope(farmRole: FarmlyFarmGrantRole.worker),
      _scope(
        organizationRole: FarmlyOrganizationRole.viewer,
        farmRole: FarmlyFarmGrantRole.manager,
      ),
    ]) {
      final domain = InMemoryDomainStore();
      await _installLivestockSnapshot(domain);
      final harness = await _pumpLivestock(
        tester,
        scope: scope,
        domain: domain,
      );

      expect(
        find.byKey(const ValueKey('live-animal-edit-$_animalId')),
        findsNothing,
      );
      expect(
        await harness.outbox.entries(
          accountId: _accountId,
          organizationId: _organizationId,
        ),
        isEmpty,
      );
      expect(harness.transport.calls, 0);
      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pumpAndSettle();
    }
  });

  testWidgets('duplicate farm-local animal tags are rejected', (tester) async {
    final domain = InMemoryDomainStore();
    await _installLivestockSnapshot(
      domain,
      animalRecords: const [
        {
          'id': _animalId,
          'version': 1,
          'herdId': _trackedHerdId,
          'tag': 'COW-001',
          'name': 'Mây',
          'birthDate': '2022-05-11',
          'status': 'alive',
          'archived': false,
        },
        {
          'id': _duplicateAnimalId,
          'version': 1,
          'herdId': _trackedHerdId,
          'tag': 'COW-002',
          'name': 'Bông',
          'status': 'alive',
          'archived': false,
        },
      ],
    );
    final harness = await _pumpLivestock(
      tester,
      scope: _scope(farmRole: FarmlyFarmGrantRole.manager),
      domain: domain,
    );

    await _openAnimalEdit(tester);
    await _saveAnimalEdit(tester, tag: 'COW-002');

    expect(
      find.byKey(const ValueKey('live-animal-edit-error')),
      findsOneWidget,
    );
    expect(
      await harness.outbox.entries(
        accountId: _accountId,
        organizationId: _organizationId,
      ),
      isEmpty,
    );
    final collection = await harness.container.read(
      farmlyLiveLivestockProvider.future,
    );
    final animals = collection.herds
        .singleWhere((row) => row.id == _trackedHerdId)
        .animals;
    expect(animals.singleWhere((row) => row.id == _animalId).tag, 'COW-001');
    expect(harness.transport.calls, 0);
    expect(tester.takeException(), isNull);
  });

  testWidgets('released tag from an applied update can be reused', (
    tester,
  ) async {
    final domain = InMemoryDomainStore();
    await _installLivestockSnapshot(
      domain,
      animalRecords: const [
        {
          'id': _animalId,
          'version': 1,
          'herdId': _trackedHerdId,
          'tag': 'COW-001',
          'name': 'Mây',
          'birthDate': '2022-05-11',
          'status': 'alive',
          'archived': false,
        },
        {
          'id': _duplicateAnimalId,
          'version': 2,
          'herdId': _trackedHerdId,
          'tag': 'COW-003',
          'name': 'Bông',
          'status': 'alive',
          'archived': false,
        },
      ],
    );
    final outbox = InMemoryOutboxStore();
    final scope = FarmlyMutationScope.farm(
      accountId: _accountId,
      organizationId: _organizationId,
      farmId: _farmId,
      continuityEpoch: '37',
    );
    await _seedAnimalUpdate(
      outbox: outbox,
      scope: scope,
      operationId: '99999999-9999-4999-8999-999999999978',
      resourceId: _duplicateAnimalId,
      baseVersion: 1,
      payload: const {'tag': 'COW-002'},
      status: OutboxEntryStatus.applied,
    );
    final harness = await _pumpLivestock(
      tester,
      scope: _scope(farmRole: FarmlyFarmGrantRole.manager),
      domain: domain,
      outbox: outbox,
    );

    await _openAnimalEdit(tester);
    await _saveAnimalEdit(tester, tag: 'COW-002');

    expect(find.byKey(const ValueKey('live-animal-edit-error')), findsNothing);
    final entries = await harness.outbox.entries(
      accountId: _accountId,
      organizationId: _organizationId,
    );
    expect(entries, hasLength(2));
    final queuedUpdate = entries.singleWhere(
      (entry) => entry.mutation.intent.resourceId == _animalId,
    );
    expect(queuedUpdate.status, OutboxEntryStatus.pending);
    expect(queuedUpdate.mutation.intent.payload['tag'], 'COW-002');
    final collection = await harness.container.read(
      farmlyLiveLivestockProvider.future,
    );
    final animals = collection.herds
        .singleWhere((row) => row.id == _trackedHerdId)
        .animals;
    expect(animals.singleWhere((row) => row.id == _animalId).tag, 'COW-002');
    expect(
      animals.singleWhere((row) => row.id == _duplicateAnimalId).tag,
      'COW-003',
    );
    expect(harness.transport.calls, 0);
    expect(tester.takeException(), isNull);
  });

  testWidgets('scope change after opening the editor prevents enqueue', (
    tester,
  ) async {
    final domain = InMemoryDomainStore();
    await _installLivestockSnapshot(domain);
    final harness = await _pumpLivestock(
      tester,
      scope: _scope(farmRole: FarmlyFarmGrantRole.manager),
      domain: domain,
    );
    await _openAnimalEdit(tester);
    (harness.container.read(selectedOrganizationScopeProvider.notifier)
            as _SelectedScopeController)
        .replaceScope(null);
    await tester.pump();
    await _saveAnimalEdit(tester, tag: 'COW-NEW');

    expect(
      find.byKey(const ValueKey('live-animal-edit-error')),
      findsOneWidget,
    );
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

  testWidgets('role or selected-farm change blocks an open animal edit', (
    tester,
  ) async {
    for (final nextScope in [
      _scope(farmRole: FarmlyFarmGrantRole.worker),
      _twoFarmManagerScope(selectedFarmId: _otherFarmId),
    ]) {
      final domain = InMemoryDomainStore();
      await _installLivestockSnapshot(domain);
      final harness = await _pumpLivestock(
        tester,
        scope: nextScope.selectedFarmId == _otherFarmId
            ? _twoFarmManagerScope()
            : _scope(farmRole: FarmlyFarmGrantRole.manager),
        domain: domain,
      );
      await _openAnimalEdit(tester);
      (harness.container.read(selectedOrganizationScopeProvider.notifier)
              as _SelectedScopeController)
          .replaceScope(nextScope);
      await tester.pump();
      await _saveAnimalEdit(tester, tag: 'COW-NEW');

      expect(
        find.byKey(const ValueKey('live-animal-edit-error')),
        findsOneWidget,
      );
      expect(
        await harness.outbox.entries(
          accountId: _accountId,
          organizationId: _organizationId,
        ),
        isEmpty,
      );
      expect(harness.transport.calls, 0);
      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pumpAndSettle();
    }
  });

  testWidgets('animal with an unresolved update cannot be edited again', (
    tester,
  ) async {
    final domain = InMemoryDomainStore();
    await _installLivestockSnapshot(domain);
    final outbox = InMemoryOutboxStore();
    final scope = FarmlyMutationScope.farm(
      accountId: _accountId,
      organizationId: _organizationId,
      farmId: _farmId,
      continuityEpoch: '37',
    );
    await _seedAnimalUpdate(
      outbox: outbox,
      scope: scope,
      operationId: '99999999-9999-4999-8999-999999999977',
      resourceId: _animalId,
      baseVersion: 1,
      payload: const {'tag': 'COW-009'},
      status: OutboxEntryStatus.conflict,
    );
    final harness = await _pumpLivestock(
      tester,
      scope: _scope(farmRole: FarmlyFarmGrantRole.manager),
      domain: domain,
      outbox: outbox,
    );

    expect(
      find.byKey(const ValueKey('live-animal-edit-$_animalId')),
      findsNothing,
    );
    expect(
      await harness.outbox.entries(
        accountId: _accountId,
        organizationId: _organizationId,
      ),
      hasLength(1),
    );
    expect(harness.transport.calls, 0);
    expect(tester.takeException(), isNull);
  });

  testWidgets('a newer confirmed animal version rejects a stale edit', (
    tester,
  ) async {
    final domain = InMemoryDomainStore();
    await _installLivestockSnapshot(domain);
    final harness = await _pumpLivestock(
      tester,
      scope: _scope(farmRole: FarmlyFarmGrantRole.manager),
      domain: domain,
    );
    await _openAnimalEdit(tester);
    await tester.enterText(
      find.byKey(const ValueKey('live-animal-tag')),
      'COW-CLIENT',
    );
    await _installLivestockSnapshot(
      domain,
      animalRecords: const [
        {
          'id': _animalId,
          'version': 2,
          'herdId': _trackedHerdId,
          'tag': 'COW-SERVER',
          'name': 'Mây đã cập nhật',
          'birthDate': '2022-05-11',
          'status': 'alive',
          'archived': false,
        },
      ],
    );
    harness.container.invalidate(farmlyLiveLivestockProvider);
    await harness.container.read(farmlyLiveLivestockProvider.future);
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('live-animal-edit-save')));
    await tester.pumpAndSettle();

    expect(
      find.byKey(const ValueKey('live-animal-edit-error')),
      findsOneWidget,
    );
    expect(
      await harness.outbox.entries(
        accountId: _accountId,
        organizationId: _organizationId,
      ),
      isEmpty,
    );
    final collection = await harness.container.read(
      farmlyLiveLivestockProvider.future,
    );
    final animal = collection.herds
        .singleWhere((row) => row.id == _trackedHerdId)
        .animals
        .singleWhere((row) => row.id == _animalId);
    expect(animal.tag, 'COW-SERVER');
    expect(animal.name, 'Mây đã cập nhật');
    expect(harness.transport.calls, 0);
    expect(tester.takeException(), isNull);
  });

  testWidgets('worker and organization viewer cannot create livestock', (
    tester,
  ) async {
    for (final scope in [
      _scope(farmRole: FarmlyFarmGrantRole.worker),
      _scope(
        organizationRole: FarmlyOrganizationRole.viewer,
        farmRole: FarmlyFarmGrantRole.manager,
      ),
    ]) {
      final domain = InMemoryDomainStore();
      await _installLivestockSnapshot(domain);
      final harness = await _pumpLivestock(
        tester,
        scope: scope,
        domain: domain,
      );

      expect(find.byKey(const ValueKey('live-herd-create')), findsNothing);
      expect(
        find.byKey(const ValueKey('live-animal-create-herd-$_trackedHerdId')),
        findsNothing,
      );
      expect(
        await harness.outbox.entries(
          accountId: _accountId,
          organizationId: _organizationId,
        ),
        isEmpty,
      );
      expect(harness.transport.calls, 0);
      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pumpAndSettle();
    }
  });

  testWidgets('organization admin can create with a worker farm grant', (
    tester,
  ) async {
    final domain = InMemoryDomainStore();
    await _installLivestockSnapshot(domain);
    await _pumpLivestock(
      tester,
      scope: _scope(
        organizationRole: FarmlyOrganizationRole.admin,
        farmRole: FarmlyFarmGrantRole.worker,
      ),
      domain: domain,
    );

    expect(find.byKey(const ValueKey('live-herd-create')), findsOneWidget);
  });

  testWidgets(
    'herd projection honors scope, snapshot identity, lifecycle, and attention',
    (tester) async {
      final domain = InMemoryDomainStore();
      await _installLivestockSnapshot(
        domain,
        animalRecords: [
          {
            'id': _animalId,
            'version': 1,
            'herdId': _trackedHerdId,
            'tag': 'COW-001',
            'name': 'Mây',
            'status': 'alive',
            'archived': false,
          },
          {
            'id': _archivedAnimalId,
            'version': 2,
            'herdId': _archivedHerdId,
            'tag': 'OLD-001',
            'name': 'Con thuộc đàn đã lưu trữ',
            'status': 'alive',
            'archived': false,
          },
        ],
      );
      final outbox = InMemoryOutboxStore();
      final scope = FarmlyMutationScope.farm(
        accountId: _accountId,
        organizationId: _organizationId,
        farmId: _farmId,
        continuityEpoch: '37',
      );
      await _seedHerdCreate(
        outbox: outbox,
        scope: scope,
        operationId: '99999999-9999-4999-8999-999999999981',
        resourceId: _batchHerdId,
        mode: 'tracked',
        species: 'Không thay thế snapshot',
      );
      await _seedHerdCreate(
        outbox: outbox,
        scope: scope,
        operationId: '99999999-9999-4999-8999-999999999989',
        resourceId: _archivedHerdId,
        mode: 'tracked',
        species: 'Không hồi sinh đàn lưu trữ',
        status: OutboxEntryStatus.applied,
      );
      await _seedHerdCreate(
        outbox: outbox,
        scope: scope,
        operationId: '99999999-9999-4999-8999-999999999982',
        resourceId: _pendingHerdId,
        mode: 'batch',
        species: 'Đàn đang gửi',
        status: OutboxEntryStatus.inFlight,
      );
      await _seedHerdCreate(
        outbox: outbox,
        scope: scope,
        operationId: '99999999-9999-4999-8999-999999999983',
        resourceId: _awaitingHerdId,
        mode: 'tracked',
        species: 'Đàn đã nhận',
        status: OutboxEntryStatus.applied,
      );
      for (final failed in [
        (
          id: _failedHerdId,
          status: OutboxEntryStatus.rejected,
          suffix: '984',
          mode: 'tracked',
        ),
        (
          id: '88888888-8888-4888-8888-888888888886',
          status: OutboxEntryStatus.conflict,
          suffix: '985',
          mode: 'batch',
        ),
        (
          id: '88888888-8888-4888-8888-888888888887',
          status: OutboxEntryStatus.blocked,
          suffix: '986',
          mode: 'tracked',
        ),
      ]) {
        await _seedHerdCreate(
          outbox: outbox,
          scope: scope,
          operationId: '99999999-9999-4999-8999-999999999${failed.suffix}',
          resourceId: failed.id,
          mode: failed.mode,
          species: 'Đàn lỗi ${failed.suffix}',
          status: failed.status,
        );
      }
      final foreignFarmScope = FarmlyMutationScope.farm(
        accountId: _accountId,
        organizationId: _organizationId,
        farmId: 'aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa',
        continuityEpoch: '37',
      );
      await _seedHerdCreate(
        outbox: outbox,
        scope: foreignFarmScope,
        operationId: '99999999-9999-4999-8999-999999999987',
        resourceId: _foreignHerdId,
        mode: 'batch',
        species: 'Đàn sai trang trại',
      );
      final wrongEpochScope = FarmlyMutationScope.farm(
        accountId: _accountId,
        organizationId: _organizationId,
        farmId: _farmId,
        continuityEpoch: '38',
      );
      await _seedHerdCreate(
        outbox: outbox,
        scope: wrongEpochScope,
        operationId: '99999999-9999-4999-8999-999999999988',
        resourceId: _wrongEpochHerdId,
        mode: 'batch',
        species: 'Đàn sai phiên',
      );
      await _seedAnimalCreate(
        outbox: outbox,
        scope: scope,
        operationId: '99999999-9999-4999-8999-999999999991',
        resourceId: _animalId,
        herdId: _trackedHerdId,
        tag: 'SHOULD-NOT-REPLACE',
        name: 'Không thay thế động vật snapshot',
        status: OutboxEntryStatus.applied,
      );
      await _seedAnimalCreate(
        outbox: outbox,
        scope: scope,
        operationId: '99999999-9999-4999-8999-999999999990',
        resourceId: _archivedAnimalId,
        herdId: _trackedHerdId,
        tag: 'NO-RESURRECTION',
        name: 'Không hồi sinh con thuộc đàn lưu trữ',
        status: OutboxEntryStatus.applied,
      );
      await _seedAnimalCreate(
        outbox: outbox,
        scope: scope,
        operationId: '99999999-9999-4999-8999-999999999992',
        resourceId: _pendingAnimalId,
        herdId: _trackedHerdId,
        tag: 'CALF-PENDING',
        name: 'Bê chờ đồng bộ',
        status: OutboxEntryStatus.inFlight,
      );
      await _seedAnimalCreate(
        outbox: outbox,
        scope: scope,
        operationId: '99999999-9999-4999-8999-999999999993',
        resourceId: _failedAnimalId,
        herdId: _trackedHerdId,
        tag: 'CALF-FAILED',
        status: OutboxEntryStatus.rejected,
      );

      final harness = await _pumpLivestock(
        tester,
        scope: _scope(farmRole: FarmlyFarmGrantRole.manager),
        domain: domain,
        outbox: outbox,
      );
      final pendingStatus = find.byKey(
        const ValueKey('live-herd-sync-$_pendingHerdId'),
      );
      final collection = await harness.container.read(
        farmlyLiveLivestockProvider.future,
      );
      expect(collection.cacheState, FarmlyLivestockCacheState.ready);
      expect(collection.herds.map((herd) => herd.id), contains(_pendingHerdId));
      final awaitingStatus = find.byKey(
        const ValueKey('live-herd-sync-$_awaitingHerdId'),
      );
      await _scrollLivestockToKey(tester, pendingStatus);
      await tester.pumpAndSettle();
      expect(pendingStatus, findsOneWidget);
      expect(
        find.descendant(
          of: pendingStatus,
          matching: find.text(
            AppLocalizations.of(
              tester.element(pendingStatus),
            ).liveLivestockSavedOnDevice,
          ),
        ),
        findsOneWidget,
      );
      final pendingAnimalStatus = find.byKey(
        const ValueKey('live-animal-sync-$_pendingAnimalId'),
      );
      await _scrollLivestockToKey(tester, pendingAnimalStatus);
      await tester.pumpAndSettle();
      expect(pendingAnimalStatus, findsOneWidget);
      expect(
        find.descendant(
          of: pendingAnimalStatus,
          matching: find.text(
            AppLocalizations.of(
              tester.element(pendingAnimalStatus),
            ).liveLivestockSavedOnDevice,
          ),
        ),
        findsOneWidget,
      );
      await _scrollLivestockToKey(tester, awaitingStatus);
      await tester.pumpAndSettle();
      expect(awaitingStatus, findsOneWidget);
      expect(
        find.descendant(
          of: awaitingStatus,
          matching: find.text(
            AppLocalizations.of(
              tester.element(awaitingStatus),
            ).liveLivestockAwaitingProjection,
          ),
        ),
        findsOneWidget,
      );
      final herdsById = {for (final herd in collection.herds) herd.id: herd};
      expect(
        herdsById.keys,
        unorderedEquals([
          _batchHerdId,
          _trackedHerdId,
          _pendingHerdId,
          _awaitingHerdId,
        ]),
      );
      expect(herdsById[_batchHerdId]?.species, 'Bò lai Sind');
      expect(herdsById[_pendingHerdId]?.species, 'Đàn đang gửi');
      expect(herdsById[_awaitingHerdId]?.species, 'Đàn đã nhận');
      expect(
        find.byKey(const ValueKey('live-animal-create-herd-$_failedHerdId')),
        findsNothing,
      );
      expect(
        find.byKey(const ValueKey('live-animal-create-herd-$_failedHerdId')),
        findsNothing,
      );
      final animalsById = {
        for (final animal in herdsById[_trackedHerdId]!.animals)
          animal.id: animal,
      };
      expect(animalsById.keys, unorderedEquals([_animalId, _pendingAnimalId]));
      expect(animalsById[_animalId]?.tag, 'COW-001');
      expect(animalsById[_animalId]?.name, 'Mây');
      expect(animalsById[_pendingAnimalId]?.tag, 'CALF-PENDING');
      expect(collection.attentionCount, 4);
      expect(
        await harness.outbox.entries(
          accountId: _accountId,
          organizationId: _organizationId,
        ),
        hasLength(13),
      );
      expect(harness.transport.calls, 0);
      expect(tester.takeException(), isNull);
    },
  );

  test('snapshot projection does not count an applied movement twice', () {
    final scope = FarmlyMutationScope.farm(
      accountId: _accountId,
      organizationId: _organizationId,
      farmId: _farmId,
      continuityEpoch: '37',
    );
    const movementId = '88888888-8888-4888-8888-888888888888';
    const operationId = '99999999-9999-4999-8999-999999999999';
    final intent = FarmlyCreateLivestockMovementIntent(
      operationId: operationId,
      continuityEpoch: '37',
      resourceId: movementId,
      herdId: _batchHerdId,
      movementType: 'stock_in',
      delta: 4,
    );
    final applied = OutboxEntry(
      mutation: FarmlyScopedMutation(scope: scope, intent: intent),
      status: OutboxEntryStatus.applied,
      sequence: 1,
    );

    final ledger = projectFarmlyLiveLivestockMovements(
      snapshotRecords: {
        movementId: {
          'id': movementId,
          'herdId': _batchHerdId,
          'movementType': 'stock_in',
          'delta': 4,
          'occurredAt': '2026-10-19T00:00:00.000Z',
        },
      },
      entries: [applied],
      scope: scope,
    );

    expect(ledger.pendingByHerd, isEmpty);
    expect(ledger.pendingDeltaByHerd, isEmpty);
    expect(ledger.latestOperationIdByHerd, isEmpty);
    expect(ledger.attentionCount, 0);
  });

  testWidgets(
    'no bootstrap and no farm never show demo herds or write actions',
    (tester) async {
      final noBootstrap = await _pumpLivestock(tester, scope: _scope());
      expect(find.text('Bò lai Sind · Theo dõi từng con'), findsNothing);
      expect(find.text('Gà ri thả vườn · Đàn theo lô'), findsNothing);
      expect(
        find.byKey(const ValueKey('live-production-create-herd-$_batchHerdId')),
        findsNothing,
      );
      expect(
        find.byKey(const ValueKey('live-production-create-animal-$_animalId')),
        findsNothing,
      );
      expect(
        await noBootstrap.outbox.entries(
          accountId: _accountId,
          organizationId: _organizationId,
        ),
        isEmpty,
      );
      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pumpAndSettle();

      await _pumpLivestock(
        tester,
        scope: _scope(farms: const [], selectedFarmId: null),
      );
      expect(find.text('Bò lai Sind · Theo dõi từng con'), findsNothing);
      expect(find.text('Gà ri thả vườn · Đàn theo lô'), findsNothing);
      expect(
        find.byKey(const ValueKey('live-production-create-herd-$_batchHerdId')),
        findsNothing,
      );
      expect(
        find.byKey(const ValueKey('live-production-create-animal-$_animalId')),
        findsNothing,
      );
      expect(tester.takeException(), isNull);
    },
  );
}
