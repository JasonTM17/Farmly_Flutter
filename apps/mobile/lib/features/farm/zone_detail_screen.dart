import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/theme/farmly_spacing.dart';
import '../../core/theme/farmly_theme_extension.dart';
import '../../ui/farm_card.dart';
import '../../ui/form_fields.dart';
import '../../ui/zone_explorer.dart';
import '../../ui/pickers.dart';
import '../../ui/screen_states.dart';
import '../app/app_router.dart';
import '../app/app_routes.dart';
import '../demo/demo_models.dart';
import '../demo/demo_providers.dart';

/// Crop zone detail: illustrated bed, crop label, manual assessment, tasks and
/// notes. Unknown progress stays explicit; read-only and conflict states are
/// reachable through the demo switcher (spec 02 §5).
class ZoneDetailScreen extends ConsumerWidget {
  const ZoneDetailScreen({required this.zoneId, super.key});

  final String? zoneId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final state = ref.watch(demoDataProvider);
    final zones = zonesOfFarm(state, state.selectedFarmId);
    final zone = zones.where((candidate) => candidate.id == zoneId).firstOrNull;
    final crops = zone == null
        ? const <DemoCrop>[]
        : cropsOfZone(state, zone.id);
    final tasks = zone == null
        ? const <DemoTask>[]
        : tasksOfZone(state, zone.id);
    final screenState = effectiveDemoState(
      ref,
      'zone-detail',
      dataEmpty: zone == null,
    );
    final readOnly = screenState == DemoLoadState.permissionDenied;

    return Scaffold(
      backgroundColor: Theme.of(context).scaffoldBackgroundColor,
      appBar: AppBar(
        title: Text(zone?.name ?? 'Chi tiết vùng'),
        // Contextual AI entry from the zone toolbar (spec 02 §3).
        actions: [
          Semantics(
            button: true,
            label: 'Hỏi Farmly AI. Mở trợ lý AI đọc dữ liệu trang trại.',
            child: IconButton(
              tooltip: 'Hỏi Farmly AI',
              icon: const Icon(Icons.forum_outlined),
              onPressed: () => openContextualChat(context, ref),
            ),
          ),
        ],
      ),
      body: SafeArea(
        child: switch (screenState) {
          DemoLoadState.loading => const _ZoneDetailSkeleton(),
          DemoLoadState.recoverableError => FarmErrorView(
            onRetry: () =>
                ref.read(demoScreenStateProvider.notifier).reset('zone-detail'),
            onSwitchScope: () => showFarmPickerSheet(context),
          ),
          DemoLoadState.permissionDenied => PermissionDeniedView(
            message:
                'Bạn chỉ có quyền xem vùng này — mọi nút ghi đã bị khóa. '
                'Liên hệ chủ nông trại để được quyền ghi.',
            onSwitchScope: () => showFarmPickerSheet(context),
          ),
          DemoLoadState.empty => EmptyStateView(
            title: 'Không tìm thấy vùng',
            message: 'Vùng này có thể đã bị lưu trữ hoặc thuộc phạm vi khác.',
            actionLabel: 'Đổi nông trại',
            onAction: () => showFarmPickerSheet(context),
          ),
          DemoLoadState.offline ||
          DemoLoadState.pendingConflict ||
          DemoLoadState.success => ListView(
            padding: const EdgeInsets.all(FarmSpacing.lg),
            children: [
              if (screenState == DemoLoadState.offline) ...[
                const OfflineBanner(asOf: '06:30'),
                const SizedBox(height: FarmSpacing.md),
              ],
              if (screenState == DemoLoadState.pendingConflict) ...[
                PendingConflictBanner(
                  count: 1,
                  onOpen: () => context.push(AppRoutes.syncCenter),
                ),
                const SizedBox(height: FarmSpacing.md),
              ],
              // Iso tile hero — the same tile the map renders, zoomed.
              if (zone != null)
                ExcludeSemantics(
                  child: ClipRRect(
                    borderRadius: BorderRadius.circular(FarmSpacing.cardRadius),
                    child: Container(
                      height: 190,
                      color: Color.lerp(
                        FarmThemeExtension.of(context).brandSage,
                        FarmThemeExtension.of(context).background,
                        0.55,
                      ),
                      alignment: Alignment.center,
                      padding: const EdgeInsets.only(top: FarmSpacing.lg),
                      child: SizedBox(
                        width: 240,
                        height: 150,
                        child: CustomPaint(
                          painter: IsoZoneTilePainter(
                            kind: zone.kind,
                            selected: false,
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
              const SizedBox(height: FarmSpacing.md),
              if (zone != null) _ZoneSummaryCard(zone: zone, crops: crops),
              const SizedBox(height: FarmSpacing.md),
              if (zone?.kind == DemoZoneKind.water) ...[
                _WaterTankSection(
                  zone: zone!,
                  tank: tankOfZone(state, zone.id),
                  readOnly: readOnly,
                ),
                const SizedBox(height: FarmSpacing.md),
              ] else if (zone?.kind == DemoZoneKind.livestock) ...[
                _LivestockZoneSection(zone: zone!),
                const SizedBox(height: FarmSpacing.md),
              ] else ...[
                for (final crop in crops)
                  Padding(
                    padding: const EdgeInsets.only(bottom: FarmSpacing.md),
                    child: _CropAssessmentSection(
                      crop: crop,
                      readOnly: readOnly,
                      pending: syncItemPending(state, 'sync-assess-${crop.id}'),
                    ),
                  ),
                if (crops.isEmpty)
                  FarmCard(
                    child: Text(
                      'Vùng này chưa có cây trồng đang theo dõi.',
                      style: Theme.of(context).textTheme.bodyMedium,
                      softWrap: true,
                    ),
                  ),
                const SizedBox(height: FarmSpacing.md),
              ],
              FarmCard(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Công việc',
                      style: Theme.of(context).textTheme.titleSmall,
                    ),
                    const SizedBox(height: FarmSpacing.sm),
                    if (tasks.isEmpty)
                      Text(
                        'Chưa có việc nào cho vùng này hôm nay.',
                        style: Theme.of(context).textTheme.bodySmall?.copyWith(
                          color: FarmThemeExtension.of(context).textSecondary,
                        ),
                        softWrap: true,
                      )
                    else
                      for (final task in tasks)
                        _TaskOccurrenceTile(task: task, readOnly: readOnly),
                    const SizedBox(height: FarmSpacing.sm),
                    OutlinedButton.icon(
                      onPressed: readOnly || zone == null
                          ? null
                          : () => _openTaskDraftSheet(context, ref, zone.id),
                      icon: const Icon(Icons.add_task_outlined),
                      label: const Text('Thêm việc'),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: FarmSpacing.md),
              FarmCard(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Ghi chú',
                      style: Theme.of(context).textTheme.titleSmall,
                    ),
                    const SizedBox(height: FarmSpacing.sm),
                    Text(
                      'Ghi chú của bạn được lưu trên thiết bị trước, rồi đồng '
                      'bộ khi có mạng.',
                      style: Theme.of(context).textTheme.bodySmall?.copyWith(
                        color: FarmThemeExtension.of(context).textSecondary,
                      ),
                      softWrap: true,
                    ),
                  ],
                ),
              ),
            ],
          ),
        },
      ),
    );
  }
}

class _CropAssessmentSection extends ConsumerWidget {
  const _CropAssessmentSection({
    required this.crop,
    required this.readOnly,
    required this.pending,
  });

  final DemoCrop crop;
  final bool readOnly;

  /// True while the assessment write sits in the local outbox (spec 02 §7).
  final bool pending;

  Future<void> _recordMoisture(BuildContext context, WidgetRef ref) async {
    final entered = await showDialog<String>(
      context: context,
      builder: (_) => const _MoistureDialog(),
    );
    final percent = entered?.trim().replaceAll(',', '.') ?? '';
    if (percent.isEmpty) return;
    ref
        .read(demoDataProvider.notifier)
        .recordMoisture(
          crop.zoneId,
          valuePercent: percent,
          method: 'đo tay',
          asOf: 'vừa xong',
        );
    if (!context.mounted) return;
    showFarmToast(context, 'Đã lưu trên thiết bị');
  }

  Future<void> _openAssessmentDialog(
    BuildContext context,
    WidgetRef ref,
  ) async {
    var value = (crop.manualProgressPercent ?? 0).toDouble();
    final saved = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => StatefulBuilder(
        builder: (dialogContext, setDialogState) => AlertDialog(
          title: const Text('Đánh giá thủ công'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                'Tiến độ ${crop.species}: ${value.round()}%',
                style: Theme.of(dialogContext).textTheme.bodyMedium,
              ),
              Slider(
                value: value,
                min: 0,
                max: 100,
                divisions: 20,
                label: '${value.round()}%',
                onChanged: (next) => setDialogState(() => value = next),
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(dialogContext).pop(false),
              child: const Text('Hủy'),
            ),
            FilledButton(
              onPressed: () => Navigator.of(dialogContext).pop(true),
              child: const Text('Lưu đánh giá'),
            ),
          ],
        ),
      ),
    );
    if (saved != true) return;
    ref
        .read(demoDataProvider.notifier)
        .setCropAssessment(crop.id, value.round());
    if (!context.mounted) return;
    showFarmToast(context, 'Đã lưu trên thiết bị');
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final tokens = FarmThemeExtension.of(context);
    final percent = crop.manualProgressPercent;

    final dateParts = <String>[
      if (crop.sowedOn != null) 'Gieo ${crop.sowedOn}',
      if (crop.expectedHarvestOn != null)
        'dự kiến thu ${crop.expectedHarvestOn}'
      else
        'chưa có ngày thu dự kiến',
    ];

    return FarmCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  crop.species,
                  style: Theme.of(context).textTheme.titleMedium,
                  softWrap: true,
                ),
              ),
              if (crop.ended)
                Chip(
                  label: const Text('Đã kết thúc'),
                  visualDensity: VisualDensity.compact,
                  backgroundColor: tokens.brandSage.withValues(alpha: 0.4),
                  side: BorderSide.none,
                )
              else if (pending)
                Chip(
                  avatar: Icon(
                    Icons.schedule,
                    size: 14,
                    color: tokens.textSecondary,
                  ),
                  label: const Text('Chờ đồng bộ'),
                  visualDensity: VisualDensity.compact,
                  side: BorderSide.none,
                ),
            ],
          ),
          const SizedBox(height: FarmSpacing.xs),
          if (dateParts.isEmpty)
            Row(
              children: [
                Icon(
                  Icons.help_outline,
                  size: 18,
                  color: tokens.semanticWarning,
                ),
                const SizedBox(width: FarmSpacing.xs),
                Expanded(
                  child: Text(
                    'Chưa ghi lịch gieo/thu — không tự suy đoán.',
                    style: Theme.of(context).textTheme.bodySmall?.copyWith(
                      color: tokens.semanticWarning,
                    ),
                    softWrap: true,
                  ),
                ),
              ],
            )
          else
            Text(
              dateParts.join(' · '),
              style: Theme.of(
                context,
              ).textTheme.bodySmall?.copyWith(color: tokens.textSecondary),
              softWrap: true,
            ),
          const SizedBox(height: FarmSpacing.md),
          if (percent == null)
            Row(
              children: [
                Icon(
                  Icons.help_outline,
                  size: 18,
                  color: tokens.semanticWarning,
                ),
                const SizedBox(width: FarmSpacing.xs),
                Expanded(
                  child: Text(
                    'Chưa có đánh giá tiến độ — không tự suy đoán.',
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
          const SizedBox(height: FarmSpacing.md),
          // Manual moisture reading — latest value with provenance; no
          // fabricated live-sensor level (phase 06 step 3, spec 02 readings).
          Builder(
            builder: (context) {
              final moisture = latestMoistureOfZone(
                ref.watch(demoDataProvider),
                crop.zoneId,
              );
              return Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  if (moisture == null)
                    Text(
                      'Chưa có số đo độ ẩm cho vùng này.',
                      style: Theme.of(context).textTheme.bodySmall?.copyWith(
                        color: tokens.textSecondary,
                      ),
                      softWrap: true,
                    )
                  else
                    Text(
                      'Độ ẩm: ${moisture.valuePercent}% '
                      '(${moisture.method}, ${moisture.asOf})',
                      style: Theme.of(context).textTheme.bodySmall,
                      softWrap: true,
                    ),
                  const SizedBox(height: FarmSpacing.sm),
                ],
              );
            },
          ),
          Wrap(
            spacing: FarmSpacing.sm,
            runSpacing: FarmSpacing.sm,
            children: [
              OutlinedButton.icon(
                onPressed: readOnly || crop.ended
                    ? null
                    : () => _openAssessmentDialog(context, ref),
                icon: const Icon(Icons.rate_review_outlined),
                label: Text(
                  crop.ended
                      ? 'Đã kết thúc'
                      : percent == null
                      ? 'Đánh giá'
                      : 'Cập nhật đánh giá',
                ),
              ),
              OutlinedButton.icon(
                onPressed: readOnly || crop.ended
                    ? null
                    : () => _recordMoisture(context, ref),
                icon: const Icon(Icons.water_drop_outlined),
                label: const Text('Đo độ ẩm'),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

/// Water tank panel for a water zone (spec 02 §5, phase 05 step 5 / D-17/18):
/// manual capacity/source/litres/asOf, a deliberate unavailable-reading state,
/// and a Smart watering entry that drafts an irrigation task — it never calls
/// a pump or any actuation endpoint.
class _WaterTankSection extends ConsumerWidget {
  const _WaterTankSection({
    required this.zone,
    required this.tank,
    required this.readOnly,
  });

  final DemoZone zone;
  final DemoWaterTank? tank;
  final bool readOnly;

  Future<void> _recordReading(BuildContext context, WidgetRef ref) async {
    final entered = await showDialog<String>(
      context: context,
      builder: (_) => const _TankReadingDialog(),
    );
    final litres = entered?.trim().replaceAll(',', '.') ?? '';
    if (litres.isEmpty) return;
    ref
        .read(demoDataProvider.notifier)
        .recordTankReading(zone.id, litres, 'vừa xong');
    if (!context.mounted) return;
    showFarmToast(context, 'Đã lưu trên thiết bị');
  }

  Future<void> _recordUsage(BuildContext context, WidgetRef ref) async {
    final entered = await showDialog<String>(
      context: context,
      builder: (_) => const _TankUsageDialog(),
    );
    final litres = entered?.trim().replaceAll(',', '.') ?? '';
    if (litres.isEmpty) return;
    ref
        .read(demoDataProvider.notifier)
        .recordWaterUsage(zone.id, litres: litres);
    if (!context.mounted) return;
    showFarmToast(context, 'Đã lưu trên thiết bị');
  }

  Future<void> _openSmartWatering(BuildContext context, WidgetRef ref) async {
    final created = await showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      builder: (_) => _SmartWateringSheet(zone: zone),
    );
    if (created != true || !context.mounted) return;
    showFarmToast(context, 'Đã lưu việc tưới trên thiết bị');
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final tokens = FarmThemeExtension.of(context);
    final tank = this.tank;

    if (tank == null) {
      return FarmCard(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Chưa có bồn nước nào trong vùng này',
              style: Theme.of(context).textTheme.titleSmall,
            ),
            const SizedBox(height: FarmSpacing.xs),
            Text(
              'Thêm bồn nước để theo dõi mực nước và lượng dùng hằng ngày.',
              style: Theme.of(
                context,
              ).textTheme.bodySmall?.copyWith(color: tokens.textSecondary),
              softWrap: true,
            ),
          ],
        ),
      );
    }

    final stored = tank.storedLitres;
    return FarmCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(tank.name, style: Theme.of(context).textTheme.titleMedium),
          const SizedBox(height: FarmSpacing.xs),
          Text(
            'Dung tích ${tank.capacityLitres} lít',
            style: Theme.of(
              context,
            ).textTheme.bodySmall?.copyWith(color: tokens.textSecondary),
            softWrap: true,
          ),
          const SizedBox(height: FarmSpacing.md),
          if (stored == null)
            Row(
              children: [
                Icon(
                  Icons.help_outline,
                  size: 18,
                  color: tokens.semanticWarning,
                ),
                const SizedBox(width: FarmSpacing.xs),
                Expanded(
                  child: Text(
                    'Chưa có số đo mực nước — không suy đoán mức hiện tại.',
                    style: Theme.of(context).textTheme.bodySmall?.copyWith(
                      color: tokens.semanticWarning,
                    ),
                    softWrap: true,
                  ),
                ),
              ],
            )
          else
            // Metric trio (reference water detail): level % / stored /
            // used-today — each column labeled, never fabricated.
            Builder(
              builder: (context) {
                final storedNum = double.tryParse(stored);
                final capNum = double.tryParse(tank.capacityLitres);
                final level = (storedNum != null && capNum != null && capNum > 0)
                    ? '${(storedNum / capNum * 100).round()}%'
                    : '—';
                return Row(
                  children: [
                    Expanded(
                      child: _TankMetric(label: 'Mực nước', value: level),
                    ),
                    Expanded(
                      child: _TankMetric(label: 'Còn lại', value: '$stored L'),
                    ),
                    Expanded(
                      child: _TankMetric(
                        label: 'Dùng hôm nay',
                        value: tank.usedTodayLitres == null
                            ? '—'
                            : '${tank.usedTodayLitres} L',
                      ),
                    ),
                  ],
                );
              },
            ),
          const SizedBox(height: FarmSpacing.sm),
          AsOfLabel(
            asOf: tank.asOf ?? '—',
            source: tank.source ?? 'thủ công',
          ),
          const SizedBox(height: FarmSpacing.md),
          Wrap(
            spacing: FarmSpacing.sm,
            runSpacing: FarmSpacing.sm,
            children: [
              OutlinedButton.icon(
                onPressed: readOnly ? null : () => _recordReading(context, ref),
                icon: const Icon(Icons.speed_outlined),
                label: const Text('Ghi số đo'),
              ),
              OutlinedButton.icon(
                onPressed: readOnly ? null : () => _recordUsage(context, ref),
                icon: const Icon(Icons.water_outlined),
                label: const Text('Ghi đã dùng'),
              ),
              FilledButton.tonalIcon(
                onPressed: readOnly
                    ? null
                    : () => _openSmartWatering(context, ref),
                icon: const Icon(Icons.water_drop_outlined),
                label: const Text('Smart watering'),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

/// Livestock zone card (phase 05 step 4 / D-05/06): herds are farm-scoped, so
/// this zone view shows the farm headcount summary and links to the herd
/// screen instead of rendering crop cards for a pen.
class _LivestockZoneSection extends ConsumerWidget {
  const _LivestockZoneSection({required this.zone});

  final DemoZone zone;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final tokens = FarmThemeExtension.of(context);
    final state = ref.watch(demoDataProvider);
    final herds = herdsOfFarm(state, zone.farmId);
    final headcount = farmLivestockHeadcount(state, zone.farmId);

    return FarmCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Khu chăn nuôi',
            style: Theme.of(context).textTheme.titleMedium,
          ),
          const SizedBox(height: FarmSpacing.xs),
          Text(
            herds.isEmpty
                ? 'Chưa có đàn nào trong nông trại này.'
                : '${herds.length} đàn · $headcount con đang nuôi',
            style: Theme.of(
              context,
            ).textTheme.bodySmall?.copyWith(color: tokens.textSecondary),
            softWrap: true,
          ),
          const SizedBox(height: FarmSpacing.md),
          Semantics(
            button: true,
            label: 'Mở khu chăn nuôi, $headcount con',
            child: FilledButton.tonalIcon(
              onPressed: () => context.push(AppRoutes.livestock),
              icon: const Icon(Icons.pets_outlined),
              label: const Text('Mở khu chăn nuôi'),
            ),
          ),
        ],
      ),
    );
  }
}

/// Manual-reading dialog: owns its controller so it can dispose safely after
/// the route unmounts (disposing from the caller races the pop animation).
class _TankReadingDialog extends StatefulWidget {
  const _TankReadingDialog();

  @override
  State<_TankReadingDialog> createState() => _TankReadingDialogState();
}

class _TankReadingDialogState extends State<_TankReadingDialog> {
  final _controller = TextEditingController();

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('Ghi số đo thủ công'),
      content: DecimalField(
        controller: _controller,
        autofocus: true,
        labelText: 'Mực nước đọc được (lít)',
        hintText: 'Ví dụ: 3200',
        helperText: 'Số đọc tay từ đồng hồ — không phải cảm biến trực tiếp.',
        onSubmitted: (value) => Navigator.of(context).pop(value),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Hủy'),
        ),
        FilledButton(
          onPressed: () => Navigator.of(context).pop(_controller.text),
          child: const Text('Lưu số đo'),
        ),
      ],
    );
  }
}

/// Smart watering wizard (spec 02 §5 / D-18): drafts an irrigation TASK for a
/// chosen zone/time/volume. Explicitly task planning — the copy states no pump
/// or device is actuated.
class _SmartWateringSheet extends ConsumerStatefulWidget {
  const _SmartWateringSheet({required this.zone});

  final DemoZone zone;

  @override
  ConsumerState<_SmartWateringSheet> createState() =>
      _SmartWateringSheetState();
}

class _SmartWateringSheetState extends ConsumerState<_SmartWateringSheet> {
  final _litresController = TextEditingController();
  final _timeController = TextEditingController(text: '06:00');
  String? _litresError;

  @override
  void dispose() {
    _litresController.dispose();
    _timeController.dispose();
    super.dispose();
  }

  void _save() {
    final litres = _litresController.text.trim().replaceAll(',', '.');
    if (litres.isEmpty) {
      setState(() => _litresError = 'Nhập lượng nước dự kiến (lít).');
      return;
    }
    final time = _timeController.text.trim();
    ref
        .read(demoDataProvider.notifier)
        .addTask(
          DemoTask(
            id: 'task-tuoi-${DateTime.now().microsecondsSinceEpoch}',
            zoneId: widget.zone.id,
            title: 'Tưới $litres lít từ ${widget.zone.name}',
            timeLabel: time.isEmpty ? 'Chưa đặt giờ' : time,
                      ),
        );
    Navigator.of(context).pop(true);
  }

  @override
  Widget build(BuildContext context) {
    final tokens = FarmThemeExtension.of(context);
    return SafeArea(
      child: Padding(
        padding: EdgeInsets.only(
          left: FarmSpacing.lg,
          right: FarmSpacing.lg,
          top: FarmSpacing.sm,
          bottom: FarmSpacing.lg + MediaQuery.of(context).viewInsets.bottom,
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(
              'Lập việc tưới nước',
              style: Theme.of(context).textTheme.titleLarge,
            ),
            const SizedBox(height: FarmSpacing.xs),
            Text(
              'Tạo công việc tưới cho vùng liên quan. Không bật/tắt máy bơm '
              'hay thiết bị nào từ đây.',
              style: Theme.of(
                context,
              ).textTheme.bodySmall?.copyWith(color: tokens.textSecondary),
              softWrap: true,
            ),
            const SizedBox(height: FarmSpacing.lg),
            DecimalField(
              controller: _litresController,
              labelText: 'Lượng nước dự kiến (lít)',
              hintText: 'Ví dụ: 200',
              errorText: _litresError,
            ),
            const SizedBox(height: FarmSpacing.md),
            TextField(
              controller: _timeController,
              decoration: const InputDecoration(
                labelText: 'Giờ dự kiến',
                hintText: 'HH:mm',
              ),
              keyboardType: TextInputType.datetime,
            ),
            const SizedBox(height: FarmSpacing.lg),
            FilledButton(
              onPressed: _save,
              child: const Text('Lưu việc tưới'),
            ),
          ],
        ),
      ),
    );
  }
}

class _ZoneDetailSkeleton extends StatelessWidget {
  const _ZoneDetailSkeleton();

  @override
  Widget build(BuildContext context) {
    return ListView(
      padding: const EdgeInsets.all(FarmSpacing.lg),
      children: const [
        SkeletonSurface(
          width: double.infinity,
          height: 160,
          radius: FarmSpacing.cardRadius,
        ),
        SizedBox(height: FarmSpacing.md),
        SkeletonSurface(
          width: double.infinity,
          height: 120,
          radius: FarmSpacing.cardRadius,
        ),
        SizedBox(height: FarmSpacing.md),
        SkeletonSurface(
          width: double.infinity,
          height: 160,
          radius: FarmSpacing.cardRadius,
        ),
      ],
    );
  }
}

/// Zone task entry (spec 02 §5, phase 05 step 3): drafts a plain zone task.
/// The write lands local-pending through `addTask` — a `task.create` intent
/// enters the demo outbox (spec 02 §7).
Future<void> _openTaskDraftSheet(
  BuildContext context,
  WidgetRef ref,
  String zoneId,
) async {
  final created = await showModalBottomSheet<bool>(
    context: context,
    isScrollControlled: true,
    builder: (_) => _TaskDraftSheet(zoneId: zoneId),
  );
  if (created != true || !context.mounted) return;
  showFarmToast(context, 'Đã lưu trên thiết bị');
}

class _TaskDraftSheet extends ConsumerStatefulWidget {
  const _TaskDraftSheet({required this.zoneId});

  final String zoneId;

  @override
  ConsumerState<_TaskDraftSheet> createState() => _TaskDraftSheetState();
}

class _TaskDraftSheetState extends ConsumerState<_TaskDraftSheet> {
  final _titleController = TextEditingController();
  final _timeController = TextEditingController(text: '06:00');
  String? _titleError;

  @override
  void dispose() {
    _titleController.dispose();
    _timeController.dispose();
    super.dispose();
  }

  void _save() {
    final title = _titleController.text.trim();
    if (title.isEmpty) {
      setState(() => _titleError = 'Nhập tên công việc.');
      return;
    }
    final time = _timeController.text.trim();
    ref
        .read(demoDataProvider.notifier)
        .addTask(
          DemoTask(
            id: 'task-${DateTime.now().microsecondsSinceEpoch}',
            zoneId: widget.zoneId,
            title: title,
            timeLabel: time.isEmpty ? 'Chưa đặt giờ' : time,
                      ),
        );
    Navigator.of(context).pop(true);
  }

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      child: Padding(
        padding: EdgeInsets.only(
          left: FarmSpacing.lg,
          right: FarmSpacing.lg,
          top: FarmSpacing.sm,
          bottom: FarmSpacing.lg + MediaQuery.of(context).viewInsets.bottom,
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(
              'Thêm việc cho vùng',
              style: Theme.of(context).textTheme.titleLarge,
            ),
            const SizedBox(height: FarmSpacing.lg),
            TextField(
              controller: _titleController,
              autofocus: true,
              decoration: InputDecoration(
                labelText: 'Tên công việc',
                hintText: 'Ví dụ: Tưới nhẹ chiều mát',
                errorText: _titleError,
              ),
              textInputAction: TextInputAction.next,
            ),
            const SizedBox(height: FarmSpacing.md),
            TextField(
              controller: _timeController,
              decoration: const InputDecoration(
                labelText: 'Giờ dự kiến',
                hintText: 'HH:mm',
              ),
              keyboardType: TextInputType.datetime,
            ),
            const SizedBox(height: FarmSpacing.lg),
            FilledButton(onPressed: _save, child: const Text('Lưu việc')),
          ],
        ),
      ),
    );
  }
}

/// Task occurrence row (spec 02 §5 task/feeding occurrence): the checkbox is a
/// visible action (not gesture-only), with explicit Hoàn thành / Bỏ qua /
/// Làm lại controls, assignee label, overdue badge, and terminal-status
/// semantics. Transitions route through `transitionTask` — every write lands
/// in the local outbox as a `taskOccurrence.transition` intent.
class _TaskOccurrenceTile extends ConsumerWidget {
  const _TaskOccurrenceTile({required this.task, required this.readOnly});

  final DemoTask task;
  final bool readOnly;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final tokens = FarmThemeExtension.of(context);
    final done = task.status == DemoTaskStatus.done;
    final terminal =
        task.status == DemoTaskStatus.skipped ||
        task.status == DemoTaskStatus.cancelled;
    final statusLabel = switch (task.status) {
      DemoTaskStatus.open => task.overdue ? 'Chưa làm — quá hạn' : 'Chưa làm',
      _ => task.status.viLabel,
    };
    return Semantics(
      container: true,
      label:
          'Việc ${task.title}, ${task.timeLabel}, $statusLabel'
          '${task.assignee == null ? ', chưa phân công' : ', giao cho ${task.assignee}'}',
      child: Padding(
        padding: const EdgeInsets.only(bottom: FarmSpacing.xs),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Semantics(
              label: done
                  ? 'Đánh dấu chưa làm: ${task.title}'
                  : 'Đánh dấu đã làm: ${task.title}',
              checked: done,
              enabled: !readOnly && !terminal,
              child: Checkbox(
                value: done,
                onChanged: readOnly || terminal
                    ? null
                    : (_) => ref
                          .read(demoDataProvider.notifier)
                          .transitionTask(
                            task.zoneId,
                            task.id,
                            done ? DemoTaskStatus.open : DemoTaskStatus.done,
                          ),
              ),
            ),
            const SizedBox(width: FarmSpacing.xs),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    task.title,
                    softWrap: true,
                    style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                      decoration: done ? TextDecoration.lineThrough : null,
                    ),
                  ),
                  Text(
                    '${task.timeLabel}'
                    '${task.assignee == null ? ' · Chưa phân công' : ' · ${task.assignee}'}',
                    style: Theme.of(context).textTheme.bodySmall?.copyWith(
                      color: tokens.textSecondary,
                    ),
                    softWrap: true,
                  ),
                  if (task.overdue || terminal)
                    Padding(
                      padding: const EdgeInsets.only(top: FarmSpacing.xs),
                      child: Text(
                        statusLabel,
                        style: Theme.of(context).textTheme.labelSmall?.copyWith(
                          color: task.overdue
                              ? tokens.semanticWarning
                              : tokens.textSecondary,
                        ),
                      ),
                    ),
                ],
              ),
            ),
            if (!readOnly) ...[
              if (task.status == DemoTaskStatus.open)
                IconButton(
                  tooltip: 'Bỏ qua việc này',
                  onPressed: () => ref
                      .read(demoDataProvider.notifier)
                      .transitionTask(
                        task.zoneId,
                        task.id,
                        DemoTaskStatus.skipped,
                      ),
                  icon: const Icon(Icons.skip_next_outlined),
                ),
              if (task.status == DemoTaskStatus.done ||
                  task.status == DemoTaskStatus.skipped)
                IconButton(
                  tooltip: 'Làm lại (mở lại việc)',
                  onPressed: () => ref
                      .read(demoDataProvider.notifier)
                      .transitionTask(
                        task.zoneId,
                        task.id,
                        DemoTaskStatus.open,
                      ),
                  icon: const Icon(Icons.replay_outlined),
                ),
            ],
          ],
        ),
      ),
    );
  }
}

/// Manual water-usage dialog (phase 06 step 3, D-17): exact decimal litres —
/// a usage fact, separate from a level reading; it never implies a new level.
class _TankUsageDialog extends StatefulWidget {
  const _TankUsageDialog();

  @override
  State<_TankUsageDialog> createState() => _TankUsageDialogState();
}

class _TankUsageDialogState extends State<_TankUsageDialog> {
  final _controller = TextEditingController();

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('Ghi lượng nước đã dùng'),
      content: DecimalField(
        controller: _controller,
        autofocus: true,
        labelText: 'Số lít đã dùng',
        hintText: 'Ví dụ: 200',
        helperText:
            'Lượng nước thực tế đã lấy — không thay đổi số đo mực nước.',
        onSubmitted: (value) => Navigator.of(context).pop(value),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Hủy'),
        ),
        FilledButton(
          onPressed: () => Navigator.of(context).pop(_controller.text),
          child: const Text('Lưu'),
        ),
      ],
    );
  }
}

/// Manual moisture dialog (phase 06 step 3): percent + method provenance —
/// a discrete fact, never averaged into a fabricated sensor level (D-12).
class _MoistureDialog extends StatefulWidget {
  const _MoistureDialog();

  @override
  State<_MoistureDialog> createState() => _MoistureDialogState();
}

class _MoistureDialogState extends State<_MoistureDialog> {
  final _controller = TextEditingController();
  String? _error;

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _save() {
    final raw = _controller.text.trim().replaceAll(',', '.');
    final parsed = double.tryParse(raw);
    if (raw.isEmpty || parsed == null || parsed < 0 || parsed > 100) {
      setState(() => _error = 'Nhập độ ẩm 0–100%.');
      return;
    }
    Navigator.of(context).pop(raw);
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('Đo độ ẩm đất'),
      content: DecimalField(
        controller: _controller,
        autofocus: true,
        labelText: 'Độ ẩm đọc được (%)',
        hintText: 'Ví dụ: 42.5',
        helperText: 'Số đo tay — ghi riêng theo thời điểm, không gộp.',
        errorText: _error,
        onSubmitted: (_) => _save(),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Hủy'),
        ),
        FilledButton(onPressed: _save, child: const Text('Lưu số đo')),
      ],
    );
  }
}

/// Zone summary card under the hero (reference zone detail): kind icon +
/// name + crop species, with the mean growth progress of tracked crops.
class _ZoneSummaryCard extends StatelessWidget {
  const _ZoneSummaryCard({required this.zone, required this.crops});

  final DemoZone zone;
  final List<DemoCrop> crops;

  @override
  Widget build(BuildContext context) {
    final tokens = FarmThemeExtension.of(context);
    final tracked =
        crops.where((crop) => crop.manualProgressPercent != null).toList();
    final mean = tracked.isEmpty
        ? null
        : tracked.fold<int>(
                0,
                (sum, crop) => sum + crop.manualProgressPercent!,
              ) /
              tracked.length;
    final speciesList = crops.map((crop) => crop.species).join(' + ');
    return FarmCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                width: 40,
                height: 40,
                decoration: BoxDecoration(
                  color: tokens.brandSage.withValues(alpha: 0.35),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Icon(
                  switch (zone.kind) {
                    DemoZoneKind.crop => Icons.grass,
                    DemoZoneKind.livestock => Icons.pets,
                    DemoZoneKind.water => Icons.water_drop,
                    DemoZoneKind.storage => Icons.warehouse,
                    DemoZoneKind.house => Icons.home,
                  },
                  color: tokens.brandAction,
                ),
              ),
              const SizedBox(width: FarmSpacing.md),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      zone.name,
                      style: Theme.of(context).textTheme.titleMedium,
                      softWrap: true,
                    ),
                    if (speciesList.isNotEmpty)
                      Text(
                        'Cây trồng: $speciesList',
                        style: Theme.of(context).textTheme.bodySmall?.copyWith(
                          color: tokens.textSecondary,
                        ),
                        softWrap: true,
                      )
                    else if (zone.subtitle != null)
                      Text(
                        zone.subtitle!,
                        style: Theme.of(context).textTheme.bodySmall?.copyWith(
                          color: tokens.textSecondary,
                        ),
                        softWrap: true,
                      ),
                  ],
                ),
              ),
            ],
          ),
          if (mean != null) ...[
            const SizedBox(height: FarmSpacing.md),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text(
                  'Tăng trưởng',
                  style: Theme.of(context).textTheme.labelLarge,
                ),
                Text(
                  '${mean.round()}%',
                  style: Theme.of(context).textTheme.labelLarge,
                ),
              ],
            ),
            const SizedBox(height: FarmSpacing.xs),
            ClipRRect(
              borderRadius: BorderRadius.circular(6),
              child: LinearProgressIndicator(
                value: mean / 100,
                minHeight: 8,
                backgroundColor: tokens.brandSage.withValues(alpha: 0.35),
                valueColor: AlwaysStoppedAnimation(tokens.brandAction),
              ),
            ),
          ],
        ],
      ),
    );
  }
}

/// One labeled metric cell of the water-tank trio (reference detail).
class _TankMetric extends StatelessWidget {
  const _TankMetric({required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    final tokens = FarmThemeExtension.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          label,
          style: Theme.of(
            context,
          ).textTheme.labelSmall?.copyWith(color: tokens.textSecondary),
        ),
        const SizedBox(height: 2),
        Text(value, style: Theme.of(context).textTheme.titleMedium),
      ],
    );
  }
}
