import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/format/display_format.dart';
import '../../core/auth/auth_session_controller.dart';
import '../../core/sync/farmly_mutation.dart';
import '../../core/sync/sync_providers.dart';
import '../../core/theme/farmly_spacing.dart';
import '../../core/theme/farmly_theme_extension.dart';
import '../../l10n/generated/app_localizations.dart';
import '../../ui/farm_card.dart';
import '../../ui/form_fields.dart';
import '../../ui/illustrations.dart';
import '../../ui/pickers.dart';
import '../../ui/screen_states.dart';
import '../app/app_routes.dart';
import '../demo/demo_models.dart';
import '../organizations/organization_scope_controller.dart';
import 'live_livestock.dart';
import 'live_livestock_creation_sheet.dart';
import 'live_livestock_movement_sheet.dart';
import 'live_livestock_observation_sheet.dart';

class FarmlyLiveLivestockScreen extends ConsumerWidget {
  const FarmlyLiveLivestockScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final state = ref.watch(farmlyLiveLivestockProvider);
    final farmName = state.asData?.value.farmName;
    final collection = state.asData?.value;
    final canCreateHerd =
        collection?.cacheState == FarmlyLivestockCacheState.ready &&
        collection?.canManageHerds == true;
    final l10n = AppLocalizations.of(context);
    return Scaffold(
      backgroundColor: Theme.of(context).scaffoldBackgroundColor,
      appBar: AppBar(
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(l10n.livestockScreenTitle),
            if (farmName != null && farmName.isNotEmpty)
              Text(
                farmName,
                style: Theme.of(context).textTheme.bodySmall?.copyWith(
                  color: FarmThemeExtension.of(context).textSecondary,
                ),
              ),
          ],
        ),
        actions: canCreateHerd
            ? [
                IconButton(
                  key: const ValueKey('live-herd-create'),
                  tooltip: l10n.liveHerdCreateAction,
                  onPressed: () => _openHerdCreateSheet(context, collection!),
                  icon: const Icon(Icons.add_circle_outline),
                ),
              ]
            : null,
      ),
      body: SafeArea(
        child: state.when(
          loading: () => const Center(child: CircularProgressIndicator()),
          error: (_, _) => _LivestockNotice(
            icon: Icons.sync_problem_outlined,
            title: l10n.liveFarmStaleTitle,
            body: l10n.liveFarmStaleBody,
            actionLabel: l10n.liveFarmRefreshButton,
            onAction: () => _synchronize(ref),
          ),
          data: (collection) => _collectionBody(context, ref, collection),
        ),
      ),
    );
  }

  Widget _collectionBody(
    BuildContext context,
    WidgetRef ref,
    FarmlyLiveLivestockCollection collection,
  ) {
    final l10n = AppLocalizations.of(context);
    final sync = ref.watch(syncStatusProvider).value;
    return switch (collection.cacheState) {
      FarmlyLivestockCacheState.noFarm => _LivestockNotice(
        icon: Icons.landscape_outlined,
        title: l10n.noSelectedFarm,
        body: l10n.liveFarmNoFarmBody,
        actionLabel: l10n.changeFarm,
        onAction: () => showFarmPickerSheet(context),
      ),
      FarmlyLivestockCacheState.scopeChanged => _LivestockNotice(
        icon: Icons.lock_outline,
        title: l10n.liveFarmScopeChanged,
        body: l10n.liveFarmReadOnlyBody,
        actionLabel: l10n.changeFarm,
        onAction: () => showFarmPickerSheet(context),
      ),
      FarmlyLivestockCacheState.notBootstrapped => _LivestockNotice(
        key: const ValueKey('live-livestock-no-cache'),
        icon: Icons.cloud_download_outlined,
        title: l10n.liveFarmNoCacheTitle,
        body: l10n.liveFarmNoCacheBody,
        actionLabel: l10n.liveFarmRefreshButton,
        onAction: sync?.running == true ? null : () => _synchronize(ref),
      ),
      FarmlyLivestockCacheState.stale => _LivestockNotice(
        icon: Icons.sync_problem_outlined,
        title: l10n.liveFarmStaleTitle,
        body: l10n.liveFarmStaleBody,
        actionLabel: l10n.liveFarmRefreshButton,
        onAction: sync?.running == true ? null : () => _synchronize(ref),
      ),
      FarmlyLivestockCacheState.ready =>
        collection.herds.isEmpty
            ? EmptyStateView(
                title: l10n.livestockEmptyTitle,
                message: l10n.livestockEmptyBody,
                actionLabel: collection.canManageHerds
                    ? l10n.liveHerdCreateAction
                    : l10n.changeFarm,
                onAction: collection.canManageHerds
                    ? () => _openHerdCreateSheet(context, collection)
                    : () => showFarmPickerSheet(context),
                secondaryActionLabel: collection.canManageHerds
                    ? l10n.changeFarm
                    : null,
                onSecondaryAction: collection.canManageHerds
                    ? () => showFarmPickerSheet(context)
                    : null,
              )
            : _herdList(context, ref, collection),
    };
  }

  Widget _herdList(
    BuildContext context,
    WidgetRef ref,
    FarmlyLiveLivestockCollection collection,
  ) {
    final l10n = AppLocalizations.of(context);
    final total = collection.herds.fold<int>(
      0,
      (sum, herd) => sum + herd.headcount,
    );
    final tracked = collection.herds
        .where((herd) => !herd.isBatch)
        .fold<int>(0, (sum, herd) => sum + herd.headcount);
    final batch = total - tracked;
    return ListView(
      padding: const EdgeInsets.fromLTRB(
        FarmSpacing.lg,
        FarmSpacing.sm,
        FarmSpacing.lg,
        FarmSpacing.xxl,
      ),
      children: [
        if (collection.attentionCount > 0) ...[
          FarmCard(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Icon(
                  Icons.info_outline,
                  color: FarmThemeExtension.of(context).brandAction,
                ),
                const SizedBox(height: FarmSpacing.sm),
                Text(
                  l10n.syncCenterTitle,
                  style: Theme.of(context).textTheme.titleMedium,
                ),
                const SizedBox(height: FarmSpacing.xs),
                Text(
                  l10n.liveLivestockAttentionCount(collection.attentionCount),
                  style: Theme.of(context).textTheme.bodyMedium,
                ),
                const SizedBox(height: FarmSpacing.md),
                FilledButton(
                  onPressed: () => context.push(AppRoutes.syncCenter),
                  child: Text(l10n.syncCenterTitle),
                ),
              ],
            ),
          ),
          const SizedBox(height: FarmSpacing.md),
        ],
        FarmCard(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                l10n.herdTotalLine(total),
                style: Theme.of(context).textTheme.titleMedium,
              ),
              const SizedBox(height: FarmSpacing.xs),
              Text(
                l10n.herdSplitLine(tracked, batch),
                style: Theme.of(context).textTheme.bodySmall?.copyWith(
                  color: FarmThemeExtension.of(context).textSecondary,
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: FarmSpacing.md),
        Text(
          l10n.herdGroupsTitle,
          style: Theme.of(context).textTheme.titleSmall,
        ),
        const SizedBox(height: FarmSpacing.sm),
        for (final herd in collection.herds) ...[
          _LiveHerdCard(collection: collection, herd: herd),
          const SizedBox(height: FarmSpacing.md),
        ],
      ],
    );
  }
}

class _LiveHerdCard extends StatelessWidget {
  const _LiveHerdCard({required this.collection, required this.herd});

  final FarmlyLiveLivestockCollection collection;
  final FarmlyLiveHerd herd;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final tokens = FarmThemeExtension.of(context);
    final species = herd.species ?? l10n.livestockScreenTitle;
    final mode = herd.isBatch ? l10n.herdModeBatch : l10n.herdModeTracked;
    return FarmCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Semantics(
            container: true,
            label: l10n.herdSemantics(species, mode, herd.headcount),
            child: Row(
              children: [
                Expanded(
                  child: Text(
                    '$species · $mode',
                    style: Theme.of(context).textTheme.titleSmall,
                    softWrap: true,
                  ),
                ),
                Text(
                  herd.isBatch
                      ? l10n.liveLivestockConfirmedHeadcount(herd.headcount)
                      : l10n.headcountSuffix(herd.headcount),
                  style: Theme.of(
                    context,
                  ).textTheme.titleSmall?.copyWith(color: tokens.brandAction),
                ),
              ],
            ),
          ),
          const SizedBox(height: FarmSpacing.sm),
          if (herd.syncState != FarmlyLivestockEntitySyncState.confirmed)
            Padding(
              key: ValueKey('live-herd-sync-${herd.id}'),
              padding: const EdgeInsets.only(bottom: FarmSpacing.sm),
              child: Text(
                _livestockEntitySyncLabel(l10n, herd.syncState),
                style: Theme.of(
                  context,
                ).textTheme.bodySmall?.copyWith(color: tokens.textSecondary),
              ),
            ),
          if (herd.isBatch)
            Row(
              children: [
                _SpeciesPortrait(species: herd.species),
                const SizedBox(width: FarmSpacing.lg),
                Expanded(
                  child: Text(
                    l10n.batchHerdNote(herd.headcount),
                    style: Theme.of(context).textTheme.bodySmall?.copyWith(
                      color: tokens.textSecondary,
                    ),
                  ),
                ),
              ],
            )
          else if (herd.animals.isEmpty)
            Text(
              l10n.liveLivestockTrackedHerdNoAnimals,
              style: Theme.of(
                context,
              ).textTheme.bodySmall?.copyWith(color: tokens.textSecondary),
            )
          else
            for (final animal in herd.animals) ...[
              _LiveAnimalCard(
                collection: collection,
                herd: herd,
                animal: animal,
              ),
              const SizedBox(height: FarmSpacing.sm),
            ],
          if (collection.canManageHerds &&
              !herd.isBatch &&
              herd.status == 'active') ...[
            const SizedBox(height: FarmSpacing.sm),
            _CreateLivestockEntityButton(
              key: ValueKey('live-animal-create-herd-${herd.id}'),
              label: l10n.liveAnimalCreateAction,
              onPressed: () =>
                  _openAnimalCreateSheet(context, collection, herd),
            ),
          ],
          if (herd.isBatch) ...[
            if (herd.pendingMovements.isNotEmpty) ...[
              const SizedBox(height: FarmSpacing.md),
              Text(
                l10n.liveMovementPendingBalance(
                  _signedHeadcount(herd.pendingMovementDelta),
                  herd.estimatedHeadcount,
                ),
                key: ValueKey('live-movement-pending-herd-${herd.id}'),
                style: Theme.of(
                  context,
                ).textTheme.bodySmall?.copyWith(color: tokens.textSecondary),
              ),
              const SizedBox(height: FarmSpacing.xs),
              for (final movement in herd.pendingMovements.take(3))
                _LiveMovementLine(movement: movement),
            ],
            if (herd.productionRecords.isNotEmpty) ...[
              const SizedBox(height: FarmSpacing.md),
              for (final record in _recent(herd.productionRecords))
                _ProductionRecordLine(record: record),
            ],
            const SizedBox(height: FarmSpacing.md),
            _CreateProductionButton(
              key: ValueKey('live-production-create-herd-${herd.id}'),
              label: l10n.recordProduction,
              enabled:
                  collection.canRecordProduction && herd.canRecordProduction,
              onPressed: () => _openProductionSheet(
                context,
                collection,
                _ProductionSubject.herd(id: herd.id, name: species),
              ),
            ),
          ],
          if (herd.observations.isNotEmpty) ...[
            const SizedBox(height: FarmSpacing.md),
            for (final observation in _recentObservations(herd.observations))
              _AnimalObservationLine(observation: observation),
          ],
          if (collection.canRecordAnimalObservations &&
              herd.canRecordProduction) ...[
            const SizedBox(height: FarmSpacing.sm),
            _CreateAnimalObservationButton(
              key: ValueKey('live-animal-observation-create-herd-${herd.id}'),
              enabled: true,
              label: l10n.liveAnimalObservationCreate,
              onPressed: () => _openAnimalObservationSheet(
                context,
                collection,
                LiveAnimalObservationSubject.herd(id: herd.id, name: species),
              ),
            ),
          ],
          if (collection.canManageLivestockMovements && herd.isBatch) ...[
            const SizedBox(height: FarmSpacing.sm),
            _CreateLivestockMovementButton(
              key: ValueKey('live-movement-create-herd-${herd.id}'),
              enabled: herd.canRecordMovement,
              label: l10n.liveMovementCreate,
              onPressed: () => _openMovementSheet(context, collection, herd),
            ),
            if (herd.movementNeedsAttention)
              TextButton.icon(
                onPressed: () => context.push(AppRoutes.syncCenter),
                icon: const Icon(Icons.sync_problem_outlined),
                label: Text(l10n.liveMovementNeedsAttention),
              ),
          ],
        ],
      ),
    );
  }
}

class _LiveAnimalCard extends StatelessWidget {
  const _LiveAnimalCard({
    required this.collection,
    required this.herd,
    required this.animal,
  });

  final FarmlyLiveLivestockCollection collection;
  final FarmlyLiveHerd herd;
  final FarmlyLiveAnimal animal;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final tokens = FarmThemeExtension.of(context);
    final name = animal.name?.trim().isNotEmpty == true
        ? animal.name!
        : animal.tag;
    final status = switch (animal.status) {
      'alive' => l10n.animalStatusAlive,
      'sold' => l10n.animalStatusSold,
      'deceased' => l10n.animalStatusDeceased,
      _ => animal.status,
    };
    final canEdit =
        collection.canManageHerds &&
        herd.mode == 'tracked' &&
        herd.status == 'active' &&
        animal.syncState == FarmlyLivestockEntitySyncState.confirmed &&
        !animal.archived &&
        !animal.hasUnresolvedUpdate;
    return Container(
      decoration: BoxDecoration(
        color: tokens.surface,
        borderRadius: BorderRadius.circular(FarmSpacing.cardRadius),
      ),
      padding: const EdgeInsets.all(FarmSpacing.md),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              _SpeciesPortrait(species: herd.species),
              const SizedBox(width: FarmSpacing.md),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(name, style: Theme.of(context).textTheme.titleSmall),
                    if (animal.syncState !=
                        FarmlyLivestockEntitySyncState.confirmed)
                      Padding(
                        key: ValueKey('live-animal-sync-${animal.id}'),
                        padding: const EdgeInsets.only(top: FarmSpacing.xs),
                        child: Text(
                          _livestockEntitySyncLabel(l10n, animal.syncState),
                          style: Theme.of(context).textTheme.bodySmall
                              ?.copyWith(color: tokens.textSecondary),
                        ),
                      ),
                    Text(
                      '${l10n.animalTagLine(animal.tag)} · $status',
                      style: Theme.of(context).textTheme.bodySmall?.copyWith(
                        color: tokens.textSecondary,
                      ),
                    ),
                  ],
                ),
              ),
              if (canEdit)
                IconButton(
                  key: ValueKey('live-animal-edit-${animal.id}'),
                  tooltip: l10n.liveAnimalEditAction,
                  onPressed: () =>
                      _openAnimalEditSheet(context, collection, herd, animal),
                  icon: const Icon(Icons.edit_outlined),
                ),
            ],
          ),
          if (animal.productionRecords.isNotEmpty) ...[
            const SizedBox(height: FarmSpacing.sm),
            for (final record in _recent(animal.productionRecords))
              _ProductionRecordLine(record: record),
          ],
          if (animal.observations.isNotEmpty) ...[
            const SizedBox(height: FarmSpacing.sm),
            for (final observation in _recentObservations(animal.observations))
              _AnimalObservationLine(observation: observation),
          ],
          if (animal.canRecordProduction) ...[
            const SizedBox(height: FarmSpacing.sm),
            _CreateProductionButton(
              key: ValueKey('live-production-create-animal-${animal.id}'),
              label: l10n.recordProduction,
              enabled:
                  collection.canRecordProduction && herd.canRecordProduction,
              onPressed: () => _openProductionSheet(
                context,
                collection,
                _ProductionSubject.animal(id: animal.id, name: name),
              ),
            ),
          ],
          if (collection.canRecordAnimalObservations &&
              herd.canRecordProduction &&
              !animal.archived) ...[
            const SizedBox(height: FarmSpacing.sm),
            _CreateAnimalObservationButton(
              key: ValueKey(
                'live-animal-observation-create-animal-${animal.id}',
              ),
              enabled: true,
              label: l10n.liveAnimalObservationCreate,
              onPressed: () => _openAnimalObservationSheet(
                context,
                collection,
                LiveAnimalObservationSubject.animal(id: animal.id, name: name),
              ),
            ),
          ],
        ],
      ),
    );
  }
}

class _CreateProductionButton extends StatelessWidget {
  const _CreateProductionButton({
    super.key,
    required this.label,
    required this.enabled,
    required this.onPressed,
  });

  final String label;
  final bool enabled;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) => Align(
    alignment: AlignmentDirectional.centerStart,
    child: OutlinedButton.icon(
      onPressed: enabled ? onPressed : null,
      icon: const Icon(Icons.add_chart_outlined),
      label: Text(label),
    ),
  );
}

class _CreateLivestockMovementButton extends StatelessWidget {
  const _CreateLivestockMovementButton({
    super.key,
    required this.enabled,
    required this.label,
    required this.onPressed,
  });

  final bool enabled;
  final String label;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) => Align(
    alignment: AlignmentDirectional.centerStart,
    child: OutlinedButton.icon(
      onPressed: enabled ? onPressed : null,
      icon: const Icon(Icons.swap_vert),
      label: Text(label),
    ),
  );
}

class _CreateAnimalObservationButton extends StatelessWidget {
  const _CreateAnimalObservationButton({
    super.key,
    required this.enabled,
    required this.label,
    required this.onPressed,
  });

  final bool enabled;
  final String label;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) => Align(
    alignment: AlignmentDirectional.centerStart,
    child: OutlinedButton.icon(
      onPressed: enabled ? onPressed : null,
      icon: const Icon(Icons.note_add_outlined),
      label: Text(label),
    ),
  );
}

class _CreateLivestockEntityButton extends StatelessWidget {
  const _CreateLivestockEntityButton({
    super.key,
    required this.label,
    required this.onPressed,
  });

  final String label;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) => Align(
    alignment: AlignmentDirectional.centerStart,
    child: OutlinedButton.icon(
      onPressed: onPressed,
      icon: const Icon(Icons.add),
      label: Text(label),
    ),
  );
}

class _AnimalObservationLine extends StatelessWidget {
  const _AnimalObservationLine({required this.observation});

  final FarmlyLiveAnimalObservation observation;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final kind = observation.kind == 'vet'
        ? l10n.liveAnimalObservationVeterinary
        : l10n.liveAnimalObservationGeneral;
    final syncSuffix = switch (observation.syncState) {
      FarmlyAnimalObservationSyncState.confirmed => '',
      FarmlyAnimalObservationSyncState.savedOnDevice =>
        ' · ${l10n.savedOnDeviceSuffix}',
      FarmlyAnimalObservationSyncState.awaitingProjection =>
        ' · ${l10n.liveAnimalObservationAwaitingProjection}',
    };
    final formattedDate = observation.observedOn == null
        ? null
        : formatDisplayDate(observation.observedOn!, l10n.localeName);
    final dateSuffix = formattedDate == null ? '' : ' · $formattedDate';
    return Padding(
      padding: const EdgeInsets.only(bottom: FarmSpacing.xs),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(
            observation.kind == 'vet'
                ? Icons.medical_information_outlined
                : Icons.notes_outlined,
            size: 18,
            color: FarmThemeExtension.of(context).textSecondary,
          ),
          const SizedBox(width: FarmSpacing.xs),
          Expanded(
            child: Text(
              '$kind · ${observation.note}$dateSuffix$syncSuffix',
              maxLines: 4,
              overflow: TextOverflow.ellipsis,
              key: ValueKey('live-animal-observation-${observation.id}'),
              style: Theme.of(context).textTheme.bodySmall?.copyWith(
                color: FarmThemeExtension.of(context).textSecondary,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _ProductionRecordLine extends StatelessWidget {
  const _ProductionRecordLine({required this.record});

  final FarmlyLiveProductionRecord record;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final product = switch (record.product) {
      'milk' => l10n.productMilk,
      'eggs' => l10n.productEggs,
      'weight' => l10n.productWeight,
      _ => record.product,
    };
    final stateLabel = switch (record.syncState) {
      FarmlyProductionSyncState.confirmed => '',
      FarmlyProductionSyncState.savedOnDevice =>
        ' · ${l10n.savedOnDeviceSuffix}',
      FarmlyProductionSyncState.awaitingProjection =>
        ' · ${l10n.liveProductionAwaitingProjection}',
    };
    return Padding(
      padding: const EdgeInsets.only(bottom: FarmSpacing.xs),
      child: Text(
        '$product: ${record.quantity} ${_localizedUnit(l10n, record.unit)} · '
        '${formatDisplayDate(record.recordedOn, l10n.localeName)}$stateLabel',
        style: Theme.of(context).textTheme.bodySmall?.copyWith(
          color: FarmThemeExtension.of(context).textSecondary,
        ),
      ),
    );
  }
}

class _LiveMovementLine extends StatelessWidget {
  const _LiveMovementLine({required this.movement});

  final FarmlyLiveLivestockMovement movement;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final type = switch (movement.movementType) {
      'stock_in' => l10n.liveMovementStockIn,
      'sold' => l10n.liveMovementSold,
      'loss' => l10n.liveMovementLoss,
      _ => movement.movementType,
    };
    final syncSuffix = switch (movement.syncState) {
      FarmlyLivestockMovementSyncState.savedOnDevice =>
        l10n.liveMovementSyncSaved,
      FarmlyLivestockMovementSyncState.awaitingProjection =>
        l10n.liveMovementSyncAwaitingProjection,
    };
    final count = l10n
        .headcountSuffix(movement.delta.abs())
        .replaceFirst(RegExp(r'^\d+'), _signedHeadcount(movement.delta));
    return Padding(
      padding: const EdgeInsets.only(bottom: FarmSpacing.xs),
      child: Text(
        '$type · $count$syncSuffix',
        key: ValueKey('live-movement-pending-record-${movement.id}'),
        style: Theme.of(context).textTheme.bodySmall?.copyWith(
          color: FarmThemeExtension.of(context).textSecondary,
        ),
      ),
    );
  }
}

class _SpeciesPortrait extends StatelessWidget {
  const _SpeciesPortrait({required this.species});

  final String? species;

  @override
  Widget build(BuildContext context) {
    final category = _categoryForSpecies(species);
    if (category == null) {
      return const SizedBox(
        width: 44,
        height: 44,
        child: Center(child: Icon(Icons.pets_outlined)),
      );
    }
    return AnimalPortrait(category: category);
  }
}

DemoAnimalCategory? _categoryForSpecies(String? species) {
  final value = species?.toLowerCase() ?? '';
  if (value.contains('cattle') ||
      value.contains('cow') ||
      value.contains('bò')) {
    return DemoAnimalCategory.cows;
  }
  if (value.contains('chicken') ||
      value.contains('hen') ||
      value.contains('gà')) {
    return DemoAnimalCategory.chickens;
  }
  if (value.contains('sheep') || value.contains('cừu')) {
    return DemoAnimalCategory.sheep;
  }
  if (value.contains('goat') || value.contains('dê')) {
    return DemoAnimalCategory.goats;
  }
  return null;
}

List<FarmlyLiveProductionRecord> _recent(
  List<FarmlyLiveProductionRecord> records,
) {
  final sorted = records.toList()
    ..sort((a, b) => b.recordedOn.compareTo(a.recordedOn));
  return sorted.take(3).toList(growable: false);
}

List<FarmlyLiveAnimalObservation> _recentObservations(
  List<FarmlyLiveAnimalObservation> observations,
) {
  final sorted = observations.toList()
    ..sort((a, b) {
      final date = (b.observedOn ?? '').compareTo(a.observedOn ?? '');
      return date != 0 ? date : b.sequence.compareTo(a.sequence);
    });
  return sorted.take(3).toList(growable: false);
}

String _localizedUnit(AppLocalizations l10n, String unit) => switch (unit) {
  'litre' => l10n.unitLitres,
  'pieces' => l10n.unitEggs,
  'kg' => l10n.unitKg,
  _ => unit,
};

void _openProductionSheet(
  BuildContext context,
  FarmlyLiveLivestockCollection collection,
  _ProductionSubject subject,
) {
  showModalBottomSheet<bool>(
    context: context,
    isScrollControlled: true,
    useSafeArea: true,
    builder: (_) =>
        _LiveProductionCreateSheet(collection: collection, subject: subject),
  ).then((saved) {
    if (saved == true && context.mounted) {
      showFarmToast(context, AppLocalizations.of(context).savedOnDeviceToast);
    }
  });
}

void _openMovementSheet(
  BuildContext context,
  FarmlyLiveLivestockCollection collection,
  FarmlyLiveHerd herd,
) {
  showModalBottomSheet<bool>(
    context: context,
    isScrollControlled: true,
    useSafeArea: true,
    builder: (_) =>
        LiveLivestockMovementCreateSheet(collection: collection, herd: herd),
  ).then((saved) {
    if (saved == true && context.mounted) {
      showFarmToast(context, AppLocalizations.of(context).savedOnDeviceToast);
    }
  });
}

void _openHerdCreateSheet(
  BuildContext context,
  FarmlyLiveLivestockCollection collection,
) {
  showModalBottomSheet<bool>(
    context: context,
    isScrollControlled: true,
    useSafeArea: true,
    builder: (_) => LiveHerdCreateSheet(collection: collection),
  ).then((saved) {
    if (saved == true && context.mounted) {
      showFarmToast(context, AppLocalizations.of(context).savedOnDeviceToast);
    }
  });
}

void _openAnimalCreateSheet(
  BuildContext context,
  FarmlyLiveLivestockCollection collection,
  FarmlyLiveHerd herd,
) {
  showModalBottomSheet<bool>(
    context: context,
    isScrollControlled: true,
    useSafeArea: true,
    builder: (_) => LiveAnimalCreateSheet(collection: collection, herd: herd),
  ).then((saved) {
    if (saved == true && context.mounted) {
      showFarmToast(context, AppLocalizations.of(context).savedOnDeviceToast);
    }
  });
}

void _openAnimalEditSheet(
  BuildContext context,
  FarmlyLiveLivestockCollection collection,
  FarmlyLiveHerd herd,
  FarmlyLiveAnimal animal,
) {
  showModalBottomSheet<bool>(
    context: context,
    isScrollControlled: true,
    useSafeArea: true,
    builder: (_) =>
        LiveAnimalEditSheet(collection: collection, herd: herd, animal: animal),
  ).then((saved) {
    if (saved == true && context.mounted) {
      showFarmToast(context, AppLocalizations.of(context).savedOnDeviceToast);
    }
  });
}

void _openAnimalObservationSheet(
  BuildContext context,
  FarmlyLiveLivestockCollection collection,
  LiveAnimalObservationSubject subject,
) {
  showModalBottomSheet<bool>(
    context: context,
    isScrollControlled: true,
    useSafeArea: true,
    builder: (_) => LiveAnimalObservationCreateSheet(
      collection: collection,
      subject: subject,
    ),
  ).then((saved) {
    if (saved == true && context.mounted) {
      showFarmToast(context, AppLocalizations.of(context).savedOnDeviceToast);
    }
  });
}

String _signedHeadcount(int count) => count > 0 ? '+$count' : '$count';

String _livestockEntitySyncLabel(
  AppLocalizations l10n,
  FarmlyLivestockEntitySyncState state,
) => switch (state) {
  FarmlyLivestockEntitySyncState.confirmed => '',
  FarmlyLivestockEntitySyncState.savedOnDevice =>
    l10n.liveLivestockSavedOnDevice,
  FarmlyLivestockEntitySyncState.awaitingProjection =>
    l10n.liveLivestockAwaitingProjection,
};

final class _ProductionSubject {
  const _ProductionSubject._({
    required this.id,
    required this.name,
    required this.herd,
  });

  factory _ProductionSubject.herd({required String id, required String name}) =>
      _ProductionSubject._(id: id, name: name, herd: true);

  factory _ProductionSubject.animal({
    required String id,
    required String name,
  }) => _ProductionSubject._(id: id, name: name, herd: false);

  final String id;
  final String name;
  final bool herd;
}

class _LiveProductionCreateSheet extends ConsumerStatefulWidget {
  const _LiveProductionCreateSheet({
    required this.collection,
    required this.subject,
  });

  final FarmlyLiveLivestockCollection collection;
  final _ProductionSubject subject;

  @override
  ConsumerState<_LiveProductionCreateSheet> createState() =>
      _LiveProductionCreateSheetState();
}

class _LiveProductionCreateSheetState
    extends ConsumerState<_LiveProductionCreateSheet> {
  final _quantityController = TextEditingController();
  String _product = 'milk';
  DateTime? _recordedOn;
  String? _error;
  bool _saving = false;

  @override
  void dispose() {
    _quantityController.dispose();
    super.dispose();
  }

  bool _scopeIsCurrent() {
    final expected = widget.collection;
    final scope = expected.scope;
    final selected = expected.selectedScope;
    if (scope == null || selected == null) return false;
    final currentAccount = ref
        .read(farmlyAuthSessionProvider)
        .asData
        ?.value
        ?.user
        .id;
    final currentSelected = ref.read(selectedOrganizationScopeProvider);
    final currentScope = ref.read(farmlySyncScopeProvider).asData?.value;
    final current = ref.read(farmlyLiveLivestockProvider).asData?.value;
    return currentAccount == scope.accountId &&
        _sameSelectedScope(selected, currentSelected) &&
        _sameFarmScope(scope, currentScope) &&
        current?.cacheState == FarmlyLivestockCacheState.ready &&
        current?.canRecordProduction == true &&
        _subjectIsWritable(current!, widget.subject);
  }

  Future<void> _chooseDate() async {
    final today = DateTime.now();
    final picked = await showDatePicker(
      context: context,
      initialDate: _recordedOn ?? DateTime(today.year, today.month, today.day),
      firstDate: DateTime(1900),
      lastDate: DateTime(9999, 12, 31),
      initialEntryMode: DatePickerEntryMode.calendar,
      helpText: AppLocalizations.of(context).liveProductionRecordedOnLabel,
    );
    if (picked != null && mounted) {
      setState(() {
        _recordedOn = picked;
        _error = null;
      });
    }
  }

  Future<void> _save() async {
    if (_saving) return;
    final l10n = AppLocalizations.of(context);
    if (_recordedOn == null) {
      setState(() => _error = l10n.liveProductionDateRequired);
      return;
    }
    if (!_scopeIsCurrent()) {
      setState(() => _error = l10n.liveFarmScopeChanged);
      return;
    }
    final quantity = _quantityController.text.trim().replaceAll(',', '.');
    final date = _civilDate(_recordedOn!);
    late final FarmlyCreateProductionRecordIntent intent;
    try {
      intent = FarmlyCreateProductionRecordIntent(
        operationId: newFarmlyOperationId(),
        continuityEpoch: widget.collection.scope!.continuityEpoch,
        resourceId: newFarmlyOperationId(),
        herdId: widget.subject.herd ? widget.subject.id : null,
        animalId: widget.subject.herd ? null : widget.subject.id,
        product: _product,
        quantity: quantity,
        recordedOn: date,
      );
    } on FormatException {
      setState(() => _error = l10n.productionRequired);
      return;
    } on ArgumentError {
      setState(() => _error = l10n.productionRequired);
      return;
    }

    setState(() {
      _saving = true;
      _error = null;
    });
    try {
      // Recheck after any async boundary, then persist to the local outbox.
      // This action never calls the transport.
      if (!_scopeIsCurrent()) {
        setState(() => _error = l10n.liveFarmScopeChanged);
        return;
      }
      final engine = await ref.read(syncEngineProvider.future);
      if (!_scopeIsCurrent()) {
        setState(() => _error = l10n.liveFarmScopeChanged);
        return;
      }
      await engine.enqueue(
        FarmlyScopedMutation(scope: widget.collection.scope!, intent: intent),
      );
      ref.invalidate(syncStatusProvider);
      ref.invalidate(farmlyLiveLivestockProvider);
      if (mounted) Navigator.of(context).pop(true);
    } catch (_) {
      if (mounted) setState(() => _error = l10n.liveProductionSaveFailed);
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final units = <String, String>{
      'milk': l10n.unitLitres,
      'eggs': l10n.unitEggs,
      'weight': l10n.unitKg,
    };
    final labels = <String, String>{
      'milk': l10n.productMilk,
      'eggs': l10n.productEggs,
      'weight': l10n.productWeight,
    };
    final scopeCurrent = _scopeIsCurrent();
    return Padding(
      padding: EdgeInsets.only(bottom: MediaQuery.viewInsetsOf(context).bottom),
      child: SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(
          FarmSpacing.lg,
          FarmSpacing.lg,
          FarmSpacing.lg,
          FarmSpacing.xl,
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(
              l10n.productionDialogTitle(widget.subject.name),
              style: Theme.of(context).textTheme.titleLarge,
            ),
            const SizedBox(height: FarmSpacing.md),
            DropdownButtonFormField<String>(
              key: const ValueKey('live-production-product'),
              initialValue: _product,
              decoration: InputDecoration(labelText: l10n.productTypeLabel),
              items: [
                for (final entry in labels.entries)
                  DropdownMenuItem(value: entry.key, child: Text(entry.value)),
              ],
              onChanged: _saving || !scopeCurrent
                  ? null
                  : (value) => setState(() => _product = value ?? 'milk'),
            ),
            const SizedBox(height: FarmSpacing.md),
            DecimalField(
              key: const ValueKey('live-production-quantity'),
              controller: _quantityController,
              autofocus: true,
              labelText: l10n.quantityLabel(units[_product]!),
              errorText: _error == l10n.productionRequired ? _error : null,
              onSubmitted: (_) => _save(),
            ),
            const SizedBox(height: FarmSpacing.md),
            Semantics(
              button: true,
              label: l10n.liveProductionRecordedOnLabel,
              child: OutlinedButton.icon(
                key: const ValueKey('live-production-recorded-on'),
                onPressed: _saving || !scopeCurrent ? null : _chooseDate,
                icon: const Icon(Icons.calendar_month_outlined),
                label: Text(
                  _recordedOn == null
                      ? l10n.liveProductionRecordedOnLabel
                      : _civilDate(_recordedOn!),
                ),
              ),
            ),
            if (_error != null && _error != l10n.productionRequired) ...[
              const SizedBox(height: FarmSpacing.sm),
              Text(
                _error!,
                style: TextStyle(
                  color: FarmThemeExtension.of(context).semanticWarning,
                ),
              ),
            ],
            const SizedBox(height: FarmSpacing.md),
            Text(
              l10n.liveProductionRecordedOnHelper,
              style: Theme.of(context).textTheme.bodySmall?.copyWith(
                color: FarmThemeExtension.of(context).textSecondary,
              ),
            ),
            const SizedBox(height: FarmSpacing.lg),
            FilledButton(
              key: const ValueKey('live-production-save'),
              onPressed: _saving || !scopeCurrent ? null : _save,
              child: Text(l10n.saveOnDevice),
            ),
          ],
        ),
      ),
    );
  }
}

bool _sameSelectedScope(
  FarmlyOrganizationScope expected,
  FarmlyOrganizationScope? current,
) =>
    current != null &&
    current.epoch == expected.epoch &&
    current.organization.id == expected.organization.id &&
    current.organization.status == expected.organization.status &&
    current.organization.role == expected.organization.role &&
    current.selectedFarmId == expected.selectedFarmId &&
    current.directory.continuityEpoch == expected.directory.continuityEpoch &&
    current.directory.scopePolicyVersion ==
        expected.directory.scopePolicyVersion;

bool _sameFarmScope(
  FarmlyMutationScope expected,
  FarmlyMutationScope? current,
) =>
    current != null &&
    current.kind == FarmlyMutationScopeKind.farm &&
    current.accountId == expected.accountId &&
    current.organizationId == expected.organizationId &&
    current.farmId == expected.farmId &&
    current.continuityEpoch == expected.continuityEpoch;

bool _subjectIsWritable(
  FarmlyLiveLivestockCollection current,
  _ProductionSubject subject,
) {
  for (final herd in current.herds) {
    if (subject.herd && herd.id == subject.id) {
      return herd.canRecordProduction && herd.isBatch;
    }
    if (!subject.herd) {
      for (final animal in herd.animals) {
        if (animal.id == subject.id) {
          return herd.canRecordProduction && animal.canRecordProduction;
        }
      }
    }
  }
  return false;
}

String _civilDate(DateTime date) =>
    '${date.year.toString().padLeft(4, '0')}-'
    '${date.month.toString().padLeft(2, '0')}-'
    '${date.day.toString().padLeft(2, '0')}';

void _synchronize(WidgetRef ref) {
  ref.read(syncStatusProvider.notifier).synchronize();
}

class _LivestockNotice extends StatelessWidget {
  const _LivestockNotice({
    super.key,
    required this.icon,
    required this.title,
    required this.body,
    this.actionLabel,
    this.onAction,
  });

  final IconData icon;
  final String title;
  final String body;
  final String? actionLabel;
  final VoidCallback? onAction;

  @override
  Widget build(BuildContext context) => ListView(
    padding: const EdgeInsets.all(FarmSpacing.lg),
    children: [
      FarmCard(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Icon(icon, color: FarmThemeExtension.of(context).brandAction),
            const SizedBox(height: FarmSpacing.sm),
            Text(title, style: Theme.of(context).textTheme.titleMedium),
            const SizedBox(height: FarmSpacing.xs),
            Text(body, style: Theme.of(context).textTheme.bodyMedium),
            if (actionLabel != null) ...[
              const SizedBox(height: FarmSpacing.md),
              FilledButton(onPressed: onAction, child: Text(actionLabel!)),
            ],
          ],
        ),
      ),
    ],
  );
}
