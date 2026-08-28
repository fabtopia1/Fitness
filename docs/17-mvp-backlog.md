# LifeDNA OS — MVP Backlog

**Version:** 1.0
**Scope:** Phase 0 + Phase 1 (Sprints 1–12)
**Estimation:** Fibonacci story points (1, 2, 3, 5, 8, 13)
**Total:** 471 points across 12 sprints

Every story carries an ID, a requirement trace, an estimate and testable acceptance
criteria. `Req` references the functional requirement IDs in `docs/01 §6`.

---

## EPIC 0 — Foundation (41 pts)

| ID | Story | Req | Pts | Sprint |
|---|---|---|---|---|
| F-01 | Flutter project scaffolding with three flavours and the folder architecture | — | 5 | 1 |
| F-02 | Firebase projects (dev/staging/prod) with Auth, Firestore, Storage, Functions | — | 5 | 1 |
| F-03 | Design tokens, theme extensions, typography scale, dark + light themes | — | 5 | 1 |
| F-04 | Core widget set: `LdCard`, `LdPrimaryButton`, `LdMetricTile`, `LdSkeleton` | — | 3 | 1 |
| F-05 | Router with shell route, 5 tabs, guards, deep-link resolution | — | 5 | 1 |
| F-06 | Riverpod container, `Result`/`Failure`, `FailureMapper`, redacting logger | — | 3 | 1 |
| F-07 | Drift database, encrypted store, migrations, outbox table | — | 5 | 1 |
| F-08 | CI pipeline: analyze, test, import-lint, build APK/AAB on PR | — | 5 | 1 |
| F-09 | Firestore security rules v1 + emulator seed dataset | — | 5 | 1 |

**F-07 acceptance**
- *Given* the app is installed fresh, *when* it launches, *then* the encrypted Drift
  database is created with schema version 1 and the outbox table exists.
- *Given* schema version 1 exists, *when* a migration to version 2 is applied, *then* no
  user data is lost and a migration test asserts row counts before and after.

---

## EPIC 1 — Authentication & Onboarding (40 pts)

| ID | Story | Req | Pts | Sprint |
|---|---|---|---|---|
| A-01 | Email/password registration with verification email | AUTH-01, 04 | 5 | 2 |
| A-02 | Google Sign-In | AUTH-02 | 3 | 2 |
| A-03 | Sign in with Apple | AUTH-02 | 3 | 2 |
| A-04 | Microsoft OAuth with incremental Graph scopes | AUTH-02, 03 | 5 | 2 |
| A-05 | Session persistence and transparent token refresh | AUTH-05 | 2 | 2 |
| A-06 | `onUserCreate` trigger seeds user, settings, defaults, starter program | — | 5 | 2 |
| A-07 | Onboarding steps 1–4 (identity, body, goal, week) | AUTH-07, 09 | 8 | 2 |
| A-08 | `MacroCalculator` in Dart + TypeScript with shared golden fixtures | AUTH-08 | 5 | 2 |
| A-09 | Onboarding step 5 (targets preview with editable override) | AUTH-08 | 3 | 2 |
| A-10 | Onboarding step 6 (module selection, progressive disclosure) | AUTH-10 | 3 | 2 |
| A-11 | Account deletion callable + purge worker | AUTH-06 | 5 | 11 |
| A-12 | Biometric app lock | AUTH-11 | 3 | 11 |

**A-08 acceptance**
- *Given* a 21-year-old male, 174.5 cm, 90.1 kg, moderate activity, cut mode
- *When* targets are computed
- *Then* BMR = 1863, TDEE = 2889, training-day kcal = 2600 ± 25, protein floor = 200 g
- *And* the TypeScript implementation returns identical values for the same fixture
- *And* requesting a 1.5 %/week rate returns `clamped: true` with the rate reduced to the
  safe ceiling and a warning the UI must display

**A-07 acceptance**
- *Given* I am on step 3, *when* I press back, *then* step 2's values are preserved
- *And* no step presents more than 3 input fields
- *And* a progress indicator shows `n of 6` on every step

---

## EPIC 2 — Nutrition Center (71 pts)

| ID | Story | Req | Pts | Sprint |
|---|---|---|---|---|
| N-01 | Food entity, DTO, mapper; ship the top-5000 index as an asset into Drift | NUTR-02 | 8 | 3 |
| N-02 | Local-first food search with remote `foodSearch` fallback | NUTR-02 | 8 | 3 |
| N-03 | Nutrition day view with meal slots and entry list | NUTR-05 | 8 | 3 |
| N-04 | `LogFoodUseCase` + portion sheet + optimistic write | NUTR-01, 04, 06 | 8 | 3 |
| N-05 | `onNutritionLogWrite` rollup trigger (recompute, not increment) | — | 5 | 3 |
| N-06 | `LdProgressRing` + `LdMacroRingCluster` with animation and semantics | NUTR-11 | 8 | 4 |
| N-07 | Barcode scanner + `barcodeLookup` + Open Food Facts adapter + caching | NUTR-03 | 8 | 4 |
| N-08 | Custom foods and multi-ingredient recipes | NUTR-17 | 5 | 4 |
| N-09 | Meal templates: create from a day, apply in one tap, favourites | NUTR-12 | 5 | 4 |
| N-10 | Water tracking with containers, target, quick actions | NUTR-10 | 3 | 4 |
| N-11 | Recent / Favourites tabs and quick-add macros | NUTR-01, 18 | 5 | 4 |
| N-12 | Training-day vs rest-day target switching | NUTR-07, 08 | 3 | 4 |
| N-13 | Edit and delete entries with atomic total recomputation | NUTR-19 | 3 | 4 |
| N-14 | Meal reminders wired to the notification engine with suppression | NUTR-15 | 3 | 8 |
| N-15 | Protein floor surfaced separately from the protein target | NUTR-09 | 2 | 4 |

**N-02 acceptance**
- *Given* the local index is loaded, *when* I type "chick", *then* results render in ≤ 400 ms
  P90 measured on a mid-tier device
- *And* with the network off, local results still return
- *And* a term with no local match calls `foodSearch` and shows a loading row, not a blank list

**N-04 acceptance**
- *Given* I am offline, *when* I add 200 g of chicken breast to Lunch, *then* the entry
  appears immediately, the rings animate, the write is committed to Drift, and an outbox op
  is queued
- *And* on reconnect the Firestore document exists with the same client-generated ID
- *And* replaying the outbox op does not create a duplicate

**N-07 acceptance**
- *Given* a barcode present in Open Food Facts, *when* I scan it, *then* the portion sheet
  opens with the resolved food and a `community data` provenance chip
- *Given* an unknown barcode, *when* I scan it, *then* I am offered create-food with the
  barcode pre-filled
- *And* a previously-resolved barcode resolves from cache with no network call

---

## EPIC 3 — Supplement System (26 pts)

| ID | Story | Req | Pts | Sprint |
|---|---|---|---|---|
| S-01 | Supplement catalogue (10 seeded) + custom creation | SUPP-01, 02 | 5 | 9 |
| S-02 | Schedules: daily, weekdays, training/rest days, cyclical | SUPP-03 | 5 | 9 |
| S-03 | Timing anchors resolving to concrete times | SUPP-04 | 3 | 9 |
| S-04 | Dose logging from the dashboard chip and from a notification | SUPP-06 | 3 | 9 |
| S-05 | Inventory tracking with decrement on log | SUPP-07 | 3 | 9 |
| S-06 | Low-stock threshold and notification | SUPP-08 | 2 | 9 |
| S-07 | Compliance score, 30-day rolling, per supplement and overall | SUPP-10 | 3 | 9 |
| S-08 | Supplement reminders with suppression when already logged | SUPP-05 | 2 | 9 |

**S-05 acceptance**
- *Given* creatine has 62 servings remaining, *when* I log a 5 g dose, *then* it shows 61
- *And* when it reaches the low-stock threshold, exactly one notification fires (not one per
  subsequent dose)

---

## EPIC 4 — Workout Center (58 pts)

| ID | Story | Req | Pts | Sprint |
|---|---|---|---|---|
| W-01 | Exercise database (400+) shipped as an asset with faceted search | WORK-01, 02 | 8 | 5 |
| W-02 | Custom exercises | WORK-03 | 3 | 5 |
| W-03 | Workout templates CRUD with the exercise picker | WORK-04 | 8 | 5 |
| W-04 | Superset and circuit grouping via `groupId` | WORK-05 | 5 | 5 |
| W-05 | Programs with a weekly schedule; seed the 8-week recomposition program | WORK-06 | 8 | 5 |
| W-06 | "Last performance" index and session prefill | WORK-07 | 8 | 5 |
| W-07 | `E1rmCalculator` (Epley + Brzycki cross-check) Dart + TS | WORK-09 | 3 | 5 |
| W-08 | PR detection across all four record types | WORK-10 | 5 | 5 |
| W-09 | Exercise history screen with per-session sets and e1RM chart | WORK-12 | 5 | 9 |
| W-10 | Workout analytics: weekly volume per muscle, frequency, duration | WORK-13 | 5 | 9 |

**W-06 acceptance**
- *Given* I performed Incline DB Press 4 days ago at 30 kg × 10
- *When* I start a session containing that exercise
- *Then* each set row shows 30 kg × 10 as the previous value, visually distinct from a
  logged value
- *And* the prefill query executes in ≤ 100 ms from the local index

**W-08 acceptance**
- *Given* my best e1RM on this lift is 40.0 kg, *when* I log 32.5 kg × 10 (e1RM 43.3)
- *Then* a `best_e1rm` PR is created with `previousValue: 40.0` and `improvementPct: 8.25`
- *And* the same set logged twice does not create two PR records

---

## EPIC 5 — Live Gym Mode (47 pts)

| ID | Story | Req | Pts | Sprint |
|---|---|---|---|---|
| L-01 | Live Gym screen layout, one-hand ergonomics, wakelock | LIVE-01, 02, 19 | 13 | 6 |
| L-02 | `CompleteSetUseCase` with local-first commit and outbox enqueue | LIVE-13 | 8 | 6 |
| L-03 | Rest timer, overlay, ±15 s, skip, haptics, background notification | LIVE-04, 05, 06 | 8 | 6 |
| L-04 | Weight/rep steppers with configurable increments and numeric entry | LIVE-07 | 5 | 6 |
| L-05 | RPE chips and to-failure flag | LIVE-12 | 3 | 6 |
| L-06 | Session checkpointing and process-death recovery + resume banner | LIVE-14 | 8 | 6 |
| L-07 | Superset alternation and group-aware rest | LIVE-10 | 3 | 6 |
| L-08 | Drop-set sub-sets under a parent set | LIVE-11 | 3 | 6 |
| L-09 | Mid-session add/remove/reorder/replace exercises | LIVE-16 | 5 | 6 |
| L-10 | Session summary, session RPE, finalize, `onSessionFinalize` trigger | LIVE-17 | 5 | 6 |
| L-11 | Skip set/exercise with explicit marking | LIVE-15 | 2 | 6 |
| L-12 | Voice notes with on-device transcription | LIVE-09 | 5 | 11 |
| L-13 | Plate calculator | WORK-19 | 3 | 11 |

**L-02 acceptance** *(the flagship criterion)*
- *Given* I am in airplane mode on set 2 of 4
- *When* I tap `Complete Set`
- *Then* the set is committed to Drift in ≤ 50 ms (asserted by a benchmark test)
- *And* the rest timer starts automatically at the exercise's rest value
- *And* the set counter advances to 3 of 4
- *And* the total interaction is **1 tap** when weight and reps are unchanged

**L-06 acceptance**
- *Given* a session with 6 sets logged, *when* the app process is killed
- *Then* on relaunch a resume banner appears on every shell route
- *And* resuming restores all 6 sets, the current exercise, the elapsed duration and the
  set index, with at most 1 set of loss

---

## EPIC 6 — Calendar Center (26 pts)

| ID | Story | Req | Pts | Sprint |
|---|---|---|---|---|
| C-01 | Google Calendar OAuth + `calendarConnect` + calendar picker | CAL-01, 03 | 8 | 7 |
| C-02 | Microsoft Graph calendar connect | CAL-02 | 5 | 7 |
| C-03 | Server delta sync with sync tokens and 410 recovery | CAL-06 | 8 | 7 |
| C-04 | Day / 3-day / week / agenda views from the local cache | CAL-04, 12 | 8 | 7 |
| C-05 | Create/edit/delete events with incremental write-scope consent | CAL-05 | 5 | 7 |
| C-06 | LifeDNA blocks rendered distinctly; optional push to provider | CAL-07 | 5 | 7 |
| C-07 | Conflict detection between planned workouts and busy events | CAL-08 | 5 | 9 |

**C-03 acceptance**
- *Given* a valid sync token, *when* delta sync runs, *then* only changed events are fetched
- *Given* the provider returns 410 Gone, *when* sync runs, *then* a full resync executes for
  that calendar with no user-visible error and no duplicate events

---

## EPIC 7 — Task Manager (26 pts)

| ID | Story | Req | Pts | Sprint |
|---|---|---|---|---|
| T-01 | Task CRUD with all fields | TASK-02 | 5 | 7 |
| T-02 | Subtasks with independent completion and parent progress | TASK-03 | 3 | 7 |
| T-03 | Categories, priorities, tags | TASK-01 | 3 | 7 |
| T-04 | Recurrence (daily/weekly/monthly/custom) with instance spawning | TASK-04 | 8 | 7 |
| T-05 | Views: Today, Upcoming, Categories, Completed | TASK-05 | 5 | 7 |
| T-06 | Natural-language quick-add with a parsed preview | TASK-06 | 5 | 7 |
| T-07 | Task reminders with configurable lead time | TASK-07 | 3 | 8 |
| T-08 | Overdue handling: distinct, rolls forward, never silently rescheduled | TASK-10 | 2 | 7 |

**T-04 acceptance**
- *Given* a task recurring weekly on Mon/Wed/Fri, *when* I complete Monday's instance
- *Then* the next instance is created for Wednesday with a fresh id and `parentTaskId` set
- *And* completing an instance twice does not create two next instances

---

## EPIC 8 — Health Sync (29 pts)

| ID | Story | Req | Pts | Sprint |
|---|---|---|---|---|
| H-01 | Health Connect Kotlin plugin: permissions, read, changes token | SAMS-02, 03 | 8 | 8 |
| H-02 | Permission explanation screen preceding the system dialog | SAMS-03 | 3 | 8 |
| H-03 | Normalizer + idempotency key + local dedup | SAMS-06 | 5 | 8 |
| H-04 | `healthSyncCommit` with server-side dedup and rollup update | SAMS-06 | 5 | 8 |
| H-05 | 90-day backfill via a resumable Cloud Task | SAMS-05 | 5 | 8 |
| H-06 | Background sync (WorkManager 60 min) + foreground + pull-to-refresh | SAMS-04 | 3 | 8 |
| H-07 | Sync status screen with per-type detail, retry, full resync | SAMS-08 | 3 | 8 |
| H-08 | Source precedence settings and conflict resolution | SAMS-07 | 3 | 8 |
| H-09 | Graceful degradation for every permission-denial combination | SAMS-10 | 3 | 8 |
| H-10 | Write completed workouts back to Health Connect | SAMS-09 | 3 | 11 |

**H-03/H-04 acceptance**
- *Given* a 90-day backfill has completed, *when* I trigger a full resync
- *Then* zero duplicate `health_records` documents exist (asserted by a count query)
- *And* `daily_stats` values are unchanged

---

## EPIC 9 — Dashboard (34 pts)

| ID | Story | Req | Pts | Sprint |
|---|---|---|---|---|
| D-01 | `DashboardSnapshot` composition from a single `daily_stats` read | DASH-16 | 8 | 9 |
| D-02 | `PriorityEngine` producing the Next Action | DASH-02 | 8 | 9 |
| D-03 | Macro, hydration and supplement cards | DASH-03, 04, 14 | 5 | 9 |
| D-04 | Workout status card with state-matched CTA | DASH-05 | 3 | 9 |
| D-05 | Recovery and sleep cards (recovery stubbed until Phase 2) | DASH-06, 07 | 3 | 9 |
| D-06 | Schedule strip and tasks card | DASH-08, 09 | 3 | 9 |
| D-07 | Insights card | DASH-10 | 2 | 9 |
| D-08 | Offline rendering with a stale-data sync badge | DASH-11 | 3 | 9 |
| D-09 | Pull-to-refresh fan-out with per-source status | DASH-13 | 3 | 9 |
| D-10 | Card reordering and hiding, persisted per user | DASH-12 | 5 | 11 |

**D-02 acceptance**
- *Given* protein is 168 g against a 200 g floor and it is 21:00
- *When* the dashboard renders
- *Then* the Next Action card reads `"You are 32 g below your protein target"` with a
  `Log protein` action and a `Why?` affordance
- *And* the engine reproduces all four reference strings from `docs/01 §6.1` given their
  corresponding states

**D-01 acceptance**
- *Given* a warm cache, *when* the dashboard loads, *then* it issues exactly **one**
  Firestore document read for daily totals (asserted by an instrumented fake)
- *And* cold start to interactive is ≤ 1.8 s at P95 on the reference device

---

## EPIC 10 — Notifications (26 pts)

| ID | Story | Req | Pts | Sprint |
|---|---|---|---|---|
| P-01 | Notification channels, categories, per-category settings | NOTIF-01, 02 | 5 | 8 |
| P-02 | Local scheduling for deterministic reminders | NOTIF-06 | 5 | 8 |
| P-03 | FCM for data-dependent notifications | NOTIF-07 | 3 | 8 |
| P-04 | Suppression rules evaluated at fire time | NOTIF-08 | 5 | 8 |
| P-05 | Quiet hours with priority-based exemption | NOTIF-03 | 3 | 8 |
| P-06 | Daily cap with per-category sub-limits | NOTIF-04 | 3 | 8 |
| P-07 | Inline actions executing through the same use cases as the UI | NOTIF-05 | 5 | 8 |
| P-08 | Deep links including cold-start resolution | — | 3 | 8 |
| P-09 | In-app notification history (30 days) | NOTIF-09 | 2 | 11 |
| P-10 | Contextual permission request (never at launch) | — | 2 | 8 |

**P-04 acceptance**
- *Given* a meal reminder is scheduled for 09:00 and I log breakfast at 08:40
- *When* 09:00 arrives, *then* no notification is delivered
- *And* a record exists with `status: suppressed`, `suppressionReason: already_satisfied`

---

## EPIC 11 — AI Assistant Hub (48 pts)

| ID | Story | Req | Pts | Sprint |
|---|---|---|---|---|
| I-01 | `aiChat` + `aiStream` callables with the full middleware chain | AI-16 | 8 | 10 |
| I-02 | AI Router: rule pass, model pass, confidence gate, decision recording | AI-03, 04 | 8 | 10 |
| I-03 | `ContextBuilder` with the 4 000-token cap and deterministic compaction | AI-08 | 8 | 10 |
| I-04 | Context transparency sheet with a per-conversation disable toggle | AI-09 | 5 | 10 |
| I-05 | Claude and Coach adapters | AI-01 | 5 | 10 |
| I-06 | Copilot adapter (Graph-augmented) | AI-01 | 5 | 10 |
| I-07 | Safety interceptor (pre + post) and the evaluation suite | AI-14 | 8 | 10 |
| I-08 | Hub UI: assistant selector, conversation list, streaming bubbles | AI-01, 07 | 8 | 10 |
| I-09 | Assistant override persisted per conversation | AI-05 | 3 | 10 |
| I-10 | Token budgets with graceful degradation at the cap | AI-13 | 5 | 10 |
| I-11 | Contextual suggested prompts | AI-12 | 3 | 10 |
| I-12 | Tool calling with mandatory confirmation | AI-10, 11 | 8 | 11 |

**I-07 acceptance**
- *Given* any of the 80 adversarial prompts in the safety suite
- *When* it is submitted, *then* the correct escalation response is returned with no model
  call for pre-check categories
- *And* the safety suite passes at 100 % — a regression blocks release unconditionally

**I-03 acceptance**
- *Given* a user with 6 months of data, *when* context is assembled
- *Then* the payload is ≤ 4 000 tokens
- *And* `profile`, `goal`, `targets` and `today` are always present
- *And* the compaction order matches `docs/11 §4.3` exactly

---

## EPIC 12 — Hardening & Launch (76 pts)

| ID | Story | Pts | Sprint |
|---|---|---|---|
| Q-01 | Offline soak test: 500-op outbox drain, all conflict classes | 8 | 11 |
| Q-02 | Performance pass against every NFR-P target on the device matrix | 8 | 11 |
| Q-03 | Accessibility: TalkBack, 200 % text, contrast goldens, reduce-motion | 8 | 11 |
| Q-04 | Error, empty and offline states across every screen | 5 | 11 |
| Q-05 | Analytics taxonomy and funnels wired end to end | 5 | 11 |
| Q-06 | Security review + penetration test of the callable API | 8 | 11 |
| Q-07 | Localization scaffolding, ARB extraction, RTL verification | 5 | 11 |
| Q-08 | Play Console health-data declaration | 5 | 12 |
| Q-09 | Privacy policy, terms, health disclaimer, in-app surfacing | 3 | 12 |
| Q-10 | Store listing, screenshots, feature graphic | 5 | 12 |
| Q-11 | Staged rollout tooling and verified kill switches | 5 | 12 |
| Q-12 | 14-day dogfood cohort with triage and fixes | 13 | 12 |

---

## Summary

| Epic | Points | % |
|---|---|---|
| 0 Foundation | 41 | 8.7 |
| 1 Auth & Onboarding | 40 | 8.5 |
| 2 Nutrition | 71 | 15.1 |
| 3 Supplements | 26 | 5.5 |
| 4 Workout | 58 | 12.3 |
| 5 Live Gym | 47 | 10.0 |
| 6 Calendar | 26 | 5.5 |
| 7 Tasks | 26 | 5.5 |
| 8 Health Sync | 29 | 6.2 |
| 9 Dashboard | 34 | 7.2 |
| 10 Notifications | 26 | 5.5 |
| 11 AI Hub | 48 | 10.2 |
| 12 Hardening & Launch | 76 | 16.1 |
| **Total** | **548** | |

> The epic total (548) exceeds the sprint-plan total (471) because Epics 1, 2, 4, 5, 9, 10
> and 11 each carry stories scheduled into Sprint 11 (hardening) rather than their home
> sprint. The sprint plan in `docs/16` is the schedule of record; this table is the
> inventory of record.

**Cut list, in the order we would cut it** if velocity underperforms:

1. L-13 plate calculator (3)
2. L-12 voice notes (5)
3. D-10 dashboard card reordering (5)
4. N-08 recipes — keep custom foods only (5)
5. C-06 push LifeDNA blocks to the provider (5)
6. T-06 natural-language quick-add (5)
7. I-11 suggested prompts (3)
8. A-12 biometric lock (3)

**Never cut:** L-02 (offline set writes), H-03/H-04 (dedup), I-07 (safety), Q-06 (security),
Q-03 (accessibility), P-04 (suppression). These are correctness and trust, not features.
