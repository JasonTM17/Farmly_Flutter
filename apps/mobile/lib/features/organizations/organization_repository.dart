import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/network/farmly_api_client.dart';

const _uuidPattern =
    r'^[0-9a-f]{8}-[0-9a-f]{4}-[1-8][0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$';
final _uuid = RegExp(_uuidPattern, caseSensitive: false);
final _positiveInteger = RegExp(r'^[1-9][0-9]{0,18}$');
final _acceptanceToken = RegExp(r'^[a-f0-9]{64}$');
final _maxPostgresBigint = BigInt.parse('9223372036854775807');

final organizationRepositoryProvider = Provider<OrganizationRepository>(
  (ref) => OrganizationRepository(ref.watch(farmlyApiClientProvider)),
);

enum FarmlyOrganizationRole { owner, admin, member, viewer }

enum FarmlyOrganizationStatus { active, suspended }

enum FarmlyFarmStatus { active, archived }

enum FarmlyFarmGrantRole { owner, admin, manager, worker, viewer }

final class FarmlyOrganization {
  const FarmlyOrganization({
    required this.id,
    required this.name,
    required this.status,
    required this.policyVersion,
    required this.role,
    required this.membershipVersion,
    this.membershipId,
  });

  final String id;
  final String name;
  final FarmlyOrganizationStatus status;
  final String policyVersion;
  final FarmlyOrganizationRole role;
  final int membershipVersion;
  final String? membershipId;

  factory FarmlyOrganization.fromJson(Object? value) {
    final json = _requireMap(value);
    final membership = _requireMap(json['membership']);
    return FarmlyOrganization(
      id: _requireUuid(json['id']),
      name: _requireNonEmptyString(json['name']),
      status: _parseEnum(
        FarmlyOrganizationStatus.values,
        json['status'],
        (value) => value.name,
      ),
      policyVersion: _requirePositiveBigintString(json['policyVersion']),
      role: _parseEnum(
        FarmlyOrganizationRole.values,
        membership['role'],
        (value) => value.name,
      ),
      membershipVersion: _requirePositiveInt(membership['version']),
      membershipId: membership['id'] == null
          ? null
          : _requireUuid(membership['id']),
    );
  }

  Map<String, Object?> toJson() => <String, Object?>{
    'id': id,
    'name': name,
    'status': status.name,
    'policyVersion': policyVersion,
    'membership': <String, Object?>{
      'id': membershipId,
      'role': role.name,
      'version': membershipVersion,
    },
  };
}

final class FarmlyDirectoryFarm {
  const FarmlyDirectoryFarm({
    required this.id,
    required this.name,
    required this.status,
    required this.grantRole,
  });

  final String id;
  final String name;
  final FarmlyFarmStatus status;
  final FarmlyFarmGrantRole grantRole;

  factory FarmlyDirectoryFarm.fromJson(Object? value) {
    final json = _requireMap(value);
    final name = _requireNonEmptyString(json['farmName']);
    if (name.length > 160) _unexpectedResponse();
    return FarmlyDirectoryFarm(
      id: _requireUuid(json['farmId']),
      name: name,
      status: _parseEnum(
        FarmlyFarmStatus.values,
        json['status'],
        (value) => value.name,
      ),
      grantRole: _parseEnum(
        FarmlyFarmGrantRole.values,
        json['grantRole'],
        (value) => value.name,
      ),
    );
  }

  Map<String, Object?> toJson() => <String, Object?>{
    'farmId': id,
    'farmName': name,
    'status': status.name,
    'grantRole': grantRole.name,
  };
}

final class FarmlyFarmDirectory {
  const FarmlyFarmDirectory({
    required this.scopePolicyVersion,
    required this.continuityEpoch,
    required this.farms,
  });

  final String scopePolicyVersion;
  final String continuityEpoch;
  final List<FarmlyDirectoryFarm> farms;

  Map<String, Object?> toJson() => <String, Object?>{
    'scopePolicyVersion': scopePolicyVersion,
    'continuityEpoch': continuityEpoch,
    'farms': farms.map((farm) => farm.toJson()).toList(growable: false),
  };

  factory FarmlyFarmDirectory.fromJson(Object? value) {
    final json = _requireMap(value);
    return FarmlyFarmDirectory(
      scopePolicyVersion: _requirePositiveBigintString(
        json['scopePolicyVersion'],
      ),
      continuityEpoch: _requirePositiveBigintString(json['continuityEpoch']),
      farms: List<FarmlyDirectoryFarm>.unmodifiable(
        _requireList(json['farms']).map(FarmlyDirectoryFarm.fromJson),
      ),
    );
  }
}

final class FarmlyAcceptedInvitation {
  const FarmlyAcceptedInvitation({
    required this.organizationId,
    required this.membershipId,
    required this.role,
    required this.policyVersion,
  });

  final String organizationId;
  final String membershipId;
  final FarmlyOrganizationRole role;
  final String policyVersion;
}

final class OrganizationRepository {
  const OrganizationRepository(this._api);

  final FarmlyApiClient _api;

  Future<List<FarmlyOrganization>> listAll() async {
    final organizations = <FarmlyOrganization>[];
    final seenIds = <String>{};
    final seenCursors = <String>{};
    String? cursor;
    do {
      final query = <String, Object?>{'limit': 100};
      if (cursor != null) query['cursor'] = cursor;
      final body = _requireMap(
        await _api.get('v1/organizations', queryParameters: query),
      );
      final data = _requireMap(body['data']);
      final items = _requireList(data['organizations']);
      for (final item in items) {
        final organization = FarmlyOrganization.fromJson(item);
        if (!seenIds.add(organization.id)) _unexpectedResponse();
        organizations.add(organization);
      }
      final page = _requireMap(body['page']);
      if (page['hasMore'] != true) {
        cursor = null;
      } else {
        final next = _requireUuid(page['nextCursor']);
        if (!seenCursors.add(next)) _unexpectedResponse();
        cursor = next;
      }
    } while (cursor != null);
    return List<FarmlyOrganization>.unmodifiable(organizations);
  }

  Future<FarmlyOrganization> create({
    required String name,
    required String operationId,
  }) async {
    final requestId = _requireUuid(operationId);
    final body = _requireMap(
      await _api.post('v1/organizations', <String, Object?>{
        'operationId': requestId,
        'name': name.trim(),
      }, idempotencyKey: requestId),
    );
    return FarmlyOrganization.fromJson(_requireMap(body['data']));
  }

  Future<FarmlyFarmDirectory> loadFarmDirectory(String organizationId) async {
    final id = _requireUuid(organizationId);
    for (var attempt = 0; attempt < 2; attempt += 1) {
      try {
        return await _loadFarmDirectoryPageSet(id);
      } on FarmlyApiFailure catch (error) {
        if (error.code != FarmlyApiFailureCode.cursorExpired || attempt == 1) {
          rethrow;
        }
      }
    }
    _unexpectedResponse();
  }

  Future<FarmlyFarmDirectory> _loadFarmDirectoryPageSet(
    String organizationId,
  ) async {
    final farms = <FarmlyDirectoryFarm>[];
    final farmIds = <String>{};
    final cursors = <String>{};
    String? cursor;
    String? policyVersion;
    String? continuityEpoch;
    do {
      final query = <String, Object?>{'limit': 100};
      if (cursor != null) query['cursor'] = cursor;
      final body = _requireMap(
        await _api.get(
          'v1/organizations/$organizationId/farm-directory',
          queryParameters: query,
        ),
      );
      if (body['schemaVersion'] != 'farm-directory.v1') {
        _unexpectedResponse();
      }
      final currentPolicy = _requirePositiveBigintString(
        body['scopePolicyVersion'],
      );
      final currentEpoch = _requirePositiveBigintString(
        body['continuityEpoch'],
      );
      if (policyVersion != null &&
          (policyVersion != currentPolicy || continuityEpoch != currentEpoch)) {
        throw const FarmlyApiFailure(FarmlyApiFailureCode.cursorExpired);
      }
      policyVersion = currentPolicy;
      continuityEpoch = currentEpoch;
      for (final value in _requireList(body['farms'])) {
        final farm = FarmlyDirectoryFarm.fromJson(value);
        if (!farmIds.add(farm.id)) _unexpectedResponse();
        farms.add(farm);
      }
      final next = body['nextCursor'];
      if (next == null) {
        cursor = null;
      } else if (next is String && next.isNotEmpty && next.length <= 2048) {
        if (!cursors.add(next)) _unexpectedResponse();
        cursor = next;
      } else {
        _unexpectedResponse();
      }
    } while (cursor != null);

    return FarmlyFarmDirectory(
      scopePolicyVersion: policyVersion,
      continuityEpoch: continuityEpoch,
      farms: List<FarmlyDirectoryFarm>.unmodifiable(farms),
    );
  }

  Future<FarmlyAcceptedInvitation> acceptInvitation({
    required String organizationId,
    required String invitationId,
    required String token,
    required String operationId,
  }) async {
    final orgId = _requireUuid(organizationId);
    final inviteId = _requireUuid(invitationId);
    final requestId = _requireUuid(operationId);
    if (!_acceptanceToken.hasMatch(token)) _unexpectedResponse();
    final body = _requireMap(
      await _api.post(
        'v1/organizations/$orgId/invitations/$inviteId/accept',
        <String, Object?>{
          'operationId': requestId,
          'payload': <String, Object?>{'token': token},
        },
        idempotencyKey: requestId,
      ),
    );
    final data = _requireMap(body['data']);
    final membership = _requireMap(data['membership']);
    return FarmlyAcceptedInvitation(
      organizationId: _requireUuid(data['organizationId']),
      membershipId: _requireUuid(membership['id']),
      role: _parseEnum(
        FarmlyOrganizationRole.values,
        membership['role'],
        (value) => value.name,
      ),
      policyVersion: _requirePositiveBigintString(data['policyVersion']),
    );
  }
}

Map<String, Object?> _requireMap(Object? value) {
  if (value is Map) {
    return value.map((key, value) => MapEntry(key.toString(), value));
  }
  return _unexpectedResponse();
}

List<Object?> _requireList(Object? value) {
  if (value is List) return value.cast<Object?>();
  return _unexpectedResponse();
}

String _requireNonEmptyString(Object? value) {
  if (value is String && value.isNotEmpty) return value;
  return _unexpectedResponse();
}

String _requireUuid(Object? value) {
  if (value is String && _uuid.hasMatch(value)) return value.toLowerCase();
  return _unexpectedResponse();
}

String _requirePositiveBigintString(Object? value) {
  if (value is! String || !_positiveInteger.hasMatch(value)) {
    return _unexpectedResponse();
  }
  if (BigInt.parse(value) > _maxPostgresBigint) return _unexpectedResponse();
  return value;
}

int _requirePositiveInt(Object? value) {
  if (value is int && value > 0) return value;
  return _unexpectedResponse();
}

T _parseEnum<T extends Enum>(
  Iterable<T> values,
  Object? raw,
  String Function(T value) nameOf,
) {
  if (raw is String) {
    for (final value in values) {
      if (nameOf(value) == raw) return value;
    }
  }
  return _unexpectedResponse();
}

Never _unexpectedResponse() =>
    throw const FarmlyApiFailure(FarmlyApiFailureCode.unexpected);
