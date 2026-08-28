# 11 — Build checklist

## 1. Prerequisites

| Tool | Version | Check |
|---|---|---|
| Flutter | **3.47.2** (pinned) | `flutter --version` |
| Dart | 3.13.2 (bundled) | |
| JDK | 17 | `java -version` |
| Android SDK | platform 34+, build-tools 34+ | `flutter doctor` |
| Node | 20+ | only for the rules tests and `functions/` |

The Flutter version is pinned because the formatter's style is SDK-specific
and CI enforces formatting. A different version will fail the gate on
correctly formatted code.

## 2. First clone

```bash
git clone <repo> && cd Fitness/app
flutter pub get
flutter analyze --fatal-infos      # expect: No issues found!
flutter test                       # expect: 506 tests passed
```

A fresh clone builds and tests with **no** Firebase configuration. That is
local mode, and it is supported.

## 3. Configuration

Nothing secret is committed. Everything arrives at build time.

### Firebase (optional — the app runs without it)

```bash
--dart-define=FIREBASE_API_KEY=...
--dart-define=FIREBASE_APP_ID=...
--dart-define=FIREBASE_SENDER_ID=...
--dart-define=FIREBASE_PROJECT_ID=...
--dart-define=FIREBASE_STORAGE_BUCKET=...      # optional; defaults to <project>.appspot.com
```

There is no `google-services.json` and no generated `firebase_options.dart`.
`Firebase.initializeApp(options:)` is called with values built from these
defines. When they are absent the app reports `notConfigured` and runs locally.

### Google Calendar (optional — the module locks itself when absent)

```bash
--dart-define=GOOGLE_CALENDAR_CLIENT_ID=...
```

Without it, `isGoogleConfigured` is false and the sync action is not offered.

### Flavour

```bash
--dart-define=FLAVOR=dev|staging|prod
```

This selects the app name, Crashlytics and analytics policy, and whether the
emulator suite is used. It is separate from the Gradle `--flavor`, which
selects the application id and resources. **Set both, to the same value.**

### Release signing

Create `app/android/key.properties` — gitignored, never committed:

```properties
storePassword=…
keyPassword=…
keyAlias=upload
storeFile=/absolute/path/to/upload-keystore.jks
```

Without this file the release build falls back to the debug key, so a fresh
clone still builds. It produces an artefact Play will refuse, which is the
correct failure mode: loud, and at the right moment.

## 4. Building

```bash
cd app

# Development — installable alongside the others, debuggable
flutter build apk --flavor dev --debug --dart-define=FLAVOR=dev

# Staging — release build, staging project
flutter build apk --flavor staging --release \
  --dart-define=FLAVOR=staging \
  --dart-define=FIREBASE_API_KEY="$FIREBASE_API_KEY" \
  --dart-define=FIREBASE_APP_ID="$FIREBASE_APP_ID" \
  --dart-define=FIREBASE_SENDER_ID="$FIREBASE_SENDER_ID" \
  --dart-define=FIREBASE_PROJECT_ID="$FIREBASE_PROJECT_ID"

# Production bundle — what Play accepts
flutter build appbundle --flavor prod --release \
  --dart-define=FLAVOR=prod \
  --dart-define=FIREBASE_API_KEY="$FIREBASE_API_KEY" \
  --dart-define=FIREBASE_APP_ID="$FIREBASE_APP_ID" \
  --dart-define=FIREBASE_SENDER_ID="$FIREBASE_SENDER_ID" \
  --dart-define=FIREBASE_PROJECT_ID="$FIREBASE_PROJECT_ID" \
  --dart-define=GOOGLE_CALENDAR_CLIENT_ID="$GOOGLE_CALENDAR_CLIENT_ID"
```

Artefacts:
- `build/app/outputs/flutter-apk/app-<flavor>-<type>.apk`
- `build/app/outputs/bundle/<flavor>Release/app-<flavor>-release.aab`

## 5. Android configuration already in place

| Setting | Value | Why |
|---|---|---|
| `minSdk` | 24 | `firebase_auth` needs 23; 24 is where the notification-channel behaviour this app relies on begins |
| `targetSdk` | Flutter's default (35) | |
| `compileSdk` | Flutter's default | |
| Java / Kotlin target | 17 | |
| Core library desugaring | **on** | required by `flutter_local_notifications` |
| Multidex | on | Firebase + Play services exceed 64k methods at this minSdk |
| R8 minify + resource shrink | on for release | with keep rules for the notification plugin's reflection and for Crashlytics line numbers |
| Flavours | dev / staging / prod | separate application ids, installable side by side |

## 6. Permissions the manifest declares

Only what the shipped code calls:

| Permission | Used by |
|---|---|
| `INTERNET` | Firebase, Google Calendar, assistant shortcuts |
| `ACCESS_NETWORK_STATE` | connectivity |
| `POST_NOTIFICATIONS` | reminders |
| `RECEIVE_BOOT_COMPLETED` | re-arming reminders after a restart |
| `CAMERA` | progress photos |

**No `SCHEDULE_EXACT_ALARM`.** Every reminder uses
`AndroidScheduleMode.inexactAllowWhileIdle`, which survives Doze and does not
require the restricted permission on Android 14+.

**No Health Connect permissions.** They are absent deliberately: declaring
health permissions an app does not use fails Google Play's health-data
declaration. They are added together with the native reader.

## 7. Pre-commit checks

```bash
cd app
flutter analyze --fatal-infos
dart format lib test integration_test
python3 tool/check_sources.py
flutter test --coverage && dart ../tool/coverage_gate.dart
```

## 8. Verifying an artefact by hand

- [ ] Install the release APK on a physical device
- [ ] Cold start under 2 s to first frame
- [ ] Grant notification permission; a supplement reminder arrives
- [ ] Reboot; the reminder is still scheduled
- [ ] Aeroplane mode: log a meal, a set, a measurement — all succeed
- [ ] Reconnect; the banner clears and the outbox drains
- [ ] Force-stop and relaunch; nothing is lost
- [ ] Live Gym Mode: the rest timer fires with the app backgrounded
- [ ] Progress photo capture works and the file stays in app storage
- [ ] Sign out; confirm every local box is empty
- [ ] Check the APK for a `google-services.json` or a keystore (there is none)

## 9. Troubleshooting

| Symptom | Cause | Fix |
|---|---|---|
| `Execution failed for task ':app:checkDebugAarMetadata'` | `minSdk` too low for a plugin | it is set to 24; check for a local override |
| `Cannot fit requested classes in a single dex file` | multidex off | `multiDexEnabled = true` is set |
| `NoSuchMethodError: java.time.*` on old devices | desugaring off | `isCoreLibraryDesugaringEnabled = true` is set |
| App starts in local mode unexpectedly | a `--dart-define` is missing | check all five Firebase defines |
| Notifications never arrive | permission denied | Settings → Reminders → Allow notifications |
| Release crashes where debug does not | an R8 keep rule is missing | check `proguard-rules.pro`; **TD-01** |
| `dart format` fails in CI but not locally | SDK version mismatch | use Flutter 3.47.2 |
