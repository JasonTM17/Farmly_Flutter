import 'package:flutter_secure_storage/flutter_secure_storage.dart';

abstract interface class FarmlySecretStore {
  Future<String?> read(String key);

  Future<void> write(String key, String value);

  Future<void> delete(String key);
}

final class FlutterFarmlySecretStore implements FarmlySecretStore {
  FlutterFarmlySecretStore({FlutterSecureStorage? storage})
    : _storage = storage ?? const FlutterSecureStorage();

  final FlutterSecureStorage _storage;

  @override
  Future<String?> read(String key) => _storage.read(key: key);

  @override
  Future<void> write(String key, String value) =>
      _storage.write(key: key, value: value);

  @override
  Future<void> delete(String key) => _storage.delete(key: key);
}

final class FarmlySessionTokenStore {
  FarmlySessionTokenStore(this._secrets);

  static const _storageKey = 'farmly.auth.session.v1';

  final FarmlySecretStore _secrets;

  Future<String?> read() => _secrets.read(_storageKey);

  Future<void> save(String token) {
    if (token.isEmpty ||
        token.trim() != token ||
        token.contains(RegExp(r'\s'))) {
      throw ArgumentError('Bearer token must be a non-empty value');
    }
    return _secrets.write(_storageKey, token);
  }

  Future<void> clear() => _secrets.delete(_storageKey);
}
