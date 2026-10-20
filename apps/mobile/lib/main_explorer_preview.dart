import 'dart:convert';
import 'dart:typed_data';

import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import 'core/auth/auth_session_controller.dart';
import 'core/auth/better_auth_client.dart';
import 'core/sync/sync_providers.dart';
import 'core/auth/farmly_auth_models.dart';
import 'core/network/farmly_api_client.dart';
import 'core/storage/secure_secret_store.dart';
import 'core/theme/farm_theme.dart';
import 'features/demo/demo_providers.dart' show farmBaViId;
import 'features/analytics/analytics_screen.dart';
import 'features/auth/login_screen.dart';
import 'features/auth/auth_flow_screens.dart';
import 'features/auth/splash_screen.dart';
import 'features/app/app_router.dart' show ChatRouteArguments;
import 'features/app/app_routes.dart';
import 'features/app/app_shell.dart';
import 'features/chat/chat_screens.dart';
import 'features/farm/farm_overview_screen.dart';
import 'features/farm/zone_detail_screen.dart';
import 'features/harvest/harvest_screen.dart';
import 'features/home/home_screen.dart';
import 'features/livestock/livestock_screen.dart';
import 'features/livestock/live_livestock.dart';
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
    // Mirrors the demo farm so the header and farm picker stay coherent
    // with the demo data shown across the preview.
    farms: <FarmlyDirectoryFarm>[
      FarmlyDirectoryFarm(
        // Mirrors the demo farm id so the header, farm picker and sync scope
        // stay coherent — FarmlyMutationScope requires UUID-shaped farm ids.
        id: farmBaViId,
        name: 'Nông trại Ba Vì',
        status: FarmlyFarmStatus.active,
        grantRole: FarmlyFarmGrantRole.owner,
      ),
    ],
  ),
  epoch: 1,
  selectedFarmId: farmBaViId,
);

class _PreviewSessionController extends FarmlyAuthSessionController {
  @override
  Future<FarmlyAuthSession?> build() async => _previewSession;
}

class _PreviewScopeController extends SelectedOrganizationScopeController {
  @override
  FarmlyOrganizationScope? build() => _previewScope;
}

/// In-memory secret store for the preview — seeds a bearer token so the API
/// client's `_send` passes its auth gate and requests reach the fake adapter
/// below. Nothing touches flutter_secure_storage.
final class _PreviewSecretStore implements FarmlySecretStore {
  final Map<String, String> _values = <String, String>{
    'farmly.auth.session.v1': 'preview-bearer-token',
  };

  @override
  Future<String?> read(String key) async => _values[key];

  @override
  Future<void> write(String key, String value) async => _values[key] = value;

  @override
  Future<void> delete(String key) async => _values.remove(key);
}

/// In-memory API stub serving just the organizations surface, so the picker
/// can select an org (loads its farm directory) and create one end-to-end in
/// preview without a backend. Every other route returns a sanitized 404 so
/// dependent screens render their translated error state instead of hanging
/// on a dead connection.
final class _PreviewApiAdapter implements HttpClientAdapter {
  final List<Map<String, Object?>> _organizations = <Map<String, Object?>>[
    _orgJson(_previewScope.organization.id, _previewScope.organization.name),
  ];
  int _created = 0;

  static Map<String, Object?> _orgJson(String id, String name) =>
      <String, Object?>{
        'id': id,
        'name': name,
        'status': 'active',
        'policyVersion': '1',
        'membership': <String, Object?>{
          'id': '55555555-5555-4555-8555-555555555555',
          'role': 'owner',
          'version': 1,
        },
      };

  ResponseBody _json(Object? body, [int status = 200]) =>
      ResponseBody.fromString(
        jsonEncode(body),
        status,
        headers: <String, List<String>>{
          Headers.contentTypeHeader: <String>[Headers.jsonContentType],
        },
      );

  @override
  Future<ResponseBody> fetch(
    RequestOptions options,
    Stream<Uint8List>? requestStream,
    Future<void>? cancelFuture,
  ) async {
    final path = options.uri.path;
    if (options.method == 'GET' && path.endsWith('/v1/organizations')) {
      return _json(<String, Object?>{
        'data': <String, Object?>{'organizations': _organizations},
        'page': <String, Object?>{'hasMore': false},
      });
    }
    if (options.method == 'POST' && path.endsWith('/v1/organizations')) {
      final raw = requestStream == null
          ? '{}'
          : utf8.decode(
              await requestStream.fold<List<int>>(
                <int>[],
                (acc, chunk) => acc..addAll(chunk),
              ),
            );
      final body = jsonDecode(raw);
      final name = body is Map && body['name'] is String
          ? body['name'] as String
          : 'Tổ chức mới';
      _created += 1;
      final organization = _orgJson(
        '66666666-6666-4666-8666-${_created.toString().padLeft(12, '0')}',
        name,
      );
      _organizations.add(organization);
      return _json(<String, Object?>{'data': organization});
    }
    final directoryMatch = RegExp(
      r'/v1/organizations/([0-9a-f-]+)/farm-directory$',
    ).firstMatch(path);
    if (options.method == 'GET' && directoryMatch != null) {
      final isPreviewOrg =
          directoryMatch.group(1) == _previewScope.organization.id;
      return _json(<String, Object?>{
        'schemaVersion': 'farm-directory.v1',
        'scopePolicyVersion': '1',
        'continuityEpoch': '1',
        'farms': isPreviewOrg
            ? <Map<String, Object?>>[
                <String, Object?>{
                  'farmId': farmBaViId,
                  'farmName': 'Nông trại Ba Vì',
                  'status': 'active',
                  'grantRole': 'owner',
                },
              ]
            : const <Object?>[],
        'nextCursor': null,
      });
    }
    return _json(<String, Object?>{
      'error': <String, Object?>{'code': 'NOT_FOUND'},
    }, 404);
  }

  @override
  void close({bool force = false}) {}
}

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  final router = GoRouter(
    initialLocation: AppRoutes.farm,
    routes: [
      // Existing authentication surfaces are available for visual inspection.
      // Their adapter is local; no live auth action can leave this preview.
      GoRoute(path: AppRoutes.splash, builder: (_, _) => const SplashScreen()),
      GoRoute(path: AppRoutes.login, builder: (_, _) => const LoginScreen()),
      GoRoute(path: AppRoutes.signup, builder: (_, _) => const SignUpScreen()),
      GoRoute(
        path: AppRoutes.verifyEmail,
        builder: (_, _) => const VerifyEmailScreen(),
      ),
      GoRoute(
        path: AppRoutes.emailVerified,
        builder: (_, _) => const EmailVerifiedScreen(),
      ),
      GoRoute(
        path: AppRoutes.forgotPassword,
        builder: (_, _) => const ForgotPasswordScreen(),
      ),
      GoRoute(
        path: AppRoutes.resetPassword,
        builder: (_, _) => const ResetPasswordScreen(token: null),
      ),
      GoRoute(
        path: AppRoutes.invitation,
        builder: (_, _) => const InvitationAcceptanceScreen(
          organizationId: null,
          invitationId: null,
          token: null,
        ),
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
        AppRoutes.splash,
        AppRoutes.login,
        AppRoutes.signup,
        AppRoutes.verifyEmail,
        AppRoutes.emailVerified,
        AppRoutes.forgotPassword,
        AppRoutes.resetPassword,
        AppRoutes.invitation,
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
        // Visual preview data is explicit; signed-in production routes never
        // infer demo mode from a selected farm or stub session.
        farmlyLivestockDemoPreviewProvider.overrideWithValue(true),
        // Preview journeys must never resolve a disk-backed outbox, even when
        // the demo has a stub signed-in session. Keep persisted app data intact.
        farmlySyncScopeProvider.overrideWith((ref) async => null),
        syncEngineProvider.overrideWith((ref) async {
          throw StateError('Persistent sync is unavailable in visual preview');
        }),
        betterAuthClientProvider.overrideWith((ref) {
          final dio = Dio()..httpClientAdapter = _PreviewApiAdapter();
          ref.onDispose(dio.close);
          return BetterAuthClient(
            apiBaseUrl: Uri.parse('https://preview.invalid/'),
            dio: dio,
          );
        }),
        farmlyAuthSessionProvider.overrideWith(_PreviewSessionController.new),
        selectedOrganizationScopeProvider.overrideWith(
          _PreviewScopeController.new,
        ),
        // Seeded in-memory credentials so FarmlyApiClient._send passes its
        // auth gate; requests land on the stub adapter below.
        farmlySecretStoreProvider.overrideWithValue(_PreviewSecretStore()),
        farmlyApiDioProvider.overrideWith((ref) {
          final dio = Dio(
            BaseOptions(
              baseUrl: 'https://preview.invalid/',
              headers: const <String, String>{'Accept': 'application/json'},
            ),
          );
          dio.httpClientAdapter = _PreviewApiAdapter();
          ref.onDispose(dio.close);
          return dio;
        }),
        // The org-picker screen reads this family; without an override it
        // calls the real API and spins forever in preview.
        farmlyOrganizationsProvider.overrideWith(
          (ref, key) async => <FarmlyOrganization>[_previewScope.organization],
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
