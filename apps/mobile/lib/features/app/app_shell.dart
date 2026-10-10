import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/theme/farmly_spacing.dart';
import '../../core/theme/farmly_theme_extension.dart';
import '../../l10n/generated/app_localizations.dart';
import '../../ui/farm_scaffold.dart';
import '../../ui/pickers.dart';
import '../organizations/organization_scope_controller.dart';
import 'app_routes.dart';

class AppShell extends ConsumerWidget {
  const AppShell({required this.navigationShell, super.key});

  final StatefulNavigationShell navigationShell;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final scope = ref.watch(selectedOrganizationScopeProvider);
    final l10n = AppLocalizations.of(context);
    return FarmScaffold(
      body: Column(
        children: [
          if (scope != null)
            _OrganizationScopeBanner(
              organizationLabel: scope.organization.name,
              farmLabel: scope.selectedFarmId == null
                  ? l10n.noSelectedFarm
                  : (scope.selectedFarm?.name ??
                      l10n.farmIdentifier(scope.selectedFarmId!)),
              l10n: l10n,
              onTap: () => context.push(AppRoutes.organizations),
              onFarmTap: () => showFarmPickerSheet(context),
            ),
          Expanded(child: navigationShell),
        ],
      ),
      bottomBar: AdaptiveBottomBar(
        currentIndex: navigationShell.currentIndex,
        onTap: (index) => navigationShell.goBranch(
          index,
          initialLocation: index == navigationShell.currentIndex,
        ),
      ),
    );
  }
}

class _OrganizationScopeBanner extends StatelessWidget {
  const _OrganizationScopeBanner({
    required this.organizationLabel,
    required this.farmLabel,
    required this.l10n,
    required this.onTap,
    required this.onFarmTap,
  });

  final String organizationLabel;
  final String farmLabel;
  final AppLocalizations l10n;
  final VoidCallback onTap;
  final VoidCallback onFarmTap;

  @override
  Widget build(BuildContext context) {
    final tokens = FarmThemeExtension.of(context);
    return Material(
      color: tokens.surface,
      child: InkWell(
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.symmetric(
            horizontal: FarmSpacing.lg,
            vertical: FarmSpacing.sm,
          ),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              Icon(Icons.apartment_outlined, color: tokens.brandAction),
              const SizedBox(width: FarmSpacing.sm),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      organizationLabel,
                      style: Theme.of(context).textTheme.labelLarge,
                      softWrap: true,
                    ),
                    Text(
                      farmLabel,
                      style: Theme.of(context).textTheme.bodySmall?.copyWith(
                        color: tokens.textSecondary,
                      ),
                      softWrap: true,
                    ),
                  ],
                ),
              ),
              IconButton(
                tooltip: l10n.changeFarm,
                onPressed: onFarmTap,
                icon: Icon(Icons.landscape_outlined, color: tokens.brandAction),
              ),
              Icon(Icons.expand_more, color: tokens.textSecondary),
            ],
          ),
        ),
      ),
    );
  }
}
