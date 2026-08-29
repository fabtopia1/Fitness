# LifeDNA OS — Closed Beta Launch Certification Report

**Scope:** a 50-user closed beta on Android.
**Baseline:** `docs/mvp/17-launch-readiness-audit.md` — 4 critical blockers,
6 high, 8 medium.
**Branch:** `claude/lifedna-os-design-npdd59`

---

## 1. Verdict

**Certified for closed beta, conditional on the CI build job producing a signed
release artifact.**

Three of the four critical blockers are closed in code with regression tests
that make them unable to return silently. The fourth — C-4, *"no release binary
has ever been produced"* — is closed in configuration and **cannot be closed in
this environment**: Google's Maven mirror is unreachable here, so no Gradle
build can run. It is closed by the CI job, and that job must be green before an
APK reaches a tester.

| | Before | After |
| --- | --- | --- |
| Critical blockers | 4 | 0 in code · 1 pending CI execution |
| High priority | 6 | 0 |
| Medium priority | 8 | 3 accepted, documented |
| Tests | 547 | **586** |
| Coverage | 80.1 % | **82.27 %** (gate 80 %) |
| `flutter analyze --fatal-infos` | clean | clean |
| Layer + colour rules | pass | pass (144 files) |

---

## 2. Scores

Each is what the evidence supports, not what a green suite suggests.

| Dimension | Score | Reasoning |
| --- | --- | --- |
| **Release readiness** | **7.5 / 10** | Every build-configuration defect is fixed and the release path is complete on paper: flavors, signing, R8, AAB, mapping upload. It is 7.5 and not 9 for one reason — **no artifact has been produced yet**. That is one green CI run away, and until it happens the claim is unverified. |
| **Security** | **8.5 / 10** | AES-encrypted local storage with a Keystore key; `allowBackup=false` coherent across all API levels; 39 Firestore rules tests against a real emulator; telemetry that *throws* on a parameter that looks like health data; secrets never committed and now gitignored at every path the build looks in. Held below 9 by the documented unencrypted-fallback mode on devices whose keystore fails, and by progress photos being unencrypted on disk. |
| **Reliability** | **8 / 10** | The permanent-lockout path is gone and replaced with a real recovery. Bootstrap failure is a first-class state. Crash reporting now reaches Crashlytics from the zone handler and is attributable to a user. Held below 9 because reliability under a 45-minute real workout on real hardware is untested — Script 5 is what settles it. |
| **Offline sync** | **9 / 10** | Hive is the source of truth, the outbox is durable, and completion is now conditional on entry identity, which was the one path that lost data silently. 12 tests cover the race directly, through `SyncedCollection`, through `SyncEngine`, and across two devices. Not 10: last-write-wins is per document and decided by the device clock, so concurrent edits to different fields of one record still lose the earlier edit (M-6, accepted). |
| **Performance** | **7.5 / 10** | The one measured pathology is fixed: Live Gym no longer rebuilds the screen and rescans the entire workout history every second. The Firestore cache is bounded. It is 7.5 rather than higher because **no profiling has been done on a physical device** — every performance claim here is structural, and Script 5 step 5 is the first real measurement. |
| **Overall** | **8 / 10** | Safe to put in front of 50 testers once CI produces the artifact and Scripts 2, 8 and 11 pass. |

---

## 3. Critical blockers — disposition

### C-1 · A lost encryption key permanently bricked the app — **CLOSED**

**Root cause.** `HiveStore.open()` caught a secure-storage failure, continued
with no cipher, and handed Hive encrypted files. Hive threw, the throw escaped
bootstrap, and the user reached a failure screen whose only button re-ran the
identical path. The only escape was uninstalling, which destroyed the data. The
common trigger is a device transfer: Keystore keys are device-bound and
non-exportable, so restored boxes arrive without their key.

**Fix.** The decision moved into `StorageModeResolver`, a pure function that
enforces one rule: *once boxes exist in a mode, a launch opens them in that
mode or it opens nothing.* An encryption-state marker lives in a box outside
`allBoxes`, so sign-out's `clearAll()` cannot erase it. When the mode cannot be
honoured, `StorageUnavailable` is thrown with a reason, and `main` renders
`StorageRecoveryScreen` — which names what happened, offers a retry (a keystore
can be briefly unavailable during boot), and offers a reset that states exactly
what is lost and takes two taps.

**Cannot regress.** 13 tests cover the decision table exhaustively, including
that an encrypted-but-keyless launch *throws* rather than opening unencrypted,
and that a replacement key is never generated over existing data. 6 widget
tests pin that the destructive action is reachable and never one tap away.

**Files.** `core/storage/storage_mode.dart` (new), `core/storage/hive_store.dart`,
`core/storage/storage_recovery_screen.dart` (new), `main.dart`.

### C-2 · Google Sign-In could not succeed in any build — **CLOSED**

**Root cause,** verified against `GoogleSignInPlugin.java` rather than
documentation: the plugin calls `requestIdToken` only when a server client id
resolves from one of two sources. The app had neither — `GoogleSignIn()` was
constructed with no arguments, and `default_web_client_id` never existed
because `com.google.gms.google-services` was declared in `settings.gradle.kts`
and never applied to the app module. Consent succeeded, `idToken` was null,
Firebase rejected the credential, and the user saw *"Couldn't sign you in.
Please try again."* on every attempt, with nothing separating a build
misconfiguration from a bad network.

**Fix.** `GoogleAuthConfig` resolves the web client id per flavor from
`--dart-define`, with the file-based resource as a fallback rather than the only
path, and detects values that are not client ids. `GoogleIdentitySource` puts
the plugin behind an interface — `GoogleSignInAccount` has a private
constructor, so the null-token case was untestable until it did.
`AuthRepository` checks the token *before* building the credential, fails with
`google_id_token_missing`, and signs the Google session back out, because
otherwise Google keeps the account selected and every retry fails identically
without even showing the picker. The Calendar service was passing `clientId`,
which Android ignores; it now passes `serverClientId`.

**Cannot regress.** 15 tests. Verification procedure, including the three
OAuth Android clients the three `applicationId`s require and Play's re-signing
key, is `18-google-auth-verification.md`.

**Files.** `core/config/google_auth_config.dart` (new),
`features/auth/data/google_identity.dart` (new), `auth_repository.dart`,
`google_calendar_service.dart`, `failure_mapper.dart`, `build.gradle.kts`,
`settings.gradle.kts`.

### C-3 · A slow upload silently discarded the write that followed it — **CLOSED**

**Root cause.** Outbox entries are keyed `collection/docId` so rapid edits to
one document collapse into a single pending write. `complete()` deleted that key
unconditionally and `_pushOne` was handed a *fabricated* entry, so there was
nothing to compare against:

```
write v1 → push starts on a slow link
write v2 → replaces the queued entry
v1's push returns OK → complete() deletes the entry holding v2
```

Firestore kept v1 forever; Hive kept v2; last-write-wins hid the divergence
locally, so it surfaced only on a second device. `recordFailure()` had the same
flaw in reverse — it wrote the stale payload back over the newer one, so a
*failed* push could revert a queued write. The hot path is Live Gym Mode, which
rewrites the session document on every set, usually on gym wifi.

**Fix.** Durable identity. `enqueue` returns the entry it created;
`SyncedCollection` and `ProfileRepository` pass that entry to the push;
`complete` and `recordFailure` read the queued entry and act only when the ids
match. The same guard protects `SyncEngine`'s drain loop against a user write
landing mid-drain.

**Cannot regress.** 12 tests: the race directly, the same path through
`SyncedCollection`, drain-after-stale-completion through `SyncEngine`, and
two-device convergence.

**Files.** `core/sync/outbox.dart`, `core/data/synced_collection.dart`,
`features/auth/data/profile_repository.dart`.

### C-4 · No release binary has ever been produced — **CLOSED IN CONFIGURATION, PENDING CI EXECUTION**

**Environment limitation, stated plainly.** No Android build can run in this
container. Three independent blocks, each verified rather than assumed:

- `/opt/android-sdk/cmdline-tools/` is an empty directory — no platform, no
  build-tools, no NDK.
- `sdkmanager` is absent, and its download host `dl.google.com` is denied by
  the network policy.
- Every Google Maven artifact 301s to that same denied host:
  `maven.google.com/com/android/tools/build/gradle/9.1.0/gradle-9.1.0.pom` →
  `dl.google.com/dl/android/maven2/...` → refused.

`repo.maven.apache.org`, `plugins.gradle.org` and `services.gradle.org` are all
reachable; the block is specific to Google's mirror, which is where AGP,
google-services, Crashlytics, Firebase and Play Services all live.

**What was done instead.** Every build-configuration defect was found and fixed
statically, and CI was changed so it is capable of producing and proving the
artifact — see §4. `19-build-validation-report.md` separates what is settled
statically, what only CI can settle, and what only a device can settle.

**Remaining condition:** the `build` job must go green for `prod`, producing
both an APK and an AAB and uploading the R8 mapping.

---

## 4. High priority — all closed

| | Defect | Fix |
| --- | --- | --- |
| **H-1** | `-Xmx8G` exceeds a standard runner's total RAM; the daemon is OOM-killed and Gradle reports "daemon disappeared unexpectedly" | `-Xmx4G -XX:MaxMetaspaceSize=1G -XX:+HeapDumpOnOutOfMemoryError`; parallel and caching on |
| **H-2** | ProGuard lacked `-keepattributes Signature`. `flutter_local_notifications` stores schedules as Gson JSON and resolves them via `TypeToken`; without the attribute the generic erases and the boot receiver throws. **Every reminder disappeared after a reboot, release builds only** | `Signature`, `*Annotation*`, `InnerClasses`, `EnclosingMethod`, plugin model fields, `renamesourcefileattribute`. Duplicate `com.dexterous.*` receivers removed from our manifest (M-7) |
| **H-3** | Progress photos stored at the `ImagePicker` **cache** path, which Android reclaims and cleaners empty; the absolute device path was replicated to Firestore | `PhotoStore` copies into the documents directory *at capture*, stores a bare file name, resolves legacy paths, and deletes a photo with its measurement or when a draft is abandoned. 15 tests |
| **H-4** | A 1-second `Timer.periodic` rebuilt the whole Live Gym screen; each rebuild ran `lastPerformance` three times, each deserialising every completed session out of Hive | The clock owns its timer and repaints one `Text`; the rest countdown drives a `ValueNotifier`; `lastPerformance` is cached and invalidated by the one event that changes it. 4 tests assert the tick performs **zero** history reads |
| **H-5** | No Crashlytics Gradle plugin, so no mapping upload — every release crash unreadable. Additionally: `setUser` gated the Crashlytics identifier on the *analytics* consent, so declining analytics produced anonymous crashes; and `runZonedGuarded`'s handler, which its own comment called the last resort, only printed | Plugin applied conditionally; mapping uploaded with 90-day retention and `if-no-files-found: error`; the two consents separated; the zone handler reports through telemetry. 5 tests |
| **H-6** | `launch_background.xml` hardcoded white while the app defaults dark — a full-screen white flash on every cold start | Themed `launch_background` colour with a `values-night` variant |

### CI changes (part of H-1/H-5 and C-4)

| Gap | Now |
| --- | --- |
| No AAB was ever built — a different packaging path, different manifest merge, per-ABI splitting that happens nowhere else | Built for staging and prod, uploaded, `if-no-files-found: error` |
| No `google-services.json`, so every artifact carried C-2 | Materialised per flavor from a secret; absence is a loud warning |
| No release keystore, so release artifacts were debug-signed | Materialised from secrets; absence warns that the artifact is not distributable |
| R8 mapping discarded — and it is regenerated every build, so an artifact kept without it can never be symbolicated | Uploaded, 90 days |
| `GOOGLE_SERVER_CLIENT_ID` not passed | Passed to APK and AAB |
| Gradle on JDK 17 while development is on 21 | Both 21; bytecode still pinned to 17 |
| Credentials left on the runner | `if: always()` cleanup |
| `.gitignore` missed the per-flavor `google-services.json` paths — the ones the setup guide instructs | `**/google-services.json` |

Release signing also now **fails the build** on a partial `key.properties`
rather than falling through to the debug key: a debug-signed release artifact
fails at Play upload and at Google Sign-In, and both failures point away from
the cause.

---

## 5. Medium priority

**Closed:** M-2 (Firestore cache bounded to 40 MB — Hive is the read path, so
an unlimited cache was a second copy of data nothing displays), M-4 (dead
multidex removed), M-7 (duplicate receivers removed), M-8 (broken doc
reference and understated `google-services.json` requirement corrected).

**Accepted for the beta, documented:**

| | Why it is acceptable at 50 users |
| --- | --- |
| **M-1** · No adaptive launcher icon | Cosmetic. Android draws the legacy icon in a system circle. Fixing it needs foreground artwork with correct safe-zone padding, not a config change — bodging it would make the icon worse. |
| **M-3** · No `autoDispose` on any provider | A visited stream provider re-reads its box for the life of the app. Real, but blanket-applying `autoDispose` changes rebuild behaviour across every screen, and this remediation is not the place to take that risk untested on hardware. Revisit after Script 5 profiling. |
| **M-5** · Hive `Box` keeps all values resident | ~40 MB modelled at *five years* of heavy logging. No beta tester reaches that in twelve weeks. Switch to `LazyBox` if a tester reports an OOM. |
| **M-6** · Last-write-wins per document, by device clock | Concurrent edits to different fields of one record lose the earlier edit. Acceptable at this scale and now explicitly tested for convergence — what is *not* acceptable, silent divergence, is what C-3 closed. |

---

## 6. Evidence

```
flutter analyze --fatal-infos        clean
dart format --set-exit-if-changed    clean
python3 tool/check_sources.py        144 files, all checks passed
flutter test                         586 passed, 0 failed
dart tool/coverage_gate.dart --min 80  82.27 % of 8115 lines — PASS
```

Tests added by this remediation:

| Suite | Tests | Closes |
| --- | --- | --- |
| `unit/core/storage/storage_mode_test.dart` | 13 | C-1 |
| `widget/storage_recovery_test.dart` | 6 | C-1 |
| `unit/core/sync/outbox_race_test.dart` | 12 | C-3 |
| `unit/core/config/google_auth_config_test.dart` | 7 | C-2 |
| `unit/features/auth/google_sign_in_test.dart` | 8 | C-2 |
| `unit/features/body/photo_store_test.dart` | 15 | H-3 |
| `widget/features/live_workout_performance_test.dart` | 4 | H-4 |
| `unit/core/firebase/telemetry_service_test.dart` (added) | 5 | H-5, M-2 |

---

## 7. Conditions of release

Ordered. Each is a gate, not a suggestion.

1. **CI `build` job green for `prod`** — APK and AAB both produced, R8 clean,
   mapping uploaded. *Closes C-4.*
2. **Secrets configured** — `GOOGLE_SERVICES_JSON_BASE64`,
   `GOOGLE_SERVER_CLIENT_ID`, `ANDROID_KEYSTORE_BASE64` and its alias/passwords.
   Without the first two the artifact still carries C-2; without the third it is
   not distributable.
3. **`18-google-auth-verification.md` §3 complete for `prod`** — release SHA-1
   registered, and Play's app-signing SHA-1 too if distributing through Play.
4. **Device scripts 2, 8 and 11 pass** — the three critical blockers, on real
   hardware. A regression in any one returns the app to unshippable.
5. **Remaining scripts pass** on at least one Samsung device on Android 14+;
   Scripts 1, 2, 7, 8 and 12 on a second device.
6. **Firestore rules deployed** to the beta project — the emulator suite passing
   locally is not deployment.
7. **Crashlytics receiving** — force one crash from the release build and
   confirm it arrives *symbolicated*. An unreadable first crash report means the
   mapping did not upload, and every report for the whole beta will be
   unreadable.

## 8. What to watch in week one

| Signal | Threshold | What it means |
| --- | --- | --- |
| `google_id_token_missing` in Crashlytics | any | The shipped artifact lacks its client id — rebuild, do not debug the device |
| Storage recovery screen reached | any | C-1's residual path; capture the reason code |
| Outbox parked entries per user | > 0 sustained | Writes are failing 10 times and giving up |
| Device set count vs Firestore | any mismatch | C-3 regression — highest severity |
| Crash-free users | < 99 % | Stop the intake |
| Reminders reported missing after reboot | any | H-2 regression, i.e. an R8 rule was lost |

---

## 9. Statement

Three critical blockers are closed in code, each with tests written against the
specific failure rather than the happy path. Six high-priority defects are
closed. Four medium defects are closed and four are accepted with stated
reasoning. 586 tests pass at 82.27 % coverage.

The one thing this report cannot certify is that a release binary builds,
because this environment cannot run an Android build at all — a limitation of
the container, not of the code, and documented with the evidence in
`19-build-validation-report.md`. Everything needed for CI to settle it is in
place.

**Recommendation: proceed to the CI build, then to device validation. Open the
beta when §7 is complete.**
