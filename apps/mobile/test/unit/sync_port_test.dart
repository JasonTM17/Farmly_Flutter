import 'dart:async';
import 'dart:convert';

import 'package:farmly_mobile/core/sync/farmly_mutation.dart';
import 'package:farmly_mobile/generated/farmly_api_types.dart';
import 'package:farmly_mobile/core/sync/sync_port.dart';
import 'package:flutter_test/flutter_test.dart';

import '../support/fake_sync_port.dart';

const accountId = '00000000-0000-4000-8000-000000000001';
const organizationId = '00000000-0000-4000-8000-000000000002';
const farmId = '00000000-0000-4000-8000-000000000003';
const otherFarmId = '00000000-0000-4000-8000-000000000004';
const operationId = '00000000-0000-4000-8000-000000000101';
const resourceId = '00000000-0000-4000-8000-000000000201';
const plantingId = '00000000-0000-4000-8000-000000000301';
const continuityEpoch = 'synthetic-fixture-epoch-v1';

void main() {
  group('Farmly mutation scopes and immutable intents', () {
    test(
      'serializes the canonical typed harvest intent without local identity fields',
      () {
        final scope = FarmlyMutationScope.farm(
          accountId: accountId,
          organizationId: organizationId,
          farmId: farmId,
          continuityEpoch: continuityEpoch,
        );
        final mutation = FarmlyScopedMutation(
          scope: scope,
          intent: FarmlyCreateHarvestIntent(
            operationId: operationId,
            continuityEpoch: continuityEpoch,
            resourceId: resourceId,
            plantingId: plantingId,
            quantityKg: FarmlyDecimal.parse('12.3750'),
            harvestDate: '2026-10-05',
          ),
        );

        final body = mutation.toRequestJson();
        expect(body, {
          'schemaVersion': 'farm-mutation.v1',
          'continuityEpoch': continuityEpoch,
          'operationId': operationId,
          'type': 'harvest.create',
          'resourceId': resourceId,
          'baseVersion': null,
          'dependsOn': <String>[],
          'payload': {
            'plantingId': plantingId,
            'quantityKg': '12.3750',
            'harvestDate': '2026-10-05',
          },
        });
        expect(jsonEncode(body), contains('12.3750'));
        expect(body.keys, isNot(contains('accountId')));
        expect(body.keys, isNot(contains('organizationId')));
        expect(body.keys, isNot(contains('farmId')));
        expect(() => body['operationId'] = 'changed', throwsUnsupportedError);
        expect(
          () => body['payload']!['quantityKg'] = '99',
          throwsUnsupportedError,
        );
      },
    );

    test('routes farm creation only through an organization scope', () {
      final intent = FarmlyCreateFarmIntent(
        operationId: operationId,
        continuityEpoch: continuityEpoch,
        resourceId: farmId,
        name: 'North field',
        timezone: 'Asia/Bangkok',
      );
      final scoped = FarmlyScopedMutation(
        scope: FarmlyMutationScope.organization(
          accountId: accountId,
          organizationId: organizationId,
          continuityEpoch: continuityEpoch,
        ),
        intent: intent,
      );
      expect(scoped.toRequestJson(), {
        'schemaVersion': 'farm-mutation.v1',
        'continuityEpoch': continuityEpoch,
        'operationId': operationId,
        'type': 'farm.create',
        'resourceId': farmId,
        'baseVersion': null,
        'dependsOn': <String>[],
        'payload': {'name': 'North field', 'timezone': 'Asia/Bangkok'},
      });
      expect(scoped.toRequestJson()['resourceId'], farmId);
      expect(
        () => FarmlyScopedMutation(
          scope: FarmlyMutationScope.farm(
            accountId: accountId,
            organizationId: organizationId,
            farmId: farmId,
            continuityEpoch: continuityEpoch,
          ),
          intent: intent,
        ),
        throwsArgumentError,
      );
      expect(
        () => FarmlyScopedMutation(
          scope: FarmlyMutationScope.organization(
            accountId: accountId,
            organizationId: organizationId,
            continuityEpoch: 'new-epoch',
          ),
          intent: intent,
        ),
        throwsArgumentError,
      );
    });

    test(
      'keeps scope-bound writes atomic and rolls back a failed local transaction',
      () async {
        final port = FakeSyncPort();
        final scope = FarmlyMutationScope.farm(
          accountId: accountId,
          organizationId: organizationId,
          farmId: farmId,
          continuityEpoch: continuityEpoch,
        );
        final mutation = FarmlyScopedMutation(
          scope: scope,
          intent: FarmlyCreateHarvestIntent(
            operationId: operationId,
            continuityEpoch: continuityEpoch,
            resourceId: resourceId,
            plantingId: plantingId,
            quantityKg: FarmlyDecimal.parse('1.25'),
            harvestDate: '2026-10-05',
          ),
        );

        await port.transactLocal((transaction) async {
          await transaction.enqueue(mutation);
        });
        expect(port.pending, hasLength(1));
        expect(port.pending.single.scope.accountId, accountId);
        expect(port.pending.single.scope.organizationId, organizationId);
        expect(port.pending.single.scope.farmId, farmId);

        await expectLater(
          port.transactLocal((transaction) async {
            await transaction.enqueue(mutation);
            throw StateError('rollback test');
          }),
          throwsStateError,
        );
        expect(port.pending, hasLength(1));
      },
    );

    test(
      'rejects reusing an operation ID across farms in one organization',
      () async {
        final port = FakeSyncPort();
        FarmlyScopedMutation harvest(String scopedFarmId) =>
            FarmlyScopedMutation(
              scope: FarmlyMutationScope.farm(
                accountId: accountId,
                organizationId: organizationId,
                farmId: scopedFarmId,
                continuityEpoch: continuityEpoch,
              ),
              intent: FarmlyCreateHarvestIntent(
                operationId: operationId,
                continuityEpoch: continuityEpoch,
                resourceId: resourceId,
                plantingId: plantingId,
                quantityKg: FarmlyDecimal.parse('1.25'),
                harvestDate: '2026-10-05',
              ),
            );

        await port.transactLocal((transaction) async {
          await transaction.enqueue(harvest(farmId));
        });
        await expectLater(
          port.transactLocal((transaction) async {
            await transaction.enqueue(harvest(otherFarmId));
          }),
          throwsStateError,
        );
        expect(port.pending, hasLength(1));
        expect(port.pending.single.scope.farmId, farmId);
      },
    );

    test(
      'closes retained handles and serializes concurrent local transactions',
      () async {
        final port = FakeSyncPort();
        final mutationA = FarmlyScopedMutation(
          scope: FarmlyMutationScope.farm(
            accountId: accountId,
            organizationId: organizationId,
            farmId: farmId,
            continuityEpoch: continuityEpoch,
          ),
          intent: FarmlyCreateHarvestIntent(
            operationId: operationId,
            continuityEpoch: continuityEpoch,
            resourceId: resourceId,
            plantingId: plantingId,
            quantityKg: FarmlyDecimal.parse('1'),
            harvestDate: '2026-10-05',
          ),
        );
        final mutationB = FarmlyScopedMutation(
          scope: FarmlyMutationScope.farm(
            accountId: accountId,
            organizationId: organizationId,
            farmId: farmId,
            continuityEpoch: continuityEpoch,
          ),
          intent: FarmlyCreateHarvestIntent(
            operationId: '00000000-0000-4000-8000-000000000102',
            continuityEpoch: continuityEpoch,
            resourceId: '00000000-0000-4000-8000-000000000202',
            plantingId: plantingId,
            quantityKg: FarmlyDecimal.parse('2'),
            harvestDate: '2026-10-05',
          ),
        );
        final firstEntered = Completer<void>();
        final releaseFirst = Completer<void>();
        LocalSyncTransaction? retained;
        final first = port.transactLocal((transaction) async {
          retained = transaction;
          await transaction.enqueue(mutationA);
          firstEntered.complete();
          await releaseFirst.future;
        });
        await firstEntered.future;
        final secondEntered = Completer<void>();
        final second = port.transactLocal((transaction) async {
          secondEntered.complete();
          await transaction.enqueue(mutationB);
        });
        await Future<void>.delayed(Duration.zero);
        expect(secondEntered.isCompleted, isFalse);
        releaseFirst.complete();
        await Future.wait([first, second]);

        expect(
          port.pending.map((item) => item.intent.operationId),
          containsAll([operationId, '00000000-0000-4000-8000-000000000102']),
        );
        await expectLater(retained!.enqueue(mutationB), throwsStateError);
        expect(port.pending, hasLength(2));
      },
    );

    test('rejects invalid civil dates and duplicate dependency IDs', () {
      expect(
        () => FarmlyCreateHarvestIntent(
          operationId: operationId,
          continuityEpoch: continuityEpoch,
          resourceId: resourceId,
          plantingId: plantingId,
          quantityKg: FarmlyDecimal.parse('1'),
          harvestDate: '2026-02-30',
        ),
        throwsFormatException,
      );
      expect(
        () => FarmlyCreateFarmIntent(
          operationId: operationId,
          continuityEpoch: continuityEpoch,
          resourceId: farmId,
          name: 'North field',
          timezone: 'Asia/Bangkok',
          dependsOn: [resourceId, resourceId],
        ),
        throwsArgumentError,
      );
    });
  });
}
