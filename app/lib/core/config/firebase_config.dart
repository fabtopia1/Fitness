import 'package:firebase_core/firebase_core.dart';

/// Firebase options supplied at BUILD TIME via `--dart-define`.
///
/// Deliberately not a committed `firebase_options.dart`. Two reasons:
///
///  1. Nothing project-specific is committed, so the repository is safe to
///     open-source and a fork does not inherit our project.
///  2. Each environment is a different build command rather than a different
///     checked-in file, which is what makes dev/staging/prod separation real
///     rather than a convention someone forgets.
///
/// When the required values are absent, [currentPlatform] returns null and the
/// app runs in local mode — see `FirebaseService`.
///
/// Android additionally needs `android/app/google-services.json` for Cloud
/// Messaging. That file is gitignored; see `docs/mvp/BUILD_CHECKLIST.md`.
abstract final class FirebaseConfig {
  static const String apiKey = String.fromEnvironment('FIREBASE_API_KEY');
  static const String appId = String.fromEnvironment('FIREBASE_APP_ID');
  static const String messagingSenderId =
      String.fromEnvironment('FIREBASE_SENDER_ID');
  static const String projectId = String.fromEnvironment('FIREBASE_PROJECT_ID');
  static const String storageBucket =
      String.fromEnvironment('FIREBASE_STORAGE_BUCKET');

  static bool get isConfigured =>
      apiKey.isNotEmpty && appId.isNotEmpty && projectId.isNotEmpty;

  /// Null when this build carries no Firebase configuration.
  static FirebaseOptions? get currentPlatform {
    if (!isConfigured) return null;
    return FirebaseOptions(
      apiKey: apiKey,
      appId: appId,
      messagingSenderId: messagingSenderId,
      projectId: projectId,
      storageBucket:
          storageBucket.isEmpty ? '$projectId.appspot.com' : storageBucket,
    );
  }

  /// The exact command that enables cloud sync, shown in Settings so a blocked
  /// state is actionable.
  static const String setupHint =
      'flutter build apk --dart-define=FIREBASE_API_KEY=... '
      '--dart-define=FIREBASE_APP_ID=... '
      '--dart-define=FIREBASE_SENDER_ID=... '
      '--dart-define=FIREBASE_PROJECT_ID=...';
}
