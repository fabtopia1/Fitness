# 16 — Architecture audit

A full pass over the shipped code looking for anything that could stop the app
**building**, **deploying**, **syncing**, **handling users**, or **scaling to
10 000 users**.

Twenty findings. **Fourteen were fixed during the audit**; the six that remain
are open with an owner and a trigger. Every fix is a commit on this branch.

---

## A. Build

### A-01 · The release binary has never been built — **OPEN**
**Severity: high**

`flutter build apk` has never run against this tree. The Android SDK cannot be
installed in this environment: `dl.google.com` is refused by the network
policy. Everything else — analyze, format, 517 tests, 39 rules tests — runs
here and is green, but the Gradle half of the build is unproven.

Specifically unproven: the AGP 9.1.0 / Kotlin 2.4.0 plugin combination, core
library desugaring, multidex, the three product flavours, and **R8**. R8
removing a class that `flutter_local_notifications` reaches by reflection is
the classic release-only failure; keep rules are written for it and for
Crashlytics line numbers, but they have not been exercised.

What *is* verified statically: every `AndroidManifest.xml` and resource file
parses as valid XML, `firebase.json` and `firestore.indexes.json` parse as
valid JSON, the Kotlin package matches the Gradle namespace, and the Dart side
compiles.

**Closes when:** the CI build matrix compiles all three flavours on a runner
with the SDK (first push), and a release APK is installed on a device
(Sprint 5). Both are blocking launch items. See TD-01.

### A-02 · Formatter drift would have broken CI — **FIXED**
The workflow pinned Flutter 3.24.0 while the code was written against 3.47.2.
The Dart formatter's style changed between those releases, so the format gate
would have failed on correctly formatted code — and the usual response to that
is to delete the gate. CI is now pinned to the version the suite was verified
against, and the whole tree is formatted for it.

### A-03 · Template TODOs in the Gradle build — **FIXED**
`app/build.gradle.kts` shipped with the Flutter template's `TODO: Specify your
own unique Application ID` and `TODO: Add your own signing config`. Replaced
with three real flavours and a signing config read from an uncommitted
`key.properties`, falling back to the debug key so a fresh clone still builds.

### A-04 · The notification icon was the launcher icon — **FIXED**
`AndroidInitializationSettings('@mipmap/ic_launcher')`. Android masks the
status-bar icon to its alpha channel, so a full-colour launcher icon renders
as a white square. Replaced with a monochrome vector drawable.

---

## B. Deploy

### B-01 · Security rules would have rejected every write — **FIXED**
**Severity: critical**

The rules from the design phase required `request.resource.data[field] is
timestamp`. The offline write path serialises entities to JSON for Hive and
replays the identical map to Firestore, where dates are ISO-8601 **strings**.

Every cloud write would have been rejected with `PERMISSION_DENIED` — in
production, on the first device that came back online. Because writes are
queued and retried in the background, it would have surfaced as "nothing ever
syncs" rather than as an error anyone could act on.

Rewritten for the MVP schema and now covered by 39 tests executed against the
real rules engine in the emulator.

### B-02 · A rules deploy could be blocked by an unbuilt functions codebase — **FIXED**
`firebase.json` declared a `functions` codebase with an `npm run build`
predeploy hook. The MVP deploys no functions, so a rules deploy on a machine
without `functions/node_modules` would fail on a step that produces nothing.
The entry is removed; `functions/README.md` records when it comes back.

### B-03 · Storage rules were permissive for a bucket nothing uses — **FIXED**
The MVP uploads nothing. `storage.rules` now denies everything, so the bucket
is closed by default if it is ever provisioned.

### B-04 · No `.firebaserc` — **OPEN, low**
Deploys require an explicit `--project`. That is arguably safer than a default
alias that points at production, and the release process documents the flag.
Accepted.

---

## C. Sync and data integrity

### C-01 · Profile writes were routed into a phantom sub-collection — **FIXED**
**Severity: high**

`ProfileRepository` queued outbox entries under the sentinel collection
`__profile__`, and `SyncEngine` blindly appended the collection name to
`users/{uid}`. The profile would have replicated to
`users/{uid}/__profile__/{uid}` — a document nothing reads — so a user's name,
goal and targets would never have reached a second device. Rules would also
have rejected it, since `__profile__` is not in the allow-list.

The sentinel is now a named constant and the engine routes it to the user
document. Covered by a test that asserts the stray sub-collection is empty.

### C-02 · Nothing pulled on sign-in — **FIXED**
**Severity: high**

A user signing in on a second device saw an empty app until they happened to
pull-to-refresh the dashboard. Sign-in now triggers a full pull.

### C-03 · Two collections replicated up but never down — **FIXED**
`ReminderRepository.pullAll` and `SettingsRepository.pullAll` existed and were
never called. Reminders and preferences would have been uploaded and never
restored — which to a user is data that vanished when they changed phones.

Both are now in `RemotePull`, a composition root for replication, and a test
asserts the shipped file mentions every repository, so adding one without a
line there fails the build.

### C-04 · Pull stopped after 500 documents — **FIXED**
**Severity: medium**

`SyncedCollection.pull()` took the 500 most recently updated documents and
stopped. A user restoring years of history onto a new phone would have
received a silently truncated training log. It now pages forward on an
ascending `updatedAt` cursor, bounded at 40 pages.

### C-05 · Reminders were not re-armed after a force-stop — **FIXED**
Android clears scheduled alarms when an app is force-stopped, and nothing
listened for app resume. The reschedule methods existed and were called only
from the settings switch. `LifeDnaApp` is now a lifecycle observer: on resume
it drains the outbox, pulls, and re-arms every reminder.

### C-06 · Last-write-wins is per document, not per field — **OPEN, accepted**
Two devices editing different fields of the same record concurrently: the
later write wins entirely and the earlier field edit is lost. The records this
could affect are single-user and rarely edited from two devices at once
(profile, a program, a task). Field-level merge would need a CRDT or per-field
timestamps, which is not proportionate to the risk. Documented, not fixed.

### C-07 · A clock skewed backwards can lose a write — **OPEN, accepted**
Conflict resolution uses the device clock. A device whose clock is materially
behind can write a record that a correct device then treats as older. Firestore
server timestamps would fix it but would break the offline invariant that the
local write *is* the commit. Accepted; the failure mode is rare and bounded.

---

## D. Users, sessions and permissions

### D-01 · Notification permission was requested before the first frame — **FIXED**
**Severity: medium**

`AppBootstrap` called `FirebaseMessaging.requestPermission()`, which raises the
Android 13+ system dialog. Asking a user who has not yet seen a single frame is
how an app gets its notifications declined permanently — and it contradicted
the app's own design, which asks where a reminder would first help. Removed
from bootstrap.

### D-02 · Permission state was assumed denied on every launch — **FIXED**
`NotificationService.hasPermission` was false until something called
`requestPermission()`, so after every restart Settings showed "Android has not
granted notification permission" to users who had granted it. It now reads the
real state at initialisation.

### D-03 · The reminder master switch could be bypassed — **FIXED**
The switch lived in the settings controller, so a reminder created by any other
feature while it was off would still schedule. The gate now lives inside
`NotificationService`, is applied to every scheduling call, and is restored on
cold start — otherwise a user who turned reminders off would be notified again
after the next launch.

### D-04 · Local mode invented an email address — **FIXED**
`continueWithoutAccount` used `local@device`, which then appeared in the
profile, on the settings screen, and in whatever the user later synced to a
real account. It is empty now, and the UI says "On this device only".

### D-05 · A settings write threw on the write it had just made — **FIXED**
`SettingsController.build()` watched the settings provider and `_update` called
`ref.read` after awaiting its own save. Saving changed the watched dependency,
so the next line threw *"cannot use ref functions after the dependency of a
provider changed"* — every switch on the settings screen, in debug. Dependencies
are captured in `build()` and the controller no longer follows what it writes.

### D-06 · Account deletion is not self-service — **OPEN, low**
Settings erases local data; deleting the account and its Firestore documents is
a support request. `AuthRepository.deleteAccount` exists but is not wired to a
screen. Acceptable for a closed beta; a store requirement before public launch.

---

## E. Scale to 10 000 users

### E-01 · Per-user read cost was linear in history — **FIXED**
**Severity: medium**

Every read of a Hive box parsed every record's JSON, and every emission of a
stream watching that box re-parsed all of them. Measured here: **130 ms for
20 000 nutrition logs**, which is several hundred milliseconds of jank per
rebuild on a phone, for a user with two or three years of history.

The store now caches decoded records validated against the exact string they
came from, so a hit is a string comparison rather than a parse. Repeat read of
20 000 records: **130 ms → 24 ms**.

### E-02 · Index write amplification — **FIXED**
Firestore indexes every field of every document by default. 32 field
exemptions now cover free text and nested arrays that no query touches,
removing three index writes per document write on the hottest collections. At
10 000 users that is the difference between a few gigabytes of index and a few
hundred megabytes.

### E-03 · No composite index is required — **verified, no action**
Every query is `orderBy('updatedAt')` optionally narrowed by
`where('updatedAt', >)` on the same field, which the automatic single-field
index serves. There is no query that will fail in production with a console
link nobody clicks. This is a consequence of the architecture: the UI never
queries Firestore, so the only question Firestore is ever asked is "what
changed since I last looked?".

### E-04 · Hive keeps every record in memory — **OPEN, monitor**
A regular Hive `Box` holds all values in RAM, and the decode cache roughly
doubles that for boxes actually read. Modelled: ~8 MB of raw strings at 20 000
nutrition logs, ~40 MB at 100 000 records (roughly five years of heavy
logging).

**Trigger:** an OOM report, or a user passing 100 000 records in one box.
**Fix when triggered:** move the highest-volume boxes to `LazyBox` and key
nutrition logs by `localDate|id` so a day can be found from `box.keys` without
decoding any value.

### E-05 · Write cost is dominated by the live workout screen — **mitigated**
25 set writes in an hour, plus a session document write per set. The outbox
keys pending entries by `collection/docId`, so rapid edits to the same session
collapse into one network write. Modelled steady state: ~45 writes and ~30
reads per active user per day; 450 000 writes/day at 10 000 users. Budget
alerts are a launch item.

---

## F. Correctness defects found by the test suite

Not architectural, but each would have shipped:

| Defect | Symptom |
|---|---|
| `LdCard`'s accent variant put a stretch `Row` in an unbounded parent | any card with an accent bar failed to lay out |
| Live Gym Mode's ± stepper icons were never drawn | the two most-tapped controls in the app were invisible |
| `SwitchListTile` inside `LdCard` painted its ink behind the card | a Flutter assertion in debug |
| Four `DropdownButtonFormField`s sized to their widest item | visible overflow on a 400 dp screen |
| Two rows overflowed (welcome screen, settings targets, completed set) | visible overflow stripes |
| `roundToIncrement` was asserted to round 103.7 up to 105 | a wrong expectation masking future regressions |

---

## G. Summary

| Area | Findings | Fixed | Open |
|---|---|---|---|
| Build | 4 | 3 | 1 (A-01) |
| Deploy | 4 | 3 | 1 (B-04) |
| Sync | 7 | 5 | 2 (C-06, C-07) |
| Users | 6 | 5 | 1 (D-06) |
| Scale | 5 | 2 | 1 (E-04) + 2 verified |
| **Total** | **26** | **18** | **6 open, 2 no-action** |

The single item that blocks production is **A-01**: nothing has produced or
run a release binary. Everything else open is accepted with a documented
trigger.
