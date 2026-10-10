import 'dart:async';
import 'dart:convert';

import '../network/farmly_api_client.dart';
import 'sse_decoder.dart';

/// Server event as decoded from the AI SSE stream. `data` is the typed
/// payload for `type` (spec05 §5); `lastEventId` is `{requestId}:{seq}`.
final class AiStreamEvent {
  const AiStreamEvent({
    required this.type,
    required this.id,
    required this.data,
  });

  final String type;
  final String id;
  final Map<String, Object?> data;

  int get seq {
    final tail = id.split(':').last;
    return int.tryParse(tail) ?? -1;
  }

  bool get isTerminal => switch (type) {
    'response.completed' || 'response.cancelled' || 'response.error' => true,
    _ => false,
  };
}

final class AiCreatedRequest {
  const AiCreatedRequest({
    required this.requestId,
    required this.conversationId,
    required this.state,
    required this.replayed,
  });

  final String requestId;
  final String conversationId;
  final String state;
  final bool replayed;
}

final class AiRequestStatus {
  const AiRequestStatus({
    required this.requestId,
    required this.status,
    required this.usageState,
    this.errorCode,
  });

  final String requestId;
  final String status;
  final String usageState;
  final String? errorCode;

  bool get isTerminal => switch (status) {
    'completed' || 'cancelled' || 'interrupted' || 'error' => true,
    _ => false,
  };
}

final class AiConsentSnapshot {
  const AiConsentSnapshot({
    required this.granted,
    required this.revision,
    required this.summaryOptedIn,
  });

  final bool granted;
  final int revision;
  final bool summaryOptedIn;
}

/// Repository for the private AI chat surface (spec05 §3–§5). Every call is
/// owner-scoped by the server; the client supplies only scope UUIDs and the
/// consent revision it knows. Never fabricates answers — a missing or failed
/// stream surfaces as an error, not a fake response.
class AiChatRepository {
  AiChatRepository(this._client);

  final FarmlyApiClient _client;

  static String _base(String orgId, String farmId) =>
      'v1/organizations/$orgId/farms/$farmId/ai';

  /// POST the durable request. `clientRequestId` + `Idempotency-Key` must be
  /// identical on retries so the server can dedupe without a second upstream
  /// attempt (spec05 §3).
  Future<AiCreatedRequest> createRequest({
    required String organizationId,
    required String farmId,
    required String clientRequestId,
    required String prompt,
    required String contextMode,
    required int consentRevision,
    String? conversationId,
  }) async {
    final body = <String, Object?>{
      'clientRequestId': clientRequestId,
      'prompt': prompt,
      // UI uses 'farm'/'general'; the contract speaks
      // 'authorized-summary'/'none'. Normalize at the wire boundary.
      'contextMode': switch (contextMode) {
        'farm' => 'authorized-summary',
        'general' => 'none',
        _ => contextMode,
      },
      'consentRevision': consentRevision,
      'schemaVersion': 'farmly-ai-request.v1',
      'conversationId': ?conversationId,
    };
    final result = await _client.post(
      '${_base(organizationId, farmId)}/requests',
      body,
      idempotencyKey: clientRequestId,
    );
    final data = (result as Map)['data'] as Map;
    return AiCreatedRequest(
      requestId: data['requestId'] as String,
      conversationId: data['conversationId'] as String,
      state: data['state'] as String,
      replayed: data['replayed'] == true,
    );
  }

  Future<AiRequestStatus> getRequest({
    required String organizationId,
    required String farmId,
    required String requestId,
  }) async {
    final result = await _client.get(
      '${_base(organizationId, farmId)}/requests/$requestId',
    );
    final data = (result as Map)['data'] as Map;
    return AiRequestStatus(
      requestId: requestId,
      status: data['status'] as String? ?? data['state'] as String? ?? 'unknown',
      usageState: data['usageState'] as String? ?? 'unknown',
      errorCode: data['errorCode'] as String?,
    );
  }

  /// Best-effort cancel; the server distinguishes queued vs post-fence
  /// cancellation and keeps usage conservative (spec05 §4).
  Future<AiRequestStatus> cancelRequest({
    required String organizationId,
    required String farmId,
    required String requestId,
  }) async {
    final result = await _client.post(
      '${_base(organizationId, farmId)}/requests/$requestId/cancel',
      const <String, Object?>{},
    );
    final data = (result as Map)['data'] as Map;
    return AiRequestStatus(
      requestId: requestId,
      status: data['status'] as String? ?? data['state'] as String? ?? 'stopping',
      usageState: data['usageState'] as String? ?? 'reserved',
      errorCode: null,
    );
  }

  /// Grant or update the caller's private AI consent (PUT /ai/consent —
  /// org-scoped singleton). The returned revision is what subsequent
  /// [createRequest] calls must bind.
  Future<AiConsentSnapshot> grantConsent({
    required String organizationId,
    bool summaryOptedIn = false,
  }) async {
    final result = await _client.put(
      'v1/organizations/$organizationId/ai/consent',
      <String, Object?>{
        'granted': true,
        'aiSafeSummaryOptedIn': summaryOptedIn,
      },
    );
    final data = (result as Map)['data'] as Map;
    return AiConsentSnapshot(
      granted: data['granted'] == true,
      revision: (data['revision'] as num?)?.toInt() ?? 0,
      summaryOptedIn: data['summaryOptedIn'] == true,
    );
  }

  /// Consent snapshot from the conversations surface — the only read the
  /// client has of server-side consent (revocation lands here on refresh).
  Future<AiConsentSnapshot?> consent({
    required String organizationId,
    required String farmId,
  }) async {
    final result = await _client.get(
      '${_base(organizationId, farmId)}/conversations',
      queryParameters: const <String, Object?>{'limit': '1'},
    );
    final consent = ((result as Map)['data'] as Map)['consent'];
    if (consent is! Map) return null;
    return AiConsentSnapshot(
      granted: consent['granted'] == true,
      revision: (consent['revision'] as num?)?.toInt() ?? 0,
      summaryOptedIn: consent['summaryOptedIn'] == true,
    );
  }

  /// Stream SSE events for exactly one request. `resumeAfterId` re-opens the
  /// log at a persisted cursor (Last-Event-ID); events arrive in seq order.
  /// Cancelling the returned stream closes the HTTP connection only — the
  /// request keeps generating server-side and can be re-attached.
  Stream<AiStreamEvent> streamEvents({
    required String organizationId,
    required String farmId,
    required String requestId,
    String? resumeAfterId,
  }) async* {
    final response = await _client.getStream(
      '${_base(organizationId, farmId)}/requests/$requestId/events',
      lastEventId: resumeAfterId,
    );
    final body = response.data;
    if (body == null) {
      throw const FarmlyApiFailure(FarmlyApiFailureCode.unavailable);
    }
    final pending = <SseFrame>[];
    final decoder = SseDecoder(onFrame: pending.add);
    try {
      await for (final chunk in body.stream) {
        decoder.addBytes(chunk);
        for (final frame in pending) {
          if (frame.id == null && frame.data == null) continue; // heartbeat
          final raw = frame.data;
          final decoded = raw == null ? null : jsonDecode(raw);
          yield AiStreamEvent(
            type: frame.event ?? 'response.delta',
            id: frame.id ?? '',
            data: decoded is Map
                ? Map<String, Object?>.from(decoded)
                : const <String, Object?>{},
          );
        }
        pending.clear();
      }
    } finally {
      await decoder.close();
    }
  }
}
