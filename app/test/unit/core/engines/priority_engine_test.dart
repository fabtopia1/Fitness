import 'package:flutter_test/flutter_test.dart';
import 'package:lifedna/core/engines/priority_engine.dart';
import 'package:lifedna/shared/enums/enums.dart';
import 'package:lifedna/shared/value_objects/macros.dart';

/// [PriorityEngine] drives the single most important surface in the product.
///
/// The four reference strings from docs/01 §6.1 are a hard acceptance
/// criterion (backlog D-02): the engine must be able to produce each one from
/// its corresponding state.
void main() {
  const targets = MacroTargets(
    kcal: 2350,
    proteinG: 200,
    carbsG: 210,
    fatG: 70,
    proteinFloorG: 200,
  );

  DayState state({
    required DateTime now,
    Macros consumed = const Macros(),
    int waterMl = 3000,
    Set<MealSlot> logged = const {},
    List<({MealSlot slot, DateTime at, String name, double kcal, double proteinG})>
        planned = const [],
    WorkoutStatus workout = WorkoutStatus.restDay,
    DateTime? workoutAt,
    int? recovery,
    TrainingAction? recoveryAction,
    DateTime? eventAt,
    String? eventTitle,
    int overdue = 0,
    String? taskTitle,
    DateTime? taskDue,
    String? insight,
    String? insightId,
    DateTime? bedtime,
    bool hasHealth = true,
    DateTime? supplementAt,
    String? supplementName,
  }) =>
      DayState(
        now: now,
        dayType: DayType.rest,
        consumed: consumed,
        targets: targets,
        waterMl: waterMl,
        waterTargetMl: 3500,
        mealSlotsLogged: logged,
        plannedMealSlots: planned,
        workoutStatus: workout,
        workoutStartsAt: workoutAt,
        workoutName: 'PUSH — Chest · Shoulders · Triceps',
        workoutSetCount: 22,
        supplementsTaken: 4,
        supplementsScheduled: 5,
        nextSupplementAt: supplementAt,
        nextSupplementName: supplementName,
        recoveryScore: recovery,
        recoveryAction: recoveryAction,
        nextEventTitle: eventTitle,
        nextEventAt: eventAt,
        overdueTaskCount: overdue,
        topTaskTitle: taskTitle,
        topTaskDueAt: taskDue,
        topInsightHeadline: insight,
        topInsightId: insightId,
        bedtimeAt: bedtime ?? DateTime(2026, 8, 28, 23),
        hasHealthSource: hasHealth,
      );

  group('reference strings from docs/01 §6.1', () {
    test('"You are 32 g below your protein target"', () {
      final s = state(
        now: DateTime(2026, 8, 28, 21),
        consumed: const Macros(kcal: 2412, proteinG: 168, carbsG: 268, fatG: 66),
      );
      final top = PriorityEngine.top(s)!;
      expect(top.title, 'You are 32 g below your protein target');
      expect(top.actionLabel, 'Log protein');
      expect(top.domain, ActionDomain.nutrition);
      // Every action carries its evidence — the "Why?" sheet is not optional.
      expect(top.evidence, isNotEmpty);
      expect(
        top.evidence.map((e) => e.label),
        containsAll(<String>['Protein today', 'Protein floor', 'Remaining']),
      );
    });

    test('"Workout starts in 45 minutes"', () {
      final s = state(
        now: DateTime(2026, 8, 28, 17, 15),
        workout: WorkoutStatus.scheduled,
        workoutAt: DateTime(2026, 8, 28, 18),
        consumed: const Macros(proteinG: 200),
      );
      final top = PriorityEngine.top(s)!;
      expect(top.title, 'Workout starts in 45 minutes');
      expect(top.subtitle, contains('22 working sets'));
    });

    test('"Time for breakfast"', () {
      final s = state(
        now: DateTime(2026, 8, 28, 9, 5),
        consumed: const Macros(proteinG: 200),
        planned: [
          (
            slot: MealSlot.breakfast,
            at: DateTime(2026, 8, 28, 9),
            name: 'Eggs · foul · baladi bread',
            kcal: 520,
            proteinG: 34,
          ),
        ],
      );
      final top = PriorityEngine.top(s)!;
      expect(top.title, 'Time for breakfast');
      expect(top.subtitle, contains('520 kcal'));
      expect(top.subtitle, contains('34 g protein'));
      expect(top.deeplink, '/nutrition/log?slot=breakfast');
    });

    test('recovery score drives a scaled session', () {
      final s = state(
        now: DateTime(2026, 8, 28, 8),
        consumed: const Macros(proteinG: 200),
        recovery: 28,
        recoveryAction: TrainingAction.reduce,
        workout: WorkoutStatus.scheduled,
        workoutAt: DateTime(2026, 8, 28, 18),
      );
      final top = PriorityEngine.top(s)!;
      expect(top.title, contains('Recovery is low (28)'));
      expect(top.actionLabel, 'Apply reduced session');
      expect(top.domain, ActionDomain.recovery);
    });
  });

  group('priority ordering', () {
    test('an in-progress session outranks everything', () {
      final s = state(
        now: DateTime(2026, 8, 28, 19),
        workout: WorkoutStatus.inProgress,
        recovery: 20,
        recoveryAction: TrainingAction.rest,
        eventTitle: 'Standup',
        eventAt: DateTime(2026, 8, 28, 19, 5),
      );
      expect(PriorityEngine.top(s)!.id, 'session_in_progress');
    });

    test('an imminent meeting outranks a meal', () {
      final s = state(
        now: DateTime(2026, 8, 28, 13, 0),
        consumed: const Macros(proteinG: 200),
        eventTitle: 'Standup',
        eventAt: DateTime(2026, 8, 28, 13, 5),
        planned: [
          (
            slot: MealSlot.lunch,
            at: DateTime(2026, 8, 28, 13),
            name: 'Chicken · rice · salad',
            kcal: 712,
            proteinG: 70,
          ),
        ],
      );
      final top = PriorityEngine.top(s)!;
      expect(top.id, 'meeting_soon');
      expect(top.title, 'Standup in 5 minutes');
    });

    test('protein debt only becomes the headline as the day runs out', () {
      const consumed = Macros(proteinG: 168);

      final midday = PriorityEngine.rank(
        state(now: DateTime(2026, 8, 28, 12), consumed: consumed),
      ).firstWhere((a) => a.id == 'protein_debt');

      final evening = PriorityEngine.rank(
        state(now: DateTime(2026, 8, 28, 21), consumed: consumed),
      ).firstWhere((a) => a.id == 'protein_debt');

      expect(evening.priority, greaterThan(midday.priority));
    });

    test('candidates are returned highest-priority first', () {
      final ranked = PriorityEngine.rank(
        state(
          now: DateTime(2026, 8, 28, 21),
          consumed: const Macros(proteinG: 150),
          waterMl: 1000,
          insight: 'Sleep dropped 14 % this week',
          insightId: 'i1',
        ),
      );
      for (var i = 1; i < ranked.length; i++) {
        expect(
          ranked[i - 1].priority,
          greaterThanOrEqualTo(ranked[i].priority),
        );
      }
    });
  });

  group('suppression — the engine must know when to say nothing', () {
    test('a logged meal slot produces no meal action', () {
      final s = state(
        now: DateTime(2026, 8, 28, 9, 5),
        consumed: const Macros(proteinG: 200),
        logged: {MealSlot.breakfast},
        planned: [
          (
            slot: MealSlot.breakfast,
            at: DateTime(2026, 8, 28, 9),
            name: 'Eggs',
            kcal: 520,
            proteinG: 34,
          ),
        ],
      );
      expect(
        PriorityEngine.rank(s).where((a) => a.id.startsWith('meal_')),
        isEmpty,
      );
    });

    test('a long-past meal is dropped rather than nagged about', () {
      final s = state(
        now: DateTime(2026, 8, 28, 15),
        consumed: const Macros(proteinG: 200),
        planned: [
          (
            slot: MealSlot.breakfast,
            at: DateTime(2026, 8, 28, 9),
            name: 'Eggs',
            kcal: 520,
            proteinG: 34,
          ),
        ],
      );
      expect(
        PriorityEngine.rank(s).where((a) => a.id.startsWith('meal_')),
        isEmpty,
      );
    });

    test('hydration is not raised when it is too late to act on it', () {
      final s = state(
        now: DateTime(2026, 8, 28, 22, 45),
        consumed: const Macros(proteinG: 200),
        waterMl: 500,
        bedtime: DateTime(2026, 8, 28, 23),
      );
      expect(
        PriorityEngine.rank(s).where((a) => a.id == 'hydration_behind'),
        isEmpty,
      );
    });

    test('a met protein floor produces no protein action', () {
      final s = state(
        now: DateTime(2026, 8, 28, 21),
        consumed: const Macros(proteinG: 205),
      );
      expect(
        PriorityEngine.rank(s).where((a) => a.id == 'protein_debt'),
        isEmpty,
      );
    });

    test('a trivial protein gap is not worth interrupting for', () {
      final s = state(
        now: DateTime(2026, 8, 28, 21),
        consumed: const Macros(proteinG: 192),
      );
      expect(
        PriorityEngine.rank(s).where((a) => a.id == 'protein_debt'),
        isEmpty,
      );
    });

    test('low recovery is not raised once the session is done', () {
      final s = state(
        now: DateTime(2026, 8, 28, 20),
        consumed: const Macros(proteinG: 200),
        recovery: 25,
        recoveryAction: TrainingAction.rest,
        workout: WorkoutStatus.completed,
      );
      expect(
        PriorityEngine.rank(s).where((a) => a.domain == ActionDomain.recovery),
        isEmpty,
      );
    });

    test('a good recovery score produces no recovery action', () {
      final s = state(
        now: DateTime(2026, 8, 28, 8),
        consumed: const Macros(proteinG: 200),
        recovery: 88,
        recoveryAction: TrainingAction.proceed,
      );
      expect(
        PriorityEngine.rank(s).where((a) => a.domain == ActionDomain.recovery),
        isEmpty,
      );
    });
  });

  group('onboarding and empty states', () {
    test('a brand-new user is asked to connect a health source', () {
      final s = state(
        now: DateTime(2026, 8, 28, 8),
        consumed: const Macros(proteinG: 200),
        hasHealth: false,
        workout: WorkoutStatus.none,
      );
      expect(PriorityEngine.top(s)!.id, 'connect_health');
    });

    test('setup guidance does not interrupt a user already logging', () {
      final s = state(
        now: DateTime(2026, 8, 28, 10),
        consumed: const Macros(proteinG: 200),
        hasHealth: false,
        logged: {MealSlot.breakfast},
      );
      expect(
        PriorityEngine.rank(s).where((a) => a.id == 'connect_health'),
        isEmpty,
      );
    });

    test('a fully-handled day produces no candidates, and allClear covers it', () {
      final s = state(
        now: DateTime(2026, 8, 28, 20),
        consumed: const Macros(kcal: 2350, proteinG: 205, carbsG: 210, fatG: 70),
        waterMl: 3500,
        logged: {MealSlot.breakfast, MealSlot.lunch, MealSlot.postWorkout},
        workout: WorkoutStatus.completed,
        recovery: 88,
        recoveryAction: TrainingAction.proceed,
      );
      expect(PriorityEngine.rank(s), isEmpty);
      expect(PriorityEngine.top(s), isNull);

      final fallback = PriorityEngine.allClear(s);
      expect(fallback.title, 'You’re on track');
      expect(fallback.actionLabel, isNotEmpty);
    });
  });

  group('determinism', () {
    test('the same state always produces the same ranking', () {
      final s = state(
        now: DateTime(2026, 8, 28, 21),
        consumed: const Macros(proteinG: 168),
        waterMl: 1500,
        insight: 'Sleep dropped 14 % this week',
        insightId: 'i1',
        overdue: 2,
        taskTitle: 'Submit DS assignment',
      );
      final a = PriorityEngine.rank(s).map((x) => x.id).toList();
      final b = PriorityEngine.rank(s).map((x) => x.id).toList();
      expect(a, b);
    });

    test('every produced action has a non-empty title, label and deeplink', () {
      final s = state(
        now: DateTime(2026, 8, 28, 17, 15),
        consumed: const Macros(proteinG: 140),
        waterMl: 800,
        workout: WorkoutStatus.scheduled,
        workoutAt: DateTime(2026, 8, 28, 18),
        supplementAt: DateTime(2026, 8, 28, 17),
        supplementName: 'Creatine',
        insight: 'Ready for a PR on incline bench',
        insightId: 'i2',
        overdue: 1,
        taskTitle: 'Reply to supervisor',
      );
      final ranked = PriorityEngine.rank(s);
      expect(ranked, isNotEmpty);
      for (final a in ranked) {
        expect(a.title, isNotEmpty, reason: '${a.id} has no title');
        expect(a.actionLabel, isNotEmpty, reason: '${a.id} has no action');
        expect(a.deeplink, startsWith('/'), reason: '${a.id} has a bad link');
        expect(a.priority, inInclusiveRange(0, 100));
      }
    });
  });
}
