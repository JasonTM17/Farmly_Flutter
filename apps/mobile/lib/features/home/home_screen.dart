import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/auth/auth_session_controller.dart';
import '../../core/theme/farmly_spacing.dart';
import '../../core/theme/farmly_theme_extension.dart';
import '../../l10n/generated/app_localizations.dart';
import '../../ui/farm_card.dart';
import '../../ui/farm_scaffold.dart';
import '../../ui/illustrations.dart';
import '../../ui/pickers.dart';
import '../../ui/screen_states.dart';
import '../../ui/summary_cards.dart';
import '../app/app_routes.dart';
import '../demo/demo_models.dart';
import '../demo/demo_providers.dart';

const _demoAnchorAsOf = '06:30';

final homeClockProvider = Provider<DateTime Function()>((ref) => DateTime.now);

String _greetingForNow(DateTime now, String name, AppLocalizations l10n) {
  if (now.hour < 11) return l10n.greetingMorning(name);
  if (now.hour < 14) return l10n.greetingNoon(name);
  if (now.hour < 18) return l10n.greetingAfternoon(name);
  return l10n.greetingEvening(name);
}

/// Home tab: greeting / avatar / farm picker / bell, health ring, weather,
/// 2x2 stats and the Farmly AI CTA (spec 02 §5 Home row).
class HomeScreen extends ConsumerWidget {
  const HomeScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final state = ref.watch(demoDataProvider);
    final now = ref.watch(homeClockProvider)();
    final farm = farmById(state, state.selectedFarmId);
    final authSession = ref.watch(farmlyAuthSessionProvider);
    final session = authSession.hasValue ? authSession.value?.user : null;
    final l10n = AppLocalizations.of(context);
    final greeting = _greetingForNow(now, session?.name ?? '', l10n);
    final useCompactHeader =
        MediaQuery.textScalerOf(context).scale(14) / 14 >= 1.5;
    final zones = zonesOfFarm(state, farm?.id);
    final animals = animalsOfFarm(state, farm?.id);
    final harvests = harvestsOfFarm(state, farm?.id);
    final zoneIds = zones.map((zone) => zone.id).toSet();
    final farmTasks = state.tasksByZone.entries
        .where((entry) => zoneIds.contains(entry.key))
        .expand((entry) => entry.value);
    final tasksTotal = farmTasks.length;
    final tasksDone = farmTasks.where((task) => task.done).length;
    final farmIsEmpty = zones.isEmpty && animals.isEmpty && harvests.isEmpty;

    final screenState = effectiveDemoState(ref, 'home', dataEmpty: farmIsEmpty);

    return FarmScaffold(
      topBar: useCompactHeader
          ? FarmTopBar(
              title: l10n.homeTab,
              actions: [
                Semantics(
                  button: true,
                  label: l10n.changeOrganization,
                  child: IconButton(
                    tooltip: l10n.changeOrganization,
                    icon: const Icon(Icons.swap_horiz_outlined),
                    onPressed: () => context.push(AppRoutes.organizations),
                  ),
                ),
                Semantics(
                  button: true,
                  label: l10n.openNotifications,
                  child: IconButton(
                    tooltip: l10n.notificationsTitle,
                    icon: const Icon(Icons.notifications_outlined),
                    onPressed: () => showNotificationsSheet(context),
                  ),
                ),
              ],
            )
          : _HomeHeader(
              greeting: greeting,
              farmName: farm?.name ?? l10n.homeTab,
              avatarInitial: (session?.name ?? 'F').characters.first
                  .toUpperCase(),
              onAvatarTap: () => context.go(AppRoutes.profile),
              onFarmTap: () => showFarmPickerSheet(context),
              onNotifications: () => showNotificationsSheet(context),
              onChangeOrganization: () => context.push(AppRoutes.organizations),
            ),
      body: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(
              FarmSpacing.lg,
              0,
              FarmSpacing.lg,
              FarmSpacing.sm,
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                const DemoStateSwitcher(screenKey: 'home'),
                if (useCompactHeader)
                  Padding(
                    padding: const EdgeInsets.only(top: FarmSpacing.xs),
                    child: Text(
                      greeting,
                      style: Theme.of(context).textTheme.titleMedium,
                      softWrap: true,
                    ),
                  ),
              ],
            ),
          ),
          Expanded(
            child: switch (screenState) {
              DemoLoadState.loading => const _HomeSkeleton(),
              DemoLoadState.recoverableError => FarmErrorView(
                onRetry: () =>
                    ref.read(demoScreenStateProvider.notifier).reset('home'),
                onSwitchScope: () => showFarmPickerSheet(context),
              ),
              DemoLoadState.permissionDenied => PermissionDeniedView(
                message: l10n.homePermissionDeniedBody,
                onSwitchScope: () => showFarmPickerSheet(context),
              ),
              DemoLoadState.empty => EmptyStateView(
                title: l10n.homeEmptyTitle,
                message: l10n.homeEmptyBody,
                actionLabel: l10n.changeFarm,
                onAction: () => showFarmPickerSheet(context),
              ),
              DemoLoadState.offline ||
              DemoLoadState.pendingConflict ||
              DemoLoadState.success => _HomeContent(
                state: state,
                screenState: screenState,
                farmId: farm?.id,
                tasksDone: tasksDone,
                tasksTotal: tasksTotal,
              ),
            },
          ),
        ],
      ),
    );
  }
}

/// Reference home header: avatar on the left, greeting + farm picker row in
/// the middle, notifications + organization actions on the right.
class _HomeHeader extends StatelessWidget {
  const _HomeHeader({
    required this.greeting,
    required this.farmName,
    required this.avatarInitial,
    required this.onAvatarTap,
    required this.onFarmTap,
    required this.onNotifications,
    required this.onChangeOrganization,
  });

  final String greeting;
  final String farmName;
  final String avatarInitial;
  final VoidCallback onAvatarTap;
  final VoidCallback onFarmTap;
  final VoidCallback onNotifications;
  final VoidCallback onChangeOrganization;

  @override
  Widget build(BuildContext context) {
    final tokens = FarmThemeExtension.of(context);
    final l10n = AppLocalizations.of(context);
    return Padding(
      padding: const EdgeInsets.fromLTRB(
        FarmSpacing.lg,
        FarmSpacing.lg,
        FarmSpacing.lg,
        FarmSpacing.sm,
      ),
      child: Row(
        children: [
          Semantics(
            button: true,
            label: l10n.profileTab,
            child: InkWell(
              onTap: onAvatarTap,
              customBorder: const CircleBorder(),
              child: Container(
                width: FarmSpacing.minTouchTarget,
                height: FarmSpacing.minTouchTarget,
                alignment: Alignment.center,
                child: CircleAvatar(
                  radius: 20,
                  backgroundColor: tokens.brandAction,
                  child: Text(
                    avatarInitial,
                    style: Theme.of(
                      context,
                    ).textTheme.labelLarge?.copyWith(color: tokens.onAction),
                  ),
                ),
              ),
            ),
          ),
          const SizedBox(width: FarmSpacing.sm),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  greeting,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: Theme.of(context).textTheme.bodySmall?.copyWith(
                    color: tokens.textSecondary,
                  ),
                ),
                Semantics(
                  button: true,
                  label: l10n.farmPickerTitle,
                  child: InkWell(
                    onTap: onFarmTap,
                    borderRadius: BorderRadius.circular(FarmSpacing.sm),
                    child: Padding(
                      padding: const EdgeInsets.symmetric(
                        vertical: FarmSpacing.xs,
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Flexible(
                            child: Text(
                              farmName,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: Theme.of(context).textTheme.titleMedium,
                            ),
                          ),
                          Icon(
                            Icons.expand_more,
                            size: 20,
                            color: tokens.textSecondary,
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
          Semantics(
            button: true,
            label: l10n.changeOrganization,
            child: IconButton(
              tooltip: l10n.changeOrganization,
              icon: const Icon(Icons.swap_horiz_outlined),
              onPressed: onChangeOrganization,
            ),
          ),
          Semantics(
            button: true,
            label: l10n.openNotifications,
            child: IconButton(
              tooltip: l10n.notificationsTitle,
              icon: const Icon(Icons.notifications_outlined),
              onPressed: onNotifications,
            ),
          ),
        ],
      ),
    );
  }
}

class _HomeContent extends ConsumerWidget {
  const _HomeContent({
    required this.state,
    required this.screenState,
    required this.farmId,
    required this.tasksDone,
    required this.tasksTotal,
  });

  final DemoDataState state;
  final DemoLoadState screenState;
  final String? farmId;
  final int tasksDone;
  final int tasksTotal;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context);
    final zones = zonesOfFarm(state, farmId);
    final headcount = farmLivestockHeadcount(state, farmId);
    final harvests = harvestsOfFarm(state, farmId);
    final confirmedKg = harvests
        .where((record) => record.countsTowardTotals)
        .fold<double>(
          0,
          (sum, record) => sum + double.parse(record.quantityKg),
        );
    final pendingKg = harvests
        .where((record) => record.status == DemoHarvestStatus.localPending)
        .fold<double>(
          0,
          (sum, record) => sum + double.parse(record.quantityKg),
        );
    final conflicts = state.syncItems
        .where(
          (item) =>
              item.farmId == farmId && item.status == DemoSyncStatus.conflict,
        )
        .length;

    return ListView(
      padding: const EdgeInsets.fromLTRB(
        FarmSpacing.lg,
        0,
        FarmSpacing.lg,
        FarmSpacing.xxl,
      ),
      children: [
        FarmCard(
          semanticsLabel: l10n.sampleDataNotice,
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Icon(
                Icons.info_outline,
                color: FarmThemeExtension.of(context).textSecondary,
              ),
              const SizedBox(width: FarmSpacing.sm),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      l10n.sampleDataLabel,
                      style: Theme.of(context).textTheme.titleSmall,
                    ),
                    const SizedBox(height: FarmSpacing.xs),
                    Text(
                      l10n.sampleDataNotice,
                      style: Theme.of(context).textTheme.bodySmall,
                      softWrap: true,
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: FarmSpacing.md),
        if (screenState == DemoLoadState.offline) ...[
          const OfflineBanner(asOf: _demoAnchorAsOf),
          const SizedBox(height: FarmSpacing.md),
        ],
        if (screenState == DemoLoadState.pendingConflict) ...[
          PendingConflictBanner(
            count: conflicts,
            onOpen: () => context.push(AppRoutes.syncCenter),
          ),
          const SizedBox(height: FarmSpacing.md),
        ],
        // Illustrated farm banner above the summary row (reference home).
        const SizedBox(
          height: 150,
          child: ExcludeSemantics(
            child: ClipRRect(
              borderRadius: BorderRadius.all(
                Radius.circular(FarmSpacing.cardRadius),
              ),
              child: CustomPaint(
                painter: FarmScenePainter(),
                size: Size.infinite,
              ),
            ),
          ),
        ),
        const SizedBox(height: FarmSpacing.md),
        // Health + weather sit side by side, like the reference home.
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(
              child: OperationsHealthRing(value: operationsHealthOf(state)),
            ),
            const SizedBox(width: FarmSpacing.md),
            // D-15: render only a real cached snapshot — when the provider
            // has never produced one for this farm the card says so instead
            // of inventing a sunny reading.
            Expanded(
              child: _WeatherSection(
                snapshot: weatherOfFarm(state, farmId),
                offline: screenState == DemoLoadState.offline,
              ),
            ),
          ],
        ),
        const SizedBox(height: FarmSpacing.lg),
        Text(
          l10n.quickStats,
          style: Theme.of(context).textTheme.titleMedium,
        ),
        const SizedBox(height: FarmSpacing.sm),
        // Static 2x2 stat rows: the home tab must expose a single scroll
        // surface, and a shrink-wrapped GridView nested in this ListView
        // would add a second Scrollable node to the tree.
        Column(
          children: [
            Row(
              children: [
                Expanded(
                  child: StatTile(
                    label: l10n.todayTasks,
                    value: '$tasksDone/$tasksTotal',
                    icon: Icons.fact_check_outlined,
                    semanticValue: l10n.tasksDoneSemantics(
                      tasksDone,
                      tasksTotal,
                    ),
                  ),
                ),
                const SizedBox(width: FarmSpacing.md),
                Expanded(
                  child: StatTile(
                    label: l10n.livestock,
                    value: '$headcount',
                    unitLabel: l10n.animalUnit,
                    icon: Icons.pets_outlined,
                  ),
                ),
              ],
            ),
            const SizedBox(height: FarmSpacing.md),
            Row(
              children: [
                Expanded(
                  child: StatTile(
                    label: l10n.zones,
                    value: '${zones.length}',
                    unitLabel: l10n.zoneUnit,
                    icon: Icons.landscape_outlined,
                  ),
                ),
                const SizedBox(width: FarmSpacing.md),
                Expanded(
                  child: StatTile(
                    label: l10n.currentHarvest,
                    value: confirmedKg.toStringAsFixed(1),
                    unitLabel: 'kg',
                    icon: Icons.eco_outlined,
                    semanticValue:
                        l10n.harvestValueSemantics(
                          confirmedKg.toStringAsFixed(1),
                        ) +
                        (pendingKg > 0
                            ? l10n.pendingHarvestAmount(
                                pendingKg.toStringAsFixed(1),
                              )
                            : ''),
                  ),
                ),
              ],
            ),
          ],
        ),
        const SizedBox(height: FarmSpacing.md),
        Semantics(
          button: true,
          label: l10n.askFarmlyAiSemantics,
          child: FilledButton.icon(
            onPressed: () => context.push(AppRoutes.chat),
            icon: const Icon(Icons.forum_outlined),
            label: Text(l10n.askFarmlyAi),
          ),
        ),
      ],
    );
  }
}

class _HomeSkeleton extends StatelessWidget {
  const _HomeSkeleton();

  @override
  Widget build(BuildContext context) {
    return ListView(
      padding: const EdgeInsets.fromLTRB(
        FarmSpacing.lg,
        0,
        FarmSpacing.lg,
        FarmSpacing.xxl,
      ),
      children: [
        const FarmCard(
          child: Row(
            children: [
              SkeletonSurface(width: 108, height: 108, radius: 54),
              SizedBox(width: FarmSpacing.lg),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    SkeletonSurface(width: 120, height: 18),
                    SizedBox(height: FarmSpacing.sm),
                    SkeletonSurface(width: 160, height: 14),
                  ],
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: FarmSpacing.md),
        const FarmCard(
          child: Column(
            children: [
              Row(
                children: [
                  SkeletonSurface(width: 40, height: 40, radius: 20),
                  SizedBox(width: FarmSpacing.lg),
                  SkeletonSurface(width: 90, height: 24),
                  Spacer(),
                  SkeletonSurface(width: 60, height: 14),
                ],
              ),
              SizedBox(height: FarmSpacing.sm),
              SkeletonSurface(width: double.infinity, height: 12),
            ],
          ),
        ),
        const SizedBox(height: FarmSpacing.md),
        GridView.count(
          crossAxisCount: 2,
          shrinkWrap: true,
          physics: const NeverScrollableScrollPhysics(),
          mainAxisSpacing: FarmSpacing.md,
          crossAxisSpacing: FarmSpacing.md,
          childAspectRatio: 1.5,
          children: const [
            SkeletonSurface(width: double.infinity, height: double.infinity),
            SkeletonSurface(width: double.infinity, height: double.infinity),
            SkeletonSurface(width: double.infinity, height: double.infinity),
            SkeletonSurface(width: double.infinity, height: double.infinity),
          ],
        ),
      ],
    );
  }
}

/// Weather section (phase 07 step 4, D-15): renders the cached provider
/// snapshot with its fetch provenance; `stale` marks an expired snapshot and
/// a missing snapshot renders an explicit unavailable card — never a
/// fabricated sunny reading.
class _WeatherSection extends StatelessWidget {
  const _WeatherSection({required this.snapshot, required this.offline});

  final DemoWeatherSnapshot? snapshot;
  final bool offline;

  @override
  Widget build(BuildContext context) {
    final tokens = FarmThemeExtension.of(context);
    final snap = snapshot;
    final stale =
        snap == null ||
        snap.status == DemoWeatherStatus.stale ||
        snap.status == DemoWeatherStatus.unavailable ||
        offline;
    if (snap == null || snap.status == DemoWeatherStatus.unavailable) {
      return Semantics(
        container: true,
        label: 'Không có dữ liệu thời tiết cho nông trại này',
        child: FarmCard(
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Icon(
                Icons.cloud_off_outlined,
                size: 32,
                color: tokens.textSecondary,
              ),
              const SizedBox(width: FarmSpacing.md),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Chưa có dữ liệu thời tiết',
                      style: Theme.of(context).textTheme.titleSmall,
                    ),
                    const SizedBox(height: FarmSpacing.xs),
                    Text(
                      'Nguồn thời tiết chưa có số đo cho nông trại này — '
                      'không hiển thị giá trị suy đoán.',
                      style: Theme.of(context).textTheme.bodySmall?.copyWith(
                        color: tokens.textSecondary,
                      ),
                      softWrap: true,
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      );
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        WeatherCard(
          temperatureC: double.tryParse(snap.temperatureC)?.round() ?? 0,
          conditionLabel: snap.conditionLabel,
          humidityPercent: double.tryParse(snap.humidityPercent)?.round() ?? 0,
          windLabel: snap.windLabel,
          asOf: snap.fetchedAt,
          offline: stale,
        ),
        Padding(
          padding: const EdgeInsets.only(
            left: FarmSpacing.sm,
            top: FarmSpacing.xs,
          ),
          child: Text(
            'Nguồn: ${snap.provider} · cập nhật ${snap.fetchedAt}'
            '${stale ? ' · dữ liệu cũ' : ''}',
            style: Theme.of(
              context,
            ).textTheme.labelSmall?.copyWith(color: tokens.textSecondary),
            softWrap: true,
          ),
        ),
      ],
    );
  }
}
