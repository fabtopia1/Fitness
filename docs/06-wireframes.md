# LifeDNA OS — Screen-by-Screen Wireframes

**Version:** 1.0
**Reference viewport:** 412 × 915 dp (Galaxy S24 class)
**Theme shown:** dark (default)

Every wireframe below states its layout, its data bindings, its interactions and its
states (loading / empty / error / offline). These are build instructions, not sketches.

---

## Screen 01 — Dashboard (`/home`)

```
┌────────────────────────────────────────────────┐
│ ●                                       ⌂ 09:41│  status bar
│                                                │
│  Good morning, Youssef            [◉]  [🔔³]   │  headlineL · avatar · notif badge
│  FRIDAY 28 AUGUST · Rest day       ⟳ 2 min ago │  labelMono textTertiary + sync badge
│                                                │
│ ┌────────────────────────────────────────────┐ │
│ │▎NEXT                                       │ │  ← THE APEX. Accent bar = domain colour
│ │                                            │ │
│ │  You are 32 g below your protein target    │ │  titleL
│ │  4 h until bed · a 40 g snack closes it    │ │  bodyS textSecondary
│ │                                            │ │
│ │  ┌──────────────────┐  ┌────────────────┐  │ │
│ │  │   Log protein    │  │      Why?      │  │ │  primary 52dp + ghost
│ │  └──────────────────┘  └────────────────┘  │ │
│ └────────────────────────────────────────────┘ │
│                                                │
│ ┌────────────────────────────────────────────┐ │
│ │  TODAY'S FUEL                    2,412 /   │ │
│ │                                  2,350 kcal│ │
│ │              ╭─────────╮                   │ │
│ │             ╱   2,412   ╲                  │ │  xl ring (168) — calories
│ │            │    /2,350   │                 │ │  over-target arc in lighter blue
│ │             ╲   KCAL    ╱                  │ │
│ │              ╰─────────╯                   │ │
│ │                                            │ │
│ │   ◐ 168/200 g    ◑ 268/210 g   ◔ 66/70 g   │ │  3 × m rings (96)
│ │     PROTEIN        CARBS         FAT       │ │  teal · amber · orange
│ │                                            │ │
│ │   💧 2,750 / 3,500 ml         [ +250 ml ]  │ │  hydration row + quick action
│ └────────────────────────────────────────────┘ │
│                                                │
│ ┌──────────────────────┐┌────────────────────┐ │
│ │ ▎RECOVERY            ││ ▎SLEEP             │ │  2-up grid
│ │  82                  ││  7h 11m            │ │  displayM
│ │  HIGH  ▲ +4 vs 7d    ││  SCORE 79          │ │
│ │  ●●●●●●●●○○          ││  23:15 → 06:26     │ │
│ └──────────────────────┘└────────────────────┘ │
│                                                │
│ ┌────────────────────────────────────────────┐ │
│ │ ▎TODAY'S TRAINING                          │ │
│ │  REST DAY · optional recovery swim         │ │
│ │  Next: PUSH tomorrow 18:00 · 22 sets       │ │
│ │  ┌──────────────────────────────────────┐  │ │
│ │  │        Start a session               │  │ │  secondary button
│ │  └──────────────────────────────────────┘  │ │
│ └────────────────────────────────────────────┘ │
│                                                │
│ ┌────────────────────────────────────────────┐ │
│ │ ▎SCHEDULE                        See all → │ │
│ │  11:00  Data Structures — Lecture   in 1h  │ │
│ │  14:30  Team standup                       │ │
│ │  17:00  Shift starts                       │ │
│ └────────────────────────────────────────────┘ │
│                                                │
│ ┌────────────────────────────────────────────┐ │
│ │ ▎TASKS                        3 due today  │ │
│ │  ○ P1  Submit DS assignment      17:00     │ │
│ │  ○ P2  Reply to supervisor                 │ │
│ │  ○ P3  Order creatine (6 days left)        │ │
│ └────────────────────────────────────────────┘ │
│                                                │
│ ┌────────────────────────────────────────────┐ │
│ │ ▎INSIGHTS                                  │ │
│ │  💡 Sleep dropped 14 % this week      86 % │ │
│ │  💡 Ready for a PR on incline bench   74 % │ │
│ └────────────────────────────────────────────┘ │
│                                                │
│ ┌────────────────────────────────────────────┐ │
│ │ ▎SUPPLEMENTS                         4/5   │ │
│ │  ✓ D3   ✓ Omega-3   ✓ Creatine   ✓ Multi   │ │
│ │  ○ Magnesium — 22:30                       │ │
│ └────────────────────────────────────────────┘ │
│                                                │
│ ══════════════════════════════════════════════ │  glass bottom nav
│   ⌂        🍽        🏋        📅        👤     │
│  Home   Nutrition   Train    Plan       Me     │
└────────────────────────────────────────────────┘
```

**Data source:** one `DashboardSnapshot` from `dashboardSnapshotProvider`, itself backed by
a single `daily_stats/{today}` read plus streams for schedule/tasks/insights.

**States**
- *Loading:* skeleton cards matching exact final heights. No spinner.
- *Offline:* sync badge turns amber, reads `Offline · synced 2 h ago`. All cards render from cache.
- *New user (day 0):* Next Action = "Log your first meal"; Recovery card replaced by
  "Connect a health source"; Insights card replaced by a progress row `Day 1 of 7`.
- *Error:* per-card inline error with retry — a failed insights fetch never blanks the page.

**Interactions**
- Pull-to-refresh → fan-out sync with a per-source progress row.
- Long-press any metric → 7-day sparkline sheet.
- Card reorder via Settings → Dashboard layout.

---

## Screen 02 — Nutrition Center (`/nutrition`)

```
┌────────────────────────────────────────────────┐
│ ←  Nutrition                          ⋯        │
│                                                │
│  ◀  MON  TUE  WED  THU [FRI] SAT  SUN  ▶       │  LdCalendarStrip
│      ✓    ✓    ✓    ✓   ●               dots = adherence
│                                                │
│ ┌────────────────────────────────────────────┐ │
│ │  2,412 / 2,350 kcal          TRAINING DAY  │ │  segmented: [Training][Rest]
│ │  ████████████████████████████░░  +62 over  │ │
│ │                                            │ │
│ │  PROTEIN  168/200 g  ████████████░░░  −32  │ │
│ │  CARBS    268/210 g  ██████████████████ +58│ │
│ │  FAT       66/70 g   ████████████████░  −4 │ │
│ └────────────────────────────────────────────┘ │
│                                                │
│  BREAKFAST                        520 kcal  ⌄  │  09:00
│   Eggs, whole · 3 pcs             234 · 19 g P │
│   Foul medames · 200 g            196 · 13 g P │
│   Baladi bread · 1 loaf            90 ·  3 g P │
│   [ + Add to breakfast ]                       │
│                                                │
│  LUNCH                            712 kcal  ⌄  │  13:00
│   Chicken breast · 200 g          330 · 62 g P │
│   White rice, cooked · 250 g      325 ·  6 g P │
│   Mixed salad · 150 g              57 ·  2 g P │
│   [ + Add to lunch ]                           │
│                                                │
│  PRE-WORKOUT                      340 kcal  ⌄  │  16:30
│  POST-WORKOUT                     840 kcal  ⌄  │  19:30
│  BEFORE BED                    ○ not logged    │  22:30  ← amber, actionable
│   [ + Add to before bed ]                      │
│                                                │
│ ┌────────────────────────────────────────────┐ │
│ │ 💧 WATER            2,750 / 3,500 ml       │ │
│ │  ▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓░░░░░░               │ │
│ │  [+250] [+500] [+750]              ⋯       │ │
│ └────────────────────────────────────────────┘ │
│                                                │
│                                    ┌─────────┐ │
│                                    │  + Log  │ │  extended FAB
│                                    └─────────┘ │
│ ══════════════════════════════════════════════ │
└────────────────────────────────────────────────┘
```

**Overflow menu:** Meal planner · Shopping list · Templates · Copy yesterday ·
Nutrition settings.
**Swipe on an entry:** left = delete (undo snackbar), right = duplicate.
**Empty day:** "Nothing logged yet today. Your first meal takes about 12 seconds."
+ `[Log breakfast]` + `[Copy yesterday]`.

---

## Screen 03 — Add Food (`/nutrition/log`)

```
┌────────────────────────────────────────────────┐
│ ←  Add to Lunch                      [ 📷 ]    │
│                                                │
│ ┌────────────────────────────────────────────┐ │
│ │ 🔍  Search foods…                          │ │  autofocus, keyboard up
│ └────────────────────────────────────────────┘ │
│                                                │
│ [ Recent ] [ Favorites ] [ Meals ] [ All ]     │  segmented, Recent default
│                                                │
│  Chicken breast, skinless, raw                 │
│  165 kcal · 31 g P per 100 g          [ + ]    │  56dp row, + adds last portion
│                                                │
│  White rice, cooked                            │
│  130 kcal · 2.7 g P per 100 g         [ + ]    │
│                                                │
│  Greek yogurt 0% · Juhayna                     │
│  59 kcal · 10 g P per 100 g           [ + ]    │
│                                                │
│  ── SAVED MEALS ──────────────────────────     │
│  Post-workout: beef · rice · veg               │
│  812 kcal · 58 g P                    [ + ]    │  one tap logs the whole meal
│                                                │
│  ── QUICK ADD ─────────────────────────────    │
│  [ Enter macros manually ]                     │
└────────────────────────────────────────────────┘

PORTION SHEET (slides up over the list)
┌────────────────────────────────────────────────┐
│              ────                              │  drag handle
│  Chicken breast, skinless, raw                 │  titleL
│  Verified · per 100 g                          │  labelMono textTertiary
│                                                │
│         ┌──────┐                               │
│    −    │ 200  │    +        [ g ▾ ]           │  stepper, 48dp targets
│         └──────┘                               │
│    100 g   150 g   200 g   1 breast            │  quick chips
│                                                │
│  ┌──────────────────────────────────────────┐  │
│  │  330 kcal   62 g P    0 g C    7.2 g F   │  │  live preview
│  └──────────────────────────────────────────┘  │
│                                                │
│  Meal:  [ Lunch ▾ ]        Time: [ 13:00 ]     │
│                                                │
│  ┌──────────────────────────────────────────┐  │
│  │               Add to Lunch               │  │  primary 64dp
│  └──────────────────────────────────────────┘  │
└────────────────────────────────────────────────┘
```

---

## Screen 04 — Barcode Scanner (`/nutrition/scan`)

```
┌────────────────────────────────────────────────┐
│ ✕                                        [⚡]  │  close · torch
│                                                │
│          ┌───────────────────────┐             │
│          │                       │             │  camera preview
│          │   ┌───────────────┐   │             │  reticle with animated
│          │   │               │   │             │  scan line
│          │   │  ▬▬▬▬▬▬▬▬▬▬▬  │   │             │
│          │   │               │   │             │
│          │   └───────────────┘   │             │
│          │                       │             │
│          └───────────────────────┘             │
│                                                │
│        Point at a barcode                      │
│                                                │
│  ┌──────────────────────────────────────────┐  │
│  │  Can't scan it?  [ Search instead ]      │  │
│  └──────────────────────────────────────────┘  │
└────────────────────────────────────────────────┘

RESOLVED → portion sheet (Screen 03) with source chip:
   "Open Food Facts · community data"  ← provenance is always shown
NOT FOUND →
   "Barcode 6224000123456 isn't in the database yet."
   [ Add this food ]  → create-food form with the barcode pre-filled
```

---

## Screen 05 — Workout Center (`/train`)

```
┌────────────────────────────────────────────────┐
│  Train                                    ⋯    │
│                                                │
│ ┌────────────────────────────────────────────┐ │
│ │ ▎TODAY                                     │ │
│ │  PUSH — Chest · Shoulders · Triceps        │ │
│ │  22 working sets · ~75 min · 18:00         │ │
│ │  ┌──────────────────────────────────────┐  │ │
│ │  │           START WORKOUT              │  │ │  primary 64dp
│ │  └──────────────────────────────────────┘  │ │
│ │  [ Preview ]              [ Swap day ]     │ │
│ └────────────────────────────────────────────┘ │
│                                                │
│  8-WEEK BODY RECOMPOSITION        Week 1 of 8  │
│  ▓▓░░░░░░░░░░░░░░░░░░░░░░  Foundation phase    │
│                                                │
│  SAT  SUN  MON  TUE  WED  THU  FRI             │
│  PUSH PULL LEGS FIT  UPP  LOW  SWIM            │  weekly strip
│   ●    ○    ○    ○    ○    ○    ○              │  ● = today
│                                                │
│  ── THIS WEEK ─────────────────────────────    │
│  Sessions          1 / 6                       │
│  Volume            14,820 kg   ▲ 6 %           │
│  Sets              22                          │
│  Every muscle 2×   ✓ on track                  │
│                                                │
│  ── RECENT SESSIONS ───────────────────────    │
│  PUSH · yesterday          14,820 kg · 73 min  │
│  🏆 1 PR · Incline DB Press 32.5 × 10          │
│                                                │
│  LOWER · 3 days ago        18,240 kg · 71 min  │
│                                                │
│  ┌──────────┐┌──────────┐┌──────────┐          │
│  │Templates ││ Exercises││ History  │          │  nav tiles
│  └──────────┘└──────────┘└──────────┘          │
│ ══════════════════════════════════════════════ │
└────────────────────────────────────────────────┘
```

**Persistent banner (any tab) when a session is in progress:**
`▶ PUSH in progress · 00:12:41   [ Resume ]` — glass, above the bottom nav.

---

## Screen 06 — Live Gym Mode (`/live/:sessionId`)  ★ flagship

```
┌────────────────────────────────────────────────┐
│  PUSH              00:12:41       ⏸    ⋯       │  compact header, mono clock
│  ▓▓▓▓▓░░░░░░░░░░░░░░░  6 of 22 sets            │
│                                                │
│                                                │
│   INCLINE DUMBBELL PRESS                       │  headlineL
│   Set 2 of 4 · target 8–12 @ RPE 8             │  bodyM textSecondary
│                                                │
│   ┌──────────────────┐  ┌──────────────────┐   │
│   │      32.5        │  │        10        │   │  displayXL 56sp, tnum
│   │       KG         │  │       REPS       │   │  labelMono
│   │   ─────  ─────   │  │   ─────  ─────   │   │
│   │   │ − │  │ + │   │  │   │ − │  │ + │   │   │  56×56 steppers
│   │   ─────  ─────   │  │   ─────  ─────   │   │
│   └──────────────────┘  └──────────────────┘   │
│                                                │
│   Last time:  30.0 kg × 10  ·  RPE 8           │  textTertiary
│                                                │
│   RPE   [6] [7] [8] [9] [10]   [to failure]    │  chips, 48dp
│                                                │
│                                                │
│   ┌────────────────────────────────────────┐   │
│   │                                        │   │
│   │            COMPLETE SET                │   │  72dp, primary, thumb zone
│   │                                        │   │
│   └────────────────────────────────────────┘   │
│                                                │
│   [  Skip  ]   [  Note  ]   [   🎤   ]         │  56dp ghost row
│                                                │
│   ─────────────────────────────────────────    │
│   NEXT   Cable Fly · 3 × 12                    │  bodyS textSecondary
└────────────────────────────────────────────────┘

REST OVERLAY (glass, slides up from the button on completion)
┌────────────────────────────────────────────────┐
│   ✓ Set 2 logged · 32.5 kg × 10                │  brief confirmation
│                                                │
│                  1:34                          │  displayXL 72sp
│                                                │
│   ▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓░░░░░░░░░░░░              │
│                                                │
│   [ − 15s ]     [  SKIP  ]     [ + 15s ]       │  56dp each
│                                                │
│   UP NEXT   Set 3 of 4 · 32.5 kg × 10          │
└────────────────────────────────────────────────┘

PR MOMENT (inline, non-blocking, 600 ms amber pulse — never a modal)
   ┌──────────────────────────────────────────┐
   │ 🏆  NEW e1RM  43.3 kg   ▲ 8.3 %          │
   └──────────────────────────────────────────┘

SET LIST (swipe down from the header, or ⋯ → Show all sets)
   ✓ 1   30.0 kg × 12   RPE 7
   ✓ 2   32.5 kg × 10   RPE 8   🏆
   ▸ 3   32.5 kg × 10   —              ← current
     4   32.5 kg × 8    —

⋯ MENU
   Add exercise · Reorder · Replace exercise · Edit rest ·
   Plate calculator · Add drop set · Show all sets · Discard session

FINISH → SUMMARY
┌────────────────────────────────────────────────┐
│              WORKOUT COMPLETE                  │
│                                                │
│   73:12        14,820 kg      22        1      │
│   DURATION      VOLUME       SETS      PRs     │
│                                                │
│   MUSCLE SPLIT                                 │
│   Chest      ████████████  5,400 kg            │
│   Shoulders  █████████     4,100 kg            │
│   Triceps    ███████████   5,320 kg            │
│                                                │
│   How hard was that?                           │
│   [6] [7] [8] [9] [10]                         │  required, 1 tap
│                                                │
│   Notes  ┌──────────────────────────────────┐  │
│          │ optional                         │  │
│          └──────────────────────────────────┘  │
│                                                │
│   ┌──────────────────────────────────────────┐ │
│   │             SAVE WORKOUT                 │ │
│   └──────────────────────────────────────────┘ │
│   [ Discard ]                                  │
└────────────────────────────────────────────────┘
```

**Hard constraints:** no bottom nav · wakelock held · every interactive element inside the
bottom 60 % · all writes local-first · foreground service while BLE HR is streaming.

---

## Screen 07 — Exercise History (`/train/exercise/:id`)

```
┌────────────────────────────────────────────────┐
│ ←  Incline Dumbbell Press              ☆       │
│  Chest (upper) · Dumbbell · Compound           │
│                                                │
│ [ History ] [ Charts ] [ Records ] [ How to ]  │
│                                                │
│  ESTIMATED 1RM                                 │
│      43.3 kg   ▲ 8.3 % over 8 sessions         │
│   ╭────────────────────────────────────────╮   │
│   │                                   ╱     │   │  line chart, EWMA
│   │                            ╱─────       │   │
│   │              ╱────────────              │   │
│   │   ╱─────────                            │   │
│   ╰────────────────────────────────────────╯   │
│    12 Jul                            28 Aug    │
│                                                │
│  ── SESSION HISTORY ──────────────────────     │
│  27 Aug · PUSH                                 │
│    30.0 × 12 (RPE 7) · 32.5 × 10 (RPE 8) 🏆    │
│    32.5 × 10 (RPE 9) · 32.5 × 8  (RPE 9)       │
│    Volume 1,371 kg · best e1RM 43.3            │
│                                                │
│  20 Aug · PUSH                                 │
│    30.0 × 10 · 30.0 × 10 · 30.0 × 9 · 27.5 × 10│
│    Volume 1,172 kg · best e1RM 40.0            │
└────────────────────────────────────────────────┘
```

---

## Screen 08 — Recovery Detail (`/me/recovery`)

```
┌────────────────────────────────────────────────┐
│ ←  Recovery                                    │
│                                                │
│              ╭─────────────╮                   │
│            ╱                 ╲                 │
│           │       82          │                │  displayXL in an arc gauge
│           │      HIGH         │                │  band colour = green
│            ╲                 ╱                 │
│              ╰─────────────╯                   │
│         ▲ +4 vs your 7-day average             │
│                                                │
│ ┌────────────────────────────────────────────┐ │
│ │  GREEN LIGHT — TRAIN AS PLANNED            │ │
│ │  Sleep is at your 28-day average and your  │ │
│ │  load ratio is balanced at 1.07.           │ │
│ └────────────────────────────────────────────┘ │
│                                                │
│  COMPONENTS                                    │
│  Sleep      79  ████████████████░░░  40 % → 31.6│
│  Training   88  ██████████████████░  40 % → 35.2│
│  Activity   76  ███████████████░░░░  20 % → 15.2│
│                                                │
│  INPUTS                              [ ⓘ ]     │
│  Sleep duration        7 h 11 m                │
│  Sleep score           79                      │
│  Acute load (7d)       2,340                   │
│  Chronic load (28d)    2,180                   │
│  Load ratio (ACWR)     1.07    ✓ balanced      │
│  Steps                 8,432                   │
│  Resting HR            58 bpm   ▼ −1           │
│  HRV                   42 ms    ▲ +3           │
│                                                │
│  14-DAY TREND                                  │
│   ╭────────────────────────────────────────╮   │
│   │  ▁▃▅▄▆█▇▅▃▄▆█▇█                        │   │  bars, band-coloured
│   ╰────────────────────────────────────────╯   │
│                                                │
│  Engine recovery-1.2.0 · computed 03:04        │  labelMono textTertiary
└────────────────────────────────────────────────┘
```

**Insufficient-data state:** the gauge is replaced by a dashed ring reading `— —` with
"Recovery needs sleep data from at least 2 of the last 3 nights." + `[Connect health source]`.

---

## Screen 09 — Body Composition (`/me/body`)

```
┌────────────────────────────────────────────────┐
│ ←  Body                              [ + Log ] │
│                                                │
│  89.4 kg          ▼ −0.7 kg this week          │  displayL
│  Trend 89.7 kg (7-day average)                 │
│                                                │
│   ╭────────────────────────────────────────╮   │
│   │ 91 ┤ ●                                  │   │  raw points 30 % opacity
│   │    │ ╲●                                 │   │  EWMA line 100 %
│   │ 89 ┤   ╲●─●╲                            │   │  target band shaded
│   │    │        ╲●─●                        │   │
│   │ 87 ┤ ░░░░░░░░░░░░░░░░░ target 84–86 ░░░ │   │
│   │ 85 ┤                                    │   │
│   ╰────────────────────────────────────────╯   │
│    Wk1                                   Wk8   │
│                                                │
│  GOAL PROGRESS                                 │
│  90.1 ──────●───────────────────── 84.0        │
│  Start      89.4                   Target      │
│  12 % complete · projected 21 Oct at this rate │
│                                                │
│ ┌──────────────┐┌──────────────┐┌────────────┐ │
│ │ BODY FAT     ││ LEAN MASS    ││ WAIST      │ │
│ │ 30.8 %       ││ 61.9 kg      ││ 104.0 cm   │ │
│ │ ▼ −0.5       ││ ▲ +0.2       ││ ▼ −1.5     │ │
│ └──────────────┘└──────────────┘└────────────┘ │
│                                                │
│  MEASUREMENTS                        Last: Sat │
│  Chest      112.0 cm    ▼ −0.5                 │
│  Waist      104.0 cm    ▼ −1.5                 │
│  Arms L/R    38.5 / 38.8 cm   ▲ +0.2           │
│  Thighs L/R  63.0 / 63.2 cm   ▬  0.0           │
│  Neck        41.0 cm    ▬  0.0                 │
│                                                │
│  PROGRESS PHOTOS                    [ + Add ]  │
│  ┌──────┐ ┌──────┐ ┌──────┐                    │
│  │ Wk 0 │ │ Wk 4 │ │ Wk 8 │   [ Compare ]      │
│  └──────┘ └──────┘ └──────┘                    │
└────────────────────────────────────────────────┘
```

---

## Screen 10 — Plan: Calendar (`/plan`)

```
┌────────────────────────────────────────────────┐
│  Plan                    [Calendar][Tasks]  ⋯  │  segmented
│                                                │
│  ◀  AUGUST 2026                          ▶     │
│  M   T   W   T   F   S   S                     │
│ 24  25  26  27 [28] 29  30                     │
│  ●   ●   ●   ●   ●   ○   ○                     │
│                                                │
│  FRIDAY 28 AUGUST                              │
│  ───────────────────────────────────────────   │
│  08 ─                                          │
│  09 ─ ┃ Breakfast              ▎lifedna        │  LifeDNA blocks: hatched
│  10 ─ │                                        │
│  11 ─ ┃━━━━━━━━━━━━━━━━━━┓                     │
│       ┃ Data Structures   ┃  Lecture Hall B    │  external: solid, cal colour
│  12 ─ ┃ 11:00 – 12:30     ┃                    │
│  13 ─ ┃ Lunch             ▎lifedna             │
│  14 ─ ┃━━━━━━━━━┓                              │
│       ┃ Standup ┃                              │
│  15 ─ ┗━━━━━━━━━┛                              │
│  16 ─ ┃ Pre-workout       ▎lifedna             │
│  17 ─ ┃━━━━━━━━━━━━━━━━━━━━━━━━━━━━━┓          │
│       ┃ Shift                        ┃          │
│  18 ─ ┃  ⚠ overlaps PUSH 18:00–19:15 ┃          │  conflict warning
│  19 ─ ┗━━━━━━━━━━━━━━━━━━━━━━━━━━━━━┛          │
│  20 ─                                          │
│                                                │
│  ⚠ Your 18:00 session overlaps Shift           │
│  [ Move to 19:30 ]  [ Shorten to 45m ] [ Keep ]│
│                                    ┌─────────┐ │
│                                    │    +    │ │
│                                    └─────────┘ │
└────────────────────────────────────────────────┘
```

---

## Screen 11 — Plan: Tasks (`/plan` → Tasks)

```
┌────────────────────────────────────────────────┐
│  Plan                    [Calendar][Tasks]  ⋯  │
│                                                │
│  [ Today ] [ Upcoming ] [ Categories ] [ Done ]│
│                                                │
│  OVERDUE                                       │
│  ▌○  Reply to supervisor email                 │  danger left bar
│      Work · due yesterday 17:00                │
│                                                │
│  TODAY                              3 tasks    │
│  ▌○  Submit DS assignment                      │  P1 = primary bar
│      University · 17:00 · ~90 min · 1/3 subtasks│
│  ▌○  Order creatine                            │
│      Personal · 6 days of supply left          │
│  ▌○  Review sprint board                       │
│      Work · 20:00                              │
│                                                │
│  COMPLETED TODAY                     5         │
│  ✓  Morning weigh-in                           │  strikethrough, 60 % opacity
│  ✓  Log breakfast                              │
│                                                │
│                                    ┌─────────┐ │
│                                    │    +    │ │
│                                    └─────────┘ │
└────────────────────────────────────────────────┘

QUICK ADD SHEET
┌────────────────────────────────────────────────┐
│  ┌──────────────────────────────────────────┐  │
│  │ submit ds assignment friday 5pm p1 #uni  │  │
│  └──────────────────────────────────────────┘  │
│  Parsed:                                       │
│  [ Submit ds assignment ] [Fri 17:00] [P1] [Uni]│  editable chips
│  ┌──────────────────────────────────────────┐  │
│  │                  Add task                │  │
│  └──────────────────────────────────────────┘  │
└────────────────────────────────────────────────┘
```

---

## Screen 12 — AI Assistant Hub (`/ai`)

```
┌────────────────────────────────────────────────┐
│ ←  AI Hub                              [ + ]   │
│                                                │
│  ┌──────┐ ┌──────┐ ┌──────┐ ┌──────┐           │
│  │  ✦   │ │  ◈   │ │  ⊞   │ │ AUTO │           │  assistant selector
│  │Coach │ │Claude│ │Copilot│ │  ●   │           │  AUTO selected by default
│  └──────┘ └──────┘ └──────┘ └──────┘           │
│                                                │
│  SUGGESTED                                     │
│  ┌────────────────────────────────────────┐    │
│  │ Why did my recovery drop this week?    │    │
│  ├────────────────────────────────────────┤    │
│  │ What should I eat to hit 200 g protein?│    │
│  ├────────────────────────────────────────┤    │
│  │ Am I ready to add weight to incline?   │    │
│  └────────────────────────────────────────┘    │
│                                                │
│  RECENT                                        │
│  ✦  Why is my bench stalling?                  │
│     Coach · 8 messages · 2 h ago               │
│  ⊞  Draft the sprint update                    │
│     Copilot · 4 messages · yesterday           │
│  ◈  Summarise this lecture PDF                 │
│     Claude · 12 messages · 3 days ago          │
└────────────────────────────────────────────────┘

CONVERSATION (/ai/:conversationId)
┌────────────────────────────────────────────────┐
│ ←  Why is my bench stalling?    ✦ Coach   ⋯    │
│                                                │
│                    ┌─────────────────────────┐ │
│                    │ Why is my bench         │ │  user, right, primaryMuted
│                    │ stalling?               │ │
│                    └─────────────────────────┘ │
│                                                │
│  ┌──────────────────────────────────────────┐  │
│  │ ✦ Three things in your data:             │  │  assistant, left, surface
│  │                                          │  │
│  │ 1. Volume is flat. Chest volume has sat  │  │
│  │    at ~5,300 kg for three weeks.         │  │
│  │ 2. Sleep is down 14 % (6 h 04 m avg vs   │  │
│  │    your 7 h 03 m baseline).              │  │
│  │ 3. You've hit your 200 g protein floor   │  │
│  │    on 2 of the last 7 days.              │  │
│  │                                          │  │
│  │ The fastest lever is sleep. Strength     │  │
│  │ regression tracks your sleep drop by     │  │
│  │ about 5 days.                            │  │
│  │                                          │  │
│  │ [ Context used ⓘ ]        👍  👎  ⧉      │  │
│  └──────────────────────────────────────────┘  │
│                                                │
│  ┌──────────────────────────────────────────┐  │
│  │ ⚡ Suggested action                       │  │  tool-call confirmation
│  │ Set a sleep reminder for 22:30?          │  │
│  │ [ Confirm ]  [ Edit ]  [ Cancel ]        │  │
│  └──────────────────────────────────────────┘  │
│                                                │
│ ┌────────────────────────────────────┐  ┌────┐ │
│ │ Ask anything…                      │  │ ➤  │ │
│ └────────────────────────────────────┘  └────┘ │
└────────────────────────────────────────────────┘

CONTEXT SHEET  ("What was sent")
┌────────────────────────────────────────────────┐
│  Context sent to Coach                         │
│  ────────────────────────────────────────      │
│  Profile      21 y · 89.4 kg · 174.5 cm        │
│  Goal         cut · target 84–86 kg            │
│  Targets      2,600/2,350 kcal · 200 g protein │
│  Today        2,412 kcal · 168 g P             │
│  Training 7d  4 sessions · 58,300 kg volume    │
│  Bench 8 sess e1RM 40.0 → 43.3 kg              │
│  Sleep 7d     6 h 04 m avg (baseline 7 h 03 m) │
│  Recovery 7d  74 avg                           │
│  Calendar     3 events in the next 24 h        │
│                                                │
│  ~1,840 tokens                                 │
│  [ Disable context for this conversation ]     │
└────────────────────────────────────────────────┘
```

---

## Screen 13 — Supplements (`/me/supplements`)

```
┌────────────────────────────────────────────────┐
│ ←  Supplements                       [ + ]     │
│                                                │
│  TODAY                              4 of 5     │
│  ▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓░░░░░░                │
│                                                │
│  ✓  Multivitamin        1 tablet   09:00       │
│  ✓  Vitamin D3          4000 IU    09:00       │
│  ✓  Omega-3             1 g EPA    13:00       │
│  ✓  Creatine mono       5 g        19:30       │
│  ○  Magnesium glycinate 400 mg     22:30  [Log]│  amber, pending
│                                                │
│  ── MY STACK ──────────────────────────────    │
│  Creatine monohydrate                          │
│  5 g · daily · post-workout                    │
│  Stock ▓▓▓▓▓▓▓▓▓▓▓▓░░░░  62 servings (12 d)    │
│  Compliance 97 % (30 d)                        │
│                                                │
│  Vitamin D3                                    │
│  4000 IU · daily · breakfast                   │
│  Stock ▓▓▓░░░░░░░░░░░░░  9 servings (9 d)  ⚠   │  low-stock warning
│  Compliance 93 % (30 d)                        │
│  [ Log purchase ]                              │
│                                                │
│  ── OVERALL ───────────────────────────────    │
│  30-day compliance      94 %                   │
│  Monthly spend          1,240 EGP              │
│  Cost per day           41 EGP                 │
└────────────────────────────────────────────────┘
```

---

## Screen 14 — Analytics Center (`/me/analytics`)

```
┌────────────────────────────────────────────────┐
│ ←  Analytics          [Week][Month][Quarter]   │
│                                                │
│  WEEK 35 · 24–30 AUGUST                        │
│                                                │
│ ┌──────────────┐┌──────────────┐┌────────────┐ │
│ │ WEIGHT       ││ SESSIONS     ││ VOLUME     │ │
│ │ −0.7 kg      ││ 6            ││ 84,200 kg  │ │
│ │ ▼ on target  ││ ▲ +1         ││ ▲ +6.4 %   │ │
│ └──────────────┘└──────────────┘└────────────┘ │
│ ┌──────────────┐┌──────────────┐┌────────────┐ │
│ │ SLEEP AVG    ││ RECOVERY AVG ││ PROTEIN    │ │
│ │ 7h 01m       ││ 78           ││ 186 g avg  │ │
│ │ ▼ −15 min    ││ ▲ +4         ││ ▲ +12 g    │ │
│ └──────────────┘└──────────────┘└────────────┘ │
│                                                │
│  VOLUME BY MUSCLE                              │
│  Chest      ████████████████  18,400 kg        │
│  Back       ██████████████████ 21,200 kg       │
│  Legs       ████████████████████ 24,100 kg     │
│  Shoulders  ██████████  11,300 kg              │
│  Arms       ████████  9,200 kg                 │
│                                                │
│  STRENGTH PROGRESSION (e1RM)                   │
│  Incline DB Press   40.0 → 43.3   ▲ 8.3 %      │
│  Barbell Squat     102.5 → 105.0  ▲ 2.4 %      │
│  Deadlift          140.0 → 140.0  ▬ 0.0 %      │
│                                                │
│  CONSISTENCY                                   │
│  Nutrition logged      7/7  ████████████████   │
│  Protein floor hit     3/7  ███████░░░░░░░░░   │
│  Supplements           94 % ███████████████░   │
│  Tasks completed       79 % ████████████░░░░   │
│                                                │
│  [ View full report ]      [ Export data ]     │
└────────────────────────────────────────────────┘
```

---

## Screen 15 — Settings (`/me/settings`)

```
┌────────────────────────────────────────────────┐
│ ←  Settings                                    │
│                                                │
│  ┌──┐  Youssef Osman                           │
│  │◉ │  fabtopia1@gmail.com                     │
│  └──┘  Pro · renews 12 Sep            [ Edit ] │
│                                                │
│  GOALS & TARGETS                               │
│  Goal mode                    Cut          ›   │
│  Calorie & macro targets      2,600 / 2,350 ›  │
│  Protein floor                200 g        ›   │
│  Water target                 3,500 ml     ›   │
│                                                │
│  INTEGRATIONS                                  │
│  Health Connect          ✓ Connected · 2m  ›   │
│  Galaxy Fit 3            ✓ Connected · 74 % ›  │
│  Google Calendar         ✓ 3 calendars     ›   │
│  Outlook Calendar        Not connected     ›   │
│                                                │
│  NOTIFICATIONS                                 │
│  All notifications             [ ●━━ ]         │
│  Quiet hours              23:00 – 07:00    ›   │
│  Daily limit                   9           ›   │
│  Per-category settings                     ›   │
│                                                │
│  AI                                            │
│  Default assistant             Auto        ›   │
│  Context injection             [ ●━━ ]         │
│  Daily token budget       60,000 · 22 % used › │
│                                                │
│  APPEARANCE                                    │
│  Theme                         Dark        ›   │
│  Units                    kg · cm · ml     ›   │
│  Dashboard layout                          ›   │
│                                                │
│  PRIVACY & DATA                                │
│  Export my data                            ›   │
│  Privacy settings                          ›   │
│  Delete account                            ›   │  danger text
│                                                │
│  ABOUT                                         │
│  Version 1.0.0 (build 142)                     │
│  Terms · Privacy · Health disclaimer           │
└────────────────────────────────────────────────┘
```

---

## 16. Responsive behaviour

| Screen | `medium` (600–839) | `expanded` (≥ 840) |
|---|---|---|
| Dashboard | 2-column card grid; Next Action spans full width | 3-column; nav rail replaces bottom bar |
| Nutrition | Meal list + day summary side by side | + persistent food-search panel |
| Live Gym | Set entry left, set list right | Same, larger type — never a 3-column layout |
| Calendar | Day + agenda side by side | Week grid + day detail |
| AI Hub | Conversation list + thread | + context inspector panel |

**Live Gym never adapts beyond two columns.** Its ergonomics are the feature.

---

## 17. Screen inventory

| # | Route | Module | Phase |
|---|---|---|---|
| 01 | `/home` | Dashboard | MVP |
| 02 | `/nutrition` | Nutrition | MVP |
| 03 | `/nutrition/log` | Nutrition | MVP |
| 04 | `/nutrition/scan` | Nutrition | MVP |
| 05 | `/nutrition/planner` | Nutrition | Phase 2 |
| 06 | `/nutrition/shopping-list` | Nutrition | Phase 2 |
| 07 | `/train` | Workout | MVP |
| 08 | `/train/templates` | Workout | MVP |
| 09 | `/train/template/:id` | Workout | MVP |
| 10 | `/train/exercise/:id` | Workout | MVP |
| 11 | `/train/history` | Workout | MVP |
| 12 | `/train/programs` | Workout | MVP |
| 13 | `/live/:sessionId` | Live Gym | MVP |
| 14 | `/plan` (Calendar) | Calendar | MVP |
| 15 | `/plan` (Tasks) | Tasks | MVP |
| 16 | `/plan/task/:id` | Tasks | MVP |
| 17 | `/plan/event/:id` | Calendar | MVP |
| 18 | `/ai` | AI Hub | MVP |
| 19 | `/ai/:conversationId` | AI Hub | MVP |
| 20 | `/me` | Profile hub | MVP |
| 21 | `/me/body` | Body | Phase 2 |
| 22 | `/me/recovery` | Recovery | Phase 2 |
| 23 | `/me/supplements` | Supplements | MVP |
| 24 | `/me/analytics` | Analytics | Phase 2 |
| 25 | `/me/settings/*` | Settings | MVP |
| 26 | `/insight/:id` | FitnessDNA | Phase 3 |
| 27 | `/onboarding/*` | Onboarding | MVP |
| 28 | `/auth/*` | Auth | MVP |
