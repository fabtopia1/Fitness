# 15 — Production readiness report

**Verdict: ready for a closed beta. Not ready for public production until one
item is closed.**

The blocking item is that no release binary has been built or run — because the
Android SDK cannot be installed in the environment this was developed in
(`dl.google.com` is refused by the network policy). Every other gate is green
and was executed, not asserted.

---

## 1. What was verified, and how

| Gate | Result | How |
|---|---|---|
| Static analysis | **PASS** | `flutter analyze --fatal-infos` — no issues across 97 lib files and 36 test files |
| Formatting | **PASS** | `dart format --set-exit-if-changed` |
| Layer boundaries | **PASS** | `tool/check_sources.py` — the domain imports no Flutter and no Firebase; no colour literal outside `core/theme` |
| Unit tests | **PASS** | 391 |
| Widget tests | **PASS** | 123 |
| End-to-end journeys (headless) | **PASS** | 3 |
| Security rules | **PASS** | 39, against the real rules engine in the Firestore emulator |
| Engine parity | **PASS** | Dart ↔ TypeScript ↔ independently generated fixtures |
| Coverage | **PASS** | 82.24 % of 7 918 measured lines, gated at 80 % |
| No TODOs | **PASS** | `todo: error` — a TODO fails the build |
| No committed secrets | **PASS** | no keys, keystores, `google-services.json` or service accounts |
| **Release build** | **NOT RUN** | no Android SDK in this environment |
| **On-device run** | **NOT RUN** | no device or emulator in this environment |

**517 automated Flutter tests + 39 security-rules tests = 556 checks, all
passing.**

## 2. Requirements against delivery

| Requirement | Status |
|---|---|
| Nine MVP modules, all functional | ✅ |
| No placeholder screens | ✅ every route resolves to a real screen |
| No fake integrations | ✅ health sync reports the truth and renders no invented data |
| No TODOs in the code | ✅ enforced by the linter |
| Every feature has UI + backend + DB + state + errors + loading + offline | ✅ |
| Offline-first | ✅ Hive is the commit; the network is never in the write path |
| Encrypted local storage | ✅ AES, key in the Android Keystore, honest fallback |
| Firestore security rules | ✅ written and **executed** |
| Authentication guards | ✅ one router redirect; no screen bypasses it |
| Input validation | ✅ at the form, at the repository, and in the rules |
| Secure API key management | ✅ `--dart-define` only; no AI key exists at all |
| 80 % coverage | ✅ 82.24 %, gated |
| Unit + widget + integration tests | ✅ |
| dev / staging / prod | ✅ three flavours, three application ids |
| CI/CD with build verification | ✅ six jobs including a flavour matrix |
| Architecture audit | ✅ 26 findings, 18 fixed — `16-architecture-audit.md` |

## 3. The one blocking item

**A-01 — no release binary has been produced or run.**

Unproven: the AGP/Kotlin plugin combination, core library desugaring,
multidex, the three product flavours, and R8. The keep rules for
`flutter_local_notifications`' reflection and for Crashlytics symbols are
written but not exercised, and R8 stripping a reflectively reached class is
the classic release-only failure.

What is proven statically: the Dart compiles, every manifest and resource file
is valid XML, both Firebase JSON files parse, and the Kotlin package matches
the Gradle namespace.

**How it closes:** the first push to GitHub runs the CI build matrix on a
runner with the SDK, which compiles all three flavours. Installing the release
APK on a physical device and walking every flow is a blocking item in
`12-launch-checklist.md`. Estimated effort: one day.

## 4. What would have shipped broken without this phase

Twenty-six findings, eighteen fixed. Five that would each have been a
production incident:

1. **Security rules rejected every client write.** The rules demanded Firestore
   timestamps; the offline path replays ISO strings. It would have surfaced as
   "nothing ever syncs", silently, in the background.
2. **The profile never replicated.** Outbox entries were routed to a phantom
   `users/{uid}/__profile__` sub-collection.
3. **Nothing pulled on sign-in.** A second device showed an empty app.
4. **Pull stopped at 500 documents.** A restore handed the user a truncated
   training log.
5. **Every settings switch threw in debug**, because the controller read a
   provider after awaiting a write that changed it.

None of these is visible by reading the code. All five were found by executing
it.

## 5. Known limits a beta tester will meet

| Limit | Effect |
|---|---|
| Health sync is not enabled | the screen says so and lists the enablement steps; it shows no data |
| Progress photos are device-local | they are not backed up and do not move to a new phone |
| No data export | leaving with your history is a support request |
| No deep links from notifications | tapping a reminder opens the app where it was |
| Account deletion is a support request | erasing local data is self-service |
| Light theme unreviewed by eye | complete and tested, but not walked screen by screen |

Each is in `14-technical-debt.md` with an effort estimate and a trigger.

## 6. Scale

Modelled at 10 000 daily-active users, from the write patterns in the code:

| | Per user/day | At 10 000 users |
|---|---|---|
| Firestore writes | ~45 | 450 000/day |
| Firestore reads | ~30 | 300 000/day |
| Storage | 15–40 MB/user/year | 150–400 GB/year |

Reads are low because the UI never queries Firestore — it reads Hive.
Writes are the dominant cost, and the outbox collapses repeated edits to one
document into a single network write. No composite index is required, and 32
field exemptions remove three index writes per document write on the hottest
collections.

The per-device ceiling is memory, not Firestore: a regular Hive box holds every
record in RAM. Modelled at ~40 MB for five years of heavy logging, with a
documented plan (E-04) to move to `LazyBox` if a user reaches it.

## 7. Recommendation

**Ship to a closed beta now.** The functionality is complete, the data path is
sound, the security rules are executed rather than reviewed, and the failure
modes are honest — offline works, parked writes are surfaced, and nothing
pretends to have data it does not.

**Before public production:**
1. Close A-01 — build and run the release binary on hardware (1 day).
2. Register the upload key's SHA-1/SHA-256 in Firebase, or Google Sign-In fails
   silently (30 minutes; the most common Android launch failure).
3. Run the emulator integration job green on `main`.
4. Have the medical framing reviewed by someone qualified.

**Deliberately not blocking:** Health Connect, data export, deep links,
self-service account deletion. Each is scheduled with a trigger rather than
shipped half-built.
