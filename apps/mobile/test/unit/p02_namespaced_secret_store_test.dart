import 'package:farmly_mobile/core/storage/secure_secret_store.dart';
import 'package:flutter_test/flutter_test.dart';

import '../support/p02_namespaced_secret_store.dart';

void main() {
  test(
    'probe writes and cleanup cannot change production credential keys',
    () async {
      final backing = _MemorySecretStore()
        ..values['farmly.auth.session.v1'] = 'existing-session'
        ..values['farmly.offline.database-key.v1'] = 'existing-key';
      final probe = P02ProbeSecretStore(backing);

      await probe.write('farmly.auth.session.v1', 'probe-session');
      await probe.delete('farmly.auth.session.v1');

      expect(backing.values['farmly.auth.session.v1'], 'existing-session');
      expect(backing.values['farmly.offline.database-key.v1'], 'existing-key');
      expect(backing.values, {
        'farmly.auth.session.v1': 'existing-session',
        'farmly.offline.database-key.v1': 'existing-key',
      });
    },
  );

  test('probe rejects keys outside its Farmly-owned key space', () async {
    final probe = P02ProbeSecretStore(_MemorySecretStore());

    expect(
      () => probe.delete('unrelated.application.key'),
      throwsArgumentError,
    );
  });
}

final class _MemorySecretStore implements FarmlySecretStore {
  final Map<String, String> values = {};

  @override
  Future<String?> read(String key) async => values[key];

  @override
  Future<void> write(String key, String value) async {
    values[key] = value;
  }

  @override
  Future<void> delete(String key) async {
    values.remove(key);
  }
}
