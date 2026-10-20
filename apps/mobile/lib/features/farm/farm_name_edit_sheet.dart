import 'dart:async';

import 'package:flutter/material.dart';

import '../../core/theme/farmly_spacing.dart';
import '../../l10n/generated/app_localizations.dart';

typedef FarmNameSaveCallback = Future<bool> Function(String name);

Future<bool?> showFarmNameEditSheet(
  BuildContext context, {
  required String initialName,
  required bool hasPendingUpdate,
  required FarmNameSaveCallback onSave,
}) => showModalBottomSheet<bool>(
  context: context,
  isScrollControlled: true,
  useSafeArea: true,
  showDragHandle: true,
  builder: (context) => FarmNameEditSheet(
    initialName: initialName,
    hasPendingUpdate: hasPendingUpdate,
    onSave: onSave,
  ),
);

final class FarmNameEditSheet extends StatefulWidget {
  const FarmNameEditSheet({
    required this.initialName,
    required this.hasPendingUpdate,
    required this.onSave,
    super.key,
  });

  final String initialName;
  final bool hasPendingUpdate;
  final FarmNameSaveCallback onSave;

  @override
  State<FarmNameEditSheet> createState() => _FarmNameEditSheetState();
}

final class _FarmNameEditSheetState extends State<FarmNameEditSheet> {
  late final TextEditingController _nameController;
  bool _saving = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    _nameController = TextEditingController(text: widget.initialName);
  }

  @override
  void dispose() {
    _nameController.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    final name = _nameController.text.trim();
    final l10n = AppLocalizations.of(context);
    if (name.isEmpty) {
      setState(() => _error = l10n.createFarmNameRequired);
      return;
    }
    if (name.length > 160) {
      setState(() => _error = l10n.farmNameTooLong);
      return;
    }
    if (name == widget.initialName.trim()) {
      Navigator.of(context).pop(false);
      return;
    }

    setState(() {
      _saving = true;
      _error = null;
    });
    try {
      final saved = await widget.onSave(name);
      if (!mounted) return;
      if (saved) {
        Navigator.of(context).pop(true);
      } else {
        setState(() {
          _saving = false;
          _error = l10n.liveFarmScopeChanged;
        });
      }
    } on Object {
      if (!mounted) return;
      setState(() {
        _saving = false;
        _error = l10n.farmNameUpdateFailed;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final theme = Theme.of(context);
    final bottomInset = MediaQuery.viewInsetsOf(context).bottom;
    return Padding(
      padding: EdgeInsets.fromLTRB(
        FarmSpacing.lg,
        FarmSpacing.sm,
        FarmSpacing.lg,
        FarmSpacing.lg + bottomInset,
      ),
      child: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(l10n.editFarmNameTitle, style: theme.textTheme.titleLarge),
            const SizedBox(height: FarmSpacing.lg),
            TextField(
              key: const ValueKey('farm-edit-name'),
              controller: _nameController,
              enabled: !_saving && !widget.hasPendingUpdate,
              autofocus: true,
              textCapitalization: TextCapitalization.sentences,
              maxLength: 160,
              textInputAction: TextInputAction.done,
              onSubmitted: (_) {
                if (!widget.hasPendingUpdate && !_saving) {
                  unawaited(_save());
                }
              },
              decoration: InputDecoration(
                labelText: l10n.createFarmNameLabel,
                errorText: _error,
              ),
            ),
            if (widget.hasPendingUpdate) ...[
              const SizedBox(height: FarmSpacing.sm),
              Text(
                l10n.farmNamePendingEditLocked,
                style: theme.textTheme.bodyMedium,
              ),
            ],
            const SizedBox(height: FarmSpacing.md),
            SizedBox(
              height: 52,
              child: FilledButton.icon(
                key: const ValueKey('farm-edit-save'),
                onPressed: _saving || widget.hasPendingUpdate ? null : _save,
                icon: _saving
                    ? const SizedBox.square(
                        dimension: 18,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : const Icon(Icons.check_rounded),
                label: Text(_saving ? l10n.creatingFarm : l10n.saveOnDevice),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
