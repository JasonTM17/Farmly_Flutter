import 'package:farmly_mobile/app/farmly_app.dart';
import 'package:farmly_mobile/core/auth/auth_session_controller.dart';
import 'package:farmly_mobile/core/auth/farmly_auth_models.dart';
import 'package:farmly_mobile/core/config/app_config.dart';
import 'package:farmly_mobile/core/storage/secure_secret_store.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

final class _SignedOutController extends FarmlyAuthSessionController {
  Never _networkDisabled() =>
      throw StateError('CP04 keyboard probe disables authentication requests');

  @override
  Future<FarmlyAuthSession?> build() async => null;

  @override
  Future<void> refreshFromServer() async {}

  @override
  Future<void> signIn({
    required String email,
    required String password,
    required bool keepSignedIn,
  }) async => _networkDisabled();

  @override
  Future<void> signUp({
    required String name,
    required String email,
    required String password,
    String? returnTo,
  }) async => _networkDisabled();

  @override
  Future<void> resendVerification(String email, {String? returnTo}) async =>
      _networkDisabled();

  @override
  Future<void> requestPasswordReset(String email) async => _networkDisabled();

  @override
  Future<void> resetPassword({
    required String token,
    required String newPassword,
  }) async => _networkDisabled();

  @override
  Future<void> signOut() async => _networkDisabled();
}

final class _NoSecretStore implements FarmlySecretStore {
  Never _unexpectedAccess() =>
      throw StateError('CP04 keyboard probe must not access credentials');

  @override
  Future<String?> read(String key) async => _unexpectedAccess();

  @override
  Future<void> write(String key, String value) async => _unexpectedAccess();

  @override
  Future<void> delete(String key) async => _unexpectedAccess();
}

void main() {
  final config = FarmlyAppConfig.fromEnvironment(
    flavorOverride: 'development',
    apiBaseUrlOverride: 'http://10.0.2.2:9',
  );
  runApp(
    ProviderScope(
      overrides: [
        farmlyAppConfigProvider.overrideWithValue(config),
        farmlySecretStoreProvider.overrideWithValue(_NoSecretStore()),
        farmlyAuthSessionProvider.overrideWith(_SignedOutController.new),
      ],
      child: FarmlyApp(config: config),
    ),
  );
}
