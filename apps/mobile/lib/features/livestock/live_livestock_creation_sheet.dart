import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/auth/auth_session_controller.dart';
import '../../core/sync/farmly_mutation.dart';
import '../../core/sync/sync_models.dart';
import '../../core/sync/sync_providers.dart';
import '../../core/theme/farmly_spacing.dart';
import '../../core/theme/farmly_theme_extension.dart';
import '../../generated/farmly_api_types.dart';
import '../../l10n/generated/app_localizations.dart';
import '../organizations/organization_repository.dart';
import '../organizations/organization_scope_controller.dart';
import 'live_livestock.dart';

class LiveHerdCreateSheet extends ConsumerStatefulWidget {
  const LiveHerdCreateSheet({required this.collection, super.key});

  final FarmlyLiveLivestockCollection collection;

  @override
  ConsumerState<LiveHerdCreateSheet> createState() =>
      _LiveHerdCreateSheetState();
}

class _LiveHerdCreateSheetState extends ConsumerState<LiveHerdCreateSheet> {
  final _speciesController = TextEditingController();
  String _mode = 'batch';
  String? _error;
  bool _saving = false;

  @override
  void dispose() {
    _speciesController.dispose();
    super.dispose();
  }

  bool _scopeIsCurrent() =>
      _scopeAndManagerAreCurrent(widget.collection, ref) != null;

  Future<void> _save() async {
    if (_saving) return;
    final l10n = AppLocalizations.of(context);
    final scopeAndSelection = _scopeAndManagerAreCurrent(
      widget.collection,
      ref,
    );
    if (scopeAndSelection == null) {
      setState(() => _error = l10n.liveFarmScopeChanged);
      return;
    }

    late final FarmlyCreateHerdIntent intent;
    try {
      intent = FarmlyCreateHerdIntent(
        operationId: newFarmlyOperationId(),
        continuityEpoch: scopeAndSelection.scope.continuityEpoch,
        resourceId: newFarmlyOperationId(),
        mode: _mode,
        species: _speciesController.text.trim().isEmpty
            ? null
            : _speciesController.text,
      );
    } on ArgumentError {
      setState(() => _error = l10n.liveHerdSpeciesInvalid);
      return;
    }

    setState(() {
      _saving = true;
      _error = null;
    });
    try {
      final engine = await ref.read(syncEngineProvider.future);
      if (!_scopeIsCurrent()) {
        setState(() => _error = l10n.liveFarmScopeChanged);
        return;
      }
      final snapshot = await engine.domainSnapshot(scopeAndSelection.scope);
      final current = _scopeAndManagerAreCurrent(widget.collection, ref);
      if (current == null ||
          !_sameFarmScope(scopeAndSelection.scope, current.scope) ||
          snapshot == null ||
          snapshot.cursor.continuityEpoch !=
              scopeAndSelection.selection.directory.continuityEpoch ||
          snapshot.cursor.scopePolicyVersion !=
              scopeAndSelection.selection.directory.scopePolicyVersion) {
        setState(() => _error = l10n.liveFarmScopeChanged);
        return;
      }
      if (!_scopeIsCurrent()) {
        setState(() => _error = l10n.liveFarmScopeChanged);
        return;
      }
      await engine.enqueue(
        FarmlyScopedMutation(scope: scopeAndSelection.scope, intent: intent),
      );
      ref.invalidate(syncStatusProvider);
      ref.invalidate(farmlyLiveLivestockProvider);
      if (mounted) Navigator.of(context).pop(true);
    } catch (_) {
      if (mounted) setState(() => _error = l10n.liveHerdCreateSaveFailed);
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final tokens = FarmThemeExtension.of(context);
    final scopeCurrent = _scopeIsCurrent();
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
              l10n.liveHerdCreateTitle,
              style: Theme.of(context).textTheme.titleLarge,
            ),
            const SizedBox(height: FarmSpacing.md),
            Text(
              l10n.liveHerdModeLabel,
              style: Theme.of(context).textTheme.titleSmall,
            ),
            const SizedBox(height: FarmSpacing.xs),
            Wrap(
              spacing: FarmSpacing.sm,
              runSpacing: FarmSpacing.xs,
              children: [
                for (final choice in [
                  ('batch', l10n.herdModeBatch),
                  ('tracked', l10n.herdModeTracked),
                ])
                  ChoiceChip(
                    key: ValueKey('live-herd-mode-${choice.$1}'),
                    label: Text(choice.$2),
                    selected: _mode == choice.$1,
                    onSelected: _saving || !scopeCurrent
                        ? null
                        : (selected) {
                            if (selected) {
                              setState(() {
                                _mode = choice.$1;
                                _error = null;
                              });
                            }
                          },
                    padding: const EdgeInsets.symmetric(horizontal: 12),
                  ),
              ],
            ),
            const SizedBox(height: FarmSpacing.md),
            TextField(
              key: const ValueKey('live-herd-species'),
              controller: _speciesController,
              enabled: !_saving && scopeCurrent,
              maxLength: 120,
              textCapitalization: TextCapitalization.words,
              decoration: InputDecoration(
                labelText: l10n.liveHerdSpeciesLabel,
                errorText: _error == l10n.liveHerdSpeciesInvalid
                    ? _error
                    : null,
              ),
              onChanged: (_) {
                if (_error != null) setState(() => _error = null);
              },
              onSubmitted: (_) => _save(),
            ),
            Text(
              l10n.liveHerdNoInitialCountHelper,
              style: Theme.of(
                context,
              ).textTheme.bodySmall?.copyWith(color: tokens.textSecondary),
            ),
            if (_error != null && _error != l10n.liveHerdSpeciesInvalid) ...[
              const SizedBox(height: FarmSpacing.sm),
              _CreationError(message: _error!),
            ],
            const SizedBox(height: FarmSpacing.lg),
            FilledButton(
              key: const ValueKey('live-herd-save'),
              onPressed: _saving || !scopeCurrent ? null : _save,
              child: Text(l10n.liveHerdCreateAction),
            ),
          ],
        ),
      ),
    );
  }
}

class LiveAnimalCreateSheet extends ConsumerStatefulWidget {
  const LiveAnimalCreateSheet({
    required this.collection,
    required this.herd,
    super.key,
  });

  final FarmlyLiveLivestockCollection collection;
  final FarmlyLiveHerd herd;

  @override
  ConsumerState<LiveAnimalCreateSheet> createState() =>
      _LiveAnimalCreateSheetState();
}

class _LiveAnimalCreateSheetState extends ConsumerState<LiveAnimalCreateSheet> {
  final _tagController = TextEditingController();
  final _nameController = TextEditingController();
  DateTime? _birthDate;
  String? _error;
  bool _saving = false;

  @override
  void dispose() {
    _tagController.dispose();
    _nameController.dispose();
    super.dispose();
  }

  bool _scopeIsCurrent() {
    final current = _scopeAndManagerAreCurrent(widget.collection, ref);
    return current != null &&
        current.collection.herds.any(
          (herd) =>
              herd.id == widget.herd.id &&
              !herd.isBatch &&
              herd.status == 'active',
        );
  }

  Future<void> _chooseBirthDate() async {
    final now = DateTime.now();
    final picked = await showDatePicker(
      context: context,
      initialDate: _birthDate ?? DateTime(now.year, now.month, now.day),
      firstDate: DateTime(1900),
      lastDate: DateTime(9999, 12, 31),
      initialEntryMode: DatePickerEntryMode.calendar,
      helpText: AppLocalizations.of(context).liveAnimalBirthDateOptional,
    );
    if (picked != null && mounted) {
      setState(() {
        _birthDate = picked;
        _error = null;
      });
    }
  }

  Future<void> _save() async {
    if (_saving) return;
    final l10n = AppLocalizations.of(context);
    final current = _scopeAndManagerAreCurrent(widget.collection, ref);
    final tag = farmlyTrimAnimalTag(_tagController.text);
    if (tag.isEmpty || tag.length > 64) {
      setState(() => _error = l10n.liveAnimalTagInvalid);
      return;
    }
    if (_nameController.text.trim().length > 160) {
      setState(() => _error = l10n.liveAnimalNameInvalid);
      return;
    }
    if (current == null || !_scopeIsCurrent()) {
      setState(() => _error = l10n.liveFarmScopeChanged);
      return;
    }

    setState(() {
      _saving = true;
      _error = null;
    });
    try {
      final scope = current.scope;
      final selection = current.selection;
      final engine = await ref.read(syncEngineProvider.future);
      if (!_scopeIsCurrent()) {
        setState(() => _error = l10n.liveFarmScopeChanged);
        return;
      }
      final snapshot = await engine.domainSnapshot(scope);
      final afterSnapshot = _scopeAndManagerAreCurrent(widget.collection, ref);
      if (afterSnapshot == null ||
          !_sameFarmScope(scope, afterSnapshot.scope) ||
          snapshot == null ||
          snapshot.cursor.continuityEpoch !=
              selection.directory.continuityEpoch ||
          snapshot.cursor.scopePolicyVersion !=
              selection.directory.scopePolicyVersion) {
        setState(() => _error = l10n.liveFarmScopeChanged);
        return;
      }

      final herdRow = snapshot.recordsFor('herd')[widget.herd.id];
      String? parentOperationId;
      if (herdRow is Map) {
        if (herdRow['mode'] != 'tracked' || herdRow['status'] != 'active') {
          setState(() => _error = l10n.liveFarmScopeChanged);
          return;
        }
      } else {
        final entries = await engine.entries(
          accountId: scope.accountId,
          organizationId: scope.organizationId,
        );
        if (!_scopeIsCurrent()) {
          setState(() => _error = l10n.liveFarmScopeChanged);
          return;
        }
        final parents = entries
            .where(
              (entry) =>
                  _entryMatchesScope(entry, scope) &&
                  entry.mutation.intent.type == 'herd.create' &&
                  entry.mutation.intent.resourceId == widget.herd.id,
            )
            .toList(growable: false);
        if (parents.length != 1) {
          setState(() => _error = l10n.liveFarmScopeChanged);
          return;
        }
        final parent = parents.single;
        final payload = parent.mutation.intent.payload;
        late final FarmlyCreateHerdIntent restoredParent;
        try {
          restoredParent = FarmlyCreateHerdIntent(
            operationId: parent.operationId,
            continuityEpoch: scope.continuityEpoch,
            resourceId: parent.mutation.intent.resourceId,
            mode: _requiredString(payload, 'mode'),
            species: _optionalString(payload, 'species'),
            status: _optionalString(payload, 'status'),
            dependsOn: parent.dependsOn,
          );
        } on FormatException {
          setState(() => _error = l10n.liveFarmScopeChanged);
          return;
        } on ArgumentError {
          setState(() => _error = l10n.liveFarmScopeChanged);
          return;
        }
        if (restoredParent.payload['mode'] != 'tracked' ||
            (restoredParent.payload['status'] as String? ?? 'active') !=
                'active') {
          setState(() => _error = l10n.liveFarmScopeChanged);
          return;
        }
        switch (parent.status) {
          case OutboxEntryStatus.pending:
          case OutboxEntryStatus.inFlight:
            parentOperationId = parent.operationId;
            break;
          case OutboxEntryStatus.applied:
            break;
          case OutboxEntryStatus.rejected:
          case OutboxEntryStatus.conflict:
          case OutboxEntryStatus.blocked:
            setState(() => _error = l10n.liveFarmScopeChanged);
            return;
        }
      }

      final intent = FarmlyCreateAnimalIntent(
        operationId: newFarmlyOperationId(),
        continuityEpoch: scope.continuityEpoch,
        resourceId: newFarmlyOperationId(),
        herdId: widget.herd.id,
        tag: tag,
        name: _nameController.text.trim().isEmpty ? null : _nameController.text,
        birthDate: _birthDate == null ? null : _civilDate(_birthDate!),
        dependsOn: [?parentOperationId],
      );
      if (!_scopeIsCurrent()) {
        setState(() => _error = l10n.liveFarmScopeChanged);
        return;
      }
      await engine.enqueue(FarmlyScopedMutation(scope: scope, intent: intent));
      ref.invalidate(syncStatusProvider);
      ref.invalidate(farmlyLiveLivestockProvider);
      if (mounted) Navigator.of(context).pop(true);
    } on FormatException {
      if (mounted) setState(() => _error = l10n.liveAnimalTagInvalid);
    } on ArgumentError {
      if (mounted) setState(() => _error = l10n.liveAnimalTagInvalid);
    } catch (_) {
      if (mounted) setState(() => _error = l10n.liveAnimalCreateSaveFailed);
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final tokens = FarmThemeExtension.of(context);
    final scopeCurrent = _scopeIsCurrent();
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
              l10n.liveAnimalCreateTitle,
              style: Theme.of(context).textTheme.titleLarge,
            ),
            const SizedBox(height: FarmSpacing.md),
            TextField(
              key: const ValueKey('live-animal-tag'),
              controller: _tagController,
              enabled: !_saving && scopeCurrent,
              maxLength: 64,
              textCapitalization: TextCapitalization.characters,
              decoration: InputDecoration(
                labelText: l10n.liveAnimalTagLabel,
                errorText: _error == l10n.liveAnimalTagInvalid ? _error : null,
              ),
              onChanged: (_) {
                if (_error != null) setState(() => _error = null);
              },
            ),
            const SizedBox(height: FarmSpacing.sm),
            TextField(
              key: const ValueKey('live-animal-name'),
              controller: _nameController,
              enabled: !_saving && scopeCurrent,
              maxLength: 160,
              textCapitalization: TextCapitalization.words,
              decoration: InputDecoration(
                labelText: l10n.liveAnimalNameLabel,
                errorText: _error == l10n.liveAnimalNameInvalid ? _error : null,
              ),
              onChanged: (_) {
                if (_error != null) setState(() => _error = null);
              },
            ),
            const SizedBox(height: FarmSpacing.sm),
            OutlinedButton.icon(
              key: const ValueKey('live-animal-birth-date'),
              onPressed: _saving || !scopeCurrent ? null : _chooseBirthDate,
              icon: const Icon(Icons.calendar_month_outlined),
              label: Text(
                _birthDate == null
                    ? l10n.liveAnimalBirthDateOptional
                    : _civilDate(_birthDate!),
              ),
            ),
            Text(
              l10n.liveAnimalBirthDateHelper,
              style: Theme.of(
                context,
              ).textTheme.bodySmall?.copyWith(color: tokens.textSecondary),
            ),
            if (_error != null &&
                _error != l10n.liveAnimalTagInvalid &&
                _error != l10n.liveAnimalNameInvalid) ...[
              const SizedBox(height: FarmSpacing.sm),
              _CreationError(message: _error!),
            ],
            const SizedBox(height: FarmSpacing.lg),
            FilledButton(
              key: const ValueKey('live-animal-save'),
              onPressed: _saving || !scopeCurrent ? null : _save,
              child: Text(l10n.liveAnimalCreateAction),
            ),
          ],
        ),
      ),
    );
  }
}

class LiveAnimalEditSheet extends ConsumerStatefulWidget {
  const LiveAnimalEditSheet({
    required this.collection,
    required this.herd,
    required this.animal,
    super.key,
  });

  final FarmlyLiveLivestockCollection collection;
  final FarmlyLiveHerd herd;
  final FarmlyLiveAnimal animal;

  @override
  ConsumerState<LiveAnimalEditSheet> createState() =>
      _LiveAnimalEditSheetState();
}

class _LiveAnimalEditSheetState extends ConsumerState<LiveAnimalEditSheet> {
  late final TextEditingController _tagController;
  late final TextEditingController _nameController;
  DateTime? _birthDate;
  String? _error;
  bool _saving = false;

  @override
  void initState() {
    super.initState();
    _tagController = TextEditingController(text: widget.animal.tag);
    _nameController = TextEditingController(text: widget.animal.name ?? '');
  }

  @override
  void dispose() {
    _tagController.dispose();
    _nameController.dispose();
    super.dispose();
  }

  bool _scopeIsCurrent() {
    final current = _scopeAndManagerAreCurrent(widget.collection, ref);
    return current != null &&
        current.collection.herds.any(
          (herd) =>
              herd.id == widget.herd.id &&
              herd.mode == 'tracked' &&
              herd.status == 'active',
        );
  }

  Future<void> _chooseBirthDate() async {
    final now = DateTime.now();
    final existingDate = widget.animal.birthDate == null
        ? null
        : DateTime.tryParse(widget.animal.birthDate!);
    final picked = await showDatePicker(
      context: context,
      initialDate:
          _birthDate ?? existingDate ?? DateTime(now.year, now.month, now.day),
      firstDate: DateTime(1900),
      lastDate: DateTime(9999, 12, 31),
      initialEntryMode: DatePickerEntryMode.calendar,
      helpText: AppLocalizations.of(context).liveAnimalBirthDateOptional,
    );
    if (picked != null && mounted) {
      setState(() {
        _birthDate = picked;
        _error = null;
      });
    }
  }

  Future<void> _save() async {
    if (_saving) return;
    final l10n = AppLocalizations.of(context);
    final tag = farmlyTrimAnimalTag(_tagController.text);
    final name = _nameController.text.trim();
    if (tag.isEmpty || tag.length > 64) {
      setState(() => _error = l10n.liveAnimalTagInvalid);
      return;
    }
    if (name.length > 160 ||
        (widget.animal.name?.trim().isNotEmpty == true && name.isEmpty)) {
      setState(
        () => _error = name.isEmpty
            ? l10n.liveAnimalNameCannotBeCleared
            : l10n.liveAnimalNameInvalid,
      );
      return;
    }
    final initial = _scopeAndManagerAreCurrent(widget.collection, ref);
    if (initial == null || !_scopeIsCurrent()) {
      setState(() => _error = l10n.liveFarmScopeChanged);
      return;
    }

    final normalizedInitialName = widget.animal.name?.trim() ?? '';
    final nextBirthDate = _birthDate == null ? null : _civilDate(_birthDate!);
    final tagChanged = tag != widget.animal.tag;
    final nameChanged = name != normalizedInitialName;
    final birthDateChanged =
        nextBirthDate != null && nextBirthDate != widget.animal.birthDate;
    if (!tagChanged && !nameChanged && !birthDateChanged) {
      Navigator.of(context).pop(false);
      return;
    }

    setState(() {
      _saving = true;
      _error = null;
    });
    try {
      final scope = initial.scope;
      final selection = initial.selection;
      final engine = await ref.read(syncEngineProvider.future);
      if (!_scopeIsCurrent()) {
        setState(() => _error = l10n.liveFarmScopeChanged);
        return;
      }
      final snapshot = await engine.domainSnapshot(scope);
      final afterSnapshot = _scopeAndManagerAreCurrent(widget.collection, ref);
      if (afterSnapshot == null ||
          !_sameFarmScope(scope, afterSnapshot.scope) ||
          snapshot == null ||
          snapshot.cursor.continuityEpoch !=
              selection.directory.continuityEpoch ||
          snapshot.cursor.scopePolicyVersion !=
              selection.directory.scopePolicyVersion) {
        setState(() => _error = l10n.liveFarmScopeChanged);
        return;
      }

      final herdRow = snapshot.recordsFor('herd')[widget.herd.id];
      if (herdRow is! Map) {
        setState(() => _error = l10n.liveFarmScopeChanged);
        return;
      }
      final herd = FarmlyHerdDto.fromJson(Map<String, dynamic>.from(herdRow));
      if (herd.id != widget.animal.herdId ||
          herd.mode != 'tracked' ||
          herd.status != 'active') {
        setState(() => _error = l10n.liveFarmScopeChanged);
        return;
      }

      final animalRow = snapshot.recordsFor('animal')[widget.animal.id];
      if (animalRow is! Map) {
        setState(() => _error = l10n.liveFarmScopeChanged);
        return;
      }
      final animal = FarmlyAnimalDto.fromJson(
        Map<String, dynamic>.from(animalRow),
      );
      if (widget.animal.syncState != FarmlyLivestockEntitySyncState.confirmed ||
          widget.animal.hasUnresolvedUpdate ||
          animal.id != widget.animal.id ||
          animal.version < 1 ||
          animal.version != widget.animal.version ||
          animal.herdId != widget.herd.id ||
          animal.archived ||
          !_scopeIsCurrent()) {
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
      final unresolvedUpdate = entries.any(
        (entry) =>
            _entryMatchesScope(entry, scope) &&
            entry.mutation.intent.type == 'animal.update' &&
            entry.mutation.intent.resourceId == animal.id &&
            _animalUpdateIsUnresolved(entry, animal.version),
      );
      if (unresolvedUpdate) {
        setState(() => _error = l10n.liveFarmScopeChanged);
        return;
      }
      if (tagChanged &&
          _animalTagIsReserved(
            tag: tag,
            animalId: animal.id,
            snapshotRecords: snapshot.recordsFor('animal'),
            entries: entries,
            scope: scope,
          )) {
        setState(() => _error = l10n.liveAnimalTagDuplicate);
        return;
      }

      final intent = FarmlyUpdateAnimalIntent(
        operationId: newFarmlyOperationId(),
        continuityEpoch: scope.continuityEpoch,
        resourceId: animal.id,
        baseVersion: animal.version,
        tag: tagChanged ? tag : null,
        name: nameChanged ? name : null,
        birthDate: birthDateChanged ? nextBirthDate : null,
      );
      if (!_scopeIsCurrent()) {
        setState(() => _error = l10n.liveFarmScopeChanged);
        return;
      }
      await engine.enqueue(FarmlyScopedMutation(scope: scope, intent: intent));
      ref.invalidate(syncStatusProvider);
      ref.invalidate(farmlyLiveLivestockProvider);
      if (mounted) Navigator.of(context).pop(true);
    } catch (_) {
      if (mounted) setState(() => _error = l10n.liveAnimalEditSaveFailed);
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final tokens = FarmThemeExtension.of(context);
    final scopeCurrent = _scopeIsCurrent();
    final birthDateLabel = _birthDate == null
        ? widget.animal.birthDate ?? l10n.liveAnimalBirthDateOptional
        : _civilDate(_birthDate!);
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
              l10n.liveAnimalEditTitle,
              style: Theme.of(context).textTheme.titleLarge,
            ),
            const SizedBox(height: FarmSpacing.md),
            TextField(
              key: const ValueKey('live-animal-tag'),
              controller: _tagController,
              enabled: !_saving && scopeCurrent,
              maxLength: 64,
              textCapitalization: TextCapitalization.characters,
              decoration: InputDecoration(
                labelText: l10n.liveAnimalTagLabel,
                errorText: _error == l10n.liveAnimalTagInvalid ? _error : null,
              ),
              onChanged: (_) {
                if (_error != null) setState(() => _error = null);
              },
            ),
            const SizedBox(height: FarmSpacing.sm),
            TextField(
              key: const ValueKey('live-animal-name'),
              controller: _nameController,
              enabled: !_saving && scopeCurrent,
              maxLength: 160,
              textCapitalization: TextCapitalization.words,
              decoration: InputDecoration(
                labelText: l10n.liveAnimalNameLabel,
                errorText: _error == l10n.liveAnimalNameInvalid ? _error : null,
              ),
              onChanged: (_) {
                if (_error != null) setState(() => _error = null);
              },
            ),
            const SizedBox(height: FarmSpacing.sm),
            OutlinedButton.icon(
              key: const ValueKey('live-animal-birth-date'),
              onPressed: _saving || !scopeCurrent ? null : _chooseBirthDate,
              icon: const Icon(Icons.calendar_month_outlined),
              label: Text(birthDateLabel),
            ),
            Text(
              l10n.liveAnimalBirthDateHelper,
              style: Theme.of(
                context,
              ).textTheme.bodySmall?.copyWith(color: tokens.textSecondary),
            ),
            if (_error != null &&
                _error != l10n.liveAnimalTagInvalid &&
                _error != l10n.liveAnimalNameInvalid) ...[
              const SizedBox(height: FarmSpacing.sm),
              _CreationError(
                key: const ValueKey('live-animal-edit-error'),
                message: _error!,
              ),
            ],
            const SizedBox(height: FarmSpacing.lg),
            FilledButton(
              key: const ValueKey('live-animal-edit-save'),
              onPressed: _saving || !scopeCurrent ? null : _save,
              child: Text(l10n.liveAnimalEditAction),
            ),
          ],
        ),
      ),
    );
  }
}

final class _ScopeAndSelection {
  const _ScopeAndSelection({
    required this.scope,
    required this.selection,
    required this.collection,
  });

  final FarmlyMutationScope scope;
  final FarmlyOrganizationScope selection;
  final FarmlyLiveLivestockCollection collection;
}

_ScopeAndSelection? _scopeAndManagerAreCurrent(
  FarmlyLiveLivestockCollection expected,
  WidgetRef ref,
) {
  final scope = expected.scope;
  final selection = expected.selectedScope;
  if (scope == null || selection == null) return null;
  final accountId = ref.read(farmlyAuthSessionProvider).asData?.value?.user.id;
  final currentSelection = ref.read(selectedOrganizationScopeProvider);
  final currentScope = ref.read(farmlySyncScopeProvider).asData?.value;
  final current = ref.read(farmlyLiveLivestockProvider).asData?.value;
  if (accountId != scope.accountId ||
      !_sameSelection(selection, currentSelection) ||
      !_sameFarmScope(scope, currentScope) ||
      scope.continuityEpoch != selection.directory.continuityEpoch ||
      selection.selectedFarm == null ||
      selection.selectedFarm!.status != FarmlyFarmStatus.active ||
      expected.cacheState != FarmlyLivestockCacheState.ready ||
      expected.canManageHerds != true ||
      current == null ||
      current.cacheState != FarmlyLivestockCacheState.ready ||
      current.canManageHerds != true ||
      current.scope == null ||
      !_sameFarmScope(scope, current.scope)) {
    return null;
  }
  return _ScopeAndSelection(
    scope: scope,
    selection: selection,
    collection: current,
  );
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
        expected.directory.scopePolicyVersion &&
    current.selectedFarm?.grantRole == expected.selectedFarm?.grantRole;

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

bool _entryMatchesScope(OutboxEntry entry, FarmlyMutationScope scope) {
  final entryScope = entry.mutation.scope;
  return entryScope.kind == FarmlyMutationScopeKind.farm &&
      entryScope.accountId == scope.accountId &&
      entryScope.organizationId == scope.organizationId &&
      entryScope.farmId == scope.farmId &&
      entryScope.continuityEpoch == scope.continuityEpoch;
}

bool _animalUpdateIsUnresolved(OutboxEntry entry, int currentVersion) {
  if (entry.status == OutboxEntryStatus.rejected) return false;
  if (entry.status != OutboxEntryStatus.applied) return true;
  final baseVersion = entry.mutation.intent.baseVersion;
  return baseVersion == null || currentVersion <= baseVersion;
}

bool _animalTagIsReserved({
  required String tag,
  required String animalId,
  required Map<String, Object?> snapshotRecords,
  required List<OutboxEntry> entries,
  required FarmlyMutationScope scope,
}) {
  for (final row in snapshotRecords.values) {
    if (row is! Map) {
      throw const FormatException('Invalid local animal snapshot');
    }
    if (row['id'] == animalId) continue;
    final existingTag = row['tag'];
    if (existingTag is String && farmlyTrimAnimalTag(existingTag) == tag) {
      return true;
    }
  }
  for (final entry in entries) {
    if (!_entryMatchesScope(entry, scope) ||
        entry.mutation.intent.resourceId == animalId ||
        entry.status == OutboxEntryStatus.rejected ||
        (entry.mutation.intent.type != 'animal.create' &&
            entry.mutation.intent.type != 'animal.update')) {
      continue;
    }
    if (entry.mutation.intent.type == 'animal.update' &&
        entry.status == OutboxEntryStatus.applied) {
      final resourceId = entry.mutation.intent.resourceId;
      final baseVersion = entry.mutation.intent.baseVersion;
      final currentRow = snapshotRecords[resourceId];
      final currentVersion = currentRow is Map ? currentRow['version'] : null;
      if (baseVersion != null &&
          currentRow is Map &&
          currentRow['id'] == resourceId &&
          currentVersion is int &&
          currentVersion > baseVersion) {
        continue;
      }
    }
    final proposedTag = entry.mutation.intent.payload['tag'];
    if (proposedTag is String && farmlyTrimAnimalTag(proposedTag) == tag) {
      return true;
    }
  }
  return false;
}

String _requiredString(Map<String, Object?> payload, String key) {
  final value = payload[key];
  if (value is! String) {
    throw const FormatException('Invalid local livestock create intent');
  }
  return value;
}

String? _optionalString(Map<String, Object?> payload, String key) {
  if (!payload.containsKey(key)) return null;
  final value = payload[key];
  if (value is! String) {
    throw const FormatException('Invalid local livestock create intent');
  }
  return value;
}

String _civilDate(DateTime date) =>
    '${date.year.toString().padLeft(4, '0')}-'
    '${date.month.toString().padLeft(2, '0')}-'
    '${date.day.toString().padLeft(2, '0')}';

class _CreationError extends StatelessWidget {
  const _CreationError({super.key, required this.message});

  final String message;

  @override
  Widget build(BuildContext context) => Text(
    message,
    style: TextStyle(color: FarmThemeExtension.of(context).semanticWarning),
  );
}
