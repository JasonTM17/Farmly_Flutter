import 'package:flutter/material.dart';

import '../core/theme/farmly_colors.dart';
import '../core/theme/farmly_spacing.dart';
import '../core/theme/farmly_theme_extension.dart';
import '../features/demo/demo_models.dart';
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
    super.key,
  });

  final List<DemoZone> zones;
  final String? selectedZoneId;
  final ValueChanged<String> onSelect;
  final ValueChanged<DemoZone> onOpenDetail;

  @override
  State<ZoneScene> createState() => _ZoneSceneState();
}

class _ZoneSceneState extends State<ZoneScene> with TickerProviderStateMixin {
  final TransformationController _transform = TransformationController();
  final GlobalKey _viewerKey = GlobalKey();
  AnimationController? _zoomController;
  Animation<Matrix4>? _zoomAnimation;

  @override
  void didUpdateWidget(ZoneScene oldWidget) {
    super.didUpdateWidget(oldWidget);
    // Switching to the Overview chip clears the selection — drop the zoom
    // back to the whole-map view so the gesture mirrors the reference.
    if (widget.selectedZoneId == null && oldWidget.selectedZoneId != null) {
      _resetView();
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
    _zoomAnimation?.removeListener(_onZoomTick);
    _zoomController?.dispose();
    final controller = AnimationController(
      vsync: this,
      duration: context.farmZoneZoomDuration(),
    );
    _zoomController = controller;
    final animation = Matrix4Tween(
      begin: _transform.value,
      end: target,
    ).animate(CurvedAnimation(parent: controller, curve: Curves.easeOutCubic));
    _zoomAnimation = animation..addListener(_onZoomTick);
    controller.forward();
  }

  void _resetView() => _animateTo(Matrix4.identity());

  /// Tile footprint in logical px — the isometric diamond is 2:1.
  static const double _tileW = 132;
  static const double _tileH = 66;
  static const double _tileDepth = 10;

  /// Zone.x/y (0..1) are treated as normalized grid coordinates and projected
  /// to isometric screen space. Returns the tile's top-face center offset.
  Offset _isoCenter(DemoZone zone, Size canvas) {
    final gx = zone.x * 2;
    final gy = zone.y * 2;
    final px = (gx - gy) * _tileW * 0.88;
    final py = (gx + gy) * _tileH * 0.72;
    return Offset(canvas.width / 2 + px, canvas.height * 0.26 + py);
  }

  void _focusZone(DemoZone zone) {
    final viewport = _viewerKey.currentContext?.size;
    if (viewport == null) return;
    const scale = 1.9;
    final center = _isoCenter(zone, viewport);
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
    return Stack(
      children: [
        ClipRRect(
          borderRadius: BorderRadius.circular(tokens.cardRadius),
          child: InteractiveViewer(
            key: _viewerKey,
            transformationController: _transform,
            maxScale: 3,
            minScale: 1,
            panEnabled: true,
            child: SizedBox(
              width: double.infinity,
              height: 320,
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
                      const Positioned.fill(
                        child: CustomPaint(painter: _IsoGroundPainter()),
                      ),
                      // Painter order: iso rows back-to-front so nearer
                      // tiles overdraw further ones correctly.
                      for (final (tileIndex, zone) in (widget.zones.toList()
                            ..sort((a, b) => (a.x + a.y).compareTo(b.x + b.y)))
                          .indexed)
                        () {
                          final center = _isoCenter(zone, canvas);
                          final selected =
                              zone.id == widget.selectedZoneId;
                          return Positioned(
                            left: center.dx - _tileW / 2,
                            top:
                                center.dy -
                                _tileH / 2 -
                                _tileDepth -
                                (selected ? 8 : 0),
                            width: _tileW,
                            height: _tileH + _tileDepth + 30,
                            child: Semantics(
                              button: true,
                              selected: selected,
                              label:
                                  'Vùng ${zone.name}. Chạm để chọn, nhấn đôi để mở chi tiết.',
                              excludeSemantics: true,
                              child: GestureDetector(
                                behavior: HitTestBehavior.translucent,
                                onTap: () {
                                  widget.onSelect(zone.id);
                                  _focusZone(zone);
                                },
                                onDoubleTap: () =>
                                    widget.onOpenDetail(zone),
                                child: FarmEntrance(
                                  delay: Duration(
                                    milliseconds: 70 * tileIndex,
                                  ),
                                  child: Column(
                                    mainAxisSize: MainAxisSize.min,
                                    children: [
                                      _ZoneLabelChip(
                                        name: zone.name,
                                        selected: selected,
                                      ),
                                      const SizedBox(height: 2),
                                      SizedBox(
                                        width: _tileW,
                                        height: _tileH + _tileDepth,
                                        child: CustomPaint(
                                          painter: IsoZoneTilePainter(
                                            kind: zone.kind,
                                            selected: selected,
                                            phase: phase,
                                          ),
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                              ),
                            ),
                          );
                        }(),
                      ],
                    ),
                  );
                },
              ),
            ),
          ),
        ),
        Positioned(
          right: FarmSpacing.sm,
          bottom: FarmSpacing.sm,
          child: Semantics(
            button: true,
            label: 'Đặt lại khung nhìn bản đồ vùng',
            child: Material(
              color: tokens.surface,
              shape: const CircleBorder(
                side: BorderSide(color: FarmlyColors.divider),
              ),
              child: IconButton(
                tooltip: 'Đặt lại khung nhìn',
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
  const _IsoGroundPainter();

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
      )!.withValues(alpha: 0.25)
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
  }

  @override
  bool shouldRepaint(_IsoGroundPainter oldDelegate) => false;
}

/// Pill label above each tile, like the reference zone tags.
class _ZoneLabelChip extends StatelessWidget {
  const _ZoneLabelChip({required this.name, required this.selected});

  final String name;
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
  });

  final DemoZoneKind kind;
  final bool selected;

  /// Ambient phase 0..1 — currently drives the pond ripple cycle.
  final double phase;

  static Path _diamond(double w, double h) => Path()
    ..moveTo(w / 2, 0)
    ..lineTo(w, h / 2)
    ..lineTo(w / 2, h)
    ..lineTo(0, h / 2)
    ..close();

  @override
  void paint(Canvas canvas, Size size) {
    final w = size.width;
    final h = size.height - _ZoneSceneState._tileDepth;
    final depth = _ZoneSceneState._tileDepth;

    final top = _diamond(w, h);
    final leftWall = Path()
      ..moveTo(0, h / 2)
      ..lineTo(w / 2, h)
      ..lineTo(w / 2, h + depth)
      ..lineTo(0, h / 2 + depth)
      ..close();
    final rightWall = Path()
      ..moveTo(w, h / 2)
      ..lineTo(w / 2, h)
      ..lineTo(w / 2, h + depth)
      ..lineTo(w, h / 2 + depth)
      ..close();

    final base = _baseColor();
    canvas.drawPath(
      leftWall,
      Paint()..color = Color.lerp(base, FarmlyColors.textPrimary, 0.3)!,
    );
    canvas.drawPath(
      rightWall,
      Paint()..color = Color.lerp(base, FarmlyColors.textPrimary, 0.45)!,
    );
    canvas.drawPath(top, Paint()..color = base);

    canvas.save();
    canvas.clipPath(top);
    _paintInterior(canvas, w, h);
    canvas.restore();

    // Rim — the selected tile gets a thicker action-colored edge.
    canvas.drawPath(
      top,
      Paint()
        ..color = selected
            ? FarmlyColors.brandAction
            : Color.lerp(base, FarmlyColors.textPrimary, 0.25)!
        ..style = PaintingStyle.stroke
        ..strokeWidth = selected ? 3 : 1.5,
    );
  }

  Color _baseColor() => switch (kind) {
    DemoZoneKind.crop => Color.lerp(
      FarmlyColors.semanticWarning,
      FarmlyColors.background,
      0.55,
    )!,
    DemoZoneKind.livestock => Color.lerp(
      FarmlyColors.brandSage,
      FarmlyColors.surface,
      0.25,
    )!,
    DemoZoneKind.water => Color.lerp(
      FarmlyColors.illustrationWater,
      FarmlyColors.surface,
      0.3,
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
        // Ploughed rows of small plant dots, like the reference field tiles.
        final rowPaint = Paint()
          ..color = Color.lerp(
            FarmlyColors.semanticWarning,
            FarmlyColors.textPrimary,
            0.3,
          )!
          ..strokeWidth = 2
          ..strokeCap = StrokeCap.round;
        final plant = Paint()..color = FarmlyColors.brandAction;
        for (var r = 0; r < 3; r++) {
          final y = h * (0.3 + r * 0.2);
          final inset = (h / 2 - (y - h / 2).abs()) / (h / 2);
          final x0 = w / 2 - (w / 2) * inset * 0.72;
          final x1 = w / 2 + (w / 2) * inset * 0.72;
          canvas.drawLine(Offset(x0, y), Offset(x1, y), rowPaint);
          for (var i = 0; i < 4; i++) {
            final px = x0 + (x1 - x0) * (i + 0.5) / 4;
            canvas.drawCircle(Offset(px, y - 3), 3.2, plant);
          }
        }
      case DemoZoneKind.livestock:
        // Pasture with a fence rail and grazing dots.
        final fence = Paint()
          ..color = Color.lerp(
            FarmlyColors.semanticWarning,
            FarmlyColors.surface,
            0.2,
          )!
          ..strokeWidth = 2.4
          ..strokeCap = StrokeCap.round;
        canvas.drawLine(Offset(w * 0.24, h * 0.62), Offset(w * 0.76, h * 0.62), fence);
        canvas.drawLine(Offset(w * 0.3, h * 0.7), Offset(w * 0.7, h * 0.7), fence);
        final grazer = Paint()..color = FarmlyColors.surface;
        final grazerEdge = Paint()
          ..color = FarmlyColors.textSecondary
          ..style = PaintingStyle.stroke
          ..strokeWidth = 1.2;
        for (final p in [
          Offset(w * 0.34, h * 0.4),
          Offset(w * 0.58, h * 0.46),
        ]) {
          canvas.drawOval(
            Rect.fromCenter(center: p, width: 16, height: 9),
            grazer,
          );
          canvas.drawOval(
            Rect.fromCenter(center: p, width: 16, height: 9),
            grazerEdge,
          );
        }
      case DemoZoneKind.water:
        // Pond highlight + expanding ripple rings. At phase 0 the ring layout
        // matches the static golden exactly (first ring at full width).
        for (var r = 0; r < 3; r++) {
          final cycle = (phase + r / 3) % 1.0;
          final ripple = Paint()
            ..color = FarmlyColors.surface.withValues(
              alpha: 0.7 * (1 - cycle),
            )
            ..strokeWidth = 1.6
            ..strokeCap = StrokeCap.round;
          final y = h * (0.42 + r * 0.14);
          final spread = 0.3 + cycle * 0.25;
          canvas.drawArc(
            Rect.fromCenter(
              center: Offset(w / 2, y),
              width: w * spread,
              height: h * 0.18 * (0.7 + cycle * 0.4),
            ),
            3.4,
            2.6,
            false,
            ripple,
          );
        }
      case DemoZoneKind.house:
        _paintTinyBuilding(canvas, w, h, FarmlyColors.illustrationBarn);
      case DemoZoneKind.storage:
        _paintTinyBuilding(canvas, w, h, FarmlyColors.textSecondary);
    }
  }

  void _paintTinyBuilding(Canvas canvas, double w, double h, Color wall) {
    final cx = w / 2;
    final cy = h * 0.48;
    canvas.drawRect(
      Rect.fromLTWH(cx - w * 0.14, cy - h * 0.1, w * 0.28, h * 0.3),
      Paint()..color = wall,
    );
    final roof = Path()
      ..moveTo(cx - w * 0.18, cy - h * 0.1)
      ..lineTo(cx, cy - h * 0.28)
      ..lineTo(cx + w * 0.18, cy - h * 0.1)
      ..close();
    canvas.drawPath(roof, Paint()..color = FarmlyColors.surface);
    canvas.drawRect(
      Rect.fromLTWH(cx - w * 0.04, cy + h * 0.04, w * 0.08, h * 0.16),
      Paint()..color = FarmlyColors.surface,
    );
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
    return Column(
      children: zones
          .map(
            (zone) => Semantics(
              button: true,
              label:
                  'Vùng ${zone.name}${zone.subtitle == null ? '' : ', ${zone.subtitle}'}'
                  '${zone.id == selectedZoneId ? ', đang chọn' : ''}. Mở chi tiết vùng.',
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
