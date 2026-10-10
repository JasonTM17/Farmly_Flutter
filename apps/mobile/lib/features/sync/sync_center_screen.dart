import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/sync/sync_providers.dart';
import '../../core/theme/farmly_spacing.dart';
import '../../core/theme/farmly_theme_extension.dart';
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

    return Scaffold(
      backgroundColor: Theme.of(context).scaffoldBackgroundColor,
      appBar: AppBar(title: const Text('Trung tâm đồng bộ')),
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
                  message:
                      'Không thể xem hàng đợi đồng bộ của phạm vi bạn vừa mất '
                      'quyền. Nội dung đã được cách ly an toàn.',
                  // Same "Đổi phạm vi" action as every other screen (§5).
                  onSwitchScope: () => showFarmPickerSheet(context),
                ),
                DemoLoadState.empty => const EmptyStateView(
                  title: 'Không có mục nào chờ đồng bộ',
                  message:
                      'Mọi thay đổi của bạn đã được đồng bộ. Bản ghi mới khi '
                      'offline sẽ xuất hiện ở đây.',
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
          '${org?.name ?? 'Tổ chức'} · ${farm?.name ?? 'Nông trại'}';
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
                  : _PendingCard(item: item),
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
    if (ref.watch(farmlySyncScopeProvider) == null) {
      return const SizedBox.shrink();
    }
    final tokens = FarmThemeExtension.of(context);
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
                    'Đồng bộ máy chủ',
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
              '${status?.pendingCount ?? 0} mục chờ'
              '${status != null && status.blockedCount > 0 ? ' · ${status.blockedCount} bị chặn' : ''}'
              '${status != null && status.conflictCount > 0 ? ' · ${status.conflictCount} xung đột' : ''}',
              style: Theme.of(context).textTheme.bodyMedium,
              softWrap: true,
            ),
            if (status?.lastError != null)
              Text(
                'Lỗi gần nhất: ${status!.lastError}',
                style: Theme.of(context).textTheme.bodySmall?.copyWith(
                  color: tokens.textSecondary,
                ),
                softWrap: true,
              ),
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
                label: Text(running ? 'Đang đồng bộ…' : 'Đồng bộ ngay'),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _PendingCard extends ConsumerWidget {
  const _PendingCard({required this.item});

  final DemoSyncItem item;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final tokens = FarmThemeExtension.of(context);
    final waiting = item.status == DemoSyncStatus.syncing
        ? 'Đang đồng bộ'
        : 'Chờ mạng';
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
          Text(
            '${item.updatedLabel} · lưu trên thiết bị',
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
                showFarmToast(context, 'Đã đồng bộ (mô phỏng).');
              },
              child: const Text('Đồng bộ ngay (mô phỏng)'),
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
                  '${item.operationType} · xung đột',
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
            label: 'Bản của bạn: ${item.localSummary}',
            child: Container(
              width: double.infinity,
              padding: const EdgeInsets.all(FarmSpacing.md),
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(FarmSpacing.md),
                border: Border.all(color: tokens.brandAction),
              ),
              child: Text(
                'Bản của bạn: ${item.localSummary}',
                style: Theme.of(context).textTheme.bodyMedium,
                softWrap: true,
              ),
            ),
          ),
          const SizedBox(height: FarmSpacing.sm),
          Semantics(
            container: true,
            label: 'Máy chủ hiện tại: ${item.serverSummary ?? ''}',
            child: Container(
              width: double.infinity,
              padding: const EdgeInsets.all(FarmSpacing.md),
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(FarmSpacing.md),
                border: Border.all(color: tokens.divider),
              ),
              child: Text(
                'Máy chủ: ${item.serverSummary ?? 'không có dữ liệu'}'
                '${item.baseVersion == null ? '' : ' · phiên gốc ${item.baseVersion}'}'
                '${item.asOfLabel == null ? '' : ' · ${item.asOfLabel}'}',
                style: Theme.of(context).textTheme.bodyMedium,
                softWrap: true,
              ),
            ),
          ),
          const SizedBox(height: FarmSpacing.sm),
          Text(
            'Chọn một hướng: không có tự động gộp số liệu.',
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
              child: const Text('So sánh chi tiết'),
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
                  showFarmToast(context, 'Đã giữ bản máy chủ.');
                },
                child: const Text('Giữ bản máy chủ'),
              ),
              FilledButton(
                onPressed: () {
                  ref
                      .read(demoDataProvider.notifier)
                      .resolveConflictWithReplacement(item.id);
                  showFarmToast(
                    context,
                    'Đã tạo intent thay thế — chờ đồng bộ lại.',
                  );
                },
                child: const Text('Gửi bản của bạn'),
              ),
              TextButton(
                onPressed: () {
                  ref.read(demoDataProvider.notifier).removeSyncItem(item.id);
                  showFarmToast(context, 'Đã lưu nháp trên thiết bị.');
                },
                child: const Text('Lưu nháp'),
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
