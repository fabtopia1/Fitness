# Build Validation Report

**Phase 1 of the closed-beta remediation.** What was verified, how, what was
fixed, and — stated plainly up front — what this environment cannot prove.

---

## 0. Environment limitation, declared first

**No Android build of any kind can be executed in this container.** Three
independent blocks, each verified rather than assumed:

| Requirement | State | Evidence |
| --- | --- | --- |
| Android SDK platform | Absent | `/opt/android-sdk/cmdline-tools/` is an empty directory; no `platforms/`, `build-tools/`, or `ndk/` |
| Ability to install one | Blocked | `sdkmanager` is not present, and its download host `dl.google.com` is denied by the network policy |
| Android Gradle Plugin | Unreachable | `https://maven.google.com/com/android/tools/build/gradle/9.1.0/gradle-9.1.0.pom` → `301` → `https://dl.google.com/dl/android/maven2/...` → connection refused by policy |

Proxy status confirms it: `{"kind":"connect_rejected","detail":"gateway
answered 403 to CONNECT (policy denial…)","host":"dl.google.com:443"}`.

`repo.maven.apache.org`, `plugins.gradle.org` and `services.gradle.org` are all
reachable — the block is specific to Google's Maven mirror, which is where AGP,
the Google Services plugin, Crashlytics, Firebase and Play Services all live.

**Consequence.** Everything in §1–§5 is verified statically or against the
toolchain's own source. The claims that require executing R8, the manifest
merger and the packaging step — *"a release APK builds"*, *"a release AAB
builds"* — can only be settled by the CI job in §6. This report does not claim
them. See §7.

---

## 1. Toolchain compatibility

Checked against Flutter's own gate, `flutter_tools/gradle/src/main/kotlin/
DependencyVersionChecker.kt`, at the SDK actually installed — not from memory,
and not from documentation that may describe a different release.

| Component | Configured | Hard floor (build fails) | Warn floor | Verdict |
| --- | --- | --- | --- | --- |
| Gradle | 9.3.1 | 8.14.0 | 9.1.0 | Above both |
| AGP | 9.1.0 | 8.11.1 | 9.0.1 | Above both |
| Kotlin (KGP) | 2.4.0 | 2.2.20 | 2.3.20 | Above both |
| Java | 21.0.10 | 17 | 17 | Above both |
| Flutter | 3.47.2 stable | — | — | Matches the pin in CI |
| Dart | 3.13.2 | — | — | — |

Sources: `android/gradle/wrapper/gradle-wrapper.properties` (Gradle),
`android/settings.gradle.kts` (AGP, KGP), `java -version`.

**No component sits in a warn band.** The combination is internally consistent:
`compileOptions` and `kotlin.compilerOptions.jvmTarget` both pin emitted
bytecode to 17, so the JDK running Gradle can be 17 or 21 without changing the
output.

### Fixed here

CI ran Gradle on **JDK 17** while the project is developed on **21**. Both are
supported, but a build that only ever runs on the version nobody develops
against is a variable nobody is watching. CI now uses 21, matching the
development toolchain; the bytecode target is unchanged because it is pinned
explicitly.

---

## 2. Gradle configuration

### 2.1 Daemon memory — fixed (H-1)

`org.gradle.jvmargs` was the template's `-Xmx8G`. A standard GitHub-hosted
runner has 7 GB **in total**, so the daemon either fails to start or is taken
by the OOM killer mid-build. Gradle reports that as *"the Gradle build daemon
disappeared unexpectedly"*, which reads as a Gradle bug rather than a memory
limit.

```properties
org.gradle.jvmargs=-Xmx4G -XX:MaxMetaspaceSize=1G -XX:+HeapDumpOnOutOfMemoryError
org.gradle.parallel=true
org.gradle.caching=true
```

`MaxMetaspaceSize` is set because Kotlin script compilation is metaspace-hungry
and an unbounded metaspace is the second-most-common cause of the same symptom.
`HeapDumpOnOutOfMemoryError` means a repeat is diagnosable rather than a rerun.

Parallel and cached execution are safe here: one application module, no custom
tasks with undeclared inputs.

### 2.2 Firebase Gradle plugins — fixed (C-2 prerequisite)

`com.google.gms.google-services` and `com.google.firebase.crashlytics` were
declared in `settings.gradle.kts` and **never applied** to the app module.
Consequences, both silent:

- `default_web_client_id` was never generated, so `google_sign_in` never
  requested an ID token → C-2.
- No R8 mapping file was uploaded, so every release crash report would arrive
  obfuscated.

They are now applied conditionally, because a clone without credentials must
still build — local mode is a supported configuration, not a stub:

```kotlin
val hasFirebaseCredentials =
    listOf("google-services.json", "src/dev", "src/staging", "src/prod")
        .map { if (it.endsWith(".json")) file(it) else file("$it/google-services.json") }
        .any { it.exists() }

if (hasFirebaseCredentials) {
    apply(plugin = "com.google.gms.google-services")
    apply(plugin = "com.google.firebase.crashlytics")
} else {
    logger.lifecycle("LifeDNA: no google-services.json found — building WITHOUT …")
}
```

The `else` branch matters as much as the `if`: the previous behaviour and the
new unconfigured behaviour are identical, so without the log line there is
nothing to distinguish "no credentials" from "credentials ignored".

### 2.3 Release signing — fixed

Previously, a missing or malformed `key.properties` fell through to the debug
signing config with no message. A debug-signed artefact that was asked for as a
release build fails in two places that both point away from the cause: Play
rejects the upload, and Google Sign-In returns `ApiException: 10` because the
debug certificate's SHA-1 was never registered.

Now:

- `key.properties` **present but incomplete** → the build fails, naming the
  missing keys.
- `storeFile` pointing at a file that does not exist → the build fails, naming
  the absolute path it tried.
- `key.properties` **absent** → still falls back to the debug key, because a
  fresh clone must produce an installable artefact — but logs what that costs.

Also fixed: `storeFile` was `getProperty("storeFile")?.let { file(it) }`, so a
missing property produced a null `storeFile` and an AGP failure much later with
no reference to `key.properties`.

### 2.4 Multidex — removed

`multiDexEnabled` and the support-library dependency were both present.
Native multidex has existed since API 21 and `minSdk` here is 24, so both were
no-ops that implied a constraint the project does not have.

### 2.5 Flavors

Three flavors on one dimension, each a separately installable artefact:

| Flavor | applicationId | Label | Default build type in CI |
| --- | --- | --- | --- |
| dev | `os.lifedna.lifedna.dev` | LifeDNA Dev | debug |
| staging | `os.lifedna.lifedna.staging` | LifeDNA Staging | release |
| prod | `os.lifedna.lifedna` | LifeDNA OS | release |

Verified: `src/dev/res/values/strings.xml` and `src/staging/...` override
`app_name`, so a tester with two flavors installed can tell them apart on the
home screen. There is no runtime switch between environments — a staging build
cannot reach production data because it is a different binary.

**Carries a requirement into Phase 3:** three applicationIds means three OAuth
Android clients. See `18-google-auth-verification.md` §2.

---

## 3. R8 / ProGuard

`isMinifyEnabled = true` and `isShrinkResources = true` on release. Every rule
in `proguard-rules.pro` exists because its absence produces a failure that
appears **only** in a shrunk release build — which is to say, only after the
beta APK is in a tester's hands.

| Rule | Failure it prevents |
| --- | --- |
| `-keepattributes Signature` | `flutter_local_notifications` persists scheduled notifications as Gson JSON. Gson resolves generics via `TypeToken`; without the generic signature `TypeToken<HashMap<String,Object>>` erases to a raw type and the boot receiver throws. **Symptom: every reminder silently disappears after a reboot, release builds only.** |
| `-keepattributes *Annotation*`, `InnerClasses`, `EnclosingMethod` | The rest of what Gson's reflection needs to reconstruct those types |
| `-keepclassmembers class com.dexterous.flutterlocalnotifications.models.** { <fields>; }` | Field-name serialisation of the plugin's own models |
| `-keepattributes SourceFile,LineNumberTable` + `-renamesourcefileattribute SourceFile` | Symbolicated Crashlytics traces without shipping original file names |
| `-keepclassmembers class com.google.firebase.** { *; }` | Firestore's reflective model serialisation |
| `-dontwarn com.google.firebase.**`, `com.google.android.gms.**` | Optional-dependency warnings failing the build |
| `-keep class io.flutter.embedding.**`, `io.flutter.plugin.**` | Plugin registrant resolution by name |

Dependency-by-dependency review found no further gaps: `hive`, `googleapis` and
`fl_chart` are pure Dart; `connectivity_plus`, `package_info_plus`,
`url_launcher`, `image_picker` and `flutter_secure_storage` ship consumer rules
and use no reflection of ours.

**Not proven here.** These rules are reviewed, not executed — R8 has not run.
The CI job in §6 is what tests them, and §7.2 is the device test that catches
the one failure R8 rules cannot be reasoned about: the reboot case.

---

## 4. Manifest and resources

| Check | Result |
| --- | --- |
| Permissions match code | `INTERNET`, `ACCESS_NETWORK_STATE`, `POST_NOTIFICATIONS`, `RECEIVE_BOOT_COMPLETED`, `CAMERA` — each traced to a call site |
| No `SCHEDULE_EXACT_ALARM` | Correct: reminders use `inexactAllowWhileIdle`, which survives Doze without the restricted Android 14+ permission |
| No Health Connect permissions | Correct: the native reader is not in this build, and declaring health permissions unused fails Play's health data declaration |
| `android:exported` on the launcher activity | Present — required since API 31 |
| `enableOnBackInvokedCallback` | Present — predictive back on Android 13+ |
| Camera feature `required="false"` | Present — does not exclude tablets from Play |
| Referenced resources exist | `@string/app_name`, `@mipmap/ic_launcher`, `@drawable/ic_notification`, `@color/notification_accent`, `@style/LaunchTheme`, `@style/NormalTheme`, `@xml/backup_rules`, `@xml/data_extraction_rules` — all present |
| Notification icon is monochrome | Yes — a coloured small icon renders as a white blob |
| Duplicate plugin receivers | **Fixed.** `com.dexterous.*` receivers were re-declared here and are already in the plugin's merged manifest; the duplicates would fail the merger the moment the plugin changed an attribute |
| `allowBackup` | **Fixed to `false`**, with `backup_rules.xml` and `data_extraction_rules.xml` excluding everything for the API levels that read those instead |

`allowBackup=false` is not conservatism. Hive boxes are AES-encrypted with a
Keystore key; Keystore keys are device-bound and non-exportable, so a box
restored onto a new device arrives without the key that opens it. Backing them
up manufactures exactly the unrecoverable state C-1 exists to handle.

### Open, low severity

No `mipmap-anydpi-v26` adaptive icon. On Android 8+ the legacy icon is shrunk
into a system-drawn circle. It works and it is dated. Fixing it needs
foreground artwork with the correct safe-zone padding, not a config change —
so it is listed, not bodged.

---

## 5. Dart-side release validation

`flutter analyze` — clean, `--fatal-infos`, across `lib/`, `test/` and
`integration_test/`.
`tool/check_sources.py` — 141 files, domain-purity and colour-discipline rules
pass.
`flutter test` — **562 passing**, including the C-1, C-2 and C-3 regression
suites added in this remediation.

`flutter build bundle --release` was attempted to validate the AOT path
independently of Gradle. It fails at `Target build_hooks failed: Error: Android
SDK could not be found` — the §0 limitation, not a code defect.

---

## 6. What CI now does about it

The `build` job is the only environment with an Android SDK, so it is the only
place the artefact claims can be settled. Changes made in this phase:

| Gap | Now |
| --- | --- |
| **No AAB was ever built.** The AAB is a different packaging path — different manifest merge, per-ABI splitting that happens nowhere else. "The APK built" was never evidence Play's upload artefact does. | `flutter build appbundle` for staging and prod, uploaded as an artifact, `if-no-files-found: error` |
| No `google-services.json` in CI → every artifact was built without the Firebase Gradle plugins, i.e. with C-2 present | Materialised per flavor from `GOOGLE_SERVICES_JSON_BASE64`; a missing secret is a loud `::warning::`, not silence |
| No release keystore → release artifacts were debug-signed | Materialised from `ANDROID_KEYSTORE_BASE64` + alias/password secrets; absence warns explicitly that the artefact is not distributable |
| `GOOGLE_SERVER_CLIENT_ID` not passed | Passed to both the APK and AAB builds |
| R8 mapping file discarded | Uploaded, 90-day retention, `if-no-files-found: error`. The mapping is regenerated on every build, so an artefact kept without it can never be symbolicated again |
| Credentials left on the runner | `if: always()` cleanup step |
| CI on JDK 17, development on 21 | Both on 21 |

Also fixed: `.gitignore` covered `app/android/app/google-services.json` but not
the per-flavor `src/{dev,staging,prod}/google-services.json` paths — which is
where a three-environment project actually puts them, and what
`18-google-auth-verification.md` §3.2 instructs. Now `**/google-services.json`.

### Required secrets

| Secret | Needed for |
| --- | --- |
| `FIREBASE_API_KEY`, `FIREBASE_APP_ID`, `FIREBASE_SENDER_ID`, `FIREBASE_PROJECT_ID`, `FIREBASE_STORAGE_BUCKET` | Cloud mode at all |
| `GOOGLE_SERVICES_JSON_BASE64` | Google Sign-In ID token; Crashlytics mapping upload |
| `GOOGLE_SERVER_CLIENT_ID` | Google Sign-In (explicit, not dependent on the generated resource) |
| `ANDROID_KEYSTORE_BASE64`, `ANDROID_KEY_ALIAS`, `ANDROID_KEY_PASSWORD`, `ANDROID_STORE_PASSWORD` | A distributable release artefact |
| `GOOGLE_CALENDAR_CLIENT_ID` | Optional — Calendar falls back to the sign-in client |

---

## 7. Verification status

### 7.1 Settled here

- [x] Gradle / AGP / Kotlin / Java mutually compatible, none in a warn band
- [x] Daemon memory fits a standard runner
- [x] Firebase Gradle plugins applied when credentials exist, and the absence is announced
- [x] Release signing fails loudly on partial configuration
- [x] Flavors distinct in id, label and artefact
- [x] R8 keep rules reviewed against every dependency
- [x] Manifest permissions, exported flags and resource references correct
- [x] Backup disabled coherently across all API levels
- [x] Analyzer, layer rules and 562 tests green

### 7.2 Settled only by CI (§6)

- [ ] `flutter build apk --release --flavor prod` produces an APK
- [ ] `flutter build appbundle --release --flavor prod` produces an AAB
- [ ] R8 completes without a missing-class error
- [ ] The mapping file is produced and uploaded
- [ ] The manifest merger completes with the plugins' manifests

### 7.3 Settled only on a physical device (Phase 6)

- [ ] The APK installs on a Samsung device
- [ ] **Reminders survive a reboot in a release build** — the Gson/R8 case in §3
- [ ] Google Sign-In returns an ID token against the registered SHA-1
- [ ] The launch theme does not flash white on a dark-mode device

---

## 8. Verdict

**Every build-configuration defect found is fixed.** The Android build
configuration is, as far as static analysis and toolchain-source verification
can establish, correct and internally consistent.

That is a different statement from *"the release APK builds"*, which this
environment cannot make. §6 is what makes it, and it must be green before
Phase 6 begins — an artefact is the input to device testing, not an output of
it.
