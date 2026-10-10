import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';

import 'package:farmly_mobile/app/farmly_app.dart';
import 'package:farmly_mobile/core/auth/auth_session_controller.dart';
import 'package:farmly_mobile/core/auth/better_auth_client.dart';
import 'package:farmly_mobile/core/auth/farmly_auth_models.dart';
import 'package:farmly_mobile/core/config/app_config.dart';
import 'package:farmly_mobile/core/network/farmly_api_client.dart';
import 'package:farmly_mobile/core/storage/secure_secret_store.dart';
import 'package:farmly_mobile/features/app/app_router.dart';
import 'package:farmly_mobile/features/app/app_routes.dart';
import 'package:farmly_mobile/features/demo/demo_providers.dart';
import 'package:farmly_mobile/features/organizations/organization_flow_screens.dart';
import 'package:farmly_mobile/features/organizations/organization_repository.dart';
import 'package:farmly_mobile/features/organizations/organization_scope_controller.dart';
import 'package:farmly_mobile/l10n/locale_controller.dart';

const _session = FarmlyAuthSession(
  user: FarmlyAuthUser(
    id: '11111111-1111-4111-8111-111111111111',
    name: 'Test Farmer',
    email: 'farmer@farmly.test',
  ),
);

class _SignedInSessionController extends FarmlyAuthSessionController {
  @override
  Future<FarmlyAuthSession?> build() async => _session;
}

class _MemorySecretStore implements FarmlySecretStore {
  final _values = <String, String>{};

  @override
  Future<String?> read(String key) async => _values[key];

  @override
  Future<void> write(String key, String value) async => _values[key] = value;

  @override
  Future<void> delete(String key) async => _values.remove(key);
}

class _BlockingSessionDeleteSecretStore extends _MemorySecretStore {
  static const _sessionKey = 'farmly.auth.session.v1';

  _BlockingSessionDeleteSecretStore() {
    _values[_sessionKey] = 'synthetic-session-token';
  }

  final deletionStarted = Completer<void>();
  final releaseDeletion = Completer<void>();

  @override
  Future<void> delete(String key) async {
    if (key == _sessionKey) {
      if (!deletionStarted.isCompleted) deletionStarted.complete();
      await releaseDeletion.future;
    }
    await super.delete(key);
  }
}

class _ExpiredInvitationAdapter implements HttpClientAdapter {
  RequestOptions? lastRequest;

  @override
  Future<ResponseBody> fetch(
    RequestOptions options,
    Stream<Uint8List>? requestStream,
    Future<void>? cancelFuture,
  ) async {
    lastRequest = options;
    return ResponseBody.fromString(
      jsonEncode(<String, Object?>{'code': 'INVITATION_EXPIRED'}),
      410,
      headers: <String, List<String>>{
        Headers.contentTypeHeader: <String>[Headers.jsonContentType],
      },
    );
  }

  @override
  void close({bool force = false}) {}
}

class _DelayedFarmDirectoryAdapter implements HttpClientAdapter {
  final requestStarted = Completer<RequestOptions>();
  final response = Completer<ResponseBody>();

  @override
  Future<ResponseBody> fetch(
    RequestOptions options,
    Stream<Uint8List>? requestStream,
    Future<void>? cancelFuture,
  ) {
    if (!requestStarted.isCompleted) requestStarted.complete(options);
    return response.future;
  }

  @override
  void close({bool force = false}) {}
}

class _UnauthorizedApiAdapter implements HttpClientAdapter {
  RequestOptions? lastRequest;

  @override
  Future<ResponseBody> fetch(
    RequestOptions options,
    Stream<Uint8List>? requestStream,
    Future<void>? cancelFuture,
  ) async {
    lastRequest = options;
    return ResponseBody.fromString(
      jsonEncode(<String, Object?>{'code': 'SESSION_EXPIRED'}),
      401,
      headers: <String, List<String>>{
        Headers.contentTypeHeader: <String>[Headers.jsonContentType],
      },
    );
  }

  @override
  void close({bool force = false}) {}
}

class _HeldUnauthorizedApiAdapter implements HttpClientAdapter {
  final requestStarted = Completer<RequestOptions>();
  final response = Completer<ResponseBody>();

  @override
  Future<ResponseBody> fetch(
    RequestOptions options,
    Stream<Uint8List>? requestStream,
    Future<void>? cancelFuture,
  ) {
    if (!requestStarted.isCompleted) requestStarted.complete(options);
    return response.future;
  }

  void releaseUnauthorized() {
    if (response.isCompleted) return;
    response.complete(
      ResponseBody.fromString(
        jsonEncode(<String, Object?>{'code': 'SESSION_EXPIRED'}),
        401,
        headers: <String, List<String>>{
          Headers.contentTypeHeader: <String>[Headers.jsonContentType],
        },
      ),
    );
  }

  @override
  void close({bool force = false}) {}
}

class _AccountAuthAdapter implements HttpClientAdapter {
  static const accountAToken = 'account-a-session-token';
  static const accountBToken = 'account-b-session-token';

  @override
  Future<ResponseBody> fetch(
    RequestOptions options,
    Stream<Uint8List>? requestStream,
    Future<void>? cancelFuture,
  ) async {
    final path = options.uri.path;
    if (path.endsWith('/sign-in/email')) {
      final body = options.data as Map<String, Object?>;
      final token = body['email'] == 'farmer-b@farmly.test'
          ? accountBToken
          : accountAToken;
      return ResponseBody.fromString(
        '{}',
        200,
        headers: <String, List<String>>{
          Headers.contentTypeHeader: <String>[Headers.jsonContentType],
          'set-auth-token': <String>[token],
        },
      );
    }
    if (path.endsWith('/get-session')) {
      final token = _requestBearer(options);
      final user = token == accountBToken
          ? _accountBSession.user
          : _session.user;
      return ResponseBody.fromString(
        jsonEncode(<String, Object?>{
          'user': <String, Object?>{
            'id': user.id,
            'name': user.name,
            'email': user.email,
            'emailVerified': true,
          },
        }),
        200,
        headers: <String, List<String>>{
          Headers.contentTypeHeader: <String>[Headers.jsonContentType],
        },
      );
    }
    if (path.endsWith('/sign-out')) {
      return ResponseBody.fromString(
        '{}',
        200,
        headers: <String, List<String>>{
          Headers.contentTypeHeader: <String>[Headers.jsonContentType],
        },
      );
    }
    return ResponseBody.fromString('{}', 404);
  }

  @override
  void close({bool force = false}) {}
}

class _AccountOrganizationsAdapter implements HttpClientAdapter {
  _AccountOrganizationsAdapter({this.holdAccountA = false});

  final bool holdAccountA;
  final accountARequestStarted = Completer<void>();
  final releaseAccountA = Completer<void>();
  final requestCounts = <String, int>{};

  @override
  Future<ResponseBody> fetch(
    RequestOptions options,
    Stream<Uint8List>? requestStream,
    Future<void>? cancelFuture,
  ) async {
    if (!options.uri.path.endsWith('/v1/organizations')) {
      return ResponseBody.fromString('{}', 404);
    }
    final token = _requestBearer(options);
    requestCounts.update(token, (count) => count + 1, ifAbsent: () => 1);
    if (holdAccountA && token == _AccountAuthAdapter.accountAToken) {
      if (!accountARequestStarted.isCompleted) {
        accountARequestStarted.complete();
      }
      await releaseAccountA.future;
    }
    final accountB = token == _AccountAuthAdapter.accountBToken;
    final id = accountB
        ? 'bbbbbbbb-bbbb-4bbb-8bbb-bbbbbbbbbbbb'
        : 'aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa';
    final membershipId = accountB
        ? 'dddddddd-dddd-4ddd-8ddd-dddddddddddd'
        : 'cccccccc-cccc-4ccc-8ccc-cccccccccccc';
    final name = accountB ? 'Account B organization' : 'Account A organization';
    return ResponseBody.fromString(
      jsonEncode(<String, Object?>{
        'data': <String, Object?>{
          'organizations': <Object?>[
            <String, Object?>{
              'id': id,
              'name': name,
              'status': 'active',
              'policyVersion': '1',
              'membership': <String, Object?>{
                'id': membershipId,
                'role': 'owner',
                'version': 1,
              },
            },
          ],
        },
        'page': <String, Object?>{'hasMore': false, 'nextCursor': null},
      }),
      200,
      headers: <String, List<String>>{
        Headers.contentTypeHeader: <String>[Headers.jsonContentType],
      },
    );
  }

  @override
  void close({bool force = false}) {}
}

String _requestBearer(RequestOptions options) {
  String? value;
  for (final entry in options.headers.entries) {
    if (entry.key.toLowerCase() == 'authorization') {
      value = entry.value.toString();
      break;
    }
  }
  return value != null && value.startsWith('Bearer ')
      ? value.substring('Bearer '.length)
      : '';
}

const _accountBSession = FarmlyAuthSession(
  user: FarmlyAuthUser(
    id: '22222222-2222-4222-8222-222222222222',
    name: 'Account B Farmer',
    email: 'farmer-b@farmly.test',
  ),
);

class _SessionThenNullAdapter implements HttpClientAdapter {
  var sessionRequests = 0;
  var nullResponses = 0;
  var returnNullOnNextSession = false;

  @override
  Future<ResponseBody> fetch(
    RequestOptions options,
    Stream<Uint8List>? requestStream,
    Future<void>? cancelFuture,
  ) async {
    if (!options.path.endsWith('/get-session')) {
      return ResponseBody.fromString('{}', 404);
    }
    sessionRequests += 1;
    final returnNull = returnNullOnNextSession;
    returnNullOnNextSession = false;
    if (returnNull) nullResponses += 1;
    final body = !returnNull
        ? <String, Object?>{
            'user': <String, Object?>{
              'id': _session.user.id,
              'name': _session.user.name,
              'email': _session.user.email,
              'emailVerified': true,
            },
          }
        : <String, Object?>{'user': null};
    return ResponseBody.fromString(
      jsonEncode(body),
      200,
      headers: <String, List<String>>{
        Headers.contentTypeHeader: <String>[Headers.jsonContentType],
      },
    );
  }

  @override
  void close({bool force = false}) {}
}

Future<({ProviderContainer container, GoRouter router})> _pumpSignedInApp(
  WidgetTester tester, {
  required FarmlyApiClient api,
  List<FarmlyOrganization> organizations = const <FarmlyOrganization>[],
}) async {
  final config = FarmlyAppConfig.fromEnvironment(
    flavorOverride: 'development',
    apiBaseUrlOverride: 'http://127.0.0.1:3000',
  );
  final container = ProviderContainer(
    overrides: [
      farmlyAppConfigProvider.overrideWithValue(config),
      farmlySecretStoreProvider.overrideWithValue(_MemorySecretStore()),
      farmlyAuthSessionProvider.overrideWith(_SignedInSessionController.new),
      farmlyApiClientProvider.overrideWithValue(api),
      farmlyOrganizationsProvider.overrideWith((ref, _) async => organizations),
      // These cases assert EN copy; the app default is vi-VN (spec 01).
      farmlyLocaleProvider.overrideWith(
        () => FarmlyLocaleController(const Locale('en')),
      ),
    ],
  );
  addTearDown(container.dispose);
  final router = container.read(farmlyRouterProvider);
  await tester.pumpWidget(
    UncontrolledProviderScope(
      container: container,
      child: FarmlyApp(config: config),
    ),
  );
  await tester.pumpAndSettle();
  return (container: container, router: router);
}

Future<({ProviderContainer container, GoRouter router})> _pumpServerSessionApp(
  WidgetTester tester, {
  required FarmlyApiClient api,
  required FarmlySecretStore secrets,
  required BetterAuthClient authClient,
  List<FarmlyOrganization> organizations = const <FarmlyOrganization>[],
}) async {
  final config = FarmlyAppConfig.fromEnvironment(
    flavorOverride: 'development',
    apiBaseUrlOverride: 'http://127.0.0.1:3000',
  );
  final container = ProviderContainer(
    overrides: [
      farmlyAppConfigProvider.overrideWithValue(config),
      farmlySecretStoreProvider.overrideWithValue(secrets),
      betterAuthClientProvider.overrideWithValue(authClient),
      farmlyApiClientProvider.overrideWithValue(api),
      farmlyOrganizationsProvider.overrideWith((ref, _) async => organizations),
      farmlyLocaleProvider.overrideWith(
        () => FarmlyLocaleController(const Locale('en')),
      ),
    ],
  );
  addTearDown(container.dispose);
  final router = container.read(farmlyRouterProvider);
  await tester.pumpWidget(
    UncontrolledProviderScope(
      container: container,
      child: FarmlyApp(config: config),
    ),
  );
  for (var attempt = 0; attempt < 20; attempt += 1) {
    final auth = container.read(farmlyAuthSessionProvider);
    if (auth.hasValue &&
        auth.value != null &&
        router.routeInformationProvider.value.uri.path ==
            AppRoutes.organizations) {
      break;
    }
    await tester.pump(const Duration(milliseconds: 50));
  }
  return (container: container, router: router);
}

Future<
  ({
    ProviderContainer container,
    GoRouter router,
    _MemorySecretStore secrets,
    _AccountOrganizationsAdapter organizations,
  })
>
_pumpAccountSwitchApp(
  WidgetTester tester, {
  required _AccountOrganizationsAdapter organizations,
}) async {
  const sessionKey = 'farmly.auth.session.v1';
  final config = FarmlyAppConfig.fromEnvironment(
    flavorOverride: 'development',
    apiBaseUrlOverride: 'http://127.0.0.1:3000',
  );
  final secrets = _MemorySecretStore()
    .._values[sessionKey] = _AccountAuthAdapter.accountAToken;
  final apiDio = Dio(BaseOptions(baseUrl: 'http://127.0.0.1:3000/'))
    ..httpClientAdapter = organizations;
  final authDio = Dio()..httpClientAdapter = _AccountAuthAdapter();
  final authClient = BetterAuthClient(
    apiBaseUrl: config.apiBaseUrl,
    dio: authDio,
  );
  final container = ProviderContainer(
    overrides: [
      farmlyAppConfigProvider.overrideWithValue(config),
      farmlySecretStoreProvider.overrideWithValue(secrets),
      farmlyApiDioProvider.overrideWithValue(apiDio),
      betterAuthClientProvider.overrideWithValue(authClient),
      farmlyLocaleProvider.overrideWith(
        () => FarmlyLocaleController(const Locale('en')),
      ),
    ],
  );
  addTearDown(container.dispose);
  addTearDown(apiDio.close);
  addTearDown(authDio.close);

  final session = await tester.runAsync(
    () => container.read(farmlyAuthSessionProvider.future),
  );
  expect(session?.user.id, _session.user.id);
  final router = container.read(farmlyRouterProvider);
  await tester.pumpWidget(
    UncontrolledProviderScope(
      container: container,
      child: FarmlyApp(config: config),
    ),
  );
  await _pumpBounded(tester);
  return (
    container: container,
    router: router,
    secrets: secrets,
    organizations: organizations,
  );
}

Future<void> _switchToAccountB(
  WidgetTester tester,
  ProviderContainer container,
) async {
  final auth = container.read(farmlyAuthSessionProvider.notifier);
  await tester.runAsync(auth.signOut);
  await tester.pump();
  await tester.runAsync(
    () => auth.signIn(
      email: 'farmer-b@farmly.test',
      password: 'synthetic-password',
      keepSignedIn: true,
    ),
  );
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 400));
  await tester.pump();
}

Future<void> _pumpUntil(
  WidgetTester tester,
  bool Function() condition, {
  required String checkpoint,
  int attempts = 20,
}) async {
  for (var attempt = 0; attempt < attempts; attempt += 1) {
    if (condition()) return;
    await tester.pump(const Duration(milliseconds: 25));
  }
  expect(condition(), isTrue, reason: 'Timed out at checkpoint: $checkpoint');
}

Future<({Dio dio, FarmlyApiClient api})> _apiWithAdapter(
  HttpClientAdapter adapter,
) async {
  final dio = Dio(BaseOptions(baseUrl: 'https://farmly.test/'))
    ..httpClientAdapter = adapter;
  final credentials = FarmlySessionCredentials(
    FarmlySessionTokenStore(_MemorySecretStore()),
  );
  await credentials.set('synthetic-session-token', persist: false);
  return (
    dio: dio,
    api: FarmlyApiClient(
      dio: dio,
      credentials: credentials,
      sessionGeneration: () => 0,
      onUnauthorized: (_, _) async {},
    ),
  );
}

Future<(Dio dio, FarmlyApiClient api, _ExpiredInvitationAdapter adapter)>
_newApi() async {
  final adapter = _ExpiredInvitationAdapter();
  final dio = Dio(BaseOptions(baseUrl: 'https://farmly.test/'))
    ..httpClientAdapter = adapter;
  final credentials = FarmlySessionCredentials(
    FarmlySessionTokenStore(_MemorySecretStore()),
  );
  await credentials.set('synthetic-session-token', persist: false);
  final api = FarmlyApiClient(
    dio: dio,
    credentials: credentials,
    sessionGeneration: () => 0,
    onUnauthorized: (_, _) async {},
  );
  return (dio, api, adapter);
}

Future<void> _pumpBounded(WidgetTester tester) async {
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 400));
  await tester.pump();
}

void main() {
  const organization = FarmlyOrganization(
    id: '22222222-2222-4222-8222-222222222222',
    name: 'Mekong Farms',
    status: FarmlyOrganizationStatus.active,
    policyVersion: '1',
    role: FarmlyOrganizationRole.owner,
    membershipVersion: 1,
  );

  testWidgets(
    'signed-in user with no organizations gets the empty-state path',
    (tester) async {
      final (dio, api, adapter) = await _newApi();
      addTearDown(dio.close);
      final app = await _pumpSignedInApp(tester, api: api);
      final router = app.router;

      expect(
        router.routeInformationProvider.value.uri.path,
        AppRoutes.organizations,
      );
      expect(find.text('No organization yet'), findsOneWidget);
      expect(
        find.text(
          'Create an organization or open an invitation link to get started.',
        ),
        findsOneWidget,
      );

      final create = find.widgetWithText(FilledButton, 'Create organization');
      await tester.ensureVisible(create);
      await tester.tap(create);
      await tester.pumpAndSettle();

      expect(find.text('Enter an organization name.'), findsOneWidget);
      expect(adapter.lastRequest, isNull);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'cached organizations are fetched again after switching accounts',
    (tester) async {
      final adapter = _AccountOrganizationsAdapter();
      final app = await _pumpAccountSwitchApp(tester, organizations: adapter);
      await _pumpUntil(
        tester,
        () => find.text('Account A organization').evaluate().isNotEmpty,
        checkpoint: 'account A organization list loaded',
      );

      await _switchToAccountB(tester, app.container);

      expect(
        adapter.requestCounts[_AccountAuthAdapter.accountBToken],
        1,
        reason: 'Account B must load its own organization list.',
      );
      expect(find.text('Account A organization'), findsNothing);
      expect(find.text('Account B organization'), findsOneWidget);
    },
  );

  testWidgets(
    'late organization response from the previous account is discarded',
    (tester) async {
      final adapter = _AccountOrganizationsAdapter(holdAccountA: true);
      final app = await _pumpAccountSwitchApp(tester, organizations: adapter);
      await _pumpUntil(
        tester,
        () => adapter.accountARequestStarted.isCompleted,
        checkpoint: 'account A organization request started',
      );
      await adapter.accountARequestStarted.future.timeout(
        const Duration(seconds: 3),
      );

      try {
        await _switchToAccountB(tester, app.container);
        adapter.releaseAccountA.complete();
        await _pumpBounded(tester);

        expect(
          adapter.requestCounts[_AccountAuthAdapter.accountBToken],
          1,
          reason: 'Account B must issue a request in its own session scope.',
        );
        expect(find.text('Account A organization'), findsNothing);
        expect(find.text('Account B organization'), findsOneWidget);
      } finally {
        if (!adapter.releaseAccountA.isCompleted) {
          adapter.releaseAccountA.complete();
        }
      }
    },
  );

  test(
    'queued credential replacement waits for held secure deletion',
    () async {
      final secrets = _BlockingSessionDeleteSecretStore();
      secrets._values[_BlockingSessionDeleteSecretStore._sessionKey] =
          _AccountAuthAdapter.accountAToken;
      final credentials = FarmlySessionCredentials(
        FarmlySessionTokenStore(secrets),
      );
      expect(await credentials.restore(), _AccountAuthAdapter.accountAToken);

      final cleanup = credentials.clear();
      await secrets.deletionStarted.future;
      final replacement = credentials.set(
        _AccountAuthAdapter.accountBToken,
        persist: true,
      );
      await Future<void>.delayed(Duration.zero);
      expect(
        secrets._values[_BlockingSessionDeleteSecretStore._sessionKey],
        _AccountAuthAdapter.accountAToken,
        reason:
            'The new token must wait until the old secure deletion finishes.',
      );

      secrets.releaseDeletion.complete();
      await Future.wait(<Future<void>>[cleanup, replacement]);
      expect(
        secrets._values[_BlockingSessionDeleteSecretStore._sessionKey],
        _AccountAuthAdapter.accountBToken,
      );
      expect(credentials.currentToken, _AccountAuthAdapter.accountBToken);
    },
  );

  test(
    'late account A 401 cannot clear account B session, scope, or credential',
    () async {
      const sessionKey = 'farmly.auth.session.v1';
      final secrets = _MemorySecretStore()
        .._values[sessionKey] = _AccountAuthAdapter.accountAToken;
      final apiAdapter = _HeldUnauthorizedApiAdapter();
      final apiDio = Dio(BaseOptions(baseUrl: 'http://127.0.0.1:3000/'))
        ..httpClientAdapter = apiAdapter;
      final authDio = Dio()..httpClientAdapter = _AccountAuthAdapter();
      final config = FarmlyAppConfig.fromEnvironment(
        flavorOverride: 'development',
        apiBaseUrlOverride: 'http://127.0.0.1:3000',
      );
      final container = ProviderContainer(
        overrides: [
          farmlyAppConfigProvider.overrideWithValue(config),
          farmlySecretStoreProvider.overrideWithValue(secrets),
          farmlyApiDioProvider.overrideWithValue(apiDio),
          betterAuthClientProvider.overrideWithValue(
            BetterAuthClient(apiBaseUrl: config.apiBaseUrl, dio: authDio),
          ),
        ],
      );
      addTearDown(container.dispose);
      addTearDown(apiDio.close);
      addTearDown(authDio.close);

      final initial = await container.read(farmlyAuthSessionProvider.future);
      expect(initial?.user.id, _session.user.id);
      container.read(farmlyRouterProvider);
      final request = container.read(farmlyApiClientProvider).get('v1/stale');
      await apiAdapter.requestStarted.future.timeout(
        const Duration(seconds: 3),
      );
      expect(
        _requestBearer(await apiAdapter.requestStarted.future),
        _AccountAuthAdapter.accountAToken,
      );

      try {
        final auth = container.read(farmlyAuthSessionProvider.notifier);
        await auth.signOut();
        await auth.signIn(
          email: 'farmer-b@farmly.test',
          password: 'synthetic-password',
          keepSignedIn: true,
        );
        final accountB = container.read(farmlyAuthSessionProvider).value;
        expect(accountB?.user.id, _accountBSession.user.id);

        final scope = container.read(
          selectedOrganizationScopeProvider.notifier,
        );
        final ticket = scope.beginSelection();
        final selected = await scope.select(
          organization,
          const FarmlyFarmDirectory(
            scopePolicyVersion: '1',
            continuityEpoch: '1',
            farms: <FarmlyDirectoryFarm>[
              FarmlyDirectoryFarm(
                id: '44444444-4444-4444-8444-444444444444',
                name: 'Test farm',
                status: FarmlyFarmStatus.active,
                grantRole: FarmlyFarmGrantRole.owner,
              ),
            ],
          ),
          ticket: ticket,
        );
        expect(selected, isTrue);
        final accountBScope = container.read(selectedOrganizationScopeProvider);
        expect(
          accountBScope?.selectedFarmId,
          '44444444-4444-4444-8444-444444444444',
        );

        apiAdapter.releaseUnauthorized();
        await expectLater(
          request,
          throwsA(
            isA<FarmlyApiFailure>().having(
              (failure) => failure.code,
              'code',
              FarmlyApiFailureCode.unauthenticated,
            ),
          ),
        );

        expect(
          container.read(farmlyAuthSessionProvider).value?.user.id,
          _accountBSession.user.id,
        );
        expect(
          container.read(selectedOrganizationScopeProvider)?.selectedFarmId,
          accountBScope?.selectedFarmId,
        );
        expect(
          container.read(farmlySessionCredentialsProvider).currentToken,
          _AccountAuthAdapter.accountBToken,
        );
        expect(
          await secrets.read(sessionKey),
          _AccountAuthAdapter.accountBToken,
        );
      } finally {
        apiAdapter.releaseUnauthorized();
      }
    },
  );

  testWidgets('expired invitation is mapped to a safe recoverable message', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(640, 360);
    tester.view.devicePixelRatio = 1;
    final dispatcher = tester.binding.platformDispatcher;
    dispatcher.textScaleFactorTestValue = 2;
    addTearDown(tester.view.reset);
    addTearDown(dispatcher.clearTextScaleFactorTestValue);

    final (dio, api, adapter) = await _newApi();
    addTearDown(dio.close);
    final app = await _pumpSignedInApp(tester, api: api);
    final router = app.router;
    const organizationId = '22222222-2222-4222-8222-222222222222';
    const invitationId = '33333333-3333-4333-8333-333333333333';
    final token = List<String>.filled(64, 'a').join();

    router.go(
      Uri(
        path: AppRoutes.invitation,
        queryParameters: <String, String>{
          'organizationId': organizationId,
          'invitationId': invitationId,
          'token': token,
        },
      ).toString(),
    );
    await tester.pumpAndSettle();

    final accept = find.widgetWithText(FilledButton, 'Accept invitation');
    await tester.ensureVisible(accept);
    await tester.tap(accept);
    await tester.pumpAndSettle();

    expect(
      find.text(
        'This invitation has expired. Ask an owner or administrator for a new one.',
      ),
      findsOneWidget,
    );
    await tester.ensureVisible(
      find.text(
        'This invitation has expired. Ask an owner or administrator for a new one.',
      ),
    );
    expect(adapter.lastRequest?.method, 'POST');
    expect(
      adapter.lastRequest?.path,
      contains(
        '/organizations/$organizationId/invitations/$invitationId/accept',
      ),
    );
    expect(adapter.lastRequest?.headers['Idempotency-Key'], isA<String>());
    expect(tester.takeException(), isNull);
  });

  testWidgets(
    'stale farm-directory completion cannot restore a cleared scope',
    (tester) async {
      final adapter = _DelayedFarmDirectoryAdapter();
      final (:dio, :api) = await _apiWithAdapter(adapter);
      addTearDown(dio.close);
      final app = await _pumpSignedInApp(
        tester,
        api: api,
        organizations: const <FarmlyOrganization>[organization],
      );

      final organizationTile = find.widgetWithText(ListTile, organization.name);
      expect(organizationTile, findsOneWidget);
      await tester.ensureVisible(organizationTile);
      await tester.tap(organizationTile);
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 10));
      expect(
        adapter.requestStarted.isCompleted,
        isTrue,
        reason: 'Selecting an organization must start the farm-directory GET.',
      );
      final request = await adapter.requestStarted.future;
      expect(
        request.path,
        contains('/organizations/${organization.id}/farm-directory'),
      );

      app.container.read(selectedOrganizationScopeProvider.notifier).clear();
      adapter.response.complete(
        ResponseBody.fromString(
          jsonEncode(<String, Object?>{
            'schemaVersion': 'farm-directory.v1',
            'scopePolicyVersion': '9007199254740993',
            'continuityEpoch': '1',
            'farms': <Object?>[
              <String, Object?>{
                'farmId': '44444444-4444-4444-8444-444444444444',
                'farmName': 'Test farm',
                'status': 'active',
                'grantRole': 'owner',
              },
            ],
            'nextCursor': null,
          }),
          200,
          headers: <String, List<String>>{
            Headers.contentTypeHeader: <String>[Headers.jsonContentType],
          },
        ),
      );
      await tester.pumpAndSettle();

      expect(app.container.read(selectedOrganizationScopeProvider), isNull);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'auth null invalidates a pending farm-directory ticket before secure deletion',
    (tester) async {
      final directoryAdapter = _DelayedFarmDirectoryAdapter();
      final (:dio, :api) = await _apiWithAdapter(directoryAdapter);
      addTearDown(dio.close);

      final secrets = _BlockingSessionDeleteSecretStore();
      final authAdapter = _SessionThenNullAdapter();
      final authDio = Dio(BaseOptions(baseUrl: 'http://127.0.0.1:3000/'))
        ..httpClientAdapter = authAdapter;
      addTearDown(authDio.close);
      final app = await _pumpServerSessionApp(
        tester,
        api: api,
        secrets: secrets,
        authClient: BetterAuthClient(
          apiBaseUrl: Uri.parse('http://127.0.0.1:3000'),
          dio: authDio,
        ),
        organizations: const <FarmlyOrganization>[organization],
      );
      expect(
        app.router.routeInformationProvider.value.uri.path,
        AppRoutes.organizations,
      );
      expect(authAdapter.nullResponses, 0);

      final previewFarmId = app.container.read(demoDataProvider).selectedFarmId;
      await _pumpUntil(
        tester,
        () => find.text(organization.name).evaluate().isNotEmpty,
        checkpoint: 'organization list tile render',
      );
      final organizationTile = find.widgetWithText(ListTile, organization.name);
      await tester.ensureVisible(organizationTile);
      await tester.tap(organizationTile);
      await tester.pump();
      await _pumpUntil(
        tester,
        () => directoryAdapter.requestStarted.isCompleted,
        checkpoint: 'farm-directory GET start',
      );
      final directoryRequest = await directoryAdapter.requestStarted.future
          .timeout(const Duration(seconds: 2));
      expect(
        directoryRequest.path,
        contains('/organizations/${organization.id}/farm-directory'),
      );
      expect(authAdapter.nullResponses, 0);

      authAdapter.returnNullOnNextSession = true;
      final authRefresh = app.container
          .read(farmlyAuthSessionProvider.notifier)
          .refreshFromServer();
      await _pumpUntil(
        tester,
        () => secrets.deletionStarted.isCompleted,
        checkpoint: 'secure-store session-token deletion start',
      );

      try {
        directoryAdapter.response.complete(
          ResponseBody.fromString(
            jsonEncode(<String, Object?>{
              'schemaVersion': 'farm-directory.v1',
              'scopePolicyVersion': '9007199254740993',
              'continuityEpoch': '1',
              'farms': <Object?>[
                <String, Object?>{
                  'farmId': '44444444-4444-4444-8444-444444444444',
                  'farmName': 'Test farm',
                  'status': 'active',
                  'grantRole': 'owner',
                },
              ],
              'nextCursor': null,
            }),
            200,
            headers: <String, List<String>>{
              Headers.contentTypeHeader: <String>[Headers.jsonContentType],
            },
          ),
        );
        await _pumpUntil(
          tester,
          () =>
              app.container.read(selectedOrganizationScopeProvider) != null ||
              app.router.routeInformationProvider.value.uri.path ==
                  AppRoutes.login,
          checkpoint: 'directory response completion or auth redirect',
        );

        expect(
          <String, Object?>{
            'scope': app.container.read(selectedOrganizationScopeProvider),
            'shellBannerVisible': find
                .byTooltip('Change farm')
                .evaluate()
                .isNotEmpty,
            'previewFarmId': app.container
                .read(demoDataProvider)
                .selectedFarmId,
          },
          <String, Object?>{
            'scope': null,
            'shellBannerVisible': false,
            'previewFarmId': previewFarmId,
          },
          reason:
              'The null server session must invalidate the selection ticket '
              'before credential deletion can finish.',
        );
      } finally {
        if (!secrets.releaseDeletion.isCompleted) {
          secrets.releaseDeletion.complete();
        }
        var refreshFinished = false;
        authRefresh.then((_) => refreshFinished = true);
        await _pumpUntil(
          tester,
          () => refreshFinished,
          checkpoint: 'auth refresh completion after releasing deletion',
        );
      }

      expect(app.container.read(selectedOrganizationScopeProvider), isNull);
      expect(find.byTooltip('Change farm'), findsNothing);
      expect(
        app.container.read(demoDataProvider).selectedFarmId,
        previewFarmId,
      );
      expect(tester.takeException(), isNull);
    },
  );

  test(
    'API provider 401 clears auth and scope before secure deletion',
    () async {
      final unauthorizedAdapter = _UnauthorizedApiAdapter();
      final dio = Dio(BaseOptions(baseUrl: 'https://api.farmly.test/'))
        ..httpClientAdapter = unauthorizedAdapter;
      addTearDown(dio.close);
      final secrets = _BlockingSessionDeleteSecretStore();
      final container = ProviderContainer(
        overrides: [
          farmlyApiDioProvider.overrideWithValue(dio),
          farmlySecretStoreProvider.overrideWithValue(secrets),
          farmlyAuthSessionProvider.overrideWith(
            _SignedInSessionController.new,
          ),
        ],
      );
      addTearDown(container.dispose);

      expect(await container.read(farmlyAuthSessionProvider.future), _session);
      final scopeController = container.read(
        selectedOrganizationScopeProvider.notifier,
      );
      final ticket = scopeController.beginSelection();
      await scopeController.select(
        organization,
        const FarmlyFarmDirectory(
          scopePolicyVersion: '1',
          continuityEpoch: '1',
          farms: <FarmlyDirectoryFarm>[
            FarmlyDirectoryFarm(
              id: '44444444-4444-4444-8444-444444444444',
              name: 'Test farm',
              status: FarmlyFarmStatus.active,
              grantRole: FarmlyFarmGrantRole.owner,
            ),
          ],
        ),
        ticket: ticket,
      );
      expect(container.read(selectedOrganizationScopeProvider), isNotNull);

      // Install the router listener that clears the selected scope on auth loss.
      container.read(farmlyRouterProvider);
      final api = container.read(farmlyApiClientProvider);
      final request = api.get('v1/test-401');
      AsyncValue<FarmlyAuthSession?>? authDuringDelete;
      Object? scopeDuringDelete;
      var reachedDeleteBarrier = false;

      try {
        await secrets.deletionStarted.future.timeout(
          const Duration(seconds: 3),
        );
        reachedDeleteBarrier = true;
        expect(unauthorizedAdapter.lastRequest?.path, 'v1/test-401');
        expect(
          unauthorizedAdapter.lastRequest?.headers['Authorization'],
          'Bearer synthetic-session-token',
        );
        authDuringDelete = container.read(farmlyAuthSessionProvider);
        scopeDuringDelete = container.read(selectedOrganizationScopeProvider);
      } finally {
        if (!secrets.releaseDeletion.isCompleted) {
          secrets.releaseDeletion.complete();
        }
      }

      await expectLater(
        request.timeout(const Duration(seconds: 3)),
        throwsA(
          isA<FarmlyApiFailure>().having(
            (failure) => failure.code,
            'code',
            FarmlyApiFailureCode.unauthenticated,
          ),
        ),
      );
      expect(reachedDeleteBarrier, isTrue);
      expect(authDuringDelete?.hasValue, isTrue);
      expect(authDuringDelete?.value, isNull);
      expect(scopeDuringDelete, isNull);
    },
  );

  testWidgets(
    'live farm picker uses authorized grants without changing preview selection',
    (tester) async {
      final adapter = _DelayedFarmDirectoryAdapter();
      final (:dio, :api) = await _apiWithAdapter(adapter);
      addTearDown(dio.close);
      final app = await _pumpSignedInApp(
        tester,
        api: api,
        organizations: const <FarmlyOrganization>[organization],
      );
      final previewFarmId = app.container.read(demoDataProvider).selectedFarmId;

      final organizationTile = find.widgetWithText(ListTile, organization.name);
      await tester.ensureVisible(organizationTile);
      await tester.tap(organizationTile);
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 10));
      expect(adapter.requestStarted.isCompleted, isTrue);
      adapter.response.complete(
        ResponseBody.fromString(
          jsonEncode(<String, Object?>{
            'schemaVersion': 'farm-directory.v1',
            'scopePolicyVersion': '9007199254740993',
            'continuityEpoch': '1',
            'farms': <Object?>[
              <String, Object?>{
                'farmId': '44444444-4444-4444-8444-444444444444',
                'farmName': 'North farm',
                'status': 'active',
                'grantRole': 'owner',
              },
              <String, Object?>{
                'farmId': '55555555-5555-4555-8555-555555555555',
                'farmName': 'South farm',
                'status': 'active',
                'grantRole': 'worker',
              },
            ],
            'nextCursor': null,
          }),
          200,
          headers: <String, List<String>>{
            Headers.contentTypeHeader: <String>[Headers.jsonContentType],
          },
        ),
      );
      await _pumpBounded(tester);

      expect(
        app.router.routeInformationProvider.value.uri.path,
        AppRoutes.home,
      );
      expect(
        find.text(
          'Preview data only. These figures are examples, not live farm records.',
        ),
        findsOneWidget,
      );
      expect(
        app.container.read(selectedOrganizationScopeProvider)?.selectedFarmId,
        '44444444-4444-4444-8444-444444444444',
      );
      final farmPickerButton = find.byTooltip('Change farm');
      expect(farmPickerButton, findsOneWidget);
      await tester.tap(farmPickerButton);
      await _pumpBounded(tester);

      final secondFarm = find.widgetWithText(
        ListTile,
        'South farm',
      );
      expect(secondFarm, findsOneWidget);
      await tester.tap(secondFarm);
      await _pumpBounded(tester);

      expect(
        app.container.read(selectedOrganizationScopeProvider)?.selectedFarmId,
        '55555555-5555-4555-8555-555555555555',
      );
      expect(
        app.container.read(demoDataProvider).selectedFarmId,
        previewFarmId,
      );
      expect(tester.takeException(), isNull);
    },
  );
}
