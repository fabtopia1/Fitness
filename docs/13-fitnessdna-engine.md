# LifeDNA OS — FitnessDNA Engine

**Version:** `dna-1.0.0`
**Phase:** 3 (architecture and rule set are built in Phase 1 so insights can ship early in
degraded form)
**Owner:** AI Lead — safety sign-off required

---

## 1. What makes this the product's unique innovation

Every competitor analyses one domain. FitnessDNA analyses the **intersections**, because
that is where the actionable truth lives:

- Sleep debt → strength regression, on a ~5-day lag.
- Calendar density → training adherence → volume → body-composition trajectory.
- Protein adherence → lean-mass retention during a deficit.
- Training load spike → sleep disruption → recovery collapse → missed sessions.

No single-domain app can see any of these. That is the moat.

---

## 2. Architecture

```
                    NIGHTLY, PER USER (local 03:15)
┌──────────────────────────────────────────────────────────────────────┐
│ 1. SIGNAL EXTRACTION                                                 │
│    28 days of daily_stats + recovery_data + sleep_data + sessions    │
│    → DailySignalVector[] (normalized, gap-marked, unit-canonical)    │
└─────────────────────────────┬────────────────────────────────────────┘
                              ▼
┌──────────────────────────────────────────────────────────────────────┐
│ 2. RULE ENGINE            (pure, deterministic, ~30 rules)           │
│    each rule: (signals) → CandidateInsight | null                    │
│    each carries: type · severity · confidence · impact · evidence ·  │
│                  action · window                                     │
└─────────────────────────────┬────────────────────────────────────────┘
                              ▼
┌──────────────────────────────────────────────────────────────────────┐
│ 3. RANKING                                                           │
│    score = impact × confidence × recency × userRelevance             │
│    dedup by type, suppress dismissed-within-7-days, cap at N         │
└─────────────────────────────┬────────────────────────────────────────┘
                              ▼
┌──────────────────────────────────────────────────────────────────────┐
│ 4. PHRASING               (LLM, strict JSON schema, ONE batched call)│
│    input: ranked candidates with their computed numbers              │
│    output: headline + body per insight — numbers are INJECTED,       │
│            never generated. Falls back to templates on failure.      │
└─────────────────────────────┬────────────────────────────────────────┘
                              ▼
┌──────────────────────────────────────────────────────────────────────┐
│ 5. PERSIST + NOTIFY                                                  │
│    write users/{uid}/insights/{id}  (id = sha256(uid|rule|window))   │
│    top insight → 07:30 notification if the category is enabled       │
└──────────────────────────────────────────────────────────────────────┘
```

---

## 3. The signal vector

```typescript
interface DailySignalVector {
  localDate: string;

  nutrition: {
    kcal: number | null; kcalTarget: number;
    proteinG: number | null; proteinFloorG: number;
    carbsG: number | null; fatG: number | null;
    adherencePct: number | null; logged: boolean;
  };
  hydration: { ml: number | null; targetMl: number };
  training: {
    performed: boolean; volumeKg: number | null; sets: number | null;
    load: number | null; sessionRpe: number | null;
    byMuscle: Record<MuscleGroup, number>;
    prCount: number;
  };
  sleep: {
    minutes: number | null; score: number | null;
    bedtimeMinutes: number | null; wakeMinutes: number | null;
    efficiency: number | null;
  };
  recovery: { score: number | null; readiness: number | null; acwr: number | null };
  activity: { steps: number | null; activeMinutes: number | null };
  body: { weightKg: number | null; weightEwmaKg: number | null; bodyFatPct: number | null };
  supplements: { taken: number; scheduled: number };
  tasks: { completed: number; created: number; overdue: number };
  calendar: { eventCount: number; busyMinutes: number };

  // Every field is explicitly nullable. A missing day is a gap, never a zero.
}
```

**Derived aggregates** available to every rule:
`mean7d · mean28d · stdev28d · trend7d (OLS slope) · deltaPct(7d vs 28d) · daysWithData ·
consecutiveDaysMissing · ewma(halfLife)`

---

## 4. Rule set

Every rule is a pure function with the same signature, lives in its own file, and has its
own unit tests with hand-computed fixtures.

```typescript
type Rule = (s: SignalWindow, ctx: UserContext) => CandidateInsight | null;
```

### 4.1 Nutrition rules

| Rule | Fires when | Severity | Action |
|---|---|---|---|
| `PROTEIN_FLOOR_MISS` | mean7d protein < 0.9 × floor AND ≥ 4 of 7 days below floor | medium | Log a high-protein template |
| `CALORIE_UNDERSHOOT` | mean7d kcal < 0.85 × target AND weight rate > 1.1 %/wk | high | Increase calories by a computed amount |
| `CALORIE_OVERSHOOT` | mean7d kcal > 1.10 × target AND goal = cut AND weight trend ≥ 0 | medium | Review portions; show the 3 largest contributors |
| `LOGGING_LAPSE` | ≥ 3 of last 7 days unlogged | low | One-tap "copy yesterday" |
| `WEEKEND_DRIFT` | Sat/Sun mean kcal > weekday mean × 1.20 over 3 weeks | low | Plan weekend meals |
| `HYDRATION_SHORTFALL` | mean7d water < 0.75 × target | low | Add a hydration reminder |
| `FIBER_LOW` | mean7d fiber < 20 g over 14 days | info | Suggest high-fiber swaps |

### 4.2 Training rules

| Rule | Fires when | Severity | Action |
|---|---|---|---|
| `READY_FOR_PR` | recovery ≥ 80 AND readiness ≥ 75 AND e1RM trend28d > +2 % AND last 2 sessions hit target reps at RPE ≤ 8 | info | Suggest a PR attempt on the named lift |
| `PROGRESSIVE_OVERLOAD_READY` | All target reps completed at RPE ≤ 8 for 2 consecutive sessions on an exercise | medium | Increase load by the exercise's increment |
| `OVERLOAD_STALL` | e1RM flat or negative over 3 sessions AND volume flat | medium | Diagnose (volume / recovery / nutrition) and propose one change |
| `ACWR_SPIKE` | ACWR > 1.5 for 2 consecutive days | high | Deload proposal |
| `MUSCLE_UNDERTRAINED` | 7-day sets for a muscle < MEV AND the program intends to train it | medium | Add a set to the relevant template |
| `MUSCLE_OVERTRAINED` | 7-day sets for a muscle > MRV | medium | Remove volume |
| `FREQUENCY_DROP` | Sessions in last 7 days < 0.6 × the 28-day weekly mean | medium | Re-plan around the calendar |
| `SESSION_DURATION_CREEP` | Mean duration > program ceiling × 1.2 over 3 sessions | low | Reduce rest or trim accessories |
| `IMBALANCE` | Push:pull volume ratio outside 0.75–1.35 over 28 days | low | Rebalance |

### 4.3 Recovery and sleep rules

| Rule | Fires when | Severity | Action |
|---|---|---|---|
| `SLEEP_DECLINE` | mean7d sleep < mean28d × 0.90 | high | Set an earlier bedtime reminder |
| `SLEEP_INCONSISTENCY` | σ(bedtime, 14d) > 60 min | medium | Propose a fixed sleep window |
| `RECOVERY_TREND_DOWN` | recovery trend7d slope < −1.5/day for 5 days | high | Reduce load; investigate the driver |
| `CHRONIC_UNDERRECOVERY` | ≥ 5 of last 7 days recovery < 40 | high | Deload week proposal |
| `SLEEP_DEBT_STRENGTH_LINK` | sleep down ≥ 10 % (7d vs 28d) AND e1RM trend negative on ≥ 2 lifts | high | Name the link explicitly with both numbers |

### 4.4 Body composition rules

| Rule | Fires when | Severity | Action |
|---|---|---|---|
| `WEIGHT_RATE_TOO_FAST` | EWMA rate > 1.0 %/wk while cutting, 2 consecutive weeks | high | Increase calories by `(rate − 0.75%) × bw × 7700 / 7` kcal/day |
| `WEIGHT_RATE_TOO_SLOW` | EWMA rate < 0.25 %/wk while cutting, 2 consecutive weeks | medium | Reduce calories or add activity |
| `WEIGHT_STALL` | \|EWMA change\| < 0.15 % over 14 days while cutting | medium | Diagnose: adherence, TDEE adaptation, or measurement error |
| `RECOMP_ON_TRACK` | Weight down AND e1RM up over 21 days | info | Positive confirmation — this is the goal state |
| `GOAL_PROJECTION_OFF` | Projected date > target date + 14 days | medium | Show what rate change closes the gap |

### 4.5 Behaviour and productivity rules

| Rule | Fires when | Severity | Action |
|---|---|---|---|
| `SUPPLEMENT_LAPSE` | Compliance < 70 % over 14 days for a supplement | low | Move the timing anchor to a better-adhered slot |
| `SUPPLEMENT_LOW_STOCK` | Days of supply < threshold | medium | Create a purchase task |
| `CALENDAR_OVERLOAD` | busyMinutes 7d > 1.4 × 28-day mean AND training frequency dropped | medium | Propose shortened sessions in real gaps |
| `TASK_BACKLOG` | Overdue tasks > 5 AND rising for 3 days | low | Triage session proposal |
| `BEST_TRAINING_WINDOW` | ≥ 21 days of data shows a time-of-day with materially higher completion | info | Suggest shifting the gym window |

### 4.6 Correlation discovery (≥ 28 days of data)

Pairwise Spearman correlation over a defined candidate set (not an exhaustive sweep, which
would guarantee spurious findings):

```
candidatePairs = [
  (sleep.minutes[t−5..t−1], training.volumeKg[t]),
  (nutrition.proteinG, body.weightEwmaKg.rate),
  (calendar.busyMinutes, training.performed),
  (recovery.score, training.sessionRpe),
  (hydration.ml, recovery.score),
  (sleep.score, tasks.completed),
]

Report only when: |ρ| ≥ 0.45  AND  n ≥ 28  AND  p < 0.05 (Benjamini–Hochberg corrected)
```

Every correlation insight is framed as association, explicitly:

> *"Across 34 days, your training volume tends to be higher after nights above 7 hours
> (ρ = 0.52). This is an association in your own data, not proof of cause."*

---

## 5. Ranking

```
score = impact × confidence × recencyDecay × userRelevance

impact         0–1, per rule (a protein floor miss during a cut = 0.85; low fiber = 0.25)
confidence     0–1, computed from sample size, data completeness and effect size
recencyDecay   exp(−daysSinceWindowEnd / 3)
userRelevance  0.5–1.5, per-user multiplier learned from thumbs up/down on that insight type
```

**Filters applied after scoring**
1. One insight per `type` per day.
2. Suppress any type dismissed within the last 7 days.
3. Suppress an insight whose action was already taken.
4. Maximum 3 on the dashboard, 8 in the insights list.
5. At most 1 `high`-severity insight per day — more than one and the user disengages.

---

## 6. Confidence computation

```
confidence = w_n · sampleScore + w_c · completenessScore + w_e · effectScore

sampleScore       = clamp(daysWithData / requiredDays, 0, 1)
completenessScore = 1 − (missingCriticalFields / totalCriticalFields)
effectScore       = clamp(|observedEffect| / meaningfulEffectThreshold, 0, 1)

weights: 0.35 / 0.25 / 0.40
```

An insight below `confidence < 0.55` is never surfaced. Confidence is displayed to the user
as a percentage on the insight detail screen.

---

## 7. Phrasing contract

One batched LLM call per user per night, with a strict output schema:

```json
{
  "type": "array",
  "items": {
    "type": "object",
    "required": ["id", "headline", "body"],
    "properties": {
      "id":       { "type": "string" },
      "headline": { "type": "string", "maxLength": 60 },
      "body":     { "type": "string", "maxLength": 240 }
    },
    "additionalProperties": false
  }
}
```

**Rules given to the model:**
- Every number in your output must appear in the input. Do not compute, round differently,
  or infer new figures.
- The headline states the finding. The body states the evidence and the consequence.
- No hedging, no encouragement, no emoji.
- Second person, present tense.

**Fallback:** if the call fails, returns invalid JSON twice, or contains a number not
present in the input, the engine writes the rule's deterministic template string instead.
Insights therefore *never* depend on model availability.

---

## 8. Worked example — `WEIGHT_RATE_TOO_FAST`

**Signals**
```
body.weightEwmaKg, last 14 days:   90.1 kg → 87.6 kg
  total change      = −2.5 kg = −2.77 % of starting bodyweight
  weeklyRate        = 2.77 % ÷ 2 weeks = 1.39 %/week   ← exceeds the 1.0 %/week ceiling

goal.mode                = cut
goal.weeklyRateTargetPct = 0.75
nutrition.kcal.mean14d   = 2,180   (blended target 2,475)
```

**Rule output**
```jsonc
{
  "type": "weight_rate_too_fast",
  "severity": "high",
  "confidence": 0.91,
  "impact": 0.88,
  "evidence": {
    "signals": [
      { "key": "body.weightRate14d", "value": 1.39, "unit": "%/week" },
      { "key": "goal.weeklyRateTarget", "value": 0.75, "unit": "%/week" },
      { "key": "body.weightRateCeiling", "value": 1.0, "unit": "%/week" },
      { "key": "nutrition.kcal.mean14d", "value": 2180, "unit": "kcal" }
    ],
    "rule": "WEIGHT_RATE_TOO_FAST",
    "window": { "from": "2026-08-15", "to": "2026-08-28" }
  },
  "computedAction": {
    "kcalIncrease": 210,          // (1.39 − 0.75)% × 89.4 kg × 7700 kcal/kg ÷ 7 days
    "newTrainingDayKcal": 2810,
    "newRestDayKcal": 2560
  }
}
```

**Phrased**
> **Increase calories by 200**
> You're losing 1.39 % of bodyweight per week against a 0.75 % target. Above 1 %, the
> deficit starts costing lean mass. Adding roughly 200 kcal a day brings you back into
> range without stopping progress.

**Action button:** `Apply +200 kcal` → calls `adjust_targets` → recomputes and writes the
new targets, recording the insight id as the reason.

---

## 9. Prediction (Phase 3)

```
Goal projection
  rate      = OLS slope of weightEwma over the last 28 days (kg/day)
  projected = targetWeight reached at currentWeight + rate × days
  band      = ±1.96 × stdev(residuals) × sqrt(days)

Reported as: "On track for 84.0 kg around 21 October (range: 12 Oct – 3 Nov)."
```

Predictions are only shown with ≥ 28 days of data and a residual standard deviation below a
threshold. A wide band is reported as a range, never as a false-precision date.

---

## 10. Feedback loop

```
User rates an insight
   ├─ 👍 → userRelevance[type] × 1.15  (capped 1.5)
   └─ 👎 → userRelevance[type] × 0.80  (floored 0.5)
          + reason recorded (not_useful | not_accurate | already_knew | bad_timing)

"not_accurate" additionally raises an engineering alert if it exceeds 10 % for a rule
across all users — that is a bug in the rule, not a preference.
```

Relevance multipliers are stored per user in `users/{uid}/settings/ai_relevance` and applied
at ranking time. They never suppress a `high`-severity safety-relevant insight.

---

## 11. Reproducibility guarantee

Every insight stores its inputs, its rule id, its window and its engine version. Re-running
`dna-1.0.0` over the same stored signals produces byte-identical output. This is asserted by
a test that replays 500 recorded insight generations.

This is what makes the "Why?" button honest — it is not a post-hoc explanation, it is the
actual computation.
