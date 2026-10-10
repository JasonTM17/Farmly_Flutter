import 'dart:convert';
import 'dart:io';

import 'package:drift/drift.dart';
import 'package:farmly_mobile/core/storage/encrypted_drift_executor.dart';
import 'package:farmly_mobile/core/storage/offline_key_store.dart';
import 'package:farmly_mobile/core/storage/secure_secret_store.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('native encrypted storage reopens, migrates, and fails closed', (
    tester,
  ) async {
    final support = await getApplicationSupportDirectory();
    final databaseFile = File(
      p.join(support.path, 'farmly-p02-storage-probe.db'),
    );
    const sidecarSuffixes = ['-wal', '-shm', '-journal'];
    final secrets = FlutterFarmlySecretStore();
    final keys = FarmlyOfflineKeyStore(secrets);
    final sessions = FarmlySessionTokenStore(secrets);

    if (await FarmlyEncryptedDriftExecutor.hasExistingDatabaseMaterial(
      databaseFile,
    )) {
      throw StateError(
        'Previous Farmly P02 probe data must be inspected first',
      );
    }

    final databaseKey = await keys.loadOrCreate(
      purpose: FarmlyOfflineKeyPurpose.localDatabase,
      hasExistingPayload: false,
    );
    final wrongKey = await keys.loadOrCreate(
      purpose: FarmlyOfflineKeyPurpose.outboxEnvelope,
      hasExistingPayload: false,
    );

    try {
      final first = _ProbeDatabaseV1(
        await const FarmlyEncryptedDriftExecutor().open(
          databaseFile: databaseFile,
          keyStore: keys,
        ),
      );
      await first.customStatement(
        "INSERT INTO farmly_probe (id, payload) VALUES (1, 'farmly_p02_sensitive_probe')",
      );
      await first.close();

      final encryptedBytes = await databaseFile.readAsBytes();
      final diskText = utf8.decode(encryptedBytes, allowMalformed: true);
      expect(diskText, isNot(contains('farmly_p02_sensitive_probe')));
      expect(diskText, isNot(startsWith('SQLite format 3')));

      final upgraded = _ProbeDatabaseV2(
        await const FarmlyEncryptedDriftExecutor().open(
          databaseFile: databaseFile,
          keyStore: keys,
        ),
      );
      final migratedRow = await upgraded
          .customSelect('SELECT payload, status FROM farmly_probe WHERE id = 1')
          .getSingle();
      expect(migratedRow.read<String>('payload'), 'farmly_p02_sensitive_probe');
      expect(migratedRow.read<String>('status'), 'pending');
      await upgraded.close();

      final beforeWrongKey = await databaseFile.readAsBytes();
      final wrong = _ProbeDatabaseV2(
        const FarmlyEncryptedDriftExecutor().openWithKey(
          databaseFile: databaseFile,
          key: wrongKey,
        ),
      );
      await expectLater(
        wrong.customSelect('SELECT payload FROM farmly_probe').get(),
        throwsA(anything),
      );
      await wrong.close();
      expect(await databaseFile.readAsBytes(), beforeWrongKey);

      await sessions.save('farmly-p02-synthetic-bearer-token');
      expect(await sessions.read(), 'farmly-p02-synthetic-bearer-token');
      await sessions.clear();
      expect(
        (await keys.loadOrCreate(
          purpose: FarmlyOfflineKeyPurpose.localDatabase,
          hasExistingPayload: true,
        )).encoded,
        databaseKey.encoded,
      );

      await keys.delete(FarmlyOfflineKeyPurpose.localDatabase);
      await expectLater(
        keys.loadOrCreate(
          purpose: FarmlyOfflineKeyPurpose.localDatabase,
          hasExistingPayload: true,
        ),
        throwsA(isA<FarmlyOfflineKeyUnavailable>()),
      );
      expect(await databaseFile.readAsBytes(), beforeWrongKey);
    } finally {
      await sessions.clear();
      await keys.delete(FarmlyOfflineKeyPurpose.localDatabase);
      await keys.delete(FarmlyOfflineKeyPurpose.outboxEnvelope);
      if (await databaseFile.exists()) await databaseFile.delete();
      for (final suffix in sidecarSuffixes) {
        final sidecar = File('${databaseFile.path}$suffix');
        if (await sidecar.exists()) await sidecar.delete();
      }
    }
  });
}

abstract class _ProbeDatabase extends GeneratedDatabase {
  _ProbeDatabase(super.executor);

  @override
  Iterable<TableInfo<Table, dynamic>> get allTables => const [];

  @override
  MigrationStrategy get migration => MigrationStrategy(
    onCreate: (_) async {
      await customStatement(
        'CREATE TABLE farmly_probe (id INTEGER PRIMARY KEY, payload TEXT NOT NULL)',
      );
    },
    onUpgrade: (_, from, to) async {
      if (from < 2 && to >= 2) {
        await customStatement(
          "ALTER TABLE farmly_probe ADD COLUMN status TEXT NOT NULL DEFAULT 'pending'",
        );
      }
    },
  );
}

final class _ProbeDatabaseV1 extends _ProbeDatabase {
  _ProbeDatabaseV1(super.executor);

  @override
  int get schemaVersion => 1;
}

final class _ProbeDatabaseV2 extends _ProbeDatabase {
  _ProbeDatabaseV2(super.executor);

  @override
  int get schemaVersion => 2;
}
