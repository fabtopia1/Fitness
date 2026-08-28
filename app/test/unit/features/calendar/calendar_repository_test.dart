import 'package:flutter_test/flutter_test.dart';
import 'package:lifedna/core/error/failure.dart';
import 'package:lifedna/core/result/result.dart';
import 'package:lifedna/core/sync/outbox.dart';
import 'package:lifedna/features/calendar/data/calendar_repository.dart';
import 'package:lifedna/features/calendar/data/google_calendar_service.dart';
import 'package:lifedna/features/calendar/domain/calendar_entities.dart';
import 'package:lifedna/shared/enums/enums.dart';

import '../../../support/test_harness.dart';

/// A Google Calendar the test drives, so the suite never needs OAuth.
class _FakeGoogleCalendar implements GoogleCalendarService {
  _FakeGoogleCalendar({this.configured = true});

  final bool configured;
  bool connected = false;
  List<CalendarEvent> remote = const [];
  Failure? failure;

  @override
  bool get isConfigured => configured;

  @override
  Future<bool> get isConnected async => connected;

  @override
  Future<Result<String>> connect() async {
    connected = true;
    return const Ok('someone@example.com');
  }

  @override
  Future<Result<void>> disconnect() async {
    connected = false;
    return const Ok(null);
  }

  @override
  Future<Result<List<CalendarEvent>>> fetchEvents({
    required DateTime from,
    required DateTime to,
    int maxResults = 250,
  }) async {
    final error = failure;
    if (error != null) return Err(error);
    return Ok(remote);
  }
}

void main() {
  late TestEnvironment env;
  late CalendarRepository repository;
  late _FakeGoogleCalendar google;

  final now = DateTime(2026, 3, 14, 9);

  setUp(() async {
    env = await TestEnvironment.create(clock: () => now);
    google = _FakeGoogleCalendar();
    repository = CalendarRepository(
      store: env.store,
      outbox: Outbox(env.store),
      notifications: env.notifications,
      google: google,
      clock: () => now,
    );
  });
  tearDown(() async => env.dispose());

  group('tasks', () {
    test('a task needs a title', () async {
      final result = await repository.saveTask(
        repository.createTask(title: '   '),
      );
      expect(result.failureOrNull, isA<ValidationFailure>());
    });

    test(
      'open tasks sort overdue first, then by due date, then by priority',
      () async {
        await repository.saveTask(
          repository.createTask(title: 'Someday', priority: TaskPriority.p1),
        );
        await repository.saveTask(
          repository.createTask(
            title: 'Tomorrow',
            dueAt: now.add(const Duration(days: 1)),
          ),
        );
        await repository.saveTask(
          repository.createTask(
            title: 'Overdue',
            dueAt: now.subtract(const Duration(days: 1)),
          ),
        );

        expect(repository.openTasks().map((t) => t.title), [
          'Overdue',
          'Tomorrow',
          'Someday',
        ]);
      },
    );

    test('a task with no due date sorts last even at P1', () async {
      // A someday item is not today's problem, whatever its priority.
      await repository.saveTask(
        repository.createTask(title: 'No date', priority: TaskPriority.p1),
      );
      await repository.saveTask(
        repository.createTask(
          title: 'Dated',
          priority: TaskPriority.p4,
          dueAt: now.add(const Duration(days: 5)),
        ),
      );

      expect(repository.openTasks().first.title, 'Dated');
    });

    test('overdueCount ignores completed tasks', () async {
      final task = repository.createTask(
        title: 'Late',
        dueAt: now.subtract(const Duration(days: 1)),
      );
      await repository.saveTask(task);
      expect(repository.overdueCount(now), 1);

      await repository.toggleTask(task);
      expect(repository.overdueCount(now), 0);
    });

    test('tasksDueOn matches by calendar day', () async {
      await repository.saveTask(
        repository.createTask(
          title: 'Today',
          dueAt: DateTime(2026, 3, 14, 23, 30),
        ),
      );
      expect(repository.tasksDueOn(DateTime(2026, 3, 14)), hasLength(1));
      expect(repository.tasksDueOn(DateTime(2026, 3, 15)), isEmpty);
    });

    test('a reminder is scheduled ahead of the due time', () async {
      await repository.saveTask(
        repository.createTask(
          title: 'Submit coursework',
          dueAt: now.add(const Duration(hours: 5)),
          reminderMinutesBefore: 30,
        ),
      );

      expect(env.notifications.scheduledOnce, hasLength(1));
      expect(
        env.notifications.scheduledOnce.single.at,
        now.add(const Duration(hours: 4, minutes: 30)),
      );
    });

    test('a task with no due date schedules nothing', () async {
      await repository.saveTask(repository.createTask(title: 'Someday'));
      expect(env.notifications.scheduledOnce, isEmpty);
    });

    test('completing a task cancels its reminder', () async {
      // Nagging about work the user already finished is the fastest way to
      // get notifications switched off entirely.
      final task = repository.createTask(
        title: 'Submit coursework',
        dueAt: now.add(const Duration(hours: 5)),
        reminderMinutesBefore: 30,
      );
      await repository.saveTask(task);

      await repository.toggleTask(task);

      expect(env.notifications.scheduledOnce, isEmpty);
      expect(env.notifications.cancelled, contains(task.notificationId));
    });

    test('re-opening a task restores its reminder', () async {
      final task = repository.createTask(
        title: 'Submit coursework',
        dueAt: now.add(const Duration(hours: 5)),
        reminderMinutesBefore: 30,
      );
      await repository.saveTask(task);
      final done = (await repository.toggleTask(task)).valueOrNull!;

      await repository.toggleTask(done);

      expect(env.notifications.scheduledOnce, hasLength(1));
    });

    test('deleting cancels the reminder and hides the task', () async {
      final task = repository.createTask(
        title: 'Submit coursework',
        dueAt: now.add(const Duration(hours: 5)),
        reminderMinutesBefore: 30,
      );
      await repository.saveTask(task);

      await repository.deleteTask(task.id);

      expect(repository.openTasks(), isEmpty);
      expect(env.notifications.scheduledOnce, isEmpty);
    });

    test(
      'rescheduleAllReminders rebuilds the schedule after a reboot',
      () async {
        await repository.saveTask(
          repository.createTask(
            title: 'Submit coursework',
            dueAt: now.add(const Duration(hours: 5)),
            reminderMinutesBefore: 30,
          ),
        );
        await env.notifications.cancelAll();

        await repository.rescheduleAllReminders();

        expect(env.notifications.scheduledOnce, hasLength(1));
      },
    );
  });

  group('events', () {
    CalendarEvent lunch() => repository.createEvent(
      title: 'Lunch',
      startAt: DateTime(2026, 3, 14, 12),
      endAt: DateTime(2026, 3, 14, 13),
    );

    test('an event needs a title and must end after it starts', () async {
      expect(
        (await repository.saveEvent(lunch().copyWith(title: ' ')))
            .failureOrNull,
        isA<ValidationFailure>(),
      );
      expect(
        (await repository.saveEvent(
          repository.createEvent(
            title: 'Backwards',
            startAt: DateTime(2026, 3, 14, 13),
            endAt: DateTime(2026, 3, 14, 12),
          ),
        )).failureOrNull,
        isA<ValidationFailure>().having(
          (f) => f.code,
          'code',
          'end_before_start',
        ),
      );
    });

    test('eventsOn returns a day in start order', () async {
      await repository.saveEvent(lunch());
      await repository.saveEvent(
        repository.createEvent(
          title: 'Standup',
          startAt: DateTime(2026, 3, 14, 9, 30),
          endAt: DateTime(2026, 3, 14, 9, 45),
        ),
      );

      expect(repository.eventsOn(DateTime(2026, 3, 14)).map((e) => e.title), [
        'Standup',
        'Lunch',
      ]);
      expect(repository.eventsOn(DateTime(2026, 3, 15)), isEmpty);
    });

    test('a Google-sourced event cannot be edited or deleted here', () async {
      // The mirror is a copy of the user's real calendar. Editing it locally
      // would silently diverge from the source of truth.
      google.remote = [
        CalendarEvent(
          id: 'g1',
          title: 'Lecture',
          startAt: DateTime.utc(2026, 3, 14, 10),
          endAt: DateTime.utc(2026, 3, 14, 11),
          source: EventSource.google,
          providerEventId: 'abc',
          updatedAt: DateTime.utc(2026, 3, 13),
        ),
      ];
      await repository.syncGoogle();

      final mirrored = repository.events.readOne('g1')!;
      expect(mirrored.isReadOnly, isTrue);
      expect(
        (await repository.saveEvent(mirrored)).failureOrNull,
        isA<ValidationFailure>().having(
          (f) => f.code,
          'code',
          'event_read_only',
        ),
      );
      expect(
        (await repository.deleteEvent('g1')).failureOrNull,
        isA<ValidationFailure>(),
      );
    });
  });

  group('Google Calendar', () {
    test('a sync mirrors the fetched events and records when it ran', () async {
      google.remote = [
        CalendarEvent(
          id: 'g1',
          title: 'Lecture',
          startAt: DateTime.utc(2026, 3, 14, 10),
          endAt: DateTime.utc(2026, 3, 14, 11),
          source: EventSource.google,
          updatedAt: DateTime.utc(2026, 3, 13),
        ),
      ];

      final result = await repository.syncGoogle();

      expect(result.valueOrNull, 1);
      expect(repository.eventsOn(DateTime(2026, 3, 14)), hasLength(1));
      expect(repository.lastGoogleSync, isNotNull);
    });

    test(
      'a failed sync leaves the mirror and the timestamp untouched',
      () async {
        google.failure = const NetworkFailure();

        final result = await repository.syncGoogle();

        expect(result.failureOrNull, isA<NetworkFailure>());
        expect(repository.lastGoogleSync, isNull);
      },
    );

    test('disconnecting removes the mirrored events', () async {
      // Keeping a copy of someone's meetings after they revoked access would
      // be indefensible.
      google.remote = [
        CalendarEvent(
          id: 'g1',
          title: 'Lecture',
          startAt: DateTime.utc(2026, 3, 14, 10),
          endAt: DateTime.utc(2026, 3, 14, 11),
          source: EventSource.google,
          updatedAt: DateTime.utc(2026, 3, 13),
        ),
      ];
      await repository.connectGoogle();
      await repository.syncGoogle();
      await repository.saveEvent(
        repository.createEvent(
          title: 'Mine',
          startAt: DateTime(2026, 3, 14, 18),
          endAt: DateTime(2026, 3, 14, 19),
        ),
      );

      await repository.disconnectGoogle();

      final remaining = repository.eventsOn(DateTime(2026, 3, 14));
      expect(remaining.map((e) => e.title), ['Mine']);
      expect(repository.lastGoogleSync, isNull);
      expect(await repository.isGoogleConnected, isFalse);
    });

    test(
      'an unconfigured build reports so rather than offering a dead button',
      () async {
        final unconfigured = CalendarRepository(
          store: env.store,
          outbox: Outbox(env.store),
          notifications: env.notifications,
          google: _FakeGoogleCalendar(configured: false),
          clock: () => now,
        );
        expect(unconfigured.isGoogleConfigured, isFalse);
      },
    );
  });
}
