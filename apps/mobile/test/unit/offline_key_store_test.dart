import 'dart:convert';

import 'package:farmly_mobile/core/storage/offline_key_store.dart';
import 'package:farmly_mobile/core/storage/secure_secret_store.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('FarmlyOfflineKeyStore', () {
    test(
      'creates a 256-bit key once and reads it back from secure storage',
      () async {
        final secrets = _MemorySecretStore();
        final store = FarmlyOfflineKeyStore(secrets);

        final first = await store.loadOrCreate(
          purpose: FarmlyOfflineKeyPurpose.outboxEnvelope,
          hasExistingPayload: false,
        );
        final second = await store.loadOrCreate(
          purpose: FarmlyOfflineKeyPurpose.outboxEnvelope,
          hasExistingPayload: true,
        );

        expect(
          base64Url.decode(base64Url.normalize(first.encoded)),
          hasLength(32),
        );
        expect(second.encoded, first.encoded);
        expect(secrets.writeCount, 1);
      },
    );

    test('refuses to recreate a missing key when stored data exists', () async {
      final secrets = _MemorySecretStore();
      final store = FarmlyOfflineKeyStore(secrets);

      await expectLater(
        store.loadOrCreate(
          purpose: FarmlyOfflineKeyPurpose.localDatabase,
          hasExistingPayload: true,
        ),
        throwsA(isA<FarmlyOfflineKeyUnavailable>()),
      );
      expect(secrets.values, isEmpty);
      expect(secrets.writeCount, 0);
    });

    test('rejects corrupt stored key material without replacing it', () async {
      final secrets = _MemorySecretStore()
        ..values['farmly.offline.database-key.v1'] = 'corrupt-key-material';
      final store = FarmlyOfflineKeyStore(secrets);

      await expectLater(
        store.loadOrCreate(
          purpose: FarmlyOfflineKeyPurpose.localDatabase,
          hasExistingPayload: true,
        ),
        throwsA(isA<FarmlyOfflineKeyUnavailable>()),
      );
      expect(
        secrets.values['farmly.offline.database-key.v1'],
        'corrupt-key-material',
      );
      expect(secrets.writeCount, 0);
    });

    test('coalesces concurrent first opens to one secure key', () async {
      final secrets = _MemorySecretStore(delayReads: true);
      final store = FarmlyOfflineKeyStore(secrets);
      final results = await Future.wait([
        store.loadOrCreate(
          purpose: FarmlyOfflineKeyPurpose.localDatabase,
          hasExistingPayload: false,
        ),
        store.loadOrCreate(
          purpose: FarmlyOfflineKeyPurpose.localDatabase,
          hasExistingPayload: false,
        ),
      ]);

      expect(results.first.encoded, results.last.encoded);
      expect(secrets.writeCount, 1);
    });
  });
}

final class _MemorySecretStore implements FarmlySecretStore {
  _MemorySecretStore({this.delayReads = false});

  final bool delayReads;
  final Map<String, String> values = {};
  int writeCount = 0;

  @override
  Future<String?> read(String key) async {
    if (delayReads) await Future<void>.delayed(Duration.zero);
    return values[key];
  }

  @override
  Future<void> write(String key, String value) async {
    writeCount++;
    values[key] = value;
  }

  @override
  Future<void> delete(String key) async => values.remove(key);
}
