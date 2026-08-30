# Build Commands — What Each Does and What Success Looks Like

Run from the repository root unless stated. Every expected output below is what
a *correct* run prints; anything else is covered in the failure table under it.

---

## 1. `flutter pub get`

```bash
cd app && flutter pub get
```

Resolves Dart dependencies against `pubspec.lock`. Needs network the first
time; afterwards it reads the pub cache.

**Expected**

```
Resolving dependencies...
Got dependencies!
```

Or, more usually after a checkout, a list of packages with newer versions
available followed by `Got dependencies!`. That list is informational — the
lockfile pins what actually builds, and upgrading is not part of shipping.

| Failure | Meaning |
| --- | --- |
| `Because lifedna depends on … version solving failed` | `pubspec.yaml` was edited without regenerating the lock |
| `Got socket error` | No network or a proxy blocking `pub.dev` |

---

## 2. `flutter analyze`

```bash
cd app && flutter analyze --fatal-infos
```

Static analysis under `analysis_options.yaml`, which sets `todo: error` and the
layering lints. `--fatal-infos` is deliberate: a warning allowed to accumulate
is a rule nobody follows.

**Expected**

```
Analyzing app...
No issues found! (ran in 1.8s)
```

Anything else is a build failure in waiting. Fix it before continuing.

### The two rules the analyzer cannot express

```bash
cd app && python3 tool/check_sources.py
```

**Expected**

```
checked 149 files
all checks passed
```

Checks the pure-Dart domain boundary and that no colour literal appears outside
`core/theme`.

---

## 3. `flutter test`

```bash
cd app && flutter test
```

**Expected**

```
00:33 +641: All tests passed!
```

641 tests, roughly 35 seconds. `+N` is passes; any `-N` is a failure and the
run exits non-zero.

With the coverage gate:

```bash
cd app && flutter test --coverage && dart ../tool/coverage_gate.dart --min 80
```

**Expected**

```
TOTAL 81.33 % of 8414 measured lines (threshold 80 %)
PASS
```

The gate excludes six device- or backend-bound files and names them, so the
number is not inflated by pretending untestable code is covered.

---

## 4. `flutter build apk --release`

```bash
cd app
flutter build apk --release --flavor prod --dart-define=FLAVOR=prod
```

or the wrapper, which also validates the configuration first:

```bash
tool/build_release.sh prod apk
```

Compiles Dart to ARM machine code, runs R8 to shrink and obfuscate, and
packages a signed APK.

**Expected**

```
Running Gradle task 'assembleProdRelease'...                    128.4s
✓ Built build/app/outputs/flutter-apk/app-prod-release.apk (28.4MB)
```

First run: 10–20 minutes while Gradle downloads AGP and the dependencies.
Later runs: 1–3 minutes.

Two log lines are expected and correct in a personal build:

```
LifeDNA: no google-services.json found — building WITHOUT Firebase Gradle plugins.
LifeDNA: no android/key.properties — release builds will be signed with the DEBUG key.
```

Both are the app telling you what it did, not warnings to fix.

| Failure | Fix |
| --- | --- |
| `Android SDK could not be found` | `export ANDROID_HOME=$HOME/android-sdk` |
| `Failed to install the following SDK packages` | `sdkmanager --licenses` |
| `Could not resolve com.android.tools.build:gradle` | No network, or a proxy blocking `dl.google.com` |
| `daemon disappeared unexpectedly` | Out of RAM. `gradle.properties` already caps the daemon at 4 GB |
| `key.properties is missing: …` | Complete the file, or delete it to use the debug key |
| `Permission denied: ./gradlew` | `chmod +x app/android/gradlew` — the repo tracks it as 100755, so this only happens after a copy that dropped the bit |

---

## 5. `flutter build appbundle --release`

```bash
cd app
flutter build appbundle --release --flavor prod --dart-define=FLAVOR=prod
```

**Expected**

```
Running Gradle task 'bundleProdRelease'...                       94.2s
✓ Built build/app/outputs/bundle/prodRelease/app-prod-release.aab (24.1MB)
```

**An AAB cannot be installed on a phone.** It is a Play upload format; Play
generates per-device APKs from it. For personal use you want the APK from §4.
Build this only if you intend to publish.

The AAB is a different packaging path — different manifest merge, per-ABI
splitting that happens nowhere else — so a green APK build is not evidence that
the bundle works.

---

## 6. Install

```bash
adb devices                                   # phone listed as "device"
adb install -r app/build/app/outputs/flutter-apk/app-prod-release.apk
```

**Expected**

```
Performing Streamed Install
Success
```

`-r` reinstalls over the existing app and **keeps your data**. Use it for every
update; never `adb uninstall` unless you have a backup.

| Failure | Meaning |
| --- | --- |
| `INSTALL_FAILED_UPDATE_INCOMPATIBLE` | Built with a different signing key. Back up, uninstall, reinstall, restore |
| `INSTALL_FAILED_VERSION_DOWNGRADE` | The APK's version code is lower than what is installed |
| `no devices/emulators found` | USB debugging off, or the cable is charge-only |
| `device unauthorized` | Accept the RSA prompt on the phone |

---

## 7. The whole sequence

```bash
git clone https://github.com/fabtopia1/Fitness.git && cd Fitness
git checkout claude/lifedna-os-design-npdd59
cd app && flutter pub get && cd ..

tool/verify_release.sh prod personal      # → Ready to build prod
tool/build_release.sh prod apk            # → ✓ Built …app-prod-release.apk
adb install -r app/build/app/outputs/flutter-apk/app-prod-release.apk
```

`verify_release.sh` runs analyze, format, the layer rules and all 641 tests
before touching Gradle. Two minutes there beats a twenty-minute build that
fails at the end.
