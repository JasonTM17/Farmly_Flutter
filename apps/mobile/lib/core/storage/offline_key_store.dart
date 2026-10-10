import 'dart:async';
import 'dart:convert';

import 'package:cryptography/cryptography.dart';

import 'secure_secret_store.dart';

enum FarmlyOfflineKeyPurpose { localDatabase, outboxEnvelope }

final class FarmlyOfflineKey {
  FarmlyOfflineKey._(this.encoded);

  factory FarmlyOfflineKey.fromEncoded(String encoded) {
    try {
      final bytes = base64Url.decode(base64Url.normalize(encoded));
      if (bytes.length != 32) throw const FormatException();
      return FarmlyOfflineKey._(encoded);
    } on FormatException {
      throw const FarmlyOfflineKeyUnavailable();
    }
  }

  final String encoded;

  List<int> get bytes =>
      List.unmodifiable(base64Url.decode(base64Url.normalize(encoded)));
}

final class FarmlyOfflineKeyUnavailable implements Exception {
  const FarmlyOfflineKeyUnavailable();

  @override
  String toString() => 'Farmly offline key unavailable';
}

final class FarmlyOfflineKeyStore {
  FarmlyOfflineKeyStore(this._secrets);

  final FarmlySecretStore _secrets;
  final Map<FarmlyOfflineKeyPurpose, Completer<FarmlyOfflineKey>> _inFlight =
      {};

  Future<FarmlyOfflineKey> loadOrCreate({
    required FarmlyOfflineKeyPurpose purpose,
    required bool hasExistingPayload,
  }) {
    final pending = _inFlight[purpose];
    if (pending != null) return pending.future;

    final completer = Completer<FarmlyOfflineKey>();
    _inFlight[purpose] = completer;
    _loadOrCreate(purpose, hasExistingPayload).then(
      (key) {
        if (identical(_inFlight[purpose], completer)) {
          _inFlight.remove(purpose);
        }
        completer.complete(key);
      },
      onError: (Object error, StackTrace stackTrace) {
        if (identical(_inFlight[purpose], completer)) {
          _inFlight.remove(purpose);
        }
        completer.completeError(error, stackTrace);
      },
    );
    return completer.future;
  }

  Future<void> delete(FarmlyOfflineKeyPurpose purpose) =>
      _secrets.delete(_storageKey(purpose));

  Future<FarmlyOfflineKey> _loadOrCreate(
    FarmlyOfflineKeyPurpose purpose,
    bool hasExistingPayload,
  ) async {
    final storageKey = _storageKey(purpose);
    String? stored;
    try {
      stored = await _secrets.read(storageKey);
    } on Object {
      throw const FarmlyOfflineKeyUnavailable();
    }

    if (stored != null) return FarmlyOfflineKey.fromEncoded(stored);
    if (hasExistingPayload) throw const FarmlyOfflineKeyUnavailable();

    final generated = await AesGcm.with256bits().newSecretKey();
    final encoded = base64Url
        .encode(await generated.extractBytes())
        .replaceAll('=', '');
    try {
      await _secrets.write(storageKey, encoded);
      final persisted = await _secrets.read(storageKey);
      if (persisted != encoded) throw const FarmlyOfflineKeyUnavailable();
    } on Object {
      throw const FarmlyOfflineKeyUnavailable();
    }
    return FarmlyOfflineKey.fromEncoded(encoded);
  }

  String _storageKey(FarmlyOfflineKeyPurpose purpose) => switch (purpose) {
    FarmlyOfflineKeyPurpose.localDatabase => 'farmly.offline.database-key.v1',
    FarmlyOfflineKeyPurpose.outboxEnvelope => 'farmly.offline.outbox-key.v1',
  };
}
