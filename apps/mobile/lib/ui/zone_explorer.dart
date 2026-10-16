import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../core/theme/farmly_colors.dart';
import '../core/theme/farmly_spacing.dart';
import '../core/theme/farmly_theme_extension.dart';
import '../features/demo/demo_models.dart';
import '../l10n/generated/app_localizations.dart';
import 'motion.dart';

IconData _zoneIcon(DemoZoneKind kind, {required bool filled}) {
  switch (kind) {
    case DemoZoneKind.crop:
      return filled ? Icons.grass : Icons.grass_outlined;
    case DemoZoneKind.livestock:
      return filled ? Icons.pets : Icons.pets_outlined;
    case DemoZoneKind.water:
      return filled ? Icons.water_drop : Icons.water_drop_outlined;
    case DemoZoneKind.storage:
      return filled ? Icons.warehouse : Icons.warehouse_outlined;
    case DemoZoneKind.house:
      return filled ? Icons.home : Icons.home_outlined;
  }
}

/// Horizontal zone chip strip (My Farm overview header).
class ZoneChipStrip extends StatelessWidget {
  const ZoneChipStrip({
    required this.zones,
    required this.selectedZoneId,
    required this.onSelect,
    this.overviewLabel,
    super.key,
  });

  final List<DemoZone> zones;
  final String? selectedZoneId;

  /// Called with a zone id, or  when the leading Overview chip is
  /// tapped (reference My Farm: the first chip shows the whole map).
  final ValueChanged<String?> onSelect;
  final String? overviewLabel;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: FarmSpacing.minTouchTarget,
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: FarmSpacing.lg),
        itemCount: zones.length + (overviewLabel == null ? 0 : 1),
        separatorBuilder: (_, _) => const SizedBox(width: FarmSpacing.sm),
        itemBuilder: (context, index) {
          if (overviewLabel != null && index == 0) {
            return Center(
              child: ChoiceChip(
                label: Text(overviewLabel!),
                selected: selectedZoneId == null,
                onSelected: (_) => onSelect(null),
              ),
            );
          }
          final zone = zones[index - (overviewLabel == null ? 0 : 1)];
          final selected = zone.id == selectedZoneId;
          return Center(
            child: ChoiceChip(
              label: Text(zone.name),
              selected: selected,
              onSelected: (_) => onSelect(zone.id),
              avatar: Icon(
                _zoneIcon(zone.kind, filled: selected),
                size: 16,
                color: selected
                    ? FarmThemeExtension.of(context).onAction
                    : FarmThemeExtension.of(context).brandAction,
              ),
            ),
          );
        },
      ),
    );
  }
}

/// Illustrated farm scene with zoomable hotspots bound to real zone IDs
/// (spec 02 §5 My Farm row and phase 05). A semantic list fallback is provided
/// separately by [AccessibleZoneList].
class ZoneScene extends StatefulWidget {
  const ZoneScene({
    required this.zones,
    required this.selectedZoneId,
    required this.onSelect,
    required this.onOpenDetail,
    this.onAdd,
    super.key,
  });

  final List<DemoZone> zones;
  final String? selectedZoneId;
  final ValueChanged<String> onSelect;
  final ValueChanged<DemoZone> onOpenDetail;

  /// Shows the floating "+" beside the reset control in the map's bottom
  /// right corner (reference has an add-zone affordance there). Null hides
  /// the button. Zone details open from the zone panel / accessible list —
  /// tiles select + focus on tap so a single tap never waits on the
  /// double-tap window.
  final VoidCallback? onAdd;

  @override
  State<ZoneScene> createState() => _ZoneSceneState();
}

class _ZoneSceneState extends State<ZoneScene> with TickerProviderStateMixin {
  final TransformationController _transform = TransformationController();
  AnimationController? _zoomController;
  Animation<Matrix4>? _zoomAnimation;

  /// Last viewport size the fit transform was computed/applied for. The
  /// first frame can report a 0×0 viewport, so the fit re-applies whenever
  /// the measured size changes — never a one-shot flag.
  Size? _fitForViewport;

  /// Measured viewport + board sizes, captured in LayoutBuilder so camera
  /// math uses board-space tile centers against the real viewport.
  Size _viewportSize = Size.zero;
  Size _boardSize = Size.zero;

  @override
  void didUpdateWidget(ZoneScene oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.zones.length != oldWidget.zones.length) {
      // Board height changed — refit so every plot stays visible.
      _fitForViewport = null;
    }
    // Any selection change flies the camera — tapping a tile, a chip in
    // the strip, or picking from the accessible list all dive the same
    // way, so there is a single camera path. Deferred: mutating the
    // transform synchronously inside didUpdateWidget rebuilds
    // InteractiveViewer's internal keyed gesture detector mid-build,
    // which trips a sliver "indexOf(child) > index" assertion when the
    // scene sits inside the page ListView.
    if (widget.selectedZoneId != oldWidget.selectedZoneId) {
      final id = widget.selectedZoneId;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted) return;
        final zone = id == null
            ? null
            : widget.zones.where((z) => z.id == id).firstOrNull;
        if (zone != null) {
          _focusZone(zone);
        } else {
          _resetView();
        }
      });
    }
  }

  @override
  void dispose() {
    _zoomAnimation?.removeListener(_onZoomTick);
    _zoomController?.dispose();
    _transform.dispose();
    super.dispose();
  }

  void _onZoomTick() {
    final animation = _zoomAnimation;
    if (animation != null) _transform.value = animation.value;
  }

  void _animateTo(Matrix4 target) {
    if (_transform.value == target) return;
    _zoomAnimation?.removeListener(_onZoomTick);
    _zoomController?.dispose();
    final controller = AnimationController(
      vsync: this,
      duration: context.farmCameraFlightDuration(),
    );
    _zoomController = controller;
    final begin = _transform.value;
    // Fly ~4.5% past the target then settle — the little dip at the end of
    // the reference's camera dive.
    final overshoot = Matrix4.copy(target)
      ..scaleByDouble(1.045, 1.045, 1.0, 1.0);
    _zoomAnimation = controller.drive(
      TweenSequence<Matrix4>(<TweenSequenceItem<Matrix4>>[
        TweenSequenceItem(
          tween: Matrix4Tween(
            begin: begin,
            end: overshoot,
          ).chain(CurveTween(curve: Curves.easeInOutCubic)),
          weight: 78,
        ),
        TweenSequenceItem(
          tween: Matrix4Tween(
            begin: overshoot,
            end: target,
          ).chain(CurveTween(curve: Curves.easeInOutQuad)),
          weight: 22,
        ),
      ]),
    )..addListener(_onZoomTick);
    controller.forward();
  }

  /// The fitted whole-board view — what reset returns to, not raw identity.
  Matrix4 _fit = Matrix4.identity();

  void _resetView() => _animateTo(_fit);

  /// Plot tiles are chunky rounded squares (~42% of map width) on a loose
  /// two-column grid — the reference map's board-game layout.
  static double _tileW(Size canvas) => canvas.width * 0.42;
  static double _tileH(Size canvas) => _tileW(canvas) * 0.72;

  /// Painter order, back row first so nearer plots overdraw correctly.
  List<DemoZone> get _ordered =>
      widget.zones.toList()..sort((a, b) => (a.x + a.y).compareTo(b.x + b.y));

  int _cellIndex(DemoZone zone) => _ordered.indexWhere((z) => z.id == zone.id);

  /// Number of grid rows for the current zone list (two per row).
  int get _rows => (_ordered.length + 1) ~/ 2;

  /// Canvas height grows with the board: each row is one tile pitch tall.
  /// 34px top margin leaves room for the overlapping label pills.
  double _mapHeight(double width) {
    final th = width * 0.42 * 0.72;
    final pitch = th * 1.38;
    return 34 + pitch * (_rows - 1) + th + 28;
  }

  /// The map viewport is capped so the floating controls always sit on the
  /// visible board. When the board is taller than the cap, the initial
  /// transform fits it — the whole farm stays visible like the reference
  /// board, and InteractiveViewer pan/zoom still works from there.
  Matrix4 _fitTransform(double viewportW, double viewportH, double boardH) {
    if (viewportW <= 0 || viewportH <= 0 || boardH <= 0) {
      return Matrix4.identity();
    }
    final s = viewportH / boardH;
    // Only fit when the board meaningfully overflows — and never produce a
    // degenerate scale (InteractiveViewer hit-tests need an invertible
    // matrix; scale 0 throws "Matrix cannot be inverted").
    if (s >= 0.99 || s <= 0.2) return Matrix4.identity();
    final dx = (viewportW - viewportW * s) / 2;
    return Matrix4.identity()
      ..translateByDouble(dx, 0, 0, 1)
      ..scaleByDouble(s, s, 1, 1);
  }

  /// Grid cell center with a small per-zone jitter so the grid reads organic
  /// rather than rigid. Rows are spaced by tile pitch, not a canvas fraction,
  /// so taller boards keep a constant rhythm.
  Offset _tileCenter(DemoZone zone, int index, Size canvas) {
    final col = index % 2;
    final row = index ~/ 2;
    final th = _tileH(canvas);
    final pitch = th * 1.38;
    final jx = (zone.x - 0.5) * canvas.width * 0.05;
    final jy = (zone.y - 0.5) * canvas.height * 0.04;
    return Offset(
      canvas.width * (0.28 + col * 0.44) + jx,
      34 + th / 2 + pitch * row + jy,
    );
  }

  void _focusZone(DemoZone zone) {
    final viewport = _viewportSize;
    final board = _boardSize;
    if (viewport.isEmpty || board.isEmpty) return;
    // Deep, slow flight into the tapped plot — the reference's signature
    // "camera dives into the tile" feel. Tile centers live in board space;
    // the translation lands that point at the viewport's center.
    const scale = 2.4;
    final center = _tileCenter(zone, _cellIndex(zone), board);
    final dx = viewport.width / 2 - center.dx * scale;
    final dy = viewport.height / 2 - center.dy * scale;
    _animateTo(
      Matrix4.identity()
        ..translateByDouble(dx, dy, 0, 1)
        ..scaleByDouble(scale, scale, 1, 1),
    );
  }

  @override
  Widget build(BuildContext context) {
    final tokens = FarmThemeExtension.of(context);
    final l10n = AppLocalizations.of(context);
    final boardW = MediaQuery.sizeOf(context).width - FarmSpacing.lg * 2;
    final boardH = _mapHeight(boardW);
    // Cap the viewport so the map + the floating controls stay visible
    // without scrolling — a fitted board (pan/zoom still allowed) reads
    // like the reference's whole-farm board.
    final viewportH = math.min(
      boardH,
      MediaQuery.sizeOf(context).height * 0.52,
    );
    return Stack(
      children: [
        ClipRRect(
          borderRadius: BorderRadius.circular(tokens.cardRadius),
          child: SizedBox(
            height: viewportH,
            width: double.infinity,
            child: LayoutBuilder(
              builder: (context, vp) {
                _boardSize = Size(boardW, boardH);
                _viewportSize = Size(vp.maxWidth, vp.maxHeight);
                _fit = _fitTransform(vp.maxWidth, vp.maxHeight, boardH);
                // Refit whenever the measured viewport changes — the first
                // frame can be 0×0, and later zone additions change the
                // board. Applying inside a post-frame callback keeps the
                // transform write out of the build phase.
                final fitKey = _viewportSize;
                if (_fitForViewport != fitKey) {
                  _fitForViewport = fitKey;
                  WidgetsBinding.instance.addPostFrameCallback((_) {
                    if (mounted) _transform.value = _fit;
                  });
                }
                return InteractiveViewer(
                  transformationController: _transform,
                  maxScale: 3,
                  // Below the fit scale so a fitted board is still legal.
                  minScale: 0.5,
                  panEnabled: true,
                  // Board is taller than the capped viewport — the child
                  // keeps its natural size and pans/zooms inside. Margin
                  // must stay finite: EdgeInsets.all(double.infinity)
                  // produces a singular matrix in InteractiveViewer's hit
                  // test ("Matrix cannot be inverted").
                  constrained: false,
                  boundaryMargin: EdgeInsets.all(boardH),
                  child: SizedBox(
                    // Unconstrained viewer → explicit board size, never
                    // double.infinity (infinite width is invalid here).
                    width: boardW,
                    height: boardH,
                    child: LayoutBuilder(
                      builder: (context, constraints) {
                        final canvas = Size(
                          constraints.maxWidth,
                          constraints.maxHeight,
                        );
                        return FarmAmbientLoop(
                          builder: (context, phase) => Stack(
                            clipBehavior: Clip.none,
                            children: [
                              Positioned.fill(
                                child: CustomPaint(
                                  painter: _IsoGroundPainter(phase: phase),
                                ),
                              ),
                              // Painter order: iso rows back-to-front so nearer
                              // tiles overdraw further ones correctly.
                              for (final (tileIndex, zone) in _ordered.indexed)
                                () {
                                  final center = _tileCenter(
                                    zone,
                                    tileIndex,
                                    canvas,
                                  );
                                  final selected =
                                      zone.id == widget.selectedZoneId;
                                  final tw = _tileW(canvas);
                                  final th = _tileH(canvas);
                                  return Positioned(
                                    left: center.dx - tw / 2,
                                    top: center.dy - th / 2 - 26,
                                    width: tw,
                                    height: th + 26,
                                    child: Semantics(
                                      button: true,
                                      selected: selected,
                                      label: l10n.zoneTileSemantics(zone.name),
                                      excludeSemantics: true,
                                      child: GestureDetector(
                                        behavior: HitTestBehavior.translucent,
                                        // Selection change drives the
                                        // camera via didUpdateWidget —
                                        // one flight path for tile tap,
                                        // chip strip, and accessible list.
                                        onTap: () => widget.onSelect(zone.id),
                                        // Selected plot lifts ~6px with a soft
                                        // overshoot — the little "pop" that makes
                                        // the reference's taps feel physical.
                                        child: TweenAnimationBuilder<double>(
                                          tween: Tween<double>(
                                            begin: 0,
                                            end: selected ? -1 : 0,
                                          ),
                                          duration: context.farmStateDuration(),
                                          curve: Curves.easeOutBack,
                                          builder: (context, lift, child) =>
                                              Transform.translate(
                                                offset: Offset(0, lift * 6),
                                                child: child,
                                              ),
                                          child: FarmEntrance(
                                            drop: true,
                                            delay: Duration(
                                              milliseconds: 90 * tileIndex,
                                            ),
                                            child: Stack(
                                              clipBehavior: Clip.none,
                                              children: [
                                                Positioned(
                                                  left: 0,
                                                  right: 0,
                                                  top: 12,
                                                  bottom: 0,
                                                  child: CustomPaint(
                                                    painter: IsoZoneTilePainter(
                                                      kind: zone.kind,
                                                      selected: selected,
                                                      phase: phase,
                                                      name: zone.name,
                                                    ),
                                                  ),
                                                ),
                                                Positioned(
                                                  left: 8,
                                                  top: 0,
                                                  child: _ZoneLabelChip(
                                                    name: zone.name,
                                                    kind: zone.kind,
                                                    selected: selected,
                                                  ),
                                                ),
                                                // Impact puff as the tile lands.
                                                Positioned.fill(
                                                  top: 12,
                                                  child: IgnorePointer(
                                                    child: FarmDustPuff(
                                                      delay: Duration(
                                                        milliseconds:
                                                            90 * tileIndex +
                                                            220,
                                                      ),
                                                    ),
                                                  ),
                                                ),
                                              ],
                                            ),
                                          ),
                                        ),
                                      ),
                                    ),
                                  );
                                }(),
                              // Broad soft shadows sweeping across the whole board
                              // on the ambient phase — overhead cloud cover passing
                              // like in the reference video's shaded board.
                              Positioned.fill(
                                child: IgnorePointer(
                                  child: CustomPaint(
                                    painter: _CloudDriftPainter(phase: phase),
                                  ),
                                ),
                              ),
                            ],
                          ),
                        );
                      },
                    ),
                  ),
                );
              },
            ),
          ),
        ),
        if (widget.onAdd != null)
          // Bottom-right cluster beside the reset control: the old top-right
          // spot collided with the leading tile's label chip (maxWidth 116 +
          // zone.x jitter pushed chips under the button).
          Positioned(
            right: FarmSpacing.sm + FarmSpacing.minTouchTarget + FarmSpacing.xs,
            bottom: FarmSpacing.sm + FarmSpacing.xs,
            child: Semantics(
              button: true,
              label: l10n.addZoneTooltip,
              child: Material(
                color: FarmlyColors.surface,
                shape: const CircleBorder(),
                elevation: 2,
                child: InkWell(
                  customBorder: const CircleBorder(),
                  onTap: widget.onAdd,
                  child: const SizedBox.square(
                    dimension: 40,
                    child: Icon(Icons.add, color: FarmlyColors.brandAction),
                  ),
                ),
              ),
            ),
          ),
        Positioned(
          right: FarmSpacing.sm,
          bottom: FarmSpacing.sm,
          child: Semantics(
            button: true,
            label: l10n.resetMapSemantics,
            child: Material(
              color: tokens.surface,
              shape: const CircleBorder(
                side: BorderSide(color: FarmlyColors.divider),
              ),
              child: IconButton(
                tooltip: l10n.resetMapView,
                onPressed: _resetView,
                icon: const Icon(Icons.center_focus_strong_outlined),
                constraints: const BoxConstraints(
                  minWidth: FarmSpacing.minTouchTarget,
                  minHeight: FarmSpacing.minTouchTarget,
                ),
              ),
            ),
          ),
        ),
      ],
    );
  }
}

/// Soft green base plane under the iso tiles (light grid of plot lines).
class _IsoGroundPainter extends CustomPainter {
  const _IsoGroundPainter({this.phase = 0});

  /// Ambient phase — edge trees sway a touch so the board feels alive.
  final double phase;

  @override
  void paint(Canvas canvas, Size size) {
    canvas.drawRect(
      Rect.fromLTWH(0, 0, size.width, size.height),
      Paint()
        ..color = Color.lerp(
          FarmlyColors.brandSage,
          FarmlyColors.background,
          0.55,
        )!,
    );
    // Faint diagonal plot lines give the map its isometric ground texture.
    final line = Paint()
      ..color = Color.lerp(
        FarmlyColors.brandSage,
        FarmlyColors.textPrimary,
        0.15,
      )!.withValues(alpha: 0.12)
      ..strokeWidth = 1;
    final step = size.width / 9;
    for (var i = -4; i < 14; i++) {
      canvas.drawLine(
        Offset(step * i, 0),
        Offset(step * i + size.height * 1.6, size.height),
        line,
      );
      canvas.drawLine(
        Offset(step * i, size.height),
        Offset(step * i + size.height * 1.6, 0),
        line,
      );
    }

    // Winding dirt walkway down the board's centre gap — the reference map
    // threads a path between the two plot columns.
    final dirt = Paint()
      ..color = Color.lerp(
        FarmlyColors.semanticWarning,
        FarmlyColors.surface,
        0.35,
      )!.withValues(alpha: 0.5)
      ..style = PaintingStyle.stroke
      ..strokeWidth = size.width * 0.035
      ..strokeCap = StrokeCap.round;
    final path = Path()..moveTo(size.width * 0.5, size.height * 0.03);
    for (var i = 0; i < 6; i++) {
      final y = size.height * (0.03 + (i + 1) * 0.16);
      final xOff = (i.isEven ? 1 : -1) * size.width * 0.015;
      path.quadraticBezierTo(
        size.width * 0.5 + xOff * 2,
        size.height * (0.03 + i * 0.16 + 0.08),
        size.width * 0.5 + xOff,
        y,
      );
    }
    canvas.drawPath(path, dirt);

    // Decorative edge trees — canopy spheres with a trunk, leaning a couple
    // of px on the ambient phase like the crop sway.
    final trunk = Paint()
      ..color = Color.lerp(
        FarmlyColors.semanticWarning,
        FarmlyColors.textPrimary,
        0.45,
      )!
      ..strokeWidth = 2.4
      ..strokeCap = StrokeCap.round;
    final canopy = Paint()
      ..color = Color.lerp(
        FarmlyColors.brandAction,
        FarmlyColors.brandSage,
        0.3,
      )!;
    final spots = <Offset>[
      Offset(size.width * 0.06, size.height * 0.12),
      Offset(size.width * 0.94, size.height * 0.24),
      Offset(size.width * 0.05, size.height * 0.52),
      Offset(size.width * 0.95, size.height * 0.62),
      Offset(size.width * 0.07, size.height * 0.88),
    ];
    final treeShade = Paint()
      ..color = FarmlyColors.textPrimary.withValues(alpha: 0.10);
    for (var i = 0; i < spots.length; i++) {
      final p0 = spots[i];
      final sway = math.sin(phase * 2 * math.pi + i * 1.3) * 1.4;
      canvas.drawOval(
        Rect.fromCenter(center: p0 + const Offset(0, 8), width: 16, height: 5),
        treeShade,
      );
      canvas.drawLine(
        Offset(p0.dx, p0.dy + 7),
        Offset(p0.dx, p0.dy - 2),
        trunk,
      );
      canvas.drawCircle(Offset(p0.dx + sway, p0.dy - 8), 8.5, canopy);
      canvas.drawCircle(
        Offset(p0.dx + sway - 2.5, p0.dy - 11),
        3.4,
        Paint()..color = FarmlyColors.surface.withValues(alpha: 0.4),
      );
    }

    // Scatter: pebbles and tiny wildflowers along the outer margins — the
    // reference board is dressed between and around the plots, not bare.
    final rock = Paint()
      ..color = FarmlyColors.textSecondary.withValues(alpha: 0.35);
    final flowerCore = Paint()..color = FarmlyColors.semanticWarning;
    final flowerPetal = Paint()
      ..color = FarmlyColors.surface.withValues(alpha: 0.9);
    final decor = <(double, double, int)>[
      (0.06, 0.34, 0),
      (0.93, 0.42, 0),
      (0.5, 0.30, 1),
      (0.07, 0.70, 1),
      (0.94, 0.80, 0),
      (0.5, 0.72, 1),
      (0.08, 0.99, 0),
      (0.92, 0.10, 1),
    ];
    for (final (fx, fy, kind) in decor) {
      final c = Offset(size.width * fx, size.height * fy);
      if (kind == 0) {
        canvas.drawOval(
          Rect.fromCenter(center: c, width: 7, height: 4.5),
          rock,
        );
      } else {
        // Four-petal wildflower: light petals + warm core.
        for (var p4 = 0; p4 < 4; p4++) {
          canvas.drawCircle(
            c +
                Offset(
                  math.cos(p4 * math.pi / 2) * 2.6,
                  math.sin(p4 * math.pi / 2) * 2.6,
                ),
            1.7,
            flowerPetal,
          );
        }
        canvas.drawCircle(c, 1.4, flowerCore);
      }
    }
  }

  @override
  bool shouldRepaint(_IsoGroundPainter oldDelegate) =>
      oldDelegate.phase != phase;
}

/// Soft cloud shadows drifting left→right across the board — three blurred
/// bands at different heights and speeds so the sky reads alive over the
/// plots, matching the reference's moving shade.
class _CloudDriftPainter extends CustomPainter {
  const _CloudDriftPainter({required this.phase});

  final double phase;

  @override
  void paint(Canvas canvas, Size size) {
    final shade = Paint()
      ..color = FarmlyColors.textPrimary.withValues(alpha: 0.05)
      ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 26);
    // Each band wraps the canvas on its own period and at its own altitude.
    for (final (speed, cy, w, h, offset)
        in <(double, double, double, double, double)>[
          (0.55, 0.16, 0.62, 0.15, 0.0),
          (0.38, 0.55, 0.75, 0.20, 0.45),
          (0.68, 0.86, 0.52, 0.12, 0.75),
        ]) {
      final t = (phase * speed + offset) % 1.0;
      final cx = size.width * (-0.45 + t * 1.9);
      canvas.drawOval(
        Rect.fromCenter(
          center: Offset(cx, size.height * cy),
          width: size.width * w,
          height: size.height * h,
        ),
        shade,
      );
    }
  }

  @override
  bool shouldRepaint(_CloudDriftPainter oldDelegate) =>
      oldDelegate.phase != phase;
}

/// Pill label above each tile, like the reference zone tags.
class _ZoneLabelChip extends StatelessWidget {
  const _ZoneLabelChip({
    required this.name,
    required this.kind,
    required this.selected,
  });

  final String name;
  final DemoZoneKind kind;
  final bool selected;

  @override
  Widget build(BuildContext context) {
    final tokens = FarmThemeExtension.of(context);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
      constraints: const BoxConstraints(maxWidth: 116),
      decoration: BoxDecoration(
        color: selected ? tokens.brandAction : tokens.surface,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(
          color: selected ? tokens.brandAction : tokens.divider,
        ),
      ),
      child: Text(
        name,
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        style: Theme.of(context).textTheme.labelSmall?.copyWith(
          color: selected ? tokens.onAction : tokens.textPrimary,
        ),
      ),
    );
  }
}

/// One extruded isometric zone tile: a 2:1 diamond top face with left/right
/// side walls for depth, and kind-specific interior detail — crop rows for
/// fields, a pond for water zones, a small building for house/storage, a
/// fenced pasture for livestock.
class IsoZoneTilePainter extends CustomPainter {
  const IsoZoneTilePainter({
    required this.kind,
    required this.selected,
    this.phase = 0,
    this.name = '',
  });

  final DemoZoneKind kind;
  final bool selected;

  /// Zone display name — picks the interior variant (e.g. trellised tomato
  /// field vs leafy beds) so each plot matches what it actually grows.
  final String name;

  /// Ambient phase 0..1 — pond ripples expand, pasture animals bob.
  final double phase;

  @override
  void paint(Canvas canvas, Size size) {
    final w = size.width;
    final h = size.height;

    // Raised platform: a darker skirt under the rounded top face gives each
    // plot its extruded 3D block look (reference map tiles float above the
    // grass). ~9% of the tile height reads as the side wall.
    final depth = h * 0.09;
    final faceH = h - depth - 6; // 6px reserved for the soft shadow bleed.
    const radius = Radius.circular(16);
    final face = RRect.fromRectAndRadius(Rect.fromLTWH(0, 0, w, faceH), radius);
    final skirt = RRect.fromRectAndRadius(
      Rect.fromLTWH(0, depth, w, faceH),
      radius,
    );

    final base = _baseColor();
    canvas.drawRRect(
      skirt.shift(const Offset(0, 7)),
      Paint()
        ..color = FarmlyColors.textPrimary.withValues(alpha: 0.16)
        ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 7),
    );
    canvas.drawRRect(
      skirt,
      Paint()..color = Color.lerp(base, FarmlyColors.textPrimary, 0.42)!,
    );
    canvas.drawRRect(face, Paint()..color = base);

    canvas.save();
    canvas.clipRRect(face);
    _paintInterior(canvas, w, faceH);
    canvas.restore();

    if (selected) {
      // Breathing halo: the glow alpha rides the ambient phase so the
      // active plot reads alive instead of just outlined.
      final glow = 0.28 + 0.14 * math.sin(phase * 2 * math.pi);
      canvas.drawRRect(
        face.inflate(5),
        Paint()
          ..color = FarmlyColors.brandAction.withValues(alpha: glow)
          ..style = PaintingStyle.stroke
          ..strokeWidth = 6
          ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 6),
      );
    }
    canvas.drawRRect(
      face,
      Paint()
        ..color = selected
            ? FarmlyColors.brandAction
            : Color.lerp(base, FarmlyColors.textPrimary, 0.3)!
        ..style = PaintingStyle.stroke
        ..strokeWidth = selected ? 3.2 : 1.6,
    );
  }

  Color _baseColor() => switch (kind) {
    DemoZoneKind.crop => Color.lerp(
      FarmlyColors.semanticWarning,
      FarmlyColors.background,
      0.52,
    )!,
    DemoZoneKind.livestock => Color.lerp(
      FarmlyColors.brandSage,
      FarmlyColors.surface,
      0.28,
    )!,
    DemoZoneKind.water => Color.lerp(
      FarmlyColors.illustrationWater,
      FarmlyColors.surface,
      0.5,
    )!,
    DemoZoneKind.storage || DemoZoneKind.house => Color.lerp(
      FarmlyColors.brandSage,
      FarmlyColors.surface,
      0.5,
    )!,
  };

  /// A little sphere: shaded base circle plus a top-left highlight so plants
  /// and animals read as 3D blobs rather than flat dots.
  void _sphere(Canvas canvas, Offset c, double r, Color color) {
    canvas.drawCircle(
      c + Offset(r * 0.22, r * 0.3),
      r,
      Paint()..color = Color.lerp(color, FarmlyColors.textPrimary, 0.22)!,
    );
    canvas.drawCircle(c, r, Paint()..color = color);
    canvas.drawCircle(
      c + Offset(-r * 0.3, -r * 0.34),
      r * 0.36,
      Paint()..color = FarmlyColors.surface.withValues(alpha: 0.55),
    );
  }

  void _paintInterior(Canvas canvas, double w, double h) {
    switch (kind) {
      case DemoZoneKind.crop:
        final lower = name.toLowerCase();
        if (lower.contains('cà chua') || lower.contains('tomato')) {
          _paintTomatoField(canvas, w, h);
        } else if (lower.contains('ngô') ||
            lower.contains('corn') ||
            lower.contains('bắp')) {
          _paintCornField(canvas, w, h);
        } else {
          _paintLeafyField(canvas, w, h);
        }
      case DemoZoneKind.livestock:
        // Pasture with fence + 3D-ish grazing blobs that bob on the phase.
        final fence = Paint()
          ..color = Color.lerp(
            FarmlyColors.semanticWarning,
            FarmlyColors.surface,
            0.22,
          )!
          ..strokeWidth = 2.6
          ..strokeCap = StrokeCap.round;
        canvas.drawLine(
          Offset(w * 0.06, h * 0.68),
          Offset(w * 0.94, h * 0.68),
          fence,
        );
        canvas.drawLine(
          Offset(w * 0.06, h * 0.8),
          Offset(w * 0.94, h * 0.8),
          fence,
        );
        for (var i = 0; i < 4; i++) {
          final x = w * (0.15 + i * 0.235);
          canvas.drawLine(Offset(x, h * 0.62), Offset(x, h * 0.88), fence);
        }
        // Water trough in the corner.
        final trough = RRect.fromRectAndRadius(
          Rect.fromLTWH(w * 0.68, h * 0.14, w * 0.2, h * 0.12),
          const Radius.circular(4),
        );
        canvas.drawRRect(
          trough,
          Paint()..color = FarmlyColors.illustrationWater,
        );
        canvas.drawRRect(
          trough,
          Paint()
            ..color = FarmlyColors.textSecondary
            ..style = PaintingStyle.stroke
            ..strokeWidth = 1.4,
        );
        // Five scattered animals, alternating sizes — the reference pasture
        // is busy, not a tidy row.
        const spots = <double>[0.16, 0.34, 0.5, 0.68, 0.84];
        for (var i = 0; i < spots.length; i++) {
          final bob =
              math.sin(phase * 2 * math.pi + i * 2.1) * (i.isEven ? 2.4 : 0);
          // Graze wander: each animal strolls a few px back and forth.
          final wander = math.sin(phase * 2 * math.pi + i * 1.7) * w * 0.03;
          final small = i.isOdd;
          final p = Offset(
            w * spots[i] + wander,
            h * (i.isEven ? 0.3 : 0.46) + bob,
          );
          final bw = small ? 17.0 : 24.0;
          final bh = small ? 10.0 : 14.0;
          canvas.drawOval(
            Rect.fromCenter(center: p, width: bw, height: bh),
            Paint()..color = FarmlyColors.surface,
          );
          canvas.drawOval(
            Rect.fromCenter(center: p, width: bw, height: bh),
            Paint()
              ..color = FarmlyColors.textSecondary
              ..style = PaintingStyle.stroke
              ..strokeWidth = 1.3,
          );
          _sphere(
            canvas,
            p + Offset(bw * 0.46, -4),
            small ? 4 : 5.2,
            Color.lerp(FarmlyColors.surface, FarmlyColors.textSecondary, 0.12)!,
          );
        }
      case DemoZoneKind.water:
        // Round tank + satellite pond rendered as ellipses (viewed at an
        // angle); ripple rings expand and fade with the phase.
        final tankRect = Rect.fromCenter(
          center: Offset(w * 0.36, h * 0.4),
          width: w * 0.42,
          height: h * 0.52,
        );
        final pondRect = Rect.fromCenter(
          center: Offset(w * 0.76, h * 0.62),
          width: w * 0.24,
          height: h * 0.26,
        );
        final water = Paint()
          ..color = Color.lerp(
            FarmlyColors.illustrationWater,
            FarmlyColors.textPrimary,
            0.18,
          )!;
        final waterEdge = Paint()
          ..color = Color.lerp(
            FarmlyColors.illustrationWater,
            FarmlyColors.textPrimary,
            0.42,
          )!;
        // Darker under-ellipse sells the cylinder wall of each pool.
        canvas.drawOval(tankRect.shift(const Offset(0, 5)), waterEdge);
        canvas.drawOval(tankRect, water);
        canvas.drawOval(pondRect.shift(const Offset(0, 3)), waterEdge);
        canvas.drawOval(pondRect, water);
        for (var r = 0; r < 3; r++) {
          final cycle = (phase + r / 3) % 1.0;
          canvas.drawOval(
            Rect.fromCenter(
              center: tankRect.center,
              width: tankRect.width * (0.36 + cycle * 0.5),
              height: tankRect.height * (0.36 + cycle * 0.5),
            ),
            Paint()
              ..color = FarmlyColors.surface.withValues(
                alpha: 0.75 * (1 - cycle),
              )
              ..style = PaintingStyle.stroke
              ..strokeWidth = 2,
          );
        }
        final lily = Paint()..color = FarmlyColors.brandAction;
        canvas.drawCircle(Offset(w * 0.72, h * 0.57), 3.6, lily);
        canvas.drawCircle(Offset(w * 0.81, h * 0.65), 3, lily);
        // Rotating sheen sweeping the tank surface.
        final sheen = Paint()
          ..color = FarmlyColors.surface.withValues(alpha: 0.55)
          ..style = PaintingStyle.stroke
          ..strokeWidth = 2.4
          ..strokeCap = StrokeCap.round;
        final sweep = phase * 2 * math.pi;
        canvas.drawArc(
          Rect.fromCenter(
            center: Offset(w * 0.36, h * 0.42),
            width: w * 0.34,
            height: w * 0.34 * 0.62,
          ),
          sweep,
          1.1,
          false,
          sheen,
        );
      case DemoZoneKind.house:
        _paintBuilding(canvas, w, h, FarmlyColors.illustrationBarn);
      case DemoZoneKind.storage:
        _paintBuilding(canvas, w, h, FarmlyColors.textSecondary);
    }
  }

  /// Two garden beds: big lettuce spheres up top, dense seedlings below —
  /// the reference vegetable plot has exactly this split.
  void _paintLeafyField(Canvas canvas, double w, double h) {
    final furrow = Paint()
      ..color = Color.lerp(
        FarmlyColors.semanticWarning,
        FarmlyColors.textPrimary,
        0.34,
      )!
      ..strokeCap = StrokeCap.round;
    for (var r = 0; r < 2; r++) {
      final y = h * (0.18 + r * 0.17);
      furrow.strokeWidth = 3;
      canvas.drawLine(Offset(w * 0.12, y + 7), Offset(w * 0.88, y + 7), furrow);
      for (var i = 0; i < 5; i++) {
        final sway = math.sin(phase * 2 * math.pi + i * 0.9 + r) * 1.8;
        final px = w * (0.16 + i * 0.17) + sway;
        _sphere(canvas, Offset(px, y), 6.4, FarmlyColors.brandAction);
      }
    }
    canvas.drawRect(
      Rect.fromLTWH(w * 0.1, h * 0.54, w * 0.8, h * 0.36),
      Paint()
        ..color = Color.lerp(
          FarmlyColors.semanticWarning,
          FarmlyColors.textPrimary,
          0.18,
        )!,
    );
    // Grass tufts poking through the topsoil between rows.
    final tuft = Paint()
      ..color = FarmlyColors.brandAction.withValues(alpha: 0.55)
      ..strokeWidth = 1.6
      ..strokeCap = StrokeCap.round;
    for (var i = 0; i < 6; i++) {
      final px = w * (0.14 + i * 0.145);
      final py = h * 0.46 + (i.isEven ? 0 : 4);
      canvas.drawLine(Offset(px, py + 5), Offset(px - 2, py - 3), tuft);
      canvas.drawLine(Offset(px, py + 5), Offset(px, py - 4), tuft);
      canvas.drawLine(Offset(px, py + 5), Offset(px + 2, py - 3), tuft);
    }
    final seedling = Paint()
      ..color = Color.lerp(
        FarmlyColors.brandAction,
        FarmlyColors.semanticWarning,
        0.25,
      )!;
    for (var r = 0; r < 3; r++) {
      for (var i = 0; i < 8; i++) {
        final sway = math.sin(phase * 2 * math.pi + i * 0.7 + r * 0.5) * 1.2;
        canvas.drawCircle(
          Offset(w * (0.14 + i * 0.103) + sway, h * (0.61 + r * 0.11)),
          2.6,
          seedling,
        );
      }
    }
  }

  /// Trellised tomato field: vertical stakes, green bushes, red fruit dots.
  void _paintTomatoField(Canvas canvas, double w, double h) {
    final stake = Paint()
      ..color = Color.lerp(
        FarmlyColors.semanticWarning,
        FarmlyColors.textPrimary,
        0.4,
      )!
      ..strokeWidth = 2
      ..strokeCap = StrokeCap.round;
    final fruit = Paint()..color = FarmlyColors.semanticError;
    for (var r = 0; r < 3; r++) {
      final y = h * (0.22 + r * 0.26);
      canvas.drawLine(Offset(w * 0.1, y), Offset(w * 0.9, y), stake);
      for (var i = 0; i < 5; i++) {
        final sway = math.sin(phase * 2 * math.pi + i * 0.8 + r * 0.4) * 1.6;
        final px = w * (0.14 + i * 0.18);
        canvas.drawLine(Offset(px, y - 8), Offset(px, y + 8), stake);
        _sphere(
          canvas,
          Offset(px + sway, y - 4),
          5.4,
          FarmlyColors.brandAction,
        );
        canvas.drawCircle(Offset(px + sway + 3.4, y - 2), 1.9, fruit);
      }
    }
  }

  /// Corn field: tall green stalk strokes with golden kernel dots, like the
  /// reference's dense corn tile.
  void _paintCornField(Canvas canvas, double w, double h) {
    final stalk = Paint()
      ..color = FarmlyColors.brandAction
      ..strokeWidth = 2.2
      ..strokeCap = StrokeCap.round;
    final kernel = Paint()..color = FarmlyColors.semanticWarning;
    for (var r = 0; r < 4; r++) {
      final t = r / 3;
      final y = h * (0.2 + r * 0.2);
      for (var i = 0; i < 7; i++) {
        final px = w * (0.12 + i * 0.127);
        // Stalk sways; kernel dots ride the lean.
        final sway = math.sin(phase * 2 * math.pi + i * 0.75 + r * 0.55) * 2.6;
        canvas.drawLine(
          Offset(px, y + 6),
          Offset(px + sway, y - 8 - t * 2),
          stalk,
        );
        canvas.drawCircle(Offset(px + sway - 2.4, y - 2), 1.8, kernel);
        canvas.drawCircle(Offset(px + sway + 2.4, y - 5), 1.8, kernel);
      }
    }
  }

  void _paintBuilding(Canvas canvas, double w, double h, Color wall) {
    final cx = w / 2;
    final cy = h * 0.52;
    final isHouse = kind == DemoZoneKind.house;
    final darkWall = Color.lerp(wall, FarmlyColors.textPrimary, 0.35)!;
    // Chimney sits behind the roof on houses.
    if (isHouse) {
      canvas.drawRect(
        Rect.fromLTWH(cx + w * 0.08, cy - h * 0.3, w * 0.045, h * 0.14),
        Paint()..color = darkWall,
      );
    }
    // Walls with a darker right face = a 3D block, not a flat rect.
    canvas.drawRect(
      Rect.fromLTWH(cx - w * 0.16, cy - h * 0.04, w * 0.32, h * 0.32),
      Paint()..color = wall,
    );
    canvas.drawRect(
      Rect.fromLTWH(cx + w * 0.08, cy - h * 0.04, w * 0.08, h * 0.32),
      Paint()..color = darkWall,
    );
    // Gabled roof: overhangs the walls both sides + a visible ridge stroke.
    final roofColor = isHouse
        ? FarmlyColors.semanticError.withValues(alpha: 0.85)
        : FarmlyColors.surface;
    final roof = Path()
      ..moveTo(cx - w * 0.21, cy - h * 0.02)
      ..lineTo(cx, cy - h * 0.28)
      ..lineTo(cx + w * 0.21, cy - h * 0.02)
      ..lineTo(cx + w * 0.16, cy - h * 0.02)
      ..lineTo(cx, cy - h * 0.22)
      ..lineTo(cx - w * 0.16, cy - h * 0.02)
      ..close();
    canvas.drawPath(
      roof,
      Paint()..color = Color.lerp(roofColor, FarmlyColors.textPrimary, 0.08)!,
    );
    // Round window on the left face, door centred on the front.
    canvas.drawCircle(
      Offset(cx - w * 0.04, cy + h * 0.05),
      w * 0.035,
      Paint()..color = FarmlyColors.surface,
    );
    canvas.drawCircle(
      Offset(cx - w * 0.04, cy + h * 0.05),
      w * 0.035,
      Paint()
        ..color = darkWall
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1.2,
    );
    canvas.drawRect(
      Rect.fromLTWH(
        cx + (isHouse ? w * 0.02 : -w * 0.075),
        cy + h * 0.08,
        isHouse ? w * 0.07 : w * 0.15,
        h * 0.2,
      ),
      Paint()..color = FarmlyColors.surface,
    );
    if (!isHouse) {
      // Cross-brace on the barn door.
      final brace = Paint()
        ..color = darkWall
        ..strokeWidth = 1.4;
      canvas.drawLine(
        Offset(cx - w * 0.075, cy + h * 0.08),
        Offset(cx + w * 0.075, cy + h * 0.28),
        brace,
      );
      canvas.drawLine(
        Offset(cx + w * 0.075, cy + h * 0.08),
        Offset(cx - w * 0.075, cy + h * 0.28),
        brace,
      );
    }
  }

  @override
  bool shouldRepaint(IsoZoneTilePainter oldDelegate) =>
      oldDelegate.kind != kind ||
      oldDelegate.selected != selected ||
      oldDelegate.phase != phase;
}

/// Semantically-complete list fallback for the explorer scene: the same zone
/// IDs as the hotspots, readable by screen readers without gestures.
class AccessibleZoneList extends StatelessWidget {
  const AccessibleZoneList({
    required this.zones,
    required this.selectedZoneId,
    required this.onOpenDetail,
    super.key,
  });

  final List<DemoZone> zones;
  final String? selectedZoneId;
  final ValueChanged<DemoZone> onOpenDetail;

  @override
  Widget build(BuildContext context) {
    final tokens = FarmThemeExtension.of(context);
    final l10n = AppLocalizations.of(context);
    return Column(
      children: zones
          .map(
            (zone) => Semantics(
              button: true,
              label:
                  '${l10n.zoneListEntry(zone.name)}'
                  '${zone.subtitle == null ? '' : ', ${zone.subtitle}'}'
                  '${zone.id == selectedZoneId ? l10n.zoneListSelectedSuffix : ''}'
                  '${l10n.openZoneDetailSuffix}',
              child: ListTile(
                leading: Icon(_zoneIcon(zone.kind, filled: false)),
                title: Text(zone.name, softWrap: true),
                subtitle: zone.subtitle == null
                    ? null
                    : Text(zone.subtitle!, softWrap: true),
                selected: zone.id == selectedZoneId,
                selectedTileColor: tokens.brandSage.withValues(alpha: 0.25),
                trailing: const Icon(Icons.chevron_right),
                onTap: () => onOpenDetail(zone),
              ),
            ),
          )
          .toList(),
    );
  }
}
