# Personal Device Checklist

One person, one phone, one afternoon. Run this once after installing the APK.
Everything here uses only local mode — no Firebase, no sign-in, no second
device.

Tick as you go. Anything that fails, note what you did and what happened.

---

## 1. Install (5 min)

| # | Do | Expect |
| --- | --- | --- |
| 1 | `adb install -r app-prod-release.apk` | `Success` |
| 2 | Tap the icon on the home screen | Opens within ~3 s |
| 3 | Watch the very first frame in **dark mode** | Background matches the theme — no white flash |
| 4 | Welcome screen | Says this build has no Firebase configuration |

- [ ] Installs and opens

## 2. Login — local mode (5 min)

| # | Do | Expect |
| --- | --- | --- |
| 1 | Tap **Continue on this device** | Goes to onboarding |
| 2 | Enter date of birth, sex, height, weight, goal | Each step advances; Back keeps what you typed |
| 3 | Finish | Home screen, with macro targets derived from your weight |
| 4 | Force-stop the app, reopen | Straight to Home — no onboarding, no welcome screen |

- [ ] Session persists across a restart

> There is no email or password in personal mode. The session is a local
> record, so nothing can lock you out of it.

## 3. Meals (10 min)

| # | Do | Expect |
| --- | --- | --- |
| 1 | Nutrition → **Add food**, search, pick, set a portion, save | Appears in today's log; macro rings move |
| 2 | Add three more in different meal slots | Each lands in the slot you chose |
| 3 | Add a water entry | Water ring updates |
| 4 | Delete one food | Removed; rings recalculate immediately |
| 5 | Force-stop, reopen, Nutrition | Everything still there, same values |
| 6 | Tomorrow: open the app | Today's log empty; yesterday intact in history |

- [ ] Meals and water persist

## 4. Supplements and reminders (20 min, mostly waiting)

| # | Do | Expect |
| --- | --- | --- |
| 1 | Me → Supplements → add one, dose time **4 minutes from now** | Saved and listed |
| 2 | Allow notifications when prompted | The Android 13+ dialog appears here, not at first launch |
| 3 | Lock the phone and wait | Notification fires within a couple of minutes of the time |
| 4 | Tap it | Opens on Supplements |
| 5 | Mark the dose taken | Marked; streak increments |
| 6 | Add another ~15 min out, then **reboot the phone** | — |
| 7 | Do not open the app. Wait for the time | **It still fires** |

Step 7 is the one that only works in a release build. If it fails, notifications
will not survive a reboot — report it.

- [ ] A reminder fires
- [ ] **A reminder survives a reboot**

## 5. Workouts and Live Gym (15 min)

| # | Do | Expect |
| --- | --- | --- |
| 1 | Train → create a workout with 3 exercises | Saved |
| 2 | Start it | Live Workout opens, clock from 00:00 |
| 3 | Tap **COMPLETE SET** | Haptic; count increments; rest overlay counts down |
| 4 | Watch the clock for 60 s, untouched | Counts smoothly — no stutter |
| 5 | Log ~20 sets across the three exercises | One tap each; "Last time" updates |
| 6 | Adjust rest with ±, then skip | Responds immediately |
| 7 | Let a rest timer run to zero with the app in the background | Buzzes and notifies |
| 8 | Finish the workout | Summary shows sets, volume, any PRs |
| 9 | Reopen Train | The session is in history |

- [ ] Live Gym stays smooth for a whole session
- [ ] Rest timer fires from the background

## 6. Body and photos (5 min)

| # | Do | Expect |
| --- | --- | --- |
| 1 | Body → add a measurement with a weight | Saved; chart updates |
| 2 | Add one with a **photo** | Thumbnail in the strip |
| 3 | Settings → Apps → LifeDNA → Storage → **Clear cache** | — |
| 4 | Reopen LifeDNA → Body | **Photo still there** |

Step 4 is the H-3 fix. A broken-image placeholder means photos went back to
living in the cache.

- [ ] Photo survives a cache clear

## 7. Calendar (2 min)

| # | Do | Expect |
| --- | --- | --- |
| 1 | Me → Plan | Tasks and events work locally |
| 2 | Look at the Google Calendar section | Reads as locked, and names what is missing |

Expected in personal mode: Google Calendar needs an OAuth client. Locked and
honest is the correct result, not a failure.

- [ ] Local tasks and events work; Calendar states why it is unavailable

## 8. Airplane mode (5 min)

| # | Do | Expect |
| --- | --- | --- |
| 1 | Airplane mode **on** | — |
| 2 | Log a meal, a supplement dose, a set, a measurement | All save, no error, no spinner |
| 3 | Move through every tab | Everything reads normally |
| 4 | Force-stop, reopen, still offline | All four present |
| 5 | Airplane mode off | Nothing changes — there is nothing to sync |

In personal mode the app never touches the network for your data, so this
should be completely uneventful. Anything that hangs or errors is a bug.

- [ ] Fully usable offline

## 9. Restart and reopen (5 min)

| # | Do | Expect |
| --- | --- | --- |
| 1 | Reboot the phone | — |
| 2 | Open LifeDNA | Opens to Home, signed in, all data present |
| 3 | Force-stop and reopen 5× | Clean every time |
| 4 | Start a workout, background the app 2 min, return | Workout still running, clock correct |

- [ ] Survives reboots and backgrounding

## 10. Backup and restore (10 min) — the important one

| # | Do | Expect |
| --- | --- | --- |
| 1 | Me → Data and sync | Backup card shows a folder path and a recent automatic backup |
| 2 | Tap **Back up now** | "Saved lifedna-…json" |
| 3 | `adb pull /sdcard/Android/data/os.lifedna.lifedna/files/backups ~/lifedna-backups` | Files land on your computer |
| 4 | Open one in a text editor | Readable JSON with your meals and workouts in it |
| 5 | In the app, log a throwaway meal called "DELETE ME" | Appears |
| 6 | Tap **Restore from a backup**, pick the one from step 2, confirm | "Restored N records" |
| 7 | Check Nutrition | "DELETE ME" is **gone** — the backup replaced it |
| 8 | Tap **Restore from a backup** again | A `before-restore-…` file is in the list |

Step 8 proves the undo path: the state you replaced was snapshotted first.

- [ ] A backup file exists and is readable on a computer
- [ ] Restore works
- [ ] Restoring is undoable

## 11. Sign out and back in (5 min)

| # | Do | Expect |
| --- | --- | --- |
| 1 | **Back up first** — sign-out wipes local data by design | File saved |
| 2 | Me → Sign out, confirm | Returns to Welcome |
| 3 | Tap **Continue on this device** | Onboarding again — the wipe was real |
| 4 | Complete onboarding, Me → Data and sync → **Restore** | Your data comes back |

In personal mode sign-out is effectively "erase and start over", because there
is no account to sign back into. **Do not tap it casually.** Step 4 is the only
way back, and it needs step 1.

- [ ] Sign-out wipes; restore brings it back

## 12. A real day (ongoing)

Use it normally for a week. Watch for:

- [ ] Anything you logged that is not there the next day
- [ ] A reminder that did not fire
- [ ] The app opening to anything other than Home
- [ ] Live Gym stuttering after several sessions
- [ ] Storage growth beyond ~100 MB in Settings → Apps → LifeDNA

---

## If something goes wrong

| Symptom | Do this |
| --- | --- |
| "Your data can't be unlocked" | Tap **Try again** once. If it persists, **Reset this phone's data** — then restore your latest backup. The old files are quarantined, not deleted |
| "LifeDNA could not start" | Tap **Try again**. If it persists, the same reset is on that screen |
| Reminders stopped | Settings → Apps → LifeDNA → Battery → **Unrestricted**, and remove it from *Sleeping apps* under Battery → Background usage limits |
| Data looks wrong | Do **not** log more. Back up first, then restore an older snapshot |
| App will not install over the old one | You built with a different signing key. Back up, uninstall, reinstall, restore |

## Sign-off

| Section | Pass | Notes |
| --- | --- | --- |
| 1 Install | | |
| 2 Login | | |
| 3 Meals | | |
| 4 Supplements and reminders | | |
| 5 Workouts and Live Gym | | |
| 6 Body and photos | | |
| 7 Calendar | | |
| 8 Airplane mode | | |
| 9 Restart | | |
| 10 Backup and restore | | |
| 11 Sign out and in | | |

Sections **4 (step 7)** and **10** matter most. The first is the only defect
that hides in a release build; the second is your entire safety net.
