import 'dart:async';
import 'dart:io';

import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:hive/hive.dart';
import 'package:lifedna/core/config/app_bootstrap.dart';
import 'package:lifedna/core/firebase/firebase_service.dart';
import 'package:lifedna/core/firebase/telemetry_service.dart';
import 'package:lifedna/core/network/connectivity_service.dart';
import 'package:lifedna/core/notifications/notification_service.dart';
import 'package:lifedna/core/providers/providers.dart';
import 'package:lifedna/core/storage/hive_store.dart';

/// A [NotificationService] that records what it was asked to do instead of
/// talking to the platform.
///
/// Reminder scheduling is the one side effect a unit test cannot observe any
/// other way, and "the reminder silently stopped being scheduled" is exactly
/// the regression worth catching.
class FakeNotificationService implements NotificationService {
  FakeNotificationService({DateTime Function()? clock})
      : _clock = clock ?? DateTime.now;

  /// The real service refuses to schedule a time that has already passed. The
  /// fake applies the same rule against the test's clock rather than the wall
  /// clock, so a suite pinned to a fixed date behaves the same in 2026 and in
  /// 2030.
  final DateTime Function() _clock;

  final List<({int id, String title, int hour, int minute})> scheduledDaily = [];
  final List<({int id, String title, DateTime at})> scheduledOnce = [];
  final List<({int id, String title})> shown = [];
  final List<int> cancelled = [];
  int cancelAllCount = 0;

  bool _remindersEnabled = true;
  bool permissionGranted = true;

  @override
  bool get isReady => true;

  @override
  bool get hasPermission => permissionGranted;

  @override
  bool get remindersEnabled => _remindersEnabled;

  @override
  Future<void> setRemindersEnabled({required bool enabled}) async {
    _remindersEnabled = enabled;
    if (!enabled) await cancelAll();
  }

  @override
  Future<void> initialize({void Function(String? payload)? onTap}) async {}

  @override
  Future<bool> requestPermission() async => permissionGranted;

  @override
  Future<void> scheduleDaily({
    required int id,
    required NotificationChannelId channel,
    required String title,
    required String body,
    required int hour,
    required int minute,
    String? payload,
  }) async {
    if (!_remindersEnabled) return;
    scheduledDaily.add((id: id, title: title, hour: hour, minute: minute));
  }

  @override
  Future<void> scheduleOnce({
    required int id,
    required NotificationChannelId channel,
    required String title,
    required String body,
    required DateTime at,
    String? payload,
  }) async {
    if (!_remindersEnabled) return;
    if (!at.isAfter(_clock())) return;
    scheduledOnce.add((id: id, title: title, at: at));
  }

  @override
  Future<void> showNow({
    required int id,
    required NotificationChannelId channel,
    required String title,
    required String body,
    String? payload,
  }) async {
    shown.add((id: id, title: title));
  }

  @override
  Future<void> cancel(int id) async {
    cancelled.add(id);
    scheduledDaily.removeWhere((entry) => entry.id == id);
    scheduledOnce.removeWhere((entry) => entry.id == id);
  }

  @override
  Future<void> cancelAll() async {
    cancelAllCount++;
    scheduledDaily.clear();
    scheduledOnce.clear();
  }

  @override
  Future<List<PendingNotificationRequest>> pending() async => const [];
}

/// Connectivity the test controls.
class FakeConnectivityService implements ConnectivityService {
  FakeConnectivityService({bool online = true}) : _online = online {
    _controller.add(online);
  }

  final _controller = StreamController<bool>.broadcast();
  bool _online;

  set online(bool value) {
    _online = value;
    _controller.add(value);
  }

  @override
  Future<bool> get isOnline async => _online;

  @override
  Stream<bool> get onStatusChange => _controller.stream;

  Future<void> dispose() => _controller.close();
}

/// A bootstrap wired to in-memory storage and inert platform services.
///
/// Every test that needs the provider graph builds one of these, so a test
/// never touches the real keystore, the real notification scheduler or the
/// network.
class TestEnvironment {
  TestEnvironment._({
    required this.bootstrap,
    required this.notifications,
    required this.connectivity,
    required this.directory,
  });

  final AppBootstrap bootstrap;
  final FakeNotificationService notifications;
  final FakeConnectivityService connectivity;
  final Directory directory;

  HiveStore get store => bootstrap.store;

  static Future<TestEnvironment> create({
    bool online = true,
    DateTime Function()? clock,
  }) async {
    final directory = await Directory.systemTemp.createTemp('lifedna_test');
    Hive.init(directory.path);

    final store = await HiveStore.open(inMemory: true);
    final notifications = FakeNotificationService(clock: clock);
    final connectivity = FakeConnectivityService(online: online);

    return TestEnvironment._(
      bootstrap: AppBootstrap(
        store: store,
        // No Firebase project: exactly the local mode a first-run device is in
        // before anyone signs in.
        firebase: FirebaseService.forTesting(
          status: FirebaseStatus.notConfigured,
        ),
        telemetry: TelemetryService(available: false),
        notifications: notifications,
        connectivity: connectivity,
      ),
      notifications: notifications,
      connectivity: connectivity,
      directory: directory,
    );
  }

  /// A container with the bootstrap injected. The caller disposes it.
  ProviderContainer container({List<Override> overrides = const []}) =>
      ProviderContainer(
        overrides: [
          bootstrapProvider.overrideWithValue(bootstrap),
          ...overrides,
        ],
      );

  /// The overrides a widget test needs for its own ProviderScope.
  List<Override> get overrides => [
        bootstrapProvider.overrideWithValue(bootstrap),
      ];

  Future<void> dispose() async {
    await connectivity.dispose();
    await Hive.close();
    if (directory.existsSync()) {
      await directory.delete(recursive: true);
    }
  }
}
