// GENERATED FILE. Run node contracts/scripts/build-contracts.mjs to refresh.
// OpenAPI SHA-256: 55e03d1a790c49ce2c88c8a06a3e3e7aec6e5e3d89057919a3409a002082f2c7

typedef FarmlyJsonMap = Map<String, dynamic>;

/// Exact base-10 wire value. It intentionally avoids floating-point conversion.
final class FarmlyDecimal {
  static final RegExp _canonical = RegExp(
    r'^-?(?:0|[1-9][0-9]*)(?:\.[0-9]+)?$',
  );
  final String value;
  const FarmlyDecimal._(this.value);
  factory FarmlyDecimal.parse(String value) {
    if (!_canonical.hasMatch(value)) {
      throw const FormatException('Invalid canonical decimal string');
    }
    return FarmlyDecimal._(value);
  }
  @override
  String toString() => value;
  @override
  bool operator ==(Object other) =>
      other is FarmlyDecimal && other.value == value;
  @override
  int get hashCode => value.hashCode;
}

final class FarmlyFieldError {
  const FarmlyFieldError({required this.code, required this.message});
  final String code;
  final String message;
  factory FarmlyFieldError.fromJson(FarmlyJsonMap json) => FarmlyFieldError(
    code: json['code'] as String,
    message: json['message'] as String,
  );
  FarmlyJsonMap toJson() {
    final json = <String, dynamic>{'code': code, 'message': message}
      ..removeWhere((key, value) => value == null);
    return json;
  }
}

final class FarmlyApiError {
  const FarmlyApiError({
    required this.code,
    required this.message,
    this.fieldErrors,
    required this.retryable,
    required this.requestId,
  });
  final String code;
  final String message;
  final List<FarmlyFieldError>? fieldErrors;
  final bool retryable;
  final String requestId;
  factory FarmlyApiError.fromJson(FarmlyJsonMap json) => FarmlyApiError(
    code: json['code'] as String,
    message: json['message'] as String,
    fieldErrors: (json['fieldErrors'] == null
        ? null
        : (json['fieldErrors'] as List<dynamic>)
              .map(
                (item) => FarmlyFieldError.fromJson(
                  Map<String, dynamic>.from(item as Map),
                ),
              )
              .toList(growable: false)),
    retryable: json['retryable'] as bool,
    requestId: json['requestId'] as String,
  );
  FarmlyJsonMap toJson() {
    final json = <String, dynamic>{
      'code': code,
      'message': message,
      'fieldErrors': fieldErrors
          ?.map((item) => item.toJson())
          .toList(growable: false),
      'retryable': retryable,
      'requestId': requestId,
    }..removeWhere((key, value) => value == null);
    return json;
  }
}

final class FarmlyErrorEnvelope {
  const FarmlyErrorEnvelope({required this.error});
  final FarmlyApiError error;
  factory FarmlyErrorEnvelope.fromJson(FarmlyJsonMap json) =>
      FarmlyErrorEnvelope(
        error: FarmlyApiError.fromJson(
          Map<String, dynamic>.from(json['error'] as Map),
        ),
      );
  FarmlyJsonMap toJson() {
    final json = <String, dynamic>{'error': error.toJson()}
      ..removeWhere((key, value) => value == null);
    return json;
  }
}

final class FarmlyResponseMeta {
  const FarmlyResponseMeta({
    required this.schemaVersion,
    required this.asOf,
    this.scopePolicyVersion,
  });
  final String schemaVersion;
  final String asOf;
  final String? scopePolicyVersion;
  factory FarmlyResponseMeta.fromJson(FarmlyJsonMap json) => FarmlyResponseMeta(
    schemaVersion: json['schemaVersion'] as String,
    asOf: json['asOf'] as String,
    scopePolicyVersion: (json['scopePolicyVersion'] == null
        ? null
        : json['scopePolicyVersion'] as String),
  );
  FarmlyJsonMap toJson() {
    final json = <String, dynamic>{
      'schemaVersion': schemaVersion,
      'asOf': asOf,
      'scopePolicyVersion': scopePolicyVersion,
    }..removeWhere((key, value) => value == null);
    return json;
  }
}

final class FarmlyPageInfo {
  const FarmlyPageInfo({this.nextCursor, required this.hasMore});
  final String? nextCursor;
  final bool hasMore;
  factory FarmlyPageInfo.fromJson(FarmlyJsonMap json) => FarmlyPageInfo(
    nextCursor: (json['nextCursor'] == null
        ? null
        : json['nextCursor'] as String),
    hasMore: json['hasMore'] as bool,
  );
  FarmlyJsonMap toJson() {
    final json = <String, dynamic>{'nextCursor': nextCursor, 'hasMore': hasMore}
      ..removeWhere((key, value) => value == null);
    return json;
  }
}

final class FarmlyOrganizationMembershipListMeta {
  const FarmlyOrganizationMembershipListMeta({
    required this.schemaVersion,
    required this.asOf,
    required this.scopePolicyVersion,
  });
  final String schemaVersion;
  final String asOf;
  final String scopePolicyVersion;
  factory FarmlyOrganizationMembershipListMeta.fromJson(FarmlyJsonMap json) =>
      FarmlyOrganizationMembershipListMeta(
        schemaVersion: json['schemaVersion'] as String,
        asOf: json['asOf'] as String,
        scopePolicyVersion: json['scopePolicyVersion'] as String,
      );
  FarmlyJsonMap toJson() {
    final json = <String, dynamic>{
      'schemaVersion': schemaVersion,
      'asOf': asOf,
      'scopePolicyVersion': scopePolicyVersion,
    }..removeWhere((key, value) => value == null);
    return json;
  }
}

final class FarmlySuccessEnvelope {
  const FarmlySuccessEnvelope({
    required this.data,
    this.page,
    required this.meta,
  });
  final Map<String, dynamic> data;
  final FarmlyPageInfo? page;
  final FarmlyResponseMeta meta;
  factory FarmlySuccessEnvelope.fromJson(FarmlyJsonMap json) =>
      FarmlySuccessEnvelope(
        data: Map<String, dynamic>.from(json['data'] as Map),
        page: (json['page'] == null
            ? null
            : FarmlyPageInfo.fromJson(
                Map<String, dynamic>.from(json['page'] as Map),
              )),
        meta: FarmlyResponseMeta.fromJson(
          Map<String, dynamic>.from(json['meta'] as Map),
        ),
      );
  FarmlyJsonMap toJson() {
    final json = <String, dynamic>{
      'data': data,
      'page': page?.toJson(),
      'meta': meta.toJson(),
    }..removeWhere((key, value) => value == null);
    return json;
  }
}

final class FarmlyFarmScope {
  const FarmlyFarmScope({
    required this.organizationId,
    required this.farmId,
    required this.continuityEpoch,
    required this.scopePolicyVersion,
  });
  final String organizationId;
  final String farmId;
  final String continuityEpoch;
  final String scopePolicyVersion;
  factory FarmlyFarmScope.fromJson(FarmlyJsonMap json) => FarmlyFarmScope(
    organizationId: json['organizationId'] as String,
    farmId: json['farmId'] as String,
    continuityEpoch: json['continuityEpoch'] as String,
    scopePolicyVersion: json['scopePolicyVersion'] as String,
  );
  FarmlyJsonMap toJson() {
    final json = <String, dynamic>{
      'organizationId': organizationId,
      'farmId': farmId,
      'continuityEpoch': continuityEpoch,
      'scopePolicyVersion': scopePolicyVersion,
    }..removeWhere((key, value) => value == null);
    return json;
  }
}

final class FarmlyFarmDirectoryEntry {
  const FarmlyFarmDirectoryEntry({
    required this.farmId,
    required this.farmName,
    required this.status,
    required this.grantRole,
  });
  final String farmId;
  final String farmName;
  final String status;
  final String grantRole;
  factory FarmlyFarmDirectoryEntry.fromJson(FarmlyJsonMap json) =>
      FarmlyFarmDirectoryEntry(
        farmId: json['farmId'] as String,
        farmName: json['farmName'] as String,
        status: json['status'] as String,
        grantRole: json['grantRole'] as String,
      );
  FarmlyJsonMap toJson() {
    final json = <String, dynamic>{
      'farmId': farmId,
      'farmName': farmName,
      'status': status,
      'grantRole': grantRole,
    }..removeWhere((key, value) => value == null);
    return json;
  }
}

final class FarmlyFarmDirectoryManifest {
  const FarmlyFarmDirectoryManifest({
    required this.schemaVersion,
    required this.scopePolicyVersion,
    required this.continuityEpoch,
    required this.farms,
    this.nextCursor,
  });
  final String schemaVersion;
  final String scopePolicyVersion;
  final String continuityEpoch;
  final List<FarmlyFarmDirectoryEntry> farms;
  final String? nextCursor;
  factory FarmlyFarmDirectoryManifest.fromJson(FarmlyJsonMap json) =>
      FarmlyFarmDirectoryManifest(
        schemaVersion: json['schemaVersion'] as String,
        scopePolicyVersion: json['scopePolicyVersion'] as String,
        continuityEpoch: json['continuityEpoch'] as String,
        farms: (json['farms'] as List<dynamic>)
            .map(
              (item) => FarmlyFarmDirectoryEntry.fromJson(
                Map<String, dynamic>.from(item as Map),
              ),
            )
            .toList(growable: false),
        nextCursor: (json['nextCursor'] == null
            ? null
            : json['nextCursor'] as String),
      );
  FarmlyJsonMap toJson() {
    final json = <String, dynamic>{
      'schemaVersion': schemaVersion,
      'scopePolicyVersion': scopePolicyVersion,
      'continuityEpoch': continuityEpoch,
      'farms': farms.map((item) => item.toJson()).toList(growable: false),
      'nextCursor': nextCursor,
    }..removeWhere((key, value) => value == null);
    return json;
  }
}

final class FarmlyFarmMutation {
  const FarmlyFarmMutation({
    required this.schemaVersion,
    required this.continuityEpoch,
    required this.operationId,
    required this.type,
    required this.resourceId,
    this.baseVersion,
    required this.dependsOn,
    required this.payload,
  });
  final String schemaVersion;
  final String continuityEpoch;
  final String operationId;
  final String type;
  final String resourceId;
  final int? baseVersion;
  final List<String> dependsOn;
  final Map<String, dynamic> payload;
  factory FarmlyFarmMutation.fromJson(FarmlyJsonMap json) => FarmlyFarmMutation(
    schemaVersion: json['schemaVersion'] as String,
    continuityEpoch: json['continuityEpoch'] as String,
    operationId: json['operationId'] as String,
    type: json['type'] as String,
    resourceId: json['resourceId'] as String,
    baseVersion: (json['baseVersion'] == null
        ? null
        : json['baseVersion'] as int),
    dependsOn: (json['dependsOn'] as List<dynamic>).cast<String>(),
    payload: Map<String, dynamic>.from(json['payload'] as Map),
  );
  FarmlyJsonMap toJson() {
    final json = <String, dynamic>{
      'schemaVersion': schemaVersion,
      'continuityEpoch': continuityEpoch,
      'operationId': operationId,
      'type': type,
      'resourceId': resourceId,
      'baseVersion': baseVersion,
      'dependsOn': dependsOn,
      'payload': payload,
    }..removeWhere((key, value) => value == null);
    return json;
  }
}

final class FarmlyFarmMutationBatch {
  const FarmlyFarmMutationBatch({
    required this.schemaVersion,
    required this.continuityEpoch,
    required this.operations,
  });
  final String schemaVersion;
  final String continuityEpoch;
  final List<FarmlyFarmMutation> operations;
  factory FarmlyFarmMutationBatch.fromJson(FarmlyJsonMap json) =>
      FarmlyFarmMutationBatch(
        schemaVersion: json['schemaVersion'] as String,
        continuityEpoch: json['continuityEpoch'] as String,
        operations: (json['operations'] as List<dynamic>)
            .map(
              (item) => FarmlyFarmMutation.fromJson(
                Map<String, dynamic>.from(item as Map),
              ),
            )
            .toList(growable: false),
      );
  FarmlyJsonMap toJson() {
    final json = <String, dynamic>{
      'schemaVersion': schemaVersion,
      'continuityEpoch': continuityEpoch,
      'operations': operations
          .map((item) => item.toJson())
          .toList(growable: false),
    }..removeWhere((key, value) => value == null);
    return json;
  }
}

final class FarmlyFarmMutationOutcome {
  const FarmlyFarmMutationOutcome({
    required this.operationId,
    required this.outcome,
    this.code,
  });
  final String operationId;
  final String outcome;
  final String? code;
  factory FarmlyFarmMutationOutcome.fromJson(FarmlyJsonMap json) =>
      FarmlyFarmMutationOutcome(
        operationId: json['operationId'] as String,
        outcome: json['outcome'] as String,
        code: (json['code'] == null ? null : json['code'] as String),
      );
  FarmlyJsonMap toJson() {
    final json = <String, dynamic>{
      'operationId': operationId,
      'outcome': outcome,
      'code': code,
    }..removeWhere((key, value) => value == null);
    return json;
  }
}

final class FarmlyMutationBatchResult {
  const FarmlyMutationBatchResult({
    required this.schemaVersion,
    required this.outcomes,
  });
  final String schemaVersion;
  final List<FarmlyFarmMutationOutcome> outcomes;
  factory FarmlyMutationBatchResult.fromJson(FarmlyJsonMap json) =>
      FarmlyMutationBatchResult(
        schemaVersion: json['schemaVersion'] as String,
        outcomes: (json['outcomes'] as List<dynamic>)
            .map(
              (item) => FarmlyFarmMutationOutcome.fromJson(
                Map<String, dynamic>.from(item as Map),
              ),
            )
            .toList(growable: false),
      );
  FarmlyJsonMap toJson() {
    final json = <String, dynamic>{
      'schemaVersion': schemaVersion,
      'outcomes': outcomes.map((item) => item.toJson()).toList(growable: false),
    }..removeWhere((key, value) => value == null);
    return json;
  }
}

final class FarmlyOperationStatus {
  const FarmlyOperationStatus({
    required this.operationId,
    required this.outcome,
  });
  final String operationId;
  final String outcome;
  factory FarmlyOperationStatus.fromJson(FarmlyJsonMap json) =>
      FarmlyOperationStatus(
        operationId: json['operationId'] as String,
        outcome: json['outcome'] as String,
      );
  FarmlyJsonMap toJson() {
    final json = <String, dynamic>{
      'operationId': operationId,
      'outcome': outcome,
    }..removeWhere((key, value) => value == null);
    return json;
  }
}

final class FarmlyBootstrapChunkDescriptor {
  const FarmlyBootstrapChunkDescriptor({
    required this.chunkId,
    required this.entity,
    required this.rowOffset,
    required this.rowCount,
    required this.sha256,
  });
  final String chunkId;
  final String entity;
  final int rowOffset;
  final int rowCount;
  final String sha256;
  factory FarmlyBootstrapChunkDescriptor.fromJson(FarmlyJsonMap json) =>
      FarmlyBootstrapChunkDescriptor(
        chunkId: json['chunkId'] as String,
        entity: json['entity'] as String,
        rowOffset: json['rowOffset'] as int,
        rowCount: json['rowCount'] as int,
        sha256: json['sha256'] as String,
      );
  FarmlyJsonMap toJson() {
    final json = <String, dynamic>{
      'chunkId': chunkId,
      'entity': entity,
      'rowOffset': rowOffset,
      'rowCount': rowCount,
      'sha256': sha256,
    }..removeWhere((key, value) => value == null);
    return json;
  }
}

final class FarmlyBootstrapManifest {
  const FarmlyBootstrapManifest({
    required this.schemaVersion,
    required this.snapshotId,
    required this.scope,
    required this.highWatermark,
    required this.createdAt,
    required this.expiresAt,
    required this.chunks,
  });
  final String schemaVersion;
  final String snapshotId;
  final FarmlyFarmScope scope;
  final String highWatermark;
  final String createdAt;
  final String expiresAt;
  final List<FarmlyBootstrapChunkDescriptor> chunks;
  factory FarmlyBootstrapManifest.fromJson(FarmlyJsonMap json) =>
      FarmlyBootstrapManifest(
        schemaVersion: json['schemaVersion'] as String,
        snapshotId: json['snapshotId'] as String,
        scope: FarmlyFarmScope.fromJson(
          Map<String, dynamic>.from(json['scope'] as Map),
        ),
        highWatermark: json['highWatermark'] as String,
        createdAt: json['createdAt'] as String,
        expiresAt: json['expiresAt'] as String,
        chunks: (json['chunks'] as List<dynamic>)
            .map(
              (item) => FarmlyBootstrapChunkDescriptor.fromJson(
                Map<String, dynamic>.from(item as Map),
              ),
            )
            .toList(growable: false),
      );
  FarmlyJsonMap toJson() {
    final json = <String, dynamic>{
      'schemaVersion': schemaVersion,
      'snapshotId': snapshotId,
      'scope': scope.toJson(),
      'highWatermark': highWatermark,
      'createdAt': createdAt,
      'expiresAt': expiresAt,
      'chunks': chunks.map((item) => item.toJson()).toList(growable: false),
    }..removeWhere((key, value) => value == null);
    return json;
  }
}

final class FarmlyBootstrapChunk {
  const FarmlyBootstrapChunk({
    required this.schemaVersion,
    required this.snapshotId,
    required this.chunkId,
    required this.entity,
    required this.rowOffset,
    required this.rows,
    this.nextCursor,
  });
  final String schemaVersion;
  final String snapshotId;
  final String chunkId;
  final String entity;
  final int rowOffset;
  final List<Map<String, dynamic>> rows;
  final String? nextCursor;
  factory FarmlyBootstrapChunk.fromJson(FarmlyJsonMap json) =>
      FarmlyBootstrapChunk(
        schemaVersion: json['schemaVersion'] as String,
        snapshotId: json['snapshotId'] as String,
        chunkId: json['chunkId'] as String,
        entity: json['entity'] as String,
        rowOffset: json['rowOffset'] as int,
        rows: (json['rows'] as List<dynamic>)
            .map((item) => Map<String, dynamic>.from(item as Map))
            .toList(growable: false),
        nextCursor: (json['nextCursor'] == null
            ? null
            : json['nextCursor'] as String),
      );
  FarmlyJsonMap toJson() {
    final json = <String, dynamic>{
      'schemaVersion': schemaVersion,
      'snapshotId': snapshotId,
      'chunkId': chunkId,
      'entity': entity,
      'rowOffset': rowOffset,
      'rows': rows.map((item) => item).toList(growable: false),
      'nextCursor': nextCursor,
    }..removeWhere((key, value) => value == null);
    return json;
  }
}

final class FarmlyDomainCommandRequest {
  const FarmlyDomainCommandRequest({
    required this.operationId,
    required this.payload,
  });
  final String operationId;
  final Map<String, dynamic> payload;
  factory FarmlyDomainCommandRequest.fromJson(FarmlyJsonMap json) =>
      FarmlyDomainCommandRequest(
        operationId: json['operationId'] as String,
        payload: Map<String, dynamic>.from(json['payload'] as Map),
      );
  FarmlyJsonMap toJson() {
    final json = <String, dynamic>{
      'operationId': operationId,
      'payload': payload,
    }..removeWhere((key, value) => value == null);
    return json;
  }
}

final class FarmlyCreateOrganizationRequest {
  const FarmlyCreateOrganizationRequest({
    required this.operationId,
    required this.name,
  });
  final String operationId;
  final String name;
  factory FarmlyCreateOrganizationRequest.fromJson(FarmlyJsonMap json) =>
      FarmlyCreateOrganizationRequest(
        operationId: json['operationId'] as String,
        name: json['name'] as String,
      );
  FarmlyJsonMap toJson() {
    final json = <String, dynamic>{'operationId': operationId, 'name': name}
      ..removeWhere((key, value) => value == null);
    return json;
  }
}

final class FarmlyInvitationFarmGrantRequest {
  const FarmlyInvitationFarmGrantRequest({
    required this.farmId,
    required this.role,
  });
  final String farmId;
  final String role;
  factory FarmlyInvitationFarmGrantRequest.fromJson(FarmlyJsonMap json) =>
      FarmlyInvitationFarmGrantRequest(
        farmId: json['farmId'] as String,
        role: json['role'] as String,
      );
  FarmlyJsonMap toJson() {
    final json = <String, dynamic>{'farmId': farmId, 'role': role}
      ..removeWhere((key, value) => value == null);
    return json;
  }
}

final class FarmlyCreateOrganizationInvitationPayload {
  const FarmlyCreateOrganizationInvitationPayload({
    required this.email,
    required this.role,
    this.farmGrants,
  });
  final String email;
  final String role;
  final List<FarmlyInvitationFarmGrantRequest>? farmGrants;
  factory FarmlyCreateOrganizationInvitationPayload.fromJson(
    FarmlyJsonMap json,
  ) => FarmlyCreateOrganizationInvitationPayload(
    email: json['email'] as String,
    role: json['role'] as String,
    farmGrants: (json['farmGrants'] == null
        ? null
        : (json['farmGrants'] as List<dynamic>)
              .map(
                (item) => FarmlyInvitationFarmGrantRequest.fromJson(
                  Map<String, dynamic>.from(item as Map),
                ),
              )
              .toList(growable: false)),
  );
  FarmlyJsonMap toJson() {
    final json = <String, dynamic>{
      'email': email,
      'role': role,
      'farmGrants': farmGrants
          ?.map((item) => item.toJson())
          .toList(growable: false),
    }..removeWhere((key, value) => value == null);
    return json;
  }
}

final class FarmlyCreateOrganizationInvitationRequest {
  const FarmlyCreateOrganizationInvitationRequest({
    required this.operationId,
    required this.payload,
  });
  final String operationId;
  final FarmlyCreateOrganizationInvitationPayload payload;
  factory FarmlyCreateOrganizationInvitationRequest.fromJson(
    FarmlyJsonMap json,
  ) => FarmlyCreateOrganizationInvitationRequest(
    operationId: json['operationId'] as String,
    payload: FarmlyCreateOrganizationInvitationPayload.fromJson(
      Map<String, dynamic>.from(json['payload'] as Map),
    ),
  );
  FarmlyJsonMap toJson() {
    final json = <String, dynamic>{
      'operationId': operationId,
      'payload': payload.toJson(),
    }..removeWhere((key, value) => value == null);
    return json;
  }
}

final class FarmlyAcceptOrganizationInvitationPayload {
  const FarmlyAcceptOrganizationInvitationPayload({required this.token});
  final String token;
  factory FarmlyAcceptOrganizationInvitationPayload.fromJson(
    FarmlyJsonMap json,
  ) =>
      FarmlyAcceptOrganizationInvitationPayload(token: json['token'] as String);
  FarmlyJsonMap toJson() {
    final json = <String, dynamic>{'token': token}
      ..removeWhere((key, value) => value == null);
    return json;
  }
}

final class FarmlyAcceptOrganizationInvitationRequest {
  const FarmlyAcceptOrganizationInvitationRequest({
    required this.operationId,
    required this.payload,
  });
  final String operationId;
  final FarmlyAcceptOrganizationInvitationPayload payload;
  factory FarmlyAcceptOrganizationInvitationRequest.fromJson(
    FarmlyJsonMap json,
  ) => FarmlyAcceptOrganizationInvitationRequest(
    operationId: json['operationId'] as String,
    payload: FarmlyAcceptOrganizationInvitationPayload.fromJson(
      Map<String, dynamic>.from(json['payload'] as Map),
    ),
  );
  FarmlyJsonMap toJson() {
    final json = <String, dynamic>{
      'operationId': operationId,
      'payload': payload.toJson(),
    }..removeWhere((key, value) => value == null);
    return json;
  }
}

final class FarmlyOrganizationInvitationView {
  const FarmlyOrganizationInvitationView({
    required this.id,
    required this.role,
    required this.status,
    required this.createdAt,
    required this.expiresAt,
    required this.acceptedAt,
    required this.revokedAt,
  });
  final String id;
  final String role;
  final String status;
  final String createdAt;
  final String expiresAt;
  final String? acceptedAt;
  final String? revokedAt;
  factory FarmlyOrganizationInvitationView.fromJson(FarmlyJsonMap json) =>
      FarmlyOrganizationInvitationView(
        id: json['id'] as String,
        role: json['role'] as String,
        status: json['status'] as String,
        createdAt: json['createdAt'] as String,
        expiresAt: json['expiresAt'] as String,
        acceptedAt: (json['acceptedAt'] == null
            ? null
            : json['acceptedAt'] as String),
        revokedAt: (json['revokedAt'] == null
            ? null
            : json['revokedAt'] as String),
      );
  FarmlyJsonMap toJson() {
    final json = <String, dynamic>{
      'id': id,
      'role': role,
      'status': status,
      'createdAt': createdAt,
      'expiresAt': expiresAt,
      'acceptedAt': acceptedAt,
      'revokedAt': revokedAt,
    }..removeWhere((key, value) => value == null);
    return json;
  }
}

final class FarmlyOrganizationInvitationListData {
  const FarmlyOrganizationInvitationListData({required this.invitations});
  final List<FarmlyOrganizationInvitationView> invitations;
  factory FarmlyOrganizationInvitationListData.fromJson(FarmlyJsonMap json) =>
      FarmlyOrganizationInvitationListData(
        invitations: (json['invitations'] as List<dynamic>)
            .map(
              (item) => FarmlyOrganizationInvitationView.fromJson(
                Map<String, dynamic>.from(item as Map),
              ),
            )
            .toList(growable: false),
      );
  FarmlyJsonMap toJson() {
    final json = <String, dynamic>{
      'invitations': invitations
          .map((item) => item.toJson())
          .toList(growable: false),
    }..removeWhere((key, value) => value == null);
    return json;
  }
}

final class FarmlyOrganizationInvitationListResponse {
  const FarmlyOrganizationInvitationListResponse({
    required this.data,
    this.page,
    required this.meta,
  });
  final FarmlyOrganizationInvitationListData data;
  final FarmlyPageInfo? page;
  final FarmlyResponseMeta meta;
  factory FarmlyOrganizationInvitationListResponse.fromJson(
    FarmlyJsonMap json,
  ) => FarmlyOrganizationInvitationListResponse(
    data: FarmlyOrganizationInvitationListData.fromJson(
      Map<String, dynamic>.from(json['data'] as Map),
    ),
    page: (json['page'] == null
        ? null
        : FarmlyPageInfo.fromJson(
            Map<String, dynamic>.from(json['page'] as Map),
          )),
    meta: FarmlyResponseMeta.fromJson(
      Map<String, dynamic>.from(json['meta'] as Map),
    ),
  );
  FarmlyJsonMap toJson() {
    final json = <String, dynamic>{
      'data': data.toJson(),
      'page': page?.toJson(),
      'meta': meta.toJson(),
    }..removeWhere((key, value) => value == null);
    return json;
  }
}

final class FarmlyOrganizationMembershipFarmGrant {
  const FarmlyOrganizationMembershipFarmGrant({
    required this.farmId,
    required this.role,
    required this.version,
  });
  final String farmId;
  final String role;
  final int version;
  factory FarmlyOrganizationMembershipFarmGrant.fromJson(FarmlyJsonMap json) =>
      FarmlyOrganizationMembershipFarmGrant(
        farmId: json['farmId'] as String,
        role: json['role'] as String,
        version: json['version'] as int,
      );
  FarmlyJsonMap toJson() {
    final json = <String, dynamic>{
      'farmId': farmId,
      'role': role,
      'version': version,
    }..removeWhere((key, value) => value == null);
    return json;
  }
}

final class FarmlyOrganizationMembershipView {
  const FarmlyOrganizationMembershipView({
    required this.id,
    required this.userId,
    required this.role,
    required this.status,
    required this.version,
    required this.farmGrants,
  });
  final String id;
  final String userId;
  final String role;
  final String status;
  final int version;
  final List<FarmlyOrganizationMembershipFarmGrant> farmGrants;
  factory FarmlyOrganizationMembershipView.fromJson(FarmlyJsonMap json) =>
      FarmlyOrganizationMembershipView(
        id: json['id'] as String,
        userId: json['userId'] as String,
        role: json['role'] as String,
        status: json['status'] as String,
        version: json['version'] as int,
        farmGrants: (json['farmGrants'] as List<dynamic>)
            .map(
              (item) => FarmlyOrganizationMembershipFarmGrant.fromJson(
                Map<String, dynamic>.from(item as Map),
              ),
            )
            .toList(growable: false),
      );
  FarmlyJsonMap toJson() {
    final json = <String, dynamic>{
      'id': id,
      'userId': userId,
      'role': role,
      'status': status,
      'version': version,
      'farmGrants': farmGrants
          .map((item) => item.toJson())
          .toList(growable: false),
    }..removeWhere((key, value) => value == null);
    return json;
  }
}

final class FarmlyOrganizationMembershipListData {
  const FarmlyOrganizationMembershipListData({required this.memberships});
  final List<FarmlyOrganizationMembershipView> memberships;
  factory FarmlyOrganizationMembershipListData.fromJson(FarmlyJsonMap json) =>
      FarmlyOrganizationMembershipListData(
        memberships: (json['memberships'] as List<dynamic>)
            .map(
              (item) => FarmlyOrganizationMembershipView.fromJson(
                Map<String, dynamic>.from(item as Map),
              ),
            )
            .toList(growable: false),
      );
  FarmlyJsonMap toJson() {
    final json = <String, dynamic>{
      'memberships': memberships
          .map((item) => item.toJson())
          .toList(growable: false),
    }..removeWhere((key, value) => value == null);
    return json;
  }
}

final class FarmlyOrganizationMembershipListResponse {
  const FarmlyOrganizationMembershipListResponse({
    required this.data,
    this.page,
    required this.meta,
  });
  final FarmlyOrganizationMembershipListData data;
  final FarmlyPageInfo? page;
  final FarmlyOrganizationMembershipListMeta meta;
  factory FarmlyOrganizationMembershipListResponse.fromJson(
    FarmlyJsonMap json,
  ) => FarmlyOrganizationMembershipListResponse(
    data: FarmlyOrganizationMembershipListData.fromJson(
      Map<String, dynamic>.from(json['data'] as Map),
    ),
    page: (json['page'] == null
        ? null
        : FarmlyPageInfo.fromJson(
            Map<String, dynamic>.from(json['page'] as Map),
          )),
    meta: FarmlyOrganizationMembershipListMeta.fromJson(
      Map<String, dynamic>.from(json['meta'] as Map),
    ),
  );
  FarmlyJsonMap toJson() {
    final json = <String, dynamic>{
      'data': data.toJson(),
      'page': page?.toJson(),
      'meta': meta.toJson(),
    }..removeWhere((key, value) => value == null);
    return json;
  }
}

final class FarmlyPatchOrganizationMembershipPayload {
  const FarmlyPatchOrganizationMembershipPayload({
    required this.role,
    required this.farmGrants,
  });
  final String role;
  final List<FarmlyInvitationFarmGrantRequest> farmGrants;
  factory FarmlyPatchOrganizationMembershipPayload.fromJson(
    FarmlyJsonMap json,
  ) => FarmlyPatchOrganizationMembershipPayload(
    role: json['role'] as String,
    farmGrants: (json['farmGrants'] as List<dynamic>)
        .map(
          (item) => FarmlyInvitationFarmGrantRequest.fromJson(
            Map<String, dynamic>.from(item as Map),
          ),
        )
        .toList(growable: false),
  );
  FarmlyJsonMap toJson() {
    final json = <String, dynamic>{
      'role': role,
      'farmGrants': farmGrants
          .map((item) => item.toJson())
          .toList(growable: false),
    }..removeWhere((key, value) => value == null);
    return json;
  }
}

final class FarmlyPatchOrganizationMembershipRequest {
  const FarmlyPatchOrganizationMembershipRequest({
    required this.operationId,
    required this.payload,
  });
  final String operationId;
  final FarmlyPatchOrganizationMembershipPayload payload;
  factory FarmlyPatchOrganizationMembershipRequest.fromJson(
    FarmlyJsonMap json,
  ) => FarmlyPatchOrganizationMembershipRequest(
    operationId: json['operationId'] as String,
    payload: FarmlyPatchOrganizationMembershipPayload.fromJson(
      Map<String, dynamic>.from(json['payload'] as Map),
    ),
  );
  FarmlyJsonMap toJson() {
    final json = <String, dynamic>{
      'operationId': operationId,
      'payload': payload.toJson(),
    }..removeWhere((key, value) => value == null);
    return json;
  }
}

final class FarmlyOrganizationMembershipMutationData {
  const FarmlyOrganizationMembershipMutationData({
    required this.membership,
    required this.policyVersion,
    required this.changed,
    required this.replayed,
  });
  final FarmlyOrganizationMembershipView membership;
  final String policyVersion;
  final bool changed;
  final bool replayed;
  factory FarmlyOrganizationMembershipMutationData.fromJson(
    FarmlyJsonMap json,
  ) => FarmlyOrganizationMembershipMutationData(
    membership: FarmlyOrganizationMembershipView.fromJson(
      Map<String, dynamic>.from(json['membership'] as Map),
    ),
    policyVersion: json['policyVersion'] as String,
    changed: json['changed'] as bool,
    replayed: json['replayed'] as bool,
  );
  FarmlyJsonMap toJson() {
    final json = <String, dynamic>{
      'membership': membership.toJson(),
      'policyVersion': policyVersion,
      'changed': changed,
      'replayed': replayed,
    }..removeWhere((key, value) => value == null);
    return json;
  }
}

final class FarmlyOrganizationMembershipMutationResponse {
  const FarmlyOrganizationMembershipMutationResponse({
    required this.data,
    required this.meta,
  });
  final FarmlyOrganizationMembershipMutationData data;
  final FarmlyResponseMeta meta;
  factory FarmlyOrganizationMembershipMutationResponse.fromJson(
    FarmlyJsonMap json,
  ) => FarmlyOrganizationMembershipMutationResponse(
    data: FarmlyOrganizationMembershipMutationData.fromJson(
      Map<String, dynamic>.from(json['data'] as Map),
    ),
    meta: FarmlyResponseMeta.fromJson(
      Map<String, dynamic>.from(json['meta'] as Map),
    ),
  );
  FarmlyJsonMap toJson() {
    final json = <String, dynamic>{'data': data.toJson(), 'meta': meta.toJson()}
      ..removeWhere((key, value) => value == null);
    return json;
  }
}

final class FarmlyTransferOrganizationOwnershipPayload {
  const FarmlyTransferOrganizationOwnershipPayload({
    required this.targetMembershipId,
    this.removeFormerOwner,
  });
  final String targetMembershipId;
  final bool? removeFormerOwner;
  factory FarmlyTransferOrganizationOwnershipPayload.fromJson(
    FarmlyJsonMap json,
  ) => FarmlyTransferOrganizationOwnershipPayload(
    targetMembershipId: json['targetMembershipId'] as String,
    removeFormerOwner: (json['removeFormerOwner'] == null
        ? null
        : json['removeFormerOwner'] as bool),
  );
  FarmlyJsonMap toJson() {
    final json = <String, dynamic>{
      'targetMembershipId': targetMembershipId,
      'removeFormerOwner': removeFormerOwner,
    }..removeWhere((key, value) => value == null);
    return json;
  }
}

final class FarmlyTransferOrganizationOwnershipRequest {
  const FarmlyTransferOrganizationOwnershipRequest({
    required this.operationId,
    required this.payload,
  });
  final String operationId;
  final FarmlyTransferOrganizationOwnershipPayload payload;
  factory FarmlyTransferOrganizationOwnershipRequest.fromJson(
    FarmlyJsonMap json,
  ) => FarmlyTransferOrganizationOwnershipRequest(
    operationId: json['operationId'] as String,
    payload: FarmlyTransferOrganizationOwnershipPayload.fromJson(
      Map<String, dynamic>.from(json['payload'] as Map),
    ),
  );
  FarmlyJsonMap toJson() {
    final json = <String, dynamic>{
      'operationId': operationId,
      'payload': payload.toJson(),
    }..removeWhere((key, value) => value == null);
    return json;
  }
}

final class FarmlyOwnershipTransferData {
  const FarmlyOwnershipTransferData({
    required this.targetMembershipId,
    required this.formerOwnerMembershipId,
    required this.formerOwnerRole,
    required this.formerOwnerStatus,
    required this.policyVersion,
    required this.replayed,
  });
  final String targetMembershipId;
  final String formerOwnerMembershipId;
  final String formerOwnerRole;
  final String formerOwnerStatus;
  final String policyVersion;
  final bool replayed;
  factory FarmlyOwnershipTransferData.fromJson(FarmlyJsonMap json) =>
      FarmlyOwnershipTransferData(
        targetMembershipId: json['targetMembershipId'] as String,
        formerOwnerMembershipId: json['formerOwnerMembershipId'] as String,
        formerOwnerRole: json['formerOwnerRole'] as String,
        formerOwnerStatus: json['formerOwnerStatus'] as String,
        policyVersion: json['policyVersion'] as String,
        replayed: json['replayed'] as bool,
      );
  FarmlyJsonMap toJson() {
    final json = <String, dynamic>{
      'targetMembershipId': targetMembershipId,
      'formerOwnerMembershipId': formerOwnerMembershipId,
      'formerOwnerRole': formerOwnerRole,
      'formerOwnerStatus': formerOwnerStatus,
      'policyVersion': policyVersion,
      'replayed': replayed,
    }..removeWhere((key, value) => value == null);
    return json;
  }
}

final class FarmlyOwnershipTransferResponse {
  const FarmlyOwnershipTransferResponse({
    required this.data,
    required this.meta,
  });
  final FarmlyOwnershipTransferData data;
  final FarmlyResponseMeta meta;
  factory FarmlyOwnershipTransferResponse.fromJson(FarmlyJsonMap json) =>
      FarmlyOwnershipTransferResponse(
        data: FarmlyOwnershipTransferData.fromJson(
          Map<String, dynamic>.from(json['data'] as Map),
        ),
        meta: FarmlyResponseMeta.fromJson(
          Map<String, dynamic>.from(json['meta'] as Map),
        ),
      );
  FarmlyJsonMap toJson() {
    final json = <String, dynamic>{'data': data.toJson(), 'meta': meta.toJson()}
      ..removeWhere((key, value) => value == null);
    return json;
  }
}

final class FarmlyCreatedOrganizationInvitationData {
  const FarmlyCreatedOrganizationInvitationData({
    required this.invitation,
    required this.acceptanceToken,
  });
  final Map<String, dynamic> invitation;
  final String acceptanceToken;
  factory FarmlyCreatedOrganizationInvitationData.fromJson(
    FarmlyJsonMap json,
  ) => FarmlyCreatedOrganizationInvitationData(
    invitation: Map<String, dynamic>.from(json['invitation'] as Map),
    acceptanceToken: json['acceptanceToken'] as String,
  );
  FarmlyJsonMap toJson() {
    final json = <String, dynamic>{
      'invitation': invitation,
      'acceptanceToken': acceptanceToken,
    }..removeWhere((key, value) => value == null);
    return json;
  }
}

final class FarmlyCreatedOrganizationInvitationResponse {
  const FarmlyCreatedOrganizationInvitationResponse({
    required this.data,
    required this.meta,
  });
  final FarmlyCreatedOrganizationInvitationData data;
  final FarmlyResponseMeta meta;
  factory FarmlyCreatedOrganizationInvitationResponse.fromJson(
    FarmlyJsonMap json,
  ) => FarmlyCreatedOrganizationInvitationResponse(
    data: FarmlyCreatedOrganizationInvitationData.fromJson(
      Map<String, dynamic>.from(json['data'] as Map),
    ),
    meta: FarmlyResponseMeta.fromJson(
      Map<String, dynamic>.from(json['meta'] as Map),
    ),
  );
  FarmlyJsonMap toJson() {
    final json = <String, dynamic>{'data': data.toJson(), 'meta': meta.toJson()}
      ..removeWhere((key, value) => value == null);
    return json;
  }
}

final class FarmlyAcceptedOrganizationInvitationData {
  const FarmlyAcceptedOrganizationInvitationData({
    required this.organizationId,
    required this.membership,
    required this.policyVersion,
    required this.replayed,
  });
  final String organizationId;
  final Map<String, dynamic> membership;
  final String policyVersion;
  final bool replayed;
  factory FarmlyAcceptedOrganizationInvitationData.fromJson(
    FarmlyJsonMap json,
  ) => FarmlyAcceptedOrganizationInvitationData(
    organizationId: json['organizationId'] as String,
    membership: Map<String, dynamic>.from(json['membership'] as Map),
    policyVersion: json['policyVersion'] as String,
    replayed: json['replayed'] as bool,
  );
  FarmlyJsonMap toJson() {
    final json = <String, dynamic>{
      'organizationId': organizationId,
      'membership': membership,
      'policyVersion': policyVersion,
      'replayed': replayed,
    }..removeWhere((key, value) => value == null);
    return json;
  }
}

final class FarmlyAcceptedOrganizationInvitationResponse {
  const FarmlyAcceptedOrganizationInvitationResponse({
    required this.data,
    required this.meta,
  });
  final FarmlyAcceptedOrganizationInvitationData data;
  final FarmlyResponseMeta meta;
  factory FarmlyAcceptedOrganizationInvitationResponse.fromJson(
    FarmlyJsonMap json,
  ) => FarmlyAcceptedOrganizationInvitationResponse(
    data: FarmlyAcceptedOrganizationInvitationData.fromJson(
      Map<String, dynamic>.from(json['data'] as Map),
    ),
    meta: FarmlyResponseMeta.fromJson(
      Map<String, dynamic>.from(json['meta'] as Map),
    ),
  );
  FarmlyJsonMap toJson() {
    final json = <String, dynamic>{'data': data.toJson(), 'meta': meta.toJson()}
      ..removeWhere((key, value) => value == null);
    return json;
  }
}

final class FarmlyRevokeOrganizationInvitationRequest {
  const FarmlyRevokeOrganizationInvitationRequest({required this.operationId});
  final String operationId;
  factory FarmlyRevokeOrganizationInvitationRequest.fromJson(
    FarmlyJsonMap json,
  ) => FarmlyRevokeOrganizationInvitationRequest(
    operationId: json['operationId'] as String,
  );
  FarmlyJsonMap toJson() {
    final json = <String, dynamic>{'operationId': operationId}
      ..removeWhere((key, value) => value == null);
    return json;
  }
}

final class FarmlyRevokedOrganizationInvitationData {
  const FarmlyRevokedOrganizationInvitationData({
    required this.invitation,
    required this.policyVersion,
    required this.replayed,
  });
  final Map<String, dynamic> invitation;
  final String policyVersion;
  final bool replayed;
  factory FarmlyRevokedOrganizationInvitationData.fromJson(
    FarmlyJsonMap json,
  ) => FarmlyRevokedOrganizationInvitationData(
    invitation: Map<String, dynamic>.from(json['invitation'] as Map),
    policyVersion: json['policyVersion'] as String,
    replayed: json['replayed'] as bool,
  );
  FarmlyJsonMap toJson() {
    final json = <String, dynamic>{
      'invitation': invitation,
      'policyVersion': policyVersion,
      'replayed': replayed,
    }..removeWhere((key, value) => value == null);
    return json;
  }
}

final class FarmlyRevokedOrganizationInvitationResponse {
  const FarmlyRevokedOrganizationInvitationResponse({
    required this.data,
    required this.meta,
  });
  final FarmlyRevokedOrganizationInvitationData data;
  final FarmlyResponseMeta meta;
  factory FarmlyRevokedOrganizationInvitationResponse.fromJson(
    FarmlyJsonMap json,
  ) => FarmlyRevokedOrganizationInvitationResponse(
    data: FarmlyRevokedOrganizationInvitationData.fromJson(
      Map<String, dynamic>.from(json['data'] as Map),
    ),
    meta: FarmlyResponseMeta.fromJson(
      Map<String, dynamic>.from(json['meta'] as Map),
    ),
  );
  FarmlyJsonMap toJson() {
    final json = <String, dynamic>{'data': data.toJson(), 'meta': meta.toJson()}
      ..removeWhere((key, value) => value == null);
    return json;
  }
}

final class FarmlyTaskTransitionRequest {
  const FarmlyTaskTransitionRequest({
    required this.operationId,
    required this.expectedVersion,
    required this.transition,
    this.reason,
  });
  final String operationId;
  final int expectedVersion;
  final String transition;
  final String? reason;
  factory FarmlyTaskTransitionRequest.fromJson(FarmlyJsonMap json) =>
      FarmlyTaskTransitionRequest(
        operationId: json['operationId'] as String,
        expectedVersion: json['expectedVersion'] as int,
        transition: json['transition'] as String,
        reason: (json['reason'] == null ? null : json['reason'] as String),
      );
  FarmlyJsonMap toJson() {
    final json = <String, dynamic>{
      'operationId': operationId,
      'expectedVersion': expectedVersion,
      'transition': transition,
      'reason': reason,
    }..removeWhere((key, value) => value == null);
    return json;
  }
}

final class FarmlyAiCreateRequest {
  const FarmlyAiCreateRequest({
    required this.schemaVersion,
    required this.clientRequestId,
    this.conversationId,
    required this.prompt,
    required this.consentRevision,
    required this.contextMode,
  });
  final String schemaVersion;
  final String clientRequestId;
  final String? conversationId;
  final String prompt;
  final int consentRevision;
  final String contextMode;
  factory FarmlyAiCreateRequest.fromJson(FarmlyJsonMap json) =>
      FarmlyAiCreateRequest(
        schemaVersion: json['schemaVersion'] as String,
        clientRequestId: json['clientRequestId'] as String,
        conversationId: (json['conversationId'] == null
            ? null
            : json['conversationId'] as String),
        prompt: json['prompt'] as String,
        consentRevision: json['consentRevision'] as int,
        contextMode: json['contextMode'] as String,
      );
  FarmlyJsonMap toJson() {
    final json = <String, dynamic>{
      'schemaVersion': schemaVersion,
      'clientRequestId': clientRequestId,
      'conversationId': conversationId,
      'prompt': prompt,
      'consentRevision': consentRevision,
      'contextMode': contextMode,
    }..removeWhere((key, value) => value == null);
    return json;
  }
}

final class FarmlyAiCancelRequest {
  const FarmlyAiCancelRequest({this.reason});
  final String? reason;
  factory FarmlyAiCancelRequest.fromJson(FarmlyJsonMap json) =>
      FarmlyAiCancelRequest(
        reason: (json['reason'] == null ? null : json['reason'] as String),
      );
  FarmlyJsonMap toJson() {
    final json = <String, dynamic>{'reason': reason}
      ..removeWhere((key, value) => value == null);
    return json;
  }
}

final class FarmlyAiRequestStatus {
  const FarmlyAiRequestStatus({
    required this.requestId,
    required this.status,
    required this.latestSeq,
    required this.usageState,
    this.finalMessageId,
  });
  final String requestId;
  final String status;
  final int latestSeq;
  final String usageState;
  final String? finalMessageId;
  factory FarmlyAiRequestStatus.fromJson(FarmlyJsonMap json) =>
      FarmlyAiRequestStatus(
        requestId: json['requestId'] as String,
        status: json['status'] as String,
        latestSeq: json['latestSeq'] as int,
        usageState: json['usageState'] as String,
        finalMessageId: (json['finalMessageId'] == null
            ? null
            : json['finalMessageId'] as String),
      );
  FarmlyJsonMap toJson() {
    final json = <String, dynamic>{
      'requestId': requestId,
      'status': status,
      'latestSeq': latestSeq,
      'usageState': usageState,
      'finalMessageId': finalMessageId,
    }..removeWhere((key, value) => value == null);
    return json;
  }
}

final class FarmlyAiSourceReference {
  const FarmlyAiSourceReference({
    required this.sourceId,
    required this.coverage,
    required this.asOf,
  });
  final String sourceId;
  final String coverage;
  final String asOf;
  factory FarmlyAiSourceReference.fromJson(FarmlyJsonMap json) =>
      FarmlyAiSourceReference(
        sourceId: json['sourceId'] as String,
        coverage: json['coverage'] as String,
        asOf: json['asOf'] as String,
      );
  FarmlyJsonMap toJson() {
    final json = <String, dynamic>{
      'sourceId': sourceId,
      'coverage': coverage,
      'asOf': asOf,
    }..removeWhere((key, value) => value == null);
    return json;
  }
}

final class FarmlyAiRequestStartedData {
  const FarmlyAiRequestStartedData({
    required this.requestId,
    required this.conversationId,
    this.snapshotId,
    required this.asOf,
    required this.modelAlias,
    required this.schemaVersion,
  });
  final String requestId;
  final String conversationId;
  final String? snapshotId;
  final String asOf;
  final String modelAlias;
  final String schemaVersion;
  factory FarmlyAiRequestStartedData.fromJson(FarmlyJsonMap json) =>
      FarmlyAiRequestStartedData(
        requestId: json['requestId'] as String,
        conversationId: json['conversationId'] as String,
        snapshotId: (json['snapshotId'] == null
            ? null
            : json['snapshotId'] as String),
        asOf: json['asOf'] as String,
        modelAlias: json['modelAlias'] as String,
        schemaVersion: json['schemaVersion'] as String,
      );
  FarmlyJsonMap toJson() {
    final json = <String, dynamic>{
      'requestId': requestId,
      'conversationId': conversationId,
      'snapshotId': snapshotId,
      'asOf': asOf,
      'modelAlias': modelAlias,
      'schemaVersion': schemaVersion,
    }..removeWhere((key, value) => value == null);
    return json;
  }
}

final class FarmlyAiResponseDeltaData {
  const FarmlyAiResponseDeltaData({required this.seq, required this.textDelta});
  final int seq;
  final String textDelta;
  factory FarmlyAiResponseDeltaData.fromJson(FarmlyJsonMap json) =>
      FarmlyAiResponseDeltaData(
        seq: json['seq'] as int,
        textDelta: json['textDelta'] as String,
      );
  FarmlyJsonMap toJson() {
    final json = <String, dynamic>{'seq': seq, 'textDelta': textDelta}
      ..removeWhere((key, value) => value == null);
    return json;
  }
}

final class FarmlyAiRequestStatusData {
  const FarmlyAiRequestStatusData({required this.status});
  final String status;
  factory FarmlyAiRequestStatusData.fromJson(FarmlyJsonMap json) =>
      FarmlyAiRequestStatusData(status: json['status'] as String);
  FarmlyJsonMap toJson() {
    final json = <String, dynamic>{'status': status}
      ..removeWhere((key, value) => value == null);
    return json;
  }
}

final class FarmlyAiResponseReferencesData {
  const FarmlyAiResponseReferencesData({required this.references});
  final List<FarmlyAiSourceReference> references;
  factory FarmlyAiResponseReferencesData.fromJson(FarmlyJsonMap json) =>
      FarmlyAiResponseReferencesData(
        references: (json['references'] as List<dynamic>)
            .map(
              (item) => FarmlyAiSourceReference.fromJson(
                Map<String, dynamic>.from(item as Map),
              ),
            )
            .toList(growable: false),
      );
  FarmlyJsonMap toJson() {
    final json = <String, dynamic>{
      'references': references
          .map((item) => item.toJson())
          .toList(growable: false),
    }..removeWhere((key, value) => value == null);
    return json;
  }
}

final class FarmlyAiUsageReportedData {
  const FarmlyAiUsageReportedData({
    required this.usageState,
    this.inputTokens,
    this.outputTokens,
    this.totalTokens,
  });
  final String usageState;
  final int? inputTokens;
  final int? outputTokens;
  final int? totalTokens;
  factory FarmlyAiUsageReportedData.fromJson(FarmlyJsonMap json) =>
      FarmlyAiUsageReportedData(
        usageState: json['usageState'] as String,
        inputTokens: (json['inputTokens'] == null
            ? null
            : json['inputTokens'] as int),
        outputTokens: (json['outputTokens'] == null
            ? null
            : json['outputTokens'] as int),
        totalTokens: (json['totalTokens'] == null
            ? null
            : json['totalTokens'] as int),
      );
  FarmlyJsonMap toJson() {
    final json = <String, dynamic>{
      'usageState': usageState,
      'inputTokens': inputTokens,
      'outputTokens': outputTokens,
      'totalTokens': totalTokens,
    }..removeWhere((key, value) => value == null);
    return json;
  }
}

final class FarmlyAiResponseCompletedData {
  const FarmlyAiResponseCompletedData({
    required this.finalMessageId,
    required this.finishReason,
    this.truncated,
    required this.usageState,
  });
  final String finalMessageId;
  final String finishReason;
  final bool? truncated;
  final String usageState;
  factory FarmlyAiResponseCompletedData.fromJson(FarmlyJsonMap json) =>
      FarmlyAiResponseCompletedData(
        finalMessageId: json['finalMessageId'] as String,
        finishReason: json['finishReason'] as String,
        truncated: (json['truncated'] == null
            ? null
            : json['truncated'] as bool),
        usageState: json['usageState'] as String,
      );
  FarmlyJsonMap toJson() {
    final json = <String, dynamic>{
      'finalMessageId': finalMessageId,
      'finishReason': finishReason,
      'truncated': truncated,
      'usageState': usageState,
    }..removeWhere((key, value) => value == null);
    return json;
  }
}

final class FarmlyAiResponseCancelledData {
  const FarmlyAiResponseCancelledData({this.partial, required this.usageState});
  final bool? partial;
  final String usageState;
  factory FarmlyAiResponseCancelledData.fromJson(FarmlyJsonMap json) =>
      FarmlyAiResponseCancelledData(
        partial: (json['partial'] == null ? null : json['partial'] as bool),
        usageState: json['usageState'] as String,
      );
  FarmlyJsonMap toJson() {
    final json = <String, dynamic>{'partial': partial, 'usageState': usageState}
      ..removeWhere((key, value) => value == null);
    return json;
  }
}

final class FarmlyAiResponseErrorData {
  const FarmlyAiResponseErrorData({
    required this.code,
    required this.retryable,
    this.statusUrl,
  });
  final String code;
  final bool retryable;
  final String? statusUrl;
  factory FarmlyAiResponseErrorData.fromJson(FarmlyJsonMap json) =>
      FarmlyAiResponseErrorData(
        code: json['code'] as String,
        retryable: json['retryable'] as bool,
        statusUrl: (json['statusUrl'] == null
            ? null
            : json['statusUrl'] as String),
      );
  FarmlyJsonMap toJson() {
    final json = <String, dynamic>{
      'code': code,
      'retryable': retryable,
      'statusUrl': statusUrl,
    }..removeWhere((key, value) => value == null);
    return json;
  }
}

final class FarmlyAiEvent {
  const FarmlyAiEvent({
    required this.id,
    required this.requestId,
    required this.seq,
    required this.type,
    required this.data,
  });
  final String id;
  final String requestId;
  final int seq;
  final String type;
  final Map<String, dynamic> data;
  factory FarmlyAiEvent.fromJson(FarmlyJsonMap json) => FarmlyAiEvent(
    id: json['id'] as String,
    requestId: json['requestId'] as String,
    seq: json['seq'] as int,
    type: json['type'] as String,
    data: Map<String, dynamic>.from(json['data'] as Map),
  );
  FarmlyJsonMap toJson() {
    final json = <String, dynamic>{
      'id': id,
      'requestId': requestId,
      'seq': seq,
      'type': type,
      'data': data,
    }..removeWhere((key, value) => value == null);
    return json;
  }
}

final class FarmlyDeviceRegistrationRequest {
  const FarmlyDeviceRegistrationRequest({
    required this.operationId,
    required this.action,
    required this.deviceId,
    this.pushToken,
  });
  final String operationId;
  final String action;
  final String deviceId;
  final String? pushToken;
  factory FarmlyDeviceRegistrationRequest.fromJson(FarmlyJsonMap json) =>
      FarmlyDeviceRegistrationRequest(
        operationId: json['operationId'] as String,
        action: json['action'] as String,
        deviceId: json['deviceId'] as String,
        pushToken: (json['pushToken'] == null
            ? null
            : json['pushToken'] as String),
      );
  FarmlyJsonMap toJson() {
    final json = <String, dynamic>{
      'operationId': operationId,
      'action': action,
      'deviceId': deviceId,
      'pushToken': pushToken,
    }..removeWhere((key, value) => value == null);
    return json;
  }
}

final class FarmlyPrivacyRequest {
  const FarmlyPrivacyRequest({
    required this.operationId,
    required this.action,
    this.confirmation,
  });
  final String operationId;
  final String action;
  final String? confirmation;
  factory FarmlyPrivacyRequest.fromJson(FarmlyJsonMap json) =>
      FarmlyPrivacyRequest(
        operationId: json['operationId'] as String,
        action: json['action'] as String,
        confirmation: (json['confirmation'] == null
            ? null
            : json['confirmation'] as String),
      );
  FarmlyJsonMap toJson() {
    final json = <String, dynamic>{
      'operationId': operationId,
      'action': action,
      'confirmation': confirmation,
    }..removeWhere((key, value) => value == null);
    return json;
  }
}

final class FarmlyAiConsentDecision {
  const FarmlyAiConsentDecision({
    required this.granted,
    this.aiSafeSummaryOptedIn,
  });
  final bool granted;
  final bool? aiSafeSummaryOptedIn;
  factory FarmlyAiConsentDecision.fromJson(FarmlyJsonMap json) =>
      FarmlyAiConsentDecision(
        granted: json['granted'] as bool,
        aiSafeSummaryOptedIn: (json['aiSafeSummaryOptedIn'] == null
            ? null
            : json['aiSafeSummaryOptedIn'] as bool),
      );
  FarmlyJsonMap toJson() {
    final json = <String, dynamic>{
      'granted': granted,
      'aiSafeSummaryOptedIn': aiSafeSummaryOptedIn,
    }..removeWhere((key, value) => value == null);
    return json;
  }
}

final class FarmlyWaterTankDto {
  const FarmlyWaterTankDto({
    required this.id,
    required this.version,
    required this.name,
    required this.zoneId,
    required this.capacityLitres,
    this.storedLitres,
    required this.status,
  });
  final String id;
  final int version;
  final String name;
  final String zoneId;
  final FarmlyDecimal capacityLitres;
  final FarmlyDecimal? storedLitres;
  final String status;
  factory FarmlyWaterTankDto.fromJson(FarmlyJsonMap json) => FarmlyWaterTankDto(
    id: json['id'] as String,
    version: json['version'] as int,
    name: json['name'] as String,
    zoneId: json['zoneId'] as String,
    capacityLitres: FarmlyDecimal.parse(json['capacityLitres'] as String),
    storedLitres: (json['storedLitres'] == null
        ? null
        : FarmlyDecimal.parse(json['storedLitres'] as String)),
    status: json['status'] as String,
  );
  FarmlyJsonMap toJson() {
    final json = <String, dynamic>{
      'id': id,
      'version': version,
      'name': name,
      'zoneId': zoneId,
      'capacityLitres': capacityLitres.value,
      'storedLitres': storedLitres?.value,
      'status': status,
    }..removeWhere((key, value) => value == null);
    return json;
  }
}

final class FarmlyHarvestDto {
  const FarmlyHarvestDto({
    required this.id,
    required this.version,
    required this.quantityKg,
    required this.harvestDate,
    required this.occurredAt,
  });
  final String id;
  final int version;
  final FarmlyDecimal quantityKg;
  final String harvestDate;
  final String occurredAt;
  factory FarmlyHarvestDto.fromJson(FarmlyJsonMap json) => FarmlyHarvestDto(
    id: json['id'] as String,
    version: json['version'] as int,
    quantityKg: FarmlyDecimal.parse(json['quantityKg'] as String),
    harvestDate: json['harvestDate'] as String,
    occurredAt: json['occurredAt'] as String,
  );
  FarmlyJsonMap toJson() {
    final json = <String, dynamic>{
      'id': id,
      'version': version,
      'quantityKg': quantityKg.value,
      'harvestDate': harvestDate,
      'occurredAt': occurredAt,
    }..removeWhere((key, value) => value == null);
    return json;
  }
}

final class FarmlyZonePoint {
  const FarmlyZonePoint({required this.x, required this.y});
  final FarmlyDecimal x;
  final FarmlyDecimal y;
  factory FarmlyZonePoint.fromJson(FarmlyJsonMap json) => FarmlyZonePoint(
    x: FarmlyDecimal.parse(json['x'] as String),
    y: FarmlyDecimal.parse(json['y'] as String),
  );
  FarmlyJsonMap toJson() {
    final json = <String, dynamic>{'x': x.value, 'y': y.value}
      ..removeWhere((key, value) => value == null);
    return json;
  }
}

final class FarmlyZoneGeometry {
  const FarmlyZoneGeometry({required this.points});
  final List<FarmlyZonePoint> points;
  factory FarmlyZoneGeometry.fromJson(FarmlyJsonMap json) => FarmlyZoneGeometry(
    points: (json['points'] as List<dynamic>)
        .map(
          (item) =>
              FarmlyZonePoint.fromJson(Map<String, dynamic>.from(item as Map)),
        )
        .toList(growable: false),
  );
  FarmlyJsonMap toJson() {
    final json = <String, dynamic>{
      'points': points.map((item) => item.toJson()).toList(growable: false),
    }..removeWhere((key, value) => value == null);
    return json;
  }
}

final class FarmlyEmptyMutationPayload {
  const FarmlyEmptyMutationPayload();
  factory FarmlyEmptyMutationPayload.fromJson(FarmlyJsonMap json) =>
      const FarmlyEmptyMutationPayload();
  FarmlyJsonMap toJson() => <String, dynamic>{};
}

final class FarmlyFarmCreatePayload {
  const FarmlyFarmCreatePayload({
    required this.name,
    required this.timezone,
    this.areaM2,
    this.location,
  });
  final String name;
  final String timezone;
  final FarmlyDecimal? areaM2;
  final String? location;
  factory FarmlyFarmCreatePayload.fromJson(FarmlyJsonMap json) =>
      FarmlyFarmCreatePayload(
        name: json['name'] as String,
        timezone: json['timezone'] as String,
        areaM2: (json['areaM2'] == null
            ? null
            : FarmlyDecimal.parse(json['areaM2'] as String)),
        location: (json['location'] == null
            ? null
            : json['location'] as String),
      );
  FarmlyJsonMap toJson() {
    final json = <String, dynamic>{
      'name': name,
      'timezone': timezone,
      'areaM2': areaM2?.value,
      'location': location,
    }..removeWhere((key, value) => value == null);
    return json;
  }
}

final class FarmlyFarmUpdatePayload {
  const FarmlyFarmUpdatePayload({
    this.name,
    this.timezone,
    this.areaM2,
    this.location,
  });
  final String? name;
  final String? timezone;
  final FarmlyDecimal? areaM2;
  final String? location;
  factory FarmlyFarmUpdatePayload.fromJson(
    FarmlyJsonMap json,
  ) => FarmlyFarmUpdatePayload(
    name: (json['name'] == null ? null : json['name'] as String),
    timezone: (json['timezone'] == null ? null : json['timezone'] as String),
    areaM2: (json['areaM2'] == null
        ? null
        : FarmlyDecimal.parse(json['areaM2'] as String)),
    location: (json['location'] == null ? null : json['location'] as String),
  );
  FarmlyJsonMap toJson() {
    final json = <String, dynamic>{
      'name': name,
      'timezone': timezone,
      'areaM2': areaM2?.value,
      'location': location,
    }..removeWhere((key, value) => value == null);
    return json;
  }
}

final class FarmlyZoneCreatePayload {
  const FarmlyZoneCreatePayload({
    required this.name,
    required this.type,
    required this.geometry,
    this.areaM2,
  });
  final String name;
  final String type;
  final FarmlyZoneGeometry geometry;
  final FarmlyDecimal? areaM2;
  factory FarmlyZoneCreatePayload.fromJson(FarmlyJsonMap json) =>
      FarmlyZoneCreatePayload(
        name: json['name'] as String,
        type: json['type'] as String,
        geometry: FarmlyZoneGeometry.fromJson(
          Map<String, dynamic>.from(json['geometry'] as Map),
        ),
        areaM2: (json['areaM2'] == null
            ? null
            : FarmlyDecimal.parse(json['areaM2'] as String)),
      );
  FarmlyJsonMap toJson() {
    final json = <String, dynamic>{
      'name': name,
      'type': type,
      'geometry': geometry.toJson(),
      'areaM2': areaM2?.value,
    }..removeWhere((key, value) => value == null);
    return json;
  }
}

final class FarmlyZoneUpdatePayload {
  const FarmlyZoneUpdatePayload({
    this.name,
    this.type,
    this.geometry,
    this.areaM2,
  });
  final String? name;
  final String? type;
  final FarmlyZoneGeometry? geometry;
  final FarmlyDecimal? areaM2;
  factory FarmlyZoneUpdatePayload.fromJson(FarmlyJsonMap json) =>
      FarmlyZoneUpdatePayload(
        name: (json['name'] == null ? null : json['name'] as String),
        type: (json['type'] == null ? null : json['type'] as String),
        geometry: (json['geometry'] == null
            ? null
            : FarmlyZoneGeometry.fromJson(
                Map<String, dynamic>.from(json['geometry'] as Map),
              )),
        areaM2: (json['areaM2'] == null
            ? null
            : FarmlyDecimal.parse(json['areaM2'] as String)),
      );
  FarmlyJsonMap toJson() {
    final json = <String, dynamic>{
      'name': name,
      'type': type,
      'geometry': geometry?.toJson(),
      'areaM2': areaM2?.value,
    }..removeWhere((key, value) => value == null);
    return json;
  }
}

final class FarmlyCropSpeciesCreatePayload {
  const FarmlyCropSpeciesCreatePayload({
    required this.name,
    required this.harvestUnit,
  });
  final String name;
  final String harvestUnit;
  factory FarmlyCropSpeciesCreatePayload.fromJson(FarmlyJsonMap json) =>
      FarmlyCropSpeciesCreatePayload(
        name: json['name'] as String,
        harvestUnit: json['harvestUnit'] as String,
      );
  FarmlyJsonMap toJson() {
    final json = <String, dynamic>{'name': name, 'harvestUnit': harvestUnit}
      ..removeWhere((key, value) => value == null);
    return json;
  }
}

final class FarmlyCropSpeciesUpdatePayload {
  const FarmlyCropSpeciesUpdatePayload({this.name, this.harvestUnit});
  final String? name;
  final String? harvestUnit;
  factory FarmlyCropSpeciesUpdatePayload.fromJson(FarmlyJsonMap json) =>
      FarmlyCropSpeciesUpdatePayload(
        name: (json['name'] == null ? null : json['name'] as String),
        harvestUnit: (json['harvestUnit'] == null
            ? null
            : json['harvestUnit'] as String),
      );
  FarmlyJsonMap toJson() {
    final json = <String, dynamic>{'name': name, 'harvestUnit': harvestUnit}
      ..removeWhere((key, value) => value == null);
    return json;
  }
}

final class FarmlyPlantingCreatePayload {
  const FarmlyPlantingCreatePayload({
    required this.cropSpeciesId,
    required this.plotId,
    this.status,
    required this.sowingDate,
    this.expectedHarvestDate,
    this.areaM2,
  });
  final String cropSpeciesId;
  final String plotId;
  final String? status;
  final String sowingDate;
  final String? expectedHarvestDate;
  final FarmlyDecimal? areaM2;
  factory FarmlyPlantingCreatePayload.fromJson(FarmlyJsonMap json) =>
      FarmlyPlantingCreatePayload(
        cropSpeciesId: json['cropSpeciesId'] as String,
        plotId: json['plotId'] as String,
        status: (json['status'] == null ? null : json['status'] as String),
        sowingDate: json['sowingDate'] as String,
        expectedHarvestDate: (json['expectedHarvestDate'] == null
            ? null
            : json['expectedHarvestDate'] as String),
        areaM2: (json['areaM2'] == null
            ? null
            : FarmlyDecimal.parse(json['areaM2'] as String)),
      );
  FarmlyJsonMap toJson() {
    final json = <String, dynamic>{
      'cropSpeciesId': cropSpeciesId,
      'plotId': plotId,
      'status': status,
      'sowingDate': sowingDate,
      'expectedHarvestDate': expectedHarvestDate,
      'areaM2': areaM2?.value,
    }..removeWhere((key, value) => value == null);
    return json;
  }
}

final class FarmlyPlantingUpdatePayload {
  const FarmlyPlantingUpdatePayload({
    this.status,
    this.sowingDate,
    this.expectedHarvestDate,
    this.areaM2,
  });
  final String? status;
  final String? sowingDate;
  final String? expectedHarvestDate;
  final FarmlyDecimal? areaM2;
  factory FarmlyPlantingUpdatePayload.fromJson(FarmlyJsonMap json) =>
      FarmlyPlantingUpdatePayload(
        status: (json['status'] == null ? null : json['status'] as String),
        sowingDate: (json['sowingDate'] == null
            ? null
            : json['sowingDate'] as String),
        expectedHarvestDate: (json['expectedHarvestDate'] == null
            ? null
            : json['expectedHarvestDate'] as String),
        areaM2: (json['areaM2'] == null
            ? null
            : FarmlyDecimal.parse(json['areaM2'] as String)),
      );
  FarmlyJsonMap toJson() {
    final json = <String, dynamic>{
      'status': status,
      'sowingDate': sowingDate,
      'expectedHarvestDate': expectedHarvestDate,
      'areaM2': areaM2?.value,
    }..removeWhere((key, value) => value == null);
    return json;
  }
}

final class FarmlyHerdCreatePayload {
  const FarmlyHerdCreatePayload({
    required this.mode,
    this.status,
    this.species,
  });
  final String mode;
  final String? status;
  final String? species;
  factory FarmlyHerdCreatePayload.fromJson(FarmlyJsonMap json) =>
      FarmlyHerdCreatePayload(
        mode: json['mode'] as String,
        status: (json['status'] == null ? null : json['status'] as String),
        species: (json['species'] == null ? null : json['species'] as String),
      );
  FarmlyJsonMap toJson() {
    final json = <String, dynamic>{
      'mode': mode,
      'status': status,
      'species': species,
    }..removeWhere((key, value) => value == null);
    return json;
  }
}

final class FarmlyHerdUpdatePayload {
  const FarmlyHerdUpdatePayload({this.mode, this.status, this.species});
  final String? mode;
  final String? status;
  final String? species;
  factory FarmlyHerdUpdatePayload.fromJson(FarmlyJsonMap json) =>
      FarmlyHerdUpdatePayload(
        mode: (json['mode'] == null ? null : json['mode'] as String),
        status: (json['status'] == null ? null : json['status'] as String),
        species: (json['species'] == null ? null : json['species'] as String),
      );
  FarmlyJsonMap toJson() {
    final json = <String, dynamic>{
      'mode': mode,
      'status': status,
      'species': species,
    }..removeWhere((key, value) => value == null);
    return json;
  }
}

final class FarmlyAnimalCreatePayload {
  const FarmlyAnimalCreatePayload({
    required this.herdId,
    required this.tag,
    this.name,
    this.birthDate,
    this.status,
  });
  final String herdId;
  final String tag;
  final String? name;
  final String? birthDate;
  final String? status;
  factory FarmlyAnimalCreatePayload.fromJson(FarmlyJsonMap json) =>
      FarmlyAnimalCreatePayload(
        herdId: json['herdId'] as String,
        tag: json['tag'] as String,
        name: (json['name'] == null ? null : json['name'] as String),
        birthDate: (json['birthDate'] == null
            ? null
            : json['birthDate'] as String),
        status: (json['status'] == null ? null : json['status'] as String),
      );
  FarmlyJsonMap toJson() {
    final json = <String, dynamic>{
      'herdId': herdId,
      'tag': tag,
      'name': name,
      'birthDate': birthDate,
      'status': status,
    }..removeWhere((key, value) => value == null);
    return json;
  }
}

final class FarmlyAnimalUpdatePayload {
  const FarmlyAnimalUpdatePayload({
    this.tag,
    this.name,
    this.birthDate,
    this.status,
  });
  final String? tag;
  final String? name;
  final String? birthDate;
  final String? status;
  factory FarmlyAnimalUpdatePayload.fromJson(FarmlyJsonMap json) =>
      FarmlyAnimalUpdatePayload(
        tag: (json['tag'] == null ? null : json['tag'] as String),
        name: (json['name'] == null ? null : json['name'] as String),
        birthDate: (json['birthDate'] == null
            ? null
            : json['birthDate'] as String),
        status: (json['status'] == null ? null : json['status'] as String),
      );
  FarmlyJsonMap toJson() {
    final json = <String, dynamic>{
      'tag': tag,
      'name': name,
      'birthDate': birthDate,
      'status': status,
    }..removeWhere((key, value) => value == null);
    return json;
  }
}

final class FarmlyWaterTankCreatePayload {
  const FarmlyWaterTankCreatePayload({
    required this.name,
    required this.zoneId,
    required this.capacityLitres,
  });
  final String name;
  final String zoneId;
  final FarmlyDecimal capacityLitres;
  factory FarmlyWaterTankCreatePayload.fromJson(FarmlyJsonMap json) =>
      FarmlyWaterTankCreatePayload(
        name: json['name'] as String,
        zoneId: json['zoneId'] as String,
        capacityLitres: FarmlyDecimal.parse(json['capacityLitres'] as String),
      );
  FarmlyJsonMap toJson() {
    final json = <String, dynamic>{
      'name': name,
      'zoneId': zoneId,
      'capacityLitres': capacityLitres.value,
    }..removeWhere((key, value) => value == null);
    return json;
  }
}

final class FarmlyWaterTankUpdatePayload {
  const FarmlyWaterTankUpdatePayload({this.name, this.capacityLitres});
  final String? name;
  final FarmlyDecimal? capacityLitres;
  factory FarmlyWaterTankUpdatePayload.fromJson(FarmlyJsonMap json) =>
      FarmlyWaterTankUpdatePayload(
        name: (json['name'] == null ? null : json['name'] as String),
        capacityLitres: (json['capacityLitres'] == null
            ? null
            : FarmlyDecimal.parse(json['capacityLitres'] as String)),
      );
  FarmlyJsonMap toJson() {
    final json = <String, dynamic>{
      'name': name,
      'capacityLitres': capacityLitres?.value,
    }..removeWhere((key, value) => value == null);
    return json;
  }
}

final class FarmlyFarmCreateMutation {
  const FarmlyFarmCreateMutation({
    required this.schemaVersion,
    required this.continuityEpoch,
    required this.operationId,
    required this.type,
    required this.resourceId,
    this.baseVersion,
    required this.dependsOn,
    required this.payload,
  });
  final String schemaVersion;
  final String continuityEpoch;
  final String operationId;
  final String type;
  final String resourceId;
  final String? baseVersion;
  final List<String> dependsOn;
  final FarmlyFarmCreatePayload payload;
  factory FarmlyFarmCreateMutation.fromJson(FarmlyJsonMap json) =>
      FarmlyFarmCreateMutation(
        schemaVersion: json['schemaVersion'] as String,
        continuityEpoch: json['continuityEpoch'] as String,
        operationId: json['operationId'] as String,
        type: json['type'] as String,
        resourceId: json['resourceId'] as String,
        baseVersion: (json['baseVersion'] == null
            ? null
            : json['baseVersion'] as String),
        dependsOn: (json['dependsOn'] as List<dynamic>).cast<String>(),
        payload: FarmlyFarmCreatePayload.fromJson(
          Map<String, dynamic>.from(json['payload'] as Map),
        ),
      );
  FarmlyJsonMap toJson() {
    final json = <String, dynamic>{
      'schemaVersion': schemaVersion,
      'continuityEpoch': continuityEpoch,
      'operationId': operationId,
      'type': type,
      'resourceId': resourceId,
      'baseVersion': baseVersion,
      'dependsOn': dependsOn,
      'payload': payload.toJson(),
    }..removeWhere((key, value) => value == null);
    return json;
  }
}

final class FarmlyFarmUpdateMutation {
  const FarmlyFarmUpdateMutation({
    required this.schemaVersion,
    required this.continuityEpoch,
    required this.operationId,
    required this.type,
    required this.resourceId,
    required this.baseVersion,
    required this.dependsOn,
    required this.payload,
  });
  final String schemaVersion;
  final String continuityEpoch;
  final String operationId;
  final String type;
  final String resourceId;
  final int baseVersion;
  final List<String> dependsOn;
  final FarmlyFarmUpdatePayload payload;
  factory FarmlyFarmUpdateMutation.fromJson(FarmlyJsonMap json) =>
      FarmlyFarmUpdateMutation(
        schemaVersion: json['schemaVersion'] as String,
        continuityEpoch: json['continuityEpoch'] as String,
        operationId: json['operationId'] as String,
        type: json['type'] as String,
        resourceId: json['resourceId'] as String,
        baseVersion: json['baseVersion'] as int,
        dependsOn: (json['dependsOn'] as List<dynamic>).cast<String>(),
        payload: FarmlyFarmUpdatePayload.fromJson(
          Map<String, dynamic>.from(json['payload'] as Map),
        ),
      );
  FarmlyJsonMap toJson() {
    final json = <String, dynamic>{
      'schemaVersion': schemaVersion,
      'continuityEpoch': continuityEpoch,
      'operationId': operationId,
      'type': type,
      'resourceId': resourceId,
      'baseVersion': baseVersion,
      'dependsOn': dependsOn,
      'payload': payload.toJson(),
    }..removeWhere((key, value) => value == null);
    return json;
  }
}

final class FarmlyFarmArchiveMutation {
  const FarmlyFarmArchiveMutation({
    required this.schemaVersion,
    required this.continuityEpoch,
    required this.operationId,
    required this.type,
    required this.resourceId,
    required this.baseVersion,
    required this.dependsOn,
    required this.payload,
  });
  final String schemaVersion;
  final String continuityEpoch;
  final String operationId;
  final String type;
  final String resourceId;
  final int baseVersion;
  final List<String> dependsOn;
  final FarmlyEmptyMutationPayload payload;
  factory FarmlyFarmArchiveMutation.fromJson(FarmlyJsonMap json) =>
      FarmlyFarmArchiveMutation(
        schemaVersion: json['schemaVersion'] as String,
        continuityEpoch: json['continuityEpoch'] as String,
        operationId: json['operationId'] as String,
        type: json['type'] as String,
        resourceId: json['resourceId'] as String,
        baseVersion: json['baseVersion'] as int,
        dependsOn: (json['dependsOn'] as List<dynamic>).cast<String>(),
        payload: FarmlyEmptyMutationPayload.fromJson(
          Map<String, dynamic>.from(json['payload'] as Map),
        ),
      );
  FarmlyJsonMap toJson() {
    final json = <String, dynamic>{
      'schemaVersion': schemaVersion,
      'continuityEpoch': continuityEpoch,
      'operationId': operationId,
      'type': type,
      'resourceId': resourceId,
      'baseVersion': baseVersion,
      'dependsOn': dependsOn,
      'payload': payload.toJson(),
    }..removeWhere((key, value) => value == null);
    return json;
  }
}

final class FarmlyZoneCreateMutation {
  const FarmlyZoneCreateMutation({
    required this.schemaVersion,
    required this.continuityEpoch,
    required this.operationId,
    required this.type,
    required this.resourceId,
    this.baseVersion,
    required this.dependsOn,
    required this.payload,
  });
  final String schemaVersion;
  final String continuityEpoch;
  final String operationId;
  final String type;
  final String resourceId;
  final String? baseVersion;
  final List<String> dependsOn;
  final FarmlyZoneCreatePayload payload;
  factory FarmlyZoneCreateMutation.fromJson(FarmlyJsonMap json) =>
      FarmlyZoneCreateMutation(
        schemaVersion: json['schemaVersion'] as String,
        continuityEpoch: json['continuityEpoch'] as String,
        operationId: json['operationId'] as String,
        type: json['type'] as String,
        resourceId: json['resourceId'] as String,
        baseVersion: (json['baseVersion'] == null
            ? null
            : json['baseVersion'] as String),
        dependsOn: (json['dependsOn'] as List<dynamic>).cast<String>(),
        payload: FarmlyZoneCreatePayload.fromJson(
          Map<String, dynamic>.from(json['payload'] as Map),
        ),
      );
  FarmlyJsonMap toJson() {
    final json = <String, dynamic>{
      'schemaVersion': schemaVersion,
      'continuityEpoch': continuityEpoch,
      'operationId': operationId,
      'type': type,
      'resourceId': resourceId,
      'baseVersion': baseVersion,
      'dependsOn': dependsOn,
      'payload': payload.toJson(),
    }..removeWhere((key, value) => value == null);
    return json;
  }
}

final class FarmlyZoneUpdateMutation {
  const FarmlyZoneUpdateMutation({
    required this.schemaVersion,
    required this.continuityEpoch,
    required this.operationId,
    required this.type,
    required this.resourceId,
    required this.baseVersion,
    required this.dependsOn,
    required this.payload,
  });
  final String schemaVersion;
  final String continuityEpoch;
  final String operationId;
  final String type;
  final String resourceId;
  final int baseVersion;
  final List<String> dependsOn;
  final FarmlyZoneUpdatePayload payload;
  factory FarmlyZoneUpdateMutation.fromJson(FarmlyJsonMap json) =>
      FarmlyZoneUpdateMutation(
        schemaVersion: json['schemaVersion'] as String,
        continuityEpoch: json['continuityEpoch'] as String,
        operationId: json['operationId'] as String,
        type: json['type'] as String,
        resourceId: json['resourceId'] as String,
        baseVersion: json['baseVersion'] as int,
        dependsOn: (json['dependsOn'] as List<dynamic>).cast<String>(),
        payload: FarmlyZoneUpdatePayload.fromJson(
          Map<String, dynamic>.from(json['payload'] as Map),
        ),
      );
  FarmlyJsonMap toJson() {
    final json = <String, dynamic>{
      'schemaVersion': schemaVersion,
      'continuityEpoch': continuityEpoch,
      'operationId': operationId,
      'type': type,
      'resourceId': resourceId,
      'baseVersion': baseVersion,
      'dependsOn': dependsOn,
      'payload': payload.toJson(),
    }..removeWhere((key, value) => value == null);
    return json;
  }
}

final class FarmlyZoneArchiveMutation {
  const FarmlyZoneArchiveMutation({
    required this.schemaVersion,
    required this.continuityEpoch,
    required this.operationId,
    required this.type,
    required this.resourceId,
    required this.baseVersion,
    required this.dependsOn,
    required this.payload,
  });
  final String schemaVersion;
  final String continuityEpoch;
  final String operationId;
  final String type;
  final String resourceId;
  final int baseVersion;
  final List<String> dependsOn;
  final FarmlyEmptyMutationPayload payload;
  factory FarmlyZoneArchiveMutation.fromJson(FarmlyJsonMap json) =>
      FarmlyZoneArchiveMutation(
        schemaVersion: json['schemaVersion'] as String,
        continuityEpoch: json['continuityEpoch'] as String,
        operationId: json['operationId'] as String,
        type: json['type'] as String,
        resourceId: json['resourceId'] as String,
        baseVersion: json['baseVersion'] as int,
        dependsOn: (json['dependsOn'] as List<dynamic>).cast<String>(),
        payload: FarmlyEmptyMutationPayload.fromJson(
          Map<String, dynamic>.from(json['payload'] as Map),
        ),
      );
  FarmlyJsonMap toJson() {
    final json = <String, dynamic>{
      'schemaVersion': schemaVersion,
      'continuityEpoch': continuityEpoch,
      'operationId': operationId,
      'type': type,
      'resourceId': resourceId,
      'baseVersion': baseVersion,
      'dependsOn': dependsOn,
      'payload': payload.toJson(),
    }..removeWhere((key, value) => value == null);
    return json;
  }
}

final class FarmlyCropSpeciesCreateMutation {
  const FarmlyCropSpeciesCreateMutation({
    required this.schemaVersion,
    required this.continuityEpoch,
    required this.operationId,
    required this.type,
    required this.resourceId,
    this.baseVersion,
    required this.dependsOn,
    required this.payload,
  });
  final String schemaVersion;
  final String continuityEpoch;
  final String operationId;
  final String type;
  final String resourceId;
  final String? baseVersion;
  final List<String> dependsOn;
  final FarmlyCropSpeciesCreatePayload payload;
  factory FarmlyCropSpeciesCreateMutation.fromJson(FarmlyJsonMap json) =>
      FarmlyCropSpeciesCreateMutation(
        schemaVersion: json['schemaVersion'] as String,
        continuityEpoch: json['continuityEpoch'] as String,
        operationId: json['operationId'] as String,
        type: json['type'] as String,
        resourceId: json['resourceId'] as String,
        baseVersion: (json['baseVersion'] == null
            ? null
            : json['baseVersion'] as String),
        dependsOn: (json['dependsOn'] as List<dynamic>).cast<String>(),
        payload: FarmlyCropSpeciesCreatePayload.fromJson(
          Map<String, dynamic>.from(json['payload'] as Map),
        ),
      );
  FarmlyJsonMap toJson() {
    final json = <String, dynamic>{
      'schemaVersion': schemaVersion,
      'continuityEpoch': continuityEpoch,
      'operationId': operationId,
      'type': type,
      'resourceId': resourceId,
      'baseVersion': baseVersion,
      'dependsOn': dependsOn,
      'payload': payload.toJson(),
    }..removeWhere((key, value) => value == null);
    return json;
  }
}

final class FarmlyCropSpeciesUpdateMutation {
  const FarmlyCropSpeciesUpdateMutation({
    required this.schemaVersion,
    required this.continuityEpoch,
    required this.operationId,
    required this.type,
    required this.resourceId,
    required this.baseVersion,
    required this.dependsOn,
    required this.payload,
  });
  final String schemaVersion;
  final String continuityEpoch;
  final String operationId;
  final String type;
  final String resourceId;
  final int baseVersion;
  final List<String> dependsOn;
  final FarmlyCropSpeciesUpdatePayload payload;
  factory FarmlyCropSpeciesUpdateMutation.fromJson(FarmlyJsonMap json) =>
      FarmlyCropSpeciesUpdateMutation(
        schemaVersion: json['schemaVersion'] as String,
        continuityEpoch: json['continuityEpoch'] as String,
        operationId: json['operationId'] as String,
        type: json['type'] as String,
        resourceId: json['resourceId'] as String,
        baseVersion: json['baseVersion'] as int,
        dependsOn: (json['dependsOn'] as List<dynamic>).cast<String>(),
        payload: FarmlyCropSpeciesUpdatePayload.fromJson(
          Map<String, dynamic>.from(json['payload'] as Map),
        ),
      );
  FarmlyJsonMap toJson() {
    final json = <String, dynamic>{
      'schemaVersion': schemaVersion,
      'continuityEpoch': continuityEpoch,
      'operationId': operationId,
      'type': type,
      'resourceId': resourceId,
      'baseVersion': baseVersion,
      'dependsOn': dependsOn,
      'payload': payload.toJson(),
    }..removeWhere((key, value) => value == null);
    return json;
  }
}

final class FarmlyCropSpeciesArchiveMutation {
  const FarmlyCropSpeciesArchiveMutation({
    required this.schemaVersion,
    required this.continuityEpoch,
    required this.operationId,
    required this.type,
    required this.resourceId,
    required this.baseVersion,
    required this.dependsOn,
    required this.payload,
  });
  final String schemaVersion;
  final String continuityEpoch;
  final String operationId;
  final String type;
  final String resourceId;
  final int baseVersion;
  final List<String> dependsOn;
  final FarmlyEmptyMutationPayload payload;
  factory FarmlyCropSpeciesArchiveMutation.fromJson(FarmlyJsonMap json) =>
      FarmlyCropSpeciesArchiveMutation(
        schemaVersion: json['schemaVersion'] as String,
        continuityEpoch: json['continuityEpoch'] as String,
        operationId: json['operationId'] as String,
        type: json['type'] as String,
        resourceId: json['resourceId'] as String,
        baseVersion: json['baseVersion'] as int,
        dependsOn: (json['dependsOn'] as List<dynamic>).cast<String>(),
        payload: FarmlyEmptyMutationPayload.fromJson(
          Map<String, dynamic>.from(json['payload'] as Map),
        ),
      );
  FarmlyJsonMap toJson() {
    final json = <String, dynamic>{
      'schemaVersion': schemaVersion,
      'continuityEpoch': continuityEpoch,
      'operationId': operationId,
      'type': type,
      'resourceId': resourceId,
      'baseVersion': baseVersion,
      'dependsOn': dependsOn,
      'payload': payload.toJson(),
    }..removeWhere((key, value) => value == null);
    return json;
  }
}

final class FarmlyPlantingCreateMutation {
  const FarmlyPlantingCreateMutation({
    required this.schemaVersion,
    required this.continuityEpoch,
    required this.operationId,
    required this.type,
    required this.resourceId,
    this.baseVersion,
    required this.dependsOn,
    required this.payload,
  });
  final String schemaVersion;
  final String continuityEpoch;
  final String operationId;
  final String type;
  final String resourceId;
  final String? baseVersion;
  final List<String> dependsOn;
  final FarmlyPlantingCreatePayload payload;
  factory FarmlyPlantingCreateMutation.fromJson(FarmlyJsonMap json) =>
      FarmlyPlantingCreateMutation(
        schemaVersion: json['schemaVersion'] as String,
        continuityEpoch: json['continuityEpoch'] as String,
        operationId: json['operationId'] as String,
        type: json['type'] as String,
        resourceId: json['resourceId'] as String,
        baseVersion: (json['baseVersion'] == null
            ? null
            : json['baseVersion'] as String),
        dependsOn: (json['dependsOn'] as List<dynamic>).cast<String>(),
        payload: FarmlyPlantingCreatePayload.fromJson(
          Map<String, dynamic>.from(json['payload'] as Map),
        ),
      );
  FarmlyJsonMap toJson() {
    final json = <String, dynamic>{
      'schemaVersion': schemaVersion,
      'continuityEpoch': continuityEpoch,
      'operationId': operationId,
      'type': type,
      'resourceId': resourceId,
      'baseVersion': baseVersion,
      'dependsOn': dependsOn,
      'payload': payload.toJson(),
    }..removeWhere((key, value) => value == null);
    return json;
  }
}

final class FarmlyPlantingUpdateMutation {
  const FarmlyPlantingUpdateMutation({
    required this.schemaVersion,
    required this.continuityEpoch,
    required this.operationId,
    required this.type,
    required this.resourceId,
    required this.baseVersion,
    required this.dependsOn,
    required this.payload,
  });
  final String schemaVersion;
  final String continuityEpoch;
  final String operationId;
  final String type;
  final String resourceId;
  final int baseVersion;
  final List<String> dependsOn;
  final FarmlyPlantingUpdatePayload payload;
  factory FarmlyPlantingUpdateMutation.fromJson(FarmlyJsonMap json) =>
      FarmlyPlantingUpdateMutation(
        schemaVersion: json['schemaVersion'] as String,
        continuityEpoch: json['continuityEpoch'] as String,
        operationId: json['operationId'] as String,
        type: json['type'] as String,
        resourceId: json['resourceId'] as String,
        baseVersion: json['baseVersion'] as int,
        dependsOn: (json['dependsOn'] as List<dynamic>).cast<String>(),
        payload: FarmlyPlantingUpdatePayload.fromJson(
          Map<String, dynamic>.from(json['payload'] as Map),
        ),
      );
  FarmlyJsonMap toJson() {
    final json = <String, dynamic>{
      'schemaVersion': schemaVersion,
      'continuityEpoch': continuityEpoch,
      'operationId': operationId,
      'type': type,
      'resourceId': resourceId,
      'baseVersion': baseVersion,
      'dependsOn': dependsOn,
      'payload': payload.toJson(),
    }..removeWhere((key, value) => value == null);
    return json;
  }
}

final class FarmlyPlantingArchiveMutation {
  const FarmlyPlantingArchiveMutation({
    required this.schemaVersion,
    required this.continuityEpoch,
    required this.operationId,
    required this.type,
    required this.resourceId,
    required this.baseVersion,
    required this.dependsOn,
    required this.payload,
  });
  final String schemaVersion;
  final String continuityEpoch;
  final String operationId;
  final String type;
  final String resourceId;
  final int baseVersion;
  final List<String> dependsOn;
  final FarmlyEmptyMutationPayload payload;
  factory FarmlyPlantingArchiveMutation.fromJson(FarmlyJsonMap json) =>
      FarmlyPlantingArchiveMutation(
        schemaVersion: json['schemaVersion'] as String,
        continuityEpoch: json['continuityEpoch'] as String,
        operationId: json['operationId'] as String,
        type: json['type'] as String,
        resourceId: json['resourceId'] as String,
        baseVersion: json['baseVersion'] as int,
        dependsOn: (json['dependsOn'] as List<dynamic>).cast<String>(),
        payload: FarmlyEmptyMutationPayload.fromJson(
          Map<String, dynamic>.from(json['payload'] as Map),
        ),
      );
  FarmlyJsonMap toJson() {
    final json = <String, dynamic>{
      'schemaVersion': schemaVersion,
      'continuityEpoch': continuityEpoch,
      'operationId': operationId,
      'type': type,
      'resourceId': resourceId,
      'baseVersion': baseVersion,
      'dependsOn': dependsOn,
      'payload': payload.toJson(),
    }..removeWhere((key, value) => value == null);
    return json;
  }
}

final class FarmlyHerdCreateMutation {
  const FarmlyHerdCreateMutation({
    required this.schemaVersion,
    required this.continuityEpoch,
    required this.operationId,
    required this.type,
    required this.resourceId,
    this.baseVersion,
    required this.dependsOn,
    required this.payload,
  });
  final String schemaVersion;
  final String continuityEpoch;
  final String operationId;
  final String type;
  final String resourceId;
  final String? baseVersion;
  final List<String> dependsOn;
  final FarmlyHerdCreatePayload payload;
  factory FarmlyHerdCreateMutation.fromJson(FarmlyJsonMap json) =>
      FarmlyHerdCreateMutation(
        schemaVersion: json['schemaVersion'] as String,
        continuityEpoch: json['continuityEpoch'] as String,
        operationId: json['operationId'] as String,
        type: json['type'] as String,
        resourceId: json['resourceId'] as String,
        baseVersion: (json['baseVersion'] == null
            ? null
            : json['baseVersion'] as String),
        dependsOn: (json['dependsOn'] as List<dynamic>).cast<String>(),
        payload: FarmlyHerdCreatePayload.fromJson(
          Map<String, dynamic>.from(json['payload'] as Map),
        ),
      );
  FarmlyJsonMap toJson() {
    final json = <String, dynamic>{
      'schemaVersion': schemaVersion,
      'continuityEpoch': continuityEpoch,
      'operationId': operationId,
      'type': type,
      'resourceId': resourceId,
      'baseVersion': baseVersion,
      'dependsOn': dependsOn,
      'payload': payload.toJson(),
    }..removeWhere((key, value) => value == null);
    return json;
  }
}

final class FarmlyHerdUpdateMutation {
  const FarmlyHerdUpdateMutation({
    required this.schemaVersion,
    required this.continuityEpoch,
    required this.operationId,
    required this.type,
    required this.resourceId,
    required this.baseVersion,
    required this.dependsOn,
    required this.payload,
  });
  final String schemaVersion;
  final String continuityEpoch;
  final String operationId;
  final String type;
  final String resourceId;
  final int baseVersion;
  final List<String> dependsOn;
  final FarmlyHerdUpdatePayload payload;
  factory FarmlyHerdUpdateMutation.fromJson(FarmlyJsonMap json) =>
      FarmlyHerdUpdateMutation(
        schemaVersion: json['schemaVersion'] as String,
        continuityEpoch: json['continuityEpoch'] as String,
        operationId: json['operationId'] as String,
        type: json['type'] as String,
        resourceId: json['resourceId'] as String,
        baseVersion: json['baseVersion'] as int,
        dependsOn: (json['dependsOn'] as List<dynamic>).cast<String>(),
        payload: FarmlyHerdUpdatePayload.fromJson(
          Map<String, dynamic>.from(json['payload'] as Map),
        ),
      );
  FarmlyJsonMap toJson() {
    final json = <String, dynamic>{
      'schemaVersion': schemaVersion,
      'continuityEpoch': continuityEpoch,
      'operationId': operationId,
      'type': type,
      'resourceId': resourceId,
      'baseVersion': baseVersion,
      'dependsOn': dependsOn,
      'payload': payload.toJson(),
    }..removeWhere((key, value) => value == null);
    return json;
  }
}

final class FarmlyHerdArchiveMutation {
  const FarmlyHerdArchiveMutation({
    required this.schemaVersion,
    required this.continuityEpoch,
    required this.operationId,
    required this.type,
    required this.resourceId,
    required this.baseVersion,
    required this.dependsOn,
    required this.payload,
  });
  final String schemaVersion;
  final String continuityEpoch;
  final String operationId;
  final String type;
  final String resourceId;
  final int baseVersion;
  final List<String> dependsOn;
  final FarmlyEmptyMutationPayload payload;
  factory FarmlyHerdArchiveMutation.fromJson(FarmlyJsonMap json) =>
      FarmlyHerdArchiveMutation(
        schemaVersion: json['schemaVersion'] as String,
        continuityEpoch: json['continuityEpoch'] as String,
        operationId: json['operationId'] as String,
        type: json['type'] as String,
        resourceId: json['resourceId'] as String,
        baseVersion: json['baseVersion'] as int,
        dependsOn: (json['dependsOn'] as List<dynamic>).cast<String>(),
        payload: FarmlyEmptyMutationPayload.fromJson(
          Map<String, dynamic>.from(json['payload'] as Map),
        ),
      );
  FarmlyJsonMap toJson() {
    final json = <String, dynamic>{
      'schemaVersion': schemaVersion,
      'continuityEpoch': continuityEpoch,
      'operationId': operationId,
      'type': type,
      'resourceId': resourceId,
      'baseVersion': baseVersion,
      'dependsOn': dependsOn,
      'payload': payload.toJson(),
    }..removeWhere((key, value) => value == null);
    return json;
  }
}

final class FarmlyAnimalCreateMutation {
  const FarmlyAnimalCreateMutation({
    required this.schemaVersion,
    required this.continuityEpoch,
    required this.operationId,
    required this.type,
    required this.resourceId,
    this.baseVersion,
    required this.dependsOn,
    required this.payload,
  });
  final String schemaVersion;
  final String continuityEpoch;
  final String operationId;
  final String type;
  final String resourceId;
  final String? baseVersion;
  final List<String> dependsOn;
  final FarmlyAnimalCreatePayload payload;
  factory FarmlyAnimalCreateMutation.fromJson(FarmlyJsonMap json) =>
      FarmlyAnimalCreateMutation(
        schemaVersion: json['schemaVersion'] as String,
        continuityEpoch: json['continuityEpoch'] as String,
        operationId: json['operationId'] as String,
        type: json['type'] as String,
        resourceId: json['resourceId'] as String,
        baseVersion: (json['baseVersion'] == null
            ? null
            : json['baseVersion'] as String),
        dependsOn: (json['dependsOn'] as List<dynamic>).cast<String>(),
        payload: FarmlyAnimalCreatePayload.fromJson(
          Map<String, dynamic>.from(json['payload'] as Map),
        ),
      );
  FarmlyJsonMap toJson() {
    final json = <String, dynamic>{
      'schemaVersion': schemaVersion,
      'continuityEpoch': continuityEpoch,
      'operationId': operationId,
      'type': type,
      'resourceId': resourceId,
      'baseVersion': baseVersion,
      'dependsOn': dependsOn,
      'payload': payload.toJson(),
    }..removeWhere((key, value) => value == null);
    return json;
  }
}

final class FarmlyAnimalUpdateMutation {
  const FarmlyAnimalUpdateMutation({
    required this.schemaVersion,
    required this.continuityEpoch,
    required this.operationId,
    required this.type,
    required this.resourceId,
    required this.baseVersion,
    required this.dependsOn,
    required this.payload,
  });
  final String schemaVersion;
  final String continuityEpoch;
  final String operationId;
  final String type;
  final String resourceId;
  final int baseVersion;
  final List<String> dependsOn;
  final FarmlyAnimalUpdatePayload payload;
  factory FarmlyAnimalUpdateMutation.fromJson(FarmlyJsonMap json) =>
      FarmlyAnimalUpdateMutation(
        schemaVersion: json['schemaVersion'] as String,
        continuityEpoch: json['continuityEpoch'] as String,
        operationId: json['operationId'] as String,
        type: json['type'] as String,
        resourceId: json['resourceId'] as String,
        baseVersion: json['baseVersion'] as int,
        dependsOn: (json['dependsOn'] as List<dynamic>).cast<String>(),
        payload: FarmlyAnimalUpdatePayload.fromJson(
          Map<String, dynamic>.from(json['payload'] as Map),
        ),
      );
  FarmlyJsonMap toJson() {
    final json = <String, dynamic>{
      'schemaVersion': schemaVersion,
      'continuityEpoch': continuityEpoch,
      'operationId': operationId,
      'type': type,
      'resourceId': resourceId,
      'baseVersion': baseVersion,
      'dependsOn': dependsOn,
      'payload': payload.toJson(),
    }..removeWhere((key, value) => value == null);
    return json;
  }
}

final class FarmlyAnimalArchiveMutation {
  const FarmlyAnimalArchiveMutation({
    required this.schemaVersion,
    required this.continuityEpoch,
    required this.operationId,
    required this.type,
    required this.resourceId,
    required this.baseVersion,
    required this.dependsOn,
    required this.payload,
  });
  final String schemaVersion;
  final String continuityEpoch;
  final String operationId;
  final String type;
  final String resourceId;
  final int baseVersion;
  final List<String> dependsOn;
  final FarmlyEmptyMutationPayload payload;
  factory FarmlyAnimalArchiveMutation.fromJson(FarmlyJsonMap json) =>
      FarmlyAnimalArchiveMutation(
        schemaVersion: json['schemaVersion'] as String,
        continuityEpoch: json['continuityEpoch'] as String,
        operationId: json['operationId'] as String,
        type: json['type'] as String,
        resourceId: json['resourceId'] as String,
        baseVersion: json['baseVersion'] as int,
        dependsOn: (json['dependsOn'] as List<dynamic>).cast<String>(),
        payload: FarmlyEmptyMutationPayload.fromJson(
          Map<String, dynamic>.from(json['payload'] as Map),
        ),
      );
  FarmlyJsonMap toJson() {
    final json = <String, dynamic>{
      'schemaVersion': schemaVersion,
      'continuityEpoch': continuityEpoch,
      'operationId': operationId,
      'type': type,
      'resourceId': resourceId,
      'baseVersion': baseVersion,
      'dependsOn': dependsOn,
      'payload': payload.toJson(),
    }..removeWhere((key, value) => value == null);
    return json;
  }
}

final class FarmlyWaterTankCreateMutation {
  const FarmlyWaterTankCreateMutation({
    required this.schemaVersion,
    required this.continuityEpoch,
    required this.operationId,
    required this.type,
    required this.resourceId,
    this.baseVersion,
    required this.dependsOn,
    required this.payload,
  });
  final String schemaVersion;
  final String continuityEpoch;
  final String operationId;
  final String type;
  final String resourceId;
  final String? baseVersion;
  final List<String> dependsOn;
  final FarmlyWaterTankCreatePayload payload;
  factory FarmlyWaterTankCreateMutation.fromJson(FarmlyJsonMap json) =>
      FarmlyWaterTankCreateMutation(
        schemaVersion: json['schemaVersion'] as String,
        continuityEpoch: json['continuityEpoch'] as String,
        operationId: json['operationId'] as String,
        type: json['type'] as String,
        resourceId: json['resourceId'] as String,
        baseVersion: (json['baseVersion'] == null
            ? null
            : json['baseVersion'] as String),
        dependsOn: (json['dependsOn'] as List<dynamic>).cast<String>(),
        payload: FarmlyWaterTankCreatePayload.fromJson(
          Map<String, dynamic>.from(json['payload'] as Map),
        ),
      );
  FarmlyJsonMap toJson() {
    final json = <String, dynamic>{
      'schemaVersion': schemaVersion,
      'continuityEpoch': continuityEpoch,
      'operationId': operationId,
      'type': type,
      'resourceId': resourceId,
      'baseVersion': baseVersion,
      'dependsOn': dependsOn,
      'payload': payload.toJson(),
    }..removeWhere((key, value) => value == null);
    return json;
  }
}

final class FarmlyWaterTankUpdateMutation {
  const FarmlyWaterTankUpdateMutation({
    required this.schemaVersion,
    required this.continuityEpoch,
    required this.operationId,
    required this.type,
    required this.resourceId,
    required this.baseVersion,
    required this.dependsOn,
    required this.payload,
  });
  final String schemaVersion;
  final String continuityEpoch;
  final String operationId;
  final String type;
  final String resourceId;
  final int baseVersion;
  final List<String> dependsOn;
  final FarmlyWaterTankUpdatePayload payload;
  factory FarmlyWaterTankUpdateMutation.fromJson(FarmlyJsonMap json) =>
      FarmlyWaterTankUpdateMutation(
        schemaVersion: json['schemaVersion'] as String,
        continuityEpoch: json['continuityEpoch'] as String,
        operationId: json['operationId'] as String,
        type: json['type'] as String,
        resourceId: json['resourceId'] as String,
        baseVersion: json['baseVersion'] as int,
        dependsOn: (json['dependsOn'] as List<dynamic>).cast<String>(),
        payload: FarmlyWaterTankUpdatePayload.fromJson(
          Map<String, dynamic>.from(json['payload'] as Map),
        ),
      );
  FarmlyJsonMap toJson() {
    final json = <String, dynamic>{
      'schemaVersion': schemaVersion,
      'continuityEpoch': continuityEpoch,
      'operationId': operationId,
      'type': type,
      'resourceId': resourceId,
      'baseVersion': baseVersion,
      'dependsOn': dependsOn,
      'payload': payload.toJson(),
    }..removeWhere((key, value) => value == null);
    return json;
  }
}

final class FarmlyFarmDto {
  const FarmlyFarmDto({
    required this.farmId,
    required this.name,
    this.areaM2,
    required this.timezone,
    this.location,
    required this.status,
    required this.version,
  });
  final String farmId;
  final String name;
  final FarmlyDecimal? areaM2;
  final String timezone;
  final String? location;
  final String status;
  final int version;
  factory FarmlyFarmDto.fromJson(FarmlyJsonMap json) => FarmlyFarmDto(
    farmId: json['farmId'] as String,
    name: json['name'] as String,
    areaM2: (json['areaM2'] == null
        ? null
        : FarmlyDecimal.parse(json['areaM2'] as String)),
    timezone: json['timezone'] as String,
    location: (json['location'] == null ? null : json['location'] as String),
    status: json['status'] as String,
    version: json['version'] as int,
  );
  FarmlyJsonMap toJson() {
    final json = <String, dynamic>{
      'farmId': farmId,
      'name': name,
      'areaM2': areaM2?.value,
      'timezone': timezone,
      'location': location,
      'status': status,
      'version': version,
    }..removeWhere((key, value) => value == null);
    return json;
  }
}

final class FarmlyZoneDto {
  const FarmlyZoneDto({
    required this.id,
    required this.version,
    required this.type,
    required this.name,
    required this.geometry,
    this.areaM2,
    required this.status,
  });
  final String id;
  final int version;
  final String type;
  final String name;
  final FarmlyZoneGeometry geometry;
  final FarmlyDecimal? areaM2;
  final String status;
  factory FarmlyZoneDto.fromJson(FarmlyJsonMap json) => FarmlyZoneDto(
    id: json['id'] as String,
    version: json['version'] as int,
    type: json['type'] as String,
    name: json['name'] as String,
    geometry: FarmlyZoneGeometry.fromJson(
      Map<String, dynamic>.from(json['geometry'] as Map),
    ),
    areaM2: (json['areaM2'] == null
        ? null
        : FarmlyDecimal.parse(json['areaM2'] as String)),
    status: json['status'] as String,
  );
  FarmlyJsonMap toJson() {
    final json = <String, dynamic>{
      'id': id,
      'version': version,
      'type': type,
      'name': name,
      'geometry': geometry.toJson(),
      'areaM2': areaM2?.value,
      'status': status,
    }..removeWhere((key, value) => value == null);
    return json;
  }
}

final class FarmlyCropSpeciesDto {
  const FarmlyCropSpeciesDto({
    required this.id,
    required this.version,
    required this.name,
    required this.harvestUnit,
    required this.status,
  });
  final String id;
  final int version;
  final String name;
  final String harvestUnit;
  final String status;
  factory FarmlyCropSpeciesDto.fromJson(FarmlyJsonMap json) =>
      FarmlyCropSpeciesDto(
        id: json['id'] as String,
        version: json['version'] as int,
        name: json['name'] as String,
        harvestUnit: json['harvestUnit'] as String,
        status: json['status'] as String,
      );
  FarmlyJsonMap toJson() {
    final json = <String, dynamic>{
      'id': id,
      'version': version,
      'name': name,
      'harvestUnit': harvestUnit,
      'status': status,
    }..removeWhere((key, value) => value == null);
    return json;
  }
}

final class FarmlyPlantingDto {
  const FarmlyPlantingDto({
    required this.id,
    required this.version,
    required this.cropSpeciesId,
    required this.plotId,
    required this.status,
    required this.sowingDate,
    this.expectedHarvestDate,
    this.areaM2,
  });
  final String id;
  final int version;
  final String cropSpeciesId;
  final String plotId;
  final String status;
  final String sowingDate;
  final String? expectedHarvestDate;
  final FarmlyDecimal? areaM2;
  factory FarmlyPlantingDto.fromJson(FarmlyJsonMap json) => FarmlyPlantingDto(
    id: json['id'] as String,
    version: json['version'] as int,
    cropSpeciesId: json['cropSpeciesId'] as String,
    plotId: json['plotId'] as String,
    status: json['status'] as String,
    sowingDate: json['sowingDate'] as String,
    expectedHarvestDate: (json['expectedHarvestDate'] == null
        ? null
        : json['expectedHarvestDate'] as String),
    areaM2: (json['areaM2'] == null
        ? null
        : FarmlyDecimal.parse(json['areaM2'] as String)),
  );
  FarmlyJsonMap toJson() {
    final json = <String, dynamic>{
      'id': id,
      'version': version,
      'cropSpeciesId': cropSpeciesId,
      'plotId': plotId,
      'status': status,
      'sowingDate': sowingDate,
      'expectedHarvestDate': expectedHarvestDate,
      'areaM2': areaM2?.value,
    }..removeWhere((key, value) => value == null);
    return json;
  }
}

final class FarmlyHerdDto {
  const FarmlyHerdDto({
    required this.id,
    required this.version,
    required this.mode,
    this.species,
    required this.status,
    required this.headcount,
  });
  final String id;
  final int version;
  final String mode;
  final String? species;
  final String status;
  final int headcount;
  factory FarmlyHerdDto.fromJson(FarmlyJsonMap json) => FarmlyHerdDto(
    id: json['id'] as String,
    version: json['version'] as int,
    mode: json['mode'] as String,
    species: (json['species'] == null ? null : json['species'] as String),
    status: json['status'] as String,
    headcount: json['headcount'] as int,
  );
  FarmlyJsonMap toJson() {
    final json = <String, dynamic>{
      'id': id,
      'version': version,
      'mode': mode,
      'species': species,
      'status': status,
      'headcount': headcount,
    }..removeWhere((key, value) => value == null);
    return json;
  }
}

final class FarmlyAnimalDto {
  const FarmlyAnimalDto({
    required this.id,
    required this.version,
    required this.herdId,
    required this.tag,
    this.name,
    this.birthDate,
    required this.status,
    required this.archived,
  });
  final String id;
  final int version;
  final String herdId;
  final String tag;
  final String? name;
  final String? birthDate;
  final String status;
  final bool archived;
  factory FarmlyAnimalDto.fromJson(FarmlyJsonMap json) => FarmlyAnimalDto(
    id: json['id'] as String,
    version: json['version'] as int,
    herdId: json['herdId'] as String,
    tag: json['tag'] as String,
    name: (json['name'] == null ? null : json['name'] as String),
    birthDate: (json['birthDate'] == null ? null : json['birthDate'] as String),
    status: json['status'] as String,
    archived: json['archived'] as bool,
  );
  FarmlyJsonMap toJson() {
    final json = <String, dynamic>{
      'id': id,
      'version': version,
      'herdId': herdId,
      'tag': tag,
      'name': name,
      'birthDate': birthDate,
      'status': status,
      'archived': archived,
    }..removeWhere((key, value) => value == null);
    return json;
  }
}

final class FarmlyZoneListData {
  const FarmlyZoneListData({required this.zones});
  final List<FarmlyZoneDto> zones;
  factory FarmlyZoneListData.fromJson(FarmlyJsonMap json) => FarmlyZoneListData(
    zones: (json['zones'] as List<dynamic>)
        .map(
          (item) =>
              FarmlyZoneDto.fromJson(Map<String, dynamic>.from(item as Map)),
        )
        .toList(growable: false),
  );
  FarmlyJsonMap toJson() {
    final json = <String, dynamic>{
      'zones': zones.map((item) => item.toJson()).toList(growable: false),
    }..removeWhere((key, value) => value == null);
    return json;
  }
}

final class FarmlyZoneListResponse {
  const FarmlyZoneListResponse({
    required this.data,
    this.page,
    required this.meta,
  });
  final FarmlyZoneListData data;
  final FarmlyPageInfo? page;
  final FarmlyResponseMeta meta;
  factory FarmlyZoneListResponse.fromJson(FarmlyJsonMap json) =>
      FarmlyZoneListResponse(
        data: FarmlyZoneListData.fromJson(
          Map<String, dynamic>.from(json['data'] as Map),
        ),
        page: (json['page'] == null
            ? null
            : FarmlyPageInfo.fromJson(
                Map<String, dynamic>.from(json['page'] as Map),
              )),
        meta: FarmlyResponseMeta.fromJson(
          Map<String, dynamic>.from(json['meta'] as Map),
        ),
      );
  FarmlyJsonMap toJson() {
    final json = <String, dynamic>{
      'data': data.toJson(),
      'page': page?.toJson(),
      'meta': meta.toJson(),
    }..removeWhere((key, value) => value == null);
    return json;
  }
}

final class FarmlyCropSpeciesListData {
  const FarmlyCropSpeciesListData({required this.cropSpecies});
  final List<FarmlyCropSpeciesDto> cropSpecies;
  factory FarmlyCropSpeciesListData.fromJson(FarmlyJsonMap json) =>
      FarmlyCropSpeciesListData(
        cropSpecies: (json['cropSpecies'] as List<dynamic>)
            .map(
              (item) => FarmlyCropSpeciesDto.fromJson(
                Map<String, dynamic>.from(item as Map),
              ),
            )
            .toList(growable: false),
      );
  FarmlyJsonMap toJson() {
    final json = <String, dynamic>{
      'cropSpecies': cropSpecies
          .map((item) => item.toJson())
          .toList(growable: false),
    }..removeWhere((key, value) => value == null);
    return json;
  }
}

final class FarmlyCropSpeciesListResponse {
  const FarmlyCropSpeciesListResponse({
    required this.data,
    this.page,
    required this.meta,
  });
  final FarmlyCropSpeciesListData data;
  final FarmlyPageInfo? page;
  final FarmlyResponseMeta meta;
  factory FarmlyCropSpeciesListResponse.fromJson(FarmlyJsonMap json) =>
      FarmlyCropSpeciesListResponse(
        data: FarmlyCropSpeciesListData.fromJson(
          Map<String, dynamic>.from(json['data'] as Map),
        ),
        page: (json['page'] == null
            ? null
            : FarmlyPageInfo.fromJson(
                Map<String, dynamic>.from(json['page'] as Map),
              )),
        meta: FarmlyResponseMeta.fromJson(
          Map<String, dynamic>.from(json['meta'] as Map),
        ),
      );
  FarmlyJsonMap toJson() {
    final json = <String, dynamic>{
      'data': data.toJson(),
      'page': page?.toJson(),
      'meta': meta.toJson(),
    }..removeWhere((key, value) => value == null);
    return json;
  }
}

final class FarmlyPlantingListData {
  const FarmlyPlantingListData({required this.plantings});
  final List<FarmlyPlantingDto> plantings;
  factory FarmlyPlantingListData.fromJson(FarmlyJsonMap json) =>
      FarmlyPlantingListData(
        plantings: (json['plantings'] as List<dynamic>)
            .map(
              (item) => FarmlyPlantingDto.fromJson(
                Map<String, dynamic>.from(item as Map),
              ),
            )
            .toList(growable: false),
      );
  FarmlyJsonMap toJson() {
    final json = <String, dynamic>{
      'plantings': plantings
          .map((item) => item.toJson())
          .toList(growable: false),
    }..removeWhere((key, value) => value == null);
    return json;
  }
}

final class FarmlyPlantingListResponse {
  const FarmlyPlantingListResponse({
    required this.data,
    this.page,
    required this.meta,
  });
  final FarmlyPlantingListData data;
  final FarmlyPageInfo? page;
  final FarmlyResponseMeta meta;
  factory FarmlyPlantingListResponse.fromJson(FarmlyJsonMap json) =>
      FarmlyPlantingListResponse(
        data: FarmlyPlantingListData.fromJson(
          Map<String, dynamic>.from(json['data'] as Map),
        ),
        page: (json['page'] == null
            ? null
            : FarmlyPageInfo.fromJson(
                Map<String, dynamic>.from(json['page'] as Map),
              )),
        meta: FarmlyResponseMeta.fromJson(
          Map<String, dynamic>.from(json['meta'] as Map),
        ),
      );
  FarmlyJsonMap toJson() {
    final json = <String, dynamic>{
      'data': data.toJson(),
      'page': page?.toJson(),
      'meta': meta.toJson(),
    }..removeWhere((key, value) => value == null);
    return json;
  }
}

final class FarmlyHerdListData {
  const FarmlyHerdListData({required this.herds});
  final List<FarmlyHerdDto> herds;
  factory FarmlyHerdListData.fromJson(FarmlyJsonMap json) => FarmlyHerdListData(
    herds: (json['herds'] as List<dynamic>)
        .map(
          (item) =>
              FarmlyHerdDto.fromJson(Map<String, dynamic>.from(item as Map)),
        )
        .toList(growable: false),
  );
  FarmlyJsonMap toJson() {
    final json = <String, dynamic>{
      'herds': herds.map((item) => item.toJson()).toList(growable: false),
    }..removeWhere((key, value) => value == null);
    return json;
  }
}

final class FarmlyHerdListResponse {
  const FarmlyHerdListResponse({
    required this.data,
    this.page,
    required this.meta,
  });
  final FarmlyHerdListData data;
  final FarmlyPageInfo? page;
  final FarmlyResponseMeta meta;
  factory FarmlyHerdListResponse.fromJson(FarmlyJsonMap json) =>
      FarmlyHerdListResponse(
        data: FarmlyHerdListData.fromJson(
          Map<String, dynamic>.from(json['data'] as Map),
        ),
        page: (json['page'] == null
            ? null
            : FarmlyPageInfo.fromJson(
                Map<String, dynamic>.from(json['page'] as Map),
              )),
        meta: FarmlyResponseMeta.fromJson(
          Map<String, dynamic>.from(json['meta'] as Map),
        ),
      );
  FarmlyJsonMap toJson() {
    final json = <String, dynamic>{
      'data': data.toJson(),
      'page': page?.toJson(),
      'meta': meta.toJson(),
    }..removeWhere((key, value) => value == null);
    return json;
  }
}

final class FarmlyAnimalListData {
  const FarmlyAnimalListData({required this.animals});
  final List<FarmlyAnimalDto> animals;
  factory FarmlyAnimalListData.fromJson(
    FarmlyJsonMap json,
  ) => FarmlyAnimalListData(
    animals: (json['animals'] as List<dynamic>)
        .map(
          (item) =>
              FarmlyAnimalDto.fromJson(Map<String, dynamic>.from(item as Map)),
        )
        .toList(growable: false),
  );
  FarmlyJsonMap toJson() {
    final json = <String, dynamic>{
      'animals': animals.map((item) => item.toJson()).toList(growable: false),
    }..removeWhere((key, value) => value == null);
    return json;
  }
}

final class FarmlyAnimalListResponse {
  const FarmlyAnimalListResponse({
    required this.data,
    this.page,
    required this.meta,
  });
  final FarmlyAnimalListData data;
  final FarmlyPageInfo? page;
  final FarmlyResponseMeta meta;
  factory FarmlyAnimalListResponse.fromJson(FarmlyJsonMap json) =>
      FarmlyAnimalListResponse(
        data: FarmlyAnimalListData.fromJson(
          Map<String, dynamic>.from(json['data'] as Map),
        ),
        page: (json['page'] == null
            ? null
            : FarmlyPageInfo.fromJson(
                Map<String, dynamic>.from(json['page'] as Map),
              )),
        meta: FarmlyResponseMeta.fromJson(
          Map<String, dynamic>.from(json['meta'] as Map),
        ),
      );
  FarmlyJsonMap toJson() {
    final json = <String, dynamic>{
      'data': data.toJson(),
      'page': page?.toJson(),
      'meta': meta.toJson(),
    }..removeWhere((key, value) => value == null);
    return json;
  }
}

final class FarmlyWaterTankListData {
  const FarmlyWaterTankListData({required this.waterTanks});
  final List<FarmlyWaterTankDto> waterTanks;
  factory FarmlyWaterTankListData.fromJson(FarmlyJsonMap json) =>
      FarmlyWaterTankListData(
        waterTanks: (json['waterTanks'] as List<dynamic>)
            .map(
              (item) => FarmlyWaterTankDto.fromJson(
                Map<String, dynamic>.from(item as Map),
              ),
            )
            .toList(growable: false),
      );
  FarmlyJsonMap toJson() {
    final json = <String, dynamic>{
      'waterTanks': waterTanks
          .map((item) => item.toJson())
          .toList(growable: false),
    }..removeWhere((key, value) => value == null);
    return json;
  }
}

final class FarmlyWaterTankListResponse {
  const FarmlyWaterTankListResponse({
    required this.data,
    this.page,
    required this.meta,
  });
  final FarmlyWaterTankListData data;
  final FarmlyPageInfo? page;
  final FarmlyResponseMeta meta;
  factory FarmlyWaterTankListResponse.fromJson(FarmlyJsonMap json) =>
      FarmlyWaterTankListResponse(
        data: FarmlyWaterTankListData.fromJson(
          Map<String, dynamic>.from(json['data'] as Map),
        ),
        page: (json['page'] == null
            ? null
            : FarmlyPageInfo.fromJson(
                Map<String, dynamic>.from(json['page'] as Map),
              )),
        meta: FarmlyResponseMeta.fromJson(
          Map<String, dynamic>.from(json['meta'] as Map),
        ),
      );
  FarmlyJsonMap toJson() {
    final json = <String, dynamic>{
      'data': data.toJson(),
      'page': page?.toJson(),
      'meta': meta.toJson(),
    }..removeWhere((key, value) => value == null);
    return json;
  }
}

final class FarmlyScopedResponseMeta {
  const FarmlyScopedResponseMeta({
    required this.schemaVersion,
    required this.asOf,
    required this.scopePolicyVersion,
  });
  final String schemaVersion;
  final String asOf;
  final String scopePolicyVersion;
  factory FarmlyScopedResponseMeta.fromJson(FarmlyJsonMap json) =>
      FarmlyScopedResponseMeta(
        schemaVersion: json['schemaVersion'] as String,
        asOf: json['asOf'] as String,
        scopePolicyVersion: json['scopePolicyVersion'] as String,
      );
  FarmlyJsonMap toJson() {
    final json = <String, dynamic>{
      'schemaVersion': schemaVersion,
      'asOf': asOf,
      'scopePolicyVersion': scopePolicyVersion,
    }..removeWhere((key, value) => value == null);
    return json;
  }
}

final class FarmlyDomainMutationData {
  const FarmlyDomainMutationData({
    required this.operationId,
    required this.outcome,
    required this.revision,
  });
  final String operationId;
  final String outcome;
  final String revision;
  factory FarmlyDomainMutationData.fromJson(FarmlyJsonMap json) =>
      FarmlyDomainMutationData(
        operationId: json['operationId'] as String,
        outcome: json['outcome'] as String,
        revision: json['revision'] as String,
      );
  FarmlyJsonMap toJson() {
    final json = <String, dynamic>{
      'operationId': operationId,
      'outcome': outcome,
      'revision': revision,
    }..removeWhere((key, value) => value == null);
    return json;
  }
}

final class FarmlyDomainMutationResponse {
  const FarmlyDomainMutationResponse({required this.data, required this.meta});
  final FarmlyDomainMutationData data;
  final FarmlyScopedResponseMeta meta;
  factory FarmlyDomainMutationResponse.fromJson(FarmlyJsonMap json) =>
      FarmlyDomainMutationResponse(
        data: FarmlyDomainMutationData.fromJson(
          Map<String, dynamic>.from(json['data'] as Map),
        ),
        meta: FarmlyScopedResponseMeta.fromJson(
          Map<String, dynamic>.from(json['meta'] as Map),
        ),
      );
  FarmlyJsonMap toJson() {
    final json = <String, dynamic>{'data': data.toJson(), 'meta': meta.toJson()}
      ..removeWhere((key, value) => value == null);
    return json;
  }
}
