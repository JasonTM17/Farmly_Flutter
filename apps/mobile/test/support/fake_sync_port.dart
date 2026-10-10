import 'dart:async';
import 'dart:convert';

import 'package:farmly_mobile/core/sync/farmly_mutation.dart';
import 'package:farmly_mobile/core/sync/sync_port.dart';

final class FakeSyncPort implements SyncPort {
  Map<String, FarmlyScopedMutation> _pending = {};
  Future<void> _lastTransaction = Future<void>.value();

  List<FarmlyScopedMutation> get pending => List.unmodifiable(_pending.values);

  @override
  Future<T> transactLocal<T>(LocalSyncWork<T> work) async {
    final previous = _lastTransaction;
    final finished = Completer<void>();
    _lastTransaction = finished.future;
    await previous;

    final staged = Map<String, FarmlyScopedMutation>.of(_pending);
    final transaction = _FakeLocalSyncTransaction(staged);
    try {
      final result = await work(transaction);
      _pending = Map<String, FarmlyScopedMutation>.of(staged);
      return result;
    } finally {
      transaction.close();
      finished.complete();
    }
  }
}

final class _FakeLocalSyncTransaction implements LocalSyncTransaction {
  _FakeLocalSyncTransaction(this._staged);

  final Map<String, FarmlyScopedMutation> _staged;
  bool _isOpen = true;

  void close() => _isOpen = false;

  @override
  Future<void> enqueue(FarmlyScopedMutation mutation) async {
    if (!_isOpen) throw StateError('Local sync transaction is closed');
    final scope = mutation.scope;
    final key = [
      scope.accountId,
      scope.organizationId,
      mutation.intent.operationId,
    ].join('|');
    final existing = _staged[key];
    final sameScope =
        existing != null &&
        existing.scope.accountId == scope.accountId &&
        existing.scope.organizationId == scope.organizationId &&
        existing.scope.farmId == scope.farmId &&
        existing.scope.continuityEpoch == scope.continuityEpoch;
    final sameIntent =
        existing != null &&
        jsonEncode(existing.toRequestJson()) ==
            jsonEncode(mutation.toRequestJson());
    if (existing != null && (!sameScope || !sameIntent)) {
      throw StateError(
        'An operation ID cannot be reused for a different local intent',
      );
    }
    _staged[key] = mutation;
  }
}
