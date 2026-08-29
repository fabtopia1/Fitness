import 'package:lifedna/core/config/env.dart';

/// The one place that decides which Google OAuth client this build talks to.
///
/// ## Why this exists
///
/// On Android, `GoogleSignIn(clientId: ...)` is **ignored** — the plugin logs a
/// warning and the app is identified by its package name plus the SHA-1 of its
/// signing key instead. The parameter that matters is `serverClientId`, and it
/// is the only thing that makes the plugin call `requestIdToken`. With no
/// server client id from any source the plugin never requests an id token,
/// `GoogleSignInAuthentication.idToken` comes back null, and
/// `signInWithCredential` fails with an error that names nothing.
///
/// The plugin's own fallback is a `default_web_client_id` string resource,
/// which only exists if `google-services.json` was present AND the
/// `com.google.gms.google-services` Gradle plugin parsed it. Relying on that
/// alone made Google sign-in fail silently on every build produced without
/// those credentials — the C-2 blocker.
///
/// So: pass it explicitly, per flavor, and let the file-based resource be a
/// fallback rather than the only path.
///
/// ## What to supply
///
/// The **web** OAuth client id from the Firebase console
/// (`Authentication → Sign-in method → Google → Web SDK configuration`), NOT
/// the Android client id. Firebase verifies the id token against the web
/// client, so an Android client id produces the same null-token symptom with a
/// different cause.
///
/// ```
/// --dart-define=GOOGLE_SERVER_CLIENT_ID_PROD=1234-abc.apps.googleusercontent.com
/// ```
///
/// See `docs/mvp/18-google-auth-verification.md`.
abstract final class GoogleAuthConfig {
  static const String _dev = String.fromEnvironment(
    'GOOGLE_SERVER_CLIENT_ID_DEV',
  );
  static const String _staging = String.fromEnvironment(
    'GOOGLE_SERVER_CLIENT_ID_STAGING',
  );
  static const String _prod = String.fromEnvironment(
    'GOOGLE_SERVER_CLIENT_ID_PROD',
  );

  /// Applies to every flavor that has no specific id. One CI secret can
  /// configure all three, and a single-environment build needs only this.
  static const String _shared = String.fromEnvironment(
    'GOOGLE_SERVER_CLIENT_ID',
  );

  /// The web OAuth client id for this build, or null to fall back to the
  /// `default_web_client_id` resource generated from `google-services.json`.
  ///
  /// Never returns an empty string: the plugin treats empty and absent
  /// differently in one direction and identically in the other, and null is
  /// the value that reads correctly at both call sites.
  static String? get serverClientId =>
      _pick(switch (Env.flavor) {
        Flavor.dev => _dev,
        Flavor.staging => _staging,
        Flavor.prod => _prod,
      }) ??
      _pick(_shared);

  /// Calendar uses the same web client unless a build overrides it, because in
  /// practice they are the same OAuth client and requiring a second define is
  /// how the Calendar module ends up locked for no reason.
  static String? get calendarServerClientId =>
      _pick(Env.googleCalendarClientId) ?? serverClientId;

  /// True when this build names its client id rather than depending on the
  /// Gradle plugin having produced the resource. Surfaced in the verification
  /// checklist and in Settings diagnostics.
  static bool get isExplicit => serverClientId != null;

  /// A client id that is present but obviously not an OAuth client id — a
  /// project id, a sender id, a truncated paste. Worth catching at startup
  /// because the runtime symptom is a null token with no clue attached.
  static bool get isMalformed {
    final id = serverClientId;
    return id != null && !looksLikeClientId(id);
  }

  /// Whether [value] has the shape of an OAuth client id. Public so the rule
  /// can be tested against real and mistaken values, which is the only way to
  /// exercise it — a build under test supplies no defines.
  static bool looksLikeClientId(String value) =>
      value.endsWith('.apps.googleusercontent.com') &&
      value.indexOf('-') > 0 &&
      value.length > '.apps.googleusercontent.com'.length + 4;

  static String? _pick(String value) {
    final trimmed = value.trim();
    return trimmed.isEmpty ? null : trimmed;
  }
}
