# LifeDNA OS — Backend Architecture

**Version:** 1.0
**Runtime:** Cloud Functions v2 · Node 20 · TypeScript 5.5
**Owner:** Backend Lead

---

## 1. What the backend is for

Firestore is the datastore and the client talks to it directly. The backend therefore
exists for exactly four reasons, and code that does not serve one of them does not belong
here:

1. **Secret custody** — AI provider keys, OAuth client secrets, refresh tokens.
2. **Cross-user or cross-document computation** — rollups, engines, reports.
3. **Third-party mediation** — calendar sync, food lookup, push delivery.
4. **Trust boundaries** — anything the client must not be able to forge (token budgets,
   subscription state, account deletion).

Everything else stays on the client, where it is faster and cheaper.

---

## 2. Function inventory

### 2.1 Callable functions (client → server, authenticated)

| Function | Purpose | Timeout | Memory | Concurrency | Rate limit |
|---|---|---|---|---|---|
| `aiChat` | Non-streaming AI turn | 120 s | 512 MiB | 40 | 20/min/user |
| `aiStream` | Streaming AI turn (SSE over HTTPS) | 300 s | 512 MiB | 20 | 20/min/user |
| `aiFeedback` | Rate a message or insight | 10 s | 256 MiB | 80 | 60/min |
| `calendarConnect` | Exchange OAuth code, store token | 30 s | 256 MiB | 20 | 5/min |
| `calendarSync` | On-demand sync of one account | 120 s | 512 MiB | 20 | 10/min |
| `calendarWriteEvent` | Create/update/delete a provider event | 30 s | 256 MiB | 40 | 30/min |
| `calendarDisconnect` | Revoke + purge | 30 s | 256 MiB | 10 | 5/min |
| `healthSyncCommit` | Commit a batch of ≤ 400 health records | 60 s | 512 MiB | 40 | 60/min |
| `healthBackfillStart` | Enqueue historical backfill | 30 s | 256 MiB | 10 | 2/hour |
| `foodSearch` | Remote food search | 15 s | 512 MiB | 80 | 60/min |
| `barcodeLookup` | Resolve a barcode | 15 s | 256 MiB | 60 | 60/min |
| `recomputeTargets` | Recompute macro targets server-side | 15 s | 256 MiB | 20 | 10/min |
| `exportData` | Build and email a signed export link | 60 s | 512 MiB | 5 | 2/day |
| `deleteAccount` | Start the deletion cascade | 60 s | 512 MiB | 5 | 2/day |
| `registerDevice` | Store/refresh the FCM token | 10 s | 256 MiB | 80 | 20/min |

### 2.2 Firestore triggers

| Trigger | Path | Does |
|---|---|---|
| `onNutritionLogWrite` | `users/{uid}/nutrition_logs/{id}` | Recompute `daily_stats.nutrition`; cancel a satisfied meal reminder |
| `onWaterLogWrite` | `users/{uid}/water_logs/{id}` | Recompute `daily_stats.hydration` |
| `onSupplementLogWrite` | `users/{uid}/supplement_logs/{id}` | Recompute compliance; decrement inventory; low-stock check |
| `onSessionFinalize` | `users/{uid}/workout_sessions/{id}` (update, `status → completed`) | PR detection, training-load update, `daily_stats.training`, enqueue insight generation |
| `onSetWrite` | `users/{uid}/workout_sessions/{sid}/sets/{id}` | Maintain the "last performance" index for prefill |
| `onBodyMetricWrite` | `users/{uid}/body_metrics/{id}` | Recompute EWMA trend, goal projection; update `daily_stats.body` |
| `onTaskWrite` | `users/{uid}/tasks/{id}` | Spawn the next recurrence; update `daily_stats.tasks` |
| `onUserCreate` (auth) | — | Seed `users/{uid}`, settings docs, default supplements, starter program |
| `onUserDelete` (auth) | — | Enqueue the purge task |

### 2.3 Scheduled jobs (Cloud Scheduler)

| Job | Schedule | Purpose |
|---|---|---|
| `recoveryEngine` | Hourly, processes the timezone bucket where local time is 03:00 | Compute yesterday's recovery for every user in that bucket |
| `fitnessDnaEngine` | Hourly, bucket at local 03:15 | Build signal vectors, run rules, enqueue insight phrasing |
| `dailyPlanBuilder` | Hourly, bucket at local 06:00 | Build today's ordered action plan and the day's notification plan |
| `notificationPlanner` | Hourly, bucket at local 06:15 | Materialize FCM-delivered notifications into Cloud Tasks |
| `calendarDeltaSync` | Every 30 min | Delta-sync every healthy calendar account |
| `weeklyReport` | Hourly, Monday bucket at local 06:00 | Generate the weekly report |
| `monthlyReport` | Daily 04:00 UTC | Generate for users whose local date is the 1st |
| `tokenRefreshSweep` | Every 6 h | Refresh OAuth tokens expiring within 24 h |
| `healthRecordCompaction` | Daily 02:00 UTC | Compact `health_records` older than 400 days |
| `purgeWorker` | Every 15 min | Process pending account deletions |
| `notificationCleanup` | Daily 03:00 UTC | Delete notification history older than 30 days |

**Timezone bucketing**: users are indexed by `tzOffsetMinutes`. Each hourly run selects the
buckets for which the target local hour has just arrived. This spreads load evenly instead
of stampeding at one UTC instant, and it means a user in Cairo and a user in São Paulo both
get their 03:00 job at *their* 03:00.

### 2.4 Cloud Tasks workers (HTTP targets, not publicly routable)

| Worker | Enqueued by | Purpose |
|---|---|---|
| `notificationDispatch` | `notificationPlanner` | Deliver one FCM message at its scheduled time |
| `healthBackfill` | `healthBackfillStart` | Walk 90 days in 7-day chunks with a resumable cursor |
| `insightGeneration` | `fitnessDnaEngine`, `onSessionFinalize` | LLM phrasing of ranked candidate insights |
| `exportBuilder` | `exportData` | Build the JSON/CSV bundle, upload, sign, email |
| `accountPurge` | `deleteAccount`, `onUserDelete` | Recursive delete of the user subtree and storage prefix |
| `reportNarrative` | `weeklyReport` | LLM narrative for a report, schema-constrained |

---

## 3. Middleware chain

Every callable runs through the same composed chain:

```typescript
export const aiChat = onCall(
  { region: 'europe-west1', memory: '512MiB', timeoutSeconds: 120,
    secrets: [ANTHROPIC_API_KEY], concurrency: 40 },
  withMiddleware(
    requireAuth(),                       // 1. rejects unauthenticated
    requireVerifiedEmail(),              // 2. optional per-function
    rateLimit({ bucket: 'ai', perMinute: 20 }),
    validate(AiChatRequestSchema),       // 3. zod; rejects on shape error
    idempotent({ ttlSeconds: 300 }),     // 4. request-id dedup
    trace('aiChat'),                     // 5. Cloud Trace span + structured log
  )(aiChatHandler),
);
```

| Middleware | Behaviour |
|---|---|
| `requireAuth` | Throws `unauthenticated` if `context.auth` is absent |
| `rateLimit` | Token bucket in Firestore `_admin/rate_limits/{uid}_{bucket}`; returns `resource-exhausted` with `retryAfter` |
| `validate` | Zod schema per function; the schema **is** the API contract in `docs/09` |
| `idempotent` | Client sends `requestId`; a repeated id within the TTL returns the cached response instead of re-executing |
| `trace` | Structured logging with `uid` hashed, never raw; latency and outcome recorded |
| `withMiddleware` | Composes; any throw is mapped to an `HttpsError` by a single error mapper |

**Error contract** — every failure returns:
```json
{ "code": "resource-exhausted",
  "message": "Daily AI limit reached.",
  "details": { "reason": "AI_BUDGET_EXCEEDED", "retryAfter": 28800, "resetAt": "…" } }
```
`reason` is a stable machine string; `message` is user-safe copy. The client maps `reason`,
never `message`.

---

## 4. Engine implementations (server side)

```
functions/src/engines/
├── recovery/
│   ├── recoveryEngine.ts       # orchestration
│   ├── sleepScore.ts           # duration · consistency · efficiency · stages
│   ├── loadScore.ts            # ACWR → score
│   ├── activityScore.ts        # steps + active minutes vs baseline
│   └── readiness.ts
├── load/
│   ├── sessionLoad.ts          # sessionRpe × durationMinutes
│   ├── acuteChronic.ts         # 7d / 28d EWMA
│   └── volumeByMuscle.ts
├── nutrition/
│   ├── macroCalculator.ts      # mirrors the Dart implementation exactly
│   ├── adherence.ts
│   └── targetAdjustment.ts     # weekly rate → calorie delta proposal
├── insights/
│   ├── signalVector.ts         # 28-day normalized signal set
│   ├── rules/                  # one file per rule, all pure
│   │   ├── proteinFloorMiss.ts
│   │   ├── weightRateTooFast.ts
│   │   ├── sleepDecline.ts
│   │   ├── readyForPr.ts
│   │   ├── overloadStall.ts
│   │   ├── acwrSpike.ts
│   │   ├── hydrationShortfall.ts
│   │   ├── supplementLapse.ts
│   │   ├── muscleUndertrained.ts
│   │   └── calendarOverload.ts
│   ├── ranker.ts               # impact × confidence × recency
│   └── phrasing.ts             # LLM call with a strict JSON schema
└── priority/
    └── nextAction.ts           # the dashboard's Next Action selection
```

**Engine parity.** `functions/src/engines/**` and `app/lib/core/engines/**` implement the
same algorithms. `test/fixtures/engines/*.json` holds input→expected-output pairs; both the
Dart and the TypeScript suites run every fixture. A divergence fails both builds. This is
the mechanism that lets the client show an instant recovery preview that always matches
what the server will later compute.

---

## 5. AI provider layer

```
functions/src/providers/ai/
├── types.ts             # AiProvider interface — the only thing callers depend on
├── router.ts            # intent classification + dispatch
├── contextBuilder.ts    # structured user snapshot, token-capped
├── safety.ts            # pre/post interceptors
├── budget.ts            # per-user daily token accounting
├── claudeAdapter.ts
├── copilotAdapter.ts    # Microsoft Graph mediated
├── coachAdapter.ts      # Claude + LifeDNA system prompt + tools
└── toolRegistry.ts      # the functions an assistant may call
```

```typescript
export interface AiProvider {
  readonly id: AssistantId;
  readonly supportsStreaming: boolean;
  readonly supportsTools: boolean;
  chat(req: AiRequest): Promise<AiResponse>;
  stream(req: AiRequest): AsyncIterable<AiChunk>;
}
```

Adding ChatGPT, Gemini, DeepSeek or Perplexity means writing one file implementing this
interface and adding a row to the routing table in Remote Config. **No client release.**

---

## 6. Integration adapters

```
functions/src/providers/calendar/
├── types.ts               # CalendarProvider interface
├── googleAdapter.ts       # Calendar API v3, syncToken delta
├── microsoftAdapter.ts    # Graph v1.0, deltaLink
├── tokenStore.ts          # KMS envelope encryption, refresh, revoke
└── eventMapper.ts         # provider event ⇄ canonical CalendarEvent
```

**Token custody**

```
_admin/oauth_tokens/{uid}_{provider}
{
  "uid": "...", "provider": "google",
  "ciphertext": "<KMS-encrypted refresh token>",
  "keyVersion": "projects/…/cryptoKeyVersions/3",
  "accessTokenExpiresAt": "ts",
  "scopes": [...],
  "createdAt": "ts", "rotatedAt": "ts"
}
```
- Encrypted with Cloud KMS envelope encryption; the plaintext exists only in memory during
  a request.
- Never returned to the client under any circumstance.
- `tokenRefreshSweep` refreshes anything expiring within 24 h; a refresh failure marks the
  account `needs_reauth` and enqueues a single re-auth notification.
- On disconnect or account deletion the token is revoked **at the provider** first, then
  deleted locally.

---

## 7. Idempotency

| Surface | Key | Mechanism |
|---|---|---|
| Callables | `requestId` from the client | Cached response in `_admin/idempotency/{uid}_{requestId}`, 5-min TTL |
| Health records | `sha256(source\|type\|startMs\|endMs)` | Document ID — a re-write is a no-op |
| Workout sets | Client UUID v7 | Document ID + `set(merge:true)` |
| Nutrition entries | Client UUID v7 | Document ID |
| Insights | `sha256(uid\|rule\|windowStart\|windowEnd)` | Document ID — the same rule over the same window cannot duplicate |
| Reports | `weekly_{ISO week}` / `monthly_{yyyy-MM}` | Document ID |
| Notifications | `sha256(uid\|category\|scheduledFor\|refId)` | Document ID |
| Cloud Tasks | Task name | Cloud Tasks dedups by name within its retention window |

**Every trigger is written to tolerate being invoked twice.** Firestore triggers are
at-least-once; assuming otherwise is the most common source of production data corruption.

---

## 8. Rollup maintenance

`daily_stats/{yyyy-MM-dd}` is updated by triggers, and correctness under concurrency
matters more than latency here.

```typescript
// Pattern used by every rollup trigger
export const onNutritionLogWrite = onDocumentWritten(
  'users/{uid}/nutrition_logs/{logId}',
  async (event) => {
    const { uid } = event.params;
    const localDate = resolveLocalDate(event);       // from before or after snapshot
    const ref = db.doc(`users/${uid}/daily_stats/${localDate}`);

    // Recompute from source rather than incrementing:
    // an at-least-once trigger must never double-count.
    await db.runTransaction(async (tx) => {
      const logs = await tx.get(
        db.collection(`users/${uid}/nutrition_logs`).where('localDate', '==', localDate),
      );
      const totals = sumMacros(logs.docs);
      const targets = await readTargets(tx, uid, localDate);
      tx.set(ref, {
        localDate,
        nutrition: { ...totals, ...targets, entryCount: logs.size,
                     adherencePct: adherence(totals, targets) },
        updatedAt: FieldValue.serverTimestamp(),
      }, { merge: true });
    });

    await maybeCancelSatisfiedMealReminder(uid, localDate, event);
  },
);
```

**Why recompute instead of `FieldValue.increment`:** increments are fast but wrong under
at-least-once delivery and impossible to repair. A day has at most ~30 nutrition entries,
so a full recompute is cheap and self-healing — a corrupted rollup fixes itself on the next
write.

**Debouncing:** a rapid burst of writes (applying a meal template writes 5 entries) is
coalesced by a 2-second Cloud Task with a deterministic name, so five writes cause one
recompute rather than five.

---

## 9. Observability

| Signal | Tool | Alert |
|---|---|---|
| Function errors | Error Reporting | > 1 % error rate over 5 min → page |
| Function latency | Cloud Monitoring | P95 > 2× baseline for 10 min → warn |
| AI cost | Custom metric from `ai_usage` | Daily spend > 130 % of forecast → page |
| Engine runs | `_admin/engine_runs` | A scheduled job that did not complete → page |
| Sync health | `sync_state.consecutiveFailures` | > 5 % of accounts unhealthy → warn |
| Firestore usage | Cloud Monitoring | Reads/user/day > 200 → warn (a read-pattern regression) |
| Client crashes | Crashlytics | Crash-free < 99.5 % → page |

**Structured log shape** (no PII, ever):
```json
{ "severity": "INFO", "function": "aiChat", "uidHash": "9f2b…",
  "assistant": "coach", "intent": "fitness", "latencyMs": 1840,
  "inputTokens": 3120, "outputTokens": 610, "outcome": "ok",
  "traceId": "…" }
```

A unit test asserts that the logger redacts any field name matching
`/email|name|food|message|content|token(?!s?Count)|weight|value/`.

---

## 10. Local development

```bash
cd functions
npm install
npm run build

# Full emulator suite with seeded data
firebase emulators:start --import=./firebase/seed --export-on-exit

# Emulators: auth 9099 · firestore 8080 · functions 5001 · storage 9199 · UI 4000
```

- AI providers are stubbed in the emulator (`AI_PROVIDER=fake`) and return deterministic
  fixtures, so tests never spend tokens.
- Calendar providers are stubbed with a recorded-response fake.
- `npm run test` runs the TypeScript unit suite including all shared engine fixtures.

---

## 11. Deployment

```bash
# Per-environment deploy
firebase use dev && firebase deploy --only functions
firebase use staging && firebase deploy --only functions,firestore:rules,firestore:indexes
firebase use prod && firebase deploy --only functions,firestore:rules,firestore:indexes

# Single function (fast iteration)
firebase deploy --only functions:aiChat
```

**Rules and index deployment always precedes the client release that needs them.** A
composite index takes minutes to build; deploying it with the client that queries it causes
a production outage on that screen.

**Rollback**: `firebase functions:rollback` restores the previous revision. Rules are
version-controlled and rolled back by re-deploying the previous file. Client-side, every
Phase 2/3 module has a Remote Config kill switch.
