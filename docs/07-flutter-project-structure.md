# LifeDNA OS — Flutter Project Structure

**Version:** 1.0
**Flutter:** 3.24+ · **Dart:** 3.5+
**Owner:** Mobile Lead

---

## 1. The rule that governs everything

```
presentation ──depends on──► domain ◄──implements── data
```

- `domain/` is **pure Dart**. No `package:flutter`, no `firebase_*`, no `dart:io`, no HTTP.
- `presentation/` may import `domain/` only. It never sees a DTO or a Firestore type.
- `data/` implements domain interfaces and is the only layer that knows about Firestore,
  Drift, platform channels or JSON.

Enforced in CI by `tool/import_lint.dart`, which fails the build on any violation.

---

## 2. Full tree

```
app/
├── android/                      # Gradle, manifest, Kotlin platform code
│   └── app/src/main/kotlin/os/lifedna/app/
│       ├── MainActivity.kt
│       ├── health/HealthConnectPlugin.kt      # Health Connect bridge
│       ├── ble/GalaxyFitPlugin.kt             # BLE GATT bridge
│       └── service/LiveSessionService.kt      # foreground service
├── ios/                          # Phase 2 parity
├── assets/
│   ├── data/exercises.json           # 400+ seeded exercises
│   ├── data/foods_top5000.json       # local food index
│   ├── data/programs.json            # seeded training programs
│   ├── fonts/  Inter/  JetBrainsMono/
│   └── images/
├── l10n/  app_en.arb  app_ar.arb
├── analysis_options.yaml
├── pubspec.yaml
├── tool/
│   ├── import_lint.dart              # layer boundary enforcement
│   └── generate_tokens.dart          # design/tokens.json → Dart
│
├── lib/
│   ├── main.dart                     # bootstrap + flavor selection
│   ├── app.dart                      # MaterialApp.router, theme, l10n
│   ├── bootstrap.dart                # Firebase init, error zone, DI overrides
│   │
│   ├── core/
│   │   ├── config/
│   │   │   ├── flavor.dart           # dev | staging | prod
│   │   │   ├── app_config.dart
│   │   │   └── feature_flags.dart    # Remote Config typed accessors
│   │   ├── theme/
│   │   │   ├── ld_colors.dart        # ThemeExtension
│   │   │   ├── ld_typography.dart
│   │   │   ├── ld_spacing.dart
│   │   │   ├── ld_radius.dart
│   │   │   ├── ld_motion.dart
│   │   │   ├── tokens.g.dart         # GENERATED from design/tokens.json
│   │   │   ├── app_theme.dart        # dark + light ThemeData
│   │   │   └── theme_extensions.dart # context.ldColors, context.ldType
│   │   ├── router/
│   │   │   ├── app_router.dart
│   │   │   ├── routes.dart           # route name constants
│   │   │   ├── guards.dart           # auth, onboarding, active session
│   │   │   └── shell_scaffold.dart   # bottom nav + resume banner
│   │   ├── database/
│   │   │   ├── app_database.dart     # Drift
│   │   │   ├── tables.dart
│   │   │   ├── daos/
│   │   │   └── migrations.dart
│   │   ├── sync/
│   │   │   ├── outbox.dart
│   │   │   ├── sync_scheduler.dart
│   │   │   ├── conflict_resolver.dart
│   │   │   └── sync_state.dart
│   │   ├── engines/                  # PURE domain algorithms shared by features
│   │   │   ├── macro_calculator.dart
│   │   │   ├── e1rm_calculator.dart
│   │   │   ├── recovery_engine.dart  # client mirror for instant preview
│   │   │   ├── load_engine.dart
│   │   │   ├── priority_engine.dart  # produces the Next Action
│   │   │   └── volume_landmarks.dart
│   │   ├── errors/
│   │   │   ├── failure.dart          # sealed Failure hierarchy
│   │   │   ├── exceptions.dart
│   │   │   └── failure_mapper.dart   # Failure → user-facing copy
│   │   ├── result/result.dart        # Result<T, Failure>
│   │   ├── network/
│   │   │   ├── functions_client.dart # callable wrapper w/ retry + auth
│   │   │   ├── connectivity.dart
│   │   │   └── interceptors.dart
│   │   ├── notifications/
│   │   │   ├── local_notification_service.dart
│   │   │   ├── push_service.dart
│   │   │   ├── notification_scheduler.dart
│   │   │   └── notification_channels.dart
│   │   ├── analytics/
│   │   │   ├── analytics_service.dart
│   │   │   └── events.dart           # typed event taxonomy
│   │   ├── platform/
│   │   │   ├── health_connect_channel.dart
│   │   │   ├── ble_client.dart
│   │   │   ├── wakelock.dart
│   │   │   └── haptics.dart
│   │   ├── utils/
│   │   │   ├── date_x.dart           # localDate bucketing, tz handling
│   │   │   ├── number_format.dart    # the formatting contract from docs/04
│   │   │   ├── unit_converter.dart
│   │   │   ├── uuid.dart             # UUID v7
│   │   │   ├── debouncer.dart
│   │   │   └── logger.dart           # redacting logger
│   │   ├── widgets/                  # the design system, in code
│   │   │   ├── ld_card.dart
│   │   │   ├── ld_metric_tile.dart
│   │   │   ├── ld_progress_ring.dart
│   │   │   ├── ld_macro_ring_cluster.dart
│   │   │   ├── ld_next_action_card.dart
│   │   │   ├── ld_primary_button.dart
│   │   │   ├── ld_segmented_control.dart
│   │   │   ├── ld_chip.dart
│   │   │   ├── ld_sheet.dart
│   │   │   ├── ld_empty_state.dart
│   │   │   ├── ld_skeleton.dart
│   │   │   ├── ld_sparkline.dart
│   │   │   ├── ld_bar_chart.dart
│   │   │   ├── ld_line_chart.dart
│   │   │   ├── ld_calendar_strip.dart
│   │   │   ├── ld_list_row.dart
│   │   │   ├── ld_banner.dart
│   │   │   ├── ld_sync_badge.dart
│   │   │   └── ld_provenance_sheet.dart
│   │   └── providers/
│   │       ├── firebase_providers.dart
│   │       ├── database_providers.dart
│   │       └── app_providers.dart    # today, connectivity, settings
│   │
│   ├── features/
│   │   ├── auth/
│   │   │   ├── domain/
│   │   │   │   ├── entities/app_user.dart
│   │   │   │   ├── repositories/auth_repository.dart
│   │   │   │   └── usecases/{sign_in,sign_up,sign_out,reset_password}.dart
│   │   │   ├── data/
│   │   │   │   ├── models/app_user_dto.dart
│   │   │   │   ├── datasources/auth_remote_ds.dart
│   │   │   │   └── repositories/auth_repository_impl.dart
│   │   │   └── presentation/
│   │   │       ├── controllers/auth_controller.dart
│   │   │       ├── screens/{welcome,sign_in,sign_up,forgot_password}_screen.dart
│   │   │       └── widgets/
│   │   ├── onboarding/            # same 3-layer shape
│   │   ├── dashboard/
│   │   │   ├── domain/entities/{dashboard_snapshot,next_action}.dart
│   │   │   ├── data/repositories/dashboard_repository_impl.dart
│   │   │   └── presentation/
│   │   │       ├── controllers/dashboard_controller.dart
│   │   │       ├── screens/dashboard_screen.dart
│   │   │       └── widgets/{next_action_card,macro_summary_card,
│   │   │                    recovery_card,sleep_card,training_card,
│   │   │                    schedule_card,tasks_card,insights_card,
│   │   │                    supplements_card}.dart
│   │   ├── nutrition/
│   │   │   ├── domain/
│   │   │   │   ├── entities/{food,nutrition_entry,macros,meal_slot,
│   │   │   │   │            meal_template,daily_nutrition,water_entry}.dart
│   │   │   │   ├── repositories/{nutrition_repository,food_repository}.dart
│   │   │   │   └── usecases/{log_food,delete_entry,search_foods,
│   │   │   │                 scan_barcode,apply_template,log_water,
│   │   │   │                 compute_targets}.dart
│   │   │   ├── data/…
│   │   │   └── presentation/
│   │   │       ├── controllers/{nutrition,food_search,portion}_controller.dart
│   │   │       └── screens/{nutrition,add_food,barcode_scanner,
│   │   │                    meal_planner,shopping_list,food_detail}_screen.dart
│   │   ├── supplements/
│   │   ├── workout/
│   │   │   ├── domain/
│   │   │   │   ├── entities/{exercise,workout_template,workout_program,
│   │   │   │   │            workout_session,workout_set,personal_record}.dart
│   │   │   │   ├── repositories/{workout_repository,exercise_repository}.dart
│   │   │   │   └── usecases/{start_session,complete_set,finish_session,
│   │   │   │                 detect_pr,get_last_performance}.dart
│   │   │   ├── data/…
│   │   │   └── presentation/…
│   │   ├── live_gym/
│   │   │   ├── domain/entities/{live_session_state,rest_timer_state}.dart
│   │   │   └── presentation/
│   │   │       ├── controllers/{live_gym,rest_timer}_controller.dart
│   │   │       ├── screens/live_gym_screen.dart
│   │   │       └── widgets/{set_entry,rest_overlay,exercise_header,
│   │   │                    weight_stepper,rpe_selector,pr_toast,
│   │   │                    session_summary}.dart
│   │   ├── body/
│   │   ├── recovery/
│   │   ├── sleep/
│   │   ├── calendar/
│   │   ├── tasks/
│   │   ├── ai_hub/
│   │   ├── insights/
│   │   ├── analytics/
│   │   ├── health_sync/
│   │   ├── notifications/
│   │   └── settings/
│   │
│   ├── shared/
│   │   ├── domain/value_objects/{weight,length,volume,energy,
│   │   │                         time_window,date_range}.dart
│   │   ├── domain/enums/{goal_mode,muscle_group,equipment,day_type,
│   │   │                 activity_level,priority}.dart
│   │   └── extensions/{context_x,list_x,num_x,string_x,duration_x}.dart
│   │
│   └── l10n/app_localizations.dart   # GENERATED
│
└── test/
    ├── unit/
    │   ├── core/engines/       # golden fixtures shared with functions/
    │   ├── features/**/domain/
    │   └── features/**/data/
    ├── widget/
    │   ├── core/widgets/       # every design-system component
    │   └── features/**/presentation/
    ├── golden/                 # visual regression, dark + light + 200 % text
    ├── integration/            # end-to-end flows on a real device
    └── fixtures/
```

---

## 3. Layer contracts by example — Nutrition

### 3.1 Domain entity (pure)

```dart
// features/nutrition/domain/entities/macros.dart
@freezed
class Macros with _$Macros {
  const factory Macros({
    @Default(0) double kcal,
    @Default(0) double proteinG,
    @Default(0) double carbsG,
    @Default(0) double fatG,
  }) = _Macros;

  const Macros._();

  Macros operator +(Macros o) => Macros(
        kcal: kcal + o.kcal,
        proteinG: proteinG + o.proteinG,
        carbsG: carbsG + o.carbsG,
        fatG: fatG + o.fatG,
      );

  Macros scaled(double factor) => Macros(
        kcal: kcal * factor,
        proteinG: proteinG * factor,
        carbsG: carbsG * factor,
        fatG: fatG * factor,
      );

  /// 4/4/9 reconstruction — used to sanity-check imported foods.
  double get derivedKcal => proteinG * 4 + carbsG * 4 + fatG * 9;
}
```

### 3.2 Repository interface (domain)

```dart
// features/nutrition/domain/repositories/nutrition_repository.dart
abstract interface class NutritionRepository {
  Stream<DailyNutrition> watchDay(DateTime localDate);
  Future<Result<NutritionEntry, Failure>> logEntry(NutritionEntry entry);
  Future<Result<void, Failure>> deleteEntry(String entryId);
  Future<Result<void, Failure>> applyTemplate(String templateId, MealSlot slot);
  Future<Result<List<NutritionEntry>, Failure>> recentEntries({int limit});
  Stream<int> watchWaterMl(DateTime localDate);
  Future<Result<void, Failure>> logWater(int ml);
}
```

### 3.3 Use case (domain)

```dart
// features/nutrition/domain/usecases/log_food.dart
class LogFoodUseCase {
  const LogFoodUseCase(this._repo, this._clock, this._ids);
  final NutritionRepository _repo;
  final Clock _clock;
  final IdGenerator _ids;

  Future<Result<NutritionEntry, Failure>> call({
    required Food food,
    required double quantity,
    required PortionUnit unit,
    required MealSlot slot,
    DateTime? at,
  }) async {
    if (quantity <= 0) return Err(const ValidationFailure('quantity_must_be_positive'));

    final grams = unit.toGrams(quantity, food);
    if (grams > 5000) return Err(const ValidationFailure('quantity_implausible'));

    final entry = NutritionEntry(
      id: _ids.v7(),
      foodId: food.id,
      foodName: food.name,
      quantity: quantity,
      unit: unit,
      gramsEquivalent: grams,
      macros: food.per100g.scaled(grams / 100),
      mealSlot: slot,
      loggedAt: at ?? _clock.now(),
    );
    return _repo.logEntry(entry);
  }
}
```

### 3.4 Repository implementation (data)

```dart
// features/nutrition/data/repositories/nutrition_repository_impl.dart
class NutritionRepositoryImpl implements NutritionRepository {
  NutritionRepositoryImpl(this._local, this._remote, this._outbox);
  final NutritionLocalDataSource _local;
  final NutritionRemoteDataSource _remote;
  final Outbox _outbox;

  @override
  Stream<DailyNutrition> watchDay(DateTime localDate) {
    // Local first — the screen never waits on the network.
    return _local.watchDay(localDate).map(NutritionMapper.toDomain);
  }

  @override
  Future<Result<NutritionEntry, Failure>> logEntry(NutritionEntry entry) async {
    try {
      final dto = NutritionEntryDto.fromDomain(entry);
      await _local.insert(dto);                  // ← commit point
      await _outbox.enqueue(OutboxOp.upsert(
        id: entry.id,
        collectionPath: 'nutrition_logs',
        payload: dto.toJson(),
      ));
      unawaited(_remote.upsert(dto).catchError((_) {/* outbox will retry */}));
      return Ok(entry);
    } on DatabaseException catch (e, s) {
      return Err(StorageFailure(e.message, stackTrace: s));
    }
  }
}
```

### 3.5 Controller (presentation)

```dart
// features/nutrition/presentation/controllers/nutrition_controller.dart
@riverpod
class NutritionController extends _$NutritionController {
  @override
  Stream<NutritionState> build(DateTime day) {
    final repo = ref.watch(nutritionRepositoryProvider);
    final targets = ref.watch(targetsProvider);
    return repo.watchDay(day).map(
      (nutrition) => NutritionState(
        day: day,
        nutrition: nutrition,
        targets: targets.forDayType(nutrition.dayType),
      ),
    );
  }

  Future<void> logFood({
    required Food food,
    required double quantity,
    required PortionUnit unit,
    required MealSlot slot,
  }) async {
    final result = await ref.read(logFoodUseCaseProvider)(
      food: food, quantity: quantity, unit: unit, slot: slot,
    );
    result.when(
      ok: (_) => ref.read(analyticsProvider).log(Events.foodLogged(source: 'search')),
      err: (f) => ref.read(bannerProvider.notifier).show(FailureMapper.map(f)),
    );
  }
}
```

---

## 4. `pubspec.yaml` (dependency contract)

```yaml
name: lifedna
description: LifeDNA OS — Your Personal Performance Operating System
publish_to: none
version: 1.0.0+1

environment:
  sdk: ">=3.5.0 <4.0.0"
  flutter: ">=3.24.0"

dependencies:
  flutter: { sdk: flutter }
  flutter_localizations: { sdk: flutter }

  # State & DI
  flutter_riverpod: ^2.5.1
  riverpod_annotation: ^2.3.5

  # Routing
  go_router: ^14.2.0

  # Models
  freezed_annotation: ^2.4.4
  json_annotation: ^4.9.0

  # Firebase
  firebase_core: ^3.3.0
  firebase_auth: ^5.1.4
  cloud_firestore: ^5.2.1
  firebase_storage: ^12.1.3
  cloud_functions: ^5.0.4
  firebase_messaging: ^15.0.4
  firebase_analytics: ^11.2.1
  firebase_crashlytics: ^4.0.4
  firebase_remote_config: ^5.0.4

  # Auth providers
  google_sign_in: ^6.2.1
  sign_in_with_apple: ^6.1.1

  # Local storage
  drift: ^2.19.0
  sqlite3_flutter_libs: ^0.5.24
  sqlcipher_flutter_libs: ^0.6.4
  path_provider: ^2.1.4
  shared_preferences: ^2.3.1
  flutter_secure_storage: ^9.2.2

  # Health & devices
  health: ^10.2.0                    # Health Connect / HealthKit
  flutter_blue_plus: ^1.32.12        # Galaxy Fit 3 BLE
  permission_handler: ^11.3.1

  # Notifications & background
  flutter_local_notifications: ^17.2.2
  timezone: ^0.9.4
  workmanager: ^0.5.2
  wakelock_plus: ^1.2.8

  # Camera / scanning
  mobile_scanner: ^5.2.3
  image_picker: ^1.1.2

  # Charts & UI
  fl_chart: ^0.68.0
  shimmer: ^3.0.0
  flutter_svg: ^2.0.10

  # Utilities
  intl: ^0.19.0
  uuid: ^4.4.2
  collection: ^1.18.0
  connectivity_plus: ^6.0.5
  package_info_plus: ^8.0.2
  device_info_plus: ^10.1.2
  url_launcher: ^6.3.0
  speech_to_text: ^6.6.2
  record: ^5.1.2

dev_dependencies:
  flutter_test: { sdk: flutter }
  integration_test: { sdk: flutter }
  build_runner: ^2.4.11
  riverpod_generator: ^2.4.3
  freezed: ^2.5.7
  json_serializable: ^6.8.0
  drift_dev: ^2.19.1
  custom_lint: ^0.6.5
  riverpod_lint: ^2.3.13
  very_good_analysis: ^6.0.0
  mocktail: ^1.0.4
  golden_toolkit: ^0.15.0
  fake_cloud_firestore: ^3.0.2
  firebase_auth_mocks: ^0.14.1

flutter:
  uses-material-design: true
  generate: true
  assets:
    - assets/data/
    - assets/images/
  fonts:
    - family: Inter
      fonts:
        - { asset: assets/fonts/Inter/Inter-Regular.ttf,  weight: 400 }
        - { asset: assets/fonts/Inter/Inter-Medium.ttf,   weight: 500 }
        - { asset: assets/fonts/Inter/Inter-SemiBold.ttf, weight: 600 }
        - { asset: assets/fonts/Inter/Inter-Bold.ttf,     weight: 700 }
        - { asset: assets/fonts/Inter/Inter-ExtraBold.ttf,weight: 800 }
    - family: JetBrainsMono
      fonts:
        - { asset: assets/fonts/JetBrainsMono/JetBrainsMono-Regular.ttf, weight: 400 }
        - { asset: assets/fonts/JetBrainsMono/JetBrainsMono-Medium.ttf,  weight: 500 }
```

---

## 5. Naming and file conventions

| Kind | Convention | Example |
|---|---|---|
| Files | `snake_case.dart` | `live_gym_screen.dart` |
| Classes | `PascalCase` | `LiveGymController` |
| Design-system widgets | `Ld` prefix | `LdProgressRing` |
| Providers | `camelCaseProvider` | `nutritionRepositoryProvider` |
| Use cases | `<Verb><Noun>UseCase` | `CompleteSetUseCase` |
| DTOs | `<Entity>Dto` | `WorkoutSetDto` |
| Mappers | `<Entity>Mapper` | `NutritionMapper` |
| Enums | `PascalCase`, values `camelCase` | `MealSlot.preWorkout` |
| Tests | `<subject>_test.dart` mirroring `lib/` | `test/unit/core/engines/e1rm_calculator_test.dart` |

**Barrel files** are used per feature layer only (`domain/domain.dart`), never a global one.

---

## 6. `analysis_options.yaml`

```yaml
include: package:very_good_analysis/analysis_options.yaml

analyzer:
  plugins: [custom_lint]
  exclude:
    - "**/*.g.dart"
    - "**/*.freezed.dart"
    - "lib/l10n/**"
  language:
    strict-casts: true
    strict-inference: true
    strict-raw-types: true
  errors:
    invalid_annotation_target: ignore
    missing_required_param: error
    missing_return: error
    todo: ignore

linter:
  rules:
    always_use_package_imports: true
    avoid_print: true
    prefer_const_constructors: true
    prefer_final_locals: true
    require_trailing_commas: true
    unawaited_futures: true
    use_super_parameters: true
    sort_pub_dependencies: false
```

---

## 7. Build and code generation

```bash
# One-time / after changing annotated sources
dart run build_runner build --delete-conflicting-outputs

# During development
dart run build_runner watch --delete-conflicting-outputs

# Localization
flutter gen-l10n

# Design tokens → Dart
dart run tool/generate_tokens.dart

# Layer boundary check (also runs in CI)
dart run tool/import_lint.dart

# Flavors
flutter run   --flavor dev     --dart-define=FLAVOR=dev
flutter build appbundle --flavor prod --dart-define=FLAVOR=prod --obfuscate \
  --split-debug-info=build/symbols
```

---

## 8. Testing structure

| Level | Location | What it proves | Gate |
|---|---|---|---|
| Engine golden | `test/unit/core/engines/` | Dart and TypeScript engines agree on the shared fixtures | 100 % of fixtures |
| Domain unit | `test/unit/features/**/domain/` | Use cases and entities behave | ≥ 90 % |
| Data unit | `test/unit/features/**/data/` | Mapping, offline path, outbox behaviour | ≥ 80 % |
| Widget | `test/widget/` | Every `Ld*` component and every screen renders its states | Every component |
| Golden | `test/golden/` | Dark, light, 200 % text scale, RTL | Key screens |
| Integration | `test/integration/` | Onboarding, log-a-meal, complete-a-workout-offline | Must pass on device |

`ProviderContainer` with overrides is the substitution mechanism; there is no service
locator to reset between tests.
