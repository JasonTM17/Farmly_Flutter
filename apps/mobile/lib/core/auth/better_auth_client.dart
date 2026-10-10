import 'package:dio/dio.dart';

import 'farmly_auth_models.dart';

/// Small typed adapter for the pinned Better Auth email/password endpoints.
/// It intentionally never exposes server error text or session tokens.
final class BetterAuthClient {
  BetterAuthClient({required Uri apiBaseUrl, Dio? dio})
    : _dio = dio ?? Dio(),
      _authBaseUrl = _authBase(apiBaseUrl);

  final Dio _dio;
  final Uri _authBaseUrl;

  static Uri _authBase(Uri apiBaseUrl) {
    final basePath = apiBaseUrl.path.replaceFirst(RegExp(r'/+$'), '');
    return apiBaseUrl.replace(path: '$basePath/api/auth/');
  }

  Future<String> signIn({
    required String email,
    required String password,
    required bool rememberMe,
  }) async {
    final response = await _post('sign-in/email', {
      'email': email.trim(),
      'password': password,
      'rememberMe': rememberMe,
    });
    final token = response.headers.value('set-auth-token');
    if (token == null ||
        token.isEmpty ||
        token.trim() != token ||
        token.contains(RegExp(r'\s'))) {
      throw const FarmlyAuthFailure(FarmlyAuthFailureCode.unexpected);
    }
    return token;
  }

  Future<FarmlyAuthSession?> getSession(String token) async {
    try {
      final response = await _dio.get<Object?>(
        _authUrl('get-session'),
        options: _bearerOptions(token),
      );
      final body = _map(response.data);
      if (body == null) {
        throw const FarmlyAuthFailure(FarmlyAuthFailureCode.unexpected);
      }
      final rawUser = body['user'];
      if (rawUser == null) return null;
      final user = _map(rawUser);
      if (user == null || user['emailVerified'] != true) {
        throw const FarmlyAuthFailure(FarmlyAuthFailureCode.emailNotVerified);
      }
      final id = user['id'];
      final name = user['name'];
      final email = user['email'];
      if ([id, name, email].any((value) => value is! String || value.isEmpty)) {
        throw const FarmlyAuthFailure(FarmlyAuthFailureCode.unexpected);
      }
      return FarmlyAuthSession(
        user: FarmlyAuthUser(
          id: id as String,
          name: name as String,
          email: email as String,
        ),
      );
    } on DioException catch (error) {
      final failure = _mapDioFailure(error);
      if (failure.code == FarmlyAuthFailureCode.invalidCredentials ||
          failure.code == FarmlyAuthFailureCode.emailNotVerified) {
        return null;
      }
      throw failure;
    }
  }

  Future<void> signOut(String token) async {
    try {
      await _post(
        'sign-out',
        const <String, Object?>{},
        options: _bearerOptions(token),
      );
    } on FarmlyAuthFailure {
      throw const FarmlyAuthFailure(FarmlyAuthFailureCode.signOutUnconfirmed);
    }
  }

  Future<void> signUp({
    required String name,
    required String email,
    required String password,
    String? returnTo,
  }) async {
    await _post('sign-up/email', {
      'name': name.trim(),
      'email': email.trim(),
      'password': password,
      'callbackURL': _verificationCallback(returnTo),
    });
  }

  Future<void> sendVerificationEmail(String email, {String? returnTo}) async {
    await _post('send-verification-email', {
      'email': email.trim(),
      'callbackURL': _verificationCallback(returnTo),
    });
  }

  Future<void> requestPasswordReset(String email) async {
    await _post('request-password-reset', {
      'email': email.trim(),
      'redirectTo': farmlyResetCallback,
    });
  }

  Future<void> resetPassword({
    required String token,
    required String newPassword,
  }) async {
    await _post('reset-password', {'token': token, 'newPassword': newPassword});
  }

  static const farmlyVerifiedCallback = 'farmly:///auth/verified';
  static const farmlyResetCallback = 'farmly:///auth/reset-password';

  static String _verificationCallback(String? returnTo) {
    if (returnTo == null ||
        !returnTo.startsWith('/') ||
        returnTo.startsWith('//')) {
      return farmlyVerifiedCallback;
    }
    final parsed = Uri.tryParse(returnTo);
    if (parsed == null || parsed.hasScheme || parsed.hasAuthority) {
      return farmlyVerifiedCallback;
    }
    return Uri.parse(
      farmlyVerifiedCallback,
    ).replace(queryParameters: {'returnTo': parsed.toString()}).toString();
  }

  Future<Response<Object?>> _post(
    String path,
    Map<String, Object?> data, {
    Options? options,
  }) async {
    try {
      return await _dio.post<Object?>(
        _authUrl(path),
        data: data,
        options: options,
      );
    } on DioException catch (error) {
      throw _mapDioFailure(error);
    }
  }

  Options _bearerOptions(String token) =>
      Options(headers: <String, String>{'Authorization': 'Bearer $token'});

  String _authUrl(String path) => _authBaseUrl.resolve(path).toString();

  static Map<String, Object?>? _map(Object? value) {
    if (value is! Map) return null;
    return value.map((key, value) => MapEntry(key.toString(), value));
  }

  static FarmlyAuthFailure _mapDioFailure(DioException error) {
    final status = error.response?.statusCode;
    final responseBody = _map(error.response?.data);
    final code = responseBody?['code'];
    if (code is String) {
      final normalized = code.toUpperCase();
      if (normalized.contains('EMAIL_NOT_VERIFIED')) {
        return const FarmlyAuthFailure(FarmlyAuthFailureCode.emailNotVerified);
      }
      if (normalized.contains('INVALID_TOKEN') ||
          normalized.contains('TOKEN_EXPIRED') ||
          normalized.contains('VERIFICATION')) {
        return const FarmlyAuthFailure(FarmlyAuthFailureCode.invalidLink);
      }
    }
    if (status == 401) {
      return const FarmlyAuthFailure(FarmlyAuthFailureCode.invalidCredentials);
    }
    if (status == 403) {
      return const FarmlyAuthFailure(FarmlyAuthFailureCode.emailNotVerified);
    }
    if (status == 429) {
      return const FarmlyAuthFailure(FarmlyAuthFailureCode.rateLimited);
    }
    if (status == null ||
        status >= 500 ||
        error.type != DioExceptionType.badResponse) {
      return const FarmlyAuthFailure(FarmlyAuthFailureCode.unavailable);
    }
    return const FarmlyAuthFailure(FarmlyAuthFailureCode.unexpected);
  }
}
