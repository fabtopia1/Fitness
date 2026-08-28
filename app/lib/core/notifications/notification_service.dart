import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:timezone/data/latest_all.dart' as tzdata;
import 'package:timezone/timezone.dart' as tz;

/// Notification categories. Each maps to its own Android channel so a user can
/// mute meal reminders in system settings without losing workout reminders.
enum NotificationChannelId {
  supplement('supplement', 'Supplements', 'Reminders to take a supplement'),
  meal('meal', 'Meals', 'Reminders to log a meal'),
  workout('workout', 'Workouts', 'Reminders about a scheduled workout'),
  task('task', 'Tasks', 'Reminders about a due task'),
  restTimer('rest_timer', 'Rest timer', 'Rest period finished'),
  reminder('reminder', 'Reminders', 'Reminders you created yourself');

  const NotificationChannelId(this.id, this.title, this.description);
  final String id;
  final String title;
  final String description;
}

/// Local notifications.
///
/// Deliberately LOCAL, not push. A supplement reminder at 22:30 must fire in a
/// basement gym with no signal; routing it through FCM would make the network
/// a dependency of a purely time-based event. FCM is reserved for things the
/// server actually knows first.
///
/// Every scheduling call is idempotent: ids are derived from the owning
/// record, so rescheduling replaces rather than stacks.
class NotificationService {
  NotificationService({FlutterLocalNotificationsPlugin? plugin})
      : _plugin = plugin ?? FlutterLocalNotificationsPlugin();

  final FlutterLocalNotificationsPlugin _plugin;
  bool _ready = false;
  bool _permissionGranted = false;

  bool _remindersEnabled = true;

  bool get isReady => _ready;
  bool get hasPermission => _permissionGranted;

  /// The user's master switch for scheduled reminders.
  bool get remindersEnabled => _remindersEnabled;

  /// Turns every *scheduled* notification on or off in one place.
  ///
  /// Gating here rather than at each call site means a reminder created while
  /// the switch is off cannot slip through, whichever feature creates it.
  /// [showNow] is deliberately not gated: the rest-timer alert is a response
  /// to something the user started seconds ago, not a scheduled interruption.
  Future<void> setRemindersEnabled({required bool enabled}) async {
    _remindersEnabled = enabled;
    if (!enabled) await cancelAll();
  }

  /// Initialises the plugin and the timezone database.
  ///
  /// Does NOT request permission — that happens at the moment a reminder would
  /// first help, which roughly doubles grant rates versus asking at launch.
  Future<void> initialize({
    void Function(String? payload)? onTap,
  }) async {
    if (_ready) return;
    try {
      tzdata.initializeTimeZones();

      // A monochrome drawable, not the launcher icon: Android masks the
      // status-bar icon to its alpha channel, so a full-colour launcher icon
      // renders as a white square.
      const android = AndroidInitializationSettings('@drawable/ic_notification');
      const darwin = DarwinInitializationSettings(
        requestAlertPermission: false,
        requestBadgePermission: false,
        requestSoundPermission: false,
      );

      await _plugin.initialize(
        const InitializationSettings(android: android, iOS: darwin),
        onDidReceiveNotificationResponse: (response) =>
            onTap?.call(response.payload),
      );

      final android_ = _plugin.resolvePlatformSpecificImplementation<
          AndroidFlutterLocalNotificationsPlugin>();
      for (final channel in NotificationChannelId.values) {
        await android_?.createNotificationChannel(
          AndroidNotificationChannel(
            channel.id,
            channel.title,
            description: channel.description,
            importance: Importance.defaultImportance,
          ),
        );
      }
      // Read the real permission state rather than assuming denial: on a
      // restart the user has usually already granted it, and asking again
      // would be the app forgetting something it was told.
      _permissionGranted = await android_?.areNotificationsEnabled() ?? true;

      _ready = true;
    } on Object catch (error) {
      // A device that cannot schedule notifications must still run the app.
      debugPrint('NotificationService: unavailable — $error');
      _ready = false;
    }
  }

  /// Requests permission. Returns whether it was granted.
  Future<bool> requestPermission() async {
    if (!_ready) return false;
    try {
      final android = _plugin.resolvePlatformSpecificImplementation<
          AndroidFlutterLocalNotificationsPlugin>();
      final ios = _plugin.resolvePlatformSpecificImplementation<
          IOSFlutterLocalNotificationsPlugin>();

      final granted = await android?.requestNotificationsPermission() ??
          await ios?.requestPermissions(alert: true, badge: true, sound: true) ??
          false;
      _permissionGranted = granted;
      return granted;
    } on Object catch (error) {
      debugPrint('NotificationService: permission request failed — $error');
      return false;
    }
  }

  /// Schedules a daily repeating reminder at [hour]:[minute].
  Future<void> scheduleDaily({
    required int id,
    required NotificationChannelId channel,
    required String title,
    required String body,
    required int hour,
    required int minute,
    String? payload,
  }) async {
    if (!_ready || !_remindersEnabled) return;
    try {
      await _plugin.zonedSchedule(
        id,
        title,
        body,
        _nextInstanceOf(hour, minute),
        _details(channel),
        androidScheduleMode: AndroidScheduleMode.inexactAllowWhileIdle,
        uiLocalNotificationDateInterpretation:
            UILocalNotificationDateInterpretation.absoluteTime,
        matchDateTimeComponents: DateTimeComponents.time,
        payload: payload,
      );
    } on Object catch (error) {
      debugPrint('NotificationService: scheduleDaily($id) failed — $error');
    }
  }

  /// Schedules a one-off reminder. A time already in the past is skipped
  /// rather than firing immediately, which would be startling and useless.
  Future<void> scheduleOnce({
    required int id,
    required NotificationChannelId channel,
    required String title,
    required String body,
    required DateTime at,
    String? payload,
  }) async {
    if (!_ready || !_remindersEnabled) return;
    if (!at.isAfter(DateTime.now())) return;
    try {
      await _plugin.zonedSchedule(
        id,
        title,
        body,
        tz.TZDateTime.from(at, tz.local),
        _details(channel),
        androidScheduleMode: AndroidScheduleMode.inexactAllowWhileIdle,
        uiLocalNotificationDateInterpretation:
            UILocalNotificationDateInterpretation.absoluteTime,
        payload: payload,
      );
    } on Object catch (error) {
      debugPrint('NotificationService: scheduleOnce($id) failed — $error');
    }
  }

  /// Fires immediately. Used by the rest timer when the app is backgrounded.
  Future<void> showNow({
    required int id,
    required NotificationChannelId channel,
    required String title,
    required String body,
    String? payload,
  }) async {
    if (!_ready) return;
    try {
      await _plugin.show(id, title, body, _details(channel), payload: payload);
    } on Object catch (error) {
      debugPrint('NotificationService: showNow($id) failed — $error');
    }
  }

  Future<void> cancel(int id) async {
    if (!_ready) return;
    try {
      await _plugin.cancel(id);
    } on Object catch (error) {
      debugPrint('NotificationService: cancel($id) failed — $error');
    }
  }

  Future<void> cancelAll() async {
    if (!_ready) return;
    try {
      await _plugin.cancelAll();
    } on Object catch (error) {
      debugPrint('NotificationService: cancelAll failed — $error');
    }
  }

  Future<List<PendingNotificationRequest>> pending() async {
    if (!_ready) return const [];
    try {
      return await _plugin.pendingNotificationRequests();
    } on Object {
      return const [];
    }
  }

  NotificationDetails _details(NotificationChannelId channel) =>
      NotificationDetails(
        android: AndroidNotificationDetails(
          channel.id,
          channel.title,
          channelDescription: channel.description,
          importance: Importance.defaultImportance,
          priority: Priority.defaultPriority,
        ),
        iOS: const DarwinNotificationDetails(),
      );

  static tz.TZDateTime _nextInstanceOf(int hour, int minute) {
    final now = tz.TZDateTime.now(tz.local);
    var scheduled =
        tz.TZDateTime(tz.local, now.year, now.month, now.day, hour, minute);
    if (!scheduled.isAfter(now)) {
      scheduled = scheduled.add(const Duration(days: 1));
    }
    return scheduled;
  }
}
