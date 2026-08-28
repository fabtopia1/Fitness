import 'package:flutter_test/flutter_test.dart';
import 'package:lifedna/core/error/failure.dart';
import 'package:lifedna/core/sync/outbox.dart';
import 'package:lifedna/features/supplements/data/supplement_repository.dart';
import 'package:lifedna/features/supplements/domain/supplement_entities.dart';

import '../../../support/test_harness.dart';

void main() {
  late TestEnvironment env;
  late SupplementRepository repository;

  // A Saturday, so weekday scheduling has something to exclude.
  final now = DateTime(2026, 3, 14, 9);

  setUp(() async {
    env = await TestEnvironment.create();
    repository = SupplementRepository(
      store: env.store,
      outbox: Outbox(env.store),
      notifications: env.notifications,
      clock: () => now,
    );
  });
  tearDown(() async => env.dispose());

  Supplement creatine({
    bool reminderEnabled = true,
    SupplementFrequency frequency = SupplementFrequency.daily,
    List<int> weekdays = const [1, 2, 3, 4, 5, 6, 7],
  }) => repository.create(
    name: 'Creatine',
    dose: 5,
    unit: 'g',
    frequency: frequency,
    weekdays: weekdays,
    reminderHour: 8,
    reminderMinute: 30,
    reminderEnabled: reminderEnabled,
  );

  group('validation', () {
    test('a nameless supplement is refused', () async {
      final result = await repository.save(creatine().copyWith(name: '   '));
      expect(result.failureOrNull, isA<ValidationFailure>());
      expect(repository.readSupplements(), isEmpty);
    });

    test('a non-positive dose is refused', () async {
      final result = await repository.save(creatine().copyWith(dose: 0));
      expect(
        result.failureOrNull,
        isA<ValidationFailure>().having(
          (f) => f.code,
          'code',
          'quantity_must_be_positive',
        ),
      );
    });
  });

  group('reminders', () {
    test('saving schedules a daily reminder at the chosen time', () async {
      await repository.save(creatine());

      expect(env.notifications.scheduledDaily, hasLength(1));
      final scheduled = env.notifications.scheduledDaily.single;
      expect(scheduled.hour, 8);
      expect(scheduled.minute, 30);
      expect(scheduled.title, contains('Creatine'));
    });

    test('rescheduling replaces rather than stacks', () async {
      // The notification id is derived from the document id precisely so that
      // saving twice cannot produce two 08:30 alarms.
      final supplement = creatine();
      await repository.save(supplement);
      await repository.save(supplement.copyWith(reminderHour: 7));

      expect(env.notifications.scheduledDaily, hasLength(1));
      expect(env.notifications.scheduledDaily.single.hour, 7);
    });

    test('a supplement with reminders off schedules nothing', () async {
      await repository.save(creatine(reminderEnabled: false));
      expect(env.notifications.scheduledDaily, isEmpty);
    });

    test('an inactive supplement schedules nothing', () async {
      await repository.save(creatine().copyWith(active: false));
      expect(env.notifications.scheduledDaily, isEmpty);
    });

    test('deleting cancels the reminder', () async {
      final supplement = creatine();
      await repository.save(supplement);
      await repository.delete(supplement.id);

      expect(env.notifications.cancelled, contains(supplement.notificationId));
      expect(env.notifications.scheduledDaily, isEmpty);
    });

    test('rescheduleAll rebuilds the schedule after a reboot', () async {
      await repository.save(creatine());
      await env.notifications.cancelAll();
      expect(env.notifications.scheduledDaily, isEmpty);

      await repository.rescheduleAll();
      expect(env.notifications.scheduledDaily, hasLength(1));
    });

    test('the master switch stops a new reminder slipping through', () async {
      await env.notifications.setRemindersEnabled(enabled: false);
      await repository.save(creatine());
      expect(env.notifications.scheduledDaily, isEmpty);
    });
  });

  group('logging a dose', () {
    test('is idempotent for a given supplement and day', () async {
      // Tapping "taken" in the app after acting on the notification must not
      // record a second dose.
      final supplement = creatine();
      await repository.save(supplement);

      await repository.logDose(supplement);
      await repository.logDose(supplement);

      expect(repository.logs.readAll(), hasLength(1));
      expect(
        repository.logs.readAll().single.id,
        SupplementLog.idFor(supplement.id, '2026-03-14'),
      );
    });

    test('a dose on another day is a separate record', () async {
      final supplement = creatine();
      await repository.save(supplement);

      await repository.logDose(supplement);
      await repository.logDose(supplement, at: DateTime(2026, 3, 15, 9));

      expect(repository.logs.readAll(), hasLength(2));
    });

    test('undo removes the dose for that day', () async {
      final supplement = creatine();
      await repository.save(supplement);
      await repository.logDose(supplement);

      await repository.undoDose(supplement.id);

      expect(repository.logs.readAll(), isEmpty);
    });
  });

  group('the daily schedule', () {
    test(
      'reports what is due and what has been taken, ordered by time',
      () async {
        final morning = creatine();
        final evening = repository.create(
          name: 'Magnesium',
          dose: 300,
          unit: 'mg',
          reminderHour: 22,
        );
        await repository.save(morning);
        await repository.save(evening);
        await repository.logDose(morning);

        final schedule = repository.scheduleFor(now, isTrainingDay: false);

        expect(schedule.map((e) => e.supplement.name), [
          'Creatine',
          'Magnesium',
        ]);
        expect(schedule.first.taken, isTrue);
        expect(schedule.last.taken, isFalse);
      },
    );

    test(
      'a weekday supplement is absent on a day it is not scheduled',
      () async {
        // 14 March 2026 is a Saturday (weekday 6).
        await repository.save(
          creatine(
            frequency: SupplementFrequency.weekdays,
            weekdays: const [1, 2, 3, 4, 5],
          ),
        );

        expect(repository.scheduleFor(now, isTrainingDay: false), isEmpty);
        expect(
          repository.scheduleFor(DateTime(2026, 3, 16), isTrainingDay: false),
          hasLength(1),
        );
      },
    );

    test(
      'a training-day supplement follows the caller, not the calendar',
      () async {
        await repository.save(
          creatine(frequency: SupplementFrequency.trainingDays),
        );

        expect(repository.scheduleFor(now, isTrainingDay: false), isEmpty);
        expect(repository.scheduleFor(now, isTrainingDay: true), hasLength(1));
      },
    );
  });

  group('compliance', () {
    test(
      'counts scheduled doses from each schedule, not one per day',
      () async {
        // A training-days-only supplement must not be marked non-compliant for
        // the rest days it was never due on.
        await repository.save(
          creatine(frequency: SupplementFrequency.trainingDays),
        );

        final compliance = repository.compliance(
          days: 7,
          now: now,
          isTrainingDay: (day) => day.weekday <= 3,
        );

        expect(compliance.scheduled, 3);
        expect(compliance.taken, 0);
        expect(compliance.percent, 0);
      },
    );

    test('a taken dose raises the percentage', () async {
      final supplement = creatine();
      await repository.save(supplement);
      await repository.logDose(supplement);

      final compliance = repository.compliance(days: 2, now: now);
      expect(compliance.scheduled, 2);
      expect(compliance.taken, 1);
      expect(compliance.percent, 50);
    });

    test('an empty stack reports zero rather than dividing by zero', () {
      expect(repository.compliance(days: 7, now: now).percent, 0);
    });
  });

  test('the starter stack seeds once and is not duplicated', () async {
    await repository.seedStarterStack();
    final seeded = repository.readSupplements().length;
    expect(seeded, greaterThan(0));

    await repository.seedStarterStack();
    expect(repository.readSupplements(), hasLength(seeded));
  });
}
