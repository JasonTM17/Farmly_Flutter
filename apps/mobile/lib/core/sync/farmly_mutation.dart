import '../../generated/farmly_api_types.dart';

enum FarmlyMutationScopeKind { organization, farm }

/// IANA identifiers exposed by the farm-creation selector. Keeping this list
/// explicit prevents a typo from becoming durable farm data that PostgreSQL
/// cannot resolve later with `AT TIME ZONE`.
const farmlySupportedTimeZones = <String>[
  'Asia/Ho_Chi_Minh',
  'Asia/Bangkok',
  'Asia/Phnom_Penh',
  'Asia/Vientiane',
  'Asia/Jakarta',
  'Asia/Kuala_Lumpur',
  'Asia/Manila',
  'Asia/Singapore',
  'Asia/Yangon',
  'Asia/Dhaka',
  'Asia/Kathmandu',
  'Asia/Kolkata',
  'Asia/Dubai',
  'Asia/Hong_Kong',
  'Asia/Shanghai',
  'Asia/Taipei',
  'Asia/Seoul',
  'Asia/Tokyo',
  'Australia/Perth',
  'Australia/Brisbane',
  'Australia/Adelaide',
  'Australia/Sydney',
  'Pacific/Auckland',
  'Pacific/Honolulu',
  'Etc/UTC',
  'Europe/London',
  'Europe/Berlin',
  'Europe/Paris',
  'Europe/Moscow',
  'America/New_York',
  'America/Chicago',
  'America/Denver',
  'America/Los_Angeles',
  'America/Toronto',
  'America/Vancouver',
  'America/Sao_Paulo',
  'Africa/Cairo',
  'Africa/Johannesburg',
];

final class FarmlyMutationScope {
  FarmlyMutationScope.organization({
    required String accountId,
    required String organizationId,
    required String continuityEpoch,
  }) : this._(
         accountId: accountId,
         organizationId: organizationId,
         farmId: null,
         continuityEpoch: continuityEpoch,
         kind: FarmlyMutationScopeKind.organization,
       );

  FarmlyMutationScope.farm({
    required String accountId,
    required String organizationId,
    required String farmId,
    required String continuityEpoch,
  }) : this._(
         accountId: accountId,
         organizationId: organizationId,
         farmId: farmId,
         continuityEpoch: continuityEpoch,
         kind: FarmlyMutationScopeKind.farm,
       );

  FarmlyMutationScope._({
    required this.accountId,
    required this.organizationId,
    required this.farmId,
    required this.continuityEpoch,
    required this.kind,
  }) {
    _requireUuid('accountId', accountId);
    _requireUuid('organizationId', organizationId);
    if (farmId != null) _requireUuid('farmId', farmId!);
    _requireNonEmpty('continuityEpoch', continuityEpoch);
  }

  final String accountId;
  final String organizationId;
  final String? farmId;
  final String continuityEpoch;
  final FarmlyMutationScopeKind kind;
}

sealed class FarmlyMutationIntent {
  FarmlyMutationIntent._({
    required this.operationId,
    required this.continuityEpoch,
    required this.type,
    required this.resourceId,
    required this.baseVersion,
    required List<String> dependsOn,
    required Map<String, Object?> payload,
  }) : dependsOn = List.unmodifiable(dependsOn),
       payload = Map.unmodifiable(payload) {
    _requireUuid('operationId', operationId);
    _requireNonEmpty('continuityEpoch', continuityEpoch);
    _requireResourceUuid('resourceId', resourceId);
    if (baseVersion != null && baseVersion! < 1) {
      throw ArgumentError.value(
        baseVersion,
        'baseVersion',
        'must be positive or null',
      );
    }
    if (dependsOn.length > 50) {
      throw ArgumentError.value(
        dependsOn.length,
        'dependsOn',
        'must contain at most 50 operation IDs',
      );
    }
    for (final dependency in dependsOn) {
      _requireUuid('dependsOn item', dependency);
    }
    if (dependsOn.toSet().length != dependsOn.length) {
      throw ArgumentError.value(
        dependsOn,
        'dependsOn',
        'must not contain duplicate operation IDs',
      );
    }
  }

  static const schemaVersion = 'farm-mutation.v1';

  final String operationId;
  final String continuityEpoch;
  final String type;
  final String resourceId;
  final int? baseVersion;
  final List<String> dependsOn;
  final Map<String, Object?> payload;

  FarmlyJsonMap toJson() => Map.unmodifiable({
    'schemaVersion': schemaVersion,
    'continuityEpoch': continuityEpoch,
    'operationId': operationId,
    'type': type,
    'resourceId': resourceId,
    'baseVersion': baseVersion,
    'dependsOn': dependsOn,
    'payload': payload,
  });

  /// Rebuilds an immutable intent from its canonical request JSON (durable
  /// outbox round-trip). Validation rules still apply — hand-edited bytes are
  /// rejected before they reach the wire.
  factory FarmlyMutationIntent.fromJson(Map<String, Object?> json) {
    if (json['schemaVersion'] != schemaVersion) {
      throw const FormatException('Unsupported Farmly mutation schema');
    }
    String requireString(String field) {
      final value = json[field];
      if (value is! String) {
        throw FormatException('Farmly mutation field $field is invalid');
      }
      return value;
    }

    final type = requireString('type');
    if (!farmlyMutationTypes.contains(type)) {
      throw const FormatException('Unsupported Farmly mutation type');
    }

    final operationId = requireString('operationId');
    final continuityEpoch = requireString('continuityEpoch');
    final resourceId = requireString('resourceId');
    final payload = Map<String, Object?>.from(json['payload'] as Map);
    final rawBaseVersion = json['baseVersion'];
    if ((type == 'farm.update' ||
            type == 'zone.update' ||
            type == 'cropSpecies.update' ||
            type == 'cropSpecies.archive' ||
            type == 'waterTank.update' ||
            type == 'planting.update' ||
            type == 'planting.archive') &&
        (rawBaseVersion is! int || rawBaseVersion < 1)) {
      throw FormatException('Invalid Farmly $type base version');
    }
    _validateRestoredPayload(type, payload);

    return _WireMutationIntent(
      operationId: operationId,
      continuityEpoch: continuityEpoch,
      type: type,
      resourceId: resourceId,
      baseVersion: (json['baseVersion'] as num?)?.toInt(),
      dependsOn: [
        for (final dep in (json['dependsOn'] as List? ?? const []))
          dep as String,
      ],
      payload: payload,
    );
  }
}

/// Generic immutable intent reconstructed from durable bytes. Typed
/// subclasses are authoring-time helpers; the outbox round-trips the
/// canonical wire shape so every allowlisted type survives a cold start.
final class _WireMutationIntent extends FarmlyMutationIntent {
  _WireMutationIntent({
    required super.operationId,
    required super.continuityEpoch,
    required super.type,
    required super.resourceId,
    required super.baseVersion,
    required super.dependsOn,
    required super.payload,
  }) : super._();
}

void _validateRestoredPayload(String type, Map<String, Object?> payload) {
  switch (type) {
    case 'farm.update':
      _requirePayloadKeys(
        payload,
        required: const {},
        allowed: const {'name', 'timezone', 'areaM2', 'location'},
      );
      if (payload.isEmpty) {
        throw const FormatException('Invalid Farmly farm.update payload');
      }

      if (payload.containsKey('name')) {
        final name = _requiredPayloadString(payload, 'name');
        if (name.length > 160) {
          throw const FormatException('Invalid Farmly farm.update payload');
        }
        _validateCreatePayload(
          () => FarmlyUpdateFarmNameIntent._namePayload(name),
        );
      }

      if (payload.containsKey('timezone')) {
        final timezone = _requiredPayloadString(payload, 'timezone');
        _validateCreatePayload(
          () => _requireLength('timezone', timezone, max: 64),
        );
      }

      if (payload.containsKey('areaM2')) {
        final areaM2 = _requiredPayloadString(payload, 'areaM2');
        _validateCreatePayload(() => _requireAreaM2(areaM2));
      }

      if (payload.containsKey('location')) {
        final location = payload['location'];
        if (location != null &&
            (location is! String || !_isCoarseWeatherGrid(location))) {
          throw const FormatException('Invalid Farmly farm.update payload');
        }
      }
    case 'zone.update':
      _requirePayloadKeys(
        payload,
        required: const {},
        allowed: const {'name', 'type', 'geometry', 'areaM2'},
      );
      if (payload.isEmpty) {
        throw const FormatException('Invalid Farmly zone.update payload');
      }
      final restoredName = payload.containsKey('name')
          ? _requiredPayloadString(payload, 'name')
          : null;
      if (restoredName != null && restoredName.length > 160) {
        throw const FormatException('Invalid Farmly zone.update payload');
      }
      final restoredGeometry = payload.containsKey('geometry')
          ? _restoredZoneGeometry(payload['geometry'])
          : _defaultZoneGeometry;
      _validateCreatePayload(
        () => FarmlyCreateZoneIntent._zonePayload(
          restoredName ?? 'Zone',
          payload.containsKey('type')
              ? _requiredPayloadString(payload, 'type')
              : 'other',
          restoredGeometry,
          payload.containsKey('areaM2')
              ? _requiredPayloadString(payload, 'areaM2')
              : null,
        ),
      );
    case 'cropSpecies.update':
      _requirePayloadKeys(
        payload,
        required: const {},
        allowed: const {'name', 'harvestUnit'},
      );
      if (payload.isEmpty) {
        throw const FormatException(
          'Invalid Farmly cropSpecies.update payload',
        );
      }
      final restoredName = payload.containsKey('name')
          ? _requiredPayloadString(payload, 'name')
          : null;
      if (restoredName != null && restoredName.length > 160) {
        throw const FormatException(
          'Invalid Farmly cropSpecies.update payload',
        );
      }
      _validateCreatePayload(
        () => _cropSpeciesUpdatePayload(
          name: restoredName,
          harvestUnit: payload.containsKey('harvestUnit')
              ? _requiredPayloadString(payload, 'harvestUnit')
              : null,
        ),
      );
    case 'cropSpecies.archive':
      _requirePayloadKeys(payload, required: const {}, allowed: const {});
    case 'waterTank.update':
      _requirePayloadKeys(
        payload,
        required: const {},
        allowed: const {'name', 'capacityLitres'},
      );
      if (payload.isEmpty) {
        throw const FormatException('Invalid Farmly waterTank.update payload');
      }
      final restoredName = payload.containsKey('name')
          ? _requiredPayloadString(payload, 'name')
          : null;
      if (restoredName != null && restoredName.length > 160) {
        throw const FormatException('Invalid Farmly waterTank.update payload');
      }
      _validateCreatePayload(
        () => FarmlyUpdateWaterTankNameIntent._payload(
          name: restoredName,
          capacityLitres: payload.containsKey('capacityLitres')
              ? _requiredPayloadString(payload, 'capacityLitres')
              : null,
        ),
      );
    case 'planting.update':
      _requirePayloadKeys(
        payload,
        required: const {},
        allowed: const {
          'status',
          'sowingDate',
          'expectedHarvestDate',
          'areaM2',
        },
      );
      if (payload.isEmpty) {
        throw const FormatException('Invalid Farmly planting.update payload');
      }
      _validateCreatePayload(
        () => FarmlyUpdatePlantingIntent._payload(
          status: _optionalPayloadString(payload, 'status'),
          sowingDate: _optionalPayloadString(payload, 'sowingDate'),
          expectedHarvestDate: _optionalPayloadString(
            payload,
            'expectedHarvestDate',
          ),
          areaM2: _optionalPayloadString(payload, 'areaM2'),
        ),
      );
    case 'planting.archive':
      _requirePayloadKeys(payload, required: const {}, allowed: const {});
    case 'herd.create':
      _requirePayloadKeys(
        payload,
        required: const {'mode'},
        allowed: const {'mode', 'species', 'status'},
      );
      _validateCreatePayload(() {
        FarmlyCreateHerdIntent._herdPayload(
          mode: _requiredPayloadString(payload, 'mode'),
          species: _optionalPayloadString(payload, 'species'),
          status: _optionalPayloadString(payload, 'status'),
        );
      });
    case 'animal.create':
      _requirePayloadKeys(
        payload,
        required: const {'herdId', 'tag'},
        allowed: const {'herdId', 'tag', 'name', 'birthDate', 'status'},
      );
      _validateCreatePayload(() {
        FarmlyCreateAnimalIntent._animalPayload(
          herdId: _requiredPayloadString(payload, 'herdId'),
          tag: _requiredPayloadString(payload, 'tag'),
          name: _optionalPayloadString(payload, 'name'),
          birthDate: _optionalPayloadString(payload, 'birthDate'),
          status: _optionalPayloadString(payload, 'status'),
        );
      });
    case 'moistureReading.create':
      _requirePayloadKeys(
        payload,
        required: const {'zoneId', 'value', 'method', 'measuredAt'},
        allowed: const {'zoneId', 'value', 'method', 'measuredAt'},
      );
      _validateCreatePayload(() {
        FarmlyCreateMoistureReadingIntent.validatePayload(
          zoneId: _requiredPayloadString(payload, 'zoneId'),
          value: _requiredPayloadString(payload, 'value'),
          method: _requiredPayloadString(payload, 'method'),
          measuredAt: _requiredPayloadString(payload, 'measuredAt'),
        );
      });
  }
}

void _validateCreatePayload(void Function() validate) {
  try {
    validate();
  } on FormatException {
    rethrow;
  } on ArgumentError {
    throw const FormatException('Invalid Farmly create mutation payload');
  }
}

void _requirePayloadKeys(
  Map<String, Object?> payload, {
  required Set<String> required,
  required Set<String> allowed,
}) {
  final keys = payload.keys.toSet();
  if (!keys.containsAll(required) || !allowed.containsAll(keys)) {
    throw const FormatException('Invalid Farmly create mutation payload');
  }
}

String _requiredPayloadString(Map<String, Object?> payload, String key) {
  final value = payload[key];
  if (value is! String) {
    throw const FormatException('Invalid Farmly create mutation payload');
  }
  return value;
}

String? _optionalPayloadString(Map<String, Object?> payload, String key) {
  if (!payload.containsKey(key)) return null;
  final value = payload[key];
  if (value is! String) {
    throw const FormatException('Invalid Farmly create mutation payload');
  }
  return value;
}

const _defaultZoneGeometry = <Map<String, String>>[
  {'x': '0', 'y': '0'},
  {'x': '1', 'y': '0'},
  {'x': '0', 'y': '1'},
];

List<Map<String, String>> _restoredZoneGeometry(Object? rawGeometry) {
  if (rawGeometry is! Map) {
    throw const FormatException('Invalid Farmly zone.update geometry');
  }
  final geometry = Map<String, Object?>.from(rawGeometry);
  _requirePayloadKeys(
    geometry,
    required: const {'points'},
    allowed: const {'points'},
  );
  final points = geometry['points'];
  if (points is! List) {
    throw const FormatException('Invalid Farmly zone.update geometry');
  }
  return [
    for (final rawPoint in points)
      if (rawPoint is Map)
        _restoredZonePoint(Map<String, Object?>.from(rawPoint))
      else
        throw const FormatException('Invalid Farmly zone.update geometry'),
  ];
}

Map<String, String> _restoredZonePoint(Map<String, Object?> point) {
  _requirePayloadKeys(
    point,
    required: const {'x', 'y'},
    allowed: const {'x', 'y'},
  );
  return {
    'x': _requiredPayloadString(point, 'x'),
    'y': _requiredPayloadString(point, 'y'),
  };
}

final class FarmlyCreateHerdIntent extends FarmlyMutationIntent {
  FarmlyCreateHerdIntent({
    required super.operationId,
    required super.continuityEpoch,
    required super.resourceId,
    required String mode,
    String? species,
    String? status,
    super.dependsOn = const [],
  }) : super._(
         type: 'herd.create',
         baseVersion: null,
         payload: _herdPayload(mode: mode, species: species, status: status),
       );

  static Map<String, Object?> _herdPayload({
    required String mode,
    required String? species,
    required String? status,
  }) {
    if (!const {'batch', 'tracked'}.contains(mode)) {
      throw ArgumentError.value(mode, 'mode', 'is not a supported herd mode');
    }
    if (status != null && !const {'active', 'archived'}.contains(status)) {
      throw ArgumentError.value(status, 'status', 'is not a herd status');
    }
    final normalizedSpecies = species?.trim();
    if (normalizedSpecies != null) {
      _requireLength('species', normalizedSpecies, max: 120);
    }
    return {'mode': mode, 'species': ?normalizedSpecies, 'status': ?status};
  }
}

final class FarmlyCreateAnimalIntent extends FarmlyMutationIntent {
  FarmlyCreateAnimalIntent({
    required super.operationId,
    required super.continuityEpoch,
    required super.resourceId,
    required String herdId,
    required String tag,
    String? name,
    String? birthDate,
    String? status,
    super.dependsOn = const [],
  }) : super._(
         type: 'animal.create',
         baseVersion: null,
         payload: _animalPayload(
           herdId: herdId,
           tag: tag,
           name: name,
           birthDate: birthDate,
           status: status,
         ),
       );

  static Map<String, Object?> _animalPayload({
    required String herdId,
    required String tag,
    required String? name,
    required String? birthDate,
    required String? status,
  }) {
    _requireUuid('herdId', herdId);
    final normalizedTag = tag.trim();
    _requireLength('tag', normalizedTag, max: 64);
    final normalizedName = name?.trim();
    if (normalizedName != null) {
      _requireLength('name', normalizedName, max: 160);
    }
    if (status != null &&
        !const {'alive', 'sold', 'deceased'}.contains(status)) {
      throw ArgumentError.value(status, 'status', 'is not an animal status');
    }
    return {
      'herdId': herdId,
      'tag': normalizedTag,
      'name': ?normalizedName,
      'birthDate': ?(birthDate == null
          ? null
          : _requireCivilDate('birthDate', birthDate)),
      'status': ?status,
    };
  }
}

final class FarmlyCreateFarmIntent extends FarmlyMutationIntent {
  FarmlyCreateFarmIntent({
    required super.operationId,
    required super.continuityEpoch,
    required super.resourceId,
    required String name,
    required String timezone,
    String? areaM2,
    super.dependsOn = const [],
  }) : super._(
         type: 'farm.create',
         baseVersion: null,
         payload: _farmPayload(name, timezone, areaM2),
       );

  static Map<String, Object?> _farmPayload(
    String name,
    String timezone,
    String? areaM2,
  ) {
    _requireLength('name', name, max: 160);
    _requireLength('timezone', timezone, max: 64);
    if (!farmlySupportedTimeZones.contains(timezone)) {
      throw const FormatException('Unsupported Farmly IANA time zone');
    }
    if (areaM2 != null) _requireAreaM2(areaM2);
    return {'name': name, 'timezone': timezone, ...?_optionalAreaEntry(areaM2)};
  }
}

/// Updates the selected farm's name using the confirmed farm row version.
/// The organization policy version is not a resource CAS token.
final class FarmlyUpdateFarmNameIntent extends FarmlyMutationIntent {
  FarmlyUpdateFarmNameIntent({
    required super.operationId,
    required super.continuityEpoch,
    required super.resourceId,
    required int baseVersion,
    required String name,
  }) : super._(
         type: 'farm.update',
         baseVersion: baseVersion,
         dependsOn: const [],
         payload: _namePayload(name),
       );

  static Map<String, Object?> _namePayload(String name) {
    final normalizedName = name.trim();
    _requireLength('name', normalizedName, max: 160);
    return {'name': normalizedName};
  }
}

/// A first child zone may be queued beside a provisional farm. Its dependency
/// keeps it behind the org-scoped farm.create until directory admission.
final class FarmlyCreateZoneIntent extends FarmlyMutationIntent {
  FarmlyCreateZoneIntent({
    required super.operationId,
    required super.continuityEpoch,
    required super.resourceId,
    required String name,
    required String type,
    required List<Map<String, String>> geometry,
    String? areaM2,
    super.dependsOn = const [],
  }) : super._(
         type: 'zone.create',
         baseVersion: null,
         payload: _zonePayload(name, type, geometry, areaM2),
       );

  static Map<String, Object?> _zonePayload(
    String name,
    String type,
    List<Map<String, String>> geometry,
    String? areaM2,
  ) {
    _requireLength('name', name, max: 160);
    const allowedTypes = {
      'house',
      'crop_plot',
      'livestock_area',
      'water',
      'storage',
      'other',
    };
    if (!allowedTypes.contains(type)) {
      throw ArgumentError.value(type, 'type', 'is not a supported zone type');
    }
    if (geometry.length < 3 || geometry.length > 128) {
      throw ArgumentError.value(
        geometry.length,
        'geometry',
        'must contain between 3 and 128 points',
      );
    }
    final points = <FarmlyZonePoint>[];
    for (final point in geometry) {
      if (point.length != 2 ||
          !point.keys.toSet().containsAll(const {'x', 'y'})) {
        throw const FormatException('Invalid Farmly zone point');
      }
      final x = point['x'];
      final y = point['y'];
      if (x == null ||
          y == null ||
          !_isUnitInterval(x) ||
          !_isUnitInterval(y)) {
        throw const FormatException('Invalid Farmly zone point');
      }
      points.add(
        FarmlyZonePoint(x: FarmlyDecimal.parse(x), y: FarmlyDecimal.parse(y)),
      );
    }
    if (areaM2 != null) _requireAreaM2(areaM2);
    final encodedGeometry = FarmlyZoneGeometry(
      points: List.unmodifiable(points),
    ).toJson();
    final encodedPoints = (encodedGeometry['points'] as List<dynamic>)
        .map(
          (point) => Map<String, String>.unmodifiable(
            Map<String, String>.from(point as Map),
          ),
        )
        .toList(growable: false);
    return {
      'name': name,
      'type': type,
      'geometry': Map<String, Object?>.unmodifiable({
        'points': List<Map<String, String>>.unmodifiable(encodedPoints),
      }),
      ...?_optionalAreaEntry(areaM2),
    };
  }
}

/// Renames an active farm zone using its confirmed row version.
final class FarmlyUpdateZoneNameIntent extends FarmlyMutationIntent {
  FarmlyUpdateZoneNameIntent({
    required super.operationId,
    required super.continuityEpoch,
    required super.resourceId,
    required int baseVersion,
    required String name,
  }) : super._(
         type: 'zone.update',
         baseVersion: baseVersion,
         dependsOn: const [],
         payload: _namePayload(name),
       );

  static Map<String, Object?> _namePayload(String name) {
    final normalizedName = name.trim();
    _requireLength('name', normalizedName, max: 160);
    return {'name': normalizedName};
  }
}

/// Crop species are farm-scoped and may be created offline before a planting
/// refers to them. The planting intent carries this operation as a dependency.
final class FarmlyCreateCropSpeciesIntent extends FarmlyMutationIntent {
  FarmlyCreateCropSpeciesIntent({
    required super.operationId,
    required super.continuityEpoch,
    required super.resourceId,
    required String name,
    required String harvestUnit,
    super.dependsOn = const [],
  }) : super._(
         type: 'cropSpecies.create',
         baseVersion: null,
         payload: _cropSpeciesUpdatePayload(
           name: name,
           harvestUnit: harvestUnit,
         ),
       );
}

/// A crop species rename carries the confirmed row version for compare-and-set.
final class FarmlyUpdateCropSpeciesNameIntent extends FarmlyMutationIntent {
  FarmlyUpdateCropSpeciesNameIntent({
    required super.operationId,
    required super.continuityEpoch,
    required super.resourceId,
    required int baseVersion,
    required String name,
    super.dependsOn = const [],
  }) : super._(
         type: 'cropSpecies.update',
         baseVersion: baseVersion,
         payload: _cropSpeciesUpdatePayload(name: name),
       );
}

/// Archives a confirmed crop species using its current version. Existing
/// plantings keep their species reference and history.
final class FarmlyArchiveCropSpeciesIntent extends FarmlyMutationIntent {
  FarmlyArchiveCropSpeciesIntent({
    required super.operationId,
    required super.continuityEpoch,
    required super.resourceId,
    required int baseVersion,
  }) : super._(
         type: 'cropSpecies.archive',
         baseVersion: baseVersion,
         dependsOn: const [],
         payload: const {},
       );
}

Map<String, Object?> _cropSpeciesUpdatePayload({
  String? name,
  String? harvestUnit,
}) {
  final payload = <String, Object?>{};
  if (name != null) {
    final normalizedName = name.trim();
    _requireLength('name', normalizedName, max: 160);
    payload['name'] = normalizedName;
  }
  if (harvestUnit != null) {
    if (!const {'kg', 'litre', 'pieces'}.contains(harvestUnit)) {
      throw ArgumentError.value(
        harvestUnit,
        'harvestUnit',
        'must be kg, litre, or pieces',
      );
    }
    payload['harvestUnit'] = harvestUnit;
  }
  if (payload.isEmpty) {
    throw ArgumentError('At least one crop species field is required');
  }
  return payload;
}

/// A planting keeps both parent resource IDs in its payload and the pending
/// parents' operation IDs in [dependsOn], so the sync engine cannot send it
/// until the crop and plot exist on the server.
final class FarmlyCreatePlantingIntent extends FarmlyMutationIntent {
  FarmlyCreatePlantingIntent({
    required super.operationId,
    required super.continuityEpoch,
    required super.resourceId,
    required String cropSpeciesId,
    required String plotId,
    required String sowingDate,
    String? status,
    String? expectedHarvestDate,
    String? areaM2,
    super.dependsOn = const [],
  }) : super._(
         type: 'planting.create',
         baseVersion: null,
         payload: _plantingPayload(
           cropSpeciesId: cropSpeciesId,
           plotId: plotId,
           sowingDate: sowingDate,
           status: status,
           expectedHarvestDate: expectedHarvestDate,
           areaM2: areaM2,
         ),
       );

  static Map<String, Object?> _plantingPayload({
    required String cropSpeciesId,
    required String plotId,
    required String sowingDate,
    String? status,
    String? expectedHarvestDate,
    String? areaM2,
  }) {
    _requireUuid('cropSpeciesId', cropSpeciesId);
    _requireUuid('plotId', plotId);
    final canonicalSowingDate = _requireCivilDate('sowingDate', sowingDate);
    const allowedStatuses = {
      'planned',
      'active',
      'harvested',
      'completed',
      'archived',
    };
    if (status != null && !allowedStatuses.contains(status)) {
      throw ArgumentError.value(status, 'status', 'is not a planting status');
    }
    String? canonicalExpectedHarvestDate;
    if (expectedHarvestDate != null) {
      canonicalExpectedHarvestDate = _requireCivilDate(
        'expectedHarvestDate',
        expectedHarvestDate,
      );
      if (canonicalExpectedHarvestDate.compareTo(canonicalSowingDate) < 0) {
        throw const FormatException(
          'Expected harvest date must not precede the sowing date',
        );
      }
    }
    if (areaM2 != null) _requireAreaM2(areaM2);
    final payload = <String, Object?>{
      'cropSpeciesId': cropSpeciesId,
      'plotId': plotId,
      'sowingDate': canonicalSowingDate,
    };
    if (status != null) payload['status'] = status;
    if (canonicalExpectedHarvestDate != null) {
      payload['expectedHarvestDate'] = canonicalExpectedHarvestDate;
    }
    if (areaM2 != null) payload['areaM2'] = areaM2;
    return payload;
  }
}

/// Updates mutable planting fields with the version of the confirmed row.
/// Archiving remains a distinct operation and is not authored through this
/// update intent.
final class FarmlyUpdatePlantingIntent extends FarmlyMutationIntent {
  FarmlyUpdatePlantingIntent({
    required super.operationId,
    required super.continuityEpoch,
    required super.resourceId,
    required int baseVersion,
    String? status,
    String? sowingDate,
    String? expectedHarvestDate,
    String? areaM2,
  }) : super._(
         type: 'planting.update',
         baseVersion: baseVersion,
         dependsOn: const [],
         payload: _payload(
           status: status,
           sowingDate: sowingDate,
           expectedHarvestDate: expectedHarvestDate,
           areaM2: areaM2,
         ),
       );

  static Map<String, Object?> _payload({
    String? status,
    String? sowingDate,
    String? expectedHarvestDate,
    String? areaM2,
  }) {
    const editableStatuses = {'planned', 'active', 'harvested', 'completed'};
    if (status != null && !editableStatuses.contains(status)) {
      throw ArgumentError.value(
        status,
        'status',
        'must be a non-archived planting status',
      );
    }
    final canonicalSowingDate = sowingDate == null
        ? null
        : _requireCivilDate('sowingDate', sowingDate);
    final canonicalExpectedHarvestDate = expectedHarvestDate == null
        ? null
        : _requireCivilDate('expectedHarvestDate', expectedHarvestDate);
    if (canonicalSowingDate != null &&
        canonicalExpectedHarvestDate != null &&
        canonicalExpectedHarvestDate.compareTo(canonicalSowingDate) < 0) {
      throw const FormatException(
        'Expected harvest date must not precede the sowing date',
      );
    }
    if (areaM2 != null) _requireAreaM2(areaM2);
    final payload = <String, Object?>{
      'status': ?status,
      'sowingDate': ?canonicalSowingDate,
      'expectedHarvestDate': ?canonicalExpectedHarvestDate,
      'areaM2': ?areaM2,
    };
    if (payload.isEmpty) {
      throw ArgumentError('At least one planting field is required');
    }
    return payload;
  }
}

/// Archives a confirmed planting using its current version. This is a
/// separate lifecycle operation from [FarmlyUpdatePlantingIntent].
final class FarmlyArchivePlantingIntent extends FarmlyMutationIntent {
  FarmlyArchivePlantingIntent({
    required super.operationId,
    required super.continuityEpoch,
    required super.resourceId,
    required int baseVersion,
  }) : super._(
         type: 'planting.archive',
         baseVersion: baseVersion,
         dependsOn: const [],
         payload: const {},
       );
}

/// An immutable field activity belongs to one non-archived planting. When
/// that planting is still queued locally, [dependsOn] keeps the activity
/// behind its parent create operation during offline replay.
final class FarmlyCreatePlantingEventIntent extends FarmlyMutationIntent {
  FarmlyCreatePlantingEventIntent({
    required super.operationId,
    required super.continuityEpoch,
    required super.resourceId,
    required String plantingId,
    required String eventType,
    String? note,
    String? occurredOn,
    super.dependsOn = const [],
  }) : super._(
         type: 'plantingEvent.create',
         baseVersion: null,
         payload: _plantingEventPayload(
           plantingId: plantingId,
           eventType: eventType,
           note: note,
           occurredOn: occurredOn,
         ),
       );

  static Map<String, Object?> _plantingEventPayload({
    required String plantingId,
    required String eventType,
    String? note,
    String? occurredOn,
  }) {
    _requireUuid('plantingId', plantingId);
    final normalizedEventType = eventType.trim();
    _requireLength('eventType', normalizedEventType, max: 40);
    final normalizedNote = note?.trim();
    if (normalizedNote != null && normalizedNote.isNotEmpty) {
      _requireLength('note', normalizedNote, max: 500);
    }
    final payload = <String, Object?>{
      'plantingId': plantingId,
      'eventType': normalizedEventType,
    };
    if (normalizedNote != null && normalizedNote.isNotEmpty) {
      payload['note'] = normalizedNote;
    }
    if (occurredOn != null) {
      payload['occurredOn'] = _requireCivilDate('occurredOn', occurredOn);
    }
    return payload;
  }
}

final class FarmlyCreateHarvestIntent extends FarmlyMutationIntent {
  FarmlyCreateHarvestIntent({
    required super.operationId,
    required super.continuityEpoch,
    required super.resourceId,
    required String plantingId,
    required FarmlyDecimal quantityKg,
    required String harvestDate,
    super.dependsOn = const [],
  }) : super._(
         type: 'harvest.create',
         baseVersion: null,
         payload: _harvestPayload(plantingId, quantityKg, harvestDate),
       );

  static Map<String, Object?> _harvestPayload(
    String plantingId,
    FarmlyDecimal quantityKg,
    String harvestDate,
  ) {
    _requireUuid('plantingId', plantingId);
    _requirePositiveHarvestQuantity(quantityKg.value);
    final canonicalHarvestDate = _requireCivilDate('harvestDate', harvestDate);
    return {
      'plantingId': plantingId,
      'quantityKg': quantityKg.value,
      'harvestDate': canonicalHarvestDate,
    };
  }
}

/// A worker's correction proposal is an immutable request for review. It has
/// no head version because it does not change the confirmed harvest total.
final class FarmlyProposeHarvestCorrectionIntent extends FarmlyMutationIntent {
  FarmlyProposeHarvestCorrectionIntent({
    required super.operationId,
    required super.continuityEpoch,
    required super.resourceId,
    required FarmlyDecimal proposedQuantityKg,
    required String reason,
    super.dependsOn = const [],
  }) : super._(
         type: 'harvest.correction.propose',
         baseVersion: null,
         payload: _proposalPayload(proposedQuantityKg, reason),
       );

  static Map<String, Object?> _proposalPayload(
    FarmlyDecimal proposedQuantityKg,
    String reason,
  ) {
    _requirePositiveHarvestQuantity(proposedQuantityKg.value);
    final normalizedReason = reason.trim();
    _requireLength('reason', normalizedReason, max: 500);
    return {
      'proposedQuantityKg': proposedQuantityKg.value,
      'reason': normalizedReason,
    };
  }
}

/// A manager's correction appends a replacement record against the exact
/// confirmed head version; a selected proposal remains explicitly linked.
final class FarmlyApplyHarvestCorrectionIntent extends FarmlyMutationIntent {
  FarmlyApplyHarvestCorrectionIntent({
    required super.operationId,
    required super.continuityEpoch,
    required super.resourceId,
    required int baseVersion,
    required FarmlyDecimal proposedQuantityKg,
    String? reason,
    String? proposalId,
    super.dependsOn = const [],
  }) : super._(
         type: 'harvest.correction.apply',
         baseVersion: baseVersion,
         payload: _correctionPayload(proposedQuantityKg, reason, proposalId),
       );

  static Map<String, Object?> _correctionPayload(
    FarmlyDecimal proposedQuantityKg,
    String? reason,
    String? proposalId,
  ) {
    _requirePositiveHarvestQuantity(proposedQuantityKg.value);
    final normalizedReason = reason?.trim();
    if (normalizedReason != null && normalizedReason.isNotEmpty) {
      _requireLength('reason', normalizedReason, max: 500);
    }
    if (proposalId != null) _requireUuid('proposalId', proposalId);
    final payload = <String, Object?>{
      'proposedQuantityKg': proposedQuantityKg.value,
    };
    if (normalizedReason != null && normalizedReason.isNotEmpty) {
      payload['reason'] = normalizedReason;
    }
    if (proposalId != null) payload['proposalId'] = proposalId;
    return payload;
  }
}

/// Voiding is manager-only at the service boundary and must carry the exact
/// harvest-head version plus a human-readable audit reason.
final class FarmlyVoidHarvestIntent extends FarmlyMutationIntent {
  FarmlyVoidHarvestIntent({
    required super.operationId,
    required super.continuityEpoch,
    required super.resourceId,
    required int baseVersion,
    required String reason,
    super.dependsOn = const [],
  }) : super._(
         type: 'harvest.void',
         baseVersion: baseVersion,
         payload: _voidPayload(reason),
       );

  static Map<String, Object?> _voidPayload(String reason) {
    final normalizedReason = reason.trim();
    _requireLength('reason', normalizedReason, max: 500);
    return {'reason': normalizedReason};
  }
}

final class FarmlyCreateWaterTankIntent extends FarmlyMutationIntent {
  FarmlyCreateWaterTankIntent({
    required super.operationId,
    required super.continuityEpoch,
    required super.resourceId,
    required String name,
    required String zoneId,
    required String capacityLitres,
    super.dependsOn = const [],
  }) : super._(
         type: 'waterTank.create',
         baseVersion: null,
         payload: _waterTankPayload(name, zoneId, capacityLitres),
       );

  static Map<String, Object?> _waterTankPayload(
    String name,
    String zoneId,
    String capacityLitres,
  ) {
    final normalizedName = name.trim();
    _requireLength('name', normalizedName, max: 160);
    _requireUuid('zoneId', zoneId);
    _requireNumeric20_4('capacityLitres', capacityLitres, positive: true);
    return {
      'name': normalizedName,
      'zoneId': zoneId,
      'capacityLitres': capacityLitres,
    };
  }
}

final class FarmlyUpdateWaterTankNameIntent extends FarmlyMutationIntent {
  FarmlyUpdateWaterTankNameIntent({
    required super.operationId,
    required super.continuityEpoch,
    required super.resourceId,
    required int baseVersion,
    required String name,
    super.dependsOn = const [],
  }) : super._(
         type: 'waterTank.update',
         baseVersion: baseVersion,
         payload: _payload(name: name),
       );

  static Map<String, Object?> _payload({String? name, String? capacityLitres}) {
    final normalizedName = name?.trim();
    if (normalizedName != null) {
      _requireLength('name', normalizedName, max: 160);
    }
    if (capacityLitres != null) {
      _requireNumeric20_4('capacityLitres', capacityLitres, positive: true);
    }
    return {
      ...?(normalizedName == null ? null : {'name': normalizedName}),
      ...?(capacityLitres == null ? null : {'capacityLitres': capacityLitres}),
    };
  }
}

final class FarmlyCreateWaterReadingIntent extends FarmlyMutationIntent {
  FarmlyCreateWaterReadingIntent({
    required super.operationId,
    required super.continuityEpoch,
    required super.resourceId,
    required String tankId,
    required String storedLitres,
    required String source,
    String? measuredAt,
    super.dependsOn = const [],
  }) : super._(
         type: 'waterReading.create',
         baseVersion: null,
         payload: _waterReadingPayload(
           tankId,
           storedLitres,
           source,
           measuredAt,
         ),
       );

  static Map<String, Object?> _waterReadingPayload(
    String tankId,
    String storedLitres,
    String source,
    String? measuredAt,
  ) {
    _requireUuid('tankId', tankId);
    _requireNumeric20_4('storedLitres', storedLitres, positive: false);
    _requireLength('source', source.trim(), max: 40);
    if (measuredAt != null && !_isValidRfc3339Timestamp(measuredAt)) {
      throw const FormatException('Invalid RFC3339 water measurement time');
    }
    return {
      'tankId': tankId,
      'storedLitres': storedLitres,
      'source': source.trim(),
      ...?(measuredAt == null ? null : {'measuredAt': measuredAt}),
    };
  }
}

final class FarmlyCreateMoistureReadingIntent extends FarmlyMutationIntent {
  FarmlyCreateMoistureReadingIntent({
    required super.operationId,
    required super.continuityEpoch,
    required super.resourceId,
    required String zoneId,
    required String value,
    required String method,
    required String measuredAt,
    DateTime? nowUtc,
    super.dependsOn = const [],
  }) : super._(
         type: 'moistureReading.create',
         baseVersion: null,
         payload: _moisturePayload(
           zoneId: zoneId,
           value: value,
           method: method,
           measuredAt: measuredAt,
           nowUtc: nowUtc ?? DateTime.now().toUtc(),
         ),
       );

  /// Validates the canonical wire payload. Restored intents deliberately omit
  /// [nowUtc] so a valid queued measurement does not expire as the clock moves.
  static void validatePayload({
    required String zoneId,
    required String value,
    required String method,
    required String measuredAt,
    DateTime? nowUtc,
  }) {
    _moisturePayload(
      zoneId: zoneId,
      value: value,
      method: method,
      measuredAt: measuredAt,
      nowUtc: nowUtc,
    );
  }

  static Map<String, Object?> _moisturePayload({
    required String zoneId,
    required String value,
    required String method,
    required String measuredAt,
    required DateTime? nowUtc,
  }) {
    _requireUuid('zoneId', zoneId);
    if (!_isValidMoisturePercent(value)) {
      throw const FormatException('Invalid moisture percentage');
    }
    if (!const {'relative_percent', 'vwc_percent'}.contains(method)) {
      throw ArgumentError.value(method, 'method', 'is not a supported method');
    }
    if (!_isValidRfc3339Timestamp(measuredAt)) {
      throw const FormatException('Invalid RFC3339 moisture measurement time');
    }

    final measuredInstant = DateTime.parse(measuredAt).toUtc();
    if (measuredInstant.isBefore(DateTime.utc(2000))) {
      throw const FormatException('Moisture measurement predates year 2000');
    }
    if (nowUtc != null &&
        measuredInstant.isAfter(
          nowUtc.toUtc().add(const Duration(hours: 24)),
        )) {
      throw const FormatException('Moisture measurement is too far in future');
    }

    return {
      'zoneId': zoneId,
      'value': value,
      'method': method,
      'measuredAt': measuredAt,
    };
  }
}

bool _isValidMoisturePercent(String value) {
  final match = RegExp(
    r'^(0|[1-9][0-9]?|100)(?:\.([0-9]{1,2}))?$',
  ).firstMatch(value);
  if (match == null) return false;

  final whole = int.parse(match.group(1)!);
  if (whole < 100) return true;
  final fraction = match.group(2);
  return fraction == null || int.parse(fraction) == 0;
}

bool _isValidRfc3339Timestamp(String value) {
  final match = RegExp(
    r'^(\d{4})-(\d{2})-(\d{2})T(\d{2}):(\d{2}):(\d{2})(?:\.(\d+))?(Z|([+-])(\d{2}):(\d{2}))$',
  ).firstMatch(value);
  if (match == null) return false;

  int component(int group) => int.parse(match.group(group)!);

  final year = component(1);
  final month = component(2);
  final day = component(3);
  final hour = component(4);
  final minute = component(5);
  final second = component(6);
  if (hour > 23 || minute > 59 || second > 59) return false;

  final date = DateTime.utc(year, month, day);
  if (date.year != year || date.month != month || date.day != day) {
    return false;
  }

  if (match.group(8) == 'Z') return true;
  return component(10) <= 23 && component(11) <= 59;
}

final class FarmlyCreateWaterUsageIntent extends FarmlyMutationIntent {
  FarmlyCreateWaterUsageIntent({
    required super.operationId,
    required super.continuityEpoch,
    required super.resourceId,
    required String tankId,
    required String usageLitres,
    required String usageDate,
    String? note,
    super.dependsOn = const [],
  }) : super._(
         type: 'waterUsage.create',
         baseVersion: null,
         payload: _waterUsagePayload(tankId, usageLitres, usageDate, note),
       );

  static Map<String, Object?> _waterUsagePayload(
    String tankId,
    String usageLitres,
    String usageDate,
    String? note,
  ) {
    _requireUuid('tankId', tankId);
    _requireNumeric20_4('usageLitres', usageLitres, positive: true);
    final canonicalUsageDate = _requireCivilDate('usageDate', usageDate);
    final normalizedNote = note?.trim();
    if (normalizedNote != null && normalizedNote.length > 200) {
      throw ArgumentError.value(note, 'note', 'must be at most 200 characters');
    }
    return {
      'tankId': tankId,
      'usageLitres': usageLitres,
      'usageDate': canonicalUsageDate,
      if (normalizedNote != null && normalizedNote.isNotEmpty)
        'note': normalizedNote,
    };
  }
}

/// Append one livestock production fact. The API derives the unit from the
/// product, so the immutable request never accepts a client-supplied unit.
/// Exactly one subject is required: a batch herd or a tracked animal.
final class FarmlyCreateProductionRecordIntent extends FarmlyMutationIntent {
  FarmlyCreateProductionRecordIntent({
    required super.operationId,
    required super.continuityEpoch,
    required super.resourceId,
    String? herdId,
    String? animalId,
    required String product,
    required String quantity,
    required String recordedOn,
  }) : super._(
         type: 'productionRecord.create',
         baseVersion: null,
         dependsOn: const [],
         payload: _productionRecordPayload(
           herdId: herdId,
           animalId: animalId,
           product: product,
           quantity: quantity,
           recordedOn: recordedOn,
         ),
       );
}

Map<String, Object?> _productionRecordPayload({
  required String? herdId,
  required String? animalId,
  required String product,
  required String quantity,
  required String recordedOn,
}) {
  if ((herdId == null) == (animalId == null)) {
    throw ArgumentError('Exactly one production subject is required');
  }
  if (herdId != null) _requireUuid('herdId', herdId);
  if (animalId != null) _requireUuid('animalId', animalId);
  if (!const {'milk', 'eggs', 'weight'}.contains(product)) {
    throw ArgumentError.value(product, 'product', 'is not supported');
  }
  _requireNumeric20_4('quantity', quantity, positive: true);
  if (product == 'eggs' && !RegExp(r'^[0-9]+$').hasMatch(quantity)) {
    throw const FormatException('Egg production quantity must be an integer');
  }
  final subject = herdId != null
      ? <String, Object?>{'herdId': herdId}
      : <String, Object?>{'animalId': animalId};
  return <String, Object?>{
    ...subject,
    'product': product,
    'quantity': quantity,
    'recordedOn': _requireCivilDate('recordedOn', recordedOn),
  };
}

/// Create a recurring farm task through the normal durable outbox. When a
/// zone is still local, callers preserve its parent operation in `dependsOn`.
/// An omitted start date is resolved by the server in the farm's timezone.
final class FarmlyCreateTaskTemplateIntent extends FarmlyMutationIntent {
  FarmlyCreateTaskTemplateIntent({
    required super.operationId,
    required super.continuityEpoch,
    required super.resourceId,
    required String title,
    String? kind,
    String? zoneId,
    String? assigneeMembershipId,
    required String frequency,
    required String timeOfDay,
    List<int> daysOfWeek = const [],
    String? startsOn,
    String? endsOn,
    super.dependsOn = const [],
  }) : super._(
         type: 'taskTemplate.create',
         baseVersion: null,
         payload: _taskTemplateCreatePayload(
           title: title,
           kind: kind,
           zoneId: zoneId,
           assigneeMembershipId: assigneeMembershipId,
           frequency: frequency,
           timeOfDay: timeOfDay,
           daysOfWeek: daysOfWeek,
           startsOn: startsOn,
           endsOn: endsOn,
         ),
       );
}

/// Repairs or changes a task's recurrence without changing its immutable kind
/// or other template fields. The template version is the compare-and-swap head.
final class FarmlyUpdateTaskTemplateScheduleIntent
    extends FarmlyMutationIntent {
  FarmlyUpdateTaskTemplateScheduleIntent({
    required super.operationId,
    required super.continuityEpoch,
    required super.resourceId,
    required int baseVersion,
    required String frequency,
    required String timeOfDay,
    List<int> daysOfWeek = const [],
    super.dependsOn = const [],
  }) : super._(
         type: 'taskTemplate.update',
         baseVersion: baseVersion,
         payload: {
           'recurrence': _taskTemplateRecurrencePayload(
             frequency: frequency,
             timeOfDay: timeOfDay,
             daysOfWeek: daysOfWeek,
           ),
         },
       );
}

/// Transition a confirmed materialized occurrence or the farm-local generated
/// occurrence for today. A missing base version means the server materializes
/// the deterministic occurrence and applies the transition atomically.
final class FarmlyTaskOccurrenceTransitionIntent extends FarmlyMutationIntent {
  FarmlyTaskOccurrenceTransitionIntent({
    required super.operationId,
    required super.continuityEpoch,
    required super.resourceId,
    required String templateId,
    required String occurrenceDate,
    required String slot,
    required String transition,
    super.baseVersion,
    String? reason,
    bool irrigation = false,
    super.dependsOn = const [],
  }) : super._(
         type: irrigation
             ? 'irrigationTask.transition'
             : 'taskOccurrence.transition',
         payload: _taskOccurrenceTransitionPayload(
           templateId: templateId,
           occurrenceDate: occurrenceDate,
           slot: slot,
           transition: transition,
           reason: reason,
         ),
       );
}

Map<String, Object?> _taskOccurrenceTransitionPayload({
  required String templateId,
  required String occurrenceDate,
  required String slot,
  required String transition,
  required String? reason,
}) {
  _requireUuid('templateId', templateId);
  final canonicalDate = _requireCivilDate('occurrenceDate', occurrenceDate);
  final canonicalSlot = slot.trim();
  _requireLength('slot', canonicalSlot, max: 40);
  if (!const {'complete', 'skip', 'reopen', 'cancel'}.contains(transition)) {
    throw ArgumentError.value(transition, 'transition', 'is not supported');
  }
  final canonicalReason = reason?.trim();
  if (canonicalReason != null && canonicalReason.isNotEmpty) {
    _requireLength('reason', canonicalReason, max: 500);
  }
  return Map<String, Object?>.unmodifiable({
    'templateId': templateId,
    'occurrenceDate': canonicalDate,
    'slot': canonicalSlot,
    'transition': transition,
    if (canonicalReason != null && canonicalReason.isNotEmpty)
      'reason': canonicalReason,
  });
}

Map<String, Object?>? _taskTemplateOptionalField(String key, Object? value) =>
    value == null ? null : <String, Object?>{key: value};

Map<String, Object?> _taskTemplateCreatePayload({
  required String title,
  required String? kind,
  required String? zoneId,
  required String? assigneeMembershipId,
  required String frequency,
  required String timeOfDay,
  required List<int> daysOfWeek,
  required String? startsOn,
  required String? endsOn,
}) {
  final canonicalTitle = title.trim();
  if (canonicalTitle.isEmpty || canonicalTitle.runes.length > 160) {
    throw ArgumentError.value(
      title,
      'title',
      'must contain 1 to 160 characters',
    );
  }
  if (kind != null &&
      !const {'general', 'feeding', 'irrigation'}.contains(kind)) {
    throw ArgumentError.value(kind, 'kind', 'is not supported');
  }
  if (zoneId != null) _requireUuid('zoneId', zoneId);
  if (assigneeMembershipId != null) {
    _requireUuid('assigneeMembershipId', assigneeMembershipId);
  }
  final recurrence = _taskTemplateRecurrencePayload(
    frequency: frequency,
    timeOfDay: timeOfDay,
    daysOfWeek: daysOfWeek,
  );

  final canonicalStartsOn = startsOn == null
      ? null
      : _requireCivilDate('startsOn', startsOn);
  final canonicalEndsOn = endsOn == null
      ? null
      : _requireCivilDate('endsOn', endsOn);
  if (canonicalStartsOn != null &&
      canonicalEndsOn != null &&
      canonicalEndsOn.compareTo(canonicalStartsOn) < 0) {
    throw ArgumentError.value(endsOn, 'endsOn', 'must not precede startsOn');
  }

  return Map<String, Object?>.unmodifiable({
    'title': canonicalTitle,
    ...?_taskTemplateOptionalField('kind', kind == 'general' ? null : kind),
    ...?_taskTemplateOptionalField('zoneId', zoneId),
    ...?_taskTemplateOptionalField(
      'assigneeMembershipId',
      assigneeMembershipId,
    ),
    'recurrence': recurrence,
    ...?_taskTemplateOptionalField('startsOn', canonicalStartsOn),
    ...?_taskTemplateOptionalField('endsOn', canonicalEndsOn),
  });
}

Map<String, Object?> _taskTemplateRecurrencePayload({
  required String frequency,
  required String timeOfDay,
  required List<int> daysOfWeek,
}) {
  if (frequency != 'daily' && frequency != 'weekly') {
    throw ArgumentError.value(frequency, 'frequency', 'is not supported');
  }
  if (!RegExp(r'^([01][0-9]|2[0-3]):[0-5][0-9]$').hasMatch(timeOfDay)) {
    throw ArgumentError.value(timeOfDay, 'timeOfDay', 'must use HH:MM');
  }
  if ((frequency == 'weekly' && daysOfWeek.isEmpty) ||
      daysOfWeek.length > 7 ||
      daysOfWeek.any((day) => day < 0 || day > 6) ||
      (daysOfWeek.isNotEmpty && frequency != 'weekly')) {
    throw ArgumentError.value(
      daysOfWeek,
      'daysOfWeek',
      'weekly recurrence requires at least one weekday; daily recurrence omits weekdays; values range from 0 to 6',
    );
  }
  return Map<String, Object?>.unmodifiable({
    'freq': frequency,
    'timeOfDay': timeOfDay,
    if (daysOfWeek.isNotEmpty) 'daysOfWeek': List<int>.unmodifiable(daysOfWeek),
  });
}

/// Append a livestock note or veterinary observation. The API defaults the
/// kind to note, so that default stays absent from the immutable payload.
/// Exactly one subject is required: a herd or a tracked animal.
final class FarmlyCreateAnimalObservationIntent extends FarmlyMutationIntent {
  FarmlyCreateAnimalObservationIntent({
    required super.operationId,
    required super.continuityEpoch,
    required super.resourceId,
    String? herdId,
    String? animalId,
    required String note,
    String? kind,
    String? observedOn,
  }) : super._(
         type: 'animalObservation.create',
         baseVersion: null,
         dependsOn: const [],
         payload: _animalObservationPayload(
           herdId: herdId,
           animalId: animalId,
           note: note,
           kind: kind,
           observedOn: observedOn,
         ),
       );
}

Map<String, Object?> _animalObservationPayload({
  required String? herdId,
  required String? animalId,
  required String note,
  required String? kind,
  required String? observedOn,
}) {
  if ((herdId == null) == (animalId == null)) {
    throw ArgumentError('Exactly one animal observation subject is required');
  }
  if (herdId != null) _requireUuid('herdId', herdId);
  if (animalId != null) _requireUuid('animalId', animalId);
  final normalizedNote = note.trim();
  _requireLength('note', normalizedNote, max: 1000);
  final normalizedKind = kind ?? 'note';
  if (!const {'note', 'vet'}.contains(normalizedKind)) {
    throw ArgumentError.value(kind, 'kind', 'is not supported');
  }
  return <String, Object?>{
    'herdId': ?herdId,
    'animalId': ?animalId,
    'note': normalizedNote,
    if (normalizedKind != 'note') 'kind': normalizedKind,
    if (observedOn != null)
      'observedOn': _requireCivilDate('observedOn', observedOn),
  };
}

void _requireNumeric20_4(String field, String value, {required bool positive}) {
  final valid = RegExp(
    r'^(0|[1-9][0-9]{0,15})(\.[0-9]{1,4})?$',
  ).hasMatch(value);
  if (!valid || (positive && !RegExp(r'[1-9]').hasMatch(value))) {
    throw FormatException(
      '$field must ${positive ? 'be positive' : 'be non-negative'} and fit NUMERIC(20,4)',
    );
  }
}

void _requirePositiveHarvestQuantity(String value) {
  if (!RegExp(r'^(0|[1-9][0-9]{0,15})(\.[0-9]{1,4})?$').hasMatch(value) ||
      !RegExp(r'[1-9]').hasMatch(value)) {
    throw const FormatException(
      'Harvest quantity must be positive and fit NUMERIC(20,4)',
    );
  }
}

final class FarmlyScopedMutation {
  FarmlyScopedMutation({required this.scope, required this.intent}) {
    if (scope.continuityEpoch != intent.continuityEpoch) {
      throw ArgumentError(
        'Mutation continuity epoch must match its captured scope',
      );
    }
    final organizationScoped = intent.type == 'farm.create';
    if (organizationScoped !=
        (scope.kind == FarmlyMutationScopeKind.organization)) {
      throw ArgumentError(
        'Mutation type does not match its organization or farm scope',
      );
    }
    if (intent.type == 'farm.update' && intent.resourceId != scope.farmId) {
      throw ArgumentError(
        'Farm profile update resource must match the selected farm scope',
      );
    }
  }

  final FarmlyMutationScope scope;
  final FarmlyMutationIntent intent;

  /// Scope stays local; the server derives actor and scope from auth and route.
  FarmlyJsonMap toRequestJson() => intent.toJson();
}

void _requireUuid(String field, String value) {
  final valid = RegExp(
    r'^[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-4[0-9a-fA-F]{3}-[89abAB][0-9a-fA-F]{3}-[0-9a-fA-F]{12}$',
  ).hasMatch(value);
  if (!valid) throw ArgumentError.value(value, field, 'must be a UUIDv4');
}

void _requireResourceUuid(String field, String value) {
  final valid = RegExp(
    r'^[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[1-5][0-9a-fA-F]{3}-[89abAB][0-9a-fA-F]{3}-[0-9a-fA-F]{12}$',
  ).hasMatch(value);
  if (!valid) {
    throw ArgumentError.value(value, field, 'must be an RFC 4122 UUID');
  }
}

void _requireNonEmpty(String field, String value) {
  if (value.trim().isEmpty) {
    throw ArgumentError.value(value, field, 'must not be empty');
  }
}

void _requireLength(String field, String value, {required int max}) {
  _requireNonEmpty(field, value);
  if (value.length > max) {
    throw ArgumentError.value(value, field, 'must be at most $max characters');
  }
}

void _requireAreaM2(String value) {
  if (!RegExp(r'^(0|[1-9][0-9]{0,11})(\.[0-9]{1,2})?$').hasMatch(value)) {
    throw const FormatException('Invalid Farmly area in square metres');
  }
}

bool _isCoarseWeatherGrid(String value) {
  if (!RegExp(r'^-?[0-9]{1,2}\.[0-9],-?[0-9]{1,3}\.[0-9]$').hasMatch(value)) {
    return false;
  }
  final coordinates = value.split(',');
  final latitude = double.parse(coordinates[0]);
  final longitude = double.parse(coordinates[1]);
  return latitude >= -90 &&
      latitude <= 90 &&
      longitude >= -180 &&
      longitude <= 180;
}

String _requireCivilDate(String field, String value) {
  if (!RegExp(r'^\d{4}-\d{2}-\d{2}$').hasMatch(value)) {
    throw FormatException('Invalid Farmly civil date in $field');
  }
  final parts = value.split('-').map(int.parse).toList(growable: false);
  final parsed = DateTime.utc(parts[0], parts[1], parts[2]);
  if (parts[0] < 1 || parsed.toIso8601String().substring(0, 10) != value) {
    throw FormatException('Invalid Farmly civil date in $field');
  }
  return value;
}

Map<String, Object?>? _optionalAreaEntry(String? areaM2) =>
    areaM2 == null ? null : {'areaM2': areaM2};

bool _isUnitInterval(String value) =>
    RegExp(r'^(0(\.[0-9]+)?|1(\.0+)?)$').hasMatch(value);

/// Append one immutable batch-herd movement. The signed delta is derived by
/// the authoring UI; callers provide the herd, movement type and exact change.
/// Same-herd local operations may depend on the preceding unresolved movement
/// so offline order is preserved when the outbox reconnects.
final class FarmlyCreateLivestockMovementIntent extends FarmlyMutationIntent {
  FarmlyCreateLivestockMovementIntent({
    required super.operationId,
    required super.continuityEpoch,
    required super.resourceId,
    required String herdId,
    required String movementType,
    required int delta,
    String? occurredOn,
    super.dependsOn = const [],
  }) : super._(
         type: 'livestockMovement.create',
         baseVersion: null,
         payload: _livestockMovementPayload(
           herdId: herdId,
           movementType: movementType,
           delta: delta,
           occurredOn: occurredOn,
         ),
       );
}

Map<String, Object?> _livestockMovementPayload({
  required String herdId,
  required String movementType,
  required int delta,
  required String? occurredOn,
}) {
  _requireUuid('herdId', herdId);
  final canonicalMovementType = movementType.trim();
  _requireLength('movementType', canonicalMovementType, max: 40);
  if (delta == 0 || delta < -2147483648 || delta > 2147483647) {
    throw ArgumentError.value(
      delta,
      'delta',
      'must be a nonzero PostgreSQL integer',
    );
  }
  return {
    'herdId': herdId,
    'movementType': canonicalMovementType,
    'delta': delta,
    if (occurredOn != null)
      'occurredOn': _requireCivilDate('occurredOn', occurredOn),
  };
}
