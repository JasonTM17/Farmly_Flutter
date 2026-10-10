import 'package:flutter/material.dart';

import '../core/theme/farmly_spacing.dart';

/// Staggered entrance — fades in while rising a few logical pixels. When the
/// platform requests reduced motion the child renders statically (widget
/// tests and accessibility users therefore never wait on it).
class FarmEntrance extends StatelessWidget {
  const FarmEntrance({
    required this.child,
    this.delay = Duration.zero,
    this.pop = false,
    this.drop = false,
    super.key,
  });

  final Widget child;
  final Duration delay;

  /// Pop entrances scale up from 55% with an overshoot curve — used for map
  /// tiles and cards that should land with a bounce rather than fade in.
  final bool pop;

  /// Drop entrances fall from above onto the board instead of rising —
  /// the reference map's tiles drop in like game pieces.
  final bool drop;

  @override
  Widget build(BuildContext context) {
    if (context.farmReducedMotion()) return child;
    final total = FarmSpacing.entrance * (pop ? 1.6 : 1) + delay;
    final beginAt = delay.inMicroseconds / total.inMicroseconds;
    return TweenAnimationBuilder<double>(
      tween: Tween(begin: 0, end: 1),
      duration: total,
      curve: Interval(
        beginAt,
        1,
        curve: drop
            ? Curves.bounceOut
            : pop
                ? Curves.easeOutBack
                : Curves.easeOutCubic,
      ),
      child: child,
      builder: (context, value, child) => Opacity(
        opacity: value.clamp(0.0, 1.0),
        child: Transform.translate(
          offset: Offset(0, (drop ? -34 : pop ? 26 : 12) * (1 - value)),
          child: Transform.scale(
            scale: (pop || drop) ? 0.55 + 0.45 * value : 1,
            child: child,
          ),
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


/// One-shot dust puff that plays when a map tile lands — small circles
/// expanding and fading from the tile's bottom edge, like the impact puff
/// in the reference video. Under reduced motion it paints nothing and
/// never ticks.
class FarmDustPuff extends StatefulWidget {
  const FarmDustPuff({required this.delay, super.key});

  /// Starts right as the parent tile's drop-in lands.
  final Duration delay;

  @override
  State<FarmDustPuff> createState() => _FarmDustPuffState();
}

class _FarmDustPuffState extends State<FarmDustPuff>
    with SingleTickerProviderStateMixin {
  // Nullable on purpose: under reduced motion the controller is never
  // created, and touching a lazy `late final` in dispose() would construct
  // a ticker on an already-deactivating element.
  AnimationController? _controller;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (context.farmReducedMotion()) return;
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 420),
    );
    Future<void>.delayed(widget.delay, () {
      if (mounted) _controller?.forward();
    });
  }

  @override
  void dispose() {
    _controller?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final controller = _controller;
    if (context.farmReducedMotion() || controller == null) {
      return const SizedBox.shrink();
    }
    return AnimatedBuilder(
      animation: controller,
      builder: (context, _) => CustomPaint(
        painter: _DustPuffPainter(
          Curves.easeOut.transform(controller.value),
        ),
      ),
    );
  }
}

class _DustPuffPainter extends CustomPainter {
  const _DustPuffPainter(this.t);

  final double t;

  @override
  void paint(Canvas canvas, Size size) {
    if (t <= 0 || t >= 1) return;
    final paint = Paint()
      ..color = const Color(0xFF8D7B5F).withValues(alpha: (1 - t) * 0.35);
    // Two burst clusters at the tile's bottom corners.
    for (final cx in [size.width * 0.18, size.width * 0.82]) {
      for (var i = 0; i < 3; i++) {
        final spread = 14.0 * t + i * 4.0;
        final p = Offset(
          cx + (i - 1) * spread,
          size.height - 6 - t * 7 + (i == 1 ? -4 : 0),
        );
        canvas.drawCircle(p, (1 - t) * (4.2 - i * 0.8), paint);
      }
    }
  }

  @override
  bool shouldRepaint(_DustPuffPainter old) => old.t != t;
}
