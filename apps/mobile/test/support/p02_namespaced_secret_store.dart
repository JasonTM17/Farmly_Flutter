import 'package:farmly_mobile/core/storage/secure_secret_store.dart';

/// Keeps the destructive native-storage probe away from application secrets.
final class P02ProbeSecretStore implements FarmlySecretStore {
  P02ProbeSecretStore(this._delegate);

  static const storagePrefix = 'farmly.p02-probe.v1.';

  final FarmlySecretStore _delegate;

  String _namespaced(String key) {
    if (!key.startsWith('farmly.')) {
      throw ArgumentError.value(key, 'key', 'Expected a Farmly storage key');
    }
    return '$storagePrefix$key';
  }

  @override
  Future<String?> read(String key) => _delegate.read(_namespaced(key));

  @override
  Future<void> write(String key, String value) =>
      _delegate.write(_namespaced(key), value);

  @override
  Future<void> delete(String key) => _delegate.delete(_namespaced(key));
}
