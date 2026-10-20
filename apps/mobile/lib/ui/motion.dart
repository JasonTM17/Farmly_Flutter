import 'dart:async';

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
          offset: Offset(
            0,
            (drop
                    ? -34
                    : pop
                    ? 26
                    : 12) *
                (1 - value),
          ),
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
///
/// The phase is quantized to 60 steps per second to keep scene motion aligned
/// with standard display refresh while sharing one phase across each painter
/// group.
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
  /// One shared phase step per frame on a standard 60Hz display.
  static const int _updatesPerSecond = 60;

  AnimationController? _controller;

  double _phase = 0;
  int _lastStep = -1;

  int get _phaseStepCount =>
      (widget.period.inMicroseconds *
              _updatesPerSecond /
              Duration.microsecondsPerSecond)
          .round();

  bool get _hasValidPeriod =>
      widget.period > Duration.zero && _phaseStepCount > 1;

  AnimationController _createController() =>
      AnimationController(vsync: this, duration: widget.period)
        ..addListener(_onTick);

  void _syncMotion() {
    final controller = _controller;
    if (context.farmReducedMotion() || !_hasValidPeriod) {
      controller?.stop();
      _phase = 0;
      _lastStep = -1;
      return;
    }
    final activeController = _controller ??= _createController();
    if (!activeController.isAnimating) activeController.repeat();
  }

  /// Quantize the controller value; only rebuild the subtree when the step
  /// actually changes, not on every display tick.
  void _onTick() {
    final steps = _phaseStepCount;
    if (steps <= 0) return;
    final step = ((_controller?.value ?? 0) * steps).floor();
    if (step == _lastStep) return;
    _lastStep = step;
    setState(() => _phase = step / steps);
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _syncMotion();
  }

  @override
  void didUpdateWidget(covariant FarmAmbientLoop oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.period == widget.period) return;
    final controller = _controller;
    controller?.stop();
    if (_hasValidPeriod) {
      controller?.duration = widget.period;
      final steps = _phaseStepCount;
      if (controller != null) {
        _lastStep = (controller.value * steps).floor();
        _phase = _lastStep / steps;
      }
    } else {
      _phase = 0;
      _lastStep = -1;
    }
    _syncMotion();
  }

  @override
  void dispose() {
    _controller?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (context.farmReducedMotion() || !_hasValidPeriod) {
      return widget.builder(context, 0);
    }
    return widget.builder(context, _phase);
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
  // A single reusable controller lets reduced-motion changes pause and resume
  // this one-shot without allocating another ticker from didChangeDependencies.
  AnimationController? _controller;
  Timer? _startTimer;
  bool _started = false;

  void _syncMotion() {
    if (context.farmReducedMotion()) {
      _startTimer?.cancel();
      _startTimer = null;
      _controller?.stop();
      return;
    }

    final controller = _controller ??= AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 420),
    );
    if (_started) {
      if (!controller.isCompleted && !controller.isAnimating) {
        controller.forward();
      }
      return;
    }
    _startTimer ??= Timer(widget.delay, () {
      _startTimer = null;
      if (!mounted || context.farmReducedMotion()) return;
      _started = true;
      _controller?.forward();
    });
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _syncMotion();
  }

  @override
  void didUpdateWidget(covariant FarmDustPuff oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.delay != widget.delay && !_started) {
      _startTimer?.cancel();
      _startTimer = null;
      _syncMotion();
    }
  }

  @override
  void dispose() {
    _startTimer?.cancel();
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
        painter: _DustPuffPainter(Curves.easeOut.transform(controller.value)),
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
