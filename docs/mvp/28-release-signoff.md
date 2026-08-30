# Release Sign-Off — LifeDNA OS Closed Beta

**Role:** Release Manager / QA Director · **Feature development: frozen**
**Question:** can this support 50 beta testers next week?

---

## 1. C-1 verification — was it actually solved?

**It was not.** Verifying it rather than accepting the previous report found
that the design rested on a false premise, and that the real behaviour is worse
than the defect as originally described.

### What was claimed

> A mode mismatch throws; `main` catches `StorageUnavailable` and shows a
> recovery screen.

### What actually happens

Measured on a real Hive box, not reasoned about:

```
written, length=1
file size before: 49
OPEN SUCCEEDED. length=0 value=null      <-- no exception thrown
file size after: 0                       <-- file truncated
REOPENED PLAINTEXT: length=0 value=null  <-- data gone
```

Hive's default `crashRecovery: true` does not throw on an unparseable box. It
concludes the file is damaged, **truncates it to zero, and returns an empty box
reporting success**. A mode mismatch was therefore never a lockout — it was
**immediate, silent, total data destruction at open time**, before any `catch`
could run. The recovery screen could not have fired for it.

Worse, the trigger was live: any install predating the encryption marker, whose
keystore holds a key while the boxes are plaintext — exactly what the old
silent fallback produced — would have had every box zeroed on first launch of
the new build.

### Additional lockout paths found

| | Defect |
| --- | --- |
| 2 | The storage-state marker box was opened unguarded. A raw `HiveError` there escaped as an ordinary bootstrap failure → retry-only screen. Same lockout, different door |
| 3 | A partial open left boxes open. Hive caches by name and **ignores the cipher for an already-open box**, so a retry silently got boxes on the first cipher — one store in two modes |
| 4 | The generic bootstrap failure screen offered only a retry |
| 5 | `resetLocalData` destroyed data outright, so a tester who tapped reset had no way back |
| 6 | `HiveStore.open()` had **zero test coverage**. Thirteen tests covered the pure resolver; the code using it had none, because it called `initFlutter` and could not be tested |

### Now

| Fix | Verified by |
| --- | --- |
| `crashRecovery: false` on every open — mismatch throws, file byte-identical | Measured both directions |
| One-shot migration probe adopts plaintext boxes when no mode was recorded | `hive_store_open_test.dart` |
| The probe is refused once a mode **is** recorded — no silent mode switch | same |
| Marker box rebuilt rather than fatal | same |
| Failed opens close what they opened | same |
| Reset quarantines, one generation, keeps the key | same |
| Both failure screens offer a two-tap reset | code + widget tests |
| `open()` takes a directory, so the real path is testable | 12 new on-disk tests |

**C-1 is now closed in code** — with the caveat that migration on a real device
(`22` §7, install-over-the-top) has not been run, because there is no artefact.

---

## 2. Remaining blockers

### CRITICAL — beta cannot open

| # | Blocker | Owner | Est. | Why it blocks |
| --- | --- | --- | --- | --- |
| **B1** | **No Firebase project, no OAuth clients, no SHA-1s registered.** Nothing in this repo can create them | Someone with console access | 2 h | Without them the build runs in local mode, Google sign-in cannot get an ID token, and Crashlytics uploads no mapping. `27` |
| **B2** | **No upload keystore exists.** No `key.properties`, no `.jks` | Release manager | 15 min | A release build would be debug-signed. Play rejects it; sign-in fails against an unregistered certificate. `25` §3 |
| **B3** | **No release artefact has ever been produced.** Not once, on any machine | CI | 30 min after B1–B2 | Everything downstream — install, device tests, Play upload — needs a file that does not exist. Cannot be done here: `dl.google.com` is denied by network policy and `/opt/android-sdk` is an empty stub |
| **B4** | **Firestore rules not deployed.** A new database ships with a 30-day allow-all rule | Firebase admin | 5 min | 50 users' health data in an open database is a reportable incident |
| **B5** | **No device testing has occurred.** Zero of the 12 scripts run | QA | 4 h after B3 | Every claim about reboot-surviving reminders, photo durability, Live Gym smoothness and two-device sync is structural, not observed |

### HIGH — must be settled before testers are added

| # | Blocker | Owner | Est. |
| --- | --- | --- | --- |
| **B6** | Migration not verified on a device. Install-over-the-top per `22` §7 | QA | 30 min |
| **B7** | Crashlytics has never received a symbolicated crash. If the first real one is `a.b.c(Unknown Source)`, every beta report is unreadable | QA | 20 min |
| **B8** | Play app record absent: data safety form, privacy policy URL, content rating, store assets. The usual reason a first upload stalls | Release manager | 1 h |
| **B9** | Smart Switch not tested. If it carries app data, every transferring Samsung tester lands in the C-1 recovery path | QA | 30 min |

### MEDIUM — accepted for the beta, tracked

| # | Item | Why acceptable |
| --- | --- | --- |
| B10 | No adaptive launcher icon | Cosmetic; needs artwork, not config |
| B11 | No `autoDispose` on any provider | Real, but a blanket change alters rebuild behaviour on every screen and is untested on hardware |
| B12 | Hive `Box` keeps values resident (~40 MB modelled at **five years** of heavy logging) | No tester reaches that in twelve weeks |
| B13 | Last-write-wins per document, by device clock | Documented; convergence is tested. Silent divergence — the unacceptable case — is what C-3 closed |
| B14 | Cloud Functions not in the deploy target | The app has no `cloud_functions` dependency and calls no callable. `27` §7 |
| B15 | A crash-damaged box no longer self-heals by truncation | Deliberate. Truncation loses the same data and says nothing |

---

## 3. System readiness

| System | Status | Basis |
| --- | --- | --- |
| **Authentication** | **BLOCKED** | Logic verified (26 tests, C-2 closed). Google sign-in cannot be exercised at all without a Firebase project and a registered SHA-1 — B1 |
| **Sync Engine** | **READY** | C-3 closed. 12 tests: the race directly, through `SyncedCollection`, through `SyncEngine`, and across two devices. Field confirmation pending B5 |
| **Database** | **READY** | Hive layer now correct and, for the first time, tested on disk. 12 new tests |
| **Storage** | **READY** | C-1 closed: no silent truncation, migration probe, quarantine, no dead-end screen. Device migration pending B6 |
| **Notifications** | **NOT READY** | Code and R8 rules correct, but the H-2 failure — reminders lost after a reboot — reproduces **only** in a shrunk release build on hardware. Untested: B3, B5 |
| **Calendar** | **BLOCKED** | Needs an OAuth client that does not exist — B1. Shipping it locked is a valid beta choice |
| **Supplements** | **NOT READY** | Logic tested; depends on notifications, so it inherits the same gap |
| **Workouts** | **NOT READY** | H-4 fixed and tested (the tick performs zero history reads), but "smooth over a 45-minute session" is structural until profiled on a device — B5 |
| **Body Tracking** | **NOT READY** | H-3 fixed with 19 tests; the cache-clear survival test is device-only — B5 |
| **Firebase** | **BLOCKED** | No project, no deployed rules — B1, B4 |
| **Offline Mode** | **READY** | Hive-first ordering, durable outbox, bounded cache. The strongest-evidenced system in the app |
| **Android Release** | **BLOCKED** | No SDK and no Google Maven here; no keystore anywhere — B2, B3 |
| **Play Store Deployment** | **BLOCKED** | No app record, no artefact, no privacy policy — B3, B8 |

**READY 4 · NOT READY 4 · BLOCKED 5**

---

## 4. The question

> **Can LifeDNA OS safely support 50 beta testers next week?**

## NO.

Not because the code is unsafe — the three critical code defects are closed and
602 tests pass — but because **no runnable artefact exists**, and nothing
downstream of that has been done.

### The exact blockers

1. **B1** — No Firebase project, OAuth clients or registered SHA-1s.
2. **B2** — No upload keystore. Any release build today is debug-signed.
3. **B3** — No release APK or AAB has ever been produced, on any machine.
4. **B4** — Firestore rules not deployed; a new database is open by default.
5. **B5** — Zero device testing. All 12 scripts unrun.
6. **B6** — Migration unverified on hardware.
7. **B7** — Crashlytics has never received a symbolicated crash.
8. **B8** — No Play app record, data safety form, or privacy policy URL.
9. **B9** — Smart Switch untested against `allowBackup=false`.

### Can they be cleared in a week?

Yes — the work is roughly **8–10 hours**, and none of it is engineering.
B1, B2, B4 and B8 need console access and credentials. B3 follows automatically.
B5–B7 and B9 need two Samsung devices and half a day.

The honest summary: **the software is ready to be built; the release is not
ready to ship.** Every remaining blocker is an operational one, and every one
of them is outside this repository.

---

## 5. Sign-off

| Role | Name | Verdict | Date |
| --- | --- | --- | --- |
| Release Manager | | NO-GO — B1…B9 open | 2026-08-30 |
| QA Director | | NO-GO — no device testing performed | 2026-08-30 |
| Firebase | | | |
| Android | | | |

Re-run this document when B1–B9 close. Go requires every CRITICAL and HIGH row
cleared and `tool/verify_release.sh prod` exiting 0.
