# 14 — Technical debt log

Everything knowingly left undone. Each entry names what it is, why it was
accepted, what it would cost to close, and what should trigger closing it.

Nothing here is a `TODO` in the code — the lint set makes a `TODO` a build
error, so debt lives in this file where it can be scheduled.

---

## TD-01 · The release binary has not been built or run
**Severity: high · Effort: 1 day · Trigger: before the first upload**

Every check in this repository ran on a host VM. `flutter build apk` was never
executed here because the Android SDK cannot be installed in this environment
— `dl.google.com` is blocked by the network policy.

The consequence: R8 minification and resource shrinking are enabled for
release with keep rules for `flutter_local_notifications`' reflection and for
Crashlytics line numbers, but the shrunk binary has never run. R8 stripping a
reflectively reached class is the classic release-only failure.

**To close:** push to GitHub so the CI build matrix compiles all three
flavours, then install the release APK on a physical device and walk every
flow. Both are blocking items in the launch checklist.

---

## TD-02 · Health Connect native handler
**Severity: medium · Effort: 3–4 days · Trigger: Sprint 6**

The Dart layer is complete: `HealthSyncService`, the `MethodChannel`
contract, the availability state machine, permission handling, sample
decoding, and the summarise rule that sums cumulative metrics and averages
instantaneous ones. Fifteen tests cover it. The screen reports
`notEnabledInBuild` and lists the exact enablement steps.

What is missing is the Kotlin side and the Play declaration. Both were
deliberately deferred: shipping unverifiable native code that cannot be
compiled or run here would be exactly the kind of placeholder this build
avoids, and declaring health permissions an app does not use fails Play's
review.

**To close:** add `androidx.health.connect:connect-client`, implement the
three channel methods, declare the four read permissions and the rationale
activity, complete the Play Health Apps declaration.

---

## TD-03 · The `functions/` codebase is not deployed
**Severity: low · Effort: 0 (by design) · Trigger: a job only a server can do**

`functions/` holds the TypeScript mirror of the engines and is deliberately
absent from `firebase.json`. It exists so the parity fixtures continue to bind
both implementations. The MVP computes everything on the device.

**To close (when warranted):** a cross-user aggregate, a scheduled push, or a
shared food catalogue. Re-add the `functions` entry to `firebase.json` at that
point, not before.

---

## TD-04 · No Hive schema version
**Severity: medium · Effort: 1 day · Trigger: the first breaking field change**

Records are JSON strings, so a renamed field silently reads as its default
rather than failing. Every `fromJson` uses explicit defaults and every entity
has a round-trip test, which contains the damage — but there is no version
number in the box and therefore no migration hook.

**To close:** write a `schemaVersion` into `boxMeta` at startup and add a
migration step that runs before the first read.

---

## TD-05 · `ExerciseBests.repsAtWeight` is keyed by `double`
**Severity: low · Effort: 2 hours · Trigger: a PR is reported as missed**

Floating-point map keys depend on exact bit equality. In practice the keys are
weights the user typed and the app stored, never accumulated arithmetic, so
equality holds. It is still fragile.

**To close:** key by grams as an `int` (`(kg * 1000).round()`).

---

## TD-06 · No data export
**Severity: low · Effort: 2 days · Trigger: the first request, or GDPR scope**

Settings offers "Erase data on this device" but no export. A user who wants to
leave with their history has to ask.

**To close:** a JSON export of every box to a shared file, plus a CSV of
nutrition and workout logs.

---

## TD-07 · No `analytics` collection
**Severity: low · Effort: n/a · Trigger: a cross-user aggregate**

The agreed schema listed one. It is not created, deliberately: Firebase
Analytics already is the analytics store, a Firestore mirror would duplicate
data, and nothing in the MVP reads it. Derived aggregates come from at most a
few thousand local records in single-digit milliseconds.

**To close:** create it when there is a server-side rollup that a device
cannot compute.

---

## TD-08 · The dashboard is the least-covered screen (56 %)
**Severity: low · Effort: 1 day · Trigger: a dashboard regression**

It is composition — every part it renders is covered where it is defined — but
its own branch logic (which cards appear, in which order, for which day) is
thinly tested.

**To close:** widget tests that seed each combination of an empty day, a
partial day, a training day and a rest day.

---

## TD-09 · No deep links
**Severity: low · Effort: 1 day · Trigger: notification-to-screen navigation**

Notifications carry payloads (`supplement:<id>`, `task:<id>`,
`reminder:<id>`), and `NotificationService.initialize` accepts an `onTap`
handler, but nothing wires a tap to a route. Tapping a reminder opens the app
at wherever it was.

**To close:** pass an `onTap` from `main` that pushes the right route, and add
`android:host` intent filters for web links.

---

## TD-10 · The light theme is complete but unexercised
**Severity: low · Effort: 0.5 day · Trigger: a user reports it**

`AppTheme.light()` is complete and one widget test renders the component set
in it, but no screen has been reviewed by eye in light mode. The design is
dark-first and every colour goes through the theme extension, so the risk is
contrast rather than breakage.

**To close:** walk every screen in light mode and check contrast ratios.

---

## TD-11 · No performance budget
**Severity: low · Effort: 2 days · Trigger: a jank report**

No frame-timing test, no startup budget, no memory ceiling. The architecture
makes the common case fast — reads never touch the network — but nothing
enforces it.

**To close:** add a `flutter driver` timeline test on the dashboard and the
live workout screen once there is a device lab.

---

## Debt deliberately NOT taken

| Shortcut refused | Why |
|---|---|
| Storing derived values to speed up the dashboard | a stored derivation can disagree with its source |
| A `TODO` for anything above | a TODO in a shipped file is a promise nobody scheduled |
| A "coming soon" screen for excluded modules | a disabled feature is worse than an absent one |
| Sample health data so the screen looks finished | inventing numbers is the one thing this integration must never do |
| Committing `google-services.json` to simplify the build | a committed credential is a published credential |
| Excluding hard-to-test files from coverage to reach 80 % | a number with a long exclusion list is a decoration |
