# LifeDNA OS — User Flows

**Version:** 1.0
**Owner:** Product + Design

Notation: `▢` screen · `◇` decision · `▷` system action · `✱` notification ·
`✓` success terminal · `✗` failure terminal

---

## Flow 1 — First run and onboarding

**Goal:** account → populated dashboard in under 180 seconds.

```
▢ Splash
   ▷ check auth state
   ◇ signed in?
      ├─ yes → ◇ onboarding complete?  ├─ yes → ▢ Dashboard  ✓
      │                                └─ no  → ▢ Onboarding step 1
      └─ no  → ▢ Welcome

▢ Welcome  ("Your personal performance operating system")
   ├─ [Create account] → ▢ Sign up
   └─ [Sign in]        → ▢ Sign in

▢ Sign up
   ├─ Continue with Google  ─┐
   ├─ Continue with Apple   ─┤→ ▷ OAuth  → ▷ create user doc → ▢ Onboarding 1
   ├─ Continue with Microsoft┘   (MS additionally offers Calendar scope later,
   │                              NOT at sign-in — incremental consent)
   └─ Email + password → ▷ validate (≥10 chars, breach-checked)
                         → ▷ send verification → ▢ Onboarding 1

▢ Onboarding 1/6  "Who are you"        name · date of birth · sex
▢ Onboarding 2/6  "Your body"          height · current weight · (optional body fat %)
▢ Onboarding 3/6  "Your goal"          ◇ Cut | Maintain | Bulk
                                       → target weight range · target date
                                       ▷ live preview of weekly rate; warn if > 1 %/wk
▢ Onboarding 4/6  "Your week"          training days/week · gym window · activity level
▢ Onboarding 5/6  "Your targets"       ▷ MacroCalculator runs
                                       shows kcal + macros for training/rest days
                                       ├─ [Looks good]  → next
                                       └─ [Adjust]      → editable fields, floors enforced
▢ Onboarding 6/6  "Start focused"      pick up to 2 modules
                                       ▷ others locked with unlock conditions
   ▷ write users/{uid} + settings/* + seed default supplements & program
   ▷ schedule default notifications locally
→ ▢ Dashboard (with a 3-step coach-mark tour)  ✓
```

**Rules**
- Max 3 inputs per screen. Progress bar always visible. Back never loses data.
- Skipping is allowed on steps 2 (body fat), 4 (gym window) and 6 (modules).
- If the computed deficit would exceed the −25 % / −1000 kcal cap, the app clamps it and
  shows: *"We've capped this at a safe rate. Faster loss costs muscle."*

---

## Flow 2 — The daily loop (the product's heartbeat)

```
07:30  ✱ "Recovery 82 — green light. Push day at 18:00."
         └─ tap → ▢ Dashboard

▢ Dashboard
   ├─ NEXT ACTION card  → the single highest-priority action right now
   ├─ Macro rings       → tap → ▢ Nutrition
   ├─ Workout card      → tap → ▢ Today's session
   ├─ Recovery card     → tap → ▢ Recovery detail (component breakdown)
   ├─ Schedule strip    → tap → ▢ Calendar day
   ├─ Tasks card        → tap → ▢ Tasks Today
   └─ Insights          → tap → ▢ Insight detail (provenance)

09:00  ✱ "Time for Meal 1 — eggs, foul, baladi bread"
         ├─ [Log it]  → ▷ applies the planned template → ✓ (0 screens)
         └─ tap body  → ▢ Nutrition log

13:00  ✱ Meal 2 …
16:30  ✱ Meal 3 (pre-workout)
17:15  ✱ "Workout starts in 45 minutes — PUSH, 22 sets"
         └─ [Start] → ▢ Live Gym Mode

18:00–19:15  ▢ Live Gym Mode  (Flow 4)
19:30  ✱ Meal 4 (post-workout) + ✱ "Creatine 5 g"
22:30  ✱ Meal 5 (before bed)
22:45  ✱ ◇ protein < floor?  → "You're 32 g below protein. A 40 g snack closes it."
         └─ [Log Greek yogurt] → ✓
23:00  ✱ "Wind down — target sleep 7.5 h for tomorrow's lower session."

03:00  ▷ recoveryEngine · 03:15 fitnessDnaEngine · 06:00 dailyPlanBuilder
```

**The suppression rule that makes this bearable:** every reminder above is cancelled the
moment its action is satisfied. A user who logs breakfast at 08:40 never sees the 09:00
notification.

---

## Flow 3 — Logging a meal

```
▢ Nutrition Center
   └─ [+] on a meal slot  → ▢ Add food

▢ Add food  (search field focused, keyboard up, 5 tabs)
   ├─ Recent      ← default tab; the user's last 30 distinct foods
   ├─ Favorites
   ├─ Templates   ← saved meals; one tap logs the whole meal
   ├─ Search      ← local index first (≤ 400 ms), remote fallback
   └─ [ Scan ]    → ▢ Barcode scanner

   ◇ result found?
      ├─ yes → ▢ Portion sheet
      └─ no  → ▢ Create food  (name, brand, per-100 g macros, serving sizes)
                 ▷ saved to the user's custom foods AND submitted to the shared cache
                 → ▢ Portion sheet

▢ Portion sheet   (bottom sheet, does not leave the screen)
   ├─ quantity stepper + unit selector (g / ml / serving / piece)
   ├─ live macro preview updating as the number changes
   ├─ meal slot selector (pre-filled from context/time)
   └─ [ Add ]
        ▷ optimistic UI: rings animate immediately
        ▷ Drift insert + outbox enqueue          ← committed here
        ▷ Firestore write (async)
        ▷ trigger updates daily_stats
      → back to ▢ Nutrition Center with the entry in place  ✓

▢ Barcode scanner
   ▷ camera + ML Kit barcode detection
   ◇ resolved?
      ├─ local cache hit → ▢ Portion sheet                       (instant)
      ├─ /foods hit      → ▢ Portion sheet
      ├─ Open Food Facts → ▷ write back to /foods → ▢ Portion sheet
      └─ miss            → ▢ Create food (barcode pre-filled)
```

**Target: ≤ 12 s median for a full meal.** Achieved by: Recent as the default tab,
one-tap templates, pre-filled slot, and never navigating away from the day view.

---

## Flow 4 — Live Gym Mode (the flagship)

```
▢ Dashboard / Workout Center  → [Start workout]
   ◇ session in progress?
      ├─ yes → ▢ Resume prompt ("PUSH · 12 min ago · 6 sets logged")
      └─ no  → ◇ from template or freeform?

▷ Session bootstrap
   • create session doc (status = in_progress) locally
   • for each exercise, read the LAST performed set from Drift → prefill weight/reps
   • acquire wakelock, start the duration clock, register the foreground service

▢ LIVE GYM  (full screen, no bottom nav)
   ┌──────────────────────────────────────────┐
   │ PUSH · 00:12:41              [pause] [⋯] │
   │                                          │
   │ INCLINE DUMBBELL PRESS                   │
   │ Set 2 of 4 · target 8–12 @ RPE 8         │
   │                                          │
   │   32.5 kg              10 reps           │
   │   −  +                 −  +              │
   │   last time: 30.0 kg × 10                │
   │                                          │
   │   RPE  [6][7][8][9][10] [to failure]     │
   │                                          │
   │   ┌────────────────────────────────┐     │
   │   │        COMPLETE SET            │     │  ← 72 dp, thumb zone
   │   └────────────────────────────────┘     │
   │   [ Skip ]   [ Note ]   [ 🎤 ]           │
   │                                          │
   │   Next: Cable Fly · 3 × 12               │
   └──────────────────────────────────────────┘

   [Complete Set]
      ▷ write set to Drift (< 50 ms)  ← COMMIT POINT
      ▷ enqueue outbox op
      ▷ PR check (E1rmCalculator)
      ◇ PR? → ✱ in-line amber pulse "New e1RM: 43.3 kg (+8.3 %)"  (non-blocking)
      ▷ haptic medium
      ▷ start rest timer at exercise.restSeconds
      → ▢ Rest overlay

▢ Rest overlay (glass, over the set list)
   │  1:34    [−15s] [Skip] [+15s]
   │  Next: set 3 of 4 · 32.5 kg × 10
   ├─ timer ends → haptic heavy + optional sound
   │               (+ local notification if backgrounded)
   └─ auto-dismiss → back to the set entry for set 3

   ◇ superset group?  → next exercise in the group loads immediately,
                        rest fires only after the last member of the group
   ◇ drop set?        → [Add drop] appends a sub-set at reduced load under the parent

   [⋯] menu → Add exercise · Reorder · Replace exercise · Plate calculator ·
              Edit rest · Discard session

   [Finish] → ▢ Session summary
              duration · volume · sets · PRs · muscle split
              session RPE selector (required, 1 tap)
              optional note
              [ Save ]
                 ▷ session.status = completed, finishedAt set
                 ▷ outbox flush attempt
                 ▷ (server) onSessionFinalize → PRs, training load, daily_stats
              → ▢ Workout Center  ✓
```

**Offline guarantee:** every step above works in airplane mode. The only thing that waits
is the Firestore write.

**Process death:** state is checkpointed to Drift on every mutation. Relaunch detects
`status == in_progress` and offers Resume from any screen via a persistent banner.

---

## Flow 5 — Connecting a health source

```
▢ Settings → Integrations → [Connect health data]

▢ Explanation screen   (BEFORE the system dialog — this is a hard requirement)
   "LifeDNA reads steps, heart rate and sleep to compute your recovery score.
    We never write your health data anywhere except your own account."
   • per-type list with what each unlocks
   • [ Continue ]  [ Not now ]

▷ Health Connect permission request (system)
   ◇ granted?
      ├─ all      → ▷ backfill 90 days (chunked Cloud Task, resumable)
      ├─ partial  → ▷ proceed; UI states which metrics are unavailable and why
      └─ denied   → ▢ Degraded state: manual sleep/weight entry offered.
                      Recovery card shows "Insufficient data" with a reconnect CTA.

▷ Sync loop
   • foreground / 60-min WorkManager / pull-to-refresh
   • read changes since token → normalize → dedup by idempotencyKey
   • batch commit ≤ 400 records → server dedups again → updates daily_stats
   • store new token

▢ Sync status (Settings → Integrations → Health)
   per data type: last sync · record count · error, with [Retry] and [Full resync]
```

**Galaxy Fit 3 (Phase 2)** adds a BLE pairing sub-flow for live heart rate only; all
historical band data still arrives through Health Connect rather than a re-implemented
proprietary protocol.

---

## Flow 6 — Connecting a calendar

```
▢ Plan tab → [Connect calendar]  →  ◇ Google | Microsoft

Google
  ▷ OAuth (readonly scope first)
  ▷ list calendars → ▢ Calendar picker (multi-select + colour)
  ▷ initial sync: −7 days … +30 days
  → ▢ Calendar day view  ✓
  ◇ user creates/edits an event later
     → ▷ incremental consent for the write scope, explained in context
     → retry the write

Microsoft
  ▷ MSAL auth → Graph /me/calendars → same picker → same sync

▷ Delta sync every 30 min (server, using provider sync tokens)
   ◇ token invalid (410) → ▷ full resync for that calendar, silent to the user
   ◇ auth expired        → ▷ mark account needs_reauth
                           ✱ "Calendar access expired" → [Reconnect]

Conflict detection
   ▷ on plan build: if a planned workout overlaps a busy external event
      → dashboard shows "Your 18:00 session overlaps Lecture (18:00–19:15)"
        [ Move to 19:30 ]  [ Shorten to 45 min ]  [ Keep ]
```

---

## Flow 7 — AI Assistant Hub

```
▢ AI Hub
   ├─ assistant selector:  ✦ Coach  ·  ◈ Claude  ·  ⊞ Copilot  ·  [Auto]
   ├─ suggested prompts, generated from today's state:
   │    "Why did my recovery drop?"  · "What should I eat to hit 200 g?"
   │    "Am I ready to add weight to incline bench?"
   └─ conversation list (pinned, recent, archived)

User sends a message
   ▷ callable aiChat
   ◇ forced provider?
      ├─ yes → use it
      └─ no  → ▷ AiRouter.classify()
                 fitness/nutrition/recovery → Coach
                 document/analysis/reasoning → Claude
                 work/mail/meeting/office   → Copilot
   ▷ SafetyInterceptor.preCheck
      ◇ blocked → ▢ escalation response (no model call)  ✗-safe
   ▷ ContextBuilder (if enabled)  — targets, today, 7-day training/sleep/recovery,
                                     next 24 h calendar, open P1/P2 tasks. Cap 4 000 tokens.
   ▷ stream tokens → ▢ message bubble renders progressively
   ▷ SafetyInterceptor.postCheck
   ▷ persist message pair + token usage

   ◇ assistant proposes a write (tool call)?
      → ▢ Confirmation card
           "Log 200 g Greek yogurt (Meal 5)?  200 kcal · 20 g protein"
           [ Confirm ]  [ Edit ]  [ Cancel ]
        ◇ Confirm → ▷ execute the same use case the UI would  ✓
        Nothing is ever written without this step.

   [ Context ] chip → ▢ "What was sent" sheet: the exact structured payload,
                        with a per-conversation toggle to disable injection

   ◇ daily token budget exhausted
      → ▢ "You've reached today's AI limit. Resets at midnight."
           Deterministic features (recovery, plan, insights) continue unaffected.
```

---

## Flow 8 — Acting on an insight

```
▢ Dashboard → Insights card → tap
▢ Insight detail
   ┌─────────────────────────────────────────────┐
   │ NUTRITION · confidence 86 %                 │
   │ Protein intake is below target              │
   │                                             │
   │ 5 of the last 7 days averaged 168 g against │
   │ your 200 g floor.                           │
   │                                             │
   │ EVIDENCE                                    │
   │   avg protein (7d)      168 g               │
   │   protein floor         200 g               │
   │   days below floor      5 / 7               │
   │   window   22 Aug – 28 Aug                  │
   │   rule     PROTEIN_FLOOR_MISS               │
   │   engine   dna-1.0.0                        │
   │                                             │
   │ [ Add a 40 g protein snack ]                │
   │ [ 👍 ]  [ 👎 ]  [ Dismiss ]                  │
   └─────────────────────────────────────────────┘

   [Apply]   → ▷ executes the action (log template / adjust target / create task /
                 edit workout template) → status = acted  ✓
   [👎]      → ▢ "What was wrong?" (not useful / not accurate / already knew / bad timing)
               ▷ feeds the per-user relevance model; that insight type is down-weighted
   [Dismiss] → status = dismissed; suppressed for 7 days
```

**Non-negotiable:** the EVIDENCE block is never collapsed by default and never omitted.
An insight without provenance is a bug.

---

## Flow 9 — Weekly review

```
Monday 06:00 ▷ weeklyReport job
✱ "Your week: −0.7 kg, 6 sessions, sleep down 14 %"

▢ Weekly report
   • hero: weight trajectory vs target line
   • metric grid: each with current / previous / delta and semantic direction
   • strength: e1RM deltas per key lift
   • highlights (max 3) and concerns (max 3)
   • narrative paragraph (LLM, schema-constrained, numbers injected not generated)
   • [ Share ]  → rendered image
   • [ Adjust plan ] → applies the engine's recommended target changes with a diff view
```

---

## Flow 10 — Task capture and scheduling

```
Any screen → FAB / quick-add
▢ Quick add   "submit ds assignment friday 5pm p1 #uni"
   ▷ NL parse → title · dueAt Fri 17:00 · priority P1 · category university
   ▢ Parsed preview with editable chips
   [ Add ]  ✓

▢ Tasks (segmented: Today · Upcoming · Categories · Done)
   ├─ row: checkbox · title · category dot · due chip · priority bar
   ├─ swipe right → complete   ◇ recurring? → ▷ spawn next instance
   ├─ swipe left  → snooze / reschedule
   └─ tap → ▢ Task detail (subtasks, notes, estimate, reminder, time block)

▢ Task detail → [ Schedule ]  (Phase 2 AI scheduling)
   ▷ read calendar gaps, gym window, training block, estimate, energy pattern
   ▢ Proposed slots (3 options with a one-line rationale each)
      "Tue 10:00–11:30 — your highest-completion window, before the 13:00 lecture"
   [ Accept ] → ▷ create a calendar block linked to the task  ✓
```

---

## Flow 11 — Recovery-driven training adjustment

```
03:00 ▷ recoveryEngine → recovery 28 (low), ACWR 1.62
06:00 ▷ dailyPlanBuilder reads recovery + today's template (heavy lower)
       → action = "reduce", proposes a reduced-volume variant

07:30 ✱ "Recovery 28. Today's lower session is scaled back."

▢ Dashboard → NEXT ACTION
   "Recovery is low (28). Cut today's volume by 30 %."
   "Sleep 5 h 10 m · load ratio 1.62 · resting HR +6 bpm"
   [ Apply reduced session ]   [ Train as planned ]   [ Why? ]

   [Apply]  ▷ clone the template → drop the last set of each accessory,
              cap top sets at RPE 7, keep the compound work
            ▷ record adjustmentReason = "low_recovery" on the session
            → ▢ Today's session (modified, with a visible "adjusted" badge)  ✓

   [Train as planned] ▷ records the override; the engine learns the user's preference
                        and lowers the aggressiveness of future suggestions

   [Why?] → ▢ Recovery detail: component breakdown, inputs, 7-day chart
```

---

## Flow 12 — Account deletion (compliance path)

```
▢ Settings → Account → Delete account
▢ Confirmation 1  "This deletes everything: every workout, meal, measurement and
                   conversation. It cannot be undone."
                   [ Export my data first ]  ← always offered
                   [ Continue ]
▢ Confirmation 2  re-authenticate (password or biometric)
▢ Confirmation 3  type DELETE
   ▷ callable deleteAccount
      • users/{uid}.deletedAt set, auth user disabled, sessions revoked
      • purge task enqueued: subtree delete, Storage prefix delete,
        OAuth token revocation at provider, FCM token removal
   → ▢ "Your account is being deleted. You'll get a confirmation email within 30 days."
   → signed out  ✓
```

---

## 13. Cross-cutting flow rules

| Rule | Rationale |
|---|---|
| **No dead ends.** Every error and empty state offers a next action. | A stuck user churns. |
| **Optimistic first.** User-initiated writes render instantly; failure surfaces as a retryable banner, never a lost input. | The gym has no signal. |
| **Confirmation only for the irreversible.** Deleting a session, deleting an account, applying an AI write. Everything else is undoable via a snackbar. | Confirmations everywhere train users to tap through them. |
| **Deep links everywhere.** Every notification action lands on the exact screen with the exact state. | The notification *is* the entry point for most sessions. |
| **Back never destroys.** Leaving a form preserves a draft. Leaving a live session keeps it running. | |
| **Progressive permission.** Ask at the moment of value, never at launch. | Permission grants roughly double when asked in context. |
