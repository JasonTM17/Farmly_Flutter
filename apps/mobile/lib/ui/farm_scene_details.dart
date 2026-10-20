import 'package:flutter/material.dart';

import '../core/theme/farmly_colors.dart';
import '../features/demo/demo_models.dart';
import '../l10n/generated/app_localizations.dart';
import 'farm_scene_accents.dart';
import 'motion.dart';

/// Inspectable scenery, separate from the farm's operational zone records.
Future<void> showFarmMeadow(
  BuildContext context, {
  VoidCallback? onOpenAnimals,
}) {
  final vi = AppLocalizations.of(context).localeName.startsWith('vi');
  return showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    showDragHandle: true,
    useSafeArea: true,
    builder: (sheetContext) => FractionallySizedBox(
      heightFactor: 0.72,
      child: SafeArea(
        top: false,
        child: SingleChildScrollView(
          key: const ValueKey('farm-meadow-sheet'),
          padding: const EdgeInsets.fromLTRB(20, 0, 20, 24),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Row(
                children: [
                  Expanded(
                    child: Text(
                      vi ? 'Đồng cỏ' : 'Meadow',
                      style: Theme.of(context).textTheme.headlineSmall,
                    ),
                  ),
                  IconButton(
                    tooltip: vi ? 'Đóng' : 'Close',
                    onPressed: () => Navigator.pop(sheetContext),
                    icon: const Icon(Icons.close),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              ClipRRect(
                borderRadius: BorderRadius.circular(24),
                child: ColoredBox(
                  color: FarmlyColors.brandSage.withValues(alpha: 0.22),
                  child: AspectRatio(
                    aspectRatio: 1.45,
                    child: FarmAmbientLoop(
                      builder: (_, phase) =>
                          CustomPaint(painter: FarmMeadowPainter(phase: phase)),
                    ),
                  ),
                ),
              ),
              const SizedBox(height: 20),
              Text(
                vi
                    ? 'Một góc xanh của nông trại'
                    : 'A green corner of the farm',
                style: Theme.of(context).textTheme.titleMedium,
              ),
              const SizedBox(height: 8),
              Text(
                vi
                    ? 'Bò thong thả đi dạo, cỏ đung đưa trong gió. Bạn có thể quan sát chuyển động ở cự ly gần.'
                    : 'Watch the cows stroll and the grass sway in the breeze, up close.',
                style: Theme.of(context).textTheme.bodyMedium,
              ),
              if (onOpenAnimals != null) ...[
                const SizedBox(height: 24),
                FilledButton.icon(
                  onPressed: () {
                    Navigator.pop(sheetContext);
                    onOpenAnimals();
                  },
                  icon: const Icon(Icons.pets_outlined),
                  label: Text(vi ? 'Xem vật nuôi' : 'View livestock'),
                ),
              ],
            ],
          ),
        ),
      ),
    ),
  );
}

/// Building-specific information avoids treating infrastructure as empty crops.
class FarmBuildingInfo extends StatelessWidget {
  const FarmBuildingInfo({required this.kind, super.key});
  final DemoZoneKind kind;

  @override
  Widget build(BuildContext context) {
    final vi = AppLocalizations.of(context).localeName.startsWith('vi');
    final storage = kind == DemoZoneKind.storage;
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Icon(
              storage ? Icons.handyman_outlined : Icons.home_work_outlined,
              color: FarmlyColors.brandAction,
              size: 28,
            ),
            const SizedBox(height: 12),
            Text(
              storage
                  ? (vi ? 'Không gian dụng cụ & vật tư' : 'Tools & supplies')
                  : (vi
                        ? 'Không gian làm việc của nông trại'
                        : 'Farm workspace'),
              style: Theme.of(context).textTheme.titleMedium,
            ),
            const SizedBox(height: 8),
            Text(
              storage
                  ? (vi
                        ? 'Khu bảo quản nông cụ, sắp xếp vật tư và chuẩn bị cho công việc đồng áng.'
                        : 'A place to store tools, organize supplies and prepare for field work.')
                  : (vi
                        ? 'Khu sơ chế và làm việc. Theo dõi việc cần làm, bảo dưỡng và ghi chú của khu ở bên dưới.'
                        : 'A place for preparation and farm work. Find tasks, maintenance and notes below.'),
            ),
          ],
        ),
      ),
    );
  }
}
