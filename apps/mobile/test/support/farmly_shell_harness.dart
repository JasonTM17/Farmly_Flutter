import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';

import 'package:farmly_mobile/core/auth/auth_session_controller.dart';
import 'package:farmly_mobile/core/auth/farmly_auth_models.dart';
import 'package:farmly_mobile/core/sync/sync_providers.dart';
import 'package:farmly_mobile/core/theme/farm_theme.dart';
import 'package:farmly_mobile/features/analytics/analytics_screen.dart';
import 'package:farmly_mobile/features/app/app_shell.dart';
import 'package:farmly_mobile/features/app/app_routes.dart';
import 'package:farmly_mobile/features/farm/farm_overview_screen.dart';
import 'package:farmly_mobile/features/farm/zone_detail_screen.dart';
import 'package:farmly_mobile/features/harvest/harvest_screen.dart';
import 'package:farmly_mobile/features/home/home_screen.dart';
import 'package:farmly_mobile/features/organizations/organization_repository.dart';
import 'package:farmly_mobile/features/organizations/organization_scope_controller.dart';
import 'package:farmly_mobile/features/profile/profile_screen.dart';
import 'package:farmly_mobile/l10n/generated/app_localizations.dart';
import 'package:farmly_mobile/features/sync/sync_center_screen.dart';

const _testSession = FarmlyAuthSession(
  user: FarmlyAuthUser(
    id: '11111111-1111-4111-8111-111111111111',
    name: 'Test Farmer',
    email: 'farmer@farmly.test',
  ),
);

const _testScope = FarmlyOrganizationScope(
  organization: FarmlyOrganization(
    id: '22222222-2222-4222-8222-222222222222',
    name: 'Test Organization',
    status: FarmlyOrganizationStatus.active,
    policyVersion: '1',
    role: FarmlyOrganizationRole.owner,
    membershipVersion: 1,
  ),
  directory: FarmlyFarmDirectory(
    scopePolicyVersion: '1',
    continuityEpoch: '1',
    farms: <FarmlyDirectoryFarm>[],
  ),
  epoch: 1,
);

class _AuthenticatedSessionController extends FarmlyAuthSessionController {
  @override
  Future<FarmlyAuthSession?> build() async => _testSession;
}

class _SelectedOrganizationScopeController
    extends SelectedOrganizationScopeController {
  @override
  FarmlyOrganizationScope? build() => _testScope;
}

Future<GoRouter> pumpFarmlyShell(
  WidgetTester tester, {
  Size viewport = const Size(390, 844),
  Locale locale = const Locale('vi'),
  double textScaleFactor = 1,
}) async {
  tester.view.physicalSize = viewport;
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  final platformDispatcher = tester.binding.platformDispatcher;
  platformDispatcher.textScaleFactorTestValue = textScaleFactor;
  addTearDown(platformDispatcher.clearTextScaleFactorTestValue);

  final router = GoRouter(
    initialLocation: AppRoutes.home,
    routes: [
      StatefulShellRoute.indexedStack(
        builder: (context, state, navigationShell) =>
            AppShell(navigationShell: navigationShell),
        branches: [
          StatefulShellBranch(
            routes: [
              GoRoute(
                path: AppRoutes.home,
                builder: (context, state) => const HomeScreen(),
              ),
            ],
          ),
          StatefulShellBranch(
            routes: [
              GoRoute(
                path: AppRoutes.farm,
                builder: (context, state) => const FarmOverviewScreen(),
                routes: [
                  GoRoute(
                    path: 'zone/:zoneId',
                    builder: (context, state) => ZoneDetailScreen(
                      zoneId: state.pathParameters['zoneId'],
                    ),
                  ),
                ],
              ),
            ],
          ),
          StatefulShellBranch(
            routes: [
              GoRoute(
                path: AppRoutes.analytics,
                builder: (context, state) => const AnalyticsScreen(),
              ),
            ],
          ),
          StatefulShellBranch(
            routes: [
              GoRoute(
                path: AppRoutes.harvest,
                builder: (context, state) => const HarvestScreen(),
              ),
            ],
          ),
          StatefulShellBranch(
            routes: [
              GoRoute(
                path: AppRoutes.profile,
                builder: (context, state) => const ProfileScreen(),
              ),
            ],
          ),
        ],
      ),
      // Top-level routes mirrored from app_router for golden/deep-link tests.
      GoRoute(
        path: AppRoutes.syncCenter,
        builder: (context, state) => const SyncCenterScreen(),
      ),
    ],
  );
  addTearDown(router.dispose);
  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        // This harness exercises the illustrated Farm Explorer preview.
        // Live-farm tests provide their own authorized sync scope explicitly.
        farmlySyncScopeProvider.overrideWith((ref) async => null),
        farmlyAuthSessionProvider.overrideWith(
          _AuthenticatedSessionController.new,
        ),
        selectedOrganizationScopeProvider.overrideWith(
          _SelectedOrganizationScopeController.new,
        ),
        homeClockProvider.overrideWithValue(() => DateTime(2026, 10, 7, 9)),
      ],
      child: MaterialApp.router(
        theme: buildFarmTheme(),
        // Reduced motion keeps pumpAndSettle deterministic: ambient loops
        // render statically and entrances land at their resting state.
        builder: (context, child) => MediaQuery(
          data: MediaQuery.of(context).copyWith(disableAnimations: true),
          child: child ?? const SizedBox.shrink(),
        ),
        locale: locale,
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        routerConfig: router,
      ),
    ),
  );
  await tester.pumpAndSettle();
  return router;
}
