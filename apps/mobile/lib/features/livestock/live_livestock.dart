import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/auth/auth_session_controller.dart';
import '../../core/sync/farmly_mutation.dart';
import '../../core/sync/sync_models.dart';
import '../../core/sync/sync_providers.dart';
import '../../features/organizations/organization_repository.dart';
import '../../features/organizations/organization_scope_controller.dart';
import '../../generated/farmly_api_types.dart';

/// Demo records are available only in the explicitly selected visual preview.
/// Authenticated app routes use the local server projection by default.
final farmlyLivestockDemoPreviewProvider = Provider<bool>((ref) => false);

enum FarmlyLivestockCacheState {
  noFarm,
  scopeChanged,
  notBootstrapped,
  stale,
  ready,
}

enum FarmlyProductionSyncState { confirmed, savedOnDevice, awaitingProjection }

enum FarmlyLivestockEntitySyncState {
  confirmed,
  savedOnDevice,
  awaitingProjection,
}

enum FarmlyLivestockMovementSyncState { savedOnDevice, awaitingProjection }

enum FarmlyAnimalObservationSyncState {
  confirmed,
  savedOnDevice,
  awaitingProjection,
}

final class FarmlyLiveAnimalObservation {
  const FarmlyLiveAnimalObservation({
    required this.id,
    required this.kind,
    required this.note,
    required this.syncState,
    this.herdId,
    this.animalId,
    this.observedOn,
    this.sequence = 0,
  });

  final String id;
  final String? herdId;
  final String? animalId;
  final String kind;
  final String note;
  final String? observedOn;
  final FarmlyAnimalObservationSyncState syncState;
  final int sequence;
}

final class FarmlyLiveAnimalObservationLedger {
  const FarmlyLiveAnimalObservationLedger({
    required this.byHerd,
    required this.byAnimal,
    required this.attentionCount,
  });

  final Map<String, List<FarmlyLiveAnimalObservation>> byHerd;
  final Map<String, List<FarmlyLiveAnimalObservation>> byAnimal;
  final int attentionCount;
}

/// Projects immutable observations from one cursor-bound snapshot and merges
/// only exact-scope local writes. Snapshot IDs suppress retained outbox rows.
FarmlyLiveAnimalObservationLedger projectFarmlyLiveAnimalObservations({
  required Map<String, Object?> snapshotRecords,
  required List<OutboxEntry> entries,
  required FarmlyMutationScope scope,
  required Set<String> activeHerdIds,
  required Set<String> activeAnimalIds,
}) {
  final byId = <String, FarmlyLiveAnimalObservation>{};
  for (final row in snapshotRecords.values) {
    if (row is! Map) {
      throw const FormatException('Invalid local animal observation');
    }
    final observation = _decodeAnimalObservation(
      Map<String, Object?>.from(row),
      syncState: FarmlyAnimalObservationSyncState.confirmed,
    );
    if (_observationSubjectIsVisible(
      observation,
      activeHerdIds: activeHerdIds,
      activeAnimalIds: activeAnimalIds,
    )) {
      byId[observation.id] = observation;
    }
  }

  var attentionCount = 0;
  for (final entry in entries) {
    if (!_entryMatchesScope(entry, scope) ||
        entry.mutation.intent.type != 'animalObservation.create') {
      continue;
    }
    if (entry.status == OutboxEntryStatus.rejected ||
        entry.status == OutboxEntryStatus.conflict ||
        entry.status == OutboxEntryStatus.blocked) {
      attentionCount++;
      continue;
    }
    final id = entry.mutation.intent.resourceId;
    if (byId.containsKey(id) ||
        (entry.status != OutboxEntryStatus.pending &&
            entry.status != OutboxEntryStatus.inFlight &&
            entry.status != OutboxEntryStatus.applied)) {
      continue;
    }
    final observation = _decodeAnimalObservation(
      <String, Object?>{'id': id, ...entry.mutation.intent.payload},
      syncState: entry.status == OutboxEntryStatus.applied
          ? FarmlyAnimalObservationSyncState.awaitingProjection
          : FarmlyAnimalObservationSyncState.savedOnDevice,
      sequence: entry.sequence,
    );
    if (_observationSubjectIsVisible(
      observation,
      activeHerdIds: activeHerdIds,
      activeAnimalIds: activeAnimalIds,
    )) {
      byId[id] = observation;
    }
  }

  final byHerd = <String, List<FarmlyLiveAnimalObservation>>{};
  final byAnimal = <String, List<FarmlyLiveAnimalObservation>>{};
  for (final observation in byId.values) {
    final herdId = observation.herdId;
    if (herdId != null) {
      byHerd.putIfAbsent(herdId, () => []).add(observation);
    }
    final animalId = observation.animalId;
    if (animalId != null) {
      byAnimal.putIfAbsent(animalId, () => []).add(observation);
    }
  }
  void sortRecent(List<FarmlyLiveAnimalObservation> observations) {
    observations.sort((a, b) {
      final date = (b.observedOn ?? '').compareTo(a.observedOn ?? '');
      return date != 0 ? date : b.sequence.compareTo(a.sequence);
    });
  }

  for (final observations in byHerd.values) {
    sortRecent(observations);
  }
  for (final observations in byAnimal.values) {
    sortRecent(observations);
  }
  return FarmlyLiveAnimalObservationLedger(
    byHerd: Map.unmodifiable({
      for (final entry in byHerd.entries)
        entry.key: List<FarmlyLiveAnimalObservation>.unmodifiable(entry.value),
    }),
    byAnimal: Map.unmodifiable({
      for (final entry in byAnimal.entries)
        entry.key: List<FarmlyLiveAnimalObservation>.unmodifiable(entry.value),
    }),
    attentionCount: attentionCount,
  );
}

FarmlyLiveAnimalObservation _decodeAnimalObservation(
  Map<String, Object?> json, {
  required FarmlyAnimalObservationSyncState syncState,
  int sequence = 0,
}) {
  final id = json['id'];
  final herdId = json['herdId'];
  final animalId = json['animalId'];
  final note = json['note'];
  final rawKind = json['kind'];
  final observedOn = json['observedOn'];
  final kind = rawKind ?? 'note';
  if (id is! String ||
      id.isEmpty ||
      (herdId == null) == (animalId == null) ||
      (herdId != null && (herdId is! String || herdId.isEmpty)) ||
      (animalId != null && (animalId is! String || animalId.isEmpty)) ||
      note is! String ||
      note.trim().isEmpty ||
      note.length > 1000 ||
      kind is! String ||
      !const {'note', 'vet'}.contains(kind) ||
      (observedOn != null &&
          (observedOn is! String || !_isCivilDate(observedOn)))) {
    throw const FormatException('Invalid animal observation fact');
  }
  return FarmlyLiveAnimalObservation(
    id: id,
    herdId: herdId as String?,
    animalId: animalId as String?,
    kind: kind,
    note: note,
    observedOn: observedOn as String?,
    syncState: syncState,
    sequence: sequence,
  );
}

bool _observationSubjectIsVisible(
  FarmlyLiveAnimalObservation observation, {
  required Set<String> activeHerdIds,
  required Set<String> activeAnimalIds,
}) {
  final herdId = observation.herdId;
  if (herdId != null) return activeHerdIds.contains(herdId);
  return activeAnimalIds.contains(observation.animalId);
}

final class FarmlyLiveProductionRecord {
  const FarmlyLiveProductionRecord({
    required this.id,
    required this.product,
    required this.quantity,
    required this.unit,
    required this.recordedOn,
    required this.syncState,
    this.herdId,
    this.animalId,
  });

  final String id;
  final String? herdId;
  final String? animalId;
  final String product;
  final String quantity;
  final String unit;
  final String recordedOn;
  final FarmlyProductionSyncState syncState;
}

final class FarmlyLiveLivestockMovement {
  const FarmlyLiveLivestockMovement({
    required this.id,
    required this.herdId,
    required this.movementType,
    required this.delta,
    required this.syncState,
    required this.sequence,
  });

  final String id;
  final String herdId;
  final String movementType;
  final int delta;
  final FarmlyLivestockMovementSyncState syncState;
  final int sequence;
}

final class FarmlyLiveLivestockMovementLedger {
  const FarmlyLiveLivestockMovementLedger({
    required this.pendingByHerd,
    required this.pendingDeltaByHerd,
    required this.latestOperationIdByHerd,
    required this.herdsNeedingAttention,
    required this.attentionCount,
  });

  final Map<String, List<FarmlyLiveLivestockMovement>> pendingByHerd;
  final Map<String, int> pendingDeltaByHerd;
  final Map<String, String> latestOperationIdByHerd;
  final Set<String> herdsNeedingAttention;
  final int attentionCount;
}

/// Merges exact-scope local movements over one cursor-bound snapshot.
/// Snapshot resource IDs win over retained applied outbox rows so a movement
/// contributes to the estimate exactly once.
FarmlyLiveLivestockMovementLedger projectFarmlyLiveLivestockMovements({
  required Map<String, Object?> snapshotRecords,
  required List<OutboxEntry> entries,
  required FarmlyMutationScope scope,
}) {
  final confirmedIds = <String>{};
  for (final row in snapshotRecords.values) {
    if (row is! Map) {
      throw const FormatException('Invalid local livestock movement');
    }
    final json = Map<String, Object?>.from(row);
    final id = json['id'];
    final herdId = json['herdId'];
    final movementType = json['movementType'];
    final delta = json['delta'];
    if (id is! String ||
        id.isEmpty ||
        herdId is! String ||
        herdId.isEmpty ||
        movementType is! String ||
        movementType.trim().isEmpty ||
        movementType.length > 40 ||
        delta is! int ||
        delta < -2147483648 ||
        delta > 2147483647 ||
        delta == 0) {
      throw const FormatException('Invalid local livestock movement');
    }
    confirmedIds.add(id);
  }

  final pendingByHerd = <String, List<FarmlyLiveLivestockMovement>>{};
  final pendingDeltaByHerd = <String, int>{};
  final latestOperationIdByHerd = <String, String>{};
  final herdsNeedingAttention = <String>{};
  var attentionCount = 0;
  for (final entry in entries) {
    if (!_entryMatchesScope(entry, scope) ||
        entry.mutation.intent.type != 'livestockMovement.create') {
      continue;
    }

    final payload = entry.mutation.intent.payload;
    final herdId = payload['herdId'];
    if (entry.status == OutboxEntryStatus.rejected ||
        entry.status == OutboxEntryStatus.conflict ||
        entry.status == OutboxEntryStatus.blocked) {
      attentionCount++;
      if (herdId is String) herdsNeedingAttention.add(herdId);
      continue;
    }
    if (confirmedIds.contains(entry.mutation.intent.resourceId)) continue;
    if (entry.status != OutboxEntryStatus.pending &&
        entry.status != OutboxEntryStatus.inFlight &&
        entry.status != OutboxEntryStatus.applied) {
      continue;
    }

    final movementType = payload['movementType'];
    final delta = payload['delta'];
    if (herdId is! String ||
        herdId.isEmpty ||
        movementType is! String ||
        movementType.trim().isEmpty ||
        movementType.length > 40 ||
        delta is! int ||
        delta < -2147483648 ||
        delta > 2147483647 ||
        delta == 0) {
      throw const FormatException('Invalid local livestock movement intent');
    }
    pendingByHerd
        .putIfAbsent(herdId, () => [])
        .add(
          FarmlyLiveLivestockMovement(
            id: entry.mutation.intent.resourceId,
            herdId: herdId,
            movementType: movementType,
            delta: delta,
            syncState: entry.status == OutboxEntryStatus.applied
                ? FarmlyLivestockMovementSyncState.awaitingProjection
                : FarmlyLivestockMovementSyncState.savedOnDevice,
            sequence: entry.sequence,
          ),
        );
    pendingDeltaByHerd.update(
      herdId,
      (current) => current + delta,
      ifAbsent: () => delta,
    );
    // Entries are in monotonic enqueue order. Chaining to the newest live
    // movement keeps its ancestors ordered through the declared DAG.
    latestOperationIdByHerd[herdId] = entry.operationId;
  }

  for (final movements in pendingByHerd.values) {
    movements.sort((a, b) => b.sequence.compareTo(a.sequence));
  }
  return FarmlyLiveLivestockMovementLedger(
    pendingByHerd: Map.unmodifiable({
      for (final entry in pendingByHerd.entries)
        entry.key: List<FarmlyLiveLivestockMovement>.unmodifiable(entry.value),
    }),
    pendingDeltaByHerd: Map.unmodifiable(pendingDeltaByHerd),
    latestOperationIdByHerd: Map.unmodifiable(latestOperationIdByHerd),
    herdsNeedingAttention: Set.unmodifiable(herdsNeedingAttention),
    attentionCount: attentionCount,
  );
}

final class FarmlyLiveAnimal {
  const FarmlyLiveAnimal({
    required this.id,
    required this.version,
    required this.herdId,
    required this.tag,
    required this.name,
    required this.birthDate,
    required this.status,
    required this.archived,
    required this.hasUnresolvedUpdate,
    required this.syncState,
    required this.productionRecords,
    required this.observations,
  });

  final String id;
  final int version;
  final String herdId;
  final String tag;
  final String? name;
  final String? birthDate;
  final String status;
  final bool archived;
  final bool hasUnresolvedUpdate;
  final FarmlyLivestockEntitySyncState syncState;
  final List<FarmlyLiveProductionRecord> productionRecords;
  final List<FarmlyLiveAnimalObservation> observations;

  bool get canRecordProduction => status == 'alive' && !archived;
}

final class FarmlyLiveHerd {
  const FarmlyLiveHerd({
    required this.id,
    required this.mode,
    required this.species,
    required this.status,
    required this.headcount,
    required this.animals,
    required this.productionRecords,
    required this.pendingMovements,
    required this.pendingMovementDelta,
    required this.movementNeedsAttention,
    required this.observations,
    required this.syncState,
    this.dependencyOperationId,
  });

  final String id;
  final String mode;
  final String? species;
  final String status;
  final int headcount;
  final List<FarmlyLiveAnimal> animals;
  final List<FarmlyLiveProductionRecord> productionRecords;
  final List<FarmlyLiveLivestockMovement> pendingMovements;
  final int pendingMovementDelta;
  final bool movementNeedsAttention;
  final List<FarmlyLiveAnimalObservation> observations;
  final FarmlyLivestockEntitySyncState syncState;

  /// Set only while this local herd.create still gates child animal writes.
  final String? dependencyOperationId;

  bool get isBatch => mode == 'batch';
  bool get canRecordProduction => status == 'active';
  bool get canRecordMovement =>
      isBatch && status == 'active' && !movementNeedsAttention;
  int get estimatedHeadcount => headcount + pendingMovementDelta;
}

final class FarmlyLiveLivestockCollection {
  const FarmlyLiveLivestockCollection({
    required this.cacheState,
    required this.canRecordProduction,
    required this.canRecordAnimalObservations,
    required this.canManageLivestockMovements,
    required this.canManageHerds,
    required this.organizationName,
    required this.farmName,
    required this.herds,
    required this.attentionCount,
    this.scope,
    this.selectedScope,
  });

  final FarmlyLivestockCacheState cacheState;
  final bool canRecordProduction;
  final bool canRecordAnimalObservations;
  final bool canManageLivestockMovements;
  final bool canManageHerds;
  final String organizationName;
  final String farmName;
  final List<FarmlyLiveHerd> herds;
  final int attentionCount;
  final FarmlyMutationScope? scope;
  final FarmlyOrganizationScope? selectedScope;
}

final farmlyLiveLivestockProvider =
    FutureProvider<FarmlyLiveLivestockCollection>((ref) async {
      final selected = ref.watch(selectedOrganizationScopeProvider);
      final syncScope = await ref.watch(farmlySyncScopeProvider.future);
      // Rebuild after a local enqueue, acknowledgement, or domain pull.
      ref.watch(syncStatusProvider);
      if (syncScope == null ||
          selected == null ||
          syncScope.kind != FarmlyMutationScopeKind.farm ||
          syncScope.farmId == null ||
          selected.organization.id != syncScope.organizationId ||
          selected.selectedFarmId != syncScope.farmId) {
        return _emptyLivestock(
          FarmlyLivestockCacheState.noFarm,
          selected: selected,
        );
      }

      final farm = selected.selectedFarm;
      if (farm == null || farm.status != FarmlyFarmStatus.active) {
        return _emptyLivestock(
          FarmlyLivestockCacheState.noFarm,
          selected: selected,
        );
      }

      final session = await ref.watch(farmlyAuthSessionProvider.future);
      if (session == null || session.user.id != syncScope.accountId) {
        return _emptyLivestock(
          FarmlyLivestockCacheState.scopeChanged,
          selected: selected,
          farmName: farm.name,
          scope: syncScope,
        );
      }

      final engine = await ref.watch(syncEngineProvider.future);
      final snapshot = await engine.domainSnapshot(syncScope);
      final entries = await engine.entries(
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
        return _emptyLivestock(
          FarmlyLivestockCacheState.scopeChanged,
          selected: selected,
          farmName: farm.name,
          scope: syncScope,
        );
      }

      final canWrite = _canRecordProduction(selected, farm);
      final canManageMovements = _canManageLivestockMovements(selected, farm);
      final canManageHerds = canManageMovements;
      if (snapshot == null) {
        return _emptyLivestock(
          FarmlyLivestockCacheState.notBootstrapped,
          selected: selected,
          farmName: farm.name,
          scope: syncScope,
          canWrite: canWrite,
          canManageMovements: canManageMovements,
          canManageHerds: canManageHerds,
          attentionCount: _livestockAttentionCount(entries, syncScope),
        );
      }

      if (snapshot.cursor.continuityEpoch !=
              selected.directory.continuityEpoch ||
          snapshot.cursor.scopePolicyVersion !=
              selected.directory.scopePolicyVersion) {
        return _emptyLivestock(
          FarmlyLivestockCacheState.stale,
          selected: selected,
          farmName: farm.name,
          scope: syncScope,
          canWrite: canWrite,
          canManageMovements: canManageMovements,
          canManageHerds: canManageHerds,
          attentionCount: _livestockAttentionCount(entries, syncScope),
        );
      }

      final herds = <String, FarmlyHerdDto>{};
      final snapshotHerdIds = snapshot.recordsFor('herd').keys.toSet();
      for (final row in snapshot.recordsFor('herd').values) {
        if (row is! Map) throw const FormatException('Invalid local herd');
        final herd = FarmlyHerdDto.fromJson(Map<String, dynamic>.from(row));
        if (herd.mode != 'batch' && herd.mode != 'tracked') {
          throw const FormatException('Invalid local herd mode');
        }
        if (herd.status != 'active' && herd.status != 'archived') {
          throw const FormatException('Invalid local herd status');
        }
        if (herd.status == 'archived') continue;
        herds[herd.id] = herd;
      }

      var createAttentionCount = 0;
      final herdSyncStateById = <String, FarmlyLivestockEntitySyncState>{
        for (final herdId in herds.keys)
          herdId: FarmlyLivestockEntitySyncState.confirmed,
      };
      final herdDependencyOperationById = <String, String>{};
      for (final entry in entries) {
        if (!_entryMatchesScope(entry, syncScope) ||
            entry.mutation.intent.type != 'herd.create') {
          continue;
        }
        if (_needsAttention(entry.status)) {
          createAttentionCount += 1;
          continue;
        }
        final resourceId = entry.mutation.intent.resourceId;
        // A server snapshot is authoritative as soon as it contains this ID.
        if (snapshotHerdIds.contains(resourceId) ||
            herds.containsKey(resourceId)) {
          continue;
        }
        if (!_canProjectCreate(entry.status)) continue;

        final payload = entry.mutation.intent.payload;
        final intent = FarmlyCreateHerdIntent(
          operationId: entry.operationId,
          continuityEpoch: syncScope.continuityEpoch,
          resourceId: resourceId,
          mode: _requireLocalString(payload, 'mode'),
          species: _optionalLocalString(payload, 'species'),
          status: _optionalLocalString(payload, 'status'),
        );
        final status = intent.payload['status'] as String? ?? 'active';
        if (status == 'archived') continue;
        final herd = FarmlyHerdDto.fromJson({
          'id': resourceId,
          'version': 1,
          'mode': intent.payload['mode'],
          'species': intent.payload['species'],
          'status': status,
          'headcount': 0,
        });
        herds[resourceId] = herd;
        herdSyncStateById[resourceId] = _entitySyncState(entry.status);
        if (entry.status == OutboxEntryStatus.pending ||
            entry.status == OutboxEntryStatus.inFlight) {
          herdDependencyOperationById[resourceId] = entry.operationId;
        }
      }

      final animalsByHerd = <String, List<FarmlyAnimalDto>>{};
      final animalsById = <String, FarmlyAnimalDto>{};
      final animalSyncStateById = <String, FarmlyLivestockEntitySyncState>{};
      final snapshotAnimals = snapshot.recordsFor('animal');
      final snapshotAnimalIds = snapshotAnimals.keys.toSet();
      for (final row in snapshotAnimals.values) {
        if (row is! Map) throw const FormatException('Invalid local animal');
        final animal = FarmlyAnimalDto.fromJson(Map<String, dynamic>.from(row));
        if (!herds.containsKey(animal.herdId)) continue;
        animalsByHerd.putIfAbsent(animal.herdId, () => []).add(animal);
        animalsById[animal.id] = animal;
        animalSyncStateById[animal.id] =
            FarmlyLivestockEntitySyncState.confirmed;
      }
      for (final entry in entries) {
        if (!_entryMatchesScope(entry, syncScope) ||
            entry.mutation.intent.type != 'animal.create') {
          continue;
        }
        if (_needsAttention(entry.status)) {
          createAttentionCount += 1;
          continue;
        }
        final resourceId = entry.mutation.intent.resourceId;
        if (snapshotAnimalIds.contains(resourceId) ||
            animalSyncStateById.containsKey(resourceId) ||
            !_canProjectCreate(entry.status)) {
          continue;
        }
        final payload = entry.mutation.intent.payload;
        final intent = FarmlyCreateAnimalIntent(
          operationId: entry.operationId,
          continuityEpoch: syncScope.continuityEpoch,
          resourceId: resourceId,
          herdId: _requireLocalString(payload, 'herdId'),
          tag: _requireLocalString(payload, 'tag'),
          name: _optionalLocalString(payload, 'name'),
          birthDate: _optionalLocalString(payload, 'birthDate'),
          status: _optionalLocalString(payload, 'status'),
          dependsOn: entry.dependsOn,
        );
        final herdId = intent.payload['herdId'] as String;
        final parent = herds[herdId];
        if (parent == null ||
            parent.mode != 'tracked' ||
            parent.status != 'active') {
          continue;
        }
        final pendingParentOperation = herdDependencyOperationById[herdId];
        if (pendingParentOperation != null &&
            !entry.dependsOn.contains(pendingParentOperation)) {
          continue;
        }
        final animalStatus = intent.payload['status'] as String? ?? 'alive';
        final animal = FarmlyAnimalDto.fromJson({
          'id': resourceId,
          'version': 1,
          'herdId': herdId,
          'tag': intent.payload['tag'],
          'name': intent.payload['name'],
          'birthDate': intent.payload['birthDate'],
          'status': animalStatus,
          'archived': false,
        });
        animalsByHerd.putIfAbsent(herdId, () => []).add(animal);
        animalsById[resourceId] = animal;
        animalSyncStateById[resourceId] = _entitySyncState(entry.status);
      }

      final updateEntriesByAnimalId = <String, List<OutboxEntry>>{};
      for (final entry in entries) {
        if (!_entryMatchesScope(entry, syncScope) ||
            entry.mutation.intent.type != 'animal.update') {
          continue;
        }
        updateEntriesByAnimalId
            .putIfAbsent(entry.mutation.intent.resourceId, () => [])
            .add(entry);
      }
      final animalHasUnresolvedUpdateById = <String, bool>{};
      for (final item in updateEntriesByAnimalId.entries) {
        final current = animalsById[item.key];
        final unresolved = item.value
            .where((entry) => _animalUpdateIsUnresolved(entry, current))
            .toList(growable: false);
        if (unresolved.isEmpty) continue;
        animalHasUnresolvedUpdateById[item.key] = true;
        // Multiple live edits for one animal have no safe local ordering
        // contract. Keep the confirmed row visible and block another edit.
        if (unresolved.length != 1) continue;

        final entry = unresolved.single;
        final baseVersion = entry.mutation.intent.baseVersion;
        if (!_canProjectCreate(entry.status) ||
            current == null ||
            baseVersion == null ||
            current.version != baseVersion) {
          continue;
        }
        final payload = entry.mutation.intent.payload;
        final intent = FarmlyUpdateAnimalIntent(
          operationId: entry.operationId,
          continuityEpoch: syncScope.continuityEpoch,
          resourceId: entry.mutation.intent.resourceId,
          baseVersion: baseVersion,
          tag: _optionalLocalString(payload, 'tag'),
          name: _optionalLocalString(payload, 'name'),
          birthDate: _optionalLocalString(payload, 'birthDate'),
          dependsOn: entry.dependsOn,
        );
        final projected = FarmlyAnimalDto.fromJson({
          ...current.toJson(),
          ...intent.payload,
        });
        final herdAnimals = animalsByHerd[current.herdId];
        if (herdAnimals == null) continue;
        final animalIndex = herdAnimals.indexWhere(
          (animal) => animal.id == current.id,
        );
        if (animalIndex < 0) continue;
        herdAnimals[animalIndex] = projected;
        animalsById[current.id] = projected;
        animalSyncStateById[current.id] = _entitySyncState(entry.status);
      }
      final activeAnimalIds = animalsByHerd.values
          .expand((animals) => animals)
          .where((animal) => !animal.archived)
          .map((animal) => animal.id)
          .toSet();
      final observationLedger = projectFarmlyLiveAnimalObservations(
        snapshotRecords: snapshot.recordsFor('animalObservation'),
        entries: entries,
        scope: syncScope,
        activeHerdIds: herds.keys.toSet(),
        activeAnimalIds: activeAnimalIds,
      );

      final recordsById = <String, FarmlyLiveProductionRecord>{};
      // The API bootstrap writer and change feed currently use the singular
      // entity key `productionRecord`; keep the client projection aligned to
      // that runtime wire value (the plural OpenAPI collection name is only a
      // route/collection identifier).
      for (final row in snapshot.recordsFor('productionRecord').values) {
        if (row is! Map) {
          throw const FormatException('Invalid local production record');
        }
        final record = _confirmedProductionRecord(
          Map<String, Object?>.from(row),
        );
        recordsById[record.id] = record;
      }

      final movementLedger = projectFarmlyLiveLivestockMovements(
        snapshotRecords: snapshot.recordsFor('livestockMovement'),
        entries: entries,
        scope: syncScope,
      );
      var attentionCount =
          movementLedger.attentionCount +
          observationLedger.attentionCount +
          createAttentionCount;
      for (final entry in entries) {
        if (!_entryMatchesScope(entry, syncScope) ||
            entry.mutation.intent.type != 'productionRecord.create') {
          continue;
        }
        if (entry.status == OutboxEntryStatus.rejected ||
            entry.status == OutboxEntryStatus.conflict ||
            entry.status == OutboxEntryStatus.blocked) {
          attentionCount += 1;
          continue;
        }
        if (recordsById.containsKey(entry.mutation.intent.resourceId)) {
          continue;
        }
        if (entry.status != OutboxEntryStatus.pending &&
            entry.status != OutboxEntryStatus.inFlight &&
            entry.status != OutboxEntryStatus.applied) {
          continue;
        }
        final payload = entry.mutation.intent.payload;
        final product = payload['product'];
        final quantity = payload['quantity'];
        final recordedOn = payload['recordedOn'];
        if (product is! String ||
            quantity is! String ||
            recordedOn is! String) {
          throw const FormatException('Invalid local production intent');
        }
        recordsById[entry.mutation.intent.resourceId] =
            FarmlyLiveProductionRecord(
              id: entry.mutation.intent.resourceId,
              herdId: payload['herdId'] as String?,
              animalId: payload['animalId'] as String?,
              product: product,
              quantity: quantity,
              unit: _unitForProduct(product),
              recordedOn: recordedOn,
              syncState: entry.status == OutboxEntryStatus.applied
                  ? FarmlyProductionSyncState.awaitingProjection
                  : FarmlyProductionSyncState.savedOnDevice,
            );
      }

      final herdProduction = <String, List<FarmlyLiveProductionRecord>>{};
      final animalProduction = <String, List<FarmlyLiveProductionRecord>>{};
      for (final record in recordsById.values) {
        final herdId = record.herdId;
        if (herdId != null && herds.containsKey(herdId)) {
          herdProduction.putIfAbsent(herdId, () => []).add(record);
        }
        final animalId = record.animalId;
        if (animalId != null) {
          animalProduction.putIfAbsent(animalId, () => []).add(record);
        }
      }

      final projectedHerds = <FarmlyLiveHerd>[];
      for (final herd in herds.values) {
        final animals = (animalsByHerd[herd.id] ?? const <FarmlyAnimalDto>[])
            .map(
              (animal) => FarmlyLiveAnimal(
                id: animal.id,
                version: animal.version,
                herdId: animal.herdId,
                tag: animal.tag,
                name: animal.name,
                birthDate: animal.birthDate,
                status: animal.status,
                archived: animal.archived,
                hasUnresolvedUpdate:
                    animalHasUnresolvedUpdateById[animal.id] ?? false,
                syncState:
                    animalSyncStateById[animal.id] ??
                    FarmlyLivestockEntitySyncState.confirmed,
                productionRecords: List.unmodifiable(
                  animalProduction[animal.id] ?? const [],
                ),
                observations: observationLedger.byAnimal[animal.id] ?? const [],
              ),
            )
            .toList(growable: false);
        projectedHerds.add(
          FarmlyLiveHerd(
            id: herd.id,
            mode: herd.mode,
            species: herd.species,
            status: herd.status,
            headcount:
                herd.headcount +
                animals
                    .where(
                      (animal) =>
                          !animal.archived &&
                          animal.status == 'alive' &&
                          animal.syncState !=
                              FarmlyLivestockEntitySyncState.confirmed,
                    )
                    .length,
            animals: List.unmodifiable(animals),
            productionRecords: List.unmodifiable(
              herdProduction[herd.id] ?? const [],
            ),
            pendingMovements: movementLedger.pendingByHerd[herd.id] ?? const [],
            pendingMovementDelta:
                movementLedger.pendingDeltaByHerd[herd.id] ?? 0,
            movementNeedsAttention: movementLedger.herdsNeedingAttention
                .contains(herd.id),
            observations: observationLedger.byHerd[herd.id] ?? const [],
            syncState:
                herdSyncStateById[herd.id] ??
                FarmlyLivestockEntitySyncState.confirmed,
            dependencyOperationId: herdDependencyOperationById[herd.id],
          ),
        );
      }
      projectedHerds.sort(
        (a, b) => (a.species ?? '').toLowerCase().compareTo(
          (b.species ?? '').toLowerCase(),
        ),
      );

      return FarmlyLiveLivestockCollection(
        cacheState: FarmlyLivestockCacheState.ready,
        canRecordProduction: canWrite,
        canRecordAnimalObservations: canWrite,
        canManageLivestockMovements: canManageMovements,
        canManageHerds: canManageHerds,
        organizationName: selected.organization.name,
        farmName: farm.name,
        herds: List.unmodifiable(projectedHerds),
        attentionCount: attentionCount,
        scope: syncScope,
        selectedScope: selected,
      );
    });

FarmlyLiveLivestockCollection _emptyLivestock(
  FarmlyLivestockCacheState state, {
  FarmlyOrganizationScope? selected,
  String farmName = '',
  FarmlyMutationScope? scope,
  bool canWrite = false,
  bool canManageMovements = false,
  bool canManageHerds = false,
  int attentionCount = 0,
}) => FarmlyLiveLivestockCollection(
  cacheState: state,
  canRecordProduction: canWrite,
  canRecordAnimalObservations: canWrite,
  canManageLivestockMovements: canManageMovements,
  canManageHerds: canManageHerds,
  organizationName: selected?.organization.name ?? '',
  farmName: farmName,
  herds: const [],
  attentionCount: attentionCount,
  scope: scope,
  selectedScope: selected,
);

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

bool _canManageLivestockMovements(
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
  return farm.grantRole == FarmlyFarmGrantRole.manager;
}

bool _canRecordProduction(
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

bool _entryMatchesScope(OutboxEntry entry, FarmlyMutationScope scope) {
  final entryScope = entry.mutation.scope;
  return entryScope.kind == FarmlyMutationScopeKind.farm &&
      entryScope.accountId == scope.accountId &&
      entryScope.organizationId == scope.organizationId &&
      entryScope.farmId == scope.farmId &&
      entryScope.continuityEpoch == scope.continuityEpoch;
}

bool _needsAttention(OutboxEntryStatus status) =>
    status == OutboxEntryStatus.rejected ||
    status == OutboxEntryStatus.conflict ||
    status == OutboxEntryStatus.blocked;

bool _canProjectCreate(OutboxEntryStatus status) =>
    status == OutboxEntryStatus.pending ||
    status == OutboxEntryStatus.inFlight ||
    status == OutboxEntryStatus.applied;

FarmlyLivestockEntitySyncState _entitySyncState(OutboxEntryStatus status) =>
    status == OutboxEntryStatus.applied
    ? FarmlyLivestockEntitySyncState.awaitingProjection
    : FarmlyLivestockEntitySyncState.savedOnDevice;

String _requireLocalString(Map<String, Object?> payload, String key) {
  final value = payload[key];
  if (value is! String) {
    throw const FormatException('Invalid local livestock create intent');
  }
  return value;
}

String? _optionalLocalString(Map<String, Object?> payload, String key) {
  if (!payload.containsKey(key)) return null;
  final value = payload[key];
  if (value is! String) {
    throw const FormatException('Invalid local livestock create intent');
  }
  return value;
}

int _livestockAttentionCount(
  List<OutboxEntry> entries,
  FarmlyMutationScope scope,
) => entries
    .where(
      (entry) =>
          _entryMatchesScope(entry, scope) &&
          (entry.mutation.intent.type == 'herd.create' ||
              entry.mutation.intent.type == 'animal.create' ||
              entry.mutation.intent.type == 'animal.update' ||
              entry.mutation.intent.type == 'productionRecord.create' ||
              entry.mutation.intent.type == 'livestockMovement.create' ||
              entry.mutation.intent.type == 'animalObservation.create') &&
          (entry.status == OutboxEntryStatus.rejected ||
              entry.status == OutboxEntryStatus.conflict ||
              entry.status == OutboxEntryStatus.blocked),
    )
    .length;

bool _animalUpdateIsUnresolved(OutboxEntry entry, FarmlyAnimalDto? current) {
  if (entry.status == OutboxEntryStatus.rejected) return false;
  if (entry.status != OutboxEntryStatus.applied) return true;
  final baseVersion = entry.mutation.intent.baseVersion;
  return current == null ||
      baseVersion == null ||
      current.version <= baseVersion;
}

FarmlyLiveProductionRecord _confirmedProductionRecord(
  Map<String, Object?> json,
) {
  final id = json['id'];
  final product = json['product'];
  final quantity = json['quantity'];
  final unit = json['unit'];
  final recordedOn = json['recordedOn'];
  if (id is! String ||
      product is! String ||
      quantity is! String ||
      unit is! String ||
      recordedOn is! String) {
    throw const FormatException('Invalid local production record');
  }
  final expectedUnit = _unitForProduct(product);
  if (unit != expectedUnit || !_isCivilDate(recordedOn)) {
    throw const FormatException('Invalid local production fact');
  }
  return FarmlyLiveProductionRecord(
    id: id,
    herdId: json['herdId'] as String?,
    animalId: json['animalId'] as String?,
    product: product,
    quantity: quantity,
    unit: unit,
    recordedOn: recordedOn,
    syncState: FarmlyProductionSyncState.confirmed,
  );
}

String _unitForProduct(String product) => switch (product) {
  'milk' => 'litre',
  'eggs' => 'pieces',
  'weight' => 'kg',
  _ => throw const FormatException('Invalid production product'),
};

bool _isCivilDate(String value) {
  if (!RegExp(r'^\d{4}-\d{2}-\d{2}$').hasMatch(value)) return false;
  final parts = value.split('-').map(int.parse).toList(growable: false);
  if (parts.first < 1) return false;
  return DateTime.utc(
        parts[0],
        parts[1],
        parts[2],
      ).toIso8601String().substring(0, 10) ==
      value;
}
