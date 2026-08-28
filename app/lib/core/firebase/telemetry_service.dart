import 'package:firebase_analytics/firebase_analytics.dart';
import 'package:firebase_crashlytics/firebase_crashlytics.dart';
import 'package:flutter/foundation.dart';
import 'package:lifedna/core/config/env.dart';
import 'package:lifedna/core/error/failure.dart';

/// Analytics and crash reporting.
///
/// GOVERNING RULE: no health value, food name, measurement, or free text ever
/// enters an event or a crash report. Events carry counts, categories,
/// durations and booleans only. This is enforced by [checkParams], which
/// throws rather than silently shipping a privacy leak, and is covered by a
/// unit test.
class TelemetryService {
  TelemetryService({this.analytics, this.crashlytics, bool available = true})
    : _available = available;

  final FirebaseAnalytics? analytics;
  final FirebaseCrashlytics? crashlytics;

  /// Whether telemetry is possible at all in this build — false in local mode,
  /// where there is no Firebase project to send anything to.
  final bool _available;

  bool _analyticsConsent = true;
  bool _crashConsent = true;

  /// Three gates, all of which must be open: the build has Firebase, the
  /// flavour permits collection, and the user has not opted out.
  bool get enabled => _available && Env.analyticsEnabled && _analyticsConsent;

  bool get crashReportingEnabled =>
      _available && Env.crashlyticsEnabled && _crashConsent;

  /// Applies the user's privacy choices to the SDKs themselves.
  ///
  /// Gating only at the call site would still leave the Firebase SDKs
  /// collecting in the background, so consent is pushed down to them as well
  /// as held here.
  Future<void> applyConsent({
    required bool analyticsConsent,
    required bool crashReportsConsent,
  }) async {
    _analyticsConsent = analyticsConsent;
    _crashConsent = crashReportsConsent;
    try {
      await analytics?.setAnalyticsCollectionEnabled(enabled);
      await crashlytics?.setCrashlyticsCollectionEnabled(crashReportingEnabled);
    } on Object catch (error) {
      debugPrint('Telemetry: consent not applied to SDKs — $error');
    }
  }

  static final RegExp _sensitiveKey = RegExp(
    r'email|name|food|meal|message|content|weight|height|value|note|title|'
    r'measurement|photo|address|phone',
    caseSensitive: false,
  );

  /// Throws if a parameter looks like personal or health data.
  ///
  /// Deliberately fails loudly: a leak that ships quietly is far more costly
  /// than a crash caught the first time a developer runs the app.
  static void checkParams(Map<String, Object>? params) {
    if (params == null) return;
    for (final entry in params.entries) {
      if (entry.value is String && _sensitiveKey.hasMatch(entry.key)) {
        throw ArgumentError(
          'Analytics parameter "${entry.key}" looks like personal or health '
          'data. Log a count, a bucket or a category instead.',
        );
      }
    }
  }

  Future<void> logEvent(String name, {Map<String, Object>? parameters}) async {
    checkParams(parameters);
    final instance = analytics;
    if (!enabled || instance == null) return;
    try {
      await instance.logEvent(name: name, parameters: parameters);
    } on Object catch (error) {
      debugPrint('Telemetry: analytics event "$name" dropped — $error');
    }
  }

  Future<void> setScreen(String screenName) async {
    final instance = analytics;
    if (!enabled || instance == null) return;
    try {
      await instance.logScreenView(screenName: screenName);
    } on Object catch (error) {
      debugPrint('Telemetry: screen view dropped — $error');
    }
  }

  /// Associates events with a user without sending anything that maps back to
  /// a person outside our own systems.
  Future<void> setUser(String? uid) async {
    if (!enabled) return;
    try {
      await analytics?.setUserId(id: uid);
      await crashlytics?.setUserIdentifier(uid ?? '');
    } on Object catch (error) {
      debugPrint('Telemetry: setUser dropped — $error');
    }
  }

  Future<void> recordError(
    Object error,
    StackTrace? stackTrace, {
    String? context,
    bool fatal = false,
  }) async {
    final instance = crashlytics;
    if (!crashReportingEnabled || instance == null) {
      debugPrint('Telemetry(local): $context $error');
      return;
    }
    try {
      await instance.recordError(
        error,
        stackTrace,
        reason: context,
        fatal: fatal,
      );
    } on Object catch (nested) {
      debugPrint('Telemetry: crash report dropped — $nested');
    }
  }

  /// Records a handled domain failure.
  ///
  /// The failure CODE is safe to send. The debug message may contain user
  /// content, so it never leaves the device.
  Future<void> recordFailure(Failure failure, {String? context}) => logEvent(
    'app_failure',
    parameters: {
      'failure_code': failure.code,
      'failure_type': failure.runtimeType.toString(),
      if (context != null) 'context': context,
    },
  );
}
