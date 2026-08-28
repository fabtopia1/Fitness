# LifeDNA OS — Database Schema

**Version:** 1.0
**Datastore:** Cloud Firestore (Native mode) + Cloud Storage + on-device SQLite (Drift)
**Owner:** Backend Lead

---

## 1. Modelling principles

1. **Per-user subtree.** Almost everything lives under `users/{uid}/…`. This makes the
   security rule trivial (`request.auth.uid == uid`), makes deletion a subtree purge, and
   keeps queries naturally scoped.
2. **Global read-only catalogues** (`exercises`, `foods`, `supplement_catalog`) live at the
   root, are readable by any authenticated user, and are writable only by admin.
3. **Rollups beat scans.** `daily_stats/{yyyy-MM-dd}` is the one document a screen reads
   for a day's totals. Triggers maintain it. No client ever aggregates by reading N logs.
4. **Client-generated IDs (UUID v7)** for every additive log, so a retry is an idempotent
   `set(merge:true)` and offline writes never collide.
5. **Denormalize what is displayed.** A set stores `exerciseName` alongside `exerciseId` so
   a history screen needs one read, not N joins.
6. **Timestamps.** Every document has `createdAt` and `updatedAt` (server timestamps).
   Every day-bucketed document additionally has `localDate` (`yyyy-MM-dd`) and
   `tzOffsetMinutes`, both computed at write time from the user's timezone.
7. **Soft delete** via `deletedAt` for user-visible entities (tasks, templates, custom
   foods) so sync can propagate a deletion; hard delete for logs.
8. **Units are canonical metric.** kg, cm, ml, kcal, g, seconds. Never store a display unit.

### Field-type legend

`str` string · `num` number · `int` integer · `bool` boolean · `ts` Timestamp ·
`map` object · `arr` array · `ref` document reference (stored as a path string) ·
`?` optional

---

## 2. Collection map

```
/users/{uid}                                   ← profile, targets, preferences
   /settings/{docId}                           ← notifications, units, privacy, integrations
   /nutrition_logs/{logId}                     ← one food entry
   /meals/{mealId}                             ← saved meal templates / recipes
   /meal_plans/{yyyy-MM-dd}                    ← planned meals for a date
   /water_logs/{logId}
   /supplements/{supplementId}                 ← the user's stack
   /supplement_logs/{logId}
   /supplement_purchases/{purchaseId}
   /workout_templates/{templateId}
   /workout_programs/{programId}
   /workout_sessions/{sessionId}
      /sets/{setId}                            ← one performed set
   /custom_exercises/{exerciseId}
   /personal_records/{recordId}
   /body_metrics/{metricId}
   /body_photos/{photoId}
   /sleep_data/{yyyy-MM-dd}
   /health_records/{idempotencyKey}            ← raw normalized wearable/phone records
   /recovery_data/{yyyy-MM-dd}
   /daily_stats/{yyyy-MM-dd}                   ← THE rollup document
   /daily_plans/{yyyy-MM-dd}                   ← today's ordered action plan
   /calendar_accounts/{accountId}
   /calendar_events/{eventId}                  ← cached mirror of provider events
   /tasks/{taskId}
   /ai_conversations/{conversationId}
      /messages/{messageId}
   /ai_usage/{yyyy-MM}
   /insights/{insightId}
   /notifications/{notificationId}             ← delivery history
   /reports/{reportId}                         ← weekly/monthly/quarterly
   /devices/{deviceId}                         ← FCM tokens, platform info
   /sync_state/{sourceId}                      ← per-source cursors + tokens

/exercises/{exerciseId}                        ← GLOBAL catalogue (read-only)
/foods/{foodId}                                ← GLOBAL catalogue (read-only)
/supplement_catalog/{itemId}                   ← GLOBAL catalogue (read-only)
/programs_library/{programId}                  ← GLOBAL seeded programs
/app_config/{configId}                         ← GLOBAL, read-only (engine weights etc.)

/_admin/{...}                                  ← server-only, no client access
   /oauth_tokens/{uid}_{provider}              ← KMS-encrypted refresh tokens
   /engine_runs/{runId}                        ← audit of engine executions
   /rate_limits/{uid}_{bucket}
```

---

## 3. Core user documents

### 3.1 `users/{uid}`

```jsonc
{
  "uid": "str",
  "email": "str",
  "displayName": "str",
  "photoUrl": "str?",
  "createdAt": "ts",
  "updatedAt": "ts",
  "onboardingCompletedAt": "ts?",
  "timezone": "str",                    // IANA, e.g. "Africa/Cairo"
  "locale": "str",                      // "en-US"

  "profile": {
    "dateOfBirth": "ts",
    "sex": "str",                       // male | female | unspecified
    "heightCm": "num",                  // 174.5
    "activityLevel": "str",             // sedentary|light|moderate|active|very_active
    "trainingDaysPerWeek": "int",       // 6
    "experienceLevel": "str",           // beginner|intermediate|advanced
    "gymWindow": { "start": "18:00", "end": "20:00" },
    "dietaryRestrictions": ["str"],     // ["halal","no_pork"]
    "injuries": ["str"]
  },

  "goal": {
    "mode": "str",                      // cut | maintain | bulk
    "startWeightKg": 90.1,
    "currentWeightKg": 90.1,
    "targetWeightKgMin": 84.0,
    "targetWeightKgMax": 86.0,
    "startBodyFatPct": 31.3,
    "targetBodyFatPctMin": 24.0,
    "targetBodyFatPctMax": 26.0,
    "startedAt": "ts",
    "targetDate": "ts",
    "weeklyRateTargetPct": 0.75,        // % bodyweight per week
    "strengthGoalPct": 15               // +10–20 % on key lifts
  },

  "targets": {                          // computed, editable; see PRD §6.2
    "bmr": 1863,
    "tdee": 2889,
    "trainingDay": { "kcal": 2600, "proteinG": 200, "carbsG": 290, "fatG": 70 },
    "restDay":     { "kcal": 2350, "proteinG": 200, "carbsG": 210, "fatG": 70 },
    "proteinFloorG": 200,               // absolute daily minimum
    "waterMl": 3500,
    "stepsGoal": 12000,
    "sleepGoalMinutes": 480,
    "computedAt": "ts",
    "overriddenByUser": false
  },

  "modules": {                          // progressive disclosure (PRD AUTH-10)
    "enabled": ["nutrition","workout","dashboard"],
    "locked":  { "recovery": "Connect a health source", "analytics": "14 days of data" }
  },

  "subscription": {
    "tier": "str",                      // free | pro
    "status": "str",                    // active | trialing | past_due | canceled
    "renewsAt": "ts?",
    "platform": "str?"                  // play | app_store
  },

  "flags": {
    "hasCompletedFirstWorkout": true,
    "hasConnectedHealthSource": false,
    "hasConnectedCalendar": false
  },

  "deletedAt": "ts?"                    // set on deletion request; purge job honours it
}
```

**Indexes:** none beyond the automatic ones (documents are fetched by uid).

---

### 3.2 `users/{uid}/settings/{docId}`

Fixed document IDs: `notifications`, `preferences`, `privacy`, `integrations`.

```jsonc
// settings/notifications
{
  "enabled": true,
  "quietHours": { "start": "23:00", "end": "07:00", "enabled": true },
  "dailyCap": 9,
  "categories": {
    "hydration":  { "enabled": true,  "times": ["10:00","13:00","16:00","19:00"] },
    "meal":       { "enabled": true,  "leadMinutes": 0 },
    "supplement": { "enabled": true },
    "workout":    { "enabled": true,  "leadMinutes": 45 },
    "sleep":      { "enabled": true,  "time": "22:45" },
    "meeting":    { "enabled": true,  "leadMinutes": 10 },
    "task":       { "enabled": true,  "leadMinutes": 30 },
    "recovery":   { "enabled": true,  "time": "07:30" },
    "insight":    { "enabled": true,  "time": "07:30" },
    "system":     { "enabled": true }
  }
}

// settings/preferences
{
  "units": { "weight": "kg", "length": "cm", "volume": "ml", "energy": "kcal" },
  "theme": "dark",                       // dark | light | system
  "startOfWeek": "monday",
  "defaultRestSeconds": 120,
  "weightIncrementKg": 2.5,
  "dashboardLayout": ["next_action","macros","workout","recovery","schedule","tasks","insights"],
  "hiddenCards": [],
  "liveGym": { "keepScreenOn": true, "volumeKeyCompletesSet": false, "restSound": true }
}

// settings/privacy
{
  "aiContextInjection": true,
  "shareAnonymizedAnalytics": true,
  "biometricLock": false,
  "photoStorageEnabled": false,
  "consents": [
    { "type": "health_data", "grantedAt": "ts", "version": "1.0" },
    { "type": "ai_processing", "grantedAt": "ts", "version": "1.0" }
  ]
}

// settings/integrations
{
  "healthConnect": { "connected": true, "lastSyncAt": "ts", "permissions": ["steps","heart_rate","sleep"] },
  "samsungHealth": { "connected": false },
  "galaxyFit3":    { "connected": true, "deviceId": "str", "lastSeenAt": "ts", "batteryPct": 74 },
  "sourcePrecedence": { "heartRate": ["wearable","phone","manual"], "weight": ["manual","scale"] }
}
```

---

## 4. Nutrition

### 4.1 `users/{uid}/nutrition_logs/{logId}`  *(logId = client UUID v7)*

```jsonc
{
  "id": "str",
  "localDate": "2026-08-28",
  "tzOffsetMinutes": 180,
  "loggedAt": "ts",
  "mealSlot": "str",                    // breakfast|lunch|pre_workout|post_workout|dinner|before_bed|snack
  "source": "str",                      // search|barcode|recent|favorite|template|quick_add|recipe|ai

  "foodId": "str?",                     // → /foods/{foodId} or custom_foods
  "foodName": "str",                    // denormalized for display
  "brand": "str?",
  "barcode": "str?",

  "quantity": 150,
  "unit": "str",                        // g | ml | serving | piece
  "servingLabel": "str?",               // "1 scoop (30 g)"
  "gramsEquivalent": 150,               // canonical mass for recomputation

  "macros": { "kcal": 248, "proteinG": 46.5, "carbsG": 0, "fatG": 5.4 },
  "micros": { "fiberG": 0, "sugarG": 0, "sodiumMg": 74, "potassiumMg": 380 },

  "recipeId": "str?",                   // if expanded from a recipe
  "templateId": "str?",
  "note": "str?",
  "createdAt": "ts",
  "updatedAt": "ts"
}
```

**Indexes**
- `localDate ASC, loggedAt ASC`
- `foodId ASC, loggedAt DESC` (for "how often do I eat this")
- `mealSlot ASC, localDate DESC`

### 4.2 `users/{uid}/meals/{mealId}` — templates and recipes

```jsonc
{
  "id": "str",
  "name": "Post-workout: beef, rice, veg",
  "type": "str",                        // template | recipe
  "mealSlot": "str?",
  "servings": 1,
  "items": [
    { "foodId": "str", "foodName": "Beef mince 10%", "quantity": 200, "unit": "g",
      "gramsEquivalent": 200,
      "macros": { "kcal": 384, "proteinG": 41.2, "carbsG": 0, "fatG": 24 } }
  ],
  "totals":    { "kcal": 812, "proteinG": 58.4, "carbsG": 78, "fatG": 26 },
  "perServing":{ "kcal": 812, "proteinG": 58.4, "carbsG": 78, "fatG": 26 },
  "tags": ["high_protein","post_workout"],
  "useCount": 23,
  "lastUsedAt": "ts",
  "isFavorite": true,
  "createdAt": "ts", "updatedAt": "ts", "deletedAt": "ts?"
}
```

**Indexes:** `isFavorite DESC, lastUsedAt DESC` · `type ASC, useCount DESC`

### 4.3 `users/{uid}/meal_plans/{yyyy-MM-dd}`

```jsonc
{
  "localDate": "2026-09-02",
  "dayType": "training",                // training | rest
  "targets": { "kcal": 2600, "proteinG": 200, "carbsG": 290, "fatG": 70 },
  "slots": [
    { "mealSlot": "breakfast", "time": "09:00", "mealId": "str?", "name": "Eggs · foul · baladi bread",
      "planned": { "kcal": 520, "proteinG": 34, "carbsG": 52, "fatG": 18 }, "status": "planned" }
  ],
  "generatedBy": "user",                // user | ai | template
  "createdAt": "ts", "updatedAt": "ts"
}
```

### 4.4 `users/{uid}/water_logs/{logId}`

```jsonc
{
  "id": "str", "localDate": "2026-08-28", "loggedAt": "ts",
  "amountMl": 250, "containerLabel": "Glass", "createdAt": "ts"
}
```
**Index:** `localDate ASC, loggedAt ASC`

### 4.5 `/foods/{foodId}` — GLOBAL catalogue

```jsonc
{
  "id": "str",
  "name": "Chicken breast, skinless, raw",
  "nameLower": "chicken breast, skinless, raw",   // for prefix search
  "searchTokens": ["chicken","breast","skinless","raw"],
  "brand": "str?",
  "barcodes": ["str"],
  "category": "protein",
  "provider": "str",                    // internal | openfoodfacts | user_contributed
  "providerId": "str?",
  "verified": true,
  "per100g": {
    "kcal": 165, "proteinG": 31, "carbsG": 0, "fatG": 3.6,
    "fiberG": 0, "sugarG": 0, "sodiumMg": 74, "saturatedFatG": 1.0
  },
  "servings": [
    { "label": "100 g", "grams": 100 },
    { "label": "1 breast (174 g)", "grams": 174 }
  ],
  "popularity": 98230,
  "locale": ["en","ar"],
  "createdAt": "ts", "updatedAt": "ts"
}
```

> **Search strategy.** The top 5 000 foods by popularity ship as a **Firestore bundle**
> loaded into Drift on first run, giving zero-latency, zero-cost local search. Cache misses
> call the `foodSearch` callable, which queries Firestore then Open Food Facts, writes the
> resolved food back into `/foods`, and returns it. This satisfies NUTR-02 (≤ 400 ms P90).

---

## 5. Supplements

### 5.1 `users/{uid}/supplements/{supplementId}`

```jsonc
{
  "id": "str",
  "catalogId": "str?",                  // → /supplement_catalog
  "name": "Creatine monohydrate",
  "form": "powder",                     // powder|capsule|tablet|softgel|liquid|gummy
  "dose": { "amount": 5, "unit": "g" },
  "schedule": {
    "type": "daily",                    // daily|weekdays|training_days|rest_days|cyclical|as_needed
    "weekdays": [1,2,3,4,5,6,7],
    "cyclical": { "onDays": 0, "offDays": 0 },
    "anchors": ["post_workout"]         // wake|breakfast|lunch|pre_workout|post_workout|dinner|before_bed|HH:mm
  },
  "inventory": {
    "tracked": true,
    "unitsRemaining": 62,               // servings
    "unitsPerContainer": 100,
    "lowStockThresholdDays": 7,
    "lastRestockedAt": "ts"
  },
  "notes": "5 g daily, timing irrelevant; consistency is what matters.",
  "active": true,
  "color": "#00D1B2",
  "createdAt": "ts", "updatedAt": "ts", "deletedAt": "ts?"
}
```

### 5.2 `users/{uid}/supplement_logs/{logId}`

```jsonc
{
  "id": "str", "supplementId": "str", "supplementName": "Creatine monohydrate",
  "localDate": "2026-08-28", "takenAt": "ts",
  "scheduledAnchor": "post_workout", "scheduledAt": "ts",
  "amount": 5, "unit": "g",
  "status": "taken",                    // taken | skipped | missed
  "loggedFrom": "notification",         // notification | dashboard | supplements_screen
  "createdAt": "ts"
}
```
**Indexes:** `localDate ASC, takenAt ASC` · `supplementId ASC, localDate DESC`

### 5.3 `users/{uid}/supplement_purchases/{purchaseId}`

```jsonc
{
  "id": "str", "supplementId": "str", "purchasedAt": "ts",
  "vendor": "str", "quantity": 1, "unitsPerContainer": 100,
  "cost": { "amount": 450, "currency": "EGP" },
  "costPerServing": 4.5, "notes": "str?", "createdAt": "ts"
}
```

---

## 6. Training

### 6.1 `/exercises/{exerciseId}` — GLOBAL catalogue

```jsonc
{
  "id": "incline-dumbbell-press",
  "name": "Incline Dumbbell Press",
  "nameLower": "incline dumbbell press",
  "searchTokens": ["incline","dumbbell","press","chest"],
  "aliases": ["Incline DB Press"],
  "primaryMuscles": ["chest_upper"],
  "secondaryMuscles": ["shoulders_front","triceps"],
  "muscleGroup": "chest",
  "equipment": "dumbbell",              // barbell|dumbbell|machine|cable|bodyweight|kettlebell|band|smith
  "category": "strength",               // strength|cardio|mobility|plyometric|olympic
  "mechanic": "compound",               // compound | isolation
  "force": "push",                      // push | pull | static
  "level": "intermediate",
  "defaultRestSeconds": 120,
  "defaultIncrementKg": 2.0,
  "isUnilateral": false,
  "tracksWeight": true, "tracksReps": true, "tracksDistance": false, "tracksDuration": false,
  "instructions": ["str"],
  "tips": ["str"],
  "mediaUrl": "str?",
  "popularity": 8734,
  "createdAt": "ts", "updatedAt": "ts"
}
```

Muscle taxonomy (fixed enum used everywhere):
`chest_upper, chest_mid, chest_lower, back_lats, back_upper, back_lower, traps,
shoulders_front, shoulders_side, shoulders_rear, biceps, triceps, forearms, abs,
obliques, glutes, quads, hamstrings, adductors, calves, neck`

### 6.2 `users/{uid}/workout_templates/{templateId}`

```jsonc
{
  "id": "str",
  "name": "PUSH — Chest · Shoulders · Triceps",
  "dayLabel": "SAT",
  "estimatedMinutes": 75,
  "targetMuscles": ["chest","shoulders","triceps"],
  "exercises": [
    {
      "order": 0,
      "exerciseId": "incline-dumbbell-press",
      "exerciseName": "Incline Dumbbell Press",
      "groupId": null,                  // non-null ⇒ superset/circuit membership
      "groupType": null,                // superset | circuit | dropset
      "targetSets": 4,
      "repRange": { "min": 8, "max": 12 },
      "loadScheme": { "type": "rpe", "targetRpe": 8 },   // rpe | percent_1rm | fixed | bodyweight
      "restSeconds": 120,
      "note": "Bench at 30°. Full ROM over load."
    }
  ],
  "totalWorkingSets": 22,
  "programId": "str?",
  "useCount": 14, "lastUsedAt": "ts", "isArchived": false,
  "createdAt": "ts", "updatedAt": "ts", "deletedAt": "ts?"
}
```

### 6.3 `users/{uid}/workout_programs/{programId}`

```jsonc
{
  "id": "str",
  "name": "8-Week Body Recomposition",
  "description": "Every muscle trained twice weekly, logged progressive overload, recovery built in.",
  "durationWeeks": 8,
  "startedAt": "ts", "currentWeek": 1,
  "phases": [
    { "name": "Foundation",  "weeks": [1,2], "focus": "Technique, baselines, habit" },
    { "name": "Overload",    "weeks": [3,4], "focus": "Add load every session" },
    { "name": "High Effort", "weeks": [5,6], "focus": "Intensity techniques, more cardio" },
    { "name": "Peak Recomp", "weeks": [7,8], "focus": "Hold strength, finish lean" }
  ],
  "weeklySchedule": {
    "saturday":  { "templateId": "str", "label": "PUSH" },
    "sunday":    { "templateId": "str", "label": "PULL" },
    "monday":    { "templateId": "str", "label": "LEGS" },
    "tuesday":   { "templateId": "str", "label": "FITNESS", "optional": true },
    "wednesday": { "templateId": "str", "label": "UPPER" },
    "thursday":  { "templateId": "str", "label": "LOWER" },
    "friday":    { "templateId": "str", "label": "SWIM", "optional": true, "type": "recovery" }
  },
  "sessionCeilingMinutes": 75,
  "structure": { "warmupMinutes": 5, "resistanceMinutes": 50, "cardioMinutes": 20 },
  "status": "active",                   // active | completed | paused
  "createdAt": "ts", "updatedAt": "ts"
}
```

### 6.4 `users/{uid}/workout_sessions/{sessionId}`

```jsonc
{
  "id": "str",
  "templateId": "str?", "programId": "str?",
  "name": "PUSH — Chest · Shoulders · Triceps",
  "localDate": "2026-08-29", "tzOffsetMinutes": 180,
  "startedAt": "ts", "finishedAt": "ts?",
  "durationSeconds": 4380,
  "pausedSeconds": 0,
  "status": "completed",                // in_progress | completed | abandoned

  "exercises": [                        // ordered plan snapshot; actual sets live in /sets
    { "order": 0, "exerciseId": "incline-dumbbell-press",
      "exerciseName": "Incline Dumbbell Press",
      "groupId": null, "targetSets": 4, "completedSets": 4,
      "restSeconds": 120, "note": "str?" }
  ],

  "totals": {
    "volumeKg": 14820,                  // Σ weight × reps (working sets only)
    "sets": 22, "workingSets": 22, "reps": 214,
    "estimatedKcal": 512,
    "muscleVolume": { "chest": 5400, "shoulders": 4100, "triceps": 5320 }
  },

  "rpeAverage": 8.1,
  "sessionRpe": 8,                      // whole-session RPE, drives training load
  "trainingLoad": 584,                  // sessionRpe × durationMinutes
  "heartRate": { "avgBpm": 128, "maxBpm": 171, "source": "galaxy_fit3" },

  "personalRecords": ["str"],           // record ids created in this session
  "note": "str?",
  "createdAt": "ts", "updatedAt": "ts"
}
```
**Indexes:** `localDate DESC` · `status ASC, startedAt DESC` · `templateId ASC, startedAt DESC`

### 6.5 `users/{uid}/workout_sessions/{sessionId}/sets/{setId}`  *(setId = client UUID v7)*

```jsonc
{
  "id": "str",
  "sessionId": "str",
  "exerciseId": "incline-dumbbell-press",
  "exerciseName": "Incline Dumbbell Press",
  "exerciseOrder": 0,
  "setIndex": 2,                        // 1-based within the exercise
  "setType": "working",                 // warmup | working | dropset | failure | amrap
  "parentSetId": "str?",                // dropsets reference their parent

  "weightKg": 32.5,
  "reps": 10,
  "distanceM": null, "durationSeconds": null,   // cardio / timed exercises

  "rpe": 8,
  "toFailure": false,
  "completed": true,
  "skipped": false,

  "restAfterSeconds": 120,
  "actualRestSeconds": 134,
  "performedAt": "ts",

  "e1rm": 43.3,                         // Epley, computed client-side, stored for trends
  "isPr": false,
  "prTypes": [],                        // ["heaviest_weight","best_e1rm","max_reps"]
  "note": "str?",
  "voiceNoteUrl": "str?",

  "previousWeightKg": 30.0,             // what was shown as "last time"
  "previousReps": 10,

  "clientCreatedAt": "ts",
  "createdAt": "ts"
}
```
**Indexes (collection group `sets`):**
`exerciseId ASC, performedAt DESC` · `exerciseId ASC, e1rm DESC` · `performedAt DESC`

### 6.6 `users/{uid}/personal_records/{recordId}`

```jsonc
{
  "id": "str",
  "exerciseId": "incline-dumbbell-press", "exerciseName": "Incline Dumbbell Press",
  "type": "best_e1rm",                  // heaviest_weight | best_e1rm | max_reps | max_volume | best_time
  "value": 43.3, "unit": "kg",
  "weightKg": 32.5, "reps": 10,
  "sessionId": "str", "setId": "str",
  "achievedAt": "ts",
  "previousValue": 40.0, "improvementPct": 8.25,
  "createdAt": "ts"
}
```
**Indexes:** `exerciseId ASC, type ASC, achievedAt DESC` · `achievedAt DESC`

---

## 7. Body, sleep, health, recovery

### 7.1 `users/{uid}/body_metrics/{metricId}`

```jsonc
{
  "id": "str", "localDate": "2026-08-29", "measuredAt": "ts",
  "context": "fasted_morning",          // fasted_morning | post_meal | evening | unspecified
  "weightKg": 89.4,
  "bodyFatPct": 30.8,
  "muscleMassKg": 61.9,
  "boneMassKg": null, "bodyWaterPct": null, "visceralFatRating": null,
  "measurements": {
    "waistCm": 104.0, "chestCm": 112.0, "neckCm": 41.0, "hipsCm": 108.0,
    "leftArmCm": 38.5, "rightArmCm": 38.8,
    "leftThighCm": 63.0, "rightThighCm": 63.2,
    "leftCalfCm": 40.0, "rightCalfCm": 40.1,
    "leftForearmCm": 30.0, "rightForearmCm": 30.2
  },
  "source": "manual",                   // manual | smart_scale | health_connect
  "note": "str?", "createdAt": "ts", "updatedAt": "ts"
}
```
**Index:** `localDate DESC`

### 7.2 `users/{uid}/body_photos/{photoId}`

```jsonc
{
  "id": "str", "localDate": "2026-08-29", "takenAt": "ts",
  "angle": "front",                     // front | side | back
  "storagePath": "users/{uid}/body_photos/{photoId}.jpg",
  "thumbnailPath": "str",
  "weightKgAtCapture": 89.4,
  "createdAt": "ts"
}
```

### 7.3 `users/{uid}/sleep_data/{yyyy-MM-dd}` — keyed by **wake** date

```jsonc
{
  "localDate": "2026-08-29",
  "bedtimeAt": "ts", "wakeAt": "ts",
  "totalMinutes": 431, "timeInBedMinutes": 468,
  "efficiencyPct": 92.1,
  "stages": { "deepMinutes": 78, "remMinutes": 96, "lightMinutes": 257, "awakeMinutes": 37 },
  "awakenings": 3,
  "sleepScore": 79,
  "scoreComponents": { "duration": 82, "consistency": 74, "efficiency": 88, "stages": 71 },
  "restingHeartRateBpm": 58, "hrvMs": 42, "respiratoryRate": 14.8,
  "source": "galaxy_fit3",              // galaxy_fit3 | health_connect | samsung_health | manual
  "confidence": "high",
  "createdAt": "ts", "updatedAt": "ts"
}
```

### 7.4 `users/{uid}/health_records/{idempotencyKey}`

`idempotencyKey = sha256(source|type|startMs|endMs)` — makes re-sync a no-op.

```jsonc
{
  "key": "str",
  "type": "steps",                      // steps|heart_rate|calories_active|calories_total|
                                        // distance|active_minutes|stress|spo2|
                                        // resting_heart_rate|hrv|exercise_session|weight
  "source": "galaxy_fit3",
  "sourcePrecedence": 100,              // wearable 100 > phone 50 > manual 10 (per type policy)
  "startAt": "ts", "endAt": "ts",
  "localDate": "2026-08-29",
  "value": 8432, "unit": "count",
  "metadata": { "deviceModel": "SM-R390", "originalId": "str" },
  "ingestedAt": "ts"
}
```
**Indexes:** `type ASC, startAt DESC` · `localDate ASC, type ASC`

**Retention:** raw records older than 400 days are compacted into `daily_stats` and deleted
by a scheduled job. `daily_stats` is retained indefinitely.

### 7.5 `users/{uid}/recovery_data/{yyyy-MM-dd}`

```jsonc
{
  "localDate": "2026-08-29",
  "recoveryScore": 82,
  "band": "high",                       // low | moderate | high
  "readinessScore": 78,
  "components": {
    "sleep":    { "score": 79, "weight": 0.40, "contribution": 31.6, "available": true },
    "training": { "score": 88, "weight": 0.40, "contribution": 35.2, "available": true },
    "activity": { "score": 76, "weight": 0.20, "contribution": 15.2, "available": true }
  },
  "inputs": {
    "sleepMinutes": 431, "sleepScore": 79,
    "acuteLoad": 2340, "chronicLoad": 2180, "acwr": 1.07,
    "steps": 8432, "activeMinutes": 62,
    "restingHrBpm": 58, "restingHrDelta": -1, "hrvMs": 42, "hrvDelta": 3
  },
  "missingInputs": [],
  "recommendation": {
    "action": "proceed",                // push | proceed | reduce | rest
    "headline": "Green light — train as planned.",
    "detail": "Sleep is at your 28-day average and your load ratio is balanced at 1.07."
  },
  "engineVersion": "recovery-1.2.0",
  "computedAt": "ts"
}
```

### 7.6 `users/{uid}/daily_stats/{yyyy-MM-dd}` — **the rollup**

One read serves the whole dashboard. Maintained by Firestore triggers, never by the client.

```jsonc
{
  "localDate": "2026-08-29",
  "dayType": "training",                // training | rest
  "updatedAt": "ts",

  "nutrition": {
    "kcal": 2412, "proteinG": 168, "carbsG": 268, "fatG": 66,
    "targetKcal": 2600, "targetProteinG": 200, "targetCarbsG": 290, "targetFatG": 70,
    "proteinFloorG": 200,
    "entryCount": 14,
    "bySlot": { "breakfast": { "kcal": 520, "proteinG": 34 } },
    "adherencePct": 92.8
  },
  "hydration": { "ml": 2750, "targetMl": 3500, "logCount": 11 },
  "supplements": { "taken": 4, "scheduled": 5, "compliancePct": 80.0 },
  "training": {
    "sessionId": "str?", "status": "completed",
    "volumeKg": 14820, "sets": 22, "durationSeconds": 4380,
    "trainingLoad": 584, "sessionRpe": 8,
    "muscleVolume": { "chest": 5400, "shoulders": 4100, "triceps": 5320 },
    "prCount": 1
  },
  "activity": { "steps": 8432, "activeMinutes": 62, "distanceM": 6210, "activeKcal": 612 },
  "sleep": { "minutes": 431, "score": 79, "bedtimeAt": "ts", "wakeAt": "ts" },
  "recovery": { "score": 82, "band": "high", "readiness": 78 },
  "tasks": { "completed": 5, "created": 7, "overdue": 1 },
  "body": { "weightKg": 89.4, "weightEwmaKg": 89.7 },

  "computedFrom": { "nutritionLogs": 14, "sets": 22, "healthRecords": 38 },
  "engineVersion": "rollup-1.0.0"
}
```

**This document is the single most important read-optimization in the system.** Dashboard
cost is 1 document read instead of ~90.

---

## 8. Planning, calendar and tasks

### 8.1 `users/{uid}/daily_plans/{yyyy-MM-dd}`

```jsonc
{
  "localDate": "2026-08-29",
  "generatedAt": "ts", "generatedBy": "daily_plan_builder-1.0.0",
  "dayType": "training",
  "headline": "Push day. Recovery is green — train as planned.",
  "actions": [
    { "id": "str", "order": 0, "type": "meal",
      "title": "Time for Meal 1", "subtitle": "Eggs · foul · baladi bread — 520 kcal · 34 g protein",
      "dueAt": "ts", "priority": 90, "status": "pending",
      "deeplink": "/nutrition/log?slot=breakfast",
      "source": "meal_plan" },
    { "id": "str", "order": 1, "type": "workout",
      "title": "Workout starts in 45 minutes", "subtitle": "PUSH — 22 working sets · 75 min",
      "dueAt": "ts", "priority": 85, "status": "pending",
      "deeplink": "/train/template/{id}", "source": "program" }
  ],
  "constraints": { "calendarBusyBlocks": [ { "start": "ts", "end": "ts", "title": "Lecture" } ],
                   "gymWindow": { "start": "18:00", "end": "20:00" } },
  "updatedAt": "ts"
}
```

### 8.2 `users/{uid}/calendar_accounts/{accountId}`

```jsonc
{
  "id": "str",
  "provider": "google",                 // google | microsoft
  "accountEmail": "str",
  "displayName": "str",
  "connectedAt": "ts",
  "scopes": ["https://www.googleapis.com/auth/calendar"],
  "calendars": [
    { "calendarId": "str", "name": "University", "color": "#0066FF",
      "enabled": true, "isPrimary": false, "canWrite": true, "syncToken": "str?" }
  ],
  "syncStatus": "healthy",              // healthy | needs_reauth | error
  "lastSyncAt": "ts", "lastError": "str?",
  "writeBackEnabled": true,
  "updatedAt": "ts"
}
```
> Refresh tokens are **not** stored here. They live in `_admin/oauth_tokens/{uid}_{provider}`,
> KMS-encrypted, server-access only.

### 8.3 `users/{uid}/calendar_events/{eventId}` — cached mirror

```jsonc
{
  "id": "str",                          // "{provider}_{calendarId}_{providerEventId}"
  "provider": "google", "accountId": "str", "calendarId": "str",
  "providerEventId": "str", "etag": "str?",
  "title": "Data Structures — Lecture",
  "description": "str?", "location": "str?",
  "startAt": "ts", "endAt": "ts", "isAllDay": false,
  "localDate": "2026-08-29", "timezone": "Africa/Cairo",
  "recurrence": { "rule": "RRULE:FREQ=WEEKLY;BYDAY=SA", "instanceId": "str?" },
  "status": "confirmed",                // confirmed | tentative | cancelled
  "attendeeCount": 42,
  "isBusy": true,
  "origin": "external",                 // external | lifedna
  "lifednaBlock": { "type": "workout", "refId": "str" },
  "color": "#0066FF",
  "syncedAt": "ts", "updatedAt": "ts"
}
```
**Indexes:** `startAt ASC` · `localDate ASC, startAt ASC` · `calendarId ASC, startAt ASC`

### 8.4 `users/{uid}/tasks/{taskId}`

```jsonc
{
  "id": "str",
  "title": "Submit data structures assignment",
  "notes": "str?",
  "category": "university",             // university|work|fitness|personal|projects|<custom>
  "projectId": "str?",
  "priority": 1,                        // 1 (P1, highest) … 4
  "status": "open",                     // open | in_progress | done | cancelled
  "dueAt": "ts?", "dueIsAllDay": false,
  "estimateMinutes": 90,
  "tags": ["uni","cs201"],

  "subtasks": [ { "id": "str", "title": "Write tests", "done": false, "order": 0 } ],
  "subtaskProgress": { "done": 1, "total": 3 },

  "recurrence": {
    "enabled": false, "frequency": "weekly",   // daily|weekly|monthly|custom
    "interval": 1, "weekdays": [1,3,5],
    "monthlyMode": "by_date", "endAt": "ts?",
    "nextInstanceAt": "ts?"
  },
  "parentTaskId": "str?",               // recurrence chain

  "reminder": { "enabled": true, "leadMinutes": 30, "notificationId": "str?" },
  "timeBlock": { "eventId": "str?", "start": "ts?", "end": "ts?" },

  "completedAt": "ts?", "completedIn": 84,   // minutes actually spent (if timed)
  "createdAt": "ts", "updatedAt": "ts", "deletedAt": "ts?"
}
```
**Indexes:**
`status ASC, dueAt ASC` · `category ASC, status ASC, dueAt ASC` ·
`status ASC, priority ASC, dueAt ASC` · `projectId ASC, status ASC`

---

## 9. AI, insights, notifications, reports

### 9.1 `users/{uid}/ai_conversations/{conversationId}`

```jsonc
{
  "id": "str",
  "title": "Why is my bench stalling?",
  "assistant": "coach",                 // coach | claude | copilot | (future: gpt|gemini|…)
  "assistantLocked": false,             // true when the user forced a provider
  "contextInjectionEnabled": true,
  "messageCount": 8,
  "lastMessageAt": "ts",
  "lastMessagePreview": "str",
  "tokenUsage": { "input": 12480, "output": 3210 },
  "archived": false, "pinned": false,
  "createdAt": "ts", "updatedAt": "ts"
}
```

### 9.2 `users/{uid}/ai_conversations/{cid}/messages/{messageId}`

```jsonc
{
  "id": "str", "role": "assistant",     // user | assistant | system | tool
  "content": "str",
  "assistant": "coach",
  "model": "claude-opus-5",
  "routedBy": "auto",                   // auto | user_override
  "routeIntent": "fitness",
  "contextSnapshotId": "str?",          // → the exact context that was injected
  "toolCalls": [
    { "name": "log_meal", "arguments": {}, "status": "awaiting_confirmation" }
  ],
  "tokenUsage": { "input": 3120, "output": 610 },
  "latencyMs": 1840,
  "safetyFlags": [],
  "feedback": "up",                     // up | down | null
  "createdAt": "ts"
}
```

### 9.3 `users/{uid}/ai_usage/{yyyy-MM}`

```jsonc
{
  "period": "2026-08",
  "byAssistant": { "coach": { "requests": 84, "inputTokens": 210400, "outputTokens": 54200 } },
  "totals": { "requests": 141, "inputTokens": 402100, "outputTokens": 96300,
              "estimatedCostUsd": 0.62 },
  "dailyBudgetTokens": 60000,
  "budgetExceededDays": 0,
  "updatedAt": "ts"
}
```

### 9.4 `users/{uid}/insights/{insightId}`

```jsonc
{
  "id": "str",
  "localDate": "2026-08-29",
  "category": "nutrition",              // nutrition|training|recovery|sleep|body|productivity|habit
  "type": "protein_below_target",
  "severity": "medium",                 // info | low | medium | high
  "confidence": 0.86,
  "impact": 0.72,
  "rank": 1,

  "headline": "Protein intake is below target",
  "body": "5 of the last 7 days averaged 168 g against your 200 g floor. Protein is the single lever protecting lean mass in a deficit.",

  "evidence": {
    "signals": [
      { "key": "nutrition.protein.avg7d", "value": 168, "unit": "g" },
      { "key": "nutrition.protein.floor", "value": 200, "unit": "g" },
      { "key": "nutrition.protein.daysBelow7d", "value": 5, "unit": "days" }
    ],
    "rule": "PROTEIN_FLOOR_MISS",
    "window": { "from": "2026-08-22", "to": "2026-08-28" }
  },

  "action": {
    "label": "Add a 40 g protein snack",
    "type": "log_meal_template",
    "payload": { "mealId": "str" },
    "deeplink": "/nutrition/log?template={id}"
  },

  "status": "new",                      // new | seen | acted | dismissed
  "feedback": null,                     // up | down | null
  "engineVersion": "dna-1.0.0",
  "generatedAt": "ts", "expiresAt": "ts"
}
```
**Indexes:** `status ASC, rank ASC, generatedAt DESC` · `category ASC, generatedAt DESC`

### 9.5 `users/{uid}/notifications/{notificationId}`

```jsonc
{
  "id": "str",
  "category": "supplement",
  "title": "Time for creatine",
  "body": "5 g — post-workout",
  "priority": 60,
  "scheduledFor": "ts", "deliveredAt": "ts?",
  "channel": "local",                   // local | fcm
  "status": "delivered",                // scheduled | delivered | suppressed | cancelled | failed
  "suppressionReason": null,            // quiet_hours | daily_cap | already_satisfied | disabled
  "actions": [ { "id": "log", "label": "Taken" }, { "id": "snooze", "label": "Snooze 15 min" } ],
  "actionTaken": "log", "actionTakenAt": "ts",
  "deeplink": "/me/supplements",
  "payload": { "supplementId": "str" },
  "createdAt": "ts"
}
```

### 9.6 `users/{uid}/reports/{reportId}`  *(reportId = `weekly_2026-W35`)*

```jsonc
{
  "id": "weekly_2026-W35",
  "type": "weekly",                     // weekly | monthly | quarterly
  "period": { "from": "2026-08-24", "to": "2026-08-30", "label": "Week 35" },
  "metrics": {
    "weight":     { "current": 89.4, "previous": 90.1, "delta": -0.7, "unit": "kg", "direction": "good" },
    "bodyFat":    { "current": 30.8, "previous": 31.3, "delta": -0.5, "unit": "%",  "direction": "good" },
    "workouts":   { "current": 6, "previous": 5, "delta": 1, "unit": "sessions", "direction": "good" },
    "volume":     { "current": 84200, "previous": 79100, "delta": 5100, "unit": "kg", "direction": "good" },
    "sleepAvg":   { "current": 421, "previous": 436, "delta": -15, "unit": "min", "direction": "bad" },
    "recoveryAvg":{ "current": 78, "previous": 74, "delta": 4, "unit": "score", "direction": "good" },
    "proteinAvg": { "current": 186, "previous": 174, "delta": 12, "unit": "g", "direction": "good" },
    "proteinFloorHitRate": { "current": 42.8, "previous": 28.5, "delta": 14.3, "unit": "%", "direction": "good" },
    "nutritionConsistency": { "current": 85.7, "previous": 71.4, "delta": 14.3, "unit": "%", "direction": "good" },
    "supplementCompliance": { "current": 91.4, "previous": 88.5, "delta": 2.9, "unit": "%", "direction": "good" },
    "taskCompletion": { "current": 78.9, "previous": 64.2, "delta": 14.7, "unit": "%", "direction": "good" },
    "strengthGains": [ { "exerciseId": "incline-dumbbell-press", "e1rmDelta": 2.1, "pct": 5.1 } ]
  },
  "highlights": ["str"], "concerns": ["str"],
  "narrative": "str",                   // LLM-written, schema-constrained
  "shareImagePath": "str?",
  "engineVersion": "report-1.0.0",
  "generatedAt": "ts"
}
```

### 9.7 `users/{uid}/devices/{deviceId}` and `users/{uid}/sync_state/{sourceId}`

```jsonc
// devices/{deviceId}
{ "deviceId": "str", "fcmToken": "str", "platform": "android", "osVersion": "14",
  "appVersion": "1.0.0", "model": "SM-S928B", "timezone": "Africa/Cairo",
  "lastSeenAt": "ts", "notificationsPermitted": true, "createdAt": "ts" }

// sync_state/{sourceId}   sourceId ∈ health_connect | galaxy_fit3 | google_cal_{accountId} | …
{ "sourceId": "str", "cursor": "str?", "changesToken": "str?",
  "lastSuccessAt": "ts", "lastAttemptAt": "ts",
  "status": "healthy", "recordsSynced": 12840, "consecutiveFailures": 0,
  "lastError": "str?", "backfill": { "complete": true, "cursorDate": "2026-05-31" },
  "updatedAt": "ts" }
```

---

## 10. Composite indexes

`firebase/firestore.indexes.json` (authoritative file; this table is the rationale).

| Collection | Fields | Serves |
|---|---|---|
| `nutrition_logs` | `localDate ASC, loggedAt ASC` | Day view, ordered |
| `nutrition_logs` | `foodId ASC, loggedAt DESC` | "Recent" + frequency |
| `nutrition_logs` | `mealSlot ASC, localDate DESC` | Slot history |
| `water_logs` | `localDate ASC, loggedAt ASC` | Hydration day view |
| `meals` | `isFavorite DESC, lastUsedAt DESC` | Favourites |
| `meals` | `type ASC, useCount DESC` | Template picker |
| `supplement_logs` | `localDate ASC, takenAt ASC` | Day compliance |
| `supplement_logs` | `supplementId ASC, localDate DESC` | Per-supplement compliance |
| `workout_sessions` | `localDate DESC` | History list |
| `workout_sessions` | `status ASC, startedAt DESC` | Resume in-progress |
| `workout_sessions` | `templateId ASC, startedAt DESC` | Template history |
| `sets` **(CG)** | `exerciseId ASC, performedAt DESC` | Exercise history / "last time" |
| `sets` **(CG)** | `exerciseId ASC, e1rm DESC` | PR detection |
| `personal_records` | `exerciseId ASC, type ASC, achievedAt DESC` | PR list per exercise |
| `body_metrics` | `localDate DESC` | Weight chart |
| `health_records` | `type ASC, startAt DESC` | Metric timeline |
| `health_records` | `localDate ASC, type ASC` | Daily aggregation |
| `calendar_events` | `localDate ASC, startAt ASC` | Day/week view |
| `calendar_events` | `calendarId ASC, startAt ASC` | Per-calendar filter |
| `tasks` | `status ASC, dueAt ASC` | Today / Upcoming |
| `tasks` | `category ASC, status ASC, dueAt ASC` | Category view |
| `tasks` | `status ASC, priority ASC, dueAt ASC` | Priority ordering |
| `insights` | `status ASC, rank ASC, generatedAt DESC` | Dashboard insights |
| `ai_conversations` | `archived ASC, lastMessageAt DESC` | Hub list |
| `notifications` | `scheduledFor DESC` | History |
| `foods` **(root)** | `searchTokens ARRAY, popularity DESC` | Remote food search |
| `exercises` **(root)** | `muscleGroup ASC, popularity DESC` | Faceted exercise browse |

---

## 11. Security rules

`firebase/firestore.rules` is authoritative. Design:

```javascript
rules_version = '2';
service cloud.firestore {
  function isSignedIn()      { return request.auth != null; }
  function isOwner(uid)      { return isSignedIn() && request.auth.uid == uid; }
  function isVerified()      { return isSignedIn() && request.auth.token.email_verified == true; }
  function notChangingOwner(){ return !('uid' in request.resource.data)
                                    || request.resource.data.uid == resource.data.uid; }

  match /databases/{db}/documents {

    // ---------- Global read-only catalogues ----------
    match /exercises/{id}          { allow read: if isSignedIn(); allow write: if false; }
    match /foods/{id}              { allow read: if isSignedIn(); allow write: if false; }
    match /supplement_catalog/{id} { allow read: if isSignedIn(); allow write: if false; }
    match /programs_library/{id}   { allow read: if isSignedIn(); allow write: if false; }
    match /app_config/{id}         { allow read: if isSignedIn(); allow write: if false; }

    // ---------- User subtree ----------
    match /users/{uid} {
      allow read:   if isOwner(uid);
      allow create: if isOwner(uid) && request.resource.data.uid == uid;
      allow update: if isOwner(uid) && notChangingOwner()
                    && !request.resource.data.diff(resource.data)
                          .affectedKeys().hasAny(['subscription','targets.computedAt']);
      allow delete: if false;                       // deletion goes through a callable

      // Client-writable collections
      match /{col}/{docId} {
        allow read, write: if isOwner(uid) && col in [
          'settings','nutrition_logs','meals','meal_plans','water_logs',
          'supplements','supplement_logs','supplement_purchases',
          'workout_templates','workout_programs','workout_sessions',
          'custom_exercises','body_metrics','body_photos','tasks',
          'ai_conversations','devices'
        ];
      }

      // Sets live one level deeper and are append-only
      match /workout_sessions/{sid}/sets/{setId} {
        allow read:   if isOwner(uid);
        allow create: if isOwner(uid);
        allow update: if isOwner(uid);               // in-session edits
        allow delete: if isOwner(uid);
      }

      match /ai_conversations/{cid}/messages/{mid} {
        allow read:   if isOwner(uid);
        allow create: if isOwner(uid) && request.resource.data.role == 'user';
        allow update: if isOwner(uid)
                      && request.resource.data.diff(resource.data)
                            .affectedKeys().hasOnly(['feedback']);
        allow delete: if isOwner(uid);
      }

      // Server-derived: read-only to the client
      match /{col}/{docId} {
        allow read:  if isOwner(uid) && col in [
          'daily_stats','daily_plans','recovery_data','sleep_data',
          'health_records','insights','reports','notifications',
          'personal_records','ai_usage','sync_state','calendar_accounts','calendar_events'
        ];
        allow write: if false;
      }

      // Insight/notification feedback is the one client write on a derived doc
      match /insights/{id} {
        allow update: if isOwner(uid)
                      && request.resource.data.diff(resource.data)
                            .affectedKeys().hasOnly(['status','feedback']);
      }
    }

    // ---------- Server-only ----------
    match /_admin/{document=**} { allow read, write: if false; }

    // Default deny
    match /{document=**} { allow read, write: if false; }
  }
}
```

**Storage rules** (`firebase/storage.rules`): a user may read/write only under
`users/{uid}/**`, images only (`request.resource.contentType.matches('image/.*')`),
maximum 8 MB per object, and export objects are written by functions only and read via
signed URLs.

---

## 12. Local (Drift) schema

The client mirrors a subset for offline speed and for the write outbox.

```dart
// Tables (abridged) — app/lib/core/database/tables.dart
class Exercises        // full catalogue, shipped as an asset, ~400 rows
class Foods            // top 5 000 by popularity + every food the user has ever logged
class NutritionEntries // mirrors nutrition_logs
class WaterEntries
class SupplementDefs
class SupplementEntries
class WorkoutTemplates
class WorkoutSessionsLocal
class WorkoutSetsLocal // the authoritative store during a live session
class BodyMetricsLocal
class TasksLocal
class CalendarEventsCache
class DailyStatsCache
class Outbox           // id, op, collectionPath, payload, attempts, nextAttemptAt, lastError
class SyncMeta         // per-source cursors
```

- Encrypted with SQLCipher; the key lives in the platform keystore.
- Schema version is explicit; every migration has an up-migration test.
- `WorkoutSetsLocal` is the **authoritative** store while a session is `in_progress`.
  Firestore becomes authoritative only after `finishedAt` is written.

---

## 13. Data lifecycle

| Data | Hot | Warm | Cold / Deleted |
|---|---|---|---|
| `health_records` | 90 days on device | 400 days in Firestore | Compacted into `daily_stats`, raw deleted |
| `nutrition_logs` | 90 days on device | Indefinite | User-initiated deletion only |
| `sets` | Current + last session per exercise on device | Indefinite | User-initiated deletion only |
| `ai_conversations` | 30 days on device | 12 months | Auto-archived, then purged on request |
| `notifications` | — | 30 days | Auto-deleted |
| `daily_stats` | 14 days on device | Indefinite | Never auto-deleted |
| `body_photos` | — | Indefinite | Deleted with the account |

**Account deletion (`deleteAccount` callable)**
1. Set `users/{uid}.deletedAt`, revoke all sessions, disable auth user.
2. Enqueue a purge task: recursive subtree delete, Storage prefix delete,
   `_admin/oauth_tokens` delete + provider token revocation, FCM token delete.
3. Emit a completion record to an audit log holding **no** personal data.
4. Complete within 30 days; confirmation email on completion.

---

## 14. Migration policy

- Every document carries an implicit shape version through `engineVersion` (derived docs)
  or an explicit `schemaVersion` field added at the first breaking change.
- Additive changes ship freely. Breaking changes require: a migration Cloud Function, a
  dual-read window of ≥ 2 client releases, and a backfill run against staging first.
- The client tolerates unknown fields and missing optional fields by construction (all DTO
  parsing uses defaults, never `!`).
