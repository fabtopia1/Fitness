import 'dart:math' as math;

import 'package:lifedna/shared/enums/enums.dart';
import 'package:lifedna/shared/value_objects/macros.dart';

/// Input to [MacroCalculator]. Pure data — no I/O, no clock, no randomness.
class MacroInput {
  const MacroInput({
    required this.weightKg,
    required this.heightCm,
    required this.age,
    required this.sex,
    required this.activityLevel,
    required this.goalMode,
    this.trainingDaysPerWeek = 4,
    this.leanMassKg,
    this.weeklyRateTargetPct = 0.75,
    this.trainingDayBonusKcal = 300,
  });

  final double weightKg;
  final double heightCm;
  final int age;
  final Sex sex;
  final ActivityLevel activityLevel;
  final GoalMode goalMode;
  final int trainingDaysPerWeek;

  /// When known (from a body-composition measurement), the protein floor uses
  /// lean mass, which is the more defensible basis.
  final double? leanMassKg;

  /// Desired rate of body-weight change, as a percentage of bodyweight per week.
  /// Always positive; direction comes from [goalMode].
  final double weeklyRateTargetPct;

  /// Additional energy attributed to a training day, before the goal delta.
  final double trainingDayBonusKcal;
}

/// The complete, explainable output of a targets calculation.
class MacroResult {
  const MacroResult({
    required this.bmr,
    required this.tdee,
    required this.trainingDay,
    required this.restDay,
    required this.proteinFloorG,
    required this.waterMl,
    required this.projectedWeeklyChangeKg,
    required this.clamped,
    required this.warnings,
    required this.engineVersion,
  });

  final double bmr;
  final double tdee;
  final MacroTargets trainingDay;
  final MacroTargets restDay;
  final double proteinFloorG;
  final int waterMl;

  /// Signed: negative while cutting.
  final double projectedWeeklyChangeKg;

  /// True when a requested rate or deficit was reduced to the safe maximum.
  /// The UI must display the warning rather than silently accepting the value.
  final bool clamped;
  final List<String> warnings;
  final String engineVersion;

  MacroTargets forDayType(DayType type) =>
      type == DayType.training ? trainingDay : restDay;
}

/// Computes energy and macronutrient targets.
///
/// Specification: docs/01-prd.md §6.2. This implementation is mirrored in
/// TypeScript at `functions/src/engines/nutrition/macroCalculator.ts`; both are
/// validated against the shared fixtures in `test/fixtures/engines/macro/`.
///
/// Deliberately free of any dependency so it can be exercised exhaustively in a
/// unit test and reasoned about by anyone reading the spec.
abstract final class MacroCalculator {
  static const String version = 'macro-1.0.0';

  /// Energy density of body tissue, used for rate projections.
  static const double _kcalPerKgBodyMass = 7700;

  /// Safety ceilings. These are hard limits, not preferences (docs/19 §8).
  static const double maxDeficitFraction = 0.25;
  static const double maxDeficitKcal = 1000;
  static const double maxWeeklyRatePct = 1.0;
  static const double minKcalMale = 1500;
  static const double minKcalFemale = 1200;

  static MacroResult compute(MacroInput input) {
    final warnings = <String>[];
    var clamped = false;

    // ---- 1. Basal metabolic rate — Mifflin-St Jeor -------------------------
    final bmr = _bmr(input);

    // ---- 2. Total daily energy expenditure ---------------------------------
    final baseTdee = bmr * input.activityLevel.factor;

    // Training days carry an additional session cost, capped so that a large
    // self-reported session cannot inflate the target without bound.
    final trainingBonus = math.min(input.trainingDayBonusKcal, 500.0);

    // ---- 3. Goal delta, with the rate the user asked for -------------------
    var requestedRatePct = input.weeklyRateTargetPct.abs();
    if (requestedRatePct > maxWeeklyRatePct) {
      requestedRatePct = maxWeeklyRatePct;
      clamped = true;
      warnings.add('RATE_CLAMPED_TO_SAFE_MAXIMUM');
    }

    double goalDeltaKcal;
    switch (input.goalMode) {
      case GoalMode.maintain:
        goalDeltaKcal = 0;
      case GoalMode.cut:
        // Daily deficit implied by the requested weekly rate.
        final weeklyKg = input.weightKg * requestedRatePct / 100;
        goalDeltaKcal = -(weeklyKg * _kcalPerKgBodyMass) / 7;
      case GoalMode.bulk:
        final weeklyKg = input.weightKg * math.min(requestedRatePct, 0.5) / 100;
        goalDeltaKcal = (weeklyKg * _kcalPerKgBodyMass) / 7;
    }

    // ---- 4. Apply the deficit ceilings -------------------------------------
    //
    // The percentage cap is measured against the WEEKLY AVERAGE expenditure,
    // not the rest-day figure. A deficit is a weekly-average concept, and
    // capping against the rest day would spuriously clamp anyone who trains
    // most days — exactly the users for whom the target matters most.
    final weeklyAverageTdee =
        baseTdee + trainingBonus * (input.trainingDaysPerWeek.clamp(0, 7) / 7);

    if (goalDeltaKcal < 0) {
      final fractionCap = -(weeklyAverageTdee * maxDeficitFraction);
      if (goalDeltaKcal < fractionCap) {
        goalDeltaKcal = fractionCap;
        clamped = true;
        warnings.add('DEFICIT_CLAMPED_TO_25_PERCENT');
      }
      if (goalDeltaKcal < -maxDeficitKcal) {
        goalDeltaKcal = -maxDeficitKcal;
        clamped = true;
        warnings.add('DEFICIT_CLAMPED_TO_1000_KCAL');
      }
    }

    // ---- 5. Day-type energy targets ---------------------------------------
    var trainingKcal = baseTdee + trainingBonus + goalDeltaKcal;
    var restKcal = baseTdee + goalDeltaKcal;

    final absoluteFloor =
        input.sex == Sex.female ? minKcalFemale : minKcalMale;
    if (restKcal < absoluteFloor) {
      restKcal = absoluteFloor;
      clamped = true;
      warnings.add('KCAL_RAISED_TO_ABSOLUTE_FLOOR');
    }
    if (trainingKcal < absoluteFloor) {
      trainingKcal = absoluteFloor;
      clamped = true;
    }

    // ---- 6. Protein floor --------------------------------------------------
    final proteinFloorG = _proteinFloor(input);

    // ---- 7. Fat, then carbohydrate as the remainder ------------------------
    final trainingTargets =
        _distribute(trainingKcal, proteinFloorG, input.weightKg);
    final restTargets = _distribute(restKcal, proteinFloorG, input.weightKg);

    // ---- 8. Hydration ------------------------------------------------------
    final waterMl = _waterTarget(input);

    // ---- 9. Projected rate, recomputed from the CLAMPED targets ------------
    // This is what the user will actually achieve, not what they asked for.
    final weeklyDeficit = _weeklyEnergyBalance(
      trainingKcal: trainingKcal,
      restKcal: restKcal,
      tdeeTraining: baseTdee + trainingBonus,
      tdeeRest: baseTdee,
      trainingDays: input.trainingDaysPerWeek,
    );
    final projectedWeeklyChangeKg = weeklyDeficit / _kcalPerKgBodyMass;

    return MacroResult(
      bmr: _round(bmr),
      tdee: _round(baseTdee),
      trainingDay: trainingTargets,
      restDay: restTargets,
      proteinFloorG: proteinFloorG,
      waterMl: waterMl,
      projectedWeeklyChangeKg:
          (projectedWeeklyChangeKg * 100).roundToDouble() / 100,
      clamped: clamped,
      warnings: List.unmodifiable(warnings),
      engineVersion: version,
    );
  }

  // -------------------------------------------------------------------------

  /// Mifflin-St Jeor. Chosen over Harris-Benedict for its better validation in
  /// modern populations.
  static double _bmr(MacroInput i) {
    final base = 10 * i.weightKg + 6.25 * i.heightCm - 5 * i.age;
    return switch (i.sex) {
      Sex.male => base + 5,
      Sex.female => base - 161,
      // Without a stated sex, use the midpoint rather than defaulting to either.
      Sex.unspecified => base - 78,
    };
  }

  /// The absolute daily protein minimum, in grams.
  ///
  /// Goal-aware by design: protein requirement rises in an energy deficit,
  /// because protein is the single largest modifiable lever protecting lean
  /// mass while calories are restricted. Using one maintenance figure across
  /// all three modes would systematically under-prescribe exactly the users
  /// who need it most.
  ///
  ///   cut       2.2 g/kg bodyweight
  ///   maintain  1.8 g/kg bodyweight
  ///   bulk      1.8 g/kg bodyweight
  ///
  /// bounded below by 2.4 g/kg of lean mass when lean mass is known, and above
  /// by 2.6 g/kg of bodyweight — beyond which there is no further benefit and
  /// the target simply displaces other macronutrients.
  static double _proteinFloor(MacroInput i) {
    final perKg = switch (i.goalMode) {
      GoalMode.cut => 2.2,
      GoalMode.maintain => 1.8,
      GoalMode.bulk => 1.8,
    };
    final byBodyweight = perKg * i.weightKg;
    final byLean = i.leanMassKg != null ? 2.4 * i.leanMassKg! : 0.0;
    final floor = math.max(byBodyweight, byLean);
    final ceiling = 2.6 * i.weightKg;
    return math.min(floor, ceiling).roundToDouble();
  }

  /// Fat is set as the larger of an absolute per-kg minimum and a share of
  /// energy; carbohydrate takes whatever energy remains.
  static MacroTargets _distribute(
    double kcal,
    double proteinG,
    double weightKg,
  ) {
    final proteinKcal = proteinG * 4;

    final fatByWeight = 0.7 * weightKg;
    final fatByEnergy = kcal * 0.20 / 9;
    var fatG = math.max(fatByWeight, fatByEnergy);

    var carbKcal = kcal - proteinKcal - fatG * 9;

    // If protein and the fat minimum already exceed the energy budget, reduce
    // fat toward its per-kg minimum rather than cutting protein, which is the
    // macronutrient the goal depends on.
    if (carbKcal < 0) {
      fatG = math.max(0.5 * weightKg, (kcal - proteinKcal) / 9 * 0.9);
      carbKcal = math.max(0.0, kcal - proteinKcal - fatG * 9);
    }

    return MacroTargets(
      kcal: _round(kcal),
      proteinG: proteinG,
      carbsG: _round(carbKcal / 4),
      fatG: _round(fatG),
      proteinFloorG: proteinG,
    );
  }

  /// 35 ml/kg baseline, plus 500 ml per training day averaged across the week,
  /// rounded to the nearest 250 ml so the number matches a real container.
  static int _waterTarget(MacroInput i) {
    final base = i.weightKg * 35;
    final trainingAdd = 500 * (i.trainingDaysPerWeek / 7);
    return ((base + trainingAdd) / 250).round() * 250;
  }

  static double _weeklyEnergyBalance({
    required double trainingKcal,
    required double restKcal,
    required double tdeeTraining,
    required double tdeeRest,
    required int trainingDays,
  }) {
    final t = trainingDays.clamp(0, 7).toInt();
    final r = 7 - t;
    return (trainingKcal - tdeeTraining) * t + (restKcal - tdeeRest) * r;
  }

  static double _round(double v) => v.roundToDouble();
}
