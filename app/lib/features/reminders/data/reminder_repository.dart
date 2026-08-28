import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:lifedna/core/data/synced_collection.dart';
import 'package:lifedna/core/notifications/notification_service.dart';
import 'package:lifedna/core/result/result.dart';
import 'package:lifedna/core/storage/hive_store.dart';
import 'package:lifedna/core/sync/outbox.dart';
import 'package:lifedna/features/reminders/domain/reminder.dart';
import 'package:uuid/uuid.dart';

/// User-created reminders and the OS schedule that backs them.
///
/// The record and its scheduled notification are always written together, so
/// there is no path where a reminder exists in the list but not in the
/// scheduler — the failure mode where an app silently stops reminding you.
class ReminderRepository {
  ReminderRepository({
    required HiveStore store,
    required Outbox outbox,
    required NotificationService notifications,
    FirebaseFirestore? firestore,
    String? uid,
    DateTime Function()? clock,
    Uuid uuid = const Uuid(),
  }) : _notifications = notifications,
       _clock = clock ?? DateTime.now,
       _uuid = uuid,
       _reminders = SyncedCollection<Reminder>(
         store: store,
         outbox: outbox,
         boxName: HiveStore.boxNotifications,
         collection: 'notifications',
         fromJson: Reminder.fromJson,
         firestore: firestore,
         uid: uid,
       );

  final SyncedCollection<Reminder> _reminders;
  final NotificationService _notifications;
  final DateTime Function() _clock;
  final Uuid _uuid;

  Stream<List<Reminder>> watchAll() => _reminders.watchAll().map(_sorted);

  List<Reminder> readAll() => _sorted(_reminders.readAll());

  static List<Reminder> _sorted(List<Reminder> items) {
    final sorted = [...items]
      ..sort((a, b) {
        final byTime = (a.hour * 60 + a.minute).compareTo(
          b.hour * 60 + b.minute,
        );
        return byTime != 0 ? byTime : a.title.compareTo(b.title);
      });
    return sorted;
  }

  Reminder draft() {
    final now = _clock().toUtc();
    return Reminder(
      id: _uuid.v4(),
      title: '',
      hour: 8,
      minute: 0,
      createdAt: now,
      updatedAt: now,
    );
  }

  Future<Result<Reminder>> save(Reminder reminder) async {
    final result = await _reminders.put(
      reminder.copyWith(updatedAt: _clock().toUtc()),
    );
    if (result is Ok<Reminder>) await _syncSchedule(reminder);
    return result;
  }

  Future<Result<void>> delete(String id) async {
    final existing = _reminders.readOne(id);
    if (existing != null) await _notifications.cancel(existing.notificationId);
    return _reminders.remove(
      id,
      tombstone: (value) => value.copyWith(deletedAt: _clock().toUtc()),
    );
  }

  Future<Result<Reminder>> setEnabled(Reminder reminder, {required bool on}) =>
      save(reminder.copyWith(enabled: on));

  /// Rebuilds the OS schedule from stored records. Called after a reboot-driven
  /// reschedule and when the global reminder switch is turned back on.
  Future<void> rescheduleAll() async {
    for (final reminder in readAll()) {
      await _syncSchedule(reminder);
    }
  }

  Future<void> _syncSchedule(Reminder reminder) async {
    await _notifications.cancel(reminder.notificationId);
    if (!reminder.enabled || reminder.deletedAt != null) return;
    await _notifications.scheduleDaily(
      id: reminder.notificationId,
      channel: NotificationChannelId.reminder,
      title: reminder.title,
      body: reminder.note ?? 'Reminder from LifeDNA',
      hour: reminder.hour,
      minute: reminder.minute,
      payload: 'reminder:${reminder.id}',
    );
  }

  Future<Result<int>> pullAll() => _reminders.pull();
}
