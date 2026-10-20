import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/misc.dart' show Override;
import 'package:flutter/semantics.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:farmly_mobile/core/auth/auth_session_controller.dart';
import 'package:farmly_mobile/core/auth/farmly_auth_models.dart';
import 'package:farmly_mobile/core/sync/farmly_mutation.dart';
import 'package:farmly_mobile/core/sync/sync_providers.dart';
import 'package:farmly_mobile/core/theme/farm_theme.dart';
import 'package:farmly_mobile/features/app/app_router.dart';
import 'package:farmly_mobile/features/app/app_routes.dart';
import 'package:farmly_mobile/features/farm/live_farm_zones.dart';
import 'package:farmly_mobile/features/harvest/harvest_screen.dart';
import 'package:farmly_mobile/features/harvest/live_harvest_screen.dart';
import 'package:farmly_mobile/features/organizations/organization_repository.dart';
import 'package:farmly_mobile/features/organizations/organization_scope_controller.dart';
import 'package:farmly_mobile/generated/farmly_api_types.dart';
import 'package:farmly_mobile/l10n/generated/app_localizations.dart';

const _accountId = '11111111-1111-4111-8111-111111111111';
const _organizationId = '22222222-2222-4222-8222-222222222222';
const _farmAId = '33333333-3333-4333-8333-333333333333';
const _farmBId = '44444444-4444-4444-8444-444444444444';
const _zoneId = '55555555-5555-4555-8555-555555555555';
const _plantingId = '66666666-6666-4666-8666-666666666666';
const _speciesId = '77777777-7777-4777-8777-777777777777';

const _session = FarmlyAuthSession(
  user: FarmlyAuthUser(
    id: _accountId,
    name: 'Test Farmer',
    email: 'farmer@farmly.test',
  ),
);

void main() {
  void phoneViewport(WidgetTester tester) {
    tester.view.physicalSize = const Size(430, 932);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
  }

  group('production and preview routing', () {
    testWidgets('production /harvest route renders the live screen', (
      tester,
    ) async {
      phoneViewport(tester);
      final scope = _scope(FarmlyFarmGrantRole.manager);
      final collection = _collection(scope);
      final container = ProviderContainer(
        overrides: _liveOverrides(scope, collection),
      );
      addTearDown(container.dispose);
      final router = container.read(farmlyRouterProvider);

      await tester.pumpWidget(
        UncontrolledProviderScope(
          container: container,
          child: MaterialApp.router(
            theme: buildFarmTheme(),
            locale: const Locale('vi'),
            localizationsDelegates: AppLocalizations.localizationsDelegates,
            supportedLocales: AppLocalizations.supportedLocales,
            routerConfig: router,
          ),
        ),
      );
      router.go(AppRoutes.harvest);
      await tester.pumpAndSettle();

      expect(find.byType(FarmlyLiveHarvestScreen), findsOneWidget);
      expect(find.byType(HarvestScreen), findsNothing);
      expect(find.text('Nông trại A'), findsOneWidget);
    });

    testWidgets('explicit visual-preview harvest remains demo-backed', (
      tester,
    ) async {
      phoneViewport(tester);
      await tester.pumpWidget(
        ProviderScope(
          child: MaterialApp(
            theme: buildFarmTheme(),
            locale: const Locale('vi'),
            localizationsDelegates: AppLocalizations.localizationsDelegates,
            supportedLocales: AppLocalizations.supportedLocales,
            home: const HarvestScreen(),
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.byType(HarvestScreen), findsOneWidget);
      expect(find.byType(FarmlyLiveHarvestScreen), findsNothing);
      expect(find.text('Cải ngọt'), findsWidgets);
    });
  });

  group('farm-local harvest projection', () {
    testWidgets(
      'uses Monday–Sunday farm dates and separates confirmed from pending kg',
      (tester) async {
        phoneViewport(tester);
        final scope = _scope(FarmlyFarmGrantRole.manager);
        final collection = _collection(
          scope,
          farmLocalDate: '2026-10-21',
          harvests: [
            _harvest('week-start', '12', '2026-10-19'),
            _harvest('week-end', '8', '2026-10-25'),
            _harvest('previous-week', '100', '2026-10-18'),
            _harvest('next-week', '50', '2026-10-26'),
            _harvest('voided', '70', '2026-10-22', status: 'voided'),
            _harvest(
              'new-pending',
              '4',
              '2026-10-22',
              syncState: FarmlyZoneSyncState.savedOnDevice,
              version: 0,
            ),
            _harvest(
              'correction-pending',
              '3',
              '2026-10-23',
              proposals: [
                FarmlyLiveHarvestCorrectionProposal(
                  id: '88888888-8888-4888-8888-888888888888',
                  harvestId: 'correction-pending',
                  proposedQuantityKg: FarmlyDecimal.parse('40'),
                  reason: 'Cân kiểm tra lại',
                  status: 'pending',
                ),
              ],
              pendingManagerMutationState: FarmlyZoneSyncState.savedOnDevice,
            ),
            _harvest(
              'void-pending',
              '2',
              '2026-10-24',
              pendingManagerMutationState: FarmlyZoneSyncState.savedOnDevice,
            ),
          ],
        );

        await _pumpLiveHarvest(tester, scope, collection);

        final confirmed = tester.widget<Text>(
          find.byKey(const ValueKey('live-harvest-confirmed-total')),
        );
        final pending = tester.widget<Text>(
          find.byKey(const ValueKey('live-harvest-pending-total')),
        );
        expect(confirmed.data, contains('25'));
        expect(pending.data, contains('4'));
        expect(confirmed.data, isNot(contains('245')));
      },
    );

    testWidgets('adds fractional confirmed kg without losing precision', (
      tester,
    ) async {
      phoneViewport(tester);
      final scope = _scope(FarmlyFarmGrantRole.manager);
      await _pumpLiveHarvest(
        tester,
        scope,
        _collection(
          scope,
          harvests: [
            _harvest('fraction-a', '12.25', '2026-10-19'),
            _harvest('fraction-b', '8.5', '2026-10-20'),
            _harvest('fraction-c', '3.75', '2026-10-21'),
            _harvest('fraction-d', '2.125', '2026-10-22'),
          ],
        ),
      );

      final confirmed = tester.widget<Text>(
        find.byKey(const ValueKey('live-harvest-confirmed-total')),
      );
      expect(confirmed.data, contains('26,625'));
    });

    testWidgets(
      'fails closed when collection farm differs from selected farm',
      (tester) async {
        phoneViewport(tester);
        final scope = _scope(FarmlyFarmGrantRole.manager);
        final mismatchedSelection = _scope(
          FarmlyFarmGrantRole.manager,
          selectedFarmId: _farmBId,
        );

        await _pumpLiveHarvest(
          tester,
          mismatchedSelection,
          _collection(
            scope,
            harvests: [_harvest('foreign', '99', '2026-10-21')],
          ),
        );

        final l10n = AppLocalizations.of(
          tester.element(find.byType(FarmlyLiveHarvestScreen)),
        );
        expect(find.text(l10n.liveFarmScopeChanged), findsOneWidget);
        expect(
          find.byKey(const ValueKey('live-harvest-row-foreign')),
          findsNothing,
        );
        expect(find.byKey(const ValueKey('live-harvest-add')), findsNothing);
      },
    );

    testWidgets('renders no-farm state without a harvest action', (
      tester,
    ) async {
      phoneViewport(tester);
      await _pumpLiveHarvest(
        tester,
        null,
        _emptyCollection(FarmlyZoneCacheState.noFarm),
      );

      final l10n = AppLocalizations.of(
        tester.element(find.byType(FarmlyLiveHarvestScreen)),
      );
      expect(find.text(l10n.noSelectedFarm), findsOneWidget);
      expect(find.byKey(const ValueKey('live-harvest-add')), findsNothing);
    });

    testWidgets('renders not-bootstrapped and stale states explicitly', (
      tester,
    ) async {
      phoneViewport(tester);
      final scope = _scope(FarmlyFarmGrantRole.manager);

      await _pumpLiveHarvest(
        tester,
        scope,
        _collection(scope, cacheState: FarmlyZoneCacheState.notBootstrapped),
      );
      var l10n = AppLocalizations.of(
        tester.element(find.byType(FarmlyLiveHarvestScreen)),
      );
      expect(find.text(l10n.liveFarmNoCacheTitle), findsOneWidget);
      expect(
        find.byKey(const ValueKey('live-harvest-confirmed-total')),
        findsNothing,
      );

      await _pumpLiveHarvest(
        tester,
        scope,
        _collection(scope, cacheState: FarmlyZoneCacheState.stale),
      );
      l10n = AppLocalizations.of(
        tester.element(find.byType(FarmlyLiveHarvestScreen)),
      );
      expect(find.text(l10n.liveFarmStaleTitle), findsOneWidget);
      expect(find.byKey(const ValueKey('live-harvest-add')), findsNothing);
    });

    testWidgets('renders scope-changed state and hides records', (
      tester,
    ) async {
      phoneViewport(tester);
      final scope = _scope(FarmlyFarmGrantRole.manager);

      await _pumpLiveHarvest(
        tester,
        scope,
        _collection(
          scope,
          cacheState: FarmlyZoneCacheState.scopeChanged,
          harvests: [_harvest('stale-record', '10', '2026-10-21')],
        ),
      );

      final l10n = AppLocalizations.of(
        tester.element(find.byType(FarmlyLiveHarvestScreen)),
      );
      expect(find.text(l10n.liveFarmScopeChanged), findsOneWidget);
      expect(
        find.byKey(const ValueKey('live-harvest-row-stale-record')),
        findsNothing,
      );
    });

    testWidgets('shows a safe retryable error when the projection fails', (
      tester,
    ) async {
      phoneViewport(tester);
      final scope = _scope(FarmlyFarmGrantRole.manager);
      await tester.pumpWidget(
        _liveHarness(
          scope,
          _collection(scope),
          projection: (ref) async => throw StateError('private failure detail'),
        ),
      );
      await tester.pumpAndSettle();

      final l10n = AppLocalizations.of(
        tester.element(find.byType(FarmlyLiveHarvestScreen)),
      );
      expect(find.text(l10n.loadErrorTitle), findsOneWidget);
      expect(find.text('private failure detail'), findsNothing);
    });

    testWidgets(
      'keeps a stable loading surface while the live projection loads',
      (tester) async {
        phoneViewport(tester);
        final completer = Completer<FarmlyLiveZoneCollection>();
        final scope = _scope(FarmlyFarmGrantRole.manager);
        await tester.pumpWidget(
          _liveHarness(
            scope,
            _collection(scope),
            projection: (_) => completer.future,
          ),
        );
        await tester.pump();

        expect(find.byType(FarmlyLiveHarvestScreen), findsOneWidget);
        expect(find.byKey(const ValueKey('live-harvest-add')), findsNothing);
        expect(
          find.byKey(const ValueKey('live-harvest-confirmed-total')),
          findsNothing,
        );
      },
    );
  });

  group('harvest roles and actions', () {
    testWidgets('worker can record and propose but cannot apply or void', (
      tester,
    ) async {
      phoneViewport(tester);
      final scope = _scope(FarmlyFarmGrantRole.worker);
      await _pumpLiveHarvest(
        tester,
        scope,
        _collection(
          scope,
          harvests: [_harvest('worker-record', '10', '2026-10-21')],
        ),
      );

      expect(find.byKey(const ValueKey('live-harvest-add')), findsOneWidget);
      await tester.tap(
        find.byKey(const ValueKey('live-harvest-row-worker-record')),
      );
      await tester.pumpAndSettle();
      final l10n = AppLocalizations.of(
        tester.element(find.byType(FarmlyLiveHarvestScreen)),
      );
      expect(find.text(l10n.liveHarvestProposeCorrection), findsOneWidget);
      expect(find.text(l10n.liveHarvestApply), findsNothing);
      expect(find.text(l10n.liveHarvestVoid), findsNothing);
    });

    testWidgets('manager can apply proposals, adjust, and void', (
      tester,
    ) async {
      phoneViewport(tester);
      final scope = _scope(FarmlyFarmGrantRole.manager);
      await _pumpLiveHarvest(
        tester,
        scope,
        _collection(
          scope,
          harvests: [
            _harvest(
              'manager-record',
              '10',
              '2026-10-21',
              proposals: [
                FarmlyLiveHarvestCorrectionProposal(
                  id: '99999999-9999-4999-8999-999999999999',
                  harvestId: 'manager-record',
                  proposedQuantityKg: FarmlyDecimal.parse('11'),
                  reason: 'Cân lại',
                  status: 'pending',
                ),
              ],
            ),
          ],
        ),
      );

      await tester.tap(
        find.byKey(const ValueKey('live-harvest-row-manager-record')),
      );
      await tester.pumpAndSettle();
      final l10n = AppLocalizations.of(
        tester.element(find.byType(FarmlyLiveHarvestScreen)),
      );
      expect(find.text(l10n.liveHarvestApply), findsOneWidget);
      expect(find.text(l10n.liveHarvestAdjust), findsOneWidget);
      expect(find.text(l10n.liveHarvestVoid), findsOneWidget);
    });

    testWidgets('viewer has neither create nor correction/void controls', (
      tester,
    ) async {
      phoneViewport(tester);
      final scope = _scope(
        FarmlyFarmGrantRole.viewer,
        organizationRole: FarmlyOrganizationRole.member,
      );
      await _pumpLiveHarvest(
        tester,
        scope,
        _collection(
          scope,
          harvests: [_harvest('viewer-record', '10', '2026-10-21')],
        ),
      );

      expect(find.byKey(const ValueKey('live-harvest-add')), findsNothing);
      await tester.tap(
        find.byKey(const ValueKey('live-harvest-row-viewer-record')),
      );
      await tester.pumpAndSettle();
      final l10n = AppLocalizations.of(
        tester.element(find.byType(FarmlyLiveHarvestScreen)),
      );
      expect(find.text(l10n.liveHarvestProposeCorrection), findsNothing);
      expect(find.text(l10n.liveHarvestApply), findsNothing);
      expect(find.text(l10n.liveHarvestVoid), findsNothing);
    });

    testWidgets(
      'add CTA opens planting picker then existing live create form',
      (tester) async {
        phoneViewport(tester);
        final scope = _scope(FarmlyFarmGrantRole.manager);
        await _pumpLiveHarvest(tester, scope, _collection(scope));

        await tester.tap(find.byKey(const ValueKey('live-harvest-add')));
        await tester.pumpAndSettle();
        expect(
          find.byKey(const ValueKey('live-harvest-planting-picker')),
          findsOneWidget,
        );
        await tester.tap(find.text('Cà chua bi'));
        await tester.pumpAndSettle();

        final l10n = AppLocalizations.of(
          tester.element(find.byType(FarmlyLiveHarvestScreen)),
        );
        final saveButton = find.byKey(const ValueKey('live-harvest-save'));
        expect(saveButton, findsOneWidget);
        final createSheet = find
            .ancestor(of: saveButton, matching: find.byType(BottomSheet))
            .first;
        expect(
          find.descendant(
            of: createSheet,
            matching: find.text(l10n.liveHarvestCreate),
          ),
          findsOneWidget,
        );
      },
    );

    testWidgets('disables create when selected planting disappears', (
      tester,
    ) async {
      phoneViewport(tester);
      final scope = _scope(FarmlyFarmGrantRole.manager);
      var currentProjection = _collection(scope);
      final container = ProviderContainer(
        overrides: _liveOverrides(
          scope,
          currentProjection,
          projection: (_) async => currentProjection,
        ),
      );
      addTearDown(container.dispose);
      await tester.pumpWidget(
        UncontrolledProviderScope(
          container: container,
          child: MaterialApp(
            theme: buildFarmTheme(),
            locale: const Locale('vi'),
            localizationsDelegates: AppLocalizations.localizationsDelegates,
            supportedLocales: AppLocalizations.supportedLocales,
            home: const FarmlyLiveHarvestScreen(),
          ),
        ),
      );
      await tester.pumpAndSettle();

      await tester.tap(find.byKey(const ValueKey('live-harvest-add')));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Cà chua bi'));
      await tester.pumpAndSettle();

      currentProjection = _collection(scope, plantings: const []);
      container.invalidate(farmlyLiveZoneCollectionProvider);
      await tester.pumpAndSettle();

      final saveButton = tester.widget<FilledButton>(
        find.byKey(const ValueKey('live-harvest-save')),
      );
      expect(saveButton.onPressed, isNull);
      final l10n = AppLocalizations.of(
        tester.element(find.byType(FarmlyLiveHarvestScreen)),
      );
      expect(find.text(l10n.liveFarmScopeChanged), findsOneWidget);
      expect(tester.takeException(), isNull);
    });

    testWidgets('record row is semantically tappable and opens actions', (
      tester,
    ) async {
      phoneViewport(tester);
      final scope = _scope(FarmlyFarmGrantRole.manager);
      await _pumpLiveHarvest(
        tester,
        scope,
        _collection(
          scope,
          harvests: [_harvest('accessible', '10', '2026-10-21')],
        ),
      );

      final row = find.byKey(const ValueKey('live-harvest-row-accessible'));
      final semantics = tester.ensureSemantics();
      expect(row, findsOneWidget);
      expect(
        tester
            .getSemantics(row)
            .getSemanticsData()
            .hasAction(SemanticsAction.tap),
        isTrue,
      );
      semantics.dispose();
      await tester.tap(row);
      await tester.pumpAndSettle();

      final l10n = AppLocalizations.of(
        tester.element(find.byType(FarmlyLiveHarvestScreen)),
      );
      expect(find.text(l10n.liveHarvestDetails), findsOneWidget);
    });
  });
}

List<Override> _liveOverrides(
  FarmlyOrganizationScope? scope,
  FarmlyLiveZoneCollection collection, {
  Future<FarmlyLiveZoneCollection> Function(Ref ref)? projection,
}) => [
  farmlyAuthSessionProvider.overrideWith(_TestSessionController.new),
  selectedOrganizationScopeProvider.overrideWith(
    () => _FixedScopeController(scope),
  ),
  farmlySyncScopeProvider.overrideWith((ref) async => _mutationScope(scope)),
  farmlyLiveZoneCollectionProvider.overrideWith(
    projection ?? (ref) async => collection,
  ),
];

Widget _liveHarness(
  FarmlyOrganizationScope? scope,
  FarmlyLiveZoneCollection collection, {
  Future<FarmlyLiveZoneCollection> Function(Ref ref)? projection,
}) => ProviderScope(
  key: UniqueKey(),
  overrides: _liveOverrides(scope, collection, projection: projection),
  child: MaterialApp(
    theme: buildFarmTheme(),
    locale: const Locale('vi'),
    localizationsDelegates: AppLocalizations.localizationsDelegates,
    supportedLocales: AppLocalizations.supportedLocales,
    home: const FarmlyLiveHarvestScreen(),
  ),
);

Future<void> _pumpLiveHarvest(
  WidgetTester tester,
  FarmlyOrganizationScope? scope,
  FarmlyLiveZoneCollection collection,
) async {
  await tester.pumpWidget(_liveHarness(scope, collection));
  await tester.pumpAndSettle();
}

FarmlyOrganizationScope _scope(
  FarmlyFarmGrantRole farmRole, {
  String selectedFarmId = _farmAId,
  FarmlyOrganizationRole organizationRole = FarmlyOrganizationRole.member,
}) => FarmlyOrganizationScope(
  organization: FarmlyOrganization(
    id: _organizationId,
    name: 'Tổ chức kiểm thử',
    status: FarmlyOrganizationStatus.active,
    policyVersion: '1',
    role: organizationRole,
    membershipVersion: 1,
  ),
  directory: FarmlyFarmDirectory(
    scopePolicyVersion: '1',
    continuityEpoch: '7',
    farms: [
      FarmlyDirectoryFarm(
        id: _farmAId,
        name: 'Nông trại A',
        status: FarmlyFarmStatus.active,
        grantRole: farmRole,
      ),
      const FarmlyDirectoryFarm(
        id: _farmBId,
        name: 'Nông trại B',
        status: FarmlyFarmStatus.active,
        grantRole: FarmlyFarmGrantRole.viewer,
      ),
    ],
  ),
  epoch: 17,
  selectedFarmId: selectedFarmId,
);

FarmlyMutationScope? _mutationScope(FarmlyOrganizationScope? scope) {
  final farm = scope?.selectedFarm;
  if (scope == null || farm == null) return null;
  return FarmlyMutationScope.farm(
    accountId: _accountId,
    organizationId: scope.organization.id,
    farmId: farm.id,
    continuityEpoch: scope.directory.continuityEpoch,
  );
}

FarmlyLiveZoneCollection _collection(
  FarmlyOrganizationScope scope, {
  FarmlyZoneCacheState cacheState = FarmlyZoneCacheState.ready,
  List<FarmlyLiveHarvest> harvests = const [],
  List<FarmlyLivePlanting>? plantings,
  String? farmLocalDate = '2026-10-21',
}) => FarmlyLiveZoneCollection(
  cacheState: cacheState,
  canCreate: false,
  organizationName: scope.organization.name,
  farmName: scope.selectedFarm?.name ?? '',
  zones: [
    const FarmlyLiveZone(
      zone: FarmlyZoneDto(
        id: _zoneId,
        version: 1,
        type: 'crop_plot',
        name: 'Luống A',
        geometry: FarmlyZoneGeometry(points: []),
        status: 'active',
      ),
      syncState: FarmlyZoneSyncState.confirmed,
    ),
  ],
  cropSpecies: const [
    FarmlyLiveCropSpecies(
      species: FarmlyCropSpeciesDto(
        id: _speciesId,
        version: 1,
        name: 'Cà chua bi',
        harvestUnit: 'kg',
        status: 'active',
      ),
      syncState: FarmlyZoneSyncState.confirmed,
    ),
  ],
  plantings:
      plantings ??
      const [
        FarmlyLivePlanting(
          planting: FarmlyPlantingDto(
            id: _plantingId,
            version: 1,
            cropSpeciesId: _speciesId,
            plotId: _zoneId,
            status: 'active',
            sowingDate: '2026-09-01',
          ),
          syncState: FarmlyZoneSyncState.confirmed,
        ),
      ],
  harvests: harvests,
  farmLocalDate: farmLocalDate,
  scope: _mutationScope(scope),
  selectedScope: scope,
);

FarmlyLiveZoneCollection _emptyCollection(FarmlyZoneCacheState cacheState) =>
    FarmlyLiveZoneCollection(
      cacheState: cacheState,
      canCreate: false,
      organizationName: '',
      farmName: '',
      zones: const [],
    );

FarmlyLiveHarvest _harvest(
  String id,
  String quantity,
  String date, {
  String status = 'active',
  FarmlyZoneSyncState syncState = FarmlyZoneSyncState.confirmed,
  int? version,
  List<FarmlyLiveHarvestCorrectionProposal> proposals = const [],
  FarmlyZoneSyncState? pendingManagerMutationState,
}) => FarmlyLiveHarvest(
  id: id,
  version: version ?? 1,
  plantingId: _plantingId,
  quantityKg: FarmlyDecimal.parse(quantity),
  harvestDate: date,
  status: status,
  syncState: syncState,
  correctionProposals: proposals,
  pendingManagerMutationState: pendingManagerMutationState,
);

class _TestSessionController extends FarmlyAuthSessionController {
  @override
  Future<FarmlyAuthSession?> build() async => _session;
}

class _FixedScopeController extends SelectedOrganizationScopeController {
  _FixedScopeController(this.scope);

  final FarmlyOrganizationScope? scope;

  @override
  FarmlyOrganizationScope? build() => scope;
}
