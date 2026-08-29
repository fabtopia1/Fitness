import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_analytics/firebase_analytics.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_crashlytics/firebase_crashlytics.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/foundation.dart';
import 'package:lifedna/core/config/env.dart';
import 'package:lifedna/core/config/firebase_config.dart';
import 'package:lifedna/core/firebase/firebase_service.dart';
import 'package:lifedna/core/firebase/telemetry_service.dart';
import 'package:lifedna/core/network/connectivity_service.dart';
import 'package:lifedna/core/notifications/notification_service.dart';
import 'package:lifedna/core/storage/hive_store.dart';
import 'package:lifedna/features/auth/data/google_identity.dart';
import 'package:lifedna/core/storage/photo_store.dart';

/// Everything that must exist before the first frame.
///
/// Assembled once in `main` and injected through Riverpod overrides, so no
/// widget ever awaits initialisation and no provider has to model "not ready
/// yet" as a state.
class AppBootstrap {
  const AppBootstrap({
    required this.store,
    required this.firebase,
    required this.telemetry,
    required this.notifications,
    required this.connectivity,
    required this.photos,
    this.firestore,
    this.auth,
    this.google,
    this.messaging,
  });

  final HiveStore store;
  final FirebaseService firebase;
  final TelemetryService telemetry;
  final NotificationService notifications;
  final ConnectivityService connectivity;

  /// Progress-photo storage. Resolved once, because widgets need the directory
  /// synchronously to build an `Image.file`.
  final PhotoStore photos;

  final FirebaseFirestore? firestore;
  final FirebaseAuth? auth;
  final GoogleIdentitySource? google;
  final FirebaseMessaging? messaging;

  bool get isCloudBacked => firestore != null && auth != null;

  static Future<AppBootstrap> initialize() async {
    final store = await HiveStore.open();
    final photos = await PhotoStore.open();

    final firebase = await FirebaseService.initialize(
      options: FirebaseConfig.currentPlatform,
    );

    FirebaseFirestore? firestore;
    FirebaseAuth? auth;
    GoogleIdentitySource? google;
    FirebaseMessaging? messaging;
    FirebaseAnalytics? analytics;
    FirebaseCrashlytics? crashlytics;

    if (firebase.isAvailable) {
      firestore = FirebaseFirestore.instance;
      auth = FirebaseAuth.instance;
      google = PluginGoogleIdentitySource();
      analytics = FirebaseAnalytics.instance;

      try {
        crashlytics = FirebaseCrashlytics.instance;
        await crashlytics.setCrashlyticsCollectionEnabled(
          Env.crashlyticsEnabled,
        );
      } on Object catch (error) {
        debugPrint('Bootstrap: Crashlytics unavailable — $error');
        crashlytics = null;
      }

      try {
        // The instance is obtained, but permission is NOT requested here.
        // `requestPermission` raises the Android 13+ system dialog, and doing
        // that during bootstrap asks a user who has not yet seen a single
        // frame — which is how an app gets its notifications declined for
        // good. The ask happens where a reminder would first help, from the
        // reminder card in Settings.
        messaging = FirebaseMessaging.instance;
      } on Object catch (error) {
        debugPrint('Bootstrap: Messaging unavailable — $error');
        messaging = null;
      }
    }

    final notifications = NotificationService();
    await notifications.initialize();

    return AppBootstrap(
      store: store,
      firebase: firebase,
      telemetry: TelemetryService(
        analytics: analytics,
        crashlytics: crashlytics,
        available: firebase.isAvailable,
      ),
      notifications: notifications,
      connectivity: ConnectivityService(),
      photos: photos,
      firestore: firestore,
      auth: auth,
      google: google,
      messaging: messaging,
    );
  }
}
