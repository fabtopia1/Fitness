import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lifedna/core/error/failure.dart';
import 'package:lifedna/features/health_sync/data/health_sync_service.dart';
import 'package:lifedna/features/health_sync/domain/health_entities.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  const channel = MethodChannel(HealthSyncService.channelName);
  final messenger =
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;

  /// Installs a native side that answers as the given handler decides. Passing
  /// null removes it, which is exactly the "not enabled in this build" case.
  void mockNative(Future<Object?>? Function(MethodCall call)? handler) {
    messenger.setMockMethodCallHandler(channel, handler);
  }

  tearDown(() => mockNative(null));

  HealthSyncService service({bool supported = true}) =>
      HealthSyncService(isSupported: () => supported);

  group('availability', () {
    test('a platform without Health Connect says so', () async {
      expect(
        await service(supported: false).availability(),
        HealthAvailability.unsupportedPlatform,
      );
    });

    test(
      'no native handler reports notEnabledInBuild, and does not crash',
      () async {
        // This is the shipped MVP's actual state. The app must run.
        mockNative(null);
        expect(
          await service().availability(),
          HealthAvailability.notEnabledInBuild,
        );
      },
    );

    test('each native answer maps to its own state', () async {
      for (final entry in {
        'ready': HealthAvailability.ready,
        'needs_permission': HealthAvailability.needsPermission,
        'provider_not_installed': HealthAvailability.providerNotInstalled,
        'anything_else': HealthAvailability.notEnabledInBuild,
      }.entries) {
        mockNative((call) async => entry.key);
        expect(await service().availability(), entry.value, reason: entry.key);
      }
    });

    test('a native error degrades instead of propagating', () async {
      mockNative((call) async => throw PlatformException(code: 'boom'));
      expect(
        await service().availability(),
        HealthAvailability.notEnabledInBuild,
      );
    });

    test(
      'only "ready" is usable, and only "needs permission" can be asked',
      () {
        expect(HealthAvailability.ready.isUsable, isTrue);
        expect(HealthAvailability.needsPermission.isUsable, isFalse);
        expect(HealthAvailability.needsPermission.canRequestPermission, isTrue);
        expect(
          HealthAvailability.notEnabledInBuild.canRequestPermission,
          isFalse,
        );

        for (final state in HealthAvailability.values) {
          expect(state.title, isNotEmpty, reason: state.name);
          expect(state.detail, isNotEmpty, reason: state.name);
        }
      },
    );
  });

  group('permissions', () {
    test('a granted request becomes ready', () async {
      mockNative((call) async {
        expect(call.method, 'requestPermissions');
        return true;
      });
      final result = await service().requestPermissions();
      expect(result.valueOrNull, HealthAvailability.ready);
    });

    test('a refused request stays at needsPermission', () async {
      mockNative((call) async => false);
      expect(
        (await service().requestPermissions()).valueOrNull,
        HealthAvailability.needsPermission,
      );
    });

    test('a platform error becomes a permission failure', () async {
      mockNative((call) async => throw PlatformException(code: 'denied'));
      expect(
        (await service().requestPermissions()).failureOrNull,
        isA<PermissionFailure>(),
      );
    });

    test('only four metrics are requested', () {
      // Every extra permission is another reason to decline the whole prompt.
      expect(HealthSyncService.requestedMetrics, hasLength(4));
      expect(
        HealthSyncService.requestedMetrics,
        containsAll([
          HealthMetric.steps,
          HealthMetric.activeCalories,
          HealthMetric.sleepMinutes,
          HealthMetric.restingHeartRate,
        ]),
      );
    });
  });

  group('reading', () {
    test(
      'an absent native side returns NO samples, not invented ones',
      () async {
        // A screen showing plausible step counts that were fabricated would be
        // worse than a screen showing nothing.
        mockNative(null);
        final result = await service().read(
          from: DateTime.utc(2026, 3, 14),
          to: DateTime.utc(2026, 3, 15),
        );
        expect(result.valueOrNull, isEmpty);
      },
    );

    test('samples are decoded and malformed rows are dropped', () async {
      mockNative(
        (call) async => [
          {
            'metric': 'steps',
            'value': 4200,
            'start': '2026-03-14T00:00:00.000Z',
            'end': '2026-03-14T23:59:00.000Z',
            'source': 'com.sec.android.app.shealth',
          },
          {'metric': 'nonsense', 'value': null},
        ],
      );

      final samples = (await service().read(
        from: DateTime.utc(2026, 3, 14),
        to: DateTime.utc(2026, 3, 15),
      )).valueOrNull!;

      expect(samples, hasLength(1));
      expect(samples.single.metric, HealthMetric.steps);
      expect(samples.single.value, 4200);
      expect(samples.single.source, contains('shealth'));
    });

    test('a read error is reported rather than swallowed', () async {
      mockNative((call) async => throw PlatformException(code: 'read_failed'));
      final result = await service().read(
        from: DateTime.utc(2026, 3, 14),
        to: DateTime.utc(2026, 3, 15),
      );
      expect(result.failureOrNull, isA<ServerFailure>());
    });
  });

  group('summarising a day', () {
    HealthSample sample(HealthMetric metric, double value) => HealthSample(
      metric: metric,
      value: value,
      start: DateTime.utc(2026, 3, 14),
      end: DateTime.utc(2026, 3, 14, 1),
      source: 'test',
    );

    test('cumulative metrics sum and instantaneous ones average', () {
      // Averaging steps or summing heart rate is the classic health bug.
      final summary = service().summarise([
        sample(HealthMetric.steps, 3000),
        sample(HealthMetric.steps, 1200),
        sample(HealthMetric.activeCalories, 200),
        sample(HealthMetric.activeCalories, 150),
        sample(HealthMetric.sleepMinutes, 420),
        sample(HealthMetric.restingHeartRate, 50),
        sample(HealthMetric.restingHeartRate, 56),
      ], '2026-03-14');

      expect(summary.steps, 4200);
      expect(summary.activeCalories, 350);
      expect(summary.sleepMinutes, 420);
      expect(summary.restingHeartRate, 53);
    });

    test('a metric with no samples stays null rather than becoming zero', () {
      // Zero steps and "we do not know" are different facts, and only one of
      // them should ever be shown as a number.
      final summary = service().summarise(const [], '2026-03-14');
      expect(summary.steps, isNull);
      expect(summary.restingHeartRate, isNull);
      expect(summary.localDate, '2026-03-14');
    });
  });

  test('the enablement steps are concrete and complete', () {
    expect(HealthSyncService.enablementSteps, isNotEmpty);
    for (final step in HealthSyncService.enablementSteps) {
      expect(step, isNotEmpty);
    }
    expect(
      HealthSyncService.enablementSteps.join(' '),
      contains(HealthSyncService.channelName),
    );
  });
}
