import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:lifedna/core/error/failure.dart';
import 'package:lifedna/core/result/result.dart';
import 'package:lifedna/features/health_sync/domain/health_entities.dart';

/// Platform health integration.
///
/// ## Why Health Connect rather than the Samsung Health SDK
///
/// The Samsung Health Data SDK requires partner registration and per-app
/// approval that cannot be obtained during a build, and its availability
/// cannot be verified from source. Health Connect is the officially supported,
/// publicly documented Android path, and Samsung Health writes its data there
/// — so reading Health Connect *is* reading Samsung Health, without a
/// commercial dependency that could block the release.
///
/// ## What this class guarantees
///
/// It NEVER fabricates a sample. If the native side is absent, the permission
/// is denied, or the provider is not installed, it reports exactly that and
/// returns no data. A screen showing plausible-looking step counts that were
/// invented would be worse than a screen showing nothing.
///
/// The Dart side is complete and compiled. The native handler is registered
/// separately; when it is missing, [MissingPluginException] is caught and the
/// module reports [HealthAvailability.notEnabledInBuild] rather than crashing.
class HealthSyncService {
  HealthSyncService({MethodChannel? channel, bool Function()? isSupported})
      : _channel = channel ?? const MethodChannel(channelName),
        _isSupported = isSupported ?? (() => Platform.isAndroid);

  static const String channelName = 'os.lifedna/health';

  final MethodChannel _channel;

  /// Injected so the platform gate itself is testable. Health Connect is
  /// Android-only; every other platform reports that plainly.
  final bool Function() _isSupported;

  /// Metrics this build requests. Kept minimal on purpose: every extra
  /// permission is another reason for a user to decline the whole prompt.
  static const List<HealthMetric> requestedMetrics = [
    HealthMetric.steps,
    HealthMetric.activeCalories,
    HealthMetric.sleepMinutes,
    HealthMetric.restingHeartRate,
  ];

  Future<HealthAvailability> availability() async {
    if (!_isSupported()) return HealthAvailability.unsupportedPlatform;
    try {
      final raw = await _channel.invokeMethod<String>('availability');
      return switch (raw) {
        'ready' => HealthAvailability.ready,
        'needs_permission' => HealthAvailability.needsPermission,
        'provider_not_installed' => HealthAvailability.providerNotInstalled,
        _ => HealthAvailability.notEnabledInBuild,
      };
    } on MissingPluginException {
      return HealthAvailability.notEnabledInBuild;
    } on PlatformException catch (error) {
      debugPrint('HealthSyncService: availability failed — ${error.message}');
      return HealthAvailability.notEnabledInBuild;
    }
  }

  /// Opens the platform permission flow. Returns the resulting availability.
  Future<Result<HealthAvailability>> requestPermissions() async {
    if (!_isSupported()) {
      return const Ok(HealthAvailability.unsupportedPlatform);
    }
    try {
      final granted = await _channel.invokeMethod<bool>(
        'requestPermissions',
        {'metrics': requestedMetrics.map((m) => m.wire).toList()},
      );
      return Ok(
        (granted ?? false)
            ? HealthAvailability.ready
            : HealthAvailability.needsPermission,
      );
    } on MissingPluginException {
      return const Ok(HealthAvailability.notEnabledInBuild);
    } on PlatformException catch (error) {
      return Err(
        PermissionFailure('health', debugMessage: error.message),
      );
    }
  }

  /// Reads samples in a window.
  ///
  /// Returns an EMPTY list when the provider is unavailable — never a
  /// synthesised one.
  Future<Result<List<HealthSample>>> read({
    required DateTime from,
    required DateTime to,
    List<HealthMetric>? metrics,
  }) async {
    if (!_isSupported()) return const Ok([]);
    try {
      final raw = await _channel.invokeListMethod<Map<Object?, Object?>>(
        'read',
        {
          'from': from.toUtc().toIso8601String(),
          'to': to.toUtc().toIso8601String(),
          'metrics':
              (metrics ?? requestedMetrics).map((m) => m.wire).toList(),
        },
      );

      final samples = <HealthSample>[];
      for (final entry in raw ?? const <Map<Object?, Object?>>[]) {
        final sample = HealthSample.fromPlatform(entry);
        if (sample != null) samples.add(sample);
      }
      return Ok(samples);
    } on MissingPluginException {
      return const Ok([]);
    } on PlatformException catch (error) {
      return Err(ServerFailure('health_read_failed', debugMessage: error.message));
    }
  }

  /// Collapses samples into a day summary.
  ///
  /// Cumulative metrics sum; instantaneous ones average. Getting this wrong in
  /// the other direction — averaging steps, summing heart rate — is the
  /// classic health-integration bug.
  DailyHealthSummary summarise(
    List<HealthSample> samples,
    String localDate,
  ) {
    double? steps;
    double? calories;
    double? distance;
    double? sleep;
    final restingRates = <double>[];

    for (final sample in samples) {
      switch (sample.metric) {
        case HealthMetric.steps:
          steps = (steps ?? 0) + sample.value;
        case HealthMetric.activeCalories:
          calories = (calories ?? 0) + sample.value;
        case HealthMetric.distance:
          distance = (distance ?? 0) + sample.value;
        case HealthMetric.sleepMinutes:
          sleep = (sleep ?? 0) + sample.value;
        case HealthMetric.restingHeartRate:
          restingRates.add(sample.value);
        case HealthMetric.heartRate:
        case HealthMetric.weight:
          break;
      }
    }

    return DailyHealthSummary(
      localDate: localDate,
      steps: steps?.round(),
      activeCalories: calories,
      distanceMetres: distance,
      sleepMinutes: sleep?.round(),
      restingHeartRate: restingRates.isEmpty
          ? null
          : (restingRates.reduce((a, b) => a + b) / restingRates.length).round(),
    );
  }

  /// What a developer must do to turn this on. Surfaced in the UI so the
  /// blocked state is actionable rather than mysterious.
  static const List<String> enablementSteps = [
    'Install Health Connect on the device (pre-installed on Android 14+).',
    'Open Samsung Health once and allow it to share data with Health Connect.',
    'Declare the Health Connect read permissions and the permissions-rationale '
        'activity in android/app/src/main/AndroidManifest.xml. They are '
        'deliberately absent today: declaring health permissions an app does '
        'not use fails the Play health-data review.',
    'Register the native handler for the "os.lifedna/health" MethodChannel.',
    'Complete the Google Play health-data declaration before release.',
  ];
}
