import 'package:flutter/material.dart';

import '../core/theme/farmly_spacing.dart';
import '../core/theme/farmly_colors.dart';
import '../core/theme/farmly_theme_extension.dart';
import '../l10n/generated/app_localizations.dart';

class FarmTabItem {
  const FarmTabItem({required this.outlinedIcon, required this.filledIcon});

  final IconData outlinedIcon;
  final IconData filledIcon;
}

/// Exactly five bottom tabs; AI is never a sixth tab (spec 02 §3).
const farmTabItems = <FarmTabItem>[
  FarmTabItem(outlinedIcon: Icons.home_outlined, filledIcon: Icons.home),
  FarmTabItem(
    outlinedIcon: Icons.landscape_outlined,
    filledIcon: Icons.landscape,
  ),
  FarmTabItem(
    outlinedIcon: Icons.insights_outlined,
    filledIcon: Icons.insights,
  ),
  FarmTabItem(outlinedIcon: Icons.eco_outlined, filledIcon: Icons.eco),
  FarmTabItem(outlinedIcon: Icons.person_outlined, filledIcon: Icons.person),
];

/// Scaffold shell with the cream background, optional custom top bar and
/// optional bottom bar. Hairline depth only. On ≥720dp tablet/landscape the
/// shell constrains body content to the 600dp max content width, centered
/// (spec 02 §2/§8); phones keep full-bleed layout unchanged.
class FarmScaffold extends StatelessWidget {
  const FarmScaffold({
    required this.body,
    this.topBar,
    this.bottomBar,
    super.key,
  });

  final Widget body;
  final Widget? topBar;
  final Widget? bottomBar;

  /// Tablet strategy: ≥720dp wide viewports center the content column at the
  /// §2 max content width of 600dp instead of stretching edge to edge.
  static Widget constrainToMaxContentWidth(
    BuildContext context,
    Widget child, {
    bool fillHeight = false,
  }) {
    if (MediaQuery.sizeOf(context).width < 720) return child;
    return LayoutBuilder(
      builder: (context, constraints) => Center(
        heightFactor: fillHeight ? null : 1,
        child: ConstrainedBox(
          constraints: BoxConstraints(
            maxWidth: 600,
            minHeight: fillHeight ? constraints.maxHeight : 0,
          ),
          child: child,
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Theme.of(context).scaffoldBackgroundColor,
      body: SafeArea(
        bottom: false,
        child: constrainToMaxContentWidth(
          context,
          Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              ?topBar,
              Expanded(child: body),
            ],
          ),
          fillHeight: true,
        ),
      ),
      bottomNavigationBar: bottomBar,
    );
  }
}

/// Screen header row: title (+ subtitle) then trailing actions. Order keeps
/// the requested focus sequence header → hero → summary → tasks.
class FarmTopBar extends StatelessWidget {
  const FarmTopBar({
    required this.title,
    this.subtitle,
    this.actions = const <Widget>[],
    super.key,
  });

  final String title;
  final String? subtitle;
  final List<Widget> actions;

  @override
  Widget build(BuildContext context) {
    final tokens = FarmThemeExtension.of(context);
    final textScale = MediaQuery.textScalerOf(context).scale(14) / 14;
    // Column layout only when the title row is genuinely crowded: large text,
    // or a phone width carrying more than two actions. With one or two icon
    // actions the row keeps them beside the title instead of stranding a
    // single icon on its own line under a wide empty band.
    final compact =
        textScale >= 1.5 ||
        (MediaQuery.sizeOf(context).width < 520 && actions.length > 2);
    final titleContent = Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          title,
          style: Theme.of(context).textTheme.titleLarge,
          softWrap: true,
        ),
        if (subtitle != null)
          Text(
            subtitle!,
            style: Theme.of(
              context,
            ).textTheme.bodySmall?.copyWith(color: tokens.textSecondary),
            softWrap: true,
          ),
      ],
    );
    return Padding(
      padding: const EdgeInsets.fromLTRB(
        FarmSpacing.lg,
        FarmSpacing.lg,
        FarmSpacing.lg,
        FarmSpacing.sm,
      ),
      child: compact
          ? Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                titleContent,
                if (actions.isNotEmpty) ...[
                  const SizedBox(height: FarmSpacing.xs),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.end,
                    children: actions,
                  ),
                ],
              ],
            )
          : Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(child: titleContent),
                const SizedBox(width: FarmSpacing.sm),
                ...actions,
              ],
            ),
    );
  }
}

/// Adaptive bottom navigation bar (spec 02 §4 [AdaptiveBottomBar]): five
/// 48dp+ targets with labels that wrap under large text scaling. On phones
/// the row spans full width; on ≥720dp tablet/landscape it is centered under
/// the 600dp max content width instead of stretching edge to edge (spec 02
/// §2/§8).
class AdaptiveBottomBar extends StatelessWidget {
  const AdaptiveBottomBar({
    required this.currentIndex,
    required this.onTap,
    super.key,
  });

  final int currentIndex;
  final ValueChanged<int> onTap;

  @override
  Widget build(BuildContext context) {
    final tokens = FarmThemeExtension.of(context);
    final l10n = AppLocalizations.of(context);
    final labels = <String>[
      l10n.homeTab,
      l10n.farmTab,
      l10n.analyticsTab,
      l10n.harvestTab,
      l10n.profileTab,
    ];
    final row = Row(
      children: List.generate(farmTabItems.length, (index) {
        final item = farmTabItems[index];
        final selected = index == currentIndex;
        return Expanded(
          child: Semantics(
            button: true,
            selected: selected,
            child: InkWell(
              onTap: () => onTap(index),
              child: AnimatedContainer(
                duration: context.farmPressDuration(),
                constraints: const BoxConstraints(
                  minHeight: 60,
                  minWidth: FarmSpacing.minTouchTarget,
                ),
                padding: const EdgeInsets.symmetric(
                  vertical: FarmSpacing.sm,
                  horizontal: FarmSpacing.xs,
                ),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Container(
                      width: 40,
                      height: 30,
                      decoration: BoxDecoration(
                        color: selected
                            ? tokens.brandSage.withValues(alpha: 0.32)
                            : null,
                        borderRadius: BorderRadius.circular(12),
                        border: selected
                            ? Border.all(color: tokens.divider)
                            : null,
                        boxShadow: selected
                            ? [
                                BoxShadow(
                                  color: tokens.brandAction.withValues(
                                    alpha: 0.08,
                                  ),
                                  offset: const Offset(0, 2),
                                  blurRadius: 3,
                                ),
                              ]
                            : null,
                      ),
                      child: Icon(
                        selected ? item.filledIcon : item.outlinedIcon,
                        size: 24,
                        color: selected
                            ? tokens.brandAction
                            : tokens.textSecondary,
                      ),
                    ),
                    const SizedBox(height: FarmSpacing.xs),
                    Text(
                      labels[index],
                      textAlign: TextAlign.center,
                      style: Theme.of(context).textTheme.labelMedium?.copyWith(
                        color: selected
                            ? tokens.brandAction
                            : tokens.textSecondary,
                      ),
                      softWrap: true,
                    ),
                  ],
                ),
              ),
            ),
          ),
        );
      }),
    );
    return Material(
      color: tokens.surface,
      elevation: 6,
      shadowColor: tokens.brandAction.withValues(alpha: 0.12),
      child: SafeArea(
        top: false,
        child: Container(
          decoration: const BoxDecoration(
            border: Border(top: BorderSide(color: FarmlyColors.divider)),
          ),
          child: FarmScaffold.constrainToMaxContentWidth(context, row),
        ),
      ),
    );
  }
}
