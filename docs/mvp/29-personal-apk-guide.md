# LifeDNA OS — Personal APK Guide

Build it, install it, use it. One person, one phone, no cloud, no Play Store.

**Time: about 40 minutes**, most of it the first Gradle download.

---

## 0. What you are building

| | Personal (this guide) | Cloud |
| --- | --- | --- |
| Firebase | **Not needed** | Project + OAuth clients |
| Sign-in | Tap *Continue on this device* | Email or Google |
| Data | Hive on the phone, AES-encrypted | Hive + Firestore |
| Safety net | **Backup files you copy off by USB** | Cloud resync |
| Setup | 40 min | 40 min + ~3 h of console work |

Personal mode is a first-class configuration, not a degraded one. Every
feature works: nutrition, meals, water, supplements and reminders, workouts,
Live Gym, rest timers, body measurements, the AI Hub. Only sync and sign-in
are absent, and with one phone there is nothing to sync to.

Google Calendar needs an OAuth client, so it stays locked in personal mode and
says so. Everything else is unaffected.

---

## 1. Flutter

```bash
# macOS / Linux
git clone https://github.com/flutter/flutter.git -b stable ~/flutter
export PATH="$HOME/flutter/bin:$PATH"
echo 'export PATH="$HOME/flutter/bin:$PATH"' >> ~/.zshrc   # or ~/.bashrc

flutter --version     # expect 3.47.x
```

Windows: download the stable zip from flutter.dev, unzip to `C:\src\flutter`,
add `C:\src\flutter\bin` to PATH.

## 2. Java 17+

```bash
java -version    # need 17 or newer; 21 is what this project is developed on
```

If missing:

```bash
# macOS
brew install --cask temurin@21
# Ubuntu / Debian
sudo apt install -y openjdk-21-jdk
```

## 3. Android SDK

The lightest path is command-line tools only — no Android Studio.

```bash
mkdir -p ~/android-sdk/cmdline-tools && cd ~/android-sdk/cmdline-tools
# Download "Command line tools only" for your OS from
# https://developer.android.com/studio#command-tools , then:
unzip ~/Downloads/commandlinetools-*.zip
mv cmdline-tools latest

export ANDROID_HOME="$HOME/android-sdk"
export PATH="$ANDROID_HOME/cmdline-tools/latest/bin:$ANDROID_HOME/platform-tools:$PATH"
# Persist both lines in ~/.zshrc or ~/.bashrc.

sdkmanager --install "platform-tools" "platforms;android-36" "build-tools;36.0.0"
sdkmanager --licenses     # accept all
```

Prefer Android Studio? Install it, open **SDK Manager**, tick *Android SDK
Platform 36*, *SDK Build-Tools*, *SDK Command-line Tools*, *Android SDK
Platform-Tools*, then `flutter doctor --android-licenses`.

Verify:

```bash
flutter doctor
```

Green ticks for *Flutter* and *Android toolchain* are all you need. Chrome and
Android Studio warnings do not matter.

## 4. The project

```bash
git clone https://github.com/fabtopia1/Fitness.git
cd Fitness
git checkout claude/lifedna-os-design-npdd59
cd app && flutter pub get && cd ..
```

## 5. Firebase — skip it

Nothing to do. No `google-services.json`, no `--dart-define`. The build detects
the absence and produces a local-only app; the Gradle log says so:

```
LifeDNA: no google-services.json found — building WITHOUT Firebase Gradle plugins.
```

That line is expected and correct here.

## 6. Signing — optional

**Skip this and the APK still installs and runs.** Without a keystore the
release build is signed with Android's debug key, which is fine for
sideloading onto your own phone.

Two things to know if you skip it:

- The debug key expires after 365 days.
- If you later build with a *different* key, Android refuses to install over
  the old app. You must uninstall first, **which erases local data** — so take
  a backup (§10) before ever switching keys.

To use your own key instead — worth 5 minutes, it removes both caveats:

```bash
keytool -genkey -v \
  -keystore ~/lifedna-upload-keystore.jks \
  -storetype JKS -keyalg RSA -keysize 2048 -validity 10000 \
  -alias lifedna

cp ~/lifedna-upload-keystore.jks app/android/app/upload-keystore.jks
cp app/android/key.properties.example app/android/key.properties
$EDITOR app/android/key.properties     # fill in the two passwords
```

Back up that `.jks` file. Losing it means your next build cannot install over
this one without an uninstall.

## 7. Preflight

```bash
tool/verify_release.sh prod personal
```

Expect **Ready to build prod**. It checks the toolchain, signing, and runs the
analyzer, formatter, layer rules and the 623-test suite. Two minutes here beats
a failed twenty-minute build.

## 8. Build

```bash
tool/build_release.sh prod apk
```

or the raw command it runs:

```bash
cd app
flutter build apk --release --flavor prod --dart-define=FLAVOR=prod
```

First build: 10–20 minutes while Gradle downloads. Later builds: 1–3 minutes.

**Output:** `app/build/app/outputs/flutter-apk/app-prod-release.apk` (~25–40 MB)

### App bundle (only if you ever publish)

```bash
tool/build_release.sh prod aab
# or: flutter build appbundle --release --flavor prod --dart-define=FLAVOR=prod
```

**Output:** `app/build/app/outputs/bundle/prodRelease/app-prod-release.aab`

An AAB cannot be installed on a phone — it is a Play upload format only. For
personal use you want the APK.

### If the build fails

| Message | Fix |
| --- | --- |
| `Android SDK could not be found` | `export ANDROID_HOME=$HOME/android-sdk` (§3) |
| `Failed to install the following Android SDK packages` | `sdkmanager --licenses` |
| `daemon disappeared unexpectedly` | Out of RAM. `gradle.properties` is already set to 4 GB; close other apps |
| `Could not resolve com.android.tools.build:gradle` | No network, or a proxy blocking `dl.google.com` |
| `key.properties is missing: …` | Complete the file, or delete it to use the debug key (§6) |

## 9. Install

```bash
# USB debugging: Settings → About phone → tap Build number 7×,
# then Settings → Developer options → USB debugging.
adb devices          # your phone should be listed as "device"
adb install -r app/build/app/outputs/flutter-apk/app-prod-release.apk
```

`-r` reinstalls **over** the existing app and keeps your data. Use it for every
update. Never `adb uninstall` unless you have a backup.

No cable? Copy the APK to the phone (Drive, email, USB storage), open it with
Files, allow *Install unknown apps* for that app when prompted.

Samsung may show *"Blocked by Play Protect"* — tap **More details → Install
anyway**. That is Play Protect not recognising a self-signed app, not a problem
with the build.

## 10. First run

1. Open LifeDNA. The welcome screen says this build has no Firebase.
2. Tap **Continue on this device**.
3. Complete onboarding: date of birth, sex, height, weight, goal.
4. Go to **Me → Reminders** and allow notifications when asked.
5. Go to **Me → Data and sync** and tap **Back up now**. Note the folder path.

### Getting backups off the phone

A snapshot is taken automatically each day and seven are kept, but they live on
the phone — which is exactly what you lose if the phone is lost.

```bash
adb pull /sdcard/Android/data/os.lifedna.lifedna/files/backups ~/lifedna-backups
```

Or plug in by USB and copy `Android/data/os.lifedna.lifedna/files/backups` with
your file manager. Do this monthly. It is the only thing standing between you
and total loss.

To restore: put the `.json` file back in that folder, then
**Me → Data and sync → Restore from a backup**. The current data is snapshotted
first, so a wrong choice is undoable.

## 11. Updating later

```bash
cd Fitness && git pull
cd app && flutter pub get && cd ..
tool/build_release.sh prod apk
adb install -r app/build/app/outputs/flutter-apk/app-prod-release.apk
```

Your data survives, because `-r` reinstalls in place. Take a backup first
anyway — it costs one tap.
