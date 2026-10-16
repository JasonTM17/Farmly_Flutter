import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/format/display_format.dart';
import '../../core/theme/farmly_spacing.dart';
import '../../core/theme/farmly_theme_extension.dart';
import '../../l10n/generated/app_localizations.dart';
import '../../ui/farm_card.dart';
import '../../ui/form_fields.dart';
import '../../ui/illustrations.dart';
import '../../ui/motion.dart';
import '../../ui/livestock_components.dart';
import '../../ui/pickers.dart';
import '../../ui/screen_states.dart';
import '../demo/demo_models.dart';
import '../demo/demo_providers.dart';

/// Livestock overview: herd-grouped list with batch-vs-tracked semantics —
/// tracked herds show per-animal cards, batch herds a single quantity card;
/// headcounts never double count and sold/deceased records stay visible but
/// excluded (D-05). No clinical/health metric is fabricated (spec 02 §5).
class LivestockScreen extends ConsumerStatefulWidget {
  const LivestockScreen({super.key});

  @override
  ConsumerState<LivestockScreen> createState() => _LivestockScreenState();
}

class _LivestockScreenState extends ConsumerState<LivestockScreen> {
  DemoAnimalCategory? _categoryFilter;

  @override
  Widget build(BuildContext context) {
    final state = ref.watch(demoDataProvider);
    final farm = farmById(state, state.selectedFarmId);
    final herds = herdsOfFarm(state, farm?.id);
    final feeding = feedingOfFarm(state, farm?.id);
    final screenState = effectiveDemoState(
      ref,
      'livestock',
      dataEmpty: herds.isEmpty,
    );
    final tokens = FarmThemeExtension.of(context);

    final visibleHerds = _categoryFilter == null
        ? herds
        : herds.where((herd) => herd.category == _categoryFilter).toList(
            growable: false,
          );
    final totalHeadcount = farmLivestockHeadcount(state, farm?.id);
    final trackedHeadcount = herds
        .where((herd) => herd.mode == DemoHerdMode.tracked)
        .fold(0, (sum, herd) => sum + herdHeadcount(state, herd));
    final batchHeadcount = totalHeadcount - trackedHeadcount;

    final feedingDone = feeding.fold<int>(0, (sum, entry) => sum + entry.done);
    final feedingTotal = feeding.fold<int>(0, (sum, entry) => sum + entry.total);
    final l10n = AppLocalizations.of(context);

    return Scaffold(
      backgroundColor: Theme.of(context).scaffoldBackgroundColor,
      appBar: AppBar(
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(l10n.livestockScreenTitle),
            if (farm != null)
              Text(
                farm.name,
                style: Theme.of(context).textTheme.bodySmall?.copyWith(
                  color: tokens.textSecondary,
                ),
              ),
          ],
        ),
      ),
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
              child: DemoStateSwitcher(screenKey: 'livestock'),
            ),
            Expanded(
              child: switch (screenState) {
                DemoLoadState.loading => _LivestockSkeleton(
                  headcount: totalHeadcount,
                  filter: _categoryFilter,
                  onFilter: (category) =>
                      setState(() => _categoryFilter = category),
                ),
                DemoLoadState.recoverableError => FarmErrorView(
                  onRetry: () => ref
                      .read(demoScreenStateProvider.notifier)
                      .reset('livestock'),
                  onSwitchScope: () => showFarmPickerSheet(context),
                ),
                DemoLoadState.permissionDenied => PermissionDeniedView(
                  message: l10n.livestockPermissionBody,
                  onSwitchScope: () => showFarmPickerSheet(context),
                ),
                DemoLoadState.empty => EmptyStateView(
                  title: l10n.livestockEmptyTitle,
                  message: l10n.livestockEmptyBody,
                  actionLabel: l10n.changeFarm,
                  onAction: () => showFarmPickerSheet(context),
                ),
                DemoLoadState.offline ||
                DemoLoadState.pendingConflict ||
                DemoLoadState.success => ListView(
                  padding: const EdgeInsets.fromLTRB(
                    FarmSpacing.lg,
                    0,
                    FarmSpacing.lg,
                    FarmSpacing.xxl,
                  ),
                  children: [
                    if (screenState == DemoLoadState.offline) ...[
                      const OfflineBanner(asOf: '06:30'),
                      const SizedBox(height: FarmSpacing.md),
                    ],
                    FarmCard(
                      semanticsLabel: l10n.herdTotalsSemantics(
                        totalHeadcount,
                        trackedHeadcount,
                        batchHeadcount,
                        feedingDone,
                        feedingTotal,
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            l10n.herdTotalLine(totalHeadcount),
                            style: Theme.of(context).textTheme.titleMedium,
                          ),
                          const SizedBox(height: FarmSpacing.xs),
                          Text(
                            l10n.herdSplitLine(trackedHeadcount, batchHeadcount),
                            style: Theme.of(context).textTheme.bodySmall
                                ?.copyWith(color: tokens.textSecondary),
                            softWrap: true,
                          ),
                          const SizedBox(height: FarmSpacing.xs),
                          Text(
                            l10n.feedingTodayLine(feedingDone, feedingTotal),
                            style: Theme.of(context).textTheme.bodySmall
                                ?.copyWith(color: tokens.textSecondary),
                            softWrap: true,
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: FarmSpacing.md),
                    FarmCard(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            children: [
                              Expanded(
                                child: Text(
                                  l10n.feedingSectionTitle,
                                  style: Theme.of(
                                    context,
                                  ).textTheme.titleSmall,
                                ),
                              ),
                              Container(
                                padding: const EdgeInsets.symmetric(
                                  horizontal: FarmSpacing.sm,
                                  vertical: 3,
                                ),
                                decoration: BoxDecoration(
                                  color: tokens.brandSage.withValues(
                                    alpha: 0.4,
                                  ),
                                  borderRadius: BorderRadius.circular(999),
                                ),
                                child: Text(
                                  l10n.feedingProgressBadge(
                                    feedingDone,
                                    feedingTotal,
                                  ),
                                  style: Theme.of(
                                    context,
                                  ).textTheme.labelSmall?.copyWith(
                                    color: tokens.brandAction,
                                    fontWeight: FontWeight.w600,
                                  ),
                                ),
                              ),
                            ],
                          ),
                          const SizedBox(height: FarmSpacing.md),
                          FeedingTimeline(entries: feeding),
                          const SizedBox(height: FarmSpacing.sm),
                          Text(
                            l10n.feedingFarmDayNote,
                            style: Theme.of(
                              context,
                            ).textTheme.labelSmall?.copyWith(
                              color: tokens.textSecondary,
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
                    const SizedBox(height: 2),
                    Text(
                      l10n.herdGroupsHint,
                      style: Theme.of(context).textTheme.bodySmall?.copyWith(
                        color: tokens.textSecondary,
                      ),
                    ),
                    const SizedBox(height: FarmSpacing.sm),
                    SizedBox(
                      height: 116,
                      child: ListView(
                        scrollDirection: Axis.horizontal,
                        children: [
                          FarmEntrance(
                            child: Semantics(
                              button: true,
                              selected: _categoryFilter == null,
                              label: l10n.allGroupsSemantics(totalHeadcount),
                              child: SizedBox(
                                width: 96,
                                child: _AllCategoryCard(
                                  count: totalHeadcount,
                                  selected: _categoryFilter == null,
                                  onTap: () =>
                                      setState(() => _categoryFilter = null),
                                ),
                              ),
                            ),
                          ),
                          for (final (ci, category)
                              in DemoAnimalCategory.values.indexed)
                            FarmEntrance(
                              delay: Duration(milliseconds: 60 * (ci + 1)),
                              child: Padding(
                                padding: const EdgeInsets.only(
                                  left: FarmSpacing.sm,
                                ),
                                child: AnimalCategoryCard(
                                category: category,
                                count: categoryLivestockHeadcount(
                                  state,
                                  farm?.id,
                                  category,
                                ),
                                  selected: _categoryFilter == category,
                                  onSelected: (_) => setState(
                                    () => _categoryFilter = category,
                                  ),
                                ),
                              ),
                            ),
                        ],
                      ),
                    ),
                    const SizedBox(height: FarmSpacing.md),
                    if (visibleHerds.isEmpty)
                      FarmCard(
                        child: Padding(
                          padding: const EdgeInsets.symmetric(
                            vertical: FarmSpacing.lg,
                          ),
                          child: Column(
                            children: [
                              Text(
                                l10n.noHerdsInGroupTitle,
                                style: Theme.of(context).textTheme.titleSmall,
                                textAlign: TextAlign.center,
                                softWrap: true,
                              ),
                              const SizedBox(height: FarmSpacing.xs),
                              Text(
                                l10n.noHerdsInGroupBody,
                                style: Theme.of(context).textTheme.bodySmall
                                    ?.copyWith(color: tokens.textSecondary),
                                softWrap: true,
                              ),
                            ],
                          ),
                        ),
                      )
                    else
                      for (final (hi, herd) in visibleHerds.indexed)
                        Padding(
                          padding: const EdgeInsets.only(bottom: FarmSpacing.md),
                          child: FarmEntrance(
                            delay: Duration(milliseconds: 80 * hi),
                            child: _HerdSection(
                            herd: herd,
                            animals: animalsOfHerd(state, herd.id),
                            headcount: herdHeadcount(state, herd),
                            records: productionOfHerd(state, herd.id),
                              readOnly:
                                  screenState == DemoLoadState.permissionDenied,
                            ),
                          ),
                        ),
                  ],
                ),
              },
          ),
        ],
        ),
      ),
    );
  }
}

/// Sentinel category used by the "Tất cả" chip is null in the filter state.

class _LivestockSkeleton extends StatelessWidget {
  const _LivestockSkeleton({
    required this.headcount,
    required this.filter,
    required this.onFilter,
  });

  final int headcount;
  final DemoAnimalCategory? filter;
  final ValueChanged<DemoAnimalCategory?> onFilter;

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
        const SkeletonSurface(
          width: double.infinity,
          height: 72,
          radius: FarmSpacing.cardRadius,
        ),
        const SizedBox(height: FarmSpacing.md),
        const SkeletonSurface(
          width: double.infinity,
          height: 140,
          radius: FarmSpacing.cardRadius,
        ),
        const SizedBox(height: FarmSpacing.md),
        SizedBox(
          height: 116,
          child: ListView(
            scrollDirection: Axis.horizontal,
            children: [
              for (var i = 0; i < 5; i++)
                const Padding(
                  padding: EdgeInsets.only(right: FarmSpacing.sm),
                  child: SkeletonSurface(
                    width: 96,
                    height: 116,
                    radius: FarmSpacing.cardRadius,
                  ),
                ),
            ],
          ),
        ),
        const SkeletonSurface(
          width: double.infinity,
          height: 88,
          radius: FarmSpacing.cardRadius,
        ),
      ],
    );
  }
}

/// One herd block (spec 02 §5 Livestock + D-05): tracked herds render their
/// animal cards (sold/deceased stay visible with their status chip but never
/// count); a batch herd renders a single quantity card — it has no
/// per-animal records by design, so no fabricated member list.
class _HerdSection extends ConsumerWidget {
  const _HerdSection({
    required this.herd,
    required this.animals,
    required this.headcount,
    required this.records,
    required this.readOnly,
  });

  final DemoHerd herd;
  final List<DemoAnimal> animals;
  final int headcount;
  final List<DemoProductionRecord> records;
  final bool readOnly;

  Future<void> _recordProduction(
    BuildContext context,
    WidgetRef ref,
  ) async {
    final saved = await showDialog<bool>(
      context: context,
      builder: (_) => _ProductionDialog(herd: herd),
    );
    if (saved != true || !context.mounted) return;
    showFarmToast(context, AppLocalizations.of(context).savedLocallyToast);
  }

  Future<void> _recordMovement(
    BuildContext context,
    WidgetRef ref,
  ) async {
    final saved = await showDialog<bool>(
      context: context,
      builder: (_) => _BatchMovementDialog(herd: herd),
    );
    if (saved != true || !context.mounted) return;
    showFarmToast(context, AppLocalizations.of(context).movementSavedToast);
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final tokens = FarmThemeExtension.of(context);
    final l10n = AppLocalizations.of(context);
    final modeLabel = herdModeLabel(l10n, herd.mode);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Semantics(
          container: true,
          label: l10n.herdSemantics(herd.species, modeLabel, headcount),
          child: Row(
            children: [
              Expanded(
                child: Text(
                  '${herd.species} · $modeLabel',
                  style: Theme.of(context).textTheme.titleSmall,
                  softWrap: true,
                ),
              ),
              Text(
                l10n.headcountSuffix(headcount),
                style: Theme.of(context).textTheme.titleSmall?.copyWith(
                  color: tokens.brandAction,
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: FarmSpacing.sm),
        if (herd.mode == DemoHerdMode.batch)
          FarmCard(
            child: Row(
              children: [
                AnimalPortrait(category: herd.category),
                const SizedBox(width: FarmSpacing.lg),
                Expanded(
                  child: Text(
                    l10n.batchHerdNote(headcount),
                    style: Theme.of(context).textTheme.bodySmall?.copyWith(
                      color: tokens.textSecondary,
                    ),
                    softWrap: true,
                  ),
                ),
              ],
            ),
          )
        else
          for (final animal in animals)
            Padding(
              padding: const EdgeInsets.only(bottom: FarmSpacing.sm),
              child: AnimalCard(animal: animal),
            ),
        if (records.isNotEmpty) ...[
          const SizedBox(height: FarmSpacing.sm),
          for (final record in records.take(3))
            Padding(
              padding: const EdgeInsets.only(bottom: FarmSpacing.xs),
              child: Text(
                '${_productLabel(l10n, record.product)}: ${record.quantity} '
                '${record.unit} · ${formatDisplayDate(record.recordedOn, l10n.localeName)}',
                style: Theme.of(context).textTheme.bodySmall?.copyWith(
                  color: FarmThemeExtension.of(context).textSecondary,
                ),
                softWrap: true,
              ),
            ),
        ],
        const SizedBox(height: FarmSpacing.sm),
        Wrap(
          spacing: FarmSpacing.sm,
          runSpacing: FarmSpacing.sm,
          children: [
            OutlinedButton.icon(
              onPressed: readOnly ? null : () => _recordProduction(context, ref),
              icon: const Icon(Icons.add_chart_outlined),
              label: Text(l10n.recordProduction),
            ),
            if (herd.mode == DemoHerdMode.batch)
              OutlinedButton.icon(
                onPressed: readOnly
                    ? null
                    : () => _recordMovement(context, ref),
                icon: const Icon(Icons.swap_vert_outlined),
                label: Text(l10n.batchMovement),
              ),
          ],
        ),
      ],
    );
  }
}

String _productLabel(AppLocalizations l10n, String product) => switch (product) {
  'milk' => l10n.productMilk,
  'eggs' => l10n.productEggs,
  'weight' => l10n.productWeight,
  _ => product,
};

/// Production-record dialog (phase 06 step 3): product + exact decimal
/// quantity in the product's unit. Writes land local-pending via
/// `recordProduction` — a `productionRecord.create` outbox intent.
class _ProductionDialog extends ConsumerStatefulWidget {
  const _ProductionDialog({required this.herd});

  final DemoHerd herd;

  @override
  ConsumerState<_ProductionDialog> createState() => _ProductionDialogState();
}

class _ProductionDialogState extends ConsumerState<_ProductionDialog> {
  final _quantityController = TextEditingController();
  String _product = 'milk';
  String? _quantityError;

  @override
  void dispose() {
    _quantityController.dispose();
    super.dispose();
  }

  Map<String, String> _productLabels(AppLocalizations l10n) => {
    'milk': l10n.productMilk,
    'eggs': l10n.productEggs,
    'weight': l10n.productWeight,
  };
  Map<String, String> _productUnits(AppLocalizations l10n) => {
    'milk': l10n.unitLitres,
    'eggs': l10n.unitEggs,
    'weight': l10n.unitKg,
  };

  void _save() {
    final l10n = AppLocalizations.of(context);
    final raw = _quantityController.text.trim().replaceAll(',', '.');
    if (raw.isEmpty || double.tryParse(raw) == null) {
      setState(() => _quantityError = l10n.productionRequired);
      return;
    }
    ref
        .read(demoDataProvider.notifier)
        .recordProduction(
          widget.herd.id,
          product: _product,
          quantity: raw,
          unit: _productUnits(l10n)[_product]!,
        );
    Navigator.of(context).pop(true);
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final productLabels = _productLabels(l10n);
    final productUnits = _productUnits(l10n);
    return AlertDialog(
      title: Text(l10n.productionDialogTitle(widget.herd.species)),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          DropdownButtonFormField<String>(
            initialValue: _product,
            decoration: InputDecoration(labelText: l10n.productTypeLabel),
            items: [
              for (final entry in productLabels.entries)
                DropdownMenuItem(value: entry.key, child: Text(entry.value)),
            ],
            onChanged: (next) => setState(() => _product = next!),
          ),
          const SizedBox(height: FarmSpacing.md),
          DecimalField(
            controller: _quantityController,
            autofocus: true,
            labelText: l10n.quantityLabel(productUnits[_product]!),
            errorText: _quantityError,
            onSubmitted: (_) => _save(),
          ),
        ],
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: Text(l10n.cancel),
        ),
        FilledButton(onPressed: _save, child: Text(l10n.saveLabel)),
      ],
    );
  }
}

/// Batch movement dialog (phase 06 step 3, D-13): signed headcount delta +
/// reason — no silent edits to `batchQuantity`. The write lands as a
/// `livestockMovement.create` outbox intent.
class _BatchMovementDialog extends ConsumerStatefulWidget {
  const _BatchMovementDialog({required this.herd});

  final DemoHerd herd;

  @override
  ConsumerState<_BatchMovementDialog> createState() =>
      _BatchMovementDialogState();
}

class _BatchMovementDialogState extends ConsumerState<_BatchMovementDialog> {
  final _deltaController = TextEditingController();
  final _reasonController = TextEditingController();
  String? _error;

  @override
  void dispose() {
    _deltaController.dispose();
    _reasonController.dispose();
    super.dispose();
  }

  void _save() {
    final l10n = AppLocalizations.of(context);
    final delta = int.tryParse(_deltaController.text.trim());
    final reason = _reasonController.text.trim();
    if (delta == null || delta == 0) {
      setState(() => _error = l10n.movementDeltaRequired);
      return;
    }
    if (reason.isEmpty) {
      setState(() => _error = l10n.movementReasonRequired);
      return;
    }
    final current = widget.herd.batchQuantity ?? 0;
    if (current + delta < 0) {
      setState(() => _error = l10n.movementExceedsHerd(current));
      return;
    }
    ref
        .read(demoDataProvider.notifier)
        .recordBatchMovement(widget.herd.id, delta, reason);
    Navigator.of(context).pop(true);
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    return AlertDialog(
      title: Text(l10n.movementDialogTitle(widget.herd.species)),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          TextField(
            controller: _deltaController,
            autofocus: true,
            decoration: InputDecoration(
              labelText: l10n.movementDeltaLabel,
              hintText: l10n.movementDeltaHint,
            ),
            keyboardType: const TextInputType.numberWithOptions(signed: true),
            onSubmitted: (_) => _save(),
          ),
          const SizedBox(height: FarmSpacing.md),
          TextField(
            controller: _reasonController,
            decoration: InputDecoration(
              labelText: l10n.movementReasonLabel,
              hintText: l10n.movementReasonHint,
              errorText: _error,
            ),
          ),
        ],
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: Text(l10n.cancel),
        ),
        FilledButton(onPressed: _save, child: Text(l10n.saveLabel)),
      ],
    );
  }
}

/// The leading "Tất cả" card in the category row — mirrors
/// [AnimalCategoryCard] with a generic herd icon instead of a portrait.
class _AllCategoryCard extends StatelessWidget {
  const _AllCategoryCard({
    required this.count,
    required this.selected,
    required this.onTap,
  });

  final int count;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final tokens = FarmThemeExtension.of(context);
    return Material(
      color: selected
          ? tokens.brandSage.withValues(alpha: 0.35)
          : Theme.of(context).colorScheme.surface,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(FarmSpacing.cardRadius),
        side: BorderSide(
          color: selected ? tokens.brandAction : tokens.divider,
          width: selected ? 1.6 : 1,
        ),
      ),
      child: InkWell(
        borderRadius: BorderRadius.circular(FarmSpacing.cardRadius),
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.symmetric(
            vertical: FarmSpacing.sm,
            horizontal: FarmSpacing.sm,
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              SizedBox(
                width: 44,
                height: 44,
                child: Icon(
                  Icons.groups_2_outlined,
                  size: 36,
                  color: tokens.brandAction,
                ),
              ),
              const SizedBox(height: FarmSpacing.sm),
              Text(
                '$count',
                style: Theme.of(context).textTheme.titleMedium,
              ),
              Text(
                AppLocalizations.of(context).allGroupsLabel,
                style: Theme.of(context).textTheme.bodySmall?.copyWith(
                  color: tokens.textSecondary,
                ),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
            ],
          ),
        ),
      ),
    );
  }
}
