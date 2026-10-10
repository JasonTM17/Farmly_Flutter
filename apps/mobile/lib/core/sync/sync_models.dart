import 'farmly_mutation.dart';

/// Local lifecycle of one immutable outbox intent (spec04 §7; no LWW).
enum OutboxEntryStatus {
  /// Durable, not yet handed to the server this session.
  pending,

  /// Sent at least once; result unknown (lost ACK). Reconciled via
  /// /me/operation-status or idempotent replay — never silently resent as a
  /// new operation.
  inFlight,

  /// Server applied the intent (including idempotent replay proof).
  applied,

  /// Server rejected the intent — terminal, user-visible, never retried.
  rejected,

  /// Server reported a version conflict — parked for manual resolution.
  conflict,

  /// A declared dependency is not applied (rejected/conflict/unknown) — the
  /// intent is held, not sent.
  blocked,
}

/// Durable local record of one immutable intent.
final class OutboxEntry {
  const OutboxEntry({
    required this.mutation,
    required this.status,
    required this.sequence,
    this.attemptCount = 0,
    this.lastFailureCode,
    this.appliedRevision,
    this.rejectionCode,
  });

  final FarmlyScopedMutation mutation;
  final OutboxEntryStatus status;

  /// Monotonic enqueue order inside the account scope.
  final int sequence;
  final int attemptCount;
  final String? lastFailureCode;
  final String? appliedRevision;
  final String? rejectionCode;

  String get operationId => mutation.intent.operationId;
  List<String> get dependsOn => mutation.intent.dependsOn;

  OutboxEntry copyWith({
    OutboxEntryStatus? status,
    int? attemptCount,
    String? lastFailureCode,
    String? appliedRevision,
    String? rejectionCode,
  }) => OutboxEntry(
    mutation: mutation,
    status: status ?? this.status,
    sequence: sequence,
    attemptCount: attemptCount ?? this.attemptCount,
    lastFailureCode: lastFailureCode,
    appliedRevision: appliedRevision ?? this.appliedRevision,
    rejectionCode: rejectionCode ?? this.rejectionCode,
  );
}

/// One entry inside a committed change set (spec04 §5.1 wire shape).
final class SyncChangeEntry {
  const SyncChangeEntry({
    required this.entity,
    required this.change,
    required this.record,
  });

  final String entity;
  final String change;
  final Map<String, Object?> record;

  factory SyncChangeEntry.fromJson(Map<String, Object?> json) {
    final record = json['record'];
    return SyncChangeEntry(
      entity: json['entity'] as String,
      change: json['change'] as String,
      record: record is Map ? Map<String, Object?>.from(record) : const {},
    );
  }
}

/// One committed farm-clock revision: an ordered, complete set of changes.
final class SyncChangeSet {
  const SyncChangeSet({
    required this.revision,
    required this.continuityEpoch,
    required this.operationId,
    required this.schemaVersion,
    required this.changes,
    required this.createdAt,
  });

  final String revision;
  final String continuityEpoch;
  final String? operationId;
  final String schemaVersion;
  final List<SyncChangeEntry> changes;
  final String createdAt;

  factory SyncChangeSet.fromJson(Map<String, Object?> json) => SyncChangeSet(
    revision: json['revision'] as String,
    continuityEpoch: json['continuityEpoch'] as String,
    operationId: json['operationId'] as String?,
    schemaVersion: json['schemaVersion'] as String,
    changes: [
      for (final entry in (json['changes'] as List? ?? const []))
        SyncChangeEntry.fromJson(Map<String, Object?>.from(entry as Map)),
    ],
    createdAt: json['createdAt'] as String,
  );
}

/// One page of the signed-cursor change feed.
final class ChangeFeedPage {
  const ChangeFeedPage({
    required this.changeSets,
    required this.highWatermark,
    required this.hasMore,
    required this.nextCursor,
  });

  final List<SyncChangeSet> changeSets;
  final String highWatermark;
  final bool hasMore;
  final String nextCursor;
}

/// Bootstrap snapshot manifest returned by POST .../sync/bootstrap.
final class BootstrapManifest {
  const BootstrapManifest({
    required this.snapshotId,
    required this.expiresAt,
    required this.continuityEpoch,
    required this.scopePolicyVersion,
    required this.highWatermark,
    required this.prunedThroughRevision,
    required this.totalRows,
    required this.byteCount,
    required this.chunkCount,
    required this.changesCursor,
  });

  final String snapshotId;
  final String expiresAt;
  final String continuityEpoch;
  final String scopePolicyVersion;
  final String highWatermark;
  final String prunedThroughRevision;
  final int totalRows;
  final int byteCount;
  final int chunkCount;
  final String changesCursor;
}

/// One entity block inside a bootstrap chunk payload.
final class BootstrapBlock {
  const BootstrapBlock({required this.entity, required this.records});

  final String entity;
  final List<Map<String, Object?>> records;

  factory BootstrapBlock.fromJson(Map<String, Object?> json) => BootstrapBlock(
    entity: json['entity'] as String,
    records: [
      for (final record in (json['records'] as List? ?? const []))
        Map<String, Object?>.from(record as Map),
    ],
  );
}

/// One page of bootstrap chunk reads.
final class BootstrapPage {
  const BootstrapPage({
    required this.snapshotId,
    required this.pageIndex,
    required this.rowCount,
    required this.blocks,
    required this.hasMore,
    required this.nextPageCursor,
    required this.chunkCount,
  });

  final String snapshotId;
  final int pageIndex;
  final int rowCount;
  final List<BootstrapBlock> blocks;
  final bool hasMore;
  final String? nextPageCursor;
  final int chunkCount;
}

/// Per-operation outcome inside a mutation batch response.
final class MutationOutcome {
  const MutationOutcome({
    required this.operationId,
    required this.outcome,
    this.revision,
    this.code,
  });

  final String operationId;

  /// 'applied' | 'rejected' | 'conflict'
  final String outcome;
  final String? revision;
  final String? code;
}

/// Result of submitting one ordered batch to a sync/mutations endpoint.
final class MutationBatchResult {
  const MutationBatchResult({
    required this.outcomes,
    required this.asOf,
    required this.scopePolicyVersion,
  });

  final List<MutationOutcome> outcomes;
  final String? asOf;
  final String? scopePolicyVersion;
}

/// Server-side truth about an operation after a lost ACK (spec04 S-05/S-06:
/// 'unknown' is honest — never collapse to notApplied).
enum OperationProof { applied, rejected, unknown }

final class OperationStatusEntry {
  const OperationStatusEntry({required this.operationId, required this.proof});

  final String operationId;
  final OperationProof proof;
}
