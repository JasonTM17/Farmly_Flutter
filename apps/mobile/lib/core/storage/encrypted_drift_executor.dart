import 'dart:io';

import 'package:drift/native.dart';
import 'package:drift/drift.dart' show QueryExecutor;

import 'offline_key_store.dart';

final class FarmlyEncryptedDatabaseUnavailable implements Exception {
  const FarmlyEncryptedDatabaseUnavailable();

  @override
  String toString() => 'Farmly encrypted database unavailable';
}

final class FarmlyEncryptedDriftExecutor {
  const FarmlyEncryptedDriftExecutor();

  Future<QueryExecutor> open({
    required File databaseFile,
    required FarmlyOfflineKeyStore keyStore,
  }) async {
    final key = await keyStore.loadOrCreate(
      purpose: FarmlyOfflineKeyPurpose.localDatabase,
      hasExistingPayload: await hasExistingDatabaseMaterial(databaseFile),
    );
    return openWithKey(databaseFile: databaseFile, key: key);
  }

  static Future<bool> hasExistingDatabaseMaterial(File databaseFile) async {
    for (final path in [
      databaseFile.path,
      '${databaseFile.path}-wal',
      '${databaseFile.path}-shm',
      '${databaseFile.path}-journal',
    ]) {
      if (await File(path).exists()) return true;
    }
    return false;
  }

  QueryExecutor openWithKey({
    required File databaseFile,
    required FarmlyOfflineKey key,
  }) {
    final phrase = key.encoded.replaceAll("'", "''");
    return NativeDatabase.createInBackground(
      databaseFile,
      setup: (database) {
        database.execute("PRAGMA cipher = 'chacha20';");
        final selectedCipher = database.select('PRAGMA cipher;');
        if (selectedCipher.isEmpty ||
            selectedCipher.first.values.single.toString() != 'chacha20') {
          throw const FarmlyEncryptedDatabaseUnavailable();
        }
        database.execute("PRAGMA key = '$phrase';");
      },
    );
  }
}
