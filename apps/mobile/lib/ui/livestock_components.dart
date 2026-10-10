import 'package:flutter/material.dart';

import '../core/theme/farmly_spacing.dart';
import '../core/theme/farmly_theme_extension.dart';
import '../features/demo/demo_models.dart';
import 'farm_card.dart';
import 'illustrations.dart';

/// Category filter chip (Cows / Chickens / Sheep / Goats) with count.
class AnimalCategoryChip extends StatelessWidget {
  const AnimalCategoryChip({
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
    return Semantics(
      button: true,
      selected: selected,
      label: 'Nhóm ${category.viLabel}, $count con',
      child: ChoiceChip(
        label: Text('${category.viLabel} ($count)'),
        selected: selected,
        onSelected: onSelected,
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
    final alive = animal.status == DemoAnimalStatus.alive;
    final birth = animal.birthDate;
    final dateLine = birth == null
        ? 'Chưa ghi ngày sinh'
        : 'Sinh $birth';
    return Semantics(
      container: true,
      label:
          '${animal.name}, thẻ ${animal.tag}, nhóm ${animal.category.viLabel}, '
          '${birth == null ? 'chưa ghi ngày sinh' : 'sinh $birth'}, '
          'trạng thái ${animal.status.viLabel}',
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
                    'Thẻ ${animal.tag} · $dateLine',
                    style: Theme.of(context).textTheme.bodySmall?.copyWith(
                      color: tokens.textSecondary,
                    ),
                    softWrap: true,
                  ),
                  const SizedBox(height: FarmSpacing.xs),
                  Chip(
                    label: Text(animal.status.viLabel),
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

/// Today's feeding timeline with done/total progress (non-color-only: the
/// fraction text always accompanies the bar).
class FeedingTimeline extends StatelessWidget {
  const FeedingTimeline({required this.entries, super.key});

  final List<DemoFeedingEntry> entries;

  @override
  Widget build(BuildContext context) {
    final tokens = FarmThemeExtension.of(context);
    return Column(
      children: entries
          .map(
            (entry) => Padding(
              padding: const EdgeInsets.only(bottom: FarmSpacing.md),
              child: Semantics(
                container: true,
                label:
                    'Cho ăn ${entry.category.viLabel} lúc ${entry.timeLabel}, '
                    '${entry.feedLabel}: đã cho ${entry.done} trên ${entry.total} lượt',
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        SizedBox(
                          width: 48,
                          child: Text(
                            entry.timeLabel,
                            style: Theme.of(context).textTheme.labelLarge,
                          ),
                        ),
                        const SizedBox(width: FarmSpacing.sm),
                        Expanded(
                          child: Text(
                            '${entry.category.viLabel} · ${entry.feedLabel}',
                            style: Theme.of(context).textTheme.bodyMedium,
                            softWrap: true,
                          ),
                        ),
                        Text(
                          '${entry.done}/${entry.total}',
                          style: Theme.of(context).textTheme.titleSmall,
                        ),
                      ],
                    ),
                    const SizedBox(height: FarmSpacing.xs),
                    ClipRRect(
                      borderRadius: BorderRadius.circular(FarmSpacing.xs),
                      child: LinearProgressIndicator(
                        value: entry.total == 0
                            ? 0
                            : entry.done / entry.total,
                        minHeight: 6,
                        backgroundColor: tokens.brandSage,
                        color: entry.done == entry.total
                            ? tokens.brandAction
                            : tokens.semanticWarning,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          )
          .toList(),
    );
  }
}
