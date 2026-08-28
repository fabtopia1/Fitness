# 02 — Complete folder structure

97 Dart files, 20 648 lines in `app/lib`. 36 test files, 8 693 lines.
Every directory below exists in the repository; there are no empty
placeholder folders.

## Repository root

```
Fitness/
├── app/                     the Flutter application
├── docs/                    full-product design (01–20) + mvp/ (this folder)
├── firebase/                security rules, indexes, and the rules test suite
├── functions/               TypeScript engine mirror — NOT deployed by the MVP
├── test/fixtures/engines/   golden fixtures executed by Dart AND TypeScript
├── tool/
│   ├── coverage_gate.dart   parses lcov, reports, fails below the threshold
│   └── generate_engine_fixtures.py
├── .github/workflows/ci.yml
├── firebase.json            firestore + storage + emulators (no functions)
└── README.md
```

## `app/lib` — core

Everything shared across features. No feature imports another feature's
internals; they meet in `core`.

```
lib/
├── main.dart                entry point, guarded bootstrap, error reporting
├── app.dart                 MaterialApp.router, theme, session-long providers
└── core/
    ├── config/
    │   ├── app_bootstrap.dart      everything that must exist before frame 1
    │   ├── env.dart                --dart-define flavour configuration
    │   └── firebase_config.dart    FirebaseOptions from --dart-define
    ├── data/
    │   ├── synced_collection.dart  THE offline-first write path
    │   └── synced_entity.dart      the contract + JSON helpers
    ├── engines/
    │   ├── macro_calculator.dart   BMR, TDEE, targets, protein floor
    │   ├── recovery_engine.dart    recovery score and training action
    │   ├── e1rm_calculator.dart    estimated 1RM, PR detection, overload
    │   └── load_engine.dart        progression schemes
    ├── error/
    │   ├── failure.dart            sealed hierarchy + isRetryable
    │   └── failure_mapper.dart     exception → failure → user-facing copy
    ├── firebase/
    │   ├── firebase_service.dart   init, or a truthful "not configured"
    │   └── telemetry_service.dart  analytics/crash, consent-gated
    ├── network/connectivity_service.dart
    ├── notifications/notification_service.dart
    ├── providers/providers.dart    the whole provider graph
    ├── result/result.dart          sealed Ok/Err
    ├── router/
    │   ├── app_router.dart         routes + the redirect
    │   └── shell_scaffold.dart     bottom bar, offline banner, resume bar
    ├── storage/hive_store.dart     18 encrypted boxes
    ├── sync/
    │   ├── outbox.dart             durable queue + exponential backoff
    │   └── sync_engine.dart        the drain loop
    ├── theme/
    │   ├── app_theme.dart          Material 3 ThemeData, both brightnesses
    │   ├── ld_colors.dart          the only file allowed colour literals
    │   ├── ld_typography.dart
    │   └── ld_spacing.dart         spacing, radius, motion, touch targets
    └── widgets/                    the design system, 10 components
        ├── ld_widgets.dart         the barrel screens import
        ├── ld_async_view.dart      loading / error / empty / data, once
        ├── ld_card.dart            ld_empty_state.dart   ld_metric_tile.dart
        ├── ld_primary_button.dart  ld_progress_ring.dart ld_section_header.dart
        └── ld_stat_row.dart        ld_switch_row.dart
```

## `app/lib/features` — one directory per module

Every feature follows `domain / data / presentation`. A feature with no data
layer does not have an empty `data/` folder.

```
features/
├── ai_hub/
│   ├── domain/ai_coach.dart               rules, prompts, assistants
│   └── presentation/ai_hub_screen.dart  ai_providers.dart
├── auth/
│   ├── domain/user_profile.dart
│   ├── data/auth_repository.dart  profile_repository.dart
│   └── presentation/  welcome, sign_in, sign_up, onboarding, auth_controller
├── body/
│   ├── domain/body_entities.dart          measurement, metric, trend, EWMA
│   ├── data/body_repository.dart
│   └── presentation/ body_screen, body_editor_sheet, body_providers
├── calendar/
│   ├── domain/calendar_entities.dart      Task, CalendarEvent
│   ├── data/calendar_repository.dart  google_calendar_service.dart
│   └── presentation/ plan_screen, task_editor_sheet, event_editor_sheet,
│                     calendar_providers
├── dashboard/
│   └── presentation/dashboard_screen.dart composes every other module
├── health_sync/
│   ├── domain/health_entities.dart        sample, availability, summary
│   ├── data/health_sync_service.dart      MethodChannel os.lifedna/health
│   └── presentation/health_sync_screen.dart
├── nutrition/
│   ├── domain/nutrition_entities.dart     food, meal, log (food AND water)
│   ├── data/nutrition_repository.dart
│   └── presentation/ nutrition_screen, add_food_screen, create_food_sheet
│                     (+ PortionSheet), nutrition_providers
├── reminders/
│   ├── domain/reminder.dart               daily user-created reminder
│   ├── data/reminder_repository.dart
│   └── presentation/ reminder_editor_sheet, reminder_providers
├── settings/
│   ├── domain/app_settings.dart           theme, reminders, consent
│   ├── data/settings_repository.dart
│   └── presentation/ settings_screen, goals_editor_sheet, settings_providers
├── supplements/
│   ├── domain/supplement_entities.dart    supplement, log, compliance
│   ├── data/supplement_repository.dart
│   └── presentation/ supplements_screen, supplement_editor_sheet, providers
├── sync/
│   └── presentation/sync_providers.dart   RemotePull — the one place that
│                                          knows every collection to download
└── workout/
    ├── domain/workout_entities.dart       exercise, workout, session, set
    ├── data/workout_repository.dart
    └── presentation/ workout_screen, live_workout_screen, workout_editor_screen,
                      exercise_library_screen, exercise_picker,
                      create_exercise_sheet, workout_providers
```

`lib/shared/` holds the two things both `core` and `features` depend on:
`enums/enums.dart` and `value_objects/macros.dart`.

## `app/test`

```
test/
├── support/
│   ├── test_harness.dart     in-memory Hive, fake notifications/connectivity
│   ├── pump.dart             pumpScreen / pumpApp / pumpSheet / tapVisible
│   └── scenarios.dart        end-to-end journeys, run headlessly AND on device
├── unit/
│   ├── core/  engines, storage, sync, data, error, firebase, result
│   ├── features/  one file per repository
│   └── shared/  enums, macros
├── widget/
│   ├── design_system_test.dart
│   ├── core_widgets_test.dart
│   └── features/  auth_flow, screens, editors, live_workout, flows
└── integration/app_scenarios_test.dart   the journeys, headless

integration_test/app_test.dart            the same journeys, on a device
```

## `app/android`

```
android/
├── app/
│   ├── build.gradle.kts       flavours, signing, desugaring, R8
│   ├── proguard-rules.pro     keeps for the notification plugin and Crashlytics
│   └── src/
│       ├── main/
│       │   ├── AndroidManifest.xml    only permissions the code calls
│       │   ├── kotlin/os/lifedna/lifedna/MainActivity.kt
│       │   └── res/  strings, colors, ic_notification (monochrome), launcher
│       ├── dev/res/values/strings.xml      "LifeDNA Dev"
│       └── staging/res/values/strings.xml  "LifeDNA Staging"
└── key.properties             NOT committed; CI writes it from a secret
```

## `firebase`

```
firebase/
├── firestore.rules            deny by default, collection allow-list
├── firestore.indexes.json     no composite indexes, 32 field exemptions
├── storage.rules              denies everything; the MVP uploads nothing
└── rules-test/                39 tests against the real rules engine
    ├── firestore.rules.test.js
    ├── package.json           firebase-tools is a dev dependency, not global
    └── vitest.config.js
```
