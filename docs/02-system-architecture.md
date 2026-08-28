# LifeDNA OS — System Architecture

**Version:** 1.0
**Owner:** Principal Architect

---

## 1. Architectural principles

| # | Principle | Consequence |
|---|---|---|
| 1 | **Offline-first, local-authoritative for user input** | The client commits writes locally and never blocks the user on the network. Firestore persistence + a Drift outbox back this. |
| 2 | **Deterministic engines own the numbers; the LLM owns the language** | Recovery, macro, load and insight *values* are computed by pure Dart / TypeScript. The model rephrases; it never invents a figure. |
| 3 | **The domain layer is a pure Dart island** | Zero Flutter, Firebase, HTTP or platform imports. Everything crosses via repository interfaces. |
| 4 | **Secrets never reach the client** | All third-party API keys and OAuth refresh tokens live in Cloud Functions + Secret Manager. |
| 5 | **Single read model per screen** | Each screen consumes one immutable view-state object composed by one controller. No card fetches independently. |
| 6 | **Idempotency everywhere** | Every sync, every function, every write carries a deterministic key. Re-running is always safe. |
| 7 | **Denormalize for read, aggregate on write** | Firestore is billed and latency-bound per document read. Daily rollups are written by triggers so screens read one document. |
| 8 | **Feature-flag every phase-2/3 surface** | Remote Config gates modules so a bad engine can be disabled without a release. |

---

## 2. C4 Level 1 — System context

```
                                  ┌──────────────────────────────┐
                                  │           THE USER           │
                                  │  (athlete / student / pro)   │
                                  └───────────────┬──────────────┘
                                                  │ uses
                                                  ▼
        ┌──────────────────────────────────────────────────────────────────────┐
        │                            LifeDNA OS                                │
        │        Personal performance operating system (Flutter + Firebase)    │
        └───┬────────┬─────────┬──────────┬──────────┬──────────┬──────────┬───┘
            │        │         │          │          │          │          │
            ▼        ▼         ▼          ▼          ▼          ▼          ▼
     ┌──────────┐ ┌──────┐ ┌────────┐ ┌────────┐ ┌────────┐ ┌────────┐ ┌────────┐
     │  Health  │ │Galaxy│ │ Google │ │Microsoft│ │Anthropic│ │  Open  │ │  FCM   │
     │ Connect /│ │ Fit 3│ │Calendar│ │  Graph  │ │ Claude  │ │  Food  │ │ Push   │
     │ Samsung  │ │ (BLE)│ │  API   │ │(Outlook,│ │   API   │ │ Facts  │ │Service │
     │  Health  │ │      │ │        │ │ Copilot)│ │         │ │        │ │        │
     └──────────┘ └──────┘ └────────┘ └────────┘ └────────┘ └────────┘ └────────┘
       physiology   live HR   events    calendar   reasoning   barcode   delivery
        + sleep    + battery  + write   + mail +   + coaching   foods
                                        Copilot
```

**External system contracts**

| System | Direction | Protocol | Auth | Failure mode |
|---|---|---|---|---|
| Health Connect | read + write-back | Android SDK (on-device) | Android runtime permissions | Feature degrades to manual entry |
| Samsung Health | read | Samsung Health SDK | Partner key + user consent | Falls back to Health Connect |
| Galaxy Fit 3 | read | BLE GATT | Bond | Live HR hidden; band data still via Health Connect |
| Google Calendar | read + write | REST v3 | OAuth 2.0 (server-held refresh) | Cached 30-day read-only view |
| Microsoft Graph | read + write | REST v1.0 | OAuth 2.0 / MSAL | Cached read-only view |
| Anthropic Claude | request/stream | HTTPS (server-side only) | API key in Secret Manager | Queued retry, then "assistant unavailable" |
| Open Food Facts | read | REST | none | Manual food creation |
| FCM | push | Firebase SDK | Firebase | Local notifications still fire |

---

## 3. C4 Level 2 — Container diagram

```
┌───────────────────────────── MOBILE DEVICE ─────────────────────────────────────┐
│                                                                                 │
│  ┌────────────────────────── Flutter Application ──────────────────────────┐    │
│  │                                                                          │   │
│  │  PRESENTATION      Screens · Widgets · Riverpod controllers · go_router   │   │
│  │  ───────────────────────────────────────────────────────────────────────  │   │
│  │  DOMAIN            Entities · Value objects · Repository interfaces ·      │   │
│  │                    Use cases · Pure engines (macro, e1RM, recovery)        │   │
│  │  ───────────────────────────────────────────────────────────────────────  │   │
│  │  DATA              Repository impls · Firestore DTOs · Drift DAOs ·        │   │
│  │                    Platform channels · Remote data sources                 │   │
│  └──────────────────────────────────────────────────────────────────────────┘   │
│            │                    │                    │                │          │
│            ▼                    ▼                    ▼                ▼          │
│   ┌────────────────┐  ┌──────────────────┐  ┌───────────────┐  ┌──────────────┐ │
│   │  Drift (SQLite)│  │ Firestore local  │  │ Platform      │  │ flutter_local│ │
│   │  offline cache │  │ persistence      │  │ channels:     │  │ _notifications│ │
│   │  + write outbox│  │ (Firebase SDK)   │  │ HealthConnect │  │  (local sched)│ │
│   │  (SQLCipher)   │  │                  │  │ BLE · Samsung │  │              │ │
│   └────────────────┘  └──────────────────┘  └───────────────┘  └──────────────┘ │
└─────────────────────────────────────────────────────────────────────────────────┘
                    │ Firestore streams          │ HTTPS callable            │ FCM
                    ▼                            ▼                           ▲
┌──────────────────────────── FIREBASE / GOOGLE CLOUD ────────────────────────────┐
│                                                                                 │
│  ┌───────────────┐  ┌─────────────────┐  ┌──────────────┐  ┌─────────────────┐  │
│  │ Firebase Auth │  │ Cloud Firestore │  │Cloud Storage │  │ Cloud Messaging │  │
│  │ email/Google/ │  │ primary store   │  │ photos,      │  │  push delivery  │  │
│  │ Apple/MS      │  │ per-user tree   │  │ exports      │  │                 │  │
│  └───────────────┘  └─────────────────┘  └──────────────┘  └─────────────────┘  │
│                                                                                 │
│  ┌────────────────────────── Cloud Functions v2 (Node 20 / TS) ──────────────┐   │
│  │                                                                            │  │
│  │  CALLABLE           aiChat · aiRouterClassify · calendarSync ·             │  │
│  │                     calendarWriteEvent · healthSyncCommit · exportData ·   │  │
│  │                     foodSearch · barcodeLookup · recomputeTargets          │  │
│  │  ───────────────────────────────────────────────────────────────────────   │  │
│  │  TRIGGERS           onNutritionLogWrite → daily rollup                     │  │
│  │                     onWorkoutSessionFinalize → PR detect + load update     │  │
│  │                     onBodyMetricWrite → trend recompute                    │  │
│  │                     onUserCreate → seed defaults                           │  │
│  │                     onUserDelete → cascade purge                           │  │
│  │  ───────────────────────────────────────────────────────────────────────   │  │
│  │  SCHEDULED          03:00 recoveryEngine · 03:15 fitnessDnaEngine ·        │  │
│  │                     06:00 dailyPlanBuilder · Mon 06:00 weeklyReport ·      │  │
│  │                     */30 calendarDeltaSync · 02:00 tokenRefreshSweep       │  │
│  │  ───────────────────────────────────────────────────────────────────────   │  │
│  │  QUEUE WORKERS      Cloud Tasks: notificationDispatch · healthBackfill ·   │  │
│  │                     aiInsightGeneration · exportBuilder                    │  │
│  └────────────────────────────────────────────────────────────────────────────┘  │
│                                                                                 │
│  ┌───────────────┐  ┌─────────────────┐  ┌──────────────┐  ┌─────────────────┐  │
│  │ Secret Manager│  │  Cloud KMS      │  │Cloud Scheduler│  │ Remote Config   │  │
│  │ provider keys │  │ token envelope  │  │  + Tasks      │  │ flags + weights │  │
│  └───────────────┘  └─────────────────┘  └──────────────┘  └─────────────────┘  │
│                                                                                 │
│  ┌────────────────────────────────────────────────────────────────────────────┐ │
│  │ OBSERVABILITY: Crashlytics · Firebase Analytics · Cloud Logging · Trace ·  │ │
│  │                Error Reporting · BigQuery export (analytics + engine audit)│ │
│  └────────────────────────────────────────────────────────────────────────────┘ │
└─────────────────────────────────────────────────────────────────────────────────┘
```

---

## 4. C4 Level 3 — Client component architecture

### 4.1 Layer contract

```
┌────────────────────────────────────────────────────────────────────────┐
│ PRESENTATION                                                           │
│   • ConsumerWidget screens                                             │
│   • Riverpod Notifiers  → expose ONE immutable ViewState per screen    │
│   • go_router routes, guards, deep links                               │
│   • Depends on: domain (entities + use cases). NEVER on data.          │
└───────────────────────────────┬────────────────────────────────────────┘
                                │ calls use cases / reads providers
┌───────────────────────────────▼────────────────────────────────────────┐
│ DOMAIN                (pure Dart — no Flutter, no Firebase)            │
│   • Entities        Meal, WorkoutSession, RecoveryScore, Task…         │
│   • Value objects   Macros, Weight, Load, TimeWindow                   │
│   • Repositories    abstract interfaces only                           │
│   • Use cases       LogMeal, CompleteSet, ComputeRecovery…             │
│   • Engines         MacroCalculator, E1rmCalculator, RecoveryEngine,   │
│                     PriorityEngine, LoadEngine  (deterministic, tested)│
│   • Failures        sealed Failure hierarchy                           │
└───────────────────────────────▲────────────────────────────────────────┘
                                │ implements
┌───────────────────────────────┴────────────────────────────────────────┐
│ DATA                                                                    │
│   • Repository implementations (map DTO ⇄ entity, choose source)        │
│   • Remote data sources   FirestoreX, FunctionsX, CalendarApiX          │
│   • Local data sources    DriftDao, SecureStore, Prefs                  │
│   • Platform data sources HealthConnectChannel, BleClient               │
│   • DTOs (freezed + json_serializable)                                  │
│   • Sync: Outbox, ConflictResolver, SyncScheduler                       │
└─────────────────────────────────────────────────────────────────────────┘
```

**Enforced by CI**: an import-lint step fails the build if `lib/features/*/domain/**`
imports `package:flutter`, `package:cloud_firestore`, `package:firebase_*`, or `dart:io`.

### 4.2 Dependency rule illustrated (Nutrition)

```
NutritionScreen (ConsumerWidget)
        │ watch
        ▼
nutritionControllerProvider  ──►  NutritionState (immutable)
        │ invokes
        ▼
LogMealUseCase ── depends on ──►  NutritionRepository (abstract, domain)
                                          ▲
                                          │ implements
                       NutritionRepositoryImpl (data)
                          │                 │                │
                          ▼                 ▼                ▼
              NutritionLocalDataSource  NutritionRemoteDS  FoodSearchDS
                   (Drift)                (Firestore)      (Functions)
```

### 4.3 State management topology (Riverpod 2, code-generated)

| Provider kind | Use | Example |
|---|---|---|
| `@Riverpod(keepAlive: true)` service | Long-lived singletons | `firestoreProvider`, `driftProvider`, `authRepositoryProvider` |
| `@riverpod` stream | Live domain data | `todayNutritionStreamProvider`, `activeSessionStreamProvider` |
| `@riverpod` future | One-shot reads | `exerciseByIdProvider(id)` |
| `@riverpod class` Notifier | Screen controllers holding mutable UI state | `LiveGymController`, `NutritionController` |
| `@riverpod` computed | Derived, memoized values | `dashboardSnapshotProvider` (combines 8 sources) |

`dashboardSnapshotProvider` is the canonical composition point:

```dart
@riverpod
Future<DashboardSnapshot> dashboardSnapshot(Ref ref) async {
  final today = ref.watch(todayProvider);
  final results = await Future.wait([
    ref.watch(nutritionSummaryProvider(today).future),
    ref.watch(hydrationSummaryProvider(today).future),
    ref.watch(workoutStatusProvider(today).future),
    ref.watch(recoverySummaryProvider(today).future),
    ref.watch(sleepSummaryProvider(today).future),
    ref.watch(scheduleSummaryProvider(today).future),
    ref.watch(taskSummaryProvider(today).future),
    ref.watch(insightSummaryProvider(today).future),
  ]);
  // PriorityEngine (pure domain) turns the snapshot into the Next Action card.
  return DashboardSnapshot.from(results, priority: PriorityEngine().rank(results));
}
```

---

## 5. Backend component architecture

### 5.1 Cloud Functions organisation

```
functions/src/
├── index.ts                     # export surface only
├── config/                      # env, secrets, constants, remote-config accessors
├── middleware/                  # auth guard, rate limit, validation, idempotency, tracing
├── callable/
│   ├── ai/          aiChat.ts · aiStream.ts · aiFeedback.ts
│   ├── calendar/    connect.ts · sync.ts · writeEvent.ts · disconnect.ts
│   ├── health/      commitBatch.ts · backfill.ts · status.ts
│   ├── nutrition/   foodSearch.ts · barcodeLookup.ts · recomputeTargets.ts
│   └── account/     exportData.ts · deleteAccount.ts
├── triggers/
│   ├── firestore/   onNutritionLogWrite.ts · onSessionFinalize.ts ·
│   │                onBodyMetricWrite.ts · onSupplementLogWrite.ts
│   └── auth/        onUserCreate.ts · onUserDelete.ts
├── scheduled/
│   ├── recoveryEngine.ts · fitnessDnaEngine.ts · dailyPlanBuilder.ts
│   ├── weeklyReport.ts · calendarDeltaSync.ts · tokenRefreshSweep.ts
│   └── notificationPlanner.ts
├── workers/                     # Cloud Tasks HTTP targets
│   ├── notificationDispatch.ts · healthBackfill.ts
│   └── insightGeneration.ts · exportBuilder.ts
├── engines/                     # pure TS, mirrors the Dart engines
│   ├── recovery/ · load/ · nutrition/ · insights/ · priority/
├── providers/                   # AI + integration adapters
│   ├── ai/  claudeAdapter.ts · copilotAdapter.ts · coachAdapter.ts · router.ts
│   ├── calendar/ googleAdapter.ts · microsoftAdapter.ts
│   └── food/ openFoodFactsAdapter.ts
└── lib/                         # firestore helpers, dates, crypto, errors, logger
```

### 5.2 Why these run server-side rather than on-device

| Concern | Server | Reason |
|---|---|---|
| AI provider calls | ✅ | Keys must never ship in an APK; also enables routing/caching/budgeting |
| OAuth refresh tokens | ✅ | Long-lived credentials; KMS-encrypted at rest |
| Recovery/DNA engines | ✅ (nightly) | Needs the full history; results are cached documents the client just reads |
| Recovery *preview* | client | A pure Dart mirror lets the UI recompute instantly when the user edits inputs |
| Macro calculation | both | Same algorithm, two implementations, one shared golden-test fixture set |
| Calendar delta sync | ✅ | Sync tokens are server state; avoids waking the client |
| Notification planning | ✅ + client | Server plans; client schedules time-based ones locally so they fire offline |

**Engine parity contract**: `functions/src/engines/**` and `app/lib/core/engines/**` are
validated against a shared JSON fixture set (`test/fixtures/engines/*.json`) run by both
the Dart and the TS test suites. A divergence fails CI on both sides.

---

## 6. Data flow scenarios

### 6.1 Logging a set in Live Gym Mode (the critical path)

```
User taps "Complete Set"
   │
   ├─(1) LiveGymController.completeSet()                      [presentation]
   │        └─ optimistic state update, haptic feedback        < 16 ms
   │
   ├─(2) CompleteSetUseCase(session, set)                      [domain]
   │        ├─ validate, stamp clientId (uuid v7) + performedAt
   │        └─ PR check via E1rmCalculator (pure)
   │
   ├─(3) WorkoutRepositoryImpl.appendSet()                     [data]
   │        ├─ Drift INSERT (authoritative local write)        < 50 ms  ✅ committed
   │        └─ Outbox INSERT (op = APPEND_SET, idempotencyKey = clientId)
   │
   ├─(4) RestTimerService.start(exercise.restSeconds)
   │        └─ schedules local notification for backgrounded case
   │
   └─(5) SyncScheduler (debounced 2 s, or immediately if online)
            └─ Firestore write to
               users/{uid}/workout_sessions/{sessionId}/sets/{clientId}
                  └─ merge:true, so a replay is a no-op
                     │
                     └─ onSessionFinalize trigger (only on session close)
                            ├─ recompute PRs → users/{uid}/personal_records
                            ├─ update training load → users/{uid}/daily_stats/{date}
                            └─ enqueue insight generation task
```

**Guarantee**: step 3 is the commit point. Steps 5+ may happen minutes or hours later.
The user is never blocked and never loses a set.

### 6.2 Health sync (Health Connect → LifeDNA)

```
Trigger: app foreground | 60-min WorkManager job | pull-to-refresh
   │
1. HealthConnectChannel.readChanges(sinceToken)          [platform, Kotlin]
      → returns records + a new changes token
2. HealthSyncMapper normalizes to canonical HealthRecord [data]
      → idempotencyKey = sha256(source|type|startMs|endMs)
3. Local upsert into Drift by idempotencyKey             (dedup pass 1)
4. Batched callable `healthSyncCommit`  (≤ 400 records/call)
      → server re-checks idempotencyKey                  (dedup pass 2)
      → writes users/{uid}/health_records/{key}
      → updates users/{uid}/daily_stats/{date} aggregates in the same batch
5. Store the new changes token locally + server-side
6. Emit sync status per data type for the settings screen
```

**Backfill**: first connect enqueues a Cloud Task that walks 90 days in 7-day chunks,
resumable via a cursor document, so a crash never restarts from zero.

### 6.3 AI request routing

```
User sends a message in the AI Hub
   │
1. Client → callable `aiChat`  { conversationId, message, forcedProvider? }
2. Auth guard + per-user rate limit + daily token budget check
3. If no forcedProvider → AiRouter.classify(message)
      • fast, cheap classifier (Haiku-class) → intent label
      • intent ∈ {fitness, nutrition, recovery} → Coach
      • intent ∈ {document, analysis, reasoning, general} → Claude
      • intent ∈ {work, mail, meeting, office} → Copilot (Graph)
4. ContextBuilder assembles a structured snapshot (only if the assistant needs it)
      • targets, today's intake, last 7 training sessions (compacted),
        sleep 7d, recovery 7d, next 24 h calendar, open P1/P2 tasks
      • hard cap 4 000 tokens; oldest/least-relevant dropped first
5. SafetyInterceptor.preCheck(message)   → may short-circuit to escalation response
6. Provider adapter streams tokens back over the callable stream
7. SafetyInterceptor.postCheck(chunks)   → may truncate + replace
8. Persist message pair to users/{uid}/ai_conversations/{cid}/messages
9. Record token usage → users/{uid}/ai_usage/{yyyy-MM}
```

### 6.4 Nightly engine pass

```
03:00 local-time bucket (users sharded by timezone)
   │
1. recoveryEngine (scheduled)
      for each user in the bucket:
        ├─ read yesterday's sleep, workouts, steps, HR
        ├─ compute sleepScore, loadScore, activityScore
        ├─ compose recoveryScore + readiness (docs/12)
        └─ write users/{uid}/recovery_data/{date}   (+ component breakdown)
2. 03:15 fitnessDnaEngine (scheduled)
      ├─ build DailySignalVector (28-day window)
      ├─ run the deterministic rule set → candidate insights
      ├─ rank by impact × confidence × recency, keep top N
      ├─ enqueue insightGeneration Cloud Task (LLM phrasing, schema-constrained)
      └─ write users/{uid}/insights/{id}
3. 06:00 dailyPlanBuilder (scheduled)
      ├─ read recovery, calendar, program, targets
      ├─ produce today's ordered action plan
      ├─ write users/{uid}/daily_plans/{date}
      └─ enqueue notification plan for the day
```

---

## 7. Offline and synchronization contract

### 7.1 Write classification

| Class | Examples | Storage | Conflict policy |
|---|---|---|---|
| **Additive log** | sets, nutrition entries, supplement doses, water, body metrics | Drift + Firestore doc keyed by client UUID v7 | **Never overwritten.** Union of all records. Duplicates impossible by key. |
| **Mutable entity** | tasks, templates, profile, settings | Drift + Firestore doc | Last-write-wins on `updatedAt`; server timestamp arbitrates ties |
| **Server-derived** | recovery, insights, daily_stats, reports | Firestore, read-only on client | Client never writes. Server recomputes. |
| **External mirror** | calendar events | Drift cache + provider | Provider is authoritative. Local edits go through a write-then-refetch. |

### 7.2 Outbox

```
outbox(
  id TEXT PRIMARY KEY,          -- uuid v7, also the idempotency key
  op  TEXT,                     -- APPEND_SET | UPSERT_TASK | DELETE_MEAL | …
  collectionPath TEXT,
  payload TEXT,                 -- JSON
  createdAt INTEGER,
  attempts INTEGER DEFAULT 0,
  nextAttemptAt INTEGER,
  lastError TEXT
)
```

- Drained by `SyncScheduler` on connectivity regain, app foreground, and a 15-minute
  WorkManager job.
- Backoff: `min(2^attempts × 2s, 15 min)` with ±20 % jitter.
- After 10 failed attempts the op is parked and surfaced in Settings → Sync with a
  manual retry. It is **never** silently dropped.
- Ordering is per-entity, not global: ops on the same document are drained in insertion
  order; independent entities drain in parallel.

### 7.3 Read path

1. Emit from Drift immediately (never an empty screen if data exists).
2. Subscribe to the Firestore stream (which itself serves from its local cache first).
3. Merge: server data replaces cache for server-derived documents; additive logs union.
4. Surface `SyncState { lastSyncedAt, pending, isStale }` in the UI as a subtle banner.

---

## 8. Navigation architecture

```
/                       → splash / auth gate
/auth
   /sign-in  /sign-up  /forgot-password
/onboarding             → stepped flow, guarded until complete

ShellRoute (bottom navigation, 5 tabs)
   /home                Dashboard
   /nutrition           Nutrition Center
       /nutrition/log            /nutrition/planner
       /nutrition/food/:id       /nutrition/scan
   /train               Workout Center
       /train/templates          /train/template/:id
       /train/exercise/:id       /train/history
       /train/programs
   /plan                Calendar + Tasks (segmented)
       /plan/task/:id            /plan/event/:id
   /me                  Body · Recovery · Analytics · Settings
       /me/body   /me/recovery   /me/analytics   /me/settings/*

Full-screen routes (outside the shell)
   /live/:sessionId     Live Gym Mode        (no bottom nav, keeps screen awake)
   /ai                  AI Assistant Hub
       /ai/:conversationId
   /insight/:id         Insight detail with provenance
```

**Guards**: `authGuard` (unauthenticated → `/auth/sign-in`), `onboardingGuard`
(incomplete → `/onboarding`), `activeSessionGuard` (an in-progress session offers a
"Resume workout" banner on every shell route).

---

## 9. Cross-cutting concerns

| Concern | Approach |
|---|---|
| **Error handling** | Domain returns `Result<T, Failure>`; presentation maps `Failure` → user-facing copy via a single `FailureMapper`. No raw exception text reaches the UI. |
| **Logging** | Structured `AppLogger` with levels. **Never** logs health values, food names, message content or tokens. Redaction is enforced by a lint rule and a unit test on the logger. |
| **Analytics** | Event taxonomy in `docs/15`. Events carry no PII/health values — only counts, categories and durations. |
| **Feature flags** | Remote Config, typed accessor `FeatureFlags.recoveryEngineEnabled`, with a compile-time default so the app works if Remote Config fails. |
| **Configuration** | Three flavours (`dev`, `staging`, `prod`) → three Firebase projects, three bundle IDs, distinct app icons. |
| **Time** | All timestamps stored UTC. All *day bucketing* uses the user's timezone at write time, persisted as `localDate` (`yyyy-MM-dd`) + `tzOffsetMinutes` so travel does not corrupt history. |
| **Units** | Canonical metric everywhere in storage and domain. Conversion is presentation-only. |
| **DI** | Riverpod is the container. No `get_it`. Overriding a provider in tests is the substitution mechanism. |

---

## 10. Scalability and cost model

### 10.1 Read/write budget per active user per day (target)

| Operation | Count/day | Notes |
|---|---|---|
| Firestore document reads | ~120 | Dashboard reads 1 rollup doc, not N logs |
| Firestore document writes | ~60 | Sets, meals, doses, tasks |
| Cloud Function invocations | ~25 | Sync batches, AI turns, calendar delta |
| AI tokens | ~14 k in / 3 k out | Budgeted; classification uses a cheap model |
| Storage | ~0.3 MB | Photos amortized |

**Cost control levers, in order of application**
1. Daily rollup documents (`daily_stats`) collapse N log reads into 1.
2. Firestore bundles ship the exercise DB and top-5 000 foods with the app — zero reads.
3. AI classification uses a small model; only the answer uses a frontier model.
4. Prompt caching on the stable system prompt + user context prefix.
5. Per-user daily token budget with a hard stop.
6. Scheduled jobs process users in timezone-sharded batches to smooth load.

### 10.2 Growth path

| Users | Change required |
|---|---|
| < 10 k | Single Firestore region, default Function concurrency. No change. |
| 10 k–100 k | Min-instances on `aiChat` and `foodSearch`; BigQuery export for analytics; Firestore composite index review. |
| 100 k–1 M | Move food search to a dedicated service (Typesense/Algolia); shard hot rollups; regional Firestore replicas; Cloud Run for streaming AI. |
| > 1 M | Split engines into Cloud Run services with an event bus (Pub/Sub); dedicated analytics warehouse; multi-region active-active. |

---

## 11. Technology decision record (abridged ADRs)

| ADR | Decision | Alternatives rejected | Rationale |
|---|---|---|---|
| 001 | Flutter | React Native, native | One codebase, Material 3 fidelity, best-in-class custom rendering for rings/charts, Skia performance in Live Gym |
| 002 | Riverpod 2 | BLoC, Provider, GetX | Compile-safe DI + state in one tool, trivial test overrides, no `BuildContext` coupling |
| 003 | Firebase | Supabase, custom | Offline persistence is first-class; auth + push + functions + analytics in one integrated stack; fastest path to a working product |
| 004 | Firestore + Drift | Firestore alone | Firestore's cache is not queryable enough for the Live Gym read patterns; Drift gives SQL, encryption and an outbox |
| 005 | Server-side AI | On-device / direct client calls | Key safety, routing, budgeting, caching, provider swap without release |
| 006 | Health Connect primary | Samsung SDK primary | Avoids a partner-approval dependency; cross-vendor; Samsung SDK stays as fallback |
| 007 | go_router | Navigator 2 raw, auto_route | Declarative, deep-link-first, official, shell routes fit the tab architecture |
| 008 | freezed + json_serializable | Manual models, built_value | Exhaustive sealed unions for state, generated equality/copy, low ceremony |
| 009 | Deterministic engines + LLM phrasing | LLM computes recommendations | Safety and reproducibility. A recommendation must be regenerable and auditable. |
| 010 | Cloud Tasks for fan-out | Pub/Sub | Native per-task scheduling, retry policy and rate limiting; simpler for per-user jobs |

---

## 12. Deployment topology

| Environment | Firebase project | Purpose | Data |
|---|---|---|---|
| `dev` | `lifedna-dev` | Local + emulator development | Synthetic, wipeable |
| `staging` | `lifedna-staging` | Internal dogfood, Play internal track | Real team data |
| `prod` | `lifedna-prod` | Production | Real user data, backed up daily |

**Promotion**: `feat/*` → PR (CI: analyze, test, engine-parity, import-lint, build) →
`develop` (auto-deploy dev + staging functions, Play internal track) → release branch →
`main` (tagged, prod functions + Play closed/open track, staged rollout 10 % → 50 % → 100 %).

**Rollback**: Functions are versioned and rolled back with `firebase functions:rollback`;
the client relies on Remote Config kill switches per module plus a Play staged-rollout halt.
