import 'dart:convert';
import 'dart:io';

import 'package:cryptography/cryptography.dart';
import 'package:flutter/foundation.dart';

import '../storage/offline_key_store.dart';
import 'sync_models.dart';

/// Where the engine pins a scope's position in the server change feed.
final class SyncCursorState {
  const SyncCursorState({
    required this.cursor,
    required this.highWatermark,
    required this.continuityEpoch,
    required this.scopePolicyVersion,
  });

  final String cursor;
  final String highWatermark;
  final String continuityEpoch;
  final String scopePolicyVersion;
}

/// Thrown when the feed carries a change kind the client cannot apply. The
/// engine must stop at that revision honestly rather than skip or guess
/// (spec04 §7 — forward compatibility is explicit, never silent).
final class UnsupportedChangeError implements Exception {
  const UnsupportedChangeError(this.change);

  final String change;

  @override
  String toString() => 'Unsupported Farmly change kind: $change';
}

/// Projection of server truth for one scope, plus the feed cursor that
/// positions it. Implementations must keep records + cursor writes atomic
/// with each other so a kill mid-feed never yields a cursor ahead of data.
abstract interface class LocalDomainStore {
  /// Install a full bootstrap: replace every record in the scope and pin the
  /// manifest's change cursor — one atomic commit.
  Future<void> installBootstrap({
    required String scopeKey,
    required List<BootstrapBlock> blocks,
    required SyncCursorState cursor,
  });

  /// Apply one committed change set and advance the cursor atomically.
  Future<void> applyChangeSet({
    required String scopeKey,
    required SyncChangeSet changeSet,
    required SyncCursorState cursor,
  });

  /// Read the authenticated domain projection and its cursor as one snapshot.
  /// `null` means this scope has not completed a bootstrap yet; a non-null
  /// snapshot with no records for an entity is a confirmed empty result.
  Future<LocalDomainSnapshot?> snapshotFor(String scopeKey);

  Future<SyncCursorState?> cursorFor(String scopeKey);

  /// Wipe scope records and cursor (revocation/reset path — caller-owned).
  Future<void> clearScope(String scopeKey);
}

/// One complete, immutable local projection for a scope. Cursor metadata is
/// kept beside its records so consumers can reject stale policy/epoch data.
final class LocalDomainSnapshot {
  LocalDomainSnapshot({
    required this.cursor,
    required Map<String, Map<String, Object?>> records,
  }) : records = _freezeEntityRecords(records);

  final SyncCursorState cursor;
  final Map<String, Map<String, Object?>> records;

  Map<String, Object?> recordsFor(String entity) =>
      records[entity] ?? const <String, Object?>{};
}

Map<String, Map<String, Object?>> _freezeEntityRecords(
  Map<String, Map<String, Object?>> records,
) => Map.unmodifiable({
  for (final entity in records.entries)
    entity.key: Map<String, Object?>.unmodifiable({
      for (final row in entity.value.entries)
        row.key: _freezeJsonValue(row.value),
    }),
});

Object? _freezeJsonValue(Object? value) {
  if (value is Map) {
    final frozen = <String, Object?>{};
    for (final entry in value.entries) {
      if (entry.key is! String) {
        throw const FarmlyDomainStoreAuthenticationFailure();
      }
      frozen[entry.key as String] = _freezeJsonValue(entry.value);
    }
    return Map<String, Object?>.unmodifiable(frozen);
  }
  if (value is List) {
    return List<Object?>.unmodifiable(value.map(_freezeJsonValue));
  }
  return value;
}

/// In-memory reference implementation; also the deterministic test double.
final class InMemoryDomainStore implements LocalDomainStore {
  /// scopeKey -> entity -> recordId -> record
  final Map<String, Map<String, Map<String, Map<String, Object?>>>> _records =
      {};
  final Map<String, SyncCursorState> _cursors = {};

  Map<String, Map<String, Object?>> recordsOf(String scopeKey, String entity) =>
      Map.unmodifiable(_records[scopeKey]?[entity] ?? const {});

  int get recordCount => _records.values.fold(
    0,
    (sum, entities) =>
        sum + entities.values.fold(0, (s, rows) => s + rows.length),
  );

  @override
  Future<void> installBootstrap({
    required String scopeKey,
    required List<BootstrapBlock> blocks,
    required SyncCursorState cursor,
  }) async {
    final entities = <String, Map<String, Map<String, Object?>>>{};
    for (final block in blocks) {
      final table = entities.putIfAbsent(block.entity, () => {});
      for (final record in block.records) {
        final id = _recordKey(block.entity, record);
        table[id] = Map.unmodifiable(record);
      }
    }
    _records[scopeKey] = entities;
    _cursors[scopeKey] = cursor;
  }

  @override
  Future<void> applyChangeSet({
    required String scopeKey,
    required SyncChangeSet changeSet,
    required SyncCursorState cursor,
  }) async {
    final entities = _records.putIfAbsent(scopeKey, () => {});
    for (final change in changeSet.changes) {
      switch (change.change) {
        case 'upsert':
          final table = entities.putIfAbsent(change.entity, () => {});
          table[_recordKey(change.entity, change.record)] = Map.unmodifiable(
            change.record,
          );
        default:
          throw UnsupportedChangeError(change.change);
      }
    }
    _cursors[scopeKey] = cursor;
  }

  @override
  Future<SyncCursorState?> cursorFor(String scopeKey) async =>
      _cursors[scopeKey];

  @override
  Future<LocalDomainSnapshot?> snapshotFor(String scopeKey) async {
    final cursor = _cursors[scopeKey];
    if (cursor == null) return null;
    final entities = _records[scopeKey] ?? const {};
    return LocalDomainSnapshot(
      cursor: cursor,
      records: {
        for (final entity in entities.entries)
          entity.key: {
            for (final row in entity.value.entries) row.key: row.value,
          },
      },
    );
  }

  @override
  Future<void> clearScope(String scopeKey) async {
    _records.remove(scopeKey);
    _cursors.remove(scopeKey);
  }

  /// Entity wire names use the resource id (`id`), except `farm` which is
  /// keyed by `farmId` — matching the kernel view contracts exactly.
  static String _recordKey(String entity, Map<String, Object?> record) {
    final key = entity == 'farm' ? 'farmId' : 'id';
    final value = record[key];
    if (value is! String || value.isEmpty) {
      throw FormatException('Farmly $entity record is missing its $key');
    }
    return value;
  }
}

/// Thrown when a persisted domain projection fails envelope authentication.
/// No silent wipe — the caller decides between re-bootstrap and error surfacing
/// (a stale/wrong key must never rebind data to another scope).
final class FarmlyDomainStoreAuthenticationFailure implements Exception {
  const FarmlyDomainStoreAuthenticationFailure();

  @override
  String toString() => 'Farmly domain projection authentication failed';
}

/// Encrypted file-backed [LocalDomainStore]: one JSON document at
/// `farmly-domain.v1.json` whose per-scope payloads are AES-256-GCM ciphertext
/// bound by AAD to `farmly.domain.v1` + the scope key. The whole file rewrites
/// atomically (write-then-rename) so a kill mid-feed cannot corrupt the prior
/// committed state — the cursor can never run ahead of its records.
final class EncryptedFileDomainStore implements LocalDomainStore {
  EncryptedFileDomainStore({required Directory directory, required this._key})
    : _file = File('${directory.path}/farmly-domain.v1.json');

  static final AesGcm _algorithm = AesGcm.with256bits();

  final File _file;
  final FarmlyOfflineKey _key;

  /// scopeKey -> {cursor: {...}, records: {entity: {id: record}}}
  final Map<String, Map<String, Object?>> _scopes = {};
  bool _loaded = false;

  @visibleForTesting
  Map<String, Map<String, Object?>> recordsOf(String scopeKey, String entity) {
    final scope = _scopes[scopeKey];
    final records = scope?['records'];
    if (records is! Map) return const {};
    final table = records[entity];
    if (table is! Map) return const {};
    return {
      for (final entry in table.entries)
        entry.key as String: Map<String, Object?>.from(entry.value as Map),
    };
  }

  Future<void> _ensureLoaded() async {
    if (_loaded) return;
    if (!await _file.exists()) {
      _loaded = true;
      return;
    }
    final raw = await _file.readAsString();
    final document = jsonDecode(raw);
    if (document is! Map || document['version'] != 1) {
      throw const FarmlyDomainStoreAuthenticationFailure();
    }
    final scopes = document['scopes'];
    if (scopes is! Map) {
      throw const FarmlyDomainStoreAuthenticationFailure();
    }
    for (final entry in scopes.entries) {
      final scopeKey = entry.key as String;
      final payload = await _decryptScope(scopeKey, entry.value);
      _scopes[scopeKey] = payload;
    }
    // A failed read/decrypt must remain a failure on every later access. If
    // this latch is set before the full document is authenticated, a retry
    // could mistake an unreadable cache for an unbootstrapped empty scope.
    _loaded = true;
  }

  Future<Map<String, Object?>> _decryptScope(
    String scopeKey,
    Object? envelope,
  ) async {
    if (envelope is! Map) {
      throw const FarmlyDomainStoreAuthenticationFailure();
    }
    final nonce = base64Url.decode(envelope['nonce'] as String);
    final ciphertext = base64Url.decode(envelope['ciphertext'] as String);
    final mac = Mac(base64Url.decode(envelope['mac'] as String));
    try {
      final plain = await _algorithm.decrypt(
        SecretBox(ciphertext, nonce: nonce, mac: mac),
        secretKey: SecretKey(_key.bytes),
        aad: utf8.encode('farmly.domain.v1|$scopeKey'),
      );
      final decoded = jsonDecode(utf8.decode(plain));
      if (decoded is! Map) {
        throw const FarmlyDomainStoreAuthenticationFailure();
      }
      return Map<String, Object?>.from(decoded);
    } on FormatException {
      throw const FarmlyDomainStoreAuthenticationFailure();
    } on SecretBoxAuthenticationError {
      throw const FarmlyDomainStoreAuthenticationFailure();
    }
  }

  Future<void> _persist() async {
    final scopes = <String, Object?>{};
    for (final entry in _scopes.entries) {
      final plain = utf8.encode(jsonEncode(entry.value));
      final box = await _algorithm.encrypt(
        plain,
        secretKey: SecretKey(_key.bytes),
        aad: utf8.encode('farmly.domain.v1|${entry.key}'),
      );
      scopes[entry.key] = {
        'nonce': base64Url.encode(box.nonce),
        'ciphertext': base64Url.encode(box.cipherText),
        'mac': base64Url.encode(box.mac.bytes),
      };
    }
    final document = jsonEncode({'version': 1, 'scopes': scopes});
    await _file.parent.create(recursive: true);
    final temporary = File('${_file.path}.tmp');
    await temporary.writeAsString(document, flush: true);
    await temporary.rename(_file.path);
  }

  Map<String, Map<String, Map<String, Object?>>> _entitiesOf(String scopeKey) {
    final scope = _scopes.putIfAbsent(
      scopeKey,
      () => <String, Object?>{'records': <String, Object?>{}},
    );
    final records = scope['records'] as Map<String, Object?>;
    return records.map(
      (entity, table) => MapEntry(
        entity,
        (table as Map).map(
          (id, record) =>
              MapEntry(id as String, Map<String, Object?>.from(record as Map)),
        ),
      ),
    );
  }

  void _writeEntities(
    String scopeKey,
    Map<String, Map<String, Map<String, Object?>>> entities,
  ) {
    _scopes[scopeKey] = {
      ...?_scopes[scopeKey],
      'records': {
        for (final entity in entities.entries)
          entity.key: {
            for (final row in entity.value.entries) row.key: row.value,
          },
      },
    };
  }

  @override
  Future<void> installBootstrap({
    required String scopeKey,
    required List<BootstrapBlock> blocks,
    required SyncCursorState cursor,
  }) async {
    await _ensureLoaded();
    final entities = <String, Map<String, Map<String, Object?>>>{};
    for (final block in blocks) {
      final table = entities.putIfAbsent(block.entity, () => {});
      for (final record in block.records) {
        table[InMemoryDomainStore._recordKey(block.entity, record)] = record;
      }
    }
    _writeEntities(scopeKey, entities);
    _scopes[scopeKey]!['cursor'] = _cursorJson(cursor);
    await _persist();
  }

  @override
  Future<void> applyChangeSet({
    required String scopeKey,
    required SyncChangeSet changeSet,
    required SyncCursorState cursor,
  }) async {
    await _ensureLoaded();
    final entities = _entitiesOf(scopeKey);
    for (final change in changeSet.changes) {
      switch (change.change) {
        case 'upsert':
          final table = entities.putIfAbsent(change.entity, () => {});
          table[InMemoryDomainStore._recordKey(change.entity, change.record)] =
              change.record;
        default:
          throw UnsupportedChangeError(change.change);
      }
    }
    _writeEntities(scopeKey, entities);
    _scopes[scopeKey]!['cursor'] = _cursorJson(cursor);
    await _persist();
  }

  @override
  Future<SyncCursorState?> cursorFor(String scopeKey) async {
    await _ensureLoaded();
    final cursor = _scopes[scopeKey]?['cursor'];
    if (cursor == null) return null;
    return _cursorFromJson(cursor);
  }

  @override
  Future<LocalDomainSnapshot?> snapshotFor(String scopeKey) async {
    await _ensureLoaded();
    final scope = _scopes[scopeKey];
    final rawCursor = scope?['cursor'];
    if (rawCursor == null) return null;
    final rawRecords = scope?['records'];
    if (rawRecords is! Map) {
      throw const FarmlyDomainStoreAuthenticationFailure();
    }
    final records = <String, Map<String, Object?>>{};
    for (final entity in rawRecords.entries) {
      if (entity.key is! String || entity.value is! Map) {
        throw const FarmlyDomainStoreAuthenticationFailure();
      }
      final table = <String, Object?>{};
      for (final row in (entity.value as Map).entries) {
        if (row.key is! String || row.value is! Map) {
          throw const FarmlyDomainStoreAuthenticationFailure();
        }
        table[row.key as String] = Map<String, Object?>.from(row.value as Map);
      }
      records[entity.key as String] = table;
    }
    return LocalDomainSnapshot(
      cursor: _cursorFromJson(rawCursor),
      records: records,
    );
  }

  @override
  Future<void> clearScope(String scopeKey) async {
    await _ensureLoaded();
    if (_scopes.remove(scopeKey) != null) await _persist();
  }

  static Map<String, Object?> _cursorJson(SyncCursorState cursor) => {
    'cursor': cursor.cursor,
    'highWatermark': cursor.highWatermark,
    'continuityEpoch': cursor.continuityEpoch,
    'scopePolicyVersion': cursor.scopePolicyVersion,
  };

  static SyncCursorState _cursorFromJson(Object? value) {
    if (value is! Map ||
        value['cursor'] is! String ||
        value['highWatermark'] is! String ||
        value['continuityEpoch'] is! String ||
        value['scopePolicyVersion'] is! String) {
      throw const FarmlyDomainStoreAuthenticationFailure();
    }
    return SyncCursorState(
      cursor: value['cursor'] as String,
      highWatermark: value['highWatermark'] as String,
      continuityEpoch: value['continuityEpoch'] as String,
      scopePolicyVersion: value['scopePolicyVersion'] as String,
    );
  }
}
