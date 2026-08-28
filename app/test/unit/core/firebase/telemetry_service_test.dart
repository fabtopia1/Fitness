import 'package:flutter_test/flutter_test.dart';
import 'package:lifedna/core/error/failure.dart';
import 'package:lifedna/core/firebase/firebase_service.dart';
import 'package:lifedna/core/firebase/telemetry_service.dart';

void main() {
  group('TelemetryService.checkParams — the privacy backstop', () {
    test('a parameter that looks like personal data throws', () {
      // Failing loudly the first time a developer runs the app is far cheaper
      // than shipping a quiet leak.
      for (final key in [
        'email',
        'user_name',
        'food_name',
        'meal',
        'message',
        'content',
        'weight',
        'height',
        'value',
        'note',
        'title',
        'measurement',
        'photo',
        'address',
        'phone',
      ]) {
        expect(
          () => TelemetryService.checkParams({key: 'chicken breast'}),
          throwsArgumentError,
          reason: key,
        );
      }
    });

    test('counts, buckets and durations are allowed', () {
      expect(
        () => TelemetryService.checkParams({
          'set_count': 5,
          'duration_ms': 1200,
          'screen': 'nutrition',
          'has_photo': true,
        }),
        returnsNormally,
      );
    });

    test('a sensitive KEY carrying a non-string value is allowed', () {
      // `weight_kg: 82.5` is a number, not free text: it cannot carry a name,
      // an address or a note, and the bucketed magnitude is what analytics is
      // for. The rule targets strings because strings are what leak.
      expect(
        () => TelemetryService.checkParams({'weight_bucket': 3}),
        returnsNormally,
      );
    });

    test('a null parameter map is fine', () {
      expect(() => TelemetryService.checkParams(null), returnsNormally);
    });
  });

  group('consent gating', () {
    test('a service with no Firebase behind it is never enabled', () {
      final telemetry = TelemetryService(available: false);
      expect(telemetry.enabled, isFalse);
      expect(telemetry.crashReportingEnabled, isFalse);
    });

    test('opting out disables analytics without throwing on later calls',
        () async {
      final telemetry = TelemetryService(available: false);
      await telemetry.applyConsent(
        analyticsConsent: false,
        crashReportsConsent: false,
      );

      expect(telemetry.enabled, isFalse);
      // Every call must remain safe after opting out — a no-op, not a crash.
      await telemetry.logEvent('screen_view', parameters: {'screen': 'home'});
      await telemetry.setScreen('home');
      await telemetry.setUser('u1');
      await telemetry.recordFailure(const NetworkFailure());
    });

    test('validation still runs when telemetry is disabled', () {
      // Otherwise a leak would be invisible in dev and only appear in prod.
      expect(
        () => TelemetryService(available: false)
            .logEvent('log', parameters: {'food_name': 'chicken'}),
        throwsArgumentError,
      );
    });
  });

  group('FirebaseStatus', () {
    test('every status has user-facing copy', () {
      for (final status in FirebaseStatus.values) {
        expect(status.label, isNotEmpty, reason: status.name);
      }
    });

    test('only "ready" counts as available', () {
      expect(
        FirebaseService.forTesting(status: FirebaseStatus.ready).isAvailable,
        isTrue,
      );
      expect(
        FirebaseService.forTesting(status: FirebaseStatus.notConfigured)
            .isAvailable,
        isFalse,
      );
      expect(
        FirebaseService.forTesting(status: FirebaseStatus.failed).isAvailable,
        isFalse,
      );
    });
  });
}
