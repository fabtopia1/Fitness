/**
 * Energy and macronutrient targets.
 *
 * THIS FILE IS A MIRROR of `app/lib/core/engines/macro_calculator.dart`.
 * Both implementations are executed against the shared fixtures in
 * `test/fixtures/engines/macro/`, and a divergence fails both builds.
 *
 * Why two implementations exist at all: the client copy lets the UI recompute
 * instantly and offline when a user edits their weight or goal; the server copy
 * is authoritative for what gets stored. See docs/02 §5.2.
 *
 * Specification: docs/01-prd.md §6.2.
 */

import { roundHalfAwayFromZero, roundTo } from '../../lib/rounding';

export type Sex = 'male' | 'female' | 'unspecified';
export type GoalMode = 'cut' | 'maintain' | 'bulk';
export type ActivityLevel =
  | 'sedentary'
  | 'light'
  | 'moderate'
  | 'active'
  | 'very_active';

export const ACTIVITY_FACTORS: Record<ActivityLevel, number> = {
  sedentary: 1.2,
  light: 1.375,
  moderate: 1.55,
  active: 1.725,
  very_active: 1.9,
};

export interface MacroInput {
  weightKg: number;
  heightCm: number;
  age: number;
  sex: Sex;
  activityLevel: ActivityLevel;
  goalMode: GoalMode;
  trainingDaysPerWeek?: number;
  leanMassKg?: number | null;
  weeklyRateTargetPct?: number;
  trainingDayBonusKcal?: number;
}

export interface MacroTargets {
  kcal: number;
  proteinG: number;
  carbsG: number;
  fatG: number;
  proteinFloorG: number;
}

export interface MacroResult {
  bmr: number;
  tdee: number;
  weeklyAverageTdee: number;
  trainingDay: MacroTargets;
  restDay: MacroTargets;
  proteinFloorG: number;
  waterMl: number;
  projectedWeeklyChangeKg: number;
  clamped: boolean;
  warnings: string[];
  engineVersion: string;
}

export const MACRO_ENGINE_VERSION = 'macro-1.0.0';

/** Energy density of body tissue, used for rate projections. */
const KCAL_PER_KG_BODY_MASS = 7700;

/** Safety ceilings. Hard limits, not preferences (docs/19 §8). */
export const MAX_DEFICIT_FRACTION = 0.25;
export const MAX_DEFICIT_KCAL = 1000;
export const MAX_WEEKLY_RATE_PCT = 1.0;
export const MIN_KCAL_MALE = 1500;
export const MIN_KCAL_FEMALE = 1200;

export function computeMacros(input: MacroInput): MacroResult {
  const warnings: string[] = [];
  let clamped = false;

  const trainingDaysPerWeek = clampInt(input.trainingDaysPerWeek ?? 4, 0, 7);
  const leanMassKg = input.leanMassKg ?? null;

  // ---- 1. Basal metabolic rate — Mifflin-St Jeor ---------------------------
  const bmr = basalMetabolicRate(input);

  // ---- 2. Total daily energy expenditure -----------------------------------
  const baseTdee = bmr * ACTIVITY_FACTORS[input.activityLevel];
  const trainingBonus = Math.min(input.trainingDayBonusKcal ?? 300, 500);

  // ---- 3. Goal delta, derived from the requested rate ----------------------
  let requestedRatePct = Math.abs(input.weeklyRateTargetPct ?? 0.75);
  if (requestedRatePct > MAX_WEEKLY_RATE_PCT) {
    requestedRatePct = MAX_WEEKLY_RATE_PCT;
    clamped = true;
    warnings.push('RATE_CLAMPED_TO_SAFE_MAXIMUM');
  }

  let goalDeltaKcal: number;
  switch (input.goalMode) {
    case 'maintain':
      goalDeltaKcal = 0;
      break;
    case 'cut': {
      const weeklyKg = (input.weightKg * requestedRatePct) / 100;
      goalDeltaKcal = -(weeklyKg * KCAL_PER_KG_BODY_MASS) / 7;
      break;
    }
    case 'bulk': {
      const weeklyKg =
        (input.weightKg * Math.min(requestedRatePct, 0.5)) / 100;
      goalDeltaKcal = (weeklyKg * KCAL_PER_KG_BODY_MASS) / 7;
      break;
    }
  }

  // ---- 4. Deficit ceilings -------------------------------------------------
  //
  // Measured against the WEEKLY AVERAGE expenditure, not the rest-day figure.
  // A deficit is a weekly-average concept, and capping against the rest day
  // spuriously clamps anyone who trains most days.
  const weeklyAverageTdee =
    baseTdee + trainingBonus * (trainingDaysPerWeek / 7);

  if (goalDeltaKcal < 0) {
    const fractionCap = -(weeklyAverageTdee * MAX_DEFICIT_FRACTION);
    if (goalDeltaKcal < fractionCap) {
      goalDeltaKcal = fractionCap;
      clamped = true;
      warnings.push('DEFICIT_CLAMPED_TO_25_PERCENT');
    }
    if (goalDeltaKcal < -MAX_DEFICIT_KCAL) {
      goalDeltaKcal = -MAX_DEFICIT_KCAL;
      clamped = true;
      warnings.push('DEFICIT_CLAMPED_TO_1000_KCAL');
    }
  }

  // ---- 5. Day-type energy targets -----------------------------------------
  let trainingKcal = baseTdee + trainingBonus + goalDeltaKcal;
  let restKcal = baseTdee + goalDeltaKcal;

  const absoluteFloor =
    input.sex === 'female' ? MIN_KCAL_FEMALE : MIN_KCAL_MALE;
  if (restKcal < absoluteFloor) {
    restKcal = absoluteFloor;
    clamped = true;
    warnings.push('KCAL_RAISED_TO_ABSOLUTE_FLOOR');
  }
  if (trainingKcal < absoluteFloor) {
    trainingKcal = absoluteFloor;
    clamped = true;
  }

  // ---- 6. Protein floor ----------------------------------------------------
  const proteinFloorG = proteinFloor(input.goalMode, input.weightKg, leanMassKg);

  // ---- 7. Fat, then carbohydrate as the remainder --------------------------
  const trainingDay = distribute(trainingKcal, proteinFloorG, input.weightKg);
  const restDay = distribute(restKcal, proteinFloorG, input.weightKg);

  // ---- 8. Hydration --------------------------------------------------------
  const waterMl =
    roundHalfAwayFromZero(
      (input.weightKg * 35 + 500 * (trainingDaysPerWeek / 7)) / 250,
    ) * 250;

  // ---- 9. Projected rate, recomputed from the CLAMPED targets --------------
  const weeklyBalance =
    (trainingKcal - (baseTdee + trainingBonus)) * trainingDaysPerWeek +
    (restKcal - baseTdee) * (7 - trainingDaysPerWeek);

  return {
    bmr: roundHalfAwayFromZero(bmr),
    tdee: roundHalfAwayFromZero(baseTdee),
    weeklyAverageTdee: roundHalfAwayFromZero(weeklyAverageTdee),
    trainingDay,
    restDay,
    proteinFloorG,
    waterMl,
    // Negative for every user in a deficit, so this must not use the
    // platform rounding primitive. See lib/rounding.ts.
    projectedWeeklyChangeKg: roundTo(weeklyBalance / KCAL_PER_KG_BODY_MASS, 2),
    clamped,
    warnings,
    engineVersion: MACRO_ENGINE_VERSION,
  };
}

/**
 * Mifflin-St Jeor. Chosen over Harris-Benedict for its better validation in
 * modern populations.
 */
function basalMetabolicRate(i: MacroInput): number {
  const base = 10 * i.weightKg + 6.25 * i.heightCm - 5 * i.age;
  switch (i.sex) {
    case 'male':
      return base + 5;
    case 'female':
      return base - 161;
    // Without a stated sex, use the midpoint rather than defaulting to either.
    case 'unspecified':
      return base - 78;
  }
}

/**
 * The absolute daily protein minimum, in grams.
 *
 * Goal-aware by design: protein requirement rises in an energy deficit,
 * because protein is the single largest modifiable lever protecting lean mass
 * while calories are restricted.
 */
function proteinFloor(
  goalMode: GoalMode,
  weightKg: number,
  leanMassKg: number | null,
): number {
  const perKg = goalMode === 'cut' ? 2.2 : 1.8;
  const byBodyweight = perKg * weightKg;
  const byLean = leanMassKg !== null ? 2.4 * leanMassKg : 0;
  const floor = Math.max(byBodyweight, byLean);
  const ceiling = 2.6 * weightKg;
  return roundHalfAwayFromZero(Math.min(floor, ceiling));
}

/**
 * Fat is the larger of a per-kg minimum and a share of energy; carbohydrate
 * takes whatever energy remains.
 */
function distribute(
  kcal: number,
  proteinG: number,
  weightKg: number,
): MacroTargets {
  const proteinKcal = proteinG * 4;

  let fatG = Math.max(0.7 * weightKg, (kcal * 0.2) / 9);
  let carbKcal = kcal - proteinKcal - fatG * 9;

  // If protein and the fat minimum already exceed the budget, reduce fat
  // toward its per-kg minimum rather than cutting protein — protein is the
  // macronutrient the goal depends on.
  if (carbKcal < 0) {
    fatG = Math.max(0.5 * weightKg, ((kcal - proteinKcal) / 9) * 0.9);
    carbKcal = Math.max(0, kcal - proteinKcal - fatG * 9);
  }

  return {
    kcal: roundHalfAwayFromZero(kcal),
    proteinG,
    carbsG: roundHalfAwayFromZero(carbKcal / 4),
    fatG: roundHalfAwayFromZero(fatG),
    proteinFloorG: proteinG,
  };
}

function clampInt(value: number, lo: number, hi: number): number {
  return Math.min(hi, Math.max(lo, roundHalfAwayFromZero(value)));
}
