# LifeDNA OS — Design System

**Version:** 1.0
**Codename:** *Obsidian*
**Owner:** Design Lead

---

## 1. Design philosophy

LifeDNA OS is a **control surface for a human being**. It should feel like the instrument
panel of something precise and expensive — not like a lifestyle app.

### The five rules

| # | Rule | In practice |
|---|---|---|
| 1 | **Dark is the ground state.** | The default theme is near-black. Light theme exists and is complete, but every design decision is made in dark first. In a gym at 19:00, dark is not a preference — it is legibility. |
| 2 | **Data is the decoration.** | No illustrations, no mascots, no gradients-for-their-own-sake. The only colour on a screen should be carrying information. |
| 3 | **One thing is the most important thing.** | Every screen has exactly one visual apex. On the dashboard it is the Next Action card. If two things compete, one is wrong. |
| 4 | **Numbers are typography.** | Metrics are set large, tabular and tight. A number is a headline, not body text. |
| 5 | **Motion explains, never entertains.** | Animation communicates causality (this became that) or state (this is loading). Anything else is deleted. |

### Influences, and what we take from each

- **Samsung One UI** — the top-third/bottom-two-thirds split. Content and identity live up
  top; the hand operates down below. This is the single most important ergonomic decision
  in the product and it drives the Live Gym layout.
- **Apple Health** — rings as the universal progress primitive, and the discipline of a
  single metric per card.
- **WHOOP** — the courage to reduce a day to one number, and to defend that number with a
  transparent breakdown.
- **Linear / Notion** — the density and keyboard-grade efficiency of the task and planning
  surfaces.

---

## 2. Colour

### 2.1 Brand palette

| Token | Hex | Role |
|---|---|---|
| `primary` | `#0066FF` | The brand blue. Primary actions, active state, key data emphasis. |
| `secondary` | `#00D1B2` | Teal. Recovery, hydration, positive physiological signal. |
| `accent` | `#FFB800` | Amber. Attention, streaks, PRs, caution-not-yet-danger. |

### 2.2 Full dark theme scale (default)

```
── Surfaces ──────────────────────────────────────────────────────────
bg              #05070D   app background (near-black, cool)
surface         #0A0E17   base card
surfaceElevated #111725   raised card, sheets
surfaceHighest  #18202F   menus, dialogs, pressed cards
scrim           #000000 @ 64%

── Borders & dividers ────────────────────────────────────────────────
border          #1C2536   default hairline (1px)
borderStrong    #2A3547   emphasised container
borderFocus     #0066FF   focus ring

── Text ──────────────────────────────────────────────────────────────
textPrimary     #F2F5FA   headings, metric values
textSecondary   #9BA8BE   supporting copy
textTertiary    #61708A   labels, captions, axis text
textDisabled    #3A455A
textOnPrimary   #FFFFFF

── Brand ─────────────────────────────────────────────────────────────
primary         #0066FF
primaryHover    #1F7BFF
primaryPressed  #0052CC
primaryMuted    #0066FF @ 12%   (chips, selected rows)
secondary       #00D1B2
secondaryMuted  #00D1B2 @ 12%
accent          #FFB800
accentMuted     #FFB800 @ 12%

── Semantic ──────────────────────────────────────────────────────────
success         #22C55E
warning         #FFB800
danger          #FF4D5E
info            #38BDF8

── Data / macro encoding (FIXED — never reassign) ────────────────────
calories        #0066FF
protein         #00D1B2
carbs           #FFB800
fat             #FF7A45
water           #38BDF8

── Recovery bands ────────────────────────────────────────────────────
recoveryLow     #FF4D5E     0–33
recoveryMod     #FFB800     34–66
recoveryHigh    #22C55E     67–100

── Muscle heat (analytics) ───────────────────────────────────────────
heat0 #18202F · heat1 #0E3A66 · heat2 #0052CC · heat3 #0066FF · heat4 #4D9AFF
```

### 2.3 Light theme scale

```
bg #F5F7FB · surface #FFFFFF · surfaceElevated #FFFFFF · surfaceHighest #EEF2F8
border #E2E8F2 · borderStrong #CBD5E5
textPrimary #0A0E17 · textSecondary #4A5568 · textTertiary #718096
primary #0052CC (darkened for AA on white) · secondary #00A88F · accent #B37F00
success #16A34A · warning #B37F00 · danger #DC2626 · info #0284C7
```

Semantic tokens are identical in name across themes; only values change. **No widget ever
references a hex literal** — all colour comes from `Theme.of(context).extension<LifeDnaColors>()`.

### 2.4 Contrast compliance

| Pair | Ratio | Verdict |
|---|---|---|
| `textPrimary` on `bg` | 16.8:1 | AAA |
| `textSecondary` on `surface` | 7.4:1 | AAA |
| `textTertiary` on `surface` | 4.6:1 | AA (body-size minimum honoured; used ≥ 12sp only) |
| `primary` on `bg` | 5.2:1 | AA |
| `textOnPrimary` on `primary` | 5.9:1 | AA |
| `danger` on `surface` | 5.1:1 | AA |

Rule: `textTertiary` is never used below 12 sp and never for interactive labels.

---

## 3. Typography

**Families**
- **UI / body:** `Inter` (variable). Fallback: Roboto → system sans.
- **Numerals / metrics:** `Inter` with `fontFeatures: [tnum, ss01]` — tabular figures so a
  changing number never causes layout shift.
- **Technical labels:** `JetBrains Mono`, uppercase, wide tracking. Used for section
  eyebrows (`SLIDE 02 / TRAINING SYSTEM` style), unit suffixes and data provenance.

**Scale**

| Token | Size / Line | Weight | Tracking | Use |
|---|---|---|---|---|
| `displayXL` | 56 / 56 | 800 | −2 % | Hero metric (recovery score, live-gym weight) |
| `displayL` | 44 / 46 | 800 | −2 % | Screen hero number |
| `displayM` | 34 / 38 | 700 | −1.5 % | Card primary metric |
| `headlineL` | 28 / 34 | 700 | −1 % | Screen title |
| `headlineM` | 22 / 28 | 700 | −0.5 % | Section title |
| `titleL` | 18 / 24 | 600 | 0 | Card title |
| `titleM` | 16 / 22 | 600 | 0 | List row title |
| `bodyL` | 16 / 24 | 400 | 0 | Body copy |
| `bodyM` | 14 / 20 | 400 | 0 | Default body |
| `bodyS` | 13 / 18 | 400 | 0 | Supporting |
| `label` | 12 / 16 | 600 | +2 % | Field labels |
| `labelMono` | 11 / 14 | 500 | +8 % | UPPERCASE eyebrows, units, provenance |
| `caption` | 11 / 14 | 400 | 0 | Timestamps, footnotes |

**Metric composition pattern** — a value and its unit are one visual object:

```
   89.4 kg          ← value: displayM, textPrimary, tnum
   WEIGHT           ← unit:  labelMono, textTertiary, baseline-aligned to value
```

---

## 4. Spacing, radius, elevation

### 4.1 Spacing — 4 pt base

```
space1  4      space2  8      space3  12     space4  16
space5  20     space6  24     space7  32     space8  40
space9  48     space10 64     space11 80     space12 96
```

**Rules**
- Screen horizontal padding: `space4` (16). Never less.
- Card internal padding: `space4` (16); dense list rows `space3` (12).
- Vertical rhythm between cards: `space3` (12).
- Between sections: `space6` (24).
- Bottom safe area + `space10` (64) of scroll padding on every scrollable screen, so the
  last item clears the navigation bar and the FAB.

### 4.2 Radius

```
radiusXS   6    chips, badges, small inputs
radiusS   10    buttons, input fields
radiusM   16    cards            ← the signature radius
radiusL   24    sheets, modals, hero cards
radiusXL  32    full-bleed feature panels
radiusFull 999  pills, avatars, rings
```

### 4.3 Elevation

Dark UI cannot rely on shadows. Elevation is expressed as **surface lightness + border**,
with shadow used only for genuinely floating layers.

| Level | Surface | Border | Shadow | Use |
|---|---|---|---|---|
| 0 | `bg` | — | none | Page |
| 1 | `surface` | `border` | none | Standard card |
| 2 | `surfaceElevated` | `border` | none | Raised / selected card |
| 3 | `surfaceElevated` | `borderStrong` | `0 8 24 rgba(0,0,0,.40)` | Bottom sheet, dialog |
| 4 | `surfaceHighest` | `borderStrong` | `0 16 40 rgba(0,0,0,.55)` | Menu, popover, FAB |

---

## 5. Glassmorphism

Used **sparingly and only where a layer floats over content**. Never on a static card —
blur is expensive and, applied everywhere, it destroys legibility.

**Permitted surfaces:** bottom navigation bar, Live Gym rest-timer overlay, sticky sheet
headers, the floating "Resume workout" banner, AI streaming overlay.

```
Glass recipe (dark):
  background : surfaceElevated @ 72 %
  backdrop   : BackdropFilter(blur σ = 18)
  border     : 1px  #FFFFFF @ 8 %      (top edge only where the layer meets content)
  highlight  : 1px inset top  #FFFFFF @ 6 %
  shadow     : 0 −4 24 rgba(0,0,0,.35)

Light:
  background : #FFFFFF @ 76 %, blur σ = 18, border 1px #0A0E17 @ 6 %
```

**Performance guard:** at most **one** `BackdropFilter` in the widget tree at any time.
`RepaintBoundary` wraps every glass surface. If `MediaQuery.disableAnimations` is true or
the device reports low-end status, glass falls back to an opaque `surfaceElevated`.

---

## 6. Motion

### 6.1 Duration and easing

| Token | Duration | Curve | Use |
|---|---|---|---|
| `instant` | 80 ms | `easeOut` | Press feedback, toggles |
| `fast` | 150 ms | `easeOutCubic` | Chips, small reveals, tooltips |
| `standard` | 250 ms | `easeOutCubic` | Screen transitions, card expand |
| `slow` | 400 ms | `easeInOutCubic` | Sheets, hero transitions |
| `ring` | 800 ms | `easeOutQuart` | Progress-ring fill |
| `count` | 600 ms | `easeOutExpo` | Number roll-up |

### 6.2 Signature motions

- **Ring fill** — on first paint a ring sweeps from 0 to value over 800 ms. On update it
  animates only the delta. Never re-sweeps from zero on a rebuild.
- **Number roll** — metric values tween digit-by-digit with tabular figures, so width is
  constant and nothing jumps.
- **Set completion (Live Gym)** — the completed row collapses upward over 200 ms while the
  rest timer expands from the button's position. One continuous gesture of causality.
- **PR celebration** — a single amber pulse from the set row outward, 600 ms, no confetti,
  no modal. It must never interrupt the next set.
- **Card entrance** — staggered 40 ms per card, 12 px upward translate + fade. Applied on
  first dashboard load only, never on refresh.

### 6.3 Reduce-motion

When `MediaQuery.of(context).disableAnimations` is true: all durations become 0, rings
paint at final value, numbers set directly, staggering is removed. Every screen must be
verified in this mode — it is a supported configuration, not a degraded one.

---

## 7. Iconography

- **Library:** Material Symbols Rounded, weight 400, grade 0, optical size 24.
- **Sizes:** 16 (inline), 20 (list), 24 (default), 32 (card header), 48 (empty state).
- **Rule:** an icon never appears alone as a control unless it has a semantic label and a
  ≥ 48 dp target. Bottom-nav icons always carry text labels.

**Module icons (fixed):**
`dashboard` grid_view · `nutrition` restaurant · `water` water_drop ·
`supplements` medication · `workout` fitness_center · `live` bolt ·
`body` monitor_weight · `recovery` favorite · `sleep` bedtime ·
`calendar` calendar_month · `tasks` checklist · `ai` auto_awesome ·
`insights` lightbulb · `analytics` insights · `settings` settings

---

## 8. Component library

Every component below is implemented in `app/lib/core/widgets/`.

### 8.1 `LdCard`

The universal container.

```
┌─────────────────────────────────────────────┐
│  ▎LABEL                              action │   ← optional accent bar + eyebrow + trailing
│                                             │
│  Content                                    │
│                                             │
└─────────────────────────────────────────────┘
radius 16 · padding 16 · surface level 1 · 1px border
optional 3px leading accent bar (module colour)
```
Variants: `standard`, `elevated`, `interactive` (adds press scale 0.985 + level 2),
`accent` (leading bar), `glass`.

### 8.2 `LdMetricTile`

```
┌───────────────────────┐
│ PROTEIN               │  labelMono / textTertiary
│ 168 g                 │  displayM / textPrimary (tnum)
│ ▁▂▄▆█ ▁▂  −32 g       │  sparkline + delta chip
└───────────────────────┘
```
Props: `label`, `value`, `unit`, `delta`, `deltaDirection`, `sparkline`, `accentColor`,
`onTap`. Delta direction is semantic (`good`/`bad`/`neutral`), **not** literal sign — for
weight in a cut, negative is good.

### 8.3 `LdProgressRing`

The core nutrition/goal primitive.

```
        ╭───────────╮
      ╱      168      ╲        value       displayM
     │       / 200     │       target      bodyS textTertiary
     │      PROTEIN    │       label       labelMono
      ╲               ╱
        ╰───────────╯
stroke 12 · track #1C2536 · cap round · start −90° · sweep clockwise
over-target: the arc continues past 100 % in a lighter tint of the same hue
```
Sizes: `s` 64, `m` 96, `l` 128, `xl` 168. Semantics label reads
`"Protein, 168 of 200 grams, 84 percent"`.

### 8.4 `LdMacroRingCluster`

Dashboard hero. One large calories ring with three satellites (protein, carbs, fat).
Layout: on ≥ 380 dp width the satellites sit in a row beneath; below that they wrap 2 + 1.

### 8.5 `LdNextActionCard`

The most important component in the product.

```
┌─────────────────────────────────────────────┐
│ ▎NEXT                                       │
│                                             │
│  You are 32 g below your protein target     │  titleL, 2-line max
│  4 h until bed · a 40 g snack closes it     │  bodyS textSecondary
│                                             │
│  ┌───────────────────┐  ┌────────────────┐  │
│  │   Log protein     │  │      Why?      │  │  primary + ghost
│  └───────────────────┘  └────────────────┘  │
└─────────────────────────────────────────────┘
Accent bar colour = the domain of the action.
"Why?" opens the provenance sheet. It is never optional.
```

### 8.6 `LdSetRow` (Live Gym)

```
┌─────────────────────────────────────────────────────┐
│  2   │  32.5 kg  │  10 reps  │  RPE 8  │      ✓     │
│ set  │  − 32.5 + │  − 10 +   │  chips  │  complete  │
│      │  prev 30.0 × 10                              │
└─────────────────────────────────────────────────────┘
height 72 · steppers are 48×48 targets · previous values in textTertiary
completed rows collapse to a 44 dp summary and dim to 60 % opacity
```

### 8.7 `LdRestTimer`

Full-width glass overlay anchored to the bottom.

```
┌─────────────────────────────────────────────┐
│               1:34                          │  displayXL, tnum, 56sp+
│      ▓▓▓▓▓▓▓▓▓▓▓▓░░░░░░░░  linear progress  │
│   [ −15 s ]      [ Skip ]      [ +15 s ]    │  each ≥ 56 dp tall
│   Next: Cable Fly · 3 × 12                  │  bodyS textSecondary
└─────────────────────────────────────────────┘
```

### 8.8 `LdPrimaryButton`

| Size | Height | Radius | Text |
|---|---|---|---|
| `s` | 40 | 10 | titleM |
| `m` | 52 | 12 | titleM |
| `l` | 64 | 16 | titleL |
| `xl` (Live Gym) | 72 | 18 | headlineM |

States: default / hover / pressed (scale 0.98) / loading (inline spinner, label retained) /
disabled (surface `surfaceHighest`, text `textDisabled`). A loading button never changes
width.

### 8.9 Other components

| Component | Purpose |
|---|---|
| `LdSegmentedControl` | Day/Week/Month, Training/Rest, Calendar views |
| `LdChip` | Filters, RPE selection, tags. Selected = `primaryMuted` fill + `primary` text |
| `LdSheet` | Bottom sheet: 24 radius top, drag handle, sticky header, glass header on scroll |
| `LdEmptyState` | 48 icon + headline + body + one primary action. Copy is always specific |
| `LdSkeleton` | Shimmer placeholders matching the final layout exactly (no layout shift) |
| `LdSparkline` | 7/28-point line, no axes, 24 dp tall, current point emphasised |
| `LdBarChart` | Weekly volume, macro history. Rounded 4 dp caps, value on tap |
| `LdLineChart` | Weight/recovery trends. Raw points at 30 % + EWMA line at 100 % |
| `LdCalendarStrip` | Horizontal 7-day selector with per-day status dots |
| `LdListRow` | 56 dp, leading icon/avatar, title, subtitle, trailing value/chevron |
| `LdBanner` | Inline info/warning/error. Never a toast for anything actionable |
| `LdSyncBadge` | Offline / syncing / synced with last-sync time |
| `LdProvenanceSheet` | Renders an insight's evidence: signals, rule, window, engine version |

---

## 9. Layout system

### 9.1 Breakpoints

| Name | Width | Behaviour |
|---|---|---|
| `compact` | < 600 | Single column. The design target. |
| `medium` | 600–839 | Two-column dashboard grid; sheets become dialogs. |
| `expanded` | ≥ 840 | Nav rail replaces bottom bar; three-column planning view. |

### 9.2 The One UI vertical split

```
┌──────────────────────────────┐  ▲
│                              │  │  UPPER THIRD — identity & context
│   Greeting / screen title    │  │  Large type, generous space, non-interactive
│   Date · sync state          │  ▼
├──────────────────────────────┤
│                              │  ▲
│   Primary content            │  │
│   (scrollable)               │  │  LOWER TWO THIRDS — everything the thumb touches
│                              │  │  Primary actions live in the bottom 40 %
│   [ Primary action ]         │  ▼
└──────────────────────────────┘
```

### 9.3 Bottom navigation

Five destinations, glass surface, 64 dp + safe area, icon + label always visible.
`Home · Nutrition · Train · Plan · Me`
The **Train** tab shows a live indicator dot when a session is in progress; tapping it
during a session goes straight to Live Gym Mode.

---

## 10. Content and voice

### 10.1 Voice

Direct, specific, second person, never cute. The product is a coach with a clipboard, not
a friend with an opinion.

| Do | Don't |
|---|---|
| "You are 32 g below your protein target." | "Oops! Looks like you might need more protein 💪" |
| "Recovery 42 — reduce today's volume by 30 %." | "Take it easy today, champ!" |
| "Sleep averaged 6 h 12 m this week, down 14 %." | "Your sleep could be better." |
| "Add 2.5 kg to incline bench." | "Maybe try going a little heavier?" |

### 10.2 Number formatting

| Quantity | Format | Example |
|---|---|---|
| Weight (body) | 1 decimal | `89.4 kg` |
| Weight (load) | 1 decimal, trailing `.0` dropped | `32.5 kg`, `30 kg` |
| Calories | integer, thousands separator | `2,412 kcal` |
| Macros | integer | `168 g` |
| Volume | integer with `k` above 10 000 | `14.8k kg` |
| Percentage | integer, 1 decimal only below 10 % | `84 %`, `8.2 %` |
| Duration | `1h 13m` / `4:31` for timers | |
| Scores | integer, no unit | `82` |
| Deltas | always signed, semantic colour | `+2.5 kg`, `−0.7 kg` |

### 10.3 Empty states

Every empty state names the value, not the void.

- Nutrition: **"Nothing logged yet today."** / "Your first meal takes about 12 seconds." / `Log breakfast`
- Workouts: **"No sessions yet."** / "Start from a template and we'll pre-fill everything you lifted last time." / `Browse templates`
- Recovery: **"Not enough data for a recovery score."** / "Connect a health source, or log sleep manually for two nights." / `Connect Health Connect`
- Insights: **"No insights yet."** / "Insights start after 7 days of data. You're on day 3." / (no action — a progress bar instead)

### 10.4 Error copy

State what happened, what it means, and what to do. Never surface a code alone.

- "Couldn't reach the server. Your workout is saved on this phone and will sync automatically." → `Retry`
- "Calendar access expired. Reconnect to keep your schedule in sync." → `Reconnect`
- "That barcode isn't in the database yet. Add it once and it's yours forever." → `Create food`

---

## 11. Accessibility specification

| Requirement | Implementation |
|---|---|
| Touch targets | 48 dp minimum; 64 dp in Live Gym; 8 dp minimum gap between adjacent targets |
| Screen reader | Every interactive widget has `Semantics(label:, hint:, value:)`. Rings announce `"<label>, <value> of <target> <unit>, <pct> percent"`. Charts expose a text summary. |
| Text scaling | Verified to 200 %. Cards grow vertically; no `maxLines: 1` on user-facing content without an ellipsis + tooltip. Metric values may shrink one step at ≥ 160 %. |
| Colour independence | Recovery bands carry a label *and* an icon. Macro rings carry text labels. Delta chips carry ▲/▼. |
| Focus | Visible 2 px `borderFocus` ring on every focusable element; logical traversal order. |
| Motion | `disableAnimations` fully honoured (§6.3). |
| Contrast | §2.4 enforced by a golden test that samples rendered pixel pairs. |
| Haptics | Meaningful only: set complete (medium), rest end (heavy), PR (double medium), destructive confirm (heavy). Respects system haptic settings. |

---

## 12. Theming implementation

```dart
// app/lib/core/theme/ld_colors.dart
@immutable
class LdColors extends ThemeExtension<LdColors> {
  final Color bg, surface, surfaceElevated, surfaceHighest;
  final Color border, borderStrong, borderFocus;
  final Color textPrimary, textSecondary, textTertiary, textDisabled;
  final Color primary, secondary, accent;
  final Color success, warning, danger, info;
  final Color calories, protein, carbs, fat, water;
  final Color recoveryLow, recoveryModerate, recoveryHigh;
  // + copyWith / lerp
}

// Usage — the ONLY sanctioned way to obtain a colour
final c = context.ldColors;
Container(color: c.surface);
```

A CI lint (`no_hardcoded_colors`) fails the build on any `Color(0x…)` or `Colors.*`
literal outside `core/theme/`.

---

## 13. Design tokens (machine-readable)

Tokens are authored once in `design/tokens.json` and generated into Dart
(`core/theme/tokens.g.dart`) so design and code cannot drift.

```jsonc
{
  "color": {
    "dark": { "bg": "#05070D", "surface": "#0A0E17", "primary": "#0066FF" },
    "light": { "bg": "#F5F7FB", "surface": "#FFFFFF", "primary": "#0052CC" }
  },
  "space":  { "1": 4, "2": 8, "3": 12, "4": 16, "5": 20, "6": 24, "7": 32, "8": 40 },
  "radius": { "xs": 6, "s": 10, "m": 16, "l": 24, "xl": 32, "full": 999 },
  "duration": { "instant": 80, "fast": 150, "standard": 250, "slow": 400, "ring": 800 },
  "type": {
    "displayXL": { "size": 56, "height": 56, "weight": 800, "tracking": -0.02 },
    "displayM":  { "size": 34, "height": 38, "weight": 700, "tracking": -0.015 }
  }
}
```
