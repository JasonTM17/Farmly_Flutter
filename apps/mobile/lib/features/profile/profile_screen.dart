import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/auth/auth_session_controller.dart';
import '../../core/auth/farmly_auth_models.dart';
import '../../core/privacy/privacy_repository.dart';
import '../../core/theme/farmly_spacing.dart';
import '../../core/theme/farmly_theme_extension.dart';
import '../../l10n/generated/app_localizations.dart';
import '../../ui/farm_card.dart';
import '../../ui/farm_scaffold.dart';
import '../../ui/pickers.dart';
import '../app/app_routes.dart';
import '../demo/demo_models.dart';
import '../demo/demo_providers.dart';
import '../organizations/organization_scope_controller.dart';

/// Profile tab: org picker, farm picker showing org + farm names, sync entry,
/// AI consent + usage, settings and logout (spec 02 §5 Profile row).
class ProfileScreen extends ConsumerWidget {
  const ProfileScreen({super.key});

  Future<void> _confirmLogout(BuildContext context, WidgetRef ref) async {
    final l10n = AppLocalizations.of(context);
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: Text(l10n.signOutTitle),
        content: Text(l10n.signOutBody),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(false),
            child: Text(l10n.cancel),
          ),
          FilledButton(
            onPressed: () => Navigator.of(dialogContext).pop(true),
            child: Text(l10n.signOut),
          ),
        ],
      ),
    );
    if (confirmed != true) return;
    String? message;
    try {
      await ref.read(farmlyAuthSessionProvider.notifier).signOut();
    } on FarmlyAuthFailure catch (error) {
      message = error.code == FarmlyAuthFailureCode.signOutUnconfirmed
          ? l10n.signOutUnconfirmed
          : l10n.authUnavailable;
    } catch (_) {
      message = l10n.authUnavailable;
    }
    ref.read(selectedOrganizationScopeProvider.notifier).clear();
    if (!context.mounted) return;
    context.go(AppRoutes.login);
    if (message != null) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(message)));
    }
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final state = ref.watch(demoDataProvider);
    final authSession = ref.watch(farmlyAuthSessionProvider);
    final session = authSession.hasValue ? authSession.value?.user : null;
    final scope = ref.watch(selectedOrganizationScopeProvider);
    final consent = ref.watch(aiConsentProvider);
    final tokens = FarmThemeExtension.of(context);
    final l10n = AppLocalizations.of(context);
    final pendingCount = state.syncItems
        .where((item) => item.status != DemoSyncStatus.conflict)
        .length;
    final conflictCount = state.syncItems
        .where((item) => item.status == DemoSyncStatus.conflict)
        .length;

    return FarmScaffold(
      topBar: FarmTopBar(title: l10n.profileTab),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(
          FarmSpacing.lg,
          0,
          FarmSpacing.lg,
          FarmSpacing.xxl,
        ),
        children: [
          FarmCard(
            child: Row(
              children: [
                CircleAvatar(
                  radius: 26,
                  backgroundColor: tokens.brandAction,
                  child: Text(
                    (session?.name ?? 'F').characters.first.toUpperCase(),
                    style: Theme.of(
                      context,
                    ).textTheme.titleMedium?.copyWith(color: tokens.onAction),
                  ),
                ),
                const SizedBox(width: FarmSpacing.lg),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        session?.name ?? l10n.appName,
                        style: Theme.of(context).textTheme.titleMedium,
                        softWrap: true,
                      ),
                      Text(
                        session?.email ?? '',
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
          ),
          const SizedBox(height: FarmSpacing.md),
          FarmCard(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  l10n.organizationTitle,
                  style: Theme.of(context).textTheme.titleSmall,
                ),
                const SizedBox(height: FarmSpacing.xs),
                Text(
                  scope?.organization.name ?? l10n.organizationEmptyTitle,
                  style: Theme.of(context).textTheme.bodyLarge,
                  softWrap: true,
                ),
                Align(
                  alignment: Alignment.centerLeft,
                  child: TextButton(
                    onPressed: () => showFarmPickerSheet(context),
                    child: Text(l10n.changeFarm),
                  ),
                ),
                const Divider(),
                Text(
                  l10n.farmTab,
                  style: Theme.of(context).textTheme.titleSmall,
                ),
                const SizedBox(height: FarmSpacing.xs),
                Text(
                  l10n.farmCount(scope?.directory.farms.length ?? 0),
                  style: Theme.of(context).textTheme.bodyLarge,
                  softWrap: true,
                ),
                Align(
                  alignment: Alignment.centerLeft,
                  child: TextButton(
                    onPressed: () => context.push(AppRoutes.organizations),
                    child: Text(l10n.changeOrganization),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: FarmSpacing.md),
          FarmCard(
            onTap: () => context.push(AppRoutes.syncCenter),
            child: Row(
              children: [
                const Icon(Icons.sync_outlined),
                const SizedBox(width: FarmSpacing.md),
                Expanded(
                  child: Text(
                    l10n.profileSyncCenter,
                    style: Theme.of(context).textTheme.titleSmall,
                    softWrap: true,
                  ),
                ),
                Flexible(
                  child: SyncStatusBadge(
                    pendingCount: pendingCount,
                    conflictCount: conflictCount,
                  ),
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
                  'Farmly AI',
                  style: Theme.of(context).textTheme.titleSmall,
                ),
                const SizedBox(height: FarmSpacing.xs),
                Text(
                  consent.decisionRecorded
                      ? (consent.contextualAccepted
                            ? l10n.profileAiConsentAccepted(consent.revision)
                            : l10n.profileAiConsentGeneral)
                      : l10n.profileAiConsentUnselected,
                  style: Theme.of(context).textTheme.bodyMedium,
                  softWrap: true,
                ),
                const SizedBox(height: FarmSpacing.sm),
                Text(
                  consent.usageState == 'known'
                      ? l10n.profileAiUsageKnown(
                          consent.inputTokensThisMonth,
                          consent.outputTokensThisMonth,
                        )
                      : l10n.profileAiUsageUnavailable,
                  style: Theme.of(
                    context,
                  ).textTheme.bodySmall?.copyWith(color: tokens.textSecondary),
                  softWrap: true,
                ),
              ],
            ),
          ),
          if (session != null) ...[
            const SizedBox(height: FarmSpacing.md),
            const _LivePrivacyCard(),
          ],
          const SizedBox(height: FarmSpacing.md),
          FarmCard(
            child: Column(
              children: [
                ListTile(
                  contentPadding: EdgeInsets.zero,
                  leading: const Icon(Icons.language_outlined),
                  title: Text(l10n.profileLanguageTitle),
                  subtitle: Text(l10n.profileLanguageSubtitle),
                ),
                ListTile(
                  contentPadding: EdgeInsets.zero,
                  leading: const Icon(Icons.accessibility_new_outlined),
                  title: Text(l10n.profileAccessibilityTitle),
                  subtitle: Text(l10n.profileAccessibilitySubtitle),
                ),
              ],
            ),
          ),
          const SizedBox(height: FarmSpacing.md),
          FilledButton.tonal(
            onPressed: () => _confirmLogout(context, ref),
            child: Text(l10n.signOut),
          ),
        ],
      ),
    );
  }
}

/// Server-backed privacy actions (export / delete-history / withdraw AI
/// consent) — rendered only for a signed-in account. Every call is an audited
/// `POST /v1/me/privacy-requests`; destructive paths confirm first.
class _LivePrivacyCard extends ConsumerStatefulWidget {
  const _LivePrivacyCard();

  @override
  ConsumerState<_LivePrivacyCard> createState() => _LivePrivacyCardState();
}

class _LivePrivacyCardState extends ConsumerState<_LivePrivacyCard> {
  PrivacyAction? _running;

  Future<void> _run(PrivacyAction action) async {
    final l10n = AppLocalizations.of(context);
    if (action == PrivacyAction.deleteHistory ||
        action == PrivacyAction.withdrawAiConsent) {
      final confirmed = await showDialog<bool>(
        context: context,
        builder: (dialogContext) => AlertDialog(
          content: Text(
            action == PrivacyAction.deleteHistory
                ? l10n.privacyDeleteHistoryConfirm
                : l10n.privacyWithdrawAiConfirm,
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(dialogContext).pop(false),
              child: Text(l10n.cancel),
            ),
            FilledButton(
              onPressed: () => Navigator.of(dialogContext).pop(true),
              child: Text(l10n.confirm),
            ),
          ],
        ),
      );
      if (confirmed != true) return;
    }
    setState(() => _running = action);
    try {
      final result = await ref
          .read(privacyRepositoryProvider)
          .createRequest(
            action,
            confirmation: switch (action) {
              PrivacyAction.deleteHistory => 'confirmed-delete-history',
              PrivacyAction.withdrawAiConsent =>
                'confirmed-withdraw-ai-consent',
              PrivacyAction.export => null,
            },
          );
      if (!mounted) return;
      if (action == PrivacyAction.export) {
        _showExport(result.payload);
      } else {
        final count = switch (action) {
          PrivacyAction.deleteHistory =>
            result.payload?['conversationsDeleted'] as int? ?? 0,
          _ => 0,
        };
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              action == PrivacyAction.deleteHistory
                  ? l10n.privacyDeleteHistoryDone(count)
                  : l10n.privacyWithdrawAiDone,
            ),
          ),
        );
      }
    } catch (_) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(l10n.privacyRequestFailed)),
      );
    } finally {
      if (mounted) setState(() => _running = null);
    }
  }

  void _showExport(Map<String, Object?>? payload) {
    final l10n = AppLocalizations.of(context);
    final json = const JsonEncoder.withIndent(
      '  ',
    ).convert(payload ?? const {});
    showDialog<void>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: Text(l10n.privacyExportDone),
        content: SizedBox(
          width: double.maxFinite,
          height: 320,
          child: SingleChildScrollView(
            child: SelectableText(
              json,
              style: Theme.of(
                dialogContext,
              ).textTheme.bodySmall?.copyWith(fontFamily: 'monospace'),
            ),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(),
            child: Text(l10n.cancel),
          ),
          FilledButton(
            onPressed: () async {
              await Clipboard.setData(ClipboardData(text: json));
              if (!dialogContext.mounted) return;
              ScaffoldMessenger.of(
                dialogContext,
              ).showSnackBar(SnackBar(content: Text(l10n.privacyCopied)));
            },
            child: Text(l10n.privacyCopyAction),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    Widget tile({
      required IconData icon,
      required String title,
      required String subtitle,
      required PrivacyAction action,
    }) {
      final running = _running == action;
      return ListTile(
        contentPadding: EdgeInsets.zero,
        leading: running
            ? const SizedBox(
                width: 24,
                height: 24,
                child: CircularProgressIndicator(strokeWidth: 2),
              )
            : Icon(icon),
        title: Text(title),
        subtitle: Text(subtitle),
        onTap: _running == null ? () => _run(action) : null,
      );
    }

    return FarmCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            l10n.profilePrivacyTitle,
            style: Theme.of(context).textTheme.titleSmall,
          ),
          tile(
            icon: Icons.download_outlined,
            title: l10n.privacyExportTitle,
            subtitle: l10n.privacyExportSubtitle,
            action: PrivacyAction.export,
          ),
          tile(
            icon: Icons.delete_outline,
            title: l10n.privacyDeleteHistoryTitle,
            subtitle: l10n.privacyDeleteHistorySubtitle,
            action: PrivacyAction.deleteHistory,
          ),
          tile(
            icon: Icons.block_outlined,
            title: l10n.privacyWithdrawAiTitle,
            subtitle: l10n.privacyWithdrawAiSubtitle,
            action: PrivacyAction.withdrawAiConsent,
          ),
        ],
      ),
    );
  }
}
