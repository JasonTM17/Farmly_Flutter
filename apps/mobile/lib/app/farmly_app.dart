import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../core/config/app_config.dart';
import '../core/auth/auth_session_lifecycle_gate.dart';
import '../features/app/app_router.dart';
import '../core/theme/farm_theme.dart';
import '../l10n/generated/app_localizations.dart';
import '../l10n/locale_controller.dart';

class FarmlyApp extends ConsumerWidget {
  const FarmlyApp({required this.config, super.key});

  final FarmlyAppConfig config;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final router = ref.watch(farmlyRouterProvider);
    return FarmlyAuthSessionLifecycleGate(
      child: MaterialApp.router(
        title: 'Farmly',
        debugShowCheckedModeBanner: config.flavor != FarmlyAppFlavor.production,
        theme: buildFarmTheme(),
        routerConfig: router,
        // Spec 01: default vi-VN; the profile switch can move this to en.
        locale: ref.watch(farmlyLocaleProvider),
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
      ),
    );
  }
}
