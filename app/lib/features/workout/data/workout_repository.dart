import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:lifedna/core/data/synced_collection.dart';
import 'package:lifedna/core/data/synced_entity.dart';
import 'package:lifedna/core/engines/e1rm_calculator.dart';
import 'package:lifedna/core/error/failure.dart';
import 'package:lifedna/core/result/result.dart';
import 'package:lifedna/core/storage/hive_store.dart';
import 'package:lifedna/core/sync/outbox.dart';
import 'package:lifedna/features/workout/domain/workout_entities.dart';
import 'package:lifedna/shared/enums/enums.dart';
import 'package:uuid/uuid.dart';

class WorkoutRepository {
  WorkoutRepository({
    required HiveStore store,
    required Outbox outbox,
    FirebaseFirestore? firestore,
    String? uid,
    Uuid uuid = const Uuid(),
    DateTime Function()? clock,
  })  : _uuid = uuid,
        _clock = clock ?? DateTime.now,
        exercises = SyncedCollection<Exercise>(
          store: store,
          outbox: outbox,
          boxName: HiveStore.boxExercises,
          collection: 'exercises',
          fromJson: Exercise.fromJson,
          firestore: firestore,
          uid: uid,
        ),
        workouts = SyncedCollection<Workout>(
          store: store,
          outbox: outbox,
          boxName: HiveStore.boxWorkouts,
          collection: 'workouts',
          fromJson: Workout.fromJson,
          firestore: firestore,
          uid: uid,
        ),
        sessions = SyncedCollection<WorkoutSession>(
          store: store,
          outbox: outbox,
          boxName: HiveStore.boxWorkoutSessions,
          collection: 'workout_sessions',
          fromJson: WorkoutSession.fromJson,
          firestore: firestore,
          uid: uid,
        );

  final Uuid _uuid;
  final DateTime Function() _clock;

  final SyncedCollection<Exercise> exercises;
  final SyncedCollection<Workout> workouts;
  final SyncedCollection<WorkoutSession> sessions;

  // -------------------------------------------------------------- exercises --

  Stream<List<Exercise>> watchExercises() => exercises.watchAll();

  List<Exercise> searchExercises(String query, {MuscleGroup? muscle}) {
    final q = query.trim().toLowerCase();
    final all = exercises.readAll()
      ..sort((a, b) => a.name.compareTo(b.name));
    return all
        .where((e) =>
            (muscle == null || e.muscleGroup == muscle) &&
            (q.isEmpty || e.name.toLowerCase().contains(q)))
        .toList();
  }

  Map<String, Exercise> get exerciseIndex => {
        for (final e in exercises.readAll()) e.id: e,
      };

  Exercise createExercise({
    required String name,
    required MuscleGroup muscleGroup,
    required Equipment equipment,
    bool isCompound = true,
    int restSeconds = 120,
    double incrementKg = 2.5,
  }) =>
      Exercise(
        id: _uuid.v4(),
        name: name.trim(),
        muscleGroup: muscleGroup,
        equipment: equipment,
        isCompound: isCompound,
        defaultRestSeconds: restSeconds,
        incrementKg: incrementKg,
        isCustom: true,
        updatedAt: _clock().toUtc(),
      );

  Future<Result<Exercise>> saveExercise(Exercise exercise) {
    if (exercise.name.trim().isEmpty) {
      return Future.value(const Err(ValidationFailure('required', field: 'name')));
    }
    return exercises.put(exercise);
  }

  // --------------------------------------------------------------- programs --

  Stream<List<Workout>> watchWorkouts() => workouts.watchAll();
  List<Workout> readWorkouts() => workouts.readAll();
  Workout? workoutById(String id) => workouts.readOne(id);

  Future<Result<Workout>> saveWorkout(Workout workout) {
    if (workout.name.trim().isEmpty) {
      return Future.value(const Err(ValidationFailure('required', field: 'name')));
    }
    if (workout.exercises.isEmpty) {
      return Future.value(const Err(ValidationFailure('no_exercises')));
    }
    return workouts.put(workout);
  }

  Future<Result<void>> deleteWorkout(String id) => workouts.remove(
        id,
        tombstone: (w) => w.copyWith(deletedAt: _clock().toUtc()),
      );

  // --------------------------------------------------------------- sessions --

  Stream<List<WorkoutSession>> watchSessions() => sessions.watchAll();

  List<WorkoutSession> history({int limit = 50}) {
    final done = sessions
        .readAll()
        .where((s) => s.status == SessionStatus.completed)
        .toList()
      ..sort((a, b) => b.startedAt.compareTo(a.startedAt));
    return done.take(limit).toList();
  }

  /// The single in-progress session, if any.
  ///
  /// Surviving process death is the whole point: the session is a normal Hive
  /// record from the first set onward, so a crash mid-workout loses nothing.
  WorkoutSession? activeSession() {
    for (final session in sessions.readAll()) {
      if (session.isActive) return session;
    }
    return null;
  }

  Stream<WorkoutSession?> watchActiveSession() =>
      sessions.watchAll().map((all) {
        for (final session in all) {
          if (session.isActive) return session;
        }
        return null;
      });

  Future<Result<WorkoutSession>> startSession({Workout? workout}) async {
    if (activeSession() != null) {
      return const Err(ValidationFailure('session_already_active'));
    }
    final now = _clock();
    final session = WorkoutSession(
      id: _uuid.v4(),
      workoutId: workout?.id,
      name: workout?.name ?? 'Freeform workout',
      plan: workout?.exercises ?? const [],
      startedAt: now.toUtc(),
      localDate: Json.localDate(now),
      updatedAt: now.toUtc(),
    );
    return sessions.put(session);
  }

  /// Appends a set and returns the updated session.
  ///
  /// PR detection runs here, against history, so the record is attached to the
  /// set at the moment it happens rather than recomputed later from a
  /// different code path that might disagree.
  Future<Result<WorkoutSession>> addSet({
    required WorkoutSession session,
    required String exerciseId,
    required String exerciseName,
    required double weightKg,
    required int reps,
    int? rpe,
    bool isWarmup = false,
  }) async {
    if (weightKg < 0 || weightKg > 500) {
      return const Err(ValidationFailure('weight_out_of_range'));
    }
    if (reps < 1 || reps > 100) {
      return const Err(ValidationFailure('reps_out_of_range'));
    }

    final records = isWarmup
        ? const <PersonalRecord>[]
        : PrDetector.forSet(
            exerciseId: exerciseId,
            weightKg: weightKg,
            reps: reps,
            isWarmup: false,
            bests: bestsFor(exerciseId),
          );

    final set = WorkoutSet(
      id: _uuid.v4(),
      exerciseId: exerciseId,
      exerciseName: exerciseName,
      weightKg: weightKg,
      reps: reps,
      rpe: rpe,
      isWarmup: isWarmup,
      performedAt: _clock().toUtc(),
      prLabels: [for (final r in records) r.headline],
    );

    final updated = session.copyWith(sets: [...session.sets, set]);
    return sessions.put(updated);
  }

  Future<Result<WorkoutSession>> removeSet({
    required WorkoutSession session,
    required String setId,
  }) {
    final remaining = session.sets.where((s) => s.id != setId).toList();
    return sessions.put(session.copyWith(sets: remaining));
  }

  Future<Result<WorkoutSession>> finishSession(
    WorkoutSession session, {
    String? notes,
  }) async {
    final finished = session.copyWith(
      finishedAt: _clock().toUtc(),
      status: SessionStatus.completed,
      notes: notes,
    );
    final result = await sessions.put(finished);

    final workoutId = session.workoutId;
    if (result.isOk && workoutId != null) {
      final workout = workouts.readOne(workoutId);
      if (workout != null) {
        await workouts.put(
          workout.copyWith(
            useCount: workout.useCount + 1,
            lastPerformedAt: _clock().toUtc(),
          ),
        );
      }
    }
    return result;
  }

  Future<Result<void>> discardSession(WorkoutSession session) => sessions.remove(
        session.id,
        tombstone: (s) => s.copyWith(deletedAt: _clock().toUtc()),
      );

  // -------------------------------------------------------------- PR / prefill

  /// Every completed set for an exercise, newest first.
  List<WorkoutSet> setsFor(String exerciseId) {
    final out = <WorkoutSet>[];
    for (final session in sessions.readAll()) {
      if (session.status != SessionStatus.completed) continue;
      for (final set in session.sets) {
        if (set.exerciseId == exerciseId && !set.isWarmup) out.add(set);
      }
    }
    out.sort((a, b) => b.performedAt.compareTo(a.performedAt));
    return out;
  }

  LastPerformance? lastPerformance(String exerciseId) {
    final sets = setsFor(exerciseId);
    if (sets.isEmpty) return null;
    final latest = sets.first;
    return LastPerformance(
      weightKg: latest.weightKg,
      reps: latest.reps,
      rpe: latest.rpe,
      performedAt: latest.performedAt,
    );
  }

  ExerciseBests bestsFor(String exerciseId) {
    double? heaviest;
    double? bestE1rm;
    final repsAtWeight = <double, int>{};

    for (final set in setsFor(exerciseId)) {
      if (heaviest == null || set.weightKg > heaviest) heaviest = set.weightKg;
      final e1rm = set.e1rm;
      if (bestE1rm == null || e1rm > bestE1rm) bestE1rm = e1rm;
      final prior = repsAtWeight[set.weightKg];
      if (prior == null || set.reps > prior) repsAtWeight[set.weightKg] = set.reps;
    }

    return ExerciseBests(
      heaviestWeightKg: heaviest,
      bestE1rm: bestE1rm == null ? null : (bestE1rm * 10).roundToDouble() / 10,
      repsAtWeight: repsAtWeight,
    );
  }

  /// All personal records, newest first. Derived from sessions on demand.
  List<PersonalRecordEntry> personalRecords() {
    final byExercise = <String, PersonalRecordEntry>{};

    final completed = sessions
        .readAll()
        .where((s) => s.status == SessionStatus.completed)
        .toList()
      ..sort((a, b) => a.startedAt.compareTo(b.startedAt));

    for (final session in completed) {
      for (final set in session.sets) {
        if (set.isWarmup || set.weightKg <= 0 || set.reps <= 0) continue;
        final e1rm = (set.e1rm * 10).roundToDouble() / 10;
        final existing = byExercise[set.exerciseId];
        if (existing == null || e1rm > existing.value) {
          byExercise[set.exerciseId] = PersonalRecordEntry(
            exerciseId: set.exerciseId,
            exerciseName: set.exerciseName,
            type: PrType.bestE1rm,
            value: e1rm,
            weightKg: set.weightKg,
            reps: set.reps,
            achievedAt: set.performedAt,
            sessionId: session.id,
          );
        }
      }
    }

    return byExercise.values.toList()
      ..sort((a, b) => b.achievedAt.compareTo(a.achievedAt));
  }

  /// Total volume per ISO week, oldest first. Used by the history chart.
  List<({DateTime weekStart, double volumeKg, int sessions})> weeklyVolume({
    int weeks = 8,
    DateTime? now,
  }) {
    final end = now ?? _clock();
    final buckets = <String, ({DateTime start, double volume, int count})>{};

    for (var i = 0; i < weeks; i++) {
      final day = end.subtract(Duration(days: 7 * i));
      final start = _weekStart(day);
      buckets[Json.localDate(start)] =
          (start: start, volume: 0, count: 0);
    }

    for (final session in history(limit: 500)) {
      final start = _weekStart(session.startedAt.toLocal());
      final key = Json.localDate(start);
      final bucket = buckets[key];
      if (bucket == null) continue;
      buckets[key] = (
        start: bucket.start,
        volume: bucket.volume + session.volumeKg,
        count: bucket.count + 1,
      );
    }

    final out = buckets.values
        .map((b) => (weekStart: b.start, volumeKg: b.volume, sessions: b.count))
        .toList()
      ..sort((a, b) => a.weekStart.compareTo(b.weekStart));
    return out;
  }

  static DateTime _weekStart(DateTime date) {
    final day = DateTime(date.year, date.month, date.day);
    return day.subtract(Duration(days: day.weekday - 1));
  }

  Future<Result<int>> pullAll() async {
    final results = await Future.wait([
      exercises.pull(),
      workouts.pull(),
      sessions.pull(),
    ]);
    var total = 0;
    for (final result in results) {
      if (result.isErr) return result;
      total += result.valueOrNull ?? 0;
    }
    return Ok(total);
  }
}
