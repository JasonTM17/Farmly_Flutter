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

  String _scopeKey(FarmlyMutationScope scope) =>
      '${scope.accountId}|${scope.organizationId}|${scope.farmId ?? ''}';

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

    // Entries the dependency gate marks blocked this pass.
    final gateBlocked = <String>{};

    // Dependency gate: an intent only flies once every declared parent is
    // provably applied (in this store or already absent = server-known).
    final sendable = <OutboxEntry>[];
    for (final entry in entries) {
      if (entry.mutation.scope.farmId != scope.farmId) continue;
      if (entry.status != OutboxEntryStatus.pending &&
          entry.status != OutboxEntryStatus.inFlight) {
        continue;
      }
      var held = false;
      for (final dep in entry.dependsOn) {
        final parent = byId[dep];
        if (parent == null || parent.status == OutboxEntryStatus.applied) {
          continue;
        }
        if (parent.status == OutboxEntryStatus.rejected ||
            parent.status == OutboxEntryStatus.conflict) {
          await _outbox.update(entry.copyWith(status: OutboxEntryStatus.blocked));
          gateBlocked.add(entry.operationId);
          blocked++;
          held = true;
          break;
        }
        // parent still pending/in-flight — hold silently this pass.
        held = true;
        break;
      }
      if (!held) sendable.add(entry);
    }

    // Statuses settled this pass, keyed by operationId — `byId` goes stale the
    // moment an outcome is written, so dependency settlement reads this.
    final settledStatus = <String, OutboxEntryStatus>{};
    for (final id in gateBlocked) {
      settledStatus[id] = OutboxEntryStatus.blocked;
    }
    OutboxEntryStatus? statusOf(String id) =>
        settledStatus[id] ?? byId[id]?.status;

    if (sendable.isNotEmpty) {
      sent = sendable.length;
      MutationBatchResult? result;
      try {
        result = await _transport.submitMutations(
          scope: scope,
          operations: [for (final e in sendable) e.mutation.intent],
        );
      } on Object {
        // Ambiguous send (lost ACK is indistinguishable from unsent): mark
        // in-flight and reconcile against the durable operation ledger.
        for (final entry in sendable) {
          await _outbox.update(
            entry.copyWith(
              status: OutboxEntryStatus.inFlight,
              attemptCount: entry.attemptCount + 1,
              lastFailureCode: 'TRANSPORT',
            ),
          );
        }
        final proofs = await _reconcile(scope, sendable, settledStatus);
        reconciled = proofs;
      }
      if (result != null) {
        final outcomes = {
          for (final o in result.outcomes) o.operationId: o,
        };
        for (final entry in sendable) {
          final outcome = outcomes[entry.operationId];
          if (outcome == null) {
            await _outbox.update(
              entry.copyWith(
                status: OutboxEntryStatus.inFlight,
                attemptCount: entry.attemptCount + 1,
                lastFailureCode: 'OUTCOME_MISSING',
              ),
            );
            reconciled += await _reconcile(scope, [entry], settledStatus);
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
      }

      // Settle dependency fallout in the same pass: children held at the
      // gate by a parent that just reached a terminal failure become
      // `blocked` now rather than next pass. Sendable entries already flew —
      // their truth lives in outcomes/reconcile, not the dependency gate.
      for (final entry in entries) {
        if (sendable.any((e) => e.operationId == entry.operationId)) continue;
        if (statusOf(entry.operationId) != OutboxEntryStatus.pending) {
          continue;
        }
        for (final dep in entry.dependsOn) {
          final parent = statusOf(dep);
          if (parent == OutboxEntryStatus.rejected ||
              parent == OutboxEntryStatus.conflict) {
            await _outbox.update(
              entry.copyWith(status: OutboxEntryStatus.blocked),
            );
            settledStatus[entry.operationId] = OutboxEntryStatus.blocked;
            blocked++;
            break;
          }
        }
      }
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
  /// trusting a transport response (S-05/S-06 — 'unknown' stays pending,
  /// never silently marked not-applied).
  Future<int> _reconcile(
    FarmlyMutationScope scope,
    List<OutboxEntry> entries,
    Map<String, OutboxEntryStatus> settledStatus,
  ) async {
    var reconciled = 0;
    List<OperationStatusEntry> proofs;
    try {
      proofs = await _transport.operationStatus(
        accountId: scope.accountId,
        operationIds: [for (final e in entries) e.operationId],
      );
    } on Object {
      return 0; // ledger unreachable — entries stay in-flight honestly.
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
          await _outbox.update(
            entry.copyWith(
              status: OutboxEntryStatus.rejected,
              rejectionCode: 'REJECTED',
            ),
          );
          settledStatus[entry.operationId] = OutboxEntryStatus.rejected;
          reconciled++;
        case OperationProof.unknown:
        case null:
          // Never claimed: back to pending — replay is idempotent by opId.
          await _outbox.update(
            entry.copyWith(status: OutboxEntryStatus.pending),
          );
          settledStatus[entry.operationId] = OutboxEntryStatus.pending;
      }
    }
    return reconciled;
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
            scopePolicyVersion:
                state.scopePolicyVersion,
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
  }) => _outbox.entries(
        accountId: accountId,
        organizationId: organizationId,
      );

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
