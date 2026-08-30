# Final Release Audit

**Date:** 2026-08-30 · **Branch:** `claude/lifedna-os-design-npdd59`
**Scope:** ship a release APK, installable and stable for daily personal use.

This pass audited the Android **files**, not the Dart code. That is where the
two remaining blockers were, and neither was visible to a single one of the 641
tests.

---

## CRITICAL — 2 found, 2 fixed, 0 open

### CR-1 · A fresh clone could not build at all — **FIXED**

`app/android/.gitignore` is the Flutter template's, which ignores `gradlew`,
`gradlew.bat` and `gradle-wrapper.jar`. That is harmless when every checkout
runs `flutter create .` first, and fatal otherwise: `flutter build apk` invokes
`android/gradlew` directly, so the build dies before it starts.

Verified rather than reasoned about:

```
$ git clone --depth 1 --branch claude/… file:///home/user/Fitness /tmp/clonetest
$ ls /tmp/clonetest/app/android/
app  build.gradle.kts  gradle  gradle.properties  settings.gradle.kts
$ test -f /tmp/clonetest/app/android/gradlew && echo YES || echo NO
NO — build would fail
```

```diff
--- a/app/android/.gitignore
+++ b/app/android/.gitignore
-gradle-wrapper.jar
+# The Gradle wrapper IS tracked, unlike the Flutter template default.
+# … a fresh clone has no wrapper, and `flutter build apk` invokes
+# android/gradlew directly, so the build dies before it starts.
 /.gradle
 /captures/
-/gradlew
-/gradlew.bat
 /local.properties
```

`gradlew` is tracked as mode **100755**, so the executable bit survives the
clone. Re-verified: a fresh clone now contains `-rwxr-xr-x … gradlew` and a
valid 53 KB wrapper jar.

### CR-2 · Scheduled notifications could never be delivered — **FIXED**

A regression introduced by an earlier commit in this same effort, which removed
the three `com.dexterous` receivers on the stated grounds that "the plugin
declares them and merges them in".

It does not. `flutter_local_notifications` 18.0.1's own manifest:

```xml
<manifest package="com.dexterous.flutterlocalnotifications">
    <uses-permission android:name="android.permission.VIBRATE" />
    <uses-permission android:name="android.permission.POST_NOTIFICATIONS"/>
</manifest>
```

Permissions only. Its README requires the app to declare the receivers. Without
them every reminder was stored, its alarm fired, and no component existed to
receive it — total, silent, and invisible to every test.

```diff
+        <receiver
+            android:name="com.dexterous.flutterlocalnotifications.ScheduledNotificationReceiver"
+            android:exported="false" />
+        <receiver
+            android:name="com.dexterous.flutterlocalnotifications.ScheduledNotificationBootReceiver"
+            android:exported="false">
+            <intent-filter>
+                <action android:name="android.intent.action.BOOT_COMPLETED" />
+                <action android:name="android.intent.action.MY_PACKAGE_REPLACED" />
+                <action android:name="android.intent.action.QUICKBOOT_POWERON" />
+                <action android:name="com.htc.intent.action.QUICKBOOT_POWERON" />
+            </intent-filter>
+        </receiver>
```

`MY_PACKAGE_REPLACED` matters as much as `BOOT_COMPLETED` here: it re-arms
reminders after an APK is sideloaded over the top, which is the normal way this
app is installed.

`ActionBroadcastReceiver` is deliberately **not** declared — nothing in `lib/`
creates a notification with actions, and a dead declaration is a lie about what
the app does.

**Guarded by** `test/unit/android/manifest_test.dart`, 11 tests that assert the
manifest from Dart: receivers present, all four boot actions, boot permission
granted, nothing exported, backup disabled with rules for both API levels, no
exact-alarm permission, exactly the five permissions the code uses, no storage
permission, and R8 keeping both the plugin classes and the Gson signatures.

---

## HIGH — 1 found, 1 fixed, 0 open

### H-7 · Backups did not include progress photos — **FIXED**

Photos are files, not Hive records. Exporting the boxes alone returned
measurements whose `photoPath` named a file that no longer existed — broken
thumbnails, and the one thing in a backup nobody can re-enter by hand.

Photos now travel with the boxes through a shared pool beside the JSON: one
copy across all seven snapshots, because photos are written once and never
edited. A legacy absolute path is skipped (it points outside the store and may
already be gone), and a photo file that has vanished does not fail the whole
backup. Six new tests.

---

## MEDIUM — 3 open, all accepted

| | Item | Why acceptable for daily personal use |
| --- | --- | --- |
| **M-1** | Release build is debug-signed unless you create a keystore | Installs and runs. Two documented caveats: the debug key expires after 365 days, and switching keys later needs an uninstall — so back up first |
| **M-2** | Google Calendar stays locked without an OAuth client | It says so rather than failing oddly. Every other module is unaffected |
| **M-3** | Backups are unencrypted JSON on the phone's own external storage | Deliberate. An encrypted archive you cannot open in three years is not a backup. No other app can read the folder; anyone with your unlocked phone can |

---

## LOW — 5 open

| | Item |
| --- | --- |
| **L-1** | Default launcher icon, no `mipmap-anydpi-v26` adaptive icon — Android draws it inside a system circle. Needs artwork, not config |
| **L-2** | The launch background follows the **system** light/dark setting, not the in-app theme override. Inherent to Android launch themes; a one-frame mismatch if you force a theme against the system |
| **L-3** | The backup photo pool is never pruned. A year of weekly photos is roughly 10 MB |
| **L-4** | Hive `Box` keeps all values resident — ~40 MB modelled at five years of heavy logging |
| **L-5** | No `autoDispose` on any provider; memory grows slowly with screens visited. Irrelevant at one person's data volume |

---

## Phase results

| Phase | Result |
| --- | --- |
| **1 · Android configuration** | Every file in `android/` audited. CR-1 and CR-2 found and fixed. Root and app Gradle scripts, both variant manifests, all resource files, `MainActivity.kt`, wrapper properties and jar (validated as a real archive containing `GradleWrapperMain`), styles for day and night, and the notification icon all verified correct |
| **2 · Encryption and local storage** | `crashRecovery: false` (a mismatch throws instead of truncating), migration probe, quarantine on reset, no dead-end failure screen, backup now including photos. 12 on-disk storage tests + 28 backup tests |
| **3 · Notifications** | CR-2 fixed and guarded. Channels created, `inexactAllowWhileIdle` so no restricted permission is needed, R8 keeps the Gson attributes. **Reboot behaviour is device-only — Phase 7 §7 is what settles it** |
| **4 · Firebase** | Not used in a personal build, and that is the recommended configuration. The cloud path remains implemented and tested; verifying it end to end needs a project and registered SHA-1/SHA-256, per `27-firebase-production-deployment.md` |
| **5 · Signing** | Partial `key.properties` fails the build rather than silently falling back to the debug key. Preflight prints SHA-1, SHA-256 and the certificate expiry. Play App Signing readiness documented in `25` |
| **6 · Build commands** | `32-build-commands.md`, with expected output and a failure table per command |
| **7 · Device checklist** | `30-personal-device-checklist.md` |
| **8 · This audit** | — |

---

## Evidence

```
flutter analyze --fatal-infos            clean
dart format --set-exit-if-changed        150 files, clean
python3 tool/check_sources.py            149 files, all checks passed
flutter test                             641 passed, 0 failed
dart tool/coverage_gate.dart --min 80    81.33 % of 8414 lines — PASS
tool/verify_release.sh prod personal     Ready to build prod (1 warning)
fresh clone → gradlew present            -rwxr-xr-x, wrapper jar valid
```

The single warning is the absent keystore, which is a warning rather than a
blocker precisely because a debug-signed APK sideloads and runs.

---

## What is still not proven

Two things, both unchanged and both stated plainly:

1. **No Gradle build has ever run on this configuration.** This container has
   no Android SDK (`/opt/android-sdk/cmdline-tools/` is empty) and Google's
   Maven mirror is denied by network policy — every artifact 301s to
   `dl.google.com`, which is refused. The first build is yours.
2. **Nothing has been exercised on a physical device.** Every claim about
   reminders surviving a reboot, Live Gym smoothness over a full session, and
   photos surviving a cache clear is structural.

CR-2 is the reason to take the second point seriously: it was a defect that
641 passing tests could not see, and only a phone would have shown.
