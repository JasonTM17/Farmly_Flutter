import 'dart:math';

import '../network/farmly_api_client.dart';
import 'conflict.dart';
import 'farmly_mutation.dart';
import 'local_domain_store.dart';
import 'outbox_store.dart';
import 'sync_models.dart';
import 'sync_transport.dart';

/// RFC 4122 §4.4 UUIDv4 from a CSPRNG — operation IDs are immutable client
/// identities, so the generator is injectable for deterministic tests.
String newOperationId([Random? random]) {
  final source = random ?? Random.secure();
  final bytes = List<int>.generate(16, (_) => source.nextInt(256));
  bytes[6] = (bytes[6] & 0x0f) | 0x40;
  bytes[8] = (bytes[8] & 0x3f) | 0x80;
  String hex(int b) => b.toRadixString(16).padLeft(2, '0');
  final h = bytes.map(hex).join();
  return '${h.substring(0, 8)}-${h.substring(8, 12)}-${h.substring(12, 16)}-'
      '${h.substring(16, 20)}-${h.substring(20)}';
}

/// What one synchronization pass changed — surfaced to the UI so "synced"
/// badges are earned, not assumed.
final class SyncRunReport {
  const SyncRunReport({
    this.sent = 0,
    this.applied = 0,
    this.rejected = 0,
    this.conflicted = 0,
    this.blocked = 0,
    this.reconciled = 0,
    this.pulledChangeSets = 0,
    this.bootstrapped = false,
  });

  final int sent;
  final int applied;
  final int rejected;
  final int conflicted;
  final int blocked;
  final int reconciled;
  final int pulledChangeSets;
  final bool bootstrapped;
}

/// The offline-first coordinator (spec08): immutable intents go out in
/// dependency order, ambiguous sends reconcile against durable server proof,
/// committed change sets apply in revision order, and an expired cursor
/// triggers a full re-bootstrap — pending work is never cleared to "fix"
/// sync state.
final class FarmlySyncEngine {
  FarmlySyncEngine({
    required this._outbox,
    required this._transport,
    required this._domain,
    String Function() operationIdGenerator = newOperationId,
  }) : _newOperationId = operationIdGenerator;

  final OutboxStore _outbox;
  final SyncTransport _transport;
  final LocalDomainStore _domain;
  final String Function() _newOperationId;

  final List<SyncConflict> _conflicts = [];

  /// Parked conflicts awaiting explicit user choice.
  List<SyncConflict> get conflicts => List.unmodifiable(_conflicts);

  /// Durable enqueue — intent bytes are immutable from this point on.
  Future<OutboxEntry> enqueue(FarmlyScopedMutation mutation) =>
      _outbox.enqueue(mutation);

  /// Refresh the authorization directory before draining any scope. Farm
  /// creation is sent at organization scope first; after an attempt, refresh
  /// again before admitting child-farm work.
  Future<SyncRunReport?> synchronizeAuthorizedScopes({
    required Future<List<FarmlyMutationScope>?> Function()
    refreshAuthorizedScopes,
  }) async {
    var scopes = await refreshAuthorizedScopes();
    if (scopes == null) return null;
    if (scopes.isEmpty) return const SyncRunReport();

    var organizationScope = _requireOrganizationScope(scopes);
    final reports = <SyncRunReport>[await synchronize(organizationScope)];
    // A lost ACK may be recovered as applied without a send in this pass.
    // Refresh in either case so child-farm work can use the newly admitted
    // farm in the same synchronization run.
    if (reports.single.sent > 0 || reports.single.reconciled > 0) {
      scopes = await refreshAuthorizedScopes();
      if (scopes == null || scopes.isEmpty) return _combineReports(reports);
      organizationScope = _requireOrganizationScope(scopes);
    }

    final seenFarmIds = <String>{};
    for (final authorizedScope in scopes) {
      if (authorizedScope.kind == FarmlyMutationScopeKind.organization) {
        continue;
      }
      if (authorizedScope.accountId != organizationScope.accountId ||
          authorizedScope.organizationId != organizationScope.organizationId ||
          authorizedScope.continuityEpoch !=
              organizationScope.continuityEpoch) {
        throw ArgumentError('Authorized farm scopes must share one directory');
      }
      final farmId = authorizedScope.farmId;
      if (farmId == null || !seenFarmIds.add(farmId)) {
        throw ArgumentError('Authorized directory farm IDs must be unique');
      }
      reports.add(await synchronize(authorizedScope));
    }
    return _combineReports(reports);
  }

  FarmlyMutationScope _requireOrganizationScope(
    List<FarmlyMutationScope> scopes,
  ) {
    final organizations = scopes
        .where((scope) => scope.kind == FarmlyMutationScopeKind.organization)
        .toList(growable: false);
    if (organizations.length != 1) {
      throw ArgumentError(
        'A fresh directory must contain one organization scope',
      );
    }
    final organization = organizations.single;
    final seenFarmIds = <String>{};
    for (final scope in scopes) {
      if (scope.accountId != organization.accountId ||
          scope.organizationId != organization.organizationId ||
          scope.continuityEpoch != organization.continuityEpoch) {
        throw ArgumentError('Authorized scopes must share one directory');
      }
      if (scope.kind == FarmlyMutationScopeKind.farm) {
        final farmId = scope.farmId;
        if (farmId == null || !seenFarmIds.add(farmId)) {
          throw ArgumentError('Authorized directory farm IDs must be unique');
        }
      }
    }
    return organization;
  }

  SyncRunReport _combineReports(List<SyncRunReport> reports) => SyncRunReport(
    sent: reports.fold(0, (sum, report) => sum + report.sent),
    applied: reports.fold(0, (sum, report) => sum + report.applied),
    rejected: reports.fold(0, (sum, report) => sum + report.rejected),
    conflicted: reports.fold(0, (sum, report) => sum + report.conflicted),
    blocked: reports.fold(0, (sum, report) => sum + report.blocked),
    reconciled: reports.fold(0, (sum, report) => sum + report.reconciled),
    pulledChangeSets: reports.fold(
      0,
      (sum, report) => sum + report.pulledChangeSets,
    ),
    bootstrapped: reports.any((report) => report.bootstrapped),
  );

  String _scopeKey(FarmlyMutationScope scope) =>
      '${scope.accountId}|${scope.organizationId}|${scope.farmId ?? ''}';

  /// Read confirmed local data and its cursor from the same authenticated
  /// scope projection used by the sync worker.
  Future<LocalDomainSnapshot?> domainSnapshot(FarmlyMutationScope scope) =>
      _domain.snapshotFor(_scopeKey(scope));

  /// One full pass: flush the outbox for the scope, then pull the feed
  /// (or re-bootstrap when the cursor is dead). Transport failures leave
  /// durable entries in place — the next pass retries idempotently.
  Future<SyncRunReport> synchronize(FarmlyMutationScope scope) async {
    var sent = 0, applied = 0, rejected = 0, conflicted = 0, blocked = 0;
    var reconciled = 0, pulled = 0;
    var bootstrapped = false;

    final entries = await _outbox.entries(
      accountId: scope.accountId,
      organizationId: scope.organizationId,
    );
    final byId = {for (final e in entries) e.operationId: e};

    final settledStatus = <String, OutboxEntryStatus>{};
    OutboxEntryStatus? statusOf(String id) =>
        settledStatus[id] ?? byId[id]?.status;

    // A cycle cannot settle through server outcomes. Persist every member as
    // blocked so the Sync Center exposes the malformed local dependency graph.
    final cycleIds = _dependencyCycleIds(entries, byId);
    for (final entry in entries) {
      if (!cycleIds.contains(entry.operationId) ||
          (entry.status != OutboxEntryStatus.pending &&
              entry.status != OutboxEntryStatus.inFlight)) {
        continue;
      }
      await _outbox.update(
        entry.copyWith(
          status: OutboxEntryStatus.blocked,
          lastFailureCode: 'DEPENDENCY_CYCLE',
        ),
      );
      settledStatus[entry.operationId] = OutboxEntryStatus.blocked;
      blocked++;
    }

    // Dependencies are settled after every response and at the start of each
    // batch round. That also recovers a parent rejection after process restart.
    Future<void> settleFailedDependencies() async {
      for (final entry in entries) {
        if (statusOf(entry.operationId) != OutboxEntryStatus.pending) continue;
        for (final dependencyId in entry.dependsOn) {
          final parent = statusOf(dependencyId);
          final failureCode = parent == null
              ? 'DEPENDENCY_MISSING'
              : parent == OutboxEntryStatus.blocked
              ? 'DEPENDENCY_BLOCKED'
              : parent == OutboxEntryStatus.rejected ||
                    parent == OutboxEntryStatus.conflict
              ? 'DEPENDENCY_FAILED'
              : null;
          if (failureCode == null) continue;
          await _outbox.update(
            entry.copyWith(
              status: OutboxEntryStatus.blocked,
              lastFailureCode: failureCode,
            ),
          );
          settledStatus[entry.operationId] = OutboxEntryStatus.blocked;
          blocked++;
          break;
        }
      }
    }

    // An earlier request may have lost its response after the server denied
    // it. Reconcile persisted in-flight entries before any operation can be
    // submitted again, including after an app restart.
    final inFlightForScope = entries
        .where(
          (entry) =>
              entry.mutation.scope.farmId == scope.farmId &&
              entry.status == OutboxEntryStatus.inFlight &&
              !cycleIds.contains(entry.operationId),
        )
        .toList(growable: false);
    if (inFlightForScope.isNotEmpty) {
      final result = await _reconcile(scope, inFlightForScope, settledStatus);
      reconciled += result.reconciled;
      rejected += result.rejected;
      await settleFailedDependencies();
    }

    bool terminal(OutboxEntry entry) {
      final status = statusOf(entry.operationId);
      return status == OutboxEntryStatus.applied ||
          status == OutboxEntryStatus.rejected ||
          status == OutboxEntryStatus.conflict ||
          status == OutboxEntryStatus.blocked;
    }

    while (true) {
      await settleFailedDependencies();
      final sendable = <OutboxEntry>[];
      for (final entry in entries) {
        final entryStatus = statusOf(entry.operationId);
        if (entry.mutation.scope.farmId != scope.farmId ||
            (entryStatus != OutboxEntryStatus.pending &&
                entryStatus != OutboxEntryStatus.inFlight) ||
            (entryStatus == OutboxEntryStatus.inFlight &&
                !settledStatus.containsKey(entry.operationId)) ||
            cycleIds.contains(entry.operationId)) {
          continue;
        }
        if (entry.dependsOn.any(
          (dependencyId) => statusOf(dependencyId) != OutboxEntryStatus.applied,
        )) {
          continue;
        }
        sendable.add(entry);
      }
      if (sendable.isEmpty) break;

      var stopAfterBatch = false;
      for (var offset = 0; offset < sendable.length; offset += 50) {
        final end = min(offset + 50, sendable.length);
        final batch = sendable.sublist(offset, end);
        sent += batch.length;
        MutationBatchResult? result;
        try {
          result = await _transport.submitMutations(
            scope: scope,
            operations: [for (final entry in batch) entry.mutation.intent],
          );
        } on Object catch (error) {
          // Ambiguous send (lost ACK is indistinguishable from unsent): mark
          // in-flight and reconcile the same bounded batch by stable IDs.
          // Keep safe typed rejection classes so an unknown ledger result
          // cannot turn a known denial into an endless retry.
          final failureMarker = _batchFailureMarker(error);
          final inFlightBatch = <OutboxEntry>[];
          for (final entry in batch) {
            final inFlightEntry = entry.copyWith(
              status: OutboxEntryStatus.inFlight,
              attemptCount: entry.attemptCount + 1,
              lastFailureCode: failureMarker,
            );
            await _outbox.update(inFlightEntry);
            settledStatus[entry.operationId] = OutboxEntryStatus.inFlight;
            inFlightBatch.add(inFlightEntry);
          }
          final reconciliation = await _reconcile(
            scope,
            inFlightBatch,
            settledStatus,
          );
          reconciled += reconciliation.reconciled;
          rejected += reconciliation.rejected;
          await settleFailedDependencies();
          if (inFlightBatch.any((entry) => !terminal(entry))) {
            stopAfterBatch = true;
            break;
          }
          continue;
        }

        final outcomes = {
          for (final outcome in result.outcomes) outcome.operationId: outcome,
        };
        for (final entry in batch) {
          final outcome = outcomes[entry.operationId];
          if (outcome == null) {
            final inFlightEntry = entry.copyWith(
              status: OutboxEntryStatus.inFlight,
              attemptCount: entry.attemptCount + 1,
              lastFailureCode: 'OUTCOME_MISSING',
            );
            await _outbox.update(inFlightEntry);
            settledStatus[entry.operationId] = OutboxEntryStatus.inFlight;
            final reconciliation = await _reconcile(scope, [
              inFlightEntry,
            ], settledStatus);
            reconciled += reconciliation.reconciled;
            rejected += reconciliation.rejected;
            continue;
          }
          switch (outcome.outcome) {
            case 'applied':
              await _outbox.update(
                entry.copyWith(
                  status: OutboxEntryStatus.applied,
                  appliedRevision: outcome.revision,
                ),
              );
              settledStatus[entry.operationId] = OutboxEntryStatus.applied;
              applied++;
            case 'rejected':
              await _outbox.update(
                entry.copyWith(
                  status: OutboxEntryStatus.rejected,
                  rejectionCode: outcome.code,
                ),
              );
              settledStatus[entry.operationId] = OutboxEntryStatus.rejected;
              rejected++;
            case 'conflict':
              await _outbox.update(
                entry.copyWith(status: OutboxEntryStatus.conflict),
              );
              settledStatus[entry.operationId] = OutboxEntryStatus.conflict;
              _conflicts.add(
                SyncConflict(
                  entry: entry.copyWith(status: OutboxEntryStatus.conflict),
                  detectedAt: DateTime.now().toUtc(),
                  serverAsOf: result.asOf,
                ),
              );
              conflicted++;
            default:
              await _outbox.update(
                entry.copyWith(
                  status: OutboxEntryStatus.pending,
                  lastFailureCode: 'OUTCOME_UNKNOWN',
                ),
              );
              settledStatus[entry.operationId] = OutboxEntryStatus.pending;
          }
        }
        await settleFailedDependencies();
        if (batch.any((entry) => !terminal(entry))) {
          stopAfterBatch = true;
          break;
        }
      }
      if (stopAfterBatch) break;
    }

    if (scope.kind == FarmlyMutationScopeKind.farm) {
      final feed = await _pullFeed(scope);
      pulled = feed.pulled;
      bootstrapped = feed.bootstrapped;
    }

    return SyncRunReport(
      sent: sent,
      applied: applied,
      rejected: rejected,
      conflicted: conflicted,
      blocked: blocked,
      reconciled: reconciled,
      pulledChangeSets: pulled,
      bootstrapped: bootstrapped,
    );
  }

  /// Lost-ACK path: ask the server's durable operation ledger instead of
  /// trusting a transport response. An unknown result stays pending for
  /// ambiguous failures, while a previously observed typed denial is terminal.
  Future<({int reconciled, int rejected})> _reconcile(
    FarmlyMutationScope scope,
    List<OutboxEntry> entries,
    Map<String, OutboxEntryStatus> settledStatus,
  ) async {
    var reconciled = 0;
    var rejected = 0;
    List<OperationStatusEntry> proofs;
    try {
      proofs = await _transport.operationStatus(
        accountId: scope.accountId,
        operationIds: [for (final e in entries) e.operationId],
      );
    } on Object {
      return (reconciled: 0, rejected: 0);
    }
    final byId = {for (final p in proofs) p.operationId: p.proof};
    for (final entry in entries) {
      switch (byId[entry.operationId]) {
        case OperationProof.applied:
          await _outbox.update(
            entry.copyWith(status: OutboxEntryStatus.applied),
          );
          settledStatus[entry.operationId] = OutboxEntryStatus.applied;
          reconciled++;
        case OperationProof.rejected:
          final rejectionCode =
              _rejectionForReconciledFailure(entry) ?? 'REJECTED';
          await _outbox.update(
            entry.copyWith(
              status: OutboxEntryStatus.rejected,
              rejectionCode: rejectionCode,
            ),
          );
          settledStatus[entry.operationId] = OutboxEntryStatus.rejected;
          reconciled++;
          rejected++;
        case OperationProof.unknown:
        case null:
          final rejectionCode = _rejectionForReconciledFailure(entry);
          if (rejectionCode != null) {
            // A typed client error proves the request was rejected once no
            // durable operation receipt exists. Do not replay it forever.
            await _outbox.update(
              entry.copyWith(
                status: OutboxEntryStatus.rejected,
                rejectionCode: rejectionCode,
              ),
            );
            settledStatus[entry.operationId] = OutboxEntryStatus.rejected;
            reconciled++;
            rejected++;
          } else {
            // Ambiguous transport failures with no receipt are safe to replay
            // under the same immutable operation ID.
            await _outbox.update(
              entry.copyWith(status: OutboxEntryStatus.pending),
            );
            settledStatus[entry.operationId] = OutboxEntryStatus.pending;
          }
      }
    }
    return (reconciled: reconciled, rejected: rejected);
  }

  Set<String> _dependencyCycleIds(
    List<OutboxEntry> entries,
    Map<String, OutboxEntry> byId,
  ) {
    final visitState = <String, int>{};
    final path = <String>[];
    final cycleIds = <String>{};

    bool unresolved(OutboxEntry entry) =>
        entry.status == OutboxEntryStatus.pending ||
        entry.status == OutboxEntryStatus.inFlight;

    void visit(OutboxEntry entry) {
      final id = entry.operationId;
      visitState[id] = 1;
      path.add(id);
      for (final dependencyId in entry.dependsOn) {
        final parent = byId[dependencyId];
        if (parent == null || !unresolved(parent)) continue;
        final parentState = visitState[dependencyId] ?? 0;
        if (parentState == 1) {
          cycleIds.addAll(path.skip(path.indexOf(dependencyId)));
        } else if (parentState == 0) {
          visit(parent);
        }
      }
      path.removeLast();
      visitState[id] = 2;
    }

    for (final entry in entries) {
      if (unresolved(entry) && (visitState[entry.operationId] ?? 0) == 0) {
        visit(entry);
      }
    }
    return cycleIds;
  }

  /// Pull committed change sets in revision order; an expired/dead cursor
  /// falls back to a full bootstrap — pending intents survive untouched.
  Future<({int pulled, bool bootstrapped})> _pullFeed(
    FarmlyMutationScope scope,
  ) async {
    final scopeKey = _scopeKey(scope);
    final state = await _domain.cursorFor(scopeKey);
    if (state == null) {
      await _bootstrap(scope);
      return (pulled: 0, bootstrapped: true);
    }

    var pulled = 0;
    var cursor = state.cursor;
    for (;;) {
      ChangeFeedPage page;
      try {
        page = await _transport.fetchChanges(scope: scope, cursor: cursor);
      } on FarmlyApiFailure catch (failure) {
        if (failure.code == FarmlyApiFailureCode.cursorExpired) {
          await _bootstrap(scope);
          return (pulled: pulled, bootstrapped: true);
        }
        rethrow;
      }
      for (final changeSet in page.changeSets) {
        final isLast = identical(changeSet, page.changeSets.last);
        await _domain.applyChangeSet(
          scopeKey: scopeKey,
          changeSet: changeSet,
          cursor: SyncCursorState(
            cursor: isLast ? page.nextCursor : cursor,
            highWatermark: page.highWatermark,
            continuityEpoch: changeSet.continuityEpoch,
            scopePolicyVersion: state.scopePolicyVersion,
          ),
        );
      }
      pulled += page.changeSets.length;
      if (!page.hasMore) break;
      cursor = page.nextCursor;
    }
    return (pulled: pulled, bootstrapped: false);
  }

  /// Server-side snapshot + chunk walk, installed atomically per scope.
  Future<void> _bootstrap(FarmlyMutationScope scope) async {
    final scopeKey = _scopeKey(scope);
    final manifest = await _transport.createBootstrap(
      scope: scope,
      operationId: _newOperationId(),
    );
    final blocks = <BootstrapBlock>[];
    String? pageCursor;
    for (;;) {
      final page = await _transport.fetchBootstrapPage(
        scope: scope,
        snapshotId: manifest.snapshotId,
        pageCursor: pageCursor,
      );
      blocks.addAll(page.blocks);
      if (!page.hasMore) break;
      pageCursor = page.nextPageCursor;
    }
    await _domain.installBootstrap(
      scopeKey: scopeKey,
      blocks: blocks,
      cursor: SyncCursorState(
        cursor: manifest.changesCursor,
        highWatermark: manifest.highWatermark,
        continuityEpoch: manifest.continuityEpoch,
        scopePolicyVersion: manifest.scopePolicyVersion,
      ),
    );
  }

  /// Durable outbox view for one account+org — used by the Sync Center and
  /// diagnostics. Reads durable truth, never the transport.
  Future<List<OutboxEntry>> entries({
    required String accountId,
    required String organizationId,
  }) => _outbox.entries(accountId: accountId, organizationId: organizationId);

  /// User chose "giữ bản máy chủ": the conflicted local intent is retired as
  /// superseded (auditable, immutable) and the conflict record clears.
  Future<void> dismissConflict(SyncConflict conflict) async {
    await _outbox.update(
      conflict.entry.copyWith(
        status: OutboxEntryStatus.rejected,
        rejectionCode: 'SUPERSEDED_BY_SERVER',
      ),
    );
    _conflicts.removeWhere(
      (c) => c.entry.operationId == conflict.entry.operationId,
    );
  }

  /// User chose "gửi bản của bạn": the original intent is retired
  /// (superseded — auditable, immutable) and a NEW operationId carries the
  /// same payload at the server's current baseVersion. No silent merge.
  Future<OutboxEntry> resolveConflict(
    SyncConflict conflict, {
    required int newBaseVersion,
  }) async {
    final entry = conflict.entry;
    await _outbox.update(
      entry.copyWith(
        status: OutboxEntryStatus.rejected,
        rejectionCode: 'SUPERSEDED',
      ),
    );
    final replacement = FarmlyScopedMutation(
      scope: entry.mutation.scope,
      intent: replacementIntent(
        conflict: conflict,
        newOperationId: _newOperationId(),
        newBaseVersion: newBaseVersion,
      ),
    );
    _conflicts.removeWhere((c) => c.entry.operationId == entry.operationId);
    return _outbox.enqueue(replacement);
  }
}

String _batchFailureMarker(Object error) {
  if (error is! FarmlyApiFailure) return 'TRANSPORT';
  return switch (error.code) {
    FarmlyApiFailureCode.permissionDenied => 'RECONCILE_PERMISSION_DENIED',
    FarmlyApiFailureCode.invalidRequest => 'RECONCILE_INVALID_REQUEST',
    FarmlyApiFailureCode.notFound => 'RECONCILE_NOT_FOUND',
    FarmlyApiFailureCode.conflict => 'RECONCILE_CONFLICT',
    _ => 'TRANSPORT',
  };
}

String? _rejectionForReconciledFailure(OutboxEntry entry) =>
    switch (entry.lastFailureCode) {
      'RECONCILE_PERMISSION_DENIED' => 'PERMISSION_DENIED',
      'RECONCILE_INVALID_REQUEST' ||
      'RECONCILE_NOT_FOUND' ||
      'RECONCILE_CONFLICT' => 'RECONCILIATION_REQUIRED',
      _ => null,
    };
