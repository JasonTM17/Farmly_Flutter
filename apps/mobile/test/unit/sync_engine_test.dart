import 'dart:convert';
import 'dart:io';

import 'package:farmly_mobile/core/network/farmly_api_client.dart';
import 'package:farmly_mobile/core/storage/encrypted_mutation_envelope.dart';
import 'package:farmly_mobile/core/storage/offline_key_store.dart';
import 'package:farmly_mobile/core/sync/farmly_mutation.dart';
import 'package:farmly_mobile/core/sync/local_domain_store.dart';
import 'package:farmly_mobile/core/sync/outbox_store.dart';
import 'package:farmly_mobile/core/sync/sync_engine.dart';
import 'package:farmly_mobile/core/sync/sync_models.dart';
import 'package:farmly_mobile/core/sync/sync_transport.dart';
import 'package:farmly_mobile/generated/farmly_api_types.dart';
import 'package:flutter_test/flutter_test.dart';

const accountId = '00000000-0000-4000-8000-000000000001';
const organizationId = '00000000-0000-4000-8000-000000000002';
const farmId = '00000000-0000-4000-8000-000000000003';
const epoch = '1';
const plantingId = '00000000-0000-4000-8000-000000000301';

FarmlyMutationScope get scope => FarmlyMutationScope.farm(
      accountId: accountId,
      organizationId: organizationId,
      farmId: farmId,
      continuityEpoch: epoch,
    );

FarmlyScopedMutation harvest(
  String operationId, {
  String resourceId = '00000000-0000-4000-8000-000000000201',
  List<String> dependsOn = const [],
}) =>
    FarmlyScopedMutation(
      scope: scope,
      intent: FarmlyCreateHarvestIntent(
        operationId: operationId,
        continuityEpoch: epoch,
        resourceId: resourceId,
        plantingId: plantingId,
        quantityKg: FarmlyDecimal.parse('10'),
        harvestDate: '2026-10-09',
        dependsOn: dependsOn,
      ),
    );

/// Scripted transport: each call consumes the next queued response or throws.
final class FakeTransport implements SyncTransport {
  final List<Object> submittedOps = [];
  final List<List<String>> submittedIds = [];
  final List<String> statusQueries = [];
  int bootstrapCalls = 0;

  Object? nextSubmit; // MutationBatchResult or Exception
  Object? nextStatus; // List<OperationStatusEntry> or Exception
  Object? nextChanges; // ChangeFeedPage or Exception
  BootstrapManifest? manifest;
  List<BootstrapBlock> bootstrapBlocks = const [];

  @override
  Future<MutationBatchResult> submitMutations({
    required FarmlyMutationScope scope,
    required List<FarmlyMutationIntent> operations,
  }) async {
    submittedOps.addAll(operations);
    submittedIds.add([for (final op in operations) op.operationId]);
    final scripted = nextSubmit;
    nextSubmit = null;
    if (scripted is Exception) throw scripted;
    return scripted as MutationBatchResult? ??
        MutationBatchResult(
          outcomes: [
            for (final op in operations)
              MutationOutcome(operationId: op.operationId, outcome: 'applied', revision: '2'),
          ],
          asOf: '2026-10-09T10:00:00Z',
          scopePolicyVersion: '1',
        );
  }

  @override
  Future<List<OperationStatusEntry>> operationStatus({
    required String accountId,
    required List<String> operationIds,
  }) async {
    statusQueries.addAll(operationIds);
    final scripted = nextStatus;
    nextStatus = null;
    if (scripted is Exception) throw scripted;
    return (scripted as List<OperationStatusEntry>?) ?? const [];
  }

  @override
  Future<ChangeFeedPage> fetchChanges({
    required FarmlyMutationScope scope,
    required String cursor,
  }) async {
    final scripted = nextChanges;
    nextChanges = null;
    if (scripted is Exception) throw scripted;
    return scripted as ChangeFeedPage? ??
        ChangeFeedPage(
          changeSets: const [],
          highWatermark: '1',
          hasMore: false,
          nextCursor: cursor,
        );
  }

  @override
  Future<BootstrapManifest> createBootstrap({
    required FarmlyMutationScope scope,
    required String operationId,
  }) async {
    bootstrapCalls++;
    return manifest ??
        BootstrapManifest(
          snapshotId: operationId,
          expiresAt: '2026-10-09T11:00:00Z',
          continuityEpoch: epoch,
          scopePolicyVersion: '1',
          highWatermark: '1',
          prunedThroughRevision: '0',
          totalRows: bootstrapBlocks.fold(0, (s, b) => s + b.records.length),
          byteCount: 128,
          chunkCount: 1,
          changesCursor: 'cursor@1',
        );
  }

  @override
  Future<BootstrapPage> fetchBootstrapPage({
    required FarmlyMutationScope scope,
    required String snapshotId,
    String? pageCursor,
  }) async {
    return BootstrapPage(
      snapshotId: snapshotId,
      pageIndex: 1,
      rowCount: bootstrapBlocks.fold(0, (s, b) => s + b.records.length),
      blocks: bootstrapBlocks,
      hasMore: false,
      nextPageCursor: null,
      chunkCount: 1,
    );
  }
}

void main() {
  late FakeTransport transport;
  late InMemoryOutboxStore outbox;
  late InMemoryDomainStore domain;
  var opSeq = 0;
  String nextOp() => '00000000-0000-4000-8000-${(opSeq++).toString().padLeft(12, '0')}';
  late FarmlySyncEngine engine;

  setUp(() {
    opSeq = 0;
    transport = FakeTransport();
    outbox = InMemoryOutboxStore();
    domain = InMemoryDomainStore();
    engine = FarmlySyncEngine(
      outbox: outbox,
      transport: transport,
      domain: domain,
      operationIdGenerator: nextOp,
    );
  });

  group('outbox flush', () {
    test('applied outcome retires the entry with its server revision', () async {
      final op = nextOp();
      await engine.enqueue(harvest(op));
      final report = await engine.synchronize(scope);
      expect(report.sent, 1);
      expect(report.applied, 1);
      expect(transport.submittedIds.single, [op]);
      final entry = await outbox.find(
        accountId: accountId,
        organizationId: organizationId,
        operationId: op,
      );
      expect(entry!.status, OutboxEntryStatus.applied);
      expect(entry.appliedRevision, '2');
    });

    test('rejected outcome is terminal and carries the code', () async {
      final op = nextOp();
      await engine.enqueue(harvest(op));
      transport.nextSubmit = MutationBatchResult(
        outcomes: [
          MutationOutcome(operationId: op, outcome: 'rejected', code: 'DOMAIN_RULE'),
        ],
        asOf: null,
        scopePolicyVersion: '1',
      );
      final report = await engine.synchronize(scope);
      expect(report.rejected, 1);
      final entry = await outbox.find(
        accountId: accountId,
        organizationId: organizationId,
        operationId: op,
      );
      expect(entry!.status, OutboxEntryStatus.rejected);
      expect(entry.rejectionCode, 'DOMAIN_RULE');
      // Terminal — a later pass never resends it.
      await engine.synchronize(scope);
      expect(transport.submittedIds, hasLength(1));
    });

    test('conflict parks a SyncConflict and retires nothing', () async {
      final op = nextOp();
      await engine.enqueue(harvest(op));
      transport.nextSubmit = MutationBatchResult(
        outcomes: [MutationOutcome(operationId: op, outcome: 'conflict', code: 'VERSION_CONFLICT')],
        asOf: '2026-10-09T10:05:00Z',
        scopePolicyVersion: '1',
      );
      final report = await engine.synchronize(scope);
      expect(report.conflicted, 1);
      expect(engine.conflicts, hasLength(1));
      expect(engine.conflicts.single.entry.operationId, op);
      // Original bytes remain immutable evidence.
      expect(
        engine.conflicts.single.entry.mutation.intent.payload['quantityKg'],
        '10',
      );
    });

    test('dependency gate: child waits for parent, blocks on rejection', () async {
      final parent = nextOp();
      final child = nextOp();
      await engine.enqueue(harvest(parent));
      await engine.enqueue(harvest(child, dependsOn: [parent], resourceId: '00000000-0000-4000-8000-000000000202'));
      transport.nextSubmit = MutationBatchResult(
        outcomes: [MutationOutcome(operationId: parent, outcome: 'rejected', code: 'X')],
        asOf: null,
        scopePolicyVersion: '1',
      );
      final report = await engine.synchronize(scope);
      // Only the parent was sent; child stayed queued.
      expect(transport.submittedIds.single, [parent]);
      expect(report.blocked, 1);
      final childEntry = await outbox.find(
        accountId: accountId,
        organizationId: organizationId,
        operationId: child,
      );
      expect(childEntry!.status, OutboxEntryStatus.blocked);
    });
  });

  group('lost-ACK reconciliation (S-05/S-06)', () {
    test('transport failure mid-flight reconciles via operation status', () async {
      final op = nextOp();
      await engine.enqueue(harvest(op));
      transport.nextSubmit = const FarmlyApiFailure(FarmlyApiFailureCode.unavailable);
      transport.nextStatus = [
        OperationStatusEntry(operationId: op, proof: OperationProof.applied),
      ];
      final report = await engine.synchronize(scope);
      expect(report.reconciled, 1);
      final entry = await outbox.find(
        accountId: accountId,
        organizationId: organizationId,
        operationId: op,
      );
      expect(entry!.status, OutboxEntryStatus.applied);
      expect(transport.statusQueries, [op]);
    });

    test('unknown proof returns the entry to pending — never notApplied', () async {
      final op = nextOp();
      await engine.enqueue(harvest(op));
      transport.nextSubmit = const FarmlyApiFailure(FarmlyApiFailureCode.unavailable);
      transport.nextStatus = [
        OperationStatusEntry(operationId: op, proof: OperationProof.unknown),
      ];
      await engine.synchronize(scope);
      final entry = await outbox.find(
        accountId: accountId,
        organizationId: organizationId,
        operationId: op,
      );
      expect(entry!.status, OutboxEntryStatus.pending);
    });

    test('unreachable ledger keeps in-flight honestly', () async {
      final op = nextOp();
      await engine.enqueue(harvest(op));
      transport.nextSubmit = const FarmlyApiFailure(FarmlyApiFailureCode.unavailable);
      transport.nextStatus = const FarmlyApiFailure(FarmlyApiFailureCode.unavailable);
      await engine.synchronize(scope);
      final entry = await outbox.find(
        accountId: accountId,
        organizationId: organizationId,
        operationId: op,
      );
      expect(entry!.status, OutboxEntryStatus.inFlight);
    });
  });

  group('change feed', () {
    test('applies committed sets and advances the cursor', () async {
      await domain.installBootstrap(
        scopeKey: '$accountId|$organizationId|$farmId',
        blocks: const [],
        cursor: const SyncCursorState(
          cursor: 'cursor@1',
          highWatermark: '1',
          continuityEpoch: epoch,
          scopePolicyVersion: '1',
        ),
      );
      transport.nextChanges = const ChangeFeedPage(
        changeSets: [
          SyncChangeSet(
            revision: '2',
            continuityEpoch: epoch,
            operationId: 'op-x',
            schemaVersion: 'farm-mutation.v1',
            createdAt: '2026-10-09T10:00:00Z',
            changes: [
              SyncChangeEntry(
                entity: 'zone',
                change: 'upsert',
                record: {'id': 'z-1', 'name': 'Rau', 'version': 1},
              ),
            ],
          ),
        ],
        highWatermark: '2',
        hasMore: false,
        nextCursor: 'cursor@2',
      );
      final report = await engine.synchronize(scope);
      expect(report.pulledChangeSets, 1);
      final zones = domain.recordsOf('$accountId|$organizationId|$farmId', 'zone');
      expect(zones['z-1']!['name'], 'Rau');
      final cursor = await domain.cursorFor('$accountId|$organizationId|$farmId');
      expect(cursor!.cursor, 'cursor@2');
      expect(cursor.highWatermark, '2');
    });

    test('expired cursor triggers a full bootstrap, keeping pending intents', () async {
      final pending = nextOp();
      await engine.enqueue(harvest(pending));
      // Pending op fails to send this round (offline transport).
      transport.nextSubmit = const FarmlyApiFailure(FarmlyApiFailureCode.unavailable);
      transport.nextStatus = const FarmlyApiFailure(FarmlyApiFailureCode.unavailable);
      await domain.installBootstrap(
        scopeKey: '$accountId|$organizationId|$farmId',
        blocks: const [],
        cursor: const SyncCursorState(
          cursor: 'stale-cursor',
          highWatermark: '9',
          continuityEpoch: epoch,
          scopePolicyVersion: '1',
        ),
      );
      transport.nextChanges = const FarmlyApiFailure(FarmlyApiFailureCode.cursorExpired);
      transport.bootstrapBlocks = const [
        BootstrapBlock(
          entity: 'zone',
          records: [
            {'id': 'z-boot', 'name': 'Bootstrapped', 'version': 3},
          ],
        ),
      ];
      final report = await engine.synchronize(scope);
      expect(report.bootstrapped, isTrue);
      expect(transport.bootstrapCalls, 1);
      final zones = domain.recordsOf('$accountId|$organizationId|$farmId', 'zone');
      expect(zones['z-boot']!['name'], 'Bootstrapped');
      final cursor = await domain.cursorFor('$accountId|$organizationId|$farmId');
      expect(cursor!.cursor, 'cursor@1');
      // The pending intent survived the re-bootstrap untouched.
      final entry = await outbox.find(
        accountId: accountId,
        organizationId: organizationId,
        operationId: pending,
      );
      expect(entry, isNotNull);
    });

    test('unknown change kind halts instead of silently skipping', () async {
      await domain.installBootstrap(
        scopeKey: '$accountId|$organizationId|$farmId',
        blocks: const [],
        cursor: const SyncCursorState(
          cursor: 'cursor@1',
          highWatermark: '1',
          continuityEpoch: epoch,
          scopePolicyVersion: '1',
        ),
      );
      transport.nextChanges = const ChangeFeedPage(
        changeSets: [
          SyncChangeSet(
            revision: '2',
            continuityEpoch: epoch,
            operationId: null,
            schemaVersion: 'farm-mutation.v1',
            createdAt: '2026-10-09T10:00:00Z',
            changes: [
              SyncChangeEntry(entity: 'zone', change: 'merge', record: {'id': 'z-1'}),
            ],
          ),
        ],
        highWatermark: '2',
        hasMore: false,
        nextCursor: 'cursor@2',
      );
      await expectLater(
        engine.synchronize(scope),
        throwsA(isA<UnsupportedChangeError>()),
      );
      // Cursor did not advance past the unapplied set.
      final cursor = await domain.cursorFor('$accountId|$organizationId|$farmId');
      expect(cursor!.cursor, 'cursor@1');
    });
  });

  group('conflict resolution', () {
    test('replacement wears a new operationId and the server baseVersion', () async {
      final op = nextOp();
      await engine.enqueue(harvest(op));
      transport.nextSubmit = MutationBatchResult(
        outcomes: [MutationOutcome(operationId: op, outcome: 'conflict')],
        asOf: null,
        scopePolicyVersion: '1',
      );
      await engine.synchronize(scope);
      final conflict = engine.conflicts.single;
      final entry = await engine.resolveConflict(conflict, newBaseVersion: 7);
      expect(entry.operationId, isNot(op));
      expect(entry.status, OutboxEntryStatus.pending);
      expect(entry.mutation.intent.baseVersion, 7);
      expect(entry.mutation.intent.payload['quantityKg'], '10');
      final original = await outbox.find(
        accountId: accountId,
        organizationId: organizationId,
        operationId: op,
      );
      expect(original!.status, OutboxEntryStatus.rejected);
      expect(original.rejectionCode, 'SUPERSEDED');
      expect(engine.conflicts, isEmpty);
    });
  });

  group('durable outbox', () {
    test('encrypted file store round-trips intents across cold start', () async {
      final dir = await Directory.systemTemp.createTemp('farmly-outbox-test');
      addTearDown(() => dir.delete(recursive: true));
      const key =
          'AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA'; // 32 zero bytes b64url
      final offlineKey = _offlineKey(key);
      final store = EncryptedFileOutboxStore(directory: dir, key: offlineKey);
      final mutation = harvest('11111111-1111-4111-8111-111111111111');
      await store.enqueue(mutation);

      // Cold start: a fresh store instance reads the same durable document.
      final reopened = EncryptedFileOutboxStore(directory: dir, key: offlineKey);
      final entries = await reopened.entries(
        accountId: accountId,
        organizationId: organizationId,
      );
      expect(entries, hasLength(1));
      expect(entries.single.operationId, mutation.intent.operationId);
      expect(entries.single.mutation.intent.payload['quantityKg'], '10');
    });

    test('encrypted file store rejects a wrong key (no silent plaintext)', () async {
      final dir = await Directory.systemTemp.createTemp('farmly-outbox-test-2');
      addTearDown(() => dir.delete(recursive: true));
      final keyA = _offlineKey('AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA');
      final keyB = _offlineKey(base64Url.encode(List<int>.filled(32, 1)));
      await EncryptedFileOutboxStore(directory: dir, key: keyA)
          .enqueue(harvest('11111111-1111-4111-8111-111111111111'));
      final wrongKey = EncryptedFileOutboxStore(directory: dir, key: keyB);
      await expectLater(
        wrongKey.entries(accountId: accountId, organizationId: organizationId),
        throwsA(isA<FarmlyMutationAuthenticationFailure>()),
      );
    });

    test('domain projection survives cold start with cursor intact', () async {
      final dir = await Directory.systemTemp.createTemp('farmly-domain-test');
      addTearDown(() => dir.delete(recursive: true));
      final key = _offlineKey('AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA');
      const scopeKey = '$accountId|$organizationId|$farmId';
      final store = EncryptedFileDomainStore(directory: dir, key: key);
      await store.installBootstrap(
        scopeKey: scopeKey,
        blocks: const [
          BootstrapBlock(
            entity: 'zone',
            records: [
              {'id': 'z-1', 'name': 'Vườn rau', 'version': 2},
            ],
          ),
        ],
        cursor: const SyncCursorState(
          cursor: 'cursor@42',
          highWatermark: '42',
          continuityEpoch: epoch,
          scopePolicyVersion: '1',
        ),
      );
      final reopened = EncryptedFileDomainStore(directory: dir, key: key);
      final cursor = await reopened.cursorFor(scopeKey);
      expect(cursor!.cursor, 'cursor@42');
      expect(cursor.highWatermark, '42');
      expect(reopened.recordsOf(scopeKey, 'zone')['z-1']!['name'], 'Vườn rau');
    });

    test('domain projection fails closed on a wrong key', () async {
      final dir = await Directory.systemTemp.createTemp('farmly-domain-test-2');
      addTearDown(() => dir.delete(recursive: true));
      final keyA = _offlineKey('AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA');
      final keyB = _offlineKey(base64Url.encode(List<int>.filled(32, 2)));
      const scopeKey = '$accountId|$organizationId|$farmId';
      await EncryptedFileDomainStore(directory: dir, key: keyA).installBootstrap(
        scopeKey: scopeKey,
        blocks: const [
          BootstrapBlock(
            entity: 'zone',
            records: [{'id': 'z-1', 'name': 'x', 'version': 1}],
          ),
        ],
        cursor: const SyncCursorState(
          cursor: 'c',
          highWatermark: '1',
          continuityEpoch: epoch,
          scopePolicyVersion: '1',
        ),
      );
      final wrongKey = EncryptedFileDomainStore(directory: dir, key: keyB);
      await expectLater(
        wrongKey.cursorFor(scopeKey),
        throwsA(isA<FarmlyDomainStoreAuthenticationFailure>()),
      );
    });

    test('operation ID cannot be rebound to different intent bytes', () async {
      final store = InMemoryOutboxStore();
      final op = '22222222-2222-4222-8222-222222222222';
      await store.enqueue(harvest(op));
      await expectLater(
        store.enqueue(
          harvest(op, resourceId: '00000000-0000-4000-8000-000000000999'),
        ),
        throwsA(isA<OutboxOperationConflict>()),
      );
      // Identical retry is a no-op.
      final again = await store.enqueue(harvest(op));
      expect(again.status, OutboxEntryStatus.pending);
    });
  });
}

FarmlyOfflineKey _offlineKey(String encoded) => FarmlyOfflineKey.fromEncoded(encoded);
