import 'dart:async';

import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../config/app_config.dart';
import '../storage/secure_secret_store.dart';
import 'better_auth_client.dart';
import 'farmly_auth_models.dart';
import 'offline_session_lease.dart';

final farmlyAppConfigProvider = Provider<FarmlyAppConfig>(
  (ref) => FarmlyAppConfig.fromEnvironment(),
);

final farmlySecretStoreProvider = Provider<FarmlySecretStore>(
  (ref) => FlutterFarmlySecretStore(),
);

final farmlyAuthClockProvider = Provider<DateTime Function()>(
  (ref) => DateTime.now,
);

final farmlySessionCredentialsProvider = Provider<FarmlySessionCredentials>((
  ref,
) {
  final secrets = ref.watch(farmlySecretStoreProvider);
  return FarmlySessionCredentials(
    FarmlySessionTokenStore(secrets),
    leaseStore: FarmlyOfflineSessionLeaseStore(secrets),
  );
});

final betterAuthClientProvider = Provider<BetterAuthClient>((ref) {
  final config = ref.watch(farmlyAppConfigProvider);
  final dio = Dio(
    BaseOptions(
      connectTimeout: const Duration(seconds: 10),
      sendTimeout: const Duration(seconds: 10),
      receiveTimeout: const Duration(seconds: 15),
      headers: const <String, String>{'Accept': 'application/json'},
    ),
  );
  ref.onDispose(dio.close);
  return BetterAuthClient(apiBaseUrl: config.apiBaseUrl, dio: dio);
});

final farmlyAuthSessionProvider =
    AsyncNotifierProvider<FarmlyAuthSessionController, FarmlyAuthSession?>(
      FarmlyAuthSessionController.new,
      retry: (_, _) => null,
    );

final farmlyAuthSessionGenerationProvider =
    NotifierProvider<FarmlyAuthSessionGenerationController, int>(
      FarmlyAuthSessionGenerationController.new,
    );

final class FarmlyAuthSessionGenerationController extends Notifier<int> {
  @override
  int build() => 0;

  int advance() => state = state + 1;
}

/// Holds the active bearer in memory and persists it only for keep-signed-in.
/// The raw token is never part of a Riverpod UI state or model.
final class FarmlySessionCredentials {
  FarmlySessionCredentials(this._store, {this._leaseStore});

  final FarmlySessionTokenStore _store;
  final FarmlyOfflineSessionLeaseStore? _leaseStore;
  String? _token;
  bool _loaded = false;
  bool _persisted = false;
  FarmlyOfflineSessionLease? _volatileLease;
  // Prevent a slow cleanup for one session from deleting a newer login.
  Future<void> _credentialMutation = Future<void>.value();
  int _credentialRevision = 0;

  String? get currentToken => _loaded ? _token : null;

  Future<String?> restore() async {
    if (_loaded) return _token;
    final revision = _credentialRevision;
    final token = await _store.read();
    if (revision != _credentialRevision) return _token;
    _token = token;
    _persisted = _token != null;
    _loaded = true;
    return _token;
  }

  Future<void> set(String token, {required bool persist}) {
    final revision = ++_credentialRevision;
    _hideCurrentCredential();
    return _serializeCredentialMutation(() async {
      if (revision != _credentialRevision) return;
      await _leaseStore?.clear();
      if (revision != _credentialRevision) return;
      if (persist) {
        await _store.save(token);
      } else {
        await _store.clear();
      }
      if (revision != _credentialRevision) return;
      _token = token;
      _loaded = true;
      _persisted = persist;
    });
  }

  Future<FarmlyOfflineSessionLease?> restoreOfflineLease() async {
    final revision = _credentialRevision;
    await restore();
    if (revision != _credentialRevision) return null;
    if (!_persisted) return _volatileLease;
    final lease = await _leaseStore?.read();
    return revision == _credentialRevision ? lease : null;
  }

  Future<void> recordAuthoritativeValidation({
    required FarmlyAuthSession session,
    required DateTime validatedAt,
  }) {
    final revision = _credentialRevision;
    return _serializeCredentialMutation(() async {
      if (revision != _credentialRevision) return;
      final lease = FarmlyOfflineSessionLease(
        session: session,
        validatedAt: validatedAt.toUtc(),
      );
      _volatileLease = lease;
      if (_persisted) {
        await _leaseStore?.recordAuthoritativeValidation(
          session: session,
          validatedAt: validatedAt,
        );
      }
    });
  }

  Future<void> saveOrganizationScope({
    required Map<String, Object?>? snapshot,
    DateTime? validatedAt,
  }) {
    final revision = _credentialRevision;
    return _serializeCredentialMutation(() async {
      if (revision != _credentialRevision) return;
      final current = await restoreOfflineLease();
      if (current == null || revision != _credentialRevision) return;
      final updated = FarmlyOfflineSessionLease(
        session: current.session,
        validatedAt: (validatedAt ?? current.validatedAt).toUtc(),
        organizationScope: snapshot,
      );
      _volatileLease = updated;
      if (_persisted) {
        await _leaseStore?.saveOrganizationScope(
          snapshot: snapshot,
          validatedAt: validatedAt,
        );
      }
    });
  }

  Future<void> clear() {
    _credentialRevision++;
    _hideCurrentCredential();
    return _serializeCredentialMutation(() async {
      Object? error;
      try {
        await _store.clear();
      } catch (caught) {
        error = caught;
      }
      try {
        await _leaseStore?.clear();
      } catch (caught) {
        error ??= caught;
      }
      if (error != null) throw error;
    });
  }

  void _hideCurrentCredential() {
    _token = null;
    _loaded = true;
    _persisted = false;
    _volatileLease = null;
  }

  Future<T> _serializeCredentialMutation<T>(Future<T> Function() action) {
    final previous = _credentialMutation;
    final finished = Completer<void>();
    _credentialMutation = finished.future;
    return () async {
      await previous;
      try {
        return await action();
      } finally {
        finished.complete();
      }
    }();
  }
}

class FarmlyAuthSessionController extends AsyncNotifier<FarmlyAuthSession?> {
  Timer? _leaseExpiryTimer;

  @override
  Future<FarmlyAuthSession?> build() async {
    ref.onDispose(() => _leaseExpiryTimer?.cancel());
    final credentials = ref.read(farmlySessionCredentialsProvider);
    final requestGeneration = ref.read(farmlyAuthSessionGenerationProvider);
    final token = await credentials.restore();
    if (ref.read(farmlyAuthSessionGenerationProvider) != requestGeneration) {
      return state.value;
    }
    if (token == null) return null;
    if (!_isCurrentCredentialContext(credentials, token, requestGeneration)) {
      return state.value;
    }

    try {
      final session = await ref
          .read(betterAuthClientProvider)
          .getSession(token);
      if (!_isCurrentCredentialContext(credentials, token, requestGeneration)) {
        return state.value;
      }
      if (session == null) {
        _leaseExpiryTimer?.cancel();
        _leaseExpiryTimer = null;
        ref.read(farmlyAuthSessionGenerationProvider.notifier).advance();
        ref.read(restoredOfflineOrganizationScopeProvider.notifier).clear();
        await credentials.clear();
        return null;
      }
      await _recordValidation(credentials, session);
      if (!_isCurrentCredentialContext(credentials, token, requestGeneration)) {
        return state.value;
      }
      ref.read(restoredOfflineOrganizationScopeProvider.notifier).clear();
      _scheduleLeaseExpiry(ref.read(farmlyAuthClockProvider)().toUtc());
      return session;
    } on FarmlyAuthFailure catch (error) {
      if (!_isCurrentCredentialContext(credentials, token, requestGeneration)) {
        return state.value;
      }
      if (error.code != FarmlyAuthFailureCode.unavailable) rethrow;
      final offlineSession = await _restoreOfflineSession(
        credentials,
        error,
        token: token,
        generation: requestGeneration,
      );
      if (!_isCurrentCredentialContext(credentials, token, requestGeneration)) {
        return state.value;
      }
      return offlineSession ?? state.value;
    } catch (_) {
      if (!_isCurrentCredentialContext(credentials, token, requestGeneration)) {
        return state.value;
      }
      throw const FarmlyAuthFailure(FarmlyAuthFailureCode.unavailable);
    }
  }

  Future<FarmlyAuthSession?> _restoreOfflineSession(
    FarmlySessionCredentials credentials,
    FarmlyAuthFailure networkFailure, {
    required String token,
    required int generation,
  }) async {
    final lease = await credentials.restoreOfflineLease();
    if (!_isCurrentCredentialContext(credentials, token, generation)) {
      return null;
    }
    if (lease == null) throw networkFailure;
    final now = ref.read(farmlyAuthClockProvider)().toUtc();
    if (!lease.permitsOfflineAt(now)) {
      throw const FarmlyAuthFailure(FarmlyAuthFailureCode.offlineLeaseExpired);
    }
    if (!_isCurrentCredentialContext(credentials, token, generation)) {
      return null;
    }
    ref
        .read(restoredOfflineOrganizationScopeProvider.notifier)
        .restore(lease.organizationScope);
    _scheduleLeaseExpiry(lease.validatedAt);
    return lease.session;
  }

  Future<void> _recordValidation(
    FarmlySessionCredentials credentials,
    FarmlyAuthSession session,
  ) async {
    try {
      await credentials.recordAuthoritativeValidation(
        session: session,
        validatedAt: ref.read(farmlyAuthClockProvider)(),
      );
    } catch (_) {
      // Online use remains available when platform secure storage cannot save
      // an offline lease; it simply cannot be restored offline later.
    }
  }

  void _scheduleLeaseExpiry(DateTime validatedAt) {
    _leaseExpiryTimer?.cancel();
    final expiresAt = validatedAt.add(farmlyOfflineSessionLeaseDuration);
    final now = ref.read(farmlyAuthClockProvider)().toUtc();
    final delay = expiresAt.difference(now);
    _leaseExpiryTimer = Timer(
      delay.isNegative ? Duration.zero : delay,
      () => unawaited(refreshFromServer()),
    );
  }

  /// Refresh on foreground and when the offline lease reaches its deadline.
  Future<void> refreshFromServer() async {
    final credentials = ref.read(farmlySessionCredentialsProvider);
    final requestGeneration = ref.read(farmlyAuthSessionGenerationProvider);
    final token = await credentials.restore();
    if (token == null) {
      if (ref.read(farmlyAuthSessionGenerationProvider) == requestGeneration) {
        state = const AsyncData(null);
      }
      return;
    }
    if (!_isCurrentCredentialContext(credentials, token, requestGeneration)) {
      return;
    }
    try {
      final session = await ref
          .read(betterAuthClientProvider)
          .getSession(token);
      if (!_isCurrentCredentialContext(credentials, token, requestGeneration)) {
        return;
      }
      if (session == null) {
        await _invalidateAndClearIfCurrent(
          credentials: credentials,
          token: token,
          generation: requestGeneration,
        );
        return;
      }
      await _recordValidation(credentials, session);
      if (!_isCurrentCredentialContext(credentials, token, requestGeneration)) {
        return;
      }
      state = AsyncData(session);
      _scheduleLeaseExpiry(ref.read(farmlyAuthClockProvider)().toUtc());
    } on FarmlyAuthFailure catch (error, stackTrace) {
      if (!_isCurrentCredentialContext(credentials, token, requestGeneration)) {
        return;
      }
      if (error.code == FarmlyAuthFailureCode.unavailable) {
        try {
          final cached = await _restoreOfflineSession(
            credentials,
            error,
            token: token,
            generation: requestGeneration,
          );
          if (!_isCurrentCredentialContext(
            credentials,
            token,
            requestGeneration,
          )) {
            return;
          }
          if (cached == null) return;
          state = AsyncData(cached);
          return;
        } on FarmlyAuthFailure catch (leaseError, leaseStack) {
          if (!_isCurrentCredentialContext(
            credentials,
            token,
            requestGeneration,
          )) {
            return;
          }
          ref.read(restoredOfflineOrganizationScopeProvider.notifier).clear();
          state = AsyncError(leaseError, leaseStack);
          return;
        }
      }
      state = AsyncError(error, stackTrace);
    } catch (_) {
      if (!_isCurrentCredentialContext(credentials, token, requestGeneration)) {
        return;
      }
      state = const AsyncError(
        FarmlyAuthFailure(FarmlyAuthFailureCode.unavailable),
        StackTrace.empty,
      );
    }
  }

  Future<void> signIn({
    required String email,
    required String password,
    required bool keepSignedIn,
  }) async {
    final credentials = ref.read(farmlySessionCredentialsProvider);
    final startingGeneration = ref.read(farmlyAuthSessionGenerationProvider);
    String? token;
    int? attemptGeneration;
    try {
      final client = ref.read(betterAuthClientProvider);
      token = await client.signIn(
        email: email,
        password: password,
        rememberMe: keepSignedIn,
      );
      if (ref.read(farmlyAuthSessionGenerationProvider) != startingGeneration) {
        return;
      }
      invalidateForRevokedSession();
      final loginGeneration = ref.read(farmlyAuthSessionGenerationProvider);
      attemptGeneration = loginGeneration;
      await credentials.set(token, persist: keepSignedIn);
      if (!_isCurrentCredentialContext(credentials, token, loginGeneration)) {
        return;
      }
      final session = await client.getSession(token);
      if (session == null) {
        throw const FarmlyAuthFailure(FarmlyAuthFailureCode.emailNotVerified);
      }
      if (!_isCurrentCredentialContext(credentials, token, loginGeneration)) {
        return;
      }
      await _recordValidation(credentials, session);
      if (!_isCurrentCredentialContext(credentials, token, loginGeneration)) {
        return;
      }
      _scheduleLeaseExpiry(ref.read(farmlyAuthClockProvider)().toUtc());
      state = AsyncData(session);
    } on FarmlyAuthFailure {
      final isSameAttempt = attemptGeneration == null
          ? ref.read(farmlyAuthSessionGenerationProvider) == startingGeneration
          : _isCurrentCredentialContext(credentials, token, attemptGeneration);
      if (isSameAttempt) {
        invalidateForRevokedSession();
        try {
          await credentials.clear();
        } catch (_) {
          // Keep the typed authentication failure; the UI never sees storage
          // details or a raw platform exception.
        }
      }
      rethrow;
    } catch (_) {
      final isSameAttempt = attemptGeneration == null
          ? ref.read(farmlyAuthSessionGenerationProvider) == startingGeneration
          : _isCurrentCredentialContext(credentials, token, attemptGeneration);
      if (isSameAttempt) {
        invalidateForRevokedSession();
        try {
          await credentials.clear();
        } catch (_) {
          // The original failure is mapped to a generic unavailable state.
        }
      }
      throw const FarmlyAuthFailure(FarmlyAuthFailureCode.unavailable);
    }
  }

  Future<void> signUp({
    required String name,
    required String email,
    required String password,
    String? returnTo,
  }) => ref
      .read(betterAuthClientProvider)
      .signUp(name: name, email: email, password: password, returnTo: returnTo);

  Future<void> resendVerification(String email, {String? returnTo}) => ref
      .read(betterAuthClientProvider)
      .sendVerificationEmail(email, returnTo: returnTo);

  Future<void> requestPasswordReset(String email) =>
      ref.read(betterAuthClientProvider).requestPasswordReset(email);

  Future<void> resetPassword({
    required String token,
    required String newPassword,
  }) => ref
      .read(betterAuthClientProvider)
      .resetPassword(token: token, newPassword: newPassword);

  Future<void> signOut() async {
    final credentials = ref.read(farmlySessionCredentialsProvider);
    final requestGeneration = ref.read(farmlyAuthSessionGenerationProvider);
    final token = await credentials.restore();
    FarmlyAuthFailure? signOutFailure;
    if (token != null &&
        _isCurrentCredentialContext(credentials, token, requestGeneration)) {
      try {
        await ref.read(betterAuthClientProvider).signOut(token);
      } on FarmlyAuthFailure catch (error) {
        signOutFailure = error;
      } catch (_) {
        signOutFailure = const FarmlyAuthFailure(
          FarmlyAuthFailureCode.signOutUnconfirmed,
        );
      }
    }
    if (_isCurrentCredentialContext(credentials, token, requestGeneration)) {
      invalidateForRevokedSession();
      try {
        await credentials.clear();
      } catch (_) {
        signOutFailure = const FarmlyAuthFailure(
          FarmlyAuthFailureCode.signOutUnconfirmed,
        );
      }
    }
    if (signOutFailure != null) throw signOutFailure;
  }

  Future<void> handleUnauthorizedResponse({
    required String requestToken,
    required int requestGeneration,
  }) async {
    final credentials = ref.read(farmlySessionCredentialsProvider);
    await _invalidateAndClearIfCurrent(
      credentials: credentials,
      token: requestToken,
      generation: requestGeneration,
    );
  }

  Future<bool> _invalidateAndClearIfCurrent({
    required FarmlySessionCredentials credentials,
    required String token,
    required int generation,
  }) async {
    if (!_isCurrentCredentialContext(credentials, token, generation)) {
      return false;
    }
    invalidateForRevokedSession();
    await credentials.clear();
    return true;
  }

  bool _isCurrentCredentialContext(
    FarmlySessionCredentials credentials,
    String? token,
    int generation,
  ) =>
      ref.read(farmlyAuthSessionGenerationProvider) == generation &&
      credentials.currentToken == token;

  /// Publishes loss of server authority before any secure-store I/O can await.
  /// Router listeners synchronously advance the selected-scope ticket here.
  void invalidateForRevokedSession() {
    _leaseExpiryTimer?.cancel();
    _leaseExpiryTimer = null;
    ref.read(farmlyAuthSessionGenerationProvider.notifier).advance();
    state = const AsyncData(null);
    ref.read(restoredOfflineOrganizationScopeProvider.notifier).clear();
  }

  void retryRestore() => ref.invalidateSelf();
}
