import 'package:flutter_test/flutter_test.dart';
import 'package:lifedna/core/engines/e1rm_calculator.dart';

void main() {
  group('E1rmCalculator — Epley', () {
    test('a single rep is the load itself', () {
      expect(E1rmCalculator.epley(100, 1), 100);
    });

    test('reference set from docs/06: 32.5 kg × 10', () {
      // 32.5 × (1 + 10/30) = 43.333…
      expect(E1rmCalculator.epley(32.5, 10), closeTo(43.333, 0.001));
      expect(E1rmCalculator.estimate(32.5, 10).value, 43.3);
    });

    test('previous session 30 kg × 10 gives the 40.0 kg prior best', () {
      expect(E1rmCalculator.estimate(30, 10).value, 40);
    });

    test('invalid input yields zero rather than NaN or a throw', () {
      expect(E1rmCalculator.epley(0, 10), 0);
      expect(E1rmCalculator.epley(100, 0), 0);
      expect(E1rmCalculator.epley(-50, 5), 0);
    });
  });

  group('E1rmCalculator — Brzycki cross-check', () {
    test('a single rep is the load itself', () {
      expect(E1rmCalculator.brzycki(100, 1), 100);
    });

    test('agrees closely with Epley in the low-rep range', () {
      // Epley 116.67 vs Brzycki 112.5 → 3.6 % apart. The formulas are close
      // here and diverge as reps rise, which is what drives the confidence
      // label rather than a hard cutoff.
      final e = E1rmCalculator.estimate(100, 5);
      expect(e.divergencePct, closeTo(3.6, 0.1));
      expect(e.confidence, E1rmConfidence.high);

      final many = E1rmCalculator.estimate(100, 15);
      expect(many.divergencePct, greaterThan(e.divergencePct));
    });

    test('is not evaluated at or beyond its asymptote', () {
      // The formula divides by (37 − reps) and is meaningless as it approaches
      // that. Returning 0 is honest; returning a huge number would not be.
      expect(E1rmCalculator.brzycki(100, 37), 0);
      expect(E1rmCalculator.brzycki(100, 50), 0);
    });
  });

  group('E1rmCalculator — confidence labelling', () {
    test('1–5 reps is high confidence', () {
      expect(E1rmCalculator.estimate(100, 1).confidence, E1rmConfidence.high);
      expect(E1rmCalculator.estimate(100, 5).confidence, E1rmConfidence.high);
    });

    test('6–12 reps is moderate', () {
      expect(
        E1rmCalculator.estimate(100, 6).confidence,
        E1rmConfidence.moderate,
      );
      expect(
        E1rmCalculator.estimate(100, 12).confidence,
        E1rmConfidence.moderate,
      );
    });

    test(
      'above 12 reps is flagged low — an endurance set is not a max test',
      () {
        expect(E1rmCalculator.estimate(100, 13).confidence, E1rmConfidence.low);
        expect(E1rmCalculator.estimate(100, 25).confidence, E1rmConfidence.low);
      },
    );
  });

  group('E1rmCalculator — inverse and rounding', () {
    test('weightForReps inverts Epley', () {
      final e1rm = E1rmCalculator.epley(100, 5); // 116.667
      expect(E1rmCalculator.weightForReps(e1rm, 5), closeTo(100, 0.1));
    });

    test('rounds to the nearest achievable plate increment', () {
      // 103.7 is 1.2 above 102.5 and 1.3 below 105, so it rounds DOWN.
      expect(
        E1rmCalculator.roundToIncrement(103.7, 2.5),
        closeTo(102.5, 0.001),
      );
      expect(E1rmCalculator.roundToIncrement(104.0, 2.5), closeTo(105, 0.001));
      expect(E1rmCalculator.roundToIncrement(101.2, 2.5), closeTo(100, 0.001));
      // An unknown increment must pass the load through untouched rather than
      // dividing by zero.
      expect(E1rmCalculator.roundToIncrement(100, 0), 100);
    });
  });

  group('PrDetector', () {
    // Not const: a map keyed by double cannot be a constant, because double
    // has no primitive equality.
    final bests = ExerciseBests(
      heaviestWeightKg: 30,
      bestE1rm: 40,
      repsAtWeight: {30.0: 10, 32.5: 8},
      maxSessionVolumeKg: 1200,
    );

    test('the reference PR from docs/06: 32.5 × 10 beats a 40.0 e1RM', () {
      final prs = PrDetector.forSet(
        exerciseId: 'incline-dumbbell-press',
        weightKg: 32.5,
        reps: 10,
        isWarmup: false,
        bests: bests,
      );

      final e1rmPr = prs.firstWhere((p) => p.type == PrType.bestE1rm);
      expect(e1rmPr.value, 43.3);
      expect(e1rmPr.previousValue, 40);
      expect(e1rmPr.improvementPct, 8.25);
      expect(e1rmPr.headline, contains('Best estimated 1RM'));
      expect(e1rmPr.headline, contains('43.3'));
    });

    test('detects a heaviest-weight record', () {
      final prs = PrDetector.forSet(
        exerciseId: 'x',
        weightKg: 35,
        reps: 5,
        isWarmup: false,
        bests: bests,
      );
      expect(prs.any((p) => p.type == PrType.heaviestWeight), isTrue);
    });

    test('detects more reps at an already-used load', () {
      final prs = PrDetector.forSet(
        exerciseId: 'x',
        weightKg: 32.5,
        reps: 10, // previous best at 32.5 was 8
        isWarmup: false,
        bests: bests,
      );
      final repPr = prs.firstWhere((p) => p.type == PrType.maxReps);
      expect(repPr.value, 10);
      expect(repPr.previousValue, 8);
    });

    test('matching a previous best is NOT a record', () {
      // Ties must not celebrate, or the celebration stops meaning anything.
      final prs = PrDetector.forSet(
        exerciseId: 'x',
        weightKg: 30,
        reps: 10,
        isWarmup: false,
        bests: bests,
      );
      expect(prs, isEmpty);
    });

    test('warm-up sets never produce records', () {
      final prs = PrDetector.forSet(
        exerciseId: 'x',
        weightKg: 200,
        reps: 20,
        isWarmup: true,
        bests: bests,
      );
      expect(prs, isEmpty);
    });

    test('a first-ever set produces records with a null previous value', () {
      final prs = PrDetector.forSet(
        exerciseId: 'x',
        weightKg: 60,
        reps: 8,
        isWarmup: false,
        bests: const ExerciseBests(),
      );
      expect(prs.length, 2); // heaviest weight + best e1RM
      expect(prs.every((p) => p.previousValue == null), isTrue);
      expect(prs.first.improvementPct, 0);
    });

    test('invalid sets produce nothing', () {
      expect(
        PrDetector.forSet(
          exerciseId: 'x',
          weightKg: 0,
          reps: 10,
          isWarmup: false,
          bests: bests,
        ),
        isEmpty,
      );
    });

    test('session volume record only fires on a strict improvement', () {
      expect(
        PrDetector.forSessionVolume(
          exerciseId: 'x',
          sessionVolumeKg: 1200,
          previousMax: 1200,
        ),
        isNull,
      );
      expect(
        PrDetector.forSessionVolume(
          exerciseId: 'x',
          sessionVolumeKg: 1371,
          previousMax: 1200,
        )?.value,
        1371,
      );
    });
  });

  group('OverloadAdvisor', () {
    SessionPerformance perfect() => SessionPerformance(
      date: DateTime(2026, 8, 27),
      workingSets: const [
        (weightKg: 32.5, reps: 12, rpe: 7),
        (weightKg: 32.5, reps: 12, rpe: 8),
        (weightKg: 32.5, reps: 12, rpe: 8),
      ],
    );

    test('two clean sessions at RPE ≤ 8 earn a load increase', () {
      final suggestion = OverloadAdvisor.suggestedIncrease(
        lastTwoSessions: [perfect(), perfect()],
        targetRepsMin: 12,
        incrementKg: 2.5,
      );
      expect(suggestion, 2.5);
    });

    test('a hard session (RPE 9) does not earn an increase', () {
      final hard = SessionPerformance(
        date: DateTime(2026, 8, 27),
        workingSets: const [
          (weightKg: 32.5, reps: 12, rpe: 9),
          (weightKg: 32.5, reps: 12, rpe: 9),
        ],
      );
      expect(
        OverloadAdvisor.suggestedIncrease(
          lastTwoSessions: [perfect(), hard],
          targetRepsMin: 12,
          incrementKg: 2.5,
        ),
        isNull,
      );
    });

    test('missing target reps does not earn an increase', () {
      final short = SessionPerformance(
        date: DateTime(2026, 8, 27),
        workingSets: const [
          (weightKg: 32.5, reps: 10, rpe: 7),
          (weightKg: 32.5, reps: 9, rpe: 8),
        ],
      );
      expect(
        OverloadAdvisor.suggestedIncrease(
          lastTwoSessions: [perfect(), short],
          targetRepsMin: 12,
          incrementKg: 2.5,
        ),
        isNull,
      );
    });

    test('a single session is not enough evidence', () {
      expect(
        OverloadAdvisor.suggestedIncrease(
          lastTwoSessions: [perfect()],
          targetRepsMin: 12,
          incrementKg: 2.5,
        ),
        isNull,
      );
    });

    test('an unrecorded RPE is treated as hard, not as easy', () {
      // Absence of evidence must not be read as evidence of an easy set.
      final unrated = SessionPerformance(
        date: DateTime(2026, 8, 27),
        workingSets: const [(weightKg: 32.5, reps: 12, rpe: null)],
      );
      expect(
        OverloadAdvisor.suggestedIncrease(
          lastTwoSessions: [perfect(), unrated],
          targetRepsMin: 12,
          incrementKg: 2.5,
        ),
        isNull,
      );
    });
  });

  group('SessionPerformance', () {
    test('computes volume and best e1RM', () {
      final s = SessionPerformance(
        date: DateTime(2026, 8, 27),
        workingSets: const [
          (weightKg: 30.0, reps: 12, rpe: 7),
          (weightKg: 32.5, reps: 10, rpe: 8),
          (weightKg: 32.5, reps: 10, rpe: 9),
          (weightKg: 32.5, reps: 8, rpe: 9),
        ],
      );
      // 360 + 325 + 325 + 260 = 1270
      expect(s.volumeKg, 1270);
      expect(s.bestE1rm, closeTo(43.333, 0.001));
    });

    test('an empty session is zero, not an error', () {
      final s = SessionPerformance(
        date: DateTime(2026, 8, 27),
        workingSets: const [],
      );
      expect(s.volumeKg, 0);
      expect(s.bestE1rm, 0);
    });
  });
}
