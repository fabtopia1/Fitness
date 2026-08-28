# 05 — UI sitemap

Every route below is registered in `app/lib/core/router/app_router.dart` and
every screen exists. There are no placeholder destinations.

## 1. The map

```
/                    splash — held only while auth resolves
│
├── UNAUTHENTICATED
│   ├── /welcome     LifeDNA OS, the two account buttons, and — when the build
│   │                has no Firebase — "Continue on this device"
│   ├── /sign-in     email + password, Google (hidden when unavailable),
│   │                password reset
│   └── /sign-up     name, email, password (≥ 10 characters)
│
├── AUTHENTICATED, NOT ONBOARDED
│   └── /onboarding  four steps: about you → measurements → goal →
│                    the derived targets, shown BEFORE anything is committed
│
└── AUTHENTICATED, ONBOARDED
    │
    ├── SHELL (five-destination bottom bar, offline banner, resume bar)
    │   ├── /home        Dashboard
    │   ├── /nutrition   today's macros, water, the day's entries
    │   ├── /train       programs, history, personal records
    │   ├── /body        weight trend, measurements, progress photos
    │   └── /me          Settings
    │
    └── FULL SCREEN (no bottom bar — a focused task)
        ├── /nutrition/add?slot=…   food and meal search → PortionSheet
        ├── /supplements            the stack, today's schedule, adherence
        ├── /train/live             LIVE GYM MODE
        ├── /train/editor?id=…      program editor
        ├── /train/exercises        exercise library
        ├── /plan                   tasks | calendar | reminders
        ├── /ai                     AI Hub
        ├── /health                 Health sync
        └── /settings               Settings (same screen as /me)
```

An unknown path renders a not-found screen with a "Go home" button, because a
dead end is worse than a wrong turn.

## 2. Why full-screen and not a tab

A bottom bar during a task is an invitation to abandon the task. Adding food,
running a workout, and editing a program are all things a user is *in the
middle of*; they get the whole screen and an explicit way back.

Live Gym Mode is the strongest case: it is operated one-handed, at arm's
length, between sets. Its primary control is 72 dp tall (`LdButtonSize.xl`),
which is above the 64 dp gym minimum and well above the 48 dp WCAG floor.

## 3. Modal surfaces

Sheets, not routes, because they return a value to the caller:

| Sheet | Opened from | Returns |
|---|---|---|
| `PortionSheet` | add food | the logged entry |
| `CreateFoodSheet` | add food | the new `FoodItem` |
| `SupplementEditorSheet` | supplements | — |
| `BodyEditorSheet` | body | — |
| `TaskEditorSheet` / `EventEditorSheet` / `ReminderEditorSheet` | plan | — |
| `ExercisePicker` | live workout, program editor | the chosen `Exercise` |
| `CreateExerciseSheet` | exercise library, picker | the new `Exercise` |
| `GoalsEditorSheet` | settings | — |
| `_SummarySheet` | live workout → Finish | confirm / keep going |

## 4. Persistent chrome

Two things follow the user everywhere inside the shell:

**The offline / sync banner.** Silent when online and synced. Otherwise:
- offline → "Offline · everything still works" (or "· 3 changes will sync later")
- parked writes → "2 changes couldn't sync" with a Retry action

It is never a blocking dialog. Being offline stops the user doing nothing, so
it must stop them seeing nothing.

**The resume bar.** While a workout is in progress, a tap-to-resume bar sits
above the bottom bar from anywhere in the app, and the Train icon carries a
live dot. Losing a live session is the worst thing that can happen to a
training log.

## 5. Every screen's required states

`LdAsyncView` renders loading, error (with retry when the failure is
retryable), empty, and data from one place, so no screen can forget one.

| State | Rule |
|---|---|
| Loading | a spinner, never a blank frame |
| Empty | names the value and offers the next action — never a bare "No data" |
| Error | mapped copy, never raw exception text; a retry only when retrying could plausibly work |
| Offline | the banner; the screen itself still renders from Hive |
| Timeout | 20 s (`Env.networkTimeout`), then the same treatment as offline |

## 6. Accessibility and ergonomics

- Minimum touch target 48 dp; 64 dp in Live Gym Mode; 72 dp for its primary action.
- Text scaling is honoured and clamped to 0.85–1.6 in `app.dart`, because
  beyond that the fixed-height gym controls stop fitting their numbers.
- Every interactive component carries a semantic label; charts and rings
  expose a screen-reader summary rather than a picture.
- `MediaQuery.disableAnimations` is honoured by every animated surface.
- Dark theme first; the light theme is complete and tested, not an afterthought.
