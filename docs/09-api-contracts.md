# LifeDNA OS — API Contracts

**Version:** `v1`
**Transport:** Firebase Callable Functions (HTTPS, `europe-west1`)
**Auth:** Firebase ID token, attached automatically by the SDK
**Owner:** Backend Lead — **breaking changes bump the version prefix**

---

## 1. Conventions

### 1.1 Envelope

Every request:
```jsonc
{
  "v": 1,                       // contract version — server rejects unknown majors
  "requestId": "uuid-v7",       // idempotency key, required on all mutating calls
  "data": { /* per-endpoint */ }
}
```

Every success response:
```jsonc
{ "ok": true, "data": { /* per-endpoint */ }, "meta": { "serverTime": "ISO8601" } }
```

Every failure (delivered as an `HttpsError`):
```jsonc
{
  "code": "resource-exhausted",         // Firebase canonical code
  "message": "Daily AI limit reached.", // user-safe copy
  "details": {
    "reason": "AI_BUDGET_EXCEEDED",     // STABLE machine string — clients switch on this
    "retryAfter": 28800,
    "resetAt": "2026-08-29T00:00:00Z"
  }
}
```

### 1.2 Error reason registry

| `reason` | Code | Meaning | Client behaviour |
|---|---|---|---|
| `UNAUTHENTICATED` | `unauthenticated` | No/invalid ID token | Re-auth |
| `EMAIL_NOT_VERIFIED` | `permission-denied` | Verification required | Prompt to verify |
| `RATE_LIMITED` | `resource-exhausted` | Bucket exhausted | Back off `retryAfter` |
| `AI_BUDGET_EXCEEDED` | `resource-exhausted` | Daily token cap | Show cap message + reset time |
| `VALIDATION_FAILED` | `invalid-argument` | Schema violation | Fix input; log a bug |
| `PROVIDER_UNAVAILABLE` | `unavailable` | Upstream down | Retry with backoff; degrade |
| `PROVIDER_AUTH_EXPIRED` | `failed-precondition` | OAuth token dead | Prompt reconnect |
| `SAFETY_BLOCKED` | `invalid-argument` | Safety interceptor blocked | Render escalation copy |
| `NOT_FOUND` | `not-found` | Resource missing | Refresh list |
| `CONFLICT` | `aborted` | Concurrent modification | Refetch and retry |
| `PAYLOAD_TOO_LARGE` | `invalid-argument` | Batch exceeds limit | Split the batch |
| `INTERNAL` | `internal` | Unhandled | Generic error + Crashlytics |

### 1.3 Types

- Timestamps: ISO 8601 UTC strings (`2026-08-28T16:30:00Z`).
- Local dates: `yyyy-MM-dd` in the user's timezone.
- Units: metric (kg, cm, ml, kcal, g, seconds).
- IDs: UUID v7 for client-generated, provider-native otherwise.
- Money: `{ "amount": number, "currency": "ISO4217" }`.

---

## 2. AI

### 2.1 `aiChat`

Non-streaming AI turn. Use `aiStream` for the interactive path; this exists for background
and tool-completion flows.

**Request**
```jsonc
{
  "v": 1,
  "requestId": "0190f1a2-…",
  "data": {
    "conversationId": "str | null",       // null creates a new conversation
    "message": "Why is my bench stalling?",
    "forcedAssistant": "coach | claude | copilot | null",
    "contextEnabled": true,
    "attachments": [
      { "type": "image | pdf", "storagePath": "users/{uid}/uploads/…", "mimeType": "image/jpeg" }
    ]
  }
}
```

**Response**
```jsonc
{
  "ok": true,
  "data": {
    "conversationId": "str",
    "messageId": "str",
    "assistant": "coach",
    "routedBy": "auto",
    "routeIntent": "fitness",
    "routeConfidence": 0.94,
    "content": "Three things in your data: …",
    "contextSnapshotId": "str | null",
    "toolCalls": [
      { "id": "str", "name": "create_task", "arguments": { "title": "Sleep by 22:30" },
        "status": "awaiting_confirmation", "preview": "Create task \"Sleep by 22:30\"" }
    ],
    "tokenUsage": { "input": 3120, "output": 610 },
    "budgetRemaining": 46400,
    "latencyMs": 1840,
    "safetyFlags": []
  }
}
```

**Errors:** `AI_BUDGET_EXCEEDED` · `SAFETY_BLOCKED` · `PROVIDER_UNAVAILABLE` · `RATE_LIMITED`

---

### 2.2 `aiStream`

Same request shape as `aiChat`. Responds with `text/event-stream`.

```
event: route
data: {"assistant":"coach","intent":"fitness","confidence":0.94,"conversationId":"…"}

event: context
data: {"contextSnapshotId":"…","tokens":1840}

event: delta
data: {"text":"Three things "}

event: delta
data: {"text":"in your data: "}

event: tool_call
data: {"id":"tc_1","name":"create_task","arguments":{…},"status":"awaiting_confirmation"}

event: done
data: {"messageId":"…","tokenUsage":{"input":3120,"output":610},"budgetRemaining":46400}

event: error
data: {"reason":"PROVIDER_UNAVAILABLE","message":"Coach is temporarily unavailable."}
```

Client contract: render `delta` progressively; treat `done` as commit; on `error` after
partial content, keep what arrived and append a retry affordance.

---

### 2.3 `aiConfirmToolCall`

Executes a tool call the user approved. **No AI-proposed write ever executes without this.**

**Request**
```jsonc
{ "v": 1, "requestId": "…",
  "data": { "conversationId": "str", "messageId": "str", "toolCallId": "str",
            "approved": true,
            "modifiedArguments": { "title": "Lights out 22:30" } } }
```

**Response**
```jsonc
{ "ok": true,
  "data": { "toolCallId": "str", "status": "executed",
            "result": { "taskId": "str" },
            "followUpMessageId": "str | null" } }
```

---

### 2.4 `aiFeedback`

```jsonc
// request
{ "v": 1, "requestId": "…",
  "data": { "target": "message | insight", "targetId": "str",
            "rating": "up | down",
            "reason": "not_useful | not_accurate | already_knew | bad_timing | null",
            "comment": "str | null" } }

// response
{ "ok": true, "data": { "recorded": true } }
```

---

## 3. Health

### 3.1 `healthSyncCommit`

Commits a batch of normalized health records. **Max 400 records per call.**

**Request**
```jsonc
{
  "v": 1, "requestId": "…",
  "data": {
    "source": "health_connect",           // health_connect | samsung_health | galaxy_fit3 | manual
    "records": [
      { "idempotencyKey": "sha256:…",
        "type": "steps",
        "startAt": "2026-08-28T00:00:00Z",
        "endAt":   "2026-08-28T23:59:59Z",
        "localDate": "2026-08-28",
        "value": 8432, "unit": "count",
        "metadata": { "deviceModel": "SM-R390" } },
      { "idempotencyKey": "sha256:…",
        "type": "sleep_session",
        "startAt": "2026-08-27T23:15:00Z",
        "endAt":   "2026-08-28T06:26:00Z",
        "localDate": "2026-08-28",
        "value": 431, "unit": "minutes",
        "metadata": { "deepMinutes": 78, "remMinutes": 96,
                      "lightMinutes": 257, "awakeMinutes": 37, "awakenings": 3 } }
    ],
    "changesToken": "str | null"          // stored server-side for the next delta
  }
}
```

**Response**
```jsonc
{ "ok": true,
  "data": { "accepted": 398, "duplicates": 2, "rejected": 0,
            "rejectedKeys": [],
            "affectedDates": ["2026-08-27","2026-08-28"],
            "rollupsUpdated": 2,
            "nextSyncAfter": "2026-08-28T17:30:00Z" } }
```

**Record type enum**
`steps · heart_rate · resting_heart_rate · hrv · calories_active · calories_total ·
distance · active_minutes · sleep_session · exercise_session · stress · spo2 · weight ·
body_fat`

**Errors:** `PAYLOAD_TOO_LARGE` (> 400 records) · `VALIDATION_FAILED` · `RATE_LIMITED`

---

### 3.2 `healthBackfillStart`

```jsonc
// request
{ "v": 1, "requestId": "…",
  "data": { "source": "health_connect", "fromDate": "2026-05-31", "toDate": "2026-08-28",
            "types": ["steps","sleep_session","heart_rate","calories_active"] } }

// response
{ "ok": true,
  "data": { "backfillId": "str", "status": "queued",
            "estimatedChunks": 13, "estimatedSeconds": 90 } }
```

Progress is observed by the client on `users/{uid}/sync_state/{source}` rather than by
polling this endpoint.

---

### 3.3 `healthSyncStatus`

```jsonc
// request
{ "v": 1, "data": {} }

// response
{ "ok": true,
  "data": { "sources": [
      { "source": "health_connect", "status": "healthy",
        "lastSuccessAt": "2026-08-28T16:04:00Z", "recordsSynced": 12840,
        "consecutiveFailures": 0, "lastError": null,
        "backfill": { "complete": true, "cursorDate": "2026-05-31" },
        "byType": { "steps": { "lastAt": "…", "count": 3120 },
                    "sleep_session": { "lastAt": "…", "count": 89 } } } ] } }
```

---

## 4. Calendar

### 4.1 `calendarConnect`

```jsonc
// request
{ "v": 1, "requestId": "…",
  "data": { "provider": "google", "authCode": "4/0Ad…",
            "redirectUri": "os.lifedna.app:/oauth", "codeVerifier": "str" } }

// response
{ "ok": true,
  "data": { "accountId": "str", "accountEmail": "user@example.com",
            "calendars": [
              { "calendarId": "primary", "name": "Youssef Osman",
                "color": "#0066FF", "isPrimary": true, "canWrite": true, "enabled": true },
              { "calendarId": "…", "name": "University",
                "color": "#00D1B2", "isPrimary": false, "canWrite": false, "enabled": false }
            ],
            "grantedScopes": ["https://www.googleapis.com/auth/calendar.readonly"] } }
```

The authorization code is exchanged **server-side**; the client never holds a refresh token.

---

### 4.2 `calendarSync`

```jsonc
// request
{ "v": 1, "requestId": "…",
  "data": { "accountId": "str | null",     // null = all accounts
            "calendarIds": ["str"] | null,
            "fullResync": false,
            "rangeDaysBack": 7, "rangeDaysForward": 30 } }

// response
{ "ok": true,
  "data": { "synced": [
      { "accountId": "str", "calendarId": "primary",
        "created": 4, "updated": 11, "deleted": 1,
        "syncTokenRefreshed": false } ],
      "totalEvents": 128,
      "conflicts": [
        { "eventId": "str", "eventTitle": "Shift",
          "startAt": "2026-08-28T17:00:00Z", "endAt": "2026-08-28T22:00:00Z",
          "conflictsWith": { "type": "workout", "refId": "str",
                             "startAt": "2026-08-28T18:00:00Z",
                             "endAt": "2026-08-28T19:15:00Z" },
          "suggestions": [
            { "action": "move", "toStartAt": "2026-08-28T19:30:00Z" },
            { "action": "shorten", "toDurationMinutes": 45 } ] } ] } }
```

**Errors:** `PROVIDER_AUTH_EXPIRED` (client shows Reconnect) · `PROVIDER_UNAVAILABLE`

---

### 4.3 `calendarWriteEvent`

```jsonc
// request
{ "v": 1, "requestId": "…",
  "data": { "operation": "create",          // create | update | delete
            "accountId": "str", "calendarId": "primary",
            "eventId": "str | null",        // required for update/delete
            "event": {
              "title": "PUSH — Chest · Shoulders · Triceps",
              "description": "22 working sets · ~75 min",
              "startAt": "2026-08-29T18:00:00Z",
              "endAt":   "2026-08-29T19:15:00Z",
              "isAllDay": false,
              "location": "Gym",
              "reminders": [{ "minutesBefore": 45 }],
              "lifednaBlock": { "type": "workout", "refId": "str" } } } }

// response
{ "ok": true,
  "data": { "eventId": "str", "providerEventId": "str",
            "htmlLink": "https://calendar.google.com/…", "etag": "str" } }
```

**Errors:** `PROVIDER_AUTH_EXPIRED` with `details.requiredScope` when only the read scope
was granted — the client then runs incremental consent and retries.

---

### 4.4 `calendarDisconnect`

```jsonc
// request
{ "v": 1, "requestId": "…", "data": { "accountId": "str", "deleteCachedEvents": true } }

// response
{ "ok": true, "data": { "disconnected": true, "eventsDeleted": 128, "tokenRevoked": true } }
```

---

## 5. Nutrition

### 5.1 `foodSearch`

```jsonc
// request
{ "v": 1,
  "data": { "query": "chicken breast", "limit": 20, "offset": 0,
            "locale": "en", "includeUserFoods": true,
            "sources": ["internal","openfoodfacts","user"] } }

// response
{ "ok": true,
  "data": { "results": [
      { "id": "fd_chicken_breast_raw",
        "name": "Chicken breast, skinless, raw",
        "brand": null, "verified": true, "provider": "internal",
        "per100g": { "kcal": 165, "proteinG": 31, "carbsG": 0, "fatG": 3.6,
                     "fiberG": 0, "sugarG": 0, "sodiumMg": 74 },
        "servings": [ { "label": "100 g", "grams": 100 },
                      { "label": "1 breast (174 g)", "grams": 174 } ],
        "popularity": 98230, "score": 0.98 } ],
      "total": 47, "hasMore": true, "source": "internal", "latencyMs": 84 } }
```

---

### 5.2 `barcodeLookup`

```jsonc
// request
{ "v": 1, "data": { "barcode": "6224000123456", "locale": "en" } }

// response — found
{ "ok": true,
  "data": { "found": true,
            "food": { /* same shape as a foodSearch result */ },
            "source": "openfoodfacts",
            "cached": false,
            "dataQuality": "community" } }        // verified | community | user

// response — not found
{ "ok": true,
  "data": { "found": false, "barcode": "6224000123456",
            "suggestion": "create_food" } }
```

---

### 5.3 `recomputeTargets`

```jsonc
// request
{ "v": 1, "requestId": "…",
  "data": { "weightKg": 89.4, "heightCm": 174.5, "age": 21, "sex": "male",
            "activityLevel": "moderate", "goalMode": "cut",
            "trainingDaysPerWeek": 6, "weeklyRateTargetPct": 0.75,
            "applyImmediately": true } }

// response
{ "ok": true,
  "data": { "bmr": 1892, "tdee": 2932,
            "weeklyAverageTdee": 3189,
            "trainingDay": { "kcal": 2489, "proteinG": 198, "carbsG": 282, "fatG": 63 },
            "restDay":     { "kcal": 2189, "proteinG": 198, "carbsG": 207, "fatG": 63 },
            "proteinFloorG": 198, "waterMl": 3500,
            "projectedWeeklyChangeKg": -0.68,
            "projectedGoalDate": "2026-10-21",
            "clamped": false,
            "warnings": [],
            "engineVersion": "macro-1.0.0" } }
```

When the requested rate exceeds the safety ceiling the server clamps and returns
`"clamped": true` with `warnings: ["RATE_CLAMPED_TO_SAFE_MAXIMUM"]`. The client must render
the warning; it may not silently accept the clamped value.

---

## 6. Account

### 6.1 `exportData`

```jsonc
// request
{ "v": 1, "requestId": "…",
  "data": { "format": "json",              // json | csv | both
            "collections": ["all"],
            "dateRange": { "from": "2026-01-01", "to": "2026-08-28" } | null,
            "deliverBy": "email" } }       // email | link

// response
{ "ok": true,
  "data": { "exportId": "str", "status": "queued", "estimatedSeconds": 45,
            "deliveryEmail": "u***@example.com" } }
```

The download URL is a signed Cloud Storage URL valid for 24 hours. It is emailed, never
returned in this response, so a compromised session cannot exfiltrate the archive.

### 6.2 `deleteAccount`

```jsonc
// request
{ "v": 1, "requestId": "…",
  "data": { "confirmation": "DELETE", "reauthToken": "str", "reason": "str | null" } }

// response
{ "ok": true,
  "data": { "status": "scheduled", "purgeStartedAt": "2026-08-28T16:40:00Z",
            "completionBy": "2026-09-27T00:00:00Z",
            "confirmationEmailSent": true } }
```

### 6.3 `registerDevice`

```jsonc
// request
{ "v": 1, "requestId": "…",
  "data": { "deviceId": "str", "fcmToken": "str", "platform": "android",
            "osVersion": "14", "appVersion": "1.0.0", "model": "SM-S928B",
            "timezone": "Africa/Cairo", "notificationsPermitted": true } }

// response
{ "ok": true, "data": { "registered": true, "deviceId": "str" } }
```

---

## 7. Direct Firestore access (no callable needed)

These paths are read/written by the client SDK directly, governed by security rules. They
are part of the API surface and are versioned by the schema document, not by this file.

| Path | Access | Notes |
|---|---|---|
| `users/{uid}` | RW (restricted fields) | `subscription` is server-only |
| `users/{uid}/settings/*` | RW | |
| `users/{uid}/nutrition_logs/*` | RW | Client-generated IDs |
| `users/{uid}/water_logs/*` | RW | |
| `users/{uid}/meals/*` | RW | |
| `users/{uid}/supplements/*` | RW | |
| `users/{uid}/supplement_logs/*` | RW | |
| `users/{uid}/workout_templates/*` | RW | |
| `users/{uid}/workout_sessions/*` | RW | |
| `users/{uid}/workout_sessions/{sid}/sets/*` | RW | Append-dominant |
| `users/{uid}/body_metrics/*` | RW | |
| `users/{uid}/tasks/*` | RW | |
| `users/{uid}/ai_conversations/*` | RW | Messages: create user role only |
| `users/{uid}/daily_stats/*` | **R** | Server-derived |
| `users/{uid}/daily_plans/*` | **R** | Server-derived |
| `users/{uid}/recovery_data/*` | **R** | Server-derived |
| `users/{uid}/insights/*` | **R** + update `{status, feedback}` | |
| `users/{uid}/reports/*` | **R** | |
| `users/{uid}/calendar_events/*` | **R** | Writes go through `calendarWriteEvent` |
| `/exercises/*`, `/foods/*`, `/supplement_catalog/*` | **R** | Global catalogues |

---

## 8. AI tool registry

Tools an assistant may call. Every tool marked `requiresConfirmation` cannot execute until
`aiConfirmToolCall` approves it.

| Tool | Args | Returns | Confirmation |
|---|---|---|---|
| `get_nutrition_today` | `{}` | Today's totals + targets | No (read) |
| `get_training_history` | `{ exerciseId?, days }` | Sessions/sets summary | No |
| `get_recovery` | `{ days }` | Recovery series | No |
| `get_sleep` | `{ days }` | Sleep series | No |
| `get_body_trend` | `{ days }` | Weight EWMA + measurements | No |
| `get_calendar` | `{ from, to }` | Events | No |
| `get_tasks` | `{ status?, category? }` | Tasks | No |
| `log_meal` | `{ foodId, quantity, unit, mealSlot }` | Entry id | **Yes** |
| `log_water` | `{ ml }` | Total | **Yes** |
| `create_task` | `{ title, dueAt?, priority?, category? }` | Task id | **Yes** |
| `schedule_workout` | `{ templateId, startAt }` | Session/event id | **Yes** |
| `adjust_targets` | `{ kcalDelta?, proteinG? }` | New targets | **Yes** |
| `set_reminder` | `{ category, time, message }` | Notification id | **Yes** |
| `modify_template` | `{ templateId, changes }` | Template | **Yes** |

---

## 9. Rate limits

| Bucket | Limit | Window | Applies to |
|---|---|---|---|
| `ai` | 20 | 1 min | `aiChat`, `aiStream` |
| `ai_daily_tokens` | 60 000 (free) / 250 000 (pro) | 24 h rolling | AI total tokens |
| `health` | 60 | 1 min | `healthSyncCommit` |
| `calendar` | 30 | 1 min | Calendar callables |
| `search` | 60 | 1 min | `foodSearch`, `barcodeLookup` |
| `export` | 2 | 24 h | `exportData` |
| `account` | 2 | 24 h | `deleteAccount` |
| `default` | 120 | 1 min | Everything else |

Exceeding a bucket returns `RATE_LIMITED` with `retryAfter` in seconds. The client honours
it with exponential backoff and never hot-loops.

---

## 10. Versioning policy

- `v` is a **major** version. The server accepts the current major and the previous one for
  a minimum of 90 days after a bump.
- Additive, optional fields are **not** breaking and ship without a bump.
- Removing a field, renaming one, changing a type, or tightening validation **is** breaking.
- Every `reason` string is permanent. A reason is deprecated by ceasing to emit it, never
  by reusing it for a different meaning.
- The client must ignore unknown response fields and must never assume field order.
