import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../core/auth/auth_session_controller.dart';
import '../core/notifications/notifications_repository.dart';
import '../core/sync/sync_providers.dart';
import '../core/theme/farmly_spacing.dart';
import '../core/theme/farmly_theme_extension.dart';
import '../features/app/app_routes.dart';
import '../features/demo/demo_providers.dart';
import '../features/farm/farm_creation_sheet.dart';
import '../features/organizations/organization_repository.dart';
import '../features/organizations/organization_scope_controller.dart';
import '../l10n/generated/app_localizations.dart';
import 'screen_states.dart';

/// Farm picker bottom sheet. Every row shows **org name + farm name** so the
/// tenant is never ambiguous (spec 02 §3).
Future<void> showFarmPickerSheet(BuildContext context) {
  final rootContext = context;
  return showModalBottomSheet<void>(
    context: rootContext,
    isScrollControlled: true,
    builder: (sheetContext) => Consumer(
      builder: (context, ref, _) {
        final l10n = AppLocalizations.of(context);
        final liveScope = ref.watch(selectedOrganizationScopeProvider);
        final demoState = ref.watch(demoDataProvider);
        final canManageFarms =
            liveScope != null &&
            liveScope.organization.status == FarmlyOrganizationStatus.active &&
            (liveScope.organization.role == FarmlyOrganizationRole.owner ||
                liveScope.organization.role == FarmlyOrganizationRole.admin);
        final syncReady =
            canManageFarms && ref.watch(syncEngineProvider).hasValue;
        final liveFarms = liveScope?.directory.farms
            .where((farm) => farm.status == FarmlyFarmStatus.active)
            .toList(growable: false);
        final demoFarms = liveScope == null
            ? farmsOfOrganization(demoState, demoState.selectedOrganizationId)
            : const [];
        return SafeArea(
          child: ListView(
            shrinkWrap: true,
            padding: const EdgeInsets.fromLTRB(
              FarmSpacing.lg,
              0,
              FarmSpacing.lg,
              FarmSpacing.lg,
            ),
            children: [
              Padding(
                padding: const EdgeInsets.only(bottom: FarmSpacing.md),
                child: Text(
                  l10n.farmPickerTitle,
                  style: Theme.of(sheetContext).textTheme.titleLarge,
                ),
              ),
              if (liveScope != null && liveFarms!.isEmpty) ...[
                Text(
                  l10n.farmEmptyTitle,
                  style: Theme.of(sheetContext).textTheme.titleMedium,
                ),
                const SizedBox(height: FarmSpacing.xs),
                Text(l10n.farmEmptyBody),
              ],
              if (liveScope != null)
                for (final farm in liveFarms!)
                  Semantics(
                    button: true,
                    selected: farm.id == liveScope.selectedFarmId,
                    label: l10n.farmRowSemantics(
                      farm.name,
                      liveScope.organization.name,
                    ),
                    child: ListTile(
                      leading: Icon(
                        farm.id == liveScope.selectedFarmId
                            ? Icons.check_circle
                            : Icons.landscape_outlined,
                        color: FarmThemeExtension.of(sheetContext).brandAction,
                      ),
                      title: Text(farm.name, softWrap: true),
                      subtitle: Text(
                        '${liveScope.organization.name} · '
                        '${_farmRoleLabel(l10n, farm.grantRole)}',
                        softWrap: true,
                      ),
                      onTap: () async {
                        final selected = await ref
                            .read(selectedOrganizationScopeProvider.notifier)
                            .selectFarm(farm.id);
                        if (selected && sheetContext.mounted) {
                          Navigator.of(sheetContext).pop();
                        }
                      },
                    ),
                  ),
              if (liveScope == null) ...[
                Padding(
                  padding: const EdgeInsets.only(bottom: FarmSpacing.xs),
                  child: Text(
                    l10n.sampleDataLabel,
                    style: Theme.of(sheetContext).textTheme.labelMedium,
                  ),
                ),
                for (final farm in demoFarms)
                  Semantics(
                    button: true,
                    selected: farm.id == demoState.selectedFarmId,
                    label: l10n.farmRowSemantics(
                      farm.name,
                      organizationById(demoState, farm.organizationId)?.name ??
                          '',
                    ),
                    child: ListTile(
                      leading: Icon(
                        farm.id == demoState.selectedFarmId
                            ? Icons.check_circle
                            : Icons.landscape_outlined,
                        color: FarmThemeExtension.of(sheetContext).brandAction,
                      ),
                      title: Text(farm.name, softWrap: true),
                      subtitle: Text(
                        organizationById(
                              demoState,
                              farm.organizationId,
                            )?.name ??
                            '',
                        softWrap: true,
                      ),
                      onTap: () {
                        ref.read(demoDataProvider.notifier).selectFarm(farm.id);
                        Navigator.of(sheetContext).pop();
                      },
                    ),
                  ),
              ],
              if (syncReady) ...[
                const SizedBox(height: FarmSpacing.sm),
                OutlinedButton.icon(
                  key: const ValueKey('farm-picker-create-farm'),
                  onPressed: () async {
                    Navigator.of(sheetContext).pop();
                    final withFirstZone = await showModalBottomSheet<bool>(
                      context: rootContext,
                      isScrollControlled: true,
                      useSafeArea: true,
                      builder: (_) => const FarmCreationSheet(),
                    );
                    if (!rootContext.mounted || withFirstZone == null) return;
                    ScaffoldMessenger.of(rootContext).showSnackBar(
                      SnackBar(
                        content: Text(
                          withFirstZone
                              ? l10n.farmAndZoneSavedOffline
                              : l10n.farmSavedOffline,
                        ),
                      ),
                    );
                  },
                  icon: const Icon(Icons.add_business_outlined),
                  label: Text(l10n.createFarm),
                ),
              ],
              Padding(
                padding: const EdgeInsets.only(top: FarmSpacing.sm),
                child: Text(
                  l10n.farmPickerOrganizationHint,
                  style: Theme.of(sheetContext).textTheme.bodySmall?.copyWith(
                    color: FarmThemeExtension.of(sheetContext).textSecondary,
                  ),
                ),
              ),
            ],
          ),
        );
      },
    ),
  );
}

String _farmRoleLabel(AppLocalizations l10n, FarmlyFarmGrantRole role) =>
    switch (role) {
      FarmlyFarmGrantRole.owner => l10n.roleOwner,
      FarmlyFarmGrantRole.admin => l10n.roleAdmin,
      FarmlyFarmGrantRole.manager => l10n.roleManager,
      FarmlyFarmGrantRole.worker => l10n.roleWorker,
      FarmlyFarmGrantRole.viewer => l10n.roleViewer,
    };

/// Steps for re-enabling notifications from the OS settings, shown when the
/// permission is denied. A real build with a permission plugin would also
/// offer a direct "open settings" deep link.
void _showNotificationPermissionGuide(BuildContext context) {
  showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    builder: (sheetContext) => SafeArea(
      child: Builder(
        builder: (context) {
          final l10n = AppLocalizations.of(context);
          return ListView(
            shrinkWrap: true,
            padding: const EdgeInsets.fromLTRB(
              FarmSpacing.lg,
              0,
              FarmSpacing.lg,
              FarmSpacing.lg,
            ),
            children: [
              Padding(
                padding: const EdgeInsets.only(bottom: FarmSpacing.md),
                child: Text(
                  l10n.notificationGuideTitle,
                  style: Theme.of(sheetContext).textTheme.titleLarge,
                  softWrap: true,
                ),
              ),
              Text(
                l10n.notificationGuideBody,
                style: Theme.of(sheetContext).textTheme.bodyMedium,
                softWrap: true,
              ),
              const SizedBox(height: FarmSpacing.md),
              Align(
                alignment: Alignment.centerLeft,
                child: TextButton(
                  onPressed: () => Navigator.of(sheetContext).pop(),
                  child: Text(l10n.understood),
                ),
              ),
            ],
          );
        },
      ),
    ),
  );
}

/// Organization picker bottom sheet; switching clears the farm selection.
Future<void> showOrganizationPickerSheet(BuildContext context) {
  return _openOrganizationPicker(context);
}

Future<void> _openOrganizationPicker(BuildContext context) async {
  await GoRouter.of(context).push<void>(AppRoutes.organizations);
}

/// Notification sheet: permission-denied state kept explicit plus a small
/// in-app event list (spec 02 §5 Notifications row).
Future<void> showNotificationsSheet(BuildContext context) {
  return showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    builder: (sheetContext) => Consumer(
      builder: (context, ref, _) {
        final l10n = AppLocalizations.of(context);
        // Live lane: recipient-owned server feed when signed in; demo list
        // otherwise. Tapping a live row marks it read server-side.
        final signedIn =
            ref.watch(farmlyAuthSessionProvider).value?.user != null;
        final demoNotifications = ref.watch(
          demoDataProvider.select((state) => state.notifications),
        );
        return SafeArea(
          child: ListView(
            shrinkWrap: true,
            padding: const EdgeInsets.fromLTRB(
              FarmSpacing.lg,
              0,
              FarmSpacing.lg,
              FarmSpacing.lg,
            ),
            children: [
              Padding(
                padding: const EdgeInsets.only(bottom: FarmSpacing.md),
                child: Text(
                  l10n.notificationsTitle,
                  style: Theme.of(sheetContext).textTheme.titleLarge,
                ),
              ),
              PermissionBanner(
                message: l10n.notificationPermissionMessage,
                // Denied permission messages carry a next action (spec 02 §5).
                // This build has no permission plugin/platform channel to open
                // system settings directly, so the action opens in-app steps.
                actionLabel: l10n.notificationPermissionAction,
                onAction: () => _showNotificationPermissionGuide(sheetContext),
              ),
              const SizedBox(height: FarmSpacing.md),
              if (signedIn)
                const _LiveNotificationList()
              else ...[
                for (final notification in demoNotifications)
                  ListTile(
                    contentPadding: EdgeInsets.zero,
                    leading: const Icon(Icons.notifications_outlined),
                    title: Text(notification.title, softWrap: true),
                    subtitle: Text(
                      '${notification.body} · ${notification.timeLabel}',
                      softWrap: true,
                    ),
                  ),
              ],
            ],
          ),
        );
      },
    ),
  );
}

/// Server-feed list for the notifications sheet — lazy reminder sweep runs
/// server-side on read; tapping an unread row marks it read.
class _LiveNotificationList extends ConsumerStatefulWidget {
  const _LiveNotificationList();

  @override
  ConsumerState<_LiveNotificationList> createState() =>
      _LiveNotificationListState();
}

class _LiveNotificationListState extends ConsumerState<_LiveNotificationList> {
  late Future<List<AppNotification>> _feed;

  @override
  void initState() {
    super.initState();
    _feed = _load();
  }

  Future<List<AppNotification>> _load() =>
      ref.read(notificationsRepositoryProvider).list().then((r) => r.items);

  void _reload() => setState(() => _feed = _load());

  Future<void> _markRead(AppNotification item) async {
    if (item.readAt != null) return;
    setState(() {
      _feed = _feed.then(
        (items) => [
          for (final n in items)
            n.id == item.id
                ? AppNotification(
                    id: n.id,
                    kind: n.kind,
                    title: n.title,
                    body: n.body,
                    sourceRef: n.sourceRef,
                    readAt: DateTime.now(),
                    createdAt: n.createdAt,
                    farmId: n.farmId,
                  )
                : n,
        ],
      );
    });
    try {
      await ref.read(notificationsRepositoryProvider).markRead(item.id);
    } catch (_) {
      _reload();
    }
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    return FutureBuilder<List<AppNotification>>(
      future: _feed,
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) {
          return const Padding(
            padding: EdgeInsets.symmetric(vertical: FarmSpacing.lg),
            child: Center(child: CircularProgressIndicator()),
          );
        }
        if (snapshot.hasError) {
          return Column(
            children: [
              Text(l10n.loadErrorTitle, textAlign: TextAlign.center),
              const SizedBox(height: FarmSpacing.sm),
              TextButton(onPressed: _reload, child: Text(l10n.retry)),
            ],
          );
        }
        final items = snapshot.data ?? const [];
        if (items.isEmpty) {
          return Padding(
            padding: const EdgeInsets.symmetric(vertical: FarmSpacing.lg),
            child: Text(l10n.notificationsEmpty, textAlign: TextAlign.center),
          );
        }
        return Column(
          children: [
            for (final item in items)
              Semantics(
                label: item.readAt == null
                    ? l10n.notificationUnreadSemantics
                    : l10n.notificationReadSemantics,
                child: ListTile(
                  contentPadding: EdgeInsets.zero,
                  leading: Icon(
                    item.readAt == null
                        ? Icons.notifications_active_outlined
                        : Icons.notifications_outlined,
                  ),
                  title: Text(item.title, softWrap: true),
                  subtitle: item.body == null
                      ? null
                      : Text(item.body!, softWrap: true),
                  onTap: () => _markRead(item),
                ),
              ),
          ],
        );
      },
    );
  }
}
