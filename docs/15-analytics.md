# LifeDNA OS — Analytics Center

**Version:** 1.0
**Owner:** Data

This document covers two distinct things that share a word: **user-facing analytics** (the
reports the user reads about their own body) and **product analytics** (the telemetry we
read about the product). They are kept strictly separate — product telemetry never contains
health values.

---

# PART A — User-facing analytics

## 1. Report types

| Type | Cadence | Generated | Window |
|---|---|---|---|
| Weekly | Every Monday 06:00 local | `weeklyReport` job | Mon–Sun of the prior week |
| Monthly | 1st of the month 06:00 local | `monthlyReport` job | Prior calendar month |
| Quarterly | 1 Jan / Apr / Jul / Oct | `monthlyReport` job (quarter branch) | Prior quarter |
| Custom | On demand | Client-side over cached `daily_stats` | Any range |

Report IDs are deterministic (`weekly_2026-W35`, `monthly_2026-08`) so generation is
idempotent — a re-run overwrites rather than duplicating.

## 2. Metric definitions

Every metric states its formula, its unit, and its **direction semantics** — whether an
increase is good, bad, or neutral. This matters: in a cut, a falling weight is good; a
falling protein intake is bad; a falling body-fat percentage is good.

| Metric | Formula | Unit | Direction |
|---|---|---|---|
| `weightChange` | `ewma(end) − ewma(start)` | kg | goal-dependent |
| `weightRate` | `weightChange / startWeight / weeks × 100` | %/wk | in-range is good |
| `bodyFatChange` | `bodyFat(end) − bodyFat(start)` | pp | lower is better |
| `leanMassChange` | `leanMass(end) − leanMass(start)` | kg | higher is better |
| `workoutFrequency` | `count(sessions)` | sessions | higher is better |
| `totalVolume` | `Σ session.totals.volumeKg` | kg | context-dependent |
| `volumeByMuscle` | `Σ per muscle` | kg | vs MEV/MRV bands |
| `avgSessionDuration` | `mean(durationSeconds)` | min | neutral |
| `strengthGain` | per lift, `(e1rm_end − e1rm_start) / e1rm_start × 100` | % | higher is better |
| `prCount` | `count(personal_records)` | count | higher is better |
| `avgSleep` | `mean(sleep.minutes)` | min | vs goal |
| `sleepConsistency` | `100 − (σ(bedtime) − 20) × 1.6` | score | higher is better |
| `avgSleepScore` | `mean(sleep.score)` | score | higher is better |
| `avgRecovery` | `mean(recovery.score)` | score | higher is better |
| `recoveryTrend` | OLS slope over the period | pts/day | higher is better |
| `avgKcal` | `mean(nutrition.kcal)` | kcal | vs target |
| `avgProtein` | `mean(nutrition.proteinG)` | g | higher is better |
| `proteinFloorHitRate` | `days(protein ≥ floor) / days × 100` | % | higher is better |
| `nutritionConsistency` | `days(\|kcal − target\| ≤ 10 % of target) / days × 100` | % | higher is better |
| `loggingCompleteness` | `days(entryCount > 0) / days × 100` | % | higher is better |
| `hydrationAdherence` | `mean(ml / targetMl) × 100` | % | higher is better |
| `supplementCompliance` | `taken / scheduled × 100` | % | higher is better |
| `taskCompletionRate` | `completed / (completed + overdue) × 100` | % | higher is better |
| `calendarLoad` | `mean(busyMinutes)` | min/day | neutral |

## 3. Comparison model

Every metric renders as `current · previous · delta`, where "previous" is the immediately
preceding equivalent period. Deltas carry semantic colour, not arithmetic colour:

```
−0.7 kg weight in a cut   → green,  ▼
−15 min sleep             → red,    ▼
+5,100 kg volume          → green,  ▲
+2 overdue tasks          → red,    ▲
```

Metrics with insufficient data show `—` and a "needs N more days" note rather than a
misleading zero.

## 4. Report composition

```
1. Hero            the period's single headline number (goal-dependent)
2. Metric grid     6 tiles, current/previous/delta
3. Body            weight trajectory vs the target corridor
4. Training        volume by muscle vs MEV/MRV bands; strength deltas per key lift
5. Recovery        sleep and recovery series with the period mean
6. Consistency     adherence bars: logging, protein floor, supplements, tasks
7. Highlights      ≤ 3, generated from the largest positive deltas
8. Concerns        ≤ 3, generated from the FitnessDNA rule set
9. Narrative       one LLM paragraph, numbers injected, schema-constrained
10. Actions        one-tap application of any recommended target changes
```

## 5. Export

| Format | Contents |
|---|---|
| JSON | Complete raw export of every user collection, one file per collection, NDJSON |
| CSV | One file per collection with a flattened, spreadsheet-friendly schema |
| PDF | Rendered report (Phase 2) |
| Image | Shareable report card (Phase 2) |

Delivery is a signed Cloud Storage URL valid 24 hours, emailed rather than returned to the
client. The export contains no other user's data and no internal identifiers beyond the
user's own.

---

# PART B — Product analytics

## 6. Governing rule

> **No health value, food name, message content, or free text ever enters an analytics
> event.** Events carry counts, categories, durations and booleans.

Enforced by a unit test that asserts the analytics service rejects any property whose value
is a string not drawn from a declared enum, and by code review on `core/analytics/events.dart`.

## 7. Event taxonomy

### Lifecycle
`app_open` · `app_background` · `session_start`
Properties: `source` (launcher | notification | deeplink | widget), `coldStart`

### Onboarding
`onboarding_start` · `onboarding_step_complete` (step, secondsOnStep) ·
`onboarding_complete` (totalSeconds, modulesSelected) · `onboarding_abandon` (lastStep)

### Nutrition
`food_logged` (source: search|barcode|recent|favorite|template|quick_add, secondsToLog,
mealSlot) · `barcode_scanned` (resolved: bool, source) · `food_created` ·
`template_applied` · `water_logged` (amount bucket) · `nutrition_day_complete`

### Training
`workout_started` (fromTemplate: bool, templateId hashed) ·
`set_completed` (setIndex, hadPrefill: bool, tapCount) ·
`rest_timer_skipped` · `workout_finished` (durationBucket, setCount, prCount) ·
`workout_abandoned` (setsCompleted, minutesElapsed) · `pr_achieved` (type)

### Live Gym (dedicated, because it is the flagship)
`live_gym_entered` · `live_gym_tap_count` (per set) · `live_gym_backgrounded` ·
`live_gym_recovered_after_kill` · `live_gym_offline_sets` (count)

### AI
`ai_message_sent` (assistant, routedBy, intent, contextEnabled) ·
`ai_response_received` (latencyBucket, tokenBucket) ·
`ai_assistant_overridden` (fromIntent, toAssistant)   ← routing quality signal ·
`ai_tool_confirmed` / `ai_tool_cancelled` (toolName) ·
`ai_feedback` (rating, reason) · `ai_budget_hit`

### Insights
`insight_shown` (category, rank) · `insight_opened` · `insight_applied` ·
`insight_dismissed` (reason) · `insight_rated` (rating)

### Integrations
`integration_connect_start` / `_success` / `_failure` (provider, errorCategory) ·
`health_sync_complete` (recordCountBucket, durationBucket) ·
`permission_requested` / `_granted` / `_denied` (permission)

### Notifications
See `docs/14 §12`.

### Errors
`error_shown` (failureType, screen) · `retry_attempted` · `offline_write_queued` ·
`sync_conflict_resolved` (strategy)

## 8. Funnels

| Funnel | Steps | Health target |
|---|---|---|
| Activation | install → account → onboarding complete → first meal logged → first workout finished | ≥ 45 % reach step 4 within 48 h |
| Nutrition habit | first log → 3 days logged → 7 days logged | ≥ 40 % reach 7 days |
| Training habit | first session → 3 sessions → 8 sessions | ≥ 35 % reach 8 |
| Integration | settings opened → explanation viewed → permission granted → first sync | ≥ 60 % of explanation viewers grant |
| AI adoption | hub opened → first message → second conversation | ≥ 50 % send a message |

## 9. North-star and supporting metrics

**North star:** *weekly cross-domain active users* — users who logged in **≥ 2 different
domains** in a week. This is chosen deliberately: single-domain usage is a competitor's
metric, and cross-domain usage is the only thing that proves the thesis.

| Tier | Metric | Target |
|---|---|---|
| North star | Weekly cross-domain active users | 55 % of WAU |
| Retention | D1 / D7 / D30 | 65 % / 48 % / 42 % |
| Engagement | Sessions per day | ≥ 3.5 |
| Depth | Domains active per user | ≥ 3 |
| Quality | Crash-free sessions | ≥ 99.6 % |
| Value | Insight helpful-rate | ≥ 70 % |
| Efficiency | Median seconds to log a meal | ≤ 12 |
| Efficiency | Median taps per set | ≤ 2 |

## 10. Data pipeline

```
Client (Firebase Analytics)  ──►  BigQuery daily export
Cloud Functions (structured logs) ──►  Cloud Logging sink ──►  BigQuery
Firestore aggregates (ai_usage, engine_runs) ──►  scheduled export ──►  BigQuery
                                                        │
                                                        ▼
                                        dbt models ──► Looker Studio dashboards
```

Retention: raw events 14 months, aggregated models indefinitely. All product-analytics
tables are pseudonymous — joined on a hashed user id that cannot be reversed to an account
without access to a separately-controlled mapping.
