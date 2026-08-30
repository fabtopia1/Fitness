# Firebase Production Deployment Checklist

Everything that must exist in the Firebase console and be deployed before a
beta artefact is built. **Nothing here can be done from this repository** — it
needs console access — which is why it is the first item on the critical path.

Target: one project per environment, or one project with three Android apps.
Three `applicationId`s means three Android apps either way.

---

## 1. Project

- [ ] Project created (or the existing beta project identified)
- [ ] **Blaze plan** if Cloud Functions are wanted — see §7. Not needed for the
      beta itself
- [ ] Project location set (irreversible; pick the region nearest your testers)
- [ ] Support email set on the project — the Google sign-in provider cannot be
      saved without one, and its absence surfaces as `ApiException: 12500`

## 2. Android apps — one per flavour

| Flavour | applicationId |
| --- | --- |
| dev | `os.lifedna.lifedna.dev` |
| staging | `os.lifedna.lifedna.staging` |
| prod | `os.lifedna.lifedna` |

For each one being shipped:

- [ ] App registered with the exact package name above
- [ ] **Release** SHA-1 added
- [ ] **Debug** SHA-1 added for each developer machine
- [ ] **Play app-signing** SHA-1 added — Play re-signs the upload, so sign-in
      works on the sideloaded APK and fails on the same build installed from
      Play unless this is present
- [ ] `google-services.json` downloaded to
      `app/android/app/src/<flavour>/google-services.json`

```bash
# Release SHA-1 — the one testers' installs are signed with.
keytool -list -v -alias "$KEY_ALIAS" -keystore /path/to/upload-keystore.jks

# Debug SHA-1 — different on every machine.
keytool -list -v -alias androiddebugkey \
  -keystore ~/.android/debug.keystore -storepass android -keypass android
```

Play app-signing SHA-1: Play Console → your app → **Setup → App integrity →
App signing key certificate**.

## 3. Authentication

- [ ] **Email/Password** enabled
- [ ] **Google** enabled, with the support email set
- [ ] Web client ID copied from *Sign-in method → Google → Web SDK
      configuration* into `GOOGLE_SERVER_CLIENT_ID_PROD`
- [ ] Authorised domains reviewed (defaults are fine for Android-only)
- [ ] Quota checked — the free tier is far above 50 testers

> The **web** client is the ID-token audience. The Android client is what lets
> the picker open. Passing the Android id as `serverClientId` reproduces the
> C-2 symptom with a different cause. Full detail:
> `18-google-auth-verification.md`.

## 4. Firestore

- [ ] Database created in **Native** mode (not Datastore — irreversible)
- [ ] Location set (irreversible)
- [ ] Rules deployed **before** the first client connects:

```bash
firebase use <project-id>
firebase deploy --only firestore:rules,firestore:indexes
```

- [ ] Verify in the console that the deployed rules match `firebase/firestore.rules`
- [ ] Confirm the default allow-all rule is **gone** — a new database ships
      with a 30-day open rule, and an open database with 50 real users' health
      data is a reportable incident, not a bug

Local proof, which is not a substitute for deploying:

```bash
cd firebase/rules-test && npm ci && npm run emulator   # 39 tests
```

## 5. Storage

- [ ] Only if progress-photo upload is wanted. **The beta does not need it** —
      photos are device-local by design, and Script 10 depends on that
- [ ] If enabled, deploy `firebase/storage.rules` and re-verify Script 10

## 6. Crashlytics

- [ ] Enabled for each Android app
- [ ] First release build produces a mapping file, uploaded by the Gradle
      plugin (which requires `google-services.json` — §2)
- [ ] **Force one crash from a release build and confirm it arrives
      symbolicated.** If the first report is `a.b.c(Unknown Source)`, the
      mapping did not upload and every report for the whole beta is unreadable
- [ ] Velocity alerts on, routed to a real inbox

## 7. Cloud Functions — deliberately out of scope

`firebase.json` declares `firestore` and `storage` only. `functions/` exists
and contains `onNutritionLogWrite` plus the shared engines, but:

- The app has **no `cloud_functions` dependency** and calls no callable.
- The one trigger maintains a server-side aggregate the client does not read —
  macros are computed on-device by the Dart engines, which the parity job binds
  to the TypeScript ones.

So the beta works without them, and adding a `functions` block would make every
deploy require Blaze billing. This is a decision, not an oversight. To deploy
them later:

```bash
cd functions && npm ci && npm run build
firebase deploy --only functions   # needs a functions block in firebase.json
```

## 8. Analytics

- [ ] Enabled (or deliberately not — the app gates on consent either way)
- [ ] Note: `Env.analyticsEnabled` is false for the `dev` flavour by design

## 9. Quotas and cost for 50 testers

Well inside the free tier, but set the guardrails anyway:

- [ ] Budget alert at a token amount (£5) — it will not fire, and it is the
      cheapest possible detector of a sync loop
- [ ] Firestore usage dashboard bookmarked

Rough ceiling: 50 users × ~200 writes/day ≈ 10 k writes/day, against a 20 k/day
free quota. A runaway retry loop is the only realistic way to exceed it, which
is why `28`'s watch list tracks parked outbox entries.

## 10. Sign-off

| Item | Done by | Date |
| --- | --- | --- |
| Project + apps registered | | |
| All SHA-1s registered (release, debug, Play) | | |
| Auth providers enabled | | |
| Rules + indexes deployed and verified | | |
| Crashlytics receiving a symbolicated crash | | |
| Budget alert set | | |

Until every row is filled, `tool/verify_release.sh prod` reports blockers and
the build must not be distributed.
