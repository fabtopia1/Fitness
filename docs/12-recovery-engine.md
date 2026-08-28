# LifeDNA OS — Recovery Engine

**Version:** `recovery-1.2.0`
**Owner:** AI Lead
**Implemented in:** `functions/src/engines/recovery/` (authoritative) and
`app/lib/core/engines/recovery_engine.dart` (client mirror for instant preview)
**Parity:** enforced by shared fixtures in `test/fixtures/engines/recovery/*.json`

---

## 1. What this engine answers

> **"How hard can I train today?"**

Not "how do I feel" — that is subjective and the user already knows it. The engine's job is
to convert last night's sleep, the last month of training load and yesterday's activity into
a single number that has a defensible meaning, and then to convert that number into one of
four actions: **push · proceed · reduce · rest**.

---

## 2. Design constraints

| Constraint | Why |
|---|---|
| **Degrades gracefully** | Most users will not have HRV. The score must be meaningful with sleep + training alone. |
| **Never fabricates** | With fewer than 2 of 3 domains available, the engine returns `insufficient_data`, not a guess. |
| **Fully decomposable** | Every score exposes its components, weights and contributions. Tapping the number shows the arithmetic. |
| **Personalized baselines** | An absolute 7-hour sleep target is meaningless. Everything is scored against the user's own 28-day baseline once enough data exists. |
| **Stable** | Day-to-day noise must not swing the score wildly, or the user stops trusting it. |
| **Reproducible** | Stored inputs + engine version regenerate the identical output. |

---

## 3. Recovery Score

```
Recovery = round( Σ (componentScore_i × weight_i) / Σ (weight_i for available components) )

Default weights (Remote Config: engine.recovery.weights):
   sleep     0.40
   training  0.40
   activity  0.20
```

**Availability rule.** Weights are renormalized over available components. If activity data
is missing, sleep and training each carry 0.5. If fewer than **2** components are available,
the engine emits:

```json
{ "recoveryScore": null, "band": "insufficient_data",
  "missingInputs": ["sleep","activity"],
  "message": "Recovery needs sleep data from at least 2 of the last 3 nights." }
```

**Bands**

| Range | Band | Colour | Meaning |
|---|---|---|---|
| 0–33 | `low` | `#FF4D5E` | The body is behind. Reduce or rest. |
| 34–66 | `moderate` | `#FFB800` | Train, but do not chase records. |
| 67–100 | `high` | `#22C55E` | Green light. |

---

## 4. Sleep Score (0–100)

```
SleepScore = 0.40·duration + 0.25·consistency + 0.20·efficiency + 0.15·stages
```

Stage data is frequently absent. When it is, weights renormalize over the available three.

### 4.1 Duration sub-score

Scored against the user's **goal** (default 480 min), with a personalized baseline once
14 nights exist.

```
ratio = actualMinutes / goalMinutes

duration =  100                              if 0.95 ≤ ratio ≤ 1.15
            100 − (0.95 − ratio) × 220       if ratio < 0.95     (floor 0)
            100 − (ratio − 1.15) × 100       if ratio > 1.15     (floor 60)
```

Under-sleeping is penalized ~2.2× harder than over-sleeping, because the physiological cost
is asymmetric. Long sleep is mildly penalized (it correlates with poor sleep quality or
illness) but never below 60.

**Worked example:** 431 min against a 480 min goal → ratio 0.898
→ `100 − (0.95 − 0.898) × 220 = 100 − 11.4 = 88.6` → **89**

### 4.2 Consistency sub-score

Rewards a stable schedule, which is one of the strongest modifiable sleep-quality levers.

```
σ_bed  = stdev(bedtime minutes-from-midnight, last 14 nights)
σ_wake = stdev(wake time minutes-from-midnight, last 14 nights)
σ      = (σ_bed + σ_wake) / 2

consistency = clamp( 100 − (σ − 20) × 1.6 , 0 , 100 )
```

σ ≤ 20 min scores 100. σ = 60 min scores 36. Fewer than 7 nights of history → this
component is unavailable rather than guessed.

### 4.3 Efficiency sub-score

```
efficiency% = totalSleepMinutes / timeInBedMinutes × 100

score =  100                                  if efficiency ≥ 90
         (efficiency − 60) × 3.33             if 60 ≤ efficiency < 90
         0                                    if efficiency < 60
```

### 4.4 Stages sub-score

```
deepPct = deepMinutes / totalMinutes × 100      ideal band 13–23 %
remPct  = remMinutes  / totalMinutes × 100      ideal band 20–25 %

deepScore = 100 − |deepPct − 18| × 5     (clamped 0–100)
remScore  = 100 − |remPct  − 22.5| × 5   (clamped 0–100)
stages    = (deepScore + remScore) / 2
```

---

## 5. Training load and the training component

### 5.1 Session load

```
sessionLoad = sessionRPE × durationMinutes
```

Session-RPE × duration is the best-validated field measure of internal training load and
requires only one extra tap at session end. When `sessionRpe` is absent, it is estimated:

```
estimatedRpe = clamp( 5 + (avgSetRpe − 7) × 1.2 + volumeFactor , 4 , 10 )
volumeFactor = clamp( (workingSets − 18) / 12 , −1 , 1.5 )
```

### 5.2 Acute and chronic load

Exponentially weighted, not simple rolling means — a session three days ago should matter
more than one seven days ago.

```
acute   = EWMA(dailyLoad, halfLife = 3.5 days)   ≈ 7-day window
chronic = EWMA(dailyLoad, halfLife = 14 days)    ≈ 28-day window
ACWR    = acute / chronic           (chronic = 0 → ACWR undefined → training = 75, neutral)
```

### 5.3 Training component score

The mapping is a plateau, not a peak: a wide sweet spot, with penalties on both sides.

```
ACWR         training score
< 0.60       70    detraining — under-stimulated
0.60–0.79    85
0.80–1.29    100   the sweet spot
1.30–1.49    75    elevated
1.50–1.79    50    high risk
≥ 1.80       25    danger

Then adjust for yesterday's session:
  −15  if yesterday's sessionLoad > 1.5 × the 28-day mean daily load
  −8   if yesterday's sessionRpe ≥ 9
  +10  if the last 2 days had no training (and ACWR ≥ 0.8)

training = clamp(base + adjustments, 0, 100)
```

**Worked example:** acute 2,340 · chronic 2,180 → ACWR 1.073 → base **100**.
Yesterday's session load was 584 against a 28-day mean daily load of 334; the threshold is
1.5 × 334 = 501, and 584 exceeds it, so the heavy-session penalty applies: **−15**.
Session RPE was 8, below the ≥ 9 trigger, so no further adjustment. Training component = **85**.

### 5.4 Volume landmarks (used by the workout module, not the score)

| Muscle | MEV (sets/wk) | MAV | MRV |
|---|---|---|---|
| Chest | 8 | 12–20 | 22 |
| Back | 10 | 14–22 | 25 |
| Quads | 8 | 12–18 | 20 |
| Hamstrings | 6 | 10–16 | 20 |
| Shoulders (side) | 8 | 12–20 | 26 |
| Biceps | 8 | 14–20 | 26 |
| Triceps | 6 | 10–18 | 24 |
| Calves | 8 | 12–16 | 20 |

Below MEV or above MRV for a muscle over a 7-day window raises an insight, not a score
change.

---

## 6. Activity component

```
stepRatio = steps / stepGoal
stepScore =  100                          if stepRatio ≥ 1.0
             stepRatio × 100              if 0.5 ≤ stepRatio < 1.0
             stepRatio × 80               if stepRatio < 0.5

activeMinutesScore = clamp(activeMinutes / 45 × 100, 0, 100)

activity = 0.6 × stepScore + 0.4 × activeMinutesScore

Sedentary penalty: −10 if steps < 3,000 and there was no training session.
```

Excess activity is **not** penalized here — its cost already appears through training load.

---

## 7. Physiological adjustment (when a wearable provides it)

Applied after the weighted composite, capped at ±10 points total.

```
rhrDelta = todayRestingHr − baselineRestingHr(28-day median)
rhrAdj   =  +3   if rhrDelta ≤ −3
             0   if −2 ≤ rhrDelta ≤ +2
            −4   if +3 ≤ rhrDelta ≤ +5
            −8   if rhrDelta > +5

hrvDelta = (todayHrv − baselineHrv) / baselineHrv × 100
hrvAdj   =  +4   if hrvDelta ≥ +10 %
             0   if −10 % < hrvDelta < +10 %
            −5   if −20 % < hrvDelta ≤ −10 %
            −9   if hrvDelta ≤ −20 %

recovery = clamp(recovery + clamp(rhrAdj + hrvAdj, −10, +10), 0, 100)
```

Baselines require ≥ 14 days of data. Below that, no adjustment is applied.

---

## 8. Readiness

Recovery is backward-looking (how recovered am I). Readiness is forward-looking (how
recovered am I *relative to what today asks of me*).

```
plannedLoad  = plannedSessionRpe × plannedDurationMinutes
loadDemand   = clamp(plannedLoad / meanDailyLoad28d, 0, 2.5)

readiness = clamp( recovery − (loadDemand − 1.0) × 18 , 0 , 100 )
```

Recovery 82 with a normal-demand session (1.0) → readiness 82.
Recovery 82 with a very heavy session (1.8) → 82 − 14.4 → **68**.

---

## 9. Recommendation mapping

```
readiness ≥ 80  and  ACWR < 1.3   → push     "Green light — go for a PR attempt."
readiness ≥ 65                    → proceed  "Train as planned."
readiness ≥ 40                    → reduce   "Cut volume by 30 %. Keep the compounds,
                                              drop the last set of each accessory."
readiness < 40   or  ACWR ≥ 1.8   → rest     "Take today off or do a light recovery session."
```

The `reduce` action is concrete and applied by one tap: the app clones today's template,
removes the final set of each accessory exercise, and caps top sets at RPE 7.

---

## 10. Worked end-to-end example

**Inputs (28 Aug 2026, Youssef)**

```
sleep:    431 min · in bed 468 · goal 480 · deep 78 · REM 96
          14-night σ_bed 24 min, σ_wake 19 min
training: acute 2,340 · chronic 2,180 · yesterday load 584 (RPE 8, 73 min)
          28-day mean daily load 334
activity: steps 8,432 · goal 12,000 · active minutes 62
physio:   resting HR 58 (baseline 59) · HRV 42 ms (baseline 40.8)
```

**Sleep**
```
duration     ratio 0.898 → 100 − 0.052×220 = 88.6
consistency  σ = (24+19)/2 = 21.5 → 100 − 1.5×1.6 = 97.6
efficiency   431/468 = 92.1 % → 100
stages       deep 18.1 % → 100 − 0.1×5 = 99.5
             REM  22.3 % → 100 − 0.2×5 = 99.0   → 99.25
SleepScore   0.40×88.6 + 0.25×97.6 + 0.20×100 + 0.15×99.25
           = 35.44 + 24.40 + 20.00 + 14.89 = 94.7 → 95
```
> **Note on `goalMinutes`.** This example uses the default 480-minute goal. Once a user has
> 14 nights of history the engine substitutes a personalized goal derived from their own
> 28-day distribution, which produces a lower duration sub-score for the same 431 minutes.
> The formula is unchanged; only `goalMinutes` differs.

**Training**
```
ACWR 2340/2180 = 1.073 → base 100
yesterday 584 > 1.5 × 334 = 501 → −15
RPE 8 → no adjustment
training = 85
```

**Activity**
```
stepRatio 8432/12000 = 0.703 → 70.3
activeMinutes 62/45 → 137.8 → clamped 100
activity = 0.6×70.3 + 0.4×100 = 42.2 + 40.0 = 82.2 → 82
```

**Composite**
```
recovery = 0.40×95 + 0.40×85 + 0.20×82
         = 38.0 + 34.0 + 16.4 = 88.4 → 88
```

**Physiological adjustment**
```
rhrDelta = 58 − 59 = −1 → 0
hrvDelta = (42 − 40.8)/40.8 = +2.9 % → 0
recovery = 88
```

**Readiness** (planned: RPE 8 × 75 min = 600; mean daily 334 → demand 1.80)
```
readiness = 88 − (1.80 − 1.0) × 18 = 88 − 14.4 = 73.6 → 74
```

**Output**
```jsonc
{ "recoveryScore": 88, "band": "high", "readinessScore": 74,
  "components": {
    "sleep":    { "score": 95, "weight": 0.40, "contribution": 38.0, "available": true },
    "training": { "score": 85, "weight": 0.40, "contribution": 34.0, "available": true },
    "activity": { "score": 82, "weight": 0.20, "contribution": 16.4, "available": true } },
  "recommendation": { "action": "proceed",
    "headline": "Train as planned.",
    "detail": "Recovery is high at 88, but today's session is heavier than your average, so readiness lands at 74. Hit your target reps; save the PR attempt for a lighter-demand day." },
  "engineVersion": "recovery-1.2.0" }
```

---

## 11. Tuning and versioning

- All weights, thresholds and half-lives live in Remote Config under `engine.recovery.*`
  and are readable by both the server engine and the client mirror.
- A change to any constant bumps the patch version; a change to a formula bumps the minor
  version; a change to the component set bumps the major version.
- `recovery_data` documents store `engineVersion`, so historical scores are never silently
  reinterpreted. Recomputation with a new version writes new documents rather than
  overwriting old ones.

## 12. Validation plan

| Check | Method | Gate |
|---|---|---|
| Determinism | Same inputs → identical output, 1,000 random fixtures | 100 % |
| Dart/TS parity | Shared fixture suite run in both languages | 100 % |
| Boundary safety | Fuzz all inputs including nulls, zeros, negatives, extremes | No crash, no NaN, no out-of-range output |
| Degradation | Every combination of missing components | Correct renormalization or `insufficient_data` |
| Face validity | 30 real user-weeks reviewed by a coach | ≥ 80 % agreement with the coach's call |
| Stability | Day-over-day change with unchanged behaviour | ≤ 8 points |
