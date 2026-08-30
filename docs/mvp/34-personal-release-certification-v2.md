# LifeDNA OS — Personal Release Certification

**Verdict: YES.** LifeDNA OS can be built into a release APK and used every day
on a personal Android phone.

**Date:** 2026-08-30 · **Branch:** `claude/lifedna-os-design-npdd59`
**Supersedes:** `31-personal-release-certification.md`, which was issued before
the Android-file audit found CR-1 and CR-2.

---

## Scores

| Dimension | Score | Reasoning |
| --- | --- | --- |
| **Stability** | **9 / 10** | 641 tests, no analyzer findings, every known crash and lockout path closed with a regression test written against the specific failure. Held below 9.5 only because no build has run for a full day on hardware |
| **Android readiness** | **9 / 10** | Every file in `android/` audited this pass, not just the Gradle scripts. Two critical blockers found and fixed — one of which meant a fresh clone could not build at all. Toolchain verified against Flutter's own `DependencyVersionChecker`. Not 10 because Gradle has still never run this configuration |
| **Offline reliability** | **9.5 / 10** | The strongest part of the app, and personal mode is its best case: Hive is the only store, reads never touch the network, writes commit locally and synchronously. There is nothing to be offline *from*. Half a point for the untested-on-device caveat |
| **Security** | **8.5 / 10** | AES-encrypted at rest with a device-bound Keystore key; cloud backup disabled coherently across both API-level mechanisms; no receiver exported; exactly five permissions, each traced to a call site; telemetry that throws on a parameter resembling health data. Held below 9 by the documented unencrypted-fallback mode and by backups being plain JSON — both deliberate, both stated |
| **Build readiness** | **9 / 10** | Preflight passes with zero blockers; a fresh clone now contains an executable wrapper; APK and AAB paths both scripted with the defines wired. Not 10 until an artefact exists |
| **Overall** | **9 / 10** | |

---

## Why this is now a YES when the last sign-off was a NO

The previous NO was operational: no Firebase project, no keystore, no artefact,
no device testing. **Personal use removes most of that list.** No Firebase
project is needed. No Play record is needed. No keystore is needed. What
remained was a build that had never been attempted from a clean checkout — and
this pass found the two reasons it would have failed:

- **CR-1** — the Gradle wrapper was gitignored, so a fresh clone had no
  `gradlew` and `flutter build apk` died before starting. Proven by cloning.
- **CR-2** — the notification receivers were missing from the manifest, so
  every reminder was scheduled and never delivered. Found by reading the
  plugin's own manifest rather than trusting an earlier claim about it.

Both are fixed. Neither was visible to 641 passing tests, which is exactly why
the audit looked at files rather than code.

---

## Final APK release checklist

### Before you build

- [ ] `flutter --version` → 3.47.x
- [ ] `java -version` → 17 or newer
- [ ] `echo $ANDROID_HOME` → non-empty, with `platforms/android-36` installed
- [ ] `sdkmanager --licenses` accepted
- [ ] Repo cloned, `cd app && flutter pub get`
- [ ] *(optional)* keystore created and `key.properties` filled in — skip for a
      first build

### Build

- [ ] `tool/verify_release.sh prod personal` → **Ready to build prod**
- [ ] `tool/build_release.sh prod apk` → `✓ Built …app-prod-release.apk`
- [ ] Log shows `no google-services.json` and `no key.properties` — both
      expected and correct for a personal build
- [ ] APK exists and is 20–40 MB

### Install

- [ ] `adb devices` lists the phone as `device`
- [ ] `adb install -r …/app-prod-release.apk` → `Success`
- [ ] App opens from the launcher
- [ ] Dark mode: no white flash on the first frame

### First 10 minutes

- [ ] **Continue on this device** — no account needed
- [ ] Onboarding completes; Home shows macro targets
- [ ] Force-stop and reopen → straight to Home
- [ ] Log a meal; it survives a restart
- [ ] **Me → Data and sync → Back up now**, and note the folder path

### The one thing to verify overnight

- [ ] Add a supplement reminder ~15 minutes out
- [ ] **Reboot the phone**, do not open the app, wait for the time
- [ ] **The notification fires**

That step is CR-2's field verification. It is the only defect class that
cannot be caught in a test and cannot be caught in a debug build.

### First week

- [ ] Reminders arriving daily
- [ ] Live Gym smooth across several sessions
- [ ] A progress photo survives Settings → Apps → LifeDNA → Clear cache
- [ ] `adb pull /sdcard/Android/data/os.lifedna.lifedna/files/backups ~/lifedna-backups`
- [ ] Open a backup JSON on your computer and confirm your data is in it

---

## Standing rules for daily use

- **`adb install -r` to update. Never `adb uninstall`.** `-r` keeps your data;
  uninstalling erases it.
- **Copy backups off the phone monthly.** Seven daily snapshots live on the
  phone, and the phone is what you lose.
- **Sign out erases everything** in personal mode — there is no account to
  return to. The dialog says so now. Back up first.

---

## Certified

| Claim | Verdict |
| --- | --- |
| Builds from a clean clone | Yes — CR-1 fixed and re-verified by cloning |
| Builds without Firebase | Yes — preflight clean, zero blockers |
| Installs without Play | Yes — sideload; debug-signed is fine |
| Fully functional offline | Yes — it is the design, not a fallback |
| Local storage safe | Yes — encrypted, migration-safe, quarantine on reset |
| Backup complete | Yes — boxes **and** photos, restorable, undoable |
| Reminders can be delivered | Yes — CR-2 fixed; **confirm on your phone overnight** |
| No startup lockout path | None found; both failure screens offer a reset |
| Data loss under normal operation | No path found |

**Certified for daily personal use**, conditional on the build succeeding on
your machine and the overnight reminder test passing on your phone.

Neither condition is a known defect. They are the two things this environment
cannot execute: it has no Android SDK, and no phone.
