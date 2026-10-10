import 'package:flutter/material.dart';

import '../core/theme/farmly_spacing.dart';
import '../core/theme/farmly_colors.dart';
import '../core/theme/farmly_theme_extension.dart';
import '../l10n/generated/app_localizations.dart';

/// Base card: surface fill, hairline divider border, radius 20, no shadow —
/// the single depth strategy of the app (spec 02 §2).
class FarmCard extends StatelessWidget {
  const FarmCard({
    required this.child,
    this.padding = const EdgeInsets.all(FarmSpacing.lg),
    this.onTap,
    this.semanticsLabel,
    super.key,
  });

  final Widget child;
  final EdgeInsetsGeometry padding;
  final VoidCallback? onTap;
  final String? semanticsLabel;

  @override
  Widget build(BuildContext context) {
    final content = Padding(padding: padding, child: child);
    return Card(
      child: semanticsLabel != null
          ? Semantics(
              label: semanticsLabel,
              container: true,
              child: onTap == null
                  ? content
                  : InkWell(onTap: onTap, child: content),
            )
          : onTap == null
          ? content
          : InkWell(onTap: onTap, child: content),
    );
  }
}

/// Compact 2x2 grid metric with full semantic meaning (value + unit).
class StatTile extends StatelessWidget {
  const StatTile({
    required this.label,
    required this.value,
    required this.icon,
    this.unitLabel,
    this.semanticValue,
    super.key,
  });

  final String label;
  final String value;
  final IconData icon;
  final String? unitLabel;
  final String? semanticValue;

  @override
  Widget build(BuildContext context) {
    final tokens = FarmThemeExtension.of(context);
    return Semantics(
      label:
          '$label: ${semanticValue ?? value}'
          '${unitLabel == null ? '' : ' $unitLabel'}',
      child: FarmCard(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 20, color: tokens.brandAction),
            const SizedBox(height: FarmSpacing.sm),
            Text(value, style: Theme.of(context).textTheme.titleLarge),
            Text(
              unitLabel == null ? label : '$label ($unitLabel)',
              style: Theme.of(
                context,
              ).textTheme.bodySmall?.copyWith(color: tokens.textSecondary),
              softWrap: true,
            ),
          ],
        ),
      ),
    );
  }
}

/// "Dữ liệu đến … · nguồn …" metadata line (spec 02 §5/§7).
class AsOfLabel extends StatelessWidget {
  const AsOfLabel({required this.asOf, required this.source, super.key});

  final String asOf;
  final String source;

  @override
  Widget build(BuildContext context) {
    final tokens = FarmThemeExtension.of(context);
    final l10n = AppLocalizations.of(context);
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(Icons.schedule, size: 14, color: tokens.textSecondary),
        const SizedBox(width: FarmSpacing.xs),
        Flexible(
          child: Text(
            l10n.asOfSource(asOf, source),
            style: Theme.of(
              context,
            ).textTheme.bodySmall?.copyWith(color: tokens.textSecondary),
            softWrap: true,
          ),
        ),
      ],
    );
  }
}

/// Sync state pill; tapping opens the Sync Center (spec 02 §7).
class SyncStatusBadge extends StatelessWidget {
  const SyncStatusBadge({
    required this.pendingCount,
    this.conflictCount = 0,
    this.onTap,
    super.key,
  });

  final int pendingCount;
  final int conflictCount;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final tokens = FarmThemeExtension.of(context);
    final l10n = AppLocalizations.of(context);
    final pendingDescription = l10n.syncPendingDescription(pendingCount);
    final conflictDescription = l10n.syncConflictDescription(conflictCount);
    final label = conflictCount > 0
        ? '$pendingDescription, $conflictDescription'
        : pendingDescription;
    final text = conflictCount > 0
        ? '${l10n.syncPendingShort(pendingCount)} · '
              '${l10n.syncConflictShort(conflictCount)}'
        : l10n.syncPendingShort(pendingCount);
    return Semantics(
      button: true,
      label: l10n.syncStatusDescription(label),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(FarmSpacing.md),
        child: Container(
          constraints: const BoxConstraints(
            minHeight: FarmSpacing.minTouchTarget,
          ),
          padding: const EdgeInsets.symmetric(horizontal: FarmSpacing.md),
          decoration: BoxDecoration(
            color: tokens.surface,
            borderRadius: BorderRadius.circular(FarmSpacing.md),
            border: Border.all(
              color: conflictCount > 0
                  ? tokens.semanticWarning
                  : tokens.divider,
            ),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(
                conflictCount > 0
                    ? Icons.warning_amber_outlined
                    : Icons.cloud_upload_outlined,
                size: 18,
                color: conflictCount > 0
                    ? tokens.semanticWarning
                    : tokens.brandAction,
              ),
              const SizedBox(width: FarmSpacing.xs),
              Flexible(
                child: Text(
                  text,
                  style: Theme.of(context).textTheme.labelMedium?.copyWith(
                    color: conflictCount > 0
                        ? tokens.semanticWarning
                        : FarmlyColors.textPrimary,
                  ),
                  softWrap: true,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
