import 'dart:io';

import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';
import 'package:lifedna/core/theme/app_theme.dart';
import 'package:lifedna/core/theme/ld_spacing.dart';
import 'package:lifedna/core/widgets/ld_widgets.dart';
import 'package:lifedna/features/body/domain/body_entities.dart';
import 'package:lifedna/features/body/presentation/body_editor_sheet.dart';
import 'package:lifedna/features/body/presentation/body_providers.dart';

class BodyScreen extends ConsumerWidget {
  const BodyScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final c = context.ldColors;
    final type = context.ldType;
    final async = ref.watch(bodyMeasurementsProvider);

    return Scaffold(
      appBar: AppBar(title: const Text('Body')),
      body: LdAsyncView(
        value: async,
        onRetry: () => ref.invalidate(bodyMeasurementsProvider),
        errorContext: 'Body tracking',
        isEmpty: (list) => list.isEmpty,
        empty: LdEmptyState(
          icon: Icons.monitor_weight_rounded,
          headline: 'No measurements yet',
          body: 'Log your weight to start seeing a trend. Everything else is '
              'optional.',
          actionLabel: 'Add measurement',
          onAction: () => _edit(context),
        ),
        data: (measurements) {
          final metrics = ref.watch(availableBodyMetricsProvider);
          final selected = ref.watch(selectedBodyMetricProvider);
          final trend = ref.watch(bodyTrendProvider);
          final photos =
              measurements.where((m) => m.photoPath != null).toList();

          return ListView(
            padding: const EdgeInsets.fromLTRB(
              LdSpacing.s4,
              LdSpacing.s3,
              LdSpacing.s4,
              LdSpacing.scrollBottom,
            ),
            children: [
              if (metrics.isNotEmpty)
                SizedBox(
                  height: 44,
                  child: ListView(
                    scrollDirection: Axis.horizontal,
                    children: [
                      for (final metric in metrics) ...[
                        ChoiceChip(
                          label: Text(metric.label),
                          selected: selected == metric,
                          onSelected: (_) => ref
                              .read(selectedBodyMetricProvider.notifier)
                              .state = metric,
                        ),
                        const SizedBox(width: LdSpacing.s2),
                      ],
                    ],
                  ),
                ),
              const SizedBox(height: LdSpacing.s3),
              _TrendCard(trend: trend),
              const LdSectionHeader(title: 'History'),
              for (final measurement in measurements.take(30))
                _MeasurementTile(measurement: measurement),
              if (photos.isNotEmpty) ...[
                const LdSectionHeader(title: 'Progress photos'),
                SizedBox(
                  height: 132,
                  child: ListView.separated(
                    scrollDirection: Axis.horizontal,
                    itemCount: photos.length,
                    separatorBuilder: (_, __) =>
                        const SizedBox(width: LdSpacing.s3),
                    itemBuilder: (context, index) {
                      final photo = photos[index];
                      return Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Expanded(
                            child: ClipRRect(
                              borderRadius:
                                  BorderRadius.circular(LdRadius.m),
                              child: Image.file(
                                // Photos are device-local; a missing file is
                                // normal after a restore, so it degrades to a
                                // placeholder instead of throwing.
                                File(photo.photoPath!),
                                width: 104,
                                fit: BoxFit.cover,
                                errorBuilder: (_, __, ___) => Container(
                                  width: 104,
                                  color: c.surfaceHighest,
                                  child: Icon(
                                    Icons.image_not_supported_rounded,
                                    color: c.textTertiary,
                                  ),
                                ),
                              ),
                            ),
                          ),
                          const SizedBox(height: LdSpacing.s1),
                          Text(
                            photo.localDate,
                            style: type.caption
                                .copyWith(color: c.textTertiary),
                          ),
                        ],
                      );
                    },
                  ),
                ),
              ],
            ],
          );
        },
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () => _edit(context),
        icon: const Icon(Icons.add_rounded),
        label: const Text('Log'),
      ),
    );
  }

  static Future<void> _edit(BuildContext context) =>
      showModalBottomSheet<void>(
        context: context,
        isScrollControlled: true,
        builder: (_) => const BodyEditorSheet(),
      );
}

class _TrendCard extends StatelessWidget {
  const _TrendCard({required this.trend});
  final BodyTrend trend;

  @override
  Widget build(BuildContext context) {
    final c = context.ldColors;
    final type = context.ldType;

    if (!trend.hasData) {
      return LdCard(
        child: Text(
          'No ${trend.metric.label.toLowerCase()} readings in the last 90 days.',
          style: type.bodyM.copyWith(color: c.textTertiary),
        ),
      );
    }

    final change = trend.change;
    final improving = trend.isImproving;
    final rate = trend.weeklyRate;
    final smoothed = trend.ewma;

    return LdCard(
      eyebrow: trend.metric.label,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.baseline,
            textBaseline: TextBaseline.alphabetic,
            children: [
              Text(
                trend.latest!.toStringAsFixed(1),
                style: type.displayM.copyWith(color: c.textPrimary),
              ),
              const SizedBox(width: LdSpacing.s1),
              Text(
                trend.metric.unit,
                style: type.labelMono.copyWith(color: c.textTertiary),
              ),
              const Spacer(),
              if (change != null && change != 0)
                Text(
                  '${change > 0 ? '+' : ''}${change.toStringAsFixed(1)} '
                  '${trend.metric.unit}',
                  style: type.titleM.copyWith(
                    color: improving == null
                        ? c.textSecondary
                        : improving
                            ? c.success
                            : c.warning,
                  ),
                ),
            ],
          ),
          if (rate != null) ...[
            const SizedBox(height: LdSpacing.s1),
            Text(
              '${rate > 0 ? '+' : ''}${rate.toStringAsFixed(2)} '
              '${trend.metric.unit} per week',
              style: type.bodyS.copyWith(color: c.textSecondary),
            ),
          ],
          if (trend.hasTrend) ...[
            const SizedBox(height: LdSpacing.s4),
            SizedBox(
              height: 160,
              child: LineChart(
                LineChartData(
                  gridData: FlGridData(
                    show: true,
                    drawVerticalLine: false,
                    getDrawingHorizontalLine: (_) =>
                        FlLine(color: c.border, strokeWidth: 1),
                  ),
                  titlesData: const FlTitlesData(show: false),
                  borderData: FlBorderData(show: false),
                  lineBarsData: [
                    // Raw readings, de-emphasised: daily weight swings by more
                    // than a week of real change.
                    LineChartBarData(
                      spots: [
                        for (var i = 0; i < trend.points.length; i++)
                          FlSpot(i.toDouble(), trend.points[i].value),
                      ],
                      isCurved: false,
                      color: c.textTertiary.withValues(alpha: 0.45),
                      barWidth: 1,
                      dotData: const FlDotData(show: false),
                    ),
                    // The smoothed line is the one to read.
                    LineChartBarData(
                      spots: [
                        for (var i = 0; i < smoothed.length; i++)
                          FlSpot(i.toDouble(), smoothed[i]),
                      ],
                      isCurved: true,
                      color: c.primary,
                      barWidth: 3,
                      dotData: const FlDotData(show: false),
                      belowBarData: BarAreaData(
                        show: true,
                        color: c.primary.withValues(alpha: 0.12),
                      ),
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: LdSpacing.s2),
            Text(
              'Solid line is a smoothed average — daily readings swing more '
              'than real change does.',
              style: type.caption.copyWith(color: c.textTertiary),
            ),
          ],
        ],
      ),
    );
  }
}

class _MeasurementTile extends StatelessWidget {
  const _MeasurementTile({required this.measurement});
  final BodyMeasurement measurement;

  @override
  Widget build(BuildContext context) {
    final c = context.ldColors;
    final type = context.ldType;
    final values = measurement.values;

    return Padding(
      padding: const EdgeInsets.only(bottom: LdSpacing.s2),
      child: LdCard(
        padding: const EdgeInsets.all(LdSpacing.s3),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              DateFormat('EEEE d MMMM')
                  .format(measurement.measuredAt.toLocal()),
              style: type.titleM.copyWith(color: c.textPrimary),
            ),
            const SizedBox(height: LdSpacing.s2),
            Wrap(
              spacing: LdSpacing.s3,
              runSpacing: LdSpacing.s1,
              children: [
                for (final entry in values.entries)
                  Text(
                    '${entry.key.label} ${entry.value.toStringAsFixed(1)} '
                    '${entry.key.unit}',
                    style: type.bodyS.copyWith(color: c.textSecondary),
                  ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
