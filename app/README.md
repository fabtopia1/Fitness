# LifeDNA OS — Flutter application

The shipped MVP. Nine modules, offline-first, 517 tests, 82.24 % coverage.

For the architecture, the schema, the audit and the readiness assessment, see
[`../docs/mvp/`](../docs/mvp/00-index.md).

## Run it

The app runs with **no Firebase project configured**. That is local mode: a
device-local session, every feature working, nothing replicating. It is a
supported path, not a debug hatch, and it is the configuration the whole test
suite runs in.

```bash
flutter pub get
flutter run --flavor dev --dart-define=FLAVOR=dev
```

With a project, pass the configuration at build time — nothing is committed:

```bash
flutter run --flavor dev \
  --dart-define=FLAVOR=dev \
  --dart-define=FIREBASE_API_KEY=... \
  --dart-define=FIREBASE_APP_ID=... \
  --dart-define=FIREBASE_SENDER_ID=... \
  --dart-define=FIREBASE_PROJECT_ID=... \
  --dart-define=GOOGLE_CALENDAR_CLIENT_ID=...
```

## Verify it

```bash
flutter analyze --fatal-infos                  # the lint set makes a TODO an error
dart format --output=none --set-exit-if-changed lib test integration_test
python3 tool/check_sources.py                  # domain purity, colour discipline
flutter test                                   # 517 tests
flutter test --coverage && dart ../tool/coverage_gate.dart
```

On a device:

```bash
flutter test integration_test/app_test.dart -d <device>
```

## The one thing to understand before reading the code

**Hive is the source of truth. Firestore is a replication target.**

Every write takes the same three steps, in this order:

1. write to Hive — synchronous, always succeeds, *is* the commit
2. enqueue in the outbox — a durable intent to replicate
3. attempt Firestore — best effort; failure is not the user's problem

Reads come from Hive only. It is implemented once, in
`lib/core/data/synced_collection.dart`, and every repository composes one. That
is the whole reason the app works in a gym basement.

## Layout

```
lib/
├── main.dart, app.dart
├── core/      config, data, engines, error, firebase, network, notifications,
│              providers, result, router, storage, sync, theme, widgets
├── features/  ai_hub, auth, body, calendar, dashboard, health_sync, nutrition,
│              reminders, settings, supplements, sync, workout
└── shared/    enums, value_objects
```

Each feature is `domain / data / presentation`. The domain layer is pure Dart —
no Flutter, no Firebase — and `tool/check_sources.py` fails the build if that
stops being true.
