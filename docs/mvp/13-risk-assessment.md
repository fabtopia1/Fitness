# 13 — Risk assessment

Scored as **likelihood × impact**. Only risks with a real mitigation or a real
owner are listed; a register of things nobody will act on is noise.

## 1. Critical — must be closed before production

### R-01 · The release binary has never run on a device
**Likelihood: certain that it is untested · Impact: high**

Every test in this repository runs on the host VM. `flutter build apk` has
never been executed here because the Android SDK cannot be installed in this
environment (`dl.google.com` is blocked by the network policy). R8
minification is *configured* and keep rules are written, but a shrunk binary
has not been exercised.

R8 removing a class that `flutter_local_notifications` reaches by reflection
is the classic form of this failure, and it appears only in release builds.

**Mitigation:** the CI build matrix compiles all three flavours on a runner
that does have the SDK, so the first push to GitHub proves the build. A manual
install and full walkthrough is a blocking item in the launch checklist.
**Owner:** release engineer, Sprint 5.

### R-02 · Google Sign-In fails silently without the right SHA fingerprints
**Likelihood: high · Impact: high**

The most common Android launch failure. The debug SHA-1 works locally; the
upload key's SHA-1 and SHA-256 must be registered in the Firebase console or
Google Sign-In returns a null account with no useful error.

**Mitigation:** an explicit blocking item in the launch checklist; verified on
the internal track before any wider rollout. The app degrades honestly —
`sign_in_canceled` is surfaced rather than a spinner that never resolves.

### R-03 · Health Connect declaration rejected by Play
**Likelihood: medium · Impact: high (blocks the release, not the app)**

Google's health-data review is slow and strict, and a rejection can hold a
release for weeks.

**Mitigation:** already mitigated structurally. The MVP declares **no** health
permissions, so the first release is not subject to the review at all. The
integration is architecturally ready and enables behind a manifest change plus
the declaration, on its own schedule.

## 2. High

### R-04 · Firestore rules reject production writes
**Likelihood: was certain, now low · Impact: critical**

The rules written during the design phase required Firestore timestamps while
the client sends ISO-8601 strings. Every write would have been rejected, and
because writes are queued and retried in the background it would have surfaced
as "nothing ever syncs" rather than as an error anyone could act on.

**Mitigation:** fixed, and 39 tests now execute the rules against the real
engine on every push. The class of defect cannot recur silently.

### R-05 · A user loses data on a shared device
**Likelihood: low · Impact: critical**

Sign-out wipes every local box, which is correct for privacy but destructive
if writes are still queued.

**Mitigation:** the sign-out dialog names the number of unsynced changes and
what happens to them. In local mode the erase dialog says the loss is
permanent, in those words.

### R-06 · Outbox entries park and the user does not notice
**Likelihood: medium · Impact: high**

After ten failures an entry stops retrying. If that were silent, a user would
believe their training log was backed up when it was not.

**Mitigation:** parked writes raise a persistent banner with a retry, and
Settings shows the count and offers "Retry failed". The parked state is
covered by tests. **Residual risk:** a user who ignores the banner. Accepted —
the alternative is a modal that blocks the app.

### R-07 · Notification permission refused, so reminders never fire
**Likelihood: high (Android 13+ asks) · Impact: medium**

**Mitigation:** permission is requested at the moment a reminder would first
help, not at launch — roughly doubling grant rates. The Settings card detects
a refusal and offers to ask again. The app never claims a reminder is
scheduled when it is not.

## 3. Medium

### R-08 · Firestore cost overruns at scale
**Likelihood: low · Impact: medium**

Modelled at ~45 writes and ~30 reads per active user per day; at 10 000 users
that is 450 k writes/day. Reads are low because the UI reads Hive.

**Mitigation:** the outbox collapses repeated edits to one document into one
write; 32 field exemptions remove three index writes per document write on the
hottest collections; budget alerts are a launch item. **Trigger to revisit:**
sustained cost above the modelled figure by 2×.

### R-09 · A Hive schema change breaks existing installs
**Likelihood: medium (it will happen) · Impact: high**

Records are stored as JSON strings, so a field rename that is not handled in
`fromJson` silently reads as a default rather than failing loudly.

**Mitigation:** every `fromJson` uses the `Json.*` helpers with explicit
defaults, and every entity has a round-trip test. **Not yet mitigated:** there
is no schema version number in the box. **TD-04.**

### R-10 · The rest timer is killed by aggressive battery management
**Likelihood: medium on Samsung/Xiaomi · Impact: medium**

Vendor battery optimisation kills background timers.

**Mitigation:** the rest alert is a scheduled local notification, not an
in-process timer, so the OS owns it. `inexactAllowWhileIdle` survives Doze.
**Residual risk:** a user who has restricted the app entirely; nothing in the
app can override that, and asking for `SCHEDULE_EXACT_ALARM` would be a
disproportionate permission for a rest timer.

### R-11 · Google Calendar mirror diverges from the real calendar
**Likelihood: medium · Impact: low**

The mirror is a snapshot of −7 to +30 days at the last sync.

**Mitigation:** mirrored events are read-only — editing or deleting one is
refused — so the divergence can only ever be staleness, never a conflicting
edit. Disconnecting removes the mirror entirely.

## 4. Low, but worth naming

### R-12 · `repsAtWeight` is a map keyed by `double`
Floating-point keys are fragile. In practice the keys are weights the user
typed and the app stored, never accumulated arithmetic, so exact equality
holds. **TD-05.**

### R-13 · The user's own data is not exportable
There is no "export my data" button. A user who wants to leave has to ask.
**TD-06.**

### R-14 · One person's judgement of the medical framing
The app clamps deficits, pace and calorie floors, and surfaces every clamp.
The disclaimer is on the welcome screen and in Settings. It has not been
reviewed by anyone qualified. **Mitigation:** a review before public launch is
in the launch checklist.

## 5. Risks that were designed out

| Risk | Why it cannot occur |
|---|---|
| Data loss when offline | Hive is the commit; the network is never in the write path |
| A stale target after a weight change | targets are derived, never stored |
| A personal record that disagrees with the sessions | records are derived, never stored |
| A double dose from a notification plus a tap | the log id is `supplementId_localDate` |
| A key extracted from the APK | there is no AI key, and Firebase config is not a secret |
| A progress photo leaking | photos are never uploaded |
| One user reading another's data | every path is under `users/{uid}`; tested |
| A stacked duplicate reminder | notification ids are derived from record ids |
| A slow pull undoing a recent edit | a strictly newer local record is never overwritten |
