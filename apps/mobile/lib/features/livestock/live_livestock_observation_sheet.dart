import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/auth/auth_session_controller.dart';
import '../../core/sync/farmly_mutation.dart';
import '../../core/sync/sync_providers.dart';
import '../../core/theme/farmly_spacing.dart';
import '../../core/theme/farmly_theme_extension.dart';
import '../../l10n/generated/app_localizations.dart';
import '../organizations/organization_scope_controller.dart';
import 'live_livestock.dart';

final class LiveAnimalObservationSubject {
  const LiveAnimalObservationSubject._({
    required this.id,
    required this.name,
    required this.herd,
  });

  factory LiveAnimalObservationSubject.herd({
    required String id,
    required String name,
  }) => LiveAnimalObservationSubject._(id: id, name: name, herd: true);

  factory LiveAnimalObservationSubject.animal({
    required String id,
    required String name,
  }) => LiveAnimalObservationSubject._(id: id, name: name, herd: false);

  final String id;
  final String name;
  final bool herd;
}

class LiveAnimalObservationCreateSheet extends ConsumerStatefulWidget {
  const LiveAnimalObservationCreateSheet({
    required this.collection,
    required this.subject,
    super.key,
  });

  final FarmlyLiveLivestockCollection collection;
  final LiveAnimalObservationSubject subject;

  @override
  ConsumerState<LiveAnimalObservationCreateSheet> createState() =>
      _LiveAnimalObservationCreateSheetState();
}

class _LiveAnimalObservationCreateSheetState
    extends ConsumerState<LiveAnimalObservationCreateSheet> {
  final _noteController = TextEditingController();
  String _kind = 'note';
  DateTime? _observedOn;
  String? _error;
  bool _saving = false;

  @override
  void dispose() {
    _noteController.dispose();
    super.dispose();
  }

  bool _scopeIsCurrent() {
    final capturedScope = widget.collection.scope;
    final capturedSelection = widget.collection.selectedScope;
    if (capturedScope == null || capturedSelection == null) return false;
    final accountId = ref
        .read(farmlyAuthSessionProvider)
        .asData
        ?.value
        ?.user
        .id;
    final currentSelection = ref.read(selectedOrganizationScopeProvider);
    final currentScope = ref.read(farmlySyncScopeProvider).asData?.value;
    final current = ref.read(farmlyLiveLivestockProvider).asData?.value;
    return accountId == capturedScope.accountId &&
        _sameSelection(capturedSelection, currentSelection) &&
        _sameFarmScope(capturedScope, currentScope) &&
        current?.cacheState == FarmlyLivestockCacheState.ready &&
        current?.canRecordAnimalObservations == true &&
        _subjectIsWritable(current!, widget.subject);
  }

  bool _subjectIsWritable(
    FarmlyLiveLivestockCollection current,
    LiveAnimalObservationSubject subject,
  ) {
    for (final herd in current.herds) {
      if (subject.herd && herd.id == subject.id) {
        return herd.status == 'active';
      }
      if (!subject.herd &&
          herd.status == 'active' &&
          herd.animals.any(
            (animal) => animal.id == subject.id && !animal.archived,
          )) {
        return true;
      }
    }
    return false;
  }

  Future<void> _chooseDate() async {
    final now = DateTime.now();
    final picked = await showDatePicker(
      context: context,
      initialDate: _observedOn ?? DateTime(now.year, now.month, now.day),
      firstDate: DateTime(1900),
      lastDate: DateTime(9999, 12, 31),
      initialEntryMode: DatePickerEntryMode.calendar,
      helpText: AppLocalizations.of(context).liveAnimalObservationDateOptional,
    );
    if (picked != null && mounted) {
      setState(() {
        _observedOn = picked;
        _error = null;
      });
    }
  }

  Future<void> _save() async {
    if (_saving) return;
    final l10n = AppLocalizations.of(context);
    final note = _noteController.text.trim();
    if (note.isEmpty) {
      setState(() => _error = l10n.liveAnimalObservationNoteRequired);
      return;
    }
    if (note.length > 1000) {
      setState(() => _error = l10n.liveAnimalObservationNoteTooLong);
      return;
    }
    if (!_scopeIsCurrent()) {
      setState(() => _error = l10n.liveFarmScopeChanged);
      return;
    }

    late final FarmlyCreateAnimalObservationIntent intent;
    try {
      intent = FarmlyCreateAnimalObservationIntent(
        operationId: newFarmlyOperationId(),
        continuityEpoch: widget.collection.scope!.continuityEpoch,
        resourceId: newFarmlyOperationId(),
        herdId: widget.subject.herd ? widget.subject.id : null,
        animalId: widget.subject.herd ? null : widget.subject.id,
        note: note,
        kind: _kind,
        observedOn: _observedOn == null ? null : _civilDate(_observedOn!),
      );
    } on FormatException {
      setState(() => _error = l10n.liveAnimalObservationNoteTooLong);
      return;
    } on ArgumentError {
      setState(() => _error = l10n.liveAnimalObservationNoteRequired);
      return;
    }

    setState(() {
      _saving = true;
      _error = null;
    });
    try {
      if (!_scopeIsCurrent()) {
        setState(() => _error = l10n.liveFarmScopeChanged);
        return;
      }
      final engine = await ref.read(syncEngineProvider.future);
      if (!_scopeIsCurrent()) {
        setState(() => _error = l10n.liveFarmScopeChanged);
        return;
      }
      await engine.enqueue(
        FarmlyScopedMutation(scope: widget.collection.scope!, intent: intent),
      );
      ref.invalidate(syncStatusProvider);
      ref.invalidate(farmlyLiveLivestockProvider);
      if (mounted) Navigator.of(context).pop(true);
    } catch (_) {
      if (mounted) {
        setState(() => _error = l10n.liveAnimalObservationSaveFailed);
      }
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final scopeCurrent = _scopeIsCurrent();
    final options = <String, String>{
      'note': l10n.liveAnimalObservationGeneral,
      'vet': l10n.liveAnimalObservationVeterinary,
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
              l10n.liveAnimalObservationDialogTitle(widget.subject.name),
              style: Theme.of(context).textTheme.titleLarge,
            ),
            const SizedBox(height: FarmSpacing.md),
            DropdownButtonFormField<String>(
              key: const ValueKey('live-animal-observation-kind'),
              initialValue: _kind,
              decoration: InputDecoration(
                labelText: l10n.liveAnimalObservationKindLabel,
              ),
              items: [
                for (final entry in options.entries)
                  DropdownMenuItem(value: entry.key, child: Text(entry.value)),
              ],
              onChanged: _saving || !scopeCurrent
                  ? null
                  : (value) => setState(() => _kind = value ?? 'note'),
            ),
            const SizedBox(height: FarmSpacing.md),
            TextField(
              key: const ValueKey('live-animal-observation-note'),
              controller: _noteController,
              enabled: !_saving && scopeCurrent,
              minLines: 3,
              maxLines: 5,
              maxLength: 1000,
              keyboardType: TextInputType.multiline,
              decoration: InputDecoration(
                labelText: l10n.liveAnimalObservationNoteLabel,
                alignLabelWithHint: true,
                errorText:
                    _error == l10n.liveAnimalObservationNoteRequired ||
                        _error == l10n.liveAnimalObservationNoteTooLong
                    ? _error
                    : null,
              ),
              onChanged: (_) {
                if (_error != null) setState(() => _error = null);
              },
            ),
            const SizedBox(height: FarmSpacing.sm),
            Semantics(
              button: true,
              label: l10n.liveAnimalObservationDateOptional,
              child: OutlinedButton.icon(
                key: const ValueKey('live-animal-observation-date'),
                onPressed: _saving || !scopeCurrent ? null : _chooseDate,
                icon: const Icon(Icons.calendar_month_outlined),
                label: Text(
                  _observedOn == null
                      ? l10n.liveAnimalObservationDateOptional
                      : _civilDate(_observedOn!),
                ),
              ),
            ),
            Text(
              l10n.liveAnimalObservationDateHelper,
              style: Theme.of(context).textTheme.bodySmall?.copyWith(
                color: FarmThemeExtension.of(context).textSecondary,
              ),
            ),
            if (_error != null &&
                _error != l10n.liveAnimalObservationNoteRequired &&
                _error != l10n.liveAnimalObservationNoteTooLong) ...[
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
              key: const ValueKey('live-animal-observation-save'),
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
