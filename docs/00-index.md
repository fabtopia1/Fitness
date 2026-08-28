# LifeDNA OS — Documentation Index

**Version:** 1.0
**Status:** Approved for build
**Owner:** Founding product/engineering team
**Last updated:** 2026-08-28

---

## 1. How to read this specification

This documentation set is written to be **executable**: an engineer joining on day one
should be able to open a document, find a screen or an endpoint, and build it without
asking a clarifying question. Every document therefore states contracts, not intentions.

### Reading order by role

**Product / founder**
`01-prd.md` → `16-roadmap-sprints.md` → `17-mvp-backlog.md` → `20-future-expansion.md`

**Flutter engineer**
`07-flutter-project-structure.md` → `04-design-system.md` → `06-wireframes.md` →
`05-user-flows.md` → `09-api-contracts.md` → `03-database-schema.md`

**Backend engineer**
`02-system-architecture.md` → `03-database-schema.md` → `08-backend-architecture.md` →
`09-api-contracts.md` → `19-security-privacy.md`

**AI engineer**
`11-ai-layer.md` → `12-recovery-engine.md` → `13-fitnessdna-engine.md` → `09-api-contracts.md`

**Designer**
`04-design-system.md` → `06-wireframes.md` → `05-user-flows.md` → `01-prd.md §5 (personas)`

**QA**
`18-testing-qa.md` → `17-mvp-backlog.md` (acceptance criteria) → `05-user-flows.md`

---

## 2. Document register

| # | Document | Primary owner | Change control |
|---|---|---|---|
| 00 | Documentation Index | Product | Editorial |
| 01 | Product Requirements Document | Product | RFC + sign-off |
| 02 | System Architecture | Principal Architect | RFC + sign-off |
| 03 | Database Schema | Backend Lead | RFC (breaking changes require migration plan) |
| 04 | Design System | Design Lead | Design review |
| 05 | User Flows | Product + Design | Design review |
| 06 | Wireframes | Design Lead | Design review |
| 07 | Flutter Project Structure | Mobile Lead | Tech review |
| 08 | Backend Architecture | Backend Lead | Tech review |
| 09 | API Contracts | Backend Lead | **Versioned** — breaking changes bump `v` |
| 10 | Integrations | Mobile Lead | Tech review |
| 11 | AI Layer | AI Lead | RFC + safety sign-off |
| 12 | Recovery Engine | AI Lead | Algorithm review |
| 13 | FitnessDNA Engine | AI Lead | Algorithm + safety review |
| 14 | Notifications Engine | Product + Backend | Tech review |
| 15 | Analytics Center | Data | Tech review |
| 16 | Roadmap & Sprints | Product | Planning cadence |
| 17 | MVP Backlog | Product | Sprint planning |
| 18 | Testing & QA | QA Lead | Tech review |
| 19 | Security & Privacy | Security | **Mandatory** sign-off |
| 20 | Future Expansion | Product | Editorial |

---

## 3. Glossary

| Term | Definition |
|---|---|
| **Recovery Score** | 0–100 composite of sleep, training load and activity. Defined in `12-recovery-engine.md §3`. |
| **Readiness** | Forward-looking 0–100 signal answering "how hard can I train today". Distinct from Recovery. |
| **Training Load** | Session-RPE × duration, accumulated. Acute (7-day) and chronic (28-day) windows. |
| **ACWR** | Acute:Chronic Workload Ratio. Load-spike guard rail. |
| **FitnessDNA** | The insight engine that converts multi-domain telemetry into ranked, actionable recommendations. |
| **Insight** | A single generated recommendation with a category, confidence, evidence set and action. |
| **Signal** | A normalized daily metric fed into the engines (`sleep.duration`, `nutrition.protein`, …). |
| **Ring** | A circular macro/goal progress indicator. Core dashboard primitive. |
| **Live Gym Mode** | The full-screen, one-handed workout execution surface. |
| **Session** | One executed workout instance derived from a template or freeform. |
| **Template** | A reusable workout definition (exercise list, target sets/reps/load scheme). |
| **AI Router** | Server-side component that classifies an AI request and dispatches it to the right provider. |
| **Provenance** | The evidence trail attached to every insight/recommendation. |
| **Quiet Hours** | User-defined window during which non-critical notifications are suppressed. |
| **Health Connect** | Android's system-level health data aggregation layer. |

---

## 4. Non-negotiable principles

1. **Offline-first.** Every write the user makes in the gym, at the table or in bed must
   succeed with the network off and reconcile deterministically later.
2. **The domain layer is pure Dart.** No Flutter, no Firebase, no `dart:io` imports.
3. **No secret leaves the server.** AI provider keys, OAuth client secrets and refresh
   tokens live only in Cloud Functions / Secret Manager.
4. **Every recommendation is explainable.** If the app tells the user to do something, the
   user can tap it and see exactly which data produced it.
5. **The dashboard answers one question.** Anything on the home screen that does not help
   the user decide what to do next is a candidate for deletion.
6. **Health data is the most sensitive class we hold.** It is never used for advertising,
   never sold, and is exportable and deletable on demand.
