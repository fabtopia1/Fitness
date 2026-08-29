# Real Device Validation Scripts

**Phase 6.** Twelve scripts a tester runs on a physical Samsung device before
the beta opens. Each is executable by someone who did not write the app: exact
taps, exact expected results, pass or fail.

Every script exists because a specific defect fixed in this remediation can
only be *proved* fixed on real hardware — R8 has run, the Keystore is real, the
signing certificate is real, and Doze is real. A green test suite says nothing
about any of them.

---

## Preconditions

| Item | Value |
| --- | --- |
| Build | `prod` flavor, `--release`, signed with the **release** key |
| Source | The CI `build` job artifact, not a local `flutter run` |
| Install | `adb install -r app-prod-release.apk`, or sideload |
| Devices | Two Samsung devices, at least one on Android 14+ |
| Accounts | One Google account registered against the release SHA-1 |
| Logging | `adb logcat -v time > run.log` for the whole session |

> **A debug build passes tests that a release build fails.** R8 has not run, the
> signing certificate is different, and `kDebugMode` copy is visible. Running
> these against a debug build proves nothing about the beta artifact.

Record for each script: device model, Android version, build fingerprint,
pass/fail, and the logcat excerpt for any failure.

---

## Script 1 — First install and onboarding

Covers the cold path every one of the 50 testers takes.

| # | Action | Expected |
| --- | --- | --- |
| 1 | Uninstall any previous LifeDNA, then install the release APK | Installs without a Play Protect block |
| 2 | Launch from the home screen icon | Launch background matches the device theme — **no white flash on a dark-mode device** (H-6) |
| 3 | Wait for the first frame | Welcome screen, under 3 s on a mid-range device |
| 4 | Tap **Create account**, enter name / email / a 10+ character password | Accepted |
| 5 | Enter a 6-character password instead | Rejected inline with "Use at least 10 characters" — not a generic error |
| 6 | Complete onboarding: date of birth, sex, height, weight, goal | Each step advances; back returns without losing entries |
| 7 | Finish onboarding | Lands on Home with macro targets derived from the entered weight |
| 8 | Force-stop the app, reopen | Opens straight to Home. **No repeat of onboarding, no sign-in prompt** |

**Fail if:** the splash flashes white on a dark device; onboarding repeats;
targets are absent after entering height and weight.

---

## Script 2 — Google sign-in (C-2)

The blocker this remediation exists partly to close. Only reproducible on a
signed install.

| # | Action | Expected |
| --- | --- | --- |
| 1 | Sign out (Script 10), reach the sign-in screen | **Continue with Google** visible |
| 2 | Tap it | Google account picker opens |
| 3 | Choose an account | Returns signed in. **No error toast** |
| 4 | Check `adb logcat -s google_sign_in` | No `clientId is not supported on Android` warning |
| 5 | Firebase console → Authentication → Users | The account is listed with provider `google.com` |
| 6 | Home screen | Google display name shown |
| 7 | Force-stop, reopen | Still signed in, no picker |

**Fail if:** the app shows *"Google sign-in isn't set up on this build"* — that
is the C-2 guard firing, meaning no ID token was returned. **Fail if:** the
picker does not open and logcat shows `ApiException: 10` — the release SHA-1 is
not registered. Both diagnoses and their fixes are in
`18-google-auth-verification.md` §5.

---

## Script 3 — Meals

| # | Action | Expected |
| --- | --- | --- |
| 1 | Nutrition tab → **Add food** | Search opens with the keyboard up |
| 2 | Search a food, pick one, set a portion, save | Appears in today's log; the macro rings move |
| 3 | Add three more across different meal slots | Each lands in the slot chosen |
| 4 | Swipe to delete one | Removed; rings recalculate immediately |
| 5 | Force-stop, reopen, Nutrition tab | All remaining entries present with the same values |
| 6 | Change the device date to tomorrow, reopen | Today's log is empty; yesterday's is intact under history |

**Fail if:** any entry is missing after a restart, or the rings disagree with
the listed entries.

---

## Script 4 — Supplements and their reminders

| # | Action | Expected |
| --- | --- | --- |
| 1 | Supplements → add one with a dose time **4 minutes from now** | Saved and listed |
| 2 | If prompted for notifications, allow | Android 13+ permission dialog appears **here**, not at first launch |
| 3 | Lock the phone and wait | Notification fires within ~2 min of the set time (inexact alarms are deliberately imprecise) |
| 4 | Tap the notification | App opens on Supplements |
| 5 | Mark the dose taken | Marked; streak increments |
| 6 | Add a second reminder ~10 minutes out, then **reboot the device** | — |
| 7 | Do not open the app. Wait for the time | **The reminder still fires** |

Step 7 is the R8/Gson case (H-2). In a shrunk build without
`-keepattributes Signature`, `flutter_local_notifications` cannot deserialise
its stored schedule in the boot receiver and every reminder disappears
silently after the first reboot. It cannot be reproduced in a debug build.

**Fail if:** no notification after the reboot. Capture
`adb logcat -s flutter_local_notifications` and check for a Gson type error.

---

## Script 5 — Workouts and Live Gym (H-4)

| # | Action | Expected |
| --- | --- | --- |
| 1 | Train → create a workout with 3 exercises | Saved |
| 2 | Start it | Live Workout opens; clock runs from 00:00 |
| 3 | Log a set with **COMPLETE SET** | Haptic; set count increments; rest overlay counts down |
| 4 | Watch the clock for 60 s without touching anything | Counts smoothly. **No stutter, no dropped frames** |
| 5 | With Developer options → *Profile HWUI rendering* on, repeat step 4 | Bars stay under the green line |
| 6 | Log 20 sets across the three exercises | Each logs on one tap; "Last time" updates after each |
| 7 | Adjust rest with ±, then skip | Overlay responds immediately |
| 8 | Finish the workout | Summary shows sets, volume, and any PRs |
| 9 | Reopen a second workout after 45 minutes of use | Still responsive — no degradation with session count |

Steps 4–5 and 9 are H-4: the per-second tick used to rebuild the whole screen
and rescan the entire workout history three times a second, getting worse the
longer someone had used the app.

**Fail if:** visible jank on the clock, or a delay between tapping COMPLETE SET
and the count changing.

---

## Script 6 — Progress photos (H-3)

| # | Action | Expected |
| --- | --- | --- |
| 1 | Body → add measurement → **Take photo** | Camera opens |
| 2 | Take a photo and save the measurement | Thumbnail appears in the photo strip |
| 3 | Settings → Apps → LifeDNA → Storage → **Clear cache** (not Clear data) | — |
| 4 | Reopen LifeDNA → Body | **The photo is still there** |
| 5 | Add a second photo, then dismiss the sheet **without saving** | No new entry appears |
| 6 | Repeat step 5 five times, then check Storage → app size | Size does not grow by five photos |
| 7 | Delete a measurement that has a photo | Entry and thumbnail both gone |
| 8 | Firestore console → the `body_measurements` document | `photoPath` is a bare file name, **not** a `/data/user/0/...` path |

Steps 3–4 are the defect: photos lived in the cache directory, which Android
reclaims and every cleaner app empties. Step 8 is the second half — a device
path replicated to the cloud is meaningless on any other device and leaks the
package and Android user id.

**Fail if:** the photo is a broken-image placeholder after clearing the cache.

---

## Script 7 — Offline mode

| # | Action | Expected |
| --- | --- | --- |
| 1 | Signed in, sync idle. Turn **Wi-Fi and mobile data off** | Offline banner appears |
| 2 | Log a meal, a supplement dose, a set, and a measurement | All four save with no error and no spinner |
| 3 | Navigate every tab | Everything reads normally — nothing shows a loading state that never resolves |
| 4 | Force-stop, reopen while still offline | All four entries present |
| 5 | Check the sync indicator | Shows pending work, with a count |
| 6 | Turn networking back on | Banner clears; pending count reaches 0 within ~30 s |
| 7 | Firestore console | All four documents present with the values entered offline |

**Fail if:** any write is rejected while offline, or the pending count does not
reach zero after reconnecting.

---

## Script 8 — Airplane mode and the sync race (C-3)

This targets the defect directly: a queued write superseded by a newer one
while the first push is in flight.

| # | Action | Expected |
| --- | --- | --- |
| 1 | Airplane mode **on** | Offline banner |
| 2 | Start a workout and log **10 sets rapidly** — the highest-frequency write in the app | Each logs instantly |
| 3 | Airplane mode **off** | Sync drains |
| 4 | **Immediately** log 3 more sets while sync is still running | All accepted |
| 5 | Wait for the pending count to reach 0 | — |
| 6 | Firestore console → the session document | **All 13 sets present** |
| 7 | Toggle airplane mode on/off 5 times during an active sync | No crash; pending count still converges to 0 |
| 8 | Compare the on-device set count with Firestore | Identical |

Step 6 is the C-3 assertion. Before the fix, an older push completing after a
newer write had replaced it deleted the queue entry holding the newer payload:
the cloud kept the stale version forever while the device kept the current one,
so the divergence was invisible until a second device pulled.

**Fail if:** Firestore has fewer sets than the device. Record the exact count.

---

## Script 9 — Notification behaviour under Doze

| # | Action | Expected |
| --- | --- | --- |
| 1 | Schedule a reminder ~15 minutes out | Saved |
| 2 | `adb shell dumpsys deviceidle force-idle` | Device enters Doze |
| 3 | Wait past the scheduled time | Notification fires (late is acceptable — inexact alarms are the deliberate choice) |
| 4 | Settings → Apps → LifeDNA → Battery → **Restricted** | — |
| 5 | Schedule another and wait | May not fire. **The app must not crash or lose the schedule** |
| 6 | Return battery to Unrestricted, reopen the app | Pending reminders still listed |
| 7 | Samsung **Device care → Sleeping apps**: add LifeDNA, then reopen | App opens normally with data intact |

Step 7 is Samsung-specific and catches nothing on a Pixel: One UI's aggressive
app sleeping is the single most common cause of "my reminders stopped" reports
on Samsung hardware.

---

## Script 10 — Sign out

| # | Action | Expected |
| --- | --- | --- |
| 1 | Log at least one meal and one workout | Present |
| 2 | Settings → **Sign out** | Confirmation asked first |
| 3 | Confirm | Returns to Welcome |
| 4 | Sign in as a **different** account | — |
| 5 | Check every tab | **Empty.** No trace of the first account's data |
| 6 | Sign back in as the first account | Data returns after sync |

Step 5 is a privacy assertion, not a convenience one: on a shared device,
leaving one account's training log for the next person to read would be a
serious failure.

**Fail if:** any entry from the first account is visible under the second.

---

## Script 11 — App restore and the storage recovery path (C-1)

The failure that used to brick an install permanently.

| # | Action | Expected |
| --- | --- | --- |
| 1 | Use the app normally, log several entries | — |
| 2 | Force-stop 10 times in a row, reopening each time | Opens cleanly every time |
| 3 | Fill the device to under 100 MB free, then log an entry | Either saves, or fails with a message that names storage — never a silent loss |
| 4 | Free space and reopen | Data intact |
| 5 | **Samsung Smart Switch**: transfer to the second device | LifeDNA is *not* in the transfer list — `allowBackup=false` and the data-extraction rules exclude everything |
| 6 | Install the APK on the second device and sign in | Data downloads from the account; nothing is carried over locally |

### 11b — Forcing the recovery screen

Only if a spare device is available; it destroys local data.

| # | Action | Expected |
| --- | --- | --- |
| 1 | With data present, clear only the Keystore entry (or restore an app-data backup onto different hardware) | — |
| 2 | Launch | **The recovery screen appears** — "Your data can't be unlocked" — not a crash, not a dead splash |
| 3 | Tap **Try again** | Retries; same screen (correct — the key is genuinely gone) |
| 4 | Tap **Reset this phone's data** | A confirmation appears stating what is lost. **One tap must not reset** |
| 5 | Tap **Cancel** | Returns to the first screen; nothing deleted |
| 6 | Tap reset, then **Reset and continue** | App restarts into Welcome and is usable |
| 7 | Sign in | Data downloads from the account |

**Fail if:** step 2 shows a crash or a retry-only screen. That is the original
C-1 lockout, whose only escape was uninstalling — which destroyed the data.

---

## Script 12 — Two-device sync

| # | Action | Expected |
| --- | --- | --- |
| 1 | Sign in to the **same account** on both devices | Both reach Home |
| 2 | Device A: log a meal | Appears on A |
| 3 | Device B: pull to refresh | The meal appears on B |
| 4 | Device B: log a workout | — |
| 5 | Device A: refresh | The workout appears on A |
| 6 | Put **both** offline. Log a different meal on each | Each saves locally |
| 7 | Bring **A** online, wait for sync; then **B** | — |
| 8 | Refresh both | **Both meals present on both devices.** Neither overwrote the other |
| 9 | Edit the same measurement on both while offline, then sync both | The later `updatedAt` wins on both — the same value on each, never a blend |
| 10 | Device A: run a full workout offline while B is online and syncing | No interference; both converge |

Steps 6–9 are the multi-device half of C-3. A last-write-wins merge is
acceptable and documented; a *silent divergence* — where the two devices
disagree forever and neither shows an error — is not.

**Fail if:** after step 8 either device is missing an entry.

---

## Sign-off

The beta opens when all twelve pass on at least one Samsung device running
Android 14+, and Scripts 1, 2, 7, 8 and 12 pass on a second device.

| Script | Device / Android | Build | Result | Notes |
| --- | --- | --- | --- | --- |
| 1 First install and onboarding | | | | |
| 2 Google sign-in | | | | |
| 3 Meals | | | | |
| 4 Supplements and reminders | | | | |
| 5 Workouts and Live Gym | | | | |
| 6 Progress photos | | | | |
| 7 Offline mode | | | | |
| 8 Airplane mode and sync race | | | | |
| 9 Notifications under Doze | | | | |
| 10 Sign out | | | | |
| 11 App restore and recovery | | | | |
| 12 Two-device sync | | | | |

A failure in Script 2, 8, or 11 blocks the beta outright: those are the three
critical blockers this remediation closed, and a regression in any of them
returns the app to the state that made it unshippable.
