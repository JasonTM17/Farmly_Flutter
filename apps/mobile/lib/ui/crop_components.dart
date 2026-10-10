import 'package:flutter/material.dart';

import '../core/theme/farmly_spacing.dart';
import '../core/theme/farmly_theme_extension.dart';
import '../features/demo/demo_models.dart';
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
    final percent = crop.manualProgressPercent;
    final dateSummary = <String>[
      if (crop.sowedOn != null) 'gieo ${crop.sowedOn}',
      if (crop.expectedHarvestOn != null)
        'dự kiến thu ${crop.expectedHarvestOn}'
      else
        'chưa có ngày thu dự kiến',
    ].join(', ');
    final semantics =
        'Cây trồng ${crop.species}'
        '${zoneName == null ? '' : ' ở vùng $zoneName'}, '
        '${dateSummary.isEmpty ? 'chưa ghi lịch gieo/thu' : dateSummary}, '
        '${crop.ended ? 'đã kết thúc, ' : ''}'
        '${percent == null ? 'chưa có đánh giá tiến độ' : 'tiến độ $percent% theo ${crop.assessmentSource ?? 'đánh giá thủ công'}'}';

    return Semantics(
      container: true,
      button: onTap != null,
      label: onTap == null ? semantics : '$semantics. Mở chi tiết.',
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
                      'Chưa có đánh giá tiến độ — cập nhật thủ công',
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
                      crop.assessmentSource ?? 'Đánh giá thủ công',
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
              dateSummary.isEmpty ? 'Chưa ghi lịch gieo/thu' : dateSummary,
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
