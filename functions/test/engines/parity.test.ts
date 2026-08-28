/**
 * ENGINE PARITY — the TypeScript half.
 *
 * Executes the same fixtures as `app/test/unit/core/engines/parity_test.dart`.
 * See that file for why this duplication exists and why it is enforced
 * mechanically rather than by convention.
 */
import { readdirSync, readFileSync } from 'node:fs';
import { join } from 'node:path';

import { describe, expect, it } from 'vitest';

import {
  computeMacros,
  type MacroInput,
} from '../../src/engines/nutrition/macroCalculator';
import {
  computeRecovery,
  type ActivityInput,
  type PhysiologyInput,
  type PlannedSession,
  type SleepInput,
  type TrainingInput,
} from '../../src/engines/recovery/recoveryEngine';

const FIXTURE_ROOT = join(__dirname, '..', '..', '..', 'test', 'fixtures', 'engines');

interface Fixture<I, E> {
  id: string;
  engineVersion: string;
  input: I;
  expected: E;
}

function loadFixtures<I, E>(engine: string): Fixture<I, E>[] {
  const dir = join(FIXTURE_ROOT, engine);
  return readdirSync(dir)
    .filter((f) => f.endsWith('.json'))
    .sort()
    .map((f) => JSON.parse(readFileSync(join(dir, f), 'utf8')) as Fixture<I, E>);
}

describe('MacroCalculator parity', () => {
  const fixtures = loadFixtures<MacroInput, ReturnType<typeof computeMacros>>('macro');

  it('fixtures are present', () => {
    expect(fixtures.length).toBeGreaterThan(0);
  });

  for (const fixture of fixtures) {
    it(`macro/${fixture.id}`, () => {
      const actual = computeMacros(fixture.input);
      const want = fixture.expected;

      expect(actual.bmr).toBe(want.bmr);
      expect(actual.tdee).toBe(want.tdee);
      expect(actual.weeklyAverageTdee).toBe(want.weeklyAverageTdee);
      expect(actual.proteinFloorG).toBe(want.proteinFloorG);
      expect(actual.waterMl).toBe(want.waterMl);
      expect(actual.clamped).toBe(want.clamped);
      expect(actual.warnings).toEqual(want.warnings);
      expect(actual.projectedWeeklyChangeKg).toBeCloseTo(
        want.projectedWeeklyChangeKg,
        2,
      );
      expect(actual.trainingDay).toEqual(want.trainingDay);
      expect(actual.restDay).toEqual(want.restDay);
    });
  }
});

interface RecoveryFixtureInput {
  sleep?: SleepInput;
  training?: TrainingInput;
  activity?: ActivityInput;
  physiology?: PhysiologyInput;
  plannedSession?: PlannedSession;
}

describe('RecoveryEngine parity', () => {
  const fixtures =
    loadFixtures<RecoveryFixtureInput, ReturnType<typeof computeRecovery>>('recovery');

  it('fixtures are present', () => {
    expect(fixtures.length).toBeGreaterThan(0);
  });

  for (const fixture of fixtures) {
    it(`recovery/${fixture.id}`, () => {
      const actual = computeRecovery({
        sleep: fixture.input.sleep ?? null,
        training: fixture.input.training ?? null,
        activity: fixture.input.activity ?? null,
        physiology: fixture.input.physiology ?? {},
        plannedSession: fixture.input.plannedSession ?? null,
      });
      const want = fixture.expected;

      expect(actual.recoveryScore).toBe(want.recoveryScore);
      expect(actual.band).toBe(want.band);
      expect(actual.readinessScore).toBe(want.readinessScore);
      expect(actual.sleepScore).toBe(want.sleepScore);
      expect(actual.action).toBe(want.action);
      expect(actual.missingInputs).toEqual(want.missingInputs);
      expect(actual.components).toHaveLength(want.components.length);

      actual.components.forEach((component, i) => {
        const expectedComponent = want.components[i];
        expect(component.name).toBe(expectedComponent.name);
        expect(component.score).toBe(expectedComponent.score);
        expect(component.weight).toBeCloseTo(expectedComponent.weight, 3);
        expect(component.contribution).toBeCloseTo(
          expectedComponent.contribution,
          1,
        );
        expect(component.available).toBe(expectedComponent.available);
      });

      if (want.detail) {
        expect(actual.detail).toBe(want.detail);
      }
    });
  }
});

describe('safety ceilings are enforced by the engine, not the UI', () => {
  it('never returns a deficit steeper than 25 % of weekly-average expenditure', () => {
    const result = computeMacros({
      weightKg: 140,
      heightCm: 180,
      age: 30,
      sex: 'male',
      activityLevel: 'sedentary',
      goalMode: 'cut',
      trainingDaysPerWeek: 0,
      weeklyRateTargetPct: 5.0,
    });
    const deficit = result.tdee - result.restDay.kcal;
    expect(deficit).toBeLessThanOrEqual(result.weeklyAverageTdee * 0.25 + 1);
    expect(result.clamped).toBe(true);
  });

  it('never returns energy below the absolute floor', () => {
    for (const sex of ['male', 'female'] as const) {
      const result = computeMacros({
        weightKg: 45,
        heightCm: 155,
        age: 60,
        sex,
        activityLevel: 'sedentary',
        goalMode: 'cut',
        trainingDaysPerWeek: 0,
        weeklyRateTargetPct: 1.0,
      });
      expect(result.restDay.kcal).toBeGreaterThanOrEqual(
        sex === 'female' ? 1200 : 1500,
      );
    }
  });

  it('never emits a recovery score from fewer than two domains', () => {
    const result = computeRecovery({
      sleep: { totalMinutes: 450, timeInBedMinutes: 480 },
    });
    expect(result.recoveryScore).toBeNull();
    expect(result.band).toBe('insufficient_data');
    // The message must say what would fix it — never a bare "insufficient data".
    expect(result.detail).toContain('sleep data');
  });

  it('produces no NaN or out-of-range score across an input sweep', () => {
    for (let minutes = 0; minutes <= 900; minutes += 60) {
      for (const acwr of [0, 0.5, 1.0, 1.5, 2.0, 3.0]) {
        for (let steps = 0; steps <= 25000; steps += 5000) {
          const result = computeRecovery({
            sleep: { totalMinutes: minutes, timeInBedMinutes: minutes + 40 },
            training: {
              acwr,
              yesterdayLoad: 400,
              meanDailyLoad28d: 350,
            },
            activity: { steps, stepGoal: 10000, activeMinutes: 30 },
          });
          expect(Number.isFinite(result.recoveryScore)).toBe(true);
          expect(result.recoveryScore).toBeGreaterThanOrEqual(0);
          expect(result.recoveryScore).toBeLessThanOrEqual(100);
        }
      }
    }
  });
});
