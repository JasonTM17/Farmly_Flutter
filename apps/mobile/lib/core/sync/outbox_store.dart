import 'dart:convert';
import 'dart:io';

import '../storage/encrypted_mutation_envelope.dart';
import '../storage/offline_key_store.dart';
import 'farmly_mutation.dart';
import 'sync_models.dart';

/// Durable outbox boundary. Entries are immutable intents plus lifecycle
/// state; an operation ID can never be rebound to different intent bytes.
abstract interface class OutboxStore {
  /// Atomically persist a new pending entry. Re-enqueueing the same
  /// operationId with identical intent bytes is a no-op (retry-safe); with
  /// different bytes it throws — an operation ID is immutable.
  Future<OutboxEntry> enqueue(FarmlyScopedMutation mutation);

  /// All entries for an account+organization, in enqueue order.
  Future<List<OutboxEntry>> entries({
    required String accountId,
    required String organizationId,
  });

  /// Persist a lifecycle transition for an existing entry.
  Future<void> update(OutboxEntry entry);

  /// Look up one entry across scopes (reconciliation path).
  Future<OutboxEntry?> find({
    required String accountId,
    required String organizationId,
    required String operationId,
  });
}

final class OutboxOperationConflict implements Exception {
  const OutboxOperationConflict(this.operationId);

  final String operationId;

  @override
  String toString() =>
      'Operation $operationId is already bound to a different intent';
}

String _entryKey(OutboxEntry entry) =>
    '${entry.mutation.scope.accountId}|${entry.mutation.scope.organizationId}|${entry.operationId}';

/// Volatile store — used by tests and as the reference semantics for the
/// durable implementation.
final class InMemoryOutboxStore implements OutboxStore {
  final Map<String, OutboxEntry> _entries = {};
  int _sequence = 0;

  @override
  Future<OutboxEntry> enqueue(FarmlyScopedMutation mutation) async {
    final probe = OutboxEntry(
      mutation: mutation,
      status: OutboxEntryStatus.pending,
      sequence: 0,
    );
    final key = _entryKey(probe);
    final existing = _entries[key];
    if (existing != null) {
      final sameBytes =
          jsonEncode(existing.mutation.toRequestJson()) ==
          jsonEncode(mutation.toRequestJson());
      if (!sameBytes) {
        throw OutboxOperationConflict(mutation.intent.operationId);
      }
      return existing;
    }
    final entry = OutboxEntry(
      mutation: mutation,
      status: OutboxEntryStatus.pending,
      sequence: ++_sequence,
    );
    _entries[key] = entry;
    return entry;
  }

  @override
  Future<List<OutboxEntry>> entries({
    required String accountId,
    required String organizationId,
  }) async =>
      _entries.values
          .where(
            (entry) =>
                entry.mutation.scope.accountId == accountId &&
                entry.mutation.scope.organizationId == organizationId,
          )
          .toList()
        ..sort((a, b) => a.sequence.compareTo(b.sequence));

  @override
  Future<void> update(OutboxEntry entry) async {
    if (!_entries.containsKey(_entryKey(entry))) {
      throw StateError('Outbox entry ${entry.operationId} does not exist');
    }
    _entries[_entryKey(entry)] = entry;
  }

  @override
  Future<OutboxEntry?> find({
    required String accountId,
    required String organizationId,
    required String operationId,
  }) async => _entries['$accountId|$organizationId|$operationId'];
}

/// Durable store: one JSON document per account, every intent payload sealed
/// as an AES-256-GCM envelope bound to its scope+operationId (AAD), so a
/// forged/renamed/cross-account blob fails authentication instead of loading.
final class EncryptedFileOutboxStore implements OutboxStore {
  EncryptedFileOutboxStore({required Directory directory, required this._key})
    : _file = File('${directory.path}/farmly-outbox.v1.json');

  final File _file;
  final FarmlyOfflineKey _key;
  final FarmlyOutboxCipher _cipher = const FarmlyOutboxCipher();
  Map<String, OutboxEntry>? _cache;
  int _sequence = 0;

  @override
  Future<OutboxEntry> enqueue(FarmlyScopedMutation mutation) async {
    final entries = await _load();
    final probe = OutboxEntry(
      mutation: mutation,
      status: OutboxEntryStatus.pending,
      sequence: 0,
    );
    final key = _entryKey(probe);
    final existing = entries[key];
    if (existing != null) {
      final sameBytes =
          jsonEncode(existing.mutation.toRequestJson()) ==
          jsonEncode(mutation.toRequestJson());
      if (!sameBytes) {
        throw OutboxOperationConflict(mutation.intent.operationId);
      }
      return existing;
    }
    final nextSequence = _sequence + 1;
    final entry = OutboxEntry(
      mutation: mutation,
      status: OutboxEntryStatus.pending,
      sequence: nextSequence,
    );
    final updated = Map<String, OutboxEntry>.of(entries)..[key] = entry;
    await _persist(updated);
    _cache = updated;
    _sequence = nextSequence;
    return entry;
  }

  @override
  Future<List<OutboxEntry>> entries({
    required String accountId,
    required String organizationId,
  }) async =>
      (await _load()).values
          .where(
            (entry) =>
                entry.mutation.scope.accountId == accountId &&
                entry.mutation.scope.organizationId == organizationId,
          )
          .toList()
        ..sort((a, b) => a.sequence.compareTo(b.sequence));

  @override
  Future<void> update(OutboxEntry entry) async {
    final entries = await _load();
    if (!entries.containsKey(_entryKey(entry))) {
      throw StateError('Outbox entry ${entry.operationId} does not exist');
    }
    final updated = Map<String, OutboxEntry>.of(entries)
      ..[_entryKey(entry)] = entry;
    await _persist(updated);
    _cache = updated;
  }

  @override
  Future<OutboxEntry?> find({
    required String accountId,
    required String organizationId,
    required String operationId,
  }) async => (await _load())['$accountId|$organizationId|$operationId'];

  Future<Map<String, OutboxEntry>> _load() async {
    if (_cache != null) return _cache!;
    final entries = <String, OutboxEntry>{};
    if (await _file.exists()) {
      final decoded = jsonDecode(await _file.readAsString());
      if (decoded is! Map ||
          decoded['version'] != 1 ||
          decoded['entries'] is! List) {
        throw const FormatException('Invalid Farmly outbox document');
      }
      for (final raw in decoded['entries'] as List) {
        final entry = await _decodeEntry(Map<String, Object?>.from(raw as Map));
        entries[_entryKey(entry)] = entry;
        if (entry.sequence > _sequence) _sequence = entry.sequence;
      }
    }
    _cache = entries;
    return entries;
  }

  /// Atomic write: temp file + rename so a kill mid-write never leaves a
  /// half-truncated outbox (spec08 step 6 reopen path).
  Future<void> _persist(Map<String, OutboxEntry> entries) async {
    final envelopes = <Map<String, Object?>>[];
    for (final entry in entries.values) {
      envelopes.add(await _encodeEntry(entry));
    }
    final document = jsonEncode({'version': 1, 'entries': envelopes});
    final temp = File('${_file.path}.tmp');
    await temp.writeAsString(document, flush: true);
    await temp.rename(_file.path);
  }

  Future<Map<String, Object?>> _encodeEntry(OutboxEntry entry) async {
    final envelope = await _cipher.encrypt(mutation: entry.mutation, key: _key);
    final scope = entry.mutation.scope;
    return {
      'accountId': scope.accountId,
      'organizationId': scope.organizationId,
      'farmId': scope.farmId,
      'scopeKind': scope.kind.name,
      'continuityEpoch': scope.continuityEpoch,
      'operationId': entry.operationId,
      'status': entry.status.name,
      'sequence': entry.sequence,
      'attemptCount': entry.attemptCount,
      'lastFailureCode': entry.lastFailureCode,
      'appliedRevision': entry.appliedRevision,
      'rejectionCode': entry.rejectionCode,
      'envelope': envelope.toJson(),
    };
  }

  Future<OutboxEntry> _decodeEntry(Map<String, Object?> row) async {
    final scopeKind = row['scopeKind'] == 'organization'
        ? FarmlyMutationScopeKind.organization
        : FarmlyMutationScopeKind.farm;
    final scope = scopeKind == FarmlyMutationScopeKind.organization
        ? FarmlyMutationScope.organization(
            accountId: row['accountId'] as String,
            organizationId: row['organizationId'] as String,
            continuityEpoch: row['continuityEpoch'] as String,
          )
        : FarmlyMutationScope.farm(
            accountId: row['accountId'] as String,
            organizationId: row['organizationId'] as String,
            farmId: row['farmId'] as String,
            continuityEpoch: row['continuityEpoch'] as String,
          );
    final operationId = row['operationId'] as String;
    final cleartext = await _cipher.decrypt(
      envelope: FarmlyEncryptedMutationEnvelope.fromJson(row['envelope']),
      scope: scope,
      operationId: operationId,
      key: _key,
    );
    final intentJson = Map<String, Object?>.from(jsonDecode(cleartext) as Map);
    final intent = FarmlyMutationIntent.fromJson(intentJson);
    return OutboxEntry(
      mutation: FarmlyScopedMutation(scope: scope, intent: intent),
      status: OutboxEntryStatus.values.byName(row['status'] as String),
      sequence: (row['sequence'] as num).toInt(),
      attemptCount: (row['attemptCount'] as num? ?? 0).toInt(),
      lastFailureCode: row['lastFailureCode'] as String?,
      appliedRevision: row['appliedRevision'] as String?,
      rejectionCode: row['rejectionCode'] as String?,
    );
  }
}
