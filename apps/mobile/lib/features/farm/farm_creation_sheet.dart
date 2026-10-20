import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/auth/auth_session_controller.dart';
import '../../core/sync/farmly_mutation.dart';
import '../../core/sync/sync_providers.dart';
import '../../core/theme/farmly_spacing.dart';
import '../../core/theme/farmly_theme_extension.dart';
import '../../features/organizations/organization_repository.dart';
import '../../features/organizations/organization_scope_controller.dart';
import '../../l10n/generated/app_localizations.dart';

/// Offline-first farm creation form. The optional first zone is a child intent
/// whose dependency keeps it behind the org-scoped farm admission.
final class FarmCreationSheet extends ConsumerStatefulWidget {
  const FarmCreationSheet({super.key});

  @override
  ConsumerState<FarmCreationSheet> createState() => _FarmCreationSheetState();
}

class _FarmCreationSheetState extends ConsumerState<FarmCreationSheet> {
  static const _firstZoneGeometry = <Map<String, String>>[
    {'x': '0.28', 'y': '0.28'},
    {'x': '0.72', 'y': '0.28'},
    {'x': '0.72', 'y': '0.72'},
    {'x': '0.28', 'y': '0.72'},
  ];

  final _name = TextEditingController();
  final _area = TextEditingController();
  final _zoneName = TextEditingController();
  String? _timezone;
  String _areaUnit = 'ha';
  String _zoneType = 'crop_plot';
  bool _createFirstZone = false;
  bool _saving = false;
  bool _farmEnqueued = false;
  bool _zoneEnqueued = false;
  String? _farmOperationId;
  String? _farmId;
  String? _zoneOperationId;
  String? _zoneId;
  String? _error;

  @override
  void dispose() {
    _name.dispose();
    _area.dispose();
    _zoneName.dispose();
    super.dispose();
  }

  void _farmFieldsChanged(String _) {
    if (_farmEnqueued) return;
    _farmOperationId = null;
    _farmId = null;
  }

  void _zoneFieldsChanged() {
    if (_zoneEnqueued) return;
    _zoneOperationId = null;
    _zoneId = null;
  }

  Future<void> _save() async {
    final l10n = AppLocalizations.of(context);
    final name = _name.text.trim();
    final timezone = _timezone;
    final zoneName = _zoneName.text.trim();
    if (name.isEmpty) {
      setState(() => _error = l10n.createFarmNameRequired);
      return;
    }
    if (timezone == null || !farmlySupportedTimeZones.contains(timezone)) {
      setState(() => _error = l10n.createFarmTimezoneRequired);
      return;
    }
    if (_createFirstZone && zoneName.isEmpty) {
      setState(() => _error = l10n.createFarmZoneNameRequired);
      return;
    }

    String? areaM2;
    try {
      areaM2 = _areaToSquareMetres(_area.text, _areaUnit);
    } on FormatException {
      setState(() => _error = l10n.createFarmAreaInvalid);
      return;
    }

    setState(() {
      _saving = true;
      _error = null;
    });
    try {
      final selectedScope = ref.read(selectedOrganizationScopeProvider);
      if (selectedScope == null ||
          selectedScope.organization.status !=
              FarmlyOrganizationStatus.active ||
          (selectedScope.organization.role != FarmlyOrganizationRole.owner &&
              selectedScope.organization.role !=
                  FarmlyOrganizationRole.admin)) {
        throw StateError('Farm creation scope is no longer authorized');
      }
      final session = await ref.read(farmlyAuthSessionProvider.future);
      if (session == null) {
        throw StateError('Farm creation requires a signed-in account');
      }
      final latestScope = ref.read(selectedOrganizationScopeProvider);
      if (latestScope == null ||
          latestScope.epoch != selectedScope.epoch ||
          latestScope.organization.id != selectedScope.organization.id ||
          ref.read(farmlyAuthSessionProvider).asData?.value?.user.id !=
              session.user.id) {
        throw StateError('Farm creation scope changed before local save');
      }

      final organizationMutationScope = FarmlyMutationScope.organization(
        accountId: session.user.id,
        organizationId: selectedScope.organization.id,
        continuityEpoch: selectedScope.directory.continuityEpoch,
      );
      _farmOperationId ??= newFarmlyOperationId();
      _farmId ??= newFarmlyOperationId();
      if (!_farmEnqueued) {
        await _enqueue(
          FarmlyScopedMutation(
            scope: organizationMutationScope,
            intent: FarmlyCreateFarmIntent(
              operationId: _farmOperationId!,
              continuityEpoch: selectedScope.directory.continuityEpoch,
              resourceId: _farmId!,
              name: name,
              timezone: timezone,
              areaM2: areaM2,
            ),
          ),
        );
        _farmEnqueued = true;
      }

      if (_createFirstZone && !_zoneEnqueued) {
        _zoneOperationId ??= newFarmlyOperationId();
        _zoneId ??= newFarmlyOperationId();
        final farmMutationScope = FarmlyMutationScope.farm(
          accountId: session.user.id,
          organizationId: selectedScope.organization.id,
          farmId: _farmId!,
          continuityEpoch: selectedScope.directory.continuityEpoch,
        );
        await _enqueue(
          FarmlyScopedMutation(
            scope: farmMutationScope,
            intent: FarmlyCreateZoneIntent(
              operationId: _zoneOperationId!,
              continuityEpoch: selectedScope.directory.continuityEpoch,
              resourceId: _zoneId!,
              name: zoneName,
              type: _zoneType,
              geometry: _firstZoneGeometry,
              dependsOn: [_farmOperationId!],
            ),
          ),
        );
        _zoneEnqueued = true;
      }

      if (!mounted) return;
      Navigator.of(context).pop(_createFirstZone);
    } on Object {
      if (!mounted) return;
      setState(
        () => _error = _farmEnqueued
            ? l10n.farmSavedZoneFailed
            : l10n.farmCreateFailed,
      );
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  Future<void> _enqueue(FarmlyScopedMutation mutation) async {
    final engine = await ref.read(syncEngineProvider.future);
    await engine.enqueue(mutation);
    ref.invalidate(syncStatusProvider);
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final tokens = FarmThemeExtension.of(context);
    final scope = ref.watch(selectedOrganizationScopeProvider);
    final canManageFarms =
        scope != null &&
        scope.organization.status == FarmlyOrganizationStatus.active &&
        (scope.organization.role == FarmlyOrganizationRole.owner ||
            scope.organization.role == FarmlyOrganizationRole.admin);
    final canCreate = canManageFarms && ref.watch(syncEngineProvider).hasValue;

    return SafeArea(
      child: SingleChildScrollView(
        padding: EdgeInsets.fromLTRB(
          FarmSpacing.lg,
          FarmSpacing.sm,
          FarmSpacing.lg,
          FarmSpacing.lg + MediaQuery.of(context).viewInsets.bottom,
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                DecoratedBox(
                  decoration: BoxDecoration(
                    color: tokens.brandAction.withValues(alpha: 0.12),
                    borderRadius: BorderRadius.circular(16),
                  ),
                  child: Padding(
                    padding: const EdgeInsets.all(FarmSpacing.md),
                    child: Icon(
                      Icons.agriculture_outlined,
                      color: tokens.brandAction,
                    ),
                  ),
                ),
                const SizedBox(width: FarmSpacing.md),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        l10n.createFarm,
                        style: Theme.of(context).textTheme.titleLarge,
                      ),
                      const SizedBox(height: FarmSpacing.xs),
                      Text(
                        scope?.organization.name ?? '',
                        style: Theme.of(context).textTheme.bodySmall?.copyWith(
                          color: tokens.textSecondary,
                        ),
                      ),
                    ],
                  ),
                ),
                IconButton(
                  tooltip: MaterialLocalizations.of(context).closeButtonTooltip,
                  onPressed: _saving ? null : () => Navigator.of(context).pop(),
                  icon: const Icon(Icons.close),
                ),
              ],
            ),
            const SizedBox(height: FarmSpacing.lg),
            TextField(
              key: const ValueKey('farm-create-name'),
              controller: _name,
              enabled: !_saving && !_farmEnqueued,
              maxLength: 160,
              textCapitalization: TextCapitalization.words,
              textInputAction: TextInputAction.next,
              onChanged: _farmFieldsChanged,
              decoration: InputDecoration(
                labelText: l10n.createFarmNameLabel,
                prefixIcon: const Icon(Icons.fence_outlined),
              ),
            ),
            const SizedBox(height: FarmSpacing.sm),
            DropdownButtonFormField<String>(
              key: const ValueKey('farm-create-timezone'),
              initialValue: _timezone,
              isExpanded: true,
              decoration: InputDecoration(
                labelText: l10n.createFarmTimezoneLabel,
                hintText: l10n.createFarmTimezoneHint,
                prefixIcon: const Icon(Icons.schedule_outlined),
              ),
              items: farmlySupportedTimeZones
                  .map(
                    (timezone) => DropdownMenuItem<String>(
                      value: timezone,
                      child: Text(timezone, softWrap: true),
                    ),
                  )
                  .toList(growable: false),
              onChanged: _saving || _farmEnqueued
                  ? null
                  : (timezone) {
                      setState(() {
                        _timezone = timezone;
                        _farmFieldsChanged(timezone ?? '');
                      });
                    },
            ),
            const SizedBox(height: FarmSpacing.sm),
            TextField(
              key: const ValueKey('farm-create-area'),
              controller: _area,
              enabled: !_saving && !_farmEnqueued,
              keyboardType: const TextInputType.numberWithOptions(
                decimal: true,
              ),
              onChanged: _farmFieldsChanged,
              decoration: InputDecoration(
                labelText: l10n.createFarmAreaLabel,
                prefixIcon: const Icon(Icons.square_foot_outlined),
                suffixIcon: SizedBox(
                  width: 104,
                  child: DropdownButtonFormField<String>(
                    key: const ValueKey('farm-create-area-unit'),
                    initialValue: _areaUnit,
                    isExpanded: true,
                    decoration: InputDecoration(
                      labelText: l10n.createFarmAreaUnitLabel,
                      border: InputBorder.none,
                    ),
                    items: [
                      DropdownMenuItem(
                        value: 'm2',
                        child: Text(l10n.areaSquareMeters),
                      ),
                      DropdownMenuItem(
                        value: 'ha',
                        child: Text(l10n.areaHectares),
                      ),
                    ],
                    onChanged: _saving || _farmEnqueued
                        ? null
                        : (value) {
                            if (value == null) return;
                            setState(() {
                              _areaUnit = value;
                              _farmFieldsChanged(value);
                            });
                          },
                  ),
                ),
              ),
            ),
            const SizedBox(height: FarmSpacing.md),
            CheckboxListTile(
              key: const ValueKey('farm-create-seed-zone'),
              value: _createFirstZone,
              contentPadding: EdgeInsets.zero,
              controlAffinity: ListTileControlAffinity.leading,
              onChanged: _saving
                  ? null
                  : (value) => setState(() {
                      _createFirstZone = value ?? false;
                      _zoneFieldsChanged();
                    }),
              title: Text(l10n.createFarmSeedZone),
            ),
            if (_createFirstZone) ...[
              TextField(
                key: const ValueKey('farm-create-zone-name'),
                controller: _zoneName,
                enabled: !_saving,
                maxLength: 160,
                textCapitalization: TextCapitalization.words,
                onChanged: (_) => _zoneFieldsChanged(),
                decoration: InputDecoration(
                  labelText: l10n.createFarmZoneNameLabel,
                  hintText: l10n.createFarmZoneNameHint,
                  prefixIcon: const Icon(Icons.grass_outlined),
                ),
              ),
              const SizedBox(height: FarmSpacing.sm),
              DropdownButtonFormField<String>(
                key: const ValueKey('farm-create-zone-type'),
                initialValue: _zoneType,
                decoration: InputDecoration(
                  labelText: l10n.createFarmZoneTypeLabel,
                  prefixIcon: const Icon(Icons.category_outlined),
                ),
                items: [
                  DropdownMenuItem(
                    value: 'crop_plot',
                    child: Text(l10n.zoneKindCrop),
                  ),
                  DropdownMenuItem(
                    value: 'livestock_area',
                    child: Text(l10n.zoneKindLivestock),
                  ),
                  DropdownMenuItem(
                    value: 'water',
                    child: Text(l10n.zoneKindWater),
                  ),
                  DropdownMenuItem(
                    value: 'storage',
                    child: Text(l10n.zoneKindStorage),
                  ),
                  DropdownMenuItem(
                    value: 'house',
                    child: Text(l10n.zoneKindHouse),
                  ),
                  DropdownMenuItem(
                    value: 'other',
                    child: Text(l10n.zoneKindOther),
                  ),
                ],
                onChanged: _saving
                    ? null
                    : (value) {
                        if (value == null) return;
                        setState(() {
                          _zoneType = value;
                          _zoneFieldsChanged();
                        });
                      },
              ),
            ],
            if (!canCreate) ...[
              const SizedBox(height: FarmSpacing.sm),
              Text(
                l10n.farmCreateFailed,
                style: TextStyle(color: tokens.semanticError),
              ),
            ],
            if (_error != null) ...[
              const SizedBox(height: FarmSpacing.sm),
              Semantics(
                liveRegion: true,
                child: Text(
                  _error!,
                  style: TextStyle(color: tokens.semanticError),
                ),
              ),
            ],
            const SizedBox(height: FarmSpacing.lg),
            FilledButton.icon(
              onPressed: _saving || !canCreate ? null : _save,
              icon: _saving
                  ? const SizedBox.square(
                      dimension: 18,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : const Icon(Icons.save_outlined),
              label: Text(_saving ? l10n.creatingFarm : l10n.createFarmSave),
            ),
          ],
        ),
      ),
    );
  }
}

String? _areaToSquareMetres(String input, String unit) {
  final value = input.trim();
  if (value.isEmpty) return null;
  final normalized = value.replaceAll(',', '.');
  if (!RegExp(r'^[0-9]+(?:\.[0-9]+)?$').hasMatch(normalized)) {
    throw const FormatException('Invalid area');
  }
  final parts = normalized.split('.');
  final whole = BigInt.parse(parts.first);
  final fraction = parts.length == 1 ? '' : parts.last;
  final scale = unit == 'ha' ? 6 : 2;
  if (fraction.length > scale) throw const FormatException('Invalid precision');
  final units = unit == 'ha' ? BigInt.from(1000000) : BigInt.from(100);
  final fractionalUnits = BigInt.parse(
    fraction.padRight(scale, '0').isEmpty ? '0' : fraction.padRight(scale, '0'),
  );
  final hundredths = whole * units + fractionalUnits;
  final squareMetres = hundredths ~/ BigInt.from(100);
  final decimals = hundredths.remainder(BigInt.from(100));
  if (squareMetres.toString().length > 12) {
    throw const FormatException('Area is too large');
  }
  if (decimals == BigInt.zero) return squareMetres.toString();
  final decimalText = decimals
      .toString()
      .padLeft(2, '0')
      .replaceFirst(RegExp(r'0+$'), '');
  return '${squareMetres.toString()}.$decimalText';
}
