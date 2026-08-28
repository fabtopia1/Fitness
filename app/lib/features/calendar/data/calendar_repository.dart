import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:lifedna/core/data/synced_collection.dart';
import 'package:lifedna/core/data/synced_entity.dart';
import 'package:lifedna/core/error/failure.dart';
import 'package:lifedna/core/notifications/notification_service.dart';
import 'package:lifedna/core/result/result.dart';
import 'package:lifedna/core/storage/hive_store.dart';
import 'package:lifedna/core/sync/outbox.dart';
import 'package:lifedna/features/calendar/data/google_calendar_service.dart';
import 'package:lifedna/features/calendar/domain/calendar_entities.dart';
import 'package:lifedna/shared/enums/enums.dart';
import 'package:uuid/uuid.dart';

class CalendarRepository {
  CalendarRepository({
    required HiveStore store,
    required Outbox outbox,
    required NotificationService notifications,
    required GoogleCalendarService google,
    FirebaseFirestore? firestore,
    String? uid,
    Uuid uuid = const Uuid(),
    DateTime Function()? clock,
  })  : _store = store,
        _notifications = notifications,
        _google = google,
        _uuid = uuid,
        _clock = clock ?? DateTime.now,
        tasks = SyncedCollection<Task>(
          store: store,
          outbox: outbox,
          boxName: HiveStore.boxTasks,
          collection: 'tasks',
          fromJson: Task.fromJson,
          firestore: firestore,
          uid: uid,
        ),
        events = SyncedCollection<CalendarEvent>(
          store: store,
          outbox: outbox,
          boxName: HiveStore.boxCalendarEvents,
          collection: 'calendar_events',
          fromJson: CalendarEvent.fromJson,
          firestore: firestore,
          uid: uid,
        );

  final HiveStore _store;
  final NotificationService _notifications;
  final GoogleCalendarService _google;
  final Uuid _uuid;
  final DateTime Function() _clock;

  final SyncedCollection<Task> tasks;
  final SyncedCollection<CalendarEvent> events;

  static const _lastGoogleSyncKey = 'google_calendar_last_sync';

  // ------------------------------------------------------------------ tasks --

  Stream<List<Task>> watchTasks() => tasks.watchAll();

  List<Task> openTasks() {
    final open = tasks.readAll().where((t) => !t.isDone).toList()
      ..sort((a, b) {
        // Overdue first, then by due date, then by priority. A task with no
        // due date sorts last: it is a someday item, not today's problem.
        final aDue = a.dueAt;
        final bDue = b.dueAt;
        if (aDue == null && bDue != null) return 1;
        if (aDue != null && bDue == null) return -1;
        if (aDue != null && bDue != null) {
          final byDue = aDue.compareTo(bDue);
          if (byDue != 0) return byDue;
        }
        return a.priority.level.compareTo(b.priority.level);
      });
    return open;
  }

  List<Task> tasksDueOn(DateTime day) =>
      tasks.readAll().where((t) => t.isDueOn(day)).toList();

  int overdueCount([DateTime? now]) {
    final when = now ?? _clock();
    return tasks.readAll().where((t) => t.isOverdue(when)).length;
  }

  Task createTask({
    required String title,
    String? notes,
    TaskCategory category = TaskCategory.personal,
    TaskPriority priority = TaskPriority.p3,
    DateTime? dueAt,
    int? reminderMinutesBefore,
  }) {
    final now = _clock().toUtc();
    return Task(
      id: _uuid.v4(),
      title: title.trim(),
      notes: notes,
      category: category,
      priority: priority,
      dueAt: dueAt?.toUtc(),
      reminderMinutesBefore: reminderMinutesBefore,
      createdAt: now,
      updatedAt: now,
    );
  }

  Future<Result<Task>> saveTask(Task task) async {
    if (task.title.trim().isEmpty) {
      return const Err(ValidationFailure('required', field: 'title'));
    }
    final result = await tasks.put(task);
    if (result.isOk) await _syncTaskReminder(task);
    return result;
  }

  Future<Result<Task>> toggleTask(Task task) async {
    final done = !task.isDone;
    final updated = task.copyWith(
      status: done ? TaskStatus.done : TaskStatus.open,
      completedAt: done ? _clock().toUtc() : null,
    );
    final result = await tasks.put(updated);
    if (result.isOk) {
      // A completed task must stop reminding, or the app nags about work the
      // user already finished — the fastest way to get notifications disabled.
      await _notifications.cancel(task.notificationId);
      if (!done) await _syncTaskReminder(updated);
    }
    return result;
  }

  Future<Result<void>> deleteTask(String id) async {
    final existing = tasks.readOne(id);
    if (existing != null) await _notifications.cancel(existing.notificationId);
    return tasks.remove(
      id,
      tombstone: (t) => t.copyWith(deletedAt: _clock().toUtc()),
    );
  }

  Future<void> _syncTaskReminder(Task task) async {
    await _notifications.cancel(task.notificationId);
    final at = task.reminderAt;
    if (task.isDone || at == null) return;
    await _notifications.scheduleOnce(
      id: task.notificationId,
      channel: NotificationChannelId.task,
      title: task.title,
      body: 'Due at ${_hhmm(task.dueAt!.toLocal())}',
      at: at.toLocal(),
      payload: 'task:${task.id}',
    );
  }

  /// Re-arms task reminders. Android drops scheduled alarms on reboot.
  Future<void> rescheduleAllReminders() async {
    for (final task in tasks.readAll()) {
      await _syncTaskReminder(task);
    }
  }

  // ----------------------------------------------------------------- events --

  Stream<List<CalendarEvent>> watchEvents() => events.watchAll();

  List<CalendarEvent> eventsOn(DateTime day) {
    final list = events.readAll().where((e) => e.occursOn(day)).toList()
      ..sort((a, b) => a.startAt.compareTo(b.startAt));
    return list;
  }

  List<CalendarEvent> upcoming({int limit = 5, DateTime? now}) {
    final from = now ?? _clock();
    final list = events
        .readAll()
        .where((e) => e.endAt.isAfter(from.toUtc()))
        .toList()
      ..sort((a, b) => a.startAt.compareTo(b.startAt));
    return list.take(limit).toList();
  }

  CalendarEvent createEvent({
    required String title,
    required DateTime startAt,
    required DateTime endAt,
    String? description,
    String? location,
    bool isAllDay = false,
  }) =>
      CalendarEvent(
        id: _uuid.v4(),
        title: title.trim(),
        description: description,
        location: location,
        startAt: startAt.toUtc(),
        endAt: endAt.toUtc(),
        isAllDay: isAllDay,
        updatedAt: _clock().toUtc(),
      );

  Future<Result<CalendarEvent>> saveEvent(CalendarEvent event) {
    if (event.title.trim().isEmpty) {
      return Future.value(
        const Err(ValidationFailure('required', field: 'title')),
      );
    }
    if (!event.endAt.isAfter(event.startAt)) {
      return Future.value(const Err(ValidationFailure('end_before_start')));
    }
    if (event.isReadOnly) {
      // Google-sourced events are mirrored, not owned. Editing one here would
      // silently diverge from the user's real calendar.
      return Future.value(const Err(ValidationFailure('event_read_only')));
    }
    return events.put(event);
  }

  Future<Result<void>> deleteEvent(String id) {
    final existing = events.readOne(id);
    if (existing != null && existing.isReadOnly) {
      return Future.value(const Err(ValidationFailure('event_read_only')));
    }
    return events.remove(
      id,
      tombstone: (e) => e.copyWith(deletedAt: _clock().toUtc()),
    );
  }

  // ---------------------------------------------------------- Google sync --

  bool get isGoogleConfigured => _google.isConfigured;

  Future<bool> get isGoogleConnected => _google.isConnected;

  DateTime? get lastGoogleSync {
    final json = _store.read(HiveStore.boxMeta, _lastGoogleSyncKey);
    return json == null ? null : Json.dateOrNull(json['at']);
  }

  Future<Result<String>> connectGoogle() => _google.connect();

  Future<Result<void>> disconnectGoogle() async {
    final result = await _google.disconnect();
    if (result.isOk) {
      // Remove mirrored events on disconnect: keeping a copy of someone's
      // meetings after they revoked access would be indefensible.
      for (final event in events.readAll()) {
        if (event.source == EventSource.google) {
          await events.remove(
            event.id,
            tombstone: (e) => e.copyWith(deletedAt: _clock().toUtc()),
          );
        }
      }
      await _store.delete(HiveStore.boxMeta, _lastGoogleSyncKey);
    }
    return result;
  }

  /// Pulls a window of Google events into the local mirror.
  Future<Result<int>> syncGoogle({int daysBack = 7, int daysForward = 30}) async {
    final now = _clock();
    final result = await _google.fetchEvents(
      from: now.subtract(Duration(days: daysBack)),
      to: now.add(Duration(days: daysForward)),
    );

    switch (result) {
      case Err(:final failure):
        return Err(failure);
      case Ok(value: final fetched):
        for (final event in fetched) {
          await events.put(event);
        }
        await _store.write(HiveStore.boxMeta, _lastGoogleSyncKey, {
          'at': now.toUtc().toIso8601String(),
          'count': fetched.length,
        });
        return Ok(fetched.length);
    }
  }

  Future<Result<int>> pullAll() async {
    final results = await Future.wait([tasks.pull(), events.pull()]);
    var total = 0;
    for (final result in results) {
      if (result.isErr) return result;
      total += result.valueOrNull ?? 0;
    }
    return Ok(total);
  }

  static String _hhmm(DateTime t) =>
      '${t.hour.toString().padLeft(2, '0')}:'
      '${t.minute.toString().padLeft(2, '0')}';
}
