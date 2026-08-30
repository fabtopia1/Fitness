# Samsung Device Testing Checklist

Samsung is the target hardware for this beta, and One UI diverges from stock
Android in ways that reliably break exactly the features LifeDNA depends on:
scheduled notifications, background sync, and cold-start appearance. Everything
here is Samsung-specific — a Pixel passes all of it without exercising
anything.

Run after `20-device-validation-scripts.md`, on devices A and B from
`23-android-test-protocol.md` §2.

---

## 1. Device sleeping — the top cause of "my reminders stopped"

One UI puts unused apps to sleep aggressively, and it is on by default.

| # | Step | Expected |
| --- | --- | --- |
| 1 | Settings → Battery → **Background usage limits** | Note whether "Put unused apps to sleep" is on (it usually is) |
| 2 | Confirm LifeDNA is **not** in *Sleeping apps* or *Deep sleeping apps* | If it is, remove it and note that a tester will hit this |
| 3 | Schedule a supplement reminder ~10 min out; lock the phone; do not touch it | Notification fires |
| 4 | Add LifeDNA to **Deep sleeping apps**, schedule another, wait | Likely does **not** fire. **The app must not crash, and the schedule must survive** |
| 5 | Remove it from deep sleep, open the app | Pending reminders still listed, nothing lost |

Step 4 failing to fire is expected One UI behaviour, not a bug. What is a bug
is a crash, a lost schedule, or a reminder that never fires again afterwards.

- [ ] Reminder fires under normal battery settings
- [ ] Deep sleep does not corrupt or lose the schedule
- [ ] Tester onboarding note mentions excluding LifeDNA from sleeping apps

## 2. Battery optimisation

| # | Step | Expected |
| --- | --- | --- |
| 1 | Settings → Apps → LifeDNA → Battery → **Unrestricted** | Reminders fire on time |
| 2 | Set to **Optimised** (the default), schedule, wait | Fires, possibly late — the app uses `inexactAllowWhileIdle` deliberately |
| 3 | Set to **Restricted**, schedule, wait | May not fire; must not crash |
| 4 | Back to Optimised, open the app | State intact |

- [ ] No crash in any of the three modes
- [ ] Late delivery under Optimised is tolerated by the UI (no "missed" spam)

## 3. Smart Switch — the C-1 trigger

The single most valuable Samsung test, because Smart Switch is exactly how a
Keystore-encrypted database arrives on hardware whose Keystore cannot open it.

| # | Step | Expected |
| --- | --- | --- |
| 1 | Install LifeDNA on device A, sign in, log several entries | — |
| 2 | Run Smart Switch A → B | **LifeDNA app data is not offered for transfer** |
| 3 | Install the APK on B and sign in | Data downloads from the account |
| 4 | Confirm on B | Entries present; **no recovery screen** |

Step 2 is the assertion: `allowBackup="false"` plus the backup and
data-extraction rules exclude everything. If Smart Switch *does* carry the
data, the manifest is wrong and step 4 will show the recovery screen — the C-1
scenario, live.

- [ ] Smart Switch does not carry LifeDNA data
- [ ] Data restores from the account instead
- [ ] No recovery screen on the receiving device

## 4. One UI appearance

| # | Step | Expected |
| --- | --- | --- |
| 1 | Dark mode on, cold start from the launcher | **No white flash** (H-6) |
| 2 | Light mode, cold start | No dark flash |
| 3 | Settings → Display → Screen zoom at maximum | No clipped text or overlapping controls |
| 4 | Font size at maximum | Live Gym buttons still tappable and labelled |
| 5 | Navigation set to **gestures**, then to **buttons** | Bottom bar not obscured either way |
| 6 | Edge panels enabled | No conflict with the Live Gym swipe areas |
| 7 | Rotate to landscape | No crash (portrait-locked is acceptable) |

- [ ] Steps 1–7 pass on device A

## 5. Multi-window and pop-up view

One UI offers these on every app; Flutter apps often mis-lay-out in them.

| # | Step | Expected |
| --- | --- | --- |
| 1 | Open LifeDNA in split screen (top half) | Renders, no overflow errors |
| 2 | Drag the divider to make it very short | Content scrolls rather than overflowing |
| 3 | Open in pop-up view | Usable or gracefully minimal |
| 4 | Return to full screen | State preserved — no lost workout |

Step 4 matters most: a resize is a configuration change, and a lost in-progress
workout there is a real data-loss report.

- [ ] No lost state on resize

## 6. Samsung keyboard

| # | Step | Expected |
| --- | --- | --- |
| 1 | Log a food with the Samsung keyboard | Text lands correctly |
| 2 | Use the number row in Live Gym weight entry | Decimals accepted |
| 3 | Enable swipe typing in a notes field | No duplicated or dropped characters |
| 4 | Switch keyboard languages mid-entry | No crash |

- [ ] Steps 1–4 pass

## 7. Secure Folder (optional but revealing)

| # | Step | Expected |
| --- | --- | --- |
| 1 | Install LifeDNA inside Secure Folder | Installs |
| 2 | Open, sign in, log an entry | Works — it is a separate Android user |
| 3 | Confirm the outside instance is unaffected | Two independent datasets |

Secure Folder is a separate Android user with a separate Keystore. If anything
here shows the recovery screen, storage is keyed on something it should not be.

- [ ] Independent, no recovery screen

## 8. Sign-off

| Area | Device A | Device B | Notes |
| --- | --- | --- | --- |
| 1 Device sleeping | | | |
| 2 Battery optimisation | | | |
| 3 Smart Switch (C-1) | | | |
| 4 Appearance | | | |
| 5 Multi-window | | | |
| 6 Keyboard | | | |
| 7 Secure Folder | | | optional |

Section 3 is a **blocker**. A Smart Switch that carries LifeDNA data puts every
transferring tester into the C-1 recovery path, and Samsung users transfer
phones constantly — it is the flow Smart Switch exists for.
