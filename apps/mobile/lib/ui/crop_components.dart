import 'package:flutter/material.dart';

import '../core/format/display_format.dart';
import '../core/theme/farmly_spacing.dart';
import '../core/theme/farmly_theme_extension.dart';
import '../features/demo/demo_models.dart';
import '../l10n/generated/app_localizations.dart';
import 'farm_card.dart';

/// Crop progress card. Missing manual assessment renders the explicit
/// "unknown" state, never a guessed percentage (spec 02 §5).
class CropProgressCard extends StatelessWidget {
  const CropProgressCard({
    required this.crop,
    this.zoneName,
    this.onTap,
    super.key,
  });

  final DemoCrop crop;
  final String? zoneName;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final tokens = FarmThemeExtension.of(context);
    final l10n = AppLocalizations.of(context);
    final percent = crop.manualProgressPercent;
    final dateSummary = <String>[
      if (crop.sowedOn != null)
        l10n.sowedOnShort(formatDisplayDate(crop.sowedOn, l10n.localeName)!),
      if (crop.expectedHarvestOn != null)
        l10n.expectedHarvestOn(
          formatDisplayDate(crop.expectedHarvestOn, l10n.localeName)!,
        )
      else
        l10n.noExpectedHarvest,
    ].join(', ');
    final semantics =
        '${l10n.cropSemanticsLead(crop.species)}'
        '${zoneName == null ? '' : l10n.cropSemanticsZoneSuffix(zoneName!)}, '
        '${dateSummary.isEmpty ? l10n.noScheduleShort : dateSummary}, '
        '${crop.ended ? '${l10n.cropEndedShort}, ' : ''}'
        '${percent == null ? l10n.noProgressShort : l10n.cropProgressSemantics(percent, crop.assessmentSource ?? l10n.manualAssessment)}';

    return Semantics(
      container: true,
      button: onTap != null,
      label: onTap == null ? semantics : '$semantics${l10n.openDetailSuffix}',
      child: FarmCard(
        onTap: onTap,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Expanded(
                  child: Text(
                    crop.species,
                    style: Theme.of(context).textTheme.titleSmall,
                    softWrap: true,
                  ),
                ),
                if (zoneName != null)
                  Text(
                    zoneName!,
                    style: Theme.of(context).textTheme.labelMedium?.copyWith(
                      color: tokens.textSecondary,
                    ),
                    softWrap: true,
                  ),
              ],
            ),
            const SizedBox(height: FarmSpacing.sm),
            if (percent == null)
              Row(
                children: [
                  Icon(
                    Icons.help_outline,
                    size: 16,
                    color: tokens.semanticWarning,
                  ),
                  const SizedBox(width: FarmSpacing.xs),
                  Expanded(
                    child: Text(
                      l10n.noProgressUpdateHint,
                      style: Theme.of(context).textTheme.bodySmall?.copyWith(
                        color: tokens.semanticWarning,
                      ),
                      softWrap: true,
                    ),
                  ),
                ],
              )
            else ...[
              Row(
                children: [
                  Text(
                    '$percent%',
                    style: Theme.of(context).textTheme.titleMedium,
                  ),
                  const SizedBox(width: FarmSpacing.sm),
                  Expanded(
                    child: Text(
                      crop.assessmentSource ?? l10n.manualAssessment,
                      style: Theme.of(context).textTheme.bodySmall?.copyWith(
                        color: tokens.textSecondary,
                      ),
                      softWrap: true,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: FarmSpacing.xs),
              ClipRRect(
                borderRadius: BorderRadius.circular(FarmSpacing.xs),
                child: LinearProgressIndicator(
                  value: percent / 100,
                  minHeight: 6,
                  backgroundColor: tokens.brandSage,
                ),
              ),
            ],
            const SizedBox(height: FarmSpacing.sm),
            Text(
              dateSummary.isEmpty ? l10n.noScheduleShort : dateSummary,
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
