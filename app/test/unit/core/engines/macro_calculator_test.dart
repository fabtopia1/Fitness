import 'package:flutter_test/flutter_test.dart';
import 'package:lifedna/core/engines/macro_calculator.dart';
import 'package:lifedna/shared/enums/enums.dart';

/// Golden fixtures for [MacroCalculator].
///
/// These same cases are executed by the TypeScript suite in
/// `functions/test/engines/macro.test.ts`. A divergence fails BOTH builds —
/// that is the mechanism that keeps the client preview and the server-stored
/// value in agreement.
void main() {
  group('MacroCalculator — reference persona (docs/01 §5, persona 1)', () {
    const input = MacroInput(
      weightKg: 90.1,
      heightCm: 174.5,
      age: 21,
      sex: Sex.male,
      activityLevel: ActivityLevel.moderate,
      goalMode: GoalMode.cut,
      trainingDaysPerWeek: 6,
      leanMassKg: 61.9,
      weeklyRateTargetPct: 0.75,
    );

    test('BMR follows Mifflin-St Jeor exactly', () {
      // 10(90.1) + 6.25(174.5) − 5(21) + 5 = 1891.625
      expect(MacroCalculator.compute(input).bmr, 1892);
    });

    test('rest-day TDEE applies the moderate activity factor', () {
      // 1891.625 × 1.55 = 2932.019
      expect(MacroCalculator.compute(input).tdee, 2932);
    });

    test('a 0.75 %/week cut is NOT clamped for a six-day trainer', () {
      // The 25 % ceiling is measured against the weekly-average TDEE (3189),
      // giving −797. The requested delta is −743, so it stands.
      // Capping against the rest-day TDEE (2932 → −733) would have clamped it.
      final r = MacroCalculator.compute(input);
      expect(r.clamped, isFalse);
      expect(r.warnings, isEmpty);
    });

    test('day-type targets', () {
      final r = MacroCalculator.compute(input);
      expect(r.trainingDay.kcal, 2489);
      expect(r.restDay.kcal, 2189);
      expect(r.trainingDay.carbsG, 282);
      expect(r.restDay.carbsG, 207);
      expect(r.trainingDay.fatG, 63);
      expect(r.restDay.fatG, 63);
    });

    test('protein floor is goal-aware: a cut uses 2.2 g/kg', () {
      // 2.2 × 90.1 = 198.22 → 198. The lean-mass floor (2.4 × 61.9 = 148.6)
      // is lower here, and the ceiling (2.6 × 90.1 = 234.3) is not reached.
      final r = MacroCalculator.compute(input);
      expect(r.proteinFloorG, 198);
      expect(r.trainingDay.proteinG, 198);
      expect(r.restDay.proteinG, 198);
    });

    test('water target rounds to a real container size', () {
      // 90.1 × 35 + 500 × 6/7 = 3582 → nearest 250 → 3500
      expect(MacroCalculator.compute(input).waterMl, 3500);
    });

    test('projected rate reproduces the requested rate', () {
      final r = MacroCalculator.compute(input);
      expect(r.projectedWeeklyChangeKg, -0.68);
      final pct = r.projectedWeeklyChangeKg.abs() / 90.1 * 100;
      expect(pct, closeTo(0.75, 0.01));
    });
  });

  group('MacroCalculator — safety ceilings', () {
    const base = MacroInput(
      weightKg: 90.1,
      heightCm: 174.5,
      age: 21,
      sex: Sex.male,
      activityLevel: ActivityLevel.moderate,
      goalMode: GoalMode.cut,
      trainingDaysPerWeek: 6,
    );

    test('a requested rate above 1 %/week is clamped and warned', () {
      final r = MacroCalculator.compute(
        MacroInput(
          weightKg: base.weightKg,
          heightCm: base.heightCm,
          age: base.age,
          sex: base.sex,
          activityLevel: base.activityLevel,
          goalMode: base.goalMode,
          trainingDaysPerWeek: base.trainingDaysPerWeek,
          weeklyRateTargetPct: 2.0,
        ),
      );
      expect(r.clamped, isTrue);
      expect(r.warnings, contains('RATE_CLAMPED_TO_SAFE_MAXIMUM'));
      // Clamped to 1 %/week, then the 25 % ceiling binds on top of that.
      expect(r.projectedWeeklyChangeKg.abs() / 90.1 * 100, lessThanOrEqualTo(1.0));
    });

    test('the deficit never exceeds 25 % of weekly-average expenditure', () {
      final r = MacroCalculator.compute(
        const MacroInput(
          weightKg: 140,
          heightCm: 180,
          age: 30,
          sex: Sex.male,
          activityLevel: ActivityLevel.sedentary,
          goalMode: GoalMode.cut,
          trainingDaysPerWeek: 0,
          weeklyRateTargetPct: 1.0,
        ),
      );
      expect(r.clamped, isTrue);
      expect(r.warnings, contains('DEFICIT_CLAMPED_TO_25_PERCENT'));
    });

    test('the deficit never exceeds 1000 kcal/day', () {
      final r = MacroCalculator.compute(
        const MacroInput(
          weightKg: 200,
          heightCm: 190,
          age: 25,
          sex: Sex.male,
          activityLevel: ActivityLevel.veryActive,
          goalMode: GoalMode.cut,
          trainingDaysPerWeek: 6,
          weeklyRateTargetPct: 1.0,
        ),
      );
      final restDeficit = r.tdee - r.restDay.kcal;
      expect(restDeficit, lessThanOrEqualTo(1000));
    });

    test('energy never falls below the absolute floor', () {
      final male = MacroCalculator.compute(
        const MacroInput(
          weightKg: 48,
          heightCm: 160,
          age: 60,
          sex: Sex.male,
          activityLevel: ActivityLevel.sedentary,
          goalMode: GoalMode.cut,
          trainingDaysPerWeek: 0,
          weeklyRateTargetPct: 1.0,
        ),
      );
      expect(male.restDay.kcal, greaterThanOrEqualTo(1500));

      final female = MacroCalculator.compute(
        const MacroInput(
          weightKg: 45,
          heightCm: 155,
          age: 55,
          sex: Sex.female,
          activityLevel: ActivityLevel.sedentary,
          goalMode: GoalMode.cut,
          trainingDaysPerWeek: 0,
          weeklyRateTargetPct: 1.0,
        ),
      );
      expect(female.restDay.kcal, greaterThanOrEqualTo(1200));
    });
  });

  group('MacroCalculator — goal modes', () {
    MacroInput of(GoalMode mode) => MacroInput(
          weightKg: 80,
          heightCm: 178,
          age: 30,
          sex: Sex.male,
          activityLevel: ActivityLevel.moderate,
          goalMode: mode,
          trainingDaysPerWeek: 4,
        );

    test('maintain produces no energy delta', () {
      final r = MacroCalculator.compute(of(GoalMode.maintain));
      expect(r.restDay.kcal, r.tdee);
      expect(r.projectedWeeklyChangeKg, 0);
    });

    test('bulk produces a surplus', () {
      final r = MacroCalculator.compute(of(GoalMode.bulk));
      expect(r.restDay.kcal, greaterThan(r.tdee));
      expect(r.projectedWeeklyChangeKg, greaterThan(0));
    });

    test('cut produces a deficit', () {
      final r = MacroCalculator.compute(of(GoalMode.cut));
      expect(r.restDay.kcal, lessThan(r.tdee));
      expect(r.projectedWeeklyChangeKg, lessThan(0));
    });

    test('a cut prescribes more protein per kg than maintenance', () {
      final cut = MacroCalculator.compute(of(GoalMode.cut));
      final maintain = MacroCalculator.compute(of(GoalMode.maintain));
      expect(cut.proteinFloorG, greaterThan(maintain.proteinFloorG));
    });
  });

  group('MacroCalculator — protein floor bounds', () {
    test('lean mass raises the floor for a high-body-fat user', () {
      // 2.2 × 70 = 154 by bodyweight, but 2.4 × 68 = 163.2 by lean mass.
      final r = MacroCalculator.compute(
        const MacroInput(
          weightKg: 70,
          heightCm: 175,
          age: 28,
          sex: Sex.male,
          activityLevel: ActivityLevel.moderate,
          goalMode: GoalMode.cut,
          leanMassKg: 68,
        ),
      );
      expect(r.proteinFloorG, 163);
    });

    test('the ceiling binds when lean mass would push the floor above it', () {
      // An implausibly lean 60 kg user: 2.4 × 66 = 158.4 by lean mass, which
      // exceeds the 2.6 × 60 = 156 ceiling. The ceiling wins — beyond it there
      // is no further benefit and protein merely displaces other fuel.
      final r = MacroCalculator.compute(
        const MacroInput(
          weightKg: 60,
          heightCm: 170,
          age: 25,
          sex: Sex.male,
          activityLevel: ActivityLevel.active,
          goalMode: GoalMode.cut,
          leanMassKg: 66,
        ),
      );
      expect(r.proteinFloorG, 156);
    });
  });

  group('MacroCalculator — sex handling', () {
    test('female BMR uses the −161 constant', () {
      final r = MacroCalculator.compute(
        const MacroInput(
          weightKg: 65,
          heightCm: 165,
          age: 30,
          sex: Sex.female,
          activityLevel: ActivityLevel.moderate,
          goalMode: GoalMode.maintain,
        ),
      );
      // 650 + 1031.25 − 150 − 161 = 1370.25
      expect(r.bmr, 1370);
    });

    test('unspecified sex uses the midpoint, not a default sex', () {
      final unspecified = MacroCalculator.compute(
        const MacroInput(
          weightKg: 65,
          heightCm: 165,
          age: 30,
          sex: Sex.unspecified,
          activityLevel: ActivityLevel.moderate,
          goalMode: GoalMode.maintain,
        ),
      );
      expect(unspecified.bmr, 1453); // 1531.25 − 78
    });
  });

  group('MacroCalculator — determinism and totals', () {
    test('identical inputs produce identical output', () {
      const i = MacroInput(
        weightKg: 82.4,
        heightCm: 179.2,
        age: 34,
        sex: Sex.male,
        activityLevel: ActivityLevel.active,
        goalMode: GoalMode.cut,
        trainingDaysPerWeek: 5,
      );
      final a = MacroCalculator.compute(i);
      final b = MacroCalculator.compute(i);
      expect(a.trainingDay, b.trainingDay);
      expect(a.restDay, b.restDay);
      expect(a.projectedWeeklyChangeKg, b.projectedWeeklyChangeKg);
    });

    test('macronutrient energy reconstructs the calorie target within 2 %', () {
      const i = MacroInput(
        weightKg: 90.1,
        heightCm: 174.5,
        age: 21,
        sex: Sex.male,
        activityLevel: ActivityLevel.moderate,
        goalMode: GoalMode.cut,
        trainingDaysPerWeek: 6,
        leanMassKg: 61.9,
      );
      final r = MacroCalculator.compute(i);
      for (final t in [r.trainingDay, r.restDay]) {
        final derived = t.proteinG * 4 + t.carbsG * 4 + t.fatG * 9;
        expect((derived - t.kcal).abs() / t.kcal, lessThan(0.02));
      }
    });

    test('no output is ever NaN, infinite or negative', () {
      final extremes = <MacroInput>[
        const MacroInput(
          weightKg: 30,
          heightCm: 120,
          age: 18,
          sex: Sex.female,
          activityLevel: ActivityLevel.sedentary,
          goalMode: GoalMode.cut,
        ),
        const MacroInput(
          weightKg: 250,
          heightCm: 210,
          age: 70,
          sex: Sex.male,
          activityLevel: ActivityLevel.veryActive,
          goalMode: GoalMode.bulk,
          trainingDaysPerWeek: 7,
          weeklyRateTargetPct: 1.0,
        ),
      ];

      for (final i in extremes) {
        final r = MacroCalculator.compute(i);
        for (final v in <double>[
          r.bmr,
          r.tdee,
          r.trainingDay.kcal,
          r.trainingDay.proteinG,
          r.trainingDay.carbsG,
          r.trainingDay.fatG,
          r.restDay.kcal,
          r.restDay.proteinG,
          r.restDay.carbsG,
          r.restDay.fatG,
          r.proteinFloorG,
        ]) {
          expect(v.isFinite, isTrue, reason: 'value must be finite');
          expect(v, greaterThanOrEqualTo(0), reason: 'value must not be negative');
        }
        expect(r.waterMl, greaterThan(0));
      }
    });
  });
}
