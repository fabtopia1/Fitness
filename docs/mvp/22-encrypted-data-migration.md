# Migration Strategy — Existing Encrypted Data

**Owner:** Release Manager · **Status:** implemented, 12 tests
**Closes:** the live half of C-1

---

## 1. The situation

Every install created before the encryption marker existed has boxes on disk
and **no record of how they were written**. There are two populations, and
until the fix landed the app could not tell them apart:

| Population | Boxes on disk | Keystore | How it happened |
| --- | --- | --- | --- |
| **A — encrypted** | AES | key present | The normal path |
| **B — plaintext** | plain | **key present** | The old code caught a keystore failure at first run, continued with no cipher, and a later launch created a key anyway |
| **C — plaintext** | plain | key absent | Keystore never worked on that device |

Population **B** is the dangerous one, and it is not hypothetical: it is
exactly what the pre-C-1 silent fallback produced.

## 2. What used to happen to population B

On first launch of the new build:

1. Marker absent → resolver treats it as a first run.
2. Keystore has a key → resolver picks **encrypted**.
3. `Hive.openBox(..., encryptionCipher: cipher)` on **plaintext** files.

The design assumed step 3 throws and the recovery screen catches it. It does
not. Measured on a real box:

```
written, length=1
file size before: 49
OPEN SUCCEEDED. length=0 value=null      <-- no exception
file size after: 0                       <-- truncated
REOPENED PLAINTEXT: length=0 value=null  <-- gone
```

Hive's default `crashRecovery: true` cannot parse the frames, concludes the
file is damaged, **truncates it to zero**, and returns an empty box reporting
success. Total, silent data loss at open time, before any `catch` runs. The
user opens the app and their entire history is simply absent — no error, no
recovery screen, nothing to report.

## 3. The migration

Three changes, in order of importance.

### 3.1 `crashRecovery: false` on every box open

The single most important line. With it, the same mismatch throws
`HiveError: Wrong checksum` and **the file is left byte-for-byte intact** —
verified in both directions (plaintext-with-cipher, encrypted-without). Only
then is a mismatch a recoverable error rather than a destructive one.

Cost, stated plainly: a box genuinely damaged by a crash no longer self-heals
by truncation; the user reaches the recovery screen instead. Truncation loses
the same data and says nothing, so this is the better failure.

### 3.2 A one-shot mode probe

```
resolve intended mode
  └─ open all boxes (crashRecovery: false)
        ├─ success ────────────────► record mode, done
        └─ throw
              ├─ close whatever opened   (Hive caches by name and ignores the
              │                           cipher for an already-open box)
              ├─ marker recorded? ──yes──► StorageUnavailable(encryptionMismatch)
              └─ no ──► open all boxes UNENCRYPTED (crashRecovery: false)
                          ├─ success ──► adopt plaintext, record it   ← population B
                          └─ throw ────► StorageUnavailable(corrupt)
```

Only the encrypted→plaintext direction is probed. The reverse needs a key, and
if one were available the resolver would already have chosen it.

**The probe is restricted to `recorded == null`.** Once a mode is recorded,
probing the other one is precisely the silent mode switch C-1 forbids: a
recorded mode that will not open is a missing key or real damage, and guessing
cannot help.

### 3.3 The marker is written after the fact

`state.put(encrypted, effectivelyEncrypted)` runs only after every box opened
cleanly, using the mode that **actually worked** — so a migrated population-B
install records `false` and never probes again.

## 4. Migration outcomes

| Population | First launch on the new build | Data |
| --- | --- | --- |
| A — encrypted, key present | Opens encrypted, records `true` | Intact |
| B — plaintext, key present | Encrypted attempt throws, probe opens plaintext, records `false` | **Intact** (was: destroyed) |
| C — plaintext, no key | Resolver picks unencrypted directly, records `false` | Intact |
| Encrypted, key lost (device transfer) | `StorageUnavailable(keyUnavailable)` → recovery screen | Unreadable by anything; resync from account |
| Encrypted, wrong key | Probe skipped (marker recorded) → `encryptionMismatch` | Quarantined, not deleted |
| Genuinely corrupt, no marker | Both attempts throw → `corrupt` | Quarantined |
| Fresh install | First run, key created, records `true` | — |

## 5. Reset is now quarantine, not deletion

`resetLocalData` moves `*.hive` aside into `<hive-home>/quarantine/` instead of
deleting, keeps one generation so it cannot grow, and **keeps the Keystore
key** — quarantined encrypted boxes are worthless without it, and the next
launch adopts an existing key anyway.

Nothing in the app reads the quarantine, so the recovery screen's copy stays
honest: the data is gone from LifeDNA. What changes is that a beta tester who
taps reset is now a recoverable support case rather than a destroyed one.

`resetLocalData(quarantine: false)` deletes outright and clears the key, for a
genuine privacy wipe.

## 6. Verification

`app/test/unit/core/storage/hive_store_open_test.dart` — 12 tests on the real
filesystem, covering: first run creates and records; a keystore that cannot be
read still starts; **plaintext boxes are adopted, not declared corrupt**; the
adopted mode is recorded so the probe runs once; encrypted legacy boxes keep
working; a missing key throws rather than probing; a recorded mode is never
second-guessed; a failed open leaves no box behind; quarantine round-trips.

Two facts these tests pin that are easy to get wrong:

- An **empty** box carries no checksum to disagree with, so it opens under any
  key. A mismatch is only detectable once a frame exists — which is also the
  only point at which it matters.
- Hive's box registry is **global and keyed by name**, not by directory. A box
  left open by one test is handed to the next one, and the assertion passes for
  the wrong reason.

## 7. Field verification

Device Script 11 (`20-device-validation-scripts.md`) covers the lockout path.
For migration specifically, before the beta opens:

1. Install the **last pre-remediation build**, sign in, log a meal, a workout
   and a measurement, force-stop.
2. Install the release build **over the top** (`adb install -r`, no uninstall).
3. Open it. **Every entry must still be there.**
4. Force-stop and reopen — still there, and `logcat` shows no probe message the
   second time.

Step 2 is the whole test. An uninstall-then-install proves nothing: it deletes
the boxes, which is the one case that was never at risk.

## 8. Rollback

If migration misbehaves in the field, the artefact is the unit of rollback —
there is no server-side switch. Halt the Play rollout, and tell affected
testers to install the previous APK; because reset now quarantines rather than
deletes, their box files are still on the device and recoverable by support.
