# 06 — User flow diagrams

Every flow below is exercised by an automated test; the test file is named
under each diagram.

## 1. First launch → a working dashboard

```mermaid
flowchart TD
    A[Cold start] --> B[AppBootstrap: Hive, keystore, Firebase, notifications]
    B -->|bootstrap threw| BF[Could not start screen<br/>with a retry]
    B --> C{Firebase configured?}
    C -->|no| D[Local mode]
    C -->|yes| E[Cloud mode]
    D --> F[/welcome/]
    E --> F
    F --> G{Choice}
    G -->|Continue on this device| H[Local session written to Hive]
    G -->|Create account| I[/sign-up/]
    G -->|Sign in| J[/sign-in/]
    I --> K[Profile created locally, not by a server trigger]
    J --> K
    H --> K
    K --> L{isOnboarded?}
    L -->|no| M[/onboarding/]
    L -->|yes| N[/home/]
    M --> N
```

The profile is created on the device rather than by a Firestore trigger, so a
user who signs up on a plane still has a working account when they land.

*Tested by* `test/support/scenarios.dart` and `test/widget/features/auth_flow_test.dart`.

## 2. Onboarding

```mermaid
flowchart LR
    S1[1 · About you<br/>date of birth, sex] --> S2[2 · Measurements<br/>height, weight]
    S2 --> S3[3 · Goal<br/>lose / maintain / build,<br/>pace, activity, training days]
    S3 --> S4[4 · Your targets]
    S4 -->|Back| S3
    S4 -->|Start using LifeDNA| DONE[onboardingCompletedAt written<br/>router redirects to /home]
```

Step 4 shows the **derived** numbers — BMR, TDEE, training and rest-day
targets, protein floor, water, projected weekly change, and any safety clamp
that was applied — *before* anything is committed. A user who disagrees with a
number can walk back and change the input that produced it. A confirmation
dialog would have hidden the derivation.

Validation refuses a height outside 90–250 cm and a weight outside 30–300 kg
at entry, because bad body data propagates into every target the app computes.

*Tested by* `auth_flow_test.dart` — including the full four-step walk and the
out-of-range refusal.

## 3. Logging food

```mermaid
flowchart TD
    A[/nutrition/] -->|Add| B[/nutrition/add?slot=…/]
    B --> C{Search your foods}
    C -->|match| D[PortionSheet]
    C -->|nothing| E[CreateFoodSheet<br/>per-100 g values]
    E -->|saved| D
    D --> F[Stepper ±10 g, presets, live macro preview]
    F --> G[Add to lunch]
    G --> H[Validate: quantity > 0, grams ≤ 5000]
    H -->|fails| F
    H -->|passes| I[Hive commit]
    I --> J[Outbox enqueue]
    J --> K[Best-effort Firestore]
    I --> L[useCount++ so search learns]
    I --> M[Day totals recompute from the log stream]
```

The energy consistency check in `CreateFoodSheet` compares the stated calories
against the Atwater reconstruction from the macros and warns on a divergence
above 15 %. Community food data fails this constantly, and saving it silently
would poison every daily total computed from it afterwards.

*Tested by* `test/widget/features/flows_test.dart` and
`test/unit/features/nutrition/nutrition_repository_test.dart`.

## 4. Live Gym Mode

```mermaid
flowchart TD
    A[/train/] --> B{Session in progress?}
    B -->|yes| C[Resume workout]
    B -->|no| D[Pick a program or Start empty]
    C --> E[/train/live/]
    D --> E
    E --> F[Panel: exercise, set N of M,<br/>weight and rep steppers, RPE]
    F --> G[Prefill from lastPerformance<br/>— not from zero]
    G --> H[COMPLETE SET · 72 dp]
    H --> I[Validate 0–500 kg, 1–100 reps]
    I --> J[PrDetector runs against history]
    J -->|record| K[Haptic + inline 🏆<br/>never a modal mid-workout]
    J --> L[Rest overlay: countdown, ±15 s, Skip]
    L -->|expires| M[Local notification 'Rest finished'<br/>— fires with the app backgrounded]
    L --> F
    F -->|Finish| N{Any sets?}
    N -->|no| O[Discard workout? · Keep going / Discard]
    N -->|yes| P[Summary: minutes, volume, sets, PRs]
    P -->|Save workout| Q[status = completed<br/>program useCount++ and lastPerformedAt]
    P -->|Keep going| F
```

Rest alerts go through **local** notifications, not FCM. A rest timer that
needs a network to fire is a rest timer that fails in the basement where it
matters.

*Tested by* `test/widget/features/live_workout_test.dart` — 23 tests covering
prefill, the steppers, PR announcement, the rest timer firing a notification,
discard, summary, and adding an exercise mid-session.

## 5. Offline write and reconciliation

```mermaid
sequenceDiagram
    participant U as User
    participant H as Hive
    participant O as Outbox
    participant S as SyncEngine
    participant F as Firestore

    U->>H: log a set
    H-->>U: committed (this is the commit)
    H->>O: enqueue upsert(workout_sessions/abc)
    O-->>S: pending
    S->>F: set(merge: true)
    alt online
        F-->>S: ok
        S->>O: complete → entry removed
    else offline or error
        F--xS: unavailable
        S->>O: recordFailure → backoff 4 s … 900 s
        Note over O: after 10 attempts the entry PARKS
        O-->>U: banner: "1 change couldn't sync · Retry"
    end
```

Rapid edits to the same document collapse: the outbox is keyed by
`collection/docId`, so typing in a field queues one write rather than one per
keystroke.

*Tested by* `test/unit/core/sync/outbox_test.dart` and `sync_engine_test.dart`.

## 6. Two devices

```mermaid
sequenceDiagram
    participant A as Phone A
    participant F as Firestore
    participant B as Phone B

    A->>F: upsert task (updatedAt = 10:00)
    B->>F: pull since 09:00
    F-->>B: the task
    B->>B: local copy is older → apply
    B->>F: upsert same task (updatedAt = 10:05)
    A->>F: pull
    F-->>A: updatedAt 10:05 > local 10:00 → apply
    Note over A,B: a local record that is strictly NEWER is never overwritten,<br/>so a slow pull cannot undo something typed 30 seconds ago
```

Deletes replicate as tombstones (`deletedAt`), because a hard delete would be
resurrected by the other device's next pull.

## 7. Reminders

```mermaid
flowchart TD
    A[Supplement / task / user reminder saved] --> B[Cancel the previous id]
    B --> C{Master switch on?}
    C -->|no| D[Nothing scheduled]
    C -->|yes| E{Enabled and not deleted?}
    E -->|no| D
    E -->|yes| F[Schedule, id derived from the record id]
    F --> G[Android fires it, no network involved]
    G --> H[Reboot] --> I[ScheduledNotificationBootReceiver<br/>+ rescheduleAll on launch]
```

The master switch lives inside `NotificationService`, so a reminder created
while it is off cannot slip past it whichever feature creates it. The gate is
restored on every cold start; otherwise a user who turned reminders off would
be notified again after the next launch.

Notification ids are derived from the record id, so rescheduling **replaces**
rather than stacking a second alarm at the same time.

## 8. Google Calendar

```mermaid
flowchart TD
    A[/plan/ → Sync] --> B{Client id configured?}
    B -->|no| C[The action is not offered at all]
    B -->|yes| D{Connected?}
    D -->|no| E[Google sign-in, calendar.readonly scope]
    D -->|yes| F[events.list, −7 to +30 days]
    E --> F
    F --> G[Mirror into calendar_events, source = google]
    G --> H[Read-only: editing or deleting a mirrored event is refused]
    A2[Disconnect] --> I[Every google-sourced event is tombstoned]
```

The scope is **read-only**. LifeDNA shows the user's day; it has no business
writing to their calendar. Disconnecting removes the mirror, because keeping a
copy of someone's meetings after they revoked access would be indefensible.

## 9. AI Hub

```mermaid
flowchart TD
    A[/ai/] --> B[LocalCoach.analyse — deterministic rules<br/>over the user's own numbers]
    B --> C[Ranked insights, each with the evidence that produced it]
    A --> D[Ask an assistant]
    D --> E[Prompt sheet shows the ENTIRE brief<br/>in selectable text]
    E --> F[Copy to clipboard]
    E --> G[Copy and open Claude / Copilot]
    G --> H[External browser, the user's own account]
```

Nothing here calls a model. There is no API key in the app, no request to any
AI provider, and no hidden payload — the user sees the exact text before it
goes anywhere, and it contains numbers only: no email, no name, no identifier.

*Tested by* `test/unit/features/ai_hub/ai_coach_test.dart`, including an
assertion that the brief contains no `@` and no `uid`.

## 10. Health sync

```mermaid
flowchart TD
    A[/health/] --> B[HealthSyncService.availability]
    B --> C{Result}
    C -->|not Android| D[Not available on this device]
    C -->|MissingPluginException| E[Not enabled in this build<br/>+ the exact enablement steps]
    C -->|provider missing| F[Health Connect not installed]
    C -->|needs permission| G[Permission needed → request]
    C -->|ready| H[Read steps, active calories, sleep, resting HR]
    H --> I[Summarise: cumulative metrics SUM,<br/>instantaneous metrics AVERAGE]
```

In the shipped MVP the native handler is not registered, so the screen reports
"Not enabled in this build" and lists what a developer must do. It renders no
step count. **A screen showing plausible-looking numbers that were invented
would be worse than a screen showing nothing.**
