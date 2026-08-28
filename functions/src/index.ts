/**
 * LifeDNA OS — Cloud Functions export surface.
 *
 * This file exports and nothing else. Every function's implementation lives in
 * its own module so that the deployment surface is a single reviewable list.
 *
 * Function inventory and operational parameters: docs/08-backend-architecture.md §2.
 */
import { initializeApp } from 'firebase-admin/app';
import { setGlobalOptions } from 'firebase-functions/v2';

initializeApp();

setGlobalOptions({
  region: process.env.FUNCTIONS_REGION ?? 'europe-west1',
  maxInstances: 20,
});

// ---------------------------------------------------------------- triggers --
export { onNutritionLogWrite } from './triggers/onNutritionLogWrite';

// ------------------------------------------------------------------ engines --
// Re-exported so the parity suite and any future callable share one
// implementation. These are pure functions with no Firebase dependency.
export {
  computeMacros,
  MACRO_ENGINE_VERSION,
} from './engines/nutrition/macroCalculator';
export {
  computeRecovery,
  RECOVERY_ENGINE_VERSION,
} from './engines/recovery/recoveryEngine';

/*
 * Remaining functions from docs/08 §2, scheduled by sprint:
 *
 *   Sprint 7   calendarConnect · calendarSync · calendarWriteEvent
 *   Sprint 8   healthSyncCommit · healthBackfillStart · notificationPlanner
 *   Sprint 9   onSessionFinalize · onBodyMetricWrite · dailyPlanBuilder
 *   Sprint 10  aiChat · aiStream · aiConfirmToolCall · aiFeedback
 *   Sprint 11  exportData · deleteAccount · accountPurge
 *   Sprint 13  recoveryEngine (scheduled) — the engine itself is already here
 *   Sprint 17  weeklyReport · monthlyReport
 *   Sprint 20  fitnessDnaEngine · insightGeneration
 *
 * Each has its contract fixed in docs/09-api-contracts.md, so they can be
 * built against a settled interface rather than a discovered one.
 */
