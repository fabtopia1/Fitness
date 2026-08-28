import 'package:flutter_test/flutter_test.dart';
import 'package:lifedna/core/engines/recovery_engine.dart';
import 'package:lifedna/shared/enums/enums.dart';

/// Golden fixtures for [RecoveryEngine] (docs/12-recovery-engine.md).
///
/// The degradation group is the most important set here: most users will never
/// have HRV, and many will have no wearable at all. An engine that only works
/// with complete data is an engine that works for nobody.
void main() {
  group('RecoveryEngine — worked example from docs/12 §10', () {
    // 431 min sleep, in bed 468, deep 78, REM 96, σ_bed 24, σ_wake 19
    const sleep = SleepInput(
      totalMinutes: 431,
      timeInBedMinutes: 468,
      deepMinutes: 78,
      remMinutes: 96,
      bedtimeStdDevMinutes: 24,
      wakeStdDevMinutes: 19,
      nightsOfHistory: 14,
    );
    const training = TrainingInput(
      acwr: 1.073,
      yesterdayLoad: 584,
      meanDailyLoad28d: 334,
      yesterdaySessionRpe: 8,
    );
    const activity = ActivityInput(
      steps: 8432,
      stepGoal: 12000,
      activeMinutes: 62,
      trainedYesterday: true,
    );

    test('sleep score composes its four sub-components', () {
      // duration 88.6 · consistency 97.6 · efficiency 100 · stages 99.25
      // → 0.40(88.6) + 0.25(97.6) + 0.20(100) + 0.15(99.25) = 94.7
      final r = RecoveryEngine.compute(sleep: sleep, training: training, activity: activity);
      expect(r.sleepScore, 95);
    });

    test('training component penalizes a heavy previous session', () {
      // ACWR 1.073 → base 100. Yesterday 584 > 1.5 × 334 = 501 → −15 → 85.
      final r = RecoveryEngine.compute(sleep: sleep, training: training, activity: activity);
      final t = r.components.firstWhere((c) => c.name == 'training');
      expect(t.score, 85);
    });

    test('activity component blends steps and active minutes', () {
      // steps 0.703 → 70.3 ; activeMinutes 62/45 → clamped 100
      // 0.6(70.3) + 0.4(100) = 82.2
      final r = RecoveryEngine.compute(sleep: sleep, training: training, activity: activity);
      final a = r.components.firstWhere((c) => c.name == 'activity');
      expect(a.score, 82);
    });

    test('composite recovery is the weighted sum', () {
      // 0.40(95) + 0.40(85) + 0.20(82) = 38 + 34 + 16.4 = 88.4 → 88
      final r = RecoveryEngine.compute(sleep: sleep, training: training, activity: activity);
      expect(r.recoveryScore, 88);
      expect(r.band, RecoveryBand.high);
    });

    test('readiness discounts recovery by the demand of today’s session', () {
      // planned 8 × 75 = 600 ; mean daily 334 → demand 1.796
      // 88 − (1.796 − 1) × 18 = 88 − 14.3 = 73.7 → 74
      final r = RecoveryEngine.compute(
        sleep: sleep,
        training: training,
        activity: activity,
        plannedSession: const PlannedSession(rpe: 8, durationMinutes: 75),
      );
      expect(r.readinessScore, 74);
      expect(r.action, TrainingAction.proceed);
    });

    test('neutral physiology leaves the score unchanged', () {
      final r = RecoveryEngine.compute(
        sleep: sleep,
        training: training,
        activity: activity,
        physiology: const PhysiologyInput(
          restingHrBpm: 58,
          baselineRestingHrBpm: 59,
          hrvMs: 42,
          baselineHrvMs: 40.8,
        ),
      );
      expect(r.recoveryScore, 88);
    });
  });

  group('RecoveryEngine — degradation', () {
    const sleep = SleepInput(totalMinutes: 450, timeInBedMinutes: 480);
    const training = TrainingInput(
      acwr: 1.0,
      yesterdayLoad: 300,
      meanDailyLoad28d: 320,
    );

    test('two components produce a score with renormalized weights', () {
      final r = RecoveryEngine.compute(sleep: sleep, training: training);
      expect(r.isSufficient, isTrue);
      expect(r.missingInputs, ['activity']);

      final s = r.components.firstWhere((c) => c.name == 'sleep');
      final t = r.components.firstWhere((c) => c.name == 'training');
      expect(s.weight, 0.5);
      expect(t.weight, 0.5);

      final a = r.components.firstWhere((c) => c.name == 'activity');
      expect(a.available, isFalse);
      expect(a.contribution, 0);
    });

    test('one component refuses to produce a score', () {
      final r = RecoveryEngine.compute(sleep: sleep);
      expect(r.recoveryScore, isNull);
      expect(r.readinessScore, isNull);
      expect(r.band, RecoveryBand.insufficientData);
      expect(r.action, isNull);
      // The message names what would fix it — never a bare "insufficient data".
      expect(r.detail, contains('training history'));
      expect(r.detail, contains('daily activity'));
    });

    test('no components at all is handled, not crashed', () {
      final r = RecoveryEngine.compute();
      expect(r.recoveryScore, isNull);
      expect(r.band, RecoveryBand.insufficientData);
      expect(r.missingInputs, ['sleep', 'training', 'activity']);
    });

    test('sleep consistency is skipped below 7 nights of history', () {
      final short = RecoveryEngine.compute(
        sleep: const SleepInput(
          totalMinutes: 450,
          timeInBedMinutes: 480,
          bedtimeStdDevMinutes: 90,
          wakeStdDevMinutes: 90,
          nightsOfHistory: 3,
        ),
        training: training,
      );
      final long = RecoveryEngine.compute(
        sleep: const SleepInput(
          totalMinutes: 450,
          timeInBedMinutes: 480,
          bedtimeStdDevMinutes: 90,
          wakeStdDevMinutes: 90,
          nightsOfHistory: 14,
        ),
        training: training,
      );
      // With enough history a wildly irregular schedule must cost something.
      expect(long.sleepScore, lessThan(short.sleepScore!));
    });

    test('an unknown ACWR yields a neutral training score, not a penalty', () {
      final r = RecoveryEngine.compute(
        sleep: sleep,
        training: const TrainingInput(
          acwr: null,
          yesterdayLoad: 0,
          meanDailyLoad28d: 0,
        ),
      );
      final t = r.components.firstWhere((c) => c.name == 'training');
      expect(t.score, 75);
    });
  });

  group('RecoveryEngine — sleep duration asymmetry', () {
    int scoreFor(int minutes) => RecoveryEngine.compute(
          sleep: SleepInput(totalMinutes: minutes, timeInBedMinutes: minutes + 30),
          training: const TrainingInput(
            acwr: 1.0,
            yesterdayLoad: 300,
            meanDailyLoad28d: 320,
          ),
        ).sleepScore!;

    test('the ideal band scores at the top', () {
      expect(scoreFor(480), greaterThanOrEqualTo(95));
      expect(scoreFor(500), greaterThanOrEqualTo(95));
    });

    test('under-sleeping is penalized harder than over-sleeping', () {
      // 20 % under (384 min) vs 20 % over (576 min)
      final under = scoreFor(384);
      final over = scoreFor(576);
      expect(under, lessThan(over));
    });

    test('over-sleeping never falls below the duration floor', () {
      // 15 h is implausible, but the duration sub-score floors at 60 rather
      // than collapsing — long sleep is a weak signal, not a catastrophe.
      expect(scoreFor(900), 73);
    });

    test('near-zero sleep does not produce a negative score', () {
      expect(scoreFor(30), greaterThanOrEqualTo(0));
    });
  });

  group('RecoveryEngine — ACWR bands', () {
    int trainingScore(double? acwr) => RecoveryEngine.compute(
          sleep: const SleepInput(totalMinutes: 450, timeInBedMinutes: 480),
          training: TrainingInput(
            acwr: acwr,
            yesterdayLoad: 100,
            meanDailyLoad28d: 300,
          ),
        ).components.firstWhere((c) => c.name == 'training').score;

    test('the productive band scores 100', () {
      expect(trainingScore(0.85), 100);
      expect(trainingScore(1.10), 100);
      expect(trainingScore(1.29), 100);
    });

    test('detraining is penalized', () => expect(trainingScore(0.4), 70));
    test('elevated load is penalized', () => expect(trainingScore(1.4), 75));
    test('high load is penalized harder', () => expect(trainingScore(1.6), 50));
    test('dangerous load scores lowest', () => expect(trainingScore(1.9), 25));
  });

  group('RecoveryEngine — recommendation mapping', () {
    RecoveryResult run({
      required int sleepMinutes,
      required double acwr,
      required int plannedRpe,
    }) =>
        RecoveryEngine.compute(
          sleep: SleepInput(
            totalMinutes: sleepMinutes,
            timeInBedMinutes: sleepMinutes + 40,
          ),
          training: TrainingInput(
            acwr: acwr,
            yesterdayLoad: 200,
            meanDailyLoad28d: 400,
          ),
          activity: const ActivityInput(
            steps: 10000,
            stepGoal: 10000,
            activeMinutes: 45,
          ),
          plannedSession:
              PlannedSession(rpe: plannedRpe, durationMinutes: 60),
        );

    test('a rested athlete on a balanced load gets a green light', () {
      final r = run(sleepMinutes: 490, acwr: 1.0, plannedRpe: 6);
      expect(r.action, TrainingAction.push);
      expect(r.detail, contains('record'));
    });

    test('a dangerous load ratio forces rest regardless of sleep', () {
      final r = run(sleepMinutes: 490, acwr: 1.9, plannedRpe: 6);
      expect(r.action, TrainingAction.rest);
    });

    test('severe sleep loss reduces the session', () {
      final r = run(sleepMinutes: 240, acwr: 1.4, plannedRpe: 9);
      expect(
        r.action,
        anyOf(TrainingAction.reduce, TrainingAction.rest),
      );
    });
  });

  group('RecoveryEngine — physiological adjustment', () {
    const sleep = SleepInput(totalMinutes: 450, timeInBedMinutes: 480);
    const training = TrainingInput(
      acwr: 1.0,
      yesterdayLoad: 300,
      meanDailyLoad28d: 320,
    );

    int scoreWith(PhysiologyInput p) => RecoveryEngine.compute(
          sleep: sleep,
          training: training,
          physiology: p,
        ).recoveryScore!;

    test('an elevated resting heart rate lowers the score', () {
      final baseline = RecoveryEngine.compute(
        sleep: sleep,
        training: training,
      ).recoveryScore!;
      final elevated = scoreWith(
        const PhysiologyInput(restingHrBpm: 68, baselineRestingHrBpm: 58),
      );
      expect(elevated, lessThan(baseline));
    });

    test('suppressed HRV lowers the score', () {
      final baseline = RecoveryEngine.compute(
        sleep: sleep,
        training: training,
      ).recoveryScore!;
      final suppressed = scoreWith(
        const PhysiologyInput(hrvMs: 30, baselineHrvMs: 45),
      );
      expect(suppressed, lessThan(baseline));
    });

    test('the total physiological adjustment is capped at ±10', () {
      final baseline = RecoveryEngine.compute(
        sleep: sleep,
        training: training,
      ).recoveryScore!;
      final worst = scoreWith(
        const PhysiologyInput(
          restingHrBpm: 80,
          baselineRestingHrBpm: 55,
          hrvMs: 10,
          baselineHrvMs: 50,
        ),
      );
      expect(baseline - worst, lessThanOrEqualTo(10));
    });

    test('an incomplete physiology reading is ignored, not half-applied', () {
      final baseline = RecoveryEngine.compute(
        sleep: sleep,
        training: training,
      ).recoveryScore!;
      // No baseline supplied — cannot be interpreted.
      final partial = scoreWith(const PhysiologyInput(restingHrBpm: 80));
      expect(partial, baseline);
    });
  });

  group('RecoveryEngine — invariants', () {
    test('the score is always within 0–100 across an input sweep', () {
      for (var minutes = 0; minutes <= 900; minutes += 30) {
        for (final acwr in [0.0, 0.5, 1.0, 1.5, 2.0, 3.0]) {
          for (var steps = 0; steps <= 25000; steps += 5000) {
            final r = RecoveryEngine.compute(
              sleep: SleepInput(
                totalMinutes: minutes,
                timeInBedMinutes: minutes + 40,
              ),
              training: TrainingInput(
                acwr: acwr,
                yesterdayLoad: 400,
                meanDailyLoad28d: 350,
              ),
              activity: ActivityInput(
                steps: steps,
                stepGoal: 10000,
                activeMinutes: 30,
              ),
            );
            final score = r.recoveryScore!;
            expect(score, inInclusiveRange(0, 100));
            expect(r.readinessScore!, inInclusiveRange(0, 100));
          }
        }
      }
    });

    test('component weights sum to 1 when all are available', () {
      final r = RecoveryEngine.compute(
        sleep: const SleepInput(totalMinutes: 450, timeInBedMinutes: 480),
        training: const TrainingInput(
          acwr: 1.0,
          yesterdayLoad: 300,
          meanDailyLoad28d: 320,
        ),
        activity: const ActivityInput(
          steps: 9000,
          stepGoal: 10000,
          activeMinutes: 40,
        ),
      );
      final total = r.components.fold<double>(0, (s, c) => s + c.weight);
      expect(total, closeTo(1.0, 0.001));
    });

    test('identical inputs produce identical output', () {
      const sleep = SleepInput(totalMinutes: 431, timeInBedMinutes: 468);
      const training = TrainingInput(
        acwr: 1.07,
        yesterdayLoad: 584,
        meanDailyLoad28d: 334,
      );
      final a = RecoveryEngine.compute(sleep: sleep, training: training);
      final b = RecoveryEngine.compute(sleep: sleep, training: training);
      expect(a.recoveryScore, b.recoveryScore);
      expect(a.readinessScore, b.readinessScore);
      expect(a.action, b.action);
    });
  });
}
