import 'package:flutter_test/flutter_test.dart';
import 'package:lifedna/core/error/failure.dart';
import 'package:lifedna/core/sync/outbox.dart';
import 'package:lifedna/features/body/data/body_repository.dart';
import 'package:lifedna/features/body/domain/body_entities.dart';

import '../../../support/test_harness.dart';

void main() {
  late TestEnvironment env;
  late BodyRepository repository;

  final now = DateTime(2026, 3, 14, 7);

  setUp(() async {
    env = await TestEnvironment.create();
    repository = BodyRepository(
      store: env.store,
      outbox: Outbox(env.store),
      clock: () => now,
    );
  });
  tearDown(() async => env.dispose());

  Future<void> weighIn(double kg, DateTime at) => repository.save(
        repository.create(measuredAt: at, weightKg: kg),
      );

  group('validation', () {
    test('an entirely empty measurement is refused', () async {
      final result = await repository.save(repository.create());
      expect(result.failureOrNull, isA<ValidationFailure>());
    });

    test('an impossible bodyweight is refused', () async {
      for (final kg in [19.0, 401.0]) {
        final result = await repository.save(
          repository.create(weightKg: kg),
        );
        expect(
          result.failureOrNull,
          isA<ValidationFailure>()
              .having((f) => f.code, 'code', 'body_weight_out_of_range'),
          reason: '$kg',
        );
      }
    });

    test('an impossible body-fat percentage is refused', () async {
      final result = await repository.save(
        repository.create(bodyFatPct: 90),
      );
      expect(result.failureOrNull, isA<ValidationFailure>());
    });

    test('an impossible circumference is refused', () async {
      final result = await repository.save(
        repository.create(waistCm: 400),
      );
      expect(result.failureOrNull, isA<ValidationFailure>());
    });

    test('a measurement dated in the future is refused', () async {
      // A future entry would sit at the right-hand end of every chart and
      // distort every trend until the date arrived.
      final result = await repository.save(
        repository.create(
          measuredAt: now.add(const Duration(days: 1)),
          weightKg: 80,
        ),
      );
      expect(
        result.failureOrNull,
        isA<ValidationFailure>().having((f) => f.code, 'code', 'date_in_future'),
      );
    });

    test('a plausible measurement is stored', () async {
      final result = await repository.save(
        repository.create(weightKg: 82.4, waistCm: 84, bodyFatPct: 18),
      );
      expect(result.isOk, isTrue);
      expect(repository.latest()?.weightKg, 82.4);
    });
  });

  group('reading', () {
    test('chronological is oldest first and latest is the newest entry',
        () async {
      await weighIn(82, now.subtract(const Duration(days: 7)));
      await weighIn(81, now);

      expect(repository.chronological().first.weightKg, 82);
      expect(repository.latest()?.weightKg, 81);
    });

    test('latestWeightKg skips entries that recorded no weight', () async {
      await weighIn(82, now.subtract(const Duration(days: 2)));
      await repository.save(
        repository.create(measuredAt: now, waistCm: 84),
      );

      // The most recent measurement has no weight, so the last known weight is
      // still the useful answer — not null.
      expect(repository.latestWeightKg(), 82);
    });

    test('availableMetrics offers only metrics with data behind them',
        () async {
      await repository.save(
        repository.create(weightKg: 82, waistCm: 84),
      );

      expect(
        repository.availableMetrics(),
        containsAll([BodyMetric.weight, BodyMetric.waist]),
      );
      expect(repository.availableMetrics(), isNot(contains(BodyMetric.neck)));
    });

    test('withPhotos lists only entries with a photo, newest first', () async {
      await repository.save(
        repository.create(
          measuredAt: now.subtract(const Duration(days: 30)),
          weightKg: 85,
          photoPath: '/a.jpg',
        ),
      );
      await repository.save(repository.create(weightKg: 82));
      await repository.save(
        repository.create(
          measuredAt: now.subtract(const Duration(days: 1)),
          weightKg: 83,
          photoPath: '/b.jpg',
        ),
      );

      final photos = repository.withPhotos();
      expect(photos, hasLength(2));
      expect(photos.first.photoPath, '/b.jpg');
    });

    test('deleting removes the entry from every derived view', () async {
      await weighIn(82, now);
      final id = repository.latest()!.id;

      await repository.delete(id);

      expect(repository.latest(), isNull);
      expect(repository.availableMetrics(), isEmpty);
    });
  });

  group('trends', () {
    test('a trend contains only points inside the window', () async {
      await weighIn(90, now.subtract(const Duration(days: 200)));
      await weighIn(85, now.subtract(const Duration(days: 10)));
      await weighIn(84, now);

      final trend = repository.trendFor(BodyMetric.weight, days: 90, now: now);
      expect(trend.points, hasLength(2));
      expect(trend.first, 85);
      expect(trend.latest, 84);
      expect(trend.change, closeTo(-1, 0.001));
    });

    test('a single point has data but no trend', () async {
      await weighIn(82, now);
      final trend = repository.trendFor(BodyMetric.weight, now: now);

      expect(trend.hasData, isTrue);
      expect(trend.hasTrend, isFalse);
      expect(trend.change, isNull);
      expect(trend.weeklyRate, isNull);
    });

    test('the smoothed line lags the raw reading, which is the point',
        () async {
      // A day of water weight must not look like a day of fat gain.
      for (var i = 10; i >= 1; i--) {
        await weighIn(80, now.subtract(Duration(days: i)));
      }
      await weighIn(84, now);

      final trend = repository.trendFor(BodyMetric.weight, now: now);
      expect(trend.latest, 84);
      expect(trend.smoothedLatest, lessThan(82));
      expect(trend.smoothedLatest, greaterThan(80));
    });

    test('weekly rate is expressed per week, not per window', () async {
      await weighIn(84, now.subtract(const Duration(days: 28)));
      await weighIn(80, now);

      final trend = repository.trendFor(BodyMetric.weight, now: now);
      // Four weeks of smoothed movement, so the weekly figure is a quarter of
      // the total — and negative, because the weight fell.
      expect(trend.weeklyRate, lessThan(0));
      expect(trend.weeklyRate!.abs(), lessThan(4));
    });

    test('an empty trend is safe to render', () {
      final trend = repository.trendFor(BodyMetric.chest, now: now);
      expect(trend.hasData, isFalse);
      expect(trend.ewma, isEmpty);
      expect(trend.smoothedLatest, isNull);
    });

    test('metric direction is semantic, not arithmetic', () {
      // A falling waist is progress; a falling arm is not. Nothing may infer
      // this from the sign of the change.
      expect(BodyMetric.waist.lowerIsBetter, isTrue);
      expect(BodyMetric.leftArm.lowerIsBetter, isFalse);
    });
  });
}
