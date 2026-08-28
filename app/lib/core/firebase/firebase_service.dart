import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:flutter/foundation.dart';
import 'package:lifedna/core/config/env.dart';

/// Owns Firebase initialisation and reports, honestly, whether it worked.
///
/// A build without `firebase_options.dart` (no `flutterfire configure` run yet)
/// must still launch. It runs in LOCAL MODE: Hive remains the source of truth,
/// every feature works, and nothing replicates. This is a real, supported
/// degraded mode — not a stub — and the UI states it plainly rather than
/// pretending to sync.
///
/// The alternative, crashing on launch when a config file is absent, makes the
/// app impossible to test or demo and teaches nobody anything.
class FirebaseService {
  FirebaseService._(this.status, this._app);

  final FirebaseStatus status;
  final FirebaseApp? _app;

  bool get isAvailable => status == FirebaseStatus.ready;

  static Future<FirebaseService> initialize({
    FirebaseOptions? options,
  }) async {
    if (options == null) {
      debugPrint(
        'FirebaseService: no FirebaseOptions supplied — starting in local '
        'mode. Run `flutterfire configure` to enable cloud sync.',
      );
      return FirebaseService._(FirebaseStatus.notConfigured, null);
    }

    try {
      final app = await Firebase.initializeApp(options: options);

      if (Env.useEmulator) {
        FirebaseFirestore.instance.useFirestoreEmulator(
          Env.emulatorHost,
          8080,
        );
        await FirebaseAuth.instance.useAuthEmulator(Env.emulatorHost, 9099);
      }

      // Offline persistence is what lets Firestore reads serve from cache
      // while the device is offline. Unlimited cache: this is a personal
      // dataset measured in megabytes, and eviction mid-workout would be
      // exactly the wrong trade.
      FirebaseFirestore.instance.settings = const Settings(
        persistenceEnabled: true,
        cacheSizeBytes: Settings.CACHE_SIZE_UNLIMITED,
      );

      return FirebaseService._(FirebaseStatus.ready, app);
    } on Object catch (error, stackTrace) {
      debugPrint('FirebaseService: initialisation failed — $error');
      debugPrintStack(stackTrace: stackTrace);
      return FirebaseService._(FirebaseStatus.failed, null);
    }
  }

  /// Test seam: lets a fake Firestore/Auth pair stand in for the real ones.
  @visibleForTesting
  factory FirebaseService.forTesting({
    FirebaseStatus status = FirebaseStatus.ready,
  }) =>
      FirebaseService._(status, null);

  FirebaseApp? get app => _app;
}

enum FirebaseStatus {
  /// Initialised and usable.
  ready,

  /// No `firebase_options.dart` in this build. Local mode.
  notConfigured,

  /// Configuration present but initialisation threw. Local mode.
  failed;

  String get label => switch (this) {
        FirebaseStatus.ready => 'Connected',
        FirebaseStatus.notConfigured => 'Local mode — cloud sync not set up',
        FirebaseStatus.failed => 'Local mode — cloud sync unavailable',
      };
}
