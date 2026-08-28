import { getFirestore, FieldValue } from 'firebase-admin/firestore';
import { onDocumentWritten } from 'firebase-functions/v2/firestore';

import { hashUid, log } from '../lib/logger';

/**
 * Maintains `users/{uid}/daily_stats/{localDate}.nutrition`.
 *
 * THE ROLLUP IS RECOMPUTED FROM SOURCE, NOT INCREMENTED.
 *
 * Firestore triggers are at-least-once. `FieldValue.increment` is faster but
 * double-counts on a redelivery and, once wrong, stays wrong with no way to
 * detect it. A day holds at most ~30 nutrition entries, so a full recompute is
 * cheap AND self-healing: a rollup corrupted by any means repairs itself on
 * the next write. See docs/08 §8.
 */
export const onNutritionLogWrite = onDocumentWritten(
  {
    document: 'users/{uid}/nutrition_logs/{logId}',
    region: 'europe-west1',
    memory: '256MiB',
  },
  async (event) => {
    const started = Date.now();
    const uid = event.params.uid as string;

    const before = event.data?.before.data();
    const after = event.data?.after.data();
    const localDate = (after?.localDate ?? before?.localDate) as
      | string
      | undefined;

    if (!localDate) {
      log.warn({ function: 'onNutritionLogWrite', outcome: 'error',
                 uidHash: hashUid(uid), errorType: 'missing_local_date' });
      return;
    }

    const db = getFirestore();
    const logsRef = db.collection(`users/${uid}/nutrition_logs`);
    const statsRef = db.doc(`users/${uid}/daily_stats/${localDate}`);

    await db.runTransaction(async (tx) => {
      const snapshot = await tx.get(
        logsRef.where('localDate', '==', localDate),
      );

      let kcal = 0;
      let proteinG = 0;
      let carbsG = 0;
      let fatG = 0;
      const bySlot: Record<string, { kcal: number; proteinG: number }> = {};

      for (const doc of snapshot.docs) {
        const macros = (doc.get('macros') ?? {}) as Record<string, number>;
        const slot = (doc.get('mealSlot') as string) ?? 'snack';
        kcal += macros.kcal ?? 0;
        proteinG += macros.proteinG ?? 0;
        carbsG += macros.carbsG ?? 0;
        fatG += macros.fatG ?? 0;

        const bucket = bySlot[slot] ?? { kcal: 0, proteinG: 0 };
        bucket.kcal += macros.kcal ?? 0;
        bucket.proteinG += macros.proteinG ?? 0;
        bySlot[slot] = bucket;
      }

      const targets = await readTargets(tx, uid, localDate);

      tx.set(
        statsRef,
        {
          localDate,
          nutrition: {
            kcal: Math.round(kcal),
            proteinG: Math.round(proteinG),
            carbsG: Math.round(carbsG),
            fatG: Math.round(fatG),
            ...targets,
            entryCount: snapshot.size,
            bySlot,
            adherencePct: adherence(kcal, targets.targetKcal),
          },
          updatedAt: FieldValue.serverTimestamp(),
        },
        { merge: true },
      );
    });

    log.info({
      function: 'onNutritionLogWrite',
      uidHash: hashUid(uid),
      outcome: 'ok',
      latencyMs: Date.now() - started,
    });
  },
);

interface DayTargets {
  targetKcal: number;
  targetProteinG: number;
  targetCarbsG: number;
  targetFatG: number;
  proteinFloorG: number;
}

async function readTargets(
  tx: FirebaseFirestore.Transaction,
  uid: string,
  localDate: string,
): Promise<DayTargets> {
  const db = getFirestore();
  const user = await tx.get(db.doc(`users/${uid}`));
  const targets = (user.get('targets') ?? {}) as Record<string, unknown>;

  // Day type follows the user's program, so the same intake is measured
  // against the right target on a training day and a rest day.
  const plan = await tx.get(db.doc(`users/${uid}/daily_plans/${localDate}`));
  const dayType = (plan.get('dayType') as string) ?? 'rest';
  const source = (targets[dayType === 'training' ? 'trainingDay' : 'restDay'] ??
    {}) as Record<string, number>;

  return {
    targetKcal: source.kcal ?? 0,
    targetProteinG: source.proteinG ?? 0,
    targetCarbsG: source.carbsG ?? 0,
    targetFatG: source.fatG ?? 0,
    proteinFloorG: (targets.proteinFloorG as number) ?? 0,
  };
}

/** Deviation in EITHER direction reduces adherence — over is not a win. */
function adherence(consumed: number, target: number): number {
  if (target <= 0) return 0;
  const deviation = Math.abs(consumed - target) / target;
  return Math.max(0, Math.round((1 - deviation) * 1000) / 10);
}
