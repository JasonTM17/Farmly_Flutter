import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/sync/sync_providers.dart';
import '../../core/theme/farmly_spacing.dart';
import '../../core/theme/farmly_theme_extension.dart';
import '../../l10n/generated/app_localizations.dart';
import '../../ui/farm_card.dart';
import '../../ui/pickers.dart';
import '../../ui/screen_states.dart';
import '../../ui/sync_components.dart';
import '../demo/demo_models.dart';
import '../demo/demo_providers.dart';

/// Sync center: pending and conflict items grouped by scope, with explicit
/// compare + resolution actions and no automatic merge (spec 02 §7).
class SyncCenterScreen extends ConsumerWidget {
  const SyncCenterScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final state = ref.watch(demoDataProvider);
    final screenState = effectiveDemoState(
      ref,
      'sync',
      dataEmpty: state.syncItems.isEmpty,
    );
    final l10n = AppLocalizations.of(context);

    return Scaffold(
      backgroundColor: Theme.of(context).scaffoldBackgroundColor,
      appBar: AppBar(title: Text(l10n.syncCenterTitle)),
      body: SafeArea(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const Padding(
              padding: EdgeInsets.fromLTRB(
                FarmSpacing.lg,
                FarmSpacing.sm,
                FarmSpacing.lg,
                FarmSpacing.sm,
              ),
              child: DemoStateSwitcher(screenKey: 'sync'),
            ),
            Expanded(
              child: switch (screenState) {
                DemoLoadState.loading => const _SyncSkeleton(),
                DemoLoadState.recoverableError => FarmErrorView(
                  onRetry: () =>
                      ref.read(demoScreenStateProvider.notifier).reset('sync'),
                ),
                DemoLoadState.permissionDenied => PermissionDeniedView(
                  message: l10n.syncQueueDeniedBody,
                  // Same "Đổi phạm vi" action as every other screen (§5).
                  onSwitchScope: () => showFarmPickerSheet(context),
                ),
                DemoLoadState.empty => EmptyStateView(
                  title: l10n.syncEmptyTitle,
                  message: l10n.syncEmptyBody,
                ),
                DemoLoadState.offline ||
                DemoLoadState.pendingConflict ||
                DemoLoadState.success => _SyncContent(state: state, offline: screenState == DemoLoadState.offline),
              },
            ),
          ],
        ),
      ),
    );
  }
}

class _SyncContent extends ConsumerWidget {
  const _SyncContent({required this.state, required this.offline});

  final DemoDataState state;
  final bool offline;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final grouped = <String, List<DemoSyncItem>>{};
    for (final item in state.syncItems) {
      final farm = farmById(state, item.farmId);
      final org = organizationById(state, farm?.organizationId);
      final scopeLabel =
          '${org?.name ?? AppLocalizations.of(context).orgFallback}'
          ' · ${farm?.name ?? AppLocalizations.of(context).farmFallback}';
      grouped.putIfAbsent(scopeLabel, () => []).add(item);
    }

    return ListView(
      padding: const EdgeInsets.fromLTRB(
        FarmSpacing.lg,
        0,
        FarmSpacing.lg,
        FarmSpacing.xxl,
      ),
      children: [
        if (offline) ...[
          const OfflineBanner(asOf: '06:30'),
          const SizedBox(height: FarmSpacing.md),
        ],
        const _LiveSyncSection(),
        for (final entry in grouped.entries) ...[
          Text(
            entry.key,
            style: Theme.of(context).textTheme.titleSmall,
            softWrap: true,
          ),
          const SizedBox(height: FarmSpacing.sm),
          for (final item in entry.value)
            Padding(
              padding: const EdgeInsets.only(bottom: FarmSpacing.md),
              child: item.status == DemoSyncStatus.conflict
                  ? _ConflictCard(item: item)
                  : _PendingCard(item: item, offline: offline),
            ),
          const SizedBox(height: FarmSpacing.md),
        ],
      ],
    );
  }
}

/// Live engine state for the signed-in scope: durable pending depth, parked
/// conflicts, and a manual sync trigger. Renders nothing without an
/// authenticated scope (demo/offline preview stays untouched below).
class _LiveSyncSection extends ConsumerWidget {
  const _LiveSyncSection();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final tokens = FarmThemeExtension.of(context);
    final l10n = AppLocalizations.of(context);
    // An invalid scope surfaces as AsyncError — the section renders a
    // translated error panel with an explicit retry instead of letting the
    // provider exception escape into the build (spec02 §5).
    return ref.watch(farmlySyncScopeProvider).when(
      data: (scope) {
        if (scope == null) return const SizedBox.shrink();
        final status = ref.watch(syncStatusProvider).value;
        final running = status?.running ?? false;

        return Padding(
          padding: const EdgeInsets.only(bottom: FarmSpacing.md),
          child: FarmCard(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Icon(Icons.sync, size: 18, color: tokens.brandAction),
                    const SizedBox(width: FarmSpacing.xs),
                    Expanded(
                      child: Text(
                        AppLocalizations.of(context).serverSyncLabel,
                        style: Theme.of(context).textTheme.labelLarge?.copyWith(
                          color: tokens.brandAction,
                        ),
                        softWrap: true,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: FarmSpacing.xs),
                Text(
                  '${AppLocalizations.of(context).pendingCountLabel(status?.pendingCount ?? 0)}'
                  '${status != null && status.blockedCount > 0 ? AppLocalizations.of(context).blockedCountSuffix(status.blockedCount) : ''}'
                  '${status != null && status.conflictCount > 0 ? AppLocalizations.of(context).conflictCountSuffix(status.conflictCount) : ''}'
                  '${status != null && status.rejectedCount > 0 ? AppLocalizations.of(context).rejectedCountSuffix(status.rejectedCount) : ''}',
                  style: Theme.of(context).textTheme.bodyMedium,
                  softWrap: true,
                ),
                if (status?.lastErrorKind != null)
                  Text(
                    _syncFailureLabel(l10n, status!.lastErrorKind!),
                    style: Theme.of(context).textTheme.bodySmall?.copyWith(
                      color: tokens.textSecondary,
                    ),
                    softWrap: true,
                  ),
                if (status != null && status.operations.isNotEmpty) ...[
                  const Divider(height: FarmSpacing.lg),
                  Text(
                    l10n.syncRecentOperationsLabel,
                    style: Theme.of(context).textTheme.labelLarge,
                  ),
                  const SizedBox(height: FarmSpacing.xs),
                  for (final operation in status.operations)
                    _LiveOutboxStatusRow(operation: operation),
                ],
                Align(
                  alignment: Alignment.centerLeft,
                  child: TextButton.icon(
                    onPressed: running
                        ? null
                        : () => ref
                            .read(syncStatusProvider.notifier)
                            .synchronize(),
                    icon: running
                        ? const SizedBox(
                            width: 14,
                            height: 14,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          )
                        : const Icon(Icons.sync, size: 16),
                    label: Text(
                      running
                          ? AppLocalizations.of(context).syncRunningLabel
                          : AppLocalizations.of(context).syncNowLabel,
                    ),
                  ),
                ),
              ],
            ),
          ),
        );
      },
      loading: () => const SizedBox.shrink(),
      error: (_, _) => Padding(
        padding: const EdgeInsets.only(bottom: FarmSpacing.md),
        child: FarmCard(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Icon(
                    Icons.sync_problem_outlined,
                    size: 18,
                    color: tokens.semanticError,
                  ),
                  const SizedBox(width: FarmSpacing.xs),
                  Expanded(
                    child: Text(
                      l10n.syncScopeErrorTitle,
                      style: Theme.of(context).textTheme.labelLarge?.copyWith(
                        color: tokens.semanticError,
                      ),
                      softWrap: true,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: FarmSpacing.xs),
              Text(
                l10n.syncScopeErrorBody,
                style: Theme.of(context).textTheme.bodyMedium,
                softWrap: true,
              ),
              Align(
                alignment: Alignment.centerLeft,
                child: TextButton.icon(
                  onPressed: () => ref.invalidate(farmlySyncScopeProvider),
                  icon: const Icon(Icons.refresh, size: 16),
                  label: Text(l10n.retry),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

String _syncFailureLabel(AppLocalizations l10n, SyncStatusFailureKind kind) =>
    switch (kind) {
      SyncStatusFailureKind.authenticationRequired =>
        l10n.syncAuthenticationRequired,
      SyncStatusFailureKind.permissionDenied => l10n.syncPermissionDenied,
      SyncStatusFailureKind.serviceUnavailable => l10n.syncServerUnavailable,
      SyncStatusFailureKind.syncConflict => l10n.syncFailureConflict,
      SyncStatusFailureKind.refreshRequired => l10n.syncRefreshRequired,
      SyncStatusFailureKind.unknown => l10n.syncUnknownFailure,
    };

class _LiveOutboxStatusRow extends StatelessWidget {
  const _LiveOutboxStatusRow({required this.operation});

  final SyncOutboxStatus operation;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final tokens = FarmThemeExtension.of(context);
    final category = switch (operation.category) {
      SyncOperationCategory.farm => l10n.syncOperationFarm,
      SyncOperationCategory.zone => l10n.syncOperationZone,
      SyncOperationCategory.crop => l10n.syncOperationCrop,
      SyncOperationCategory.livestock => l10n.syncOperationLivestock,
      SyncOperationCategory.task => l10n.syncOperationTask,
      SyncOperationCategory.harvest => l10n.syncOperationHarvest,
      SyncOperationCategory.water => l10n.syncOperationWater,
      SyncOperationCategory.general => l10n.syncOperationGeneral,
    };
    final status = switch (operation.state) {
      SyncOutboxState.synced => l10n.syncSynced,
      SyncOutboxState.savedOnDevice => l10n.syncSavedOnDeviceStatus,
      SyncOutboxState.checkingServerResult => l10n.syncCheckingServerResult,
      SyncOutboxState.outcomeUnknown => l10n.syncOutcomeUnknown,
      SyncOutboxState.dependencyMissing => l10n.syncDependencyMissing,
      SyncOutboxState.dependencyCycle => l10n.syncDependencyCycle,
      SyncOutboxState.dependencyFailed => l10n.syncDependencyFailed,
      SyncOutboxState.dependencyBlocked => l10n.syncDependencyBlocked,
      SyncOutboxState.dependencyNeedsAttention =>
        l10n.syncDependencyNeedsAttention,
      SyncOutboxState.conflictNeedsReview => l10n.syncConflictNeedsReview,
      SyncOutboxState.rejectedPermission => l10n.syncPermissionDenied,
      SyncOutboxState.rejectedValidation => l10n.syncRejectedValidation,
      SyncOutboxState.rejectedNeedsReview => l10n.syncRejectedNeedsReview,
    };
    final reference = operation.operationId.length > 8
        ? operation.operationId.substring(operation.operationId.length - 8)
        : operation.operationId;

    return Semantics(
      container: true,
      label: '$category. $status. ${l10n.syncOperationReference(reference)}',
      child: ExcludeSemantics(
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: FarmSpacing.xs),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Icon(
                _statusIcon(operation.state),
                size: 18,
                color: _statusColor(operation.state, tokens),
              ),
              const SizedBox(width: FarmSpacing.sm),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(category, style: Theme.of(context).textTheme.labelLarge),
                    Text(status, style: Theme.of(context).textTheme.bodySmall),
                    Text(
                      l10n.syncOperationReference(reference),
                      style: Theme.of(context).textTheme.bodySmall?.copyWith(
                        color: tokens.textSecondary,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  IconData _statusIcon(SyncOutboxState state) => switch (state) {
    SyncOutboxState.synced => Icons.cloud_done_outlined,
    SyncOutboxState.savedOnDevice => Icons.phone_android_outlined,
    SyncOutboxState.checkingServerResult || SyncOutboxState.outcomeUnknown =>
      Icons.sync,
    SyncOutboxState.conflictNeedsReview => Icons.compare_arrows,
    SyncOutboxState.rejectedPermission => Icons.lock_outline,
    SyncOutboxState.rejectedValidation ||
    SyncOutboxState.rejectedNeedsReview ||
    SyncOutboxState.dependencyMissing ||
    SyncOutboxState.dependencyCycle ||
    SyncOutboxState.dependencyFailed ||
    SyncOutboxState.dependencyBlocked ||
    SyncOutboxState.dependencyNeedsAttention => Icons.sync_problem_outlined,
  };

  Color _statusColor(SyncOutboxState state, FarmThemeExtension tokens) =>
      switch (state) {
        SyncOutboxState.synced || SyncOutboxState.savedOnDevice =>
          tokens.brandAction,
        SyncOutboxState.checkingServerResult ||
        SyncOutboxState.outcomeUnknown => tokens.textSecondary,
        SyncOutboxState.conflictNeedsReview => tokens.semanticWarning,
        SyncOutboxState.rejectedPermission ||
        SyncOutboxState.rejectedValidation ||
        SyncOutboxState.rejectedNeedsReview ||
        SyncOutboxState.dependencyMissing ||
        SyncOutboxState.dependencyCycle ||
        SyncOutboxState.dependencyFailed ||
        SyncOutboxState.dependencyBlocked ||
        SyncOutboxState.dependencyNeedsAttention => tokens.semanticError,
      };
}

class _PendingCard extends ConsumerWidget {
  const _PendingCard({required this.item, required this.offline});

  final DemoSyncItem item;
  final bool offline;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final tokens = FarmThemeExtension.of(context);
    final l10n = AppLocalizations.of(context);
    final waiting = switch (item.status) {
      DemoSyncStatus.syncing => l10n.syncingShort,
      DemoSyncStatus.localPending =>
        offline ? l10n.waitingNetwork : l10n.syncSavedOnDeviceStatus,
      DemoSyncStatus.conflict => l10n.conflictLabel,
    };
    return FarmCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(
                Icons.cloud_upload_outlined,
                size: 18,
                color: tokens.brandAction,
              ),
              const SizedBox(width: FarmSpacing.xs),
              Expanded(
                child: Text(
                  '${item.operationType} · $waiting',
                  style: Theme.of(context).textTheme.labelLarge?.copyWith(
                    color: tokens.brandAction,
                  ),
                  softWrap: true,
                ),
              ),
            ],
          ),
          const SizedBox(height: FarmSpacing.xs),
          Text(item.localSummary, style: Theme.of(context).textTheme.bodyMedium, softWrap: true),
          if (item.status == DemoSyncStatus.localPending && offline)
            Text(
              l10n.savedOnDeviceSuffix,
              style: Theme.of(context).textTheme.bodySmall?.copyWith(
                color: tokens.textSecondary,
              ),
              softWrap: true,
            )
          else if (item.status == DemoSyncStatus.syncing)
            Text(
              item.updatedLabel,
              style: Theme.of(context).textTheme.bodySmall?.copyWith(
                color: tokens.textSecondary,
              ),
              softWrap: true,
            ),
          Align(
            alignment: Alignment.centerLeft,
            child: TextButton(
              onPressed: () {
                ref.read(demoDataProvider.notifier).markSyncItemSynced(item.id);
                showFarmToast(
                  context,
                  AppLocalizations.of(context).syncSimulatedToast,
                );
              },
              child: Text(AppLocalizations.of(context).syncNowSimulated),
            ),
          ),
        ],
      ),
    );
  }
}

class _ConflictCard extends ConsumerWidget {
  const _ConflictCard({required this.item});

  final DemoSyncItem item;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final tokens = FarmThemeExtension.of(context);
    return FarmCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(
                Icons.sync_problem_outlined,
                size: 18,
                color: tokens.semanticWarning,
              ),
              const SizedBox(width: FarmSpacing.xs),
              Expanded(
                child: Text(
                  '${item.operationType} · ${AppLocalizations.of(context).conflictLabel}',
                  style: Theme.of(context).textTheme.labelLarge?.copyWith(
                    color: tokens.semanticWarning,
                  ),
                  softWrap: true,
                ),
              ),
            ],
          ),
          const SizedBox(height: FarmSpacing.sm),
          Semantics(
            container: true,
            label:
                '${AppLocalizations.of(context).yourVersionLabel}: ${item.localSummary}',
            child: Container(
              width: double.infinity,
              padding: const EdgeInsets.all(FarmSpacing.md),
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(FarmSpacing.md),
                border: Border.all(color: tokens.brandAction),
              ),
              child: Text(
                '${AppLocalizations.of(context).yourVersionLabel}: ${item.localSummary}',
                style: Theme.of(context).textTheme.bodyMedium,
                softWrap: true,
              ),
            ),
          ),
          const SizedBox(height: FarmSpacing.sm),
          Semantics(
            container: true,
            label:
                '${AppLocalizations.of(context).serverNowLabel}: ${item.serverSummary ?? ''}',
            child: Container(
              width: double.infinity,
              padding: const EdgeInsets.all(FarmSpacing.md),
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(FarmSpacing.md),
                border: Border.all(color: tokens.divider),
              ),
              child: Text(
                '${AppLocalizations.of(context).serverLabel}: ${item.serverSummary ?? AppLocalizations.of(context).noServerData}'
                '${item.baseVersion == null ? '' : ' · ${AppLocalizations.of(context).baseVersionPrefix} ${item.baseVersion}'}'
                '${item.asOfLabel == null ? '' : ' · ${item.asOfLabel}'}',
                style: Theme.of(context).textTheme.bodyMedium,
                softWrap: true,
              ),
            ),
          ),
          const SizedBox(height: FarmSpacing.sm),
          Text(
            AppLocalizations.of(context).chooseDirectionNote,
            style: Theme.of(context).textTheme.bodySmall?.copyWith(
              color: tokens.textSecondary,
            ),
            softWrap: true,
          ),
          const SizedBox(height: FarmSpacing.xs),
          Align(
            alignment: Alignment.centerLeft,
            child: TextButton(
              onPressed: () => showConflictCompareSheet(context, item: item),
              child: Text(AppLocalizations.of(context).compareDetailLabel),
            ),
          ),
          const SizedBox(height: FarmSpacing.xs),
          Wrap(
            spacing: FarmSpacing.sm,
            runSpacing: FarmSpacing.xs,
            children: [
              OutlinedButton(
                onPressed: () {
                  ref.read(demoDataProvider.notifier).removeSyncItem(item.id);
                  showFarmToast(
                    context,
                    AppLocalizations.of(context).keepServerToast,
                  );
                },
                child: Text(AppLocalizations.of(context).keepServerVersion),
              ),
              FilledButton(
                onPressed: () {
                  ref
                      .read(demoDataProvider.notifier)
                      .resolveConflictWithReplacement(item.id);
                  showFarmToast(
                    context,
                    AppLocalizations.of(context).replaceIntentToast,
                  );
                },
                child: Text(AppLocalizations.of(context).sendYourVersion),
              ),
              TextButton(
                onPressed: () {
                  ref.read(demoDataProvider.notifier).removeSyncItem(item.id);
                  showFarmToast(
                    context,
                    AppLocalizations.of(context).draftSavedToast,
                  );
                },
                child: Text(AppLocalizations.of(context).saveDraft),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _SyncSkeleton extends StatelessWidget {
  const _SyncSkeleton();

  @override
  Widget build(BuildContext context) {
    return ListView(
      padding: const EdgeInsets.all(FarmSpacing.lg),
      children: const [
        SkeletonSurface(width: 180, height: 18),
        SizedBox(height: FarmSpacing.sm),
        SkeletonSurface(
          width: double.infinity,
          height: 110,
          radius: FarmSpacing.cardRadius,
        ),
        SizedBox(height: FarmSpacing.md),
        SkeletonSurface(width: 180, height: 18),
        SizedBox(height: FarmSpacing.sm),
        SkeletonSurface(
          width: double.infinity,
          height: 200,
          radius: FarmSpacing.cardRadius,
        ),
      ],
    );
  }
}
