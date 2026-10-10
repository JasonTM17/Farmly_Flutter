import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../network/farmly_api_client.dart';
import '../sync/sync_engine.dart';

/// Audited privacy request result (POST /v1/me/privacy-requests). Payload is
/// server-produced (export contents / action summary) — the client only
/// surfaces counts and status, never reserializes it into a file itself.
final class PrivacyRequestResult {
  const PrivacyRequestResult({
    required this.requestId,
    required this.action,
    required this.status,
    this.payload,
  });

  final String requestId;
  final String action;
  final String status;
  final Map<String, Object?>? payload;
}

enum PrivacyAction { export, deleteHistory, withdrawAiConsent }

final privacyRepositoryProvider = Provider<PrivacyRepository>(
  (ref) => PrivacyRepository(ref.watch(farmlyApiClientProvider)),
);

class PrivacyRepository {
  PrivacyRepository(this._client);

  final FarmlyApiClient _client;

  static const _actionWire = {
    PrivacyAction.export: 'export',
    PrivacyAction.deleteHistory: 'delete-history',
    PrivacyAction.withdrawAiConsent: 'withdraw-ai-consent',
  };

  Future<PrivacyRequestResult> createRequest(
    PrivacyAction action, {
    String? confirmation,
  }) async {
    final result = await _client.post(
      'v1/me/privacy-requests',
      <String, Object?>{
        'operationId': newOperationId(),
        'action': _actionWire[action],
        'confirmation': ?confirmation,
      },
    );
    final data = (result as Map)['data'] as Map;
    return PrivacyRequestResult(
      requestId: data['requestId'] as String,
      action: data['action'] as String,
      status: data['status'] as String,
      payload: data['payload'] is Map
          ? Map<String, Object?>.from(data['payload'] as Map)
          : null,
    );
  }
}
