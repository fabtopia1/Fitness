import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:lifedna/core/providers/providers.dart';
import 'package:lifedna/features/workout/domain/workout_entities.dart';

final exercisesProvider = StreamProvider<List<Exercise>>(
  (ref) => ref.watch(workoutRepositoryProvider).watchExercises(),
);

final workoutsProvider = StreamProvider<List<Workout>>(
  (ref) => ref.watch(workoutRepositoryProvider).watchWorkouts(),
);

final sessionsProvider = StreamProvider<List<WorkoutSession>>(
  (ref) => ref.watch(workoutRepositoryProvider).watchSessions(),
);

/// The in-progress session, if any. Watched by the shell so the resume bar is
/// available from every screen.
final activeSessionProvider = StreamProvider<WorkoutSession?>(
  (ref) => ref.watch(workoutRepositoryProvider).watchActiveSession(),
);

/// Completed sessions, newest first.
final workoutHistoryProvider = Provider<List<WorkoutSession>>((ref) {
  ref.watch(sessionsProvider);
  return ref.watch(workoutRepositoryProvider).history();
});

final personalRecordsProvider = Provider<List<PersonalRecordEntry>>((ref) {
  ref.watch(sessionsProvider);
  return ref.watch(workoutRepositoryProvider).personalRecords();
});

final weeklyVolumeProvider =
    Provider<List<({DateTime weekStart, double volumeKg, int sessions})>>((
      ref,
    ) {
      ref.watch(sessionsProvider);
      return ref.watch(workoutRepositoryProvider).weeklyVolume();
    });

/// Sessions completed in the current ISO week.
final sessionsThisWeekProvider = Provider<int>((ref) {
  final history = ref.watch(workoutHistoryProvider);
  final now = ref.watch(clockProvider)();
  final day = DateTime(now.year, now.month, now.day);
  final weekStart = day.subtract(Duration(days: day.weekday - 1));
  return history.where((s) => s.startedAt.toLocal().isAfter(weekStart)).length;
});

final trainedTodayProvider = Provider<bool>((ref) {
  final history = ref.watch(workoutHistoryProvider);
  final today = ref.watch(todayLocalDateProvider);
  return history.any((s) => s.localDate == today);
});
