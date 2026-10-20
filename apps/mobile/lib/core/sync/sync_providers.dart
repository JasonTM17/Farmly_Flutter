import 'dart:async';
import 'dart:io';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:path_provider/path_provider.dart';

import '../../features/organizations/organization_scope_controller.dart';
import '../../features/organizations/organization_repository.dart';
import '../auth/auth_session_controller.dart';
import '../network/farmly_api_client.dart';
import '../storage/offline_key_store.dart';
import 'farmly_mutation.dart';
import 'local_domain_store.dart';
import 'outbox_store.dart';
import 'sync_engine.dart';
import 'sync_models.dart';
import 'sync_transport.dart';

/// Wire transport over the authenticated API client.
final syncTransportProvider = Provider<SyncTransport>(
  (ref) => FarmlyApiTransport(ref.watch(farmlyApiClientProvider)),
);

/// Durable outbox: encrypted file store keyed by the device-held outbox key.
/// Key resolution follows the offline key store contract — existing payload
/// without a readable key fails closed ([FarmlyOfflineKeyUnavailable]), never
/// silently rebinding data to a fresh key.
final syncEngineProvider = FutureProvider<FarmlySyncEngine>((ref) async {
  final directory = await getApplicationDocumentsDirectory();
  final payloadFile = File('${directory.path}/farmly-outbox.v1.json');
  final keys = FarmlyOfflineKeyStore(ref.watch(farmlySecretStoreProvider));
  final key = await keys.loadOrCreate(
    purpose: FarmlyOfflineKeyPurpose.outboxEnvelope,
    hasExistingPayload: await payloadFile.exists(),
  );
  return FarmlySyncEngine(
    outbox: EncryptedFileOutboxStore(directory: directory, key: key),
    transport: ref.watch(syncTransportProvider),
    // Encrypted file projection — durable cursor + records, atomic rewrite.
    // The Drift/SQLite database lane can replace this without touching the
    // engine surface.
    domain: EncryptedFileDomainStore(directory: directory, key: key),
  );
});

/// The signed-in account + selected organization/farm as a mutation scope —
/// `null` until both exist, which is honest "nothing to sync" state. An
/// invalid scope (e.g. a non-UUID farm id) surfaces as [AsyncError] instead
/// of throwing during widget build: screens render a translated error state,
/// never a raw provider exception (spec 02 §5).
final farmlySyncScopeProvider = FutureProvider<FarmlyMutationScope?>((
  ref,
) async {
  final session = ref.watch(farmlyAuthSessionProvider).value;
  final orgScope = ref.watch(selectedOrganizationScopeProvider);
  if (session == null || orgScope == null) return null;
  final epoch = orgScope.directory.continuityEpoch;
  final farm = orgScope.selectedFarm;
  if (farm == null) {
    return FarmlyMutationScope.organization(
      accountId: session.user.id,
      organizationId: orgScope.organization.id,
      continuityEpoch: epoch,
    );
  }
  return FarmlyMutationScope.farm(
    accountId: session.user.id,
    organizationId: orgScope.organization.id,
    farmId: farm.id,
    continuityEpoch: epoch,
  );
}, retry: (_, _) => null);

/// Snapshot of engine truth for the Sync Center: pending depth, parked
/// conflicts, last run report. Not a state machine of its own — the durable
/// outbox is the source of truth.
final class SyncStatusSnapshot {
  const SyncStatusSnapshot({
    required this.pendingCount,
    required this.blockedCount,
    required this.conflictCount,
    required this.running,
    this.rejectedCount = 0,
    this.operations = const [],
    this.lastReport,
    this.lastErrorKind,
  });

  final int pendingCount;
  final int blockedCount;
  final int conflictCount;
  final int rejectedCount;
  final bool running;
  final List<SyncOutboxStatus> operations;
  final SyncRunReport? lastReport;
  final SyncStatusFailureKind? lastErrorKind;
}

enum SyncOperationCategory {
  farm,
  zone,
  crop,
  livestock,
  task,
  harvest,
  water,
  general,
}

enum SyncOutboxState {
  synced,
  savedOnDevice,
  checkingServerResult,
  outcomeUnknown,
  dependencyMissing,
  dependencyCycle,
  dependencyFailed,
  dependencyBlocked,
  dependencyNeedsAttention,
  conflictNeedsReview,
  rejectedPermission,
  rejectedValidation,
  rejectedNeedsReview,
}

enum SyncStatusFailureKind {
  authenticationRequired,
  permissionDenied,
  serviceUnavailable,
  syncConflict,
  refreshRequired,
  unknown,
}

/// Safe UI projection of an encrypted outbox row. It intentionally omits the
/// mutation payload and server-provided error text/code.
final class SyncOutboxStatus {
  const SyncOutboxStatus({
    required this.operationId,
    required this.category,
    required this.state,
  });

  final String operationId;
  final SyncOperationCategory category;
  final SyncOutboxState state;
}

SyncStatusFailureKind classifySyncStatusFailure(Object error) {
  if (error is! FarmlyApiFailure) return SyncStatusFailureKind.unknown;
  return switch (error.code) {
    FarmlyApiFailureCode.unauthenticated =>
      SyncStatusFailureKind.authenticationRequired,
    FarmlyApiFailureCode.permissionDenied =>
      SyncStatusFailureKind.permissionDenied,
    FarmlyApiFailureCode.unavailable =>
      SyncStatusFailureKind.serviceUnavailable,
    FarmlyApiFailureCode.conflict => SyncStatusFailureKind.syncConflict,
    FarmlyApiFailureCode.cursorExpired => SyncStatusFailureKind.refreshRequired,
    _ => SyncStatusFailureKind.unknown,
  };
}

final syncStatusProvider =
    AsyncNotifierProvider<SyncStatusController, SyncStatusSnapshot>(
      SyncStatusController.new,
    );

final class SyncStatusController extends AsyncNotifier<SyncStatusSnapshot> {
  @override
  Future<SyncStatusSnapshot> build() async {
    // Keep the derived queue projection bound to the active account and org;
    // _snapshot awaits their current values before reading encrypted entries.
    ref.watch(farmlyAuthSessionProvider);
    ref.watch(selectedOrganizationScopeProvider);
    ref.watch(farmlySyncScopeProvider);
    final engine = await ref.watch(syncEngineProvider.future);
    return _snapshot(engine);
  }

  /// One full pass: flush the durable outbox, reconcile in-flight, pull the
  /// change feed. Safe to call on connectivity restore or pull-to-refresh.
  Future<void> synchronize() async {
    final scope = ref.read(farmlySyncScopeProvider).value;
    if (scope == null) return;
    final selectedOrganization = ref.read(selectedOrganizationScopeProvider);
    final session = ref.read(farmlyAuthSessionProvider).value;
    if (selectedOrganization == null || session == null) return;
    final engine = await ref.read(syncEngineProvider.future);
    final organizationId = selectedOrganization.organization.id;
    final accountId = session.user.id;
    final selectionTicket = selectedOrganization.epoch;
    final scopeController = ref.read(
      selectedOrganizationScopeProvider.notifier,
    );
    final repository = ref.read(organizationRepositoryProvider);
    state = AsyncData((state.value ?? await _snapshot(engine)).copyRunning());
    try {
      final report = await engine.synchronizeAuthorizedScopes(
        refreshAuthorizedScopes: () async {
          final directory = await repository.loadFarmDirectory(organizationId);
          if (!ref.mounted ||
              !scopeController.isCurrent(selectionTicket) ||
              ref.read(farmlyAuthSessionProvider).value?.user.id != accountId) {
            return null;
          }
          final installed = await scopeController.refreshDirectory(
            directory,
            ticket: selectionTicket,
          );
          if (!installed) return null;
          final organizationScope = FarmlyMutationScope.organization(
            accountId: accountId,
            organizationId: organizationId,
            continuityEpoch: directory.continuityEpoch,
          );
          return [
            organizationScope,
            for (final farm in directory.farms)
              if (farm.status == FarmlyFarmStatus.active)
                FarmlyMutationScope.farm(
                  accountId: accountId,
                  organizationId: organizationId,
                  farmId: farm.id,
                  continuityEpoch: directory.continuityEpoch,
                ),
          ];
        },
      );
      final snapshot = await _snapshot(engine);
      if (report == null) {
        state = AsyncData(snapshot);
        return;
      }
      state = AsyncData(
        SyncStatusSnapshot(
          pendingCount: snapshot.pendingCount,
          blockedCount: snapshot.blockedCount,
          conflictCount: snapshot.conflictCount,
          rejectedCount: snapshot.rejectedCount,
          operations: snapshot.operations,
          running: false,
          lastReport: report,
        ),
      );
    } on Object catch (error) {
      final snapshot = await _snapshot(engine);
      state = AsyncData(
        SyncStatusSnapshot(
          pendingCount: snapshot.pendingCount,
          blockedCount: snapshot.blockedCount,
          conflictCount: snapshot.conflictCount,
          rejectedCount: snapshot.rejectedCount,
          operations: snapshot.operations,
          running: false,
          lastErrorKind: classifySyncStatusFailure(error),
        ),
      );
    }
  }

  /// Enqueue an intent durably — survives process death before send.
  Future<void> enqueue(FarmlyScopedMutation mutation) async {
    final engine = await ref.read(syncEngineProvider.future);
    await engine.enqueue(mutation);
    state = AsyncData(await _snapshot(engine));
  }

  /// Manual conflict resolution — a new intent under a new operationId at the
  /// server's current baseVersion (no mutation of the original bytes).
  Future<void> resolveConflict(
    String operationId, {
    required int newBaseVersion,
  }) async {
    final engine = await ref.read(syncEngineProvider.future);
    final match = engine.conflicts
        .where((c) => c.entry.operationId == operationId)
        .firstOrNull;
    if (match == null) return;
    await engine.resolveConflict(match, newBaseVersion: newBaseVersion);
    state = AsyncData(await _snapshot(engine));
  }

  /// Keep the server version: retire the conflicted local intent.
  Future<void> keepServerVersion(String operationId) async {
    final engine = await ref.read(syncEngineProvider.future);
    final match = engine.conflicts
        .where((c) => c.entry.operationId == operationId)
        .firstOrNull;
    if (match == null) return;
    await engine.dismissConflict(match);
    state = AsyncData(await _snapshot(engine));
  }

  Future<SyncStatusSnapshot> _snapshot(FarmlySyncEngine engine) async {
    final scope = await ref.read(farmlySyncScopeProvider.future);
    final selectedOrganization = ref.read(selectedOrganizationScopeProvider);
    final accountId = (await ref.read(
      farmlyAuthSessionProvider.future,
    ))?.user.id;
    var entries = <OutboxEntry>[];
    if (scope != null &&
        selectedOrganization != null &&
        accountId == scope.accountId &&
        selectedOrganization.organization.id == scope.organizationId) {
      final activeFarmIds = selectedOrganization.directory.farms
          .where((farm) => farm.status == FarmlyFarmStatus.active)
          .map((farm) => farm.id)
          .toSet();
      final allEntries = await engine.entries(
        accountId: scope.accountId,
        organizationId: scope.organizationId,
      );
      final entriesById = {
        for (final entry in allEntries) entry.operationId: entry,
      };
      entries = allEntries
          .where(
            (entry) =>
                entry.mutation.scope.kind ==
                    FarmlyMutationScopeKind.organization ||
                activeFarmIds.contains(entry.mutation.scope.farmId) ||
                _isProvisionalFarmChild(
                  entry,
                  entriesById,
                  continuityEpoch:
                      selectedOrganization.directory.continuityEpoch,
                ),
          )
          .toList(growable: false);
    }
    var pending = 0;
    var blocked = 0;
    var conflicts = 0;
    var rejected = 0;
    for (final entry in entries) {
      switch (entry.status) {
        case OutboxEntryStatus.pending || OutboxEntryStatus.inFlight:
          pending++;
        case OutboxEntryStatus.blocked:
          blocked++;
        case OutboxEntryStatus.conflict:
          conflicts++;
        case OutboxEntryStatus.rejected:
          rejected++;
        case OutboxEntryStatus.applied:
          break;
      }
    }
    final recentOperations = entries.toList()
      ..sort((a, b) {
        final aNeedsAttention = a.status != OutboxEntryStatus.applied;
        final bNeedsAttention = b.status != OutboxEntryStatus.applied;
        if (aNeedsAttention != bNeedsAttention) {
          return aNeedsAttention ? -1 : 1;
        }
        return b.sequence.compareTo(a.sequence);
      });
    return SyncStatusSnapshot(
      pendingCount: pending,
      blockedCount: blocked,
      conflictCount: conflicts,
      rejectedCount: rejected,
      running: false,
      operations: [
        for (final entry in recentOperations.take(12))
          SyncOutboxStatus(
            operationId: entry.operationId,
            category: _categoryFor(entry.mutation.intent.type),
            state: _stateFor(entry),
          ),
      ],
    );
  }
}

bool _isProvisionalFarmChild(
  OutboxEntry entry,
  Map<String, OutboxEntry> entriesById, {
  required String continuityEpoch,
}) {
  final childScope = entry.mutation.scope;
  final farmId = childScope.farmId;
  if (childScope.kind != FarmlyMutationScopeKind.farm ||
      farmId == null ||
      childScope.continuityEpoch != continuityEpoch ||
      entry.mutation.intent.continuityEpoch != continuityEpoch) {
    return false;
  }

  final pending = List<String>.of(entry.dependsOn);
  final visited = <String>{};
  while (pending.isNotEmpty) {
    final operationId = pending.removeLast();
    if (!visited.add(operationId)) continue;
    final ancestor = entriesById[operationId];
    if (ancestor == null) continue;
    final ancestorScope = ancestor.mutation.scope;
    if (ancestorScope.accountId != childScope.accountId ||
        ancestorScope.organizationId != childScope.organizationId ||
        ancestorScope.continuityEpoch != continuityEpoch ||
        ancestor.mutation.intent.continuityEpoch != continuityEpoch) {
      continue;
    }
    if (ancestorScope.kind == FarmlyMutationScopeKind.organization &&
        ancestor.mutation.intent.type == 'farm.create' &&
        ancestor.mutation.intent.resourceId == farmId) {
      // Show only the status/reference projection. Payload, farm ID, and
      // server rejection detail remain absent from Sync Center.
      return true;
    }
    if (ancestorScope.kind == FarmlyMutationScopeKind.farm &&
        ancestorScope.farmId == farmId) {
      pending.addAll(ancestor.dependsOn);
    }
  }
  return false;
}

SyncOperationCategory _categoryFor(String type) {
  if (type.startsWith('farm.')) return SyncOperationCategory.farm;
  if (type.startsWith('zone.')) return SyncOperationCategory.zone;
  if (type.startsWith('cropSpecies.') || type.startsWith('planting.')) {
    return SyncOperationCategory.crop;
  }
  if (type.startsWith('herd.') ||
      type.startsWith('animal.') ||
      type == 'livestockMovement.create' ||
      type == 'animalObservation.create' ||
      type == 'productionRecord.create') {
    return SyncOperationCategory.livestock;
  }
  if (type.startsWith('task') || type.startsWith('irrigationTask.')) {
    return SyncOperationCategory.task;
  }
  if (type.startsWith('harvest.')) return SyncOperationCategory.harvest;
  if (type.startsWith('water') || type.startsWith('moistureReading.')) {
    return SyncOperationCategory.water;
  }
  return SyncOperationCategory.general;
}

SyncOutboxState _stateFor(OutboxEntry entry) => switch (entry.status) {
  OutboxEntryStatus.pending =>
    entry.lastFailureCode == 'OUTCOME_UNKNOWN'
        ? SyncOutboxState.outcomeUnknown
        : SyncOutboxState.savedOnDevice,
  OutboxEntryStatus.inFlight => SyncOutboxState.checkingServerResult,
  OutboxEntryStatus.blocked => switch (entry.lastFailureCode) {
    'DEPENDENCY_MISSING' => SyncOutboxState.dependencyMissing,
    'DEPENDENCY_CYCLE' => SyncOutboxState.dependencyCycle,
    'DEPENDENCY_FAILED' => SyncOutboxState.dependencyFailed,
    'DEPENDENCY_BLOCKED' => SyncOutboxState.dependencyBlocked,
    _ => SyncOutboxState.dependencyNeedsAttention,
  },
  OutboxEntryStatus.conflict => SyncOutboxState.conflictNeedsReview,
  OutboxEntryStatus.rejected => switch (entry.rejectionCode) {
    'ACCESS_REVOKED' || 'PERMISSION_DENIED' =>
      SyncOutboxState.rejectedPermission,
    'FIELD_VALIDATION_FAILED' => SyncOutboxState.rejectedValidation,
    _ => SyncOutboxState.rejectedNeedsReview,
  },
  OutboxEntryStatus.applied => SyncOutboxState.synced,
};

extension on SyncStatusSnapshot {
  SyncStatusSnapshot copyRunning() => SyncStatusSnapshot(
    pendingCount: pendingCount,
    blockedCount: blockedCount,
    conflictCount: conflictCount,
    rejectedCount: rejectedCount,
    running: true,
    operations: operations,
    lastReport: lastReport,
    lastErrorKind: lastErrorKind,
  );
}
