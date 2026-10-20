import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../core/theme/farmly_colors.dart';
import '../core/theme/farmly_spacing.dart';
import '../core/theme/farmly_theme_extension.dart';
import '../features/demo/demo_models.dart';
import '../l10n/generated/app_localizations.dart';
import 'farm_life_painter.dart';
import 'clay_shapes.dart';
import 'farm_structure_painter.dart';
import 'farm_scene_accents.dart';
import 'farm_scene_details.dart';
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
    final tokens = FarmThemeExtension.of(context);
    final labelStyle = Theme.of(context).chipTheme.labelStyle;
    // The strip grows with the scaled chip label so 200% text never clips;
    // the floor keeps the full 48dp touch-target band at normal scale.
    final scaledLabelHeight = MediaQuery.textScalerOf(
      context,
    ).scale((labelStyle?.fontSize ?? 14) * (labelStyle?.height ?? 1.35));
    final stripHeight = math.max(
      FarmSpacing.minTouchTarget,
      scaledLabelHeight + FarmSpacing.xxl + FarmSpacing.xs,
    );
    return SizedBox(
      height: stripHeight,
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: FarmSpacing.lg),
        itemCount: zones.length + (overviewLabel == null ? 0 : 1),
        separatorBuilder: (_, _) => const SizedBox(width: FarmSpacing.sm),
        itemBuilder: (context, index) {
          if (overviewLabel != null && index == 0) {
            final selected = selectedZoneId == null;
            return Center(
              child: ChoiceChip(
                label: Text(overviewLabel!),
                selected: selected,
                showCheckmark: false,
                materialTapTargetSize: MaterialTapTargetSize.padded,
                onSelected: (_) => onSelect(null),
                avatar: Icon(
                  Icons.grid_view_rounded,
                  size: 16,
                  color: selected ? tokens.onAction : tokens.brandAction,
                ),
              ),
            );
          }
          final zone = zones[index - (overviewLabel == null ? 0 : 1)];
          final selected = zone.id == selectedZoneId;
          return Center(
            child: ChoiceChip(
              label: Text(zone.name),
              selected: selected,
              showCheckmark: false,
              materialTapTargetSize: MaterialTapTargetSize.padded,
              onSelected: (_) => onSelect(zone.id),
              avatar: Icon(
                _zoneIcon(zone.kind, filled: selected),
                size: 16,
                color: selected ? tokens.onAction : tokens.brandAction,
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
    this.onOpenAnimals,
    super.key,
  });

  final List<DemoZone> zones;
  final String? selectedZoneId;
  final ValueChanged<String> onSelect;
  final ValueChanged<DemoZone> onOpenDetail;
  final VoidCallback? onOpenAnimals;

  /// Shows the floating "+" beside the reset control in the map's bottom
  /// right corner (reference has an add-zone affordance there). Null hides
  /// the button. Every plot opens its detail on the first tap; selection also
  /// keeps the camera focused when the user returns to the map.
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

  void _openMeadow() =>
      showFarmMeadow(context, onOpenAnimals: widget.onOpenAnimals);

  void _activateZone(DemoZone zone) {
    widget.onSelect(zone.id);
    widget.onOpenDetail(zone);
  }

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
                        final meadowHeight = _tileH(canvas) * 0.64;
                        // Convert fixed screen-space control clearance back to
                        // the fitted board; omit decor if that row cannot fit.
                        final meadowTop = math.min(
                          34 + _tileH(canvas) * 1.38 * (_rows - 1),
                          (vp.maxHeight - FarmSpacing.minTouchTarget - 16) /
                                  _fit.entry(0, 0) -
                              meadowHeight,
                        );
                        final previousRowBottom =
                            34 +
                            _tileH(canvas) * 1.38 * (_rows - 2) +
                            _tileH(canvas);
                        return FarmAmbientLoop(
                          builder: (context, phase) => Stack(
                            clipBehavior: Clip.none,
                            children: [
                              Positioned.fill(
                                child: CustomPaint(
                                  painter: _IsoGroundPainter(phase: phase),
                                ),
                              ),
                              // The meadow is inspectable scenery in the vacant
                              // final right cell, separate from domain zones.
                              if (_ordered.length >= 3 &&
                                  _ordered.length.isOdd &&
                                  meadowTop >= previousRowBottom)
                                Positioned(
                                  left: canvas.width * 0.52,
                                  top: meadowTop,
                                  width: _tileW(canvas) * 0.93,
                                  height: meadowHeight,
                                  child: Semantics(
                                    button: true,
                                    excludeSemantics: true,
                                    onTap: _openMeadow,
                                    label: l10n.localeName.startsWith('vi')
                                        ? 'Đồng cỏ, chạm để xem bò'
                                        : 'Meadow, tap to watch cows',
                                    child: GestureDetector(
                                      key: const ValueKey(
                                        'farm-meadow-hotspot',
                                      ),
                                      behavior: HitTestBehavior.opaque,
                                      onTap: _openMeadow,
                                      child: Stack(
                                        children: [
                                          Positioned.fill(
                                            child: CustomPaint(
                                              painter: FarmMeadowPainter(
                                                phase: phase,
                                              ),
                                            ),
                                          ),
                                          Positioned(
                                            left: 8,
                                            top: 0,
                                            child: Text(
                                              l10n.localeName.startsWith('vi')
                                                  ? 'Đồng cỏ'
                                                  : 'Meadow',
                                              style: const TextStyle(
                                                fontSize: 9,
                                                color: FarmlyColors.textPrimary,
                                                fontWeight: FontWeight.w600,
                                              ),
                                            ),
                                          ),
                                        ],
                                      ),
                                    ),
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
                                      onTap: () => _activateZone(zone),
                                      child: GestureDetector(
                                        behavior: HitTestBehavior.translucent,
                                        // Selection change drives the
                                        // camera via didUpdateWidget —
                                        // one flight path for tile tap,
                                        // chip strip, and accessible list.
                                        onTap: () => _activateZone(zone),
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

    // Decorative edge trees use the same top-left light and faceted foliage
    // as the plots; each crown sways slightly around its planted trunk.
    final spots = <Offset>[
      Offset(size.width * 0.06, size.height * 0.12),
      Offset(size.width * 0.94, size.height * 0.24),
      Offset(size.width * 0.05, size.height * 0.52),
      Offset(size.width * 0.95, size.height * 0.62),
      Offset(size.width * 0.07, size.height * 0.88),
    ];
    for (var i = 0; i < spots.length; i++) {
      FarmLifePainter.drawTree(
        canvas,
        ground: spots[i],
        scale: i.isEven ? 0.94 : 0.82,
        phase: phase,
        seed: i,
      );
    }

    // Rooted tufts animate with the same wind as the edge trees.
    for (var i = 0; i < 10; i++) {
      FarmLifePainter.drawGrassTuft(
        canvas,
        ground: Offset(
          size.width * (i.isEven ? 0.09 : 0.91),
          size.height * (0.18 + (i ~/ 2) * 0.16),
        ),
        scale: 0.8,
        phase: phase,
        seed: i,
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

  /// Ambient phase 0..1 — ripples, rooted grass and walking pasture animals.
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
    canvas.drawRRect(
      face,
      Paint()
        ..shader = LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [
            ClayShapes.light(base, 0.18),
            base,
            ClayShapes.dark(base, 0.06),
          ],
          stops: const [0, 0.55, 1],
        ).createShader(face.outerRect),
    );

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
        FarmSceneAccents.butterfly(
          canvas,
          bounds: Rect.fromLTWH(w * 0.1, h * 0.15, w * 0.8, h * 0.55),
          phase: phase,
          golden: lower.contains('ngô') || lower.contains('corn'),
        );
      case DemoZoneKind.livestock:
        // Buildings and actors are decorative, never operational quantities.
        FarmStructurePainter.building(
          canvas,
          bounds: Rect.fromLTWH(w * 0.06, h * 0.15, w * 0.28, h * 0.29),
          kind: FarmStructureKind.barn,
        );
        FarmSceneAccents.buildingLife(
          canvas,
          bounds: Rect.fromLTWH(w * 0.06, h * 0.15, w * 0.28, h * 0.29),
          kind: FarmStructureKind.barn,
          phase: phase,
        );
        FarmStructurePainter.fence(
          canvas,
          bounds: Rect.fromLTWH(w * 0.06, h * 0.62, w * 0.88, h * 0.26),
        );
        FarmStructurePainter.trough(
          canvas,
          bounds: Rect.fromLTWH(w * 0.68, h * 0.14, w * 0.2, h * 0.12),
        );
        for (var i = 0; i < 7; i++) {
          FarmLifePainter.drawGrassTuft(
            canvas,
            ground: Offset(w * (0.12 + i * 0.12), h * (i.isEven ? 0.4 : 0.65)),
            scale: 0.72,
            phase: phase,
            seed: i,
          );
        }
        // Lane-bound decorative walkers, never herd-count data.
        const spots = <double>[0.16, 0.34, 0.5, 0.68, 0.84];
        final form = FarmLifePainter.formForZoneName(name);
        for (var i = 0; i < spots.length; i++) {
          FarmLifePainter.drawPastureAnimal(
            canvas,
            ground: Offset(w * spots[i], h * (i.isEven ? 0.48 : 0.56)),
            scale: i.isOdd ? 0.78 : 0.9,
            phase: phase,
            seed: i,
            form: form,
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
        final waterEdge = Paint()
          ..color = Color.lerp(
            FarmlyColors.illustrationWater,
            FarmlyColors.textPrimary,
            0.42,
          )!;
        // Darker under-ellipse sells the cylinder wall of each pool.
        canvas.drawOval(tankRect.shift(const Offset(0, 5)), waterEdge);
        ClayShapes.oval(canvas, tankRect, FarmlyColors.illustrationWater);
        canvas.drawOval(pondRect.shift(const Offset(0, 3)), waterEdge);
        ClayShapes.oval(canvas, pondRect, FarmlyColors.illustrationWater);
        FarmSceneAccents.pondFish(
          canvas,
          bounds: tankRect.deflate(w * 0.018),
          phase: phase,
        );
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
        FarmSceneAccents.lily(
          canvas,
          center: Offset(w * 0.72, h * 0.57),
          phase: phase,
          seed: 0,
        );
        FarmSceneAccents.lily(
          canvas,
          center: Offset(w * 0.81, h * 0.65),
          phase: phase,
          seed: 2,
        );
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

  /// Two garden beds: layered lettuce plants up top and raised seedlings below —
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
      final y = h * (0.23 + r * 0.21);
      furrow.strokeWidth = 3;
      canvas.drawLine(Offset(w * 0.12, y + 7), Offset(w * 0.88, y + 7), furrow);
      for (var i = 0; i < 5; i++) {
        final px = w * (0.16 + i * 0.17);
        FarmSceneAccents.lettuce(
          canvas,
          ground: Offset(px, y + 3.5),
          scale: 1.55 * w / 150,
          phase: phase,
          seed: r * 7 + i,
        );
      }
    }
    final soil = Color.lerp(
      FarmlyColors.semanticWarning,
      FarmlyColors.textPrimary,
      0.28,
    )!;
    for (var row = 0; row < 2; row++) {
      final bed = Rect.fromLTWH(
        w * 0.09,
        h * (0.57 + row * 0.16),
        w * 0.82,
        h * 0.14,
      );
      canvas.drawRRect(
        RRect.fromRectAndRadius(
          bed.shift(const Offset(0, 2)),
          const Radius.circular(4),
        ),
        Paint()..color = ClayShapes.dark(soil, 0.3),
      );
      canvas.drawRRect(
        RRect.fromRectAndRadius(bed, const Radius.circular(4)),
        Paint()
          ..shader = LinearGradient(
            colors: [ClayShapes.light(soil, 0.2), soil],
          ).createShader(bed),
      );
    }
    // Grass tufts poking through the topsoil between rows.
    for (var i = 0; i < 6; i++) {
      final px = w * (0.14 + i * 0.145);
      final py = h * 0.46 + (i.isEven ? 0 : 4);
      FarmLifePainter.drawGrassTuft(
        canvas,
        ground: Offset(px, py + 5),
        scale: 0.8,
        phase: phase,
        seed: i,
      );
    }
    for (var r = 0; r < 2; r++) {
      for (var i = 0; i < 6; i++) {
        FarmSceneAccents.lettuce(
          canvas,
          ground: Offset(w * (0.15 + i * 0.14), h * (0.66 + r * 0.16) + 1.5),
          scale: 0.84 * w / 150,
          phase: phase,
          seed: r * 11 + i,
        );
      }
    }
  }

  /// Trellised tomato field: vertical stakes, faceted leaves and fruit.
  void _paintTomatoField(Canvas canvas, double w, double h) {
    final stake = Paint()
      ..color = Color.lerp(
        FarmlyColors.semanticWarning,
        FarmlyColors.textPrimary,
        0.4,
      )!
      ..strokeWidth = 2
      ..strokeCap = StrokeCap.round;
    for (var r = 0; r < 3; r++) {
      final y = h * (0.26 + r * 0.27);
      canvas.drawLine(Offset(w * 0.1, y), Offset(w * 0.9, y), stake);
      for (var i = 0; i < 5; i++) {
        final px = w * (0.14 + i * 0.18);
        canvas.drawLine(Offset(px, y - 8), Offset(px, y + 8), stake);
        FarmSceneAccents.tomato(
          canvas,
          ground: Offset(px, y + 7),
          scale: 1.35 * w / 150,
          phase: phase,
          seed: r * 7 + i,
        );
      }
    }
  }

  /// Corn field: tall faceted stalks with shaded golden ears.
  void _paintCornField(Canvas canvas, double w, double h) {
    for (var r = 0; r < 3; r++) {
      final t = r / 2;
      final y = h * (0.28 + r * 0.26);
      for (var i = 0; i < 5; i++) {
        final px = w * (0.15 + i * 0.175);
        // The leaves, cob and stalk lean together on the ambient phase.
        FarmLifePainter.drawCornStalk(
          canvas,
          ground: Offset(px, y + 7),
          scale: (1.3 + t * 0.08) * w / 150,
          phase: phase,
          seed: r * 13 + i,
        );
      }
    }
  }

  void _paintBuilding(Canvas canvas, double w, double h, Color wall) {
    FarmStructurePainter.building(
      canvas,
      bounds: Rect.fromLTWH(w * 0.19, h * 0.12, w * 0.62, h * 0.76),
      kind: kind == DemoZoneKind.house
          ? FarmStructureKind.house
          : FarmStructureKind.storage,
      detailed: true,
    );
    FarmSceneAccents.buildingLife(
      canvas,
      bounds: Rect.fromLTWH(w * 0.19, h * 0.12, w * 0.62, h * 0.76),
      kind: kind == DemoZoneKind.house
          ? FarmStructureKind.house
          : FarmStructureKind.storage,
      phase: phase,
    );
    for (var i = 0; i < 4; i++) {
      FarmLifePainter.drawGrassTuft(
        canvas,
        ground: Offset(w * (0.12 + i * 0.25), h * 0.9),
        scale: 0.85,
        phase: phase,
        seed: i + 30,
      );
    }
  }

  @override
  bool shouldRepaint(IsoZoneTilePainter oldDelegate) =>
      oldDelegate.kind != kind ||
      oldDelegate.name != name ||
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
    final l10n = AppLocalizations.of(context);
    return Column(
      children: [
        for (final (index, zone) in zones.indexed) ...[
          if (index > 0)
            const Divider(
              height: 1,
              indent: FarmSpacing.lg + _previewWidth + FarmSpacing.md,
              endIndent: FarmSpacing.lg,
            ),
          Semantics(
            button: true,
            selected: zone.id == selectedZoneId,
            label:
                '${l10n.zoneListEntry(zone.name)}'
                '${zone.subtitle == null ? '' : ', ${zone.subtitle}'}'
                '${zone.id == selectedZoneId ? l10n.zoneListSelectedSuffix : ''}'
                '${l10n.openZoneDetailSuffix}',
            child: _ZoneDirectoryRow(
              zone: zone,
              selected: zone.id == selectedZoneId,
              kindLabel: _zoneKindText(l10n, zone.kind),
              onTap: () => onOpenDetail(zone),
            ),
          ),
        ],
      ],
    );
  }
}

/// Localized zone-kind label shared by the directory row (mirrors the
/// overview screen's kind chip wording).
String _zoneKindText(AppLocalizations l10n, DemoZoneKind kind) =>
    switch (kind) {
      DemoZoneKind.crop => l10n.zoneKindCrop,
      DemoZoneKind.livestock => l10n.zoneKindLivestock,
      DemoZoneKind.water => l10n.zoneKindWater,
      DemoZoneKind.storage => l10n.zoneKindStorage,
      DemoZoneKind.house => l10n.zoneKindHouse,
    };

const double _previewWidth = 72;
const double _previewHeight = 64;

/// One accessible directory row: a static clay scene thumbnail matching the
/// map tile, wrapped title, optional subtitle, localized kind label and a
/// trailing chevron. Grows vertically so scaled text never clips.
class _ZoneDirectoryRow extends StatelessWidget {
  const _ZoneDirectoryRow({
    required this.zone,
    required this.selected,
    required this.kindLabel,
    required this.onTap,
  });

  final DemoZone zone;
  final bool selected;
  final String kindLabel;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final tokens = FarmThemeExtension.of(context);
    final textTheme = Theme.of(context).textTheme;
    final subtitle = zone.subtitle;
    return Material(
      color: selected ? tokens.brandSage.withValues(alpha: 0.25) : null,
      child: InkWell(
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.symmetric(
            horizontal: FarmSpacing.lg,
            vertical: FarmSpacing.md,
          ),
          child: Row(
            children: [
              // Static thumbnail of the same scene painter used on the map;
              // clipped to bound the skirt/shadow bleed and excluded from
              // semantics (the row label already names the zone).
              ExcludeSemantics(
                child: RepaintBoundary(
                  child: ClipRRect(
                    borderRadius: BorderRadius.circular(
                      FarmSpacing.inputRadius,
                    ),
                    child: Container(
                      width: _previewWidth,
                      height: _previewHeight,
                      color: tokens.surface,
                      child: CustomPaint(
                        painter: IsoZoneTilePainter(
                          kind: zone.kind,
                          selected: false,
                          phase: 0,
                          name: zone.name,
                        ),
                      ),
                    ),
                  ),
                ),
              ),
              const SizedBox(width: FarmSpacing.md),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      zone.name,
                      softWrap: true,
                      style: textTheme.titleMedium,
                    ),
                    if (subtitle != null && subtitle.isNotEmpty)
                      Text(
                        subtitle,
                        softWrap: true,
                        style: textTheme.bodySmall?.copyWith(
                          color: tokens.textSecondary,
                        ),
                      ),
                    const SizedBox(height: FarmSpacing.xs),
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: FarmSpacing.sm,
                        vertical: 3,
                      ),
                      decoration: BoxDecoration(
                        color: tokens.brandSage.withValues(alpha: 0.4),
                        borderRadius: BorderRadius.circular(FarmSpacing.sm),
                      ),
                      child: Text(kindLabel, style: textTheme.labelSmall),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: FarmSpacing.sm),
              const Icon(Icons.chevron_right),
            ],
          ),
        ),
      ),
    );
  }
}
