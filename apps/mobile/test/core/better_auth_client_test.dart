import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:farmly_mobile/core/auth/better_auth_client.dart';
import 'package:farmly_mobile/core/auth/farmly_auth_models.dart';

void main() {
  test(
    'sign-in uses the verified token header and pinned endpoint fields',
    () async {
      RequestOptions? captured;
      final dio = Dio()
        ..interceptors.add(
          InterceptorsWrapper(
            onRequest: (options, handler) {
              captured = options;
              handler.resolve(
                Response<Object?>(
                  requestOptions: options,
                  statusCode: 200,
                  data: {'token': 'must-not-be-used'},
                  headers: Headers.fromMap({
                    'set-auth-token': ['opaque-token'],
                  }),
                ),
              );
            },
          ),
        );
      final client = BetterAuthClient(
        apiBaseUrl: Uri.parse('https://api.farmly.test/v1/'),
        dio: dio,
      );

      final token = await client.signIn(
        email: 'farmer@farmly.test',
        password: 'private-password',
        rememberMe: true,
      );

      expect(token, 'opaque-token');
      expect(captured!.uri.path, '/v1/api/auth/sign-in/email');
      expect(captured!.data, {
        'email': 'farmer@farmly.test',
        'password': 'private-password',
        'rememberMe': true,
      });
      dio.close(force: true);
    },
  );

  test('sign-in fails closed when the bearer header is absent', () async {
    final dio = Dio()
      ..interceptors.add(
        InterceptorsWrapper(
          onRequest: (options, handler) => handler.resolve(
            Response<Object?>(
              requestOptions: options,
              statusCode: 200,
              data: {'token': 'body-token'},
            ),
          ),
        ),
      );
    final client = BetterAuthClient(
      apiBaseUrl: Uri.parse('https://api.farmly.test'),
      dio: dio,
    );

    await expectLater(
      client.signIn(
        email: 'farmer@farmly.test',
        password: 'private-password',
        rememberMe: false,
      ),
      throwsA(
        isA<FarmlyAuthFailure>().having(
          (failure) => failure.code,
          'code',
          FarmlyAuthFailureCode.unexpected,
        ),
      ),
    );
    dio.close(force: true);
  });

  test(
    'verification callbacks preserve only a safe local invitation target',
    () async {
      final requests = <RequestOptions>[];
      final dio = Dio()
        ..interceptors.add(
          InterceptorsWrapper(
            onRequest: (options, handler) {
              requests.add(options);
              handler.resolve(
                Response<Object?>(
                  requestOptions: options,
                  statusCode: 200,
                  data: const <String, Object?>{},
                ),
              );
            },
          ),
        );
      final client = BetterAuthClient(
        apiBaseUrl: Uri.parse('https://api.farmly.test'),
        dio: dio,
      );

      await client.signUp(
        name: 'Farmly Member',
        email: 'member@farmly.test',
        password: 'private-password',
        returnTo: '/invite?organizationId=org&token=private-token',
      );
      await client.sendVerificationEmail(
        'member@farmly.test',
        returnTo: 'https://evil.example/capture',
      );

      final safeCallback = Uri.parse(
        (requests.first.data as Map<String, Object?>)['callbackURL']! as String,
      );
      final rejectedCallback = Uri.parse(
        (requests.last.data as Map<String, Object?>)['callbackURL']! as String,
      );
      expect(safeCallback.scheme, 'farmly');
      expect(safeCallback.path, '/auth/verified');
      expect(
        safeCallback.queryParameters['returnTo'],
        '/invite?organizationId=org&token=private-token',
      );
      expect(
        rejectedCallback.toString(),
        BetterAuthClient.farmlyVerifiedCallback,
      );
      dio.close(force: true);
    },
  );
}
