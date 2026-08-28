import 'package:lifedna/core/data/synced_entity.dart';

/// How the app decides which theme to paint.
///
/// Dark is the default rather than "system": this app is used in gyms and
/// kitchens at both ends of the day, and the design system was built dark-first.
enum ThemePreference {
  dark('dark', 'Dark'),
  light('light', 'Light'),
  system('system', 'Match system');

  const ThemePreference(this.wire, this.label);
  final String wire;
  final String label;

  static ThemePreference fromWire(String value) => values.firstWhere(
    (t) => t.wire == value,
    orElse: () => ThemePreference.dark,
  );
}

/// User preferences. Firestore: `users/{uid}/settings/preferences`.
///
/// Deliberately small. Every field here is read by something that changes
/// behaviour — a setting that does not is a lie told in a switch.
class AppSettings implements SyncedEntity {
  const AppSettings({
    required this.updatedAt,
    this.theme = ThemePreference.dark,
    this.remindersEnabled = true,
    this.analyticsConsent = false,
    this.crashReportsConsent = true,
    this.deletedAt,
  });

  /// There is exactly one settings document per user.
  static const String docId = 'preferences';

  @override
  String get id => docId;

  final ThemePreference theme;

  /// Master switch for every scheduled local notification. Turning it off
  /// cancels what is already scheduled rather than only suppressing new ones.
  final bool remindersEnabled;

  /// Opt-IN. Defaults to false so a user who never opens this screen is not
  /// measured.
  final bool analyticsConsent;

  /// Opt-OUT. Crash reports carry no health data and are what makes a beta
  /// build fixable, so the default is on and the switch is honest about it.
  final bool crashReportsConsent;

  @override
  final DateTime updatedAt;
  @override
  final DateTime? deletedAt;

  AppSettings copyWith({
    ThemePreference? theme,
    bool? remindersEnabled,
    bool? analyticsConsent,
    bool? crashReportsConsent,
    DateTime? updatedAt,
  }) => AppSettings(
    theme: theme ?? this.theme,
    remindersEnabled: remindersEnabled ?? this.remindersEnabled,
    analyticsConsent: analyticsConsent ?? this.analyticsConsent,
    crashReportsConsent: crashReportsConsent ?? this.crashReportsConsent,
    updatedAt: updatedAt ?? DateTime.now().toUtc(),
    deletedAt: deletedAt,
  );

  @override
  Map<String, dynamic> toJson() => {
    'id': id,
    'theme': theme.wire,
    'remindersEnabled': remindersEnabled,
    'analyticsConsent': analyticsConsent,
    'crashReportsConsent': crashReportsConsent,
    'updatedAt': updatedAt.toIso8601String(),
    'deletedAt': deletedAt?.toIso8601String(),
  };

  factory AppSettings.fromJson(Map<String, dynamic> json) => AppSettings(
    theme: ThemePreference.fromWire(Json.string(json['theme'], 'dark')),
    remindersEnabled: Json.boolean(json['remindersEnabled'], true),
    analyticsConsent: Json.boolean(json['analyticsConsent']),
    crashReportsConsent: Json.boolean(json['crashReportsConsent'], true),
    updatedAt: Json.date(json['updatedAt'], fallback: DateTime.now()),
    deletedAt: Json.dateOrNull(json['deletedAt']),
  );

  factory AppSettings.defaults({DateTime? now}) =>
      AppSettings(updatedAt: (now ?? DateTime.now()).toUtc());
}
