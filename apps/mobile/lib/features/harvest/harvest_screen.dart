import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/theme/farmly_spacing.dart';
import '../../core/theme/farmly_theme_extension.dart';
import '../../ui/farm_card.dart';
import '../../ui/farm_scaffold.dart';
import '../../ui/form_fields.dart';
import '../../ui/pickers.dart';
import '../../ui/screen_states.dart';
import '../app/app_router.dart';
import '../app/app_routes.dart';
import '../demo/demo_models.dart';
import '../demo/demo_providers.dart';

const _demoToday = '2026-10-06';

/// Harvest tab: confirmed period kg, separate pending kg, record timeline and
/// an add form validating exact decimal strings (spec 02 §5 Harvest row).
class HarvestScreen extends ConsumerWidget {
  const HarvestScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final state = ref.watch(demoDataProvider);
    final farm = farmById(state, state.selectedFarmId);
    final organization = organizationById(state, state.selectedOrganizationId);
    final records = harvestsOfFarm(state, farm?.id);
    final screenState = effectiveDemoState(
      ref,
      'harvest',
      dataEmpty: records.isEmpty,
    );

    return FarmScaffold(
      topBar: FarmTopBar(
        title: 'Thu hoạch',
        subtitle: '${organization?.name ?? ''} · ${farm?.name ?? ''}',
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
          Semantics(
            button: true,
            label: 'Đổi nông trại',
            child: IconButton(
              tooltip: 'Đổi nông trại',
              icon: const Icon(Icons.swap_horiz_outlined),
              onPressed: () => showFarmPickerSheet(context),
            ),
          ),
        ],
      ),
      body: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const Padding(
            padding: EdgeInsets.fromLTRB(
              FarmSpacing.lg,
              0,
              FarmSpacing.lg,
              FarmSpacing.sm,
            ),
            child: DemoStateSwitcher(screenKey: 'harvest'),
          ),
          Expanded(
            child: switch (screenState) {
              DemoLoadState.loading => const _HarvestSkeleton(),
              DemoLoadState.recoverableError => FarmErrorView(
                onRetry: () =>
                    ref.read(demoScreenStateProvider.notifier).reset('harvest'),
                onSwitchScope: () => showFarmPickerSheet(context),
              ),
              DemoLoadState.permissionDenied => PermissionDeniedView(
                message:
                    'Bạn chỉ có quyền xem thu hoạch của nông trại này — '
                    'thêm bản ghi cần quyền ghi.',
                onSwitchScope: () => showFarmPickerSheet(context),
              ),
              DemoLoadState.empty => EmptyStateView(
                title: 'Chưa có bản ghi thu hoạch',
                message:
                    'Ghi nhận lần thu hoạch đầu tiên — bản ghi được lưu trên '
                    'thiết bị trước khi đồng bộ.',
                actionLabel: 'Đổi nông trại khác',
                onAction: () => showFarmPickerSheet(context),
              ),
              DemoLoadState.offline ||
              DemoLoadState.pendingConflict ||
              DemoLoadState.success => _HarvestContent(
                state: state,
                farmId: farm?.id,
                records: records,
                screenState: screenState,
              ),
            },
          ),
        ],
      ),
    );
  }
}

class _HarvestContent extends ConsumerWidget {
  const _HarvestContent({
    required this.state,
    required this.farmId,
    required this.records,
    required this.screenState,
  });

  final DemoDataState state;
  final String? farmId;
  final List<DemoHarvestRecord> records;
  final DemoLoadState screenState;

  Future<void> _openAddSheet(BuildContext context, WidgetRef ref) async {
    // Ended/archived plantings are not harvest parents (spec 02 §5).
    final crops = cropsOfFarm(
      state,
      farmId,
    ).where((crop) => !crop.ended).toList(growable: false);
    if (farmId == null || crops.isEmpty) {
      // Offline parent dependency (spec 02 §5): a harvest record needs an
      // existing crop, so the button never fails silently.
      showFarmToast(
        context,
        'Nông trại này chưa có cây trồng — mở một vùng để thêm cây trồng '
        'trước khi ghi thu hoạch.',
      );
      return;
    }
    final saved = await showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      builder: (sheetContext) => _AddHarvestSheet(crops: crops),
    );
    if (saved != true) return;
    if (!context.mounted) return;
    showFarmToast(context, 'Đã lưu trên thiết bị');
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final tokens = FarmThemeExtension.of(context);
    final role = ref.watch(demoFarmRoleProvider);
    final confirmed = records
        .where((record) => record.countsTowardTotals)
        .toList(growable: false);
    final pending = records
        .where((record) => record.status == DemoHarvestStatus.localPending)
        .toList(growable: false);
    final confirmedKg = confirmed.fold<double>(
      0,
      (sum, record) => sum + double.parse(record.quantityKg),
    );
    final pendingKg = pending.fold<double>(
      0,
      (sum, record) => sum + double.parse(record.quantityKg),
    );
    final conflicts = state.syncItems
        .where(
          (item) =>
              item.farmId == farmId && item.status == DemoSyncStatus.conflict,
        )
        .length;

    return ListView(
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
        if (conflicts > 0) ...[
          PendingConflictBanner(
            count: conflicts,
            onOpen: () => context.push(AppRoutes.syncCenter),
          ),
          const SizedBox(height: FarmSpacing.md),
        ],
        FarmCard(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Kỳ này (7 ngày)',
                style: Theme.of(context).textTheme.titleSmall,
              ),
              const SizedBox(height: FarmSpacing.xs),
              Text(
                '${confirmedKg.toStringAsFixed(2)} kg',
                style: Theme.of(context).textTheme.headlineMedium,
              ),
              if (pendingKg > 0) ...[
                const SizedBox(height: FarmSpacing.xs),
                Semantics(
                  container: true,
                  label:
                      'Thêm ${pendingKg.toStringAsFixed(2)} kilô gam đang chờ '
                      'đồng bộ, chưa tính vào tổng đã xác nhận',
                  child: Row(
                    children: [
                      Icon(
                        Icons.cloud_upload_outlined,
                        size: 16,
                        color: tokens.semanticWarning,
                      ),
                      const SizedBox(width: FarmSpacing.xs),
                      Expanded(
                        child: Text(
                          'Còn ${pendingKg.toStringAsFixed(2)} kg đang chờ '
                          'đồng bộ — chưa tính vào tổng trên.',
                          style: Theme.of(context).textTheme.bodySmall
                              ?.copyWith(color: tokens.semanticWarning),
                          softWrap: true,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
              const SizedBox(height: FarmSpacing.sm),
              const AsOfLabel(asOf: '06:30', source: 'nhật ký của bạn'),
            ],
          ),
        ),
        const SizedBox(height: FarmSpacing.md),
        Semantics(
          button: true,
          label: 'Thêm bản ghi thu hoạch',
          child: FilledButton.icon(
            onPressed: () => _openAddSheet(context, ref),
            icon: const Icon(Icons.add),
            label: const Text('Thêm thu hoạch'),
          ),
        ),
        const SizedBox(height: FarmSpacing.md),
        Text('Nhật ký', style: Theme.of(context).textTheme.titleSmall),
        const SizedBox(height: FarmSpacing.sm),
        for (final record in records)
          Padding(
            padding: const EdgeInsets.only(bottom: FarmSpacing.sm),
            child: _HarvestRecordTile(record: record, role: role),
          ),
      ],
    );
  }
}

/// Harvest record row (spec 02 §5 Harvest correction row): shows the effective
/// value, status, and — when a proposal is pending — the original→proposed
/// comparison. Tapping opens the correction sheet: worker proposes, manager
/// applies/rejects or voids.
class _HarvestRecordTile extends StatelessWidget {
  const _HarvestRecordTile({required this.record, required this.role});

  final DemoHarvestRecord record;
  final DemoFarmRole role;

  @override
  Widget build(BuildContext context) {
    final tokens = FarmThemeExtension.of(context);
    final voided = record.status == DemoHarvestStatus.voided;
    final proposal = record.correction;
    final subtitle = StringBuffer(
      '${record.harvestedOn} · ${record.quantityKg} kg',
    );
    if (proposal != null) {
      subtitle.write(' → đề xuất ${proposal.proposedQuantityKg} kg');
    }
    if (record.voidReason != null) {
      subtitle.write(' · ${record.voidReason}');
    }
    return Semantics(
      button: true,
      label:
          'Bản ghi ${record.cropLabel}, ${record.quantityKg} kg, '
          '${_statusSemantics(record)}',
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: () => showModalBottomSheet<void>(
            context: context,
            isScrollControlled: true,
            builder: (sheetContext) =>
                _HarvestCorrectionSheet(record: record, role: role),
          ),
          borderRadius: BorderRadius.circular(FarmSpacing.md),
          child: FarmCard(
            padding: const EdgeInsets.all(FarmSpacing.md),
            child: Row(
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        record.cropLabel,
                        style: Theme.of(context).textTheme.titleSmall?.copyWith(
                          decoration: voided ? TextDecoration.lineThrough : null,
                        ),
                        softWrap: true,
                      ),
                      Text(
                        subtitle.toString(),
                        style: Theme.of(context).textTheme.bodySmall?.copyWith(
                          color: voided
                              ? tokens.semanticError
                              : tokens.textSecondary,
                        ),
                        softWrap: true,
                      ),
                    ],
                  ),
                ),
                _HarvestStatusChip(status: record.status),
              ],
            ),
          ),
        ),
      ),
    );
  }

  String _statusSemantics(DemoHarvestRecord record) => switch (record.status) {
    DemoHarvestStatus.confirmed => 'đã xác nhận',
    DemoHarvestStatus.localPending => 'đang chờ đồng bộ',
    DemoHarvestStatus.correctionPending => 'đang chờ duyệt chỉnh sửa',
    DemoHarvestStatus.voided => 'đã huỷ',
  };
}

class _HarvestStatusChip extends StatelessWidget {
  const _HarvestStatusChip({required this.status});

  final DemoHarvestStatus status;

  @override
  Widget build(BuildContext context) {
    final tokens = FarmThemeExtension.of(context);
    final (icon, label, color) = switch (status) {
      DemoHarvestStatus.confirmed => (
        Icons.check_circle_outline,
        'Đã xác nhận',
        tokens.brandAction,
      ),
      DemoHarvestStatus.localPending => (
        Icons.cloud_upload_outlined,
        'Chờ đồng bộ',
        tokens.semanticWarning,
      ),
      DemoHarvestStatus.correctionPending => (
        Icons.rate_review_outlined,
        'Chờ duyệt chỉnh sửa',
        tokens.semanticWarning,
      ),
      DemoHarvestStatus.voided => (
        Icons.block_outlined,
        'Đã huỷ',
        tokens.semanticError,
      ),
    };
    return Semantics(
      label: label,
      child: Container(
        padding: const EdgeInsets.symmetric(
          horizontal: FarmSpacing.md,
          vertical: FarmSpacing.xs,
        ),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(FarmSpacing.xl),
          border: Border.all(color: color),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 14, color: color),
            const SizedBox(width: FarmSpacing.xs),
            Text(
              label,
              style: Theme.of(
                context,
              ).textTheme.labelMedium?.copyWith(color: color),
              softWrap: true,
            ),
          ],
        ),
      ),
    );
  }
}

/// Add-harvest sheet (spec 02 §5 Harvest row): exact decimal kg input,
/// farm-local date, parent crop from the farm's live plantings. The write is
/// an append `harvest.create` intent — records land local-pending.
class _AddHarvestSheet extends ConsumerStatefulWidget {
  const _AddHarvestSheet({required this.crops});

  final List<DemoCrop> crops;

  @override
  ConsumerState<_AddHarvestSheet> createState() => _AddHarvestSheetState();
}

class _AddHarvestSheetState extends ConsumerState<_AddHarvestSheet> {
  final _quantityController = TextEditingController();
  final _dateController = TextEditingController(text: _demoToday);
  DemoCrop? _selected;
  String? _quantityError;
  String? _dateError;

  @override
  void dispose() {
    _quantityController.dispose();
    _dateController.dispose();
    super.dispose();
  }

  void _save() {
    final crop = _selected;
    final kg = _quantityController.text.trim().replaceAll(',', '.');
    final date = _dateController.text.trim();
    var ok = true;
    if (crop == null) {
      ok = false;
    }
    if (kg.isEmpty || double.tryParse(kg) == null || double.parse(kg) <= 0) {
      setState(() => _quantityError = 'Nhập khối lượng (kg, số thập phân).');
      ok = false;
    }
    if (!RegExp(r'^\d{4}-\d{2}-\d{2}$').hasMatch(date)) {
      setState(() => _dateError = 'Ngày theo định dạng yyyy-MM-dd.');
      ok = false;
    }
    if (!ok || crop == null) return;
    ref
        .read(demoDataProvider.notifier)
        .addHarvest(
          DemoHarvestRecord(
            id: 'harvest-${DateTime.now().microsecondsSinceEpoch}',
            cropLabel: crop.species,
            quantityKg: kg,
            harvestedOn: date,
            status: DemoHarvestStatus.localPending,
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
              'Thêm thu hoạch',
              style: Theme.of(context).textTheme.titleLarge,
            ),
            const SizedBox(height: FarmSpacing.sm),
            DropdownButtonFormField<DemoCrop>(
              initialValue: _selected,
              decoration: const InputDecoration(labelText: 'Cây trồng'),
              items: [
                for (final crop in widget.crops)
                  DropdownMenuItem(value: crop, child: Text(crop.species)),
              ],
              onChanged: (crop) => setState(() => _selected = crop),
            ),
            const SizedBox(height: FarmSpacing.sm),
            DecimalField(
              controller: _quantityController,
              labelText: 'Khối lượng (kg)',
              hintText: 'Ví dụ: 12.5',
              errorText: _quantityError,
            ),
            const SizedBox(height: FarmSpacing.sm),
            LocalDateField(
              controller: _dateController,
              labelText: 'Ngày thu (theo giờ nông trại)',
              errorText: _dateError,
              helperText: 'Ngày dương lịch của nông trại, không phải UTC.',
            ),
            const SizedBox(height: FarmSpacing.sm),
            Text(
              'Bản ghi lưu trên thiết bị trước, đồng bộ sau.',
              style: Theme.of(
                context,
              ).textTheme.bodySmall?.copyWith(color: tokens.textSecondary),
              softWrap: true,
            ),
            const SizedBox(height: FarmSpacing.lg),
            FilledButton(
              onPressed: _save,
              child: const Text('Lưu thu hoạch'),
            ),
          ],
        ),
      ),
    );
  }
}

/// Correction lifecycle sheet (spec 02 §5 "Harvest correction"; phase 06 step
/// 2): the original value stays immutable — a worker *proposes* a replacement
/// (`harvest.correction.propose`), a manager *applies* or *rejects* it, and
/// `harvest.void` tombstones a record with a mandatory reason. Every action
/// lands local-pending in the outbox; nothing edits the confirmed quantity
/// in place.
class _HarvestCorrectionSheet extends ConsumerStatefulWidget {
  const _HarvestCorrectionSheet({required this.record, required this.role});

  final DemoHarvestRecord record;
  final DemoFarmRole role;

  @override
  ConsumerState<_HarvestCorrectionSheet> createState() =>
      _HarvestCorrectionSheetState();
}

class _HarvestCorrectionSheetState
    extends ConsumerState<_HarvestCorrectionSheet> {
  final _quantityController = TextEditingController();
  final _reasonController = TextEditingController();
  String? _quantityError;
  String? _reasonError;

  @override
  void dispose() {
    _quantityController.dispose();
    _reasonController.dispose();
    super.dispose();
  }

  bool get _isWorker => !widget.role.canApproveCorrections;

  void _propose() {
    final kg = _quantityController.text.trim().replaceAll(',', '.');
    final reason = _reasonController.text.trim();
    var ok = true;
    if (kg.isEmpty || double.tryParse(kg) == null || double.parse(kg) <= 0) {
      setState(() => _quantityError = 'Nhập khối lượng mới (kg, số thập phân).');
      ok = false;
    }
    if (reason.isEmpty) {
      setState(() => _reasonError = 'Nhập lý do chỉnh sửa.');
      ok = false;
    }
    if (!ok) return;
    ref
        .read(demoDataProvider.notifier)
        .proposeHarvestCorrection(
          widget.record.id,
          proposedQuantityKg: kg,
          reason: reason,
          proposedBy: 'bạn',
        );
    Navigator.of(context).pop();
    showFarmToast(context, 'Đã gửi đề xuất chỉnh sửa — chờ quản lý duyệt.');
  }

  void _apply() {
    ref
        .read(demoDataProvider.notifier)
        .applyHarvestCorrection(widget.record.id);
    Navigator.of(context).pop();
    showFarmToast(context, 'Đã áp dụng chỉnh sửa — chờ đồng bộ.');
  }

  void _reject() {
    ref
        .read(demoDataProvider.notifier)
        .rejectHarvestCorrection(widget.record.id);
    Navigator.of(context).pop();
    showFarmToast(context, 'Đã từ chối đề xuất chỉnh sửa.');
  }

  void _void() {
    final reason = _reasonController.text.trim();
    if (reason.isEmpty) {
      setState(() => _reasonError = 'Bắt buộc nhập lý do huỷ.');
      return;
    }
    ref
        .read(demoDataProvider.notifier)
        .voidHarvest(widget.record.id, reason: reason);
    Navigator.of(context).pop();
    showFarmToast(context, 'Đã huỷ bản ghi — chờ đồng bộ.');
  }

  @override
  Widget build(BuildContext context) {
    final tokens = FarmThemeExtension.of(context);
    final record = widget.record;
    final proposal = record.correction;
    final voided = record.status == DemoHarvestStatus.voided;
    final localPending = record.status == DemoHarvestStatus.localPending;
    final roleLabel = widget.role.viLabel;
    return SafeArea(
      child: Padding(
        padding: EdgeInsets.only(
          left: FarmSpacing.lg,
          right: FarmSpacing.lg,
          top: FarmSpacing.sm,
          bottom: FarmSpacing.lg + MediaQuery.of(context).viewInsets.bottom,
        ),
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(
                'Chỉnh sửa / huỷ bản ghi',
                style: Theme.of(context).textTheme.titleLarge,
              ),
              const SizedBox(height: FarmSpacing.xs),
              Text(
                'Vai trò hiện tại: $roleLabel',
                style: Theme.of(
                  context,
                ).textTheme.bodySmall?.copyWith(color: tokens.textSecondary),
                softWrap: true,
              ),
              const SizedBox(height: FarmSpacing.md),
              // Original value is immutable — always shown as the base.
              FarmCard(
                padding: const EdgeInsets.all(FarmSpacing.md),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Giá trị gốc (bất biến)',
                      style: Theme.of(context).textTheme.labelLarge,
                    ),
                    Text(
                      '${record.cropLabel} · ${record.harvestedOn}',
                      style: Theme.of(context).textTheme.bodySmall?.copyWith(
                        color: tokens.textSecondary,
                      ),
                    ),
                    Text(
                      '${record.quantityKg} kg',
                      style: Theme.of(context).textTheme.headlineSmall,
                    ),
                    if (proposal != null) ...[
                      const Divider(height: FarmSpacing.lg),
                      Text(
                        'Đề xuất của ${proposal.proposedBy}',
                        style: Theme.of(context).textTheme.labelLarge?.copyWith(
                          color: tokens.semanticWarning,
                        ),
                      ),
                      Text(
                        '${proposal.proposedQuantityKg} kg — ${proposal.reason}',
                        style: Theme.of(context).textTheme.bodyMedium,
                        softWrap: true,
                      ),
                    ],
                  ],
                ),
              ),
              const SizedBox(height: FarmSpacing.md),
              if (voided)
                Text(
                  'Bản ghi này đã huỷ — không thể chỉnh sửa. '
                  'Sửa sai bằng cách ghi bản ghi mới.',
                  style: Theme.of(
                    context,
                  ).textTheme.bodyMedium?.copyWith(color: tokens.semanticError),
                  softWrap: true,
                )
              else if (localPending)
                Text(
                  'Bản ghi đang chờ đồng bộ lần đầu — chỉnh sửa sẽ khả dụng '
                  'sau khi máy chủ xác nhận.',
                  style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                    color: tokens.semanticWarning,
                  ),
                  softWrap: true,
                )
              else if (!widget.role.canWriteFacts)
                Text(
                  'Bạn chỉ có quyền xem — không thể đề xuất hay duyệt '
                  'chỉnh sửa.',
                  style: Theme.of(context).textTheme.bodySmall?.copyWith(
                    color: tokens.semanticWarning,
                  ),
                  softWrap: true,
                )
              else ...[
                if (proposal == null) ...[
                  Text(
                    _isWorker
                        ? 'Bạn là công nhân — đề xuất chỉnh sửa để quản lý duyệt.'
                        : 'Đề xuất giá trị thay thế — bản ghi mới sẽ thay giá '
                              'trị hiệu lực sau khi được phê duyệt.',
                    style: Theme.of(context).textTheme.bodySmall?.copyWith(
                      color: tokens.textSecondary,
                    ),
                    softWrap: true,
                  ),
                  const SizedBox(height: FarmSpacing.sm),
                  DecimalField(
                    controller: _quantityController,
                    labelText: 'Khối lượng mới (kg)',
                    errorText: _quantityError,
                  ),
                  const SizedBox(height: FarmSpacing.sm),
                  TextField(
                    controller: _reasonController,
                    decoration: InputDecoration(
                      labelText: 'Lý do chỉnh sửa',
                      hintText: 'VD: cân lại đúng là …',
                      errorText: _reasonError,
                    ),
                  ),
                  const SizedBox(height: FarmSpacing.md),
                  FilledButton.icon(
                    onPressed: _propose,
                    icon: const Icon(Icons.rate_review_outlined),
                    label: Text(
                      _isWorker ? 'Gửi đề xuất' : 'Đề xuất chỉnh sửa',
                    ),
                  ),
                ] else ...[
                  Text(
                    'Đề xuất đang chờ duyệt — giá trị gốc vẫn tính vào tổng.',
                    style: Theme.of(context).textTheme.bodySmall?.copyWith(
                      color: tokens.semanticWarning,
                    ),
                    softWrap: true,
                  ),
                  const SizedBox(height: FarmSpacing.sm),
                  if (widget.role.canApproveCorrections)
                    Row(
                      children: [
                        Expanded(
                          child: OutlinedButton.icon(
                            onPressed: _reject,
                            icon: const Icon(Icons.close),
                            label: const Text('Từ chối'),
                          ),
                        ),
                        const SizedBox(width: FarmSpacing.sm),
                        Expanded(
                          child: FilledButton.icon(
                            onPressed: _apply,
                            icon: const Icon(Icons.check),
                            label: const Text('Áp dụng'),
                          ),
                        ),
                      ],
                    )
                  else
                    Text(
                      'Chỉ quản lý mới được duyệt đề xuất chỉnh sửa.',
                      style: Theme.of(context).textTheme.bodySmall?.copyWith(
                        color: tokens.textSecondary,
                      ),
                      softWrap: true,
                    ),
                ],
                if (widget.role.canApproveCorrections) ...[
                  const Divider(height: FarmSpacing.xl),
                  if (proposal == null)
                    TextField(
                      controller: _reasonController,
                      decoration: InputDecoration(
                        labelText: 'Lý do huỷ bản ghi',
                        errorText: _reasonError,
                      ),
                    ),
                  if (proposal == null)
                    const SizedBox(height: FarmSpacing.sm),
                  OutlinedButton.icon(
                    onPressed: _void,
                    icon: Icon(Icons.block_outlined, color: tokens.semanticError),
                    label: Text(
                      'Huỷ bản ghi',
                      style: TextStyle(color: tokens.semanticError),
                    ),
                  ),
                ],
              ],
            ],
          ),
        ),
      ),
    );
  }
}

class _HarvestSkeleton extends StatelessWidget {
  const _HarvestSkeleton();

  @override
  Widget build(BuildContext context) {
    return ListView(
      padding: const EdgeInsets.all(FarmSpacing.lg),
      children: const [
        SkeletonSurface(height: 120, radius: FarmSpacing.md),
        SizedBox(height: FarmSpacing.md),
        SkeletonSurface(height: 64, radius: FarmSpacing.md),
        SizedBox(height: FarmSpacing.sm),
        SkeletonSurface(height: 64, radius: FarmSpacing.md),
      ],
    );
  }
}
