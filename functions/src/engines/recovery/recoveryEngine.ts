/**
 * The Recovery Engine — the authoritative implementation.
 *
 * Mirrored on the client at `app/lib/core/engines/recovery_engine.dart`; both
 * run the shared fixtures in `test/fixtures/engines/recovery/`.
 *
 * Specification: docs/12-recovery-engine.md.
 *
 * It answers exactly one question: how hard can I train today?
 */

import { roundHalfAwayFromZero } from '../../lib/rounding';

export type RecoveryBand = 'low' | 'moderate' | 'high' | 'insufficient_data';
export type TrainingAction = 'push' | 'proceed' | 'reduce' | 'rest';

export interface SleepInput {
  totalMinutes: number;
  timeInBedMinutes: number;
  goalMinutes?: number;
  deepMinutes?: number | null;
  remMinutes?: number | null;
  bedtimeStdDevMinutes?: number | null;
  wakeStdDevMinutes?: number | null;
  nightsOfHistory?: number;
}

export interface TrainingInput {
  acwr: number | null;
  yesterdayLoad: number;
  meanDailyLoad28d: number;
  yesterdaySessionRpe?: number | null;
  daysSinceLastSession?: number;
}

export interface ActivityInput {
  steps: number;
  stepGoal: number;
  activeMinutes: number;
  trainedYesterday?: boolean;
}

export interface PhysiologyInput {
  restingHrBpm?: number | null;
  baselineRestingHrBpm?: number | null;
  hrvMs?: number | null;
  baselineHrvMs?: number | null;
}

export interface PlannedSession {
  rpe: number;
  durationMinutes: number;
}

export interface RecoveryComponent {
  name: 'sleep' | 'training' | 'activity';
  score: number;
  weight: number;
  contribution: number;
  available: boolean;
}

export interface RecoveryResult {
  recoveryScore: number | null;
  band: RecoveryBand;
  readinessScore: number | null;
  sleepScore: number | null;
  components: RecoveryComponent[];
  missingInputs: string[];
  action: TrainingAction | null;
  detail: string;
  engineVersion: string;
}

export const RECOVERY_ENGINE_VERSION = 'recovery-1.2.0';

/** Default weights. Overridable via Remote Config (RECV-02). */
export const W_SLEEP = 0.4;
export const W_TRAINING = 0.4;
export const W_ACTIVITY = 0.2;

/**
 * Fewer than two available domains produces NO score, rather than a
 * confident-looking guess (RECV-07).
 */
export const MINIMUM_COMPONENTS = 2;

export function computeRecovery(args: {
  sleep?: SleepInput | null;
  training?: TrainingInput | null;
  activity?: ActivityInput | null;
  physiology?: PhysiologyInput;
  plannedSession?: PlannedSession | null;
}): RecoveryResult {
  const { sleep, training, activity, physiology = {}, plannedSession } = args;

  const missing: string[] = [];
  const sleepScore = sleep ? computeSleepScore(sleep) : null;
  const trainingScore = training ? computeTrainingScore(training) : null;
  const activityScore = activity ? computeActivityScore(activity) : null;

  if (sleepScore === null) missing.push('sleep');
  if (trainingScore === null) missing.push('training');
  if (activityScore === null) missing.push('activity');

  const availableCount = [sleepScore, trainingScore, activityScore].filter(
    (s) => s !== null,
  ).length;

  if (availableCount < MINIMUM_COMPONENTS) {
    return {
      recoveryScore: null,
      band: 'insufficient_data',
      readinessScore: null,
      sleepScore,
      components: [],
      missingInputs: missing,
      action: null,
      detail: insufficientDataMessage(missing),
      engineVersion: RECOVERY_ENGINE_VERSION,
    };
  }

  // Renormalize over what is actually available, so a missing domain does not
  // silently drag the score toward zero.
  let weightTotal = 0;
  if (sleepScore !== null) weightTotal += W_SLEEP;
  if (trainingScore !== null) weightTotal += W_TRAINING;
  if (activityScore !== null) weightTotal += W_ACTIVITY;

  const normSleep = sleepScore !== null ? W_SLEEP / weightTotal : 0;
  const normTraining = trainingScore !== null ? W_TRAINING / weightTotal : 0;
  const normActivity = activityScore !== null ? W_ACTIVITY / weightTotal : 0;

  const components: RecoveryComponent[] = [
    component('sleep', sleepScore, normSleep),
    component('training', trainingScore, normTraining),
    component('activity', activityScore, normActivity),
  ];

  let composite =
    (sleepScore ?? 0) * normSleep +
    (trainingScore ?? 0) * normTraining +
    (activityScore ?? 0) * normActivity;

  composite += physiologyAdjustment(physiology);

  const recovery = clamp(roundHalfAwayFromZero(composite), 0, 100);
  const band = bandFor(recovery);
  const readiness = computeReadiness(
    recovery,
    plannedSession ?? null,
    training?.meanDailyLoad28d ?? 0,
  );
  const action = actionFor(readiness ?? recovery, training?.acwr ?? null);

  return {
    recoveryScore: recovery,
    band,
    readinessScore: readiness,
    sleepScore,
    components,
    missingInputs: missing,
    action,
    detail: detailFor(action, recovery, readiness, sleepScore, training?.acwr ?? null),
    engineVersion: RECOVERY_ENGINE_VERSION,
  };
}

// ------------------------------------------------------------------- sleep --

export function computeSleepScore(s: SleepInput): number {
  const duration = sleepDuration(s);
  const consistency = sleepConsistency(s);
  const efficiency = sleepEfficiency(s);
  const stages = sleepStages(s);

  let sum = duration * 0.4;
  let weight = 0.4;

  if (consistency !== null) {
    sum += consistency * 0.25;
    weight += 0.25;
  }
  if (efficiency !== null) {
    sum += efficiency * 0.2;
    weight += 0.2;
  }
  if (stages !== null) {
    sum += stages * 0.15;
    weight += 0.15;
  }

  return clamp(roundHalfAwayFromZero(sum / weight), 0, 100);
}

/**
 * Under-sleeping is penalized ~2.2x harder than over-sleeping, because the
 * physiological cost is asymmetric. Long sleep is mildly penalized (it
 * correlates with poor quality or illness) but never below 60.
 */
function sleepDuration(s: SleepInput): number {
  const goal = s.goalMinutes ?? 480;
  if (goal <= 0) return 0;
  const ratio = s.totalMinutes / goal;
  if (ratio >= 0.95 && ratio <= 1.15) return 100;
  if (ratio < 0.95) return Math.max(0, 100 - (0.95 - ratio) * 220);
  return Math.max(60, 100 - (ratio - 1.15) * 100);
}

function sleepConsistency(s: SleepInput): number | null {
  if ((s.nightsOfHistory ?? 0) < 7) return null;
  const bed = s.bedtimeStdDevMinutes;
  const wake = s.wakeStdDevMinutes;
  if (bed === null || bed === undefined || wake === null || wake === undefined) {
    return null;
  }
  const sigma = (bed + wake) / 2;
  return clamp(100 - (sigma - 20) * 1.6, 0, 100);
}

function sleepEfficiency(s: SleepInput): number | null {
  if (s.timeInBedMinutes <= 0) return null;
  const pct = (s.totalMinutes / s.timeInBedMinutes) * 100;
  if (pct >= 90) return 100;
  if (pct >= 60) return (pct - 60) * 3.33;
  return 0;
}

/** Ideal bands: deep 13–23 %, REM 20–25 %. */
function sleepStages(s: SleepInput): number | null {
  const deep = s.deepMinutes;
  const rem = s.remMinutes;
  if (deep === null || deep === undefined) return null;
  if (rem === null || rem === undefined) return null;
  if (s.totalMinutes <= 0) return null;

  const deepPct = (deep / s.totalMinutes) * 100;
  const remPct = (rem / s.totalMinutes) * 100;
  const deepScore = clamp(100 - Math.abs(deepPct - 18) * 5, 0, 100);
  const remScore = clamp(100 - Math.abs(remPct - 22.5) * 5, 0, 100);
  return (deepScore + remScore) / 2;
}

// ---------------------------------------------------------------- training --

/** A plateau, not a peak: a wide productive band with penalties on both sides. */
export function computeTrainingScore(t: TrainingInput): number {
  const acwr = t.acwr;

  // Without enough history the ratio is meaningless, so return a neutral
  // score rather than penalizing a new user for having no chronic load.
  let base = 75;
  if (acwr !== null) {
    if (acwr < 0.6) base = 70;
    else if (acwr < 0.8) base = 85;
    else if (acwr < 1.3) base = 100;
    else if (acwr < 1.5) base = 75;
    else if (acwr < 1.8) base = 50;
    else base = 25;
  }

  let adjustment = 0;
  if (t.meanDailyLoad28d > 0 && t.yesterdayLoad > 1.5 * t.meanDailyLoad28d) {
    adjustment -= 15;
  }
  if ((t.yesterdaySessionRpe ?? 0) >= 9) adjustment -= 8;
  if ((t.daysSinceLastSession ?? 0) >= 2 && (acwr === null || acwr >= 0.8)) {
    adjustment += 10;
  }

  return clamp(roundHalfAwayFromZero(base + adjustment), 0, 100);
}

// ---------------------------------------------------------------- activity --

export function computeActivityScore(a: ActivityInput): number {
  if (a.stepGoal <= 0) return 0;
  const stepRatio = a.steps / a.stepGoal;

  let stepScore: number;
  if (stepRatio >= 1) stepScore = 100;
  else if (stepRatio >= 0.5) stepScore = stepRatio * 100;
  else stepScore = stepRatio * 80;

  const activeScore = clamp((a.activeMinutes / 45) * 100, 0, 100);
  let score = 0.6 * stepScore + 0.4 * activeScore;

  // A genuinely sedentary day is a recovery signal in its own right.
  if (a.steps < 3000 && !(a.trainedYesterday ?? false)) score -= 10;

  return clamp(roundHalfAwayFromZero(score), 0, 100);
}

// -------------------------------------------------------------- physiology --

/** Capped at ±10 so a noisy wearable reading can never dominate the score. */
function physiologyAdjustment(p: PhysiologyInput): number {
  let adjustment = 0;

  const rhr = p.restingHrBpm;
  const rhrBase = p.baselineRestingHrBpm;
  if (rhr !== null && rhr !== undefined && rhrBase !== null && rhrBase !== undefined) {
    const delta = rhr - rhrBase;
    if (delta <= -3) adjustment += 3;
    else if (delta >= 3 && delta <= 5) adjustment -= 4;
    else if (delta > 5) adjustment -= 8;
  }

  const hrv = p.hrvMs;
  const hrvBase = p.baselineHrvMs;
  if (hrv !== null && hrv !== undefined && hrvBase !== null && hrvBase !== undefined && hrvBase > 0) {
    const deltaPct = ((hrv - hrvBase) / hrvBase) * 100;
    if (deltaPct >= 10) adjustment += 4;
    else if (deltaPct <= -20) adjustment -= 9;
    else if (deltaPct <= -10) adjustment -= 5;
  }

  return clamp(adjustment, -10, 10);
}

// --------------------------------------------------------------- readiness --

/**
 * Recovery is backward-looking. Readiness asks the forward question: how
 * recovered am I relative to what today actually demands?
 */
function computeReadiness(
  recovery: number,
  planned: PlannedSession | null,
  meanDailyLoad28d: number,
): number | null {
  if (planned === null || meanDailyLoad28d <= 0) return recovery;
  const plannedLoad = planned.rpe * planned.durationMinutes;
  const demand = clamp(plannedLoad / meanDailyLoad28d, 0, 2.5);
  return clamp(roundHalfAwayFromZero(recovery - (demand - 1) * 18), 0, 100);
}

function actionFor(readiness: number, acwr: number | null): TrainingAction {
  if (readiness < 40 || (acwr !== null && acwr >= 1.8)) return 'rest';
  if (readiness < 65) return 'reduce';
  if (readiness >= 80 && (acwr === null || acwr < 1.3)) return 'push';
  return 'proceed';
}

export function bandFor(score: number): RecoveryBand {
  if (score <= 33) return 'low';
  if (score <= 66) return 'moderate';
  return 'high';
}

// -------------------------------------------------------------------- copy --

function detailFor(
  action: TrainingAction,
  recovery: number,
  readiness: number | null,
  sleepScore: number | null,
  acwr: number | null,
): string {
  const ratio = acwr === null ? null : acwr.toFixed(2);
  switch (action) {
    case 'push':
      return `Recovery ${recovery} with a balanced load ratio${
        ratio === null ? '' : ` of ${ratio}`
      }. This is the day to attempt a record.`;
    case 'proceed':
      return readiness !== null && readiness < recovery
        ? `Recovery is ${recovery}, but today's session is heavier than your average, so readiness lands at ${readiness}. Hit your target reps; save the record attempt for a lighter day.`
        : `Recovery ${recovery}${
            ratio === null ? '' : ` and a load ratio of ${ratio}`
          }. Train as planned.`;
    case 'reduce':
      return `Recovery is ${recovery}${
        sleepScore === null ? '' : ` with a sleep score of ${sleepScore}`
      }. Keep the compound work and drop the last set of each accessory.`;
    case 'rest':
      return `Recovery is ${recovery}${
        ratio === null ? '' : ` and your load ratio is ${ratio}`
      }. Training hard today costs more than it earns.`;
  }
}

/**
 * Names exactly what is missing. "Insufficient data" without saying what would
 * fix it is a dead end, and the flow rules forbid dead ends.
 */
function insufficientDataMessage(missing: string[]): string {
  if (missing.includes('sleep')) {
    return 'Recovery needs sleep data from at least 2 of the last 3 nights.';
  }
  const names = missing.map(domainLabel).join(' and ');
  return `Recovery needs at least two data sources. Still missing: ${names}.`;
}

function domainLabel(domain: string): string {
  switch (domain) {
    case 'sleep':
      return 'sleep';
    case 'training':
      return 'training history';
    case 'activity':
      return 'daily activity';
    default:
      return domain;
  }
}

function component(
  name: RecoveryComponent['name'],
  score: number | null,
  weight: number,
): RecoveryComponent {
  const available = score !== null;
  const roundedWeight = roundHalfAwayFromZero(weight * 100) / 100;
  return {
    name,
    score: score ?? 0,
    weight: roundedWeight,
    contribution: available
      ? roundHalfAwayFromZero((score ?? 0) * roundedWeight * 10) / 10
      : 0,
    available,
  };
}

function clamp(value: number, lo: number, hi: number): number {
  return Math.min(hi, Math.max(lo, value));
}
