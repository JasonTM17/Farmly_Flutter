import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/format/decimal_format.dart';
import '../../core/theme/farmly_spacing.dart';
import '../../core/theme/farmly_theme_extension.dart';
import '../../ui/crop_components.dart';
import '../../ui/farm_card.dart';
import '../../ui/farm_scaffold.dart';
import '../../ui/pickers.dart';
import '../../ui/screen_states.dart';
import '../../ui/zone_explorer.dart';
import '../app/app_routes.dart';
import '../demo/demo_models.dart';
import '../demo/demo_providers.dart';

const _demoToday = '2026-10-06';

/// My Farm overview: title/location/area, horizontal zone chips, illustrated
/// zone scene with hotspots plus the semantic list fallback (spec 02 §5).
class FarmOverviewScreen extends ConsumerStatefulWidget {
  const FarmOverviewScreen({super.key});

  @override
  ConsumerState<FarmOverviewScreen> createState() => _FarmOverviewScreenState();
}

class _FarmOverviewScreenState extends ConsumerState<FarmOverviewScreen> {
  String? _selectedZoneId;

  void _ensureSelection(List<DemoZone> zones) {
    if (zones.isEmpty) {
      _selectedZoneId = null;
      return;
    }
    // Null selection is the reference "Overview" state — only repair a
    // stale non-null id, never force a zone when the user picked overview.
    if (_selectedZoneId != null &&
        !zones.any((zone) => zone.id == _selectedZoneId)) {
      _selectedZoneId = zones.first.id;
    }
  }

  Future<void> _openCreateZoneSheet(
    BuildContext context,
    WidgetRef ref,
    String? farmId,
  ) async {
    if (farmId == null) return;
    final created = await showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      builder: (_) => _CreateZoneSheet(farmId: farmId),
    );
    if (created != true) return;
    if (!context.mounted) return;
    showFarmToast(context, 'Đã lưu trên thiết bị');
  }

  @override
  Widget build(BuildContext context) {
    final state = ref.watch(demoDataProvider);
    final farm = farmById(state, state.selectedFarmId);
    final organization = organizationById(state, state.selectedOrganizationId);
    final zones = zonesOfFarm(state, farm?.id);
    _ensureSelection(zones);
    final animals = animalsOfFarm(state, farm?.id);
    final screenState = effectiveDemoState(
      ref,
      'farm',
      dataEmpty: zones.isEmpty,
    );
    final selectedZone = zones
        .where((zone) => zone.id == _selectedZoneId)
        .firstOrNull;

    return FarmScaffold(
      topBar: FarmTopBar(
        title: farm?.name ?? 'Nông trại',
        subtitle:
            '${farm?.location ?? ''} · '
            '${formatAreaHectares(farm?.areaM2) ?? '—'} ha · '
            '${organization?.name ?? ''}',
        actions: [
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
            child: DemoStateSwitcher(screenKey: 'farm'),
          ),
          Expanded(
            child: switch (screenState) {
              DemoLoadState.loading => const _FarmSkeleton(),
              DemoLoadState.recoverableError => FarmErrorView(
                onRetry: () =>
                    ref.read(demoScreenStateProvider.notifier).reset('farm'),
                onSwitchScope: () => showFarmPickerSheet(context),
              ),
              DemoLoadState.permissionDenied => PermissionDeniedView(
                message:
                    'Bạn chỉ có quyền xem ở tổ chức khác. Đổi phạm vi để tiếp tục.',
                onSwitchScope: () => showFarmPickerSheet(context),
              ),
              DemoLoadState.empty => EmptyStateView(
                title: 'Chưa có vùng nào',
                message:
                    'Nông trại này chưa có vùng trồng hoặc khu chăn nuôi. '
                    'Tạo vùng đầu tiên hoặc xem nông trại khác.',
                // §5 My Farm row: a new farm needs a working no-zone CTA,
                // not only the scope switch.
                actionLabel: 'Tạo vùng đầu tiên',
                onAction: () =>
                    _openCreateZoneSheet(context, ref, state.selectedFarmId),
                secondaryActionLabel: 'Đổi nông trại khác',
                onSecondaryAction: () => showFarmPickerSheet(context),
              ),
              DemoLoadState.offline ||
              DemoLoadState.pendingConflict ||
              DemoLoadState.success => ListView(
                padding: const EdgeInsets.only(bottom: FarmSpacing.xxl),
                children: [
                  if (screenState == DemoLoadState.offline) ...[
                    const Padding(
                      padding: EdgeInsets.symmetric(horizontal: FarmSpacing.lg),
                      child: OfflineBanner(asOf: '06:30'),
                    ),
                    const SizedBox(height: FarmSpacing.md),
                  ],
                  ZoneChipStrip(
                    zones: zones,
                    selectedZoneId: _selectedZoneId,
                    overviewLabel: 'Tổng quan',
                    onSelect: (zoneId) =>
                        setState(() => _selectedZoneId = zoneId),
                  ),
                  const SizedBox(height: FarmSpacing.md),
                  Padding(
                    padding: const EdgeInsets.symmetric(
                      horizontal: FarmSpacing.lg,
                    ),
                    child: ZoneScene(
                      zones: zones,
                      selectedZoneId: _selectedZoneId,
                      onSelect: (zoneId) =>
                          setState(() => _selectedZoneId = zoneId),
                      onOpenDetail: (zone) => context.push(
                        '${AppRoutes.zoneDetail}/${Uri.encodeComponent(zone.id)}',
                      ),
                    ),
                  ),
                  const SizedBox(height: FarmSpacing.sm),
                  // Reference hint bar: counts of what the map contains.
                  Padding(
                    padding: const EdgeInsets.symmetric(
                      horizontal: FarmSpacing.lg,
                    ),
                    child: Row(
                      children: [
                        Icon(
                          Icons.touch_app_outlined,
                          size: 18,
                          color: FarmThemeExtension.of(context).textSecondary,
                        ),
                        const SizedBox(width: FarmSpacing.sm),
                        Expanded(
                          child: Text(
                            'Chạm vào một vùng để khám phá · '
                            '${zones.length} vùng · ${animals.length} con vật',
                            style: Theme.of(context).textTheme.bodySmall
                                ?.copyWith(
                                  color: FarmThemeExtension.of(
                                    context,
                                  ).textSecondary,
                                ),
                            softWrap: true,
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: FarmSpacing.sm),
                  AnimatedSwitcher(
                    duration: context.farmZoneZoomDuration(),
                    child: _ZonePanel(
                      key: ValueKey(_selectedZoneId),
                      zone: selectedZone,
                      animalsCount: animals.length,
                    ),
                  ),
                  Padding(
                    padding: const EdgeInsets.fromLTRB(
                      FarmSpacing.lg,
                      FarmSpacing.lg,
                      FarmSpacing.lg,
                      FarmSpacing.sm,
                    ),
                    child: Text(
                      'Khám phá',
                      style: Theme.of(context).textTheme.titleSmall,
                    ),
                  ),
                  Padding(
                    padding: const EdgeInsets.symmetric(
                      horizontal: FarmSpacing.lg,
                    ),
                    child: Card(
                      child: AccessibleZoneList(
                        zones: zones,
                        selectedZoneId: _selectedZoneId,
                        onOpenDetail: (zone) => context.push(
                          '${AppRoutes.zoneDetail}/${Uri.encodeComponent(zone.id)}',
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            },
          ),
        ],
      ),
    );
  }
}

class _ZonePanel extends ConsumerWidget {
  const _ZonePanel({required this.zone, required this.animalsCount, super.key});

  final DemoZone? zone;
  final int animalsCount;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final state = ref.watch(demoDataProvider);
    final tokens = FarmThemeExtension.of(context);
    final selectedZone = zone;
    if (selectedZone == null) {
      return const SizedBox.shrink();
    }
    final crops = cropsOfZone(state, selectedZone.id);

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: FarmSpacing.lg),
      child: FarmCard(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Expanded(
                  child: Text(
                    selectedZone.name,
                    style: Theme.of(context).textTheme.titleMedium,
                    softWrap: true,
                  ),
                ),
                Text(
                  selectedZone.subtitle ?? '',
                  style: Theme.of(context).textTheme.labelMedium?.copyWith(
                    color: tokens.textSecondary,
                  ),
                  softWrap: true,
                ),
              ],
            ),
            const SizedBox(height: FarmSpacing.md),
            for (final crop in crops)
              Padding(
                padding: const EdgeInsets.only(bottom: FarmSpacing.md),
                child: CropProgressCard(
                  crop: crop,
                  zoneName: selectedZone.name,
                  onTap: () => context.push(
                    '${AppRoutes.zoneDetail}/${Uri.encodeComponent(selectedZone.id)}',
                  ),
                ),
              ),
            if (selectedZone.kind == DemoZoneKind.livestock)
              Padding(
                padding: const EdgeInsets.only(bottom: FarmSpacing.md),
                child: Semantics(
                  button: true,
                  label: 'Mở khu chăn nuôi, $animalsCount con',
                  child: FilledButton.tonal(
                    onPressed: () => context.push(AppRoutes.livestock),
                    child: const Text('Mở khu chăn nuôi'),
                  ),
                ),
              ),
            if (crops.isEmpty && selectedZone.kind != DemoZoneKind.livestock)
              Text(
                'Vùng này chưa có cây trồng đang theo dõi.',
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

String _zoneKindLabel(DemoZoneKind kind) => switch (kind) {
  DemoZoneKind.crop => 'Trồng trọt',
  DemoZoneKind.livestock => 'Chăn nuôi',
  DemoZoneKind.water => 'Nước',
  DemoZoneKind.storage => 'Kho',
  DemoZoneKind.house => 'Nhà',
};

/// Minimal create-zone sheet backing the My Farm no-zone CTA (spec 02 §5):
/// names the zone, picks its kind and stores it as a local demo write.
class _CreateZoneSheet extends ConsumerStatefulWidget {
  const _CreateZoneSheet({required this.farmId});

  final String farmId;

  @override
  ConsumerState<_CreateZoneSheet> createState() => _CreateZoneSheetState();
}

class _CreateZoneSheetState extends ConsumerState<_CreateZoneSheet> {
  final _nameController = TextEditingController();
  String? _nameError;
  DemoZoneKind _kind = DemoZoneKind.crop;

  @override
  void dispose() {
    _nameController.dispose();
    super.dispose();
  }

  void _save() {
    final name = _nameController.text.trim();
    if (name.isEmpty) {
      setState(() => _nameError = 'Nhập tên vùng.');
      return;
    }
    ref
        .read(demoDataProvider.notifier)
        .addZone(
          DemoZone(
            id: 'zone-${DateTime.now().microsecondsSinceEpoch}',
            farmId: widget.farmId,
            name: name,
            kind: _kind,
            x: 0.5,
            y: 0.5,
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
              'Tạo vùng đầu tiên',
              style: Theme.of(context).textTheme.titleLarge,
            ),
            const SizedBox(height: FarmSpacing.lg),
            TextField(
              controller: _nameController,
              autofocus: true,
              decoration: InputDecoration(
                labelText: 'Tên vùng',
                hintText: 'Ví dụ: Luống hành tím',
                errorText: _nameError,
              ),
              onSubmitted: (_) => _save(),
            ),
            const SizedBox(height: FarmSpacing.md),
            Align(
              alignment: Alignment.centerLeft,
              child: Text(
                'Loại vùng',
                style: Theme.of(context).textTheme.titleSmall,
              ),
            ),
            const SizedBox(height: FarmSpacing.xs),
            Wrap(
              spacing: FarmSpacing.sm,
              runSpacing: FarmSpacing.sm,
              children: [
                for (final kind in DemoZoneKind.values)
                  ChoiceChip(
                    label: Text(_zoneKindLabel(kind)),
                    selected: _kind == kind,
                    onSelected: (_) => setState(() => _kind = kind),
                  ),
              ],
            ),
            const SizedBox(height: FarmSpacing.md),
            const AsOfLabel(asOf: _demoToday, source: 'bạn nhập'),
            const SizedBox(height: FarmSpacing.lg),
            FilledButton(
              onPressed: _save,
              child: const Text('Lưu trên thiết bị'),
            ),
          ],
        ),
      ),
    );
  }
}

class _FarmSkeleton extends StatelessWidget {
  const _FarmSkeleton();

  @override
  Widget build(BuildContext context) {
    return ListView(
      padding: const EdgeInsets.only(bottom: FarmSpacing.xxl),
      children: const [
        SizedBox(
          height: FarmSpacing.minTouchTarget,
          child: Row(
            children: [
              SizedBox(width: FarmSpacing.lg),
              SkeletonSurface(width: 96, height: 32, radius: 16),
              SizedBox(width: FarmSpacing.sm),
              SkeletonSurface(width: 110, height: 32, radius: 16),
            ],
          ),
        ),
        Padding(
          padding: EdgeInsets.symmetric(horizontal: FarmSpacing.lg),
          child: SkeletonSurface(
            width: double.infinity,
            height: 260,
            radius: FarmSpacing.cardRadius,
          ),
        ),
        SizedBox(height: FarmSpacing.md),
        Padding(
          padding: EdgeInsets.symmetric(horizontal: FarmSpacing.lg),
          child: SkeletonSurface(
            width: double.infinity,
            height: 140,
            radius: FarmSpacing.cardRadius,
          ),
        ),
      ],
    );
  }
}
