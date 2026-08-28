# LifeDNA OS

**Your Personal Performance Operating System**

LifeDNA OS is not a fitness tracker. It is a unified life-operations platform that
fuses training, nutrition, recovery, sleep, productivity, calendar, health analytics
and a multi-model AI layer into a single decision engine that continuously answers
one question:

> **"What should I do next to achieve my goals?"**

---

## 1. What this repository contains

| Path | Contents |
|---|---|
| `app/` | The Flutter application — **the shipped MVP** |
| `docs/mvp/` | **What was built**: 16 delivery documents, including the architecture audit and the production-readiness report |
| `docs/` (01–20) | The full-product specification from the architecture phase — fifteen modules, of which the MVP ships nine |
| `firebase/` | Firestore rules, index configuration, Storage rules, and a rules test suite that executes them |
| `functions/` | TypeScript mirror of the engines. **Not deployed by the MVP** — it exists so the parity fixtures bind both implementations |
| `test/fixtures/` | Golden engine fixtures executed by the Dart *and* TypeScript suites |
| `tool/` | The coverage gate and the independent fixture generator |
| `.github/` | CI workflows |

> **Start here:** [`docs/mvp/00-index.md`](docs/mvp/00-index.md) describes the
> application that exists. The numbered documents in `docs/` describe the
> product it is a subset of.

---

## 2. Documentation index

### The MVP that exists — `docs/mvp/`

| # | Document | Answers |
|---|---|---|
| 00 | [Index](docs/mvp/00-index.md) | What shipped, and what is deliberately absent |
| 01 | [Product architecture](docs/mvp/01-product-architecture.md) | How the app is put together, and why Hive is the source of truth |
| 02 | [Folder structure](docs/mvp/02-folder-structure.md) | Where every file lives |
| 03 | [Firestore schema](docs/mvp/03-firestore-schema.md) | What is stored, and the indexing strategy |
| 04 | [Security rules](docs/mvp/04-security-rules.md) | What stops one user reading another's data |
| 05 | [UI sitemap](docs/mvp/05-ui-sitemap.md) | Every screen and how it is reached |
| 06 | [User flows](docs/mvp/06-user-flows.md) | The journeys, as diagrams |
| 07 | [Sprint plan](docs/mvp/07-sprint-plan.md) | What was done, in order, and what is next |
| 08 | [CI/CD](docs/mvp/08-cicd.md) | What runs on every push |
| 09 | [Testing strategy](docs/mvp/09-testing-strategy.md) | What is tested, and what is not |
| 10 | [Completion checklist](docs/mvp/10-mvp-completion-checklist.md) | Feature-by-feature status |
| 11 | [Build checklist](docs/mvp/11-build-checklist.md) | Producing an installable artefact |
| 12 | [Launch checklist](docs/mvp/12-launch-checklist.md) | Store submission and beta rollout |
| 13 | [Risk assessment](docs/mvp/13-risk-assessment.md) | What could go wrong |
| 14 | [Technical debt](docs/mvp/14-technical-debt.md) | Everything knowingly left undone |
| 15 | [Production readiness](docs/mvp/15-production-readiness.md) | Ship / do-not-ship, with evidence |
| 16 | [Architecture audit](docs/mvp/16-architecture-audit.md) | 26 findings; 18 fixed |

### The full product specification — `docs/`

| # | Document | Purpose |
|---|---|---|
| 00 | [Documentation Index](docs/00-index.md) | Reading order and ownership map |
| 01 | [Product Requirements Document](docs/01-prd.md) | Vision, personas, user stories, functional & non-functional requirements |
| 02 | [System Architecture](docs/02-system-architecture.md) | C4 diagrams, layering, data flow, sync topology |
| 03 | [Database Schema](docs/03-database-schema.md) | Firestore collections, field contracts, indexes, rules |
| 04 | [Design System](docs/04-design-system.md) | Colour, type, spacing, elevation, glassmorphism, motion, components |
| 05 | [User Flows](docs/05-user-flows.md) | End-to-end flows per module |
| 06 | [Wireframes](docs/06-wireframes.md) | Screen-by-screen layout specification |
| 07 | [Flutter Project Structure](docs/07-flutter-project-structure.md) | Folder architecture and layer contracts |
| 08 | [Backend Architecture](docs/08-backend-architecture.md) | Cloud Functions, jobs, queues, schedulers |
| 09 | [API Contracts](docs/09-api-contracts.md) | Callable/REST endpoints with request & response payloads |
| 10 | [Integrations](docs/10-integrations.md) | Samsung Health, Galaxy Fit 3, Google/Outlook Calendar, Microsoft Graph |
| 11 | [AI Layer](docs/11-ai-layer.md) | Multi-assistant hub, AI router, prompt contracts, guardrails |
| 12 | [Recovery Engine](docs/12-recovery-engine.md) | Recovery, readiness, sleep and load algorithms |
| 13 | [FitnessDNA Engine](docs/13-fitnessdna-engine.md) | Insight generation, rule set, ML roadmap |
| 14 | [Notifications Engine](docs/14-notifications-engine.md) | Triggers, scheduling, quiet hours, delivery |
| 15 | [Analytics Center](docs/15-analytics.md) | Reporting model, metric definitions, rollups |
| 16 | [Roadmap & Sprint Plan](docs/16-roadmap-sprints.md) | Phases, sprints, milestones, resourcing |
| 17 | [MVP Backlog](docs/17-mvp-backlog.md) | Fully estimated, acceptance-criteria-bearing backlog |
| 18 | [Testing & QA Strategy](docs/18-testing-qa.md) | Test pyramid, coverage gates, device matrix |
| 19 | [Security & Privacy](docs/19-security-privacy.md) | Threat model, health-data handling, compliance |
| 20 | [Future Expansion](docs/20-future-expansion.md) | Post-v1 platform strategy |

---

## 3. Technology stack

What the shipped MVP actually uses.

**Client**
- Flutter **3.47.2** / Dart 3.13.2 (pinned; CI enforces the formatter of this SDK)
- Material 3, dark-theme-first
- Riverpod 2.6 — hand-written providers, **no code generation**
- `go_router` 14.6 with a single redirect for every auth decision
- **Hive** (AES-encrypted) as the source of truth; records stored as JSON strings
- `flutter_local_notifications` + `timezone` for reminders that need no network

**Backend**
- Firebase Authentication (email/password, Google)
- Cloud Firestore — a **replication target**, not the read path
- Firebase Analytics and Crashlytics, both consent-gated
- Firebase Messaging (instance obtained; no push is sent yet)
- **No Cloud Functions.** Every engine runs on the device
- **No Cloud Storage.** Progress photos never leave the phone

**AI**
- An on-device deterministic coach (`LocalCoach`) — rules over the user's own numbers
- Clipboard + deep-link shortcuts to Claude and Copilot
- **No AI API key exists anywhere in the app**, because a key inside an APK is a published key

**Integrations**
- Google Calendar, **read-only** scope
- Health Connect (the officially supported Android path to Samsung Health data) —
  Dart layer, permission state machine and UI complete; the native reader is Sprint 6

---

## 4. Repository conventions

- **Branching** — `main` (protected) ← `develop` ← `feat/*`, `fix/*`, `chore/*`
- **Commits** — Conventional Commits (`feat(nutrition): add macro ring widget`)
- **Layering** — presentation → domain ← data. The domain layer imports nothing from Flutter or Firebase.
- **Every feature module** has `domain/`, `data/`, `presentation/` and mirrors that structure in `test/`.

---

## 5. What is built

A **complete, runnable, installable MVP**. Nine modules, no placeholder
screens, no fake integrations, and no `TODO` in the code — the lint set makes
one a build error.

| Area | State |
|---|---|
| Authentication | Email, Google, and a first-class **local mode** for a build with no Firebase project |
| Dashboard | Today's macros, water, supplements, training, body trend, tasks |
| Nutrition | Food library with ranked search, portion logging, saved meals, water |
| Supplements | Stack, schedules, reminders, idempotent dose logging, adherence |
| Workout | Programs, exercise library, **Live Gym Mode** with rest timer and PR detection |
| Body | Weight and measurements, smoothed trend chart, device-local progress photos |
| Calendar | Tasks, events, read-only Google Calendar mirror, standalone reminders |
| Health sync | Architecture, API layer, permission handling, ready-to-enable — **and no invented data** |
| AI Hub | On-device coach with evidence, prompt templates, Claude/Copilot shortcuts |
| Offline-first | Every write commits to Hive, queues in a durable outbox, then replicates |
| Security rules | Written **and executed** — 39 tests against the real rules engine |
| Tests | 517 Flutter tests + 39 rules tests; **82.24 % coverage**, gated at 80 % |
| CI/CD | Six jobs: analyze, format, layers, tests, coverage, flavour build matrix, emulator journeys, rules, engine parity, secrets |

**Deliberately absent:** Galaxy Fit 3 Bluetooth, the FitnessDNA prediction
engine, ML, predictive analytics, voice, social, marketplace, subscriptions,
gamification. Each is in [`docs/20`](docs/20-future-expansion.md). None has a
stub or a disabled button in the app.

**One thing blocks public production:** no release binary has been built or run,
because the Android SDK cannot be installed in the environment this was
developed in. See
[`docs/mvp/15-production-readiness.md`](docs/mvp/15-production-readiness.md).

### The audit found 26 issues; 18 are fixed

Five would each have been a production incident, and none is visible by reading
the code:

1. The security rules demanded Firestore timestamps while the offline path
   replays ISO strings — **every cloud write would have been rejected**, silently.
2. Profile writes were routed to a phantom `users/{uid}/__profile__` collection.
3. Nothing pulled on sign-in, so a second device showed an empty app.
4. Pull stopped after 500 documents, truncating a restored training log.
5. Every settings switch threw in debug, because the controller read a provider
   after awaiting a write that changed it.

Full list: [`docs/mvp/16-architecture-audit.md`](docs/mvp/16-architecture-audit.md).

---

### Engine parity, and why it matters

The recovery and macro engines exist twice: in Dart so the client can recompute
instantly and offline, and in TypeScript because the server is authoritative
for what gets stored. They are kept in lockstep by fixtures that both suites
execute, generated by a third independent implementation of the published
formulas.

That arrangement immediately found a real bug. `Math.round` rounds half toward
+Infinity; Dart's `num.round()` rounds half **away from zero**. They agree on
positive halves and disagree on negative ones — and
`projectedWeeklyChangeKg` is negative for every user in a deficit. A value
landing on a `.5` boundary would have stored a different weekly target than the
one already shown to the user: silent, intermittent, and nearly unreproducible
in the field. See [`functions/README.md`](functions/README.md) §4.

---

## 6. Getting started

```bash
# The app runs with no Firebase project at all. That is local mode, and it is
# a supported path, not a debug hatch.
cd app
flutter pub get
flutter analyze --fatal-infos
flutter test                              # 517 tests
flutter run --flavor dev --dart-define=FLAVOR=dev

# Coverage, with the gate CI applies
flutter test --coverage && dart ../tool/coverage_gate.dart

# Security rules, executed against the emulator
cd ../firebase/rules-test && npm ci && npm run emulator   # 39 tests
```

With a Firebase project, add the configuration at build time — nothing is
committed:

```bash
flutter run --flavor dev \
  --dart-define=FLAVOR=dev \
  --dart-define=FIREBASE_API_KEY=... \
  --dart-define=FIREBASE_APP_ID=... \
  --dart-define=FIREBASE_SENDER_ID=... \
  --dart-define=FIREBASE_PROJECT_ID=...
```

Full instructions: [`docs/mvp/11-build-checklist.md`](docs/mvp/11-build-checklist.md).

Intentionally **not** committed: `google-services.json`,
`GoogleService-Info.plist`, `firebase_options.dart`, `android/key.properties`,
and any keystore. CI fails if one appears.

---

## 7. Module map

| # | Module | MVP | Where |
|---|---|---|---|
| 1 | Authentication & profile | ✅ shipped | `features/auth` |
| 2 | Personal dashboard | ✅ shipped | `features/dashboard` |
| 3 | Nutrition | ✅ shipped | `features/nutrition` |
| 4 | Supplements | ✅ shipped | `features/supplements` |
| 5 | Workout + **Live Gym Mode** | ✅ shipped | `features/workout` |
| 6 | Body tracking | ✅ shipped | `features/body` |
| 7 | Calendar, tasks, reminders | ✅ shipped | `features/calendar`, `features/reminders` |
| 8 | Samsung Health (via Health Connect) | ⚠️ ready to enable, no fabricated data | `features/health_sync` |
| 9 | AI Hub | ✅ shipped (on-device coach) | `features/ai_hub` |
| 10 | Galaxy Fit 3 (Bluetooth) | ⛔ out of scope | [docs/20](docs/20-future-expansion.md) |
| 11 | FitnessDNA prediction engine | ⛔ out of scope | [docs/13](docs/13-fitnessdna-engine.md) |
| 12 | Recovery engine | engine built and tested; not yet surfaced | `core/engines` |
| 13 | Analytics centre | ⛔ out of scope | [docs/15](docs/15-analytics.md) |
| 14 | Notifications engine | ✅ local reminders shipped | `core/notifications` |
| 15 | Social, marketplace, subscriptions | ⛔ out of scope | [docs/20](docs/20-future-expansion.md) |

---

## 8. Health & safety position

LifeDNA OS produces **training and nutrition information for healthy adults**.
It is not a medical device, does not diagnose, and does not treat. The
disclaimer appears on the welcome screen and in Settings.

The engines clamp what they will recommend, and every clamp is **surfaced
rather than hidden**: a requested pace above 1 % of bodyweight per week, a
deficit past 25 % or 1 000 kcal, and a calorie target below the sex-specific
floor are all reduced, and the app says so and why. Those limits are constants
in `MacroCalculator`, covered by golden fixtures, and mirrored in the
TypeScript implementation.

Every insight the on-device coach produces carries the numbers that produced
it, so guidance can always be traced back to the user's own data.
