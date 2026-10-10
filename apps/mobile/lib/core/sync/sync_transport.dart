import '../network/farmly_api_client.dart';
import 'farmly_mutation.dart';
import 'sync_models.dart';

/// Server boundary for the sync engine. The engine never speaks HTTP; tests
/// drive it through a scripted fake transport.
abstract interface class SyncTransport {
  /// Submit an ordered batch of immutable intents. The wire envelope is
  /// `farm-mutation-batch.v1`; each intent is sent with its own
  /// Idempotency-Key semantics via operationId inside the payload.
  Future<MutationBatchResult> submitMutations({
    required FarmlyMutationScope scope,
    required List<FarmlyMutationIntent> operations,
  });

  /// Durable server-side proof for operations whose responses were lost.
  Future<List<OperationStatusEntry>> operationStatus({
    required String accountId,
    required List<String> operationIds,
  });

  /// Signed-cursor change feed. Throws [FarmlyApiFailure] with
  /// [FarmlyApiFailureCode.cursorExpired] for tampered/stale/pruned cursors.
  Future<ChangeFeedPage> fetchChanges({
    required FarmlyMutationScope scope,
    required String cursor,
  });

  /// Materialize a server-side bootstrap snapshot (operationId = snapshot id).
  Future<BootstrapManifest> createBootstrap({
    required FarmlyMutationScope scope,
    required String operationId,
  });

  /// Read one immutable chunk page of a private bootstrap snapshot.
  Future<BootstrapPage> fetchBootstrapPage({
    required FarmlyMutationScope scope,
    required String snapshotId,
    String? pageCursor,
  });
}

/// [SyncTransport] over the authenticated API client. Paths follow the
/// generated OpenAPI surface (spec04 §7).
final class FarmlyApiTransport implements SyncTransport {
  const FarmlyApiTransport(this._api);

  final FarmlyApiClient _api;

  String _scopeBase(FarmlyMutationScope scope) =>
      'v1/organizations/${scope.organizationId}';

  String _farmBase(FarmlyMutationScope scope) {
    final farmId = scope.farmId;
    if (farmId == null) {
      throw ArgumentError('Farm-scoped endpoint requires a farm scope');
    }
    return '${_scopeBase(scope)}/farms/$farmId';
  }

  @override
  Future<MutationBatchResult> submitMutations({
    required FarmlyMutationScope scope,
    required List<FarmlyMutationIntent> operations,
  }) async {
    final base = scope.kind == FarmlyMutationScopeKind.organization
        ? _scopeBase(scope)
        : _farmBase(scope);
    final body = await _api.post('$base/sync/mutations', <String, Object?>{
      'schemaVersion': 'farm-mutation-batch.v1',
      'continuityEpoch': scope.continuityEpoch,
      'operations': [
        for (final operation in operations) operation.toJson(),
      ],
    });
    final map = _requireMap(body, 'MutationBatchResult');
    final data = _requireMap(map['data'], 'MutationBatchResult.data');
    final meta = map['meta'];
    return MutationBatchResult(
      outcomes: [
        for (final entry in (data['outcomes'] as List? ?? const []))
          _outcome(entry),
      ],
      asOf: meta is Map ? meta['asOf'] as String? : null,
      scopePolicyVersion:
          meta is Map ? meta['scopePolicyVersion'] as String? : null,
    );
  }

  @override
  Future<List<OperationStatusEntry>> operationStatus({
    required String accountId,
    required List<String> operationIds,
  }) async {
    if (operationIds.isEmpty) return const [];
    final body = await _api.get(
      'v1/me/operation-status',
      queryParameters: {'operationIds': operationIds.join(',')},
    );
    final map = _requireMap(body, 'OperationStatus');
    final data = _requireMap(map['data'], 'OperationStatus.data');
    final items = data['operations'] as List? ?? data['items'] as List? ?? const [];
    return [
      for (final entry in items)
        _statusEntry(Map<String, Object?>.from(entry as Map)),
    ];
  }

  @override
  Future<ChangeFeedPage> fetchChanges({
    required FarmlyMutationScope scope,
    required String cursor,
  }) async {
    final body = await _api.get(
      '${_farmBase(scope)}/sync/changes',
      queryParameters: {'cursor': cursor},
    );
    final map = _requireMap(body, 'ChangeFeed');
    final data = _requireMap(map['data'], 'ChangeFeed.data');
    final page = _requireMap(map['page'], 'ChangeFeed.page');
    return ChangeFeedPage(
      changeSets: [
        for (final entry in (data['changeSets'] as List? ?? const []))
          SyncChangeSet.fromJson(Map<String, Object?>.from(entry as Map)),
      ],
      highWatermark: data['highWatermark'] as String,
      hasMore: page['hasMore'] == true,
      nextCursor: page['nextCursor'] as String,
    );
  }

  @override
  Future<BootstrapManifest> createBootstrap({
    required FarmlyMutationScope scope,
    required String operationId,
  }) async {
    final body = await _api.post(
      '${_farmBase(scope)}/sync/bootstrap',
      <String, Object?>{'operationId': operationId, 'payload': <String, Object?>{}},
      idempotencyKey: operationId,
    );
    final data = _requireMap(_requireMap(body, 'Bootstrap')['data'], 'Bootstrap.data');
    return BootstrapManifest(
      snapshotId: data['snapshotId'] as String,
      expiresAt: data['expiresAt'] as String,
      continuityEpoch: data['continuityEpoch'] as String,
      scopePolicyVersion: data['scopePolicyVersion'] as String,
      highWatermark: data['highWatermark'] as String,
      prunedThroughRevision: data['prunedThroughRevision'] as String,
      totalRows: (data['totalRows'] as num).toInt(),
      byteCount: (data['byteCount'] as num).toInt(),
      chunkCount: (data['chunkCount'] as num).toInt(),
      changesCursor: data['changesCursor'] as String,
    );
  }

  @override
  Future<BootstrapPage> fetchBootstrapPage({
    required FarmlyMutationScope scope,
    required String snapshotId,
    String? pageCursor,
  }) async {
    final body = await _api.get(
      '${_farmBase(scope)}/sync/bootstrap/$snapshotId',
      queryParameters:
          pageCursor == null ? const {} : {'pageCursor': pageCursor},
    );
    final map = _requireMap(body, 'BootstrapPage');
    final data = _requireMap(map['data'], 'BootstrapPage.data');
    final page = _requireMap(map['page'], 'BootstrapPage.page');
    return BootstrapPage(
      snapshotId: data['snapshotId'] as String,
      pageIndex: (data['pageIndex'] as num).toInt(),
      rowCount: (data['rowCount'] as num).toInt(),
      blocks: [
        for (final block in (data['blocks'] as List? ?? const []))
          BootstrapBlock.fromJson(Map<String, Object?>.from(block as Map)),
      ],
      hasMore: page['hasMore'] == true,
      nextPageCursor: page['nextPageCursor'] as String?,
      chunkCount: (page['chunkCount'] as num).toInt(),
    );
  }

  static MutationOutcome _outcome(Object? entry) {
    final map = Map<String, Object?>.from(entry as Map);
    return MutationOutcome(
      operationId: map['operationId'] as String,
      outcome: map['outcome'] as String,
      revision: map['revision'] as String?,
      code: map['code'] as String?,
    );
  }

  static OperationStatusEntry _statusEntry(Map<String, Object?> map) {
    final raw = (map['status'] ?? map['outcome'] ?? 'unknown') as String;
    return OperationStatusEntry(
      operationId: map['operationId'] as String,
      proof: switch (raw) {
        'applied' => OperationProof.applied,
        'rejected' => OperationProof.rejected,
        _ => OperationProof.unknown,
      },
    );
  }

  static Map<String, Object?> _requireMap(Object? value, String label) {
    if (value is Map) return Map<String, Object?>.from(value);
    throw FormatException('Farmly transport: $label is not an object');
  }
}
