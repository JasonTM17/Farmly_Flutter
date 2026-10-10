import 'dart:convert';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../storage/secure_secret_store.dart';
import 'farmly_auth_models.dart';

const farmlyOfflineSessionLeaseDuration = Duration(days: 7);

final restoredOfflineOrganizationScopeProvider =
    NotifierProvider<
      RestoredOfflineOrganizationScopeController,
      Map<String, Object?>?
    >(RestoredOfflineOrganizationScopeController.new);

final class RestoredOfflineOrganizationScopeController
    extends Notifier<Map<String, Object?>?> {
  @override
  Map<String, Object?>? build() => null;

  void restore(Map<String, Object?>? snapshot) {
    state = snapshot == null
        ? null
        : Map<String, Object?>.unmodifiable(snapshot);
  }

  void clear() => state = null;
}

final class FarmlyOfflineSessionLease {
  const FarmlyOfflineSessionLease({
    required this.session,
    required this.validatedAt,
    this.organizationScope,
  });

  final FarmlyAuthSession session;
  final DateTime validatedAt;
  final Map<String, Object?>? organizationScope;

  bool permitsOfflineAt(DateTime now) {
    final current = now.toUtc();
    final expiry = validatedAt.toUtc().add(farmlyOfflineSessionLeaseDuration);
    return !current.isBefore(validatedAt.toUtc()) && current.isBefore(expiry);
  }
}

/// Keeps only the last server-validated identity and selected scope in secure
/// storage. Domain cache and pending mutation data remain in their own stores.
final class FarmlyOfflineSessionLeaseStore {
  FarmlyOfflineSessionLeaseStore(this._secrets);

  static const storageKey = 'farmly.auth.offline-session.v1';

  final FarmlySecretStore _secrets;

  Future<FarmlyOfflineSessionLease?> read() async {
    final raw = await _secrets.read(storageKey);
    if (raw == null) return null;
    try {
      final decoded = jsonDecode(raw);
      if (decoded is! Map || decoded['version'] != 1) return null;
      final validatedAt = decoded['validatedAt'];
      final session = _readSession(decoded['session']);
      if (validatedAt is! String || session == null) return null;
      final instant = DateTime.tryParse(validatedAt);
      if (instant == null || !instant.isUtc) return null;
      final scope = _readScope(decoded['organizationScope']);
      return FarmlyOfflineSessionLease(
        session: session,
        validatedAt: instant,
        organizationScope: scope,
      );
    } on FormatException {
      return null;
    } on TypeError {
      return null;
    }
  }

  Future<void> recordAuthoritativeValidation({
    required FarmlyAuthSession session,
    required DateTime validatedAt,
  }) async {
    final previous = await read();
    final scope = previous?.session.user.id == session.user.id
        ? previous?.organizationScope
        : null;
    await _write(
      session: session,
      validatedAt: validatedAt,
      organizationScope: scope,
    );
  }

  Future<void> saveOrganizationScope({
    required Map<String, Object?>? snapshot,
    DateTime? validatedAt,
  }) async {
    final current = await read();
    if (current == null) return;
    await _write(
      session: current.session,
      validatedAt: validatedAt ?? current.validatedAt,
      organizationScope: snapshot,
    );
  }

  Future<void> clear() => _secrets.delete(storageKey);

  Future<void> _write({
    required FarmlyAuthSession session,
    required DateTime validatedAt,
    required Map<String, Object?>? organizationScope,
  }) => _secrets.write(
    storageKey,
    jsonEncode(<String, Object?>{
      'version': 1,
      'validatedAt': validatedAt.toUtc().toIso8601String(),
      'session': <String, Object?>{
        'user': <String, Object?>{
          'id': session.user.id,
          'name': session.user.name,
          'email': session.user.email,
        },
      },
      'organizationScope': organizationScope,
    }),
  );

  static FarmlyAuthSession? _readSession(Object? value) {
    if (value is! Map) return null;
    final user = value['user'];
    if (user is! Map) return null;
    final id = user['id'];
    final name = user['name'];
    final email = user['email'];
    if ([id, name, email].any((part) => part is! String || part.isEmpty)) {
      return null;
    }
    return FarmlyAuthSession(
      user: FarmlyAuthUser(
        id: id as String,
        name: name as String,
        email: email as String,
      ),
    );
  }

  static Map<String, Object?>? _readScope(Object? value) {
    if (value == null) return null;
    if (value is! Map || value.keys.any((key) => key is! String)) return null;
    return Map<String, Object?>.from(value);
  }
}
