# LifeDNA OS — Product Requirements Document

**Document version:** 1.0
**Status:** Approved for build
**Product:** LifeDNA OS — *Your Personal Performance Operating System*
**Platforms:** Android (primary), iOS (parity target, Phase 2)

---

## 1. Executive summary

Serious self-optimizers currently operate a fragmented stack: MyFitnessPal for food,
Strong or Hevy for lifting, Samsung Health or WHOOP for physiology, Google Calendar for
time, Notion for tasks, and a chat assistant for thinking. Each app owns one slice of the
truth and none of them can reason across slices. The consequence is that the highest-value
question a person can ask — *"given everything happening in my body and my week, what
should I do next?"* — is unanswerable by any product on the market.

**LifeDNA OS is the answer layer.** It ingests training, nutrition, sleep, physiology,
calendar and task data into one normalized daily record, runs deterministic engines
(Recovery, Readiness, Load) plus a multi-model AI layer over that record, and surfaces a
single prioritized action list. The user does not browse dashboards. The user is told what
to do, why, and what it will change.

### The wedge

We enter through the module that today's tools execute worst relative to their importance:
**the intersection of nutrition adherence and training execution during a body
recomposition phase.** That is a hard, high-intent, high-retention use case where the user
must simultaneously hit a protein floor, hold a moderate deficit, train each muscle twice
weekly with progressive overload, and protect sleep. It requires exactly the cross-domain
reasoning nobody ships. The reference program embedded in the product (an 8-week
recomposition blueprint: 90.1 kg / 31.3 % BF → 84–86 kg / 24–26 % BF, 6 sessions per week,
200 g protein floor, 2600 kcal training / 2350 kcal rest days) is the canonical test case
for every engine in this document.

### Why now

- Health Connect (Android) finally makes cross-vendor physiological data portable.
- Frontier LLMs are now good enough to reason over structured longitudinal health data,
  and cheap enough to run daily per user.
- Consumer expectation has shifted from "log it" to "tell me what it means".

---

## 2. Product vision

> **In five years, LifeDNA OS is the operating system a high-performer opens first every
> morning and last every night, because it is the only surface that knows their body,
> their calendar and their goals at the same time.**

### Vision pillars

| Pillar | Statement | How we know it is true |
|---|---|---|
| **One truth** | Every number about the user's body, day and goals lives in one normalized record. | No module reads a metric a different module computed differently. |
| **Decision, not data** | The product's output is an ordered action list, not a chart. | Home screen top card is always an action with a verb. |
| **Explainable** | Every recommendation exposes its evidence. | 100 % of insights carry a provenance object. |
| **Ambient** | The right prompt arrives at the right moment without being opened. | > 55 % of daily actions begin from a notification. |
| **Composable intelligence** | The best model for each job, swappable without a client release. | Adding a provider is a config change, not a deploy. |

### Positioning statement

*For* driven individuals managing training, nutrition, study and work simultaneously,
*who* are tired of stitching together six apps that never talk,
*LifeDNA OS* is a personal performance operating system
*that* unifies body and calendar data and continuously tells them the single highest-value
next action,
*unlike* Apple Health, WHOOP, MyFitnessPal or Notion, which each own one domain and
optimize for logging rather than deciding.

### Anti-goals (explicitly out of scope forever)

- Social feed, follower graph, public leaderboards.
- Gamified streak-shaming or aggressive engagement loops.
- Medical diagnosis, treatment, or claims of therapeutic effect.
- Advertising, or any monetization of user health data.
- Serving competitive athletes' periodization needs at elite/coach-managed level (v1).

---

## 3. Goals and success metrics

### 3.1 Business goals

| # | Goal | Metric | Target (12 months post-launch) |
|---|---|---|---|
| B1 | Prove retention on the wedge | D30 retention | ≥ 42 % |
| B2 | Convert to paid | Free → Pro conversion | ≥ 8 % |
| B3 | Establish the AI layer as the differentiator | % of WAU using AI Hub weekly | ≥ 60 % |
| B4 | Contain AI unit economics | AI cost per active user / month | ≤ $0.85 |
| B5 | Build the data moat | Median days of continuous multi-domain data per retained user | ≥ 120 |

### 3.2 Product goals

| # | Goal | Metric | Target |
|---|---|---|---|
| P1 | Logging must be effortless | Median time to log a full meal | ≤ 12 s |
| P2 | Live Gym Mode beats incumbents | Median taps per completed set | ≤ 2 |
| P3 | Insights must be trusted | Insight helpful-rate (thumbs up / rated) | ≥ 70 % |
| P4 | Cross-domain value is felt | % users with ≥ 3 domains active at D14 | ≥ 50 % |
| P5 | Notifications are welcome, not noise | Notification opt-out rate | ≤ 12 % |

### 3.3 Technical goals

| # | Goal | Metric | Target |
|---|---|---|---|
| T1 | Instant home | Dashboard cold start to interactive (P95, mid-tier Android) | ≤ 1.8 s |
| T2 | Gym reliability | Live Gym set-write success rate offline | 100 % |
| T3 | AI responsiveness | AI first-token latency (P90) | ≤ 2.0 s |
| T4 | Stability | Crash-free sessions | ≥ 99.6 % |
| T5 | Sync integrity | Duplicate health records after resync | 0 |

### 3.4 Counter-metrics (guard rails)

We will not celebrate a win on the above if any of these degrade:

- Median session length **increases** beyond 4 min (indicates friction, not value).
- Notification volume exceeds **9 per day** median.
- % of users whose logged intake drops below **1.2 g protein/kg** while in a deficit
  (indicates the product is enabling under-eating) — triggers product review, not a nudge.

---

## 4. Scope

### 4.1 In scope for v1.0 (MVP)

Authentication and onboarding · Personal Dashboard · Nutrition Center (logging, macros,
water, meal planner, barcode scan, templates) · Supplement System · Workout Center
(templates, exercise DB, history, PRs) · Live Gym Mode · Calendar Center (Google +
Outlook read/write) · Task Manager · Notifications Engine · Samsung Health / Health
Connect sync · AI Assistant Hub with router (Claude + Copilot) · Basic body-weight and
waist tracking · Settings, export, delete.

### 4.2 In scope for v1.1 – v1.3 (Phase 2)

Galaxy Fit 3 BLE integration · full Recovery Engine · Analytics Center (weekly/monthly
reports) · full Body Composition Center (all measurements, photos, charts) · Sleep detail
· iOS parity · Apple Health / HealthKit.

### 4.3 In scope for v2.0 (Phase 3)

FitnessDNA Engine (predictive, personalized) · AI Coaching with adaptive programming ·
Quarterly reports · Deload and periodization automation · Voice-first logging · Wearable
companion app (Wear OS tile + complication).

### 4.4 Explicitly out of scope

Multi-user coaching dashboards · Meal delivery / e-commerce checkout · Medication
management · Menstrual-cycle-based programming (deferred, requires dedicated clinical
review) · Continuous glucose monitoring · Web application (read-only export only).

---

## 5. User personas

### Persona 1 — Youssef, "The Recomposer" (PRIMARY, 60 % of design weight)

| Attribute | Detail |
|---|---|
| Age / context | 21, university student, part-time technical work |
| Body | 90.1 kg, 174.5 cm, 31.3 % body fat, BMI 29.4, 61.9 kg lean mass |
| Goal | 84–86 kg at 24–26 % BF in 8 weeks while **gaining** 10–20 % on key lifts |
| Schedule | Gym 18:00–20:00 (shifting to 19:00–21:00 in October); lectures mid-day; work evenings |
| Training | 6 days: Push / Pull / Legs / Fitness / Upper / Lower, plus Friday recovery swim |
| Nutrition | 2600 kcal training days, 2350 rest days, **200 g protein floor every day** |
| Devices | Samsung Galaxy phone, Galaxy Fit 3 |
| Tech comfort | High. Will use advanced features if they are fast. |

**Jobs to be done**
- *When* I'm standing at the rack between sets, *I want to* log the set in one tap and see
  what I lifted last time, *so I can* beat it without doing arithmetic.
- *When* it's 21:00 and I've eaten four meals, *I want to* know exactly how much protein I
  still owe, *so I can* fix it before bed instead of discovering the gap tomorrow.
- *When* my week has three deadlines and two late shifts, *I want* my training plan to bend
  rather than break, *so I* don't lose the whole block.

**Frustrations with the status quo**
- MyFitnessPal's database is polluted and its UI takes 40+ seconds per meal.
- Strong knows his lifts but nothing about his sleep; Samsung Health knows his sleep but
  nothing about his lifts. Nobody connects them.
- Generic AI chat has no memory of his actual numbers, so every conversation starts at zero.

**Success for Youssef** = arrives at week 8 having hit the body-composition target *and*
added load on the incline bench, with a logged, explainable record of how.

---

### Persona 2 — Dina, "The Optimizer Professional" (SECONDARY, 25 %)

| Attribute | Detail |
|---|---|
| Age / context | 33, product manager, 6–8 meetings/day, frequent travel |
| Goal | Maintain composition, protect sleep, stop energy crashes at 15:00 |
| Constraint | Training time is whatever the calendar leaves. Often 35 minutes. |
| Devices | iPhone (Phase 2), Apple Watch |

**Jobs to be done**
- *When* my calendar changes at 09:00, *I want* my training and meals re-planned
  automatically, *so I* don't have to renegotiate my whole day.
- *When* I've slept 5 h before a heavy day, *I want* the app to downgrade the session
  rather than let me fail it, *so I* stay consistent instead of injured.

**What wins her** — the Calendar ↔ Training ↔ Recovery loop. She will not log food
meticulously; she needs *good-enough* nutrition with excellent time and recovery
management.

---

### Persona 3 — Karim, "The Data Purist" (TERTIARY, 10 %)

| Attribute | Detail |
|---|---|
| Age / context | 41, engineer, 6 years of self-tracking history |
| Goal | Understand causality in his own data; run personal experiments |
| Behaviour | Exports everything. Will find and report any inconsistency in a formula. |

**Jobs to be done**
- *When* I read a recommendation, *I want* the exact inputs and weights, *so I can* verify it.
- *When* I change one variable for 3 weeks, *I want* a clean before/after readout.

**What wins him** — transparent algorithms (`docs/12`), raw data export, and the ability
to see confidence intervals rather than false precision.

---

### Persona 4 — Sara, "The Returning Beginner" (TERTIARY, 5 %)

| Attribute | Detail |
|---|---|
| Age / context | 28, restarting training after 3 years off |
| Goal | Build the habit; not be overwhelmed |
| Risk | Churns in week 1 if the product presents 15 modules on day one |

**Design implication** — progressive disclosure is mandatory. Onboarding activates **two**
modules (training + one habit). Modules unlock as adherence is demonstrated. This is the
single most important anti-churn mechanism in the product.

---

## 6. Functional requirements by module

Requirement IDs are stable and referenced by the backlog (`17-mvp-backlog.md`) and tests.
Priority uses MoSCoW: **M**ust / **S**hould / **C**ould / **W**on't-in-this-release.

---

### 6.0 Authentication & Onboarding (`AUTH`)

| ID | Requirement | Priority |
|---|---|---|
| AUTH-01 | Users can register with email + password (min 10 chars, breach-checked via Firebase). | M |
| AUTH-02 | Users can sign in with Google, Apple and Microsoft OAuth providers. | M |
| AUTH-03 | Microsoft sign-in additionally requests Graph scopes (`Calendars.ReadWrite`, `User.Read`, `Mail.Read` optional) with granular consent. | M |
| AUTH-04 | Password reset via email link. | M |
| AUTH-05 | Session persists across app restarts; token refresh is transparent. | M |
| AUTH-06 | Account deletion removes all user data within 30 days and issues confirmation. | M |
| AUTH-07 | Onboarding collects: name, DOB, sex, height, current weight, target weight, activity level, goal mode (cut/maintain/bulk), training days/week, gym window, dietary restrictions. | M |
| AUTH-08 | Onboarding computes and presents initial targets (BMR, TDEE, macros) with an editable override. | M |
| AUTH-09 | Onboarding never asks more than 3 questions per screen and shows a progress indicator. | M |
| AUTH-10 | User selects **at most two** starting modules; remainder are locked with an explanation of the unlock condition. | S |
| AUTH-11 | Biometric app lock (fingerprint/face) is available and off by default. | S |
| AUTH-12 | Anonymous "try it" mode with upgrade-to-account migration. | C |

---

### 6.1 Module 1 — Personal Dashboard (`DASH`)

| ID | Requirement | Priority |
|---|---|---|
| DASH-01 | Home renders a time-aware greeting and today's date context. | M |
| DASH-02 | **Next Action card** occupies the visual apex and always contains exactly one imperative action derived from the priority engine. | M |
| DASH-03 | Macro rings display calories, protein, carbs, fat as consumed/target with remaining values. | M |
| DASH-04 | Hydration card shows current/target ml with a one-tap `+250 ml` quick action. | M |
| DASH-05 | Workout status card shows one of: `Scheduled at HH:MM` / `In progress` / `Completed` / `Rest day`, with a primary CTA matching the state. | M |
| DASH-06 | Recovery card shows score 0–100, colour band, and delta vs 7-day average. | M (stub in MVP, live Phase 2) |
| DASH-07 | Sleep card shows last night's duration, sleep score and bed/wake times. | M |
| DASH-08 | Today's Schedule strip shows the next 3 calendar events with time-until. | M |
| DASH-09 | Upcoming Tasks card shows up to 4 tasks ordered by (due date, priority). | M |
| DASH-10 | AI Insights card shows up to 3 ranked insights with a tap-through to evidence. | M |
| DASH-11 | Dashboard is fully functional offline from cache; a subtle banner indicates stale data with last-sync time. | M |
| DASH-12 | Cards are reorderable and individually hideable; layout persists per user. | S |
| DASH-13 | Pull-to-refresh triggers a full sync fan-out with per-source status. | M |
| DASH-14 | Supplement compliance chip shows taken/total for today. | S |
| DASH-15 | Long-press on any metric opens its 7-day sparkline in a bottom sheet. | C |
| DASH-16 | Dashboard state is a single immutable `DashboardSnapshot`; no card fetches independently. | M |

**Reference card copy (must be reproducible by the priority engine):**
- `"Today's Recovery: 82%"`
- `"Time for Meal 1"`
- `"Workout starts in 45 minutes"`
- `"You are currently 32 g below protein target"`

---

### 6.2 Module 2 — Nutrition Center (`NUTR`)

| ID | Requirement | Priority |
|---|---|---|
| NUTR-01 | User can log a food item by search, barcode, recent, favourite, or meal template. | M |
| NUTR-02 | Food search returns results in ≤ 400 ms P90 from a local index for the top 5 000 foods, falling back to remote. | M |
| NUTR-03 | Barcode scanning resolves via Open Food Facts + internal cache; unresolved codes offer manual creation which is then cached for that user. | M |
| NUTR-04 | Portions support grams, ml, and named household units per food (`1 scoop = 30 g`). | M |
| NUTR-05 | Meals are grouped into user-defined slots with times (default: Breakfast 09:00, Lunch 13:00, Pre-workout 16:30, Post-workout 19:30, Before bed 22:30). | M |
| NUTR-06 | Daily totals update optimistically and reconcile on write confirmation. | M |
| NUTR-07 | Targets differ by day type (**training day / rest day**) and are driven by the active nutrition plan. | M |
| NUTR-08 | Goal modes: **Cut**, **Maintain**, **Bulk**, each with a defined kcal delta and macro distribution rule. | M |
| NUTR-09 | Protein floor is enforced as an absolute daily minimum independent of calorie target and is surfaced separately from the protein *target*. | M |
| NUTR-10 | Water tracking with configurable container sizes and a daily target derived from body mass and training volume. | M |
| NUTR-11 | Macro progress rings animate on change and are colour-coded per macro. | M |
| NUTR-12 | Meal templates can be created from any logged day or built manually, then applied in one tap. | M |
| NUTR-13 | Meal planner allows assigning templates to future days on a 7-day grid. | S |
| NUTR-14 | Shopping list auto-generates from the planner across a selected date range, aggregating quantities by ingredient. | S |
| NUTR-15 | Meal reminders fire per slot and are suppressed if that slot is already logged. | M |
| NUTR-16 | Smart meal recommendations propose a meal that closes the current macro gap from foods the user actually eats. | S |
| NUTR-17 | Custom foods and custom recipes (multi-ingredient with per-serving computation). | M |
| NUTR-18 | Quick-add supports raw macros without a food entry. | M |
| NUTR-19 | Editing or deleting an entry recomputes totals atomically. | M |
| NUTR-20 | Day view shows a macro timeline (intake distribution across the day) for meal-timing feedback. | C |

**Macro derivation contract (must be implemented exactly):**

```
BMR  = Mifflin-St Jeor
       male:   10·kg + 6.25·cm − 5·age + 5
       female: 10·kg + 6.25·cm − 5·age − 161
TDEE = BMR × activityFactor            (1.2 / 1.375 / 1.55 / 1.725 / 1.9)
       + trainingDayBonus (kcal)       (session kcal estimate, capped at 500)

Goal deltas:  Cut −18 %   |   Maintain 0 %   |   Bulk +10 %
              (deficit hard-capped at −25 % of TDEE and at −1 000 kcal)

Protein floor = clamp( 1.8 g/kg bodyweight ,  min 1.6 g/kg lean ,  max 2.6 g/kg )
Fat           = max( 0.7 g/kg bodyweight , 20 % of kcal )
Carbohydrate  = remaining kcal / 4
```

---

### 6.3 Module 3 — Supplement System (`SUPP`)

| ID | Requirement | Priority |
|---|---|---|
| SUPP-01 | Built-in catalogue: Creatine monohydrate, Vitamin D3, Omega-3, Magnesium glycinate, Ashwagandha, Pre-workout, Multivitamin, Whey protein, Zinc, Caffeine. | M |
| SUPP-02 | User can create custom supplements with name, dose, unit, form and notes. | M |
| SUPP-03 | Each supplement has a schedule: daily / specific weekdays / training days only / rest days only / cyclical (n on, m off). | M |
| SUPP-04 | Each schedule entry binds to a **timing anchor**: wake, breakfast, lunch, pre-workout, post-workout, dinner, before bed, or a fixed clock time. | M |
| SUPP-05 | Recurring reminders fire at the resolved anchor time and are suppressed once logged. | M |
| SUPP-06 | Logging a dose is one tap from the notification and from the dashboard chip. | M |
| SUPP-07 | Inventory tracks units remaining; each logged dose decrements it. | M |
| SUPP-08 | Low-stock notification fires at a user-set threshold (default 7 days of supply remaining). | M |
| SUPP-09 | Purchase history records date, vendor, quantity, cost; computes cost per serving and monthly spend. | S |
| SUPP-10 | Compliance score = taken doses / scheduled doses over a rolling 30-day window, per supplement and overall. | M |
| SUPP-11 | Interaction/timing warnings for known conflicts (e.g. calcium + iron; caffeine within 8 h of bedtime) from a static rule table. | S |
| SUPP-12 | Supplement stack can be exported as a shareable summary. | C |

---

### 6.4 Module 4 — Workout Center (`WORK`)

| ID | Requirement | Priority |
|---|---|---|
| WORK-01 | Exercise database ships with ≥ 400 exercises: name, primary/secondary muscles, equipment, category, mechanic (compound/isolation), instructions, and a `defaultRestSeconds`. | M |
| WORK-02 | Full-text and faceted exercise search (muscle, equipment, category). | M |
| WORK-03 | User can create custom exercises. | M |
| WORK-04 | Workout templates define ordered exercises with target sets, rep ranges, load scheme and rest. | M |
| WORK-05 | Templates support supersets and circuits via a `groupId` on exercise entries. | M |
| WORK-06 | Training programs bundle templates onto a weekly schedule (the reference 6-day Push/Pull/Legs/Fitness/Upper/Lower/Swim split is a seeded program). | M |
| WORK-07 | Starting a session from a template pre-fills every set with the last performed values for that exercise. | M |
| WORK-08 | Progressive overload tracking computes, per exercise: best set, best e1RM, total volume, and trend over the last 8 sessions. | M |
| WORK-09 | e1RM uses Epley (`w × (1 + r/30)`) with Brzycki cross-check; reps > 12 are flagged low-confidence. | M |
| WORK-10 | Personal records are detected automatically for: heaviest weight, best e1RM, max reps at a load, and max session volume. | M |
| WORK-11 | PR detection raises a celebratory, non-blocking in-session toast. | M |
| WORK-12 | Exercise history screen shows every past set for that exercise, grouped by session, with charts. | M |
| WORK-13 | Workout analytics: weekly volume per muscle group, session count, average duration, frequency per muscle. | M |
| WORK-14 | Volume-landmark guidance flags muscle groups below MEV or above MRV per week. | S |
| WORK-15 | Sessions can be created freeform without a template. | M |
| WORK-16 | Session notes and per-exercise notes persist and surface next time that exercise is performed. | M |
| WORK-17 | Session duration is measured from first set to finish, excluding pauses > 20 min (auto-split prompt). | M |
| WORK-18 | Deload suggestion when ACWR > 1.5 for 2 consecutive weeks or when e1RM trend is negative for 3 sessions. | S (Phase 2) |
| WORK-19 | Plate calculator for a target barbell load with configurable available plates and bar weight. | S |
| WORK-20 | Workout history calendar heat map. | S |

---

### 6.5 Module 5 — Live Gym Mode (`LIVE`)

> **This is the module that must be demonstrably better than Strong and Hevy.** The success
> criterion is taps-per-set and glanceability at arm's length, not feature count.

| ID | Requirement | Priority |
|---|---|---|
| LIVE-01 | Full-screen, pure-dark surface. No bottom navigation. Screen stays awake for the session duration. | M |
| LIVE-02 | Primary layout shows: exercise name, current set index / total, target reps, target weight, previous-session values, and remaining sets. | M |
| LIVE-03 | **Complete Set** is a single full-width primary button ≥ 64 dp tall, reachable by the thumb in the bottom third of the screen. | M |
| LIVE-04 | Completing a set auto-starts the rest timer using the exercise's rest value. | M |
| LIVE-05 | Rest countdown is legible at 1 m (≥ 56 sp), with `−15 s` / `+15 s` / `Skip` controls. | M |
| LIVE-06 | Rest completion fires haptic + optional sound, and a notification if the app is backgrounded. | M |
| LIVE-07 | Weight and reps are adjustable with steppers (`±2.5 kg`, `±1 rep`) and a direct numeric entry sheet. Default increment is configurable per exercise. | M |
| LIVE-08 | Next exercise is always previewed at the bottom of the screen. | M |
| LIVE-09 | Voice notes: record, auto-transcribe (on-device where available), attach to set or session. | S |
| LIVE-10 | Superset mode alternates exercises within a group and adjusts rest to fire only after the group completes. | M |
| LIVE-11 | Drop-set mode appends sub-sets under a parent set with reduced load, logged as a unit. | M |
| LIVE-12 | Failure tracking: each set records an RPE (6–10) or a `to failure` flag via a one-tap chip row. | M |
| LIVE-13 | All writes are local-first; the session is fully operable in airplane mode and syncs on reconnect. | M |
| LIVE-14 | Session survives process death: state is checkpointed on every mutation and restored on relaunch. | M |
| LIVE-15 | `Skip` moves to the next set/exercise and marks the skipped unit explicitly. | M |
| LIVE-16 | Reordering, adding or removing exercises mid-session is supported. | M |
| LIVE-17 | **Finish Workout** shows a summary (duration, volume, sets, PRs) and requires confirm. | M |
| LIVE-18 | Heart rate from a connected wearable is displayed live when available. | S (Phase 2) |
| LIVE-19 | One-hand mode: all interactive elements sit within the bottom 60 % of the viewport. | M |
| LIVE-20 | Optional volume-key binding to complete a set without looking at the screen. | C |

---

### 6.6 Module 6 — Body Composition Center (`BODY`)

| ID | Requirement | Priority |
|---|---|---|
| BODY-01 | Track weight with date, time and optional context (fasted/post-meal). | M |
| BODY-02 | Track body fat %, muscle mass, and (optional) visceral fat, bone mass, body water. | M (Phase 2 for the optional set) |
| BODY-03 | Track circumference: waist, chest, arms (L/R), thighs (L/R), neck, hips, calves, forearms. | M |
| BODY-04 | Weight chart displays raw points plus a 7-day exponentially-weighted moving average; the EWMA is the primary line. | M |
| BODY-05 | Trend readout states rate of change per week in kg and % bodyweight. | M |
| BODY-06 | Progress photos: front/side/back, stored in Cloud Storage, private by default, with a side-by-side comparison view. | S |
| BODY-07 | Goal progress bar from start → current → target, with projected date at current rate. | M |
| BODY-08 | Weekly report: weight change, average intake, adherence, training volume, sleep average. | S (Phase 2) |
| BODY-09 | Monthly report adds strength deltas and measurement deltas. | S (Phase 2) |
| BODY-10 | Navy-method body-fat estimate from neck/waist/(hip) circumference as a fallback when no scale data exists. | C |
| BODY-11 | Measurement reminder on the user's chosen weekly cadence (default Saturday morning). | S |

---

### 6.7 Module 7 — Recovery Engine (`RECV`)

Full algorithm specification: `docs/12-recovery-engine.md`.

| ID | Requirement | Priority |
|---|---|---|
| RECV-01 | Compute a daily Recovery Score 0–100 from sleep (40 %), training load (40 %) and activity (20 %). | M (Phase 2) |
| RECV-02 | Weights are configurable server-side via Remote Config without a client release. | M |
| RECV-03 | Compute a Sleep Score 0–100 from duration, consistency, efficiency and (when available) stage distribution. | M |
| RECV-04 | Compute acute (7-day) and chronic (28-day) training load and the ACWR. | M |
| RECV-05 | Compute a Readiness score that combines Recovery with today's planned load. | S |
| RECV-06 | Recovery is degraded-but-valid with partial inputs; the UI states which inputs were missing. | M |
| RECV-07 | Never emit a score with fewer than 2 of 3 domains present; show `Insufficient data` instead. | M |
| RECV-08 | Each score exposes its component breakdown on tap. | M |
| RECV-09 | Recovery bands: `0–33 Low` (red), `34–66 Moderate` (amber), `67–100 High` (green). | M |
| RECV-10 | Recovery drives the dashboard's training recommendation (`push / proceed / reduce / rest`). | M |
| RECV-11 | Resting-heart-rate and HRV deltas adjust the score when a wearable supplies them. | S (Phase 2) |

---

### 6.8 Module 8 — Samsung Health Integration (`SAMS`)

| ID | Requirement | Priority |
|---|---|---|
| SAMS-01 | Sync steps, heart rate, active calories, total calories, distance, sleep sessions, exercise sessions and active minutes. | M |
| SAMS-02 | Primary path is **Health Connect**; Samsung Health SDK is the fallback where Health Connect lacks a data type. | M |
| SAMS-03 | Granular permission request with a clear explanation screen before the system dialog. | M |
| SAMS-04 | Background sync every 60 minutes plus on app foreground plus on pull-to-refresh. | M |
| SAMS-05 | Historical backfill of 90 days on first connect, chunked and resumable. | M |
| SAMS-06 | Deduplication is deterministic: `(source, type, startTime, endTime)` hash is the idempotency key. | M |
| SAMS-07 | Conflict policy: the highest-precedence source wins per data type, configurable in settings (default: wearable > phone > manual for HR/steps; manual > all for weight). | M |
| SAMS-08 | Sync status screen shows last successful sync per data type, record counts and errors. | M |
| SAMS-09 | A LifeDNA-recorded workout is written **back** to Health Connect so the ecosystem stays consistent. | S |
| SAMS-10 | All health-permission denials degrade gracefully with a specific "what you lose" message. | M |

---

### 6.9 Module 9 — Galaxy Fit 3 Integration (`FIT3`)

| ID | Requirement | Priority |
|---|---|---|
| FIT3-01 | Discover and pair the band over BLE; persist the bond. | M (Phase 2) |
| FIT3-02 | Read heart rate via the standard Heart Rate Service (`0x180D`) when a live session is active. | M |
| FIT3-03 | Read battery level (`0x180F`) and surface it in settings. | S |
| FIT3-04 | Pull sleep, stress, SpO2, steps and calories via Samsung Health (the band's authoritative sync path), not by re-implementing the proprietary protocol. | M |
| FIT3-05 | Build a continuous health timeline merging band data with phone data, gap-marked where data is absent. | M |
| FIT3-06 | Live HR streams into Live Gym Mode with a zone indicator. | S |
| FIT3-07 | Connection state machine surfaces `disconnected / scanning / connecting / connected / syncing` with recovery actions. | M |
| FIT3-08 | BLE operations run in a foreground service during an active session to survive Doze. | M |
| FIT3-09 | Graceful degradation: absence of the band never blocks any feature. | M |

---

### 6.10 Module 10 — Calendar Center (`CAL`)

| ID | Requirement | Priority |
|---|---|---|
| CAL-01 | Connect Google Calendar via OAuth 2.0 with incremental authorization. | M |
| CAL-02 | Connect Outlook/Microsoft 365 via Microsoft Graph. | M |
| CAL-03 | Multiple calendars per provider, individually toggleable, each with a display colour. | M |
| CAL-04 | Views: Day (time-blocked), 3-Day, Week, Agenda. | M |
| CAL-05 | Create, edit and delete events, writing through to the source provider. | M |
| CAL-06 | Two-way sync using provider delta/sync tokens; full resync fallback on token invalidation. | M |
| CAL-07 | LifeDNA-owned blocks (workouts, meals, recovery) are rendered distinctly and can optionally be pushed to the external calendar. | M |
| CAL-08 | Conflict detection warns when a planned workout overlaps an external event. | M |
| CAL-09 | Time blocking: drag a task onto the calendar to create a block linked to that task. | S |
| CAL-10 | Deadline tracking surfaces task due-dates on the calendar surface. | M |
| CAL-11 | Free-slot finder proposes training windows that fit the user's gym window and session duration. | S |
| CAL-12 | Calendar data is cached for 30 days forward / 7 days back for offline read. | M |

---

### 6.11 Module 11 — Task Manager (`TASK`)

| ID | Requirement | Priority |
|---|---|---|
| TASK-01 | Categories: University, Work, Fitness, Personal, Projects (user-extensible). | M |
| TASK-02 | Task fields: title, notes, category, priority (P1–P4), due date/time, estimate (min), tags, status. | M |
| TASK-03 | Unlimited subtasks with independent completion; parent shows `n/m`. | M |
| TASK-04 | Recurring tasks: daily, weekly (by weekday set), monthly (by date or nth weekday), custom interval; completion spawns the next instance. | M |
| TASK-05 | Views: Today, Upcoming, By category, By project, Completed. | M |
| TASK-06 | Quick-add parses natural language (`"submit report friday 5pm p1 #uni"`). | S |
| TASK-07 | Reminders at a configurable lead time before due. | M |
| TASK-08 | AI scheduling proposes time blocks for open tasks against real calendar gaps, respecting energy patterns and the training window. | S (Phase 2) |
| TASK-09 | Completion history feeds the Analytics Center. | M |
| TASK-10 | Overdue tasks are visually distinct and roll forward without silently rescheduling. | M |

---

### 6.12 Module 12 — AI Assistant Hub (`AI`)

Full specification: `docs/11-ai-layer.md`.

| ID | Requirement | Priority |
|---|---|---|
| AI-01 | Dedicated hub listing available assistants: **Claude**, **Copilot**, **Coach** (custom, LifeDNA-tuned). | M |
| AI-02 | Architecture supports adding ChatGPT, Gemini, DeepSeek and Perplexity as adapters with no client change. | M |
| AI-03 | **AI Router** classifies each request by intent and dispatches to the correct provider. | M |
| AI-04 | Routing table (default): fitness/nutrition/recovery → **Coach**; documents, long-context analysis, reasoning → **Claude**; work, mail, meetings, Office artifacts → **Copilot**. | M |
| AI-05 | User can override the route by explicitly selecting an assistant; the override persists for that conversation. | M |
| AI-06 | Conversations persist with title, provider, message list and token accounting. | M |
| AI-07 | Responses stream token-by-token. | M |
| AI-08 | **Context injection**: the Coach receives a compact, structured snapshot of the user's real numbers (targets, today's intake, last 7 days of training, sleep, recovery, upcoming calendar). | M |
| AI-09 | Context injection is transparent — the user can view exactly what was sent and disable it per conversation. | M |
| AI-10 | Tool/function calling lets the assistant read app data and, with confirmation, write (log a meal, create a task, schedule a workout). | S |
| AI-11 | Every write proposed by an AI requires explicit user confirmation before execution. | M |
| AI-12 | Suggested prompts are contextual to the current state ("Why did my recovery drop?"). | S |
| AI-13 | Per-user daily token budget with graceful degradation and a clear message at the cap. | M |
| AI-14 | Safety layer intercepts out-of-scope requests (medical diagnosis, extreme restriction, PED dosing) and returns the escalation response. | M |
| AI-15 | Voice input for AI queries. | C |
| AI-16 | All provider keys are server-side only; the client never holds a model API key. | M |

---

### 6.13 Module 13 — FitnessDNA Engine (`DNA`)

Full specification: `docs/13-fitnessdna-engine.md`.

| ID | Requirement | Priority |
|---|---|---|
| DNA-01 | Nightly job builds a per-user `DailySignalVector` from all domains. | M (Phase 3) |
| DNA-02 | Deterministic rule engine generates candidate insights; each carries category, severity, confidence, evidence and a suggested action. | M |
| DNA-03 | LLM layer converts ranked candidates into natural language with a strict output schema. | M |
| DNA-04 | Insights are ranked by `impact × confidence × recency` and capped at 3 per surface. | M |
| DNA-05 | Users can rate insights; ratings feed a per-user relevance model. | M |
| DNA-06 | Insight actions are one tap (`Apply` adjusts the target / creates the task / edits the template). | M |
| DNA-07 | Correlation discovery over ≥ 28 days of data (e.g. sleep ↔ session volume) with an explicit "association, not causation" framing. | S |
| DNA-08 | Trend detection reports statistically meaningful changes only (≥ 1 SD from the trailing mean, minimum sample size enforced). | M |
| DNA-09 | Prediction: projected goal date and probability band at current trajectory. | S |
| DNA-10 | Every insight is reproducible: stored inputs + engine version regenerate the identical result. | M |

**Reference insight set (must be generable by the rule engine):**
- `"Increase calories by 200 — your weight has dropped 1.4 %/week for 2 weeks, above the 0.9 % ceiling for lean-mass retention."`
- `"Sleep dropped 14 % this week vs your 28-day average."`
- `"Increase incline bench by 2.5 kg — you completed all target reps at RPE ≤ 8 in your last two sessions."`
- `"You're ready for a PR — recovery 88, and your e1RM trend is +4.1 % over 3 weeks."`
- `"Protein intake is below target — 5 of the last 7 days averaged 168 g against a 200 g floor."`

---

### 6.14 Module 14 — Notifications Engine (`NOTIF`)

Full specification: `docs/14-notifications-engine.md`.

| ID | Requirement | Priority |
|---|---|---|
| NOTIF-01 | Categories: Hydration, Meal, Supplement, Workout, Sleep, Meeting, Task, Recovery, Insight, System. | M |
| NOTIF-02 | Each category is independently toggleable with its own schedule. | M |
| NOTIF-03 | Quiet hours (default 23:00–07:00) suppress all but critical categories. | M |
| NOTIF-04 | A global daily cap (default 9) drops the lowest-priority pending notifications. | M |
| NOTIF-05 | Notifications carry inline actions (`Log 250 ml`, `Taken`, `Snooze 15 min`, `Start workout`). | M |
| NOTIF-06 | Deterministic/time-based reminders are scheduled **locally** so they fire offline. | M |
| NOTIF-07 | Data-dependent notifications (insights, recovery, meeting changes) are delivered via FCM. | M |
| NOTIF-08 | Suppression rule: a reminder is cancelled if its underlying action is already satisfied. | M |
| NOTIF-09 | Notification history is browsable in-app for 30 days. | S |
| NOTIF-10 | Adaptive timing shifts a reminder toward the time the user historically acts on it. | C (Phase 3) |

---

### 6.15 Module 15 — Analytics Center (`ANLY`)

| ID | Requirement | Priority |
|---|---|---|
| ANLY-01 | Weekly report generated every Monday 06:00 local. | M (Phase 2) |
| ANLY-02 | Monthly report on the 1st, quarterly on Jan/Apr/Jul/Oct 1st. | S |
| ANLY-03 | Metrics: weight change, strength gains (e1RM by lift), workout frequency, volume per muscle, sleep quality, recovery trend, task completion rate, nutrition consistency (days within ±10 % of target), protein floor hit rate, supplement compliance, hydration adherence. | M |
| ANLY-04 | Each metric shows current period, previous period and delta with direction semantics (some metrics are "lower is better"). | M |
| ANLY-05 | Reports are shareable as a rendered image and exportable as PDF. | S |
| ANLY-06 | Full data export (JSON + CSV) on demand, emailed as a signed, expiring link. | M |
| ANLY-07 | Custom date-range comparison. | C |
| ANLY-08 | Report generation is idempotent per (user, period). | M |

---

## 7. Non-functional requirements

### 7.1 Performance

| ID | Requirement | Target |
|---|---|---|
| NFR-P01 | Cold start to interactive dashboard (mid-tier Android, cached) | ≤ 1.8 s P95 |
| NFR-P02 | Warm start | ≤ 600 ms P95 |
| NFR-P03 | Screen transition | ≤ 250 ms, 60 fps, no frame > 32 ms |
| NFR-P04 | Live Gym set write (local commit) | ≤ 50 ms |
| NFR-P05 | Food search P90 | ≤ 400 ms |
| NFR-P06 | AI first token P90 | ≤ 2.0 s |
| NFR-P07 | Full health sync (24 h window) | ≤ 8 s |
| NFR-P08 | APK size (release, arm64) | ≤ 42 MB |
| NFR-P09 | Memory (steady state) | ≤ 180 MB |
| NFR-P10 | Battery drain during a 75-min Live Gym session with BLE HR | ≤ 6 % |

### 7.2 Reliability & availability

| ID | Requirement |
|---|---|
| NFR-R01 | Crash-free sessions ≥ 99.6 %; crash-free users ≥ 99.85 %. |
| NFR-R02 | All user-generated writes succeed offline and sync on reconnect with no data loss. |
| NFR-R03 | Sync conflicts resolve by last-write-wins on `updatedAt`, except sets/logs which are additive and never overwritten. |
| NFR-R04 | Cloud Functions target 99.9 % monthly availability; every function is idempotent. |
| NFR-R05 | Firestore backups daily with 30-day point-in-time recovery. |
| NFR-R06 | Third-party outage (AI provider, calendar, Health Connect) degrades one feature, never the app. |
| NFR-R07 | Live Gym session state survives process death with ≤ 1 set of loss. |

### 7.3 Security

| ID | Requirement |
|---|---|
| NFR-S01 | TLS 1.3 for all transport; certificate pinning for the LifeDNA API domain. |
| NFR-S02 | Firestore security rules enforce strict per-user document ownership; deny by default. |
| NFR-S03 | OAuth refresh tokens are stored server-side only, encrypted with Cloud KMS. |
| NFR-S04 | Local sensitive cache is encrypted (SQLCipher / EncryptedSharedPreferences / Keychain). |
| NFR-S05 | No PII or health data is written to logs or analytics events. |
| NFR-S06 | AI provider keys reside in Secret Manager, rotated quarterly. |
| NFR-S07 | Per-user rate limits on all callable functions; abuse triggers exponential backoff. |
| NFR-S08 | Dependency scanning and SAST run on every PR; release blocked on high severity. |

### 7.4 Privacy & compliance

| ID | Requirement |
|---|---|
| NFR-C01 | GDPR: lawful basis is consent for health data; consent is granular, logged and revocable. |
| NFR-C02 | Right to access, portability, rectification and erasure, fulfilled in ≤ 30 days. |
| NFR-C03 | Data minimization: only fields with a stated product purpose are collected. |
| NFR-C04 | Health data is never used for advertising and is never sold. |
| NFR-C05 | Data sent to AI providers is minimized, and zero-data-retention terms are required contractually. |
| NFR-C06 | Google Play Health apps policy and Health Connect data-usage policy are satisfied. |
| NFR-C07 | Regional data residency (EU) is supported at the Firestore instance level. |
| NFR-C08 | Under-18 accounts are not permitted in v1. |

### 7.5 Accessibility

| ID | Requirement |
|---|---|
| NFR-A01 | WCAG 2.1 AA contrast for all text and meaningful UI. |
| NFR-A02 | Full TalkBack/VoiceOver support with semantic labels on every interactive element. |
| NFR-A03 | Supports 200 % text scaling without truncation or overlap. |
| NFR-A04 | Minimum touch target 48 × 48 dp (64 dp in Live Gym Mode). |
| NFR-A05 | No information conveyed by colour alone; every state carries an icon or label. |
| NFR-A06 | Respects reduce-motion; animation-free path is fully functional. |

### 7.6 Localization

| ID | Requirement |
|---|---|
| NFR-L01 | v1 ships English; the string layer is externalized (ARB) from day one. |
| NFR-L02 | RTL layout support is verified in CI (Arabic is the first planned locale). |
| NFR-L03 | Units are user-selectable (kg/lb, cm/in, ml/fl oz, kcal/kJ) and stored canonically in metric. |
| NFR-L04 | Dates, times and numbers follow device locale. |

### 7.7 Maintainability

| ID | Requirement |
|---|---|
| NFR-M01 | Domain layer has zero Flutter/Firebase imports, enforced by a CI import-lint rule. |
| NFR-M02 | ≥ 80 % unit coverage on domain + data layers; ≥ 60 % overall. |
| NFR-M03 | Every module is independently testable with fake repositories. |
| NFR-M04 | Public APIs are versioned; breaking changes require a migration note. |
| NFR-M05 | Feature flags via Remote Config for every Phase 2/3 module. |

---

## 8. User stories

Format: `As a <persona>, I want <capability>, so that <outcome>.` — each with acceptance
criteria in Given/When/Then. The full estimated set lives in `17-mvp-backlog.md`; this
section states the epics and their headline stories.

### Epic A — Onboarding

**A-1** As a new user, I want to set up my profile and goals in under three minutes, so
that the app is useful immediately.
- **Given** I have installed the app and created an account
- **When** I complete onboarding
- **Then** I see a dashboard populated with my computed calorie and macro targets
- **And** total elapsed time from account creation to dashboard is under 180 s

**A-2** As a returning beginner, I want to start with only two modules, so that I am not
overwhelmed.
- **Given** I selected "Nutrition" and "Workouts" at onboarding
- **When** the dashboard renders
- **Then** only those modules' cards appear, and locked modules show their unlock condition

### Epic B — Daily operation

**B-1** As Youssef, I want to see how much protein I still owe today, so that I can fix it
before bed.
- **Given** I have logged 168 g against a 200 g floor
- **When** I open the dashboard
- **Then** the protein ring shows 168/200 and the Next Action card reads
  `"You are currently 32 g below protein target"` with a `Log protein` action

**B-2** As Dina, I want my day's plan to reflect my real calendar, so that I schedule
training in a slot that actually exists.
- **Given** my calendar has a meeting from 18:00–19:15
- **When** the dashboard computes today's plan
- **Then** the workout block is proposed outside that window, inside my gym window
- **And** if no slot fits, I am offered a shortened session variant

### Epic C — Training execution

**C-1** As Youssef, I want to log a set in one tap while holding my phone in one hand, so
that I do not break my rest rhythm.
- **Given** I am in Live Gym Mode on set 2 of 4 of Incline Dumbbell Press
- **When** I tap `Complete Set`
- **Then** the set is written locally in ≤ 50 ms, the rest timer starts at the exercise's
  rest value, and the set counter advances to 3 of 4

**C-2** As Youssef, I want to know what I lifted last time without leaving the screen, so
that I can beat it.
- **Given** I performed this exercise 4 days ago
- **When** the exercise loads in Live Gym Mode
- **Then** each set row is pre-filled with the previous session's weight and reps, labelled
  as the previous value, not as a logged value

### Epic D — Recovery and adaptation

**D-1** As Dina, I want the app to downgrade my session when I am wrecked, so that I stay
consistent instead of injured.
- **Given** my Recovery Score is 28 and today's plan is a heavy lower session
- **When** I open the dashboard
- **Then** the Next Action card recommends a reduced-volume variant with a one-tap `Apply`
- **And** applying it swaps the template and records the reason

### Epic E — Intelligence

**E-1** As Karim, I want to see exactly why a recommendation was made, so that I can trust
or challenge it.
- **Given** an insight says `"Increase calories by 200"`
- **When** I tap it
- **Then** I see the input signals, the rule that fired, the engine version and the
  computed values

**E-2** As Youssef, I want to ask the Coach a question about my own numbers, so that I get
an answer specific to me rather than generic advice.
- **Given** I ask `"Why is my bench stalling?"`
- **When** the Coach responds
- **Then** the answer references my actual last-8-session bench data, my sleep average and
  my calorie adherence
- **And** I can view the exact context that was sent

### Epic F — Integrations

**F-1** As Youssef, I want my Galaxy Fit 3 sleep and steps in LifeDNA, so that recovery is
computed from real physiology.
- **Given** I have connected Health Connect and granted sleep + steps permissions
- **When** sync completes
- **Then** last night's sleep session and today's steps appear on the dashboard
- **And** re-running the sync creates zero duplicate records

---

## 9. Assumptions

| # | Assumption | Risk if wrong | Mitigation |
|---|---|---|---|
| AS-1 | Health Connect is available on the target Android device population (Android 14+ ships it in-system). | Sync coverage gap on older devices | Samsung Health SDK fallback + manual entry |
| AS-2 | Galaxy Fit 3 exposes standard BLE HRS for live HR. | Live HR feature unavailable | Feature-flag it; band data still arrives via Health Connect |
| AS-3 | Users will grant calendar OAuth scopes. | Calendar module value collapses | Read-only first, write-scope requested only when the user creates an event |
| AS-4 | AI cost per active user stays ≤ $0.85/month at target usage. | Margin erosion | Token budgets, aggressive caching, small-model routing for classification |
| AS-5 | Open Food Facts coverage is adequate for the launch market. | Barcode misses | User-contributed cache + manual create; evaluate a commercial DB by Phase 2 |
| AS-6 | A single Firestore region meets latency needs at launch. | Latency for distant users | Multi-region evaluation gated on geography of the first 10k users |

## 10. Dependencies

| # | Dependency | Owner | Needed by |
|---|---|---|---|
| D-1 | Firebase project (dev/staging/prod) with billing | Backend | Sprint 1 |
| D-2 | Google Cloud OAuth consent screen verification (Calendar scopes) | Product | Sprint 6 |
| D-3 | Microsoft Entra app registration + Graph permissions consent | Backend | Sprint 6 |
| D-4 | Anthropic API account with production rate limits | AI | Sprint 7 |
| D-5 | Health Connect declaration + Play Console health-data form | Product | Sprint 8 |
| D-6 | Exercise database content (400+ items, licensed or authored) | Content | Sprint 4 |
| D-7 | Play Console account, signing keys, internal testing track | DevOps | Sprint 2 |
| D-8 | Legal: privacy policy, terms, health disclaimer | Legal | Sprint 9 |

## 11. Risks

| # | Risk | Likelihood | Impact | Mitigation |
|---|---|---|---|---|
| R-1 | Scope: 15 modules is a multi-year build attempted as an MVP | High | Critical | Phase gating is contractual, not aspirational. Phase 1 ships 9 modules with reduced depth; no Phase 2 work starts before Phase 1 is in production. |
| R-2 | Play Store rejection under the health-data policy | Medium | High | Complete the health declaration in Sprint 8, not at submission. Legal review of every health claim string. |
| R-3 | AI hallucinating unsafe advice | Medium | Critical | Deterministic engines own all numeric recommendations. The LLM only *phrases* what a rule already computed. Hard safety interceptor (`AI-14`). |
| R-4 | Samsung Health SDK access requires partner approval | Medium | Medium | Health Connect is the primary path specifically to avoid this dependency. |
| R-5 | Barcode database quality damages trust | Medium | Medium | Show data provenance on every food; allow correction; cache corrections per user. |
| R-6 | Notification fatigue drives uninstalls | Medium | High | Hard daily cap, suppression rules, and opt-out rate as a tracked counter-metric. |
| R-7 | Cross-domain value is not felt because users only use one module | High | High | The unlock mechanic and the Next Action card exist precisely to force cross-domain exposure early. |
| R-8 | Offline sync produces duplicates or lost sets | Medium | Critical | Additive, client-generated-ID writes for all logs; `docs/02 §7` sync contract; dedicated soak test in CI. |

## 12. Open questions

| # | Question | Owner | Needed by |
|---|---|---|---|
| Q-1 | Do we license a commercial food database (Nutritionix/Edamam) or ship Open Food Facts + curated core? | Product | Sprint 3 |
| Q-2 | Is Coach a fine-tuned model, or Claude with a system prompt + tools? (Cost vs. control.) | AI Lead | Sprint 7 |
| Q-3 | Pricing: single Pro tier, or Pro + AI add-on metered? | Product | Sprint 10 |
| Q-4 | Does Copilot integration ship as Graph-mediated productivity actions, or as a chat passthrough? | AI Lead | Sprint 7 |
| Q-5 | Do we store progress photos at all in v1 given the privacy surface? | Security + Product | Sprint 5 |

## 13. Launch criteria

v1.0 does not ship until **all** of the following are true:

1. Every `M`-priority requirement in §6 for MVP modules is implemented and accepted.
2. NFR-P01, P04, P06 and NFR-R01, R02 are met on the reference device matrix (`docs/18`).
3. Zero P0/P1 defects open; ≤ 5 P2 defects with agreed workarounds.
4. Security review signed off (`docs/19`), including a penetration test of the callable API.
5. Play Console health-data declaration approved.
6. Privacy policy, terms and health disclaimer published and linked in-app.
7. A 14-day internal dogfood cohort of ≥ 20 users shows crash-free sessions ≥ 99.6 % and
   no data-loss reports.
8. Rollback plan and a feature-flag kill switch verified for every Phase-2 flag.
