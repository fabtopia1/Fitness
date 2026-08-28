# LifeDNA OS — Integrations

**Version:** 1.0
**Owner:** Mobile Lead

---

## 1. Integration strategy

| Principle | Consequence |
|---|---|
| **Prefer the open, system-level path** | Health Connect over the Samsung Health SDK, because it avoids a partner-approval dependency and works across vendors. |
| **Never re-implement a proprietary sync protocol** | Galaxy Fit 3 historical data arrives through Health Connect. BLE is used only for live heart rate, which the standard HRS profile exposes. |
| **Every integration is optional** | The absence of any integration degrades exactly one feature and never blocks the app. |
| **Ask in context, never at launch** | Permission grant rates roughly double when the request follows a screen that explains the value. |
| **The user can always see and repair sync state** | A sync status screen with per-type detail, last error, retry and full-resync. |

---

## 2. Health Connect (primary health path)

### 2.1 Data types

| LifeDNA type | Health Connect record | Read | Write back |
|---|---|---|---|
| `steps` | `StepsRecord` | ✅ | — |
| `heart_rate` | `HeartRateRecord` | ✅ | — |
| `resting_heart_rate` | `RestingHeartRateRecord` | ✅ | — |
| `hrv` | `HeartRateVariabilityRmssdRecord` | ✅ | — |
| `calories_active` | `ActiveCaloriesBurnedRecord` | ✅ | — |
| `calories_total` | `TotalCaloriesBurnedRecord` | ✅ | — |
| `distance` | `DistanceRecord` | ✅ | — |
| `active_minutes` | `ExerciseSessionRecord` (derived) | ✅ | — |
| `sleep_session` | `SleepSessionRecord` (+ stages) | ✅ | — |
| `exercise_session` | `ExerciseSessionRecord` | ✅ | ✅ |
| `weight` | `WeightRecord` | ✅ | ✅ |
| `body_fat` | `BodyFatRecord` | ✅ | ✅ |
| `spo2` | `OxygenSaturationRecord` | ✅ | — |
| `hydration` | `HydrationRecord` | ✅ | ✅ |
| `nutrition` | `NutritionRecord` | — | ✅ (optional) |

Write-back keeps the wider ecosystem consistent: a workout logged in LifeDNA appears in
Samsung Health and any other Health Connect client.

### 2.2 Android manifest declarations

```xml
<!-- Health Connect permissions -->
<uses-permission android:name="android.permission.health.READ_STEPS" />
<uses-permission android:name="android.permission.health.READ_HEART_RATE" />
<uses-permission android:name="android.permission.health.READ_RESTING_HEART_RATE" />
<uses-permission android:name="android.permission.health.READ_HEART_RATE_VARIABILITY" />
<uses-permission android:name="android.permission.health.READ_ACTIVE_CALORIES_BURNED" />
<uses-permission android:name="android.permission.health.READ_TOTAL_CALORIES_BURNED" />
<uses-permission android:name="android.permission.health.READ_DISTANCE" />
<uses-permission android:name="android.permission.health.READ_SLEEP" />
<uses-permission android:name="android.permission.health.READ_EXERCISE" />
<uses-permission android:name="android.permission.health.READ_WEIGHT" />
<uses-permission android:name="android.permission.health.READ_BODY_FAT" />
<uses-permission android:name="android.permission.health.READ_OXYGEN_SATURATION" />
<uses-permission android:name="android.permission.health.WRITE_EXERCISE" />
<uses-permission android:name="android.permission.health.WRITE_WEIGHT" />
<uses-permission android:name="android.permission.health.WRITE_HYDRATION" />

<!-- Required rationale activity (Play policy) -->
<activity-alias
    android:name="ViewPermissionUsageActivity"
    android:exported="true"
    android:targetActivity=".MainActivity"
    android:permission="android.permission.START_VIEW_PERMISSION_USAGE">
  <intent-filter>
    <action android:name="android.intent.action.VIEW_PERMISSION_USAGE" />
    <category android:name="android.intent.category.HEALTH_PERMISSIONS" />
  </intent-filter>
</activity-alias>
```

### 2.3 Sync algorithm

```kotlin
// android/.../health/HealthConnectPlugin.kt — outline
suspend fun readChanges(token: String?): SyncResult {
  val client = HealthConnectClient.getOrCreate(context)

  // First run: no token → seed one and do a bounded initial read.
  val changesToken = token ?: client.getChangesToken(
      ChangesTokenRequest(recordTypes = SUPPORTED_TYPES))

  val records = mutableListOf<NormalizedRecord>()
  var next: String? = changesToken
  var pages = 0

  while (next != null && pages < MAX_PAGES) {
    val response = client.getChanges(next)
    if (response.changesTokenExpired) {
      // Token expired → caller falls back to a bounded window read.
      return SyncResult.TokenExpired
    }
    response.changes.forEach { change ->
      when (change) {
        is UpsertionChange -> records += normalize(change.record)
        is DeletionChange  -> records += tombstone(change.recordId)
      }
    }
    next = if (response.hasMore) response.nextChangesToken else null
    pages++
  }
  return SyncResult.Success(records, next ?: changesToken)
}

private fun normalize(r: Record): NormalizedRecord {
  val key = sha256("${r.metadata.dataOrigin.packageName}|${typeOf(r)}|" +
                   "${startMillis(r)}|${endMillis(r)}")
  return NormalizedRecord(
    idempotencyKey = key,
    type = typeOf(r),
    source = sourceOf(r.metadata.dataOrigin.packageName),
    startAt = startMillis(r), endAt = endMillis(r),
    value = valueOf(r), unit = unitOf(r),
    metadata = extrasOf(r),
  )
}
```

**Cadence:** app foreground · `WorkManager` periodic 60 min (`NetworkType.CONNECTED`,
battery-not-low) · pull-to-refresh · after a workout is saved.

**Backfill:** first connect enqueues `healthBackfillStart` for 90 days, processed in 7-day
chunks with a resumable cursor in `sync_state`.

### 2.4 Deduplication and source precedence

```
idempotencyKey = sha256(source | type | startMs | endMs)
```

The same key is enforced twice — locally in Drift and again server-side — so a duplicate is
structurally impossible, not merely unlikely.

When two sources report the same metric for an overlapping window, precedence resolves it:

| Metric | Default precedence |
|---|---|
| Heart rate, HRV, resting HR | wearable (100) > phone (50) > manual (10) |
| Steps, distance, active minutes | wearable (100) > phone (50) |
| Sleep | wearable (100) > phone (50) > manual (10) |
| Weight, body fat | **manual (100)** > smart scale (80) > estimate (20) |
| Calories | wearable (100) > phone (50) |

Precedence is user-editable in Settings → Integrations. Losing records are retained but
excluded from aggregates and marked `superseded`.

### 2.5 Degradation

| Situation | Behaviour |
|---|---|
| Health Connect not installed (Android < 14) | Prompt to install; offer Samsung Health fallback; manual entry always available |
| All permissions denied | Recovery card → "Insufficient data" with reconnect CTA. Sleep and weight can be entered manually. Nothing else is affected. |
| Partial grant | Each unavailable metric is named explicitly with what it would unlock |
| Token expired | Silent fallback to a bounded window read, then a fresh token |

---

## 3. Samsung Health (fallback)

Used only for data types Health Connect does not expose, and only where the Samsung Health
SDK is available and the partner key has been approved.

| Aspect | Detail |
|---|---|
| Access | Samsung Health SDK for Android (`data` module), partner registration required |
| Types used as fallback | Stress, detailed sleep stages on older devices, body composition from Samsung scales |
| Permission model | Samsung's own consent dialog, requested separately and only after Health Connect has been attempted |
| Failure | Never blocks; the app simply reports those metrics as unavailable |

**Decision record:** Health Connect is primary specifically so that a delay or refusal in
Samsung partner approval cannot block the launch (`docs/01 §11 R-4`).

---

## 4. Galaxy Fit 3

### 4.1 What comes from where

| Data | Path | Why |
|---|---|---|
| Live heart rate during a session | **BLE GATT** — Heart Rate Service `0x180D`, characteristic `0x2A37` (notify) | Standard profile, real-time, no proprietary protocol |
| Battery level | **BLE GATT** — `0x180F` / `0x2A19` | Standard |
| Device info | **BLE GATT** — `0x180A` | Standard |
| Sleep, stress, SpO2, steps, calories, workouts | **Health Connect** (band → Samsung Health → Health Connect) | The band's authoritative sync path. Re-implementing it would be fragile and would break on firmware updates. |

### 4.2 BLE connection state machine

```
        ┌──────────────┐
        │ DISCONNECTED │◄──────────────────────────┐
        └──────┬───────┘                           │
               │ scan()                            │ error / timeout / user
        ┌──────▼───────┐                           │
        │   SCANNING   │───── not found (10 s) ────┤
        └──────┬───────┘                           │
               │ device found                      │
        ┌──────▼───────┐                           │
        │  CONNECTING  │───── failed ──────────────┤
        └──────┬───────┘                           │
               │ GATT connected                    │
        ┌──────▼───────┐                           │
        │ DISCOVERING  │───── no HRS ──────────────┤
        └──────┬───────┘                           │
               │ services resolved                 │
        ┌──────▼───────┐                           │
        │  CONNECTED   │───── link lost ───────────┘
        └──────┬───────┘        (auto-reconnect ×3, then give up quietly)
               │ subscribe 0x2A37
        ┌──────▼───────┐
        │  STREAMING   │  → live HR into Live Gym Mode
        └──────────────┘
```

**Reconnection:** 3 attempts with 2 s / 4 s / 8 s backoff. After that the app stops trying
and shows a passive "Band disconnected" chip — it never nags.

**Foreground service:** while a live session is streaming HR, `LiveSessionService` runs as
a foreground service with a `connectedDevice` type so Doze cannot kill the connection.
The notification shows session duration and current HR.

**Permissions:** `BLUETOOTH_SCAN` (with `neverForLocation`), `BLUETOOTH_CONNECT`,
`FOREGROUND_SERVICE`, `FOREGROUND_SERVICE_CONNECTED_DEVICE`.

### 4.3 Continuous health timeline

Band data and phone data are merged into one timeline per metric per day. Gaps are marked
explicitly rather than interpolated — a flat line the user believes is real is worse than a
visible gap.

```
HR timeline, 28 Aug
00:00 ──── band ──── 06:26   │ 06:26 ─ gap ─ 07:10 │ 07:10 ─ phone ─ 17:55 │ 17:55 ─ band ─ 24:00
```

---

## 5. Google Calendar

| Aspect | Detail |
|---|---|
| API | Calendar API v3 |
| Auth | OAuth 2.0 Authorization Code + PKCE; code exchanged server-side |
| Initial scope | `calendar.readonly` |
| Incremental scope | `calendar.events` requested only when the user first creates or edits an event |
| Sync | `events.list` with `syncToken`; on `410 Gone` → full resync for that calendar, silently |
| Window | −7 days to +30 days, extended on demand when the user navigates |
| Cadence | Server delta sync every 30 min; on-demand via `calendarSync` |
| Write | `calendarWriteEvent` callable; provider is authoritative, local cache updated from the response |
| Push (Phase 2) | `events.watch` webhook → immediate delta instead of polling |

**Why read-only first:** the write scope triggers a heavier consent screen and, for some
Workspace tenants, admin approval. Requesting it at connect time measurably reduces
connection rates. Asking at the moment the user taps "Add event" converts far better.

---

## 6. Microsoft Graph (Outlook Calendar + Copilot)

| Aspect | Detail |
|---|---|
| API | Microsoft Graph v1.0 |
| Auth | MSAL, Authorization Code + PKCE, Entra ID app registration |
| Scopes | `User.Read`, `Calendars.Read`, `Calendars.ReadWrite` (incremental), `Mail.Read` (optional, Copilot only), `offline_access` |
| Calendar sync | `/me/calendars`, then `/me/calendars/{id}/calendarView/delta` with `deltaLink` |
| Write | `POST /me/calendars/{id}/events`, `PATCH`, `DELETE` |
| Copilot mediation | Graph is the productivity substrate: mail summaries, meeting context, document lookup. Work-intent AI requests are answered with Graph-retrieved context. |
| Multi-tenant | The app registration is multi-tenant; some tenants require admin consent, which is surfaced as a specific, actionable error rather than a generic failure |

**Copilot integration model (v1):** the Copilot assistant is a *Graph-context-augmented*
assistant. A work-intent request retrieves the relevant Graph objects (today's meetings,
recent mail threads, referenced documents) and answers over them. This is deliverable
without a Copilot licence dependency and degrades cleanly for users who have one.
(Open question Q-4 in `docs/01` tracks whether v2 adds a direct Copilot passthrough.)

---

## 7. Open Food Facts

| Aspect | Detail |
|---|---|
| Use | Barcode resolution and food search fallback |
| Auth | None (public API); a descriptive User-Agent is required by their terms |
| Caching | Every resolved product is written into `/foods` with `provider: "openfoodfacts"` so the second user to scan it pays zero latency |
| Quality | Community data is labelled as such in the UI. Users can correct any field; corrections are stored per user and, above a confidence threshold, promoted to the shared record |
| Rate limiting | Server-side only; the client never calls Open Food Facts directly |
| Fallback | Not found → manual creation, which is then cached for that user and submitted to the shared pool |

---

## 8. Firebase Cloud Messaging

| Aspect | Detail |
|---|---|
| Token lifecycle | Registered on launch and on refresh via `registerDevice`; stale tokens pruned on `UNREGISTERED` responses |
| Channels (Android) | One per category — `hydration`, `meal`, `supplement`, `workout`, `sleep`, `meeting`, `task`, `recovery`, `insight`, `system` — so the user can tune each in system settings |
| Priority | `high` for time-critical (meal, workout, meeting), `default` for the rest |
| Payload | Data-only messages; the client renders the notification so it can apply suppression rules at delivery time |
| Actions | Inline actions per category (`Log 250 ml`, `Taken`, `Snooze 15 min`, `Start workout`) |
| Deep links | Every notification carries a `deeplink` that lands on the exact screen with the exact state |
| Local vs push | Deterministic, time-based reminders are scheduled **locally** so they fire offline. Only data-dependent notifications go through FCM. |

---

## 9. Integration health monitoring

Every integration writes `users/{uid}/sync_state/{sourceId}`:

```jsonc
{ "sourceId": "health_connect", "status": "healthy",
  "lastSuccessAt": "ts", "lastAttemptAt": "ts",
  "consecutiveFailures": 0, "recordsSynced": 12840, "lastError": null }
```

| Status | Meaning | UI |
|---|---|---|
| `healthy` | Last attempt succeeded | Green check + relative time |
| `degraded` | 1–4 consecutive failures | Amber, silent, auto-retry |
| `failing` | ≥ 5 consecutive failures | Red, banner in Settings, manual retry offered |
| `needs_reauth` | Credentials invalid | Red + one `Reconnect` notification (never repeated) |
| `disconnected` | User disconnected | Neutral, reconnect CTA |

Alerting: if more than 5 % of accounts on a given source enter `failing` within an hour, the
on-call engineer is paged — that pattern means a provider change, not user error.

---

## 10. Integration test matrix

| Integration | Unit | Integration | Manual / device |
|---|---|---|---|
| Health Connect | Normalizer + dedup key on recorded payloads | Emulated client with synthetic records | Real device, real band, 7-day soak |
| Galaxy Fit 3 BLE | State machine transitions | Mock GATT peripheral | Real band: pair, stream, disconnect, reconnect, Doze survival |
| Google Calendar | Event mapper, sync-token handling | Recorded HTTP fixtures | Real account: connect, edit, conflict, 410 resync |
| Microsoft Graph | Same | Recorded fixtures | Real account incl. a tenant requiring admin consent |
| Open Food Facts | Mapper, quality labelling | Recorded fixtures | Scan 20 real regional products |
| FCM | Payload builder, suppression rules | Emulator | Real device: delivery, actions, deep links, quiet hours, doze |
