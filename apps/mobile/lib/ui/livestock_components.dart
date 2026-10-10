import 'package:flutter/material.dart';

import '../core/theme/farmly_spacing.dart';
import '../core/theme/farmly_theme_extension.dart';
import '../features/demo/demo_models.dart';
import 'farm_card.dart';
import 'illustrations.dart';
import 'motion.dart';

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
    return Semantics(
      button: true,
      selected: selected,
      label: 'Nhóm ${category.viLabel}, $count con',
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
                    category.viLabel,
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
    final alive = animal.status == DemoAnimalStatus.alive;
    final birth = animal.birthDate;
    final dateLine = birth == null ? 'Chưa ghi ngày sinh' : 'Sinh $birth';
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
    final finished = entry.total > 0 && entry.done == entry.total;
    final started = entry.done > 0 && !finished;
    final stateLabel = finished
        ? 'Xong'
        : started
        ? 'Đang làm'
        : 'Sắp tới';
    return Semantics(
      container: true,
      label:
          'Cho ăn ${entry.category.viLabel} lúc ${entry.timeLabel}, '
          '${entry.feedLabel}: đã cho ${entry.done} trên ${entry.total} lượt — '
          '$stateLabel',
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
