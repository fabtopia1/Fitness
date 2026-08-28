import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:lifedna/core/engines/macro_calculator.dart';
import 'package:lifedna/core/engines/priority_engine.dart';
import 'package:lifedna/core/engines/recovery_engine.dart';
import 'package:lifedna/features/nutrition/data/in_memory_nutrition_repository.dart';
import 'package:lifedna/features/nutrition/domain/repositories/nutrition_repository.dart';
import 'package:lifedna/features/workout/data/in_memory_workout_repository.dart';
import 'package:lifedna/features/workout/domain/entities/workout.dart';
import 'package:lifedna/features/workout/domain/repositories/workout_repository.dart';
import 'package:lifedna/shared/enums/enums.dart';
import 'package:lifedna/shared/value_objects/macros.dart';

/// The user's profile and derived targets.
///
/// In production this streams from `users/{uid}`; here it is seeded with the
/// reference persona so every screen has real numbers to render.
class UserProfile {
  const UserProfile({
    required this.displayName,
    required this.weightKg,
    required this.heightCm,
    required this.age,
    required this.sex,
    required this.activityLevel,
    required this.goalMode,
    required this.trainingDaysPerWeek,
    required this.leanMassKg,
    required this.bodyFatPct,
    required this.startWeightKg,
    required this.targetWeightKg,
    required this.gymWindowStart,
    required this.bedtimeHour,
    required this.hasHealthSource,
  });

  final String displayName;
  final double weightKg;
  final double heightCm;
  final int age;
  final Sex sex;
  final ActivityLevel activityLevel;
  final GoalMode goalMode;
  final int trainingDaysPerWeek;
  final double leanMassKg;
  final double bodyFatPct;
  final double startWeightKg;
  final double targetWeightKg;
  final TimeOfDay gymWindowStart;
  final int bedtimeHour;
  final bool hasHealthSource;

  static const reference = UserProfile(
    displayName: 'Youssef',
    weightKg: 89.4,
    heightCm: 174.5,
    age: 21,
    sex: Sex.male,
    activityLevel: ActivityLevel.moderate,
    goalMode: GoalMode.cut,
    trainingDaysPerWeek: 6,
    leanMassKg: 61.9,
    bodyFatPct: 30.8,
    startWeightKg: 90.1,
    targetWeightKg: 84,
    gymWindowStart: TimeOfDay(hour: 18, minute: 0),
    bedtimeHour: 23,
    hasHealthSource: true,
  );

  MacroInput get macroInput => MacroInput(
        weightKg: weightKg,
        heightCm: heightCm,
        age: age,
        sex: sex,
        activityLevel: activityLevel,
        goalMode: goalMode,
        trainingDaysPerWeek: trainingDaysPerWeek,
        leanMassKg: leanMassKg,
      );

  /// Progress toward the goal, 0–1.
  double get goalProgress {
    final total = startWeightKg - targetWeightKg;
    if (total <= 0) return 0;
    return ((startWeightKg - weightKg) / total).clamp(0.0, 1.0);
  }
}

final userProfileProvider = Provider<UserProfile>(
  (ref) => UserProfile.reference,
);

/// The computed macro targets. Derived, never stored — so a profile change is
/// reflected everywhere immediately.
final macroResultProvider = Provider<MacroResult>((ref) {
  final profile = ref.watch(userProfileProvider);
  return MacroCalculator.compute(profile.macroInput);
});

/// Targets for a specific day type.
final macroTargetsProvider = Provider.family<MacroTargets, DayType>(
  (ref, dayType) => ref.watch(macroResultProvider).forDayType(dayType),
);

/// "Now", overridable in tests and in widget previews.
final clockProvider = Provider<DateTime Function()>((ref) => DateTime.now);

final todayProvider = Provider<DateTime>((ref) {
  final now = ref.watch(clockProvider)();
  return DateTime(now.year, now.month, now.day);
});

// ----------------------------------------------------------- repositories --

final nutritionRepositoryProvider = Provider<NutritionRepository>((ref) {
  final repo = InMemoryNutritionRepository(clock: ref.watch(clockProvider));
  ref.onDispose(repo.dispose);
  return repo;
});

final workoutRepositoryProvider = Provider<WorkoutRepository>((ref) {
  final repo = InMemoryWorkoutRepository(clock: ref.watch(clockProvider));
  ref.onDispose(repo.dispose);
  return repo;
});

// ---------------------------------------------------------------- streams --

final dailyNutritionProvider = StreamProvider<DailyNutrition>((ref) {
  final repo = ref.watch(nutritionRepositoryProvider);
  return repo.watchDay(ref.watch(todayProvider));
});

final activeSessionProvider = StreamProvider<WorkoutSession?>((ref) {
  return ref.watch(workoutRepositoryProvider).watchActiveSession();
});

final todaysPlanProvider =
    Provider<({String label, WorkoutTemplate? template, bool optional})>((ref) {
  return ref.watch(workoutRepositoryProvider).todaysPlan(
        ref.watch(todayProvider),
      );
});

/// Yesterday's recovery, computed from the same engine the server runs.
///
/// The client mirror exists so the score is available instantly and offline;
/// docs/12 §1 explains why the two implementations must stay in lockstep.
final recoveryProvider = Provider<RecoveryResult>((ref) {
  final plan = ref.watch(todaysPlanProvider);
  return RecoveryEngine.compute(
    sleep: const SleepInput(
      totalMinutes: 431,
      timeInBedMinutes: 468,
      deepMinutes: 78,
      remMinutes: 96,
      bedtimeStdDevMinutes: 24,
      wakeStdDevMinutes: 19,
      nightsOfHistory: 14,
    ),
    training: const TrainingInput(
      acwr: 1.073,
      yesterdayLoad: 584,
      meanDailyLoad28d: 334,
      yesterdaySessionRpe: 8,
    ),
    activity: const ActivityInput(
      steps: 8432,
      stepGoal: 12000,
      activeMinutes: 62,
      trainedYesterday: true,
    ),
    physiology: const PhysiologyInput(
      restingHrBpm: 58,
      baselineRestingHrBpm: 59,
      hrvMs: 42,
      baselineHrvMs: 40.8,
    ),
    plannedSession: plan.template == null
        ? null
        : PlannedSession(
            rpe: 8,
            durationMinutes: plan.template!.estimatedMinutes,
          ),
  );
});

/// The composed dashboard state.
///
/// This is the single composition point described in docs/02 §4.3: one object
/// assembled from every domain, so no card fetches independently and the
/// Next Action can reason across all of them at once.
final dayStateProvider = Provider<DayState?>((ref) {
  final nutritionAsync = ref.watch(dailyNutritionProvider);
  final nutrition = nutritionAsync.valueOrNull;
  if (nutrition == null) return null;

  final profile = ref.watch(userProfileProvider);
  final now = ref.watch(clockProvider)();
  final targets = ref.watch(macroTargetsProvider(nutrition.dayType));
  final plan = ref.watch(todaysPlanProvider);
  final recovery = ref.watch(recoveryProvider);
  final activeSession = ref.watch(activeSessionProvider).valueOrNull;
  final macros = ref.watch(macroResultProvider);

  final workoutStatus = switch (activeSession?.status) {
    SessionStatus.inProgress => WorkoutStatus.inProgress,
    _ => plan.template == null
        ? WorkoutStatus.restDay
        : WorkoutStatus.scheduled,
  };

  final workoutAt = DateTime(
    now.year,
    now.month,
    now.day,
    profile.gymWindowStart.hour,
    profile.gymWindowStart.minute,
  );

  return DayState(
    now: now,
    dayType: nutrition.dayType,
    consumed: nutrition.totals,
    targets: targets,
    waterMl: nutrition.waterMl,
    waterTargetMl: macros.waterMl,
    mealSlotsLogged: nutrition.loggedSlots,
    plannedMealSlots: _plannedMeals(now, targets),
    workoutStatus: workoutStatus,
    workoutStartsAt: plan.template == null ? null : workoutAt,
    workoutName: plan.template?.name ?? plan.label,
    workoutSetCount: plan.template?.totalWorkingSets ?? 0,
    supplementsTaken: 4,
    supplementsScheduled: 5,
    nextSupplementAt: DateTime(now.year, now.month, now.day, 22, 30),
    nextSupplementName: 'Magnesium glycinate',
    recoveryScore: recovery.recoveryScore,
    recoveryAction: recovery.action,
    nextEventTitle: null,
    nextEventAt: null,
    overdueTaskCount: 0,
    topTaskTitle: null,
    topTaskDueAt: null,
    topInsightHeadline: null,
    topInsightId: null,
    bedtimeAt: DateTime(now.year, now.month, now.day, profile.bedtimeHour),
    hasHealthSource: profile.hasHealthSource,
  );
});

/// The Next Action, or the all-clear card when nothing is outstanding.
final nextActionProvider = Provider<NextAction?>((ref) {
  final state = ref.watch(dayStateProvider);
  if (state == null) return null;
  return PriorityEngine.top(state) ?? PriorityEngine.allClear(state);
});

/// Today's planned meal slots, sized proportionally against the day's targets.
List<({MealSlot slot, DateTime at, String name, double kcal, double proteinG})>
    _plannedMeals(DateTime now, MacroTargets targets) {
  const plan = <({MealSlot slot, String name, double share})>[
    (slot: MealSlot.breakfast, name: 'Eggs · foul · baladi bread', share: 0.22),
    (slot: MealSlot.lunch, name: 'Chicken · rice · salad', share: 0.28),
    (slot: MealSlot.preWorkout, name: 'Cottage cheese · fruit', share: 0.14),
    (slot: MealSlot.postWorkout, name: 'Beef or fish · rice · veg', share: 0.24),
    (slot: MealSlot.beforeBed, name: 'Greek yogurt · nuts', share: 0.12),
  ];

  return [
    for (final p in plan)
      (
        slot: p.slot,
        at: DateTime(
          now.year,
          now.month,
          now.day,
          p.slot.defaultHour,
          p.slot.defaultMinute,
        ),
        name: p.name,
        kcal: targets.kcal * p.share,
        proteinG: targets.proteinG * p.share,
      ),
  ];
}
