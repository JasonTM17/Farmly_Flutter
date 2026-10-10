import 'farmly_mutation.dart';
import 'sync_models.dart';

/// A version conflict parked for explicit user choice (spec08 step 5: manual
/// conflicts only — no LWW, no quantitative merge, never a retried mutation
/// silently wearing a new baseVersion).
final class SyncConflict {
  const SyncConflict({
    required this.entry,
    required this.detectedAt,
    this.serverRevision,
    this.serverRecord,
    this.serverAsOf,
  });

  /// The original outbox entry — immutable; resolving never edits it.
  final OutboxEntry entry;
  final DateTime detectedAt;

  /// Server-side context when the batch outcome carried it.
  final String? serverRevision;
  final Map<String, Object?>? serverRecord;
  final String? serverAsOf;
}

/// Builds the replacement intent for "gửi bản của bạn": same payload, NEW
/// operationId, and the server's current version as baseVersion. The original
/// intent bytes stay untouched in the conflict record for audit.
FarmlyMutationIntent replacementIntent({
  required SyncConflict conflict,
  required String newOperationId,
  required int newBaseVersion,
}) {
  final original = conflict.entry.mutation.intent;
  return FarmlyMutationIntent.fromJson(
    Map<String, Object?>.from(original.toJson())
      ..['operationId'] = newOperationId
      ..['baseVersion'] = newBaseVersion,
  );
}
