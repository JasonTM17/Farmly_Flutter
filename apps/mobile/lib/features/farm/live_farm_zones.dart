import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/auth/auth_session_controller.dart';
import '../../core/format/display_format.dart';
import '../../core/sync/farmly_mutation.dart';
import '../../core/sync/farmly_task_schedule.dart';
import '../../core/sync/sync_models.dart';
import '../../core/sync/sync_providers.dart';
import '../../core/theme/farmly_spacing.dart';
import '../../core/theme/farmly_theme_extension.dart';
import '../../generated/farmly_api_types.dart';
import '../../l10n/generated/app_localizations.dart';
import '../../ui/farm_card.dart';
import '../../ui/farm_scaffold.dart';
import '../../ui/form_fields.dart';
import '../../ui/pickers.dart';
import '../../ui/screen_states.dart';
import 'farm_name_edit_sheet.dart';
import '../organizations/organization_repository.dart';
import '../organizations/organization_scope_controller.dart';

enum FarmlyZoneCacheState {
  noFarm,
  notBootstrapped,
  stale,
  ready,
  scopeChanged,
}

enum FarmlyZoneSyncState {
  confirmed,
  savedOnDevice,
  checkingServer,
  needsAttention,
  awaitingProjection,
}

const _liveTaskOccurrencesListKey = ValueKey('live-task-occurrences-list');
final _inFlightPlantingMutationKeys = <String>{};

final class FarmlyLiveZone {
  const FarmlyLiveZone({
    required this.zone,
    required this.syncState,
    this.operationId,
  });

  final FarmlyZoneDto zone;
  final FarmlyZoneSyncState syncState;
  final String? operationId;
}

final class FarmlyLiveCropSpecies {
  const FarmlyLiveCropSpecies({
    required this.species,
    required this.syncState,
    this.operationId,
    this.hasUnresolvedUpdate = false,
  });

  final FarmlyCropSpeciesDto species;
  final FarmlyZoneSyncState syncState;
  final String? operationId;
  final bool hasUnresolvedUpdate;
}

final class FarmlyLivePlanting {
  const FarmlyLivePlanting({
    required this.planting,
    required this.syncState,
    this.operationId,
    this.events = const [],
    this.hasUnresolvedUpdate = false,
    this.hasUnresolvedArchive = false,
    this.isUniqueConfirmedRecord = true,
  });

  final FarmlyPlantingDto planting;
  final FarmlyZoneSyncState syncState;
  final String? operationId;
  final List<FarmlyLivePlantingEvent> events;
  final bool hasUnresolvedUpdate;
  final bool hasUnresolvedArchive;
  final bool isUniqueConfirmedRecord;
}

final class FarmlyLivePlantingEvent {
  const FarmlyLivePlantingEvent({
    required this.id,
    required this.plantingId,
    required this.eventType,
    required this.syncState,
    this.note,
    this.occurredOn,
    this.operationId,
  });

  final String id;
  final String plantingId;
  final String eventType;
  final String? note;
  final String? occurredOn;
  final FarmlyZoneSyncState syncState;
  final String? operationId;
}

final class FarmlyLiveHarvest {
  const FarmlyLiveHarvest({
    required this.id,
    required this.version,
    required this.plantingId,
    required this.quantityKg,
    required this.harvestDate,
    required this.status,
    required this.syncState,
    this.correctionProposals = const [],
    this.pendingManagerMutationState,
    this.operationId,
  });

  final String id;
  final int version;
  final String plantingId;
  final FarmlyDecimal quantityKg;
  final String harvestDate;
  final String status;
  final FarmlyZoneSyncState syncState;
  final List<FarmlyLiveHarvestCorrectionProposal> correctionProposals;
  final FarmlyZoneSyncState? pendingManagerMutationState;
  final String? operationId;
}

final class FarmlyLiveHarvestCorrectionProposal {
  const FarmlyLiveHarvestCorrectionProposal({
    required this.id,
    required this.harvestId,
    required this.proposedQuantityKg,
    required this.reason,
    required this.status,
  });

  final String id;
  final String harvestId;
  final FarmlyDecimal proposedQuantityKg;
  final String reason;
  final String status;
}

final class FarmlyLiveWaterTank {
  const FarmlyLiveWaterTank({
    required this.tank,
    required this.syncState,
    this.operationId,
    this.projectedName,
    this.hasUnresolvedNameUpdate = false,
    this.isUniqueConfirmedRecord = false,
  });

  final FarmlyWaterTankDto tank;
  final FarmlyZoneSyncState syncState;
  final String? operationId;
  final String? projectedName;
  final bool hasUnresolvedNameUpdate;
  final bool isUniqueConfirmedRecord;

  String get displayName => projectedName ?? tank.name;
}

final class FarmlyLiveWaterReading {
  const FarmlyLiveWaterReading({
    required this.id,
    required this.tankId,
    required this.storedLitres,
    required this.source,
    this.measuredAt,
    required this.syncState,
    this.operationId,
  });

  final String id;
  final String tankId;
  final FarmlyDecimal storedLitres;
  final String source;
  final String? measuredAt;
  final FarmlyZoneSyncState syncState;
  final String? operationId;
}

final class FarmlyLiveMoistureReading {
  const FarmlyLiveMoistureReading({
    required this.id,
    required this.zoneId,
    required this.value,
    required this.method,
    required this.source,
    required this.measuredAt,
    required this.syncState,
    this.operationId,
  });

  final String id;
  final String zoneId;
  final FarmlyDecimal value;
  final String method;
  final String source;
  final String measuredAt;
  final FarmlyZoneSyncState syncState;
  final String? operationId;
}

final class FarmlyLiveWaterUsage {
  const FarmlyLiveWaterUsage({
    required this.id,
    required this.tankId,
    required this.usageLitres,
    required this.usageDate,
    this.note,
    required this.syncState,
    this.operationId,
  });

  final String id;
  final String tankId;
  final FarmlyDecimal usageLitres;
  final String usageDate;
  final String? note;
  final FarmlyZoneSyncState syncState;
  final String? operationId;
}

final class FarmlyLiveTaskTemplate {
  FarmlyLiveTaskTemplate({
    required this.id,
    required this.version,
    required this.title,
    required this.kind,
    required this.zoneId,
    required this.frequency,
    required this.timeOfDay,
    required List<int> daysOfWeek,
    required this.startsOn,
    required this.endsOn,
    required this.assigneeMembershipId,
    required this.scheduleValid,
    required this.status,
    required this.syncState,
    this.operationId,
  }) : daysOfWeek = List.unmodifiable(daysOfWeek);

  final String id;
  final int version;
  final String title;
  final String kind;
  final String? zoneId;
  final String frequency;
  final String timeOfDay;
  final List<int> daysOfWeek;
  final String? startsOn;
  final String? endsOn;
  final String? assigneeMembershipId;
  final bool scheduleValid;
  final String status;
  final FarmlyZoneSyncState syncState;
  final String? operationId;

  FarmlyLiveTaskTemplate copyWith({
    String? frequency,
    String? timeOfDay,
    List<int>? daysOfWeek,
    bool? scheduleValid,
    FarmlyZoneSyncState? syncState,
    String? operationId,
  }) => FarmlyLiveTaskTemplate(
    id: id,
    version: version,
    title: title,
    kind: kind,
    zoneId: zoneId,
    frequency: frequency ?? this.frequency,
    timeOfDay: timeOfDay ?? this.timeOfDay,
    daysOfWeek: daysOfWeek ?? this.daysOfWeek,
    startsOn: startsOn,
    endsOn: endsOn,
    assigneeMembershipId: assigneeMembershipId,
    scheduleValid: scheduleValid ?? this.scheduleValid,
    status: status,
    syncState: syncState ?? this.syncState,
    operationId: operationId ?? this.operationId,
  );
}

final class FarmlyLiveTaskOccurrence {
  const FarmlyLiveTaskOccurrence({
    required this.id,
    required this.templateId,
    required this.occurrenceDate,
    required this.slot,
    required this.status,
    required this.version,
    required this.isMaterialized,
    required this.syncState,
    this.operationId,
  });

  final String id;
  final String templateId;
  final String occurrenceDate;
  final String slot;
  final String status;
  final int? version;
  final bool isMaterialized;
  final FarmlyZoneSyncState syncState;
  final String? operationId;

  FarmlyLiveTaskOccurrence copyWith({
    String? status,
    FarmlyZoneSyncState? syncState,
    String? operationId,
  }) => FarmlyLiveTaskOccurrence(
    id: id,
    templateId: templateId,
    occurrenceDate: occurrenceDate,
    slot: slot,
    status: status ?? this.status,
    version: version,
    isMaterialized: isMaterialized,
    syncState: syncState ?? this.syncState,
    operationId: operationId ?? this.operationId,
  );
}

Widget _sectionTitle(BuildContext context, {required String title}) => Padding(
  padding: const EdgeInsets.only(bottom: FarmSpacing.xs),
  child: Text(title, style: Theme.of(context).textTheme.titleMedium),
);

final class FarmlyLiveZoneCollection {
  FarmlyLiveZoneCollection({
    required this.cacheState,
    required this.canCreate,
    required this.organizationName,
    required this.farmName,
    required List<FarmlyLiveZone> zones,
    List<FarmlyLiveCropSpecies> cropSpecies = const [],
    List<FarmlyLivePlanting> plantings = const [],
    List<FarmlyLiveHarvest> harvests = const [],
    List<FarmlyLiveWaterTank> waterTanks = const [],
    List<FarmlyLiveWaterReading> waterReadings = const [],
    List<FarmlyLiveMoistureReading> moistureReadings = const [],
    List<FarmlyLiveWaterUsage> waterUsages = const [],
    List<FarmlyLiveTaskTemplate> taskTemplates = const [],
    List<FarmlyLiveTaskOccurrence> taskOccurrences = const [],
    this.canEditFarmName = false,
    this.farmNamePending = false,
    this.farmNameHasPendingUpdate = false,
    this.farmVersion,
    this.farmTimezone,
    this.farmLocalDate,
    this.scope,
    this.selectedScope,
  }) : zones = List.unmodifiable(zones),
       cropSpecies = List.unmodifiable(cropSpecies),
       plantings = List.unmodifiable(plantings),
       harvests = List.unmodifiable(harvests),
       waterTanks = List.unmodifiable(waterTanks),
       waterReadings = List.unmodifiable(waterReadings),
       moistureReadings = List.unmodifiable(moistureReadings),
       waterUsages = List.unmodifiable(waterUsages),
       taskTemplates = List.unmodifiable(taskTemplates),
       taskOccurrences = List.unmodifiable(taskOccurrences);

  final FarmlyZoneCacheState cacheState;
  final bool canCreate;
  final String organizationName;
  final String farmName;
  final bool canEditFarmName;
  final bool farmNamePending;
  final bool farmNameHasPendingUpdate;
  final int? farmVersion;
  final FarmlyMutationScope? scope;
  final FarmlyOrganizationScope? selectedScope;
  final List<FarmlyLiveZone> zones;
  final List<FarmlyLiveCropSpecies> cropSpecies;
  final List<FarmlyLivePlanting> plantings;
  final List<FarmlyLiveHarvest> harvests;
  final List<FarmlyLiveWaterTank> waterTanks;
  final List<FarmlyLiveWaterReading> waterReadings;
  final List<FarmlyLiveMoistureReading> moistureReadings;
  final List<FarmlyLiveWaterUsage> waterUsages;
  final List<FarmlyLiveTaskTemplate> taskTemplates;
  final List<FarmlyLiveTaskOccurrence> taskOccurrences;
  final String? farmTimezone;
  final String? farmLocalDate;
}

final class _FarmNameProjection {
  const _FarmNameProjection({
    required this.name,
    required this.pending,
    required this.hasPendingUpdate,
  });

  final String name;
  final bool pending;
  final bool hasPendingUpdate;
}

_FarmNameProjection _projectFarmName({
  required FarmlyFarmDto confirmedFarm,
  required List<OutboxEntry> entries,
  required FarmlyMutationScope scope,
}) {
  final updates = entries
      .where(
        (entry) =>
            _entryMatchesScope(entry, scope) &&
            entry.mutation.intent.type == 'farm.update' &&
            entry.mutation.intent.resourceId == confirmedFarm.farmId &&
            entry.status != OutboxEntryStatus.rejected,
      )
      .where((entry) {
        final intent = entry.mutation.intent;
        return !(entry.status == OutboxEntryStatus.applied &&
            intent.baseVersion != null &&
            confirmedFarm.version > intent.baseVersion!);
      })
      .toList(growable: false);

  if (updates.isEmpty) {
    return _FarmNameProjection(
      name: confirmedFarm.name,
      pending: false,
      hasPendingUpdate: false,
    );
  }
  if (updates.length != 1) {
    return _FarmNameProjection(
      name: confirmedFarm.name,
      pending: false,
      hasPendingUpdate: true,
    );
  }

  final entry = updates.single;
  final intent = entry.mutation.intent;
  final name = intent.payload['name'];
  final versionMatches = intent.baseVersion == confirmedFarm.version;
  final canShowPendingName =
      versionMatches &&
      name is String &&
      name.isNotEmpty &&
      name == name.trim() &&
      entry.status != OutboxEntryStatus.blocked &&
      entry.status != OutboxEntryStatus.conflict;
  if (!canShowPendingName) {
    return _FarmNameProjection(
      name: confirmedFarm.name,
      pending: false,
      hasPendingUpdate: true,
    );
  }

  return _FarmNameProjection(
    name: name,
    pending:
        entry.status == OutboxEntryStatus.pending ||
        entry.status == OutboxEntryStatus.inFlight,
    hasPendingUpdate: entry.status != OutboxEntryStatus.rejected,
  );
}

final farmlyUtcNowProvider = Provider<DateTime Function()>(
  (ref) =>
      () => DateTime.now().toUtc(),
);

final farmlyLiveZoneCollectionProvider =
    FutureProvider<FarmlyLiveZoneCollection>((ref) async {
      final selected = ref.watch(selectedOrganizationScopeProvider);
      final syncScope = await ref.watch(farmlySyncScopeProvider.future);
      // Rebuild this projection after a local enqueue, sync, or reconciliation.
      ref.watch(syncStatusProvider);
      if (syncScope == null ||
          selected == null ||
          syncScope.kind != FarmlyMutationScopeKind.farm ||
          syncScope.farmId == null ||
          selected.organization.id != syncScope.organizationId ||
          selected.selectedFarmId != syncScope.farmId) {
        return FarmlyLiveZoneCollection(
          cacheState: FarmlyZoneCacheState.noFarm,
          canCreate: false,
          organizationName: selected?.organization.name ?? '',
          farmName: '',
          zones: const [],
          selectedScope: selected,
        );
      }

      final farm = selected.selectedFarm;
      if (farm == null || farm.status != FarmlyFarmStatus.active) {
        return FarmlyLiveZoneCollection(
          cacheState: FarmlyZoneCacheState.noFarm,
          canCreate: false,
          organizationName: selected.organization.name,
          farmName: '',
          zones: const [],
          selectedScope: selected,
        );
      }

      final session = await ref.watch(farmlyAuthSessionProvider.future);
      if (session == null || session.user.id != syncScope.accountId) {
        return FarmlyLiveZoneCollection(
          cacheState: FarmlyZoneCacheState.scopeChanged,
          canCreate: false,
          organizationName: selected.organization.name,
          farmName: farm.name,
          zones: const [],
          selectedScope: selected,
        );
      }

      final engine = await ref.watch(syncEngineProvider.future);
      final snapshot = await engine.domainSnapshot(syncScope);
      final outboxEntries = await engine.entries(
        accountId: syncScope.accountId,
        organizationId: syncScope.organizationId,
      );

      final currentSelection = ref.read(selectedOrganizationScopeProvider);
      final currentSyncScope = ref.read(farmlySyncScopeProvider).asData?.value;
      final currentAccount = ref
          .read(farmlyAuthSessionProvider)
          .asData
          ?.value
          ?.user
          .id;
      if (!_sameSelection(selected, currentSelection) ||
          !_sameFarmScope(syncScope, currentSyncScope) ||
          currentAccount != syncScope.accountId) {
        return FarmlyLiveZoneCollection(
          cacheState: FarmlyZoneCacheState.scopeChanged,
          canCreate: false,
          organizationName: selected.organization.name,
          farmName: farm.name,
          zones: const [],
          scope: syncScope,
          selectedScope: selected,
        );
      }

      final canCreate = _canManageZones(selected, farm);
      if (snapshot == null) {
        return FarmlyLiveZoneCollection(
          cacheState: FarmlyZoneCacheState.notBootstrapped,
          canCreate: canCreate,
          organizationName: selected.organization.name,
          farmName: farm.name,
          zones: _pendingZoneEntries(outboxEntries, syncScope),
          cropSpecies: _pendingCropSpeciesEntries(outboxEntries, syncScope),
          plantings: _withPlantingEvents(
            _pendingPlantingEntries(outboxEntries, syncScope),
            const {},
            outboxEntries,
            syncScope,
          ),
          harvests: _pendingHarvestEntries(outboxEntries, syncScope),
          waterTanks: _pendingWaterTankEntries(outboxEntries, syncScope),
          waterReadings: _pendingWaterReadingEntries(outboxEntries, syncScope),
          moistureReadings: _pendingMoistureReadingEntries(
            outboxEntries,
            syncScope,
          ),
          waterUsages: _pendingWaterUsageEntries(outboxEntries, syncScope),
          taskTemplates: _pendingTaskTemplateEntries(outboxEntries, syncScope),
          scope: syncScope,
          selectedScope: selected,
        );
      }

      if (snapshot.cursor.continuityEpoch !=
              selected.directory.continuityEpoch ||
          snapshot.cursor.scopePolicyVersion !=
              selected.directory.scopePolicyVersion) {
        return FarmlyLiveZoneCollection(
          cacheState: FarmlyZoneCacheState.stale,
          canCreate: canCreate,
          organizationName: selected.organization.name,
          farmName: farm.name,
          zones: _pendingZoneEntries(outboxEntries, syncScope),
          cropSpecies: _pendingCropSpeciesEntries(outboxEntries, syncScope),
          plantings: _withPlantingEvents(
            _pendingPlantingEntries(outboxEntries, syncScope),
            const {},
            outboxEntries,
            syncScope,
          ),
          harvests: _pendingHarvestEntries(outboxEntries, syncScope),
          waterTanks: _pendingWaterTankEntries(outboxEntries, syncScope),
          waterReadings: _pendingWaterReadingEntries(outboxEntries, syncScope),
          moistureReadings: _pendingMoistureReadingEntries(
            outboxEntries,
            syncScope,
          ),
          waterUsages: _pendingWaterUsageEntries(outboxEntries, syncScope),
          taskTemplates: _pendingTaskTemplateEntries(outboxEntries, syncScope),
          scope: syncScope,
          selectedScope: selected,
        );
      }

      String? farmTimezone;
      String? farmLocalDate;
      FarmlyFarmDto? confirmedFarm;
      final farmRows = snapshot.recordsFor('farm').values;
      if (farmRows.length == 1 && farmRows.single is Map) {
        final row = FarmlyFarmDto.fromJson(
          Map<String, dynamic>.from(farmRows.single as Map),
        );
        if (row.farmId == syncScope.farmId) {
          confirmedFarm = row;
          try {
            farmLocalDate = farmlyTaskCivilDateAtUtc(
              ref.read(farmlyUtcNowProvider)(),
              row.timezone,
            );
            farmTimezone = row.timezone;
          } on Object {
            // Invalid/missing timezone data gates date-derived tasks. Do not
            // substitute the device's timezone or break other farm details.
          }
        }
      }
      final farmNameProjection = confirmedFarm == null
          ? _FarmNameProjection(
              name: farm.name,
              pending: false,
              hasPendingUpdate: false,
            )
          : _projectFarmName(
              confirmedFarm: confirmedFarm,
              entries: outboxEntries,
              scope: syncScope,
            );

      final confirmed = <String, FarmlyLiveZone>{};
      for (final row in snapshot.recordsFor('zone').values) {
        if (row is! Map) {
          throw const FormatException('Invalid local zone record');
        }
        final zone = FarmlyZoneDto.fromJson(Map<String, dynamic>.from(row));
        confirmed[zone.id] = FarmlyLiveZone(
          zone: zone,
          syncState: FarmlyZoneSyncState.confirmed,
        );
      }
      for (final pending in _pendingZoneEntries(outboxEntries, syncScope)) {
        confirmed.putIfAbsent(pending.zone.id, () => pending);
      }
      _projectZoneUpdates(confirmed, outboxEntries, syncScope);
      final zones = confirmed.values.toList()
        ..sort(
          (a, b) =>
              a.zone.name.toLowerCase().compareTo(b.zone.name.toLowerCase()),
        );
      final cropSpecies = <String, FarmlyLiveCropSpecies>{};
      for (final row in snapshot.recordsFor('cropSpecies').values) {
        if (row is! Map) {
          throw const FormatException('Invalid local crop species record');
        }
        final species = FarmlyCropSpeciesDto.fromJson(
          Map<String, dynamic>.from(row),
        );
        cropSpecies[species.id] = FarmlyLiveCropSpecies(
          species: species,
          syncState: FarmlyZoneSyncState.confirmed,
        );
      }
      for (final pending in _pendingCropSpeciesEntries(
        outboxEntries,
        syncScope,
      )) {
        cropSpecies.putIfAbsent(pending.species.id, () => pending);
      }
      _projectCropSpeciesMutations(cropSpecies, outboxEntries, syncScope);
      final plantings = <String, FarmlyLivePlanting>{};
      final plantingRecords = snapshot.recordsFor('planting');
      final plantingIdCounts = <String, int>{};
      for (final row in plantingRecords.values) {
        if (row is Map && row['id'] is String) {
          plantingIdCounts.update(
            row['id'] as String,
            (count) => count + 1,
            ifAbsent: () => 1,
          );
        }
      }
      for (final record in plantingRecords.entries) {
        final row = record.value;
        if (row is! Map) {
          throw const FormatException('Invalid local planting record');
        }
        final planting = FarmlyPlantingDto.fromJson(
          Map<String, dynamic>.from(row),
        );
        plantings[planting.id] = FarmlyLivePlanting(
          planting: planting,
          syncState: FarmlyZoneSyncState.confirmed,
          isUniqueConfirmedRecord:
              record.key == planting.id && plantingIdCounts[planting.id] == 1,
        );
      }
      for (final pending in _pendingPlantingEntries(outboxEntries, syncScope)) {
        plantings.putIfAbsent(pending.planting.id, () => pending);
      }
      _projectPlantingMutations(plantings, outboxEntries, syncScope);
      final plantingsWithEvents = _withPlantingEvents(
        plantings.values.toList(growable: false),
        snapshot.recordsFor('plantingEvent'),
        outboxEntries,
        syncScope,
      );
      final proposalsByHarvest =
          <String, List<FarmlyLiveHarvestCorrectionProposal>>{};
      for (final row in snapshot.recordsFor('correctionProposal').values) {
        if (row is! Map) {
          throw const FormatException('Invalid local harvest proposal record');
        }
        final json = Map<String, dynamic>.from(row);
        final status = json['status'] as String;
        if (status != 'pending' &&
            status != 'applied' &&
            status != 'superseded') {
          throw const FormatException('Invalid local harvest proposal status');
        }
        final proposal = FarmlyLiveHarvestCorrectionProposal(
          id: json['id'] as String,
          harvestId: json['harvestId'] as String,
          proposedQuantityKg: FarmlyDecimal.parse(
            json['proposedQuantityKg'] as String,
          ),
          reason: json['reason'] as String,
          status: status,
        );
        proposalsByHarvest
            .putIfAbsent(proposal.harvestId, () => [])
            .add(proposal);
      }

      final harvests = <String, FarmlyLiveHarvest>{};
      for (final row in snapshot.recordsFor('harvest').values) {
        if (row is! Map) {
          throw const FormatException('Invalid local harvest record');
        }
        final json = Map<String, dynamic>.from(row);
        final status = json['status'] as String;
        if (status != 'active' && status != 'voided') {
          throw const FormatException('Invalid local harvest status');
        }
        final harvest = FarmlyLiveHarvest(
          id: json['id'] as String,
          version: json['version'] as int,
          plantingId: json['plantingId'] as String,
          quantityKg: FarmlyDecimal.parse(json['quantityKg'] as String),
          harvestDate: json['harvestDate'] as String,
          status: status,
          syncState: FarmlyZoneSyncState.confirmed,
          correctionProposals: List.unmodifiable(
            proposalsByHarvest[json['id'] as String] ?? const [],
          ),
          pendingManagerMutationState: _pendingHarvestManagerMutationState(
            outboxEntries,
            syncScope,
            json['id'] as String,
            headVersion: json['version'] as int,
            headStatus: status,
          ),
        );
        harvests[harvest.id] = harvest;
      }
      for (final pending in _pendingHarvestEntries(outboxEntries, syncScope)) {
        harvests.putIfAbsent(pending.id, () => pending);
      }
      final waterTankRecords = snapshot.recordsFor('waterTank');
      final waterTanks = <String, FarmlyLiveWaterTank>{};
      for (final record in waterTankRecords.entries) {
        final row = record.value;
        if (row is! Map) {
          throw const FormatException('Invalid local water tank record');
        }
        final tank = FarmlyWaterTankDto.fromJson(
          Map<String, dynamic>.from(row),
        );
        final matchingRecordCount = waterTankRecords.values
            .whereType<Map>()
            .where((candidate) => candidate['id'] == tank.id)
            .length;
        final update = _projectWaterTankNameUpdate(
          outboxEntries,
          syncScope,
          tank,
        );
        waterTanks[tank.id] = FarmlyLiveWaterTank(
          tank: tank,
          syncState: update.syncState ?? FarmlyZoneSyncState.confirmed,
          projectedName: update.name,
          hasUnresolvedNameUpdate: update.hasUnresolvedUpdate,
          isUniqueConfirmedRecord:
              record.key == tank.id && matchingRecordCount == 1,
        );
      }
      for (final pending in _pendingWaterTankEntries(
        outboxEntries,
        syncScope,
      )) {
        waterTanks.putIfAbsent(pending.tank.id, () => pending);
      }
      final waterReadings = <String, FarmlyLiveWaterReading>{};
      for (final row in snapshot.recordsFor('waterReading').values) {
        if (row is! Map) {
          throw const FormatException('Invalid local water reading record');
        }
        final json = Map<String, dynamic>.from(row);
        final reading = FarmlyLiveWaterReading(
          id: json['id'] as String,
          tankId: json['tankId'] as String,
          storedLitres: FarmlyDecimal.parse(json['storedLitres'] as String),
          source: json['source'] as String,
          measuredAt: json['measuredAt'] as String?,
          syncState: FarmlyZoneSyncState.confirmed,
        );
        waterReadings[reading.id] = reading;
      }
      for (final pending in _pendingWaterReadingEntries(
        outboxEntries,
        syncScope,
      )) {
        waterReadings.putIfAbsent(pending.id, () => pending);
      }
      final moistureReadings = <String, FarmlyLiveMoistureReading>{};
      for (final row in snapshot.recordsFor('moistureReading').values) {
        if (row is! Map) {
          throw const FormatException('Invalid local moisture reading record');
        }
        final reading = _farmlyLiveMoistureReadingFromJson(
          Map<String, dynamic>.from(row),
          syncState: FarmlyZoneSyncState.confirmed,
        );
        moistureReadings[reading.id] = reading;
      }
      for (final pending in _pendingMoistureReadingEntries(
        outboxEntries,
        syncScope,
      )) {
        moistureReadings.putIfAbsent(pending.id, () => pending);
      }
      final waterUsages = <String, FarmlyLiveWaterUsage>{};
      for (final row in snapshot.recordsFor('waterUsage').values) {
        if (row is! Map) {
          throw const FormatException('Invalid local water usage record');
        }
        final json = Map<String, dynamic>.from(row);
        final usage = FarmlyLiveWaterUsage(
          id: json['id'] as String,
          tankId: json['tankId'] as String,
          usageLitres: FarmlyDecimal.parse(json['usageLitres'] as String),
          usageDate: json['usageDate'] as String,
          note: json['note'] as String?,
          syncState: FarmlyZoneSyncState.confirmed,
        );
        waterUsages[usage.id] = usage;
      }
      for (final pending in _pendingWaterUsageEntries(
        outboxEntries,
        syncScope,
      )) {
        waterUsages.putIfAbsent(pending.id, () => pending);
      }
      final taskTemplates = <String, FarmlyLiveTaskTemplate>{};
      for (final row in snapshot.recordsFor('taskTemplate').values) {
        if (row is! Map) {
          throw const FormatException('Invalid local task template record');
        }
        final template = _farmlyLiveTaskTemplateFromJson(
          Map<String, dynamic>.from(row),
          syncState: FarmlyZoneSyncState.confirmed,
        );
        taskTemplates[template.id] = template;
      }
      for (final pending in _pendingTaskTemplateEntries(
        outboxEntries,
        syncScope,
      )) {
        taskTemplates.putIfAbsent(pending.id, () => pending);
      }
      _projectTaskTemplateScheduleUpdates(
        taskTemplates,
        outboxEntries,
        syncScope,
      );
      final taskOccurrences = _farmlyTaskOccurrencesForToday(
        farmId: syncScope.farmId!,
        farmLocalDate: farmLocalDate,
        templates: taskTemplates.values.toList(growable: false),
        occurrenceRows: snapshot.recordsFor('taskOccurrence').values,
        outboxEntries: outboxEntries,
        scope: syncScope,
      );
      return FarmlyLiveZoneCollection(
        cacheState: FarmlyZoneCacheState.ready,
        canCreate: canCreate,
        organizationName: selected.organization.name,
        farmName: farmNameProjection.name,
        canEditFarmName:
            confirmedFarm != null &&
            confirmedFarm.status == 'active' &&
            _canEditFarmName(selected, farm),
        farmNamePending: farmNameProjection.pending,
        farmNameHasPendingUpdate: farmNameProjection.hasPendingUpdate,
        farmVersion: confirmedFarm?.version,
        zones: zones,
        cropSpecies: cropSpecies.values.toList(growable: false),
        plantings: plantingsWithEvents,
        harvests: harvests.values.toList(growable: false),
        waterTanks: waterTanks.values.toList(growable: false),
        waterReadings: waterReadings.values.toList(growable: false),
        moistureReadings: moistureReadings.values.toList(growable: false),
        waterUsages: waterUsages.values.toList(growable: false),
        taskTemplates: taskTemplates.values.toList(growable: false),
        taskOccurrences: taskOccurrences,
        farmTimezone: farmTimezone,
        farmLocalDate: farmLocalDate,
        scope: syncScope,
        selectedScope: selected,
      );
    });

bool _sameSelection(
  FarmlyOrganizationScope expected,
  FarmlyOrganizationScope? current,
) =>
    current != null &&
    current.epoch == expected.epoch &&
    current.organization.id == expected.organization.id &&
    current.organization.status == expected.organization.status &&
    current.organization.role == expected.organization.role &&
    current.selectedFarmId == expected.selectedFarmId &&
    current.directory.continuityEpoch == expected.directory.continuityEpoch &&
    current.directory.scopePolicyVersion ==
        expected.directory.scopePolicyVersion;

bool _sameFarmScope(
  FarmlyMutationScope expected,
  FarmlyMutationScope? current,
) =>
    current != null &&
    current.kind == FarmlyMutationScopeKind.farm &&
    current.accountId == expected.accountId &&
    current.organizationId == expected.organizationId &&
    current.farmId == expected.farmId &&
    current.continuityEpoch == expected.continuityEpoch;

List<OutboxEntry> _zoneUpdateEntries({
  required List<OutboxEntry> entries,
  required FarmlyMutationScope scope,
  required String zoneId,
  required int confirmedVersion,
}) => entries
    .where((entry) {
      final intent = entry.mutation.intent;
      if (!_entryMatchesScope(entry, scope) ||
          intent.type != 'zone.update' ||
          intent.resourceId != zoneId ||
          entry.status == OutboxEntryStatus.rejected) {
        return false;
      }
      return !(entry.status == OutboxEntryStatus.applied &&
          intent.baseVersion != null &&
          confirmedVersion > intent.baseVersion!);
    })
    .toList(growable: false);

void _projectZoneUpdates(
  Map<String, FarmlyLiveZone> zones,
  List<OutboxEntry> entries,
  FarmlyMutationScope scope,
) {
  for (final current in zones.values.toList(growable: false)) {
    if (current.syncState != FarmlyZoneSyncState.confirmed ||
        current.zone.version < 1 ||
        current.zone.status != 'active') {
      continue;
    }
    final updates = _zoneUpdateEntries(
      entries: entries,
      scope: scope,
      zoneId: current.zone.id,
      confirmedVersion: current.zone.version,
    );
    if (updates.isEmpty) continue;
    if (updates.length != 1) {
      zones[current.zone.id] = FarmlyLiveZone(
        zone: current.zone,
        syncState: FarmlyZoneSyncState.needsAttention,
      );
      continue;
    }

    final entry = updates.single;
    final intent = entry.mutation.intent;
    FarmlyZoneDto? projected;
    try {
      if (intent.payload.isNotEmpty &&
          intent.payload.keys.every(
            const {'name', 'type', 'geometry', 'areaM2'}.contains,
          )) {
        projected = FarmlyZoneDto.fromJson({
          ...current.zone.toJson(),
          ...intent.payload,
        });
      }
    } on Object {
      projected = null;
    }
    final canProject =
        intent.baseVersion == current.zone.version &&
        projected != null &&
        projected.id == current.zone.id &&
        projected.version == current.zone.version &&
        projected.status == 'active' &&
        entry.status != OutboxEntryStatus.blocked &&
        entry.status != OutboxEntryStatus.conflict;
    if (!canProject) {
      zones[current.zone.id] = FarmlyLiveZone(
        zone: current.zone,
        syncState: FarmlyZoneSyncState.needsAttention,
        operationId: entry.operationId,
      );
      continue;
    }
    zones[current.zone.id] = FarmlyLiveZone(
      zone: projected,
      syncState: _syncStateForEntry(entry),
      operationId: entry.operationId,
    );
  }
}

Future<void> _openLiveZoneRename(
  BuildContext context,
  WidgetRef ref, {
  required FarmlyMutationScope scope,
  required FarmlyOrganizationScope selectedScope,
  required FarmlyZoneDto zone,
}) async {
  final saved = await showModalBottomSheet<bool>(
    context: context,
    isScrollControlled: true,
    useSafeArea: true,
    builder: (_) => _LiveZoneRenameSheet(
      scope: scope,
      selectedScope: selectedScope,
      zone: zone,
    ),
  );
  if (!context.mounted || saved != true) return;
  ref.invalidate(syncStatusProvider);
  ref.invalidate(farmlyLiveZoneCollectionProvider);
  showFarmToast(context, AppLocalizations.of(context).liveFarmSavedPending);
}

Future<bool> _enqueueFarmNameUpdate({
  required WidgetRef ref,
  required FarmlyLiveZoneCollection captured,
  required String name,
}) async {
  final scope = captured.scope;
  final selected = captured.selectedScope;
  final farmId = scope?.farmId;
  if (!captured.canEditFarmName ||
      captured.farmNameHasPendingUpdate ||
      scope == null ||
      selected == null ||
      farmId == null ||
      captured.farmVersion == null) {
    return false;
  }

  final session = await ref.read(farmlyAuthSessionProvider.future);
  if (session == null || session.user.id != scope.accountId) return false;
  final engine = await ref.read(syncEngineProvider.future);
  final snapshot = await engine.domainSnapshot(scope);
  if (snapshot == null ||
      snapshot.cursor.continuityEpoch != scope.continuityEpoch ||
      snapshot.cursor.scopePolicyVersion !=
          selected.directory.scopePolicyVersion) {
    return false;
  }
  final farmRows = snapshot.recordsFor('farm').values;
  if (farmRows.length != 1 || farmRows.single is! Map) return false;
  final farm = FarmlyFarmDto.fromJson(
    Map<String, dynamic>.from(farmRows.single as Map),
  );
  if (farm.farmId != farmId ||
      farm.status != 'active' ||
      farm.version != captured.farmVersion) {
    return false;
  }

  final entries = await engine.entries(
    accountId: scope.accountId,
    organizationId: scope.organizationId,
  );
  if (_hasOutstandingFarmNameUpdate(entries, scope, farm.version)) {
    return false;
  }

  final currentSelection = ref.read(selectedOrganizationScopeProvider);
  final currentScope = ref.read(farmlySyncScopeProvider).asData?.value;
  final currentAccount = ref
      .read(farmlyAuthSessionProvider)
      .asData
      ?.value
      ?.user
      .id;
  final currentFarm = currentSelection?.selectedFarm;
  if (currentAccount != scope.accountId ||
      !_sameSelection(selected, currentSelection) ||
      !_sameFarmScope(scope, currentScope) ||
      currentSelection?.selectedFarmId != farmId ||
      currentFarm == null ||
      !_canEditFarmName(currentSelection!, currentFarm)) {
    return false;
  }

  await engine.enqueue(
    FarmlyScopedMutation(
      scope: scope,
      intent: FarmlyUpdateFarmNameIntent(
        operationId: newFarmlyOperationId(),
        continuityEpoch: scope.continuityEpoch,
        resourceId: farmId,
        baseVersion: farm.version,
        name: name,
      ),
    ),
  );
  return true;
}

bool _hasOutstandingFarmNameUpdate(
  List<OutboxEntry> entries,
  FarmlyMutationScope scope,
  int confirmedVersion,
) => entries.any((entry) {
  final intent = entry.mutation.intent;
  if (!_entryMatchesScope(entry, scope) ||
      intent.type != 'farm.update' ||
      intent.resourceId != scope.farmId ||
      entry.status == OutboxEntryStatus.rejected) {
    return false;
  }
  return !(entry.status == OutboxEntryStatus.applied &&
      intent.baseVersion != null &&
      confirmedVersion > intent.baseVersion!);
});

bool _hasOutstandingCropSpeciesMutation(
  List<OutboxEntry> entries,
  FarmlyMutationScope scope,
  String speciesId,
  int confirmedVersion,
) => entries.any((entry) {
  final intent = entry.mutation.intent;
  if (!_entryMatchesScope(entry, scope) ||
      (intent.type != 'cropSpecies.update' &&
          intent.type != 'cropSpecies.archive') ||
      intent.resourceId != speciesId ||
      entry.status == OutboxEntryStatus.rejected) {
    return false;
  }
  return !(entry.status == OutboxEntryStatus.applied &&
      intent.baseVersion != null &&
      confirmedVersion > intent.baseVersion!);
});

bool _hasOutstandingWaterTankUpdate(
  List<OutboxEntry> entries,
  FarmlyMutationScope scope,
  String tankId,
  int confirmedVersion,
) => entries.any((entry) {
  final intent = entry.mutation.intent;
  if (!_entryMatchesScope(entry, scope) ||
      intent.type != 'waterTank.update' ||
      intent.resourceId != tankId ||
      entry.status == OutboxEntryStatus.rejected) {
    return false;
  }
  return !(entry.status == OutboxEntryStatus.applied &&
      intent.baseVersion != null &&
      confirmedVersion > intent.baseVersion!);
});

List<OutboxEntry> _unresolvedPlantingMutations(
  List<OutboxEntry> entries,
  FarmlyMutationScope scope,
  String plantingId,
  int confirmedVersion,
) => entries
    .where((entry) {
      final intent = entry.mutation.intent;
      if (!_entryMatchesScope(entry, scope) ||
          (intent.type != 'planting.update' &&
              intent.type != 'planting.archive') ||
          intent.resourceId != plantingId ||
          entry.status == OutboxEntryStatus.rejected) {
        return false;
      }
      return !(entry.status == OutboxEntryStatus.applied &&
          intent.baseVersion != null &&
          confirmedVersion > intent.baseVersion!);
    })
    .toList(growable: false);

bool _hasOutstandingPlantingMutation(
  List<OutboxEntry> entries,
  FarmlyMutationScope scope,
  String plantingId,
  int confirmedVersion,
) => _unresolvedPlantingMutations(
  entries,
  scope,
  plantingId,
  confirmedVersion,
).isNotEmpty;

void _projectPlantingMutations(
  Map<String, FarmlyLivePlanting> plantings,
  List<OutboxEntry> entries,
  FarmlyMutationScope scope,
) {
  for (final current in plantings.values.toList(growable: false)) {
    if (current.syncState != FarmlyZoneSyncState.confirmed ||
        current.planting.version < 1 ||
        current.planting.status == 'archived') {
      continue;
    }
    final mutations = _unresolvedPlantingMutations(
      entries,
      scope,
      current.planting.id,
      current.planting.version,
    );

    if (mutations.isEmpty) continue;
    if (mutations.length != 1) {
      plantings[current.planting.id] = FarmlyLivePlanting(
        planting: current.planting,
        syncState: FarmlyZoneSyncState.needsAttention,
        hasUnresolvedUpdate: mutations.any(
          (entry) => entry.mutation.intent.type == 'planting.update',
        ),
        hasUnresolvedArchive: mutations.any(
          (entry) => entry.mutation.intent.type == 'planting.archive',
        ),
        isUniqueConfirmedRecord: current.isUniqueConfirmedRecord,
      );
      continue;
    }

    final entry = mutations.single;
    final intent = entry.mutation.intent;
    if (intent.type == 'planting.archive') {
      final canProjectArchive =
          intent.baseVersion == current.planting.version &&
          intent.payload.isEmpty &&
          (entry.status == OutboxEntryStatus.pending ||
              entry.status == OutboxEntryStatus.inFlight ||
              entry.status == OutboxEntryStatus.applied);
      if (!canProjectArchive) {
        plantings[current.planting.id] = FarmlyLivePlanting(
          planting: current.planting,
          syncState: FarmlyZoneSyncState.needsAttention,
          operationId: entry.operationId,
          hasUnresolvedArchive: true,
          isUniqueConfirmedRecord: current.isUniqueConfirmedRecord,
        );
        continue;
      }
      plantings[current.planting.id] = FarmlyLivePlanting(
        planting: FarmlyPlantingDto(
          id: current.planting.id,
          version: current.planting.version,
          cropSpeciesId: current.planting.cropSpeciesId,
          plotId: current.planting.plotId,
          status: 'archived',
          sowingDate: current.planting.sowingDate,
          expectedHarvestDate: current.planting.expectedHarvestDate,
          areaM2: current.planting.areaM2,
        ),
        syncState: _syncStateForEntry(entry),
        operationId: entry.operationId,
        hasUnresolvedArchive: true,
        isUniqueConfirmedRecord: current.isUniqueConfirmedRecord,
      );
      continue;
    }

    final canProject =
        intent.baseVersion == current.planting.version &&
        _isValidPlantingUpdateProjection(intent, current.planting) &&
        (entry.status == OutboxEntryStatus.pending ||
            entry.status == OutboxEntryStatus.inFlight ||
            entry.status == OutboxEntryStatus.applied);
    if (!canProject) {
      plantings[current.planting.id] = FarmlyLivePlanting(
        planting: current.planting,
        syncState: FarmlyZoneSyncState.needsAttention,
        operationId: entry.operationId,
        hasUnresolvedUpdate: true,
        isUniqueConfirmedRecord: current.isUniqueConfirmedRecord,
      );
      continue;
    }

    final payload = intent.payload;
    final areaM2 = payload['areaM2'];
    plantings[current.planting.id] = FarmlyLivePlanting(
      planting: FarmlyPlantingDto(
        id: current.planting.id,
        version: current.planting.version,
        cropSpeciesId: current.planting.cropSpeciesId,
        plotId: current.planting.plotId,
        status: payload['status'] as String? ?? current.planting.status,
        sowingDate:
            payload['sowingDate'] as String? ?? current.planting.sowingDate,
        expectedHarvestDate:
            payload['expectedHarvestDate'] as String? ??
            current.planting.expectedHarvestDate,
        areaM2: areaM2 is String
            ? FarmlyDecimal.parse(areaM2)
            : current.planting.areaM2,
      ),
      syncState: _syncStateForEntry(entry),
      operationId: entry.operationId,
      hasUnresolvedUpdate: true,
      isUniqueConfirmedRecord: current.isUniqueConfirmedRecord,
    );
  }
}

bool _isValidPlantingUpdateProjection(
  FarmlyMutationIntent intent,
  FarmlyPlantingDto planting,
) {
  const allowedFields = {
    'status',
    'sowingDate',
    'expectedHarvestDate',
    'areaM2',
  };
  final payload = intent.payload;
  if (payload.isEmpty || !allowedFields.containsAll(payload.keys)) {
    return false;
  }

  final status = payload['status'];
  if (payload.containsKey('status') &&
      (status is! String ||
          !const {
            'planned',
            'active',
            'harvested',
            'completed',
          }.contains(status))) {
    return false;
  }

  final sowingDate = payload['sowingDate'];
  if (payload.containsKey('sowingDate') &&
      (sowingDate is! String || !_isValidCivilDate(sowingDate))) {
    return false;
  }
  final expectedHarvestDate = payload['expectedHarvestDate'];
  if (payload.containsKey('expectedHarvestDate') &&
      (expectedHarvestDate is! String ||
          !_isValidCivilDate(expectedHarvestDate))) {
    return false;
  }
  final effectiveSowingDate = sowingDate as String? ?? planting.sowingDate;
  final effectiveExpectedHarvestDate =
      expectedHarvestDate as String? ?? planting.expectedHarvestDate;
  if (!_isValidCivilDate(effectiveSowingDate) ||
      (effectiveExpectedHarvestDate != null &&
          (!_isValidCivilDate(effectiveExpectedHarvestDate) ||
              effectiveExpectedHarvestDate.compareTo(effectiveSowingDate) <
                  0))) {
    return false;
  }

  final areaM2 = payload['areaM2'];
  if (payload.containsKey('areaM2') &&
      (areaM2 is! String ||
          !RegExp(r'^(0|[1-9][0-9]{0,11})(\.[0-9]{1,2})?$').hasMatch(areaM2))) {
    return false;
  }
  return true;
}

({bool hasUnresolvedUpdate, String? name, FarmlyZoneSyncState? syncState})
_projectWaterTankNameUpdate(
  List<OutboxEntry> entries,
  FarmlyMutationScope scope,
  FarmlyWaterTankDto tank,
) {
  final matchingUpdates = entries
      .where((entry) {
        final intent = entry.mutation.intent;
        return _entryMatchesScope(entry, scope) &&
            intent.type == 'waterTank.update' &&
            intent.resourceId == tank.id &&
            entry.status != OutboxEntryStatus.rejected &&
            !(entry.status == OutboxEntryStatus.applied &&
                intent.baseVersion != null &&
                tank.version > intent.baseVersion!);
      })
      .toList(growable: false);
  if (matchingUpdates.isEmpty) {
    return (hasUnresolvedUpdate: false, name: null, syncState: null);
  }
  if (matchingUpdates.length != 1) {
    return (
      hasUnresolvedUpdate: true,
      name: null,
      syncState: FarmlyZoneSyncState.needsAttention,
    );
  }

  final entry = matchingUpdates.single;
  final intent = entry.mutation.intent;
  final canProjectEntry =
      (entry.status == OutboxEntryStatus.pending ||
          entry.status == OutboxEntryStatus.inFlight ||
          entry.status == OutboxEntryStatus.applied) &&
      intent.baseVersion == tank.version;
  return (
    hasUnresolvedUpdate: true,
    name: canProjectEntry && intent.payload['name'] is String
        ? intent.payload['name'] as String
        : null,
    syncState: canProjectEntry
        ? _syncStateForEntry(entry)
        : FarmlyZoneSyncState.needsAttention,
  );
}

bool _canManageCropSpecies(
  FarmlyOrganizationScope organizationScope,
  FarmlyDirectoryFarm farm,
) =>
    farm.status == FarmlyFarmStatus.active &&
    _canManageZones(organizationScope, farm);

Future<bool> _enqueueCropSpeciesNameUpdate({
  required WidgetRef ref,
  required FarmlyMutationScope scope,
  required FarmlyOrganizationScope selectedScope,
  required FarmlyCropSpeciesDto species,
  required String name,
}) => _enqueueCropSpeciesMutation(
  ref: ref,
  scope: scope,
  selectedScope: selectedScope,
  species: species,
  buildIntent: (operationId, baseVersion) => FarmlyUpdateCropSpeciesNameIntent(
    operationId: operationId,
    continuityEpoch: scope.continuityEpoch,
    resourceId: species.id,
    baseVersion: baseVersion,
    name: name,
  ),
);

Future<bool> _enqueueCropSpeciesArchive({
  required WidgetRef ref,
  required FarmlyMutationScope scope,
  required FarmlyOrganizationScope selectedScope,
  required FarmlyCropSpeciesDto species,
}) => _enqueueCropSpeciesMutation(
  ref: ref,
  scope: scope,
  selectedScope: selectedScope,
  species: species,
  buildIntent: (operationId, baseVersion) => FarmlyArchiveCropSpeciesIntent(
    operationId: operationId,
    continuityEpoch: scope.continuityEpoch,
    resourceId: species.id,
    baseVersion: baseVersion,
  ),
);

final _cropSpeciesMutationsInFlight =
    <
      ({
        String accountId,
        String organizationId,
        String? farmId,
        String continuityEpoch,
        String speciesId,
      })
    >{};

Future<bool> _enqueueCropSpeciesMutation({
  required WidgetRef ref,
  required FarmlyMutationScope scope,
  required FarmlyOrganizationScope selectedScope,
  required FarmlyCropSpeciesDto species,
  required FarmlyMutationIntent Function(String operationId, int baseVersion)
  buildIntent,
}) async {
  final mutationKey = (
    accountId: scope.accountId,
    organizationId: scope.organizationId,
    farmId: scope.farmId,
    continuityEpoch: scope.continuityEpoch,
    speciesId: species.id,
  );
  if (!_cropSpeciesMutationsInFlight.add(mutationKey)) return false;

  try {
    final selectedFarm = selectedScope.selectedFarm;
    if (species.version < 1 ||
        species.status != 'active' ||
        selectedFarm == null ||
        !_canManageCropSpecies(selectedScope, selectedFarm) ||
        !_capturedFarmScopeIsCurrent(ref, scope, selectedScope)) {
      return false;
    }

    final session = await ref.read(farmlyAuthSessionProvider.future);
    if (session == null || session.user.id != scope.accountId) return false;
    final engine = await ref.read(syncEngineProvider.future);
    final snapshot = await engine.domainSnapshot(scope);
    if (snapshot == null ||
        snapshot.cursor.continuityEpoch != scope.continuityEpoch ||
        snapshot.cursor.scopePolicyVersion !=
            selectedScope.directory.scopePolicyVersion) {
      return false;
    }
    final matchingRows = <FarmlyCropSpeciesDto>[];
    for (final row in snapshot.recordsFor('cropSpecies').values) {
      if (row is! Map) continue;
      final current = FarmlyCropSpeciesDto.fromJson(
        Map<String, dynamic>.from(row),
      );
      if (current.id == species.id) matchingRows.add(current);
    }
    if (matchingRows.length != 1) return false;
    final confirmedSpecies = matchingRows.single;
    if (confirmedSpecies.status != 'active' ||
        confirmedSpecies.version != species.version) {
      return false;
    }

    final entries = await engine.entries(
      accountId: scope.accountId,
      organizationId: scope.organizationId,
    );
    if (_hasOutstandingCropSpeciesMutation(
      entries,
      scope,
      species.id,
      confirmedSpecies.version,
    )) {
      return false;
    }

    final currentSelection = ref.read(selectedOrganizationScopeProvider);
    final currentScope = ref.read(farmlySyncScopeProvider).asData?.value;
    final currentAccount = ref
        .read(farmlyAuthSessionProvider)
        .asData
        ?.value
        ?.user
        .id;
    final currentFarm = currentSelection?.selectedFarm;
    if (currentAccount != scope.accountId ||
        !_sameSelection(selectedScope, currentSelection) ||
        !_sameFarmScope(scope, currentScope) ||
        currentSelection?.selectedFarmId != scope.farmId ||
        currentFarm == null ||
        !_canManageCropSpecies(currentSelection!, currentFarm)) {
      return false;
    }

    await engine.enqueue(
      FarmlyScopedMutation(
        scope: scope,
        intent: buildIntent(newFarmlyOperationId(), confirmedSpecies.version),
      ),
    );
    return true;
  } finally {
    _cropSpeciesMutationsInFlight.remove(mutationKey);
  }
}

final _zoneNameUpdatesInFlight =
    <
      ({
        String accountId,
        String organizationId,
        String? farmId,
        String continuityEpoch,
        String zoneId,
      })
    >{};

Future<bool> _enqueueZoneNameUpdate({
  required WidgetRef ref,
  required FarmlyMutationScope scope,
  required FarmlyOrganizationScope selectedScope,
  required FarmlyZoneDto zone,
  required String name,
}) async {
  final updateKey = (
    accountId: scope.accountId,
    organizationId: scope.organizationId,
    farmId: scope.farmId,
    continuityEpoch: scope.continuityEpoch,
    zoneId: zone.id,
  );
  if (!_zoneNameUpdatesInFlight.add(updateKey)) return false;

  try {
    final selectedFarm = selectedScope.selectedFarm;
    if (zone.version < 1 ||
        zone.status != 'active' ||
        selectedFarm == null ||
        !_canManageZones(selectedScope, selectedFarm) ||
        !_capturedFarmScopeIsCurrent(ref, scope, selectedScope)) {
      return false;
    }

    final session = await ref.read(farmlyAuthSessionProvider.future);
    if (session == null || session.user.id != scope.accountId) return false;
    final engine = await ref.read(syncEngineProvider.future);
    final snapshot = await engine.domainSnapshot(scope);
    if (snapshot == null ||
        snapshot.cursor.continuityEpoch != scope.continuityEpoch ||
        snapshot.cursor.scopePolicyVersion !=
            selectedScope.directory.scopePolicyVersion) {
      return false;
    }

    List<FarmlyZoneDto> matchingZones(Map<String, Object?> records) {
      final matches = <FarmlyZoneDto>[];
      for (final row in records.values) {
        if (row is! Map) return const [];
        final current = FarmlyZoneDto.fromJson(Map<String, dynamic>.from(row));
        if (current.id == zone.id) matches.add(current);
      }
      return matches;
    }

    final confirmedZones = matchingZones(snapshot.recordsFor('zone'));
    if (confirmedZones.length != 1 ||
        confirmedZones.single.status != 'active' ||
        confirmedZones.single.version != zone.version) {
      return false;
    }
    final entries = await engine.entries(
      accountId: scope.accountId,
      organizationId: scope.organizationId,
    );
    if (_zoneUpdateEntries(
      entries: entries,
      scope: scope,
      zoneId: zone.id,
      confirmedVersion: confirmedZones.single.version,
    ).isNotEmpty) {
      return false;
    }

    final freshSnapshot = await engine.domainSnapshot(scope);
    if (freshSnapshot == null ||
        freshSnapshot.cursor.continuityEpoch != scope.continuityEpoch ||
        freshSnapshot.cursor.scopePolicyVersion !=
            selectedScope.directory.scopePolicyVersion) {
      return false;
    }
    final latestZones = matchingZones(freshSnapshot.recordsFor('zone'));
    if (latestZones.length != 1 ||
        latestZones.single.status != 'active' ||
        latestZones.single.version != confirmedZones.single.version) {
      return false;
    }

    if (!_capturedFarmScopeIsCurrent(ref, scope, selectedScope)) return false;
    await engine.enqueue(
      FarmlyScopedMutation(
        scope: scope,
        intent: FarmlyUpdateZoneNameIntent(
          operationId: newFarmlyOperationId(),
          continuityEpoch: scope.continuityEpoch,
          resourceId: zone.id,
          baseVersion: latestZones.single.version,
          name: name,
        ),
      ),
    );
    return true;
  } finally {
    _zoneNameUpdatesInFlight.remove(updateKey);
  }
}

Future<bool> _enqueueWaterTankNameUpdate({
  required WidgetRef ref,
  required FarmlyMutationScope scope,
  required FarmlyOrganizationScope selectedScope,
  required FarmlyLiveZone zone,
  required FarmlyLiveWaterTank tank,
  required String name,
}) async {
  final selectedFarm = selectedScope.selectedFarm;
  if (tank.tank.version < 1 ||
      tank.tank.status != 'active' ||
      tank.tank.zoneId != zone.zone.id ||
      tank.syncState != FarmlyZoneSyncState.confirmed ||
      tank.hasUnresolvedNameUpdate ||
      !tank.isUniqueConfirmedRecord ||
      zone.zone.type != 'water' ||
      zone.zone.status != 'active' ||
      zone.syncState != FarmlyZoneSyncState.confirmed ||
      selectedFarm == null ||
      !_canManageCropSpecies(selectedScope, selectedFarm) ||
      !_capturedWaterScopeIsCurrent(
        ref,
        scope,
        selectedScope,
        zone,
        tank: tank,
      )) {
    return false;
  }

  final session = await ref.read(farmlyAuthSessionProvider.future);
  if (session == null || session.user.id != scope.accountId) return false;
  final engine = await ref.read(syncEngineProvider.future);
  final snapshot = await engine.domainSnapshot(scope);
  if (snapshot == null ||
      snapshot.cursor.continuityEpoch != scope.continuityEpoch ||
      snapshot.cursor.scopePolicyVersion !=
          selectedScope.directory.scopePolicyVersion) {
    return false;
  }

  final tankRows = snapshot
      .recordsFor('waterTank')
      .entries
      .where((record) {
        final row = record.value;
        return row is Map && row['id'] == tank.tank.id;
      })
      .toList(growable: false);
  if (tankRows.length != 1 || tankRows.single.key != tank.tank.id) {
    return false;
  }
  final confirmedTank = FarmlyWaterTankDto.fromJson(
    Map<String, dynamic>.from(tankRows.single.value as Map),
  );
  if (confirmedTank.status != 'active' ||
      confirmedTank.zoneId != zone.zone.id ||
      confirmedTank.version != tank.tank.version ||
      confirmedTank.name != tank.tank.name) {
    return false;
  }

  final zoneRows = snapshot
      .recordsFor('zone')
      .entries
      .where((record) {
        final row = record.value;
        return row is Map && row['id'] == zone.zone.id;
      })
      .toList(growable: false);
  if (zoneRows.length != 1 || zoneRows.single.key != zone.zone.id) {
    return false;
  }
  final confirmedZone = FarmlyZoneDto.fromJson(
    Map<String, dynamic>.from(zoneRows.single.value as Map),
  );
  if (confirmedZone.type != 'water' ||
      confirmedZone.status != 'active' ||
      confirmedZone.version != zone.zone.version) {
    return false;
  }

  final entries = await engine.entries(
    accountId: scope.accountId,
    organizationId: scope.organizationId,
  );
  if (_hasOutstandingWaterTankUpdate(
    entries,
    scope,
    confirmedTank.id,
    confirmedTank.version,
  )) {
    return false;
  }

  final currentSelection = ref.read(selectedOrganizationScopeProvider);
  final currentScope = ref.read(farmlySyncScopeProvider).asData?.value;
  final currentAccount = ref
      .read(farmlyAuthSessionProvider)
      .asData
      ?.value
      ?.user
      .id;
  final currentFarm = currentSelection?.selectedFarm;
  if (currentAccount != scope.accountId ||
      !_sameSelection(selectedScope, currentSelection) ||
      !_sameFarmScope(scope, currentScope) ||
      currentSelection?.selectedFarmId != scope.farmId ||
      currentFarm == null ||
      !_canManageCropSpecies(currentSelection!, currentFarm) ||
      !_capturedWaterScopeIsCurrent(
        ref,
        scope,
        selectedScope,
        zone,
        tank: tank,
      )) {
    return false;
  }

  await engine.enqueue(
    FarmlyScopedMutation(
      scope: scope,
      intent: FarmlyUpdateWaterTankNameIntent(
        operationId: newFarmlyOperationId(),
        continuityEpoch: scope.continuityEpoch,
        resourceId: confirmedTank.id,
        baseVersion: confirmedTank.version,
        name: name,
      ),
    ),
  );
  return true;
}

bool _capturedPlantingIsCurrent({
  required WidgetRef ref,
  required FarmlyMutationScope scope,
  required FarmlyOrganizationScope selectedScope,
  required FarmlyLiveZone zone,
  required FarmlyLivePlanting planting,
}) {
  final collection = ref.read(farmlyLiveZoneCollectionProvider).asData?.value;
  final matchingZones = (collection?.zones ?? const <FarmlyLiveZone>[])
      .where((item) => item.zone.id == zone.zone.id)
      .toList(growable: false);
  final matchingPlantings =
      (collection?.plantings ?? const <FarmlyLivePlanting>[])
          .where((item) => item.planting.id == planting.planting.id)
          .toList(growable: false);
  final currentZone = matchingZones.length == 1 ? matchingZones.single : null;
  final currentPlanting = matchingPlantings.length == 1
      ? matchingPlantings.single
      : null;
  final selectedFarm = selectedScope.selectedFarm;
  final cacheIsWritable =
      collection?.cacheState == FarmlyZoneCacheState.ready ||
      collection?.cacheState == FarmlyZoneCacheState.notBootstrapped;

  return collection?.scope != null &&
      _sameFarmScope(scope, collection!.scope) &&
      collection.canCreate &&
      cacheIsWritable &&
      selectedFarm != null &&
      _canManageCropSpecies(selectedScope, selectedFarm) &&
      _capturedFarmScopeIsCurrent(ref, scope, selectedScope) &&
      currentZone != null &&
      currentZone.zone.id == zone.zone.id &&
      currentZone.zone.type == 'crop_plot' &&
      currentZone.zone.status == 'active' &&
      currentZone.zone.version == zone.zone.version &&
      currentZone.syncState == FarmlyZoneSyncState.confirmed &&
      zone.zone.type == 'crop_plot' &&
      zone.zone.status == 'active' &&
      zone.syncState == FarmlyZoneSyncState.confirmed &&
      currentPlanting != null &&
      currentPlanting.syncState == FarmlyZoneSyncState.confirmed &&
      currentPlanting.isUniqueConfirmedRecord &&
      planting.isUniqueConfirmedRecord &&
      !currentPlanting.hasUnresolvedUpdate &&
      !currentPlanting.hasUnresolvedArchive &&
      currentPlanting.planting.status != 'archived' &&
      currentPlanting.planting.id == planting.planting.id &&
      currentPlanting.planting.version == planting.planting.version &&
      currentPlanting.planting.cropSpeciesId ==
          planting.planting.cropSpeciesId &&
      currentPlanting.planting.plotId == planting.planting.plotId &&
      currentPlanting.planting.status == planting.planting.status &&
      currentPlanting.planting.sowingDate == planting.planting.sowingDate &&
      currentPlanting.planting.expectedHarvestDate ==
          planting.planting.expectedHarvestDate &&
      currentPlanting.planting.areaM2?.value == planting.planting.areaM2?.value;
}

Future<bool> _withPlantingMutationLock({
  required FarmlyMutationScope scope,
  required String plantingId,
  required Future<bool> Function() action,
}) async {
  final key = [
    scope.accountId,
    scope.organizationId,
    scope.farmId,
    scope.continuityEpoch,
    plantingId,
  ].join('|');
  if (!_inFlightPlantingMutationKeys.add(key)) return false;
  try {
    return await action();
  } finally {
    _inFlightPlantingMutationKeys.remove(key);
  }
}

Future<bool> _enqueuePlantingUpdate({
  required WidgetRef ref,
  required FarmlyMutationScope scope,
  required FarmlyOrganizationScope selectedScope,
  required FarmlyLiveZone zone,
  required FarmlyLivePlanting planting,
  String? status,
  String? sowingDate,
  String? expectedHarvestDate,
  String? areaM2,
}) => _withPlantingMutationLock(
  scope: scope,
  plantingId: planting.planting.id,
  action: () => _enqueuePlantingMutation(
    ref: ref,
    scope: scope,
    selectedScope: selectedScope,
    zone: zone,
    planting: planting,
    archive: false,
    status: status,
    sowingDate: sowingDate,
    expectedHarvestDate: expectedHarvestDate,
    areaM2: areaM2,
  ),
);

Future<bool> _enqueuePlantingArchive({
  required WidgetRef ref,
  required FarmlyMutationScope scope,
  required FarmlyOrganizationScope selectedScope,
  required FarmlyLiveZone zone,
  required FarmlyLivePlanting planting,
}) => _withPlantingMutationLock(
  scope: scope,
  plantingId: planting.planting.id,
  action: () => _enqueuePlantingMutation(
    ref: ref,
    scope: scope,
    selectedScope: selectedScope,
    zone: zone,
    planting: planting,
    archive: true,
  ),
);

Future<bool> _enqueuePlantingMutation({
  required WidgetRef ref,
  required FarmlyMutationScope scope,
  required FarmlyOrganizationScope selectedScope,
  required FarmlyLiveZone zone,
  required FarmlyLivePlanting planting,
  required bool archive,
  String? status,
  String? sowingDate,
  String? expectedHarvestDate,
  String? areaM2,
}) async {
  final selectedFarm = selectedScope.selectedFarm;
  if (planting.planting.version < 1 ||
      planting.planting.status == 'archived' ||
      planting.syncState != FarmlyZoneSyncState.confirmed ||
      !planting.isUniqueConfirmedRecord ||
      planting.hasUnresolvedUpdate ||
      planting.hasUnresolvedArchive ||
      planting.planting.plotId != zone.zone.id ||
      selectedFarm == null ||
      !_canManageCropSpecies(selectedScope, selectedFarm) ||
      !_capturedPlantingIsCurrent(
        ref: ref,
        scope: scope,
        selectedScope: selectedScope,
        zone: zone,
        planting: planting,
      )) {
    return false;
  }

  final session = await ref.read(farmlyAuthSessionProvider.future);
  if (session == null || session.user.id != scope.accountId) return false;
  final engine = await ref.read(syncEngineProvider.future);
  final snapshot = await engine.domainSnapshot(scope);
  if (snapshot == null ||
      snapshot.cursor.continuityEpoch != scope.continuityEpoch ||
      snapshot.cursor.scopePolicyVersion !=
          selectedScope.directory.scopePolicyVersion) {
    return false;
  }

  final plantingRows = snapshot
      .recordsFor('planting')
      .entries
      .where((record) {
        final row = record.value;
        return row is Map && row['id'] == planting.planting.id;
      })
      .toList(growable: false);
  if (plantingRows.length != 1 ||
      plantingRows.single.key != planting.planting.id) {
    return false;
  }
  final confirmedPlanting = FarmlyPlantingDto.fromJson(
    Map<String, dynamic>.from(plantingRows.single.value as Map),
  );
  if (confirmedPlanting.version != planting.planting.version ||
      confirmedPlanting.cropSpeciesId != planting.planting.cropSpeciesId ||
      confirmedPlanting.plotId != zone.zone.id ||
      confirmedPlanting.status == 'archived' ||
      confirmedPlanting.status != planting.planting.status ||
      confirmedPlanting.sowingDate != planting.planting.sowingDate ||
      confirmedPlanting.expectedHarvestDate !=
          planting.planting.expectedHarvestDate ||
      confirmedPlanting.areaM2?.value != planting.planting.areaM2?.value) {
    return false;
  }

  final zoneRows = snapshot
      .recordsFor('zone')
      .entries
      .where((record) {
        final row = record.value;
        return row is Map && row['id'] == zone.zone.id;
      })
      .toList(growable: false);
  if (zoneRows.length != 1 || zoneRows.single.key != zone.zone.id) {
    return false;
  }
  final confirmedZone = FarmlyZoneDto.fromJson(
    Map<String, dynamic>.from(zoneRows.single.value as Map),
  );
  if (confirmedZone.type != 'crop_plot' ||
      confirmedZone.status != 'active' ||
      confirmedZone.version != zone.zone.version) {
    return false;
  }

  final effectiveSowingDate = sowingDate ?? confirmedPlanting.sowingDate;
  final effectiveExpectedHarvestDate =
      expectedHarvestDate ?? confirmedPlanting.expectedHarvestDate;
  if (!archive &&
      (!_isValidCivilDate(effectiveSowingDate) ||
          (effectiveExpectedHarvestDate != null &&
              (!_isValidCivilDate(effectiveExpectedHarvestDate) ||
                  effectiveExpectedHarvestDate.compareTo(effectiveSowingDate) <
                      0)))) {
    return false;
  }

  final entries = await engine.entries(
    accountId: scope.accountId,
    organizationId: scope.organizationId,
  );
  if (_hasOutstandingPlantingMutation(
    entries,
    scope,
    confirmedPlanting.id,
    confirmedPlanting.version,
  )) {
    return false;
  }

  final currentSelection = ref.read(selectedOrganizationScopeProvider);
  final currentScope = ref.read(farmlySyncScopeProvider).asData?.value;
  final currentAccount = ref
      .read(farmlyAuthSessionProvider)
      .asData
      ?.value
      ?.user
      .id;
  final currentFarm = currentSelection?.selectedFarm;
  if (currentAccount != scope.accountId ||
      !_sameSelection(selectedScope, currentSelection) ||
      !_sameFarmScope(scope, currentScope) ||
      currentSelection?.selectedFarmId != scope.farmId ||
      currentFarm == null ||
      !_canManageCropSpecies(currentSelection!, currentFarm) ||
      !_capturedPlantingIsCurrent(
        ref: ref,
        scope: scope,
        selectedScope: selectedScope,
        zone: zone,
        planting: planting,
      )) {
    return false;
  }

  final intent = archive
      ? FarmlyArchivePlantingIntent(
          operationId: newFarmlyOperationId(),
          continuityEpoch: scope.continuityEpoch,
          resourceId: confirmedPlanting.id,
          baseVersion: confirmedPlanting.version,
        )
      : FarmlyUpdatePlantingIntent(
          operationId: newFarmlyOperationId(),
          continuityEpoch: scope.continuityEpoch,
          resourceId: confirmedPlanting.id,
          baseVersion: confirmedPlanting.version,
          status: status,
          sowingDate: sowingDate,
          expectedHarvestDate: expectedHarvestDate,
          areaM2: areaM2,
        );
  await engine.enqueue(FarmlyScopedMutation(scope: scope, intent: intent));
  return true;
}

bool _canManageZones(
  FarmlyOrganizationScope organizationScope,
  FarmlyDirectoryFarm farm,
) {
  if (organizationScope.organization.status !=
          FarmlyOrganizationStatus.active ||
      organizationScope.organization.role == FarmlyOrganizationRole.viewer) {
    return false;
  }
  if (organizationScope.organization.role == FarmlyOrganizationRole.owner ||
      organizationScope.organization.role == FarmlyOrganizationRole.admin) {
    return true;
  }
  return farm.grantRole == FarmlyFarmGrantRole.owner ||
      farm.grantRole == FarmlyFarmGrantRole.admin ||
      farm.grantRole == FarmlyFarmGrantRole.manager;
}

bool _canEditFarmName(
  FarmlyOrganizationScope organizationScope,
  FarmlyDirectoryFarm farm,
) =>
    organizationScope.organization.status == FarmlyOrganizationStatus.active &&
    farm.status == FarmlyFarmStatus.active &&
    (organizationScope.organization.role == FarmlyOrganizationRole.owner ||
        organizationScope.organization.role == FarmlyOrganizationRole.admin);

bool _canRecordHarvest(
  FarmlyOrganizationScope organizationScope,
  FarmlyDirectoryFarm farm,
) {
  if (organizationScope.organization.status !=
          FarmlyOrganizationStatus.active ||
      organizationScope.organization.role == FarmlyOrganizationRole.viewer ||
      farm.status != FarmlyFarmStatus.active) {
    return false;
  }
  if (organizationScope.organization.role == FarmlyOrganizationRole.owner ||
      organizationScope.organization.role == FarmlyOrganizationRole.admin) {
    return true;
  }
  return farm.grantRole != FarmlyFarmGrantRole.viewer;
}

bool canRecordLiveHarvest(
  FarmlyOrganizationScope organizationScope,
  FarmlyDirectoryFarm farm,
) => _canRecordHarvest(organizationScope, farm);

bool canManageLiveFarmZones(
  FarmlyOrganizationScope organizationScope,
  FarmlyDirectoryFarm farm,
) => _canManageZones(organizationScope, farm);

bool _entryMatchesScope(OutboxEntry entry, FarmlyMutationScope scope) {
  final entryScope = entry.mutation.scope;
  final intent = entry.mutation.intent;
  return entryScope.kind == FarmlyMutationScopeKind.farm &&
      entryScope.accountId == scope.accountId &&
      entryScope.organizationId == scope.organizationId &&
      entryScope.farmId == scope.farmId &&
      entryScope.continuityEpoch == scope.continuityEpoch &&
      intent.continuityEpoch == scope.continuityEpoch;
}

FarmlyZoneSyncState _syncStateForEntry(OutboxEntry entry) =>
    switch (entry.status) {
      OutboxEntryStatus.pending => FarmlyZoneSyncState.savedOnDevice,
      OutboxEntryStatus.inFlight => FarmlyZoneSyncState.checkingServer,
      OutboxEntryStatus.applied => FarmlyZoneSyncState.awaitingProjection,
      OutboxEntryStatus.blocked ||
      OutboxEntryStatus.conflict ||
      OutboxEntryStatus.rejected => FarmlyZoneSyncState.needsAttention,
    };

List<FarmlyLiveZone> _pendingZoneEntries(
  List<OutboxEntry> entries,
  FarmlyMutationScope scope,
) {
  final pending = <FarmlyLiveZone>[];
  for (final entry in entries) {
    final intent = entry.mutation.intent;
    if (intent.type != 'zone.create' || !_entryMatchesScope(entry, scope)) {
      continue;
    }
    final payload = <String, dynamic>{
      ...intent.payload,
      'id': intent.resourceId,
      'version': 0,
      'status': 'active',
    };
    pending.add(
      FarmlyLiveZone(
        zone: FarmlyZoneDto.fromJson(payload),
        syncState: _syncStateForEntry(entry),
        operationId: entry.operationId,
      ),
    );
  }
  return pending;
}

List<FarmlyLiveCropSpecies> _pendingCropSpeciesEntries(
  List<OutboxEntry> entries,
  FarmlyMutationScope scope,
) {
  final pending = <FarmlyLiveCropSpecies>[];
  for (final entry in entries) {
    final intent = entry.mutation.intent;
    if (intent.type != 'cropSpecies.create' ||
        !_entryMatchesScope(entry, scope)) {
      continue;
    }
    final species = FarmlyCropSpeciesDto.fromJson({
      ...intent.payload,
      'id': intent.resourceId,
      'version': 0,
      'status': 'active',
    });
    pending.add(
      FarmlyLiveCropSpecies(
        species: species,
        syncState: _syncStateForEntry(entry),
        operationId: entry.operationId,
      ),
    );
  }
  return pending;
}

void _projectCropSpeciesMutations(
  Map<String, FarmlyLiveCropSpecies> species,
  List<OutboxEntry> entries,
  FarmlyMutationScope scope,
) {
  for (final current in species.values.toList(growable: false)) {
    if (current.syncState != FarmlyZoneSyncState.confirmed ||
        current.species.version < 1 ||
        current.species.status != 'active') {
      continue;
    }
    final updates = entries
        .where((entry) {
          final intent = entry.mutation.intent;
          return _entryMatchesScope(entry, scope) &&
              (intent.type == 'cropSpecies.update' ||
                  intent.type == 'cropSpecies.archive') &&
              intent.resourceId == current.species.id &&
              entry.status != OutboxEntryStatus.rejected;
        })
        .where((entry) {
          final intent = entry.mutation.intent;
          return !(entry.status == OutboxEntryStatus.applied &&
              intent.baseVersion != null &&
              current.species.version > intent.baseVersion!);
        })
        .toList(growable: false);

    if (updates.isEmpty) continue;
    if (updates.length != 1) {
      species[current.species.id] = FarmlyLiveCropSpecies(
        species: current.species,
        syncState: FarmlyZoneSyncState.needsAttention,
        hasUnresolvedUpdate: true,
      );
      continue;
    }

    final entry = updates.single;
    final intent = entry.mutation.intent;
    final canProject =
        intent.baseVersion == current.species.version &&
        entry.status != OutboxEntryStatus.blocked &&
        entry.status != OutboxEntryStatus.conflict;
    if (!canProject) {
      species[current.species.id] = FarmlyLiveCropSpecies(
        species: current.species,
        syncState: FarmlyZoneSyncState.needsAttention,
        hasUnresolvedUpdate: true,
        operationId: entry.operationId,
      );
      continue;
    }

    if (intent.type == 'cropSpecies.archive') {
      if (intent.payload.isNotEmpty) {
        species[current.species.id] = FarmlyLiveCropSpecies(
          species: current.species,
          syncState: FarmlyZoneSyncState.needsAttention,
          hasUnresolvedUpdate: true,
          operationId: entry.operationId,
        );
        continue;
      }
      species[current.species.id] = FarmlyLiveCropSpecies(
        species: FarmlyCropSpeciesDto(
          id: current.species.id,
          version: current.species.version,
          name: current.species.name,
          harvestUnit: current.species.harvestUnit,
          status: 'archived',
        ),
        syncState: _syncStateForEntry(entry),
        operationId: entry.operationId,
        hasUnresolvedUpdate: true,
      );
      continue;
    }

    if (intent.type != 'cropSpecies.update') {
      species[current.species.id] = FarmlyLiveCropSpecies(
        species: current.species,
        syncState: FarmlyZoneSyncState.needsAttention,
        hasUnresolvedUpdate: true,
        operationId: entry.operationId,
      );
      continue;
    }

    final name = intent.payload['name'];
    final harvestUnit = intent.payload['harvestUnit'];
    final nameIsValid =
        !intent.payload.containsKey('name') ||
        (name is String &&
            name.isNotEmpty &&
            name == name.trim() &&
            name.length <= 160);
    final unitIsValid =
        !intent.payload.containsKey('harvestUnit') ||
        (harvestUnit is String &&
            const {'kg', 'litre', 'pieces'}.contains(harvestUnit));
    final canProjectUpdate =
        (intent.payload.containsKey('name') ||
            intent.payload.containsKey('harvestUnit')) &&
        nameIsValid &&
        unitIsValid;
    if (!canProjectUpdate) {
      species[current.species.id] = FarmlyLiveCropSpecies(
        species: current.species,
        syncState: FarmlyZoneSyncState.needsAttention,
        hasUnresolvedUpdate: true,
        operationId: entry.operationId,
      );
      continue;
    }

    species[current.species.id] = FarmlyLiveCropSpecies(
      species: FarmlyCropSpeciesDto(
        id: current.species.id,
        version: current.species.version,
        name: name as String? ?? current.species.name,
        harvestUnit: harvestUnit as String? ?? current.species.harvestUnit,
        status: current.species.status,
      ),
      syncState: _syncStateForEntry(entry),
      operationId: entry.operationId,
      hasUnresolvedUpdate: true,
    );
  }
}

List<FarmlyLivePlanting> _pendingPlantingEntries(
  List<OutboxEntry> entries,
  FarmlyMutationScope scope,
) {
  final pending = <FarmlyLivePlanting>[];
  for (final entry in entries) {
    final intent = entry.mutation.intent;
    if (intent.type != 'planting.create' || !_entryMatchesScope(entry, scope)) {
      continue;
    }
    final planting = FarmlyPlantingDto.fromJson({
      ...intent.payload,
      'id': intent.resourceId,
      'version': 0,
      'status': intent.payload['status'] ?? 'planned',
    });
    pending.add(
      FarmlyLivePlanting(
        planting: planting,
        syncState: _syncStateForEntry(entry),
        operationId: entry.operationId,
      ),
    );
  }
  return pending;
}

List<FarmlyLivePlanting> _withPlantingEvents(
  List<FarmlyLivePlanting> plantings,
  Map<String, Object?> eventRecords,
  List<OutboxEntry> entries,
  FarmlyMutationScope scope,
) {
  final eventsById = <String, FarmlyLivePlantingEvent>{};
  for (final row in eventRecords.values) {
    if (row is! Map) {
      throw const FormatException('Invalid local planting event record');
    }
    final json = Map<String, dynamic>.from(row);
    final id = json['id'] as String;
    final plantingId = json['plantingId'] as String;
    final eventType = (json['eventType'] as String).trim();
    if (eventType.isEmpty || eventType.length > 40) {
      throw const FormatException('Invalid local planting event type');
    }
    final note = json['note'] as String?;
    if (note != null && (note.trim().isEmpty || note.length > 500)) {
      throw const FormatException('Invalid local planting event note');
    }
    final occurredOn = json['occurredOn'] as String?;
    if (occurredOn != null && !_isValidCivilDate(occurredOn)) {
      throw const FormatException('Invalid local planting event date');
    }
    eventsById[id] = FarmlyLivePlantingEvent(
      id: id,
      plantingId: plantingId,
      eventType: eventType,
      note: note,
      occurredOn: occurredOn,
      syncState: FarmlyZoneSyncState.confirmed,
    );
  }

  for (final entry in entries) {
    final intent = entry.mutation.intent;
    if (intent.type != 'plantingEvent.create' ||
        !_entryMatchesScope(entry, scope) ||
        eventsById.containsKey(intent.resourceId)) {
      continue;
    }
    final payload = intent.payload;
    final plantingId = payload['plantingId'] as String;
    final eventType = (payload['eventType'] as String).trim();
    final note = payload['note'] as String?;
    final occurredOn = payload['occurredOn'] as String?;
    eventsById[intent.resourceId] = FarmlyLivePlantingEvent(
      id: intent.resourceId,
      plantingId: plantingId,
      eventType: eventType,
      note: note,
      occurredOn: occurredOn,
      syncState: _syncStateForEntry(entry),
      operationId: entry.operationId,
    );
  }

  final eventsByPlanting = <String, List<FarmlyLivePlantingEvent>>{};
  for (final event in eventsById.values) {
    eventsByPlanting.putIfAbsent(event.plantingId, () => []).add(event);
  }
  return [
    for (final item in plantings)
      FarmlyLivePlanting(
        planting: item.planting,
        syncState: item.syncState,
        operationId: item.operationId,
        hasUnresolvedUpdate: item.hasUnresolvedUpdate,
        hasUnresolvedArchive: item.hasUnresolvedArchive,
        isUniqueConfirmedRecord: item.isUniqueConfirmedRecord,
        events: List.unmodifiable(
          eventsByPlanting[item.planting.id] ?? const [],
        ),
      ),
  ];
}

List<FarmlyLiveHarvest> _pendingHarvestEntries(
  List<OutboxEntry> entries,
  FarmlyMutationScope scope,
) {
  final pending = <FarmlyLiveHarvest>[];
  for (final entry in entries) {
    final intent = entry.mutation.intent;
    if (intent.type != 'harvest.create' || !_entryMatchesScope(entry, scope)) {
      continue;
    }
    final payload = intent.payload;
    pending.add(
      FarmlyLiveHarvest(
        id: intent.resourceId,
        version: 0,
        plantingId: payload['plantingId'] as String,
        quantityKg: FarmlyDecimal.parse(payload['quantityKg'] as String),
        harvestDate: payload['harvestDate'] as String,
        status: 'active',
        syncState: _syncStateForEntry(entry),
        operationId: entry.operationId,
      ),
    );
  }
  return pending;
}

FarmlyZoneSyncState? _pendingHarvestManagerMutationState(
  List<OutboxEntry> entries,
  FarmlyMutationScope scope,
  String harvestId, {
  required int headVersion,
  required String headStatus,
}) {
  final mutations = entries
      .where((entry) {
        final intent = entry.mutation.intent;
        if (!_entryMatchesScope(entry, scope) ||
            intent.resourceId != harvestId ||
            (intent.type != 'harvest.correction.apply' &&
                intent.type != 'harvest.void')) {
          return false;
        }
        if (entry.status == OutboxEntryStatus.applied) {
          final baseVersion = intent.baseVersion;
          if (baseVersion != null && headVersion > baseVersion) {
            if (intent.type != 'harvest.void' || headStatus == 'voided') {
              return false;
            }
          }
        }
        return true;
      })
      .toList(growable: false);
  if (mutations.isEmpty) return null;
  if (mutations.length > 1) return FarmlyZoneSyncState.needsAttention;
  return _syncStateForEntry(mutations.single);
}

List<FarmlyLiveWaterTank> _pendingWaterTankEntries(
  List<OutboxEntry> entries,
  FarmlyMutationScope scope,
) {
  final pending = <FarmlyLiveWaterTank>[];
  for (final entry in entries) {
    final intent = entry.mutation.intent;
    if (intent.type != 'waterTank.create' ||
        !_entryMatchesScope(entry, scope)) {
      continue;
    }
    final tank = FarmlyWaterTankDto.fromJson({
      ...intent.payload,
      'id': intent.resourceId,
      'version': 0,
      'storedLitres': null,
      'status': 'active',
    });
    pending.add(
      FarmlyLiveWaterTank(
        tank: tank,
        syncState: _syncStateForEntry(entry),
        operationId: entry.operationId,
      ),
    );
  }
  return pending;
}

List<FarmlyLiveWaterReading> _pendingWaterReadingEntries(
  List<OutboxEntry> entries,
  FarmlyMutationScope scope,
) {
  final pending = <FarmlyLiveWaterReading>[];
  for (final entry in entries) {
    final intent = entry.mutation.intent;
    if (intent.type != 'waterReading.create' ||
        !_entryMatchesScope(entry, scope)) {
      continue;
    }
    final payload = intent.payload;
    pending.add(
      FarmlyLiveWaterReading(
        id: intent.resourceId,
        tankId: payload['tankId'] as String,
        storedLitres: FarmlyDecimal.parse(payload['storedLitres'] as String),
        source: payload['source'] as String,
        measuredAt: payload['measuredAt'] as String?,
        syncState: _syncStateForEntry(entry),
        operationId: entry.operationId,
      ),
    );
  }
  return pending;
}

FarmlyLiveMoistureReading _farmlyLiveMoistureReadingFromJson(
  Map<String, dynamic> json, {
  required FarmlyZoneSyncState syncState,
  String? operationId,
}) {
  final id = json['id'];
  final zoneId = json['zoneId'];
  final value = json['value'];
  final method = json['method'];
  final source = json['source'];
  final measuredAt = json['measuredAt'];
  if (id is! String ||
      !_isFarmlyUuid(id) ||
      zoneId is! String ||
      value is! String ||
      method is! String ||
      source != 'manual' ||
      measuredAt is! String) {
    throw const FormatException('Invalid local moisture reading fields');
  }
  FarmlyCreateMoistureReadingIntent.validatePayload(
    zoneId: zoneId,
    value: value,
    method: method,
    measuredAt: measuredAt,
  );
  return FarmlyLiveMoistureReading(
    id: id,
    zoneId: zoneId,
    value: FarmlyDecimal.parse(value),
    method: method,
    source: source,
    measuredAt: measuredAt,
    syncState: syncState,
    operationId: operationId,
  );
}

List<FarmlyLiveMoistureReading> _pendingMoistureReadingEntries(
  List<OutboxEntry> entries,
  FarmlyMutationScope scope,
) {
  final pending = <FarmlyLiveMoistureReading>[];
  for (final entry in entries) {
    final intent = entry.mutation.intent;
    if (intent.type != 'moistureReading.create' ||
        !_entryMatchesScope(entry, scope)) {
      continue;
    }
    pending.add(
      _farmlyLiveMoistureReadingFromJson(
        {'id': intent.resourceId, ...intent.payload, 'source': 'manual'},
        syncState: _syncStateForEntry(entry),
        operationId: entry.operationId,
      ),
    );
  }
  return pending;
}

bool _isFarmlyUuid(String value) => RegExp(
  r'^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$',
  caseSensitive: false,
).hasMatch(value);

List<FarmlyLiveMoistureReading> _latestMoistureReadingsForZone(
  List<FarmlyLiveMoistureReading> readings,
  String zoneId,
) {
  final latestByMethod = <String, FarmlyLiveMoistureReading>{};
  for (final reading in readings.where((item) => item.zoneId == zoneId)) {
    final latest = latestByMethod[reading.method];
    if (latest == null ||
        DateTime.parse(
          reading.measuredAt,
        ).isAfter(DateTime.parse(latest.measuredAt))) {
      latestByMethod[reading.method] = reading;
    }
  }
  final latest = latestByMethod.values.toList(growable: false)
    ..sort(
      (a, b) =>
          DateTime.parse(b.measuredAt).compareTo(DateTime.parse(a.measuredAt)),
    );
  return latest;
}

List<FarmlyLiveWaterUsage> _pendingWaterUsageEntries(
  List<OutboxEntry> entries,
  FarmlyMutationScope scope,
) {
  final pending = <FarmlyLiveWaterUsage>[];
  for (final entry in entries) {
    final intent = entry.mutation.intent;
    if (intent.type != 'waterUsage.create' ||
        !_entryMatchesScope(entry, scope)) {
      continue;
    }
    final payload = intent.payload;
    pending.add(
      FarmlyLiveWaterUsage(
        id: intent.resourceId,
        tankId: payload['tankId'] as String,
        usageLitres: FarmlyDecimal.parse(payload['usageLitres'] as String),
        usageDate: payload['usageDate'] as String,
        note: payload['note'] as String?,
        syncState: _syncStateForEntry(entry),
        operationId: entry.operationId,
      ),
    );
  }
  return pending;
}

List<FarmlyLiveTaskTemplate> _pendingTaskTemplateEntries(
  List<OutboxEntry> entries,
  FarmlyMutationScope scope,
) {
  final pending = <FarmlyLiveTaskTemplate>[];
  for (final entry in entries) {
    final intent = entry.mutation.intent;
    if (intent.type != 'taskTemplate.create' ||
        !_entryMatchesScope(entry, scope)) {
      continue;
    }
    pending.add(
      _farmlyLiveTaskTemplateFromJson(
        {
          ...intent.payload,
          'id': intent.resourceId,
          'version': 0,
          'status': 'active',
        },
        syncState: _syncStateForEntry(entry),
        operationId: entry.operationId,
      ),
    );
  }
  return pending;
}

void _projectTaskTemplateScheduleUpdates(
  Map<String, FarmlyLiveTaskTemplate> templates,
  List<OutboxEntry> entries,
  FarmlyMutationScope scope,
) {
  final updatesByTemplate = <String, List<OutboxEntry>>{};
  for (final entry in entries) {
    final intent = entry.mutation.intent;
    if (intent.type != 'taskTemplate.update' ||
        !_entryMatchesScope(entry, scope) ||
        !templates.containsKey(intent.resourceId)) {
      continue;
    }
    updatesByTemplate.putIfAbsent(intent.resourceId, () => []).add(entry);
  }

  for (final item in updatesByTemplate.entries) {
    final template = templates[item.key]!;
    if (item.value.length != 1) {
      templates[item.key] = template.copyWith(
        syncState: FarmlyZoneSyncState.needsAttention,
      );
      continue;
    }
    final entry = item.value.single;
    final intent = entry.mutation.intent;
    final baseVersion = intent.baseVersion;
    if (entry.status == OutboxEntryStatus.applied &&
        baseVersion != null &&
        template.version > baseVersion) {
      continue;
    }
    if (baseVersion == null || template.version != baseVersion) {
      templates[item.key] = template.copyWith(
        syncState: FarmlyZoneSyncState.needsAttention,
        operationId: entry.operationId,
      );
      continue;
    }
    final syncState = _syncStateForEntry(entry);
    if (syncState == FarmlyZoneSyncState.needsAttention) {
      templates[item.key] = template.copyWith(
        syncState: syncState,
        operationId: entry.operationId,
      );
      continue;
    }

    final payload = intent.payload;
    final recurrenceValue = payload['recurrence'];
    if (payload.keys.length != 1 || recurrenceValue is! Map) {
      templates[item.key] = template.copyWith(
        syncState: FarmlyZoneSyncState.needsAttention,
        operationId: entry.operationId,
      );
      continue;
    }
    final recurrence = Map<String, dynamic>.from(recurrenceValue);
    final frequency = recurrence['freq'];
    final timeOfDay = recurrence['timeOfDay'];
    final daysValue = recurrence['daysOfWeek'];
    final days = <int>[];
    var validRecurrence =
        recurrence.keys.every(
          (key) => const {'freq', 'timeOfDay', 'daysOfWeek'}.contains(key),
        ) &&
        (frequency == 'daily' || frequency == 'weekly') &&
        timeOfDay is String &&
        RegExp(r'^([01][0-9]|2[0-3]):[0-5][0-9]$').hasMatch(timeOfDay);
    if (recurrence.containsKey('daysOfWeek')) {
      if (frequency != 'weekly' ||
          daysValue is! List ||
          daysValue.isEmpty ||
          daysValue.length > 7) {
        validRecurrence = false;
      } else {
        for (final day in daysValue) {
          if (day is! int || day < 0 || day > 6) {
            validRecurrence = false;
          } else {
            days.add(day);
          }
        }
      }
    } else if (frequency == 'weekly') {
      validRecurrence = false;
    }
    final startsOn = template.startsOn;
    final dateWindowValid =
        startsOn != null &&
        farmlyTaskScheduleIncludesDate(
          frequency: 'daily',
          daysOfWeek: const [],
          startsOn: startsOn,
          endsOn: template.endsOn,
          occurrenceDate: startsOn,
        );
    templates[item.key] = template.copyWith(
      frequency: frequency is String ? frequency : template.frequency,
      timeOfDay: timeOfDay is String ? timeOfDay : template.timeOfDay,
      daysOfWeek: days,
      scheduleValid: validRecurrence && dateWindowValid,
      syncState: syncState,
      operationId: entry.operationId,
    );
  }
}

FarmlyLiveTaskTemplate _farmlyLiveTaskTemplateFromJson(
  Map<String, dynamic> json, {
  required FarmlyZoneSyncState syncState,
  String? operationId,
}) {
  final id = json['id'];
  final version = json['version'];
  final title = json['title'];
  final kind = json['kind'] ?? 'general';
  final zoneId = json['zoneId'];
  final assigneeMembershipId = json['assigneeMembershipId'];
  final startsOnValue = json['startsOn'];
  final endsOnValue = json['endsOn'];
  final status = json['status'];
  final recurrenceValue = json['recurrence'];
  if (id is! String ||
      version is! int ||
      version < 0 ||
      title is! String ||
      kind is! String ||
      (zoneId != null && zoneId is! String) ||
      (assigneeMembershipId != null && assigneeMembershipId is! String) ||
      (status != 'active' && status != 'archived') ||
      recurrenceValue is! Map) {
    throw const FormatException('Invalid local task template fields');
  }
  final canonicalTitle = title.trim();
  if (canonicalTitle.isEmpty || canonicalTitle.runes.length > 160) {
    throw const FormatException('Invalid local task template title');
  }
  if (!const {'general', 'feeding', 'irrigation'}.contains(kind)) {
    throw const FormatException('Invalid local task template kind');
  }
  if (assigneeMembershipId is String &&
      !RegExp(
        r'^[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-4[0-9a-fA-F]{3}-[89abAB][0-9a-fA-F]{3}-[0-9a-fA-F]{12}$',
      ).hasMatch(assigneeMembershipId)) {
    throw const FormatException('Invalid local task assignee');
  }
  final recurrence = Map<String, dynamic>.from(recurrenceValue);
  if (recurrence.keys.any(
    (key) => !const {'freq', 'timeOfDay', 'daysOfWeek'}.contains(key),
  )) {
    throw const FormatException('Invalid local task template recurrence');
  }
  final frequency = recurrence['freq'];
  final timeOfDay = recurrence['timeOfDay'];
  final daysValue = recurrence['daysOfWeek'];
  if ((frequency != 'daily' && frequency != 'weekly') ||
      timeOfDay is! String ||
      !RegExp(r'^([01][0-9]|2[0-3]):[0-5][0-9]$').hasMatch(timeOfDay)) {
    throw const FormatException('Invalid local task template recurrence');
  }
  final daysOfWeek = <int>[];
  var weekdaysValid = true;
  if (recurrence.containsKey('daysOfWeek')) {
    if (frequency != 'weekly') {
      weekdaysValid = false;
    } else if (daysValue is! List ||
        daysValue.isEmpty ||
        daysValue.length > 7) {
      weekdaysValid = false;
    } else {
      for (final day in daysValue) {
        if (day is! int || day < 0 || day > 6) {
          weekdaysValid = false;
        } else {
          daysOfWeek.add(day);
        }
      }
    }
  } else if (frequency == 'weekly') {
    weekdaysValid = false;
  }
  final startsOn = startsOnValue is String ? startsOnValue : null;
  final endsOn = endsOnValue is String ? endsOnValue : null;
  final dateWindowValid =
      startsOn != null &&
      (endsOnValue == null || endsOnValue is String) &&
      farmlyTaskScheduleIncludesDate(
        frequency: 'daily',
        daysOfWeek: const [],
        startsOn: startsOn,
        endsOn: endsOn,
        occurrenceDate: startsOn,
      );
  return FarmlyLiveTaskTemplate(
    id: id,
    version: version,
    title: canonicalTitle,
    kind: kind,
    zoneId: zoneId as String?,
    frequency: frequency as String,
    timeOfDay: timeOfDay,
    daysOfWeek: daysOfWeek,
    startsOn: startsOn,
    endsOn: endsOn,
    assigneeMembershipId: assigneeMembershipId as String?,
    scheduleValid: weekdaysValid && dateWindowValid,
    status: status as String,
    syncState: syncState,
    operationId: operationId,
  );
}

FarmlyLiveTaskOccurrence _farmlyLiveTaskOccurrenceFromJson(
  Map<String, dynamic> json, {
  required String farmId,
}) {
  final id = json['id'];
  final version = json['version'];
  final templateId = json['templateId'];
  final occurrenceDate = json['occurrenceDate'];
  final slot = json['slot'];
  final status = json['status'];
  if (id is! String ||
      version is! int ||
      version < 1 ||
      templateId is! String ||
      occurrenceDate is! String ||
      slot is! String ||
      !const {
        'open',
        'in_progress',
        'done',
        'skipped',
        'cancelled',
      }.contains(status)) {
    throw const FormatException('Invalid local task occurrence fields');
  }
  final expectedId = farmlyTaskOccurrenceResourceId(
    farmId: farmId,
    templateId: templateId,
    occurrenceDate: occurrenceDate,
    slot: slot,
  );
  if (expectedId != id.toLowerCase()) {
    throw const FormatException('Invalid local task occurrence identity');
  }
  return FarmlyLiveTaskOccurrence(
    id: id.toLowerCase(),
    templateId: templateId.toLowerCase(),
    occurrenceDate: occurrenceDate,
    slot: slot.trim(),
    status: status as String,
    version: version,
    isMaterialized: true,
    syncState: FarmlyZoneSyncState.confirmed,
  );
}

List<FarmlyLiveTaskOccurrence> _farmlyTaskOccurrencesForToday({
  required String farmId,
  required String? farmLocalDate,
  required List<FarmlyLiveTaskTemplate> templates,
  required Iterable<Object?> occurrenceRows,
  required List<OutboxEntry> outboxEntries,
  required FarmlyMutationScope scope,
}) {
  if (farmLocalDate == null) return const [];
  final templatesById = {
    for (final template in templates) template.id: template,
  };
  final materialized = <String, FarmlyLiveTaskOccurrence>{};
  for (final row in occurrenceRows) {
    if (row is! Map) {
      throw const FormatException('Invalid local task occurrence row');
    }
    final occurrence = _farmlyLiveTaskOccurrenceFromJson(
      Map<String, dynamic>.from(row),
      farmId: farmId,
    );
    if (occurrence.occurrenceDate == farmLocalDate &&
        templatesById[occurrence.templateId]?.status == 'active') {
      materialized[occurrence.id] = occurrence;
    }
  }

  final occurrences = <String, FarmlyLiveTaskOccurrence>{};
  for (final template in templates) {
    if (template.version < 1 ||
        template.syncState != FarmlyZoneSyncState.confirmed ||
        template.status != 'active') {
      continue;
    }
    final templateMaterialized = materialized.values
        .where(
          (item) =>
              item.templateId == template.id &&
              item.occurrenceDate == farmLocalDate,
        )
        .toList(growable: false);
    if (templateMaterialized.isNotEmpty) {
      for (final item in templateMaterialized) {
        occurrences[item.id] = item;
      }
      continue;
    }
    if (template.zoneId == null ||
        !template.scheduleValid ||
        !farmlyTaskScheduleIncludesDate(
          frequency: template.frequency,
          daysOfWeek: template.daysOfWeek,
          startsOn: template.startsOn,
          endsOn: template.endsOn,
          occurrenceDate: farmLocalDate,
        )) {
      continue;
    }
    final id = farmlyTaskOccurrenceResourceId(
      farmId: farmId,
      templateId: template.id,
      occurrenceDate: farmLocalDate,
      slot: 'default',
    );
    occurrences[id] = FarmlyLiveTaskOccurrence(
      id: id,
      templateId: template.id,
      occurrenceDate: farmLocalDate,
      slot: 'default',
      status: 'open',
      version: null,
      isMaterialized: false,
      syncState: FarmlyZoneSyncState.confirmed,
    );
  }

  for (final entry in outboxEntries) {
    final intent = entry.mutation.intent;
    if (!_entryMatchesScope(entry, scope) ||
        (intent.type != 'taskOccurrence.transition' &&
            intent.type != 'irrigationTask.transition')) {
      continue;
    }
    final payload = intent.payload;
    final templateId = payload['templateId'];
    final occurrenceDate = payload['occurrenceDate'];
    final slot = payload['slot'];
    final transition = payload['transition'];
    if (templateId is! String ||
        occurrenceDate != farmLocalDate ||
        slot is! String ||
        transition is! String) {
      continue;
    }
    final template = templatesById[templateId];
    if (template == null) continue;
    String expectedId;
    try {
      expectedId = farmlyTaskOccurrenceResourceId(
        farmId: farmId,
        templateId: templateId,
        occurrenceDate: farmLocalDate,
        slot: slot,
      );
    } on Object {
      continue;
    }
    if (intent.resourceId != expectedId) continue;
    var occurrence = occurrences[expectedId];
    occurrence ??= FarmlyLiveTaskOccurrence(
      id: expectedId,
      templateId: templateId,
      occurrenceDate: farmLocalDate,
      slot: slot.trim(),
      status: 'open',
      version: intent.baseVersion,
      isMaterialized: intent.baseVersion != null,
      syncState: FarmlyZoneSyncState.confirmed,
    );
    final targetStatus = switch (transition) {
      'complete' => 'done',
      'skip' => 'skipped',
      'reopen' => 'open',
      'cancel' => 'cancelled',
      _ => null,
    };
    if (targetStatus == null) continue;
    final reflectedVersion = intent.baseVersion ?? 1;
    if (entry.status == OutboxEntryStatus.applied &&
        occurrence.isMaterialized &&
        occurrence.version != null &&
        occurrence.version! > reflectedVersion) {
      continue;
    }
    final syncState = _syncStateForEntry(entry);
    occurrences[expectedId] = occurrence.copyWith(
      status: syncState == FarmlyZoneSyncState.needsAttention
          ? occurrence.status
          : targetStatus,
      syncState: syncState,
      operationId: entry.operationId,
    );
  }

  final sorted = occurrences.values.toList(growable: false)
    ..sort((a, b) {
      final templateA = templatesById[a.templateId];
      final templateB = templatesById[b.templateId];
      final timeOrder = (templateA?.timeOfDay ?? '').compareTo(
        templateB?.timeOfDay ?? '',
      );
      return timeOrder != 0 ? timeOrder : a.slot.compareTo(b.slot);
    });
  return sorted;
}

final class LiveFarmZonesScreen extends ConsumerWidget {
  const LiveFarmZonesScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context);
    final zonesState = ref.watch(farmlyLiveZoneCollectionProvider);
    return zonesState.when(
      loading: () => FarmScaffold(
        topBar: FarmTopBar(title: l10n.farmOverviewFallbackTitle),
        body: const Center(child: CircularProgressIndicator()),
      ),
      error: (_, _) => FarmScaffold(
        topBar: FarmTopBar(title: l10n.farmOverviewFallbackTitle),
        body: FarmErrorView(
          onRetry: () => ref.invalidate(farmlyLiveZoneCollectionProvider),
          onSwitchScope: () => showFarmPickerSheet(context),
        ),
      ),
      data: (data) => _buildData(context, ref, l10n, data),
    );
  }

  Widget _buildData(
    BuildContext context,
    WidgetRef ref,
    AppLocalizations l10n,
    FarmlyLiveZoneCollection data,
  ) {
    final syncStatus = ref.watch(syncStatusProvider).value;
    final tokens = FarmThemeExtension.of(context);
    return FarmScaffold(
      topBar: FarmTopBar(
        title: data.farmName.isEmpty
            ? l10n.farmOverviewFallbackTitle
            : data.farmName,
        subtitle: data.organizationName.isEmpty
            ? l10n.liveFarmDataLabel
            : '${data.organizationName} · ${l10n.liveFarmDataLabel}',
        actions: [
          if (data.canEditFarmName)
            IconButton(
              key: const ValueKey('farm-overview-edit-farm'),
              tooltip: l10n.editFarmNameAction,
              icon: const Icon(Icons.edit_outlined),
              onPressed: () => _editFarmName(context, ref, data, l10n),
            ),
          IconButton(
            tooltip: l10n.changeFarm,
            icon: const Icon(Icons.swap_horiz_outlined),
            onPressed: () => showFarmPickerSheet(context),
          ),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(
          FarmSpacing.lg,
          FarmSpacing.sm,
          FarmSpacing.lg,
          FarmSpacing.xxl,
        ),
        children: [
          if (data.farmNamePending)
            Padding(
              padding: const EdgeInsets.only(bottom: FarmSpacing.md),
              child: DecoratedBox(
                decoration: BoxDecoration(
                  color: Theme.of(context).colorScheme.secondaryContainer,
                  borderRadius: BorderRadius.circular(FarmSpacing.inputRadius),
                ),
                child: Padding(
                  padding: const EdgeInsets.all(FarmSpacing.md),
                  child: Row(
                    children: [
                      Icon(
                        Icons.sync_rounded,
                        color: Theme.of(
                          context,
                        ).colorScheme.onSecondaryContainer,
                      ),
                      const SizedBox(width: FarmSpacing.sm),
                      Expanded(
                        child: Text(
                          l10n.liveFarmSavedPending,
                          style: Theme.of(context).textTheme.bodyMedium,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          switch (data.cacheState) {
            FarmlyZoneCacheState.noFarm => _StatusCard(
              icon: Icons.landscape_outlined,
              title: l10n.noSelectedFarm,
              body: l10n.liveFarmNoFarmBody,
              actionLabel: l10n.changeFarm,
              onAction: () => showFarmPickerSheet(context),
            ),
            FarmlyZoneCacheState.notBootstrapped => _StatusCard(
              key: const ValueKey('live-farm-no-cache'),
              icon: Icons.cloud_download_outlined,
              title: l10n.liveFarmNoCacheTitle,
              body: l10n.liveFarmNoCacheBody,
              actionLabel: l10n.liveFarmRefreshButton,
              onAction: syncStatus?.running == true
                  ? null
                  : () => _synchronize(ref),
            ),
            FarmlyZoneCacheState.stale => _StatusCard(
              icon: Icons.sync_problem_outlined,
              title: l10n.liveFarmStaleTitle,
              body: l10n.liveFarmStaleBody,
              actionLabel: l10n.liveFarmRefreshButton,
              onAction: syncStatus?.running == true
                  ? null
                  : () => _synchronize(ref),
            ),
            FarmlyZoneCacheState.scopeChanged => _StatusCard(
              icon: Icons.lock_outline,
              title: l10n.liveFarmScopeChanged,
              body: l10n.liveFarmReadOnlyBody,
              actionLabel: l10n.changeFarm,
              onAction: () => showFarmPickerSheet(context),
            ),
            FarmlyZoneCacheState.ready => const SizedBox.shrink(),
          },
          if (data.cacheState == FarmlyZoneCacheState.ready &&
              data.zones.isEmpty)
            _StatusCard(
              icon: Icons.spa_outlined,
              title: l10n.zonesEmptyTitle,
              body: l10n.zonesEmptyBody,
            ),
          if (data.zones.isNotEmpty) ...[
            Padding(
              padding: const EdgeInsets.fromLTRB(
                FarmSpacing.xs,
                FarmSpacing.lg,
                FarmSpacing.xs,
                FarmSpacing.sm,
              ),
              child: Text(
                l10n.exploreSection,
                style: Theme.of(context).textTheme.titleMedium,
              ),
            ),
            for (final item in data.zones)
              Padding(
                padding: const EdgeInsets.only(bottom: FarmSpacing.sm),
                child: FarmCard(
                  key: ValueKey('live-zone-row-${item.zone.id}'),
                  semanticsLabel: l10n.liveZoneOpenDetailsSemantics(
                    item.zone.name,
                  ),
                  onTap: () => _openZoneDetails(context, data, item),
                  child: Row(
                    children: [
                      DecoratedBox(
                        decoration: BoxDecoration(
                          color: tokens.brandAction.withValues(alpha: 0.10),
                          borderRadius: BorderRadius.circular(
                            FarmSpacing.inputRadius,
                          ),
                        ),
                        child: SizedBox(
                          width: 48,
                          height: 48,
                          child: Icon(
                            _zoneIcon(item.zone.type),
                            color: tokens.brandAction,
                          ),
                        ),
                      ),
                      const SizedBox(width: FarmSpacing.md),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              item.zone.name,
                              style: Theme.of(context).textTheme.titleSmall,
                            ),
                            const SizedBox(height: FarmSpacing.xs),
                            Text(_zoneTypeLabel(l10n, item.zone.type)),
                          ],
                        ),
                      ),
                      const SizedBox(width: FarmSpacing.sm),
                      _ZoneSyncBadge(state: item.syncState),
                    ],
                  ),
                ),
              ),
          ],
          if (!data.canCreate)
            Padding(
              padding: const EdgeInsets.only(top: FarmSpacing.md),
              child: Text(
                l10n.liveFarmReadOnlyBody,
                style: Theme.of(
                  context,
                ).textTheme.bodySmall?.copyWith(color: tokens.textSecondary),
              ),
            ),
          if (data.canCreate)
            Padding(
              padding: const EdgeInsets.only(top: FarmSpacing.lg),
              child: FilledButton.icon(
                key: const ValueKey('live-zone-create'),
                onPressed: data.scope == null || data.selectedScope == null
                    ? null
                    : () => _openCreateSheet(context, ref, data),
                icon: const Icon(Icons.add_location_alt_outlined),
                label: Text(l10n.liveFarmAddZone),
              ),
            ),
        ],
      ),
    );
  }

  Future<void> _synchronize(WidgetRef ref) async {
    await ref.read(syncStatusProvider.notifier).synchronize();
    ref.invalidate(farmlyLiveZoneCollectionProvider);
  }

  Future<void> _editFarmName(
    BuildContext context,
    WidgetRef ref,
    FarmlyLiveZoneCollection data,
    AppLocalizations l10n,
  ) async {
    if (!data.canEditFarmName ||
        data.scope == null ||
        data.selectedScope == null ||
        data.farmVersion == null) {
      return;
    }
    final saved = await showFarmNameEditSheet(
      context,
      initialName: data.farmName,
      hasPendingUpdate: data.farmNameHasPendingUpdate,
      onSave: (name) =>
          _enqueueFarmNameUpdate(ref: ref, captured: data, name: name),
    );
    if (!context.mounted || saved != true) return;
    ref.invalidate(syncStatusProvider);
    ref.invalidate(farmlyLiveZoneCollectionProvider);
    showFarmToast(context, l10n.savedOnDeviceToast);
  }

  Future<void> _openZoneDetails(
    BuildContext context,
    FarmlyLiveZoneCollection data,
    FarmlyLiveZone zone,
  ) => showModalBottomSheet<void>(
    context: context,
    useSafeArea: true,
    isScrollControlled: true,
    builder: (_) => _LiveZoneDetailsSheet(data: data, zone: zone),
  );

  Future<void> _openCreateSheet(
    BuildContext context,
    WidgetRef ref,
    FarmlyLiveZoneCollection data,
  ) async {
    final created = await showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      builder: (_) => _LiveZoneCreateSheet(
        scope: data.scope!,
        selectedScope: data.selectedScope!,
      ),
    );
    if (created != true || !context.mounted) return;
    ref.invalidate(farmlyLiveZoneCollectionProvider);
    showFarmToast(context, AppLocalizations.of(context).liveFarmSavedPending);
  }
}

class _LiveZoneDetailsSheet extends ConsumerWidget {
  const _LiveZoneDetailsSheet({required this.data, required this.zone});

  final FarmlyLiveZoneCollection data;
  final FarmlyLiveZone zone;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context);
    final selectedScope = ref.watch(selectedOrganizationScopeProvider);
    final selectedFarm = selectedScope?.selectedFarm;
    final currentScope = ref.watch(farmlySyncScopeProvider).asData?.value;
    final currentAccount = ref
        .watch(farmlyAuthSessionProvider)
        .asData
        ?.value
        ?.user
        .id;
    final capturedScope = data.scope;
    final capturedSelection = data.selectedScope;
    final scopeIsCurrent =
        capturedScope != null &&
        capturedSelection != null &&
        currentAccount == capturedScope.accountId &&
        _sameSelection(capturedSelection, selectedScope) &&
        _sameFarmScope(capturedScope, currentScope) &&
        selectedFarm?.status == FarmlyFarmStatus.active;
    final projection = ref
        .watch(farmlyLiveZoneCollectionProvider)
        .asData
        ?.value;
    final displayData =
        scopeIsCurrent &&
            projection?.scope != null &&
            _sameFarmScope(capturedScope, projection!.scope)
        ? projection
        : data;
    var displayZone = zone;
    for (final item in displayData.zones) {
      if (item.zone.id == zone.zone.id) {
        displayZone = item;
        break;
      }
    }
    final canWrite =
        scopeIsCurrent &&
        selectedScope != null &&
        selectedFarm != null &&
        _canManageZones(selectedScope, selectedFarm) &&
        displayData.canCreate &&
        displayZone.syncState != FarmlyZoneSyncState.needsAttention;
    final isUniqueZone =
        displayData.zones
            .where((item) => item.zone.id == displayZone.zone.id)
            .length ==
        1;
    final canRenameZone =
        canWrite &&
        isUniqueZone &&
        displayZone.syncState == FarmlyZoneSyncState.confirmed &&
        displayZone.zone.version > 0 &&
        displayZone.zone.status == 'active';
    final canRecordHarvest =
        scopeIsCurrent &&
        selectedScope != null &&
        selectedFarm != null &&
        _canRecordHarvest(selectedScope, selectedFarm) &&
        displayZone.syncState != FarmlyZoneSyncState.needsAttention;
    final canRecordWater = canRecordHarvest;
    final canRecordMoisture =
        canRecordHarvest &&
        displayZone.zone.type == 'crop_plot' &&
        displayZone.zone.status == 'active' &&
        displayZone.syncState != FarmlyZoneSyncState.needsAttention &&
        (displayData.cacheState == FarmlyZoneCacheState.ready ||
            displayData.cacheState == FarmlyZoneCacheState.notBootstrapped);
    final visibleMoistureReadings = _latestMoistureReadingsForZone(
      displayData.moistureReadings,
      displayZone.zone.id,
    );
    final speciesById = {
      for (final item in displayData.cropSpecies) item.species.id: item.species,
    };
    final visiblePlantings = displayData.plantings
        .where(
          (item) =>
              item.planting.plotId == displayZone.zone.id &&
              item.planting.status != 'archived',
        )
        .toList(growable: false);
    final selectableSpecies = displayData.cropSpecies
        .where(
          (item) =>
              item.species.status != 'archived' &&
              item.syncState != FarmlyZoneSyncState.needsAttention,
        )
        .toList(growable: false);
    final visibleTaskTemplates =
        displayData.taskTemplates
            .where(
              (item) =>
                  item.zoneId == displayZone.zone.id && item.status == 'active',
            )
            .toList(growable: false)
          ..sort(
            (a, b) => a.title.toLowerCase().compareTo(b.title.toLowerCase()),
          );
    final visibleTaskTemplateIds = {
      for (final template in visibleTaskTemplates) template.id,
    };
    final visibleTaskOccurrences = displayData.taskOccurrences
        .where(
          (occurrence) =>
              visibleTaskTemplateIds.contains(occurrence.templateId),
        )
        .toList(growable: false);
    final canManageTasks = canWrite && displayZone.zone.status == 'active';
    final canWorkerTasks =
        scopeIsCurrent &&
        selectedScope != null &&
        selectedFarm != null &&
        selectedFarm.grantRole == FarmlyFarmGrantRole.worker &&
        _canRecordHarvest(selectedScope, selectedFarm) &&
        displayData.cacheState == FarmlyZoneCacheState.ready &&
        displayZone.zone.status == 'active' &&
        displayZone.syncState != FarmlyZoneSyncState.needsAttention;

    return SafeArea(
      child: ConstrainedBox(
        constraints: BoxConstraints(
          maxHeight: MediaQuery.sizeOf(context).height * 0.88,
        ),
        child: SingleChildScrollView(
          child: Padding(
            key: const ValueKey('live-zone-details'),
            padding: const EdgeInsets.fromLTRB(
              FarmSpacing.lg,
              FarmSpacing.sm,
              FarmSpacing.lg,
              FarmSpacing.xl,
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Text(
                  l10n.liveZoneDetailsTitle,
                  style: Theme.of(context).textTheme.titleLarge,
                ),
                const SizedBox(height: FarmSpacing.md),
                Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Expanded(
                      child: Text(
                        displayZone.zone.name,
                        style: Theme.of(context).textTheme.headlineSmall,
                        softWrap: true,
                      ),
                    ),
                    if (canRenameZone)
                      IconButton(
                        key: const ValueKey('live-zone-edit-name'),
                        tooltip: l10n.liveZoneRenameAction,
                        onPressed: () => _openLiveZoneRename(
                          context,
                          ref,
                          scope: capturedScope,
                          selectedScope: capturedSelection,
                          zone: displayZone.zone,
                        ),
                        icon: const Icon(Icons.edit_outlined),
                      ),
                  ],
                ),
                const SizedBox(height: FarmSpacing.sm),
                Wrap(
                  spacing: FarmSpacing.sm,
                  runSpacing: FarmSpacing.xs,
                  crossAxisAlignment: WrapCrossAlignment.center,
                  children: [
                    Chip(
                      label: Text(_zoneTypeLabel(l10n, displayZone.zone.type)),
                      visualDensity: VisualDensity.compact,
                    ),
                    _ZoneSyncBadge(state: displayZone.syncState),
                  ],
                ),
                if (!scopeIsCurrent) ...[
                  const SizedBox(height: FarmSpacing.md),
                  Text(
                    l10n.liveFarmScopeChanged,
                    style: TextStyle(
                      color: FarmThemeExtension.of(context).semanticWarning,
                    ),
                  ),
                ] else ...[
                  const SizedBox(height: FarmSpacing.lg),
                  Text(
                    l10n.liveFarmDataLabel,
                    style: Theme.of(context).textTheme.bodySmall,
                  ),
                  const SizedBox(height: FarmSpacing.lg),
                  if (displayZone.zone.type == 'crop_plot') ...[
                    const SizedBox(height: FarmSpacing.lg),
                    KeyedSubtree(
                      key: const ValueKey('live-zone-moisture-section'),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          _sectionTitle(
                            context,
                            title: l10n.moistureSectionTitle,
                          ),
                          if (visibleMoistureReadings.isEmpty)
                            Padding(
                              padding: const EdgeInsets.symmetric(
                                vertical: FarmSpacing.sm,
                              ),
                              child: Text(l10n.noMoistureReading),
                            ),
                          for (final reading in visibleMoistureReadings)
                            Padding(
                              padding: const EdgeInsets.only(
                                bottom: FarmSpacing.xs,
                              ),
                              child: FarmCard(
                                key: ValueKey(
                                  'live-moisture-reading-${reading.id}',
                                ),
                                child: Row(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Icon(
                                      Icons.water_drop_outlined,
                                      color: FarmThemeExtension.of(
                                        context,
                                      ).brandAction,
                                    ),
                                    const SizedBox(width: FarmSpacing.sm),
                                    Expanded(
                                      child: Column(
                                        crossAxisAlignment:
                                            CrossAxisAlignment.start,
                                        children: [
                                          Text(
                                            l10n.moistureLine(
                                              formatDisplayDecimal(
                                                reading.value.value,
                                                l10n.localeName,
                                              ),
                                              _moistureMethodLabel(
                                                l10n,
                                                reading.method,
                                              ),
                                              _formatFarmMeasurementTime(
                                                reading.measuredAt,
                                                displayData.farmTimezone,
                                                l10n.localeName,
                                              ),
                                            ),
                                            style: Theme.of(
                                              context,
                                            ).textTheme.titleSmall,
                                          ),
                                          const SizedBox(
                                            height: FarmSpacing.xs,
                                          ),
                                          Text(l10n.moistureSourceManual),
                                        ],
                                      ),
                                    ),
                                    const SizedBox(width: FarmSpacing.xs),
                                    _ZoneSyncBadge(state: reading.syncState),
                                  ],
                                ),
                              ),
                            ),
                          if (canRecordMoisture)
                            OutlinedButton.icon(
                              key: const ValueKey('live-moisture-create'),
                              onPressed: () => _openMoistureCreate(
                                context,
                                ref,
                                displayZone,
                                capturedScope,
                                capturedSelection,
                              ),
                              icon: const Icon(Icons.add),
                              label: Text(l10n.measureMoisture),
                            ),
                        ],
                      ),
                    ),
                    const SizedBox(height: FarmSpacing.lg),
                    KeyedSubtree(
                      key: const ValueKey('live-crop-species-list'),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          _sectionTitle(
                            context,
                            title: l10n.liveCropSpeciesSection,
                          ),
                          if (displayData.cropSpecies.isEmpty)
                            Padding(
                              padding: const EdgeInsets.symmetric(
                                vertical: FarmSpacing.sm,
                              ),
                              child: Text(l10n.liveCropSpeciesEmpty),
                            ),
                          for (final item in displayData.cropSpecies)
                            Padding(
                              padding: const EdgeInsets.only(
                                bottom: FarmSpacing.xs,
                              ),
                              child: FarmCard(
                                key: ValueKey(
                                  'live-crop-species-row-${item.species.id}',
                                ),
                                child: Column(
                                  crossAxisAlignment:
                                      CrossAxisAlignment.stretch,
                                  children: [
                                    Row(
                                      children: [
                                        const Icon(Icons.spa_outlined),
                                        const SizedBox(width: FarmSpacing.sm),
                                        Expanded(
                                          child: Column(
                                            crossAxisAlignment:
                                                CrossAxisAlignment.start,
                                            children: [
                                              Text(
                                                '${item.species.name} · '
                                                '${_cropUnitLabel(l10n, item.species.harvestUnit)}',
                                                style: Theme.of(
                                                  context,
                                                ).textTheme.titleSmall,
                                              ),
                                              if (item.species.status ==
                                                  'archived')
                                                Padding(
                                                  padding:
                                                      const EdgeInsets.only(
                                                        top: FarmSpacing.xs,
                                                      ),
                                                  child: Semantics(
                                                    label:
                                                        item.syncState ==
                                                            FarmlyZoneSyncState
                                                                .confirmed
                                                        ? l10n.liveCropSpeciesArchived
                                                        : l10n.liveCropSpeciesArchivePending,
                                                    child: Text(
                                                      item.syncState ==
                                                              FarmlyZoneSyncState
                                                                  .confirmed
                                                          ? l10n.liveCropSpeciesArchived
                                                          : l10n.liveCropSpeciesArchivePending,
                                                      style: Theme.of(context)
                                                          .textTheme
                                                          .bodySmall
                                                          ?.copyWith(
                                                            color:
                                                                FarmThemeExtension.of(
                                                                  context,
                                                                ).textSecondary,
                                                          ),
                                                    ),
                                                  ),
                                                ),
                                            ],
                                          ),
                                        ),
                                        _ZoneSyncBadge(state: item.syncState),
                                      ],
                                    ),
                                    if (canWrite &&
                                        item.species.status == 'active' &&
                                        item.species.version > 0 &&
                                        item.syncState ==
                                            FarmlyZoneSyncState.confirmed &&
                                        !item.hasUnresolvedUpdate)
                                      Padding(
                                        padding: const EdgeInsets.only(
                                          top: FarmSpacing.xs,
                                        ),
                                        child: Row(
                                          mainAxisAlignment:
                                              MainAxisAlignment.end,
                                          children: [
                                            IconButton(
                                              key: ValueKey(
                                                'live-crop-species-archive-${item.species.id}',
                                              ),
                                              tooltip: l10n
                                                  .liveCropSpeciesArchiveAction(
                                                    item.species.name,
                                                  ),
                                              onPressed: () =>
                                                  _openSpeciesArchive(
                                                    context,
                                                    ref,
                                                    item.species,
                                                  ),
                                              icon: const Icon(
                                                Icons.archive_outlined,
                                              ),
                                              padding: EdgeInsets.zero,
                                              visualDensity:
                                                  VisualDensity.compact,
                                              constraints: const BoxConstraints(
                                                minWidth: 40,
                                                minHeight: 40,
                                              ),
                                            ),
                                            IconButton(
                                              key: ValueKey(
                                                'live-crop-species-edit-${item.species.id}',
                                              ),
                                              tooltip: l10n
                                                  .liveCropSpeciesRenameAction,
                                              onPressed: () =>
                                                  _openSpeciesRename(
                                                    context,
                                                    ref,
                                                    item.species,
                                                  ),
                                              icon: const Icon(
                                                Icons.edit_outlined,
                                              ),
                                              padding: EdgeInsets.zero,
                                              visualDensity:
                                                  VisualDensity.compact,
                                              constraints: const BoxConstraints(
                                                minWidth: 40,
                                                minHeight: 40,
                                              ),
                                            ),
                                          ],
                                        ),
                                      ),
                                  ],
                                ),
                              ),
                            ),
                          if (canWrite)
                            OutlinedButton.icon(
                              key: const ValueKey('live-crop-species-create'),
                              onPressed: () => _openSpeciesCreate(context, ref),
                              icon: const Icon(Icons.add),
                              label: Text(l10n.liveCropSpeciesCreate),
                            ),
                        ],
                      ),
                    ),
                    const SizedBox(height: FarmSpacing.lg),
                    KeyedSubtree(
                      key: const ValueKey('live-plantings-list'),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          _sectionTitle(
                            context,
                            title: l10n.livePlantingsSection,
                          ),
                          if (visiblePlantings.isEmpty)
                            Padding(
                              padding: const EdgeInsets.symmetric(
                                vertical: FarmSpacing.sm,
                              ),
                              child: Text(l10n.livePlantingsEmpty),
                            ),
                          for (final item in visiblePlantings)
                            Padding(
                              padding: const EdgeInsets.only(
                                bottom: FarmSpacing.xs,
                              ),
                              child: FarmCard(
                                key: ValueKey(
                                  'live-planting-row-${item.planting.id}',
                                ),
                                child: Column(
                                  crossAxisAlignment:
                                      CrossAxisAlignment.stretch,
                                  children: [
                                    Builder(
                                      builder: (headerContext) {
                                        final canMutate =
                                            canWrite &&
                                            item.syncState ==
                                                FarmlyZoneSyncState.confirmed &&
                                            item.planting.version >= 1 &&
                                            item.planting.status !=
                                                'archived' &&
                                            item.isUniqueConfirmedRecord &&
                                            !item.hasUnresolvedUpdate &&
                                            !item.hasUnresolvedArchive;
                                        final mutationActions = <Widget>[
                                          if (canMutate)
                                            IconButton(
                                              key: ValueKey(
                                                'live-planting-edit-${item.planting.id}',
                                              ),
                                              tooltip:
                                                  l10n.livePlantingEditAction,
                                              onPressed: () =>
                                                  _openPlantingUpdate(
                                                    context,
                                                    ref,
                                                    displayZone,
                                                    item,
                                                  ),
                                              icon: const Icon(
                                                Icons.edit_outlined,
                                              ),
                                            ),
                                          if (canMutate)
                                            IconButton(
                                              key: ValueKey(
                                                'live-planting-archive-${item.planting.id}',
                                              ),
                                              tooltip: l10n
                                                  .livePlantingArchiveAction,
                                              onPressed: () =>
                                                  _openPlantingArchive(
                                                    context,
                                                    ref,
                                                    displayZone,
                                                    item,
                                                  ),
                                              icon: const Icon(
                                                Icons.archive_outlined,
                                              ),
                                            ),
                                        ];
                                        final title = Text(
                                          speciesById[item
                                                      .planting
                                                      .cropSpeciesId]
                                                  ?.name ??
                                              l10n.livePlantingUnknownSpecies,
                                          style: Theme.of(
                                            headerContext,
                                          ).textTheme.titleSmall,
                                        );
                                        return LayoutBuilder(
                                          builder: (context, constraints) {
                                            final compact =
                                                constraints.maxWidth < 280 ||
                                                MediaQuery.textScalerOf(
                                                      context,
                                                    ).scale(1) >
                                                    1.15;
                                            if (compact) {
                                              return Column(
                                                crossAxisAlignment:
                                                    CrossAxisAlignment.stretch,
                                                children: [
                                                  Row(
                                                    children: [
                                                      const Icon(
                                                        Icons.grass_outlined,
                                                      ),
                                                      const SizedBox(
                                                        width: FarmSpacing.sm,
                                                      ),
                                                      Expanded(child: title),
                                                      _ZoneSyncBadge(
                                                        state: item.syncState,
                                                      ),
                                                    ],
                                                  ),
                                                  Align(
                                                    alignment:
                                                        AlignmentDirectional
                                                            .centerEnd,
                                                    child: Row(
                                                      mainAxisSize:
                                                          MainAxisSize.min,
                                                      children: mutationActions,
                                                    ),
                                                  ),
                                                ],
                                              );
                                            }
                                            return Row(
                                              children: [
                                                const Icon(
                                                  Icons.grass_outlined,
                                                ),
                                                const SizedBox(
                                                  width: FarmSpacing.sm,
                                                ),
                                                Expanded(child: title),
                                                ...mutationActions,
                                                _ZoneSyncBadge(
                                                  state: item.syncState,
                                                ),
                                              ],
                                            );
                                          },
                                        );
                                      },
                                    ),
                                    const SizedBox(height: FarmSpacing.xs),
                                    Text(
                                      '${_plantingStatusLabel(l10n, item.planting.status)} · '
                                      '${l10n.livePlantingSowingValue(formatDisplayDate(item.planting.sowingDate, l10n.localeName) ?? item.planting.sowingDate)}',
                                    ),
                                    if (item.planting.expectedHarvestDate !=
                                        null)
                                      Text(
                                        l10n.livePlantingHarvestValue(
                                          formatDisplayDate(
                                                item
                                                    .planting
                                                    .expectedHarvestDate,
                                                l10n.localeName,
                                              ) ??
                                              item
                                                  .planting
                                                  .expectedHarvestDate!,
                                        ),
                                      ),
                                    if (item.planting.areaM2 != null)
                                      Text(
                                        l10n.livePlantingAreaValue(
                                          formatDisplayDecimal(
                                            item.planting.areaM2!.value,
                                            l10n.localeName,
                                          ),
                                        ),
                                      ),
                                    const SizedBox(height: FarmSpacing.md),
                                    _sectionTitle(
                                      context,
                                      title: l10n.liveHarvestSection,
                                    ),
                                    if (displayData.harvests
                                        .where(
                                          (harvest) =>
                                              harvest.plantingId ==
                                              item.planting.id,
                                        )
                                        .isEmpty)
                                      Padding(
                                        padding: const EdgeInsets.only(
                                          bottom: FarmSpacing.xs,
                                        ),
                                        child: Text(l10n.liveHarvestEmpty),
                                      ),
                                    for (final harvest
                                        in displayData.harvests.where(
                                          (harvest) =>
                                              harvest.plantingId ==
                                              item.planting.id,
                                        ))
                                      Padding(
                                        padding: const EdgeInsets.only(
                                          bottom: FarmSpacing.xs,
                                        ),
                                        child: Semantics(
                                          button: true,
                                          label: l10n.liveHarvestOpenSemantics(
                                            formatDisplayDecimal(
                                              harvest.quantityKg.value,
                                              l10n.localeName,
                                            ),
                                            formatDisplayDate(
                                                  harvest.harvestDate,
                                                  l10n.localeName,
                                                ) ??
                                                harvest.harvestDate,
                                            harvest.status == 'voided'
                                                ? l10n.liveHarvestVoided
                                                : l10n.syncSynced,
                                          ),
                                          child: InkWell(
                                            key: ValueKey(
                                              'live-harvest-row-${harvest.id}',
                                            ),
                                            borderRadius: BorderRadius.circular(
                                              FarmSpacing.inputRadius,
                                            ),
                                            onTap: () => _openHarvestActions(
                                              context,
                                              ref,
                                              displayZone,
                                              harvest,
                                              canPropose: canRecordHarvest,
                                              canManage: canWrite,
                                            ),
                                            child: ConstrainedBox(
                                              constraints: const BoxConstraints(
                                                minHeight: 48,
                                              ),
                                              child: Padding(
                                                padding:
                                                    const EdgeInsets.symmetric(
                                                      vertical: FarmSpacing.xs,
                                                    ),
                                                child: Row(
                                                  children: [
                                                    const Icon(
                                                      Icons
                                                          .agriculture_outlined,
                                                    ),
                                                    const SizedBox(
                                                      width: FarmSpacing.sm,
                                                    ),
                                                    Expanded(
                                                      child: Text(
                                                        '${harvest.status == 'voided' ? '${l10n.liveHarvestVoided} · ' : ''}'
                                                        '${formatDisplayDecimal(harvest.quantityKg.value, l10n.localeName)} kg · '
                                                        '${formatDisplayDate(harvest.harvestDate, l10n.localeName) ?? harvest.harvestDate}',
                                                      ),
                                                    ),
                                                    _ZoneSyncBadge(
                                                      state: harvest.syncState,
                                                    ),
                                                  ],
                                                ),
                                              ),
                                            ),
                                          ),
                                        ),
                                      ),
                                    const SizedBox(height: FarmSpacing.md),
                                    _sectionTitle(
                                      context,
                                      title: l10n.livePlantingEventsSection,
                                    ),
                                    if (item.events.isEmpty)
                                      Padding(
                                        padding: const EdgeInsets.only(
                                          bottom: FarmSpacing.xs,
                                        ),
                                        child: Text(
                                          l10n.livePlantingEventsEmpty,
                                        ),
                                      ),
                                    for (final event in item.events)
                                      Container(
                                        key: ValueKey(
                                          'live-planting-event-row-${event.id}',
                                        ),
                                        margin: const EdgeInsets.only(
                                          bottom: FarmSpacing.xs,
                                        ),
                                        padding: const EdgeInsets.symmetric(
                                          vertical: FarmSpacing.xs,
                                        ),
                                        child: Row(
                                          crossAxisAlignment:
                                              CrossAxisAlignment.start,
                                          children: [
                                            const Icon(
                                              Icons.event_note_outlined,
                                              size: 20,
                                            ),
                                            const SizedBox(
                                              width: FarmSpacing.sm,
                                            ),
                                            Expanded(
                                              child: Column(
                                                crossAxisAlignment:
                                                    CrossAxisAlignment.start,
                                                children: [
                                                  Text(
                                                    event.eventType,
                                                    style: Theme.of(
                                                      context,
                                                    ).textTheme.titleSmall,
                                                  ),
                                                  if (event.occurredOn != null)
                                                    Text(
                                                      formatDisplayDate(
                                                            event.occurredOn!,
                                                            l10n.localeName,
                                                          ) ??
                                                          event.occurredOn!,
                                                    ),
                                                  if (event.note != null)
                                                    Text(event.note!),
                                                ],
                                              ),
                                            ),
                                            const SizedBox(
                                              width: FarmSpacing.xs,
                                            ),
                                            _ZoneSyncBadge(
                                              state: event.syncState,
                                            ),
                                          ],
                                        ),
                                      ),
                                    if (canRecordHarvest &&
                                        item.planting.status != 'archived' &&
                                        item.syncState !=
                                            FarmlyZoneSyncState.needsAttention)
                                      Align(
                                        alignment: Alignment.centerLeft,
                                        child: OutlinedButton.icon(
                                          key: ValueKey(
                                            'live-planting-event-create-${item.planting.id}',
                                          ),
                                          onPressed: () =>
                                              _openPlantingEventCreate(
                                                context,
                                                ref,
                                                displayZone,
                                                item,
                                              ),
                                          icon: const Icon(
                                            Icons.add_comment_outlined,
                                          ),
                                          label: Text(
                                            l10n.livePlantingEventCreate,
                                          ),
                                        ),
                                      ),
                                    if (canRecordHarvest &&
                                        item.planting.status == 'active' &&
                                        item.syncState !=
                                            FarmlyZoneSyncState.needsAttention)
                                      Align(
                                        alignment: Alignment.centerLeft,
                                        child: OutlinedButton.icon(
                                          key: ValueKey(
                                            'live-harvest-create-${item.planting.id}',
                                          ),
                                          onPressed: () => _openHarvestCreate(
                                            context,
                                            ref,
                                            displayZone,
                                            item,
                                          ),
                                          icon: const Icon(
                                            Icons.add_chart_outlined,
                                          ),
                                          label: Text(l10n.liveHarvestCreate),
                                        ),
                                      ),
                                  ],
                                ),
                              ),
                            ),
                          if (displayZone.syncState ==
                              FarmlyZoneSyncState.needsAttention)
                            Padding(
                              padding: const EdgeInsets.symmetric(
                                vertical: FarmSpacing.sm,
                              ),
                              child: Text(
                                l10n.liveCropPlotNeedsAttention,
                                style: TextStyle(
                                  color: FarmThemeExtension.of(
                                    context,
                                  ).semanticWarning,
                                ),
                              ),
                            )
                          else if (canWrite && selectableSpecies.isEmpty)
                            Padding(
                              padding: const EdgeInsets.symmetric(
                                vertical: FarmSpacing.xs,
                              ),
                              child: Text(l10n.livePlantingNeedsSpecies),
                            ),
                          if (canWrite)
                            FilledButton.icon(
                              key: const ValueKey('live-planting-create'),
                              onPressed: selectableSpecies.isEmpty
                                  ? null
                                  : () => _openPlantingCreate(
                                      context,
                                      ref,
                                      displayZone,
                                      selectableSpecies,
                                    ),
                              icon: const Icon(Icons.add_task),
                              label: Text(l10n.livePlantingCreate),
                            ),
                        ],
                      ),
                    ),
                  ],
                  if (displayZone.zone.type == 'water') ...[
                    const SizedBox(height: FarmSpacing.lg),
                    KeyedSubtree(
                      key: const ValueKey('live-water-tanks-section'),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          _sectionTitle(
                            context,
                            title: l10n.liveWaterTanksSection,
                          ),
                          if (displayData.waterTanks
                              .where(
                                (item) =>
                                    item.tank.zoneId == displayZone.zone.id,
                              )
                              .isEmpty)
                            Padding(
                              padding: const EdgeInsets.symmetric(
                                vertical: FarmSpacing.sm,
                              ),
                              child: Text(l10n.liveWaterTanksEmpty),
                            ),
                          for (final item in displayData.waterTanks.where(
                            (item) => item.tank.zoneId == displayZone.zone.id,
                          ))
                            Padding(
                              padding: const EdgeInsets.only(
                                bottom: FarmSpacing.sm,
                              ),
                              child: _LiveWaterTankCard(
                                tank: item,
                                readings: displayData.waterReadings
                                    .where(
                                      (reading) =>
                                          reading.tankId == item.tank.id,
                                    )
                                    .toList(growable: false),
                                usages: displayData.waterUsages
                                    .where(
                                      (usage) => usage.tankId == item.tank.id,
                                    )
                                    .toList(growable: false),
                                canRecord:
                                    canRecordWater &&
                                    displayZone.zone.status == 'active' &&
                                    item.tank.status == 'active' &&
                                    item.syncState !=
                                        FarmlyZoneSyncState.needsAttention,
                                canRename:
                                    canWrite &&
                                    displayZone.zone.status == 'active' &&
                                    displayZone.zone.type == 'water' &&
                                    displayZone.syncState ==
                                        FarmlyZoneSyncState.confirmed &&
                                    item.tank.status == 'active' &&
                                    item.tank.version >= 1 &&
                                    item.syncState ==
                                        FarmlyZoneSyncState.confirmed &&
                                    !item.hasUnresolvedNameUpdate &&
                                    item.isUniqueConfirmedRecord,
                                onRename: () => _openWaterTankRename(
                                  context,
                                  ref,
                                  displayZone,
                                  item,
                                ),
                                onRecordReading: () => _openWaterReadingCreate(
                                  context,
                                  ref,
                                  displayZone,
                                  item,
                                ),
                                onRecordUsage: () => _openWaterUsageCreate(
                                  context,
                                  ref,
                                  displayZone,
                                  item,
                                ),
                              ),
                            ),
                          if (canWrite && displayZone.zone.status == 'active')
                            OutlinedButton.icon(
                              key: const ValueKey('live-water-tank-create'),
                              onPressed: () => _openWaterTankCreate(
                                context,
                                ref,
                                displayZone,
                              ),
                              icon: const Icon(Icons.add),
                              label: Text(l10n.liveWaterTankCreate),
                            ),
                        ],
                      ),
                    ),
                  ],
                  KeyedSubtree(
                    key: _liveTaskOccurrencesListKey,
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        _sectionTitle(
                          context,
                          title: l10n.liveTaskOccurrencesSection,
                        ),
                        if (displayData.farmLocalDate == null)
                          Padding(
                            padding: const EdgeInsets.symmetric(
                              vertical: FarmSpacing.sm,
                            ),
                            child: Text(l10n.liveTaskTimezoneUnavailable),
                          )
                        else if (visibleTaskOccurrences.isEmpty)
                          Padding(
                            padding: const EdgeInsets.symmetric(
                              vertical: FarmSpacing.sm,
                            ),
                            child: Text(l10n.liveTaskOccurrencesEmpty),
                          )
                        else
                          for (final occurrence in visibleTaskOccurrences)
                            for (final template in visibleTaskTemplates)
                              if (template.id == occurrence.templateId)
                                _LiveTaskOccurrenceCard(
                                  key: ValueKey(
                                    'live-task-occurrence-card-${occurrence.id}',
                                  ),
                                  scope: capturedScope,
                                  selectedScope: capturedSelection,
                                  zoneId: displayZone.zone.id,
                                  template: template,
                                  occurrence: occurrence,
                                  canManage: canManageTasks,
                                  canWorker: canWorkerTasks,
                                ),
                      ],
                    ),
                  ),
                  KeyedSubtree(
                    key: ValueKey(
                      'live-task-templates-list-${displayZone.zone.id}',
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        _sectionTitle(
                          context,
                          title: l10n.liveTaskTemplatesSection,
                        ),
                        if (visibleTaskTemplates.isEmpty)
                          Padding(
                            padding: const EdgeInsets.symmetric(
                              vertical: FarmSpacing.sm,
                            ),
                            child: Text(l10n.liveTaskTemplatesEmpty),
                          ),
                        for (final item in visibleTaskTemplates)
                          Padding(
                            padding: const EdgeInsets.only(
                              bottom: FarmSpacing.xs,
                            ),
                            child: FarmCard(
                              key: ValueKey(
                                'live-task-template-row-${item.id}',
                              ),
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.stretch,
                                children: [
                                  Row(
                                    crossAxisAlignment:
                                        CrossAxisAlignment.start,
                                    children: [
                                      const Icon(Icons.event_note_outlined),
                                      const SizedBox(width: FarmSpacing.sm),
                                      Expanded(
                                        child: Column(
                                          crossAxisAlignment:
                                              CrossAxisAlignment.start,
                                          children: [
                                            Text(
                                              item.title,
                                              style: Theme.of(
                                                context,
                                              ).textTheme.titleSmall,
                                            ),
                                            const SizedBox(
                                              height: FarmSpacing.xs,
                                            ),
                                            Text(
                                              '${_taskTemplateKindLabel(l10n, item.kind)} · '
                                              '${_taskTemplateScheduleLabel(l10n, item)}',
                                              style: Theme.of(
                                                context,
                                              ).textTheme.bodySmall,
                                            ),
                                          ],
                                        ),
                                      ),
                                      const SizedBox(width: FarmSpacing.sm),
                                      _ZoneSyncBadge(state: item.syncState),
                                    ],
                                  ),
                                  if (canWrite &&
                                      displayZone.zone.status == 'active' &&
                                      item.frequency == 'weekly' &&
                                      item.daysOfWeek.isEmpty)
                                    Align(
                                      alignment: Alignment.centerLeft,
                                      child: TextButton.icon(
                                        key: ValueKey(
                                          'live-task-template-repair-${item.id}',
                                        ),
                                        onPressed: () =>
                                            _openTaskTemplateWeekdayRepair(
                                              context,
                                              ref,
                                              item,
                                            ),
                                        icon: const Icon(
                                          Icons.edit_calendar_outlined,
                                        ),
                                        label: Text(l10n.liveTaskWeekdayRepair),
                                      ),
                                    ),
                                ],
                              ),
                            ),
                          ),
                        if (canWrite && displayZone.zone.status == 'active')
                          OutlinedButton.icon(
                            key: ValueKey(
                              'live-task-template-create-${displayZone.zone.id}',
                            ),
                            onPressed: () => _openTaskTemplateCreate(
                              context,
                              ref,
                              displayZone,
                            ),
                            icon: const Icon(Icons.add_task_outlined),
                            label: Text(l10n.liveTaskTemplateCreate),
                          ),
                      ],
                    ),
                  ),
                  if (!canWrite &&
                      !(displayZone.zone.type == 'crop_plot' &&
                          canRecordHarvest) &&
                      !(displayZone.zone.type == 'water' && canRecordWater) &&
                      selectedScope != null &&
                      selectedFarm != null &&
                      !_canManageZones(selectedScope, selectedFarm)) ...[
                    const SizedBox(height: FarmSpacing.md),
                    Text(l10n.liveFarmReadOnlyBody),
                  ],
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _sectionTitle(BuildContext context, {required String title}) =>
      Padding(
        padding: const EdgeInsets.only(bottom: FarmSpacing.xs),
        child: Text(title, style: Theme.of(context).textTheme.titleMedium),
      );

  Future<void> _openMoistureCreate(
    BuildContext context,
    WidgetRef ref,
    FarmlyLiveZone currentZone,
    FarmlyMutationScope scope,
    FarmlyOrganizationScope selectedScope,
  ) async {
    final saved = await showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      builder: (_) => _LiveMoistureReadingCreateSheet(
        scope: scope,
        selectedScope: selectedScope,
        zone: currentZone,
      ),
    );
    if (!context.mounted) return;
    _finishCropSave(context, ref, saved);
  }

  Future<void> _openSpeciesCreate(BuildContext context, WidgetRef ref) async {
    final scope = data.scope;
    final selectedScope = data.selectedScope;
    if (scope == null || selectedScope == null) return;
    final saved = await showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      builder: (_) => _LiveCropSpeciesCreateSheet(
        scope: scope,
        selectedScope: selectedScope,
      ),
    );
    if (!context.mounted) return;
    _finishCropSave(context, ref, saved);
  }

  Future<void> _openSpeciesRename(
    BuildContext context,
    WidgetRef ref,
    FarmlyCropSpeciesDto species,
  ) async {
    final scope = data.scope;
    final selectedScope = data.selectedScope;
    if (scope == null ||
        selectedScope == null ||
        species.status != 'active' ||
        species.version < 1) {
      return;
    }
    final saved = await showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      builder: (_) => _LiveCropSpeciesRenameSheet(
        scope: scope,
        selectedScope: selectedScope,
        species: species,
      ),
    );
    if (!context.mounted) return;
    _finishCropSave(context, ref, saved);
  }

  Future<void> _openSpeciesArchive(
    BuildContext context,
    WidgetRef ref,
    FarmlyCropSpeciesDto species,
  ) async {
    final scope = data.scope;
    final selectedScope = data.selectedScope;
    final selectedFarm = selectedScope?.selectedFarm;
    if (scope == null ||
        selectedScope == null ||
        selectedFarm == null ||
        species.status != 'active' ||
        species.version < 1 ||
        !_canManageCropSpecies(selectedScope, selectedFarm)) {
      return;
    }

    final confirmed = await showDialog<bool>(
      context: context,
      useRootNavigator: false,
      builder: (dialogContext) {
        final l10n = AppLocalizations.of(dialogContext);
        return AlertDialog(
          key: const ValueKey('live-crop-species-archive-dialog'),
          title: Text(l10n.liveCropSpeciesArchiveTitle),
          content: Text(l10n.liveCropSpeciesArchiveDescription(species.name)),
          actions: [
            TextButton(
              key: const ValueKey('live-crop-species-archive-cancel'),
              onPressed: () => Navigator.of(dialogContext).pop(false),
              child: Text(l10n.liveCropSpeciesArchiveCancel),
            ),
            FilledButton(
              key: const ValueKey('live-crop-species-archive-confirm'),
              onPressed: () => Navigator.of(dialogContext).pop(true),
              child: Text(l10n.liveCropSpeciesArchiveConfirm),
            ),
          ],
        );
      },
    );
    if (confirmed != true || !context.mounted) return;

    final saved = await _enqueueCropSpeciesArchive(
      ref: ref,
      scope: scope,
      selectedScope: selectedScope,
      species: species,
    );
    if (!context.mounted) return;
    if (saved) {
      _finishCropSave(context, ref, true);
    } else {
      showFarmToast(
        context,
        AppLocalizations.of(context).liveCropSpeciesArchiveFailed,
      );
    }
  }

  Future<void> _openTaskTemplateCreate(
    BuildContext context,
    WidgetRef ref,
    FarmlyLiveZone currentZone,
  ) async {
    final scope = data.scope;
    final selectedScope = data.selectedScope;
    if (scope == null || selectedScope == null) return;
    final saved = await showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      builder: (_) => _LiveTaskTemplateCreateSheet(
        scope: scope,
        selectedScope: selectedScope,
        zone: currentZone,
      ),
    );
    if (!context.mounted) return;
    _finishTaskSave(context, ref, saved);
  }

  Future<void> _openTaskTemplateWeekdayRepair(
    BuildContext context,
    WidgetRef ref,
    FarmlyLiveTaskTemplate template,
  ) async {
    final scope = data.scope;
    final selectedScope = data.selectedScope;
    if (scope == null || selectedScope == null) return;
    final saved = await showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      builder: (_) => _LiveTaskWeekdayRepairSheet(
        scope: scope,
        selectedScope: selectedScope,
        template: template,
      ),
    );
    if (!context.mounted || saved != true) return;
    ref.invalidate(syncStatusProvider);
    ref.invalidate(farmlyLiveZoneCollectionProvider);
    showFarmToast(
      context,
      AppLocalizations.of(context).liveTaskTransitionSavedPending,
    );
  }

  Future<void> _openPlantingCreate(
    BuildContext context,
    WidgetRef ref,
    FarmlyLiveZone currentZone,
    List<FarmlyLiveCropSpecies> species,
  ) async {
    final scope = data.scope;
    final selectedScope = data.selectedScope;
    if (scope == null || selectedScope == null) return;
    final saved = await showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      builder: (_) => _LivePlantingCreateSheet(
        scope: scope,
        selectedScope: selectedScope,
        zone: currentZone,
        species: species,
      ),
    );
    if (!context.mounted) return;
    _finishCropSave(context, ref, saved);
  }

  Future<void> _openPlantingUpdate(
    BuildContext context,
    WidgetRef ref,
    FarmlyLiveZone currentZone,
    FarmlyLivePlanting planting,
  ) async {
    final scope = data.scope;
    final selectedScope = data.selectedScope;
    if (scope == null ||
        selectedScope == null ||
        planting.planting.status == 'archived' ||
        planting.planting.version < 1 ||
        planting.syncState != FarmlyZoneSyncState.confirmed ||
        !planting.isUniqueConfirmedRecord ||
        planting.hasUnresolvedUpdate ||
        planting.hasUnresolvedArchive ||
        !_capturedPlantingIsCurrent(
          ref: ref,
          scope: scope,
          selectedScope: selectedScope,
          zone: currentZone,
          planting: planting,
        )) {
      return;
    }
    final saved = await showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      builder: (_) => _LivePlantingUpdateSheet(
        scope: scope,
        selectedScope: selectedScope,
        zone: currentZone,
        planting: planting,
      ),
    );
    if (!context.mounted) return;
    _finishCropSave(context, ref, saved);
  }

  Future<void> _openPlantingArchive(
    BuildContext context,
    WidgetRef ref,
    FarmlyLiveZone currentZone,
    FarmlyLivePlanting planting,
  ) async {
    final scope = data.scope;
    final selectedScope = data.selectedScope;
    final selectedFarm = selectedScope?.selectedFarm;
    if (scope == null ||
        selectedScope == null ||
        selectedFarm == null ||
        planting.planting.status == 'archived' ||
        planting.planting.version < 1 ||
        planting.syncState != FarmlyZoneSyncState.confirmed ||
        !planting.isUniqueConfirmedRecord ||
        planting.hasUnresolvedUpdate ||
        planting.hasUnresolvedArchive ||
        !_canManageCropSpecies(selectedScope, selectedFarm) ||
        !_capturedPlantingIsCurrent(
          ref: ref,
          scope: scope,
          selectedScope: selectedScope,
          zone: currentZone,
          planting: planting,
        )) {
      return;
    }

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) {
        final l10n = AppLocalizations.of(dialogContext);
        return AlertDialog(
          key: const ValueKey('live-planting-archive-dialog'),
          title: Text(l10n.livePlantingArchiveTitle),
          content: Text(l10n.livePlantingArchiveDescription),
          actions: [
            TextButton(
              key: const ValueKey('live-planting-archive-cancel'),
              onPressed: () => Navigator.of(dialogContext).pop(false),
              child: Text(l10n.livePlantingArchiveCancel),
            ),
            FilledButton.icon(
              key: const ValueKey('live-planting-archive-confirm'),
              onPressed: () => Navigator.of(dialogContext).pop(true),
              icon: const Icon(Icons.archive_outlined),
              label: Text(l10n.livePlantingArchiveConfirm),
            ),
          ],
        );
      },
    );
    if (confirmed != true || !context.mounted) return;

    final saved = await _enqueuePlantingArchive(
      ref: ref,
      scope: scope,
      selectedScope: selectedScope,
      zone: currentZone,
      planting: planting,
    );
    if (!context.mounted) return;
    if (saved) {
      _finishCropSave(context, ref, true);
      return;
    }
    showFarmToast(
      context,
      AppLocalizations.of(context).livePlantingArchiveFailed,
    );
  }

  Future<void> _openHarvestCreate(
    BuildContext context,
    WidgetRef ref,
    FarmlyLiveZone currentZone,
    FarmlyLivePlanting planting,
  ) async {
    final scope = data.scope;
    final selectedScope = data.selectedScope;
    if (scope == null || selectedScope == null) return;
    final saved = await showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      builder: (_) => _LiveHarvestCreateSheet(
        scope: scope,
        selectedScope: selectedScope,
        zone: currentZone,
        planting: planting,
      ),
    );
    if (!context.mounted) return;
    _finishCropSave(context, ref, saved);
  }

  Future<void> _openPlantingEventCreate(
    BuildContext context,
    WidgetRef ref,
    FarmlyLiveZone currentZone,
    FarmlyLivePlanting planting,
  ) async {
    final scope = data.scope;
    final selectedScope = data.selectedScope;
    if (scope == null || selectedScope == null) return;
    final saved = await showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      builder: (_) => _LivePlantingEventCreateSheet(
        scope: scope,
        selectedScope: selectedScope,
        zone: currentZone,
        planting: planting,
      ),
    );
    if (!context.mounted) return;
    _finishCropSave(context, ref, saved);
  }

  Future<void> _openHarvestActions(
    BuildContext context,
    WidgetRef ref,
    FarmlyLiveZone currentZone,
    FarmlyLiveHarvest harvest, {
    required bool canPropose,
    required bool canManage,
  }) async {
    final scope = data.scope;
    final selectedScope = data.selectedScope;
    if (scope == null || selectedScope == null) return;
    final saved = await showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      builder: (_) => _LiveHarvestActionsSheet(
        scope: scope,
        selectedScope: selectedScope,
        zone: currentZone,
        harvest: harvest,
        canPropose: canPropose,
        canManage: canManage,
      ),
    );
    if (!context.mounted) return;
    _finishCropSave(context, ref, saved);
  }

  Future<void> _openWaterTankCreate(
    BuildContext context,
    WidgetRef ref,
    FarmlyLiveZone currentZone,
  ) async {
    final scope = data.scope;
    final selectedScope = data.selectedScope;
    if (scope == null || selectedScope == null) return;
    final saved = await showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      builder: (_) => _LiveWaterTankCreateSheet(
        scope: scope,
        selectedScope: selectedScope,
        zone: currentZone,
      ),
    );
    if (!context.mounted) return;
    _finishWaterSave(context, ref, saved);
  }

  Future<void> _openWaterTankRename(
    BuildContext context,
    WidgetRef ref,
    FarmlyLiveZone currentZone,
    FarmlyLiveWaterTank tank,
  ) async {
    final scope = data.scope;
    final selectedScope = data.selectedScope;
    final selectedFarm = selectedScope?.selectedFarm;
    if (scope == null ||
        selectedScope == null ||
        selectedFarm == null ||
        !_canManageZones(selectedScope, selectedFarm) ||
        !_capturedWaterScopeIsCurrent(
          ref,
          scope,
          selectedScope,
          currentZone,
          tank: tank,
        ) ||
        tank.tank.version < 1 ||
        tank.syncState != FarmlyZoneSyncState.confirmed ||
        tank.hasUnresolvedNameUpdate ||
        !tank.isUniqueConfirmedRecord) {
      return;
    }
    final saved = await showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      builder: (_) => _LiveWaterTankRenameSheet(
        scope: scope,
        selectedScope: selectedScope,
        zone: currentZone,
        tank: tank,
      ),
    );
    if (!context.mounted) return;
    _finishWaterSave(context, ref, saved);
  }

  Future<void> _openWaterReadingCreate(
    BuildContext context,
    WidgetRef ref,
    FarmlyLiveZone currentZone,
    FarmlyLiveWaterTank tank,
  ) async {
    final scope = data.scope;
    final selectedScope = data.selectedScope;
    if (scope == null || selectedScope == null) return;
    final saved = await showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      builder: (_) => _LiveWaterReadingCreateSheet(
        scope: scope,
        selectedScope: selectedScope,
        zone: currentZone,
        tank: tank,
      ),
    );
    if (!context.mounted) return;
    _finishWaterSave(context, ref, saved);
  }

  Future<void> _openWaterUsageCreate(
    BuildContext context,
    WidgetRef ref,
    FarmlyLiveZone currentZone,
    FarmlyLiveWaterTank tank,
  ) async {
    final scope = data.scope;
    final selectedScope = data.selectedScope;
    if (scope == null || selectedScope == null) return;
    final saved = await showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      builder: (_) => _LiveWaterUsageCreateSheet(
        scope: scope,
        selectedScope: selectedScope,
        zone: currentZone,
        tank: tank,
      ),
    );
    if (!context.mounted) return;
    _finishWaterSave(context, ref, saved);
  }

  void _finishWaterSave(BuildContext context, WidgetRef ref, bool? saved) {
    if (saved != true || !context.mounted) return;
    ref.invalidate(syncStatusProvider);
    ref.invalidate(farmlyLiveZoneCollectionProvider);
    showFarmToast(context, AppLocalizations.of(context).liveFarmSavedPending);
  }

  void _finishCropSave(BuildContext context, WidgetRef ref, bool? saved) {
    if (saved != true || !context.mounted) return;
    ref.invalidate(syncStatusProvider);
    ref.invalidate(farmlyLiveZoneCollectionProvider);
    showFarmToast(context, AppLocalizations.of(context).liveFarmSavedPending);
  }

  void _finishTaskSave(BuildContext context, WidgetRef ref, bool? saved) {
    if (saved != true || !context.mounted) return;
    ref.invalidate(syncStatusProvider);
    ref.invalidate(farmlyLiveZoneCollectionProvider);
    showFarmToast(context, AppLocalizations.of(context).liveFarmSavedPending);
  }
}

class _LiveTaskTemplateCreateSheet extends ConsumerStatefulWidget {
  const _LiveTaskTemplateCreateSheet({
    required this.scope,
    required this.selectedScope,
    required this.zone,
  });

  final FarmlyMutationScope scope;
  final FarmlyOrganizationScope selectedScope;
  final FarmlyLiveZone zone;

  @override
  ConsumerState<_LiveTaskTemplateCreateSheet> createState() =>
      _LiveTaskTemplateCreateSheetState();
}

class _LiveTaskTemplateCreateSheetState
    extends ConsumerState<_LiveTaskTemplateCreateSheet> {
  final _titleController = TextEditingController();
  String _kind = 'general';
  String _frequency = 'daily';
  TimeOfDay _timeOfDay = const TimeOfDay(hour: 7, minute: 0);
  final Set<int> _daysOfWeek = {};
  String? _error;
  bool _saving = false;

  @override
  void dispose() {
    _titleController.dispose();
    super.dispose();
  }

  FarmlyLiveZoneCollection? _currentCollection() =>
      ref.read(farmlyLiveZoneCollectionProvider).asData?.value;

  FarmlyLiveZone? _currentZone() {
    for (final zone
        in _currentCollection()?.zones ?? const <FarmlyLiveZone>[]) {
      if (zone.zone.id == widget.zone.zone.id) return zone;
    }
    return null;
  }

  bool _scopeIsCurrent() {
    final accountId = ref
        .read(farmlyAuthSessionProvider)
        .asData
        ?.value
        ?.user
        .id;
    final currentSelection = ref.read(selectedOrganizationScopeProvider);
    final currentSyncScope = ref.read(farmlySyncScopeProvider).asData?.value;
    final currentCollection = _currentCollection();
    final currentFarm = currentSelection?.selectedFarm;
    final currentZone = _currentZone();
    final cacheIsWritable =
        currentCollection?.cacheState == FarmlyZoneCacheState.ready ||
        currentCollection?.cacheState == FarmlyZoneCacheState.notBootstrapped;
    return accountId == widget.scope.accountId &&
        _sameSelection(widget.selectedScope, currentSelection) &&
        _sameFarmScope(widget.scope, currentSyncScope) &&
        currentFarm != null &&
        currentFarm.status == FarmlyFarmStatus.active &&
        _canManageZones(currentSelection!, currentFarm) &&
        currentCollection?.canCreate == true &&
        cacheIsWritable &&
        _sameFarmScope(widget.scope, currentCollection?.scope) &&
        currentZone != null &&
        currentZone.zone.status == 'active' &&
        currentZone.syncState != FarmlyZoneSyncState.needsAttention;
  }

  Future<void> _chooseTime() async {
    final picked = await showTimePicker(
      context: context,
      initialTime: _timeOfDay,
      helpText: AppLocalizations.of(context).liveTaskTimeLabel,
    );
    if (picked != null && mounted) {
      setState(() {
        _timeOfDay = picked;
        _error = null;
      });
    }
  }

  Future<void> _save() async {
    if (_saving) return;
    final l10n = AppLocalizations.of(context);
    final title = _titleController.text.trim();
    if (title.isEmpty || title.runes.length > 160) {
      setState(() => _error = l10n.liveTaskTemplateTitleInvalid);
      return;
    }
    if (_frequency == 'weekly' && _daysOfWeek.isEmpty) {
      setState(() => _error = l10n.liveTaskWeekdaysRequired);
      return;
    }
    if (!_scopeIsCurrent()) {
      setState(() => _error = l10n.liveFarmScopeChanged);
      return;
    }

    setState(() {
      _saving = true;
      _error = null;
    });
    try {
      final engine = await ref.read(syncEngineProvider.future);
      if (!_scopeIsCurrent()) {
        setState(() => _error = l10n.liveFarmScopeChanged);
        return;
      }
      final snapshot = await engine.domainSnapshot(widget.scope);
      if (!_scopeIsCurrent()) {
        setState(() => _error = l10n.liveFarmScopeChanged);
        return;
      }
      if (snapshot != null &&
          (snapshot.cursor.continuityEpoch !=
                  widget.selectedScope.directory.continuityEpoch ||
              snapshot.cursor.scopePolicyVersion !=
                  widget.selectedScope.directory.scopePolicyVersion)) {
        setState(() => _error = l10n.liveFarmScopeChanged);
        return;
      }

      final entries = await engine.entries(
        accountId: widget.scope.accountId,
        organizationId: widget.scope.organizationId,
      );
      if (!_scopeIsCurrent()) {
        setState(() => _error = l10n.liveFarmScopeChanged);
        return;
      }
      final currentZone = _currentZone();
      if (currentZone == null) {
        setState(() => _error = l10n.liveFarmScopeChanged);
        return;
      }
      String? zoneDependency;
      final zoneRecord = snapshot?.recordsFor('zone')[currentZone.zone.id];
      if (zoneRecord is Map) {
        if (zoneRecord['status'] != 'active') {
          setState(() => _error = l10n.liveFarmScopeChanged);
          return;
        }
      } else {
        final parentOperationId = currentZone.operationId;
        final parentEntry = parentOperationId == null
            ? null
            : entries.where((entry) {
                final intent = entry.mutation.intent;
                return entry.operationId == parentOperationId &&
                    intent.type == 'zone.create' &&
                    intent.resourceId == currentZone.zone.id &&
                    _entryMatchesScope(entry, widget.scope);
              }).firstOrNull;
        if (parentEntry == null) {
          setState(() => _error = l10n.liveFarmScopeChanged);
          return;
        }
        zoneDependency = parentEntry.operationId;
      }

      final intent = FarmlyCreateTaskTemplateIntent(
        operationId: newFarmlyOperationId(),
        continuityEpoch: widget.scope.continuityEpoch,
        resourceId: newFarmlyOperationId(),
        title: title,
        kind: _kind,
        zoneId: currentZone.zone.id,
        frequency: _frequency,
        timeOfDay:
            '${_timeOfDay.hour.toString().padLeft(2, '0')}:'
            '${_timeOfDay.minute.toString().padLeft(2, '0')}',
        daysOfWeek: _daysOfWeek.toList()..sort(),
        dependsOn: [?zoneDependency],
      );
      if (!_scopeIsCurrent()) {
        setState(() => _error = l10n.liveFarmScopeChanged);
        return;
      }
      await engine.enqueue(
        FarmlyScopedMutation(scope: widget.scope, intent: intent),
      );
      ref.invalidate(syncStatusProvider);
      ref.invalidate(farmlyLiveZoneCollectionProvider);
      if (mounted) Navigator.of(context).pop(true);
    } on FormatException {
      if (mounted) {
        setState(() => _error = l10n.liveTaskTemplateTitleInvalid);
      }
    } on ArgumentError {
      if (mounted) {
        setState(() => _error = l10n.liveTaskTemplateTitleInvalid);
      }
    } catch (_) {
      if (mounted) setState(() => _error = l10n.liveTaskTemplateSaveFailed);
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final scopeCurrent = _scopeIsCurrent();
    final kinds = <String, String>{
      'general': l10n.liveTaskKindGeneral,
      'feeding': l10n.liveTaskKindFeeding,
      'irrigation': l10n.liveTaskKindIrrigation,
    };
    return Padding(
      padding: EdgeInsets.only(bottom: MediaQuery.viewInsetsOf(context).bottom),
      child: SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(
          FarmSpacing.lg,
          FarmSpacing.lg,
          FarmSpacing.lg,
          FarmSpacing.xl,
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(
              l10n.liveTaskTemplateDialogTitle,
              style: Theme.of(context).textTheme.titleLarge,
            ),
            const SizedBox(height: FarmSpacing.xs),
            Text(l10n.liveTaskTemplateForZone(widget.zone.zone.name)),
            const SizedBox(height: FarmSpacing.md),
            TextField(
              key: const ValueKey('live-task-template-title'),
              controller: _titleController,
              enabled: scopeCurrent && !_saving,
              textCapitalization: TextCapitalization.sentences,
              decoration: InputDecoration(
                labelText: l10n.liveTaskTemplateTitleLabel,
                hintText: l10n.liveTaskTemplateTitleHint,
              ),
              onChanged: (_) => setState(() => _error = null),
            ),
            const SizedBox(height: FarmSpacing.md),
            DropdownButtonFormField<String>(
              key: const ValueKey('live-task-template-kind'),
              initialValue: _kind,
              decoration: InputDecoration(labelText: l10n.liveTaskKindLabel),
              items: [
                for (final entry in kinds.entries)
                  DropdownMenuItem(value: entry.key, child: Text(entry.value)),
              ],
              onChanged: !scopeCurrent || _saving
                  ? null
                  : (value) => setState(() {
                      _kind = value ?? 'general';
                      _error = null;
                    }),
            ),
            const SizedBox(height: FarmSpacing.md),
            DropdownButtonFormField<String>(
              key: const ValueKey('live-task-template-frequency'),
              initialValue: _frequency,
              decoration: InputDecoration(
                labelText: l10n.liveTaskFrequencyLabel,
              ),
              items: [
                DropdownMenuItem(
                  value: 'daily',
                  child: Text(l10n.liveTaskFrequencyDaily),
                ),
                DropdownMenuItem(
                  value: 'weekly',
                  child: Text(l10n.liveTaskFrequencyWeekly),
                ),
              ],
              onChanged: !scopeCurrent || _saving
                  ? null
                  : (value) => setState(() {
                      _frequency = value ?? 'daily';
                      _daysOfWeek.clear();
                      _error = null;
                    }),
            ),
            const SizedBox(height: FarmSpacing.md),
            OutlinedButton.icon(
              key: const ValueKey('live-task-template-time'),
              onPressed: !scopeCurrent || _saving ? null : _chooseTime,
              icon: const Icon(Icons.schedule_outlined),
              label: Text(
                '${l10n.liveTaskTimeChoose}: ${_timeOfDay.format(context)}',
              ),
            ),
            const SizedBox(height: FarmSpacing.xs),
            Text(
              l10n.liveTaskTimeFarmLocalNote,
              style: Theme.of(context).textTheme.bodySmall,
            ),
            if (_frequency == 'weekly') ...[
              const SizedBox(height: FarmSpacing.md),
              Text(
                l10n.liveTaskWeekdaysLabel,
                style: Theme.of(context).textTheme.titleSmall,
              ),
              const SizedBox(height: FarmSpacing.xs),
              Wrap(
                spacing: FarmSpacing.xs,
                runSpacing: FarmSpacing.xs,
                children: [
                  for (var day = 0; day <= 6; day++)
                    FilterChip(
                      key: ValueKey('live-task-weekday-$day'),
                      label: Text(_taskWeekdayLabel(l10n, day)),
                      selected: _daysOfWeek.contains(day),
                      onSelected: !scopeCurrent || _saving
                          ? null
                          : (selected) => setState(() {
                              if (selected) {
                                _daysOfWeek.add(day);
                              } else {
                                _daysOfWeek.remove(day);
                              }
                            }),
                    ),
                ],
              ),
            ],
            if (_error != null) ...[
              const SizedBox(height: FarmSpacing.sm),
              Text(
                _error!,
                style: TextStyle(
                  color: FarmThemeExtension.of(context).semanticWarning,
                ),
              ),
            ],
            const SizedBox(height: FarmSpacing.lg),
            FilledButton.icon(
              key: const ValueKey('live-task-template-save'),
              onPressed: !scopeCurrent || _saving ? null : _save,
              icon: _saving
                  ? const SizedBox.square(
                      dimension: 18,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : const Icon(Icons.save_outlined),
              label: Text(l10n.liveTaskTemplateSave),
            ),
          ],
        ),
      ),
    );
  }
}

class _LiveTaskWeekdayRepairSheet extends ConsumerStatefulWidget {
  const _LiveTaskWeekdayRepairSheet({
    required this.scope,
    required this.selectedScope,
    required this.template,
  });

  final FarmlyMutationScope scope;
  final FarmlyOrganizationScope selectedScope;
  final FarmlyLiveTaskTemplate template;

  @override
  ConsumerState<_LiveTaskWeekdayRepairSheet> createState() =>
      _LiveTaskWeekdayRepairSheetState();
}

class _LiveTaskWeekdayRepairSheetState
    extends ConsumerState<_LiveTaskWeekdayRepairSheet> {
  final Set<int> _daysOfWeek = {};
  bool _saving = false;
  String? _error;

  bool _scopeIsCurrent() =>
      _capturedFarmScopeIsCurrent(ref, widget.scope, widget.selectedScope) &&
      ref.read(farmlyLiveZoneCollectionProvider).asData?.value.cacheState ==
          FarmlyZoneCacheState.ready;

  Future<void> _save() async {
    if (_saving) return;
    final l10n = AppLocalizations.of(context);
    if (_daysOfWeek.isEmpty) {
      setState(() => _error = l10n.liveTaskWeekdaysRequired);
      return;
    }
    if (!_scopeIsCurrent()) {
      setState(() => _error = l10n.liveFarmScopeChanged);
      return;
    }
    setState(() {
      _saving = true;
      _error = null;
    });
    try {
      final engine = await ref.read(syncEngineProvider.future);
      if (!_scopeIsCurrent()) {
        setState(() => _error = l10n.liveFarmScopeChanged);
        return;
      }
      final snapshot = await engine.domainSnapshot(widget.scope);
      if (!_scopeIsCurrent() ||
          snapshot == null ||
          snapshot.cursor.continuityEpoch !=
              widget.selectedScope.directory.continuityEpoch ||
          snapshot.cursor.scopePolicyVersion !=
              widget.selectedScope.directory.scopePolicyVersion) {
        setState(() => _error = l10n.liveFarmScopeChanged);
        return;
      }
      final row = snapshot.recordsFor('taskTemplate')[widget.template.id];
      if (row is! Map) {
        setState(() => _error = l10n.liveFarmScopeChanged);
        return;
      }
      final currentTemplate = _farmlyLiveTaskTemplateFromJson(
        Map<String, dynamic>.from(row),
        syncState: FarmlyZoneSyncState.confirmed,
      );
      if (currentTemplate.version != widget.template.version ||
          currentTemplate.status != 'active' ||
          currentTemplate.frequency != 'weekly' ||
          currentTemplate.daysOfWeek.isNotEmpty ||
          currentTemplate.zoneId != widget.template.zoneId) {
        setState(() => _error = l10n.liveFarmScopeChanged);
        return;
      }

      final entries = await engine.entries(
        accountId: widget.scope.accountId,
        organizationId: widget.scope.organizationId,
      );
      if (!_scopeIsCurrent()) {
        setState(() => _error = l10n.liveFarmScopeChanged);
        return;
      }
      for (final entry in entries) {
        final intent = entry.mutation.intent;
        if (!_entryMatchesScope(entry, widget.scope) ||
            intent.type != 'taskTemplate.update' ||
            intent.resourceId != currentTemplate.id) {
          continue;
        }
        if (entry.status != OutboxEntryStatus.applied ||
            currentTemplate.version <= (intent.baseVersion ?? 0)) {
          setState(() => _error = l10n.liveTaskTemplateSaveFailed);
          return;
        }
      }

      final intent = FarmlyUpdateTaskTemplateScheduleIntent(
        operationId: newFarmlyOperationId(),
        continuityEpoch: widget.scope.continuityEpoch,
        resourceId: currentTemplate.id,
        baseVersion: currentTemplate.version,
        frequency: currentTemplate.frequency,
        timeOfDay: currentTemplate.timeOfDay,
        daysOfWeek: _daysOfWeek.toList()..sort(),
      );
      if (!_scopeIsCurrent()) {
        setState(() => _error = l10n.liveFarmScopeChanged);
        return;
      }
      await engine.enqueue(
        FarmlyScopedMutation(scope: widget.scope, intent: intent),
      );
      if (mounted) Navigator.of(context).pop(true);
    } on Object {
      if (mounted) setState(() => _error = l10n.liveTaskTemplateSaveFailed);
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final scopeCurrent = _scopeIsCurrent();
    return Padding(
      padding: EdgeInsets.only(bottom: MediaQuery.viewInsetsOf(context).bottom),
      child: SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(
          FarmSpacing.lg,
          FarmSpacing.lg,
          FarmSpacing.lg,
          FarmSpacing.xl,
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(
              l10n.liveTaskWeekdayRepair,
              style: Theme.of(context).textTheme.titleLarge,
            ),
            const SizedBox(height: FarmSpacing.xs),
            Text(widget.template.title),
            const SizedBox(height: FarmSpacing.md),
            Text(
              l10n.liveTaskWeekdaysLabel,
              style: Theme.of(context).textTheme.titleSmall,
            ),
            const SizedBox(height: FarmSpacing.xs),
            Wrap(
              spacing: FarmSpacing.xs,
              runSpacing: FarmSpacing.xs,
              children: [
                for (var day = 0; day <= 6; day++)
                  FilterChip(
                    key: ValueKey('live-task-repair-weekday-$day'),
                    label: Text(_taskWeekdayLabel(l10n, day)),
                    selected: _daysOfWeek.contains(day),
                    onSelected: !scopeCurrent || _saving
                        ? null
                        : (selected) => setState(() {
                            if (selected) {
                              _daysOfWeek.add(day);
                            } else {
                              _daysOfWeek.remove(day);
                            }
                            _error = null;
                          }),
                  ),
              ],
            ),
            if (_error != null) ...[
              const SizedBox(height: FarmSpacing.sm),
              Text(
                _error!,
                style: TextStyle(
                  color: FarmThemeExtension.of(context).semanticWarning,
                ),
              ),
            ],
            const SizedBox(height: FarmSpacing.lg),
            FilledButton.icon(
              key: const ValueKey('live-task-template-repair-save'),
              onPressed: !scopeCurrent || _saving ? null : _save,
              icon: _saving
                  ? const SizedBox.square(
                      dimension: 18,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : const Icon(Icons.save_outlined),
              label: Text(l10n.liveTaskTemplateSave),
            ),
          ],
        ),
      ),
    );
  }
}

class _LiveCropSpeciesCreateSheet extends ConsumerStatefulWidget {
  const _LiveCropSpeciesCreateSheet({
    required this.scope,
    required this.selectedScope,
  });

  final FarmlyMutationScope scope;
  final FarmlyOrganizationScope selectedScope;

  @override
  ConsumerState<_LiveCropSpeciesCreateSheet> createState() =>
      _LiveCropSpeciesCreateSheetState();
}

class _LiveCropSpeciesCreateSheetState
    extends ConsumerState<_LiveCropSpeciesCreateSheet> {
  final _name = TextEditingController();
  String _unit = 'kg';
  String? _error;
  bool _saving = false;

  @override
  void dispose() {
    _name.dispose();
    super.dispose();
  }

  bool _scopeIsCurrent() =>
      _capturedFarmScopeIsCurrent(ref, widget.scope, widget.selectedScope);

  Future<void> _save() async {
    if (_saving) return;
    final l10n = AppLocalizations.of(context);
    final name = _name.text.trim();
    if (name.isEmpty) {
      setState(() => _error = l10n.liveCropSpeciesNameRequired);
      return;
    }
    if (name.length > 160) {
      setState(() => _error = l10n.liveCropSpeciesNameTooLong);
      return;
    }
    if (!_scopeIsCurrent()) {
      setState(() => _error = l10n.liveFarmScopeChanged);
      return;
    }

    setState(() {
      _saving = true;
      _error = null;
    });
    try {
      final session = await ref.read(farmlyAuthSessionProvider.future);
      final engine = await ref.read(syncEngineProvider.future);
      if (session == null ||
          session.user.id != widget.scope.accountId ||
          !_scopeIsCurrent()) {
        throw StateError('Farm scope changed before local save');
      }
      await engine.enqueue(
        FarmlyScopedMutation(
          scope: widget.scope,
          intent: FarmlyCreateCropSpeciesIntent(
            operationId: newFarmlyOperationId(),
            continuityEpoch: widget.scope.continuityEpoch,
            resourceId: newFarmlyOperationId(),
            name: name,
            harvestUnit: _unit,
          ),
        ),
      );
      ref.invalidate(syncStatusProvider);
      ref.invalidate(farmlyLiveZoneCollectionProvider);
      if (mounted) Navigator.of(context).pop(true);
    } on Object {
      if (!mounted) return;
      setState(
        () => _error = _scopeIsCurrent()
            ? l10n.liveCropSpeciesSaveFailed
            : l10n.liveFarmScopeChanged,
      );
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    ref.watch(selectedOrganizationScopeProvider);
    ref.watch(farmlySyncScopeProvider);
    ref.watch(farmlyAuthSessionProvider);
    final l10n = AppLocalizations.of(context);
    final tokens = FarmThemeExtension.of(context);
    final scopeCurrent = _scopeIsCurrent();
    return SafeArea(
      child: SingleChildScrollView(
        padding: EdgeInsets.fromLTRB(
          FarmSpacing.lg,
          FarmSpacing.sm,
          FarmSpacing.lg,
          FarmSpacing.lg + MediaQuery.viewInsetsOf(context).bottom,
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(
              l10n.liveCropSpeciesCreate,
              style: Theme.of(context).textTheme.titleLarge,
            ),
            const SizedBox(height: FarmSpacing.md),
            TextField(
              key: const ValueKey('live-crop-species-name'),
              controller: _name,
              autofocus: true,
              enabled: !_saving && scopeCurrent,
              maxLength: 160,
              decoration: InputDecoration(
                labelText: l10n.liveCropSpeciesNameLabel,
                errorText: _error,
              ),
              onSubmitted: (_) => _save(),
            ),
            const SizedBox(height: FarmSpacing.sm),
            DropdownButtonFormField<String>(
              key: const ValueKey('live-crop-species-unit'),
              initialValue: _unit,
              decoration: InputDecoration(
                labelText: l10n.liveCropSpeciesUnitLabel,
              ),
              items: [
                DropdownMenuItem(
                  value: 'kg',
                  child: Text(l10n.cropHarvestUnitKg),
                ),
                DropdownMenuItem(
                  value: 'litre',
                  child: Text(l10n.cropHarvestUnitLitre),
                ),
                DropdownMenuItem(
                  value: 'pieces',
                  child: Text(l10n.cropHarvestUnitPieces),
                ),
              ],
              onChanged: !_saving && scopeCurrent
                  ? (value) => setState(() => _unit = value ?? 'kg')
                  : null,
            ),
            if (!scopeCurrent) ...[
              const SizedBox(height: FarmSpacing.md),
              Text(
                l10n.liveFarmScopeChanged,
                style: TextStyle(color: tokens.semanticWarning),
              ),
            ],
            const SizedBox(height: FarmSpacing.lg),
            FilledButton(
              key: const ValueKey('live-crop-species-save'),
              onPressed: _saving || !scopeCurrent ? null : _save,
              child: Text(l10n.saveOnDevice),
            ),
          ],
        ),
      ),
    );
  }
}

class _LiveZoneRenameSheet extends ConsumerStatefulWidget {
  const _LiveZoneRenameSheet({
    required this.scope,
    required this.selectedScope,
    required this.zone,
  });

  final FarmlyMutationScope scope;
  final FarmlyOrganizationScope selectedScope;
  final FarmlyZoneDto zone;

  @override
  ConsumerState<_LiveZoneRenameSheet> createState() =>
      _LiveZoneRenameSheetState();
}

class _LiveZoneRenameSheetState extends ConsumerState<_LiveZoneRenameSheet> {
  late final TextEditingController _name = TextEditingController(
    text: widget.zone.name,
  );
  String? _error;
  bool _saving = false;

  @override
  void dispose() {
    _name.dispose();
    super.dispose();
  }

  bool _scopeIsCurrent() =>
      _capturedFarmScopeIsCurrent(ref, widget.scope, widget.selectedScope);

  Future<void> _save() async {
    if (_saving) return;
    final l10n = AppLocalizations.of(context);
    final name = _name.text.trim();
    if (name.isEmpty) {
      setState(() => _error = l10n.liveZoneRenameNameRequired);
      return;
    }
    if (name.length > 160) {
      setState(() => _error = l10n.liveZoneRenameNameTooLong);
      return;
    }
    if (name == widget.zone.name) {
      Navigator.of(context).pop(false);
      return;
    }
    if (!_scopeIsCurrent()) {
      setState(() => _error = l10n.liveFarmScopeChanged);
      return;
    }

    setState(() {
      _saving = true;
      _error = null;
    });
    try {
      final saved = await _enqueueZoneNameUpdate(
        ref: ref,
        scope: widget.scope,
        selectedScope: widget.selectedScope,
        zone: widget.zone,
        name: name,
      );
      if (!mounted) return;
      if (saved) {
        Navigator.of(context).pop(true);
      } else {
        setState(
          () => _error = _scopeIsCurrent()
              ? l10n.liveZoneRenameSaveFailed
              : l10n.liveFarmScopeChanged,
        );
      }
    } on Object {
      if (!mounted) return;
      setState(
        () => _error = _scopeIsCurrent()
            ? l10n.liveZoneRenameSaveFailed
            : l10n.liveFarmScopeChanged,
      );
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    ref.watch(selectedOrganizationScopeProvider);
    ref.watch(farmlySyncScopeProvider);
    ref.watch(farmlyAuthSessionProvider);
    final l10n = AppLocalizations.of(context);
    final scopeCurrent = _scopeIsCurrent();
    return SafeArea(
      child: SingleChildScrollView(
        padding: EdgeInsets.fromLTRB(
          FarmSpacing.lg,
          FarmSpacing.sm,
          FarmSpacing.lg,
          FarmSpacing.lg + MediaQuery.viewInsetsOf(context).bottom,
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(
              l10n.liveZoneRenameTitle,
              style: Theme.of(context).textTheme.titleLarge,
            ),
            const SizedBox(height: FarmSpacing.md),
            TextField(
              key: const ValueKey('live-zone-edit-name-field'),
              controller: _name,
              enabled: scopeCurrent && !_saving,
              maxLength: 160,
              textCapitalization: TextCapitalization.sentences,
              decoration: InputDecoration(
                labelText: l10n.liveZoneRenameNameLabel,
                errorText: _error,
                counterText: '',
              ),
            ),
            const SizedBox(height: FarmSpacing.md),
            FilledButton.icon(
              key: const ValueKey('live-zone-edit-name-save'),
              onPressed: scopeCurrent && !_saving ? _save : null,
              icon: _saving
                  ? const SizedBox.square(
                      dimension: 18,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : const Icon(Icons.save_outlined),
              label: Text(l10n.liveZoneRenameSave),
            ),
            if (!scopeCurrent) ...[
              const SizedBox(height: FarmSpacing.sm),
              Text(
                l10n.liveFarmScopeChanged,
                style: TextStyle(
                  color: FarmThemeExtension.of(context).semanticWarning,
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

class _LiveCropSpeciesRenameSheet extends ConsumerStatefulWidget {
  const _LiveCropSpeciesRenameSheet({
    required this.scope,
    required this.selectedScope,
    required this.species,
  });

  final FarmlyMutationScope scope;
  final FarmlyOrganizationScope selectedScope;
  final FarmlyCropSpeciesDto species;

  @override
  ConsumerState<_LiveCropSpeciesRenameSheet> createState() =>
      _LiveCropSpeciesRenameSheetState();
}

class _LiveCropSpeciesRenameSheetState
    extends ConsumerState<_LiveCropSpeciesRenameSheet> {
  late final TextEditingController _name = TextEditingController(
    text: widget.species.name,
  );
  String? _error;
  bool _saving = false;

  @override
  void dispose() {
    _name.dispose();
    super.dispose();
  }

  bool _scopeIsCurrent() =>
      _capturedFarmScopeIsCurrent(ref, widget.scope, widget.selectedScope);

  Future<void> _save() async {
    if (_saving) return;
    final l10n = AppLocalizations.of(context);
    final name = _name.text.trim();
    if (name.isEmpty) {
      setState(() => _error = l10n.liveCropSpeciesNameRequired);
      return;
    }
    if (name.length > 160) {
      setState(() => _error = l10n.liveCropSpeciesNameTooLong);
      return;
    }
    if (name == widget.species.name) {
      Navigator.of(context).pop(false);
      return;
    }
    if (!_scopeIsCurrent()) {
      setState(() => _error = l10n.liveFarmScopeChanged);
      return;
    }

    setState(() {
      _saving = true;
      _error = null;
    });
    try {
      final saved = await _enqueueCropSpeciesNameUpdate(
        ref: ref,
        scope: widget.scope,
        selectedScope: widget.selectedScope,
        species: widget.species,
        name: name,
      );
      if (!mounted) return;
      if (saved) {
        ref.invalidate(syncStatusProvider);
        ref.invalidate(farmlyLiveZoneCollectionProvider);
        Navigator.of(context).pop(true);
      } else {
        setState(
          () => _error = _scopeIsCurrent()
              ? l10n.liveCropSpeciesRenameFailed
              : l10n.liveFarmScopeChanged,
        );
      }
    } on Object {
      if (!mounted) return;
      setState(
        () => _error = _scopeIsCurrent()
            ? l10n.liveCropSpeciesRenameFailed
            : l10n.liveFarmScopeChanged,
      );
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    ref.watch(selectedOrganizationScopeProvider);
    ref.watch(farmlySyncScopeProvider);
    ref.watch(farmlyAuthSessionProvider);
    final l10n = AppLocalizations.of(context);
    final tokens = FarmThemeExtension.of(context);
    final scopeCurrent = _scopeIsCurrent();
    return SafeArea(
      child: SingleChildScrollView(
        padding: EdgeInsets.fromLTRB(
          FarmSpacing.lg,
          FarmSpacing.sm,
          FarmSpacing.lg,
          FarmSpacing.lg + MediaQuery.viewInsetsOf(context).bottom,
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(
              l10n.liveCropSpeciesRenameTitle,
              style: Theme.of(context).textTheme.titleLarge,
            ),
            const SizedBox(height: FarmSpacing.md),
            TextField(
              key: const ValueKey('live-crop-species-edit-name'),
              controller: _name,
              autofocus: true,
              enabled: !_saving && scopeCurrent,
              maxLength: 160,
              textCapitalization: TextCapitalization.sentences,
              textInputAction: TextInputAction.done,
              decoration: InputDecoration(
                labelText: l10n.liveCropSpeciesNameLabel,
                errorText: _error,
              ),
              onSubmitted: (_) {
                if (!_saving && scopeCurrent) _save();
              },
            ),
            if (!scopeCurrent) ...[
              const SizedBox(height: FarmSpacing.md),
              Text(
                l10n.liveFarmScopeChanged,
                style: TextStyle(color: tokens.semanticWarning),
              ),
            ],
            const SizedBox(height: FarmSpacing.lg),
            SizedBox(
              height: 52,
              child: FilledButton(
                key: const ValueKey('live-crop-species-edit-save'),
                onPressed: _saving || !scopeCurrent ? null : _save,
                child: Text(l10n.saveOnDevice),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _LivePlantingCreateSheet extends ConsumerStatefulWidget {
  const _LivePlantingCreateSheet({
    required this.scope,
    required this.selectedScope,
    required this.zone,
    required this.species,
  });

  final FarmlyMutationScope scope;
  final FarmlyOrganizationScope selectedScope;
  final FarmlyLiveZone zone;
  final List<FarmlyLiveCropSpecies> species;

  @override
  ConsumerState<_LivePlantingCreateSheet> createState() =>
      _LivePlantingCreateSheetState();
}

class _LivePlantingCreateSheetState
    extends ConsumerState<_LivePlantingCreateSheet> {
  final _areaM2 = TextEditingController();
  late String? _speciesId = widget.species.isEmpty
      ? null
      : widget.species.first.species.id;
  DateTime? _sowingDate;
  DateTime? _expectedHarvestDate;
  String? _error;
  bool _saving = false;

  @override
  void dispose() {
    _areaM2.dispose();
    super.dispose();
  }

  bool _scopeIsCurrent() =>
      _capturedFarmScopeIsCurrent(ref, widget.scope, widget.selectedScope) &&
      widget.zone.syncState != FarmlyZoneSyncState.needsAttention;

  Future<DateTime?> _pickDate({
    required String helpText,
    required DateTime? selectedDate,
    DateTime? firstDate,
  }) => showDatePicker(
    context: context,
    initialDate: selectedDate ?? firstDate ?? DateTime.now(),
    firstDate: firstDate ?? DateTime(1900),
    lastDate: DateTime(9999, 12, 31),
    initialEntryMode: DatePickerEntryMode.calendar,
    helpText: helpText,
  );

  Future<void> _pickSowingDate() async {
    final picked = await _pickDate(
      helpText: AppLocalizations.of(context).livePlantingSowingDateLabel,
      selectedDate: _sowingDate,
    );
    if (picked != null && mounted) {
      setState(() {
        _sowingDate = picked;
        if (_expectedHarvestDate != null &&
            _expectedHarvestDate!.isBefore(picked)) {
          _expectedHarvestDate = null;
        }
        _error = null;
      });
    }
  }

  Future<void> _pickExpectedHarvestDate() async {
    final firstDate = _sowingDate ?? DateTime(1900);
    final selected = _expectedHarvestDate;
    final picked = await _pickDate(
      helpText: AppLocalizations.of(
        context,
      ).livePlantingExpectedHarvestDateLabel,
      selectedDate: selected != null && !selected.isBefore(firstDate)
          ? selected
          : firstDate,
      firstDate: firstDate,
    );
    if (picked != null && mounted) {
      setState(() {
        _expectedHarvestDate = picked;
        _error = null;
      });
    }
  }

  String? _validate(AppLocalizations l10n) {
    if (!_scopeIsCurrent()) return l10n.liveFarmScopeChanged;
    if (_speciesId == null ||
        !widget.species.any((item) => item.species.id == _speciesId)) {
      return l10n.livePlantingNeedsSpecies;
    }
    if (_sowingDate == null) return l10n.livePlantingSowingDateRequired;
    if (_expectedHarvestDate != null &&
        _expectedHarvestDate!.isBefore(_sowingDate!)) {
      return l10n.livePlantingExpectedHarvestInvalid;
    }
    final area = _areaM2.text.trim().replaceAll(',', '.');
    if (area.isNotEmpty &&
        !RegExp(r'^(0|[1-9][0-9]{0,11})(\.[0-9]{1,2})?$').hasMatch(area)) {
      return l10n.livePlantingAreaInvalid;
    }
    return null;
  }

  Future<void> _save() async {
    if (_saving) return;
    final l10n = AppLocalizations.of(context);
    final validation = _validate(l10n);
    if (validation != null) {
      setState(() => _error = validation);
      return;
    }

    setState(() {
      _saving = true;
      _error = null;
    });
    try {
      final session = await ref.read(farmlyAuthSessionProvider.future);
      final engine = await ref.read(syncEngineProvider.future);
      if (session == null ||
          session.user.id != widget.scope.accountId ||
          !_scopeIsCurrent()) {
        throw StateError('Farm scope changed before local save');
      }
      final species = widget.species.firstWhere(
        (item) => item.species.id == _speciesId,
      );
      final dependencies = <String>{};
      final plotOperationId = widget.zone.operationId;
      if (plotOperationId != null) dependencies.add(plotOperationId);
      final speciesOperationId = species.operationId;
      if (speciesOperationId != null) dependencies.add(speciesOperationId);
      final area = _areaM2.text.trim().replaceAll(',', '.');
      await engine.enqueue(
        FarmlyScopedMutation(
          scope: widget.scope,
          intent: FarmlyCreatePlantingIntent(
            operationId: newFarmlyOperationId(),
            continuityEpoch: widget.scope.continuityEpoch,
            resourceId: newFarmlyOperationId(),
            cropSpeciesId: species.species.id,
            plotId: widget.zone.zone.id,
            sowingDate: _formatCivilDate(_sowingDate!),
            expectedHarvestDate: _expectedHarvestDate == null
                ? null
                : _formatCivilDate(_expectedHarvestDate!),
            areaM2: area.isEmpty ? null : area,
            dependsOn: dependencies.toList(growable: false),
          ),
        ),
      );
      ref.invalidate(syncStatusProvider);
      ref.invalidate(farmlyLiveZoneCollectionProvider);
      if (mounted) Navigator.of(context).pop(true);
    } on Object {
      if (!mounted) return;
      setState(
        () => _error = _scopeIsCurrent()
            ? l10n.livePlantingSaveFailed
            : l10n.liveFarmScopeChanged,
      );
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    ref.watch(selectedOrganizationScopeProvider);
    ref.watch(farmlySyncScopeProvider);
    ref.watch(farmlyAuthSessionProvider);
    final l10n = AppLocalizations.of(context);
    final tokens = FarmThemeExtension.of(context);
    final scopeCurrent = _scopeIsCurrent();
    final dateLabels = MaterialLocalizations.of(context);
    return SafeArea(
      child: SingleChildScrollView(
        padding: EdgeInsets.fromLTRB(
          FarmSpacing.lg,
          FarmSpacing.sm,
          FarmSpacing.lg,
          FarmSpacing.lg + MediaQuery.viewInsetsOf(context).bottom,
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(
              l10n.livePlantingCreate,
              style: Theme.of(context).textTheme.titleLarge,
            ),
            const SizedBox(height: FarmSpacing.sm),
            Text(
              '${widget.zone.zone.name} · ${widget.selectedScope.selectedFarm?.name ?? ''}',
              style: Theme.of(
                context,
              ).textTheme.bodySmall?.copyWith(color: tokens.textSecondary),
            ),
            const SizedBox(height: FarmSpacing.lg),
            DropdownButtonFormField<String>(
              key: const ValueKey('live-planting-species'),
              initialValue: _speciesId,
              decoration: InputDecoration(
                labelText: l10n.livePlantingSpeciesLabel,
              ),
              items: [
                for (final item in widget.species)
                  DropdownMenuItem(
                    value: item.species.id,
                    child: Text(item.species.name),
                  ),
              ],
              onChanged: !_saving && scopeCurrent
                  ? (value) => setState(() => _speciesId = value)
                  : null,
            ),
            const SizedBox(height: FarmSpacing.md),
            _DatePickerField(
              key: const ValueKey('live-planting-sowing-date'),
              label: l10n.livePlantingSowingDateLabel,
              value: _sowingDate == null
                  ? null
                  : dateLabels.formatMediumDate(_sowingDate!),
              enabled: !_saving && scopeCurrent,
              onTap: _pickSowingDate,
            ),
            const SizedBox(height: FarmSpacing.md),
            _DatePickerField(
              key: const ValueKey('live-planting-expected-harvest-date'),
              label: l10n.livePlantingExpectedHarvestDateLabel,
              value: _expectedHarvestDate == null
                  ? null
                  : dateLabels.formatMediumDate(_expectedHarvestDate!),
              enabled: !_saving && scopeCurrent,
              onTap: _pickExpectedHarvestDate,
            ),
            const SizedBox(height: FarmSpacing.md),
            DecimalField(
              key: const ValueKey('live-planting-area-m2'),
              controller: _areaM2,
              labelText: l10n.livePlantingAreaLabel,
              hintText: l10n.livePlantingAreaHint,
              helperText: l10n.livePlantingAreaHelper,
            ),
            if (_error != null) ...[
              const SizedBox(height: FarmSpacing.sm),
              Text(_error!, style: TextStyle(color: tokens.semanticWarning)),
            ],
            if (!scopeCurrent) ...[
              const SizedBox(height: FarmSpacing.md),
              Text(
                l10n.liveFarmScopeChanged,
                style: TextStyle(color: tokens.semanticWarning),
              ),
            ],
            const SizedBox(height: FarmSpacing.lg),
            FilledButton(
              key: const ValueKey('live-planting-save'),
              onPressed: _saving || !scopeCurrent ? null : _save,
              child: Text(l10n.saveOnDevice),
            ),
          ],
        ),
      ),
    );
  }
}

class _LivePlantingUpdateSheet extends ConsumerStatefulWidget {
  const _LivePlantingUpdateSheet({
    required this.scope,
    required this.selectedScope,
    required this.zone,
    required this.planting,
  });

  final FarmlyMutationScope scope;
  final FarmlyOrganizationScope selectedScope;
  final FarmlyLiveZone zone;
  final FarmlyLivePlanting planting;

  @override
  ConsumerState<_LivePlantingUpdateSheet> createState() =>
      _LivePlantingUpdateSheetState();
}

class _LivePlantingUpdateSheetState
    extends ConsumerState<_LivePlantingUpdateSheet> {
  late final TextEditingController _areaM2 = TextEditingController(
    text: widget.planting.planting.areaM2?.value ?? '',
  );
  late String _status = widget.planting.planting.status;
  late DateTime _sowingDate = _dateFromCivil(
    widget.planting.planting.sowingDate,
  );
  late DateTime? _expectedHarvestDate =
      widget.planting.planting.expectedHarvestDate == null
      ? null
      : _dateFromCivil(widget.planting.planting.expectedHarvestDate!);
  String? _error;
  bool _saving = false;

  @override
  void dispose() {
    _areaM2.dispose();
    super.dispose();
  }

  DateTime _dateFromCivil(String value) => DateTime(
    int.parse(value.substring(0, 4)),
    int.parse(value.substring(5, 7)),
    int.parse(value.substring(8, 10)),
  );

  bool _farmScopeIsCurrent() =>
      _capturedFarmScopeIsCurrent(ref, widget.scope, widget.selectedScope);

  bool _plantingRowIsCurrent() => _capturedPlantingIsCurrent(
    ref: ref,
    scope: widget.scope,
    selectedScope: widget.selectedScope,
    zone: widget.zone,
    planting: widget.planting,
  );

  bool _scopeIsCurrent() => _farmScopeIsCurrent() && _plantingRowIsCurrent();

  String _scopeChangedMessage(AppLocalizations l10n) => _farmScopeIsCurrent()
      ? l10n.livePlantingChanged
      : l10n.liveFarmScopeChanged;

  Future<DateTime?> _pickDate({
    required String helpText,
    required DateTime? selectedDate,
    DateTime? firstDate,
  }) => showDatePicker(
    context: context,
    initialDate: selectedDate ?? firstDate ?? DateTime.now(),
    firstDate: firstDate ?? DateTime(1900),
    lastDate: DateTime(9999, 12, 31),
    initialEntryMode: DatePickerEntryMode.calendar,
    helpText: helpText,
  );

  Future<void> _pickSowingDate() async {
    final picked = await _pickDate(
      helpText: AppLocalizations.of(context).livePlantingSowingDateLabel,
      selectedDate: _sowingDate,
    );
    if (picked != null && mounted) {
      setState(() {
        _sowingDate = picked;
        _error = null;
      });
    }
  }

  Future<void> _pickExpectedHarvestDate() async {
    final picked = await _pickDate(
      helpText: AppLocalizations.of(
        context,
      ).livePlantingExpectedHarvestDateLabel,
      selectedDate:
          _expectedHarvestDate != null &&
              !_expectedHarvestDate!.isBefore(_sowingDate)
          ? _expectedHarvestDate
          : _sowingDate,
      firstDate: _sowingDate,
    );
    if (picked != null && mounted) {
      setState(() {
        _expectedHarvestDate = picked;
        _error = null;
      });
    }
  }

  String? _validate(AppLocalizations l10n) {
    if (!_scopeIsCurrent()) return _scopeChangedMessage(l10n);
    if (!const {
      'planned',
      'active',
      'harvested',
      'completed',
    }.contains(_status)) {
      return l10n.livePlantingEditFailed;
    }
    if (_expectedHarvestDate != null &&
        _expectedHarvestDate!.isBefore(_sowingDate)) {
      return l10n.livePlantingExpectedHarvestInvalid;
    }
    final area = _areaM2.text.trim().replaceAll(',', '.');
    if (area.isEmpty && widget.planting.planting.areaM2 != null) {
      return l10n.livePlantingAreaCannotClear;
    }
    if (area.isNotEmpty &&
        !RegExp(r'^(0|[1-9][0-9]{0,11})(\.[0-9]{1,2})?$').hasMatch(area)) {
      return l10n.livePlantingAreaInvalid;
    }
    return null;
  }

  Future<void> _save() async {
    if (_saving) return;
    final l10n = AppLocalizations.of(context);
    final validation = _validate(l10n);
    if (validation != null) {
      setState(() => _error = validation);
      return;
    }

    final current = widget.planting.planting;
    final sowingDateValue = _formatCivilDate(_sowingDate);
    final expectedHarvestDateValue = _expectedHarvestDate == null
        ? null
        : _formatCivilDate(_expectedHarvestDate!);
    final area = _areaM2.text.trim().replaceAll(',', '.');
    final status = _status == current.status ? null : _status;
    final sowingDate = sowingDateValue == current.sowingDate
        ? null
        : sowingDateValue;
    final expectedHarvestDate =
        expectedHarvestDateValue == current.expectedHarvestDate
        ? null
        : expectedHarvestDateValue;
    final areaM2 = area.isEmpty || area == current.areaM2?.value ? null : area;
    if (status == null &&
        sowingDate == null &&
        expectedHarvestDate == null &&
        areaM2 == null) {
      Navigator.of(context).pop(false);
      return;
    }

    setState(() {
      _saving = true;
      _error = null;
    });
    try {
      final saved = await _enqueuePlantingUpdate(
        ref: ref,
        scope: widget.scope,
        selectedScope: widget.selectedScope,
        zone: widget.zone,
        planting: widget.planting,
        status: status,
        sowingDate: sowingDate,
        expectedHarvestDate: expectedHarvestDate,
        areaM2: areaM2,
      );
      if (!mounted) return;
      if (saved) {
        ref.invalidate(syncStatusProvider);
        ref.invalidate(farmlyLiveZoneCollectionProvider);
        Navigator.of(context).pop(true);
      } else {
        setState(
          () => _error = _scopeIsCurrent()
              ? l10n.livePlantingEditFailed
              : _scopeChangedMessage(l10n),
        );
      }
    } on Object {
      if (!mounted) return;
      setState(
        () => _error = _scopeIsCurrent()
            ? l10n.livePlantingEditFailed
            : _scopeChangedMessage(l10n),
      );
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    ref.watch(selectedOrganizationScopeProvider);
    ref.watch(farmlySyncScopeProvider);
    ref.watch(farmlyAuthSessionProvider);
    ref.watch(farmlyLiveZoneCollectionProvider);
    final l10n = AppLocalizations.of(context);
    final tokens = FarmThemeExtension.of(context);
    final scopeCurrent = _scopeIsCurrent();
    final dateLabels = MaterialLocalizations.of(context);
    return SafeArea(
      child: SingleChildScrollView(
        padding: EdgeInsets.fromLTRB(
          FarmSpacing.lg,
          FarmSpacing.sm,
          FarmSpacing.lg,
          FarmSpacing.lg + MediaQuery.viewInsetsOf(context).bottom,
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(
              l10n.livePlantingEditTitle,
              style: Theme.of(context).textTheme.titleLarge,
            ),
            const SizedBox(height: FarmSpacing.sm),
            Text(
              '${widget.zone.zone.name} · ${widget.selectedScope.selectedFarm?.name ?? ''}',
              style: Theme.of(
                context,
              ).textTheme.bodySmall?.copyWith(color: tokens.textSecondary),
            ),
            const SizedBox(height: FarmSpacing.lg),
            DropdownButtonFormField<String>(
              key: const ValueKey('live-planting-edit-status'),
              initialValue: _status,
              decoration: InputDecoration(
                labelText: l10n.livePlantingEditStatusLabel,
              ),
              items: [
                for (final status in const [
                  'planned',
                  'active',
                  'harvested',
                  'completed',
                ])
                  DropdownMenuItem(
                    value: status,
                    child: Text(_plantingStatusLabel(l10n, status)),
                  ),
              ],
              onChanged: !_saving && scopeCurrent
                  ? (value) {
                      if (value != null) setState(() => _status = value);
                    }
                  : null,
            ),
            const SizedBox(height: FarmSpacing.md),
            _DatePickerField(
              key: const ValueKey('live-planting-edit-sowing-date'),
              label: l10n.livePlantingSowingDateLabel,
              value: dateLabels.formatMediumDate(_sowingDate),
              enabled: !_saving && scopeCurrent,
              onTap: _pickSowingDate,
            ),
            const SizedBox(height: FarmSpacing.md),
            _DatePickerField(
              key: const ValueKey('live-planting-edit-expected-harvest-date'),
              label: l10n.livePlantingExpectedHarvestDateLabel,
              value: _expectedHarvestDate == null
                  ? null
                  : dateLabels.formatMediumDate(_expectedHarvestDate!),
              enabled: !_saving && scopeCurrent,
              onTap: _pickExpectedHarvestDate,
            ),
            const SizedBox(height: FarmSpacing.md),
            DecimalField(
              key: const ValueKey('live-planting-edit-area-m2'),
              controller: _areaM2,
              labelText: l10n.livePlantingAreaLabel,
              hintText: l10n.livePlantingAreaHint,
              helperText: l10n.livePlantingAreaHelper,
              enabled: !_saving && scopeCurrent,
            ),
            if (_error != null) ...[
              const SizedBox(height: FarmSpacing.sm),
              Text(_error!, style: TextStyle(color: tokens.semanticWarning)),
            ],
            if (!scopeCurrent) ...[
              const SizedBox(height: FarmSpacing.md),
              Text(
                _scopeChangedMessage(l10n),
                style: TextStyle(color: tokens.semanticWarning),
              ),
            ],
            const SizedBox(height: FarmSpacing.lg),
            FilledButton(
              key: const ValueKey('live-planting-edit-save'),
              onPressed: _saving || !scopeCurrent ? null : _save,
              child: Text(l10n.livePlantingEditSave),
            ),
          ],
        ),
      ),
    );
  }
}

class _LiveWaterTankCard extends StatelessWidget {
  const _LiveWaterTankCard({
    required this.tank,
    required this.readings,
    required this.usages,
    required this.canRecord,
    required this.canRename,
    required this.onRename,
    required this.onRecordReading,
    required this.onRecordUsage,
  });

  final FarmlyLiveWaterTank tank;
  final List<FarmlyLiveWaterReading> readings;
  final List<FarmlyLiveWaterUsage> usages;
  final bool canRecord;
  final bool canRename;
  final VoidCallback onRename;
  final VoidCallback onRecordReading;
  final VoidCallback onRecordUsage;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final sortedReadings = [...readings]
      ..sort((a, b) => _waterMeasuredAt(a).compareTo(_waterMeasuredAt(b)));
    final sortedUsages = [...usages]
      ..sort((a, b) => a.usageDate.compareTo(b.usageDate));
    final latestReadings = sortedReadings.reversed.take(3);
    final latestUsages = sortedUsages.reversed.take(3);
    final capacity = formatDisplayDecimal(
      tank.tank.capacityLitres.value,
      l10n.localeName,
    );
    final stored = tank.tank.storedLitres;

    return FarmCard(
      key: ValueKey('live-water-tank-row-${tank.tank.id}'),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              const Icon(Icons.water_drop_outlined),
              const SizedBox(width: FarmSpacing.sm),
              Expanded(
                child: Text(
                  tank.displayName,
                  style: Theme.of(context).textTheme.titleSmall,
                ),
              ),
              if (canRename)
                IconButton(
                  key: ValueKey('live-water-tank-edit-${tank.tank.id}'),
                  tooltip: l10n.liveWaterTankRenameAction,
                  onPressed: onRename,
                  icon: const Icon(Icons.edit_outlined),
                ),
              _ZoneSyncBadge(state: tank.syncState),
            ],
          ),
          if (tank.tank.status == 'archived') ...[
            const SizedBox(height: FarmSpacing.xs),
            Text(l10n.livePlantingStatusArchived),
          ],
          const SizedBox(height: FarmSpacing.xs),
          Text(
            '${l10n.liveWaterReadingLabel}: '
            '${stored == null ? '—' : formatDisplayDecimal(stored.value, l10n.localeName)}'
            ' / $capacity L',
          ),
          if (readings.isNotEmpty) ...[
            const SizedBox(height: FarmSpacing.md),
            _sectionTitle(context, title: l10n.liveWaterReadingHistory),
            for (final reading in latestReadings)
              Padding(
                key: ValueKey('live-water-reading-row-${reading.id}'),
                padding: const EdgeInsets.only(bottom: FarmSpacing.xs),
                child: Row(
                  children: [
                    const Icon(Icons.opacity_outlined, size: 18),
                    const SizedBox(width: FarmSpacing.xs),
                    Expanded(
                      child: Text(
                        '${formatDisplayDecimal(reading.storedLitres.value, l10n.localeName)} L'
                        '${reading.measuredAt == null ? '' : ' · ${_formatDisplayInstantDate(reading.measuredAt!, l10n.localeName)}'}',
                      ),
                    ),
                    _ZoneSyncBadge(state: reading.syncState),
                  ],
                ),
              ),
          ],
          const SizedBox(height: FarmSpacing.md),
          _sectionTitle(context, title: l10n.liveWaterUsageSection),
          if (usages.isEmpty)
            Padding(
              padding: const EdgeInsets.only(bottom: FarmSpacing.xs),
              child: Text(l10n.liveWaterUsageEmpty),
            ),
          for (final usage in latestUsages)
            Padding(
              key: ValueKey('live-water-usage-row-${usage.id}'),
              padding: const EdgeInsets.only(bottom: FarmSpacing.xs),
              child: Row(
                children: [
                  const Icon(Icons.water_outlined, size: 18),
                  const SizedBox(width: FarmSpacing.xs),
                  Expanded(
                    child: Text(
                      '${formatDisplayDecimal(usage.usageLitres.value, l10n.localeName)} L · '
                      '${formatDisplayDate(usage.usageDate, l10n.localeName) ?? usage.usageDate}'
                      '${usage.note == null ? '' : ' · ${usage.note}'}',
                    ),
                  ),
                  _ZoneSyncBadge(state: usage.syncState),
                ],
              ),
            ),
          if (canRecord && tank.tank.status == 'active') ...[
            const SizedBox(height: FarmSpacing.sm),
            Wrap(
              spacing: FarmSpacing.sm,
              runSpacing: FarmSpacing.xs,
              children: [
                OutlinedButton.icon(
                  key: ValueKey('live-water-reading-create-${tank.tank.id}'),
                  onPressed: onRecordReading,
                  icon: const Icon(Icons.opacity_outlined),
                  label: Text(l10n.liveWaterReadingCreate),
                ),
                OutlinedButton.icon(
                  key: ValueKey('live-water-usage-create-${tank.tank.id}'),
                  onPressed: onRecordUsage,
                  icon: const Icon(Icons.water_outlined),
                  label: Text(l10n.liveWaterUsageCreate),
                ),
              ],
            ),
          ],
        ],
      ),
    );
  }
}

DateTime _waterMeasuredAt(FarmlyLiveWaterReading reading) =>
    DateTime.tryParse(reading.measuredAt ?? '') ??
    DateTime.fromMillisecondsSinceEpoch(0, isUtc: true);

String _formatDisplayInstantDate(String value, String localeName) {
  final instant = DateTime.tryParse(value);
  if (instant == null) return value;
  final date = _formatCivilDate(instant.toLocal());
  return formatDisplayDate(date, localeName) ?? date;
}

class _LiveWaterTankCreateSheet extends ConsumerStatefulWidget {
  const _LiveWaterTankCreateSheet({
    required this.scope,
    required this.selectedScope,
    required this.zone,
  });

  final FarmlyMutationScope scope;
  final FarmlyOrganizationScope selectedScope;
  final FarmlyLiveZone zone;

  @override
  ConsumerState<_LiveWaterTankCreateSheet> createState() =>
      _LiveWaterTankCreateSheetState();
}

class _LiveWaterTankCreateSheetState
    extends ConsumerState<_LiveWaterTankCreateSheet> {
  final _name = TextEditingController();
  final _capacityLitres = TextEditingController();
  String? _error;
  bool _saving = false;

  @override
  void dispose() {
    _name.dispose();
    _capacityLitres.dispose();
    super.dispose();
  }

  bool _scopeIsCurrent() => _capturedWaterScopeIsCurrent(
    ref,
    widget.scope,
    widget.selectedScope,
    widget.zone,
  );

  String? _validate(AppLocalizations l10n) {
    if (!_scopeIsCurrent()) return l10n.liveFarmScopeChanged;
    if (_name.text.trim().isEmpty) return l10n.liveWaterTankNameRequired;
    final capacity = _capacityLitres.text.trim().replaceAll(',', '.');
    if (!_isValidWaterAmount(capacity, positive: true)) {
      return l10n.liveWaterTankCapacityInvalid;
    }
    return null;
  }

  Future<void> _save() async {
    if (_saving) return;
    final l10n = AppLocalizations.of(context);
    final validation = _validate(l10n);
    if (validation != null) {
      setState(() => _error = validation);
      return;
    }
    setState(() {
      _saving = true;
      _error = null;
    });
    try {
      final session = await ref.read(farmlyAuthSessionProvider.future);
      final engine = await ref.read(syncEngineProvider.future);
      if (!mounted ||
          session == null ||
          session.user.id != widget.scope.accountId ||
          !_scopeIsCurrent()) {
        throw StateError('Farm scope changed before local save');
      }
      await engine.enqueue(
        FarmlyScopedMutation(
          scope: widget.scope,
          intent: FarmlyCreateWaterTankIntent(
            operationId: newFarmlyOperationId(),
            continuityEpoch: widget.scope.continuityEpoch,
            resourceId: newFarmlyOperationId(),
            name: _name.text.trim(),
            zoneId: widget.zone.zone.id,
            capacityLitres: _capacityLitres.text.trim().replaceAll(',', '.'),
            dependsOn: [
              if (widget.zone.operationId != null) widget.zone.operationId!,
            ],
          ),
        ),
      );
      ref.invalidate(syncStatusProvider);
      ref.invalidate(farmlyLiveZoneCollectionProvider);
      if (mounted) Navigator.of(context).pop(true);
    } on Object {
      if (!mounted) return;
      setState(
        () => _error = _scopeIsCurrent()
            ? l10n.liveWaterTankSaveFailed
            : l10n.liveFarmScopeChanged,
      );
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    ref.watch(selectedOrganizationScopeProvider);
    ref.watch(farmlySyncScopeProvider);
    ref.watch(farmlyAuthSessionProvider);
    final l10n = AppLocalizations.of(context);
    final tokens = FarmThemeExtension.of(context);
    final scopeCurrent = _scopeIsCurrent();
    return _WaterActionForm(
      title: l10n.liveWaterTankCreate,
      subtitle: widget.zone.zone.name,
      fields: [
        TextField(
          key: const ValueKey('live-water-tank-name'),
          controller: _name,
          autofocus: true,
          enabled: !_saving && scopeCurrent,
          maxLength: 160,
          decoration: InputDecoration(
            labelText: l10n.liveWaterTankNameLabel,
            errorText: _error == l10n.liveWaterTankNameRequired ? _error : null,
          ),
        ),
        DecimalField(
          key: const ValueKey('live-water-tank-capacity-litres'),
          controller: _capacityLitres,
          labelText: l10n.liveWaterTankCapacityLabel,
          hintText: '1000',
          helperText: l10n.liveWaterReadingHelper,
          errorText: _error == l10n.liveWaterTankCapacityInvalid
              ? _error
              : null,
        ),
        if (_error != null &&
            _error != l10n.liveWaterTankNameRequired &&
            _error != l10n.liveWaterTankCapacityInvalid)
          Text(_error!, style: TextStyle(color: tokens.semanticWarning)),
      ],
      scopeCurrent: scopeCurrent,
      saving: _saving,
      onSave: _save,
    );
  }
}

class _LiveWaterTankRenameSheet extends ConsumerStatefulWidget {
  const _LiveWaterTankRenameSheet({
    required this.scope,
    required this.selectedScope,
    required this.zone,
    required this.tank,
  });

  final FarmlyMutationScope scope;
  final FarmlyOrganizationScope selectedScope;
  final FarmlyLiveZone zone;
  final FarmlyLiveWaterTank tank;

  @override
  ConsumerState<_LiveWaterTankRenameSheet> createState() =>
      _LiveWaterTankRenameSheetState();
}

class _LiveWaterTankRenameSheetState
    extends ConsumerState<_LiveWaterTankRenameSheet> {
  late final TextEditingController _name = TextEditingController(
    text: widget.tank.displayName,
  );
  String? _error;
  bool _saving = false;

  @override
  void dispose() {
    _name.dispose();
    super.dispose();
  }

  FarmlyLiveZoneCollection? _currentCollection() =>
      ref.read(farmlyLiveZoneCollectionProvider).asData?.value;

  FarmlyLiveZone? _currentZone() {
    final matches = (_currentCollection()?.zones ?? const <FarmlyLiveZone>[])
        .where((item) => item.zone.id == widget.zone.zone.id)
        .toList(growable: false);
    return matches.length == 1 ? matches.single : null;
  }

  FarmlyLiveWaterTank? _currentTank() {
    final matches =
        (_currentCollection()?.waterTanks ?? const <FarmlyLiveWaterTank>[])
            .where((item) => item.tank.id == widget.tank.tank.id)
            .toList(growable: false);
    return matches.length == 1 ? matches.single : null;
  }

  bool _scopeIsCurrent() {
    final projection = _currentCollection();
    final currentZone = _currentZone();
    final currentTank = _currentTank();
    final cacheIsWritable =
        projection?.cacheState == FarmlyZoneCacheState.ready ||
        projection?.cacheState == FarmlyZoneCacheState.notBootstrapped;
    return projection?.scope != null &&
        _sameFarmScope(widget.scope, projection!.scope) &&
        projection.canCreate &&
        cacheIsWritable &&
        currentZone != null &&
        currentZone.zone.id == widget.zone.zone.id &&
        currentZone.zone.type == 'water' &&
        currentZone.zone.status == 'active' &&
        currentZone.zone.version == widget.zone.zone.version &&
        currentZone.syncState == FarmlyZoneSyncState.confirmed &&
        currentTank != null &&
        currentTank.isUniqueConfirmedRecord &&
        currentTank.tank.id == widget.tank.tank.id &&
        currentTank.tank.version == widget.tank.tank.version &&
        currentTank.tank.name == widget.tank.tank.name &&
        currentTank.tank.zoneId == widget.zone.zone.id &&
        currentTank.tank.status == 'active' &&
        currentTank.syncState == FarmlyZoneSyncState.confirmed &&
        !currentTank.hasUnresolvedNameUpdate &&
        widget.tank.isUniqueConfirmedRecord &&
        !widget.tank.hasUnresolvedNameUpdate &&
        _capturedWaterScopeIsCurrent(
          ref,
          widget.scope,
          widget.selectedScope,
          widget.zone,
          tank: widget.tank,
        );
  }

  Future<void> _save() async {
    if (_saving) return;
    final l10n = AppLocalizations.of(context);
    final name = _name.text.trim();
    if (name.isEmpty) {
      setState(() => _error = l10n.liveWaterTankNameRequired);
      return;
    }
    if (name.length > 160) {
      setState(() => _error = l10n.liveWaterTankNameTooLong);
      return;
    }
    if (name == widget.tank.tank.name) {
      Navigator.of(context).pop(false);
      return;
    }
    if (!_scopeIsCurrent()) {
      setState(() => _error = l10n.liveFarmScopeChanged);
      return;
    }

    setState(() {
      _saving = true;
      _error = null;
    });
    try {
      final saved = await _enqueueWaterTankNameUpdate(
        ref: ref,
        scope: widget.scope,
        selectedScope: widget.selectedScope,
        zone: widget.zone,
        tank: widget.tank,
        name: name,
      );
      if (!mounted) return;
      if (saved) {
        ref.invalidate(syncStatusProvider);
        ref.invalidate(farmlyLiveZoneCollectionProvider);
        Navigator.of(context).pop(true);
      } else {
        setState(
          () => _error = _scopeIsCurrent()
              ? l10n.liveWaterTankRenameFailed
              : l10n.liveFarmScopeChanged,
        );
      }
    } on Object {
      if (!mounted) return;
      setState(
        () => _error = _scopeIsCurrent()
            ? l10n.liveWaterTankRenameFailed
            : l10n.liveFarmScopeChanged,
      );
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    ref.watch(selectedOrganizationScopeProvider);
    ref.watch(farmlySyncScopeProvider);
    ref.watch(farmlyAuthSessionProvider);
    ref.watch(farmlyLiveZoneCollectionProvider);
    final l10n = AppLocalizations.of(context);
    final tokens = FarmThemeExtension.of(context);
    final scopeCurrent = _scopeIsCurrent();
    return SafeArea(
      child: SingleChildScrollView(
        padding: EdgeInsets.fromLTRB(
          FarmSpacing.lg,
          FarmSpacing.sm,
          FarmSpacing.lg,
          FarmSpacing.lg + MediaQuery.viewInsetsOf(context).bottom,
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(
              l10n.liveWaterTankRenameTitle,
              style: Theme.of(context).textTheme.titleLarge,
            ),
            const SizedBox(height: FarmSpacing.md),
            TextField(
              key: const ValueKey('live-water-tank-edit-name'),
              controller: _name,
              autofocus: true,
              enabled: !_saving && scopeCurrent,
              maxLength: 160,
              textCapitalization: TextCapitalization.sentences,
              textInputAction: TextInputAction.done,
              decoration: InputDecoration(
                labelText: l10n.liveWaterTankNameLabel,
                errorText:
                    _error == l10n.liveWaterTankNameRequired ||
                        _error == l10n.liveWaterTankNameTooLong
                    ? _error
                    : null,
              ),
              onSubmitted: (_) {
                if (!_saving && scopeCurrent) _save();
              },
            ),
            if (_error != null &&
                _error != l10n.liveWaterTankNameRequired &&
                _error != l10n.liveWaterTankNameTooLong) ...[
              const SizedBox(height: FarmSpacing.sm),
              Text(_error!, style: TextStyle(color: tokens.semanticWarning)),
            ],
            if (!scopeCurrent) ...[
              const SizedBox(height: FarmSpacing.md),
              Text(
                l10n.liveFarmScopeChanged,
                style: TextStyle(color: tokens.semanticWarning),
              ),
            ],
            const SizedBox(height: FarmSpacing.lg),
            SizedBox(
              height: 52,
              child: FilledButton(
                key: const ValueKey('live-water-tank-edit-save'),
                onPressed: _saving || !scopeCurrent ? null : _save,
                child: Text(l10n.saveOnDevice),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _LiveWaterReadingCreateSheet extends ConsumerStatefulWidget {
  const _LiveWaterReadingCreateSheet({
    required this.scope,
    required this.selectedScope,
    required this.zone,
    required this.tank,
  });

  final FarmlyMutationScope scope;
  final FarmlyOrganizationScope selectedScope;
  final FarmlyLiveZone zone;
  final FarmlyLiveWaterTank tank;

  @override
  ConsumerState<_LiveWaterReadingCreateSheet> createState() =>
      _LiveWaterReadingCreateSheetState();
}

class _LiveWaterReadingCreateSheetState
    extends ConsumerState<_LiveWaterReadingCreateSheet> {
  final _storedLitres = TextEditingController();
  String? _error;
  bool _saving = false;

  @override
  void dispose() {
    _storedLitres.dispose();
    super.dispose();
  }

  bool _scopeIsCurrent() => _capturedWaterScopeIsCurrent(
    ref,
    widget.scope,
    widget.selectedScope,
    widget.zone,
    tank: widget.tank,
    allowWorker: true,
  );

  String? _validate(AppLocalizations l10n) {
    if (!_scopeIsCurrent()) return l10n.liveFarmScopeChanged;
    final value = _storedLitres.text.trim().replaceAll(',', '.');
    if (!_isValidWaterAmount(value, positive: false) ||
        _waterAmountUnits(value) >
            _waterAmountUnits(widget.tank.tank.capacityLitres.value)) {
      return l10n.liveWaterReadingInvalid;
    }
    return null;
  }

  Future<void> _save() async {
    if (_saving) return;
    final l10n = AppLocalizations.of(context);
    final validation = _validate(l10n);
    if (validation != null) {
      setState(() => _error = validation);
      return;
    }
    setState(() {
      _saving = true;
      _error = null;
    });
    try {
      final session = await ref.read(farmlyAuthSessionProvider.future);
      final engine = await ref.read(syncEngineProvider.future);
      if (!mounted ||
          session == null ||
          session.user.id != widget.scope.accountId ||
          !_scopeIsCurrent()) {
        throw StateError('Farm scope changed before local save');
      }
      await engine.enqueue(
        FarmlyScopedMutation(
          scope: widget.scope,
          intent: FarmlyCreateWaterReadingIntent(
            operationId: newFarmlyOperationId(),
            continuityEpoch: widget.scope.continuityEpoch,
            resourceId: newFarmlyOperationId(),
            tankId: widget.tank.tank.id,
            storedLitres: _storedLitres.text.trim().replaceAll(',', '.'),
            source: 'manual',
            measuredAt: DateTime.now().toUtc().toIso8601String(),
            dependsOn: [
              if (widget.tank.operationId != null) widget.tank.operationId!,
            ],
          ),
        ),
      );
      ref.invalidate(syncStatusProvider);
      ref.invalidate(farmlyLiveZoneCollectionProvider);
      if (mounted) Navigator.of(context).pop(true);
    } on Object {
      if (!mounted) return;
      setState(
        () => _error = _scopeIsCurrent()
            ? l10n.liveWaterReadingSaveFailed
            : l10n.liveFarmScopeChanged,
      );
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    ref.watch(selectedOrganizationScopeProvider);
    ref.watch(farmlySyncScopeProvider);
    ref.watch(farmlyAuthSessionProvider);
    final l10n = AppLocalizations.of(context);
    final tokens = FarmThemeExtension.of(context);
    final scopeCurrent = _scopeIsCurrent();
    return _WaterActionForm(
      title: l10n.liveWaterReadingCreate,
      subtitle: widget.tank.tank.name,
      fields: [
        DecimalField(
          key: const ValueKey('live-water-reading-stored-litres'),
          controller: _storedLitres,
          autofocus: true,
          labelText: l10n.liveWaterReadingLabel,
          hintText: '0',
          helperText: l10n.liveWaterReadingHelper,
          errorText: _error == l10n.liveWaterReadingInvalid ? _error : null,
        ),
        if (_error != null && _error != l10n.liveWaterReadingInvalid)
          Text(_error!, style: TextStyle(color: tokens.semanticWarning)),
      ],
      scopeCurrent: scopeCurrent,
      saving: _saving,
      onSave: _save,
    );
  }
}

class _LiveWaterUsageCreateSheet extends ConsumerStatefulWidget {
  const _LiveWaterUsageCreateSheet({
    required this.scope,
    required this.selectedScope,
    required this.zone,
    required this.tank,
  });

  final FarmlyMutationScope scope;
  final FarmlyOrganizationScope selectedScope;
  final FarmlyLiveZone zone;
  final FarmlyLiveWaterTank tank;

  @override
  ConsumerState<_LiveWaterUsageCreateSheet> createState() =>
      _LiveWaterUsageCreateSheetState();
}

class _LiveWaterUsageCreateSheetState
    extends ConsumerState<_LiveWaterUsageCreateSheet> {
  final _usageLitres = TextEditingController();
  final _usageDate = TextEditingController();
  final _note = TextEditingController();
  String? _error;
  bool _saving = false;

  @override
  void dispose() {
    _usageLitres.dispose();
    _usageDate.dispose();
    _note.dispose();
    super.dispose();
  }

  bool _scopeIsCurrent() => _capturedWaterScopeIsCurrent(
    ref,
    widget.scope,
    widget.selectedScope,
    widget.zone,
    tank: widget.tank,
    allowWorker: true,
  );

  String? _validate(AppLocalizations l10n) {
    if (!_scopeIsCurrent()) return l10n.liveFarmScopeChanged;
    final amount = _usageLitres.text.trim().replaceAll(',', '.');
    if (!_isValidWaterAmount(amount, positive: true)) {
      return l10n.liveWaterUsageAmountInvalid;
    }
    if (!_isValidCivilDate(_usageDate.text.trim())) {
      return l10n.liveWaterUsageDateInvalid;
    }
    if (_note.text.trim().length > 200) {
      return l10n.liveWaterUsageAmountInvalid;
    }
    return null;
  }

  Future<void> _save() async {
    if (_saving) return;
    final l10n = AppLocalizations.of(context);
    final validation = _validate(l10n);
    if (validation != null) {
      setState(() => _error = validation);
      return;
    }
    setState(() {
      _saving = true;
      _error = null;
    });
    try {
      final session = await ref.read(farmlyAuthSessionProvider.future);
      final engine = await ref.read(syncEngineProvider.future);
      if (!mounted ||
          session == null ||
          session.user.id != widget.scope.accountId ||
          !_scopeIsCurrent()) {
        throw StateError('Farm scope changed before local save');
      }
      await engine.enqueue(
        FarmlyScopedMutation(
          scope: widget.scope,
          intent: FarmlyCreateWaterUsageIntent(
            operationId: newFarmlyOperationId(),
            continuityEpoch: widget.scope.continuityEpoch,
            resourceId: newFarmlyOperationId(),
            tankId: widget.tank.tank.id,
            usageLitres: _usageLitres.text.trim().replaceAll(',', '.'),
            usageDate: _usageDate.text.trim(),
            note: _note.text.trim().isEmpty ? null : _note.text.trim(),
            dependsOn: [
              if (widget.tank.operationId != null) widget.tank.operationId!,
            ],
          ),
        ),
      );
      ref.invalidate(syncStatusProvider);
      ref.invalidate(farmlyLiveZoneCollectionProvider);
      if (mounted) Navigator.of(context).pop(true);
    } on Object {
      if (!mounted) return;
      setState(
        () => _error = _scopeIsCurrent()
            ? l10n.liveWaterUsageSaveFailed
            : l10n.liveFarmScopeChanged,
      );
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    ref.watch(selectedOrganizationScopeProvider);
    ref.watch(farmlySyncScopeProvider);
    ref.watch(farmlyAuthSessionProvider);
    final l10n = AppLocalizations.of(context);
    final tokens = FarmThemeExtension.of(context);
    final scopeCurrent = _scopeIsCurrent();
    final amountError = _error == l10n.liveWaterUsageAmountInvalid
        ? _error
        : null;
    final dateError = _error == l10n.liveWaterUsageDateInvalid ? _error : null;
    return _WaterActionForm(
      title: l10n.liveWaterUsageCreate,
      subtitle: widget.tank.tank.name,
      fields: [
        DecimalField(
          key: const ValueKey('live-water-usage-litres'),
          controller: _usageLitres,
          autofocus: true,
          labelText: l10n.liveWaterUsageAmountLabel,
          hintText: '12,5',
          helperText: l10n.liveWaterUsageHelper,
          errorText: amountError,
        ),
        LocalDateField(
          key: const ValueKey('live-water-usage-date'),
          controller: _usageDate,
          labelText: l10n.liveWaterUsageDateLabel,
          helperText: l10n.liveWaterUsageDateHelper,
          errorText: dateError,
        ),
        TextField(
          key: const ValueKey('live-water-usage-note'),
          controller: _note,
          enabled: !_saving && scopeCurrent,
          maxLength: 200,
          decoration: InputDecoration(labelText: l10n.liveWaterUsageNoteLabel),
        ),
        if (_error != null && amountError == null && dateError == null)
          Text(_error!, style: TextStyle(color: tokens.semanticWarning)),
      ],
      scopeCurrent: scopeCurrent,
      saving: _saving,
      onSave: _save,
    );
  }
}

class _LiveMoistureReadingCreateSheet extends ConsumerStatefulWidget {
  const _LiveMoistureReadingCreateSheet({
    required this.scope,
    required this.selectedScope,
    required this.zone,
  });

  final FarmlyMutationScope scope;
  final FarmlyOrganizationScope selectedScope;
  final FarmlyLiveZone zone;

  @override
  ConsumerState<_LiveMoistureReadingCreateSheet> createState() =>
      _LiveMoistureReadingCreateSheetState();
}

class _LiveMoistureReadingCreateSheetState
    extends ConsumerState<_LiveMoistureReadingCreateSheet> {
  final _value = TextEditingController();
  String _method = 'relative_percent';
  String? _error;
  bool _saving = false;

  @override
  void dispose() {
    _value.dispose();
    super.dispose();
  }

  FarmlyLiveZone? _currentZone() {
    final collection = ref.read(farmlyLiveZoneCollectionProvider).asData?.value;
    for (final item in collection?.zones ?? const <FarmlyLiveZone>[]) {
      if (item.zone.id == widget.zone.zone.id) return item;
    }
    return null;
  }

  bool _scopeIsCurrent() {
    final collection = ref.read(farmlyLiveZoneCollectionProvider).asData?.value;
    if (collection == null ||
        !_sameFarmScope(widget.scope, collection.scope) ||
        (collection.cacheState != FarmlyZoneCacheState.ready &&
            collection.cacheState != FarmlyZoneCacheState.notBootstrapped)) {
      return false;
    }
    final currentZone = _currentZone();
    return _capturedFarmScopeIsCurrent(
          ref,
          widget.scope,
          widget.selectedScope,
          allowWorker: true,
        ) &&
        currentZone != null &&
        currentZone.zone.type == 'crop_plot' &&
        currentZone.zone.status == 'active' &&
        currentZone.syncState != FarmlyZoneSyncState.needsAttention;
  }

  String _normalizedValue() => _value.text.trim().replaceAll(',', '.');

  String? _validate(
    AppLocalizations l10n, {
    required String value,
    required String method,
  }) {
    if (!_scopeIsCurrent()) return l10n.liveFarmScopeChanged;
    final nowUtc = ref.read(farmlyUtcNowProvider)().toUtc();
    try {
      FarmlyCreateMoistureReadingIntent.validatePayload(
        zoneId: widget.zone.zone.id,
        value: value,
        method: method,
        measuredAt: nowUtc.toIso8601String(),
        nowUtc: nowUtc,
      );
    } on Object {
      return l10n.moistureErrorRange;
    }
    return null;
  }

  Future<void> _save() async {
    if (_saving) return;
    final l10n = AppLocalizations.of(context);
    final value = _normalizedValue();
    final method = _method;
    final validation = _validate(l10n, value: value, method: method);
    if (validation != null) {
      setState(() => _error = validation);
      return;
    }
    setState(() {
      _saving = true;
      _error = null;
    });
    try {
      final session = await ref.read(farmlyAuthSessionProvider.future);
      final engine = await ref.read(syncEngineProvider.future);
      final snapshot = await engine.domainSnapshot(widget.scope);
      if (!mounted ||
          session == null ||
          session.user.id != widget.scope.accountId ||
          !_scopeIsCurrent()) {
        if (mounted) setState(() => _error = l10n.liveFarmScopeChanged);
        return;
      }
      if (snapshot != null &&
          (snapshot.cursor.continuityEpoch !=
                  widget.selectedScope.directory.continuityEpoch ||
              snapshot.cursor.scopePolicyVersion !=
                  widget.selectedScope.directory.scopePolicyVersion)) {
        setState(() => _error = l10n.liveFarmScopeChanged);
        return;
      }

      final currentZone = _currentZone();
      if (currentZone == null || !_scopeIsCurrent()) {
        setState(() => _error = l10n.liveFarmScopeChanged);
        return;
      }
      final nowUtc = ref.read(farmlyUtcNowProvider)().toUtc();
      await engine.enqueue(
        FarmlyScopedMutation(
          scope: widget.scope,
          intent: FarmlyCreateMoistureReadingIntent(
            operationId: newFarmlyOperationId(),
            continuityEpoch: widget.scope.continuityEpoch,
            resourceId: newFarmlyOperationId(),
            zoneId: currentZone.zone.id,
            value: value,
            method: method,
            measuredAt: nowUtc.toIso8601String(),
            nowUtc: nowUtc,
            dependsOn: [
              if (currentZone.operationId != null) currentZone.operationId!,
            ],
          ),
        ),
      );
      ref.invalidate(syncStatusProvider);
      ref.invalidate(farmlyLiveZoneCollectionProvider);
      if (mounted) Navigator.of(context).pop(true);
    } on Object {
      if (!mounted) return;
      setState(
        () => _error = _scopeIsCurrent()
            ? l10n.moistureSaveFailed
            : l10n.liveFarmScopeChanged,
      );
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    ref.watch(selectedOrganizationScopeProvider);
    ref.watch(farmlySyncScopeProvider);
    ref.watch(farmlyAuthSessionProvider);
    final l10n = AppLocalizations.of(context);
    final tokens = FarmThemeExtension.of(context);
    final scopeCurrent = _scopeIsCurrent();
    final rangeError = _error == l10n.moistureErrorRange ? _error : null;
    return SafeArea(
      child: SingleChildScrollView(
        padding: EdgeInsets.fromLTRB(
          FarmSpacing.lg,
          FarmSpacing.sm,
          FarmSpacing.lg,
          FarmSpacing.lg + MediaQuery.viewInsetsOf(context).bottom,
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(
              l10n.moistureDialogTitle,
              style: Theme.of(context).textTheme.titleLarge,
            ),
            const SizedBox(height: FarmSpacing.sm),
            Text(
              widget.zone.zone.name,
              style: Theme.of(
                context,
              ).textTheme.bodySmall?.copyWith(color: tokens.textSecondary),
            ),
            const SizedBox(height: FarmSpacing.lg),
            DecimalField(
              key: const ValueKey('live-moisture-value'),
              controller: _value,
              autofocus: true,
              enabled: !_saving && scopeCurrent,
              labelText: l10n.moistureFieldLabel,
              hintText: '35',
              helperText: l10n.moistureHelper,
              errorText: rangeError,
            ),
            const SizedBox(height: FarmSpacing.md),
            DropdownButtonFormField<String>(
              key: const ValueKey('live-moisture-method'),
              isExpanded: true,
              initialValue: _method,
              decoration: InputDecoration(labelText: l10n.moistureMethodLabel),
              items: [
                DropdownMenuItem(
                  value: 'relative_percent',
                  child: Text(l10n.moistureMethodRelativePercent),
                ),
                DropdownMenuItem(
                  key: const ValueKey('live-moisture-method-vwc_percent'),
                  value: 'vwc_percent',
                  child: Text(l10n.moistureMethodVwcPercent),
                ),
              ],
              onChanged: _saving || !scopeCurrent
                  ? null
                  : (value) {
                      if (value == null) return;
                      setState(() {
                        _method = value;
                        if (_error == l10n.moistureErrorRange) _error = null;
                      });
                    },
            ),
            if (_error != null && _error != l10n.moistureErrorRange) ...[
              const SizedBox(height: FarmSpacing.sm),
              Text(_error!, style: TextStyle(color: tokens.semanticWarning)),
            ],
            if (!scopeCurrent) ...[
              const SizedBox(height: FarmSpacing.md),
              Text(
                l10n.liveFarmScopeChanged,
                style: TextStyle(color: tokens.semanticWarning),
              ),
            ],
            const SizedBox(height: FarmSpacing.md),
            FilledButton(
              key: const ValueKey('live-moisture-save'),
              onPressed: _saving || !scopeCurrent ? null : _save,
              child: Text(l10n.saveOnDevice),
            ),
          ],
        ),
      ),
    );
  }
}

class _WaterActionForm extends StatelessWidget {
  const _WaterActionForm({
    required this.title,
    required this.subtitle,
    required this.fields,
    required this.scopeCurrent,
    required this.saving,
    required this.onSave,
  });

  final String title;
  final String subtitle;
  final List<Widget> fields;
  final bool scopeCurrent;
  final bool saving;
  final VoidCallback onSave;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final tokens = FarmThemeExtension.of(context);
    return SafeArea(
      child: SingleChildScrollView(
        padding: EdgeInsets.fromLTRB(
          FarmSpacing.lg,
          FarmSpacing.sm,
          FarmSpacing.lg,
          FarmSpacing.lg + MediaQuery.viewInsetsOf(context).bottom,
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(title, style: Theme.of(context).textTheme.titleLarge),
            const SizedBox(height: FarmSpacing.sm),
            Text(
              subtitle,
              style: Theme.of(
                context,
              ).textTheme.bodySmall?.copyWith(color: tokens.textSecondary),
            ),
            const SizedBox(height: FarmSpacing.lg),
            for (final field in fields) ...[
              field,
              const SizedBox(height: FarmSpacing.md),
            ],
            if (!scopeCurrent) ...[
              Text(
                l10n.liveFarmScopeChanged,
                style: TextStyle(color: tokens.semanticWarning),
              ),
              const SizedBox(height: FarmSpacing.md),
            ],
            FilledButton(
              key: const ValueKey('live-water-action-save'),
              onPressed: saving || !scopeCurrent ? null : onSave,
              child: Text(l10n.saveOnDevice),
            ),
          ],
        ),
      ),
    );
  }
}

bool _capturedWaterScopeIsCurrent(
  WidgetRef ref,
  FarmlyMutationScope scope,
  FarmlyOrganizationScope selectedScope,
  FarmlyLiveZone zone, {
  FarmlyLiveWaterTank? tank,
  bool allowWorker = false,
}) =>
    zone.zone.type == 'water' &&
    zone.zone.status == 'active' &&
    zone.syncState != FarmlyZoneSyncState.needsAttention &&
    (tank == null ||
        (tank.tank.status == 'active' &&
            tank.syncState != FarmlyZoneSyncState.needsAttention)) &&
    _capturedFarmScopeIsCurrent(
      ref,
      scope,
      selectedScope,
      allowWorker: allowWorker,
    );

bool _isValidWaterAmount(String value, {required bool positive}) {
  if (!RegExp(r'^(0|[1-9][0-9]{0,15})(\.[0-9]{1,4})?$').hasMatch(value)) {
    return false;
  }
  return !positive || _waterAmountUnits(value) > BigInt.zero;
}

BigInt _waterAmountUnits(String value) {
  final parts = value.split('.');
  final whole = BigInt.parse(parts.first) * BigInt.from(10000);
  final fraction = parts.length == 1
      ? BigInt.zero
      : BigInt.parse(parts.last.padRight(4, '0'));
  return whole + fraction;
}

class _LivePlantingEventCreateSheet extends ConsumerStatefulWidget {
  const _LivePlantingEventCreateSheet({
    required this.scope,
    required this.selectedScope,
    required this.zone,
    required this.planting,
  });

  final FarmlyMutationScope scope;
  final FarmlyOrganizationScope selectedScope;
  final FarmlyLiveZone zone;
  final FarmlyLivePlanting planting;

  @override
  ConsumerState<_LivePlantingEventCreateSheet> createState() =>
      _LivePlantingEventCreateSheetState();
}

class _LivePlantingEventCreateSheetState
    extends ConsumerState<_LivePlantingEventCreateSheet> {
  final _eventType = TextEditingController();
  final _note = TextEditingController();
  final _occurredOn = TextEditingController();
  String? _error;
  bool _saving = false;

  Future<void> _pickOccurredOn() async {
    final current = _occurredOn.text.trim();
    final initialDate = _isValidCivilDate(current)
        ? DateTime.parse(current)
        : DateTime.now();
    final picked = await showDatePicker(
      context: context,
      initialDate: initialDate,
      firstDate: DateTime(1900),
      lastDate: DateTime(9999, 12, 31),
      initialEntryMode: DatePickerEntryMode.calendar,
      helpText: AppLocalizations.of(context).livePlantingEventDateLabel,
    );
    if (picked != null && mounted) {
      _occurredOn.text = _formatCivilDate(picked);
      setState(() => _error = null);
    }
  }

  @override
  void dispose() {
    _eventType.dispose();
    _note.dispose();
    _occurredOn.dispose();
    super.dispose();
  }

  FarmlyLiveZoneCollection? _currentProjection() =>
      ref.read(farmlyLiveZoneCollectionProvider).asData?.value;

  FarmlyLivePlanting? _currentPlanting() {
    final projection = _currentProjection();
    if (projection == null) return null;
    for (final item in projection.plantings) {
      if (item.planting.id == widget.planting.planting.id) return item;
    }
    return null;
  }

  bool _scopeIsCurrent() {
    final projection = _currentProjection();
    final currentPlanting = _currentPlanting();
    FarmlyLiveZone? currentZone;
    for (final item in projection?.zones ?? const <FarmlyLiveZone>[]) {
      if (item.zone.id == widget.zone.zone.id) {
        currentZone = item;
        break;
      }
    }
    return widget.zone.zone.type == 'crop_plot' &&
        widget.planting.planting.status != 'archived' &&
        widget.planting.syncState != FarmlyZoneSyncState.needsAttention &&
        widget.zone.syncState != FarmlyZoneSyncState.needsAttention &&
        projection?.scope != null &&
        _sameFarmScope(widget.scope, projection!.scope) &&
        currentZone != null &&
        currentZone.zone.type == 'crop_plot' &&
        currentZone.syncState != FarmlyZoneSyncState.needsAttention &&
        currentPlanting != null &&
        currentPlanting.planting.plotId == widget.zone.zone.id &&
        currentPlanting.planting.status != 'archived' &&
        currentPlanting.syncState != FarmlyZoneSyncState.needsAttention &&
        currentPlanting.operationId == widget.planting.operationId &&
        _capturedFarmScopeIsCurrent(
          ref,
          widget.scope,
          widget.selectedScope,
          allowWorker: true,
        );
  }

  String? _validate(AppLocalizations l10n) {
    if (!_scopeIsCurrent()) return l10n.liveFarmScopeChanged;
    final eventType = _eventType.text.trim();
    if (eventType.isEmpty || eventType.length > 40) {
      return l10n.livePlantingEventTypeInvalid;
    }
    if (_note.text.trim().length > 500) {
      return l10n.livePlantingEventNoteInvalid;
    }
    final date = _occurredOn.text.trim();
    if (date.isNotEmpty && !_isValidCivilDate(date)) {
      return l10n.livePlantingEventDateInvalid;
    }
    return null;
  }

  Future<void> _save() async {
    if (_saving) return;
    final l10n = AppLocalizations.of(context);
    final validation = _validate(l10n);
    if (validation != null) {
      setState(() => _error = validation);
      return;
    }

    setState(() {
      _saving = true;
      _error = null;
    });
    try {
      final session = await ref.read(farmlyAuthSessionProvider.future);
      final engine = await ref.read(syncEngineProvider.future);
      if (!mounted ||
          session == null ||
          session.user.id != widget.scope.accountId ||
          !_scopeIsCurrent()) {
        throw StateError('Farm scope changed before local save');
      }

      final snapshot = await engine.domainSnapshot(widget.scope);
      final entries = await engine.entries(
        accountId: widget.scope.accountId,
        organizationId: widget.scope.organizationId,
      );
      final plantingId = widget.planting.planting.id;
      final confirmedRow = snapshot?.recordsFor('planting')[plantingId];
      final parentEntries = entries
          .where(
            (entry) =>
                _entryMatchesScope(entry, widget.scope) &&
                entry.mutation.intent.type == 'planting.create' &&
                entry.mutation.intent.resourceId == plantingId,
          )
          .toList(growable: false);
      if (parentEntries.length > 1) {
        throw StateError('Planting has ambiguous local create operations');
      }

      String? currentStatus;
      String? currentPlotId;
      if (confirmedRow != null) {
        if (confirmedRow is! Map) {
          throw const FormatException('Invalid current planting snapshot');
        }
        currentStatus = confirmedRow['status'] as String;
        currentPlotId = confirmedRow['plotId'] as String;
      }
      final parent = parentEntries.isEmpty ? null : parentEntries.single;
      if (currentStatus == null && parent != null) {
        final payload = parent.mutation.intent.payload;
        currentStatus = payload['status'] as String? ?? 'planned';
        currentPlotId = payload['plotId'] as String?;
      }
      if (currentStatus == null ||
          currentPlotId != widget.zone.zone.id ||
          currentStatus == 'archived' ||
          (parent != null &&
              (parent.status == OutboxEntryStatus.rejected ||
                  parent.status == OutboxEntryStatus.conflict ||
                  parent.status == OutboxEntryStatus.blocked))) {
        throw StateError('Planting is no longer writable in this farm');
      }

      if (!mounted || !_scopeIsCurrent()) {
        throw StateError('Farm scope changed before local save');
      }
      final dependencies =
          parent != null && parent.status != OutboxEntryStatus.applied
          ? [parent.operationId]
          : const <String>[];
      final occurredOn = _occurredOn.text.trim();
      await engine.enqueue(
        FarmlyScopedMutation(
          scope: widget.scope,
          intent: FarmlyCreatePlantingEventIntent(
            operationId: newFarmlyOperationId(),
            continuityEpoch: widget.scope.continuityEpoch,
            resourceId: newFarmlyOperationId(),
            plantingId: plantingId,
            eventType: _eventType.text,
            note: _note.text,
            occurredOn: occurredOn.isEmpty ? null : occurredOn,
            dependsOn: dependencies,
          ),
        ),
      );
      ref.invalidate(syncStatusProvider);
      ref.invalidate(farmlyLiveZoneCollectionProvider);
      if (mounted) Navigator.of(context).pop(true);
    } on Object {
      if (!mounted) return;
      setState(
        () => _error = _scopeIsCurrent()
            ? l10n.livePlantingEventSaveFailed
            : l10n.liveFarmScopeChanged,
      );
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    ref.watch(selectedOrganizationScopeProvider);
    ref.watch(farmlySyncScopeProvider);
    ref.watch(farmlyAuthSessionProvider);
    ref.watch(farmlyLiveZoneCollectionProvider);
    final l10n = AppLocalizations.of(context);
    final tokens = FarmThemeExtension.of(context);
    final scopeCurrent = _scopeIsCurrent();
    final typeError = _error == l10n.livePlantingEventTypeInvalid
        ? _error
        : null;
    final noteError = _error == l10n.livePlantingEventNoteInvalid
        ? _error
        : null;
    final dateError = _error == l10n.livePlantingEventDateInvalid
        ? _error
        : null;
    return SafeArea(
      child: SingleChildScrollView(
        padding: EdgeInsets.fromLTRB(
          FarmSpacing.lg,
          FarmSpacing.sm,
          FarmSpacing.lg,
          FarmSpacing.lg + MediaQuery.viewInsetsOf(context).bottom,
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(
              l10n.livePlantingEventCreate,
              style: Theme.of(context).textTheme.titleLarge,
            ),
            const SizedBox(height: FarmSpacing.sm),
            Text(
              widget.zone.zone.name,
              style: Theme.of(
                context,
              ).textTheme.bodySmall?.copyWith(color: tokens.textSecondary),
            ),
            const SizedBox(height: FarmSpacing.md),
            TextField(
              key: const ValueKey('live-planting-event-type'),
              controller: _eventType,
              maxLength: 40,
              textCapitalization: TextCapitalization.sentences,
              decoration: InputDecoration(
                labelText: l10n.livePlantingEventTypeLabel,
                hintText: l10n.livePlantingEventTypeHint,
                helperText: l10n.livePlantingEventTypeHelper,
                errorText: typeError,
              ),
            ),
            const SizedBox(height: FarmSpacing.sm),
            TextField(
              key: const ValueKey('live-planting-event-note'),
              controller: _note,
              maxLength: 500,
              minLines: 2,
              maxLines: 4,
              textCapitalization: TextCapitalization.sentences,
              decoration: InputDecoration(
                labelText: l10n.livePlantingEventNoteLabel,
                helperText: l10n.livePlantingEventNoteHelper,
                errorText: noteError,
              ),
            ),
            const SizedBox(height: FarmSpacing.sm),
            TextField(
              key: const ValueKey('live-planting-event-date'),
              controller: _occurredOn,
              readOnly: true,
              onTap: _pickOccurredOn,
              decoration: InputDecoration(
                labelText: l10n.livePlantingEventDateLabel,
                hintText: l10n.livePlantingChooseDate,
                errorText: dateError,
                suffixIcon: _occurredOn.text.isEmpty
                    ? const Icon(Icons.calendar_today_outlined)
                    : IconButton(
                        tooltip: l10n.livePlantingEventClearDate,
                        onPressed: () {
                          _occurredOn.clear();
                          setState(() => _error = null);
                        },
                        icon: const Icon(Icons.close),
                      ),
              ),
            ),
            if (_error != null &&
                typeError == null &&
                noteError == null &&
                dateError == null)
              Padding(
                padding: const EdgeInsets.only(top: FarmSpacing.sm),
                child: Text(
                  _error!,
                  style: TextStyle(color: tokens.semanticWarning),
                ),
              ),
            if (!scopeCurrent) ...[
              const SizedBox(height: FarmSpacing.md),
              Text(
                l10n.liveFarmScopeChanged,
                style: TextStyle(color: tokens.semanticWarning),
              ),
            ],
            const SizedBox(height: FarmSpacing.lg),
            FilledButton(
              key: const ValueKey('live-planting-event-save'),
              onPressed: _saving || !scopeCurrent ? null : _save,
              child: Text(l10n.saveOnDevice),
            ),
          ],
        ),
      ),
    );
  }
}

class _LiveHarvestCreateSheet extends ConsumerStatefulWidget {
  const _LiveHarvestCreateSheet({
    required this.scope,
    required this.selectedScope,
    required this.zone,
    required this.planting,
  });

  final FarmlyMutationScope scope;
  final FarmlyOrganizationScope selectedScope;
  final FarmlyLiveZone zone;
  final FarmlyLivePlanting planting;

  @override
  ConsumerState<_LiveHarvestCreateSheet> createState() =>
      _LiveHarvestCreateSheetState();
}

Future<void> showLiveHarvestCreateForm({
  required BuildContext context,
  required WidgetRef ref,
  required FarmlyLiveZoneCollection collection,
  required FarmlyLiveZone zone,
  required FarmlyLivePlanting planting,
}) async {
  final scope = collection.scope;
  final selectedScope = collection.selectedScope;
  if (scope == null || selectedScope == null) return;
  final saved = await showModalBottomSheet<bool>(
    context: context,
    isScrollControlled: true,
    useSafeArea: true,
    builder: (_) => _LiveHarvestCreateSheet(
      scope: scope,
      selectedScope: selectedScope,
      zone: zone,
      planting: planting,
    ),
  );
  if (!context.mounted || saved != true) return;
  ref.invalidate(syncStatusProvider);
  ref.invalidate(farmlyLiveZoneCollectionProvider);
  showFarmToast(context, AppLocalizations.of(context).liveFarmSavedPending);
}

class _LiveHarvestCreateSheetState
    extends ConsumerState<_LiveHarvestCreateSheet> {
  final _quantityKg = TextEditingController();
  final _harvestDate = TextEditingController();
  String? _error;
  bool _saving = false;

  @override
  void dispose() {
    _quantityKg.dispose();
    _harvestDate.dispose();
    super.dispose();
  }

  bool _scopeIsCurrent() => _scopeIsCurrentAgainst(
    ref.read(farmlyLiveZoneCollectionProvider).asData?.value,
  );

  bool _scopeIsCurrentAgainst(FarmlyLiveZoneCollection? projection) {
    if (projection == null ||
        projection.cacheState != FarmlyZoneCacheState.ready ||
        !_sameFarmScope(widget.scope, projection.scope) ||
        !_sameSelection(widget.selectedScope, projection.selectedScope) ||
        !_capturedFarmScopeIsCurrent(
          ref,
          widget.scope,
          widget.selectedScope,
          allowWorker: true,
        )) {
      return false;
    }

    final plantings = projection.plantings
        .where((row) => row.planting.id == widget.planting.planting.id)
        .toList(growable: false);
    final zones = projection.zones
        .where((row) => row.zone.id == widget.zone.zone.id)
        .toList(growable: false);
    if (plantings.length != 1 || zones.length != 1) return false;

    final currentPlanting = plantings.single;
    final currentZone = zones.single;
    if (!currentPlanting.isUniqueConfirmedRecord ||
        currentPlanting.planting.status != 'active' ||
        currentPlanting.syncState == FarmlyZoneSyncState.needsAttention ||
        currentPlanting.hasUnresolvedUpdate ||
        currentPlanting.hasUnresolvedArchive ||
        widget.zone.zone.id != widget.planting.planting.plotId ||
        currentPlanting.planting.version != widget.planting.planting.version ||
        currentPlanting.planting.plotId != widget.planting.planting.plotId ||
        currentPlanting.planting.cropSpeciesId !=
            widget.planting.planting.cropSpeciesId ||
        currentPlanting.operationId != widget.planting.operationId ||
        currentPlanting.planting.plotId != currentZone.zone.id ||
        currentZone.zone.type != 'crop_plot' ||
        currentZone.zone.status != 'active' ||
        currentZone.syncState == FarmlyZoneSyncState.needsAttention) {
      return false;
    }

    final species = projection.cropSpecies
        .where(
          (row) => row.species.id == currentPlanting.planting.cropSpeciesId,
        )
        .toList(growable: false);
    return species.length == 1 &&
        species.single.species.status == 'active' &&
        species.single.syncState != FarmlyZoneSyncState.needsAttention;
  }

  String? _validate(AppLocalizations l10n) {
    if (!_scopeIsCurrent()) return l10n.liveFarmScopeChanged;
    final quantity = _quantityKg.text.trim().replaceAll(',', '.');
    if (!_isValidHarvestQuantity(quantity)) {
      return l10n.liveHarvestQuantityInvalid;
    }
    if (!_isValidCivilDate(_harvestDate.text.trim())) {
      return l10n.liveHarvestDateInvalid;
    }
    return null;
  }

  Future<void> _save() async {
    if (_saving) return;
    final l10n = AppLocalizations.of(context);
    final validation = _validate(l10n);
    if (validation != null) {
      setState(() => _error = validation);
      return;
    }

    setState(() {
      _saving = true;
      _error = null;
    });
    try {
      final session = await ref.read(farmlyAuthSessionProvider.future);
      final engine = await ref.read(syncEngineProvider.future);
      if (!mounted ||
          session == null ||
          session.user.id != widget.scope.accountId ||
          !_scopeIsCurrent()) {
        throw StateError('Farm scope changed before local save');
      }
      final dependencies = <String>[
        if (widget.planting.operationId != null) widget.planting.operationId!,
      ];
      final quantity = _quantityKg.text.trim().replaceAll(',', '.');
      await engine.enqueue(
        FarmlyScopedMutation(
          scope: widget.scope,
          intent: FarmlyCreateHarvestIntent(
            operationId: newFarmlyOperationId(),
            continuityEpoch: widget.scope.continuityEpoch,
            resourceId: newFarmlyOperationId(),
            plantingId: widget.planting.planting.id,
            quantityKg: FarmlyDecimal.parse(quantity),
            harvestDate: _harvestDate.text.trim(),
            dependsOn: dependencies,
          ),
        ),
      );
      ref.invalidate(syncStatusProvider);
      ref.invalidate(farmlyLiveZoneCollectionProvider);
      if (mounted) Navigator.of(context).pop(true);
    } on Object {
      if (!mounted) return;
      setState(
        () => _error = _scopeIsCurrent()
            ? l10n.liveHarvestSaveFailed
            : l10n.liveFarmScopeChanged,
      );
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    ref.watch(selectedOrganizationScopeProvider);
    ref.watch(farmlySyncScopeProvider);
    ref.watch(farmlyAuthSessionProvider);
    ref.watch(farmlyLiveZoneCollectionProvider);
    final l10n = AppLocalizations.of(context);
    final tokens = FarmThemeExtension.of(context);
    final scopeCurrent = _scopeIsCurrent();
    final quantityError = _error == l10n.liveHarvestQuantityInvalid
        ? _error
        : null;
    final dateError = _error == l10n.liveHarvestDateInvalid ? _error : null;
    return SafeArea(
      child: SingleChildScrollView(
        padding: EdgeInsets.fromLTRB(
          FarmSpacing.lg,
          FarmSpacing.sm,
          FarmSpacing.lg,
          FarmSpacing.lg + MediaQuery.viewInsetsOf(context).bottom,
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(
              l10n.liveHarvestCreate,
              style: Theme.of(context).textTheme.titleLarge,
            ),
            const SizedBox(height: FarmSpacing.sm),
            Text(
              widget.zone.zone.name,
              style: Theme.of(
                context,
              ).textTheme.bodySmall?.copyWith(color: tokens.textSecondary),
            ),
            const SizedBox(height: FarmSpacing.lg),
            DecimalField(
              key: const ValueKey('live-harvest-quantity-kg'),
              controller: _quantityKg,
              labelText: l10n.liveHarvestQuantityLabel,
              hintText: '12,375',
              errorText: quantityError,
              helperText: l10n.liveHarvestQuantityHelper,
            ),
            const SizedBox(height: FarmSpacing.md),
            LocalDateField(
              key: const ValueKey('live-harvest-date'),
              controller: _harvestDate,
              labelText: l10n.liveHarvestDateLabel,
              hintText: '2026-10-19',
              errorText: dateError,
              helperText: l10n.harvestDateHelper,
            ),
            if (_error != null && quantityError == null && dateError == null)
              Padding(
                padding: const EdgeInsets.only(top: FarmSpacing.sm),
                child: Text(
                  _error!,
                  style: TextStyle(color: tokens.semanticWarning),
                ),
              ),
            if (!scopeCurrent) ...[
              const SizedBox(height: FarmSpacing.md),
              Text(
                l10n.liveFarmScopeChanged,
                style: TextStyle(color: tokens.semanticWarning),
              ),
            ],
            const SizedBox(height: FarmSpacing.lg),
            FilledButton(
              key: const ValueKey('live-harvest-save'),
              onPressed: _saving || !scopeCurrent ? null : _save,
              child: Text(l10n.saveOnDevice),
            ),
          ],
        ),
      ),
    );
  }
}

class _LiveHarvestActionsSheet extends ConsumerStatefulWidget {
  const _LiveHarvestActionsSheet({
    required this.scope,
    required this.selectedScope,
    required this.zone,
    required this.harvest,
    required this.canPropose,
    required this.canManage,
  });

  final FarmlyMutationScope scope;
  final FarmlyOrganizationScope selectedScope;
  final FarmlyLiveZone zone;
  final FarmlyLiveHarvest harvest;
  final bool canPropose;
  final bool canManage;

  @override
  ConsumerState<_LiveHarvestActionsSheet> createState() =>
      _LiveHarvestActionsSheetState();
}

Future<void> showLiveHarvestActions({
  required BuildContext context,
  required WidgetRef ref,
  required FarmlyLiveZoneCollection collection,
  required FarmlyLiveZone zone,
  required FarmlyLiveHarvest harvest,
  required bool canPropose,
  required bool canManage,
}) async {
  final scope = collection.scope;
  final selectedScope = collection.selectedScope;
  if (scope == null || selectedScope == null) return;
  final saved = await showModalBottomSheet<bool>(
    context: context,
    isScrollControlled: true,
    useSafeArea: true,
    builder: (_) => _LiveHarvestActionsSheet(
      scope: scope,
      selectedScope: selectedScope,
      zone: zone,
      harvest: harvest,
      canPropose: canPropose,
      canManage: canManage,
    ),
  );
  if (!context.mounted || saved != true) return;
  ref.invalidate(syncStatusProvider);
  ref.invalidate(farmlyLiveZoneCollectionProvider);
  showFarmToast(context, AppLocalizations.of(context).liveFarmSavedPending);
}

class _LiveHarvestActionsSheetState
    extends ConsumerState<_LiveHarvestActionsSheet> {
  final _proposalQuantity = TextEditingController();
  final _proposalReason = TextEditingController();
  final _correctionQuantity = TextEditingController();
  final _correctionReason = TextEditingController();
  final _voidReason = TextEditingController();
  String? _error;
  bool _directCorrection = false;
  bool _saving = false;

  @override
  void dispose() {
    _proposalQuantity.dispose();
    _proposalReason.dispose();
    _correctionQuantity.dispose();
    _correctionReason.dispose();
    _voidReason.dispose();
    super.dispose();
  }

  FarmlyLiveZoneCollection? _currentProjection() =>
      ref.read(farmlyLiveZoneCollectionProvider).asData?.value;

  FarmlyLiveHarvest? _currentHarvest() {
    final projection = _currentProjection();
    if (projection == null) return null;
    for (final harvest in projection.harvests) {
      if (harvest.id == widget.harvest.id) return harvest;
    }
    return null;
  }

  bool _scopeIsCurrent({required bool allowWorker}) {
    final projection = _currentProjection();
    final currentHarvest = _currentHarvest();
    return widget.zone.zone.type == 'crop_plot' &&
        widget.zone.zone.status == 'active' &&
        widget.zone.syncState == FarmlyZoneSyncState.confirmed &&
        widget.harvest.status == 'active' &&
        widget.harvest.version > 0 &&
        widget.harvest.syncState == FarmlyZoneSyncState.confirmed &&
        widget.harvest.pendingManagerMutationState == null &&
        projection?.cacheState == FarmlyZoneCacheState.ready &&
        projection?.scope != null &&
        _sameFarmScope(widget.scope, projection!.scope) &&
        currentHarvest?.status == 'active' &&
        currentHarvest?.version == widget.harvest.version &&
        currentHarvest?.syncState == FarmlyZoneSyncState.confirmed &&
        currentHarvest?.pendingManagerMutationState == null &&
        _capturedFarmScopeIsCurrent(
          ref,
          widget.scope,
          widget.selectedScope,
          allowWorker: allowWorker,
        );
  }

  Future<void> _proposeCorrection() async {
    final l10n = AppLocalizations.of(context);
    final quantity = _proposalQuantity.text.trim().replaceAll(',', '.');
    final reason = _proposalReason.text.trim();
    if (!_isValidHarvestQuantity(quantity)) {
      setState(() => _error = l10n.liveHarvestQuantityInvalid);
      return;
    }
    if (!_isValidHarvestReason(reason)) {
      setState(() => _error = l10n.liveHarvestCorrectionReasonInvalid);
      return;
    }
    await _enqueue(
      allowWorker: true,
      intent: () => FarmlyProposeHarvestCorrectionIntent(
        operationId: newFarmlyOperationId(),
        continuityEpoch: widget.scope.continuityEpoch,
        resourceId: widget.harvest.id,
        proposedQuantityKg: FarmlyDecimal.parse(quantity),
        reason: reason,
      ),
    );
  }

  Future<void> _applyProposal(FarmlyLiveHarvestCorrectionProposal proposal) =>
      _enqueue(
        allowWorker: false,
        intent: () => FarmlyApplyHarvestCorrectionIntent(
          operationId: newFarmlyOperationId(),
          continuityEpoch: widget.scope.continuityEpoch,
          resourceId: widget.harvest.id,
          baseVersion: widget.harvest.version,
          proposedQuantityKg: proposal.proposedQuantityKg,
          proposalId: proposal.id,
        ),
      );

  Future<void> _applyDirectCorrection() async {
    final l10n = AppLocalizations.of(context);
    final quantity = _correctionQuantity.text.trim().replaceAll(',', '.');
    final reason = _correctionReason.text.trim();
    if (!_isValidHarvestQuantity(quantity)) {
      setState(() => _error = l10n.liveHarvestQuantityInvalid);
      return;
    }
    if (reason.length > 500) {
      setState(() => _error = l10n.liveHarvestCorrectionReasonInvalid);
      return;
    }
    await _enqueue(
      allowWorker: false,
      intent: () => FarmlyApplyHarvestCorrectionIntent(
        operationId: newFarmlyOperationId(),
        continuityEpoch: widget.scope.continuityEpoch,
        resourceId: widget.harvest.id,
        baseVersion: widget.harvest.version,
        proposedQuantityKg: FarmlyDecimal.parse(quantity),
        reason: reason.isEmpty ? null : reason,
      ),
    );
  }

  Future<void> _voidHarvest() async {
    final l10n = AppLocalizations.of(context);
    final reason = _voidReason.text.trim();
    if (!_isValidHarvestReason(reason)) {
      setState(() => _error = l10n.liveHarvestCorrectionReasonInvalid);
      return;
    }
    await _enqueue(
      allowWorker: false,
      intent: () => FarmlyVoidHarvestIntent(
        operationId: newFarmlyOperationId(),
        continuityEpoch: widget.scope.continuityEpoch,
        resourceId: widget.harvest.id,
        baseVersion: widget.harvest.version,
        reason: reason,
      ),
    );
  }

  Future<void> _enqueue({
    required bool allowWorker,
    required FarmlyMutationIntent Function() intent,
  }) async {
    if (_saving) return;
    final l10n = AppLocalizations.of(context);
    if (!_scopeIsCurrent(allowWorker: allowWorker)) {
      setState(() => _error = l10n.liveFarmScopeChanged);
      return;
    }
    setState(() {
      _saving = true;
      _error = null;
    });
    try {
      final session = await ref.read(farmlyAuthSessionProvider.future);
      final engine = await ref.read(syncEngineProvider.future);
      if (!mounted ||
          session == null ||
          session.user.id != widget.scope.accountId ||
          !_scopeIsCurrent(allowWorker: allowWorker)) {
        throw StateError('Harvest scope changed before local save');
      }
      await engine.enqueue(
        FarmlyScopedMutation(scope: widget.scope, intent: intent()),
      );
      ref.invalidate(syncStatusProvider);
      ref.invalidate(farmlyLiveZoneCollectionProvider);
      if (mounted) Navigator.of(context).pop(true);
    } on Object {
      if (!mounted) return;
      setState(
        () => _error = _scopeIsCurrent(allowWorker: allowWorker)
            ? l10n.liveHarvestCorrectionSaveFailed
            : l10n.liveFarmScopeChanged,
      );
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    ref.watch(selectedOrganizationScopeProvider);
    ref.watch(farmlySyncScopeProvider);
    ref.watch(farmlyAuthSessionProvider);
    final projectionState = ref.watch(farmlyLiveZoneCollectionProvider);
    final projection = projectionState.asData?.value;
    final currentHarvest = projection?.harvests
        .where((item) => item.id == widget.harvest.id)
        .firstOrNull;
    final l10n = AppLocalizations.of(context);
    final tokens = FarmThemeExtension.of(context);
    final scopeCurrent = _scopeIsCurrent(allowWorker: true);
    final canProposeNow = widget.canPropose && scopeCurrent && !_saving;
    final canManageNow =
        widget.canManage && _scopeIsCurrent(allowWorker: false) && !_saving;
    final currentProposalRows =
        (currentHarvest?.correctionProposals ?? const [])
            .where((proposal) => proposal.status == 'pending')
            .toList(growable: false);
    final isAttention =
        widget.harvest.syncState == FarmlyZoneSyncState.needsAttention ||
        widget.harvest.pendingManagerMutationState ==
            FarmlyZoneSyncState.needsAttention ||
        currentHarvest?.pendingManagerMutationState ==
            FarmlyZoneSyncState.needsAttention;
    final pendingAction =
        currentHarvest?.pendingManagerMutationState ??
        widget.harvest.pendingManagerMutationState;

    return SafeArea(
      child: SingleChildScrollView(
        padding: EdgeInsets.fromLTRB(
          FarmSpacing.lg,
          FarmSpacing.sm,
          FarmSpacing.lg,
          FarmSpacing.lg + MediaQuery.viewInsetsOf(context).bottom,
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(
              l10n.liveHarvestDetails,
              style: Theme.of(context).textTheme.titleLarge,
            ),
            const SizedBox(height: FarmSpacing.sm),
            Text(widget.zone.zone.name),
            const SizedBox(height: FarmSpacing.xs),
            Text(
              '${formatDisplayDecimal(widget.harvest.quantityKg.value, l10n.localeName)} kg · '
              '${formatDisplayDate(widget.harvest.harvestDate, l10n.localeName) ?? widget.harvest.harvestDate}',
              style: Theme.of(context).textTheme.titleMedium,
            ),
            const SizedBox(height: FarmSpacing.sm),
            _ZoneSyncBadge(state: widget.harvest.syncState),
            if (isAttention) ...[
              const SizedBox(height: FarmSpacing.sm),
              Text(
                l10n.liveHarvestCorrectionNeedsAttention,
                style: TextStyle(color: tokens.semanticWarning),
              ),
            ] else if (pendingAction != null) ...[
              const SizedBox(height: FarmSpacing.sm),
              Row(
                children: [
                  Expanded(child: Text(l10n.liveHarvestCorrectionPending)),
                  _ZoneSyncBadge(state: pendingAction),
                ],
              ),
            ],
            if (currentProposalRows.isNotEmpty) ...[
              const SizedBox(height: FarmSpacing.lg),
              _sectionTitle(
                context,
                title: l10n.liveHarvestCorrectionProposals,
              ),
              for (final proposal in currentProposalRows)
                Padding(
                  key: ValueKey('live-harvest-proposal-${proposal.id}'),
                  padding: const EdgeInsets.only(bottom: FarmSpacing.sm),
                  child: FarmCard(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        Text(
                          '${formatDisplayDecimal(proposal.proposedQuantityKg.value, l10n.localeName)} kg',
                          style: Theme.of(context).textTheme.titleSmall,
                        ),
                        const SizedBox(height: FarmSpacing.xs),
                        Text(proposal.reason),
                        const SizedBox(height: FarmSpacing.xs),
                        Text(l10n.liveHarvestProposalStatusPending),
                        if (canManageNow &&
                            !isAttention &&
                            pendingAction == null)
                          Align(
                            alignment: Alignment.centerLeft,
                            child: OutlinedButton.icon(
                              key: ValueKey(
                                'live-harvest-apply-${proposal.id}',
                              ),
                              onPressed: () => _applyProposal(proposal),
                              icon: const Icon(Icons.check_circle_outline),
                              label: Text(l10n.liveHarvestApply),
                            ),
                          ),
                      ],
                    ),
                  ),
                ),
            ] else if (projection?.cacheState !=
                FarmlyZoneCacheState.ready) ...[
              const SizedBox(height: FarmSpacing.md),
              Text(l10n.liveHarvestProposalsUnavailable),
            ] else ...[
              const SizedBox(height: FarmSpacing.md),
              Text(l10n.liveHarvestNoCorrectionProposals),
            ],
            if (canProposeNow && !widget.canManage) ...[
              const SizedBox(height: FarmSpacing.lg),
              _sectionTitle(context, title: l10n.liveHarvestProposeSection),
              DecimalField(
                key: ValueKey(
                  'live-harvest-proposal-quantity-${widget.harvest.id}',
                ),
                controller: _proposalQuantity,
                labelText: l10n.liveHarvestNewQuantityLabel,
                hintText: '12,375',
                helperText: l10n.liveHarvestQuantityHelper,
              ),
              const SizedBox(height: FarmSpacing.sm),
              TextField(
                key: ValueKey(
                  'live-harvest-proposal-reason-${widget.harvest.id}',
                ),
                controller: _proposalReason,
                maxLength: 500,
                decoration: InputDecoration(
                  labelText: l10n.liveHarvestCorrectionReasonLabel,
                ),
              ),
              const SizedBox(height: FarmSpacing.sm),
              FilledButton.icon(
                key: ValueKey('live-harvest-propose-${widget.harvest.id}'),
                onPressed: canProposeNow ? _proposeCorrection : null,
                icon: const Icon(Icons.send_outlined),
                label: Text(l10n.liveHarvestProposeCorrection),
              ),
            ],
            if (widget.canManage &&
                widget.harvest.status == 'active' &&
                widget.harvest.version > 0 &&
                widget.harvest.syncState == FarmlyZoneSyncState.confirmed &&
                widget.harvest.pendingManagerMutationState == null) ...[
              const SizedBox(height: FarmSpacing.lg),
              if (_directCorrection) ...[
                _sectionTitle(context, title: l10n.liveHarvestAdjust),
                DecimalField(
                  key: ValueKey(
                    'live-harvest-correction-quantity-${widget.harvest.id}',
                  ),
                  controller: _correctionQuantity,
                  labelText: l10n.liveHarvestNewQuantityLabel,
                  hintText: '12,375',
                  helperText: l10n.liveHarvestQuantityHelper,
                ),
                const SizedBox(height: FarmSpacing.sm),
                TextField(
                  key: ValueKey(
                    'live-harvest-correction-reason-${widget.harvest.id}',
                  ),
                  controller: _correctionReason,
                  maxLength: 500,
                  decoration: InputDecoration(
                    labelText: l10n.liveHarvestCorrectionReasonLabel,
                  ),
                ),
                FilledButton.icon(
                  key: ValueKey(
                    'live-harvest-apply-direct-${widget.harvest.id}',
                  ),
                  onPressed: canManageNow ? _applyDirectCorrection : null,
                  icon: const Icon(Icons.check_circle_outline),
                  label: Text(l10n.liveHarvestApply),
                ),
                TextButton(
                  onPressed: _saving
                      ? null
                      : () => setState(() {
                          _directCorrection = false;
                          _error = null;
                        }),
                  child: Text(l10n.cancel),
                ),
              ] else if (!_directCorrection) ...[
                OutlinedButton.icon(
                  key: ValueKey('live-harvest-adjust-${widget.harvest.id}'),
                  onPressed: canManageNow
                      ? () => setState(() {
                          _directCorrection = true;
                          _error = null;
                        })
                      : null,
                  icon: const Icon(Icons.edit_outlined),
                  label: Text(l10n.liveHarvestAdjust),
                ),
                const SizedBox(height: FarmSpacing.md),
                _sectionTitle(context, title: l10n.liveHarvestVoidSection),
                TextField(
                  key: ValueKey(
                    'live-harvest-void-reason-${widget.harvest.id}',
                  ),
                  controller: _voidReason,
                  maxLength: 500,
                  decoration: InputDecoration(
                    labelText: l10n.liveHarvestVoidReasonLabel,
                  ),
                ),
                FilledButton.tonalIcon(
                  key: ValueKey('live-harvest-void-${widget.harvest.id}'),
                  onPressed: canManageNow ? _voidHarvest : null,
                  icon: const Icon(Icons.remove_circle_outline),
                  label: Text(l10n.liveHarvestVoid),
                ),
              ],
            ],
            if (!scopeCurrent) ...[
              const SizedBox(height: FarmSpacing.md),
              Text(
                l10n.liveFarmScopeChanged,
                style: TextStyle(color: tokens.semanticWarning),
              ),
            ],
            if (_error != null) ...[
              const SizedBox(height: FarmSpacing.sm),
              Text(_error!, style: TextStyle(color: tokens.semanticWarning)),
            ],
            if (widget.harvest.status == 'voided') ...[
              const SizedBox(height: FarmSpacing.md),
              Text(l10n.liveHarvestVoided),
            ],
          ],
        ),
      ),
    );
  }
}

bool _isValidHarvestQuantity(String value) =>
    RegExp(r'^(0|[1-9][0-9]{0,15})(\.[0-9]{1,4})?$').hasMatch(value) &&
    RegExp(r'[1-9]').hasMatch(value);

bool _isValidHarvestReason(String value) =>
    value.isNotEmpty && value.length <= 500;

bool _isValidCivilDate(String value) {
  if (!RegExp(r'^\d{4}-\d{2}-\d{2}$').hasMatch(value)) return false;
  final parsed = DateTime.tryParse('${value}T00:00:00');
  return parsed != null && _formatCivilDate(parsed) == value;
}

class _DatePickerField extends StatelessWidget {
  const _DatePickerField({
    required this.label,
    required this.value,
    required this.enabled,
    required this.onTap,
    super.key,
  });

  final String label;
  final String? value;
  final bool enabled;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) => InkWell(
    onTap: enabled ? onTap : null,
    borderRadius: BorderRadius.circular(FarmSpacing.inputRadius),
    child: InputDecorator(
      decoration: InputDecoration(
        labelText: label,
        suffixIcon: const Icon(Icons.calendar_month_outlined),
      ),
      child: Text(
        value ?? AppLocalizations.of(context).livePlantingChooseDate,
        style: Theme.of(context).textTheme.bodyLarge?.copyWith(
          color: value == null
              ? FarmThemeExtension.of(context).textSecondary
              : null,
        ),
      ),
    ),
  );
}

bool _capturedFarmScopeIsCurrent(
  WidgetRef ref,
  FarmlyMutationScope scope,
  FarmlyOrganizationScope selectedScope, {
  bool allowWorker = false,
}) {
  final currentSelection = ref.read(selectedOrganizationScopeProvider);
  final currentSyncScope = ref.read(farmlySyncScopeProvider).asData?.value;
  final currentAccount = ref
      .read(farmlyAuthSessionProvider)
      .asData
      ?.value
      ?.user
      .id;
  final currentFarm = currentSelection?.selectedFarm;
  return currentAccount == scope.accountId &&
      _sameSelection(selectedScope, currentSelection) &&
      _sameFarmScope(scope, currentSyncScope) &&
      currentFarm != null &&
      currentFarm.status == FarmlyFarmStatus.active &&
      (allowWorker
          ? _canRecordHarvest(currentSelection!, currentFarm)
          : _canManageZones(currentSelection!, currentFarm));
}

String _formatCivilDate(DateTime date) =>
    '${date.year.toString().padLeft(4, '0')}-'
    '${date.month.toString().padLeft(2, '0')}-'
    '${date.day.toString().padLeft(2, '0')}';

String _cropUnitLabel(AppLocalizations l10n, String unit) => switch (unit) {
  'kg' => l10n.cropHarvestUnitKg,
  'litre' => l10n.cropHarvestUnitLitre,
  'pieces' => l10n.cropHarvestUnitPieces,
  _ => unit,
};

String _taskTemplateKindLabel(AppLocalizations l10n, String kind) =>
    switch (kind) {
      'feeding' => l10n.liveTaskKindFeeding,
      'irrigation' => l10n.liveTaskKindIrrigation,
      _ => l10n.liveTaskKindGeneral,
    };

String _taskTemplateScheduleLabel(
  AppLocalizations l10n,
  FarmlyLiveTaskTemplate template,
) {
  if (!template.scheduleValid) {
    if (template.frequency == 'weekly' && template.daysOfWeek.isEmpty) {
      return l10n.liveTaskScheduleWeeklyNeedsDays;
    }
    return l10n.liveTaskScheduleInvalid;
  }
  if (template.frequency == 'daily') {
    return l10n.liveTaskScheduleDaily(template.timeOfDay);
  }
  final days = template.daysOfWeek
      .map((day) => _taskWeekdayLabel(l10n, day))
      .join(', ');
  return l10n.liveTaskScheduleWeeklyOnDays(days, template.timeOfDay);
}

String _taskWeekdayLabel(AppLocalizations l10n, int day) => switch (day) {
  0 => l10n.liveTaskDaySunday,
  1 => l10n.liveTaskDayMonday,
  2 => l10n.liveTaskDayTuesday,
  3 => l10n.liveTaskDayWednesday,
  4 => l10n.liveTaskDayThursday,
  5 => l10n.liveTaskDayFriday,
  6 => l10n.liveTaskDaySaturday,
  _ => throw ArgumentError.value(day, 'day', 'must be between 0 and 6'),
};

List<String> _availableTaskOccurrenceTransitions({
  required FarmlyLiveTaskTemplate template,
  required FarmlyLiveTaskOccurrence occurrence,
  required bool canManage,
  required bool canWorker,
  required String? membershipId,
}) {
  if (occurrence.syncState != FarmlyZoneSyncState.confirmed ||
      template.syncState != FarmlyZoneSyncState.confirmed ||
      template.version < 1 ||
      template.status != 'active' ||
      !farmlyTaskDateWithinWindow(
        startsOn: template.startsOn,
        endsOn: template.endsOn,
        occurrenceDate: occurrence.occurrenceDate,
      )) {
    return const [];
  }
  if (canManage) {
    return switch (occurrence.status) {
      'open' => const ['complete', 'skip', 'cancel'],
      'done' || 'skipped' => const ['reopen', 'cancel'],
      'cancelled' => const ['reopen'],
      _ => const [],
    };
  }
  if (canWorker &&
      occurrence.status == 'open' &&
      (template.assigneeMembershipId == null ||
          (membershipId != null &&
              template.assigneeMembershipId == membershipId))) {
    return const ['complete', 'skip'];
  }
  return const [];
}

String _taskOccurrenceStatusLabel(AppLocalizations l10n, String status) =>
    switch (status) {
      'open' => l10n.liveTaskOccurrenceOpen,
      'in_progress' => l10n.liveTaskOccurrenceInProgress,
      'done' => l10n.liveTaskOccurrenceDone,
      'skipped' => l10n.liveTaskOccurrenceSkipped,
      'cancelled' => l10n.liveTaskOccurrenceCancelled,
      _ => status,
    };

String _taskOccurrenceTransitionLabel(AppLocalizations l10n, String action) =>
    switch (action) {
      'complete' => l10n.liveTaskTransitionComplete,
      'skip' => l10n.liveTaskTransitionSkip,
      'reopen' => l10n.liveTaskTransitionReopen,
      'cancel' => l10n.liveTaskTransitionCancel,
      _ => action,
    };

IconData _taskOccurrenceTransitionIcon(String action) => switch (action) {
  'complete' => Icons.check_circle_outline,
  'skip' => Icons.skip_next_outlined,
  'reopen' => Icons.restart_alt,
  'cancel' => Icons.cancel_outlined,
  _ => Icons.task_alt_outlined,
};

class _LiveTaskOccurrenceCard extends ConsumerStatefulWidget {
  const _LiveTaskOccurrenceCard({
    required this.scope,
    required this.selectedScope,
    required this.zoneId,
    required this.template,
    required this.occurrence,
    required this.canManage,
    required this.canWorker,
    super.key,
  });

  final FarmlyMutationScope scope;
  final FarmlyOrganizationScope selectedScope;
  final String zoneId;
  final FarmlyLiveTaskTemplate template;
  final FarmlyLiveTaskOccurrence occurrence;
  final bool canManage;
  final bool canWorker;

  @override
  ConsumerState<_LiveTaskOccurrenceCard> createState() =>
      _LiveTaskOccurrenceCardState();
}

class _LiveTaskOccurrenceCardState
    extends ConsumerState<_LiveTaskOccurrenceCard> {
  bool _saving = false;
  String? _error;

  bool _scopeIsCurrent() =>
      _capturedFarmScopeIsCurrent(
        ref,
        widget.scope,
        widget.selectedScope,
        allowWorker: true,
      ) &&
      ref.read(farmlyLiveZoneCollectionProvider).asData?.value.cacheState ==
          FarmlyZoneCacheState.ready;

  void _setError(String message) {
    if (mounted) setState(() => _error = message);
  }

  Future<void> _transition(String transition) async {
    if (_saving) return;
    final l10n = AppLocalizations.of(context);
    if (!_scopeIsCurrent()) {
      _setError(l10n.liveFarmScopeChanged);
      return;
    }
    setState(() {
      _saving = true;
      _error = null;
    });
    try {
      final engine = await ref.read(syncEngineProvider.future);
      if (!_scopeIsCurrent()) {
        _setError(l10n.liveFarmScopeChanged);
        return;
      }
      final snapshot = await engine.domainSnapshot(widget.scope);
      if (!_scopeIsCurrent() ||
          snapshot == null ||
          snapshot.cursor.continuityEpoch !=
              widget.selectedScope.directory.continuityEpoch ||
          snapshot.cursor.scopePolicyVersion !=
              widget.selectedScope.directory.scopePolicyVersion) {
        _setError(l10n.liveFarmScopeChanged);
        return;
      }

      final farmRow = snapshot.recordsFor('farm')[widget.scope.farmId];
      if (farmRow is! Map) {
        _setError(l10n.liveFarmScopeChanged);
        return;
      }
      final farm = Map<String, dynamic>.from(farmRow);
      final timezone = farm['timezone'];
      if (farm['farmId'] != widget.scope.farmId || timezone is! String) {
        _setError(l10n.liveTaskTimezoneUnavailable);
        return;
      }
      final farmLocalDate = farmlyTaskCivilDateAtUtc(
        ref.read(farmlyUtcNowProvider)(),
        timezone,
      );
      if (farmLocalDate != widget.occurrence.occurrenceDate) {
        _setError(l10n.liveFarmScopeChanged);
        return;
      }

      final zoneRow = snapshot.recordsFor('zone')[widget.zoneId];
      if (zoneRow is! Map ||
          Map<String, dynamic>.from(zoneRow)['status'] != 'active') {
        _setError(l10n.liveFarmScopeChanged);
        return;
      }
      final templateRow = snapshot.recordsFor(
        'taskTemplate',
      )[widget.template.id];
      if (templateRow is! Map) {
        _setError(l10n.liveFarmScopeChanged);
        return;
      }
      final template = _farmlyLiveTaskTemplateFromJson(
        Map<String, dynamic>.from(templateRow),
        syncState: FarmlyZoneSyncState.confirmed,
      );
      if (template.zoneId != widget.zoneId ||
          template.status != 'active' ||
          !template.scheduleValid) {
        _setError(l10n.liveFarmScopeChanged);
        return;
      }
      if (!farmlyTaskDateWithinWindow(
        startsOn: template.startsOn,
        endsOn: template.endsOn,
        occurrenceDate: farmLocalDate,
      )) {
        _setError(l10n.liveFarmScopeChanged);
        return;
      }
      final expectedId = farmlyTaskOccurrenceResourceId(
        farmId: widget.scope.farmId!,
        templateId: template.id,
        occurrenceDate: farmLocalDate,
        slot: widget.occurrence.slot,
      );
      if (expectedId != widget.occurrence.id) {
        _setError(l10n.liveFarmScopeChanged);
        return;
      }
      final occurrenceRow = snapshot.recordsFor(
        'taskOccurrence',
      )[widget.occurrence.id];
      final FarmlyLiveTaskOccurrence occurrence;
      if (occurrenceRow is Map) {
        occurrence = _farmlyLiveTaskOccurrenceFromJson(
          Map<String, dynamic>.from(occurrenceRow),
          farmId: widget.scope.farmId!,
        );
      } else if (!widget.occurrence.isMaterialized &&
          farmlyTaskScheduleIncludesDate(
            frequency: template.frequency,
            daysOfWeek: template.daysOfWeek,
            startsOn: template.startsOn,
            endsOn: template.endsOn,
            occurrenceDate: farmLocalDate,
          )) {
        occurrence = FarmlyLiveTaskOccurrence(
          id: expectedId,
          templateId: template.id,
          occurrenceDate: farmLocalDate,
          slot: widget.occurrence.slot,
          status: 'open',
          version: null,
          isMaterialized: false,
          syncState: FarmlyZoneSyncState.confirmed,
        );
      } else {
        _setError(l10n.liveFarmScopeChanged);
        return;
      }
      if (occurrence.occurrenceDate != farmLocalDate ||
          occurrence.status != 'open' && !occurrence.isMaterialized ||
          (occurrence.isMaterialized && occurrence.version == null)) {
        _setError(l10n.liveFarmScopeChanged);
        return;
      }

      final currentSelection = ref.read(selectedOrganizationScopeProvider);
      final currentFarm = currentSelection?.selectedFarm;
      if (currentSelection == null ||
          currentFarm == null ||
          currentFarm.status != FarmlyFarmStatus.active ||
          !_availableTaskOccurrenceTransitions(
            template: template,
            occurrence: occurrence,
            canManage: _canManageZones(currentSelection, currentFarm),
            canWorker:
                currentFarm.grantRole == FarmlyFarmGrantRole.worker &&
                _canRecordHarvest(currentSelection, currentFarm),
            membershipId: currentSelection.organization.membershipId,
          ).contains(transition)) {
        _setError(l10n.liveFarmScopeChanged);
        return;
      }

      final entries = await engine.entries(
        accountId: widget.scope.accountId,
        organizationId: widget.scope.organizationId,
      );
      if (!_scopeIsCurrent()) {
        _setError(l10n.liveFarmScopeChanged);
        return;
      }
      for (final entry in entries) {
        final intent = entry.mutation.intent;
        if (!_entryMatchesScope(entry, widget.scope) ||
            intent.resourceId != occurrence.id ||
            (intent.type != 'taskOccurrence.transition' &&
                intent.type != 'irrigationTask.transition')) {
          continue;
        }
        final reflectedAfter = intent.baseVersion ?? 1;
        if (entry.status == OutboxEntryStatus.applied &&
            occurrence.isMaterialized &&
            occurrence.version! > reflectedAfter) {
          continue;
        }
        _setError(l10n.liveTaskTransitionSaveFailed);
        return;
      }

      final intent = FarmlyTaskOccurrenceTransitionIntent(
        operationId: newFarmlyOperationId(),
        continuityEpoch: widget.scope.continuityEpoch,
        resourceId: occurrence.id,
        templateId: template.id,
        occurrenceDate: farmLocalDate,
        slot: occurrence.slot,
        transition: transition,
        baseVersion: occurrence.isMaterialized ? occurrence.version : null,
        irrigation: template.kind == 'irrigation',
      );
      if (!_scopeIsCurrent()) {
        _setError(l10n.liveFarmScopeChanged);
        return;
      }
      await engine.enqueue(
        FarmlyScopedMutation(scope: widget.scope, intent: intent),
      );
      ref.invalidate(syncStatusProvider);
      ref.invalidate(farmlyLiveZoneCollectionProvider);
      if (mounted) {
        showFarmToast(context, l10n.liveTaskTransitionSavedPending);
      }
    } on Object {
      _setError(l10n.liveTaskTransitionSaveFailed);
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final transitions = _availableTaskOccurrenceTransitions(
      template: widget.template,
      occurrence: widget.occurrence,
      canManage: widget.canManage,
      canWorker: widget.canWorker,
      membershipId: widget.selectedScope.organization.membershipId,
    );
    final date =
        formatDisplayDate(widget.occurrence.occurrenceDate, l10n.localeName) ??
        widget.occurrence.occurrenceDate;
    return Padding(
      padding: const EdgeInsets.only(bottom: FarmSpacing.xs),
      child: FarmCard(
        key: ValueKey('live-task-occurrence-row-${widget.occurrence.id}'),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Icon(
                  widget.template.kind == 'irrigation'
                      ? Icons.water_drop_outlined
                      : Icons.task_alt_outlined,
                ),
                const SizedBox(width: FarmSpacing.sm),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        widget.template.title,
                        style: Theme.of(context).textTheme.titleSmall,
                      ),
                      const SizedBox(height: FarmSpacing.xs),
                      Text(
                        '${_taskTemplateKindLabel(l10n, widget.template.kind)} · '
                        '${widget.template.timeOfDay} · $date',
                        style: Theme.of(context).textTheme.bodySmall,
                      ),
                      const SizedBox(height: FarmSpacing.xs),
                      Text(
                        _taskOccurrenceStatusLabel(
                          l10n,
                          widget.occurrence.status,
                        ),
                        key: ValueKey(
                          'live-task-occurrence-status-${widget.occurrence.id}',
                        ),
                        style: Theme.of(context).textTheme.labelLarge,
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: FarmSpacing.sm),
                _ZoneSyncBadge(state: widget.occurrence.syncState),
              ],
            ),
            if (transitions.isNotEmpty) ...[
              const SizedBox(height: FarmSpacing.md),
              Wrap(
                spacing: FarmSpacing.xs,
                runSpacing: FarmSpacing.xs,
                children: [
                  for (final transition in transitions)
                    OutlinedButton.icon(
                      key: ValueKey(
                        'live-task-occurrence-${widget.occurrence.id}-$transition',
                      ),
                      onPressed: _saving ? null : () => _transition(transition),
                      icon: Icon(_taskOccurrenceTransitionIcon(transition)),
                      label: Text(
                        _taskOccurrenceTransitionLabel(l10n, transition),
                      ),
                    ),
                ],
              ),
            ],
            if (_error != null) ...[
              const SizedBox(height: FarmSpacing.sm),
              Text(
                _error!,
                style: TextStyle(
                  color: FarmThemeExtension.of(context).semanticWarning,
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

String _plantingStatusLabel(AppLocalizations l10n, String status) =>
    switch (status) {
      'planned' => l10n.livePlantingStatusPlanned,
      'active' => l10n.livePlantingStatusActive,
      'harvested' => l10n.livePlantingStatusHarvested,
      'completed' => l10n.livePlantingStatusCompleted,
      'archived' => l10n.livePlantingStatusArchived,
      _ => status,
    };

String _moistureMethodLabel(AppLocalizations l10n, String method) =>
    switch (method) {
      'relative_percent' => l10n.moistureMethodRelativePercent,
      'vwc_percent' => l10n.moistureMethodVwcPercent,
      _ => method,
    };

String _formatFarmMeasurementTime(
  String measuredAt,
  String? farmTimezone,
  String localeName,
) {
  if (farmTimezone == null || farmTimezone.trim().isEmpty) return measuredAt;
  try {
    final farmTime = farmlyTaskDateTimeAtUtc(
      DateTime.parse(measuredAt),
      farmTimezone,
    );
    final farmDate = _formatCivilDate(farmTime);
    final displayDate = formatDisplayDate(farmDate, localeName) ?? farmDate;
    final hour = farmTime.hour.toString().padLeft(2, '0');
    final minute = farmTime.minute.toString().padLeft(2, '0');
    return '$displayDate $hour:$minute';
  } on Object {
    // Retain the exact offset-bearing timestamp if a legacy snapshot carries
    // an unavailable farm timezone. Never substitute the device timezone.
    return measuredAt;
  }
}

class _StatusCard extends StatelessWidget {
  const _StatusCard({
    required this.icon,
    required this.title,
    required this.body,
    this.actionLabel,
    this.onAction,
    super.key,
  });

  final IconData icon;
  final String title;
  final String body;
  final String? actionLabel;
  final VoidCallback? onAction;

  @override
  Widget build(BuildContext context) {
    final tokens = FarmThemeExtension.of(context);
    return FarmCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, color: tokens.brandAction, size: 28),
          const SizedBox(height: FarmSpacing.md),
          Text(title, style: Theme.of(context).textTheme.titleMedium),
          const SizedBox(height: FarmSpacing.xs),
          Text(body, softWrap: true),
          if (actionLabel != null) ...[
            const SizedBox(height: FarmSpacing.md),
            OutlinedButton.icon(
              onPressed: onAction,
              icon: const Icon(Icons.sync_outlined),
              label: Text(actionLabel!),
            ),
          ],
        ],
      ),
    );
  }
}

class _ZoneSyncBadge extends StatelessWidget {
  const _ZoneSyncBadge({required this.state});

  final FarmlyZoneSyncState state;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final tokens = FarmThemeExtension.of(context);
    final label = switch (state) {
      FarmlyZoneSyncState.confirmed => l10n.syncSynced,
      FarmlyZoneSyncState.savedOnDevice => l10n.pendingSyncChip,
      FarmlyZoneSyncState.checkingServer => l10n.syncCheckingServerResult,
      FarmlyZoneSyncState.needsAttention => l10n.syncRejectedNeedsReview,
      FarmlyZoneSyncState.awaitingProjection => l10n.liveFarmAwaitingProjection,
    };
    final color = switch (state) {
      FarmlyZoneSyncState.confirmed => tokens.brandSage,
      FarmlyZoneSyncState.savedOnDevice ||
      FarmlyZoneSyncState.checkingServer ||
      FarmlyZoneSyncState.awaitingProjection => tokens.textSecondary,
      FarmlyZoneSyncState.needsAttention => tokens.semanticWarning,
    };
    return Semantics(
      label: label,
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 180),
        child: Chip(
          label: Text(
            label,
            maxLines: 1,
            softWrap: false,
            overflow: TextOverflow.ellipsis,
          ),
          visualDensity: VisualDensity.compact,
          labelStyle: TextStyle(color: color),
          side: BorderSide(color: color.withValues(alpha: 0.28)),
          backgroundColor: color.withValues(alpha: 0.08),
        ),
      ),
    );
  }
}

IconData _zoneIcon(String type) => switch (type) {
  'house' => Icons.home_work_outlined,
  'crop_plot' => Icons.grass,
  'livestock_area' => Icons.pets_outlined,
  'water' => Icons.water_drop_outlined,
  'storage' => Icons.warehouse_outlined,
  _ => Icons.landscape_outlined,
};

String _zoneTypeLabel(AppLocalizations l10n, String type) => switch (type) {
  'house' => l10n.zoneKindHouse,
  'crop_plot' => l10n.zoneKindCrop,
  'livestock_area' => l10n.zoneKindLivestock,
  'water' => l10n.zoneKindWater,
  'storage' => l10n.zoneKindStorage,
  _ => l10n.zoneKindOther,
};

class _LiveZoneCreateSheet extends ConsumerStatefulWidget {
  const _LiveZoneCreateSheet({
    required this.scope,
    required this.selectedScope,
  });

  final FarmlyMutationScope scope;
  final FarmlyOrganizationScope selectedScope;

  @override
  ConsumerState<_LiveZoneCreateSheet> createState() =>
      _LiveZoneCreateSheetState();
}

class _LiveZoneCreateSheetState extends ConsumerState<_LiveZoneCreateSheet> {
  static const _defaultGeometry = <Map<String, String>>[
    {'x': '0.28', 'y': '0.28'},
    {'x': '0.72', 'y': '0.28'},
    {'x': '0.72', 'y': '0.72'},
    {'x': '0.28', 'y': '0.72'},
  ];

  final _name = TextEditingController();
  String _type = 'crop_plot';
  String? _error;
  bool _saving = false;

  @override
  void dispose() {
    _name.dispose();
    super.dispose();
  }

  bool _scopeIsCurrent() {
    final currentSelection = ref.read(selectedOrganizationScopeProvider);
    final currentScope = ref.read(farmlySyncScopeProvider).asData?.value;
    final currentAccount = ref
        .read(farmlyAuthSessionProvider)
        .asData
        ?.value
        ?.user
        .id;
    return currentAccount == widget.scope.accountId &&
        _sameSelection(widget.selectedScope, currentSelection) &&
        _sameFarmScope(widget.scope, currentScope) &&
        currentSelection?.selectedFarm?.status == FarmlyFarmStatus.active &&
        _canManageZones(currentSelection!, currentSelection.selectedFarm!);
  }

  Future<void> _save() async {
    final l10n = AppLocalizations.of(context);
    final name = _name.text.trim();
    if (name.isEmpty) {
      setState(() => _error = l10n.zoneNameRequired);
      return;
    }
    if (!_scopeIsCurrent()) {
      setState(() => _error = l10n.liveFarmScopeChanged);
      return;
    }

    setState(() {
      _saving = true;
      _error = null;
    });
    try {
      final session = await ref.read(farmlyAuthSessionProvider.future);
      final engine = await ref.read(syncEngineProvider.future);
      if (session == null || !_scopeIsCurrent()) {
        throw StateError('Farm scope changed before local save');
      }
      final mutation = FarmlyScopedMutation(
        scope: widget.scope,
        intent: FarmlyCreateZoneIntent(
          operationId: newFarmlyOperationId(),
          continuityEpoch: widget.scope.continuityEpoch,
          resourceId: newFarmlyOperationId(),
          name: name,
          type: _type,
          geometry: _defaultGeometry,
        ),
      );
      await engine.enqueue(mutation);
      ref.invalidate(syncStatusProvider);
      ref.invalidate(farmlyLiveZoneCollectionProvider);
      if (mounted) Navigator.of(context).pop(true);
    } on Object {
      if (!mounted) return;
      setState(
        () => _error = _scopeIsCurrent()
            ? l10n.liveFarmZoneSaveFailed
            : l10n.liveFarmScopeChanged,
      );
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final tokens = FarmThemeExtension.of(context);
    final scopeCurrent = _scopeIsCurrent();
    return SafeArea(
      child: SingleChildScrollView(
        padding: EdgeInsets.fromLTRB(
          FarmSpacing.lg,
          FarmSpacing.sm,
          FarmSpacing.lg,
          FarmSpacing.lg + MediaQuery.of(context).viewInsets.bottom,
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(
              l10n.liveFarmAddZone,
              style: Theme.of(context).textTheme.titleLarge,
            ),
            const SizedBox(height: FarmSpacing.xs),
            Text(
              '${widget.selectedScope.organization.name} · '
              '${widget.selectedScope.selectedFarm?.name ?? ''}',
              style: Theme.of(
                context,
              ).textTheme.bodySmall?.copyWith(color: tokens.textSecondary),
            ),
            const SizedBox(height: FarmSpacing.lg),
            TextField(
              key: const ValueKey('live-zone-name'),
              controller: _name,
              autofocus: true,
              enabled: !_saving && scopeCurrent,
              maxLength: 160,
              decoration: InputDecoration(
                labelText: l10n.zoneNameLabel,
                hintText: l10n.zoneNameHint,
                errorText: _error,
              ),
              onSubmitted: (_) => _save(),
            ),
            const SizedBox(height: FarmSpacing.md),
            Text(
              l10n.zoneKindLabel,
              style: Theme.of(context).textTheme.titleSmall,
            ),
            const SizedBox(height: FarmSpacing.sm),
            Wrap(
              spacing: FarmSpacing.sm,
              runSpacing: FarmSpacing.sm,
              children: [
                for (final kind in const [
                  'crop_plot',
                  'livestock_area',
                  'water',
                  'storage',
                  'house',
                  'other',
                ])
                  ChoiceChip(
                    label: Text(_zoneTypeLabel(l10n, kind)),
                    selected: _type == kind,
                    onSelected: _saving || !scopeCurrent
                        ? null
                        : (_) => setState(() => _type = kind),
                  ),
              ],
            ),
            if (!scopeCurrent) ...[
              const SizedBox(height: FarmSpacing.md),
              Text(
                l10n.liveFarmScopeChanged,
                style: TextStyle(color: tokens.semanticWarning),
              ),
            ],
            const SizedBox(height: FarmSpacing.lg),
            FilledButton(
              key: const ValueKey('live-zone-save'),
              onPressed: _saving || !scopeCurrent ? null : _save,
              child: Text(l10n.saveOnDevice),
            ),
          ],
        ),
      ),
    );
  }
}
