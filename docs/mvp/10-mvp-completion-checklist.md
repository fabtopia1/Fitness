# 10 — MVP completion checklist

Legend: **✅ shipped and tested** · **⚠️ shipped with a documented limit** ·
**⛔ deliberately absent**

## Module 1 — Authentication

| Requirement | Status | Evidence |
|---|---|---|
| Email + password sign-up | ✅ | `auth_repository.dart`; 21 tests |
| Email + password sign-in | ✅ | validated before any network call |
| Google Sign-In | ⚠️ | implemented; hidden when the build has no Firebase, because a button that cannot work is worse than no button |
| Password reset | ✅ | reports `firebase_unavailable` honestly in local mode |
| Profile setup / onboarding | ✅ | four steps; `auth_flow_test.dart` walks all of them |
| Sign-out | ✅ | wipes every local box — shared-device privacy |
| Local mode (no Firebase) | ✅ | a first-class supported path |

## Module 2 — Dashboard

| Requirement | Status | Evidence |
|---|---|---|
| Today's calories and macros | ✅ | derived from the log stream, never stored |
| Water | ✅ | same collection as food, so a day is one pass |
| Supplements due | ✅ | reads the real schedule |
| Training status | ✅ | live-session awareness, weekly volume |
| Body trend | ✅ | smoothed, not raw |
| Tasks and events | ✅ | overdue count |
| Loading / empty / error / offline | ✅ | via `LdAsyncView` |

## Module 3 — Nutrition tracking

| Requirement | Status | Evidence |
|---|---|---|
| Food database (user-owned) | ✅ | ranked local search that learns from use |
| Create a food from label values | ✅ | with an Atwater consistency warning |
| Log a portion (g / ml / serving) | ✅ | `PortionSheet` with a live macro preview |
| Saved meals | ✅ | one log entry written per item |
| Water logging | ✅ | |
| Daily totals vs targets | ✅ | derived from the profile |
| Delete an entry | ✅ | swipe; tombstone replicates |
| Validation | ✅ | non-positive and implausible quantities refused |

## Module 4 — Supplement tracking

| Requirement | Status | Evidence |
|---|---|---|
| Stack management | ✅ | name, dose, unit, frequency |
| Daily / weekday / training-day schedules | ✅ | 19 tests |
| Reminders | ✅ | replace rather than stack; survive reboot |
| Log a dose | ✅ | **idempotent by construction** — id is `supplementId_date` |
| Undo a dose | ✅ | |
| Adherence | ✅ | recomputes each supplement's own schedule |
| Starter stack | ✅ | seeds once |

## Module 5 — Workout tracker

| Requirement | Status | Evidence |
|---|---|---|
| Exercise library | ✅ | search, muscle filter, custom exercises |
| Program builder | ✅ | reorderable, per-exercise sets/reps/rest |
| **Live Gym Mode** | ✅ | 23 tests |
| Prefill from last performance | ✅ | not from zero — the friction that stops people logging |
| Rest timer | ✅ | ±15 s, skip, **local** notification when it expires |
| PR tracking | ✅ | derived from sessions; best e1RM wins, not heaviest bar |
| Session summary | ✅ | duration, volume, sets, PRs |
| Resume from anywhere | ✅ | persistent bar + live dot on the Train icon |
| Discard an empty session | ✅ | with a confirmation |
| Weekly volume history | ✅ | ISO weeks |

## Module 6 — Body tracking

| Requirement | Status | Evidence |
|---|---|---|
| Weight and body fat | ✅ | 17 tests |
| Circumferences | ✅ | eight sites, behind a disclosure |
| Progress photos | ⚠️ | captured and shown; **device-local only**, never uploaded |
| Trend chart | ✅ | `fl_chart`, metric selector offers only metrics with data |
| Smoothed trend | ✅ | EWMA — a day of water weight must not read as fat gain |
| Weekly rate | ✅ | per week, not per window |
| Validation | ✅ | impossible values and future dates refused |

## Module 7 — Calendar, tasks and reminders

| Requirement | Status | Evidence |
|---|---|---|
| Tasks with priority and category | ✅ | 18 tests |
| Due dates and overdue detection | ✅ | overdue first, then due date, then priority |
| Task reminders | ✅ | cancelled the moment a task is completed |
| Events | ✅ | validated: must end after it starts |
| **Google Calendar** | ✅ | read-only scope; mirrored events are not editable |
| Disconnect | ✅ | removes the mirror entirely |
| **Standalone reminders** | ✅ | daily, editable, per-item switch |
| Reboot survival | ✅ | boot receiver + reschedule on launch |

## Module 8 — Samsung Health

| Requirement | Status | Evidence |
|---|---|---|
| Sync module architecture | ✅ | Health Connect, not the Samsung SDK — see below |
| API layer | ✅ | `HealthSyncService`, `MethodChannel os.lifedna/health` |
| Permission handling | ✅ | full availability state machine, 15 tests |
| Ready-to-enable integration | ✅ | the screen lists the exact enablement steps |
| Reading real samples | ⛔ | the native handler is not registered in this build |
| **Fabricated data** | ⛔ | never. An absent provider returns an empty list |

Health Connect rather than the Samsung Health Data SDK: the Samsung SDK
requires partner registration and per-app approval that cannot be obtained
during a build, and Samsung Health writes its data into Health Connect anyway
— so reading Health Connect *is* reading Samsung Health, without a commercial
dependency that could block the release.

## Module 9 — AI Hub

| Requirement | Status | Evidence |
|---|---|---|
| Custom AI coach | ✅ | `LocalCoach.analyse` — deterministic rules, 14 tests |
| Insights carry their evidence | ✅ | every insight shows the numbers that produced it |
| Prompt templates | ✅ | unique ids, complete text |
| Claude shortcut | ✅ | clipboard + `launchUrl` |
| Copilot shortcut | ✅ | same |
| The brief is shown before it leaves | ✅ | selectable text, numbers only, no identifiers |
| **A fake AI API** | ⛔ | never. No key, no request, no model |

## Cross-cutting requirements

| Requirement | Status |
|---|---|
| Offline-first: every write local-first | ✅ |
| Durable outbox with backoff and parking | ✅ |
| Encrypted local storage | ✅ (keystore, with an honest fallback) |
| Firestore security rules | ✅ (39 tests against the real engine) |
| Authentication guards | ✅ (one router redirect) |
| Input validation | ✅ (form, repository, and rules) |
| Secure API key management | ✅ (`--dart-define`; nothing committed) |
| Every screen: loading/empty/error/offline/retry | ✅ (`LdAsyncView`) |
| Network timeout handling | ✅ (20 s, then treated as offline) |
| Dark theme first, Material 3 | ✅ |
| Large touch targets, one-handed gym use | ✅ (48 / 64 / 72 dp) |
| Smooth animations, reduce-motion honoured | ✅ |
| 80 % test coverage | ✅ (82.19 %, gated) |
| Unit / widget / integration tests | ✅ (380 / 123 / 3 + 39 rules) |
| dev / staging / prod configuration | ✅ (three flavours, separate ids) |
| GitHub Actions CI | ✅ (six jobs) |
| Automated build verification | ✅ (a matrix over all three flavours) |
| `flutter analyze` in CI | ✅ (`--fatal-infos`) |
| Release build process | ⚠️ (configured and documented; not yet executed on hardware — TD-01) |
| **No TODOs in the code** | ✅ (`todo: error`; a TODO fails the build) |
| **No placeholder screens** | ✅ (every route resolves to a real screen) |
| **No fake integrations** | ✅ |
