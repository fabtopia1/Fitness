# Play Internal Testing — Launch Plan

Target: **50 testers within 48 hours.** Internal testing, not closed or open —
it has no review wait, admits up to 100 testers, and updates go live in
minutes.

---

## 1. Why Internal, not Closed

| Track | Review | Testers | Time to live |
| --- | --- | --- | --- |
| **Internal** | None | 100 | Minutes |
| Closed | Full app review | Unlimited | Days |
| Open | Full review + policy scrutiny | Unlimited | Days |

Internal testing is the only track that fits 48 hours. It still requires the
app record, the store listing basics, and the content declarations — those are
**not** waived, and they are the usual reason a first upload stalls.

## 2. Critical path

Strictly ordered. Each step blocks the next.

```
Firebase project + SHA-1s          (27)   ~2 h, needs console access
        ↓
Upload keystore generated + stored (§3)   ~15 min, irreversible if lost
        ↓
tool/verify_release.sh prod        green  ~2 min
        ↓
tool/build_release.sh prod both           ~20 min
        ↓
Device scripts 2, 8, 11 pass       (20)   ~2 h, needs 2 devices
        ↓
Play app record + declarations     (§4)   ~1 h, the usual stall
        ↓
Upload AAB → Internal testing      (§5)   ~15 min
        ↓
Testers added, link sent           (§6)
```

Two items on that path cannot be done from this repository and have no
workaround: the **Firebase console** and the **Play Console**.

## 3. Upload keystore

Generate once. **Losing it means you can never update this Play listing
again** — there is no recovery, only a new app with a new URL and no installs.

```bash
keytool -genkey -v \
  -keystore ~/lifedna-upload-keystore.jks \
  -storetype JKS -keyalg RSA -keysize 2048 -validity 10000 \
  -alias lifedna-upload

cp ~/lifedna-upload-keystore.jks app/android/app/upload-keystore.jks
cp app/android/key.properties.example app/android/key.properties
# fill in storePassword / keyAlias / keyPassword
```

- [ ] Keystore backed up somewhere that survives this laptop
- [ ] Passwords in a password manager, not a note
- [ ] SHA-1 registered in Firebase (`27` §2)
- [ ] **Play App Signing enrolled** at upload — Google holds the app signing
      key and the upload key becomes replaceable, which removes the
      single-point-of-failure above. Enrol; then register Play's app-signing
      SHA-1 in Firebase too, or sign-in works sideloaded and fails from Play

## 4. Play Console — the app record

Internal testing still needs all of this before an upload is accepted:

- [ ] App created: name, default language, **App** (not Game), **Free**
- [ ] App access — if sign-in is required, either provide test credentials or
      state that a local mode exists. LifeDNA has **Continue without an
      account**, so say so; it removes a review question
- [ ] **Data safety** form. This one is not a formality — it is a legal
      declaration and it must match the code:

| Data | Collected | Shared | Purpose | Notes |
| --- | --- | --- | --- | --- |
| Email address | Yes | No | Account management | Firebase Auth |
| Name | Yes | No | Account management | Optional |
| Health & fitness | Yes | No | App functionality | Encrypted in transit; encrypted at rest on device |
| Photos | **No** (not collected) | No | — | Progress photos never leave the device |
| Crash logs | Yes | No | Diagnostics | Crashlytics, user-toggleable |
| Diagnostics | Yes | No | Analytics | Analytics, user-toggleable |

- [ ] **Health apps declaration** — LifeDNA logs fitness and body measurements.
      It declares **no** Health Connect permissions (the native reader is not
      in this build), which keeps the declaration simple. Do not add health
      permissions to the manifest before shipping, or this becomes a review item
- [ ] Content rating questionnaire completed
- [ ] Target audience: **18+** (the app already enforces 18+ at onboarding)
- [ ] Ads: **No**
- [ ] Privacy policy URL — **required even for internal testing**, must be a
      live public URL
- [ ] Store listing: short description, full description, app icon (512×512),
      feature graphic (1024×500), ≥ 2 phone screenshots

> The privacy policy URL and the feature graphic are the two most common
> reasons a first internal-testing upload is blocked. Neither is code.

## 5. Upload

```bash
set -a && . app/.env.release && set +a
tool/verify_release.sh prod        # must exit 0
tool/build_release.sh prod both
```

Upload `app/build/app/outputs/bundle/prodRelease/app-prod-release.aab` to
**Testing → Internal testing → Create new release**.

- [ ] AAB uploaded and accepted
- [ ] Release name: `1.0.0+1 — closed beta`
- [ ] Release notes written for testers (what to try, how to report)
- [ ] **Upload `mapping.txt`** if Play does not ingest it automatically —
      without it every crash report is unreadable
- [ ] Review the pre-launch report after it runs (Play tests on real devices;
      free signal you did not have to gather)

### If the upload is rejected

| Message | Cause | Fix |
| --- | --- | --- |
| "You uploaded a debug-signed APK" | No `key.properties` | §3 — and note the build no longer falls through silently on a *partial* config |
| "Version code already used" | Re-upload of the same build | Bump `version:` in `pubspec.yaml` |
| "You need to declare permissions" | A permission without a use case | The manifest declares only 5, each traced to a call site |
| "Missing privacy policy" | §4 | A live public URL |

## 6. Testers

- [ ] Email list created under **Internal testing → Testers**, ≤ 100 addresses
- [ ] **Each address must be a Google account** — a work address that is not a
      Google account silently cannot accept the invitation, and this is the
      most common "the link doesn't work" report
- [ ] Opt-in URL copied and sent
- [ ] Onboarding note sent with it: install link, what to test, how to report,
      and that progress photos stay on their device

Sample note:

> LifeDNA OS beta — thanks for helping.
> 1. Open the link on your Android phone and tap **Become a tester**.
> 2. Install from Play (not a sideloaded file), then sign in.
> 3. Use it as you normally would for a week — meals, workouts, supplements.
> 4. Please try one thing deliberately: log a workout in **airplane mode**,
>    then turn it off and check everything is still there.
> 5. Report anything odd with a screenshot and roughly when it happened.
> Progress photos never leave your phone. You can turn analytics and crash
> reports off in Settings.

## 7. Day-one monitoring

| Signal | Where | Threshold |
| --- | --- | --- |
| Crash-free users | Crashlytics | < 99 % → stop the intake |
| `google_id_token_missing` | Crashlytics | Any → the artefact lacks its client id; rebuild, do not debug the device |
| Storage recovery screen reached | Crashlytics | Any → capture the reason code before anything else |
| Firestore writes | Firebase usage | > 20 k/day → a retry loop |
| Install failures | Play → Statistics | > 5 % → device compatibility |

## 8. Rollback

Internal testing has no staged rollout. To pull a bad build: upload the
previous AAB with a **higher** version code — Play will not accept a lower one,
so there is no true "roll back", only "roll forward to the old code".

- [ ] Keep the previous AAB **and its mapping.txt**
- [ ] Keep `version:` in `pubspec.yaml` ahead of the last uploaded code

## 9. Go / no-go

Open the beta only when all hold:

- [ ] `tool/verify_release.sh prod` exits 0
- [ ] AAB accepted by Play
- [ ] Device Scripts **2, 8, 11** pass on a Play-installed build
- [ ] Migration verified per `22` §7
- [ ] Crashlytics has received one **symbolicated** test crash
- [ ] Firestore rules deployed and confirmed in the console
- [ ] Privacy policy live
- [ ] Rollback AAB and mapping archived
