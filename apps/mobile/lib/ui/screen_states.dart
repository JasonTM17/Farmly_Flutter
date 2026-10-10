import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../core/theme/farmly_spacing.dart';
import '../core/theme/farmly_theme_extension.dart';
import '../features/demo/demo_models.dart';
import '../features/demo/demo_providers.dart';
import '../l10n/generated/app_localizations.dart';
import 'illustrations.dart';

/// Skeleton block. Shimmers unless reduced motion is on, in which case a
/// static placeholder is rendered (spec 02 §2).
class SkeletonSurface extends StatefulWidget {
  const SkeletonSurface({
    this.width,
    this.height = 16,
    this.radius = FarmSpacing.sm,
    super.key,
  });

  final double? width;
  final double height;
  final double radius;

  @override
  State<SkeletonSurface> createState() => _SkeletonSurfaceState();
}

class _SkeletonSurfaceState extends State<SkeletonSurface>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 1200),
  );

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (context.farmReducedMotion()) {
      _controller.stop();
    } else if (!_controller.isAnimating) {
      _controller.repeat();
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (context.farmReducedMotion()) {
      return _surface(FarmThemeExtension.of(context), 0);
    }
    return AnimatedBuilder(
      animation: _controller,
      builder: (context, _) => _surface(
        FarmThemeExtension.of(context),
        Curves.easeInOut.transform(_controller.value),
      ),
    );
  }

  Widget _surface(FarmThemeExtension tokens, double t) {
    return Container(
      width: widget.width,
      height: widget.height,
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(widget.radius),
        gradient: LinearGradient(
          begin: Alignment(-1 + 2 * t, 0),
          end: Alignment(1 + 2 * t, 0),
          colors: [
            tokens.divider,
            tokens.brandSage.withValues(alpha: 0.5),
            tokens.divider,
          ],
        ),
      ),
    );
  }
}

/// Recoverable error view with explicit actions (retry / switch scope).
/// Never surfaces raw server text (spec 02 §5).
class FarmErrorView extends StatelessWidget {
  const FarmErrorView({required this.onRetry, this.onSwitchScope, super.key});

  final VoidCallback onRetry;
  final VoidCallback? onSwitchScope;

  @override
  Widget build(BuildContext context) {
    final tokens = FarmThemeExtension.of(context);
    final l10n = AppLocalizations.of(context);
    return Center(
      child: SingleChildScrollView(
        padding: const EdgeInsets.all(FarmSpacing.xxl),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.error_outline, size: 48, color: tokens.semanticError),
            const SizedBox(height: FarmSpacing.lg),
            Text(
              l10n.loadErrorTitle,
              style: Theme.of(context).textTheme.titleLarge,
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: FarmSpacing.sm),
            Text(
              l10n.loadErrorBody,
              style: Theme.of(context).textTheme.bodyMedium,
              textAlign: TextAlign.center,
              softWrap: true,
            ),
            const SizedBox(height: FarmSpacing.xl),
            FilledButton.icon(
              onPressed: onRetry,
              icon: const Icon(Icons.refresh),
              label: Text(l10n.retry),
            ),
            if (onSwitchScope != null)
              TextButton(
                onPressed: onSwitchScope,
                child: Text(l10n.changeScope),
              ),
          ],
        ),
      ),
    );
  }
}

/// Empty state with the quiet farm artwork, a primary action and an optional
/// secondary action (e.g. create-first vs switch-scope on My Farm, spec 02 §5).
class EmptyStateView extends StatelessWidget {
  const EmptyStateView({
    required this.title,
    required this.message,
    this.actionLabel,
    this.onAction,
    this.secondaryActionLabel,
    this.onSecondaryAction,
    super.key,
  });

  final String title;
  final String message;
  final String? actionLabel;
  final VoidCallback? onAction;
  final String? secondaryActionLabel;
  final VoidCallback? onSecondaryAction;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: SingleChildScrollView(
        padding: const EdgeInsets.all(FarmSpacing.xxl),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const EmptyFarmIllustration(),
            const SizedBox(height: FarmSpacing.lg),
            Text(
              title,
              style: Theme.of(context).textTheme.titleLarge,
              textAlign: TextAlign.center,
              softWrap: true,
            ),
            const SizedBox(height: FarmSpacing.sm),
            Text(
              message,
              style: Theme.of(context).textTheme.bodyMedium,
              textAlign: TextAlign.center,
              softWrap: true,
            ),
            if (actionLabel != null && onAction != null) ...[
              const SizedBox(height: FarmSpacing.xl),
              FilledButton(onPressed: onAction, child: Text(actionLabel!)),
            ],
            if (secondaryActionLabel != null && onSecondaryAction != null) ...[
              const SizedBox(height: FarmSpacing.sm),
              TextButton(
                onPressed: onSecondaryAction,
                child: Text(secondaryActionLabel!),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

/// Permission denied content with an explicit next action.
class PermissionDeniedView extends StatelessWidget {
  const PermissionDeniedView({
    required this.message,
    this.onSwitchScope,
    super.key,
  });

  final String message;
  final VoidCallback? onSwitchScope;

  @override
  Widget build(BuildContext context) {
    final tokens = FarmThemeExtension.of(context);
    final l10n = AppLocalizations.of(context);
    return Center(
      child: SingleChildScrollView(
        padding: const EdgeInsets.all(FarmSpacing.xxl),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.lock_outline, size: 48, color: tokens.semanticWarning),
            const SizedBox(height: FarmSpacing.lg),
            Text(
              l10n.permissionDeniedTitle,
              style: Theme.of(context).textTheme.titleLarge,
              textAlign: TextAlign.center,
              softWrap: true,
            ),
            const SizedBox(height: FarmSpacing.sm),
            Text(
              message,
              style: Theme.of(context).textTheme.bodyMedium,
              textAlign: TextAlign.center,
              softWrap: true,
            ),
            if (onSwitchScope != null) ...[
              const SizedBox(height: FarmSpacing.xl),
              FilledButton.tonal(
                onPressed: onSwitchScope,
                child: Text(l10n.changeScope),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

/// Inline read-only permission notice (banner) with an optional next action —
/// denied messages never ship actionless (spec 02 §5: "error message có
/// action").
class PermissionBanner extends StatelessWidget {
  const PermissionBanner({
    required this.message,
    this.actionLabel,
    this.onAction,
    super.key,
  });

  final String message;
  final String? actionLabel;
  final VoidCallback? onAction;

  @override
  Widget build(BuildContext context) {
    final tokens = FarmThemeExtension.of(context);
    final l10n = AppLocalizations.of(context);
    return Semantics(
      container: true,
      label: l10n.permissionBannerSemantics(message),
      child: Container(
        padding: const EdgeInsets.all(FarmSpacing.md),
        decoration: BoxDecoration(
          color: tokens.surface,
          borderRadius: BorderRadius.circular(FarmSpacing.md),
          border: Border.all(color: tokens.divider),
        ),
        child: Row(
          children: [
            Icon(Icons.lock_outline, size: 18, color: tokens.semanticWarning),
            const SizedBox(width: FarmSpacing.sm),
            Expanded(
              child: Text(
                message,
                style: Theme.of(
                  context,
                ).textTheme.bodySmall?.copyWith(color: tokens.semanticWarning),
                softWrap: true,
              ),
            ),
            if (actionLabel != null && onAction != null)
              TextButton(onPressed: onAction, child: Text(actionLabel!)),
          ],
        ),
      ),
    );
  }
}

/// Offline notice: cached data with an as-of anchor (spec 02 §7).
class OfflineBanner extends StatelessWidget {
  const OfflineBanner({this.asOf, super.key});

  final String? asOf;

  @override
  Widget build(BuildContext context) {
    final tokens = FarmThemeExtension.of(context);
    final l10n = AppLocalizations.of(context);
    final semantics = asOf == null
        ? l10n.offlineSemanticsNoDate
        : l10n.offlineSemantics(asOf!);
    return Semantics(
      container: true,
      label: semantics,
      child: Container(
        padding: const EdgeInsets.all(FarmSpacing.md),
        decoration: BoxDecoration(
          color: tokens.surface,
          borderRadius: BorderRadius.circular(FarmSpacing.md),
          border: Border.all(color: tokens.semanticWarning),
        ),
        child: Row(
          children: [
            Icon(
              Icons.cloud_off_outlined,
              size: 18,
              color: tokens.semanticWarning,
            ),
            const SizedBox(width: FarmSpacing.sm),
            Expanded(
              child: Text(
                asOf == null ? l10n.offlineNoDate : l10n.offlineWithDate(asOf!),
                style: Theme.of(
                  context,
                ).textTheme.bodySmall?.copyWith(color: tokens.semanticWarning),
                softWrap: true,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Pending-conflict notice linking to the Sync Center.
class PendingConflictBanner extends StatelessWidget {
  const PendingConflictBanner({
    required this.count,
    required this.onOpen,
    super.key,
  });

  final int count;
  final VoidCallback onOpen;

  @override
  Widget build(BuildContext context) {
    final tokens = FarmThemeExtension.of(context);
    final l10n = AppLocalizations.of(context);
    return Semantics(
      button: true,
      label: l10n.conflictBannerSemantics(count),
      child: InkWell(
        onTap: onOpen,
        borderRadius: BorderRadius.circular(FarmSpacing.md),
        child: Container(
          constraints: const BoxConstraints(
            minHeight: FarmSpacing.minTouchTarget,
          ),
          padding: const EdgeInsets.all(FarmSpacing.md),
          decoration: BoxDecoration(
            color: tokens.surface,
            borderRadius: BorderRadius.circular(FarmSpacing.md),
            border: Border.all(color: tokens.semanticWarning),
          ),
          child: Row(
            children: [
              Icon(
                Icons.sync_problem_outlined,
                size: 18,
                color: tokens.semanticWarning,
              ),
              const SizedBox(width: FarmSpacing.sm),
              Expanded(
                child: Text(
                  l10n.conflictBannerBody(count),
                  style: Theme.of(context).textTheme.bodySmall?.copyWith(
                    color: tokens.semanticWarning,
                  ),
                  softWrap: true,
                ),
              ),
              const Icon(Icons.chevron_right, size: 18),
            ],
          ),
        ),
      ),
    );
  }
}

/// Per-screen demo state switcher so every state of every resource screen is
/// inspectable (spec 02 §5: success/loading/empty/error/offline/denied/conflict).
/// Uses a modal bottom sheet instead of a popup menu: the sheet is positioned
/// by the framework and its rows can never render outside the viewport
/// (a popup here measured its row center at x=-195 on a 800x600 surface).
class DemoStateSwitcher extends ConsumerWidget {
  const DemoStateSwitcher({required this.screenKey, super.key});

  final String screenKey;

  Future<void> _openStateSheet(BuildContext context, WidgetRef ref) {
    return showModalBottomSheet<void>(
      context: context,
      builder: (sheetContext) => Consumer(
        builder: (context, sheetRef, _) {
          final l10n = AppLocalizations.of(context);
          final current = sheetRef.watch(
            demoScreenStateProvider.select((value) => value[screenKey]),
          );
          final tokens = FarmThemeExtension.of(sheetContext);
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
                  padding: const EdgeInsets.only(bottom: FarmSpacing.sm),
                  child: Text(
                    l10n.demoState,
                    style: Theme.of(sheetContext).textTheme.titleLarge,
                  ),
                ),
                for (final state in DemoLoadState.values)
                  Semantics(
                    button: true,
                    selected: current == state,
                    label: l10n.demoStateSelected(
                      _demoStateLabel(l10n, state),
                      current == state ? l10n.demoSelectedSuffix : '',
                    ),
                    child: ListTile(
                      leading: Icon(
                        current == state
                            ? Icons.check_circle
                            : Icons.tune_outlined,
                        color: current == state
                            ? tokens.brandAction
                            : tokens.textSecondary,
                      ),
                      title: Text(_demoStateLabel(l10n, state), softWrap: true),
                      onTap: () {
                        sheetRef
                            .read(demoScreenStateProvider.notifier)
                            .set(screenKey, state);
                        Navigator.of(sheetContext).pop();
                      },
                    ),
                  ),
              ],
            ),
          );
        },
      ),
    );
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context);
    final current = ref.watch(
      demoScreenStateProvider.select((value) => value[screenKey]),
    );
    final tokens = FarmThemeExtension.of(context);
    final label = current == null
        ? l10n.demoState
        : l10n.demoStateCurrent(_demoStateLabel(l10n, current));
    return Align(
      alignment: Alignment.centerLeft,
      child: LayoutBuilder(
        builder: (context, constraints) {
          final compact = constraints.maxWidth < 190;
          final control = compact
              ? IconButton(
                  tooltip: label,
                  onPressed: () => _openStateSheet(context, ref),
                  icon: const Icon(Icons.tune),
                )
              : InkWell(
                  onTap: () => _openStateSheet(context, ref),
                  borderRadius: BorderRadius.circular(FarmSpacing.md),
                  child: Container(
                    constraints: const BoxConstraints(
                      minHeight: FarmSpacing.minTouchTarget,
                    ),
                    padding: const EdgeInsets.symmetric(
                      horizontal: FarmSpacing.md,
                    ),
                    decoration: BoxDecoration(
                      borderRadius: BorderRadius.circular(FarmSpacing.md),
                      border: Border.all(color: tokens.divider),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(Icons.tune, size: 16, color: tokens.textSecondary),
                        const SizedBox(width: FarmSpacing.xs),
                        Flexible(
                          child: Text(
                            label,
                            style: Theme.of(context).textTheme.labelMedium
                                ?.copyWith(color: tokens.textSecondary),
                            softWrap: true,
                          ),
                        ),
                      ],
                    ),
                  ),
                );
          return Semantics(
            button: true,
            label: l10n.demoStateSwitchSemantics,
            child: control,
          );
        },
      ),
    );
  }
}

String _demoStateLabel(AppLocalizations l10n, DemoLoadState state) =>
    switch (state) {
      DemoLoadState.success => l10n.demoSuccess,
      DemoLoadState.loading => l10n.demoLoading,
      DemoLoadState.empty => l10n.demoEmpty,
      DemoLoadState.recoverableError => l10n.demoRecoverableError,
      DemoLoadState.offline => l10n.demoOffline,
      DemoLoadState.permissionDenied => l10n.demoPermissionDenied,
      DemoLoadState.pendingConflict => l10n.demoPendingConflict,
    };

/// Offline-safe toast copy: "Đã lưu trên thiết bị", never a server claim
/// (spec 02 §7).
void showFarmToast(BuildContext context, String message) {
  ScaffoldMessenger.of(context)
    ..hideCurrentSnackBar()
    ..showSnackBar(
      SnackBar(
        content: Text(message),
        duration: const Duration(milliseconds: 2200),
      ),
    );
}
