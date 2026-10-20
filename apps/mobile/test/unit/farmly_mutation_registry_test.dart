import 'dart:convert';

import 'package:farmly_mobile/core/sync/farmly_mutation.dart';
import 'package:farmly_mobile/generated/farmly_api_types.dart';
import 'package:flutter_test/flutter_test.dart';

const _accountId = '00000000-0000-4000-8000-000000000001';
const _organizationId = '00000000-0000-4000-8000-000000000002';
const _farmId = '00000000-0000-4000-8000-000000000003';
const _animalId = '00000000-0000-4000-8000-000000000004';
const _operationId = '00000000-0000-4000-8000-000000000101';
const _taskOccurrenceId = 'd6b616b7-5153-57e6-87cc-2e379ee6a10b';
const _continuityEpoch = '7';

dynamic _dynamicNullVersion() => null;

// Canonical allowlist from contracts/scripts/build-contracts.mjs. This test
// covers durable registry decoding; typed local create payloads use the
// smallest valid wire shape so restore validation is exercised honestly.
const _canonicalMutationTypes = <String>[
  'farm.create',
  'farm.update',
  'farm.archive',
  'zone.create',
  'zone.update',
  'zone.archive',
  'cropSpecies.create',
  'cropSpecies.update',
  'cropSpecies.archive',
  'planting.create',
  'planting.update',
  'planting.archive',
  'plantingEvent.create',
  'herd.create',
  'herd.update',
  'herd.archive',
  'animal.create',
  'animal.update',
  'animal.archive',
  'livestockMovement.create',
  'animalObservation.create',
  'productionRecord.create',
  'taskTemplate.create',
  'taskTemplate.update',
  'taskOccurrence.transition',
  'harvest.create',
  'harvest.correction.propose',
  'harvest.correction.apply',
  'harvest.void',
  'moistureReading.create',
  'waterTank.create',
  'waterTank.update',
  'waterTank.archive',
  'waterReading.create',
  'waterUsage.create',
  'irrigationTask.transition',
];

Map<String, Object?> _wireIntent(String type) => {
  'schemaVersion': FarmlyMutationIntent.schemaVersion,
  'continuityEpoch': _continuityEpoch,
  'operationId': _operationId,
  'type': type,
  'resourceId': _farmId,
  'baseVersion':
      type == 'farm.update' ||
          type == 'zone.update' ||
          type == 'cropSpecies.update' ||
          type == 'cropSpecies.archive' ||
          type == 'waterTank.update' ||
          type == 'planting.update' ||
          type == 'planting.archive' ||
          type == 'animal.update'
      ? 1
      : null,
  'dependsOn': <String>[],
  'payload': switch (type) {
    'farm.update' => <String, Object?>{'name': 'North field'},
    'zone.update' => <String, Object?>{'name': 'North plot'},
    'cropSpecies.update' => <String, Object?>{'name': 'Tomato'},
    'waterTank.update' => <String, Object?>{'name': 'Tank A'},
    'planting.update' => <String, Object?>{'areaM2': '125.5'},
    'animal.update' => <String, Object?>{'tag': 'COW-002'},
    'herd.create' => <String, Object?>{'mode': 'batch'},
    'animal.create' => <String, Object?>{'herdId': _farmId, 'tag': 'COW-001'},
    'moistureReading.create' => <String, Object?>{
      'zoneId': _farmId,
      'value': '50.25',
      'method': 'relative_percent',
      'measuredAt': '2026-10-18T00:00:00Z',
    },
    _ => <String, Object?>{},
  },
};

void main() {
  group('Farmly durable mutation registry', () {
    test('matches the generated API contract allowlist exactly', () {
      expect(farmlyMutationTypes, unorderedEquals(_canonicalMutationTypes));
    });

    test('rejects an unknown but well-formed namespaced operation type', () {
      expect(
        () => FarmlyMutationIntent.fromJson(_wireIntent('farm.futureCreate')),
        throwsFormatException,
      );
    });

    test('round-trips every canonical operation type through durable JSON', () {
      final restoredTypes = <String>[];

      for (final type in _canonicalMutationTypes) {
        final durableJson = jsonEncode(_wireIntent(type));
        final decodedMap = Map<String, Object?>.from(
          jsonDecode(durableJson) as Map,
        );
        final intent = FarmlyMutationIntent.fromJson(decodedMap);
        final restoredJson = Map<String, Object?>.from(
          jsonDecode(jsonEncode(intent.toJson())) as Map,
        );

        restoredTypes.add(restoredJson['type'] as String);
        expect(
          restoredJson,
          decodedMap,
          reason: 'type $type changed on restore',
        );
      }

      expect(restoredTypes, _canonicalMutationTypes);
    });

    test('restores a farm name update only with a versioned name payload', () {
      final intent = FarmlyMutationIntent.fromJson(_wireIntent('farm.update'));

      expect(intent.baseVersion, 1);
      expect(intent.payload, {'name': 'North field'});
    });

    test('restores all farm.update fields and preserves location values', () {
      for (final location in <Object?>['37.7,-122.4', null]) {
        final payload = <String, Object?>{
          'name': 'North field',
          'timezone': 'America/New_York',
          'areaM2': '123.45',
          'location': location,
        };
        final json = {..._wireIntent('farm.update'), 'payload': payload};

        final intent = FarmlyMutationIntent.fromJson(json);

        expect(intent.payload, payload);
        expect(intent.toJson()['payload'], payload);
      }
    });

    test('authors a farm name update with the confirmed row version', () {
      final intent = FarmlyUpdateFarmNameIntent(
        operationId: _operationId,
        continuityEpoch: _continuityEpoch,
        resourceId: _farmId,
        baseVersion: 7,
        name: '  North field  ',
      );

      expect(intent.type, 'farm.update');
      expect(intent.baseVersion, 7);
      expect(intent.payload, {'name': 'North field'});
      expect(
        () => FarmlyUpdateFarmNameIntent(
          operationId: _operationId,
          continuityEpoch: _continuityEpoch,
          resourceId: _farmId,
          baseVersion: 0,
          name: 'North field',
        ),
        throwsArgumentError,
      );
      expect(
        () => FarmlyUpdateFarmNameIntent(
          operationId: _operationId,
          continuityEpoch: _continuityEpoch,
          resourceId: _farmId,
          baseVersion: 7,
          name: '  ',
        ),
        throwsArgumentError,
      );
    });

    test('authors and restores an animal update with strict CAS fields', () {
      final update = FarmlyUpdateAnimalIntent(
        operationId: _operationId,
        continuityEpoch: _continuityEpoch,
        resourceId: _animalId,
        baseVersion: 7,
        tag: ' COW-002 ',
        name: ' Bông ',
        birthDate: '2023-04-05',
      );

      expect(update.type, 'animal.update');
      expect(update.resourceId, _animalId);
      expect(update.baseVersion, 7);
      expect(update.payload, {
        'tag': 'COW-002',
        'name': 'Bông',
        'birthDate': '2023-04-05',
      });
      final restored = FarmlyMutationIntent.fromJson(
        Map<String, Object?>.from(
          jsonDecode(jsonEncode(update.toJson())) as Map,
        ),
      );
      expect(restored.type, 'animal.update');
      expect(restored.resourceId, _animalId);
      expect(restored.baseVersion, 7);
      expect(restored.payload, update.payload);

      expect(
        () => FarmlyUpdateAnimalIntent(
          operationId: _operationId,
          continuityEpoch: _continuityEpoch,
          resourceId: _animalId,
          baseVersion: 0,
          tag: 'COW-002',
        ),
        throwsArgumentError,
      );
      expect(
        () => FarmlyUpdateAnimalIntent(
          operationId: _operationId,
          continuityEpoch: _continuityEpoch,
          resourceId: _animalId,
          baseVersion: 7,
        ),
        throwsArgumentError,
      );
    });

    test(
      'animal.update restore rejects missing CAS and immutable or status fields',
      () {
        for (final invalid in [
          {..._wireIntent('animal.update'), 'baseVersion': null},
          {..._wireIntent('animal.update'), 'baseVersion': 0},
          {
            ..._wireIntent('animal.update'),
            'payload': <String, Object?>{'herdId': _farmId},
          },
          {
            ..._wireIntent('animal.update'),
            'payload': <String, Object?>{'status': 'sold'},
          },
          {
            ..._wireIntent('animal.update'),
            'payload': <String, Object?>{'tag': '  '},
          },
          {
            ..._wireIntent('animal.update'),
            'payload': <String, Object?>{'unknown': 'value'},
          },
        ]) {
          expect(
            () => FarmlyMutationIntent.fromJson(invalid),
            throwsFormatException,
          );
        }
      },
    );

    test(
      'rejects malformed farm.update durable payloads and base versions',
      () {
        final invalid = <Map<String, Object?>>[
          {..._wireIntent('farm.update'), 'baseVersion': null},
          {..._wireIntent('farm.update'), 'baseVersion': 0},
          {..._wireIntent('farm.update'), 'baseVersion': 1.5},
          {..._wireIntent('farm.update'), 'payload': <String, Object?>{}},
          {
            ..._wireIntent('farm.update'),
            'payload': <String, Object?>{'name': '  '},
          },
          {
            ..._wireIntent('farm.update'),
            'payload': <String, Object?>{
              'name': 'North field',
              'unsupported': true,
            },
          },
          {
            ..._wireIntent('farm.update'),
            'payload': <String, Object?>{'name': 42},
          },
          {
            ..._wireIntent('farm.update'),
            'payload': <String, Object?>{'timezone': 42},
          },
          {
            ..._wireIntent('farm.update'),
            'payload': <String, Object?>{'timezone': '   '},
          },
          {
            ..._wireIntent('farm.update'),
            'payload': <String, Object?>{
              'timezone': List<String>.filled(65, 'x').join(),
            },
          },
          {
            ..._wireIntent('farm.update'),
            'payload': <String, Object?>{'areaM2': 12.5},
          },
          {
            ..._wireIntent('farm.update'),
            'payload': <String, Object?>{'areaM2': '01.25'},
          },
          {
            ..._wireIntent('farm.update'),
            'payload': <String, Object?>{'location': 42},
          },
          {
            ..._wireIntent('farm.update'),
            'payload': <String, Object?>{'location': '91.0,181.0'},
          },
        ];

        for (final json in invalid) {
          expect(
            () => FarmlyMutationIntent.fromJson(json),
            throwsFormatException,
            reason: 'invalid durable farm.update should fail closed: $json',
          );
        }
      },
    );

    test('authors a versioned zone name update', () {
      final intent = FarmlyUpdateZoneNameIntent(
        operationId: _operationId,
        continuityEpoch: _continuityEpoch,
        resourceId: '00000000-0000-4000-8000-000000000204',
        baseVersion: 7,
        name: '  North plot  ',
      );

      expect(intent.type, 'zone.update');
      expect(intent.baseVersion, 7);
      expect(intent.payload, {'name': 'North plot'});
      expect(
        () => FarmlyUpdateZoneNameIntent(
          operationId: _operationId,
          continuityEpoch: _continuityEpoch,
          resourceId: '00000000-0000-4000-8000-000000000204',
          baseVersion: 0,
          name: 'North plot',
        ),
        throwsArgumentError,
      );
      expect(
        () => FarmlyUpdateZoneNameIntent(
          operationId: _operationId,
          continuityEpoch: _continuityEpoch,
          resourceId: '00000000-0000-4000-8000-000000000204',
          baseVersion: 7,
          name: '  ',
        ),
        throwsArgumentError,
      );
      expect(
        () => FarmlyUpdateZoneNameIntent(
          operationId: _operationId,
          continuityEpoch: _continuityEpoch,
          resourceId: '00000000-0000-4000-8000-000000000204',
          baseVersion: 7,
          name: 'x' * 161,
        ),
        throwsArgumentError,
      );
    });

    test('restores zone.update name and exact P05 patch subsets', () {
      final geometry = <String, Object?>{
        'points': [
          {'x': '0.1', 'y': '0.1'},
          {'x': '0.8', 'y': '0.1'},
          {'x': '0.8', 'y': '0.8'},
        ],
      };
      for (final payload in <Map<String, Object?>>[
        {'name': 'North plot'},
        {'type': 'crop_plot'},
        {'geometry': geometry},
        {'areaM2': '125.50'},
        {
          'name': 'North plot',
          'type': 'crop_plot',
          'geometry': geometry,
          'areaM2': '125.50',
        },
      ]) {
        final json = {
          ..._wireIntent('zone.update'),
          'resourceId': '00000000-0000-4000-8000-000000000204',
          'payload': payload,
        };

        final restored = FarmlyMutationIntent.fromJson(json);

        expect(restored.type, 'zone.update');
        expect(restored.baseVersion, 1);
        expect(restored.payload, payload);
        expect(restored.toJson(), json);
      }
    });

    test('rejects malformed zone.update payloads and base versions', () {
      final invalid = <Map<String, Object?>>[
        {..._wireIntent('zone.update'), 'baseVersion': null},
        {..._wireIntent('zone.update'), 'baseVersion': 0},
        {..._wireIntent('zone.update'), 'baseVersion': 1.5},
        {..._wireIntent('zone.update'), 'payload': <String, Object?>{}},
        {
          ..._wireIntent('zone.update'),
          'payload': <String, Object?>{'unsupported': true},
        },
        {
          ..._wireIntent('zone.update'),
          'payload': <String, Object?>{'name': '  '},
        },
        {
          ..._wireIntent('zone.update'),
          'payload': <String, Object?>{'name': 'x' * 161},
        },
        {
          ..._wireIntent('zone.update'),
          'payload': <String, Object?>{'type': 'swamp'},
        },
        {
          ..._wireIntent('zone.update'),
          'payload': <String, Object?>{
            'geometry': <String, Object?>{'points': <Object?>[]},
          },
        },
        {
          ..._wireIntent('zone.update'),
          'payload': <String, Object?>{'areaM2': '01.25'},
        },
      ];

      for (final json in invalid) {
        expect(
          () => FarmlyMutationIntent.fromJson(json),
          throwsFormatException,
          reason: 'invalid durable zone.update should fail closed: $json',
        );
      }
    });

    test('authors a versioned crop species name update', () {
      final intent = FarmlyUpdateCropSpeciesNameIntent(
        operationId: _operationId,
        continuityEpoch: _continuityEpoch,
        resourceId: '00000000-0000-4000-8000-000000000204',
        baseVersion: 7,
        name: '  Cà chua hữu cơ  ',
      );

      expect(intent.type, 'cropSpecies.update');
      expect(intent.baseVersion, 7);
      expect(intent.payload, {'name': 'Cà chua hữu cơ'});
      expect(
        () => FarmlyUpdateCropSpeciesNameIntent(
          operationId: _operationId,
          continuityEpoch: _continuityEpoch,
          resourceId: '00000000-0000-4000-8000-000000000204',
          baseVersion: 0,
          name: 'Tomato',
        ),
        throwsArgumentError,
      );
      expect(
        () => FarmlyUpdateCropSpeciesNameIntent(
          operationId: _operationId,
          continuityEpoch: _continuityEpoch,
          resourceId: '00000000-0000-4000-8000-000000000204',
          baseVersion: 7,
          name: '  ',
        ),
        throwsArgumentError,
      );
    });

    test('restores cropSpecies.update with its version and exact schema', () {
      for (final payload in <Map<String, Object?>>[
        {'name': 'Tomato'},
        {'harvestUnit': 'pieces'},
        {'name': 'Tomato', 'harvestUnit': 'kg'},
      ]) {
        final json = {
          ..._wireIntent('cropSpecies.update'),
          'resourceId': '00000000-0000-4000-8000-000000000204',
          'payload': payload,
        };

        final restored = FarmlyMutationIntent.fromJson(json);

        expect(restored.type, 'cropSpecies.update');
        expect(restored.baseVersion, 1);
        expect(restored.payload, payload);
        expect(restored.toJson(), json);
      }
    });

    test('rejects malformed cropSpecies.update payloads and versions', () {
      final invalid = <Map<String, Object?>>[
        {..._wireIntent('cropSpecies.update'), 'baseVersion': null},
        {..._wireIntent('cropSpecies.update'), 'baseVersion': 0},
        {..._wireIntent('cropSpecies.update'), 'baseVersion': 1.5},
        {..._wireIntent('cropSpecies.update'), 'payload': <String, Object?>{}},
        {
          ..._wireIntent('cropSpecies.update'),
          'payload': <String, Object?>{'name': '  '},
        },
        {
          ..._wireIntent('cropSpecies.update'),
          'payload': <String, Object?>{
            'name': '${List<String>.filled(160, ' ').join()}Tomato',
          },
        },
        {
          ..._wireIntent('cropSpecies.update'),
          'payload': <String, Object?>{'name': 42},
        },
        {
          ..._wireIntent('cropSpecies.update'),
          'payload': <String, Object?>{'harvestUnit': 'box'},
        },
        {
          ..._wireIntent('cropSpecies.update'),
          'payload': <String, Object?>{'harvestUnit': null},
        },
        {
          ..._wireIntent('cropSpecies.update'),
          'payload': <String, Object?>{'name': 'Tomato', 'unsupported': true},
        },
      ];

      for (final json in invalid) {
        expect(
          () => FarmlyMutationIntent.fromJson(json),
          throwsFormatException,
          reason:
              'invalid durable cropSpecies.update should fail closed: $json',
        );
      }
    });

    test('authors a versioned crop species archive with an empty payload', () {
      final intent = FarmlyArchiveCropSpeciesIntent(
        operationId: _operationId,
        continuityEpoch: _continuityEpoch,
        resourceId: '00000000-0000-4000-8000-000000000204',
        baseVersion: 7,
      );

      expect(intent.type, 'cropSpecies.archive');
      expect(intent.baseVersion, 7);
      expect(intent.payload, isEmpty);
      expect(
        () => FarmlyArchiveCropSpeciesIntent(
          operationId: _operationId,
          continuityEpoch: _continuityEpoch,
          resourceId: '00000000-0000-4000-8000-000000000204',
          baseVersion: 0,
        ),
        throwsArgumentError,
      );
    });

    test('restores cropSpecies.archive with exact empty payload and CAS', () {
      final json = {
        ..._wireIntent('cropSpecies.archive'),
        'resourceId': '00000000-0000-4000-8000-000000000204',
        'baseVersion': 9,
        'payload': <String, Object?>{},
      };

      final restored = FarmlyMutationIntent.fromJson(json);

      expect(restored.type, 'cropSpecies.archive');
      expect(restored.baseVersion, 9);
      expect(restored.payload, isEmpty);
      expect(restored.toJson(), json);
    });

    test('rejects malformed cropSpecies.archive payloads and versions', () {
      final invalid = <Map<String, Object?>>[
        {..._wireIntent('cropSpecies.archive'), 'baseVersion': null},
        {..._wireIntent('cropSpecies.archive'), 'baseVersion': 0},
        {..._wireIntent('cropSpecies.archive'), 'baseVersion': 1.5},
        {
          ..._wireIntent('cropSpecies.archive'),
          'payload': <String, Object?>{'name': 'Tomato'},
        },
      ];

      for (final json in invalid) {
        expect(
          () => FarmlyMutationIntent.fromJson(json),
          throwsFormatException,
          reason:
              'invalid durable cropSpecies.archive should fail closed: $json',
        );
      }
    });

    test('restores farm.create as an organization-scoped ingress intent', () {
      final authored = FarmlyCreateFarmIntent(
        operationId: _operationId,
        continuityEpoch: _continuityEpoch,
        resourceId: _farmId,
        name: 'North field',
        timezone: 'Asia/Bangkok',
      );
      final durableJson = jsonEncode(authored.toJson());
      final decoded = FarmlyMutationIntent.fromJson(
        Map<String, Object?>.from(jsonDecode(durableJson) as Map),
      );
      final organizationScope = FarmlyMutationScope.organization(
        accountId: _accountId,
        organizationId: _organizationId,
        continuityEpoch: _continuityEpoch,
      );

      final scoped = FarmlyScopedMutation(
        scope: organizationScope,
        intent: decoded,
      );

      expect(scoped.scope.kind, FarmlyMutationScopeKind.organization);
      expect(scoped.scope.organizationId, _organizationId);
      expect(scoped.scope.farmId, isNull);
      expect(scoped.intent.type, 'farm.create');
      expect(scoped.toRequestJson(), authored.toJson());
    });

    test('authors a farm child zone with an explicit parent dependency', () {
      final parentOperationId = _operationId;
      final zone = FarmlyCreateZoneIntent(
        operationId: '00000000-0000-4000-8000-000000000102',
        continuityEpoch: _continuityEpoch,
        resourceId: '00000000-0000-4000-8000-000000000103',
        name: 'Vegetable bed A',
        type: 'crop_plot',
        geometry: const [
          {'x': '0.2', 'y': '0.2'},
          {'x': '0.8', 'y': '0.2'},
          {'x': '0.8', 'y': '0.8'},
          {'x': '0.2', 'y': '0.8'},
        ],
        dependsOn: [parentOperationId],
      );

      expect(zone.type, 'zone.create');
      expect(zone.baseVersion, isNull);
      expect(zone.dependsOn, [parentOperationId]);
      expect(zone.payload, {
        'name': 'Vegetable bed A',
        'type': 'crop_plot',
        'geometry': {
          'points': const [
            {'x': '0.2', 'y': '0.2'},
            {'x': '0.8', 'y': '0.2'},
            {'x': '0.8', 'y': '0.8'},
            {'x': '0.2', 'y': '0.8'},
          ],
        },
      });
    });

    test('authors a recurring task template with strict schedule fields', () {
      const parentZoneOperationId = '00000000-0000-4000-8000-000000000104';
      final intent = FarmlyCreateTaskTemplateIntent(
        operationId: '00000000-0000-4000-8000-000000000105',
        continuityEpoch: _continuityEpoch,
        resourceId: '00000000-0000-4000-8000-000000000106',
        title: '  Feed the calves  ',
        kind: 'feeding',
        zoneId: _farmId,
        frequency: 'weekly',
        timeOfDay: '06:30',
        daysOfWeek: const [1, 3, 5],
        startsOn: '2026-10-19',
        endsOn: '2026-12-31',
        dependsOn: const [parentZoneOperationId],
      );

      expect(intent.type, 'taskTemplate.create');
      expect(intent.baseVersion, isNull);
      expect(intent.dependsOn, [parentZoneOperationId]);
      expect(intent.payload, {
        'title': 'Feed the calves',
        'kind': 'feeding',
        'zoneId': _farmId,
        'recurrence': {
          'freq': 'weekly',
          'timeOfDay': '06:30',
          'daysOfWeek': [1, 3, 5],
        },
        'startsOn': '2026-10-19',
        'endsOn': '2026-12-31',
      });
      final recurrence = intent.payload['recurrence'] as Map;
      expect(() => recurrence.clear(), throwsUnsupportedError);
      expect(
        () => (recurrence['daysOfWeek'] as List).clear(),
        throwsUnsupportedError,
      );
    });

    test('repairs weekly task weekdays with the current template version', () {
      final intent = FarmlyUpdateTaskTemplateScheduleIntent(
        operationId: _operationId,
        continuityEpoch: _continuityEpoch,
        resourceId: _farmId,
        baseVersion: 4,
        frequency: 'weekly',
        timeOfDay: '07:30',
        daysOfWeek: const [1, 4],
      );

      expect(intent.type, 'taskTemplate.update');
      expect(intent.resourceId, _farmId);
      expect(intent.baseVersion, 4);
      expect(intent.payload, {
        'recurrence': {
          'freq': 'weekly',
          'timeOfDay': '07:30',
          'daysOfWeek': [1, 4],
        },
      });
      expect(
        () => FarmlyUpdateTaskTemplateScheduleIntent(
          operationId: _operationId,
          continuityEpoch: _continuityEpoch,
          resourceId: _farmId,
          baseVersion: 4,
          frequency: 'weekly',
          timeOfDay: '07:30',
        ),
        throwsArgumentError,
      );
    });

    test('defaults task templates to general daily recurrence', () {
      final intent = FarmlyCreateTaskTemplateIntent(
        operationId: _operationId,
        continuityEpoch: _continuityEpoch,
        resourceId: _farmId,
        title: 'Inspect the greenhouse',
        frequency: 'daily',
        timeOfDay: '07:00',
      );

      expect(intent.payload, {
        'title': 'Inspect the greenhouse',
        'recurrence': {'freq': 'daily', 'timeOfDay': '07:00'},
      });

      expect(
        () => FarmlyCreateTaskTemplateIntent(
          operationId: _operationId,
          continuityEpoch: _continuityEpoch,
          resourceId: _farmId,
          title: 'Water the greenhouse',
          frequency: 'weekly',
          timeOfDay: '07:00',
        ),
        throwsArgumentError,
      );

      final repeatedWeekdaysArePreserved = FarmlyCreateTaskTemplateIntent(
        operationId: _operationId,
        continuityEpoch: _continuityEpoch,
        resourceId: _farmId,
        title: 'Inspect on selected weekdays',
        frequency: 'weekly',
        timeOfDay: '07:00',
        daysOfWeek: const [1, 1],
      );
      expect(
        (repeatedWeekdaysArePreserved.payload['recurrence']
            as Map)['daysOfWeek'],
        [1, 1],
      );
    });

    test('authors a versioned task occurrence transition', () {
      final intent = FarmlyTaskOccurrenceTransitionIntent(
        operationId: _operationId,
        continuityEpoch: _continuityEpoch,
        resourceId: _taskOccurrenceId,
        templateId: _organizationId,
        occurrenceDate: '2026-10-19',
        slot: 'morning',
        transition: 'complete',
        baseVersion: 3,
        reason: '  Watered the bed  ',
      );

      expect(intent.type, 'taskOccurrence.transition');
      expect(intent.baseVersion, 3);
      expect(intent.payload, {
        'templateId': _organizationId,
        'occurrenceDate': '2026-10-19',
        'slot': 'morning',
        'transition': 'complete',
        'reason': 'Watered the bed',
      });
      expect(
        FarmlyMutationIntent.fromJson(
          jsonDecode(jsonEncode(intent.toJson())) as Map<String, Object?>,
        ).payload,
        intent.payload,
      );
    });

    test(
      'authors an unmaterialized default-slot transition without a version',
      () {
        final intent = FarmlyTaskOccurrenceTransitionIntent(
          operationId: _operationId,
          continuityEpoch: _continuityEpoch,
          resourceId: _taskOccurrenceId,
          templateId: _organizationId,
          occurrenceDate: '2026-10-19',
          slot: ' default ',
          transition: 'complete',
        );

        expect(intent.baseVersion, isNull);
        expect(intent.payload['slot'], 'default');
        expect(intent.type, 'taskOccurrence.transition');
      },
    );

    test(
      'rejects invalid task title, kind, time, weekday, and date ranges',
      () {
        FarmlyCreateTaskTemplateIntent create({
          String title = 'Inspect the greenhouse',
          String? kind,
          String frequency = 'daily',
          String timeOfDay = '07:00',
          List<int> daysOfWeek = const [],
          String? startsOn,
          String? endsOn,
        }) => FarmlyCreateTaskTemplateIntent(
          operationId: _operationId,
          continuityEpoch: _continuityEpoch,
          resourceId: _farmId,
          title: title,
          kind: kind,
          frequency: frequency,
          timeOfDay: timeOfDay,
          daysOfWeek: daysOfWeek,
          startsOn: startsOn,
          endsOn: endsOn,
        );

        expect(() => create(title: '   '), throwsArgumentError);
        expect(() => create(title: 't' * 161), throwsArgumentError);
        expect(() => create(kind: 'feeding-ish'), throwsArgumentError);
        expect(() => create(timeOfDay: '24:00'), throwsArgumentError);
        expect(
          () => create(frequency: 'weekly', daysOfWeek: const [7]),
          throwsArgumentError,
        );
        expect(
          () => create(frequency: 'daily', daysOfWeek: const [1]),
          throwsArgumentError,
        );
        expect(() => create(endsOn: '2026-02-30'), throwsFormatException);
        expect(
          () => create(startsOn: '2026-10-20', endsOn: '2026-10-19'),
          throwsArgumentError,
        );
      },
    );

    test('rejects unsupported farm time zones before enqueue', () {
      expect(
        () => FarmlyCreateFarmIntent(
          operationId: _operationId,
          continuityEpoch: _continuityEpoch,
          resourceId: _farmId,
          name: 'North field',
          timezone: 'Asia/Not_A_Real_Place',
        ),
        throwsFormatException,
      );
    });

    test('rejects malformed child zone geometry and noncanonical area', () {
      expect(
        () => FarmlyCreateZoneIntent(
          operationId: _operationId,
          continuityEpoch: _continuityEpoch,
          resourceId: _farmId,
          name: 'Broken plot',
          type: 'crop_plot',
          geometry: const [
            {'x': '0.2', 'y': '0.2'},
            {'x': '1.2', 'y': '0.2'},
            {'x': '0.8', 'y': '0.8'},
          ],
        ),
        throwsFormatException,
      );
      expect(
        () => FarmlyCreateFarmIntent(
          operationId: _operationId,
          continuityEpoch: _continuityEpoch,
          resourceId: _farmId,
          name: 'North field',
          timezone: 'Asia/Bangkok',
          areaM2: '12.345',
        ),
        throwsFormatException,
      );
    });

    test('creates exact offline crop species and planting payloads', () {
      const parentOperationId = '00000000-0000-4000-8000-000000000201';
      const speciesResourceId = '00000000-0000-4000-8000-000000000202';
      const plantingResourceId = '00000000-0000-4000-8000-000000000203';
      final species = FarmlyCreateCropSpeciesIntent(
        operationId: _operationId,
        continuityEpoch: _continuityEpoch,
        resourceId: speciesResourceId,
        name: '  Cà chua bi  ',
        harvestUnit: 'kg',
      );
      final planting = FarmlyCreatePlantingIntent(
        operationId: '00000000-0000-4000-8000-000000000204',
        continuityEpoch: _continuityEpoch,
        resourceId: plantingResourceId,
        cropSpeciesId: speciesResourceId,
        plotId: _farmId,
        sowingDate: '2024-02-29',
        expectedHarvestDate: '2024-06-30',
        areaM2: '125.50',
        dependsOn: [parentOperationId, _operationId],
      );

      expect(species.type, 'cropSpecies.create');
      expect(species.baseVersion, isNull);
      expect(species.payload, {'name': 'Cà chua bi', 'harvestUnit': 'kg'});
      expect(planting.type, 'planting.create');
      expect(planting.baseVersion, isNull);
      expect(planting.dependsOn, [parentOperationId, _operationId]);
      expect(planting.payload, {
        'cropSpeciesId': speciesResourceId,
        'plotId': _farmId,
        'sowingDate': '2024-02-29',
        'expectedHarvestDate': '2024-06-30',
        'areaM2': '125.50',
      });
    });

    test('rejects invalid crop units, civil dates, and planting areas', () {
      expect(
        () => FarmlyCreateCropSpeciesIntent(
          operationId: _operationId,
          continuityEpoch: _continuityEpoch,
          resourceId: _farmId,
          name: 'Tomato',
          harvestUnit: 'box',
        ),
        throwsArgumentError,
      );
      expect(
        () => FarmlyCreatePlantingIntent(
          operationId: _operationId,
          continuityEpoch: _continuityEpoch,
          resourceId: _farmId,
          cropSpeciesId: _operationId,
          plotId: _farmId,
          sowingDate: '2026-02-29',
        ),
        throwsFormatException,
      );
      expect(
        () => FarmlyCreatePlantingIntent(
          operationId: _operationId,
          continuityEpoch: _continuityEpoch,
          resourceId: _farmId,
          cropSpeciesId: _operationId,
          plotId: _farmId,
          sowingDate: '2026-10-19',
          expectedHarvestDate: '2026-10-18',
        ),
        throwsFormatException,
      );
      expect(
        () => FarmlyCreatePlantingIntent(
          operationId: _operationId,
          continuityEpoch: _continuityEpoch,
          resourceId: _farmId,
          cropSpeciesId: _operationId,
          plotId: _farmId,
          sowingDate: '2026-10-19',
          areaM2: '12.345',
        ),
        throwsFormatException,
      );
    });

    test('authors a versioned planting update with only mutable fields', () {
      final intent = FarmlyUpdatePlantingIntent(
        operationId: _operationId,
        continuityEpoch: _continuityEpoch,
        resourceId: '00000000-0000-4000-8000-000000000205',
        baseVersion: 12,
        status: 'completed',
        sowingDate: '2026-09-12',
        expectedHarvestDate: '2026-11-12',
        areaM2: '125.50',
      );

      expect(intent.type, 'planting.update');
      expect(intent.baseVersion, 12);
      expect(intent.payload, {
        'status': 'completed',
        'sowingDate': '2026-09-12',
        'expectedHarvestDate': '2026-11-12',
        'areaM2': '125.50',
      });
      expect(intent.payload, isNot(contains('cropSpeciesId')));
      expect(intent.payload, isNot(contains('plotId')));
      expect(
        () => FarmlyUpdatePlantingIntent(
          operationId: _operationId,
          continuityEpoch: _continuityEpoch,
          resourceId: '00000000-0000-4000-8000-000000000205',
          baseVersion: 0,
          areaM2: '125.50',
        ),
        throwsArgumentError,
      );
      expect(
        () => FarmlyUpdatePlantingIntent(
          operationId: _operationId,
          continuityEpoch: _continuityEpoch,
          resourceId: '00000000-0000-4000-8000-000000000205',
          baseVersion: 12,
        ),
        throwsArgumentError,
      );
      expect(
        () => FarmlyUpdatePlantingIntent(
          operationId: _operationId,
          continuityEpoch: _continuityEpoch,
          resourceId: '00000000-0000-4000-8000-000000000205',
          baseVersion: 12,
          status: 'archived',
        ),
        throwsArgumentError,
      );
      expect(
        () => FarmlyUpdatePlantingIntent(
          operationId: _operationId,
          continuityEpoch: _continuityEpoch,
          resourceId: '00000000-0000-4000-8000-000000000205',
          baseVersion: 12,
          sowingDate: '2026-02-29',
        ),
        throwsFormatException,
      );
      expect(
        () => FarmlyUpdatePlantingIntent(
          operationId: _operationId,
          continuityEpoch: _continuityEpoch,
          resourceId: '00000000-0000-4000-8000-000000000205',
          baseVersion: 12,
          expectedHarvestDate: 'not-a-date',
        ),
        throwsFormatException,
      );
      expect(
        () => FarmlyUpdatePlantingIntent(
          operationId: _operationId,
          continuityEpoch: _continuityEpoch,
          resourceId: '00000000-0000-4000-8000-000000000205',
          baseVersion: 12,
          areaM2: '12.345',
        ),
        throwsFormatException,
      );
    });

    test('restores planting.update as a strict mutable-field subset', () {
      for (final payload in <Map<String, Object?>>[
        {'status': 'active'},
        {'sowingDate': '2026-09-12'},
        {'expectedHarvestDate': '2026-11-12'},
        {'areaM2': '125.50'},
        {
          'status': 'completed',
          'sowingDate': '2026-09-12',
          'expectedHarvestDate': '2026-11-12',
          'areaM2': '125.50',
        },
      ]) {
        final json = {..._wireIntent('planting.update'), 'payload': payload};

        final restored = FarmlyMutationIntent.fromJson(json);

        expect(restored.type, 'planting.update');
        expect(restored.baseVersion, 1);
        expect(restored.payload, payload);
        expect(restored.toJson(), json);
      }
    });

    test('rejects malformed planting.update payloads and base versions', () {
      final invalid = <Map<String, Object?>>[
        {..._wireIntent('planting.update'), 'baseVersion': null},
        {..._wireIntent('planting.update'), 'baseVersion': 0},
        {..._wireIntent('planting.update'), 'baseVersion': 1.5},
        {..._wireIntent('planting.update'), 'payload': <String, Object?>{}},
        {
          ..._wireIntent('planting.update'),
          'payload': <String, Object?>{'status': 'archived'},
        },
        {
          ..._wireIntent('planting.update'),
          'payload': <String, Object?>{'status': 'unknown'},
        },
        {
          ..._wireIntent('planting.update'),
          'payload': <String, Object?>{'sowingDate': '2026-02-29'},
        },
        {
          ..._wireIntent('planting.update'),
          'payload': <String, Object?>{'expectedHarvestDate': 'not-a-date'},
        },
        {
          ..._wireIntent('planting.update'),
          'payload': <String, Object?>{'areaM2': '12.345'},
        },
        {
          ..._wireIntent('planting.update'),
          'payload': <String, Object?>{'areaM2': 125.5},
        },
        {
          ..._wireIntent('planting.update'),
          'payload': <String, Object?>{'cropSpeciesId': _farmId},
        },
        {
          ..._wireIntent('planting.update'),
          'payload': <String, Object?>{'plotId': _farmId},
        },
        {
          ..._wireIntent('planting.update'),
          'payload': <String, Object?>{'status': 'active', 'unknown': true},
        },
      ];

      for (final json in invalid) {
        expect(
          () => FarmlyMutationIntent.fromJson(json),
          throwsFormatException,
          reason: 'invalid durable planting.update should fail closed: $json',
        );
      }
    });

    test('authors a versioned planting archive with an empty payload', () {
      final intent = FarmlyArchivePlantingIntent(
        operationId: _operationId,
        continuityEpoch: _continuityEpoch,
        resourceId: '00000000-0000-4000-8000-000000000205',
        baseVersion: 12,
      );

      expect(intent.type, 'planting.archive');
      expect(intent.baseVersion, 12);
      expect(intent.payload, isEmpty);
      expect(intent.dependsOn, isEmpty);
      expect(
        () => FarmlyArchivePlantingIntent(
          operationId: _operationId,
          continuityEpoch: _continuityEpoch,
          resourceId: '00000000-0000-4000-8000-000000000205',
          baseVersion: 0,
        ),
        throwsArgumentError,
      );
    });

    test(
      'restores planting.archive only with positive CAS and empty payload',
      () {
        final json = {
          ..._wireIntent('planting.archive'),
          'baseVersion': 12,
          'payload': <String, Object?>{},
        };

        final restored = FarmlyMutationIntent.fromJson(json);

        expect(restored.type, 'planting.archive');
        expect(restored.baseVersion, 12);
        expect(restored.payload, isEmpty);
        expect(restored.toJson(), json);
      },
    );

    test('rejects malformed planting.archive payloads and base versions', () {
      final invalid = <Map<String, Object?>>[
        {..._wireIntent('planting.archive'), 'baseVersion': null},
        {..._wireIntent('planting.archive'), 'baseVersion': 0},
        {..._wireIntent('planting.archive'), 'baseVersion': 1.5},
        {
          ..._wireIntent('planting.archive'),
          'payload': <String, Object?>{'status': 'archived'},
        },
      ];

      for (final json in invalid) {
        expect(
          () => FarmlyMutationIntent.fromJson(json),
          throwsFormatException,
          reason: 'invalid durable planting.archive should fail closed: $json',
        );
      }
    });

    test('authors immutable herd and animal creation intents', () {
      const herdId = '00000000-0000-4000-8000-000000000321';
      const animalId = '00000000-0000-4000-8000-000000000322';
      const herdOperationId = '00000000-0000-4000-8000-000000000323';
      const animalOperationId = '00000000-0000-4000-8000-000000000324';
      final batch = FarmlyCreateHerdIntent(
        operationId: herdOperationId,
        continuityEpoch: _continuityEpoch,
        resourceId: herdId,
        mode: 'batch',
        species: '  Bò lai Sind  ',
      );
      final tracked = FarmlyCreateHerdIntent(
        operationId: _operationId,
        continuityEpoch: _continuityEpoch,
        resourceId: _farmId,
        mode: 'tracked',
        species: 'Bò sữa',
      );
      final animal = FarmlyCreateAnimalIntent(
        operationId: animalOperationId,
        continuityEpoch: _continuityEpoch,
        resourceId: animalId,
        herdId: _farmId,
        tag: '  COW-002  ',
        name: '  Mây  ',
        birthDate: '2024-02-29',
        dependsOn: const [herdOperationId],
      );

      expect(batch.type, 'herd.create');
      expect(batch.baseVersion, isNull);
      expect(batch.payload, {'mode': 'batch', 'species': 'Bò lai Sind'});
      expect(batch.payload, isNot(contains('headcount')));
      expect(batch.payload, isNot(contains('status')));
      expect(tracked.payload, {'mode': 'tracked', 'species': 'Bò sữa'});
      expect(animal.type, 'animal.create');
      expect(animal.baseVersion, isNull);
      expect(animal.dependsOn, [herdOperationId]);
      expect(animal.payload, {
        'herdId': _farmId,
        'tag': 'COW-002',
        'name': 'Mây',
        'birthDate': '2024-02-29',
      });
      expect(animal.payload, isNot(contains('status')));
      expect(() => batch.payload.clear(), throwsUnsupportedError);
      expect(() => animal.payload.clear(), throwsUnsupportedError);

      for (final intent in [batch, tracked, animal]) {
        final restored = FarmlyMutationIntent.fromJson(
          Map<String, Object?>.from(
            jsonDecode(jsonEncode(intent.toJson())) as Map,
          ),
        );
        expect(restored.toJson(), intent.toJson());
      }
    });

    test('animal tag normalization matches PostgreSQL btrim exactly', () {
      final create = FarmlyCreateAnimalIntent(
        operationId: _operationId,
        continuityEpoch: _continuityEpoch,
        resourceId: _animalId,
        herdId: _farmId,
        tag: '  COW-ASCII  ',
      );
      final update = FarmlyUpdateAnimalIntent(
        operationId: _operationId,
        continuityEpoch: _continuityEpoch,
        resourceId: _animalId,
        baseVersion: 1,
        tag: '\tCOW-TAB\t',
      );

      expect(create.payload['tag'], 'COW-ASCII');
      expect(update.payload['tag'], '\tCOW-TAB\t');
      expect(farmlyTrimAnimalTag('  cow-case  '), 'cow-case');
      expect(farmlyTrimAnimalTag('\t'), '\t');
    });

    test('rejects malformed herd and animal creation fields', () {
      FarmlyCreateHerdIntent herd({String mode = 'batch', String? species}) =>
          FarmlyCreateHerdIntent(
            operationId: _operationId,
            continuityEpoch: _continuityEpoch,
            resourceId: _farmId,
            mode: mode,
            species: species,
          );
      FarmlyCreateAnimalIntent animal({
        String herdId = _farmId,
        String tag = 'COW-001',
        String? name,
        String? birthDate,
      }) => FarmlyCreateAnimalIntent(
        operationId: _operationId,
        continuityEpoch: _continuityEpoch,
        resourceId: _farmId,
        herdId: herdId,
        tag: tag,
        name: name,
        birthDate: birthDate,
      );

      expect(() => herd(mode: 'individual'), throwsArgumentError);
      expect(() => herd(species: '  '), throwsArgumentError);
      expect(() => herd(species: 'b' * 121), throwsArgumentError);
      expect(() => animal(herdId: 'not-a-uuid'), throwsArgumentError);
      expect(() => animal(tag: '  '), throwsArgumentError);
      expect(() => animal(tag: 'T' * 65), throwsArgumentError);
      expect(() => animal(name: 'n' * 161), throwsArgumentError);
      expect(() => animal(birthDate: '2026-02-29'), throwsFormatException);
    });

    test('rejects malformed durable herd and animal creation payloads', () {
      Map<String, Object?> wireIntent(
        String type,
        Map<String, Object?> payload,
      ) => {..._wireIntent(type), 'payload': payload};

      FarmlyMutationIntent restore(String type, Map<String, Object?> payload) =>
          FarmlyMutationIntent.fromJson(wireIntent(type, payload));

      expect(() => restore('herd.create', const {}), throwsFormatException);
      expect(
        () => restore('herd.create', const {'mode': 'individual'}),
        throwsFormatException,
      );
      expect(
        () => restore('herd.create', const {'mode': 'batch', 'headcount': 8}),
        throwsFormatException,
        reason: 'initial headcount is a separate livestock movement fact',
      );
      expect(
        () => restore('animal.create', const {'tag': 'COW-001'}),
        throwsFormatException,
      );
      expect(
        () => restore('animal.create', {
          'herdId': 'not-a-uuid',
          'tag': 'COW-001',
        }),
        throwsFormatException,
      );
      expect(
        () => restore('animal.create', {'herdId': _farmId}),
        throwsFormatException,
      );
      expect(
        () => restore('animal.create', {'herdId': _farmId, 'tag': '  '}),
        throwsFormatException,
      );
    });

    test('rejects non-positive or over-precision harvest quantities', () {
      FarmlyCreateHarvestIntent createHarvest(String quantityKg) =>
          FarmlyCreateHarvestIntent(
            operationId: _operationId,
            continuityEpoch: _continuityEpoch,
            resourceId: _farmId,
            plantingId: _farmId,
            quantityKg: FarmlyDecimal.parse(quantityKg),
            harvestDate: '2026-10-19',
          );

      expect(() => createHarvest('0'), throwsFormatException);
      expect(() => createHarvest('0.0000'), throwsFormatException);
      expect(() => createHarvest('-1'), throwsFormatException);
      expect(() => createHarvest('1.23456'), throwsFormatException);
      expect(createHarvest('12.375').payload['quantityKg'], '12.375');
    });

    test(
      'authors herd and animal production records without derived units',
      () {
        const herdId = '00000000-0000-4000-8000-000000000301';
        const animalId = '00000000-0000-4000-8000-000000000302';
        final herdRecord = FarmlyCreateProductionRecordIntent(
          operationId: _operationId,
          continuityEpoch: _continuityEpoch,
          resourceId: _farmId,
          herdId: herdId,
          product: 'milk',
          quantity: '12.5',
          recordedOn: '2026-10-19',
        );
        final animalRecord = FarmlyCreateProductionRecordIntent(
          operationId: '00000000-0000-4000-8000-000000000303',
          continuityEpoch: _continuityEpoch,
          resourceId: _farmId,
          animalId: animalId,
          product: 'eggs',
          quantity: '6',
          recordedOn: '2026-10-18',
        );

        expect(herdRecord.type, 'productionRecord.create');
        expect(herdRecord.baseVersion, isNull);
        expect(herdRecord.payload, {
          'herdId': herdId,
          'product': 'milk',
          'quantity': '12.5',
          'recordedOn': '2026-10-19',
        });
        expect(animalRecord.type, 'productionRecord.create');
        expect(animalRecord.payload, {
          'animalId': animalId,
          'product': 'eggs',
          'quantity': '6',
          'recordedOn': '2026-10-18',
        });
        expect(herdRecord.payload, isNot(contains('unit')));
        expect(animalRecord.payload, isNot(contains('unit')));
      },
    );

    test(
      'rejects invalid production subjects, products, quantities, and dates',
      () {
        FarmlyCreateProductionRecordIntent createProduction({
          String? herdId,
          String? animalId,
          String product = 'milk',
          String quantity = '1',
          String recordedOn = '2026-10-19',
        }) => FarmlyCreateProductionRecordIntent(
          operationId: _operationId,
          continuityEpoch: _continuityEpoch,
          resourceId: _farmId,
          herdId: herdId,
          animalId: animalId,
          product: product,
          quantity: quantity,
          recordedOn: recordedOn,
        );

        const herdId = '00000000-0000-4000-8000-000000000311';
        const animalId = '00000000-0000-4000-8000-000000000312';
        expect(() => createProduction(), throwsArgumentError);
        expect(
          () => createProduction(herdId: herdId, animalId: animalId),
          throwsArgumentError,
        );
        expect(
          () => createProduction(herdId: herdId, product: 'wool'),
          throwsArgumentError,
        );
        expect(
          () => createProduction(herdId: herdId, quantity: '0'),
          throwsFormatException,
        );
        expect(
          () => createProduction(herdId: herdId, quantity: '-1'),
          throwsFormatException,
        );
        expect(
          () => createProduction(herdId: herdId, quantity: '1.23456'),
          throwsFormatException,
        );
        expect(
          () => createProduction(
            herdId: herdId,
            product: 'eggs',
            quantity: '1.5',
          ),
          throwsFormatException,
        );
        expect(
          () => createProduction(herdId: herdId, recordedOn: '2026-02-29'),
          throwsFormatException,
        );
      },
    );

    test('authors exact batch livestock movement payloads', () {
      FarmlyCreateLivestockMovementIntent movement({
        String movementType = 'stock_in',
        int delta = 1,
        String? occurredOn,
        List<String> dependsOn = const [],
      }) => FarmlyCreateLivestockMovementIntent(
        operationId: _operationId,
        continuityEpoch: _continuityEpoch,
        resourceId: _farmId,
        herdId: _farmId,
        movementType: movementType,
        delta: delta,
        occurredOn: occurredOn,
        dependsOn: dependsOn,
      );

      const dependencyId = '00000000-0000-4000-8000-000000000125';
      final dated = movement(
        movementType: 'stock_in',
        occurredOn: '2026-10-19',
        dependsOn: const [dependencyId],
      );
      final undated = movement(movementType: 'sold', delta: -2);

      expect(dated.type, 'livestockMovement.create');
      expect(dated.baseVersion, isNull);
      expect(dated.dependsOn, [dependencyId]);
      expect(dated.payload, {
        'herdId': _farmId,
        'movementType': 'stock_in',
        'delta': 1,
        'occurredOn': '2026-10-19',
      });
      expect(undated.payload, {
        'herdId': _farmId,
        'movementType': 'sold',
        'delta': -2,
      });
    });

    test('rejects invalid livestock movement types, deltas, and dates', () {
      FarmlyCreateLivestockMovementIntent movement({
        String movementType = 'stock_in',
        int delta = 1,
        String? occurredOn,
      }) => FarmlyCreateLivestockMovementIntent(
        operationId: _operationId,
        continuityEpoch: _continuityEpoch,
        resourceId: _farmId,
        herdId: _farmId,
        movementType: movementType,
        delta: delta,
        occurredOn: occurredOn,
      );

      expect(() => movement(movementType: ''), throwsArgumentError);
      expect(() => movement(movementType: 'x' * 41), throwsArgumentError);
      expect(() => movement(delta: 0), throwsArgumentError);
      expect(() => movement(delta: 2147483648), throwsArgumentError);
      expect(() => movement(delta: -2147483649), throwsArgumentError);
      expect(() => movement(occurredOn: '2026-02-29'), throwsFormatException);
    });

    test('authors herd and tracked-animal observation payloads', () {
      const herdId = '00000000-0000-4000-8000-000000000321';
      const animalId = '00000000-0000-4000-8000-000000000322';
      final herdObservation = FarmlyCreateAnimalObservationIntent(
        operationId: _operationId,
        continuityEpoch: _continuityEpoch,
        resourceId: _farmId,
        herdId: herdId,
        note: 'Routine health check',
        kind: 'vet',
        observedOn: '2026-10-19',
      );
      final animalObservation = FarmlyCreateAnimalObservationIntent(
        operationId: '00000000-0000-4000-8000-000000000323',
        continuityEpoch: _continuityEpoch,
        resourceId: '00000000-0000-4000-8000-000000000324',
        animalId: animalId,
        note: 'Mây is calm',
      );

      expect(herdObservation.type, 'animalObservation.create');
      expect(herdObservation.baseVersion, isNull);
      expect(herdObservation.payload, {
        'herdId': herdId,
        'note': 'Routine health check',
        'kind': 'vet',
        'observedOn': '2026-10-19',
      });
      expect(animalObservation.type, 'animalObservation.create');
      expect(animalObservation.payload, {
        'animalId': animalId,
        'note': 'Mây is calm',
      });
    });

    test(
      'rejects invalid animal observation subjects, notes, kinds, and dates',
      () {
        FarmlyCreateAnimalObservationIntent createObservation({
          String? herdId,
          String? animalId,
          String note = 'Routine observation',
          String? kind,
          String? observedOn,
        }) => FarmlyCreateAnimalObservationIntent(
          operationId: _operationId,
          continuityEpoch: _continuityEpoch,
          resourceId: _farmId,
          herdId: herdId,
          animalId: animalId,
          note: note,
          kind: kind,
          observedOn: observedOn,
        );

        const herdId = '00000000-0000-4000-8000-000000000331';
        const animalId = '00000000-0000-4000-8000-000000000332';
        expect(() => createObservation(), throwsArgumentError);
        expect(
          () => createObservation(herdId: herdId, animalId: animalId),
          throwsArgumentError,
        );
        expect(
          () => createObservation(herdId: herdId, note: ''),
          throwsArgumentError,
        );
        expect(
          () => createObservation(herdId: herdId, note: 'x' * 1001),
          throwsArgumentError,
        );
        expect(
          () => createObservation(herdId: herdId, kind: 'feeding'),
          throwsArgumentError,
        );
        expect(
          () => createObservation(herdId: herdId, observedOn: '2026-02-29'),
          throwsFormatException,
        );
      },
    );

    test('authors harvest correction and void intents against the head', () {
      const harvestId = '00000000-0000-4000-8000-000000000121';
      const proposalId = '00000000-0000-4000-8000-000000000122';
      const dependencyId = '00000000-0000-4000-8000-000000000123';
      final proposal = FarmlyProposeHarvestCorrectionIntent(
        operationId: '00000000-0000-4000-8000-000000000124',
        continuityEpoch: _continuityEpoch,
        resourceId: harvestId,
        proposedQuantityKg: FarmlyDecimal.parse('12.375'),
        reason: '  Reweighed after drying  ',
        dependsOn: [dependencyId],
      );
      final directCorrection = FarmlyApplyHarvestCorrectionIntent(
        operationId: '00000000-0000-4000-8000-000000000125',
        continuityEpoch: _continuityEpoch,
        resourceId: harvestId,
        baseVersion: 7,
        proposedQuantityKg: FarmlyDecimal.parse('12.5'),
      );
      final proposalCorrection = FarmlyApplyHarvestCorrectionIntent(
        operationId: '00000000-0000-4000-8000-000000000126',
        continuityEpoch: _continuityEpoch,
        resourceId: harvestId,
        baseVersion: 7,
        proposedQuantityKg: FarmlyDecimal.parse('12.625'),
        reason: '  Verified with the manager  ',
        proposalId: proposalId,
      );
      final voidIntent = FarmlyVoidHarvestIntent(
        operationId: '00000000-0000-4000-8000-000000000127',
        continuityEpoch: _continuityEpoch,
        resourceId: harvestId,
        baseVersion: 7,
        reason: '  Duplicate weigh ticket  ',
      );

      expect(proposal.type, 'harvest.correction.propose');
      expect(proposal.resourceId, harvestId);
      expect(proposal.baseVersion, isNull);
      expect(proposal.payload, {
        'proposedQuantityKg': '12.375',
        'reason': 'Reweighed after drying',
      });
      expect(proposal.dependsOn, [dependencyId]);

      expect(directCorrection.type, 'harvest.correction.apply');
      expect(directCorrection.resourceId, harvestId);
      expect(directCorrection.baseVersion, 7);
      expect(directCorrection.payload, {'proposedQuantityKg': '12.5'});

      expect(proposalCorrection.baseVersion, 7);
      expect(proposalCorrection.payload, {
        'proposedQuantityKg': '12.625',
        'reason': 'Verified with the manager',
        'proposalId': proposalId,
      });

      expect(voidIntent.type, 'harvest.void');
      expect(voidIntent.resourceId, harvestId);
      expect(voidIntent.baseVersion, 7);
      expect(voidIntent.payload, {'reason': 'Duplicate weigh ticket'});
    });

    test('apply correction rejects a dynamic null base version', () {
      final nullVersion = _dynamicNullVersion();

      expect(
        () => FarmlyApplyHarvestCorrectionIntent(
          operationId: _operationId,
          continuityEpoch: _continuityEpoch,
          resourceId: _farmId,
          baseVersion: nullVersion,
          proposedQuantityKg: FarmlyDecimal.parse('1'),
        ),
        throwsA(isA<TypeError>()),
      );
    });

    test('void rejects a dynamic null base version', () {
      final nullVersion = _dynamicNullVersion();

      expect(
        () => FarmlyVoidHarvestIntent(
          operationId: _operationId,
          continuityEpoch: _continuityEpoch,
          resourceId: _farmId,
          baseVersion: nullVersion,
          reason: 'Valid reason',
        ),
        throwsA(isA<TypeError>()),
      );
    });

    test('rejects invalid harvest correction and void authoring', () {
      FarmlyProposeHarvestCorrectionIntent proposal({
        String quantity = '1',
        String reason = 'Valid reason',
      }) => FarmlyProposeHarvestCorrectionIntent(
        operationId: _operationId,
        continuityEpoch: _continuityEpoch,
        resourceId: _farmId,
        proposedQuantityKg: FarmlyDecimal.parse(quantity),
        reason: reason,
      );
      FarmlyApplyHarvestCorrectionIntent correction({
        String quantity = '1',
        int version = 1,
      }) => FarmlyApplyHarvestCorrectionIntent(
        operationId: _operationId,
        continuityEpoch: _continuityEpoch,
        resourceId: _farmId,
        baseVersion: version,
        proposedQuantityKg: FarmlyDecimal.parse(quantity),
      );
      FarmlyVoidHarvestIntent voidHarvest({
        String reason = 'Valid reason',
        int version = 1,
      }) => FarmlyVoidHarvestIntent(
        operationId: _operationId,
        continuityEpoch: _continuityEpoch,
        resourceId: _farmId,
        baseVersion: version,
        reason: reason,
      );

      for (final invalidQuantity in ['0', '0.0000', '-1', '1.12345']) {
        expect(
          () => proposal(quantity: invalidQuantity),
          throwsFormatException,
          reason:
              'proposal quantity $invalidQuantity must be positive NUMERIC(20,4)',
        );
        expect(
          () => correction(quantity: invalidQuantity),
          throwsFormatException,
          reason:
              'correction quantity $invalidQuantity must be positive NUMERIC(20,4)',
        );
      }
      expect(() => proposal(reason: '  '), throwsArgumentError);
      expect(() => proposal(reason: 'x' * 501), throwsArgumentError);
      expect(() => voidHarvest(reason: '  '), throwsArgumentError);
      expect(() => voidHarvest(reason: 'x' * 501), throwsArgumentError);
      expect(() => correction(version: 0), throwsArgumentError);
      expect(() => voidHarvest(version: 0), throwsArgumentError);
    });

    test('authors bounded tank, reading, and usage payloads exactly', () {
      const parentOperationId = '00000000-0000-4000-8000-000000000102';
      const tankId = '00000000-0000-4000-8000-000000000103';
      final tank = FarmlyCreateWaterTankIntent(
        operationId: '00000000-0000-4000-8000-000000000104',
        continuityEpoch: _continuityEpoch,
        resourceId: tankId,
        name: '  Bồn phía đông  ',
        zoneId: _farmId,
        capacityLitres: '1000.0000',
        dependsOn: [parentOperationId],
      );
      final reading = FarmlyCreateWaterReadingIntent(
        operationId: '00000000-0000-4000-8000-000000000105',
        continuityEpoch: _continuityEpoch,
        resourceId: '00000000-0000-4000-8000-000000000106',
        tankId: tankId,
        storedLitres: '0',
        source: ' manual ',
        measuredAt: '2024-02-29T01:02:03.123+07:30',
        dependsOn: [parentOperationId],
      );
      final usage = FarmlyCreateWaterUsageIntent(
        operationId: '00000000-0000-4000-8000-000000000107',
        continuityEpoch: _continuityEpoch,
        resourceId: '00000000-0000-4000-8000-000000000108',
        tankId: tankId,
        usageLitres: '12.375',
        usageDate: '2026-10-19',
        note: '  Irrigation  ',
        dependsOn: [parentOperationId],
      );

      expect(tank.type, 'waterTank.create');
      expect(tank.payload, {
        'name': 'Bồn phía đông',
        'zoneId': _farmId,
        'capacityLitres': '1000.0000',
      });
      expect(tank.dependsOn, [parentOperationId]);
      expect(reading.type, 'waterReading.create');
      expect(reading.payload, {
        'tankId': tankId,
        'storedLitres': '0',
        'source': 'manual',
        'measuredAt': '2024-02-29T01:02:03.123+07:30',
      });
      expect(usage.type, 'waterUsage.create');
      expect(usage.payload, {
        'tankId': tankId,
        'usageLitres': '12.375',
        'usageDate': '2026-10-19',
        'note': 'Irrigation',
      });
    });

    test('rejects invalid water amounts, timestamps, dates, and notes', () {
      FarmlyCreateWaterTankIntent tank(String capacity) =>
          FarmlyCreateWaterTankIntent(
            operationId: _operationId,
            continuityEpoch: _continuityEpoch,
            resourceId: _farmId,
            name: 'Tank',
            zoneId: _farmId,
            capacityLitres: capacity,
          );
      FarmlyCreateWaterReadingIntent reading({
        String amount = '1',
        String source = 'manual',
        String? measuredAt,
      }) => FarmlyCreateWaterReadingIntent(
        operationId: _operationId,
        continuityEpoch: _continuityEpoch,
        resourceId: _farmId,
        tankId: _farmId,
        storedLitres: amount,
        source: source,
        measuredAt: measuredAt,
      );
      FarmlyCreateWaterUsageIntent usage({
        String amount = '1',
        String date = '2026-10-19',
        String? note,
      }) => FarmlyCreateWaterUsageIntent(
        operationId: _operationId,
        continuityEpoch: _continuityEpoch,
        resourceId: _farmId,
        tankId: _farmId,
        usageLitres: amount,
        usageDate: date,
        note: note,
      );

      expect(() => tank('0'), throwsFormatException);
      expect(() => tank('1.12345'), throwsFormatException);
      expect(() => reading(amount: '-1'), throwsFormatException);
      expect(() => reading(amount: '1.12345'), throwsFormatException);
      expect(() => reading(source: '  '), throwsArgumentError);
      expect(() => reading(measuredAt: '2026-10-19'), throwsFormatException);
      for (final invalidTimestamp in [
        '2026-02-30T00:00:00Z',
        '2026-02-29T00:00:00Z',
        '2026-10-19T24:00:00Z',
        '2026-10-19T01:02:03+24:00',
        '2026-10-19T01:02:03+07:60',
      ]) {
        expect(
          () => reading(measuredAt: invalidTimestamp),
          throwsFormatException,
          reason: 'must reject invalid RFC3339 timestamp $invalidTimestamp',
        );
      }
      expect(() => usage(amount: '0'), throwsFormatException);
      expect(() => usage(date: '2026-02-29'), throwsFormatException);
      expect(() => usage(note: 'x' * 201), throwsArgumentError);
    });

    test('authors a versioned water-tank name update', () {
      final intent = FarmlyUpdateWaterTankNameIntent(
        operationId: _operationId,
        continuityEpoch: _continuityEpoch,
        resourceId: _farmId,
        baseVersion: 9,
        name: '  Bồn phía đông  ',
      );

      expect(intent.type, 'waterTank.update');
      expect(intent.baseVersion, 9);
      expect(intent.payload, {'name': 'Bồn phía đông'});
      expect(
        () => FarmlyUpdateWaterTankNameIntent(
          operationId: _operationId,
          continuityEpoch: _continuityEpoch,
          resourceId: _farmId,
          baseVersion: 0,
          name: 'Bồn phía đông',
        ),
        throwsArgumentError,
      );
      expect(
        () => FarmlyUpdateWaterTankNameIntent(
          operationId: _operationId,
          continuityEpoch: _continuityEpoch,
          resourceId: _farmId,
          baseVersion: 9,
          name: '  ',
        ),
        throwsArgumentError,
      );
      expect(
        () => FarmlyUpdateWaterTankNameIntent(
          operationId: _operationId,
          continuityEpoch: _continuityEpoch,
          resourceId: _farmId,
          baseVersion: 9,
          name: 'x' * 161,
        ),
        throwsArgumentError,
      );
    });

    test('restores waterTank.update name and full-schema subsets', () {
      for (final payload in <Map<String, Object?>>[
        {'name': 'Bồn phía đông'},
        {'capacityLitres': '1200.5'},
        {'name': 'Bồn phía đông', 'capacityLitres': '1200.5'},
      ]) {
        final json = {..._wireIntent('waterTank.update'), 'payload': payload};

        final restored = FarmlyMutationIntent.fromJson(json);

        expect(restored.type, 'waterTank.update');
        expect(restored.baseVersion, 1);
        expect(restored.payload, payload);
        expect(restored.toJson(), json);
      }
    });

    test('rejects malformed waterTank.update payloads and base versions', () {
      final invalid = <Map<String, Object?>>[
        {..._wireIntent('waterTank.update'), 'baseVersion': null},
        {..._wireIntent('waterTank.update'), 'baseVersion': 0},
        {..._wireIntent('waterTank.update'), 'baseVersion': 1.5},
        {..._wireIntent('waterTank.update'), 'payload': <String, Object?>{}},
        {
          ..._wireIntent('waterTank.update'),
          'payload': <String, Object?>{'name': '  '},
        },
        {
          ..._wireIntent('waterTank.update'),
          'payload': <String, Object?>{
            'name': '${List<String>.filled(160, ' ').join()}T',
          },
        },
        {
          ..._wireIntent('waterTank.update'),
          'payload': <String, Object?>{'name': 42},
        },
        {
          ..._wireIntent('waterTank.update'),
          'payload': <String, Object?>{'capacityLitres': '0'},
        },
        {
          ..._wireIntent('waterTank.update'),
          'payload': <String, Object?>{'capacityLitres': '-1'},
        },
        {
          ..._wireIntent('waterTank.update'),
          'payload': <String, Object?>{'capacityLitres': '01.0'},
        },
        {
          ..._wireIntent('waterTank.update'),
          'payload': <String, Object?>{'capacityLitres': '1.12345'},
        },
        {
          ..._wireIntent('waterTank.update'),
          'payload': <String, Object?>{'capacityLitres': 1000},
        },
        {
          ..._wireIntent('waterTank.update'),
          'payload': <String, Object?>{'unsupported': true},
        },
      ];

      for (final json in invalid) {
        expect(
          () => FarmlyMutationIntent.fromJson(json),
          throwsFormatException,
          reason: 'invalid durable waterTank.update should fail closed: $json',
        );
      }
    });

    test('authors moisture readings with the strict offline contract', () {
      final intent = FarmlyCreateMoistureReadingIntent(
        operationId: _operationId,
        continuityEpoch: _continuityEpoch,
        resourceId: _farmId,
        zoneId: _farmId,
        value: '100.00',
        method: 'vwc_percent',
        measuredAt: '2026-10-20T00:00:00+07:00',
        nowUtc: DateTime.utc(2026, 10, 19, 17),
      );

      expect(intent.type, 'moistureReading.create');
      expect(intent.baseVersion, isNull);
      expect(intent.payload, {
        'zoneId': _farmId,
        'value': '100.00',
        'method': 'vwc_percent',
        'measuredAt': '2026-10-20T00:00:00+07:00',
      });
      expect(intent.payload, isNot(contains('source')));
    });

    test('rejects out-of-range or malformed moisture readings', () {
      FarmlyCreateMoistureReadingIntent reading({
        String value = '48.75',
        String method = 'relative_percent',
        String measuredAt = '2026-10-19T00:00:00Z',
        DateTime? nowUtc,
      }) => FarmlyCreateMoistureReadingIntent(
        operationId: _operationId,
        continuityEpoch: _continuityEpoch,
        resourceId: _farmId,
        zoneId: _farmId,
        value: value,
        method: method,
        measuredAt: measuredAt,
        nowUtc: nowUtc ?? DateTime.utc(2026, 10, 19),
      );

      for (final value in ['-1', '100.01', '101', '1.234', '01', '']) {
        expect(
          () => reading(value: value),
          throwsFormatException,
          reason: 'invalid moisture percent $value must be rejected',
        );
      }
      expect(() => reading(method: 'sensor'), throwsArgumentError);
      expect(
        () => reading(measuredAt: '1999-12-31T23:59:59Z'),
        throwsFormatException,
      );
      expect(
        () => reading(measuredAt: '2026-10-20T00:00:01Z'),
        throwsFormatException,
      );
      expect(
        () => reading(measuredAt: '2026-02-30T00:00:00Z'),
        throwsFormatException,
      );
      expect(
        () => reading(
          measuredAt: '2026-10-20T00:00:02Z',
          nowUtc: DateTime.utc(2026, 10, 19, 0, 0, 1),
        ),
        throwsFormatException,
        reason:
            'a measurement more than 24 hours ahead of the injected clock is rejected',
      );
    });

    test(
      'validates restored moisture payloads without reapplying clock skew',
      () {
        Map<String, Object?> restorePayload(Map<String, Object?> payload) => {
          ..._wireIntent('moistureReading.create'),
          'payload': payload,
        };

        final payload = {
          'zoneId': _farmId,
          'value': '12.5',
          'method': 'relative_percent',
          'measuredAt': '2000-01-01T00:00:00Z',
        };
        final restored = FarmlyMutationIntent.fromJson(restorePayload(payload));
        expect(restored.payload, payload);

        expect(
          () => FarmlyMutationIntent.fromJson(
            restorePayload({...payload, 'source': 'manual'}),
          ),
          throwsFormatException,
          reason:
              'the server derives source and it is not an allowed request key',
        );
        expect(
          () => FarmlyMutationIntent.fromJson(
            restorePayload({...payload, 'value': 100.01}),
          ),
          throwsFormatException,
        );
        expect(
          () => FarmlyMutationIntent.fromJson(
            restorePayload({...payload, 'measuredAt': '1999-12-31T23:59:59Z'}),
          ),
          throwsFormatException,
        );
      },
    );

    test('rejects organization and farm scope mismatches after restore', () {
      final organizationScope = FarmlyMutationScope.organization(
        accountId: _accountId,
        organizationId: _organizationId,
        continuityEpoch: _continuityEpoch,
      );
      final farmScope = FarmlyMutationScope.farm(
        accountId: _accountId,
        organizationId: _organizationId,
        farmId: _farmId,
        continuityEpoch: _continuityEpoch,
      );
      final otherFarmScope = FarmlyMutationScope.farm(
        accountId: _accountId,
        organizationId: _organizationId,
        farmId: '00000000-0000-4000-8000-000000000777',
        continuityEpoch: _continuityEpoch,
      );
      final farmCreate = FarmlyMutationIntent.fromJson(
        _wireIntent('farm.create'),
      );
      final farmUpdate = FarmlyMutationIntent.fromJson(
        _wireIntent('farm.update'),
      );

      expect(
        () => FarmlyScopedMutation(scope: farmScope, intent: farmCreate),
        throwsArgumentError,
      );
      expect(
        () =>
            FarmlyScopedMutation(scope: organizationScope, intent: farmUpdate),
        throwsArgumentError,
      );
      expect(
        () => FarmlyScopedMutation(scope: otherFarmScope, intent: farmUpdate),
        throwsArgumentError,
      );
    });

    test('authors planting events with the typed offline contract', () {
      const parentOperationId = '00000000-0000-4000-8000-000000000102';
      const eventResourceId = '00000000-0000-4000-8000-000000000103';
      final event = FarmlyCreatePlantingEventIntent(
        operationId: _operationId,
        continuityEpoch: _continuityEpoch,
        resourceId: eventResourceId,
        plantingId: _farmId,
        eventType: '  watering  ',
        note: '  Watered this morning.  ',
        occurredOn: '2026-10-19',
        dependsOn: const [parentOperationId],
      );

      expect(event.type, 'plantingEvent.create');
      expect(event.baseVersion, isNull);
      expect(event.dependsOn, [parentOperationId]);
      expect(event.payload, {
        'plantingId': _farmId,
        'eventType': 'watering',
        'note': 'Watered this morning.',
        'occurredOn': '2026-10-19',
      });
    });

    test('rejects invalid planting event type, note, date, and parent', () {
      FarmlyCreatePlantingEventIntent event({
        String plantingId = _farmId,
        String eventType = 'watering',
        String? note,
        String? occurredOn,
      }) => FarmlyCreatePlantingEventIntent(
        operationId: _operationId,
        continuityEpoch: _continuityEpoch,
        resourceId: _operationId,
        plantingId: plantingId,
        eventType: eventType,
        note: note,
        occurredOn: occurredOn,
      );

      expect(() => event(eventType: ' '), throwsArgumentError);
      expect(() => event(eventType: 'e' * 41), throwsArgumentError);
      expect(() => event(note: 'n' * 501), throwsArgumentError);
      expect(() => event(occurredOn: '2026-02-30'), throwsFormatException);
      expect(() => event(plantingId: 'not-a-uuid'), throwsArgumentError);
    });
  });
}
