# LifeDNA OS — Flutter application

Material 3 · Clean Architecture · Riverpod · dark-theme-first.

---

## 1. What runs today, and what is scaffolded

This module is a **working application**, not a stub. It builds and runs with
`flutter run` against a compiled-in reference dataset, so you can exercise the
real screens and the real algorithms without a Firebase project, a signing
config, or a code-generation step.

| Layer | Status |
|---|---|
| Design system (`core/theme`, `core/widgets`) | **Complete** — tokens, both themes, 9 components, widget-tested |
| Deterministic engines (`core/engines`) | **Complete** — macro, recovery, load, e1RM/PR, priority. 100 % of the documented formulas, unit-tested against hand-verified fixtures |
| Domain layer (`features/*/domain`) | **Complete for the shipped modules** — entities, value objects, repository interfaces |
| Data layer (`features/*/data`) | **Reference in-memory implementations.** They implement the full repository contract including the offline-first write ordering. Firestore + Drift implementations replace them without touching anything above |
| Screens | Dashboard · Nutrition · Add Food · Train · **Live Gym Mode** are built. Plan and Me are placeholders pointing at their sprint |
| Firebase wiring | Rules, indexes and Cloud Functions live in `../firebase` and `../functions`. The client SDK dependencies are commented out in `pubspec.yaml` |

**The honest summary:** the parts that are hard to get right — the algorithms,
the offline write path, the design system, the ergonomics of Live Gym Mode —
are real and tested. The parts that are mechanical — swapping an in-memory map
for a Firestore collection — are specified but not yet wired.

---

## 2. Running it

```bash
flutter pub get
flutter run
```

No `build_runner` step. The scaffold deliberately avoids `freezed`,
`json_serializable` and `riverpod_generator` so that the checked-in source is
the complete source — there are no `.g.dart` files you cannot see. When the
production data layer lands, those generators come with it (the dependency
block is already written out in `pubspec.yaml`, commented).

### Tests

```bash
flutter test                      # unit + widget
flutter test test/unit            # engines only — fast
python3 tool/check_sources.py     # layer boundaries + colour discipline
```

`tool/check_sources.py` enforces two rules `flutter analyze` cannot express:

1. **The layer boundary.** Anything under `domain/`, `engines/`,
   `shared/value_objects/` or `shared/enums/` must not import Flutter,
   Firebase, Riverpod, go_router or `dart:io`. The domain is pure Dart.
2. **Colour discipline.** No `Colors.*` or `Color(0x…)` literal outside
   `core/theme/`. Every colour comes from `context.ldColors`.

---

## 3. Wiring the production data layer

Two provider overrides. Nothing above the repository interfaces changes:

```dart
runApp(
  ProviderScope(
    overrides: [
      nutritionRepositoryProvider.overrideWith(
        (ref) => FirestoreNutritionRepository(
          firestore: ref.watch(firestoreProvider),
          local: ref.watch(driftProvider),
          outbox: ref.watch(outboxProvider),
        ),
      ),
      workoutRepositoryProvider.overrideWith(
        (ref) => FirestoreWorkoutRepository(/* … */),
      ),
    ],
    child: const LifeDnaApp(),
  ),
);
```

The in-memory implementations already model the ordering the production ones
must preserve — commit locally first, replicate second — so they double as the
specification for the real thing. See `docs/02-system-architecture.md §7`.

---

## 4. Layout

```
lib/
├── main.dart                 bootstrap
├── app.dart                  MaterialApp.router
├── core/
│   ├── theme/                tokens, LdColors, LdTypography, AppTheme
│   ├── widgets/              the design system in code (Ld* components)
│   ├── engines/              PURE DART — every number the user sees
│   ├── router/               go_router, shell, resume banner
│   ├── providers/            the Riverpod graph
│   ├── data/                 seeded catalogues (foods, exercises, programs)
│   ├── errors/               sealed Failure + the copy mapper
│   ├── result/               Result<T, Failure>
│   └── utils/                UUID v7
├── features/<module>/
│   ├── domain/               entities · repository interfaces  (pure)
│   ├── data/                 implementations                    (impure)
│   └── presentation/         screens + widgets
└── shared/                   enums, value objects
```

---

## 5. Why these engines are on the client at all

`core/engines/` mirrors `functions/src/engines/`. That duplication is
deliberate and is discussed in `docs/02 §5.2`: the client copy exists so the UI
can recompute a recovery score or a macro target **instantly and offline** when
the user edits an input, and the server copy is authoritative for what gets
stored. They are kept in lockstep by a shared fixture suite that both test
suites execute — a divergence fails both builds.

If you change a formula, change it in both places and update
`test/fixtures/engines/`.

---

## 6. Conventions

- **Files** `snake_case.dart` · **Classes** `PascalCase` · design-system
  widgets carry the `Ld` prefix.
- **Every colour** via `context.ldColors`; **every text style** via
  `context.ldType`.
- **Every animated surface** honours `context.reduceMotion`.
- **Every interactive element** has a semantic label and a ≥ 48 dp target
  (≥ 64 dp in Live Gym Mode).
- **Failures** never surface raw: they go through `FailureMapper`, which is the
  single place user-facing error copy is written.
