import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/theme/farmly_spacing.dart';
import '../../core/theme/farmly_theme_extension.dart';
import '../../ui/farm_card.dart';
import '../../ui/farm_scaffold.dart';
import '../../ui/pickers.dart';
import '../../ui/screen_states.dart';
import '../demo/demo_models.dart';
import '../demo/demo_providers.dart';

const _demoAnchorDay = '2026-10-06';

final class _DailyPoint {
  const _DailyPoint({
    required this.dayLabel,
    required this.isoDay,
    required this.kg,
    required this.feedingPercent,
  });

  final String dayLabel;
  final String isoDay;
  final double kg;
  final double feedingPercent;
}

String _isoDay(DateTime day) =>
    '${day.year.toString().padLeft(4, '0')}-'
    '${day.month.toString().padLeft(2, '0')}-'
    '${day.day.toString().padLeft(2, '0')}';

List<_DailyPoint> _buildSeries(DemoDataState state, String? farmId, int days) {
  // Confirmed-effective records only: voided records contribute nothing, and
  // a pending correction keeps counting its original value (spec 04 §5.2).
  final records = harvestsOfFarm(
    state,
    farmId,
  ).where((record) => record.countsTowardTotals);
  final feeding = feedingOfFarm(state, farmId);
  final feedingRatio = feeding.isEmpty
      ? 0.0
      : feeding.fold<int>(0, (sum, entry) => sum + entry.done) /
            feeding.fold<int>(0, (sum, entry) => sum + entry.total);

  final anchor = DateTime.parse(_demoAnchorDay);
  // Records are keyed by their ISO date (`harvestedOn`, e.g. 2026-10-01);
  // each generated day must look itself up by the same ISO key. The 'dd/MM'
  // label below is display-only (spec 02 §5: no silent zero totals).
  final byDay = <String, double>{};
  for (final record in records) {
    byDay.update(
      record.harvestedOn,
      (value) => value + double.parse(record.quantityKg),
      ifAbsent: () => double.parse(record.quantityKg),
    );
  }
  return List.generate(days, (index) {
    final day = anchor.subtract(Duration(days: days - 1 - index));
    final label =
        '${day.day.toString().padLeft(2, '0')}/'
        '${day.month.toString().padLeft(2, '0')}';
    return _DailyPoint(
      dayLabel: label,
      isoDay: _isoDay(day),
      kg: byDay[_isoDay(day)] ?? 0,
      feedingPercent: feedingRatio,
    );
  });
}

/// RFC-4180 escaping plus a leading-apostrophe guard so spreadsheet imports
/// cannot interpret a hostile cell as a formula (spec 02 §5: export safe CSV).
String _csvCell(String value) {
  var escaped = value.replaceAll('"', '""');
  if (escaped.startsWith(RegExp(r'[=+\-@]'))) escaped = "'$escaped";
  return '"$escaped"';
}

String _buildCsv(List<_DailyPoint> series, {required String farmName}) {
  final buffer = StringBuffer()
    ..writeln('${_csvCell('farm')},${_csvCell(farmName)}')
    ..writeln('${_csvCell('ngay')},${_csvCell('thu_hoach_kg')},${_csvCell('cho_an_hoan_tat_pct')}');
  for (final point in series) {
    buffer.writeln(
      '${_csvCell(point.isoDay)},'
      '${point.kg.toStringAsFixed(2)},'
      '${(point.feedingPercent * 100).round()}',
    );
  }
  return buffer.toString();
}

/// Analytics tab: 7d/30d toggle, hand-painted chart with legend + text table
/// so color is never the only encoding (spec 02 §5 Analytics row).
class AnalyticsScreen extends ConsumerStatefulWidget {
  const AnalyticsScreen({super.key});

  @override
  ConsumerState<AnalyticsScreen> createState() => _AnalyticsScreenState();
}

class _AnalyticsScreenState extends ConsumerState<AnalyticsScreen> {
  int _rangeDays = 7;

  @override
  Widget build(BuildContext context) {
    final state = ref.watch(demoDataProvider);
    final farm = farmById(state, state.selectedFarmId);
    final organization = organizationById(state, state.selectedOrganizationId);
    final harvests = harvestsOfFarm(state, farm?.id);
    final animals = animalsOfFarm(state, farm?.id);
    final zones = zonesOfFarm(state, farm?.id);
    final farmIsEmpty = harvests.isEmpty && animals.isEmpty && zones.isEmpty;
    final screenState = effectiveDemoState(
      ref,
      'analytics',
      dataEmpty: farmIsEmpty,
    );

    return FarmScaffold(
      topBar: FarmTopBar(
        title: 'Phân tích',
        subtitle:
            '${organization?.name ?? ''} · ${farm?.name ?? ''} · '
            '$_rangeDays ngày gần nhất',
      ),
      body: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(
              FarmSpacing.lg,
              0,
              FarmSpacing.lg,
              FarmSpacing.sm,
            ),
            child: Row(
              children: [
                const Expanded(child: DemoStateSwitcher(screenKey: 'analytics')),
                const SizedBox(width: FarmSpacing.sm),
                SegmentedButton<int>(
                  segments: const [
                    ButtonSegment(value: 7, label: Text('7 ngày')),
                    ButtonSegment(value: 30, label: Text('30 ngày')),
                  ],
                  selected: {_rangeDays},
                  onSelectionChanged: (selection) =>
                      setState(() => _rangeDays = selection.first),
                  showSelectedIcon: false,
                  // Default M3 segment height is 40dp; §8 requires 48dp touch.
                  style: const ButtonStyle(
                    minimumSize: WidgetStatePropertyAll(
                      Size(0, FarmSpacing.minTouchTarget),
                    ),
                  ),
                ),
              ],
            ),
          ),
          Expanded(
            child: switch (screenState) {
              DemoLoadState.loading => const _AnalyticsSkeleton(),
              DemoLoadState.recoverableError => FarmErrorView(
                onRetry: () => ref
                    .read(demoScreenStateProvider.notifier)
                    .reset('analytics'),
                onSwitchScope: () => showFarmPickerSheet(context),
              ),
              DemoLoadState.permissionDenied => PermissionDeniedView(
                message: 'Bạn không có quyền xem số liệu của nông trại này.',
                onSwitchScope: () => showFarmPickerSheet(context),
              ),
              DemoLoadState.empty => EmptyStateView(
                title: 'Chưa có số liệu trong kỳ',
                message:
                    'Khi có bản ghi thu hoạch và cho ăn, biểu đồ và bảng số '
                    'liệu sẽ xuất hiện ở đây.',
                actionLabel: 'Đổi nông trại khác',
                onAction: () => showFarmPickerSheet(context),
              ),
              DemoLoadState.offline ||
              DemoLoadState.pendingConflict ||
              DemoLoadState.success => _AnalyticsContent(
                state: state,
                farmId: farm?.id,
                farmName: farm?.name ?? '',
                days: _rangeDays,
                offline: screenState == DemoLoadState.offline,
              ),
            },
          ),
        ],
      ),
    );
  }
}

class _AnalyticsContent extends StatelessWidget {
  const _AnalyticsContent({
    required this.state,
    required this.farmId,
    required this.farmName,
    required this.days,
    required this.offline,
  });

  final DemoDataState state;
  final String? farmId;
  final String farmName;
  final int days;
  final bool offline;

  @override
  Widget build(BuildContext context) {
    final tokens = FarmThemeExtension.of(context);
    final series = _buildSeries(state, farmId, days);
    final totalKg = series.fold<double>(0, (sum, point) => sum + point.kg);
    final averageKg = totalKg / days;
    // Axis labels use the smallest type-scale step (12) and honor text
    // scaling instead of a fixed 9px paint (spec 02 §2/§8); the text table
    // below stays the accessible full-data alternative.
    final labelFontSize = MediaQuery.textScalerOf(context).scale(12);

    return ListView(
      padding: const EdgeInsets.fromLTRB(
        FarmSpacing.lg,
        0,
        FarmSpacing.lg,
        FarmSpacing.xxl,
      ),
      children: [
        if (offline) ...[
          const OfflineBanner(asOf: '06:30'),
          const SizedBox(height: FarmSpacing.md),
        ],
        FarmCard(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Thu hoạch $days ngày',
                style: Theme.of(context).textTheme.titleSmall,
              ),
              const SizedBox(height: FarmSpacing.xs),
              Text(
                'Tổng ${totalKg.toStringAsFixed(1)} kg · trung bình '
                '${averageKg.toStringAsFixed(1)} kg/ngày',
                style: Theme.of(context).textTheme.bodySmall?.copyWith(
                  color: tokens.textSecondary,
                ),
                softWrap: true,
              ),
              const SizedBox(height: FarmSpacing.md),
              Semantics(
                container: true,
                label:
                    'Biểu đồ cột thu hoạch $days ngày. '
                    'Tổng ${totalKg.toStringAsFixed(1)} kilô gam; bảng số liệu '
                    'chi tiết nằm bên dưới.',
                child: SizedBox(
                  height: 180,
                  width: double.infinity,
                  child: CustomPaint(
                    painter: _HarvestChartPainter(
                      series: series,
                      barColor: tokens.brandAction,
                      patternColor: tokens.semanticWarning,
                      gridColor: tokens.divider,
                      labelColor: tokens.textSecondary,
                      labelFontSize: labelFontSize,
                    ),
                  ),
                ),
              ),
              const SizedBox(height: FarmSpacing.sm),
              Row(
                children: [
                  _LegendSwatch(color: tokens.brandAction, hatched: false),
                  const SizedBox(width: FarmSpacing.xs),
                  const Expanded(child: Text('Thu hoạch (kg)')),
                  _LegendSwatch(color: tokens.semanticWarning, hatched: true),
                  const SizedBox(width: FarmSpacing.xs),
                  const Expanded(child: Text('Cho ăn hoàn tất (%)')),
                ],
              ),
            ],
          ),
        ),
        const SizedBox(height: FarmSpacing.md),
        FarmCard(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Expanded(
                    child: Text(
                      'Bảng số liệu',
                      style: Theme.of(context).textTheme.titleSmall,
                    ),
                  ),
                  TextButton.icon(
                    onPressed: () => _showCsvExportSheet(
                      context,
                      csv: _buildCsv(series, farmName: farmName),
                    ),
                    icon: const Icon(Icons.download_outlined, size: 18),
                    label: const Text('Xuất CSV'),
                  ),
                ],
              ),
              const SizedBox(height: FarmSpacing.sm),
              SizedBox(
                height: 220,
                child: SingleChildScrollView(
                  child: Table(
                    columnWidths: const {
                      0: FlexColumnWidth(1),
                      1: FlexColumnWidth(1),
                      2: FlexColumnWidth(1),
                    },
                    defaultVerticalAlignment: TableCellVerticalAlignment.middle,
                    children: [
                      TableRow(
                        decoration: BoxDecoration(
                          border: Border(
                            bottom: BorderSide(color: tokens.divider),
                          ),
                        ),
                        children: [
                          _tableCell(context, 'Ngày', header: true),
                          _tableCell(context, 'Thu hoạch (kg)', header: true),
                          _tableCell(context, 'Cho ăn (%)', header: true),
                        ],
                      ),
                      for (final point in series)
                        TableRow(
                          decoration: BoxDecoration(
                            border: Border(
                              bottom: BorderSide(color: tokens.divider),
                            ),
                          ),
                          children: [
                            _tableCell(context, point.dayLabel),
                            _tableCell(context, point.kg.toStringAsFixed(2)),
                            _tableCell(
                              context,
                              '${(point.feedingPercent * 100).round()}%',
                            ),
                          ],
                        ),
                    ],
                  ),
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _tableCell(BuildContext context, String text, {bool header = false}) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: FarmSpacing.xs),
      child: Text(
        text,
        style: header
            ? Theme.of(context).textTheme.labelLarge
            : Theme.of(context).textTheme.bodySmall,
        softWrap: true,
      ),
    );
  }
}

/// Demo export surface: the same rows the chart/table render, as CSV the user
/// can inspect and copy out. Production wiring shares/saves the file; no
/// silent file-system write happens here (spec 02 §5: accessible export).
void _showCsvExportSheet(BuildContext context, {required String csv}) {
  showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    showDragHandle: true,
    builder: (sheetContext) => Padding(
      padding: EdgeInsets.fromLTRB(
        FarmSpacing.lg,
        0,
        FarmSpacing.lg,
        FarmSpacing.lg + MediaQuery.viewInsetsOf(sheetContext).bottom,
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
            'Xuất CSV',
            style: Theme.of(sheetContext).textTheme.titleMedium,
          ),
          const SizedBox(height: FarmSpacing.xs),
          Text(
            'Dữ liệu đúng như bảng số liệu — ngày ISO, đơn vị kg.',
            style: Theme.of(sheetContext).textTheme.bodySmall,
          ),
          const SizedBox(height: FarmSpacing.md),
          ConstrainedBox(
            constraints: const BoxConstraints(maxHeight: 260),
            child: DecoratedBox(
              decoration: BoxDecoration(
                border: Border.all(
                  color: FarmThemeExtension.of(sheetContext).divider,
                ),
                borderRadius: BorderRadius.circular(FarmSpacing.cardRadius),
              ),
              child: SingleChildScrollView(
                padding: const EdgeInsets.all(FarmSpacing.sm),
                child: SelectableText(
                  csv,
                  style: Theme.of(sheetContext)
                      .textTheme
                      .bodySmall
                      ?.copyWith(fontFamily: 'monospace'),
                ),
              ),
            ),
          ),
          const SizedBox(height: FarmSpacing.md),
          FilledButton.icon(
            onPressed: () async {
              await Clipboard.setData(ClipboardData(text: csv));
              if (sheetContext.mounted) {
                Navigator.of(sheetContext).pop();
                showFarmToast(context, 'Đã sao chép CSV.');
              }
            },
            icon: const Icon(Icons.copy_outlined),
            label: const Text('Sao chép CSV'),
          ),
        ],
      ),
    ),
  );
}

class _LegendSwatch extends StatelessWidget {
  const _LegendSwatch({required this.color, required this.hatched});

  final Color color;
  final bool hatched;

  @override
  Widget build(BuildContext context) {
    return ExcludeSemantics(
      child: SizedBox.square(
        dimension: 14,
        child: CustomPaint(
          painter: _LegendPainter(color: color, hatched: hatched),
        ),
      ),
    );
  }
}

class _LegendPainter extends CustomPainter {
  _LegendPainter({required this.color, required this.hatched});

  final Color color;
  final bool hatched;

  @override
  void paint(Canvas canvas, Size size) {
    final rect = Offset.zero & size;
    final fill = Paint()..color = color;
    if (!hatched) {
      canvas.drawRect(rect, fill);
      return;
    }
    canvas.drawRect(
      rect,
      Paint()
        ..color = color.withValues(alpha: 0.25),
    );
    final line = Paint()
      ..color = color
      ..strokeWidth = 2;
    for (var x = -size.height; x < size.width + size.height; x += 5) {
      canvas.drawLine(
        Offset(x.toDouble(), size.height),
        Offset(x + size.height, 0),
        line,
      );
    }
  }

  @override
  bool shouldRepaint(_LegendPainter oldDelegate) =>
      oldDelegate.color != color || oldDelegate.hatched != hatched;
}

class _HarvestChartPainter extends CustomPainter {
  _HarvestChartPainter({
    required this.series,
    required this.barColor,
    required this.patternColor,
    required this.gridColor,
    required this.labelColor,
    required this.labelFontSize,
  });

  final List<_DailyPoint> series;
  final Color barColor;
  final Color patternColor;
  final Color gridColor;
  final Color labelColor;

  /// Scaled 12 (type-scale minimum) from the text scaler, not a fixed px.
  final double labelFontSize;

  @override
  void paint(Canvas canvas, Size size) {
    if (series.isEmpty) return;
    final bottomReserve = labelFontSize * 1.5 + 12;
    final chartRect = Rect.fromLTWH(
      8,
      8,
      size.width - 16,
      (size.height - 8 - bottomReserve).clamp(40.0, size.height),
    );
    final maxKg = series.fold<double>(
      0.001,
      (max, point) => point.kg > max ? point.kg : max,
    );

    final grid = Paint()
      ..color = gridColor
      ..strokeWidth = 1;
    for (var i = 0; i <= 3; i++) {
      final y = chartRect.top + chartRect.height * i / 3;
      canvas.drawLine(
        Offset(chartRect.left, y),
        Offset(chartRect.right, y),
        grid,
      );
    }

    final slot = chartRect.width / series.length;
    final barWidth = (slot * 0.55).clamp(3.0, 26.0);
    final labelPaint = TextPainter()
      ..textDirection = TextDirection.ltr;

    // Measure one label at the scaled size, then pick a stride that gives
    // every drawn label enough horizontal room instead of clipping it.
    labelPaint.text = TextSpan(
      text: series.first.dayLabel,
      style: TextStyle(color: labelColor, fontSize: labelFontSize),
    );
    labelPaint.layout();
    var labelStride = (labelPaint.width / slot).ceil();
    if (labelStride < 1) labelStride = 1;
    if (labelStride > series.length) labelStride = series.length;

    for (var i = 0; i < series.length; i++) {
      final point = series[i];
      final centerX = chartRect.left + slot * (i + 0.5);

      // Feeding completion: hatched background bar (pattern, not color-only).
      final feedHeight = chartRect.height * point.feedingPercent;
      if (feedHeight > 0) {
        final feedRect = Rect.fromLTWH(
          centerX - barWidth / 2,
          chartRect.bottom - feedHeight,
          barWidth,
          feedHeight,
        );
        canvas.drawRect(
          feedRect,
          Paint()..color = patternColor.withValues(alpha: 0.18),
        );
        final hatch = Paint()
          ..color = patternColor.withValues(alpha: 0.5)
          ..strokeWidth = 1.5;
        for (
          var x = feedRect.left - feedRect.height;
          x < feedRect.right;
          x += 5
        ) {
          canvas.drawLine(
            Offset(x, feedRect.bottom),
            Offset(x + feedRect.height, feedRect.top),
            hatch,
          );
        }
      }

      // Harvest kg: solid bar.
      final barHeight = chartRect.height * (point.kg / maxKg);
      if (barHeight > 0) {
        canvas.drawRRect(
          RRect.fromRectAndRadius(
            Rect.fromLTWH(
              centerX - barWidth / 2,
              chartRect.bottom - barHeight,
              barWidth,
              barHeight,
            ),
            const Radius.circular(3),
          ),
          Paint()..color = barColor,
        );
      }

      if (i % labelStride == 0) {
        labelPaint.text = TextSpan(
          text: point.dayLabel,
          style: TextStyle(color: labelColor, fontSize: labelFontSize),
        );
        labelPaint.layout(maxWidth: slot * labelStride);
        labelPaint.paint(
          canvas,
          Offset(
            centerX - labelPaint.width / 2,
            chartRect.bottom + 4,
          ),
        );
      }
    }
  }

  @override
  bool shouldRepaint(_HarvestChartPainter oldDelegate) =>
      oldDelegate.series != series ||
      oldDelegate.barColor != barColor ||
      oldDelegate.patternColor != patternColor ||
      oldDelegate.labelFontSize != labelFontSize;
}

class _AnalyticsSkeleton extends StatelessWidget {
  const _AnalyticsSkeleton();

  @override
  Widget build(BuildContext context) {
    return ListView(
      padding: const EdgeInsets.fromLTRB(
        FarmSpacing.lg,
        0,
        FarmSpacing.lg,
        FarmSpacing.xxl,
      ),
      children: const [
        SkeletonSurface(
          width: double.infinity,
          height: 240,
          radius: FarmSpacing.cardRadius,
        ),
        SizedBox(height: FarmSpacing.md),
        SkeletonSurface(
          width: double.infinity,
          height: 220,
          radius: FarmSpacing.cardRadius,
        ),
      ],
    );
  }
}
