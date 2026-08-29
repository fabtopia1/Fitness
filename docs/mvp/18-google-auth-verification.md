# Google Authentication Verification Checklist

**Closes C-2.** Google sign-in returned a null ID token on every Android build,
which surfaced to the user as *"Couldn't sign you in. Please try again."* —
forever, with nothing distinguishing a misconfigured build from a bad network.

This document is the procedure that proves it works, per environment, before
an APK reaches a tester.

---

## 1. Root cause, so the checklist is not cargo cult

`google_sign_in_android` decides whether to request an ID token like this
(`GoogleSignInPlugin.java`, v6.2.1):

```java
String serverClientId = params.getServerClientId();
if (!isNullOrEmpty(params.getClientId()) && isNullOrEmpty(serverClientId)) {
  Log.w("google_sign_in", "clientId is not supported on Android ...");
  serverClientId = params.getClientId();
}
if (isNullOrEmpty(serverClientId)) {
  // Only if google-services.json was parsed by the Gradle plugin.
  int id = res.getIdentifier("default_web_client_id", "string", pkg);
  if (id != 0) serverClientId = context.getString(id);
}
if (!isNullOrEmpty(serverClientId)) {
  optionsBuilder.requestIdToken(serverClientId);      // <-- never reached
}
```

The app had **neither** source:

| Source | Status before the fix |
| --- | --- |
| `serverClientId` argument | Not passed — `GoogleSignIn()` took no arguments |
| `default_web_client_id` resource | Never generated: `com.google.gms.google-services` was declared in `settings.gradle.kts` but **never applied** to the app module |

So `requestIdToken` was never called, `idToken` was null, and
`GoogleAuthProvider.credential(idToken: null, ...)` was handed to Firebase.

### What changed

| File | Change |
| --- | --- |
| `lib/core/config/google_auth_config.dart` | New. Resolves the web client id per flavor from `--dart-define`, falling back to the file-based resource. Rejects obviously-wrong values. |
| `lib/features/auth/data/google_identity.dart` | New seam. `GoogleSignInAccount` has a private constructor, so the null-token case was untestable while the repository talked to the plugin directly. |
| `lib/features/auth/data/auth_repository.dart` | Checks `hasIdToken` **before** building the credential; fails with `google_id_token_missing` and signs the Google session back out. |
| `lib/features/calendar/data/google_calendar_service.dart` | Was passing `clientId`, which Android ignores. Now passes `serverClientId`. |
| `android/app/build.gradle.kts` | Applies the `google-services` and `crashlytics` plugins when credentials are present, and says so in the build log when they are not. |
| `lib/core/error/failure_mapper.dart` | `google_id_token_missing` gets copy that names the cause instead of "try again". |

---

## 2. The three environments are three apps

`build.gradle.kts` gives each flavor its own `applicationId`. Google identifies
an Android app by **package name + signing certificate SHA-1**, so each of
these needs its own OAuth *Android* client — a single one does not cover all
three:

| Flavor | Package name | Firebase app needed |
| --- | --- | --- |
| dev | `os.lifedna.lifedna.dev` | yes |
| staging | `os.lifedna.lifedna.staging` | yes |
| prod | `os.lifedna.lifedna` | yes |

Missing one produces `PlatformException(sign_in_failed, ...ApiException: 10)`
— `DEVELOPER_ERROR` — which says nothing about which of the two halves is
wrong.

### Web vs Android client — the distinction that matters

- The **Android** client (package + SHA-1) is what lets the consent dialog open
  at all. It is never named in Dart code.
- The **Web** client is what `serverClientId` must be set to. Firebase verifies
  the ID token against it. Passing the Android client id here reproduces the
  original symptom with a new cause.

Find the web client at **Firebase console → Authentication → Sign-in method →
Google → Web SDK configuration → Web client ID**.

---

## 3. Per-environment setup

### 3.1 Collect the signing SHA-1 and SHA-256

Every certificate that will ever sign an installable build needs registering.
For a 50-user beta that is **at least two** per flavor: the debug key (local
runs) and the release key (the APK the testers install).

```bash
# Release key — the one testers' APKs are signed with.
keytool -list -v -alias "$KEY_ALIAS" -keystore /path/to/upload-keystore.jks

# Debug key — every developer machine has a different one.
keytool -list -v -alias androiddebugkey \
  -keystore ~/.android/debug.keystore -storepass android -keypass android
```

> If the app is distributed through Play (internal testing track included),
> Play re-signs it. Register the **App signing key certificate** SHA-1 from
> Play Console → Setup → App integrity as well, or sign-in works for the
> sideloaded APK and fails for the same build installed from Play.

- [ ] Release SHA-1 registered — dev
- [ ] Release SHA-1 registered — staging
- [ ] Release SHA-1 registered — prod
- [ ] Debug SHA-1 registered for every developer machine
- [ ] Play app-signing SHA-1 registered (if distributing via Play)

### 3.2 Register the app and download credentials

In the Firebase console, for each flavor: **Project settings → Your apps → Add
app → Android**, using the package name from the table above, then paste the
SHA-1 values.

Place the downloaded file so Gradle picks it up per flavor:

```
android/app/src/dev/google-services.json
android/app/src/staging/google-services.json
android/app/src/prod/google-services.json
```

`build.gradle.kts` applies the Google Services plugin only when at least one of
these exists, and prints a warning naming this document when none do.

- [ ] `google-services.json` present for each flavor being built
- [ ] Build log does **not** contain `building WITHOUT Firebase Gradle plugins`

### 3.3 Enable the provider

- [ ] Firebase console → Authentication → Sign-in method → **Google enabled**
- [ ] A project support email is set (the provider cannot be saved without one)

### 3.4 Pass the client id at build time

```bash
flutter build apk --release --flavor prod \
  --dart-define=FLAVOR=prod \
  --dart-define=FIREBASE_API_KEY=... \
  --dart-define=FIREBASE_APP_ID=... \
  --dart-define=FIREBASE_SENDER_ID=... \
  --dart-define=FIREBASE_PROJECT_ID=... \
  --dart-define=GOOGLE_SERVER_CLIENT_ID_PROD=1234-abc.apps.googleusercontent.com
```

`GOOGLE_SERVER_CLIENT_ID` (no suffix) applies to any flavor that has no
specific value, so one CI secret can cover all three when the project uses a
single Firebase project.

- [ ] The value ends in `.apps.googleusercontent.com`
- [ ] The value is the **Web** client id, not the Android one
- [ ] `--dart-define=FLAVOR=` matches `--flavor`

---

## 4. Verification — run this, do not assume

### 4.1 Automated (CI, every commit)

```bash
cd app && flutter test test/unit/core/config test/unit/features/auth
```

Covers: a build with no client id reports itself unconfigured rather than
passing an empty string; malformed ids are detected; a null or empty ID token
fails with `google_id_token_missing`; the Google session is signed back out so
retries are not silently poisoned; the user-facing copy names the cause; the
complete-identity path still signs in; cancellation is still a cancellation.

- [ ] `flutter test` green

### 4.2 On a real device — the part that cannot be faked

Install the actual flavored release build on a physical Samsung device.
`ApiException: 10` only ever reproduces on a real, signed install.

| # | Step | Pass condition |
| --- | --- | --- |
| 1 | Cold start, tap **Continue with Google** | Account picker opens (if not: Android client / SHA-1 wrong) |
| 2 | Pick an account | Returns to the app signed in, no error toast |
| 3 | Check the session | Home shows the Google display name and avatar |
| 4 | `adb logcat -s google_sign_in` during step 2 | **No** `clientId is not supported on Android` warning |
| 5 | Firebase console → Authentication → Users | The account appears with provider `google.com` |
| 6 | Force-stop, reopen | Still signed in — no picker |
| 7 | Sign out, sign in again | Picker reappears and completes |
| 8 | Airplane mode, tap Google | `You're offline`, not `google_id_token_missing` |
| 9 | Open the picker and press back | `Sign-in cancelled`, app usable |
| 10 | Sign in on a second device with the same account | Same `uid`; logged data appears after sync |

- [ ] Steps 1–10 pass on the **prod** release build
- [ ] Steps 1–3 pass on the **staging** build
- [ ] Steps 1–3 pass on the **dev** build

### 4.3 Calendar authentication

Calendar uses a second consent, for the `calendar.readonly` scope only.

| # | Step | Pass condition |
| --- | --- | --- |
| 1 | Settings → Calendar with no client id configured | Module reads as locked and names the missing define |
| 2 | With a client id, tap **Connect** | Consent screen lists **read-only** calendar access and nothing more |
| 3 | Approve | Connected account email is shown |
| 4 | Return to the calendar view | Real events load |
| 5 | Force-stop and reopen | Events load with **no** second consent prompt (silent sign-in works) |
| 6 | Tap Disconnect | Connection cleared; events gone; no crash |
| 7 | Reconnect | Works without a reinstall |

> Consent-screen scope note: the OAuth consent screen must list
> `.../auth/calendar.readonly`. If it lists `.../auth/calendar` (read/write),
> the wrong scope was configured — the app never writes to a user's calendar
> and must not ask permission to.

- [ ] Steps 1–7 pass, or Calendar is deliberately shipped locked for the beta

---

## 5. Failure lookup

| Symptom | Cause | Fix |
| --- | --- | --- |
| `google_id_token_missing` in-app | No `serverClientId` from any source | §3.4, or add `google-services.json` (§3.2) |
| `ApiException: 10` (`DEVELOPER_ERROR`) | Package name or SHA-1 not registered | §3.1 + §3.2 — check the **flavor's** package name |
| `ApiException: 12500` | Provider not enabled, or no support email | §3.3 |
| `ApiException: 12501` | User cancelled | Not an error |
| Works sideloaded, fails from Play | Play re-signed the app | Register the Play app-signing SHA-1 (§3.1) |
| Works in dev, fails in prod | Per-flavor client id missing | §3.4 — check the `_PROD` suffix |
| Picker opens, then generic failure | Android client id passed as `serverClientId` | §3.2 — use the **Web** client id |
| Calendar consent asks for write access | Wrong scope on the consent screen | §4.3 |

---

## 6. Sign-off

The environment is verified when every box above is ticked **for that
environment**. Ticking prod does not tick staging: they are different apps with
different certificates.

| Environment | Verified by | Date | Build |
| --- | --- | --- | --- |
| dev | | | |
| staging | | | |
| prod | | | |
