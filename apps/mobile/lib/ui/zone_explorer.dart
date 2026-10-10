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
    final h = size.height;

    // Raised platform: a darker skirt under the rounded top face gives each
    // plot its extruded 3D block look (reference map tiles float above the
    // grass). ~9% of the tile height reads as the side wall.
    final depth = h * 0.09;
    final faceH = h - depth - 6; // 6px reserved for the soft shadow bleed.
    const radius = Radius.circular(16);
    final face = RRect.fromRectAndRadius(
      Rect.fromLTWH(0, 0, w, faceH),
      radius,
    );
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
      Paint()
        ..color = Color.lerp(base, FarmlyColors.textPrimary, 0.42)!,
    );
    canvas.drawRRect(face, Paint()..color = base);

    canvas.save();
    canvas.clipRRect(face);
    _paintInterior(canvas, w, faceH);
    canvas.restore();

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
        // Furrowed soil with spherical plants; rows compress toward the top
        // of the face so the plot reads as receding in perspective.
        final furrow = Paint()
          ..color = Color.lerp(
            FarmlyColors.semanticWarning,
            FarmlyColors.textPrimary,
            0.34,
          )!
          ..strokeCap = StrokeCap.round;
        for (var r = 0; r < 4; r++) {
          final t = r / 3; // 0 = far (top), 1 = near (bottom)
          final y = h * (0.2 + r * 0.19);
          final inset = w * (0.16 - t * 0.07);
          final pr = 3.4 + t * 1.8;
          furrow.strokeWidth = 2.2 + t * 1.2;
          canvas.drawLine(
            Offset(inset, y),
            Offset(w - inset, y),
            furrow,
          );
          for (var i = 0; i < 6; i++) {
            final px = inset + (w - inset * 2) * (i + 0.5) / 6;
            _sphere(
              canvas,
              Offset(px, y - 4 - t * 2),
              pr,
              FarmlyColors.brandAction,
            );
          }
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
        for (var i = 0; i < 3; i++) {
          final bob = math.sin(phase * 2 * math.pi + i * 2.1) * 2.4;
          final p = Offset(
            w * (0.24 + i * 0.26),
            h * (0.32 + (i.isOdd ? 0.12 : 0)) + bob,
          );
          canvas.drawOval(
            Rect.fromCenter(center: p, width: 24, height: 14),
            Paint()..color = FarmlyColors.surface,
          );
          canvas.drawOval(
            Rect.fromCenter(center: p, width: 24, height: 14),
            Paint()
              ..color = FarmlyColors.textSecondary
              ..style = PaintingStyle.stroke
              ..strokeWidth = 1.3,
          );
          _sphere(
            canvas,
            p + const Offset(11, -5),
            5.2,
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
        final water = Paint()..color = FarmlyColors.illustrationWater;
        final waterEdge = Paint()
          ..color = Color.lerp(
            FarmlyColors.illustrationWater,
            FarmlyColors.textPrimary,
            0.3,
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
      case DemoZoneKind.house:
        _paintBuilding(canvas, w, h, FarmlyColors.illustrationBarn);
      case DemoZoneKind.storage:
        _paintBuilding(canvas, w, h, FarmlyColors.textSecondary);
    }
  }

  void _paintBuilding(Canvas canvas, double w, double h, Color wall) {
    final cx = w / 2;
    final cy = h * 0.5;
    // Darker right strip = 3D block rather than a flat rectangle.
    canvas.drawRect(
      Rect.fromLTWH(cx - w * 0.16, cy - h * 0.04, w * 0.32, h * 0.3),
      Paint()..color = wall,
    );
    canvas.drawRect(
      Rect.fromLTWH(cx + w * 0.08, cy - h * 0.04, w * 0.08, h * 0.3),
      Paint()..color = Color.lerp(wall, FarmlyColors.textPrimary, 0.35)!,
    );
    final roof = Path()
      ..moveTo(cx - w * 0.2, cy - h * 0.04)
      ..lineTo(cx, cy - h * 0.26)
      ..lineTo(cx + w * 0.2, cy - h * 0.04)
      ..close();
    canvas.drawPath(roof, Paint()..color = FarmlyColors.surface);
    canvas.drawRect(
      Rect.fromLTWH(cx - w * 0.05, cy + h * 0.12, w * 0.1, h * 0.14),
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
