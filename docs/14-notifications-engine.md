# LifeDNA OS — Notifications Engine

**Version:** 1.0
**Owner:** Product + Backend

---

## 1. The problem this engine exists to solve

A product with fifteen modules could plausibly send forty notifications a day. That product
gets uninstalled in week one. The engine's job is not to send notifications — it is to
**suppress** the ones that no longer matter and rank what remains.

Three mechanisms do the work:

1. **Suppression** — a reminder whose action is already satisfied is cancelled, not sent.
2. **Capping** — a hard daily ceiling drops the lowest-priority pending items.
3. **Local scheduling** — deterministic reminders fire on-device so they work offline and
   so the server is never the reason a meal reminder is late.

Opt-out rate is a tracked counter-metric (`docs/01 §3.4`): if it exceeds 12 %, the engine is
too aggressive regardless of what any engagement metric says.

---

## 2. Categories

| Category | Priority | Channel | Default | Example |
|---|---|---|---|---|
| `meeting` | 95 | FCM | on | "Standup in 10 minutes" |
| `workout` | 90 | Local | on | "Workout starts in 45 minutes — PUSH, 22 sets" |
| `meal` | 85 | Local | on | "Time for Meal 1 — eggs, foul, baladi bread" |
| `task` | 80 | Local | on | "Submit DS assignment — due in 30 minutes" |
| `supplement` | 70 | Local | on | "Creatine 5 g — post-workout" |
| `recovery` | 65 | FCM | on | "Recovery 28 — today's session is scaled back" |
| `insight` | 60 | FCM | on | "Sleep dropped 14 % this week" |
| `sleep` | 55 | Local | on | "Wind down — target 7.5 h for tomorrow's lower session" |
| `hydration` | 40 | Local | on | "Drink 250 ml — you're 750 ml behind" |
| `system` | 30 | FCM | on | "Calendar access expired" |

Each category is independently toggleable and has its own schedule. Each maps to a distinct
Android notification channel, so the user can also tune importance and sound in system
settings without disabling the category in-app.

---

## 3. Local vs. push

| Property | Local (`flutter_local_notifications`) | Push (FCM) |
|---|---|---|
| Determined by | Time and user configuration | Server-computed data |
| Works offline | ✅ | ✗ |
| Categories | meal, workout, supplement, hydration, sleep, task | meeting, recovery, insight, system |
| Scheduled | On the device, up to 7 days ahead, re-armed on app open | Cloud Tasks at the target minute |
| Cancellation | Immediate, on-device, at the moment the action is satisfied | Task deleted before dispatch |

**Why the split matters:** the gym has no signal, and a meal reminder that requires
connectivity is a meal reminder that fails exactly when the user is least likely to be
looking at their phone.

---

## 4. Scheduling pipeline

```
06:15 local  ▷ notificationPlanner (server)
   │
   ├─ read: settings/notifications · meal_plan · daily_plan · supplements ·
   │        calendar_events · tasks · insights · recovery_data
   │
   ├─ build the day's candidate list
   │     for each candidate: { category, scheduledFor, priority, payload,
   │                           suppressionCondition, idempotencyKey }
   │
   ├─ apply quiet hours          → drop or shift non-critical candidates
   ├─ apply the daily cap        → sort by priority, keep the top N
   ├─ apply per-category limits  → e.g. max 4 hydration/day
   │
   ├─ LOCAL candidates  → written to users/{uid}/notifications with status=scheduled
   │                      the client reads them and arms them on-device
   └─ PUSH candidates   → one Cloud Task per notification, named by idempotencyKey
```

**Client re-arm:** on every foreground the client reads the day's scheduled local
notifications and reconciles them with what the OS has armed. This repairs the case where
the device rebooted, the app was force-stopped, or the plan changed mid-day.

---

## 5. Suppression rules

The heart of the engine. Each rule is evaluated **at fire time**, not only at schedule time.

| Category | Suppressed when |
|---|---|
| `meal` | An entry exists for that meal slot today |
| `hydration` | Water logged within the last 45 minutes, or the daily target is met |
| `supplement` | That supplement is logged today at that anchor |
| `workout` | A session for today is `in_progress` or `completed` |
| `sleep` | The device has been idle > 30 min (already asleep), or a session is in progress |
| `task` | The task is `done` or `cancelled` |
| `meeting` | The event was cancelled or declined |
| `recovery` | Already opened the recovery screen today |
| `insight` | The insight was already seen or acted on |

Implementation on the client:

```dart
Future<bool> shouldSuppress(ScheduledNotification n) async {
  return switch (n.category) {
    NotificationCategory.meal =>
      await _nutrition.hasEntryForSlot(n.localDate, n.payload.mealSlot),
    NotificationCategory.hydration =>
      await _nutrition.lastWaterLogWithin(const Duration(minutes: 45)) ||
      await _nutrition.waterTargetMet(n.localDate),
    NotificationCategory.supplement =>
      await _supplements.isLoggedToday(n.payload.supplementId, n.payload.anchor),
    NotificationCategory.workout =>
      await _workout.hasSessionToday(n.localDate),
    NotificationCategory.task =>
      await _tasks.isClosed(n.payload.taskId),
    _ => false,
  };
}
```

A suppressed notification is recorded with `status: suppressed` and its
`suppressionReason`, so the effectiveness of the rules is measurable rather than assumed.

---

## 6. Quiet hours

```
Default: 23:00 – 07:00

Behaviour by priority:
  priority ≥ 90  → delivered (a meeting at 06:45 must fire)
  priority < 90  → shifted to the end of quiet hours, or dropped if
                   its relevance window has passed by then

Sleep reminders are exempt in the other direction: they are *scheduled into* the
approach to quiet hours by design (22:45 for a 23:00 start).
```

Quiet hours are per-user and can be disabled entirely. When disabled, the daily cap still
applies.

---

## 7. Daily cap

```
Default cap: 9 notifications/day (user-configurable, 3–20)

When the planned list exceeds the cap:
  1. sort by priority descending, then by scheduledFor ascending
  2. keep the top N
  3. drop the remainder with status = suppressed, reason = daily_cap
  4. never drop more than 2 of any single category before dropping from another
     (prevents the cap from silently disabling hydration entirely)
```

Per-category sub-limits: hydration ≤ 4, supplement ≤ 5, insight ≤ 1, task ≤ 3.

---

## 8. Inline actions

Every notification is actionable without opening the app, because opening the app is
friction and friction is why reminders get ignored.

| Category | Actions |
|---|---|
| `meal` | `Log planned meal` · `Snooze 30 min` · `Skip` |
| `hydration` | `+250 ml` · `+500 ml` · `Snooze 1 h` |
| `supplement` | `Taken` · `Snooze 15 min` · `Skip today` |
| `workout` | `Start workout` · `Snooze 15 min` · `Move to…` |
| `task` | `Done` · `Snooze 1 h` · `Reschedule` |
| `sleep` | `Good night` (dismisses and logs intent) · `Snooze 30 min` |
| `insight` | `Apply` · `Dismiss` |
| `recovery` | `Apply reduced session` · `View` |

Actions execute through the **same use cases as the UI** — a dose logged from a notification
is identical in every respect to one logged in the app, including offline behaviour and
rollup updates.

---

## 9. Deep links

Every notification carries a `deeplink` that lands on the exact screen in the exact state.

| Category | Deep link |
|---|---|
| `meal` | `/nutrition/log?slot=breakfast&date=2026-08-28` |
| `workout` | `/train` or `/live/{sessionId}` if resumable |
| `supplement` | `/me/supplements` |
| `task` | `/plan/task/{taskId}` |
| `meeting` | `/plan/event/{eventId}` |
| `insight` | `/insight/{insightId}` |
| `recovery` | `/me/recovery` |
| `system` | `/me/settings/integrations` |

Cold-start deep links are handled by the router's initial-location resolver, so a
notification tap from a killed app lands correctly rather than on the dashboard.

---

## 10. Android channels

```kotlin
val channels = listOf(
  Channel("meeting",    "Meetings",     IMPORTANCE_HIGH),
  Channel("workout",    "Workouts",     IMPORTANCE_HIGH),
  Channel("meal",       "Meals",        IMPORTANCE_DEFAULT),
  Channel("task",       "Tasks",        IMPORTANCE_DEFAULT),
  Channel("supplement", "Supplements",  IMPORTANCE_DEFAULT),
  Channel("recovery",   "Recovery",     IMPORTANCE_DEFAULT),
  Channel("insight",    "Insights",     IMPORTANCE_LOW),
  Channel("sleep",      "Sleep",        IMPORTANCE_LOW),
  Channel("hydration",  "Hydration",    IMPORTANCE_LOW),
  Channel("system",     "System",       IMPORTANCE_DEFAULT),
  Channel("live_session","Live session",IMPORTANCE_LOW),   // foreground service
)
```

`live_session` is the ongoing foreground-service notification during Live Gym Mode. It is
non-dismissible while a session is active, shows duration and current heart rate, and
carries a `Finish workout` action.

---

## 11. Permission strategy

Android 13+ requires runtime notification permission. It is **not** requested at launch.

```
Requested at the first moment a notification would demonstrably help:
  • after the first meal is logged  → "Want a reminder for your next meal?"
  • after the first workout is scheduled → "Remind you 45 minutes before?"

If denied:
  • all local scheduling is skipped
  • the dashboard's Next Action card takes over the reminding role entirely
  • a single, dismissible settings row offers to re-enable — never a repeated prompt
```

---

## 12. Analytics

| Event | Properties | Answers |
|---|---|---|
| `notification_scheduled` | category, priority, leadMinutes | What are we planning to send? |
| `notification_suppressed` | category, reason | Are the suppression rules working? |
| `notification_delivered` | category, hour | What actually goes out? |
| `notification_opened` | category, secondsToOpen | Which categories earn attention? |
| `notification_action` | category, actionId | Are inline actions used? |
| `notification_dismissed` | category | Which categories are noise? |
| `notification_category_disabled` | category | The strongest negative signal we have |

**Health metrics reviewed weekly**

| Metric | Target |
|---|---|
| Open rate | ≥ 35 % |
| Inline action rate | ≥ 20 % |
| Suppression rate | ≥ 25 % (proof the rules are earning their keep) |
| Category disable rate | ≤ 5 % per category |
| Median daily delivered | ≤ 6 |

A category whose disable rate exceeds 8 % is redesigned or removed. No exceptions, and no
appeal to its engagement numbers — a user who disables a category has told us something
more important than a click-through rate.
