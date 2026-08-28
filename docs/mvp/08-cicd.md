# 08 — CI/CD configuration

Source: `.github/workflows/ci.yml`. Six jobs, all of which must be green for a
release.

## 1. Why the Flutter version is pinned

```yaml
FLUTTER_VERSION: '3.47.2'
```

The Dart formatter's output changes between SDK releases. An unpinned runner
would fail the format gate on code that is correctly formatted locally, and
the usual response to that is to delete the gate. Pinning is what keeps the
gate credible. The same version is what the 545 tests were verified against.

## 2. Job: `flutter` — the gate that decides whether the app ships

| Step | Command | Fails when |
|---|---|---|
| Install | `flutter pub get` | a dependency cannot resolve |
| Analyze | `flutter analyze --fatal-infos` | any lint fires — including `todo: error`, so a `TODO` fails the build |
| Format | `dart format --set-exit-if-changed lib test integration_test` | anything is unformatted |
| Layers | `python3 tool/check_sources.py` | a domain file imports Flutter or Firebase, or a colour literal appears outside `core/theme` |
| Test | `flutter test --coverage` | any of 506 tests fails |
| Coverage | `dart ../tool/coverage_gate.dart --min 80` | coverage drops below 80 % |

`--fatal-infos` is deliberate. A warning that is allowed to accumulate is a
rule nobody follows.

The coverage artefact is uploaded on every run, including failures, so a drop
can be diffed rather than argued about.

## 3. Job: `build` — three flavours, in parallel

A green test suite says nothing about whether the Android toolchain can
produce an installable artefact. This job proves it for `dev` (debug),
`staging` and `prod` (release).

Firebase configuration is passed as `--dart-define` from repository secrets:

```
FIREBASE_API_KEY  FIREBASE_APP_ID  FIREBASE_SENDER_ID
FIREBASE_PROJECT_ID  FIREBASE_STORAGE_BUCKET  GOOGLE_CALENDAR_CLIENT_ID
```

A pull request from a fork has no secrets, so it builds the **local-mode**
binary — which is a supported configuration, not a stub, and therefore still a
meaningful build. Nothing is committed and nothing is decrypted onto disk.

Each flavour is a separate application id (`.dev`, `.staging`, and the base id
for prod), so all three can be installed side by side and a staging build can
never reach production data.

## 4. Job: `integration` — the journeys on a real emulator

Runs the same scenarios as the headless suite, on an Android 34 emulator with
`reactivecircus/android-emulator-runner`. It is slower and inherently flakier,
so it does not gate every pull request: it runs on pushes to `main`/`develop`
and on any PR labelled `run-integration`. It **must** be green before a
release.

The scenarios themselves live in `test/support/scenarios.dart` and are shared
by both entry points, so the emulator run and the headless run cannot drift
apart.

## 5. Job: `rules` — security rules, executed

```bash
cd firebase/rules-test && npm ci && npm run emulator
```

39 tests against the real Firestore rules engine. `firebase-tools` is a dev
dependency of that package rather than a global install, so CI runs the same
emulator version a developer does.

This job is the reason the rules can be trusted. It already caught a defect
that would have rejected every client write in production.

## 6. Job: `engine-parity` — Dart ↔ TypeScript ↔ specification

1. Regenerate the fixtures with `tool/generate_engine_fixtures.py` and fail if
   the committed fixtures differ. A formula that changed without regenerating
   them, or a generator that disagrees with the specification, stops here.
2. Run the Dart parity test against the fixtures.
3. Run the TypeScript parity test against the same fixtures.
4. Reject `Math.round` inside `functions/src/engines` — it disagrees with
   Dart's `num.round()` on negative halves, and `projectedWeeklyChangeKg` is
   negative for every user in a deficit.

Agreement between three independent implementations is much stronger evidence
than agreement between two.

## 7. Job: `security`

- No `google-services.json`, `GoogleService-Info.plist`, `firebase_options.dart`,
  `serviceAccountKey.json` or `key.properties` in the tree.
- No string matching a live Google API key or an Anthropic key.
- No `.jks`, `.keystore`, `.p12` or `.pem`. An app that ships its signing key
  is an app anyone can publish an update to.

## 8. Environments

| | dev | staging | prod |
|---|---|---|---|
| Application id | `os.lifedna.lifedna.dev` | `…lifedna.staging` | `os.lifedna.lifedna` |
| Build type | debug | release | release |
| Firebase project | `lifedna-dev` | `lifedna-staging` | `lifedna-prod` |
| Emulators | `--dart-define=USE_EMULATOR=true` | no | no |
| Crashlytics | off | on | on |
| Analytics | off | on | on, and consent-gated |
| Signing | debug key | release key | release key |

There is no runtime switch between environments. Each is a separate binary
with a separate configuration, so a staging build cannot be pointed at
production by a flag someone forgot to flip.

## 9. Release process

```bash
# 1. Everything green on main.
# 2. Bump the version in app/pubspec.yaml (version: 1.0.0+1).
# 3. Build the bundle Play wants:
cd app
flutter build appbundle --flavor prod --release \
  --dart-define=FLAVOR=prod \
  --dart-define=FIREBASE_API_KEY="$FIREBASE_API_KEY" \
  --dart-define=FIREBASE_APP_ID="$FIREBASE_APP_ID" \
  --dart-define=FIREBASE_SENDER_ID="$FIREBASE_SENDER_ID" \
  --dart-define=FIREBASE_PROJECT_ID="$FIREBASE_PROJECT_ID" \
  --dart-define=FIREBASE_STORAGE_BUCKET="$FIREBASE_STORAGE_BUCKET" \
  --dart-define=GOOGLE_CALENDAR_CLIENT_ID="$GOOGLE_CALENDAR_CLIENT_ID"

# 4. Deploy the rules and the index configuration:
firebase deploy --only firestore:rules,firestore:indexes --project lifedna-prod

# 5. Upload to the internal testing track, then promote.
```

Signing comes from `android/key.properties`, which CI writes from a secret and
which is never committed. Without it the build falls back to the debug key, so
a fresh clone still builds — it simply produces an artefact Play will refuse,
which is the correct failure mode.

## 10. What CI does not do yet

- **Deploy.** Publishing to Play is manual for the beta. Automating it before
  a human has installed the artefact once would be automating something nobody
  has verified.
- **Screenshot testing.** Golden files are brittle across renderer versions;
  the widget suite asserts on behaviour and layout constraints instead.
- **Performance budgets.** No frame-timing gate. Added when there is a device
  lab to measure on.
