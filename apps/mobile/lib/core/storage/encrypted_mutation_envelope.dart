import 'dart:convert';

import 'package:cryptography/cryptography.dart';

import '../sync/farmly_mutation.dart';
import 'offline_key_store.dart';

final class FarmlyEncryptedMutationEnvelope {
  const FarmlyEncryptedMutationEnvelope({
    required this.version,
    required this.algorithm,
    required this.nonce,
    required this.ciphertext,
    required this.mac,
  });

  static const currentVersion = 1;
  static const currentAlgorithm = 'AES-256-GCM';
  static const _keys = {'version', 'algorithm', 'nonce', 'ciphertext', 'mac'};

  final int version;
  final String algorithm;
  final String nonce;
  final String ciphertext;
  final String mac;

  Map<String, Object> toJson() => Map.unmodifiable({
    'version': version,
    'algorithm': algorithm,
    'nonce': nonce,
    'ciphertext': ciphertext,
    'mac': mac,
  });

  factory FarmlyEncryptedMutationEnvelope.fromJson(Object? value) {
    if (value is! Map) {
      throw const FormatException('Invalid Farmly envelope');
    }
    final map = Map<String, Object?>.from(value);
    if (map.keys.toSet().difference(_keys).isNotEmpty ||
        _keys.difference(map.keys.toSet()).isNotEmpty ||
        map['version'] != currentVersion ||
        map['algorithm'] != currentAlgorithm) {
      throw const FormatException('Invalid Farmly envelope');
    }

    final nonce = _decode(map['nonce']);
    final ciphertext = _decode(map['ciphertext']);
    final mac = _decode(map['mac']);
    if (nonce.length != 12 || mac.length != 16) {
      throw const FormatException('Invalid Farmly envelope');
    }
    return FarmlyEncryptedMutationEnvelope(
      version: currentVersion,
      algorithm: currentAlgorithm,
      nonce: base64Url.encode(nonce).replaceAll('=', ''),
      ciphertext: base64Url.encode(ciphertext).replaceAll('=', ''),
      mac: base64Url.encode(mac).replaceAll('=', ''),
    );
  }

  static List<int> _decode(Object? value) {
    if (value is! String) {
      throw const FormatException('Invalid Farmly envelope');
    }
    try {
      return base64Url.decode(base64Url.normalize(value));
    } on FormatException {
      throw const FormatException('Invalid Farmly envelope');
    }
  }
}

final class FarmlyMutationAuthenticationFailure implements Exception {
  const FarmlyMutationAuthenticationFailure();

  @override
  String toString() => 'Farmly mutation authentication failed';
}

final class FarmlyOutboxCipher {
  const FarmlyOutboxCipher();

  Future<FarmlyEncryptedMutationEnvelope> encrypt({
    required FarmlyScopedMutation mutation,
    required FarmlyOfflineKey key,
  }) async {
    final algorithm = AesGcm.with256bits();
    final secretBox = await algorithm.encrypt(
      utf8.encode(jsonEncode(mutation.toRequestJson())),
      secretKey: SecretKey(key.bytes),
      nonce: algorithm.newNonce(),
      aad: _associatedData(mutation.scope, mutation.intent.operationId),
    );
    return FarmlyEncryptedMutationEnvelope(
      version: FarmlyEncryptedMutationEnvelope.currentVersion,
      algorithm: FarmlyEncryptedMutationEnvelope.currentAlgorithm,
      nonce: base64Url.encode(secretBox.nonce).replaceAll('=', ''),
      ciphertext: base64Url.encode(secretBox.cipherText).replaceAll('=', ''),
      mac: base64Url.encode(secretBox.mac.bytes).replaceAll('=', ''),
    );
  }

  Future<String> decrypt({
    required FarmlyEncryptedMutationEnvelope envelope,
    required FarmlyMutationScope scope,
    required String operationId,
    required FarmlyOfflineKey key,
  }) async {
    if (!_isUuidV4(operationId)) {
      throw const FormatException('Invalid Farmly operation identity');
    }
    final validatedEnvelope = FarmlyEncryptedMutationEnvelope.fromJson(
      envelope.toJson(),
    );
    final secretBox = SecretBox(
      base64Url.decode(base64Url.normalize(validatedEnvelope.ciphertext)),
      nonce: base64Url.decode(base64Url.normalize(validatedEnvelope.nonce)),
      mac: Mac(base64Url.decode(base64Url.normalize(validatedEnvelope.mac))),
    );
    try {
      final cleartext = await AesGcm.with256bits().decrypt(
        secretBox,
        secretKey: SecretKey(key.bytes),
        aad: _associatedData(scope, operationId),
      );
      return utf8.decode(cleartext);
    } on Object {
      throw const FarmlyMutationAuthenticationFailure();
    }
  }

  List<int> _associatedData(FarmlyMutationScope scope, String operationId) =>
      utf8.encode(
        jsonEncode([
          'farmly.outbox.v1',
          scope.accountId.toLowerCase(),
          scope.organizationId.toLowerCase(),
          scope.farmId?.toLowerCase() ?? '',
          scope.kind == FarmlyMutationScopeKind.organization
              ? 'organization'
              : 'farm',
          scope.continuityEpoch,
          operationId.toLowerCase(),
        ]),
      );

  bool _isUuidV4(String value) => RegExp(
    r'^[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-4[0-9a-fA-F]{3}-[89abAB][0-9a-fA-F]{3}-[0-9a-fA-F]{12}$',
  ).hasMatch(value);
}
