import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../network/farmly_api_client.dart';

/// Recipient-owned in-app notification (GET /v1/me/notifications).
final class AppNotification {
  const AppNotification({
    required this.id,
    required this.kind,
    required this.title,
    this.body,
    this.sourceRef,
    this.readAt,
    required this.createdAt,
    this.farmId,
  });

  final String id;
  final String kind;
  final String title;
  final String? body;
  final String? sourceRef;
  final DateTime? readAt;
  final DateTime createdAt;
  final String? farmId;
}

final notificationsRepositoryProvider = Provider<NotificationsRepository>(
  (ref) => NotificationsRepository(ref.watch(farmlyApiClientProvider)),
);

class NotificationsRepository {
  NotificationsRepository(this._client);

  final FarmlyApiClient _client;

  Future<({List<AppNotification> items, String? nextCursor})> list({
    int limit = 25,
    String? cursor,
  }) async {
    final result = await _client.get(
      'v1/me/notifications',
      queryParameters: <String, Object?>{
        'limit': '$limit',
        'cursor': ?cursor,
      },
    );
    final data = (result as Map)['data'] as Map;
    final items = (data['items'] as List? ?? const [])
        .whereType<Map>()
        .map(
          (row) => AppNotification(
            id: row['id'] as String,
            kind: row['kind'] as String? ?? 'system',
            title: row['title'] as String? ?? '',
            body: row['body'] as String?,
            sourceRef: row['sourceRef'] as String?,
            readAt: row['readAt'] == null
                ? null
                : DateTime.tryParse(row['readAt'] as String),
            createdAt:
                DateTime.tryParse(row['createdAt'] as String? ?? '') ??
                DateTime.fromMillisecondsSinceEpoch(0),
            farmId: row['farmId'] as String?,
          ),
        )
        .toList();
    return (
      items: items,
      nextCursor: (data['page'] as Map?)?['nextCursor'] as String?,
    );
  }

  Future<void> markRead(String notificationId) async {
    await _client.post(
      'v1/me/notifications/$notificationId/read',
      const <String, Object?>{},
    );
  }
}
