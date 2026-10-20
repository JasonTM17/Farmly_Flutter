import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/auth/auth_session_controller.dart';
import '../../core/auth/farmly_auth_models.dart';
import '../../core/format/display_format.dart';
import '../../core/sync/farmly_mutation.dart';
import '../../core/sync/sync_providers.dart';
import '../../core/theme/farmly_spacing.dart';
import '../../core/theme/farmly_theme_extension.dart';
import '../../l10n/generated/app_localizations.dart';
import '../../ui/farm_card.dart';
import '../../ui/farm_scaffold.dart';
import '../../ui/pickers.dart';
import '../../ui/screen_states.dart';
import '../farm/live_farm_zones.dart';
import '../organizations/organization_repository.dart';
import '../organizations/organization_scope_controller.dart';

class FarmlyLiveHarvestScreen extends ConsumerStatefulWidget {
  const FarmlyLiveHarvestScreen({super.key});

  @override
  ConsumerState<FarmlyLiveHarvestScreen> createState() =>
      _FarmlyLiveHarvestScreenState();
}

class _FarmlyLiveHarvestScreenState
    extends ConsumerState<FarmlyLiveHarvestScreen> {
  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final collectionState = ref.watch(farmlyLiveZoneCollectionProvider);
    return collectionState.when(
      loading: () => _scaffold(
        l10n,
        body: const Center(child: CircularProgressIndicator()),
      ),
      error: (_, _) => _scaffold(
        l10n,
        body: FarmErrorView(
          onRetry: () => ref.invalidate(farmlyLiveZoneCollectionProvider),
          onSwitchScope: () => showFarmPickerSheet(context),
        ),
      ),
      data: (collection) => _buildCollection(context, l10n, collection),
    );
  }

  Widget _scaffold(AppLocalizations l10n, {required Widget body}) =>
      FarmScaffold(
        topBar: FarmTopBar(
          title: l10n.harvestTab,
          actions: [
            IconButton(
              tooltip: l10n.changeFarm,
              icon: const Icon(Icons.swap_horiz_outlined),
              onPressed: () => showFarmPickerSheet(context),
            ),
          ],
        ),
        body: body,
      );

  Widget _buildCollection(
    BuildContext context,
    AppLocalizations l10n,
    FarmlyLiveZoneCollection collection,
  ) {
    final selectedScope = ref.watch(selectedOrganizationScopeProvider);
    final session = ref.watch(farmlyAuthSessionProvider).value;
    final currentMutationScope = ref.watch(farmlySyncScopeProvider).value;
    final farm = selectedScope?.selectedFarm;
    final subtitle = collection.organizationName.isEmpty
        ? collection.farmName
        : '${collection.organizationName} · ${collection.farmName}';

    if (collection.cacheState == FarmlyZoneCacheState.noFarm || farm == null) {
      return _scaffold(
        l10n,
        body: _notice(
          context,
          title: l10n.noSelectedFarm,
          message: l10n.liveFarmNoFarmBody,
        ),
      );
    }
    if (collection.cacheState == FarmlyZoneCacheState.notBootstrapped) {
      return _scaffold(
        l10n,
        body: _notice(
          context,
          title: l10n.liveFarmNoCacheTitle,
          message: l10n.liveFarmNoCacheBody,
          onRetry: _retry,
        ),
      );
    }
    if (collection.cacheState == FarmlyZoneCacheState.stale) {
      return _scaffold(
        l10n,
        body: _notice(
          context,
          title: l10n.liveFarmStaleTitle,
          message: l10n.liveFarmStaleBody,
          onRetry: _retry,
        ),
      );
    }
    if (collection.cacheState == FarmlyZoneCacheState.scopeChanged ||
        selectedScope == null ||
        !_collectionScopeIsCurrent(
          collection: collection,
          selectedScope: selectedScope,
          session: session,
          currentMutationScope: currentMutationScope,
        )) {
      return _scaffold(
        l10n,
        body: _notice(
          context,
          title: l10n.liveFarmScopeChanged,
          message: l10n.liveFarmScopeChanged,
        ),
      );
    }
    if (collection.cacheState != FarmlyZoneCacheState.ready) {
      return _scaffold(
        l10n,
        body: _notice(
          context,
          title: l10n.loadErrorTitle,
          message: l10n.loadErrorBody,
          onRetry: _retry,
        ),
      );
    }

    final period = _FarmWeek.fromFarmDate(collection.farmLocalDate);
    final canRecord = canRecordLiveHarvest(selectedScope, farm);
    final canManage = canManageLiveFarmZones(selectedScope, farm);
    final records = collection.harvests.toList(growable: false)
      ..sort((left, right) => right.harvestDate.compareTo(left.harvestDate));
    final confirmedTotal = period == null
        ? null
        : _sumHarvests(
            records.where(
              (harvest) =>
                  harvest.status == 'active' &&
                  harvest.syncState == FarmlyZoneSyncState.confirmed &&
                  period.contains(harvest.harvestDate),
            ),
          );
    final pendingTotal = period == null
        ? null
        : _sumHarvests(
            records.where(
              (harvest) =>
                  harvest.version == 0 &&
                  harvest.status == 'active' &&
                  _isPendingCreate(harvest.syncState) &&
                  period.contains(harvest.harvestDate),
            ),
          );

    return FarmScaffold(
      topBar: FarmTopBar(
        title: l10n.harvestTab,
        subtitle: subtitle,
        actions: [
          IconButton(
            tooltip: l10n.changeFarm,
            icon: const Icon(Icons.swap_horiz_outlined),
            onPressed: () => showFarmPickerSheet(context),
          ),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(
          FarmSpacing.lg,
          FarmSpacing.sm,
          FarmSpacing.lg,
          FarmSpacing.xxl,
        ),
        children: [
          if (!canRecord) ...[
            _readOnlyBanner(context, l10n),
            const SizedBox(height: FarmSpacing.md),
          ],
          if (period == null)
            _notice(
              context,
              title: l10n.liveHarvestPeriodUnavailable,
              message: l10n.liveHarvestPeriodUnavailable,
              compact: true,
            )
          else
            _periodCard(
              context,
              l10n,
              period: period,
              confirmedTotal: confirmedTotal!,
              pendingTotal: pendingTotal!,
            ),
          const SizedBox(height: FarmSpacing.md),
          if (canRecord) ...[
            FilledButton.icon(
              key: const ValueKey('live-harvest-add'),
              onPressed: () => _openCreatePicker(context, collection),
              icon: const Icon(Icons.add_rounded),
              label: Text(l10n.liveHarvestCreate),
            ),
            const SizedBox(height: FarmSpacing.lg),
          ],
          Text(
            l10n.liveHarvestSection,
            style: Theme.of(context).textTheme.titleMedium,
          ),
          const SizedBox(height: FarmSpacing.sm),
          if (records.isEmpty)
            FarmCard(child: Text(l10n.liveHarvestEmpty))
          else
            ...records.map(
              (harvest) => Padding(
                padding: const EdgeInsets.only(bottom: FarmSpacing.sm),
                child: _harvestRow(
                  context,
                  l10n,
                  collection,
                  harvest,
                  canRecord: canRecord,
                  canManage: canManage,
                ),
              ),
            ),
        ],
      ),
    );
  }

  bool _collectionScopeIsCurrent({
    required FarmlyLiveZoneCollection collection,
    required FarmlyOrganizationScope? selectedScope,
    required FarmlyAuthSession? session,
    required FarmlyMutationScope? currentMutationScope,
  }) {
    final farm = selectedScope?.selectedFarm;
    final captured = collection.selectedScope;
    final scope = collection.scope;
    if (selectedScope == null ||
        farm == null ||
        captured == null ||
        scope == null ||
        session == null ||
        currentMutationScope == null) {
      return false;
    }
    return currentMutationScope.kind == FarmlyMutationScopeKind.farm &&
        session.user.id == scope.accountId &&
        currentMutationScope.accountId == scope.accountId &&
        currentMutationScope.organizationId == scope.organizationId &&
        currentMutationScope.farmId == scope.farmId &&
        currentMutationScope.continuityEpoch == scope.continuityEpoch &&
        scope.organizationId == selectedScope.organization.id &&
        scope.farmId == farm.id &&
        scope.continuityEpoch == selectedScope.directory.continuityEpoch &&
        captured.organization.id == selectedScope.organization.id &&
        captured.epoch == selectedScope.epoch &&
        captured.directory.continuityEpoch ==
            selectedScope.directory.continuityEpoch &&
        captured.selectedFarm?.id == farm.id &&
        captured.organization.role == selectedScope.organization.role &&
        captured.organization.status == selectedScope.organization.status &&
        captured.selectedFarm?.grantRole == farm.grantRole &&
        farm.status == FarmlyFarmStatus.active;
  }

  Widget _notice(
    BuildContext context, {
    required String title,
    required String message,
    VoidCallback? onRetry,
    bool compact = false,
  }) => ListView(
    shrinkWrap: true,
    padding: EdgeInsets.all(compact ? 0 : FarmSpacing.lg),
    children: [
      FarmCard(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(title, style: Theme.of(context).textTheme.titleMedium),
            if (message != title) ...[
              const SizedBox(height: FarmSpacing.xs),
              Text(message),
            ],
            if (onRetry != null) ...[
              const SizedBox(height: FarmSpacing.md),
              OutlinedButton.icon(
                onPressed: onRetry,
                icon: const Icon(Icons.sync_rounded),
                label: Text(AppLocalizations.of(context).liveFarmRefreshButton),
              ),
            ],
          ],
        ),
      ),
    ],
  );

  Widget _readOnlyBanner(BuildContext context, AppLocalizations l10n) =>
      DecoratedBox(
        decoration: BoxDecoration(
          color: Theme.of(context).colorScheme.surfaceContainerHighest,
          borderRadius: BorderRadius.circular(FarmSpacing.inputRadius),
        ),
        child: Padding(
          padding: const EdgeInsets.all(FarmSpacing.md),
          child: Text(l10n.liveFarmReadOnlyBody),
        ),
      );

  Widget _periodCard(
    BuildContext context,
    AppLocalizations l10n, {
    required _FarmWeek period,
    required BigInt confirmedTotal,
    required BigInt pendingTotal,
  }) {
    final materialLocalizations = MaterialLocalizations.of(context);
    final start = materialLocalizations.formatMediumDate(period.startDate);
    final end = materialLocalizations.formatMediumDate(period.endDate);
    return FarmCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            l10n.thisWeekLabel,
            style: Theme.of(context).textTheme.titleSmall,
          ),
          const SizedBox(height: FarmSpacing.xs),
          Text('$start – $end', style: Theme.of(context).textTheme.bodySmall),
          const SizedBox(height: FarmSpacing.md),
          Text(
            '${formatDisplayDecimal(_formatScaled(confirmedTotal), l10n.localeName)} kg',
            key: const ValueKey('live-harvest-confirmed-total'),
            style: Theme.of(context).textTheme.headlineMedium,
          ),
          const SizedBox(height: FarmSpacing.sm),
          Row(
            children: [
              Icon(
                Icons.cloud_upload_outlined,
                size: 18,
                color: FarmThemeExtension.of(context).semanticWarning,
              ),
              const SizedBox(width: FarmSpacing.xs),
              Expanded(child: Text(l10n.pendingSyncChip)),
              Text(
                '${formatDisplayDecimal(_formatScaled(pendingTotal), l10n.localeName)} kg',
                key: const ValueKey('live-harvest-pending-total'),
                style: Theme.of(context).textTheme.titleMedium,
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _harvestRow(
    BuildContext context,
    AppLocalizations l10n,
    FarmlyLiveZoneCollection collection,
    FarmlyLiveHarvest harvest, {
    required bool canRecord,
    required bool canManage,
  }) {
    final planting = collection.plantings
        .where((row) => row.planting.id == harvest.plantingId)
        .firstOrNull;
    final zone = planting == null
        ? null
        : collection.zones
              .where((row) => row.zone.id == planting.planting.plotId)
              .firstOrNull;
    final species = planting == null
        ? null
        : collection.cropSpecies
              .where((row) => row.species.id == planting.planting.cropSpeciesId)
              .firstOrNull;
    final date = _displayCivilDate(context, harvest.harvestDate);
    final quantity = formatDisplayDecimal(
      harvest.quantityKg.value,
      l10n.localeName,
    );
    final status = harvest.status == 'voided'
        ? l10n.liveHarvestVoided
        : _syncLabel(
            l10n,
            harvest.pendingManagerMutationState ?? harvest.syncState,
          );
    final semanticLabel = l10n.liveHarvestOpenSemantics(quantity, date, status);

    return Semantics(
      key: ValueKey('live-harvest-row-${harvest.id}'),
      container: true,
      button: true,
      label: semanticLabel,
      onTap: () => _openHarvestDetails(
        context,
        collection,
        harvest,
        zone: zone,
        canRecord: canRecord,
        canManage: canManage,
      ),
      child: ExcludeSemantics(
        child: FarmCard(
          child: InkWell(
            borderRadius: BorderRadius.circular(FarmSpacing.inputRadius),
            onTap: () => _openHarvestDetails(
              context,
              collection,
              harvest,
              zone: zone,
              canRecord: canRecord,
              canManage: canManage,
            ),
            child: ConstrainedBox(
              constraints: const BoxConstraints(minHeight: 72),
              child: Padding(
                padding: const EdgeInsets.symmetric(vertical: FarmSpacing.xs),
                child: Row(
                  children: [
                    CircleAvatar(
                      backgroundColor: Theme.of(
                        context,
                      ).colorScheme.secondaryContainer,
                      child: const Icon(Icons.eco_outlined),
                    ),
                    const SizedBox(width: FarmSpacing.md),
                    Expanded(
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            species?.species.name ?? l10n.harvestTab,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: Theme.of(context).textTheme.titleSmall,
                          ),
                          const SizedBox(height: 2),
                          Text(
                            '${zone?.zone.name ?? ''} · $date',
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                            style: Theme.of(context).textTheme.bodySmall,
                          ),
                          const SizedBox(height: FarmSpacing.xs),
                          Align(
                            alignment: Alignment.centerLeft,
                            child: _StatusChip(label: status),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(width: FarmSpacing.sm),
                    Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      crossAxisAlignment: CrossAxisAlignment.end,
                      children: [
                        Text(
                          '$quantity kg',
                          style: Theme.of(context).textTheme.titleMedium,
                        ),
                        const Icon(Icons.chevron_right_rounded, size: 20),
                      ],
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  Future<void> _openCreatePicker(
    BuildContext context,
    FarmlyLiveZoneCollection collection,
  ) async {
    final scope = collection.selectedScope;
    final farm = scope?.selectedFarm;
    if (scope == null || farm == null || !canRecordLiveHarvest(scope, farm)) {
      return;
    }
    final candidates = _eligiblePlantings(collection);
    if (candidates.isEmpty) {
      showFarmToast(context, AppLocalizations.of(context).harvestNoCropsBody);
      return;
    }
    final selectedId = await showModalBottomSheet<String>(
      context: context,
      useSafeArea: true,
      builder: (sheetContext) => _PlantingPicker(
        key: const ValueKey('live-harvest-planting-picker'),
        collection: collection,
        plantings: candidates,
        onSelect: (planting) =>
            Navigator.of(sheetContext).pop(planting.planting.id),
      ),
    );
    if (!context.mounted || selectedId == null) return;
    final planting = candidates
        .where((candidate) => candidate.planting.id == selectedId)
        .firstOrNull;
    if (planting == null) return;
    final zone = collection.zones
        .where((row) => row.zone.id == planting.planting.plotId)
        .firstOrNull;
    if (zone == null) return;
    await showLiveHarvestCreateForm(
      context: context,
      ref: ref,
      collection: collection,
      zone: zone,
      planting: planting,
    );
  }

  List<FarmlyLivePlanting> _eligiblePlantings(
    FarmlyLiveZoneCollection collection,
  ) {
    final counts = <String, int>{};
    for (final planting in collection.plantings) {
      counts.update(
        planting.planting.id,
        (count) => count + 1,
        ifAbsent: () => 1,
      );
    }
    final zones = {
      for (final row in collection.zones)
        if (row.zone.type == 'crop_plot' &&
            row.zone.status == 'active' &&
            row.syncState != FarmlyZoneSyncState.needsAttention)
          row.zone.id: row,
    };
    final species = {
      for (final row in collection.cropSpecies)
        if (row.species.status == 'active' &&
            row.syncState != FarmlyZoneSyncState.needsAttention)
          row.species.id: row,
    };
    return collection.plantings
        .where(
          (row) =>
              counts[row.planting.id] == 1 &&
              row.isUniqueConfirmedRecord &&
              row.planting.status == 'active' &&
              row.syncState != FarmlyZoneSyncState.needsAttention &&
              zones.containsKey(row.planting.plotId) &&
              species.containsKey(row.planting.cropSpeciesId),
        )
        .toList(growable: false);
  }

  Future<void> _openHarvestDetails(
    BuildContext context,
    FarmlyLiveZoneCollection collection,
    FarmlyLiveHarvest harvest, {
    required FarmlyLiveZone? zone,
    required bool canRecord,
    required bool canManage,
  }) async {
    if ((canRecord || canManage) && zone != null) {
      await showLiveHarvestActions(
        context: context,
        ref: ref,
        collection: collection,
        zone: zone,
        harvest: harvest,
        canPropose: canRecord,
        canManage: canManage,
      );
      return;
    }
    await showModalBottomSheet<void>(
      context: context,
      useSafeArea: true,
      builder: (sheetContext) =>
          _HarvestReadOnlyDetails(collection: collection, harvest: harvest),
    );
  }

  String _displayCivilDate(BuildContext context, String raw) {
    final parsed = _parseCivilDate(raw);
    if (parsed == null) return raw;
    return MaterialLocalizations.of(context).formatMediumDate(parsed);
  }

  String _syncLabel(AppLocalizations l10n, FarmlyZoneSyncState state) =>
      switch (state) {
        FarmlyZoneSyncState.confirmed => l10n.syncSynced,
        FarmlyZoneSyncState.savedOnDevice => l10n.pendingSyncChip,
        FarmlyZoneSyncState.checkingServer => l10n.syncCheckingServerResult,
        FarmlyZoneSyncState.awaitingProjection =>
          l10n.liveFarmAwaitingProjection,
        FarmlyZoneSyncState.needsAttention => l10n.syncRejectedNeedsReview,
      };

  void _retry() => ref.invalidate(farmlyLiveZoneCollectionProvider);
}

class _PlantingPicker extends StatelessWidget {
  const _PlantingPicker({
    super.key,
    required this.collection,
    required this.plantings,
    required this.onSelect,
  });

  final FarmlyLiveZoneCollection collection;
  final List<FarmlyLivePlanting> plantings;
  final ValueChanged<FarmlyLivePlanting> onSelect;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    return Material(
      child: SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(
            FarmSpacing.lg,
            FarmSpacing.md,
            FarmSpacing.lg,
            FarmSpacing.lg,
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(
                l10n.liveHarvestChoosePlanting,
                style: Theme.of(context).textTheme.titleLarge,
              ),
              const SizedBox(height: FarmSpacing.sm),
              ...plantings.map((planting) {
                final species = collection.cropSpecies
                    .where(
                      (row) =>
                          row.species.id == planting.planting.cropSpeciesId,
                    )
                    .firstOrNull;
                final zone = collection.zones
                    .where((row) => row.zone.id == planting.planting.plotId)
                    .firstOrNull;
                return ListTile(
                  minVerticalPadding: FarmSpacing.sm,
                  leading: const Icon(Icons.eco_outlined),
                  title: Text(species?.species.name ?? l10n.harvestTab),
                  subtitle: zone == null ? null : Text(zone.zone.name),
                  trailing: const Icon(Icons.chevron_right_rounded),
                  onTap: () => onSelect(planting),
                );
              }),
            ],
          ),
        ),
      ),
    );
  }
}

class _HarvestReadOnlyDetails extends StatelessWidget {
  const _HarvestReadOnlyDetails({
    required this.collection,
    required this.harvest,
  });

  final FarmlyLiveZoneCollection collection;
  final FarmlyLiveHarvest harvest;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final planting = collection.plantings
        .where((row) => row.planting.id == harvest.plantingId)
        .firstOrNull;
    final species = planting == null
        ? null
        : collection.cropSpecies
              .where((row) => row.species.id == planting.planting.cropSpeciesId)
              .firstOrNull;
    final date = _parseCivilDate(harvest.harvestDate);
    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.all(FarmSpacing.lg),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              l10n.liveHarvestDetails,
              style: Theme.of(context).textTheme.titleLarge,
            ),
            const SizedBox(height: FarmSpacing.md),
            Text(species?.species.name ?? l10n.harvestTab),
            const SizedBox(height: FarmSpacing.xs),
            Text(
              '${formatDisplayDecimal(harvest.quantityKg.value, l10n.localeName)} kg',
              style: Theme.of(context).textTheme.headlineSmall,
            ),
            if (date != null) ...[
              const SizedBox(height: FarmSpacing.xs),
              Text(MaterialLocalizations.of(context).formatMediumDate(date)),
            ],
            const SizedBox(height: FarmSpacing.md),
            Text(
              harvest.status == 'voided'
                  ? l10n.liveHarvestVoided
                  : l10n.syncSynced,
            ),
          ],
        ),
      ),
    );
  }
}

class _StatusChip extends StatelessWidget {
  const _StatusChip({required this.label});

  final String label;

  @override
  Widget build(BuildContext context) {
    final tokens = FarmThemeExtension.of(context);
    return DecoratedBox(
      decoration: BoxDecoration(
        color: tokens.semanticWarning.withValues(alpha: 0.14),
        borderRadius: BorderRadius.circular(999),
      ),
      child: Padding(
        padding: const EdgeInsets.symmetric(
          horizontal: FarmSpacing.sm,
          vertical: 2,
        ),
        child: Text(label, style: Theme.of(context).textTheme.labelSmall),
      ),
    );
  }
}

final class _FarmWeek {
  const _FarmWeek(this.startDate, this.endDate, this.startKey, this.endKey);

  final DateTime startDate;
  final DateTime endDate;
  final String startKey;
  final String endKey;

  bool contains(String date) =>
      date.compareTo(startKey) >= 0 && date.compareTo(endKey) <= 0;

  static _FarmWeek? fromFarmDate(String? raw) {
    final date = _parseCivilDate(raw);
    if (date == null) return null;
    final start = DateTime.utc(
      date.year,
      date.month,
      date.day - date.weekday + 1,
    );
    final end = start.add(const Duration(days: 6));
    return _FarmWeek(start, end, _civilKey(start), _civilKey(end));
  }
}

DateTime? _parseCivilDate(String? raw) {
  if (raw == null || !RegExp(r'^\d{4}-\d{2}-\d{2}$').hasMatch(raw)) {
    return null;
  }
  final year = int.tryParse(raw.substring(0, 4));
  final month = int.tryParse(raw.substring(5, 7));
  final day = int.tryParse(raw.substring(8, 10));
  if (year == null || month == null || day == null) return null;
  final parsed = DateTime.utc(year, month, day);
  if (parsed.year != year || parsed.month != month || parsed.day != day) {
    return null;
  }
  return DateTime(year, month, day);
}

String _civilKey(DateTime date) =>
    '${date.year.toString().padLeft(4, "0")}-'
    '${date.month.toString().padLeft(2, "0")}-'
    '${date.day.toString().padLeft(2, "0")}';

bool _isPendingCreate(FarmlyZoneSyncState state) =>
    state == FarmlyZoneSyncState.savedOnDevice ||
    state == FarmlyZoneSyncState.checkingServer ||
    state == FarmlyZoneSyncState.awaitingProjection;

BigInt _sumHarvests(Iterable<FarmlyLiveHarvest> harvests) {
  var total = BigInt.zero;
  for (final harvest in harvests) {
    total += _scaleDecimal(harvest.quantityKg.value);
  }
  return total;
}

BigInt _scaleDecimal(String canonical) {
  final parts = canonical.split('.');
  final whole = BigInt.parse(parts.first);
  final fraction = parts.length == 1 ? '' : parts[1];
  return whole * BigInt.from(10000) +
      BigInt.parse(
        fraction.padRight(4, '0').isEmpty ? '0' : fraction.padRight(4, '0'),
      );
}

String _formatScaled(BigInt scaled) {
  final whole = scaled ~/ BigInt.from(10000);
  final fraction = (scaled % BigInt.from(10000)).toString().padLeft(4, '0');
  final trimmed = fraction.replaceFirst(RegExp(r'0+$'), '');
  return trimmed.isEmpty ? '$whole' : '$whole.$trimmed';
}
