import 'package:flutter/material.dart';

import '../core/theme/farmly_spacing.dart';

/// Staggered entrance — fades in while rising a few logical pixels. When the
/// platform requests reduced motion the child renders statically (widget
/// tests and accessibility users therefore never wait on it).
class FarmEntrance extends StatelessWidget {
  const FarmEntrance({
    required this.child,
    this.delay = Duration.zero,
    super.key,
  });

  final Widget child;
  final Duration delay;

  @override
  Widget build(BuildContext context) {
    if (context.farmReducedMotion()) return child;
    final total = FarmSpacing.entrance + delay;
    final beginAt = delay.inMicroseconds / total.inMicroseconds;
    return TweenAnimationBuilder<double>(
      tween: Tween(begin: 0, end: 1),
      duration: total,
      curve: Interval(beginAt, 1, curve: Curves.easeOutCubic),
      child: child,
      builder: (context, value, child) => Opacity(
        opacity: value,
        child: Transform.translate(
          offset: Offset(0, 12 * (1 - value)),
          child: child,
        ),
      ),
    );
  }
}

/// Ambient animation driver — repeats `period`, delivering a 0..1 phase to
/// [builder] for continuous scenes (cloud drift, pond ripples). Under reduced
/// motion it renders phase 0 statically and never starts the ticker.
class FarmAmbientLoop extends StatefulWidget {
  const FarmAmbientLoop({
    required this.builder,
    this.period = FarmSpacing.ambient,
    super.key,
  });

  final Widget Function(BuildContext context, double phase) builder;
  final Duration period;

  @override
  State<FarmAmbientLoop> createState() => _FarmAmbientLoopState();
}

class _FarmAmbientLoopState extends State<FarmAmbientLoop>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller = AnimationController(
    vsync: this,
    duration: widget.period,
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
      return widget.builder(context, 0);
    }
    return AnimatedBuilder(
      animation: _controller,
      builder: (context, _) => widget.builder(context, _controller.value),
    );
  }
}
