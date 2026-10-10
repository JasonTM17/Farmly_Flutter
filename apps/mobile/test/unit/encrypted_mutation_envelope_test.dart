import 'dart:convert';

import 'package:farmly_mobile/core/storage/encrypted_mutation_envelope.dart';
import 'package:farmly_mobile/core/storage/offline_key_store.dart';
import 'package:farmly_mobile/core/sync/farmly_mutation.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('FarmlyOutboxCipher', () {
    final key = FarmlyOfflineKey.fromEncoded(
      base64Url
          .encode(List<int>.generate(32, (index) => index))
          .replaceAll('=', ''),
    );
    final cipher = const FarmlyOutboxCipher();

    test(
      'round-trips the immutable mutation through a versioned envelope',
      () async {
        final mutation = _mutation();
        final envelope = await cipher.encrypt(mutation: mutation, key: key);
        final parsed = FarmlyEncryptedMutationEnvelope.fromJson(
          envelope.toJson(),
        );

        expect(parsed.version, FarmlyEncryptedMutationEnvelope.currentVersion);
        expect(
          parsed.algorithm,
          FarmlyEncryptedMutationEnvelope.currentAlgorithm,
        );
        expect(
          await cipher.decrypt(
            envelope: parsed,
            scope: mutation.scope,
            operationId: mutation.intent.operationId,
            key: key,
          ),
          jsonEncode(mutation.toRequestJson()),
        );
        expect(
          envelope.toJson().containsValue('Farmly offline payload'),
          isFalse,
        );
      },
    );

    test('uses a fresh nonce and authenticates the captured scope', () async {
      final mutation = _mutation();
      final first = await cipher.encrypt(mutation: mutation, key: key);
      final second = await cipher.encrypt(mutation: mutation, key: key);
      final otherScope = FarmlyMutationScope.organization(
        accountId: mutation.scope.accountId,
        organizationId: '66666666-6666-4666-8666-666666666666',
        continuityEpoch: mutation.scope.continuityEpoch,
      );

      expect(first.nonce, isNot(second.nonce));
      await expectLater(
        cipher.decrypt(
          envelope: first,
          scope: otherScope,
          operationId: mutation.intent.operationId,
          key: key,
        ),
        throwsA(isA<FarmlyMutationAuthenticationFailure>()),
      );
    });

    test('rejects tampered ciphertext authentication data', () async {
      final mutation = _mutation();
      final original = await cipher.encrypt(mutation: mutation, key: key);
      final tamperedJson = Map<String, Object>.from(original.toJson())
        ..['mac'] = base64Url
            .encode(List<int>.filled(16, 0))
            .replaceAll('=', '');
      final tampered = FarmlyEncryptedMutationEnvelope.fromJson(tamperedJson);

      await expectLater(
        cipher.decrypt(
          envelope: tampered,
          scope: mutation.scope,
          operationId: mutation.intent.operationId,
          key: key,
        ),
        throwsA(isA<FarmlyMutationAuthenticationFailure>()),
      );
    });

    test('rejects unsupported envelope versions and extra fields', () {
      final envelope = const FarmlyEncryptedMutationEnvelope(
        version: 1,
        algorithm: 'AES-256-GCM',
        nonce: 'AA',
        ciphertext: 'AA',
        mac: 'AA',
      );

      expect(
        () => FarmlyEncryptedMutationEnvelope.fromJson({
          ...envelope.toJson(),
          'version': 2,
        }),
        throwsFormatException,
      );
      expect(
        () => FarmlyEncryptedMutationEnvelope.fromJson({
          ...envelope.toJson(),
          'debug': 'must not be persisted',
        }),
        throwsFormatException,
      );
    });
  });
}

FarmlyScopedMutation _mutation() => FarmlyScopedMutation(
  scope: FarmlyMutationScope.organization(
    accountId: '11111111-1111-4111-8111-111111111111',
    organizationId: '22222222-2222-4222-8222-222222222222',
    continuityEpoch: 'epoch-7',
  ),
  intent: FarmlyCreateFarmIntent(
    operationId: '33333333-3333-4333-8333-333333333333',
    continuityEpoch: 'epoch-7',
    resourceId: '44444444-4444-4444-8444-444444444444',
    name: 'Farmly offline payload',
    timezone: 'Asia/Bangkok',
  ),
);
