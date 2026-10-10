import 'package:flutter_test/flutter_test.dart';

import 'package:farmly_mobile/generated/farmly_api_types.dart';

void main() {
  test('scoped policy versions round-trip exact positive decimal strings', () {
    const value = '9223372036854775807';
    const asOf = '2026-10-06T00:00:00Z';
    const organizationId = '00000000-0000-4000-8000-000000000011';
    const farmId = '00000000-0000-4000-8000-000000000012';

    final responseMeta = FarmlyResponseMeta.fromJson({
      'schemaVersion': 'farmly.v1',
      'asOf': asOf,
      'scopePolicyVersion': value,
    });
    expect(responseMeta.scopePolicyVersion, value);
    expect(responseMeta.toJson()['scopePolicyVersion'], value);

    final rosterMeta = FarmlyOrganizationMembershipListMeta.fromJson({
      'schemaVersion': 'farmly.v1',
      'asOf': asOf,
      'scopePolicyVersion': value,
    });
    expect(rosterMeta.scopePolicyVersion, value);
    expect(rosterMeta.toJson()['scopePolicyVersion'], value);

    final scope = FarmlyFarmScope.fromJson({
      'organizationId': organizationId,
      'farmId': farmId,
      'continuityEpoch': '7',
      'scopePolicyVersion': value,
    });
    expect(scope.scopePolicyVersion, value);
    expect(scope.toJson()['scopePolicyVersion'], value);

    final directory = FarmlyFarmDirectoryManifest.fromJson({
      'schemaVersion': 'farm-directory.v1',
      'scopePolicyVersion': value,
      'continuityEpoch': '7',
      'farms': <dynamic>[],
    });
    expect(directory.scopePolicyVersion, value);
    expect(directory.toJson()['scopePolicyVersion'], value);
    expect(
      () => FarmlyFarmDirectoryManifest.fromJson({
        'schemaVersion': 'farm-directory.v1',
        'scopePolicyVersion': 9007199254740993,
        'continuityEpoch': '7',
        'farms': <dynamic>[],
      }),
      throwsA(isA<TypeError>()),
    );
  });

  group('FarmlyDecimal', () {
    test('preserves exact base-10 text beyond IEEE-754 precision', () {
      const value = '9007199254740993.1250';

      expect(FarmlyDecimal.parse(value).value, value);
      expect(() => FarmlyDecimal.parse('01.25'), throwsFormatException);
      expect(() => FarmlyDecimal.parse('1e3'), throwsFormatException);
    });

    test(
      'generated harvest DTO round-trips decimal text without conversion',
      () {
        final input = <String, dynamic>{
          'id': '00000000-0000-4000-8000-000000000001',
          'version': 2,
          'quantityKg': '9007199254740993.1250',
          'harvestDate': '2026-10-05',
          'occurredAt': '2026-10-05T08:00:00Z',
        };

        final dto = FarmlyHarvestDto.fromJson(input);

        expect(dto.quantityKg.value, '9007199254740993.1250');
        expect(dto.toJson(), input);
        expect(
          () => FarmlyHarvestDto.fromJson({...input, 'quantityKg': 12.375}),
          throwsA(isA<TypeError>()),
        );
      },
    );
  });

  test('optional DTO fields remain omitted on serialization', () {
    final tank = FarmlyWaterTankDto(
      id: '00000000-0000-4000-8000-000000000002',
      version: 1,
      name: 'North tank',
      zoneId: '00000000-0000-4000-8000-000000000007',
      capacityLitres: FarmlyDecimal.parse('10000.00'),
      status: 'active',
    );

    expect(tank.toJson(), {
      'id': '00000000-0000-4000-8000-000000000002',
      'version': 1,
      'name': 'North tank',
      'zoneId': '00000000-0000-4000-8000-000000000007',
      'capacityLitres': '10000.00',
      'status': 'active',
    });
  });

  test(
    'sanitized structured API error can round-trip without optional field errors',
    () {
      final input = <String, dynamic>{
        'error': {
          'code': 'VERSION_CONFLICT',
          'message': 'The record changed on the server.',
          'retryable': false,
          'requestId': '00000000-0000-4000-8000-000000000003',
        },
      };

      expect(FarmlyErrorEnvelope.fromJson(input).toJson(), input);
    },
  );
}
