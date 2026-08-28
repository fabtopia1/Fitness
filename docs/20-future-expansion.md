# LifeDNA OS — Future Expansion

**Version:** 1.0
**Owner:** Product
**Horizon:** post-v2.0 (Sprint 25 onward)

---

## 1. The strategic arc

```
v1.0   LOG        The user tells LifeDNA what happened.
v1.1   MEASURE    LifeDNA knows what happened, physiologically.
v2.0   EXPLAIN    LifeDNA tells the user what it means.
v3.0   DECIDE     LifeDNA tells the user what to do next, and the plan adapts on its own.
v4.0   ORCHESTRATE LifeDNA runs the week — training, meals, time — and the user overrides.
```

Each step is only defensible if the previous one is trusted. Skipping to "decide" without
having earned "explain" produces a product people ignore.

---

## 2. v3.0 — Adaptive programming (post-Sprint 24, ~2 quarters)

### 2.1 Auto-regulating training

The program stops being a fixed schedule and becomes a controller.

| Capability | Mechanism |
|---|---|
| Daily session adjustment | Readiness score modifies volume and intensity before the session, not after it fails |
| Automatic deloads | ACWR, e1RM trend and recovery jointly trigger a deload week, proposed with one tap |
| Mesocycle progression | Volume ramps from MEV toward MRV across a block, then resets |
| Exercise rotation | Stalled lifts trigger a variation swap with matched stimulus |
| Fatigue-aware ordering | Priority lifts move earlier when readiness is marginal |

### 2.2 Adaptive nutrition

| Capability | Mechanism |
|---|---|
| Weekly calorie titration | Actual weight trend vs target rate → automatic ±100–250 kcal adjustment, always user-confirmed |
| Refeed and diet-break scheduling | Adherence, recovery and rate trends propose a planned break rather than an unplanned collapse |
| Training-day carb cycling | Carbohydrate distribution follows the actual session load |
| Metabolic adaptation detection | Sustained divergence between predicted and observed rate flags adaptation rather than blaming adherence |

### 2.3 Voice-first logging

`"Log 200 grams chicken and 250 rice"` → parsed → confirmed → written. The single largest
remaining friction in nutrition logging is typing, and the gym and kitchen are both
hands-busy environments.

---

## 3. v3.x — Platform expansion

| Surface | Value | Effort |
|---|---|---|
| **Wear OS app** | Log sets from the wrist; rest timer on the watch; HR without the phone | L |
| **Home-screen widgets** | Macro rings, next action, workout countdown | S |
| **Web dashboard** | Deep analysis, program building, data export on a real screen | L |
| **Tablet-optimised** | Program builder and analytics benefit enormously from width | M |
| **iOS Live Activities** | Rest timer and session progress on the lock screen | S |
| **Shortcuts / Assistant** | "Hey, log my creatine" | M |

---

## 4. v4.0 — The orchestration layer

The end state of the thesis: LifeDNA does not answer "what should I do next" — it **plans
the week** and the user edits it.

```
Sunday evening:
  LifeDNA reads next week's calendar, current recovery trajectory, program phase,
  goal progress and known constraints, then produces:

    • 6 training sessions placed in real calendar gaps, sized to the time available
    • meal plan with a shopping list, respecting the week's schedule
    • supplement timing aligned to the actual sessions
    • sleep windows protected as calendar blocks
    • deep-work blocks for open P1 tasks in the user's highest-completion hours

  The user reviews one screen and adjusts. LifeDNA re-plans around every change.

Mid-week: a meeting moves. The plan re-flows automatically and tells the user what changed
and why — never silently.
```

This requires everything before it: trustworthy physiology (v1.1), trustworthy explanation
(v2.0), and trustworthy adaptation (v3.0).

---

## 5. Intelligence roadmap

| Stage | Approach | Data required | Timeline |
|---|---|---|---|
| **Now** | Deterministic rules + LLM phrasing | Any | Shipped in v2.0 |
| **Next** | Per-user regression models for weight rate and strength trajectory | 60+ days | v3.0 |
| **Then** | Population priors with per-user Bayesian updating — a new user benefits from what similar users' data has shown | 10k+ users | v3.5 |
| **Later** | Sequence models over the daily signal vector for genuine multi-day prediction | 100k+ user-months | v4.0 |
| **Research** | Causal inference from natural experiments in each user's own history | Large longitudinal corpus | v4.0+ |

**The constraint that never relaxes:** every recommendation must remain explainable. A model
that cannot show its evidence does not ship, regardless of accuracy. That is the product's
identity, not a limitation of the current implementation.

---

## 6. Integration expansion

| Integration | Unlocks | Priority |
|---|---|---|
| Apple Health / HealthKit | iOS parity | Phase 2 (committed) |
| Garmin Connect | Serious endurance athletes | High |
| Oura | Best-in-class sleep data | High |
| WHOOP | Recovery-first users we would otherwise lose | Medium |
| Withings / smart scales | Automatic body composition | High |
| Continuous glucose monitors | Metabolic response to meals | Medium (regulatory review required) |
| Strava | Endurance training import | Medium |
| Notion / Todoist | Task import for users with an existing system | Medium |
| Slack | Work context for Copilot | Low |
| Spotify | Session soundtracking | Low |

---

## 7. Monetization roadmap

| Tier | Price | Contents |
|---|---|---|
| **Free** | — | Nutrition, workouts, Live Gym, tasks, 1 calendar, basic dashboard, 60k AI tokens/month |
| **Pro** | ~$9.99/mo | Recovery engine, FitnessDNA insights, analytics and reports, unlimited calendars, 250k AI tokens, body photos, export |
| **Pro+** *(v3.0)* | ~$19.99/mo | Adaptive programming, weekly orchestration, voice logging, priority AI, Wear OS |

**Never monetized:** the user's data. No advertising, no data sale, no "insights partner"
arrangement. This is a permanent constraint on the business model, stated here so that it is
a design input rather than a later debate.

**Additional lines under consideration:** a coach-facing seat (a coach manages athletes'
LifeDNA accounts with consent), and a team/corporate wellness tier — both explicitly out of
scope until the consumer product retains.

---

## 8. Technical debt to repay before v3.0

| Item | Why it becomes urgent |
|---|---|
| Food search → dedicated search service (Typesense/Algolia) | Firestore array-contains search does not scale past ~100k foods or fuzzy matching |
| Engines → Cloud Run services behind Pub/Sub | Scheduled Functions become the bottleneck past ~100k users |
| Rollup sharding | Hot daily documents under concurrent triggers |
| Analytics warehouse | BigQuery + dbt models needed before cohort analysis is credible |
| Client modularization | A single Flutter package with 15 modules slows builds; split into feature packages |
| Design tokens → a shared cross-platform package | Web and Wear OS need the same tokens |
| Engine parity → generated from one source | Two hand-written implementations will eventually drift, fixtures notwithstanding |

---

## 9. Ideas deliberately rejected

| Idea | Why not |
|---|---|
| Social feed and following | Contradicts the product's positioning; introduces moderation, comparison and privacy problems for no retention gain we believe in |
| Streaks with loss aversion | Punishes exactly the users a health product should support on a bad week |
| Public leaderboards | Encourages unsafe behaviour in a product that gives training and nutrition advice |
| In-app supplement sales | Destroys the neutrality of supplement recommendations |
| Photo-based calorie estimation | Current accuracy is not good enough to be the basis of a daily target |
| Genetic testing integration | Actionability for training and nutrition is weak; the privacy surface is enormous |
| Menstrual-cycle-based programming | Genuinely valuable, but requires dedicated clinical review — deferred, not rejected |
| An "AI does everything" chat-only interface | Users need to see their numbers. Chat is a lens, not a replacement for the instrument panel |

---

## 10. The three-year picture

> A user opens LifeDNA on Sunday evening. It shows them next week: six sessions placed in
> the gaps their real calendar leaves, meals that fit their schedule and their goal, sleep
> windows protected, deep work scheduled when they actually focus. They move two things. It
> re-plans around them.
>
> On Wednesday they sleep badly. Thursday's session is already adjusted when they wake, and
> the app tells them exactly why, with the numbers.
>
> In eight weeks they hit the target — and they can see, precisely, which decisions got
> them there.

That is the product. Everything in this repository is a step toward it.
