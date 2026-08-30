# Release Verification Matrix

Every claim the release rests on, what evidence would settle it, where that
evidence comes from, and whether it exists **today**.

Legend: **✅ verified** · **⏳ pending** (mechanism exists, not yet run) ·
**❌ blocked** (cannot be settled as things stand)

---

## A. Source and logic

| # | Claim | Evidence | Status |
| --- | --- | --- | --- |
| A1 | Compiles with no analyzer findings | `flutter analyze --fatal-infos` | ✅ clean |
| A2 | Formatted | `dart format --set-exit-if-changed` | ✅ 145 files |
| A3 | Layer + colour rules hold | `tool/check_sources.py` | ✅ 146 files |
| A4 | Test suite green | `flutter test` | ✅ **602 passing** |
| A5 | Coverage ≥ 80 % | `tool/coverage_gate.dart` | ✅ 82 % |
| A6 | Dart and TS engines agree | `engine-parity` CI job | ✅ |
| A7 | Firestore rules enforce isolation | 39 vitest tests, real emulator | ✅ |

## B. Storage and data safety (C-1)

| # | Claim | Evidence | Status |
| --- | --- | --- | --- |
| B1 | A mode mismatch cannot destroy data | `crashRecovery: false`; measured 49→49 bytes, throws | ✅ |
| B2 | Legacy plaintext boxes are adopted, not zeroed | `hive_store_open_test.dart` migration group | ✅ |
| B3 | A recorded mode is never second-guessed | same suite | ✅ |
| B4 | A failed open leaves no box cached | same suite | ✅ |
| B5 | A damaged marker box does not brick startup | rebuilt in `open()` | ✅ |
| B6 | Reset is recoverable (quarantine) | same suite | ✅ |
| B7 | No bootstrap failure is a dead end | both failure screens offer reset | ✅ |
| B8 | Migration preserves data **on a real device** | Install-over-the-top test, `22` §7 | ⏳ needs a device |

## C. Sync (C-3)

| # | Claim | Evidence | Status |
| --- | --- | --- | --- |
| C1 | A superseded write is never dropped | `outbox_race_test.dart`, 12 tests | ✅ |
| C2 | A failed push cannot revert a newer payload | same | ✅ |
| C3 | Two devices converge | same, multi-device group | ✅ |
| C4 | Zero divergence **on hardware** | Device Scripts 8 and 12 | ⏳ |

## D. Authentication (C-2)

| # | Claim | Evidence | Status |
| --- | --- | --- | --- |
| D1 | A null ID token fails loudly, not generically | `google_sign_in_test.dart` | ✅ |
| D2 | The client id is plumbed per flavour | `google_auth_config_test.dart` | ✅ |
| D3 | Email/password works | repository tests | ✅ |
| D4 | Google sign-in **succeeds** end to end | Device Script 2 + a registered SHA-1 | ❌ no credentials |
| D5 | Calendar OAuth works | Device Script 4.3 | ❌ no credentials |

## E. Android build (C-4)

| # | Claim | Evidence | Status |
| --- | --- | --- | --- |
| E1 | Toolchain versions are mutually compatible | Checked against Flutter's `DependencyVersionChecker` | ✅ |
| E2 | Gradle config is correct | `19-build-validation-report.md` | ✅ static |
| E3 | Partial signing config fails the build | `build.gradle.kts` guard | ✅ |
| E4 | Preflight catches misconfiguration | `tool/verify_release.sh` | ✅ runs, reports 9 blockers |
| E5 | **Release APK builds** | `flutter build apk --release --flavor prod` | ❌ no Android SDK here |
| E6 | **Release AAB builds** | `flutter build appbundle` | ❌ same |
| E7 | R8 completes, mapping produced | CI `build` job | ❌ same |
| E8 | Artefact installs on a device | `adb install -r` | ❌ no artefact |

E5–E8 are blocked by the environment, not the code: `dl.google.com` is denied
by network policy and `/opt/android-sdk` is an empty stub, so no Gradle build
can run here. Evidence in `19-build-validation-report.md` §0.

## F. Firebase

| # | Claim | Evidence | Status |
| --- | --- | --- | --- |
| F1 | Rules deny cross-user reads | emulator suite | ✅ |
| F2 | Rules **deployed to the beta project** | `firebase deploy --only firestore:rules` | ❌ no project |
| F3 | Indexes deployed | `--only firestore:indexes` | ❌ |
| F4 | Crashlytics receives a symbolicated crash | Forced crash from a release build | ❌ |
| F5 | Cache is bounded | `firestoreCacheBytes` test | ✅ |

## G. Device behaviour

| # | Claim | Script | Status |
| --- | --- | --- | --- |
| G1 | Onboarding completes, no dark-mode white flash | 1 | ⏳ |
| G2 | Reminders survive a reboot (H-2) | 4 step 7 | ⏳ |
| G3 | Live Gym stays smooth over a full session (H-4) | 5 | ⏳ |
| G4 | Photos survive a cache clear (H-3) | 6 | ⏳ |
| G5 | Offline writes reconcile | 7 | ⏳ |
| G6 | Sign-out leaves nothing, photos included | 10 | ⏳ |
| G7 | The recovery screen is reachable and works | 11b | ⏳ |

---

## Summary

| Band | ✅ | ⏳ | ❌ |
| --- | --- | --- | --- |
| Source and logic | 7 | 0 | 0 |
| Storage (C-1) | 7 | 1 | 0 |
| Sync (C-3) | 3 | 1 | 0 |
| Auth (C-2) | 3 | 0 | 2 |
| Android build (C-4) | 4 | 0 | 4 |
| Firebase | 2 | 0 | 3 |
| Device | 0 | 7 | 0 |
| **Total** | **26** | **9** | **9** |

The nine ❌ split into two causes and neither is a code defect:

- **Six** need a Firebase project and an OAuth client that do not exist yet
  (D4, D5, F2, F3, F4, and E-adjacent credential checks). Someone with console
  access closes these; see `27-firebase-production-deployment.md`.
- **Four** (E5–E8) need an Android SDK, which this environment cannot provide.
  CI closes these.

The nine ⏳ all need a physical device and a built artefact — that is, they are
downstream of the ❌ above, in that order.
