import 'package:flutter_test/flutter_test.dart';
import 'package:lifedna/core/engines/load_engine.dart';

void main() {
  List<DailyLoad> series(List<double> loads) {
    final start = DateTime(2026, 8, 1);
    return [
      for (var i = 0; i < loads.length; i++)
        DailyLoad(
          date: start.add(Duration(days: i)),
          load: loads[i],
        ),
    ];
  }

  group('LoadEngine — session load', () {
    test('is RPE × duration', () {
      expect(LoadEngine.sessionLoad(sessionRpe: 8, durationMinutes: 73), 584);
    });

    test('invalid input yields zero, not a negative load', () {
      expect(LoadEngine.sessionLoad(sessionRpe: 0, durationMinutes: 60), 0);
      expect(LoadEngine.sessionLoad(sessionRpe: 8, durationMinutes: 0), 0);
      expect(LoadEngine.sessionLoad(sessionRpe: -3, durationMinutes: 60), 0);
    });
  });

  group(
    'LoadEngine — RPE estimation when the user did not rate the session',
    () {
      test('a typical session estimates near its mean set RPE', () {
        // 5 + (8 − 7) × 1.2 + volumeFactor(22 sets → 0.333) = 6.53 → 7
        expect(LoadEngine.estimateSessionRpe(avgSetRpe: 8, workingSets: 22), 7);
      });

      test('high volume raises the estimate', () {
        final low = LoadEngine.estimateSessionRpe(
          avgSetRpe: 8,
          workingSets: 10,
        );
        final high = LoadEngine.estimateSessionRpe(
          avgSetRpe: 8,
          workingSets: 30,
        );
        expect(high, greaterThan(low));
      });

      test('the estimate is always a valid RPE', () {
        for (final rpe in [null, 1.0, 5.0, 7.5, 10.0]) {
          for (final sets in [0, 5, 22, 60]) {
            final e = LoadEngine.estimateSessionRpe(
              avgSetRpe: rpe,
              workingSets: sets,
            );
            expect(e, inInclusiveRange(4, 10));
          }
        }
      });
    },
  );

  group('LoadEngine — acute and chronic windows', () {
    test('an empty series is handled, not divided by zero', () {
      final s = LoadEngine.summarize(const []);
      expect(s.acute, 0);
      expect(s.chronic, 0);
      expect(s.acwr, isNull);
      expect(s.hasSufficientHistory, isFalse);
    });

    test('a steady load produces a ratio near 1', () {
      final s = LoadEngine.summarize(series(List.filled(28, 400)));
      expect(s.hasSufficientHistory, isTrue);
      expect(s.acwr, closeTo(1.0, 0.05));
      expect(s.meanDailyLoad28d, 400);
    });

    test('a recent spike raises the ratio above 1', () {
      final loads = <double>[...List.filled(21, 300), ...List.filled(7, 900)];
      final s = LoadEngine.summarize(series(loads));
      expect(s.acwr, greaterThan(1.3));
    });

    test('a recent drop lowers the ratio below 1', () {
      final loads = <double>[...List.filled(21, 600), ...List.filled(7, 100)];
      final s = LoadEngine.summarize(series(loads));
      expect(s.acwr, lessThan(0.8));
    });

    test('the ratio is null below the minimum history, not a false number', () {
      // A new user has no chronic baseline. Reporting a ratio would be a lie.
      final s = LoadEngine.summarize(series(List.filled(5, 400)));
      expect(s.hasSufficientHistory, isFalse);
      expect(s.acwr, isNull);
    });

    test('rest days must be included and are weighted as zero load', () {
      final withRest = LoadEngine.summarize(
        series([for (var i = 0; i < 28; i++) i.isEven ? 800.0 : 0.0]),
      );
      final withoutRest = LoadEngine.summarize(series(List.filled(28, 800)));
      expect(withRest.chronic, lessThan(withoutRest.chronic));
    });

    test('recency is weighted — the acute window tracks the last few days', () {
      final risingLate = LoadEngine.summarize(
        series([...List.filled(24, 200), 900, 900, 900, 900]),
      );
      final risingEarly = LoadEngine.summarize(
        series([900, 900, 900, 900, ...List.filled(24, 200)]),
      );
      expect(risingLate.acute, greaterThan(risingEarly.acute));
    });
  });

  group('VolumeLandmarks', () {
    test('classifies weekly sets against the MEV/MRV band', () {
      expect(VolumeLandmarks.assess('chest', 4), VolumeVerdict.belowMev);
      expect(VolumeLandmarks.assess('chest', 9), VolumeVerdict.adequate);
      expect(VolumeLandmarks.assess('chest', 16), VolumeVerdict.optimal);
      expect(VolumeLandmarks.assess('chest', 21), VolumeVerdict.adequate);
      expect(VolumeLandmarks.assess('chest', 30), VolumeVerdict.aboveMrv);
    });

    test('an unknown muscle is unknown, not silently optimal', () {
      expect(VolumeLandmarks.assess('tail', 12), VolumeVerdict.unknown);
    });

    test('every band is internally consistent', () {
      for (final entry in VolumeLandmarks.table.entries) {
        final b = entry.value;
        expect(b.mev, lessThanOrEqualTo(b.mavLow), reason: entry.key);
        expect(b.mavLow, lessThanOrEqualTo(b.mavHigh), reason: entry.key);
        expect(b.mavHigh, lessThanOrEqualTo(b.mrv), reason: entry.key);
      }
    });
  });

  group('LoadEngine — weekly sets by muscle', () {
    test('aggregates across sessions', () {
      final result = LoadEngine.weeklySetsByMuscle([
        (muscle: 'chest', sets: 8),
        (muscle: 'chest', sets: 6),
        (muscle: 'triceps', sets: 9),
      ]);
      expect(result['chest'], 14);
      expect(result['triceps'], 9);
    });
  });
}
