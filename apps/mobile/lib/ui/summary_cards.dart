import 'package:flutter/material.dart';

import '../core/theme/farmly_spacing.dart';
import '../core/theme/farmly_theme_extension.dart';
import '../l10n/generated/app_localizations.dart';
import 'farm_card.dart';

/// Farm operations health ring. A null value renders the explicit "unknown"
/// state instead of inventing a score (spec 02 §5).
class OperationsHealthRing extends StatelessWidget {
  const OperationsHealthRing({required this.value, super.key});

  /// 0..1 progress, or null when unknown.
  final double? value;

  @override
  Widget build(BuildContext context) {
    final tokens = FarmThemeExtension.of(context);
    final l10n = AppLocalizations.of(context);
    final known = value != null;
    final percentText = known ? '${(value! * 100).round()}%' : l10n.unknown;
    final semantics =
        '${l10n.operationalHealth}: $percentText. '
        '${known ? l10n.operationalHealthEstimate : l10n.operationalHealthUnknown}';

    return Semantics(
      container: true,
      label: semantics,
      child: FarmCard(
        // Reference layout: title + status copy on the left, ring on the
        // right — the card lives in a half-width row next to weather.
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    l10n.operationalHealth,
                    style: Theme.of(context).textTheme.titleSmall,
                    softWrap: true,
                  ),
                  const SizedBox(height: FarmSpacing.xs),
                  Text(
                    known
                        ? l10n.operationalHealthEstimate
                        : l10n.operationalHealthUnknown,
                    style: Theme.of(context).textTheme.bodySmall?.copyWith(
                      color: tokens.textSecondary,
                    ),
                    softWrap: true,
                  ),
                ],
              ),
            ),
            const SizedBox(width: FarmSpacing.md),
            SizedBox.square(
              dimension: 72,
              child: CustomPaint(
                painter: _HealthRingPainter(
                  value: value,
                  track: tokens.brandSage,
                  arc: tokens.brandAction,
                  ink: tokens.textPrimary,
                ),
                child: Center(
                  child: Text(
                    percentText,
                    style: Theme.of(context).textTheme.labelLarge,
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _HealthRingPainter extends CustomPainter {
  _HealthRingPainter({
    required this.value,
    required this.track,
    required this.arc,
    required this.ink,
  });

  final double? value;
  final Color track;
  final Color arc;
  final Color ink;

  @override
  void paint(Canvas canvas, Size size) {
    final center = Offset(size.width / 2, size.height / 2);
    final radius = size.shortestSide / 2 - 6;
    final strokeWidth = size.shortestSide * 0.1;
    final trackPaint = Paint()
      ..color = track
      ..style = PaintingStyle.stroke
      ..strokeWidth = strokeWidth
      ..strokeCap = StrokeCap.round;
    canvas.drawCircle(center, radius, trackPaint);

    final v = value;
    if (v == null) {
      // Unknown: small dash marker instead of a fake score.
      final dash = Paint()
        ..color = ink
        ..style = PaintingStyle.stroke
        ..strokeWidth = strokeWidth * 0.6
        ..strokeCap = StrokeCap.round;
      canvas.drawArc(
        Rect.fromCircle(center: center, radius: radius),
        -0.35,
        0.7,
        false,
        dash,
      );
      return;
    }
    final arcPaint = Paint()
      ..color = arc
      ..style = PaintingStyle.stroke
      ..strokeWidth = strokeWidth
      ..strokeCap = StrokeCap.round;
    canvas.drawArc(
      Rect.fromCircle(center: center, radius: radius),
      -1.5708,
      6.28318 * v.clamp(0.0, 1.0),
      false,
      arcPaint,
    );
  }

  @override
  bool shouldRepaint(_HealthRingPainter oldDelegate) =>
      oldDelegate.value != value ||
      oldDelegate.track != track ||
      oldDelegate.arc != arc;
}

/// Weather card fed by demo data; as-of makes the source explicit.
class WeatherCard extends StatelessWidget {
  const WeatherCard({
    required this.temperatureC,
    required this.conditionLabel,
    required this.humidityPercent,
    required this.windLabel,
    required this.asOf,
    this.offline = false,
    super.key,
  });

  final int temperatureC;
  final String conditionLabel;
  final int humidityPercent;
  final String windLabel;
  final String asOf;
  final bool offline;

  @override
  Widget build(BuildContext context) {
    final tokens = FarmThemeExtension.of(context);
    final l10n = AppLocalizations.of(context);
    return Semantics(
      container: true,
      label: l10n.weatherSemantics(
        conditionLabel,
        temperatureC,
        humidityPercent,
        windLabel,
        offline ? l10n.savedDataSource : l10n.todayForecastSource,
        asOf,
      ),
      child: FarmCard(
        // Reference layout: sun icon top-right, big temperature + condition
        // on the left, humidity/wind pair below — half of the two-card row.
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        '$temperatureC°C',
                        style: Theme.of(context).textTheme.headlineMedium,
                      ),
                      Text(
                        conditionLabel,
                        style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                          color: tokens.textSecondary,
                        ),
                        softWrap: true,
                      ),
                    ],
                  ),
                ),
                Icon(
                  Icons.wb_sunny_outlined,
                  size: 32,
                  color: tokens.illustrationBarn,
                ),
              ],
            ),
            const SizedBox(height: FarmSpacing.sm),
            Text(
              l10n.weatherHumidity(humidityPercent),
              style: Theme.of(context).textTheme.bodySmall,
              softWrap: true,
            ),
            const SizedBox(height: FarmSpacing.xs),
            Text(
              windLabel,
              style: Theme.of(context).textTheme.bodySmall,
              softWrap: true,
            ),
          ],
        ),
      ),
    );
  }
}
