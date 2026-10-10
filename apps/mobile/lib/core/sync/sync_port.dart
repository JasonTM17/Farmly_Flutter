import 'dart:async';

import 'farmly_mutation.dart';

typedef LocalSyncWork<T> =
    FutureOr<T> Function(LocalSyncTransaction transaction);

/// Atomic local boundary for optimistic data and its immutable outbox intent.
abstract interface class SyncPort {
  Future<T> transactLocal<T>(LocalSyncWork<T> work);
}

abstract interface class LocalSyncTransaction {
  Future<void> enqueue(FarmlyScopedMutation mutation);
}
