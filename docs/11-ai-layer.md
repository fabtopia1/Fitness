# LifeDNA OS — AI Layer

**Version:** 1.0
**Owner:** AI Lead — **safety sign-off required for any change**

---

## 1. The governing rule

> **Deterministic engines produce every number. The language model only phrases what an
> engine already computed, or answers questions about data it was given.**

A model never decides that the user should eat 2,400 calories. `MacroCalculator` decides
that; the model explains it. A model never decides the user is recovered. `RecoveryEngine`
decides that; the model narrates it.

This is not a stylistic preference. It is what makes every recommendation reproducible,
auditable and safe. It is also what keeps costs predictable, because the expensive model is
used for language, not for arithmetic.

---

## 2. Assistants

| Assistant | Backing model | Owns | Personality |
|---|---|---|---|
| **Coach** ✦ | Claude + LifeDNA system prompt + tool access + injected user context | Training, nutrition, recovery, body composition, habit | Direct, specific, evidence-first. Speaks in the user's actual numbers. |
| **Claude** ◈ | Claude, general | Documents, long-context analysis, study material, reasoning, writing | General-purpose assistant |
| **Copilot** ⊞ | Microsoft Graph–augmented | Work, mail, meetings, Office artifacts, professional scheduling | Work-context assistant |
| *(future)* | ChatGPT · Gemini · DeepSeek · Perplexity | — | Added as adapters, config-only |

Adding a provider is one file implementing `AiProvider` plus a Remote Config row. No client
release, no schema change.

---

## 3. The AI Router

### 3.1 Flow

```
message
   │
   ├─ user forced an assistant? ──yes──► use it (and remember for the conversation)
   │
   no
   │
   ├─ 1. Rule pass (deterministic, free, sub-millisecond)
   │       regex/keyword table over an explicit intent lexicon
   │       high-confidence hit → route immediately
   │
   ├─ 2. Model pass (only if rules were ambiguous)
   │       small, fast classifier model, temperature 0
   │       returns { intent, confidence }
   │
   ├─ 3. Confidence gate
   │       ≥ 0.75 → route
   │       < 0.75 → default to Coach (the safest, most contextual assistant)
   │
   └─ 4. Record the decision on the message (routedBy, routeIntent, routeConfidence)
          so routing quality is measurable and tunable.
```

### 3.2 Intent taxonomy and routing table

| Intent | Signals | Route |
|---|---|---|
| `fitness` | exercise names, sets/reps, PR, plateau, form, program | **Coach** |
| `nutrition` | calories, macros, protein, meal, food, deficit, bulk | **Coach** |
| `recovery` | sleep, recovery score, fatigue, soreness, rest day, readiness | **Coach** |
| `body` | weight, body fat, measurements, progress | **Coach** |
| `habit` | consistency, streak, motivation, adherence | **Coach** |
| `document` | "summarise this", attachment present, "read the PDF" | **Claude** |
| `analysis` | "explain", "compare", "why does", open-ended reasoning | **Claude** |
| `study` | lecture, exam, assignment, concept explanation | **Claude** |
| `work` | project, deadline, stakeholder, report, sprint | **Copilot** |
| `mail` | email, inbox, reply, thread | **Copilot** |
| `meeting` | meeting, schedule, availability, invite, calendar (work) | **Copilot** |
| `office` | document, spreadsheet, slide, Teams | **Copilot** |
| `general` | anything else | **Coach** (default) |

The table lives in Remote Config (`ai.routing.table`) and is tunable without a release.

### 3.3 Router quality tracking

Every routed message records `routeIntent`, `routeConfidence` and whether the user
subsequently overrode the assistant. An override rate above 15 % for any intent triggers a
review of that row.

---

## 4. Context injection

### 4.1 What is sent

Only when the assistant is **Coach** (or when a user explicitly asks another assistant a
data question and confirms). Hard cap: **4,000 tokens**.

```jsonc
{
  "profile":  { "age": 21, "sex": "male", "heightCm": 174.5, "weightKg": 89.4,
                "experienceLevel": "intermediate" },
  "goal":     { "mode": "cut", "targetWeightKg": "84–86", "targetDate": "2026-10-21",
                "weeklyRatePct": 0.75, "weeksElapsed": 1 },
  "targets":  { "trainingDay": { "kcal": 2600, "proteinG": 200 },
                "restDay": { "kcal": 2350, "proteinG": 200 },
                "proteinFloorG": 200, "waterMl": 3500 },
  "today":    { "date": "2026-08-28", "dayType": "rest",
                "kcal": 2412, "proteinG": 168, "carbsG": 268, "fatG": 66,
                "waterMl": 2750, "steps": 8432,
                "supplementsTaken": "4/5", "workout": null },
  "training7d": { "sessions": 4, "volumeKg": 58300, "sets": 88,
                  "byMuscle": { "chest": 18400, "back": 21200, "legs": 24100 },
                  "acuteLoad": 2340, "chronicLoad": 2180, "acwr": 1.07 },
  "keyLifts": [ { "exercise": "Incline Dumbbell Press",
                  "e1rmSeries": [40.0, 40.0, 41.2, 43.3], "lastSession": "2026-08-27",
                  "lastSets": "30×12 · 32.5×10 · 32.5×10 · 32.5×8" } ],
  "sleep7d":    { "avgMinutes": 364, "baselineMinutes": 423, "deltaPct": -14,
                  "avgScore": 71 },
  "recovery7d": { "avg": 74, "today": 82, "band": "high" },
  "body":       { "weightEwmaKg": 89.7, "weeklyChangeKg": -0.7,
                  "bodyFatPct": 30.8, "waistCm": 104.0 },
  "calendar24h":[ { "title": "Data Structures — Lecture", "start": "11:00", "end": "12:30" } ],
  "openTasks":  [ { "title": "Submit DS assignment", "due": "17:00", "priority": 1 } ],
  "insightsActive": ["protein_below_target", "sleep_decline"]
}
```

### 4.2 What is never sent

- Email address, real name, phone, device identifiers, precise location.
- Progress photos.
- The contents of other conversations.
- Anything from `settings/privacy` beyond the injection toggle itself.

### 4.3 Compaction

When the assembled context exceeds the cap, fields are dropped in this order until it fits:
`calendar24h` → `openTasks` → older entries of `keyLifts` → `training7d.byMuscle` →
`insightsActive`. `profile`, `goal`, `targets` and `today` are never dropped.

### 4.4 Transparency

The exact payload is stored as a context snapshot and rendered verbatim in the
"What was sent" sheet (`docs/06 Screen 12`). The user can disable injection globally
(Settings → AI) or per conversation. With injection off, Coach answers generically and says
so explicitly rather than pretending to know the user's numbers.

---

## 5. Coach system prompt (production text)

```
You are Coach, the training and nutrition assistant inside LifeDNA OS.

WHO YOU ARE
You are a knowledgeable, direct strength and nutrition coach. You speak plainly.
You do not use hype, emoji, or motivational filler. You treat the user as an adult
who wants the truth about their data.

YOUR DATA
You receive a structured snapshot of the user's real numbers: profile, goals,
targets, today's intake, recent training, sleep, recovery, body trend, calendar and
open tasks. Use those numbers. Cite them specifically.

HARD RULES
1. Never invent a number. If a figure is not in the context, say you do not have it.
2. Never contradict a computed value. Recovery scores, macro targets, e1RM values and
   training load come from the app's engines. You explain them; you do not recompute
   or dispute them.
3. Never give medical advice, diagnose, or interpret symptoms. If the user describes
   chest pain, fainting, persistent injury, disordered eating, or anything clinical,
   stop coaching and direct them to a qualified professional.
4. Never recommend a calorie intake below 1,500 kcal for men or 1,200 kcal for women,
   a deficit steeper than 25% of TDEE, or weight loss faster than 1% of bodyweight
   per week.
5. Never discuss dosing, sourcing, or protocols for anabolic steroids, SARMs, or any
   performance-enhancing drug.
6. Never propose a change to the user's data. Use a tool call, which the user must
   confirm before anything is written.

HOW YOU ANSWER
- Lead with the answer. Explain after.
- Cite the specific numbers you used.
- Give at most three recommendations, ordered by impact.
- Say what you would expect to change and by when.
- When the data is insufficient, say exactly what is missing and how to get it.
- Keep answers under 200 words unless the user asks for depth.

TONE EXAMPLES
Good: "Your bench is stalling because chest volume has been flat at ~5,300 kg for
       three weeks and your sleep is down 14%. Fix sleep first — strength follows
       your sleep by about five days."
Bad:  "Great question! 💪 Plateaus happen to everyone! Try mixing it up!"
```

---

## 6. Tool calling

### 6.1 Registry

Read tools execute immediately. Write tools **always** require explicit user confirmation
through `aiConfirmToolCall`. The full registry is in `docs/09 §8`.

### 6.2 Confirmation contract

```
Assistant emits a tool call
   → status = "awaiting_confirmation"
   → the client renders a confirmation card showing the exact effect in plain language
   → the user may Confirm, Edit (modify arguments), or Cancel
   → only on Confirm does the server execute — through the same use case the UI uses,
     so validation, rollups and analytics are identical
```

There is no configuration, no "trusted mode", and no preference that removes this step.

### 6.3 Why writes go through the same use case

An AI-initiated meal log must be indistinguishable from a hand-logged one: same validation,
same rollup trigger, same analytics event, same offline behaviour. Any parallel write path
would eventually diverge and corrupt the rollups.

---

## 7. Cost management

| Lever | Effect |
|---|---|
| Rule-first routing | ~70 % of messages route without any model call |
| Small classifier | The remaining classifications cost ~200 tokens, not a frontier call |
| Prompt caching | System prompt + stable context prefix are cached; repeat turns pay a fraction |
| Context cap | 4,000 tokens maximum, compacted deterministically |
| Response cap | 800 output tokens default; the user can request "more detail" explicitly |
| Daily budget | 60,000 tokens free / 250,000 pro, per user, tracked in `ai_usage` |
| Insight batching | One phrasing call produces all of a day's insights, not one call each |
| Report narrative | One call per report, schema-constrained |

**Target:** ≤ $0.85 per active user per month (business goal B4). Tracked as a custom
metric; a daily spend above 130 % of forecast pages on-call.

**Budget exhaustion** returns `AI_BUDGET_EXCEEDED` with a reset time. Deterministic
features — recovery, plan, insights, reports — are unaffected, because they do not depend
on the language model for their values.

---

## 8. Safety layer

### 8.1 Pre-check (before any model call)

| Category | Trigger | Response |
|---|---|---|
| **Medical** | Symptoms, diagnosis requests, medication, injury interpretation | "I can't help with medical questions. Please speak to a doctor or physiotherapist. I can adjust your training around a restriction once you have professional advice." |
| **Disordered eating** | Extreme restriction language, purging, "how do I stop eating", body-image distress signals | Non-judgmental redirect to professional support with region-appropriate resources. **No coaching content is returned.** |
| **PEDs** | Steroid, SARM, or PED dosing/sourcing/cycling | "I don't provide guidance on performance-enhancing drugs." No further engagement. |
| **Self-harm** | Any self-harm or crisis signal | Crisis resources. Nothing else. |
| **Minors** | Age indicators below 18 | Under-18 accounts are not permitted in v1; the account is flagged for review. |

### 8.2 Post-check (on the streamed/returned output)

- Numeric claims are cross-checked against the injected context. A figure not present in
  the context and not derivable from it flags the message and, above a threshold,
  truncates and replaces the response.
- Calorie or rate recommendations violating the floors in the system prompt are blocked.
- Every block is logged (category, not content) for safety review.

### 8.3 Escalation path

A blocked request never silently fails. The user sees the escalation copy, the reason
category, and — where relevant — a link to appropriate resources. The message is stored with
`safetyFlags` so the conversation history is honest about what happened.

---

## 9. Prompt and evaluation management

```
functions/src/providers/ai/prompts/
├── coach.system.md          # versioned, reviewed, diffed like code
├── router.classify.md
├── insight.phrasing.md      # strict JSON schema output
├── report.narrative.md      # strict JSON schema output
└── versions.json            # active version per prompt, per environment
```

Prompts are versioned artifacts. A prompt change goes through the same review as a code
change and is rolled out via Remote Config so it can be reverted without a deploy.

**Evaluation suite** (`functions/test/ai/eval/`) — run on every prompt change:

| Suite | Cases | Gate |
|---|---|---|
| Routing accuracy | 200 labelled messages | ≥ 92 % correct intent |
| Numeric fidelity | 100 context+question pairs | 0 invented numbers |
| Safety | 80 adversarial prompts across all 5 categories | 100 % correct escalation |
| Tone | 40 responses, rubric-scored | ≥ 4.0 / 5 mean |
| Length | All responses | ≥ 90 % under 200 words |
| Schema | 100 insight/report generations | 100 % valid against schema |

A regression on the safety suite blocks release unconditionally.

---

## 10. Failure behaviour

| Failure | Behaviour |
|---|---|
| Provider timeout | Retry once with backoff, then `PROVIDER_UNAVAILABLE`; partial streamed content is kept with a retry affordance |
| Provider 5xx | Circuit breaker opens after 5 failures in 60 s; requests fail fast for 30 s |
| Rate limited upstream | Queue with backoff; the user sees "Coach is busy — retrying" |
| Malformed structured output | Reparse once with a repair prompt; on second failure, discard and fall back to the deterministic template text |
| Budget exhausted | Clear message with reset time; deterministic features continue |
| Safety block | Escalation response; never a generic error |

**Critically:** insights and reports have a deterministic template fallback. If the language
layer is completely unavailable, the user still gets
`"Protein intake is below target: 168 g average against a 200 g floor, 5 of 7 days."` —
less elegant, equally correct, equally actionable.
