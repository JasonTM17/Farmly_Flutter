import 'dart:async';
import 'dart:io';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:path_provider/path_provider.dart';

import '../../features/organizations/organization_scope_controller.dart';
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
final farmlySyncScopeProvider = FutureProvider<FarmlyMutationScope?>((ref) async {
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
    this.lastReport,
    this.lastError,
  });

  final int pendingCount;
  final int blockedCount;
  final int conflictCount;
  final bool running;
  final SyncRunReport? lastReport;
  final String? lastError;
}

final syncStatusProvider =
    AsyncNotifierProvider<SyncStatusController, SyncStatusSnapshot>(
  SyncStatusController.new,
);

final class SyncStatusController extends AsyncNotifier<SyncStatusSnapshot> {
  @override
  Future<SyncStatusSnapshot> build() async {
    final engine = await ref.watch(syncEngineProvider.future);
    return _snapshot(engine);
  }

  /// One full pass: flush the durable outbox, reconcile in-flight, pull the
  /// change feed. Safe to call on connectivity restore or pull-to-refresh.
  Future<void> synchronize() async {
    final scope = ref.read(farmlySyncScopeProvider).value;
    if (scope == null) return;
    final engine = await ref.read(syncEngineProvider.future);
    state = AsyncData(
      (state.value ?? await _snapshot(engine)).copyRunning(),
    );
    try {
      final report = await engine.synchronize(scope);
      final snapshot = await _snapshot(engine);
      state = AsyncData(
        SyncStatusSnapshot(
          pendingCount: snapshot.pendingCount,
          blockedCount: snapshot.blockedCount,
          conflictCount: snapshot.conflictCount,
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
          running: false,
          lastError: error.toString(),
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
    final scope = ref.read(farmlySyncScopeProvider).value;
    var pending = 0;
    var blocked = 0;
    if (scope != null) {
      final entries = await engine.entries(
        accountId: scope.accountId,
        organizationId: scope.organizationId,
      );
      for (final entry in entries) {
        switch (entry.status) {
          case OutboxEntryStatus.pending || OutboxEntryStatus.inFlight:
            pending++;
          case OutboxEntryStatus.blocked:
            blocked++;
          case OutboxEntryStatus.conflict:
          case OutboxEntryStatus.applied:
          case OutboxEntryStatus.rejected:
            break;
        }
      }
    }
    return SyncStatusSnapshot(
      pendingCount: pending,
      blockedCount: blocked,
      conflictCount: engine.conflicts.length,
      running: false,
    );
  }
}

extension on SyncStatusSnapshot {
  SyncStatusSnapshot copyRunning() => SyncStatusSnapshot(
        pendingCount: pendingCount,
        blockedCount: blockedCount,
        conflictCount: conflictCount,
        running: true,
        lastReport: lastReport,
      );
}
