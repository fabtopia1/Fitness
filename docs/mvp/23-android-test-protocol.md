# Android Device Testing Protocol

**Owner:** QA Director. How device testing is *run* — the scripts themselves
are `20-device-validation-scripts.md`, the Samsung specifics are
`26-samsung-device-checklist.md`.

---

## 1. What counts as a valid test run

A run is void unless all four hold:

| | Requirement | Why |
| --- | --- | --- |
| 1 | The artefact came from **CI**, not a local `flutter run` | A local run is debug: R8 has not run, the signing certificate differs, and `kDebugMode` copy is visible. The R8 and SHA-1 defects are invisible in it |
| 2 | It is the **release** build type | H-2 (reminders lost after reboot) reproduces only in a shrunk build |
| 3 | The device is **physical** | Doze, Keystore, Samsung app sleeping and the camera do not exist on an emulator |
| 4 | `adb logcat` was captured for the whole session | A failure without a log is a rumour |

## 2. Device matrix

Minimum for the beta. One device cannot cover it: Android 14 changed
notification permissions and Android 15 changed edge-to-edge defaults.

| Slot | Device class | Android | Purpose |
| --- | --- | --- | --- |
| **A** | Samsung flagship (S23/S24) | 14 or 15 | Primary. All 12 scripts |
| **B** | Samsung mid-range (A54 or similar) | 13 or 14 | One UI battery management, lower RAM |
| **C** | Any second device | any | Scripts 1, 2, 7, 8, 12 — the two-device cases |

Slot C exists because Script 12 (two-device sync) and Script 8 (the C-3 race)
cannot be run on one phone, and C-3 is the defect whose entire symptom was
*"invisible until a second device pulled"*.

## 3. Session setup

```bash
# Record everything. Timestamped, because a report says "around 3pm".
adb logcat -c
adb logcat -v time > "run-$(date +%Y%m%d-%H%M)-$(adb shell getprop ro.product.model | tr -d '\r').log" &

# Fingerprint the exact build under test.
adb shell dumpsys package os.lifedna.lifedna | grep -E "versionName|versionCode|firstInstallTime"
adb shell getprop ro.build.fingerprint

# Install WITHOUT uninstalling, so the migration path is exercised (see
# 22-encrypted-data-migration.md §7). Uninstalling first proves nothing.
adb install -r app-prod-release.apk
```

Useful filters:

```bash
adb logcat -s google_sign_in          # C-2 — the clientId warning
adb logcat -s flutter_local_notifications  # H-2 — Gson after reboot
adb logcat -s flutter | grep -i hive  # C-1 — the migration probe message
```

## 4. Running a script

1. **Reset to a known state** — the script says which: fresh install, signed
   in, or mid-workout. Do not inherit state from the previous script.
2. Follow the steps in order. A skipped step voids the script.
3. Record the result **per step**, not per script. "Script 5 failed" is not
   actionable; "Script 5 step 4, visible stutter on the clock" is.
4. On failure: capture the logcat excerpt, screenshot, `dumpsys` if relevant,
   and **stop that script**. Do not work around a failure to reach the end.

## 5. Severity and escalation

| Severity | Definition | Action |
| --- | --- | --- |
| **S1 — Blocker** | Data loss, lockout, or a critical script (2, 8, 11) failing | Stop testing. Beta does not open. Notify the release manager immediately |
| **S2 — Major** | A user-facing function does not work, no workaround | Fix before the beta opens |
| **S3 — Minor** | Works with a workaround, or cosmetic on one device | Ship with it, log in `14-technical-debt.md` |
| **S4 — Observation** | Not wrong, worth knowing | Note only |

**Any suspected data loss is S1 by default** until proven otherwise. The
history of this codebase is two defects — C-1 and C-3 — whose entire nature was
that data disappeared without an error, so "the tester probably didn't save it"
is not an acceptable first hypothesis.

## 6. Reporting

One row per step that failed:

```
Script / step   : 5 / 4
Device          : SM-S911B, Android 14, One UI 6.1
Build           : 1.0.0+1 prod release, CI run #142
Severity        : S2
Expected        : clock counts smoothly, no dropped frames
Observed        : ~1s stutter every 3rd tick after 20 sets
Logcat          : run-20260830-1412-SM-S911B.log lines 4102–4180
Reproduces      : 3/3
```

`Reproduces: 1/3` is a different bug from `3/3` and needs saying.

## 7. Exit criteria

The protocol is satisfied when:

- [ ] All 12 scripts pass on device **A**
- [ ] Scripts 1–6, 9, 10 pass on device **B**
- [ ] Scripts 1, 2, 7, 8, 12 pass with device **C** paired
- [ ] Migration verified per `22-encrypted-data-migration.md` §7 on A and B
- [ ] Zero S1 open
- [ ] Zero S2 open, or each accepted in writing by the release manager
- [ ] A logcat capture exists for every run
- [ ] The Samsung checklist (`26`) is complete on A and B

Sign-off goes in `28-release-signoff.md`.
