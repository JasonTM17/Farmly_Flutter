import 'package:flutter/material.dart';

import '../core/format/display_format.dart';
import '../core/theme/farmly_spacing.dart';
import '../core/theme/farmly_theme_extension.dart';
import '../features/demo/demo_models.dart';
import '../l10n/generated/app_localizations.dart';
import 'farm_card.dart';
import 'illustrations.dart';
import 'motion.dart';

/// Localized label for a demo animal category (UI reads arb strings; the
/// model's `viLabel` stays for demo-data output outside the UI layer).
String animalCategoryLabel(AppLocalizations l10n, DemoAnimalCategory category) =>
    switch (category) {
      DemoAnimalCategory.cows => l10n.animalCategoryCows,
      DemoAnimalCategory.chickens => l10n.animalCategoryChickens,
      DemoAnimalCategory.sheep => l10n.animalCategorySheep,
      DemoAnimalCategory.goats => l10n.animalCategoryGoats,
    };

/// Localized label for a herd's tracking mode.
String herdModeLabel(AppLocalizations l10n, DemoHerdMode mode) =>
    switch (mode) {
      DemoHerdMode.tracked => l10n.herdModeTracked,
      DemoHerdMode.batch => l10n.herdModeBatch,
    };

/// Localized label for an animal lifecycle status.
String animalStatusLabel(AppLocalizations l10n, DemoAnimalStatus status) =>
    switch (status) {
      DemoAnimalStatus.alive => l10n.animalStatusAlive,
      DemoAnimalStatus.sold => l10n.animalStatusSold,
      DemoAnimalStatus.deceased => l10n.animalStatusDeceased,
    };

/// Category selector card (reference livestock screen): square card with the
/// animal portrait, headcount and label; doubles as the herd filter.
class AnimalCategoryCard extends StatelessWidget {
  const AnimalCategoryCard({
    required this.category,
    required this.count,
    required this.selected,
    required this.onSelected,
    super.key,
  });

  final DemoAnimalCategory category;
  final int count;
  final bool selected;
  final ValueChanged<bool> onSelected;

  @override
  Widget build(BuildContext context) {
    final tokens = FarmThemeExtension.of(context);
    final l10n = AppLocalizations.of(context);
    final categoryLabel = animalCategoryLabel(l10n, category);
    return Semantics(
      button: true,
      selected: selected,
      label: l10n.animalGroupSemantics(categoryLabel, count),
      child: SizedBox(
        width: 96,
        child: Material(
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
            onTap: () => onSelected(!selected),
            child: Padding(
              padding: const EdgeInsets.symmetric(
                vertical: FarmSpacing.sm,
                horizontal: FarmSpacing.sm,
              ),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  AnimalPortrait(category: category, size: 44),
                  const SizedBox(height: FarmSpacing.sm),
                  Text(
                    '$count',
                    style: Theme.of(context).textTheme.titleMedium,
                  ),
                  Text(
                    categoryLabel,
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
        ),
      ),
    );
  }
}

/// Animal card with cartoon portrait — contract master fields only (tag,
/// name, birthDate, status); no fabricated weight or health metric.
class AnimalCard extends StatelessWidget {
  const AnimalCard({required this.animal, super.key});

  final DemoAnimal animal;

  @override
  Widget build(BuildContext context) {
    final tokens = FarmThemeExtension.of(context);
    final l10n = AppLocalizations.of(context);
    final alive = animal.status == DemoAnimalStatus.alive;
    final birth = animal.birthDate;
    final displayBirth = formatDisplayDate(birth, l10n.localeName);
    final dateLine = birth == null
        ? l10n.noBirthDate
        : l10n.bornOn(displayBirth!);
    return Semantics(
      container: true,
      label: l10n.animalSemantics(
        animal.name,
        animal.tag,
        animalCategoryLabel(l10n, animal.category),
        birth == null ? l10n.noBirthDate : l10n.bornOnShort(displayBirth!),
        animalStatusLabel(l10n, animal.status),
      ),
      child: FarmCard(
        child: Row(
          children: [
            AnimalPortrait(category: animal.category),
            const SizedBox(width: FarmSpacing.lg),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    animal.name,
                    style: Theme.of(context).textTheme.titleSmall,
                    softWrap: true,
                  ),
                  Text(
                    '${l10n.animalTagLine(animal.tag)} · $dateLine',
                    style: Theme.of(context).textTheme.bodySmall?.copyWith(
                      color: tokens.textSecondary,
                    ),
                    softWrap: true,
                  ),
                  const SizedBox(height: FarmSpacing.xs),
                  Chip(
                    label: Text(animalStatusLabel(l10n, animal.status)),
                    visualDensity: VisualDensity.compact,
                    side: BorderSide.none,
                    backgroundColor: alive
                        ? tokens.brandSage.withValues(alpha: 0.4)
                        : tokens.textSecondary.withValues(alpha: 0.18),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Today's feeding slots as a horizontal timeline (reference livestock
/// screen): status circle + time + feed label + state caption per slot, with
/// the fraction always rendered as text (non-color-only).
class FeedingTimeline extends StatelessWidget {
  const FeedingTimeline({required this.entries, super.key});

  final List<DemoFeedingEntry> entries;

  @override
  Widget build(BuildContext context) {
    final tokens = FarmThemeExtension.of(context);
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        for (var i = 0; i < entries.length; i++) ...[
          if (i > 0)
            Padding(
              padding: const EdgeInsets.only(top: 13),
              child: SizedBox(
                width: FarmSpacing.md,
                child: Divider(height: 2, thickness: 2, color: tokens.divider),
              ),
            ),
          Expanded(
            child: FarmEntrance(
              delay: Duration(milliseconds: 70 * i),
              child: _FeedingSlot(entry: entries[i], tokens: tokens),
            ),
          ),
        ],
      ],
    );
  }
}

class _FeedingSlot extends StatelessWidget {
  const _FeedingSlot({required this.entry, required this.tokens});

  final DemoFeedingEntry entry;
  final FarmThemeExtension tokens;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final finished = entry.total > 0 && entry.done == entry.total;
    final started = entry.done > 0 && !finished;
    final stateLabel = finished
        ? l10n.feedingDoneLabel
        : started
        ? l10n.feedingStartedLabel
        : l10n.feedingUpcomingLabel;
    return Semantics(
      container: true,
      label: l10n.feedingSlotSemantics(
        animalCategoryLabel(l10n, entry.category),
        entry.timeLabel,
        entry.feedLabel,
        entry.done,
        entry.total,
        stateLabel,
      ),
      child: Column(
        children: [
          Container(
            width: 26,
            height: 26,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: finished ? tokens.brandAction : Colors.transparent,
              border: Border.all(
                color: finished ? tokens.brandAction : tokens.textSecondary,
                width: 1.6,
              ),
            ),
            child: finished
                // Finished slots pop their check in after the circle fills;
                // reduced motion shows the check immediately.
                ? TweenAnimationBuilder<double>(
                    tween: Tween(begin: 0, end: 1),
                    duration: context.farmReducedMotion()
                        ? Duration.zero
                        : FarmSpacing.entrance,
                    curve: Curves.easeOutBack,
                    builder: (context, value, _) => Transform.scale(
                      scale: value,
                      child: const Icon(
                        Icons.check,
                        size: 16,
                        color: Colors.white,
                      ),
                    ),
                  )
                : started
                ? Icon(Icons.more_horiz, size: 16, color: tokens.textSecondary)
                : null,
          ),
          const SizedBox(height: FarmSpacing.xs),
          Text(
            entry.timeLabel,
            style: Theme.of(context).textTheme.labelLarge,
          ),
          Text(
            entry.feedLabel,
            style: Theme.of(context).textTheme.bodySmall?.copyWith(
              color: tokens.textSecondary,
            ),
            textAlign: TextAlign.center,
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
          ),
          const SizedBox(height: 2),
          Text(
            '${entry.done}/${entry.total} · $stateLabel',
            style: Theme.of(context).textTheme.labelSmall?.copyWith(
              color: finished ? tokens.brandAction : tokens.textSecondary,
            ),
            textAlign: TextAlign.center,
          ),
        ],
      ),
    );
  }
}
