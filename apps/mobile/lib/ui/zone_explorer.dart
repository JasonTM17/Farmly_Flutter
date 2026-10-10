import 'dart:math' as math;

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
      duration: context.farmCameraFlightDuration(),
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

  /// Plot tiles are chunky rounded squares (~42% of map width) on a loose
  /// two-column grid — the reference map's board-game layout.
  static double _tileW(Size canvas) => canvas.width * 0.42;
  static double _tileH(Size canvas) => _tileW(canvas) * 0.72;

  /// Painter order, back row first so nearer plots overdraw correctly.
  List<DemoZone> get _ordered => widget.zones.toList()
    ..sort((a, b) => (a.x + a.y).compareTo(b.x + b.y));

  int _cellIndex(DemoZone zone) =>
      _ordered.indexWhere((z) => z.id == zone.id);

  /// Grid cell center with a small per-zone jitter so the grid reads organic
  /// rather than rigid.
  Offset _tileCenter(DemoZone zone, int index, Size canvas) {
    final col = index % 2;
    final row = index ~/ 2;
    final jx = (zone.x - 0.5) * canvas.width * 0.05;
    final jy = (zone.y - 0.5) * canvas.height * 0.05;
    return Offset(
      canvas.width * (0.28 + col * 0.44) + jx,
      canvas.height * (0.3 + row * 0.48) + jy,
    );
  }

  void _focusZone(DemoZone zone) {
    final viewport = _viewerKey.currentContext?.size;
    if (viewport == null) return;
    // Deep, slow flight into the tapped plot — the reference's signature
    // "camera dives into the tile" feel.
    const scale = 2.4;
    final center = _tileCenter(zone, _cellIndex(zone), viewport);
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
                      for (final (tileIndex, zone) in _ordered.indexed)
                        () {
                          final center = _tileCenter(zone, tileIndex, canvas);
                          final selected =
                              zone.id == widget.selectedZoneId;
                          final tw = _tileW(canvas);
                          final th = _tileH(canvas);
                          return Positioned(
                            left: center.dx - tw / 2,
                            top: center.dy - th / 2 - 26 - (selected ? 6 : 0),
                            width: tw,
                            height: th + 26,
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
                                  pop: true,
                                  delay: Duration(
                                    milliseconds: 90 * tileIndex,
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
                                        width: tw,
                                        height: th,
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

  /// Ambient phase 0..1 — pond ripples expand, pasture animals bob.
  final double phase;

  @override
  void paint(Canvas canvas, Size size) {
    final w = size.width;
    final h = size.height - 8;
    final tile = RRect.fromRectAndRadius(
      Rect.fromLTWH(0, 0, w, h),
      const Radius.circular(16),
    );

    // Soft ground shadow under the plot.
    canvas.drawRRect(
      tile.shift(const Offset(0, 7)),
      Paint()
        ..color = FarmlyColors.textPrimary.withValues(alpha: 0.14)
        ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 7),
    );

    final base = _baseColor();
    canvas.drawRRect(tile, Paint()..color = base);

    canvas.save();
    canvas.clipRRect(tile);
    _paintInterior(canvas, w, h);
    canvas.restore();

    canvas.drawRRect(
      tile,
      Paint()
        ..color = selected
            ? FarmlyColors.brandAction
            : Color.lerp(base, FarmlyColors.textPrimary, 0.28)!
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
      FarmlyColors.brandSage,
      FarmlyColors.surface,
      0.45,
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
        // Furrows + tidy rows of plant dots, like the reference field plots.
        final furrow = Paint()
          ..color = Color.lerp(
            FarmlyColors.semanticWarning,
            FarmlyColors.textPrimary,
            0.3,
          )!
          ..strokeWidth = 3
          ..strokeCap = StrokeCap.round;
        final plant = Paint()..color = FarmlyColors.brandAction;
        final plantCore = Paint()
          ..color = Color.lerp(
            FarmlyColors.brandAction,
            FarmlyColors.surface,
            0.35,
          )!;
        for (var r = 0; r < 4; r++) {
          final y = h * (0.24 + r * 0.18);
          canvas.drawLine(Offset(w * 0.09, y), Offset(w * 0.91, y), furrow);
          for (var i = 0; i < 6; i++) {
            final px = w * (0.13 + i * 0.148);
            canvas.drawCircle(Offset(px, y - 5), 4.6, plant);
            canvas.drawCircle(Offset(px, y - 5), 2.1, plantCore);
          }
        }
      case DemoZoneKind.livestock:
        // Pasture: fence rails + posts, grazing animals bobbing gently.
        final fence = Paint()
          ..color = Color.lerp(
            FarmlyColors.semanticWarning,
            FarmlyColors.surface,
            0.25,
          )!
          ..strokeWidth = 2.6
          ..strokeCap = StrokeCap.round;
        canvas.drawLine(
          Offset(w * 0.07, h * 0.66),
          Offset(w * 0.93, h * 0.66),
          fence,
        );
        canvas.drawLine(
          Offset(w * 0.07, h * 0.78),
          Offset(w * 0.93, h * 0.78),
          fence,
        );
        for (var i = 0; i < 4; i++) {
          final x = w * (0.16 + i * 0.23);
          canvas.drawLine(Offset(x, h * 0.6), Offset(x, h * 0.86), fence);
        }
        final body = Paint()..color = FarmlyColors.surface;
        final edge = Paint()
          ..color = FarmlyColors.textSecondary
          ..style = PaintingStyle.stroke
          ..strokeWidth = 1.4;
        for (var i = 0; i < 3; i++) {
          final bob =
              math.sin(phase * 2 * math.pi + i * 2.1) * 2.4;
          final p = Offset(
            w * (0.24 + i * 0.26),
            h * (0.3 + (i.isOdd ? 0.14 : 0)) + bob,
          );
          canvas.drawOval(
            Rect.fromCenter(center: p, width: 22, height: 13),
            body,
          );
          canvas.drawOval(
            Rect.fromCenter(center: p, width: 22, height: 13),
            edge,
          );
          canvas.drawCircle(p + const Offset(10, -4), 4.6, body);
          canvas.drawCircle(p + const Offset(10, -4), 4.6, edge);
        }
      case DemoZoneKind.water:
        // Main round tank + satellite pond; rings expand with the phase.
        final water = Paint()..color = FarmlyColors.illustrationWater;
        canvas.drawCircle(Offset(w * 0.36, h * 0.42), h * 0.27, water);
        canvas.drawCircle(Offset(w * 0.75, h * 0.62), h * 0.15, water);
        for (var r = 0; r < 3; r++) {
          final cycle = (phase + r / 3) % 1.0;
          canvas.drawCircle(
            Offset(w * 0.36, h * 0.42),
            h * 0.27 * (0.4 + cycle * 0.55),
            Paint()
              ..color = FarmlyColors.surface.withValues(
                alpha: 0.75 * (1 - cycle),
              )
              ..style = PaintingStyle.stroke
              ..strokeWidth = 2,
          );
        }
        final lily = Paint()..color = FarmlyColors.brandAction;
        canvas.drawCircle(Offset(w * 0.71, h * 0.57), 3.6, lily);
        canvas.drawCircle(Offset(w * 0.79, h * 0.66), 3, lily);
      case DemoZoneKind.house:
        _paintBuilding(canvas, w, h, FarmlyColors.illustrationBarn);
      case DemoZoneKind.storage:
        _paintBuilding(canvas, w, h, FarmlyColors.textSecondary);
    }
  }

  void _paintBuilding(Canvas canvas, double w, double h, Color wall) {
    final cx = w / 2;
    final cy = h * 0.52;
    canvas.drawRect(
      Rect.fromLTWH(cx - w * 0.16, cy - h * 0.06, w * 0.32, h * 0.3),
      Paint()..color = wall,
    );
    final roof = Path()
      ..moveTo(cx - w * 0.2, cy - h * 0.06)
      ..lineTo(cx, cy - h * 0.26)
      ..lineTo(cx + w * 0.2, cy - h * 0.06)
      ..close();
    canvas.drawPath(roof, Paint()..color = FarmlyColors.surface);
    canvas.drawRect(
      Rect.fromLTWH(cx - w * 0.05, cy + h * 0.1, w * 0.1, h * 0.14),
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
