import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/auth/auth_session_controller.dart';
import '../../core/auth/farmly_auth_models.dart';
import '../auth/auth_flow_screens.dart';
import '../auth/login_screen.dart';
import '../auth/splash_screen.dart';
import '../chat/chat_screens.dart';
import '../demo/demo_providers.dart';
import '../farm/zone_detail_screen.dart';
import '../livestock/livestock_screen.dart';
import '../organizations/organization_flow_screens.dart';
import '../organizations/organization_scope_controller.dart';
import '../sync/sync_center_screen.dart';
import 'app_routes.dart';
import 'app_shell.dart';
import '../analytics/analytics_screen.dart';
import '../farm/farm_overview_screen.dart';
import '../harvest/harvest_screen.dart';
import '../home/home_screen.dart';
import '../profile/profile_screen.dart';

final _rootNavigatorKey = GlobalKey<NavigatorState>(debugLabel: 'farmly-root');

final farmlyRouterProvider = Provider<GoRouter>((ref) {
  final router = GoRouter(
    navigatorKey: _rootNavigatorKey,
    initialLocation: AppRoutes.splash,
    routes: [
      GoRoute(
        path: AppRoutes.splash,
        builder: (context, state) => const SplashScreen(),
      ),
      GoRoute(
        path: AppRoutes.login,
        builder: (context, state) =>
            LoginScreen(returnTo: state.uri.queryParameters['returnTo']),
      ),
      GoRoute(
        path: AppRoutes.signup,
        builder: (context, state) =>
            SignUpScreen(returnTo: state.uri.queryParameters['returnTo']),
      ),
      GoRoute(
        path: AppRoutes.verifyEmail,
        builder: (context, state) => const VerifyEmailScreen(),
      ),
      GoRoute(
        path: AppRoutes.emailVerified,
        builder: (context, state) => EmailVerifiedScreen(
          returnTo: state.uri.queryParameters['returnTo'],
        ),
      ),
      GoRoute(
        path: AppRoutes.forgotPassword,
        builder: (context, state) => const ForgotPasswordScreen(),
      ),
      GoRoute(
        path: AppRoutes.resetPassword,
        builder: (context, state) {
          final token = state.uri.queryParameters['token'];
          return ResetPasswordScreen(
            token: token != null && token.trim().isNotEmpty ? token : null,
          );
        },
      ),
      GoRoute(
        path: AppRoutes.organizations,
        builder: (context, state) => OrganizationFlowScreen(
          returnTo: state.uri.queryParameters['returnTo'],
        ),
      ),
      GoRoute(
        path: AppRoutes.invitation,
        builder: (context, state) => InvitationAcceptanceScreen(
          organizationId: state.uri.queryParameters['organizationId'],
          invitationId: state.uri.queryParameters['invitationId'],
          token: state.uri.queryParameters['token'],
        ),
      ),
      GoRoute(
        path: AppRoutes.shell,
        redirect: (context, state) => AppRoutes.home,
      ),
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
                    parentNavigatorKey: _rootNavigatorKey,
                    builder: (context, state) => ZoneDetailScreen(
                      zoneId: state.pathParameters['zoneId'],
                    ),
                  ),
                  GoRoute(
                    path: 'livestock',
                    parentNavigatorKey: _rootNavigatorKey,
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
        path: AppRoutes.chat,
        parentNavigatorKey: _rootNavigatorKey,
        builder: (context, state) => const ChatWelcomeScreen(),
      ),
      GoRoute(
        path: AppRoutes.chatConversation,
        parentNavigatorKey: _rootNavigatorKey,
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
      GoRoute(
        path: AppRoutes.syncCenter,
        parentNavigatorKey: _rootNavigatorKey,
        builder: (context, state) => const SyncCenterScreen(),
      ),
    ],
    redirect: (context, state) {
      final path = state.uri.path;
      final auth = ref.read(farmlyAuthSessionProvider);
      final selectedScope = ref.read(selectedOrganizationScopeProvider);
      final returnToQuery = state.uri.queryParameters['returnTo'];
      final isAuthRoute = <String>{
        AppRoutes.login,
        AppRoutes.signup,
        AppRoutes.verifyEmail,
        AppRoutes.emailVerified,
        AppRoutes.forgotPassword,
        AppRoutes.resetPassword,
      }.contains(path);

      if (auth.isLoading || auth.hasError) {
        if (path == AppRoutes.splash ||
            path == AppRoutes.emailVerified ||
            path == AppRoutes.resetPassword) {
          return null;
        }
        final pending =
            safeFarmlyReturnTo(returnToQuery) ??
            (isAuthRoute ? null : state.uri.toString());
        return farmlyRouteWithReturnTo(AppRoutes.splash, pending);
      }

      final session = auth.hasValue ? auth.value : null;

      if (session == null) {
        if (path == AppRoutes.splash) {
          return farmlyRouteWithReturnTo(
            AppRoutes.login,
            safeFarmlyReturnTo(returnToQuery),
          );
        }
        if (isAuthRoute) return null;
        if (path == AppRoutes.organizations) return AppRoutes.login;
        final returnTo = state.uri.toString();
        return farmlyRouteWithReturnTo(AppRoutes.login, returnTo);
      }

      if (path == AppRoutes.splash ||
          path == AppRoutes.login ||
          path == AppRoutes.signup ||
          path == AppRoutes.verifyEmail ||
          path == AppRoutes.forgotPassword) {
        return farmlyRouteWithReturnTo(
          AppRoutes.organizations,
          safeFarmlyReturnTo(returnToQuery),
        );
      }
      if (_isOrganizationScopedPath(path) && selectedScope == null) {
        return farmlyRouteWithReturnTo(
          AppRoutes.organizations,
          state.uri.toString(),
        );
      }
      return null;
    },
  );

  ref.listen(farmlyAuthSessionProvider, (_, next) {
    if ((next is AsyncData<FarmlyAuthSession?> && next.value == null) ||
        next is AsyncError<FarmlyAuthSession?>) {
      ref.read(selectedOrganizationScopeProvider.notifier).clear();
    }
    router.refresh();
  });
  ref.listen(selectedOrganizationScopeProvider, (_, _) => router.refresh());
  ref.onDispose(router.dispose);
  return router;
});

bool _isOrganizationScopedPath(String path) =>
    path == AppRoutes.shell ||
    path == AppRoutes.home ||
    path == AppRoutes.farm ||
    path.startsWith('${AppRoutes.farm}/') ||
    path == AppRoutes.analytics ||
    path == AppRoutes.harvest ||
    path == AppRoutes.profile ||
    path == AppRoutes.livestock ||
    path == AppRoutes.chat ||
    path.startsWith('${AppRoutes.chat}/') ||
    path == AppRoutes.syncCenter;

/// Arguments for a contextual conversation opened from a feature screen.
class ChatRouteArguments {
  const ChatRouteArguments({this.prompt, required this.contextual});

  final String? prompt;
  final bool contextual;
}

/// Opens the conversation directly only after contextual consent was recorded.
void openContextualChat(BuildContext context, WidgetRef ref) {
  final accepted = ref.read(aiConsentProvider).contextualAccepted;
  if (accepted) {
    context.push(
      AppRoutes.chatConversation,
      extra: const ChatRouteArguments(contextual: true),
    );
  } else {
    context.push(AppRoutes.chat);
  }
}
