import 'dart:convert';

import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../auth/auth_session_controller.dart';

enum FarmlyApiFailureCode {
  unauthenticated,
  permissionDenied,
  notFound,
  conflict,
  cursorExpired,
  invitationExpired,
  invitationRevoked,
  invitationUnavailable,
  invitationEmailMismatch,
  invitationAlreadyAccepted,
  rateLimited,
  unavailable,
  invalidRequest,
  unexpected,
}

final class FarmlyApiFailure implements Exception {
  const FarmlyApiFailure(this.code);

  final FarmlyApiFailureCode code;
}

final farmlyApiDioProvider = Provider<Dio>((ref) {
  final config = ref.watch(farmlyAppConfigProvider);
  final dio = Dio(
    BaseOptions(
      baseUrl: _apiBase(config.apiBaseUrl),
      connectTimeout: const Duration(seconds: 10),
      sendTimeout: const Duration(seconds: 10),
      receiveTimeout: const Duration(seconds: 20),
      headers: const <String, String>{'Accept': 'application/json'},
    ),
  );
  ref.onDispose(dio.close);
  return dio;
});

final farmlyApiClientProvider = Provider<FarmlyApiClient>((ref) {
  final dio = ref.watch(farmlyApiDioProvider);
  final credentials = ref.watch(farmlySessionCredentialsProvider);
  return FarmlyApiClient(
    dio: dio,
    credentials: credentials,
    sessionGeneration: () => ref.read(farmlyAuthSessionGenerationProvider),
    onUnauthorized: (requestToken, requestGeneration) => ref
        .read(farmlyAuthSessionProvider.notifier)
        .handleUnauthorizedResponse(
          requestToken: requestToken,
          requestGeneration: requestGeneration,
        ),
  );
});

String _apiBase(Uri base) {
  final path = base.path.replaceFirst(RegExp(r'/+$'), '');
  return base.replace(path: '$path/').toString();
}

final class FarmlyApiClient {
  factory FarmlyApiClient({
    required Dio dio,
    required FarmlySessionCredentials credentials,
    required int Function() sessionGeneration,
    required Future<void> Function(String token, int generation) onUnauthorized,
  }) => FarmlyApiClient._(dio, credentials, sessionGeneration, onUnauthorized);

  FarmlyApiClient._(
    this._dio,
    this._credentials,
    this._sessionGeneration,
    this._onUnauthorized,
  );

  final Dio _dio;
  final FarmlySessionCredentials _credentials;
  final int Function() _sessionGeneration;
  final Future<void> Function(String token, int generation) _onUnauthorized;

  Future<Object?> get(
    String path, {
    Map<String, Object?> queryParameters = const <String, Object?>{},
  }) => _send(
    (options) => _dio.get<Object?>(
      path,
      queryParameters: queryParameters,
      options: options,
    ),
  );

  Future<Object?> post(
    String path,
    Map<String, Object?> body, {
    String? idempotencyKey,
  }) => _send((options) {
    final headers = <String, Object?>{...?options.headers};
    if (idempotencyKey != null) headers['Idempotency-Key'] = idempotencyKey;
    return _dio.post<Object?>(
      path,
      data: body,
      options: options.copyWith(headers: headers),
    );
  });

  Future<Object?> put(String path, Map<String, Object?> body) =>
      _send((options) => _dio.put<Object?>(path, data: body, options: options));

  /// Raw byte-stream GET for Server-Sent Events. Returns the live response so
  /// the caller owns cancellation + reconnection; auth and failure mapping are
  /// identical to [_send]. `Last-Event-ID` replays exactly one request's event
  /// log (spec05 §5).
  Future<Response<ResponseBody>> getStream(
    String path, {
    String? lastEventId,
  }) async {
    final requestGeneration = _sessionGeneration();
    final token = await _credentials.restore();
    if (token == null ||
        _sessionGeneration() != requestGeneration ||
        _credentials.currentToken != token) {
      throw const FarmlyApiFailure(FarmlyApiFailureCode.unauthenticated);
    }
    try {
      return await _dio.get<ResponseBody>(
        path,
        options: Options(
          responseType: ResponseType.stream,
          headers: <String, Object?>{
            'Authorization': 'Bearer $token',
            'Accept': 'text/event-stream',
            'Last-Event-ID': ?lastEventId,
          },
        ),
      );
    } on DioException catch (error) {
      // A non-SSE error body can still carry the sanitized envelope — decode
      // it before mapping so CURSOR_EXPIRED/permission codes reach the UI.
      final data = error.response?.data;
      if (data is ResponseBody) {
        try {
          final bytes = await data.stream.fold<List<int>>(
            <int>[],
            (acc, chunk) => acc..addAll(chunk),
          );
          final decoded = jsonDecode(utf8.decode(bytes));
          final mapped = _mapFailure(
            DioException(
              requestOptions: error.requestOptions,
              response: Response<Object?>(
                requestOptions: error.requestOptions,
                statusCode: error.response?.statusCode,
                data: decoded,
              ),
              type: error.type,
              error: error.error,
            ),
          );
          throw mapped;
        } on FarmlyApiFailure {
          rethrow;
        } catch (_) {
          // Fall through to the standard mapping below.
        }
      }
      final failure = _mapFailure(error);
      if (failure.code == FarmlyApiFailureCode.unauthenticated) {
        try {
          await _onUnauthorized(token, requestGeneration);
        } catch (_) {}
      }
      throw failure;
    }
  }

  Future<Object?> _send(
    Future<Response<Object?>> Function(Options options) request,
  ) async {
    final requestGeneration = _sessionGeneration();
    final token = await _credentials.restore();
    if (token == null ||
        _sessionGeneration() != requestGeneration ||
        _credentials.currentToken != token) {
      throw const FarmlyApiFailure(FarmlyApiFailureCode.unauthenticated);
    }
    final options = Options(
      headers: <String, String>{'Authorization': 'Bearer $token'},
    );
    try {
      final response = await request(options);
      return response.data;
    } on DioException catch (error) {
      final failure = _mapFailure(error);
      if (failure.code == FarmlyApiFailureCode.unauthenticated) {
        try {
          await _onUnauthorized(token, requestGeneration);
        } catch (_) {
          // Keep storage failures out of the public API error surface.
        }
      }
      throw failure;
    }
  }

  static FarmlyApiFailure _mapFailure(DioException error) {
    final status = error.response?.statusCode;
    final body = error.response?.data;
    // Nest errors carry {error:{code,...}}; tolerate a flat {code} too.
    final code = body is Map
        ? (body['error'] is Map ? body['error']['code'] : body['code'])
        : null;
    if (code is String) {
      switch (code.toUpperCase()) {
        case 'CURSOR_EXPIRED':
          return const FarmlyApiFailure(FarmlyApiFailureCode.cursorExpired);
        case 'INVITATION_EXPIRED':
          return const FarmlyApiFailure(FarmlyApiFailureCode.invitationExpired);
        case 'INVITATION_REVOKED':
          return const FarmlyApiFailure(FarmlyApiFailureCode.invitationRevoked);
        case 'INVITATION_NOT_AVAILABLE':
        case 'INVITATION_UNAVAILABLE':
          return const FarmlyApiFailure(
            FarmlyApiFailureCode.invitationUnavailable,
          );
        case 'INVITATION_EMAIL_MISMATCH':
          return const FarmlyApiFailure(
            FarmlyApiFailureCode.invitationEmailMismatch,
          );
        case 'INVITATION_ALREADY_ACCEPTED':
          return const FarmlyApiFailure(
            FarmlyApiFailureCode.invitationAlreadyAccepted,
          );
        case 'ACCESS_REVOKED':
          return const FarmlyApiFailure(FarmlyApiFailureCode.permissionDenied);
        case 'PERMISSION_DENIED':
          return const FarmlyApiFailure(FarmlyApiFailureCode.permissionDenied);
      }
    }
    if (status == 401) {
      return const FarmlyApiFailure(FarmlyApiFailureCode.unauthenticated);
    }
    if (status == 403) {
      return const FarmlyApiFailure(FarmlyApiFailureCode.permissionDenied);
    }
    if (status == 404) {
      return const FarmlyApiFailure(FarmlyApiFailureCode.notFound);
    }
    if (status == 409) {
      return const FarmlyApiFailure(FarmlyApiFailureCode.conflict);
    }
    if (status == 410) {
      return const FarmlyApiFailure(FarmlyApiFailureCode.invitationExpired);
    }
    if (status == 429) {
      return const FarmlyApiFailure(FarmlyApiFailureCode.rateLimited);
    }
    if (status == 400 || status == 422) {
      return const FarmlyApiFailure(FarmlyApiFailureCode.invalidRequest);
    }
    if (status == null ||
        status >= 500 ||
        error.type != DioExceptionType.badResponse) {
      return const FarmlyApiFailure(FarmlyApiFailureCode.unavailable);
    }
    return const FarmlyApiFailure(FarmlyApiFailureCode.unexpected);
  }
}
