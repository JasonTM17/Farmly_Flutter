import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/auth/auth_session_controller.dart';
import '../../core/auth/farmly_auth_models.dart';
import '../../core/theme/farmly_spacing.dart';
import '../../core/theme/farmly_theme_extension.dart';
import '../../l10n/generated/app_localizations.dart';
import '../../ui/illustrations.dart';
import '../app/app_routes.dart';

class SplashScreen extends ConsumerWidget {
  const SplashScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final auth = ref.watch(farmlyAuthSessionProvider);
    final tokens = FarmThemeExtension.of(context);
    final l10n = AppLocalizations.of(context);
    final offlineLeaseExpired =
        auth.error is FarmlyAuthFailure &&
        (auth.error as FarmlyAuthFailure).code ==
            FarmlyAuthFailureCode.offlineLeaseExpired;
    return Scaffold(
      backgroundColor: tokens.background,
      body: SafeArea(
        child: Stack(
          fit: StackFit.expand,
          children: [
            const ExcludeSemantics(
              child: CustomPaint(painter: FarmScenePainter(showBarn: false)),
            ),
            Center(
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 600),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Container(
                      width: FarmSpacing.huge * 2,
                      height: FarmSpacing.huge * 2,
                      decoration: BoxDecoration(
                        color: tokens.surface,
                        shape: BoxShape.circle,
                        border: Border.all(color: tokens.divider),
                      ),
                      alignment: Alignment.center,
                      child: const SproutMark(size: 72),
                    ),
                    const SizedBox(height: 12),
                    Text(
                      l10n.appName,
                      style: Theme.of(context).textTheme.displaySmall?.copyWith(
                        color: tokens.textPrimary,
                      ),
                    ),
                    const SizedBox(height: 8),
                    Text(
                      l10n.appSubtitle,
                      textAlign: TextAlign.center,
                      style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                        color: tokens.textSecondary,
                      ),
                    ),
                    if (auth.hasError) ...[
                      const SizedBox(height: 24),
                      Semantics(
                        liveRegion: true,
                        child: Text(
                          offlineLeaseExpired
                              ? l10n.offlineLeaseExpiredBody
                              : l10n.sessionUnavailableBody,
                          textAlign: TextAlign.center,
                        ),
                      ),
                      TextButton(
                        onPressed: () => ref
                            .read(farmlyAuthSessionProvider.notifier)
                            .retryRestore(),
                        child: Text(l10n.retry),
                      ),
                      TextButton(
                        onPressed: () => context.go(AppRoutes.login),
                        child: Text(l10n.signIn),
                      ),
                    ] else ...[
                      const SizedBox(height: 24),
                      const SizedBox.square(
                        dimension: 24,
                        child: CircularProgressIndicator(strokeWidth: 2.5),
                      ),
                    ],
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
