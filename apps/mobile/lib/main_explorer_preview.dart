import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import 'core/auth/auth_session_controller.dart';
import 'core/auth/farmly_auth_models.dart';
import 'core/theme/farm_theme.dart';
import 'features/analytics/analytics_screen.dart';
import 'features/app/app_router.dart' show ChatRouteArguments;
import 'features/app/app_routes.dart';
import 'features/app/app_shell.dart';
import 'features/chat/chat_screens.dart';
import 'features/farm/farm_overview_screen.dart';
import 'features/farm/zone_detail_screen.dart';
import 'features/harvest/harvest_screen.dart';
import 'features/home/home_screen.dart';
import 'features/livestock/livestock_screen.dart';
import 'features/organizations/organization_flow_screens.dart';
import 'features/organizations/organization_repository.dart';
import 'features/organizations/organization_scope_controller.dart';
import 'features/profile/profile_screen.dart';
import 'features/sync/sync_center_screen.dart';
import 'l10n/generated/app_localizations.dart';

/// Native preview entrypoint for Farm Explorer evidence (V-03, phase 05).
///
/// `flutter run -d <device> -t lib/main_explorer_preview.dart` boots straight
/// into the My Farm shell tab with a stub session/scope; all data comes from
/// the demo repository — no backend, no auth, no network. Never shipped.
const _previewSession = FarmlyAuthSession(
  user: FarmlyAuthUser(
    id: '11111111-1111-4111-8111-111111111111',
    name: 'Preview Farmer',
    email: 'preview@farmly.test',
  ),
);

const _previewScope = FarmlyOrganizationScope(
  organization: FarmlyOrganization(
    id: '22222222-2222-4222-8222-222222222222',
    name: 'Preview Organization',
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

class _PreviewSessionController extends FarmlyAuthSessionController {
  @override
  Future<FarmlyAuthSession?> build() async => _previewSession;
}

class _PreviewScopeController extends SelectedOrganizationScopeController {
  @override
  FarmlyOrganizationScope? build() => _previewScope;
}

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  final router = GoRouter(
    initialLocation: AppRoutes.farm,
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
                  GoRoute(
                    path: 'livestock',
                    builder: (context, state) => const LivestockScreen(),
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
      GoRoute(
        path: AppRoutes.organizations,
        builder: (context, state) => OrganizationFlowScreen(
          returnTo: state.uri.queryParameters['returnTo'],
        ),
      ),
      GoRoute(
        path: AppRoutes.syncCenter,
        builder: (context, state) => const SyncCenterScreen(),
      ),
      GoRoute(
        path: AppRoutes.chat,
        builder: (context, state) => const ChatWelcomeScreen(),
      ),
      GoRoute(
        path: AppRoutes.chatConversation,
        builder: (context, state) {
          final arguments = state.extra;
          final routeArguments = arguments is ChatRouteArguments
              ? arguments
              : const ChatRouteArguments(contextual: false);
          return ChatConversationScreen(
            initialPrompt: routeArguments.prompt,
            contextual: routeArguments.contextual,
          );
        },
      ),
    ],
    // The preview table only covers the shell + secondary routes above; any
    // stray navigation (e.g. the error page's home button) lands on the farm
    // tab instead of go_router's red error screen.
    redirect: (context, state) {
      final path = state.uri.path;
      const known = {
        AppRoutes.home,
        AppRoutes.farm,
        AppRoutes.livestock,
        AppRoutes.analytics,
        AppRoutes.harvest,
        AppRoutes.profile,
        AppRoutes.organizations,
        AppRoutes.syncCenter,
        AppRoutes.chat,
        AppRoutes.chatConversation,
      };
      final allowed =
          known.contains(path) || path.startsWith('${AppRoutes.zoneDetail}/');
      return allowed ? null : AppRoutes.farm;
    },
  );

  runApp(
    ProviderScope(
      overrides: [
        farmlyAuthSessionProvider.overrideWith(_PreviewSessionController.new),
        selectedOrganizationScopeProvider.overrideWith(
          _PreviewScopeController.new,
        ),
      ],
      child: MaterialApp.router(
        title: 'Farmly Preview',
        debugShowCheckedModeBanner: false,
        theme: buildFarmTheme(),
        routerConfig: router,
        locale: const Locale('vi'),
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
      ),
    ),
  );
}
