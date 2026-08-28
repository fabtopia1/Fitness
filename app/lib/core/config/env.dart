/// Build environment.
///
/// Selected at build time with `--dart-define=FLAVOR=...`. There is no runtime
/// switch: a staging build can never accidentally talk to production.
enum Flavor {
  dev('dev', 'LifeDNA Dev'),
  staging('staging', 'LifeDNA Staging'),
  prod('prod', 'LifeDNA OS');

  const Flavor(this.key, this.appName);
  final String key;
  final String appName;

  static Flavor fromKey(String value) =>
      values.firstWhere((f) => f.key == value, orElse: () => Flavor.dev);
}

/// Compile-time configuration.
///
/// Every value here comes from `--dart-define`, so nothing secret is committed
/// and each environment is a separate build artefact.
abstract final class Env {
  static const String _flavorKey = String.fromEnvironment(
    'FLAVOR',
    defaultValue: 'dev',
  );

  static final Flavor flavor = Flavor.fromKey(_flavorKey);

  static bool get isDev => flavor == Flavor.dev;
  static bool get isProd => flavor == Flavor.prod;

  /// Points the app at the local Firebase emulator suite.
  /// `--dart-define=USE_EMULATOR=true`
  static const bool useEmulator = bool.fromEnvironment('USE_EMULATOR');

  static const String emulatorHost = String.fromEnvironment(
    'EMULATOR_HOST',
    defaultValue: '10.0.2.2',
  );

  /// Google OAuth client id used for Calendar scopes on Android.
  /// Empty means the Calendar module stays locked and says so in the UI.
  static const String googleCalendarClientId = String.fromEnvironment(
    'GOOGLE_CALENDAR_CLIENT_ID',
  );

  static bool get calendarConfigured => googleCalendarClientId.isNotEmpty;

  /// Crashlytics is off in dev so local stack traces stay local.
  static bool get crashlyticsEnabled => !isDev;

  /// Analytics collection follows the same rule plus the user's own consent,
  /// which is checked separately at the call site.
  static bool get analyticsEnabled => !isDev;

  static const Duration networkTimeout = Duration(seconds: 20);
  static const Duration syncDebounce = Duration(seconds: 2);
}
