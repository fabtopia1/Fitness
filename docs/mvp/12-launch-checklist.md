# 12 — Launch checklist

Ordered by when it blocks. Everything in §1 must be true before an artefact is
uploaded anywhere.

## 1. Before the first upload — blocking

### Engineering
- [x] CI green on `main`: analyze, format, layers, 517 tests, coverage ≥ 80 %
- [x] 39 security-rules tests green against the emulator
- [x] Engine parity green (Dart ↔ TypeScript ↔ generated fixtures)
- [x] No secret, keystore or service-account key in the tree
- [ ] **Release APK installed on a physical device and every flow walked**
- [ ] **R8-shrunk release build verified** — configured, keep rules written,
      not yet exercised on hardware (TD-01)
- [ ] Emulator integration job green on `main`

### Firebase
- [ ] Three projects exist: `lifedna-dev`, `lifedna-staging`, `lifedna-prod`
- [ ] `firebase deploy --only firestore:rules,firestore:indexes` run against
      each
- [ ] Email/password and Google providers enabled
- [ ] The SHA-1 and SHA-256 of the **upload** key registered (Google Sign-In
      fails silently without them — the single most common launch failure)
- [ ] Budget alerts set on the production project
- [ ] Crashlytics receiving from a staging build

### Signing
- [ ] Upload keystore generated and stored in a password manager, not a repo
- [ ] `key.properties` present on the release machine and in CI secrets
- [ ] Play App Signing enrolled — losing an upload key is recoverable; losing
      an app signing key is not

## 2. Store listing

- [ ] App name: **LifeDNA OS**
- [ ] Short description (80 chars) and full description (4 000)
- [ ] Feature graphic 1024×500, icon 512×512
- [ ] At least four phone screenshots: dashboard, Live Gym Mode, nutrition, body
- [ ] Category: Health & Fitness
- [ ] Content rating questionnaire completed
- [ ] Target audience: adults; **not** designed for children
- [ ] Privacy policy URL, live before submission

## 3. Data safety declaration

Answer it from what the code actually does:

| Question | Answer |
|---|---|
| Does the app collect data? | Yes, when the user has an account |
| Personal info | Name, email address (account creation) |
| Health and fitness | Body measurements, workouts, nutrition |
| Photos | **Collected but never transmitted** — progress photos stay in app storage |
| Is data encrypted in transit? | Yes (Firestore TLS) |
| Is data encrypted at rest on device? | Yes (AES, key in the Android Keystore) |
| Can a user request deletion? | Yes — Settings → Erase data on this device; account deletion on request |
| Is data shared with third parties? | No |
| Analytics | Optional, **opt-in**, screen names and counts only |
| Crash reports | On by default, opt-out, no health values |

The `TelemetryService.checkParams` guard throws if a String parameter key
matches `email|name|food|meal|message|content|weight|height|value|note|title|
measurement|photo|address|phone`. It is unit-tested. That is the mechanical
reason the answers above stay true as the app grows.

## 4. Health data — read this before adding Health Connect

The MVP declares **no** health permissions, so no health declaration is
required for the first release.

When the native Health Connect reader ships (Sprint 6), all of the following
become blocking:
- [ ] Declare `READ_STEPS`, `READ_ACTIVE_CALORIES_BURNED`, `READ_SLEEP`,
      `READ_HEART_RATE` in the manifest
- [ ] Add the permissions-rationale activity
- [ ] Complete the Play Health Apps declaration form
- [ ] Confirm the privacy policy covers health data specifically
- [ ] Do not request a permission the app does not read

## 5. Legal and medical positioning

- [ ] The disclaimer appears on the welcome screen and in Settings:
      *"LifeDNA provides training and nutrition information for healthy adults.
      It is not a medical device and does not diagnose, treat or prevent any
      condition."*
- [ ] No claim to diagnose, treat, cure or prevent anything
- [ ] Safety clamps are surfaced, not hidden: the app tells the user when it
      reduced a requested deficit or pace, and why
- [ ] Terms of service and privacy policy published

## 6. Beta rollout

### Internal testing (week 1)
- [ ] Upload to the internal track
- [ ] 5–10 testers on real Samsung hardware
- [ ] Verify: onboarding, an offline day, a full workout, a reboot, a sign-out

### Closed testing (weeks 2–3)
- [ ] 20–50 testers
- [ ] Crash-free sessions ≥ 99.5 %
- [ ] Feedback channel with a triage owner
- [ ] Watch for: notification permission refusals, Google Sign-In failures
      (SHA mismatch), sync parking, battery complaints

### Production (week 4+)
- [ ] Staged rollout: 5 % → 20 % → 50 % → 100 %
- [ ] Halt on a crash-free rate below 99 % or an ANR rate above 0.5 %

## 7. Monitoring from day one

| Signal | Source | Threshold |
|---|---|---|
| Crash-free sessions | Crashlytics | ≥ 99.5 % |
| ANR rate | Play Console | ≤ 0.5 % |
| Cold start | Play Console vitals | ≤ 2 s |
| Parked outbox entries | in-app; a support signal | any report is investigated |
| Firestore reads/writes | Firebase console | against the modelled 45 writes/user/day |
| Sign-in failure rate | Firebase Auth | ≤ 2 % |

## 8. Rollback

1. Halt the staged rollout in the Play Console (takes effect in minutes).
2. Rules are versioned in git and deployed separately: `firebase deploy
   --only firestore:rules` from the previous tag reverts them independently of
   the client.
3. Because clients are offline-first, a bad release does not lose data — Hive
   still holds everything, and the outbox drains once a fixed build lands.
4. Publish a fix on the internal track first. Never straight to production.
