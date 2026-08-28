# LifeDNA OS — Roadmap & Sprint Plan

**Version:** 1.0
**Owner:** Product
**Sprint length:** 2 weeks
**Assumed team:** 2 Flutter engineers · 1 backend engineer · 1 designer (0.5 FTE from S5) ·
1 QA (0.5 FTE from S7) · 1 product/founder

---

## 1. The scope reality

Fifteen modules is a multi-year product. Attempting it as an MVP is the single largest risk
in this project (`docs/01 §11 R-1`). The phase gates below are therefore **contractual**:

> **No Phase 2 work begins before Phase 1 is in production with real users.**

Phase 1 ships nine modules at reduced depth. It is a complete, coherent product on its own —
a person can run an entire training block on it. It is not a demo.

---

## 2. Phase overview

| Phase | Duration | Sprints | Ships | Outcome |
|---|---|---|---|---|
| **0 — Foundation** | 4 weeks | 1–2 | Architecture, design system, auth, CI/CD | A running app skeleton with a real login |
| **1 — MVP** | 20 weeks | 3–12 | Dashboard, Nutrition, Supplements, Workout, Live Gym, Calendar, Tasks, Notifications, Health sync, AI Hub | Public beta |
| **2 — Physiology & Insight** | 12 weeks | 13–18 | Galaxy Fit 3, Recovery Engine, Body Center, Analytics, iOS | v1.1 — the recovery loop closes |
| **3 — Intelligence** | 12 weeks | 19–24 | FitnessDNA, AI coaching, predictions, advanced reports | v2.0 — the differentiator ships |

**Total to v2.0: ~48 weeks.**

---

## 3. Phase 0 — Foundation (Sprints 1–2)

### Sprint 1 — Skeleton

| # | Deliverable | Owner | Points |
|---|---|---|---|
| 1.1 | Flutter project, flavours (dev/staging/prod), folder architecture per `docs/07` | Mobile | 5 |
| 1.2 | Firebase projects ×3, Auth, Firestore, Storage, Functions initialised | Backend | 5 |
| 1.3 | Design system: tokens, theme extensions, typography, `LdCard`, `LdPrimaryButton`, `LdMetricTile` | Mobile + Design | 8 |
| 1.4 | `go_router` with shell route, 5 tabs, guards | Mobile | 5 |
| 1.5 | Riverpod setup, `Result`/`Failure`, logger with redaction | Mobile | 3 |
| 1.6 | Drift database, migrations, encrypted store | Mobile | 5 |
| 1.7 | CI: analyze, test, import-lint, build on PR | Backend | 5 |
| 1.8 | Firestore rules v1 + emulator seed data | Backend | 5 |
| | **Total** | | **41** |

**Exit criteria:** the app builds for all three flavours, boots to a themed empty dashboard,
CI is green on a PR, and the emulator suite runs locally.

### Sprint 2 — Auth and onboarding

| # | Deliverable | Owner | Points |
|---|---|---|---|
| 2.1 | Email/password auth + verification + reset | Mobile | 5 |
| 2.2 | Google, Apple, Microsoft OAuth | Mobile | 8 |
| 2.3 | `onUserCreate` trigger: seed user doc, settings, defaults | Backend | 5 |
| 2.4 | Onboarding flow, 6 steps, progress, back-safe | Mobile + Design | 8 |
| 2.5 | `MacroCalculator` (Dart + TS) with shared golden fixtures | Mobile + Backend | 8 |
| 2.6 | Auth + onboarding guards, deep-link resolution | Mobile | 3 |
| 2.7 | Play Console setup, signing, internal testing track | Backend | 3 |
| | **Total** | | **40** |

**Exit criteria:** a real user can install from the internal track, create an account,
complete onboarding, and see computed targets. Time from install to dashboard ≤ 180 s.

---

## 4. Phase 1 — MVP (Sprints 3–12)

### Sprint 3 — Nutrition foundation
- Food entity, local index of 5 000 foods shipped as an asset (8)
- Food search with local-first, remote fallback `foodSearch` callable (8)
- Nutrition day view, meal slots, entry list (8)
- `LogFoodUseCase`, portion sheet, optimistic write (8)
- `onNutritionLogWrite` rollup trigger (5)
**Total 37** · *Exit: a meal can be logged offline and the day total is correct.*

### Sprint 4 — Nutrition depth
- Macro rings, `LdProgressRing`, `LdMacroRingCluster` (8)
- Barcode scanner + `barcodeLookup` + Open Food Facts adapter (8)
- Custom foods and recipes (5)
- Meal templates: create, apply, favourites (5)
- Water tracking + quick actions (3)
- Recent/favourites tabs, quick-add (5)
**Total 34** · *Exit: median time to log a full meal ≤ 12 s in a timed internal test.*

### Sprint 5 — Workout foundation
- Exercise database (400+) as a shipped asset + search (8)
- Workout templates: CRUD, exercise picker, supersets (8)
- Programs, weekly schedule, the seeded 8-week recomposition program (8)
- Session bootstrap, "last performance" prefill index (8)
- `E1rmCalculator` + PR detection (Dart + TS fixtures) (5)
**Total 37** · *Exit: a template can be built and a session started with prefilled values.*

### Sprint 6 — Live Gym Mode ★
- Live Gym screen: layout, steppers, RPE chips, one-hand ergonomics (13)
- `CompleteSetUseCase`, local-first write path, outbox (8)
- Rest timer + overlay + haptics + background notification (8)
- Session state checkpointing, process-death recovery, resume banner (8)
- Superset and drop-set handling (5)
- Session summary, session RPE, finalize (5)
**Total 47 — the largest sprint in the plan, deliberately.**
*Exit: a full 22-set session completes in airplane mode, survives a force-stop, and
median taps per set ≤ 2.*

### Sprint 7 — Calendar & Tasks
- Google Calendar OAuth, `calendarConnect`, calendar picker (8)
- Microsoft Graph calendar connect (5)
- Delta sync (server) + local cache + day/week views (8)
- `calendarWriteEvent` + incremental consent flow (5)
- Task CRUD, subtasks, priorities, categories, recurrence (8)
- Task views, swipe actions, quick-add with NL parsing (5)
**Total 39** · *Exit: two providers connect, events render offline, tasks recur correctly.*

### Sprint 8 — Health sync & Notifications
- Health Connect plugin (Kotlin), permission explanation screen (8)
- Normalizer, dedup, `healthSyncCommit`, backfill worker (8)
- Sync status screen, precedence settings (5)
- Notification engine: categories, channels, local scheduling (8)
- Suppression rules, quiet hours, daily cap (5)
- Inline actions + deep links (5)
**Total 39** · *Exit: 90-day backfill completes with zero duplicates; a suppressed meal
reminder never fires.*

### Sprint 9 — Dashboard & Supplements
- `DashboardSnapshot` composition, single-read rollup path (8)
- All dashboard cards (13)
- `PriorityEngine` → Next Action card (8)
- Supplements: catalogue, stack CRUD, schedules, anchors (8)
- Supplement logging, inventory, low stock, compliance (5)
**Total 42** · *Exit: dashboard cold start ≤ 1.8 s P95; Next Action reproduces all four
reference strings from `docs/01 §6.1`.*

### Sprint 10 — AI Hub
- `aiChat` / `aiStream` callables, middleware chain, budgets (8)
- AI Router: rule pass, model pass, confidence gate (8)
- `ContextBuilder` + transparency sheet (8)
- Claude, Coach and Copilot adapters (8)
- Safety interceptor + evaluation suite (8)
- Hub UI, conversations, streaming, suggested prompts (8)
**Total 48** · *Exit: routing accuracy ≥ 92 % on the labelled set; safety suite 100 %;
zero invented numbers on the fidelity set.*

### Sprint 11 — Hardening
- Offline soak test: 500-operation outbox drain, conflict cases (8)
- Performance pass against every NFR-P target (8)
- Accessibility pass: TalkBack, 200 % text, contrast goldens (8)
- Error states, empty states, failure copy across every screen (5)
- Crashlytics, analytics taxonomy, funnels wired (5)
- Security review + penetration test of the callable API (8)
**Total 42**

### Sprint 12 — Launch
- Play Console health-data declaration (5)
- Privacy policy, terms, health disclaimer, in-app links (3)
- Store listing, screenshots, feature graphic (5)
- Staged rollout tooling, kill switches verified (5)
- 14-day dogfood cohort (≥ 20 users), triage, fixes (13)
- Launch-criteria sign-off (`docs/01 §13`) (3)
**Total 34**

**→ v1.0 public beta**

---

## 5. Phase 2 — Physiology & Insight (Sprints 13–18)

| Sprint | Focus | Key deliverables | Points |
|---|---|---|---|
| 13 | Recovery Engine | Sleep/load/activity scores, composite, readiness, Dart mirror, fixtures | 42 |
| 14 | Recovery UX | Recovery detail screen, band UI, recommendation → plan adjustment, `dailyPlanBuilder` | 38 |
| 15 | Galaxy Fit 3 | BLE plugin, state machine, live HR in Live Gym, foreground service, battery | 40 |
| 16 | Body Center | All measurements, EWMA charts, goal projection, progress photos, comparison | 38 |
| 17 | Analytics | Weekly/monthly reports, metric grid, charts, narrative, export (JSON/CSV) | 42 |
| 18 | iOS parity | HealthKit, sign-in with Apple, platform QA, App Store submission | 45 |

**→ v1.1**

---

## 6. Phase 3 — Intelligence (Sprints 19–24)

| Sprint | Focus | Key deliverables | Points |
|---|---|---|---|
| 19 | Signal layer | `DailySignalVector`, aggregate library, 28-day windowing, backfill | 38 |
| 20 | Rule engine | ~30 rules with unit fixtures, ranking, confidence, dedup, suppression | 45 |
| 21 | Insight surface | Phrasing call + schema + template fallback, insight detail with provenance, feedback loop | 40 |
| 22 | AI coaching | Tool calling end-to-end, confirmation flow, adaptive program adjustment | 42 |
| 23 | Prediction & reports | Goal projection with bands, correlation discovery, quarterly reports, PDF/image | 40 |
| 24 | Polish & scale | Performance at 100k users, cost optimisation, index review, v2 launch | 35 |

**→ v2.0**

---

## 7. Milestones

| Milestone | Sprint | Gate |
|---|---|---|
| **M0** Skeleton | 2 | App installs from internal track; onboarding completes |
| **M1** Nutrition usable | 4 | Log a full day in ≤ 60 s total |
| **M2** Live Gym usable | 6 | Complete a real 75-min session offline |
| **M3** Feature complete | 10 | All MVP `M` requirements implemented |
| **M4** Beta | 12 | Launch criteria met; public beta live |
| **M5** Recovery loop | 14 | Recovery drives the daily plan end-to-end |
| **M6** Cross-platform | 18 | iOS in App Store review |
| **M7** Intelligence | 21 | Insights generated nightly with provenance |
| **M8** v2.0 | 24 | FitnessDNA in production |

---

## 8. Dependency and critical path

```
S1 Foundation
 └─ S2 Auth ──┬─ S3 Nutrition ── S4 Nutrition depth ─┐
              ├─ S5 Workout ──── S6 LIVE GYM ────────┤
              ├─ S7 Calendar/Tasks ──────────────────┼─ S9 Dashboard ─┐
              └─ S8 Health/Notifications ────────────┘                │
                                                     S10 AI Hub ──────┤
                                                                      ├─ S11 Harden ─ S12 Launch
                                                                      │
                              (Phase 2 blocked until v1.0 in production)
                                    S13 Recovery ← needs S8 health data
                                    S15 Fit 3    ← needs S8
                                    S17 Analytics← needs S13
                                    (Phase 3 blocked until Phase 2 in production)
                                    S19 Signals  ← needs S13 + S17
```

**Critical path:** S1 → S2 → S5 → S6 → S9 → S11 → S12. Live Gym Mode (S6) is the longest
single item and the highest-value differentiator; it is scheduled early enough that a
one-sprint overrun does not move the launch date.

---

## 9. Resourcing

| Sprint range | Flutter | Backend | Design | QA | Total FTE |
|---|---|---|---|---|---|
| 1–2 | 2 | 1 | 1 | 0 | 4 |
| 3–8 | 2 | 1 | 0.5 | 0 | 3.5 |
| 9–12 | 2 | 1 | 0.5 | 0.5 | 4 |
| 13–18 | 2 | 1 | 0.5 | 1 | 4.5 |
| 19–24 | 2 | 1.5 (AI) | 0.5 | 1 | 5 |

Velocity assumption: **38–42 points per sprint** at 4 FTE, established from Sprints 1–2 and
re-baselined every three sprints.

---

## 10. Risk-adjusted schedule

| Risk | Buffer |
|---|---|
| Live Gym complexity underestimated | S6 is sized at 47 points against a 40-point norm; S7 carries a 5-point reserve |
| Play health-data declaration rejected | Declaration submitted in S8, not S12 — four sprints of recovery time |
| OAuth verification delays (Google/Microsoft) | Started in S2, needed in S7 |
| Health Connect device fragmentation | S8 includes a 3-device test matrix; Samsung SDK fallback is scoped but not built unless needed |
| AI cost overrun | S10 includes budget enforcement before public beta, not after |

**Overall schedule confidence:** 70 % for M4 (beta) within ±2 sprints. The plan assumes no
team changes; a single engineer departure moves M4 by approximately 3 sprints.

---

## 11. Definition of done

A story is done when **all** of the following are true:

1. Code merged to `develop` with review approval.
2. Unit tests for domain and data layers; widget tests for new UI.
3. Engine changes include fixtures passing in **both** Dart and TypeScript.
4. Acceptance criteria demonstrably met, verified by someone other than the author.
5. Offline behaviour verified where the story touches user writes.
6. Accessibility verified: TalkBack labels, 48 dp targets, 200 % text.
7. Analytics events emitted per `docs/15`.
8. No new lint warnings; no new import-lint violations.
9. Strings externalized to ARB.
10. Documentation updated if a contract in `docs/03` or `docs/09` changed.
