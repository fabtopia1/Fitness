import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:lifedna/core/providers/providers.dart';
import 'package:lifedna/features/body/domain/body_entities.dart';

final bodyMeasurementsProvider = StreamProvider<List<BodyMeasurement>>(
  (ref) => ref.watch(bodyRepositoryProvider).watchAll(),
);

final selectedBodyMetricProvider =
    StateProvider<BodyMetric>((ref) => BodyMetric.weight);

final bodyTrendProvider = Provider<BodyTrend>((ref) {
  ref.watch(bodyMeasurementsProvider);
  return ref
      .watch(bodyRepositoryProvider)
      .trendFor(ref.watch(selectedBodyMetricProvider));
});

final availableBodyMetricsProvider = Provider<List<BodyMetric>>((ref) {
  ref.watch(bodyMeasurementsProvider);
  return ref.watch(bodyRepositoryProvider).availableMetrics();
});

/// 30-day bodyweight change, used by the dashboard and the coach.
final weightChangeProvider = Provider<double?>((ref) {
  ref.watch(bodyMeasurementsProvider);
  return ref
      .watch(bodyRepositoryProvider)
      .trendFor(BodyMetric.weight, days: 30)
      .change;
});
