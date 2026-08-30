# LifeDNA OS — Personal Release Certification

**Scope:** one person, one Android phone, local-only. Not a launch.
**Date:** 2026-08-30 · **Branch:** `claude/lifedna-os-design-npdd59`

---

## 1. Final audit

### CRITICAL — none open

| | Was | Now |
| --- | --- | --- |
| C-1 | Hive silently **truncated** any box opened in the wrong mode — 49 bytes to 0, no exception. Not a lockout: total data destruction before any catch could run | `crashRecovery: false` (throws, file byte-identical), migration probe, quarantine on reset, no dead-end screen. 12 on-disk tests |
| C-2 | Google sign-in could never get an ID token | Fixed — and **not applicable** in personal mode: no sign-in at all |
| C-3 | A slow upload deleted the write that superseded it | Outbox identity is durable. **Not applicable** in personal mode: nothing uploads |
| C-4 | No release binary ever produced | Still true here, but now unblocked: `verify_release.sh prod personal` passes with zero blockers and `build_release.sh prod apk` needs no configuration |

### HIGH — none open

| | Item |
| --- | --- |
| H-1 | Gradle daemon memory fits a normal machine |
| H-2 | R8 keeps the Gson attributes, so reminders survive a reboot in a release build |
| H-3 | Photos copied out of the cache at capture; survive a cache clear |
| H-4 | Live Gym no longer rescans the whole workout history every second |
| H-5 | Crash reporting attributable and reaching the zone handler |
| **NEW** | **Sign-out told a local-only user "your data stays on this device and in your account"** — a one-tap path to total loss with reassuring copy. Now says it erases, and names the backup as the way back |
| **NEW** | **No backup existed.** With no cloud, Hive was the only copy. Automatic daily snapshots, manual export, restore with a safety snapshot first |

### MEDIUM

| | Item | Why acceptable for personal use |
| --- | --- | --- |
| M-1 | Release build is debug-signed unless you make a keystore | Installs and runs fine. Two caveats, both documented: the key expires after 365 days, and switching keys later needs an uninstall — so back up first |
| M-2 | Google Calendar stays locked | Needs an OAuth client. It says so rather than failing oddly |
| M-3 | Backups are unencrypted JSON on the phone's own external storage | Deliberate. An encrypted archive you cannot open in three years is not a backup. Another app cannot read the folder; anyone with your unlocked phone can |
| M-4 | No `autoDispose` on any provider | Memory grows slowly with screens visited. Irrelevant at one user's data volume |
| M-5 | A crash-damaged box no longer self-heals by truncation | Deliberate: truncation loses the same data and says nothing. You reach the recovery screen and restore a backup |

### LOW

| | Item |
| --- | --- |
| L-1 | Default launcher icon, no adaptive icon — Android draws it in a system circle |
| L-2 | Hive `Box` keeps all values resident; ~40 MB modelled at five years of heavy logging |
| L-3 | Backups accumulate 7 auto-snapshots plus every manual one; manual ones are never pruned |
| L-4 | Sign-out in personal mode is effectively "erase and start over" — correct, now clearly labelled |

---

## 2. Evidence

```
flutter analyze --fatal-infos            clean
dart format --set-exit-if-changed        149 files, clean
python3 tool/check_sources.py            148 files, all checks passed
flutter test                             624 passed, 0 failed
dart tool/coverage_gate.dart --min 80    81.30 % of 8378 lines — PASS
tool/verify_release.sh prod personal     Ready to build prod (1 warning)
```

The one warning is the missing keystore, which is a warning and not a blocker
precisely because a debug-signed APK sideloads and runs.

---

## 3. Scores

| Dimension | Score | Reasoning |
| --- | --- | --- |
| **Readiness** | **9 / 10** | Everything needed to build is present and preflight passes clean. Not 10 only because the APK has not been produced on a machine with an Android SDK — which is 20 minutes of your time, not more work |
| **Stability** | **8.5 / 10** | 624 tests, no analyzer findings, every known crash and lockout path closed with a regression test. Held below 9.5 because no build has run on real hardware for a full day |
| **Offline reliability** | **9.5 / 10** | The strongest part of the app, and personal mode is its best case: Hive is the only store, reads never touch the network, writes commit locally and synchronously. Nothing to be offline *from*. Half a point for the untested-on-device caveat |
| **Android readiness** | **8.5 / 10** | Toolchain verified against Flutter's own version checker; manifest, permissions, R8 rules, flavours and signing all audited and repaired. Held below 9.5 because Gradle has never actually run this configuration |
| **Data safety** | **9 / 10** | Encrypted at rest, migration cannot destroy data, reset quarantines rather than deletes, both failure screens offer a way out, automatic daily backups, restore takes a safety snapshot first. Not 10: backups only leave the phone when you copy them |
| **Overall** | **9 / 10** | |

---

## 4. Recommendation

**Install it.**

Follow `29-personal-apk-guide.md`. Skip Firebase entirely and skip the keystore
on the first build if you want it working tonight; both are optional for
personal use and the guide says exactly what each costs.

```bash
tool/verify_release.sh prod personal
tool/build_release.sh prod apk
adb install -r app/build/app/outputs/flutter-apk/app-prod-release.apk
```

Then, in order:

1. **Continue on this device** — no account needed.
2. Complete onboarding.
3. **Me → Data and sync → Back up now**, and note the folder path.
4. Run `30-personal-device-checklist.md` over an afternoon. Sections 4 (step 7,
   reminders surviving a reboot) and 10 (backup and restore) matter most —
   everything else you will notice through ordinary use.

### The three things to actually remember

- **Copy your backups off the phone monthly.**
  `adb pull /sdcard/Android/data/os.lifedna.lifedna/files/backups ~/lifedna-backups`
  Seven daily snapshots live on the phone. They do not help if the phone is
  what you lose.
- **Never `adb uninstall`.** Use `adb install -r` to update; it keeps your data.
- **Sign out erases everything** in personal mode. The dialog now says so.
  Back up first if you ever tap it.

### What is not certified

- No Gradle build has run on this configuration, anywhere. The first one is
  yours. If it fails, `29` §8 has the four failures worth knowing.
- Nothing has been exercised on a physical device. That is what §4 of this
  recommendation is for.
- Cloud sync, Google sign-in and Calendar are untested end to end and out of
  scope for personal use.

---

## 5. Certification

| Item | Verdict |
| --- | --- |
| Builds without Firebase | Yes — preflight clean, zero blockers |
| Installs without Play | Yes — sideload, debug-signed is fine |
| Fully functional offline | Yes — it is the design, not a fallback |
| Local storage safe | Yes — encrypted, migration-safe, recoverable |
| Backup exists | Yes — automatic daily, manual, restorable, undoable |
| Reminders reliable | Code and R8 rules correct; **verify on your phone** (checklist §4) |
| Data loss under normal operation | No path found |

**Certified for personal daily use, conditional on the build succeeding on your
machine and the checklist passing on your phone.**
