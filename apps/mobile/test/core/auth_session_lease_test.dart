import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:farmly_mobile/core/auth/auth_session_controller.dart';
import 'package:farmly_mobile/core/auth/better_auth_client.dart';
import 'package:farmly_mobile/core/auth/farmly_auth_models.dart';
import 'package:farmly_mobile/core/auth/offline_session_lease.dart';
import 'package:farmly_mobile/core/network/farmly_api_client.dart';
import 'package:farmly_mobile/core/storage/secure_secret_store.dart';
import 'package:farmly_mobile/features/app/app_router.dart';
import 'package:farmly_mobile/features/organizations/organization_repository.dart';
import 'package:farmly_mobile/features/organizations/organization_scope_controller.dart';

final _now = DateTime.utc(2026, 10, 7, 12);
const _sessionJson = <String, Object?>{
  'user': <String, Object?>{
    'id': 'user-1',
    'name': 'Test Farmer',
    'email': 'farmer@farmly.test',
    'emailVerified': true,
  },
};
const _session = FarmlyAuthSession(
  user: FarmlyAuthUser(
    id: 'user-1',
    name: 'Test Farmer',
    email: 'farmer@farmly.test',
  ),
);
const _secondSessionJson = <String, Object?>{
  'user': <String, Object?>{
    'id': 'user-2',
    'name': 'Second Farmer',
    'email': 'second@farmly.test',
    'emailVerified': true,
  },
};
const _secondSession = FarmlyAuthSession(
  user: FarmlyAuthUser(
    id: 'user-2',
    name: 'Second Farmer',
    email: 'second@farmly.test',
  ),
);

class _MemorySecretStore implements FarmlySecretStore {
  final values = <String, String>{};

  @override
  Future<String?> read(String key) async => values[key];

  @override
  Future<void> write(String key, String value) async => values[key] = value;

  @override
  Future<void> delete(String key) async => values.remove(key);
}

class _HeldLeaseReadSecretStore extends _MemorySecretStore {
  final readStarted = Completer<void>();
  final releaseRead = Completer<void>();
  bool _holdNextLeaseRead = false;

  void holdNextLeaseRead() => _holdNextLeaseRead = true;

  @override
  Future<String?> read(String key) async {
    final captured = values[key];
    if (key == FarmlyOfflineSessionLeaseStore.storageKey &&
        _holdNextLeaseRead) {
      _holdNextLeaseRead = false;
      readStarted.complete();
      await releaseRead.future;
    }
    return captured;
  }
}

class _HeldLeaseWriteSecretStore extends _MemorySecretStore {
  final writeStarted = Completer<void>();
  final releaseWrite = Completer<void>();

  @override
  Future<void> write(String key, String value) async {
    if (key == FarmlyOfflineSessionLeaseStore.storageKey) {
      if (!writeStarted.isCompleted) writeStarted.complete();
      await releaseWrite.future;
    }
    await super.write(key, value);
  }
}

class _HeldSessionWriteSecretStore extends _MemorySecretStore {
  final writeStarted = Completer<void>();
  final releaseWrite = Completer<void>();

  @override
  Future<void> write(String key, String value) async {
    if (key == 'farmly.auth.session.v1' &&
        value == 'session-token-b' &&
        !writeStarted.isCompleted) {
      writeStarted.complete();
      await releaseWrite.future;
    }
    await super.write(key, value);
  }
}

class _SessionAdapter implements HttpClientAdapter {
  _SessionAdapter(this.response);

  final Future<ResponseBody> Function(RequestOptions options) response;

  @override
  Future<ResponseBody> fetch(
    RequestOptions options,
    Stream<Uint8List>? requestStream,
    Future<void>? cancelFuture,
  ) => response(options);

  @override
  void close({bool force = false}) {}
}

ProviderContainer _container({
  required FarmlySecretStore secrets,
  required HttpClientAdapter adapter,
  required DateTime Function() clock,
}) {
  final dio = Dio(BaseOptions(baseUrl: 'https://farmly.test/'))
    ..httpClientAdapter = adapter;
  final container = ProviderContainer(
    overrides: [
      farmlySecretStoreProvider.overrideWithValue(secrets),
      farmlyAuthClockProvider.overrideWithValue(clock),
      betterAuthClientProvider.overrideWithValue(
        BetterAuthClient(
          apiBaseUrl: Uri.parse('https://farmly.test'),
          dio: dio,
        ),
      ),
    ],
  );
  addTearDown(container.dispose);
  addTearDown(dio.close);
  return container;
}

ResponseBody _jsonResponse(Object? body, int status) => ResponseBody.fromString(
  jsonEncode(body),
  status,
  headers: <String, List<String>>{
    Headers.contentTypeHeader: <String>[Headers.jsonContentType],
  },
);

Future<void> _seedPersistentToken(
  _MemorySecretStore secrets, {
  String token = 'synthetic-session-token',
}) => FarmlySessionTokenStore(secrets).save(token);

ResponseBody _signInResponse(String token) => ResponseBody.fromString(
  '{}',
  200,
  headers: <String, List<String>>{
    Headers.contentTypeHeader: <String>[Headers.jsonContentType],
    'set-auth-token': <String>[token],
  },
);

class _RecordingApiAdapter implements HttpClientAdapter {
  final requests = <RequestOptions>[];

  @override
  Future<ResponseBody> fetch(
    RequestOptions options,
    Stream<Uint8List>? requestStream,
    Future<void>? cancelFuture,
  ) async {
    requests.add(options);
    return ResponseBody.fromString(
      '{}',
      200,
      headers: <String, List<String>>{
        Headers.contentTypeHeader: <String>[Headers.jsonContentType],
      },
    );
  }

  @override
  void close({bool force = false}) {}
}

void main() {
  test(
    'offline startup restores the latest validated session within 7 days',
    () async {
      final secrets = _MemorySecretStore();
      await _seedPersistentToken(secrets);
      final firstRun = _container(
        secrets: secrets,
        adapter: _SessionAdapter((_) async => _jsonResponse(_sessionJson, 200)),
        clock: () => _now,
      );

      final online = await firstRun.read(farmlyAuthSessionProvider.future);
      expect(online?.user.id, _session.user.id);

      // A fresh container models an app restart; no in-memory session survives.
      final restarted = _container(
        secrets: secrets,
        adapter: _SessionAdapter((options) async {
          throw DioException.connectionError(
            requestOptions: options,
            reason: 'offline test transport',
            error: StateError('offline'),
          );
        }),
        clock: () => _now.add(const Duration(days: 6, hours: 23)),
      );
      final offline = await restarted.read(farmlyAuthSessionProvider.future);

      expect(offline?.user.id, _session.user.id);
    },
  );

  test(
    'offline startup restores the last authorized organization and farm',
    () async {
      final secrets = _MemorySecretStore();
      await _seedPersistentToken(secrets);
      final leaseStore = FarmlyOfflineSessionLeaseStore(secrets);
      await leaseStore.recordAuthoritativeValidation(
        session: _session,
        validatedAt: _now,
      );
      await leaseStore.saveOrganizationScope(
        validatedAt: _now,
        snapshot: <String, Object?>{
          'version': 1,
          'organization': <String, Object?>{
            'id': '22222222-2222-4222-8222-222222222222',
            'name': 'Mekong Farms',
            'status': 'active',
            'policyVersion': '9007199254740993',
            'membership': <String, Object?>{
              'id': '33333333-3333-4333-8333-333333333333',
              'role': 'owner',
              'version': 1,
            },
          },
          'directory': <String, Object?>{
            'scopePolicyVersion': '9007199254740993',
            'continuityEpoch': '4',
            'farms': <Object?>[
              <String, Object?>{
                'farmId': '44444444-4444-4444-8444-444444444444',
                'farmName': 'Test farm',
                'status': 'active',
                'grantRole': 'owner',
              },
            ],
          },
          'selectedFarmId': '44444444-4444-4444-8444-444444444444',
        },
      );
      final container = _container(
        secrets: secrets,
        adapter: _SessionAdapter((options) async {
          throw DioException.connectionError(
            requestOptions: options,
            reason: 'offline test transport',
            error: StateError('offline'),
          );
        }),
        clock: () => _now.add(const Duration(days: 1)),
      );

      final session = await container.read(farmlyAuthSessionProvider.future);
      final scope = container.read(selectedOrganizationScopeProvider);

      expect(session?.user.id, _session.user.id);
      expect(scope?.organization.name, 'Mekong Farms');
      expect(scope?.directory.scopePolicyVersion, '9007199254740993');
      expect(scope?.selectedFarmId, '44444444-4444-4444-8444-444444444444');
    },
  );

  test(
    'expired offline lease requires online recovery and preserves pending data',
    () async {
      final secrets = _MemorySecretStore()
        ..values['farmly.pending.test'] = 'encrypted-pending-work';
      await _seedPersistentToken(secrets);
      await FarmlyOfflineSessionLeaseStore(
        secrets,
      ).recordAuthoritativeValidation(
        session: _session,
        validatedAt: _now.subtract(const Duration(days: 8)),
      );
      final container = _container(
        secrets: secrets,
        adapter: _SessionAdapter((options) async {
          throw DioException.connectionError(
            requestOptions: options,
            reason: 'offline test transport',
            error: StateError('offline'),
          );
        }),
        clock: () => _now,
      );

      final failed = Completer<AsyncValue<FarmlyAuthSession?>>();
      final subscription = container.listen(farmlyAuthSessionProvider, (
        _,
        next,
      ) {
        if (next is AsyncError<FarmlyAuthSession?> && !failed.isCompleted) {
          failed.complete(next);
        }
      });
      addTearDown(subscription.close);
      late AsyncValue<FarmlyAuthSession?> state;
      state = await failed.future.timeout(const Duration(seconds: 2));
      final failure = (state as AsyncError<FarmlyAuthSession?>).error;
      expect(failure, isA<FarmlyAuthFailure>());
      expect(
        (failure as FarmlyAuthFailure).code,
        FarmlyAuthFailureCode.offlineLeaseExpired,
      );
      expect(secrets.values['farmly.auth.session.v1'], isNotNull);
      expect(secrets.values['farmly.pending.test'], 'encrypted-pending-work');
    },
  );

  test(
    'active lease expiry clears restored scope but preserves credentials and pending work',
    () async {
      final secrets = _MemorySecretStore()
        ..values['farmly.pending.test'] = 'encrypted-pending-work';
      await _seedPersistentToken(secrets);
      var now = _now;
      var calls = 0;
      final container = _container(
        secrets: secrets,
        adapter: _SessionAdapter((options) async {
          calls += 1;
          if (calls == 1) return _jsonResponse(_sessionJson, 200);
          throw DioException.connectionError(
            requestOptions: options,
            reason: 'offline test transport',
            error: StateError('offline'),
          );
        }),
        clock: () => now,
      );
      // The production router clears the in-memory selected scope whenever
      // an authenticated session becomes invalid or its offline lease expires.
      container.read(farmlyRouterProvider);

      expect(
        (await container.read(farmlyAuthSessionProvider.future))?.user.id,
        _session.user.id,
      );
      final scopeController = container.read(
        selectedOrganizationScopeProvider.notifier,
      );
      final ticket = scopeController.beginSelection();
      expect(
        await scopeController.select(
          const FarmlyOrganization(
            id: '22222222-2222-4222-8222-222222222222',
            name: 'Mekong Farms',
            status: FarmlyOrganizationStatus.active,
            policyVersion: '1',
            role: FarmlyOrganizationRole.owner,
            membershipVersion: 1,
          ),
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
        ),
        isTrue,
      );

      now = _now.add(farmlyOfflineSessionLeaseDuration);
      await container
          .read(farmlyAuthSessionProvider.notifier)
          .refreshFromServer();

      final state = container.read(farmlyAuthSessionProvider);
      expect(state, isA<AsyncError<FarmlyAuthSession?>>());
      final failure = (state as AsyncError<FarmlyAuthSession?>).error;
      expect(failure, isA<FarmlyAuthFailure>());
      expect(
        (failure as FarmlyAuthFailure).code,
        FarmlyAuthFailureCode.offlineLeaseExpired,
      );
      expect(container.read(selectedOrganizationScopeProvider), isNull);
      expect(secrets.values['farmly.auth.session.v1'], isNotNull);
      expect(secrets.values['farmly.pending.test'], 'encrypted-pending-work');
    },
  );

  test(
    'a server-rejected session does not fall back to its cached lease',
    () async {
      final secrets = _MemorySecretStore();
      await _seedPersistentToken(secrets);
      await FarmlyOfflineSessionLeaseStore(
        secrets,
      ).recordAuthoritativeValidation(session: _session, validatedAt: _now);
      final container = _container(
        secrets: secrets,
        adapter: _SessionAdapter(
          (_) async =>
              _jsonResponse(<String, Object?>{'code': 'SESSION_EXPIRED'}, 401),
        ),
        clock: () => _now.add(const Duration(hours: 1)),
      );

      expect(await container.read(farmlyAuthSessionProvider.future), isNull);
      expect(secrets.values['farmly.auth.session.v1'], isNull);
      expect(secrets.values['farmly.auth.offline-session.v1'], isNull);
    },
  );

  test(
    'a held offline lease read cannot restore account A scope after account B signs in',
    () async {
      final secrets = _HeldLeaseReadSecretStore();
      await _seedPersistentToken(secrets, token: 'session-token-a');
      const scopeA = <String, Object?>{
        'version': 1,
        'organizationId': 'organization-a',
        'selectedFarmId': 'farm-a',
      };
      final leaseStore = FarmlyOfflineSessionLeaseStore(secrets);
      await leaseStore.recordAuthoritativeValidation(
        session: _session,
        validatedAt: _now,
      );
      await leaseStore.saveOrganizationScope(
        validatedAt: _now,
        snapshot: scopeA,
      );

      var sessionLookups = 0;
      final container = _container(
        secrets: secrets,
        adapter: _SessionAdapter((options) async {
          if (options.path.endsWith('/api/auth/sign-in/email')) {
            return _signInResponse('session-token-b');
          }
          final authorization = options.headers['Authorization'];
          if (authorization == 'Bearer session-token-a') {
            sessionLookups += 1;
            if (sessionLookups == 1) return _jsonResponse(_sessionJson, 200);
            throw DioException.connectionError(
              requestOptions: options,
              reason: 'offline A refresh',
              error: StateError('offline'),
            );
          }
          if (authorization == 'Bearer session-token-b') {
            return _jsonResponse(_secondSessionJson, 200);
          }
          throw StateError('Unexpected test request: ${options.path}');
        }),
        clock: () => _now.add(const Duration(hours: 1)),
      );
      await container.read(farmlyAuthSessionProvider.future);
      final controller = container.read(farmlyAuthSessionProvider.notifier);
      secrets.holdNextLeaseRead();

      final staleRefresh = controller.refreshFromServer();
      await secrets.readStarted.future.timeout(const Duration(seconds: 2));
      await controller.signIn(
        email: 'second@farmly.test',
        password: 'synthetic-password',
        keepSignedIn: true,
      );
      expect(
        container.read(farmlyAuthSessionProvider).value?.user.id,
        _secondSession.user.id,
      );
      expect(await FarmlySessionTokenStore(secrets).read(), 'session-token-b');

      secrets.releaseRead.complete();
      await staleRefresh;

      expect(
        container.read(farmlyAuthSessionProvider).value?.user.id,
        _secondSession.user.id,
      );
      expect(container.read(restoredOfflineOrganizationScopeProvider), isNull);
      final storedLease = await leaseStore.read();
      expect(storedLease?.session.user.id, _secondSession.user.id);
      expect(storedLease?.organizationScope, isNull);
    },
  );

  test(
    'initial offline build cannot publish account A after account B becomes current',
    () async {
      final secrets = _MemorySecretStore();
      await _seedPersistentToken(secrets, token: 'session-token-a');
      final leaseStore = FarmlyOfflineSessionLeaseStore(secrets);
      await leaseStore.recordAuthoritativeValidation(
        session: _session,
        validatedAt: _now,
      );
      await leaseStore.saveOrganizationScope(
        validatedAt: _now,
        snapshot: const <String, Object?>{'organizationId': 'organization-a'},
      );
      final container = _container(
        secrets: secrets,
        adapter: _SessionAdapter((options) async {
          throw DioException.connectionError(
            requestOptions: options,
            reason: 'offline initial lookup',
            error: StateError('offline'),
          );
        }),
        clock: () => _now.add(const Duration(hours: 1)),
      );

      var switched = false;
      late Future<void> replacement;
      final subscription = container.listen(
        restoredOfflineOrganizationScopeProvider,
        (_, scope) {
          if (scope == null || switched) return;
          switched = true;
          container
              .read(farmlyAuthSessionGenerationProvider.notifier)
              .advance();
          final controller = container.read(farmlyAuthSessionProvider.notifier);
          controller.state = const AsyncData(_secondSession);
          replacement = container
              .read(farmlySessionCredentialsProvider)
              .set('session-token-b', persist: true);
        },
      );
      addTearDown(subscription.close);

      final builtSession = await container.read(
        farmlyAuthSessionProvider.future,
      );
      await replacement;

      expect(switched, isTrue);
      expect(builtSession?.user.id, _secondSession.user.id);
      expect(
        container.read(farmlyAuthSessionProvider).value?.user.id,
        _secondSession.user.id,
      );
      expect(
        container.read(farmlySessionCredentialsProvider).currentToken,
        'session-token-b',
      );
    },
  );

  test(
    'queued credential clear hides the old bearer before API authorization',
    () async {
      final secrets = _HeldLeaseWriteSecretStore();
      await _seedPersistentToken(secrets, token: 'session-token-a');
      final credentials = FarmlySessionCredentials(
        FarmlySessionTokenStore(secrets),
        leaseStore: FarmlyOfflineSessionLeaseStore(secrets),
      );
      expect(await credentials.restore(), 'session-token-a');

      final pendingLeaseWrite = credentials.recordAuthoritativeValidation(
        session: _session,
        validatedAt: _now,
      );
      await secrets.writeStarted.future.timeout(const Duration(seconds: 2));

      var generation = 0;
      final adapter = _RecordingApiAdapter();
      final dio = Dio(BaseOptions(baseUrl: 'https://farmly.test/'))
        ..httpClientAdapter = adapter;
      final api = FarmlyApiClient(
        dio: dio,
        credentials: credentials,
        sessionGeneration: () => generation,
        onUnauthorized: (_, _) async {},
      );

      generation += 1;
      final cleanup = credentials.clear();
      try {
        await expectLater(
          api.get('v1/memberships'),
          throwsA(
            isA<FarmlyApiFailure>().having(
              (failure) => failure.code,
              'code',
              FarmlyApiFailureCode.unauthenticated,
            ),
          ),
        );
        expect(adapter.requests, isEmpty);
      } finally {
        if (!secrets.releaseWrite.isCompleted) secrets.releaseWrite.complete();
        await Future.wait(<Future<void>>[pendingLeaseWrite, cleanup]);
        dio.close();
      }
    },
  );

  test(
    'queued credential replacement hides the old bearer while the new token is saved',
    () async {
      final secrets = _HeldSessionWriteSecretStore();
      await _seedPersistentToken(secrets, token: 'session-token-a');
      final credentials = FarmlySessionCredentials(
        FarmlySessionTokenStore(secrets),
      );
      expect(await credentials.restore(), 'session-token-a');

      var generation = 0;
      final adapter = _RecordingApiAdapter();
      final dio = Dio(BaseOptions(baseUrl: 'https://farmly.test/'))
        ..httpClientAdapter = adapter;
      final api = FarmlyApiClient(
        dio: dio,
        credentials: credentials,
        sessionGeneration: () => generation,
        onUnauthorized: (_, _) async {},
      );

      generation += 1;
      final replacement = credentials.set('session-token-b', persist: true);
      await secrets.writeStarted.future.timeout(const Duration(seconds: 2));
      try {
        await expectLater(
          api.get('v1/memberships'),
          throwsA(
            isA<FarmlyApiFailure>().having(
              (failure) => failure.code,
              'code',
              FarmlyApiFailureCode.unauthenticated,
            ),
          ),
        );
        expect(adapter.requests, isEmpty);
      } finally {
        if (!secrets.releaseWrite.isCompleted) secrets.releaseWrite.complete();
        await replacement;
        dio.close();
      }

      expect(credentials.currentToken, 'session-token-b');
      expect(await FarmlySessionTokenStore(secrets).read(), 'session-token-b');
    },
  );

  test(
    'a late successful sign-in cannot replace the newer account session or token',
    () async {
      final secrets = _MemorySecretStore();
      final firstSignInStarted = Completer<void>();
      final releaseFirstSignIn = Completer<void>();
      final container = _container(
        secrets: secrets,
        adapter: _SessionAdapter((options) async {
          if (options.path.endsWith('/api/auth/sign-in/email')) {
            final data = options.data as Map<String, Object?>;
            if (data['email'] == 'first@farmly.test') {
              firstSignInStarted.complete();
              await releaseFirstSignIn.future;
              return _signInResponse('session-token-a');
            }
            return _signInResponse('session-token-b');
          }
          final authorization = options.headers['Authorization'];
          if (authorization == 'Bearer session-token-a') {
            return _jsonResponse(_sessionJson, 200);
          }
          if (authorization == 'Bearer session-token-b') {
            return _jsonResponse(_secondSessionJson, 200);
          }
          throw StateError('Unexpected test request: ${options.path}');
        }),
        clock: () => _now,
      );
      await container.read(farmlyAuthSessionProvider.future);
      final controller = container.read(farmlyAuthSessionProvider.notifier);

      final firstSignIn = controller.signIn(
        email: 'first@farmly.test',
        password: 'synthetic-password',
        keepSignedIn: true,
      );
      await firstSignInStarted.future.timeout(const Duration(seconds: 2));
      await controller.signIn(
        email: 'second@farmly.test',
        password: 'synthetic-password',
        keepSignedIn: true,
      );
      releaseFirstSignIn.complete();
      await firstSignIn;

      expect(
        container.read(farmlyAuthSessionProvider).value?.user.id,
        _secondSession.user.id,
      );
      expect(
        container.read(farmlySessionCredentialsProvider).currentToken,
        'session-token-b',
      );
      expect(await FarmlySessionTokenStore(secrets).read(), 'session-token-b');
      expect(
        (await FarmlyOfflineSessionLeaseStore(secrets).read())?.session.user.id,
        _secondSession.user.id,
      );
    },
  );

  test(
    'a stale initial session lookup cannot clear a newer sign-in credential',
    () async {
      final secrets = _MemorySecretStore();
      await _seedPersistentToken(secrets, token: 'session-token-a');
      final firstLookupStarted = Completer<void>();
      final releaseFirstLookup = Completer<void>();
      final container = _container(
        secrets: secrets,
        adapter: _SessionAdapter((options) async {
          if (options.path.endsWith('/api/auth/sign-in/email')) {
            return _signInResponse('session-token-b');
          }
          final authorization = options.headers['Authorization'];
          if (authorization == 'Bearer session-token-a') {
            firstLookupStarted.complete();
            await releaseFirstLookup.future;
            return _jsonResponse(<String, Object?>{'user': null}, 200);
          }
          if (authorization == 'Bearer session-token-b') {
            return _jsonResponse(_secondSessionJson, 200);
          }
          throw StateError('Unexpected test request: ${options.path}');
        }),
        clock: () => _now,
      );

      final initialBuild = container.read(farmlyAuthSessionProvider.future);
      await firstLookupStarted.future.timeout(const Duration(seconds: 2));
      final controller = container.read(farmlyAuthSessionProvider.notifier);
      await controller.signIn(
        email: 'second@farmly.test',
        password: 'synthetic-password',
        keepSignedIn: true,
      );
      releaseFirstLookup.complete();
      await initialBuild;

      expect(
        container.read(farmlyAuthSessionProvider).value?.user.id,
        _secondSession.user.id,
      );
      expect(
        container.read(farmlySessionCredentialsProvider).currentToken,
        'session-token-b',
      );
      expect(await FarmlySessionTokenStore(secrets).read(), 'session-token-b');
    },
  );
}
