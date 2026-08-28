import 'package:flutter_test/flutter_test.dart';
import 'package:lifedna/core/sync/outbox.dart';
import 'package:lifedna/features/reminders/data/reminder_repository.dart';

import '../../../support/test_harness.dart';

void main() {
  late TestEnvironment env;
  late ReminderRepository repository;

  final now = DateTime(2026, 3, 14, 9);

  setUp(() async {
    env = await TestEnvironment.create(clock: () => now);
    repository = ReminderRepository(
      store: env.store,
      outbox: Outbox(env.store),
      notifications: env.notifications,
      clock: () => now,
    );
  });
  tearDown(() async => env.dispose());

  test('a draft starts at a sensible hour with an empty title', () {
    final draft = repository.draft();
    expect(draft.title, isEmpty);
    expect(draft.hour, 8);
    expect(draft.enabled, isTrue);
    expect(draft.timeLabel, '08:00');
  });

  test('saving schedules the notification alongside the record', () async {
    // The record and its schedule are written together. Any path that stores
    // one without the other is the "app silently stopped reminding me" bug.
    await repository.save(
      repository.draft().copyWith(title: 'Weigh in', hour: 7, minute: 15),
    );

    expect(repository.readAll(), hasLength(1));
    final scheduled = env.notifications.scheduledDaily.single;
    expect(scheduled.title, 'Weigh in');
    expect(scheduled.hour, 7);
    expect(scheduled.minute, 15);
  });

  test('editing replaces the schedule rather than stacking a second alarm',
      () async {
    final reminder = repository.draft().copyWith(title: 'Weigh in', hour: 7);
    await repository.save(reminder);
    await repository.save(reminder.copyWith(hour: 9));

    expect(env.notifications.scheduledDaily, hasLength(1));
    expect(env.notifications.scheduledDaily.single.hour, 9);
  });

  test('disabling cancels the notification but keeps the record', () async {
    final reminder = repository.draft().copyWith(title: 'Stretch');
    await repository.save(reminder);

    await repository.setEnabled(reminder, on: false);

    expect(env.notifications.scheduledDaily, isEmpty);
    expect(repository.readAll(), hasLength(1));
    expect(repository.readAll().single.enabled, isFalse);
  });

  test('re-enabling schedules it again', () async {
    final reminder = repository.draft().copyWith(title: 'Stretch');
    await repository.save(reminder);
    await repository.setEnabled(reminder, on: false);

    await repository.setEnabled(
      repository.readAll().single,
      on: true,
    );

    expect(env.notifications.scheduledDaily, hasLength(1));
  });

  test('deleting removes the record and cancels the notification', () async {
    final reminder = repository.draft().copyWith(title: 'Stretch');
    await repository.save(reminder);

    await repository.delete(reminder.id);

    expect(repository.readAll(), isEmpty);
    expect(env.notifications.scheduledDaily, isEmpty);
    expect(env.notifications.cancelled, contains(reminder.notificationId));
  });

  test('reminders list in time order, then alphabetically', () async {
    await repository.save(
      repository.draft().copyWith(title: 'Evening', hour: 21),
    );
    await repository.save(
      repository.draft().copyWith(title: 'Beta', hour: 7),
    );
    await repository.save(
      repository.draft().copyWith(title: 'Alpha', hour: 7),
    );

    expect(
      repository.readAll().map((r) => r.title),
      ['Alpha', 'Beta', 'Evening'],
    );
  });

  test('rescheduleAll rebuilds only the enabled reminders', () async {
    await repository.save(
      repository.draft().copyWith(title: 'On', hour: 7),
    );
    final off = repository.draft().copyWith(title: 'Off', hour: 8);
    await repository.save(off);
    await repository.setEnabled(off, on: false);

    await env.notifications.cancelAll();
    await repository.rescheduleAll();

    expect(env.notifications.scheduledDaily.map((e) => e.title), ['On']);
  });

  test('the master switch stops a new reminder scheduling', () async {
    await env.notifications.setRemindersEnabled(enabled: false);

    await repository.save(
      repository.draft().copyWith(title: 'Weigh in'),
    );

    expect(repository.readAll(), hasLength(1));
    expect(env.notifications.scheduledDaily, isEmpty);
  });

  test('a reminder survives a JSON round-trip', () async {
    await repository.save(
      repository.draft().copyWith(
            title: 'Weigh in',
            note: 'Before breakfast',
            hour: 7,
            minute: 5,
          ),
    );

    final restored = repository.readAll().single;
    expect(restored.title, 'Weigh in');
    expect(restored.note, 'Before breakfast');
    expect(restored.timeLabel, '07:05');
  });
}
