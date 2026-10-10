import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:farmly_mobile/core/auth/auth_session_controller.dart';
import 'package:farmly_mobile/core/network/farmly_api_client.dart';
import 'package:farmly_mobile/core/notifications/notifications_repository.dart';
import 'package:farmly_mobile/core/privacy/privacy_repository.dart';
import 'package:farmly_mobile/core/storage/secure_secret_store.dart';

final class _MemorySecretStore implements FarmlySecretStore {
  final values = <String, String>{};

  @override
  Future<String?> read(String key) async => values[key];

  @override
  Future<void> write(String key, String value) async => values[key] = value;

  @override
  Future<void> delete(String key) async => values.remove(key);
}

final class _RecordedRequest {
  _RecordedRequest(this.method, this.path, this.query, this.body);

  final String method;
  final String path;
  final Map<String, dynamic> query;
  final Object? body;
}

/// Routes requests to canned envelopes; records every call for assertions.
final class _RoutingAdapter implements HttpClientAdapter {
  final requests = <_RecordedRequest>[];
  final responses = <String, (int status, Object? body)>{};

  @override
  Future<ResponseBody> fetch(
    RequestOptions options,
    Stream<Uint8List>? requestStream,
    Future<void>? cancelFuture,
  ) async {
    Object? body;
    if (requestStream != null) {
      final bytes = await requestStream.fold<List<int>>(
        <int>[],
        (a, b) => a..addAll(b),
      );
      body = jsonDecode(utf8.decode(bytes));
    }
    final key = '${options.method} ${options.uri.path}';
    requests.add(
      _RecordedRequest(
        options.method,
        options.uri.path,
        options.queryParameters,
        body,
      ),
    );
    final canned =
        responses[key] ?? (404, {'error': {'code': 'NOT_FOUND'}});
    return ResponseBody.fromString(
      jsonEncode(canned.$2),
      canned.$1,
      headers: <String, List<String>>{
        Headers.contentTypeHeader: <String>[Headers.jsonContentType],
      },
    );
  }

  @override
  void close({bool force = false}) {}
}

Future<(FarmlyApiClient, _RoutingAdapter)> _api(
  _RoutingAdapter adapter,
) async {
  final dio = Dio(BaseOptions(baseUrl: 'https://farmly.test/'))
    ..httpClientAdapter = adapter;
  final credentials = FarmlySessionCredentials(
    FarmlySessionTokenStore(_MemorySecretStore()),
  );
  await credentials.set('synthetic-session-token', persist: false);
  return (
    FarmlyApiClient(
      dio: dio,
      credentials: credentials,
      sessionGeneration: () => 0,
      onUnauthorized: (_, _) async {},
    ),
    adapter,
  );
}

void main() {
  group('NotificationsRepository', () {
    test('list maps wire rows and passes cursor/limit', () async {
      final adapter = _RoutingAdapter()
        ..responses['GET /v1/me/notifications'] = (
          200,
          {
            'data': {
              'items': [
                {
                  'id': 'n-1',
                  'kind': 'task-reminder',
                  'title': 'Cho ăn lúa',
                  'body': 'Tới giờ cho ăn',
                  'sourceRef': 'task-1',
                  'readAt': null,
                  'createdAt': '2026-10-14T08:00:00.000Z',
                  'farmId': 'f-1',
                },
                {
                  'id': 'n-2',
                  'kind': 'system',
                  'title': 'Đồng bộ xong',
                  'readAt': '2026-10-14T09:00:00.000Z',
                  'createdAt': '2026-10-14T08:30:00.000Z',
                },
              ],
              'page': {'nextCursor': 'cursor-2'},
            },
          },
        );
      final (client, _) = await _api(adapter);
      final repo = NotificationsRepository(client);

      final result = await repo.list(limit: 10, cursor: 'cursor-1');

      expect(result.nextCursor, 'cursor-2');
      expect(result.items, hasLength(2));
      expect(result.items[0].id, 'n-1');
      expect(result.items[0].readAt, isNull);
      expect(result.items[1].readAt, isNotNull);
      final request = adapter.requests.single;
      expect(request.query['limit'], '10');
      expect(request.query['cursor'], 'cursor-1');
    });

    test('markRead posts to the notification read route', () async {
      final adapter = _RoutingAdapter()
        ..responses['POST /v1/me/notifications/n-9/read'] = (
          200,
          {'data': {'id': 'n-9', 'readAt': '2026-10-14T10:00:00Z'}},
        );
      final (client, _) = await _api(adapter);
      await NotificationsRepository(client).markRead('n-9');

      expect(adapter.requests.single.path, '/v1/me/notifications/n-9/read');
    });
  });

  group('PrivacyRepository', () {
    test('createRequest sends action + fresh UUIDv4 operationId', () async {
      final adapter = _RoutingAdapter()
        ..responses['POST /v1/me/privacy-requests'] = (
          202,
          {
            'data': {
              'requestId': 'pr-1',
              'action': 'export',
              'status': 'completed',
              'payload': {'exportedAt': '2026-10-14T10:00:00Z'},
            },
          },
        );
      final (client, _) = await _api(adapter);
      final repo = PrivacyRepository(client);

      final result = await repo.createRequest(PrivacyAction.export);

      expect(result.requestId, 'pr-1');
      expect(result.status, 'completed');
      final body = adapter.requests.single.body as Map;
      expect(body['action'], 'export');
      expect(body['confirmation'], isNull);
      expect(
        body['operationId'],
        matches(
          RegExp(
            r'^[0-9a-f]{8}-[0-9a-f]{4}-4[0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$',
          ),
        ),
      );
    });

    test('each call generates a distinct operationId (no reuse)', () async {
      final adapter = _RoutingAdapter()
        ..responses['POST /v1/me/privacy-requests'] = (
          202,
          {
            'data': {
              'requestId': 'pr-2',
              'action': 'delete-history',
              'status': 'completed',
              'payload': {'conversationsDeleted': 3},
            },
          },
        );
      final (client, _) = await _api(adapter);
      final repo = PrivacyRepository(client);

      final first = await repo.createRequest(
        PrivacyAction.deleteHistory,
        confirmation: 'confirmed-delete-history',
      );
      final second = await repo.createRequest(
        PrivacyAction.deleteHistory,
        confirmation: 'confirmed-delete-history',
      );

      expect(first.payload?['conversationsDeleted'], 3);
      final bodies = adapter.requests.map((r) => r.body as Map).toList();
      expect(
        (bodies[0]['operationId'] as String) !=
            (bodies[1]['operationId'] as String),
        isTrue,
      );
      expect(bodies[0]['confirmation'], 'confirmed-delete-history');
    });

    test('error envelope maps to FarmlyApiFailure with its code', () async {
      final adapter = _RoutingAdapter()
        ..responses['POST /v1/me/privacy-requests'] = (
          409,
          {
            'error': {'code': 'CONFLICT'},
          },
        );
      final (client, _) = await _api(adapter);

      await expectLater(
        PrivacyRepository(client).createRequest(PrivacyAction.export),
        throwsA(
          isA<FarmlyApiFailure>().having(
            (f) => f.code,
            'code',
            isA<FarmlyApiFailureCode>(),
          ),
        ),
      );
    });
  });
}
