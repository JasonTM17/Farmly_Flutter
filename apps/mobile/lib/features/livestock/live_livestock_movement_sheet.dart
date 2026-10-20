import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/auth/auth_session_controller.dart';
import '../../core/sync/farmly_mutation.dart';
import '../../core/sync/sync_providers.dart';
import '../../core/theme/farmly_spacing.dart';
import '../../core/theme/farmly_theme_extension.dart';
import '../../l10n/generated/app_localizations.dart';
import '../../ui/farm_card.dart';
import '../organizations/organization_scope_controller.dart';
import 'live_livestock.dart';

class LiveLivestockMovementCreateSheet extends ConsumerStatefulWidget {
  const LiveLivestockMovementCreateSheet({
    required this.collection,
    required this.herd,
    super.key,
  });

  final FarmlyLiveLivestockCollection collection;
  final FarmlyLiveHerd herd;

  @override
  ConsumerState<LiveLivestockMovementCreateSheet> createState() =>
      _LiveLivestockMovementCreateSheetState();
}

class _LiveLivestockMovementCreateSheetState
    extends ConsumerState<LiveLivestockMovementCreateSheet> {
  final _countController = TextEditingController();
  String _movementType = 'stock_in';
  DateTime? _occurredOn;
  String? _error;
  bool _saving = false;

  @override
  void dispose() {
    _countController.dispose();
    super.dispose();
  }

  bool _scopeIsCurrent() {
    final scope = widget.collection.scope;
    final selected = widget.collection.selectedScope;
    if (scope == null || selected == null) return false;
    final accountId = ref
        .read(farmlyAuthSessionProvider)
        .asData
        ?.value
        ?.user
        .id;
    final currentSelected = ref.read(selectedOrganizationScopeProvider);
    final currentScope = ref.read(farmlySyncScopeProvider).asData?.value;
    final current = ref.read(farmlyLiveLivestockProvider).asData?.value;
    return accountId == scope.accountId &&
        _sameSelection(selected, currentSelected) &&
        _sameFarmScope(scope, currentScope) &&
        current?.cacheState == FarmlyLivestockCacheState.ready &&
        current?.canManageLivestockMovements == true &&
        current!.herds.any(
          (herd) =>
              herd.id == widget.herd.id &&
              herd.isBatch &&
              herd.status == 'active',
        );
  }

  Future<void> _chooseDate() async {
    final now = DateTime.now();
    final picked = await showDatePicker(
      context: context,
      initialDate: _occurredOn ?? DateTime(now.year, now.month, now.day),
      firstDate: DateTime(1900),
      lastDate: DateTime(9999, 12, 31),
      initialEntryMode: DatePickerEntryMode.calendar,
      helpText: AppLocalizations.of(context).liveMovementOccurredOnLabel,
    );
    if (picked != null && mounted) {
      setState(() {
        _occurredOn = picked;
        _error = null;
      });
    }
  }

  Future<void> _save() async {
    if (_saving) return;
    final l10n = AppLocalizations.of(context);
    final count = int.tryParse(_countController.text.trim());
    if (count == null || count < 1 || count > 2147483647) {
      setState(() => _error = l10n.liveMovementCountInvalid);
      return;
    }
    if (!_scopeIsCurrent()) {
      setState(() => _error = l10n.liveFarmScopeChanged);
      return;
    }

    setState(() {
      _saving = true;
      _error = null;
    });
    try {
      final scope = widget.collection.scope!;
      final selection = widget.collection.selectedScope!;
      final engine = await ref.read(syncEngineProvider.future);
      if (!_scopeIsCurrent()) {
        setState(() => _error = l10n.liveFarmScopeChanged);
        return;
      }

      final snapshot = await engine.domainSnapshot(scope);
      if (!_scopeIsCurrent() || snapshot == null) {
        setState(() => _error = l10n.liveFarmScopeChanged);
        return;
      }
      if (snapshot.cursor.continuityEpoch !=
              selection.directory.continuityEpoch ||
          snapshot.cursor.scopePolicyVersion !=
              selection.directory.scopePolicyVersion) {
        setState(() => _error = l10n.liveFarmScopeChanged);
        return;
      }

      final herdRow = snapshot.recordsFor('herd')[widget.herd.id];
      if (herdRow is! Map ||
          herdRow['mode'] != 'batch' ||
          herdRow['status'] != 'active' ||
          herdRow['headcount'] is! int ||
          (herdRow['headcount'] as int) < 0) {
        setState(() => _error = l10n.liveFarmScopeChanged);
        return;
      }

      final entries = await engine.entries(
        accountId: scope.accountId,
        organizationId: scope.organizationId,
      );
      if (!_scopeIsCurrent()) {
        setState(() => _error = l10n.liveFarmScopeChanged);
        return;
      }
      final ledger = projectFarmlyLiveLivestockMovements(
        snapshotRecords: snapshot.recordsFor('livestockMovement'),
        entries: entries,
        scope: scope,
      );
      if (ledger.herdsNeedingAttention.contains(widget.herd.id)) {
        setState(() => _error = l10n.liveMovementNeedsAttention);
        return;
      }

      final delta = _movementType == 'stock_in' ? count : -count;
      final confirmedHeadcount = herdRow['headcount'] as int;
      final currentEstimate =
          confirmedHeadcount + (ledger.pendingDeltaByHerd[widget.herd.id] ?? 0);
      if (currentEstimate + delta < 0) {
        setState(() => _error = l10n.liveMovementWouldBeNegative);
        return;
      }

      final intent = FarmlyCreateLivestockMovementIntent(
        operationId: newFarmlyOperationId(),
        continuityEpoch: scope.continuityEpoch,
        resourceId: newFarmlyOperationId(),
        herdId: widget.herd.id,
        movementType: _movementType,
        delta: delta,
        occurredOn: _occurredOn == null ? null : _civilDate(_occurredOn!),
        dependsOn: [?ledger.latestOperationIdByHerd[widget.herd.id]],
      );
      if (!_scopeIsCurrent()) {
        setState(() => _error = l10n.liveFarmScopeChanged);
        return;
      }
      // Enqueue stays local. The server locks the herd and remains the final
      // authority if another device moves it before this intent arrives.
      await engine.enqueue(FarmlyScopedMutation(scope: scope, intent: intent));
      ref.invalidate(syncStatusProvider);
      ref.invalidate(farmlyLiveLivestockProvider);
      if (mounted) Navigator.of(context).pop(true);
    } on FormatException {
      if (mounted) setState(() => _error = l10n.liveMovementCountInvalid);
    } on ArgumentError {
      if (mounted) setState(() => _error = l10n.liveMovementCountInvalid);
    } catch (_) {
      if (mounted) setState(() => _error = l10n.liveMovementSaveFailed);
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final scopeCurrent = _scopeIsCurrent();
    final choices = <String, String>{
      'stock_in': l10n.liveMovementStockIn,
      'sold': l10n.liveMovementSold,
      'loss': l10n.liveMovementLoss,
    };
    return Padding(
      padding: EdgeInsets.only(bottom: MediaQuery.viewInsetsOf(context).bottom),
      child: SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(
          FarmSpacing.lg,
          FarmSpacing.lg,
          FarmSpacing.lg,
          FarmSpacing.xl,
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(
              l10n.liveMovementDialogTitle,
              style: Theme.of(context).textTheme.titleLarge,
            ),
            const SizedBox(height: FarmSpacing.md),
            FarmCard(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    l10n.liveLivestockConfirmedHeadcount(widget.herd.headcount),
                  ),
                  if (widget.herd.pendingMovements.isNotEmpty) ...[
                    const SizedBox(height: FarmSpacing.xs),
                    Text(
                      l10n.liveMovementPendingBalance(
                        _signedHeadcount(widget.herd.pendingMovementDelta),
                        widget.herd.estimatedHeadcount,
                      ),
                    ),
                  ],
                ],
              ),
            ),
            const SizedBox(height: FarmSpacing.md),
            DropdownButtonFormField<String>(
              key: const ValueKey('live-movement-type'),
              initialValue: _movementType,
              decoration: InputDecoration(
                labelText: l10n.liveMovementTypeLabel,
              ),
              items: [
                for (final entry in choices.entries)
                  DropdownMenuItem(value: entry.key, child: Text(entry.value)),
              ],
              onChanged: _saving || !scopeCurrent
                  ? null
                  : (value) => setState(() {
                      _movementType = value ?? 'stock_in';
                      _error = null;
                    }),
            ),
            const SizedBox(height: FarmSpacing.md),
            TextField(
              key: const ValueKey('live-movement-count'),
              controller: _countController,
              keyboardType: TextInputType.number,
              decoration: InputDecoration(
                labelText: l10n.liveMovementCountLabel,
                errorText: _error == l10n.liveMovementCountInvalid
                    ? _error
                    : null,
              ),
              onChanged: (_) {
                if (_error != null) setState(() => _error = null);
              },
              onSubmitted: (_) => _save(),
            ),
            const SizedBox(height: FarmSpacing.md),
            OutlinedButton.icon(
              key: const ValueKey('live-movement-occurred-on'),
              onPressed: _saving || !scopeCurrent ? null : _chooseDate,
              icon: const Icon(Icons.calendar_month_outlined),
              label: Text(
                _occurredOn == null
                    ? l10n.liveMovementOccurredOnLabel
                    : _civilDate(_occurredOn!),
              ),
            ),
            const SizedBox(height: FarmSpacing.sm),
            Text(
              l10n.liveMovementOccurredOnHelper,
              style: Theme.of(context).textTheme.bodySmall?.copyWith(
                color: FarmThemeExtension.of(context).textSecondary,
              ),
            ),
            if (_error != null && _error != l10n.liveMovementCountInvalid) ...[
              const SizedBox(height: FarmSpacing.sm),
              Text(
                _error!,
                style: TextStyle(
                  color: FarmThemeExtension.of(context).semanticWarning,
                ),
              ),
            ],
            const SizedBox(height: FarmSpacing.lg),
            FilledButton(
              key: const ValueKey('live-movement-save'),
              onPressed: _saving || !scopeCurrent ? null : _save,
              child: Text(l10n.saveOnDevice),
            ),
          ],
        ),
      ),
    );
  }
}

bool _sameSelection(
  FarmlyOrganizationScope expected,
  FarmlyOrganizationScope? current,
) =>
    current != null &&
    current.epoch == expected.epoch &&
    current.organization.id == expected.organization.id &&
    current.organization.status == expected.organization.status &&
    current.organization.role == expected.organization.role &&
    current.selectedFarmId == expected.selectedFarmId &&
    current.directory.continuityEpoch == expected.directory.continuityEpoch &&
    current.directory.scopePolicyVersion ==
        expected.directory.scopePolicyVersion;

bool _sameFarmScope(
  FarmlyMutationScope expected,
  FarmlyMutationScope? current,
) =>
    current != null &&
    current.kind == FarmlyMutationScopeKind.farm &&
    current.accountId == expected.accountId &&
    current.organizationId == expected.organizationId &&
    current.farmId == expected.farmId &&
    current.continuityEpoch == expected.continuityEpoch;

String _civilDate(DateTime date) =>
    '${date.year.toString().padLeft(4, '0')}-'
    '${date.month.toString().padLeft(2, '0')}-'
    '${date.day.toString().padLeft(2, '0')}';

String _signedHeadcount(int count) => count > 0 ? '+$count' : '$count';
