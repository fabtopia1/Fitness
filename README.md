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
| `docs/` | The complete product and engineering specification (PRD, architecture, schema, design system, flows, wireframes, API contracts, roadmap, backlog) |
| `app/` | Flutter application — Material 3, Clean Architecture, Riverpod |
| `functions/` | Firebase Cloud Functions (TypeScript) — AI router, engines, sync workers, schedulers |
| `firebase/` | Firestore security rules, composite indexes, Storage rules, project config |
| `.github/` | CI workflows |

---

## 2. Documentation index

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

**Client**
- Flutter 3.24+ / Dart 3.5+
- Material 3, dark-theme-first
- Riverpod 2 (code-generated providers)
- `go_router` navigation
- `drift` (SQLite) offline cache + Firestore persistence
- `freezed` + `json_serializable` models

**Backend**
- Firebase Authentication (Email, Google, Apple, Microsoft)
- Cloud Firestore (primary datastore, offline-first)
- Cloud Storage (progress photos, food images, exports)
- Cloud Functions v2 (TypeScript, Node 20)
- Cloud Messaging (push), Firebase Analytics, Crashlytics, Remote Config
- Cloud Scheduler + Cloud Tasks (engines, sync, digests)

**AI**
- Anthropic Claude (reasoning, coaching, documents, long-context analysis)
- Microsoft Copilot via Microsoft Graph (work, mail, meetings, productivity)
- Provider-agnostic `AiRouter` with pluggable adapters (OpenAI, Gemini, DeepSeek, Perplexity ready)

**Integrations**
- Samsung Health SDK (Android)
- Galaxy Fit 3 via BLE GATT + Samsung Health passthrough
- Google Calendar API, Microsoft Graph Calendar API
- Health Connect (Android system health aggregation)

---

## 4. Repository conventions

- **Branching** — `main` (protected) ← `develop` ← `feat/*`, `fix/*`, `chore/*`
- **Commits** — Conventional Commits (`feat(nutrition): add macro ring widget`)
- **Layering** — presentation → domain ← data. The domain layer imports nothing from Flutter or Firebase.
- **Every feature module** has `domain/`, `data/`, `presentation/` and mirrors that structure in `test/`.

---

## 5. What is built, and what is specified

This repository contains a **complete specification** and a **working
implementation of its foundation**. The distinction is stated explicitly
because "production-ready" applied to fifteen modules would not be true, and
the phase gates in [docs/16](docs/16-roadmap-sprints.md) exist precisely to
stop that claim being made.

| Area | State |
|---|---|
| Specification (`docs/`, 21 documents) | **Complete.** Every module has requirements, contracts, schema, screens and acceptance criteria |
| Deterministic engines (Dart **and** TypeScript) | **Complete and verified.** Macro, recovery, load, e1RM/PR, priority. 262 parity assertions across 31 shared fixtures |
| Design system | **Complete.** Tokens, both themes, 9 components, widget-tested |
| Screens | Dashboard · Nutrition · Add Food · Train · **Live Gym Mode** built. Plan and Me are placeholders naming their sprint |
| Data layer | Reference in-memory implementations of the full repository contracts, modelling the production offline-first write ordering |
| Firestore rules + 26 indexes | **Complete** |
| Cloud Functions | Engines, error registry, redacting logger and the nutrition rollup trigger built; the rest have fixed contracts in [docs/09](docs/09-api-contracts.md) |
| CI | Parity gate, layer boundaries, colour discipline, secret scanning |

**The parts that are hard to get right are real and tested. The parts that are
mechanical are specified.** Wiring Firestore behind the repository interfaces
is two provider overrides — see [`app/README.md`](app/README.md) §3.

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
# 1. Flutter app
cd app
flutter pub get
dart run build_runner build --delete-conflicting-outputs
flutter run --flavor dev

# 2. Cloud Functions
cd functions
npm install
npm run build
npm run serve          # local emulator

# 3. Firebase emulator suite (auth + firestore + functions + storage)
firebase emulators:start --import=./firebase/seed
```

Configuration files that are intentionally **not** committed: `google-services.json`,
`GoogleService-Info.plist`, `firebase_options.dart`, `functions/.env`. See
`functions/.env.example` and `docs/19-security-privacy.md` for the required keys.

---

## 7. Module map

| # | Module | Phase | Docs |
|---|---|---|---|
| 1 | Personal Dashboard | MVP | [PRD §6.1](docs/01-prd.md) |
| 2 | Nutrition Center | MVP | [PRD §6.2](docs/01-prd.md) |
| 3 | Supplement System | MVP | [PRD §6.3](docs/01-prd.md) |
| 4 | Workout Center | MVP | [PRD §6.4](docs/01-prd.md) |
| 5 | Live Gym Mode | MVP | [PRD §6.5](docs/01-prd.md) |
| 6 | Body Composition Center | Phase 2 | [PRD §6.6](docs/01-prd.md) |
| 7 | Recovery Engine | Phase 2 | [Recovery Engine](docs/12-recovery-engine.md) |
| 8 | Samsung Health Integration | MVP | [Integrations](docs/10-integrations.md) |
| 9 | Galaxy Fit 3 Integration | Phase 2 | [Integrations](docs/10-integrations.md) |
| 10 | Calendar Center | MVP | [Integrations](docs/10-integrations.md) |
| 11 | Task Manager | MVP | [PRD §6.11](docs/01-prd.md) |
| 12 | AI Assistant Hub | MVP | [AI Layer](docs/11-ai-layer.md) |
| 13 | FitnessDNA Engine | Phase 3 | [FitnessDNA](docs/13-fitnessdna-engine.md) |
| 14 | Notifications Engine | MVP | [Notifications](docs/14-notifications-engine.md) |
| 15 | Analytics Center | Phase 2 | [Analytics](docs/15-analytics.md) |

---

## 8. Health & safety position

LifeDNA OS produces **training, nutrition and lifestyle guidance for healthy adults**.
It is not a medical device, does not diagnose, and does not treat. Every generated
recommendation carries a provenance record and every AI surface is bounded by the
safety policy in [`docs/11-ai-layer.md` §8](docs/11-ai-layer.md). Red-flag inputs
(disordered-eating signals, extreme deficits, cardiac symptoms) route to a
non-negotiable escalation path rather than to a coaching response.
