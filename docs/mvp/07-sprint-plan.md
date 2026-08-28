# 07 — Development sprint plan

## 1. What was actually built, in the order it was built

Each sprint below corresponds to real commits on
`claude/lifedna-os-design-npdd59`. Nothing here is aspirational.

### Sprint 0 — Design (complete)
`docs/01`–`docs/20`. PRD, system architecture, database schema, design
system, user flows, wireframes, project structure, backend architecture, API
contracts, integrations, AI layer, three engine specifications, notifications,
analytics, roadmap, MVP backlog, QA strategy, security and privacy, future
expansion. 9 466 lines.

**Exit criterion met:** every MVP feature had a written specification before a
line of it was implemented.

### Sprint 1 — Foundation (complete)
`3b49979`, `c84f81f`

- A real Flutter 3.47.2 project, created by the tool rather than hand-written,
  so the platform folders and the Gradle wiring are the ones Flutter expects.
- `HiveStore` — 18 AES-encrypted boxes, keyed from the Android Keystore.
- `SyncedCollection` — the Hive → outbox → Firestore write path.
- `Outbox` and `SyncEngine` — durable queue, exponential backoff, parking.
- Sealed `Result` and `Failure`, and one `FailureMapper` from exception to
  user-facing copy.
- The four engines, ported and bound to the shared fixtures.
- Every domain entity and every repository for all nine modules.

**Exit criterion met:** `flutter analyze` clean; the engine parity suite green.

### Sprint 2 — Screens (complete)
`61e227e`, `dc71974`, `e067c84`

Dashboard, nutrition (screen, add-food, create-food, portion), supplements,
workout (train, program editor, exercise library, picker, **Live Gym Mode**
with rest timer and PR detection), body (chart, editor, photos), plan (tasks,
calendar, Google sync), AI Hub, health sync, onboarding, settings,
`main.dart`, `app.dart`.

**Exit criterion met:** every route in the router resolves to a real screen;
`flutter analyze` clean across the project.

### Sprint 3 — Platform and security (complete)
`0b61685`

- Standalone daily reminders, closing the gap in module 7 — reminders could
  previously exist only attached to a supplement or a task.
- The reminder master switch moved into `NotificationService` so no feature
  can schedule past it.
- Firestore rules rewritten for the MVP schema; storage rules closed.
- Index strategy: no composite indexes, 32 field exemptions.
- Android: three flavours, release signing from an uncommitted properties
  file, core-library desugaring, multidex, R8 with keep rules, a manifest that
  declares only the permissions the shipped code calls.

**Exit criterion met:** an installable artefact configuration exists for each
environment.

### Sprint 4 — Verification (complete)
`741d953`, `377d9f8`, `ce403e5`, `76f6543`, `b5c9d45`, `ee03c6e`

545 automated tests: 506 Flutter (unit, widget, headless end-to-end) and 39
security-rules tests against the real rules engine. Coverage 82.19 %, enforced
by a gate. CI pinned, flavoured build matrix, emulator integration job.

**Exit criterion met:** the coverage gate passes at 80 %; every defect the
suite found is fixed (eleven of them — see §3).

## 2. What each sprint deliberately did not do

| Not done | Why |
|---|---|
| Cloud Functions | every engine runs on the device; a server round-trip would be slower and less available without being more correct |
| Firebase Storage | progress photos stay on the device |
| Native Health Connect reader | the Dart layer, permission state machine and UI are complete; the native handler and the Play health-data declaration are a release-blocking process, not a build task |
| An `analytics` collection | it would duplicate Firebase Analytics and nothing reads it |

## 3. Defects found and fixed during Sprint 4

Every one of these was found by a test that did not exist before that sprint.

| # | Defect | Would have caused |
|---|---|---|
| 1 | Rules required Firestore timestamps; the client sends ISO strings | **every** cloud write rejected in production |
| 2 | Profile writes queued to `users/{uid}/__profile__` | the profile never syncing between devices |
| 3 | `SettingsController` used `ref.read` after awaiting its own write | every settings switch throwing in debug |
| 4 | `LdCard`'s accent variant forced infinite height in a list | any card with an accent bar failing to lay out |
| 5 | Live Gym Mode's ± stepper icons were never drawn | the two most-tapped controls invisible |
| 6 | Notification small icon was the launcher icon | a white square in the status bar |
| 7 | Notification permission assumed denied on launch | a false "permission needed" warning after every restart |
| 8 | Four dropdowns overflowed their rows | visible layout errors on a 400 dp screen |
| 9 | `SwitchListTile` inside `LdCard` painted ink behind the card | a Flutter assertion in debug |
| 10 | `continueWithoutAccount` invented a `local@device` email | a fake address in the profile and on screen |
| 11 | `roundToIncrement` test asserted the wrong plate | a wrong expectation masking future regressions |

## 4. Next sprints

### Sprint 5 — Beta hardening (2 weeks)
1. Run the emulator integration job on real hardware; fix what only a device
   reveals (keystore behaviour, notification channels, back-gesture handling).
2. Build and install a signed release APK on a physical Samsung device and
   walk every flow.
3. Verify R8: the release build is configured with minification and resource
   shrinking, and the keep rules are written, but the shrunk binary has not yet
   been exercised on a device (TD-01).
4. Firestore emulator round-trip: sign in on two devices and confirm
   convergence, tombstones, and that a slow pull never undoes a recent write.
5. Crashlytics smoke test: force a crash in staging, confirm the report
   arrives with symbols.

### Sprint 6 — Health Connect (2 weeks)
1. Add `androidx.health.connect:connect-client`.
2. Implement the `os.lifedna/health` channel: availability, permission
   request, read.
3. Declare the four read permissions and the rationale activity in the
   manifest.
4. Complete the Google Play health-data declaration **before** submitting.
5. The Dart side, the state machine and the UI already exist and are tested;
   this sprint replaces `notEnabledInBuild` with real data.

### Sprint 7 — Closed beta (2 weeks)
Internal testing track, 20–50 users, structured feedback, crash-free-sessions
target ≥ 99.5 %, and the launch checklist in `12-launch-checklist.md`.

## 5. Definition of done

A feature is done when **all** of these hold. This is the standard the eleven
shipped modules were held to.

- [x] Domain entity, JSON round-trip, and its own unit test
- [x] Repository with validation, offline write path, and its own test
- [x] Riverpod providers
- [x] Screen with loading, empty, error, offline and retry states
- [x] Widget test covering the empty state and the primary interaction
- [x] `flutter analyze --fatal-infos` clean
- [x] No TODO in the code — the lint set makes one an error
- [x] Documented in this folder
