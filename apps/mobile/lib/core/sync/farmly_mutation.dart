import '../../generated/farmly_api_types.dart';

enum FarmlyMutationScopeKind { organization, farm }

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
    _requireUuid('resourceId', resourceId);
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

    return _WireMutationIntent(
      operationId: requireString('operationId'),
      continuityEpoch: requireString('continuityEpoch'),
      type: requireString('type'),
      resourceId: requireString('resourceId'),
      baseVersion: (json['baseVersion'] as num?)?.toInt(),
      dependsOn: [
        for (final dep in (json['dependsOn'] as List? ?? const []))
          dep as String,
      ],
      payload: Map<String, Object?>.from(json['payload'] as Map),
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
  }) : super._() {
    if (type.trim().isEmpty || !type.contains('.')) {
      throw ArgumentError.value(type, 'type', 'must be a namespaced op type');
    }
  }
}

final class FarmlyCreateFarmIntent extends FarmlyMutationIntent {
  FarmlyCreateFarmIntent({
    required super.operationId,
    required super.continuityEpoch,
    required super.resourceId,
    required String name,
    required String timezone,
    super.dependsOn = const [],
  }) : super._(
         type: 'farm.create',
         baseVersion: null,
         payload: _farmPayload(name, timezone),
       );

  static Map<String, Object?> _farmPayload(String name, String timezone) {
    _requireNonEmpty('name', name);
    _requireNonEmpty('timezone', timezone);
    return {'name': name, 'timezone': timezone};
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
    if (!RegExp(r'^\d{4}-\d{2}-\d{2}$').hasMatch(harvestDate)) {
      throw const FormatException('Invalid Farmly civil date');
    }
    final parts = harvestDate.split('-').map(int.parse).toList(growable: false);
    final parsed = DateTime.utc(parts[0], parts[1], parts[2]);
    if (parts[0] < 1 ||
        parsed.toIso8601String().substring(0, 10) != harvestDate) {
      throw const FormatException('Invalid Farmly civil date');
    }
    return {
      'plantingId': plantingId,
      'quantityKg': quantityKg.value,
      'harvestDate': harvestDate,
    };
  }
}

final class FarmlyScopedMutation {
  FarmlyScopedMutation({required this.scope, required this.intent}) {
    if (scope.continuityEpoch != intent.continuityEpoch) {
      throw ArgumentError(
        'Mutation continuity epoch must match its captured scope',
      );
    }
    final organizationScoped = intent is FarmlyCreateFarmIntent;
    if (organizationScoped !=
        (scope.kind == FarmlyMutationScopeKind.organization)) {
      throw ArgumentError(
        'Mutation type does not match its organization or farm scope',
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

void _requireNonEmpty(String field, String value) {
  if (value.trim().isEmpty) {
    throw ArgumentError.value(value, field, 'must not be empty');
  }
}
