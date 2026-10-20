import 'dart:async';
import 'dart:math';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/auth/auth_session_controller.dart';
import '../../core/auth/offline_session_lease.dart';
import 'organization_repository.dart';

final selectedOrganizationScopeProvider =
    NotifierProvider<
      SelectedOrganizationScopeController,
      FarmlyOrganizationScope?
    >(SelectedOrganizationScopeController.new);

final class FarmlyOrganizationScope {
  const FarmlyOrganizationScope({
    required this.organization,
    required this.directory,
    required this.epoch,
    this.selectedFarmId,
  });

  final FarmlyOrganization organization;
  final FarmlyFarmDirectory directory;
  final int epoch;
  final String? selectedFarmId;

  FarmlyDirectoryFarm? get selectedFarm {
    for (final farm in directory.farms) {
      if (farm.id == selectedFarmId) return farm;
    }
    return null;
  }

  Map<String, Object?> toOfflineSnapshot() {
    final farm = selectedFarm;
    return <String, Object?>{
      'version': 1,
      'organization': organization.toJson(),
      'directory': FarmlyFarmDirectory(
        scopePolicyVersion: directory.scopePolicyVersion,
        continuityEpoch: directory.continuityEpoch,
        farms: farm == null ? const [] : <FarmlyDirectoryFarm>[farm],
      ).toJson(),
      'selectedFarmId': farm?.id,
    };
  }

  static FarmlyOrganizationScope? fromOfflineSnapshot(
    Map<String, Object?> snapshot, {
    required int epoch,
  }) {
    try {
      if (snapshot['version'] != 1) return null;
      final organization = FarmlyOrganization.fromJson(
        snapshot['organization'],
      );
      final directory = FarmlyFarmDirectory.fromJson(snapshot['directory']);
      final rawSelectedFarmId = snapshot['selectedFarmId'];
      if (rawSelectedFarmId != null && rawSelectedFarmId is! String) {
        return null;
      }
      final selectedFarmId = rawSelectedFarmId as String?;
      if (selectedFarmId != null &&
          !directory.farms.any(
            (farm) =>
                farm.id == selectedFarmId &&
                farm.status == FarmlyFarmStatus.active,
          )) {
        return null;
      }
      return FarmlyOrganizationScope(
        organization: organization,
        directory: directory,
        epoch: epoch,
        selectedFarmId: selectedFarmId,
      );
    } catch (_) {
      return null;
    }
  }
}

class SelectedOrganizationScopeController
    extends Notifier<FarmlyOrganizationScope?> {
  var _epoch = 0;
  Future<void> _pendingPersistence = Future<void>.value();

  @override
  FarmlyOrganizationScope? build() {
    final snapshot = ref.watch(restoredOfflineOrganizationScopeProvider);
    if (snapshot == null) return null;
    final restored = FarmlyOrganizationScope.fromOfflineSnapshot(
      snapshot,
      epoch: ++_epoch,
    );
    return restored;
  }

  int beginSelection() {
    final ticket = ++_epoch;
    state = null;
    ref.read(restoredOfflineOrganizationScopeProvider.notifier).clear();
    _queuePersist(null);
    return ticket;
  }

  bool isCurrent(int ticket) => ticket == _epoch;

  Future<bool> select(
    FarmlyOrganization organization,
    FarmlyFarmDirectory directory, {
    required int ticket,
  }) async {
    if (!isCurrent(ticket)) return false;
    final activeFarms = directory.farms.where(
      (farm) => farm.status == FarmlyFarmStatus.active,
    );
    final firstActiveFarm = activeFarms.isEmpty ? null : activeFarms.first;
    final selectedFarmId = firstActiveFarm?.id;
    state = FarmlyOrganizationScope(
      organization: organization,
      directory: directory,
      epoch: ticket,
      selectedFarmId: selectedFarmId,
    );
    await _queuePersist(
      state!.toOfflineSnapshot(),
      validatedAt: ref.read(farmlyAuthClockProvider)().toUtc(),
    );
    return isCurrent(ticket);
  }

  /// Install a freshly fetched, complete directory without changing the
  /// selected organization or switching farms behind the user's back.
  Future<bool> refreshDirectory(
    FarmlyFarmDirectory directory, {
    required int ticket,
  }) async {
    final current = state;
    if (current == null || !isCurrent(ticket)) return false;
    final selectedFarmId = current.selectedFarmId;
    final selectedStillAuthorized =
        selectedFarmId != null &&
        directory.farms.any(
          (farm) =>
              farm.id == selectedFarmId &&
              farm.status == FarmlyFarmStatus.active,
        );
    final next = FarmlyOrganizationScope(
      organization: current.organization,
      directory: directory,
      epoch: current.epoch,
      selectedFarmId: selectedStillAuthorized ? selectedFarmId : null,
    );
    state = next;
    await _queuePersist(
      next.toOfflineSnapshot(),
      validatedAt: ref.read(farmlyAuthClockProvider)().toUtc(),
    );
    return isCurrent(ticket);
  }

  Future<bool> selectFarm(String farmId) async {
    final current = state;
    if (current == null ||
        !current.directory.farms.any(
          (farm) => farm.id == farmId && farm.status == FarmlyFarmStatus.active,
        )) {
      return false;
    }
    final ticket = ++_epoch;
    final next = FarmlyOrganizationScope(
      organization: current.organization,
      directory: current.directory,
      epoch: ticket,
      selectedFarmId: farmId,
    );
    state = next;
    await _queuePersist(next.toOfflineSnapshot());
    return isCurrent(ticket);
  }

  void clear() {
    _epoch += 1;
    state = null;
    ref.read(restoredOfflineOrganizationScopeProvider.notifier).clear();
    unawaited(_queuePersist(null));
  }

  Future<void> _queuePersist(
    Map<String, Object?>? snapshot, {
    DateTime? validatedAt,
  }) {
    final credentials = ref.read(farmlySessionCredentialsProvider);
    _pendingPersistence = _pendingPersistence.then((_) async {
      try {
        await credentials.saveOrganizationScope(
          snapshot: snapshot,
          validatedAt: validatedAt,
        );
      } catch (_) {
        // Current online selection remains usable; offline restore fails
        // closed if the platform cannot persist this authorization snapshot.
      }
    });
    return _pendingPersistence;
  }
}

String newFarmlyOperationId() {
  final random = Random.secure();
  final bytes = List<int>.generate(16, (_) => random.nextInt(256));
  bytes[6] = (bytes[6] & 0x0f) | 0x40;
  bytes[8] = (bytes[8] & 0x3f) | 0x80;
  final hex = bytes
      .map((byte) => byte.toRadixString(16).padLeft(2, '0'))
      .join();
  return '${hex.substring(0, 8)}-${hex.substring(8, 12)}-'
      '${hex.substring(12, 16)}-${hex.substring(16, 20)}-${hex.substring(20)}';
}
