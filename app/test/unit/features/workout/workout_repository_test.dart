import 'package:flutter_test/flutter_test.dart';
import 'package:lifedna/core/engines/e1rm_calculator.dart';
import 'package:lifedna/core/error/failure.dart';
import 'package:lifedna/core/sync/outbox.dart';
import 'package:lifedna/features/workout/data/workout_repository.dart';
import 'package:lifedna/features/workout/domain/workout_entities.dart';
import 'package:lifedna/shared/enums/enums.dart';

import '../../../support/test_harness.dart';

void main() {
  late TestEnvironment env;
  late WorkoutRepository repository;

  var now = DateTime(2026, 3, 14, 18);

  setUp(() async {
    now = DateTime(2026, 3, 14, 18);
    env = await TestEnvironment.create();
    repository = WorkoutRepository(
      store: env.store,
      outbox: Outbox(env.store),
      clock: () => now,
    );
  });
  tearDown(() async => env.dispose());

  Exercise bench() => repository.createExercise(
        name: 'Bench press',
        muscleGroup: MuscleGroup.chest,
        equipment: Equipment.barbell,
      );

  /// Runs one complete session: start, log the sets, finish.
  Future<WorkoutSession> completeSession(
    List<({double weight, int reps})> sets, {
    required String exerciseId,
    Workout? workout,
  }) async {
    var session = (await repository.startSession(workout: workout)).valueOrNull!;
    for (final set in sets) {
      session = (await repository.addSet(
        session: session,
        exerciseId: exerciseId,
        exerciseName: 'Bench press',
        weightKg: set.weight,
        reps: set.reps,
      ))
          .valueOrNull!;
    }
    return (await repository.finishSession(session)).valueOrNull!;
  }

  group('exercises', () {
    test('an exercise needs a name', () async {
      final result = await repository.saveExercise(
        bench().copyWith(name: '  '),
      );
      expect(result.failureOrNull, isA<ValidationFailure>());
    });

    test('search filters by text and by muscle group', () async {
      await repository.saveExercise(bench());
      await repository.saveExercise(
        repository.createExercise(
          name: 'Back squat',
          muscleGroup: MuscleGroup.quads,
          equipment: Equipment.barbell,
        ),
      );

      expect(repository.searchExercises('squat'), hasLength(1));
      expect(
        repository.searchExercises('', muscle: MuscleGroup.chest),
        hasLength(1),
      );
      expect(repository.searchExercises(''), hasLength(2));
      expect(repository.exerciseIndex.keys, hasLength(2));
    });
  });

  group('workouts', () {
    test('a workout needs a name and at least one exercise', () async {
      final exercise = bench();
      final planned = WorkoutExercise(
        exerciseId: exercise.id,
        exerciseName: exercise.name,
        targetSets: 3,
        repMin: 5,
        repMax: 8,
        restSeconds: 150,
      );

      expect(
        (await repository.saveWorkout(
          Workout(id: 'a', name: '  ', exercises: [planned], updatedAt: now),
        ))
            .failureOrNull,
        isA<ValidationFailure>(),
      );
      expect(
        (await repository.saveWorkout(
          Workout(id: 'b', name: 'Empty', exercises: const [], updatedAt: now),
        ))
            .failureOrNull,
        isA<ValidationFailure>()
            .having((f) => f.code, 'code', 'no_exercises'),
      );
      expect(repository.readWorkouts(), isEmpty);
    });

    test('estimated duration accounts for rest as well as working time', () {
      final workout = Workout(
        id: 'w',
        name: 'Push',
        exercises: const [
          WorkoutExercise(
            exerciseId: 'e',
            exerciseName: 'Bench press',
            targetSets: 3,
            repMin: 5,
            repMax: 8,
            restSeconds: 120,
          ),
        ],
        updatedAt: DateTime(2026),
      );

      expect(workout.totalSets, 3);
      expect(workout.estimatedMinutes, 8);
    });

    test('deleting a workout hides it from the list', () async {
      final exercise = bench();
      final workout = Workout(
        id: 'w1',
        name: 'Push A',
        exercises: [
          WorkoutExercise(
            exerciseId: exercise.id,
            exerciseName: exercise.name,
            targetSets: 3,
            repMin: 5,
            repMax: 8,
            restSeconds: 150,
          ),
        ],
        updatedAt: now,
      );
      await repository.saveWorkout(workout);
      await repository.deleteWorkout('w1');

      expect(repository.readWorkouts(), isEmpty);
      expect(repository.workoutById('w1'), isNull);
    });
  });

  group('the live session', () {
    test('starting twice is refused — one live session at a time', () async {
      await repository.startSession();
      final second = await repository.startSession();

      expect(
        second.failureOrNull,
        isA<ValidationFailure>()
            .having((f) => f.code, 'code', 'session_already_active'),
      );
    });

    test('a session started from a workout carries its plan and name',
        () async {
      final exercise = bench();
      await repository.saveExercise(exercise);
      final workout = Workout(
        id: 'w1',
        name: 'Push A',
        exercises: [
          WorkoutExercise(
            exerciseId: exercise.id,
            exerciseName: exercise.name,
            targetSets: 3,
            repMin: 6,
            repMax: 8,
            restSeconds: 150,
          ),
        ],
        updatedAt: now,
      );
      await repository.saveWorkout(workout);

      final session = (await repository.startSession(workout: workout))
          .valueOrNull!;

      expect(session.name, 'Push A');
      expect(session.plan, hasLength(1));
      expect(repository.activeSession()?.id, session.id);
    });

    test('an out-of-range weight or rep count never reaches the log', () async {
      final session = (await repository.startSession()).valueOrNull!;

      for (final bad in [
        (weight: -1.0, reps: 5),
        (weight: 501.0, reps: 5),
        (weight: 100.0, reps: 0),
        (weight: 100.0, reps: 101),
      ]) {
        final result = await repository.addSet(
          session: session,
          exerciseId: 'e1',
          exerciseName: 'Bench press',
          weightKg: bad.weight,
          reps: bad.reps,
        );
        expect(result.failureOrNull, isA<ValidationFailure>(), reason: '$bad');
      }

      expect(repository.activeSession()?.sets, isEmpty);
    });

    test('a set can be removed mid-session', () async {
      var session = (await repository.startSession()).valueOrNull!;
      session = (await repository.addSet(
        session: session,
        exerciseId: 'e1',
        exerciseName: 'Bench press',
        weightKg: 100,
        reps: 5,
      ))
          .valueOrNull!;

      session = (await repository.removeSet(
        session: session,
        setId: session.sets.single.id,
      ))
          .valueOrNull!;

      expect(session.sets, isEmpty);
    });

    test('finishing marks the session complete and counts the workout used',
        () async {
      final exercise = bench();
      await repository.saveExercise(exercise);
      final workout = Workout(
        id: 'w1',
        name: 'Push A',
        exercises: [
          WorkoutExercise(
            exerciseId: exercise.id,
            exerciseName: exercise.name,
            targetSets: 3,
            repMin: 5,
            repMax: 8,
            restSeconds: 150,
          ),
        ],
        updatedAt: now,
      );
      expect((await repository.saveWorkout(workout)).isOk, isTrue);

      await completeSession(
        [(weight: 100, reps: 5)],
        exerciseId: exercise.id,
        workout: workout,
      );

      expect(repository.activeSession(), isNull);
      expect(repository.workoutById('w1')?.useCount, 1);
      expect(repository.workoutById('w1')?.lastPerformedAt, isNotNull);
    });

    test('discarding removes the session entirely', () async {
      final session = (await repository.startSession()).valueOrNull!;
      await repository.discardSession(session);

      expect(repository.activeSession(), isNull);
      expect(repository.history(), isEmpty);
    });
  });

  group('personal records', () {
    test('the first working set of an exercise is a record', () async {
      final exercise = bench();
      final session = (await repository.startSession()).valueOrNull!;

      final updated = (await repository.addSet(
        session: session,
        exerciseId: exercise.id,
        exerciseName: exercise.name,
        weightKg: 100,
        reps: 5,
      ))
          .valueOrNull!;

      expect(updated.sets.single.prLabels, isNotEmpty);
    });

    test('a warm-up set is never a record and never enters the bests',
        () async {
      final exercise = bench();
      final session = (await repository.startSession()).valueOrNull!;

      final updated = (await repository.addSet(
        session: session,
        exerciseId: exercise.id,
        exerciseName: exercise.name,
        weightKg: 200,
        reps: 5,
        isWarmup: true,
      ))
          .valueOrNull!;

      expect(updated.sets.single.prLabels, isEmpty);
      expect(repository.bestsFor(exercise.id).heaviestWeightKg, isNull);
    });

    test('records are DERIVED from sessions, so they cannot disagree',
        () async {
      // Nothing stores a PR. Deleting the session that produced one removes
      // the record too, which is the only self-consistent behaviour.
      final exercise = bench();
      await completeSession(
        [(weight: 100, reps: 5)],
        exerciseId: exercise.id,
      );

      expect(repository.personalRecords(), hasLength(1));

      final session = repository.history().single;
      await repository.discardSession(session);

      expect(repository.personalRecords(), isEmpty);
    });

    test('the best e1RM wins, not the heaviest weight', () async {
      final exercise = bench();
      await completeSession(
        [(weight: 100, reps: 5)],
        exerciseId: exercise.id,
      );

      now = now.add(const Duration(days: 3));
      await completeSession(
        // 90 × 10 is a higher estimated max than 100 × 5, despite the lighter
        // bar. Reporting the heaviest weight instead would tell the user they
        // got weaker.
        [(weight: 90, reps: 10)],
        exerciseId: exercise.id,
      );

      final record = repository.personalRecords().single;
      expect(record.weightKg, 90);
      expect(record.reps, 10);
      expect(
        record.value,
        closeTo(E1rmCalculator.epley(90, 10), 0.1),
      );
    });

    test('bests aggregate the heaviest load and the best reps at each load',
        () async {
      final exercise = bench();
      await completeSession(
        [(weight: 100, reps: 5), (weight: 100, reps: 8), (weight: 110, reps: 3)],
        exerciseId: exercise.id,
      );

      final bests = repository.bestsFor(exercise.id);
      expect(bests.heaviestWeightKg, 110);
      expect(bests.repsAtWeight[100.0], 8);
    });

    test('an in-progress session does not contribute to history or bests',
        () async {
      final exercise = bench();
      final session = (await repository.startSession()).valueOrNull!;
      await repository.addSet(
        session: session,
        exerciseId: exercise.id,
        exerciseName: exercise.name,
        weightKg: 300,
        reps: 5,
      );

      expect(repository.history(), isEmpty);
      expect(repository.bestsFor(exercise.id).heaviestWeightKg, isNull);
    });
  });

  group('prefill and history', () {
    test('lastPerformance returns the most recent working set', () async {
      final exercise = bench();
      await completeSession(
        [(weight: 100, reps: 5)],
        exerciseId: exercise.id,
      );
      now = now.add(const Duration(days: 3));
      await completeSession(
        [(weight: 102.5, reps: 5)],
        exerciseId: exercise.id,
      );

      final last = repository.lastPerformance(exercise.id);
      expect(last?.weightKg, 102.5);
    });

    test('lastPerformance is null for an exercise never performed', () {
      expect(repository.lastPerformance('never'), isNull);
    });

    test('weekly volume buckets completed sessions by ISO week', () async {
      final exercise = bench();
      await completeSession(
        [(weight: 100, reps: 5), (weight: 100, reps: 5)],
        exerciseId: exercise.id,
      );

      final weeks = repository.weeklyVolume(weeks: 4, now: now);
      expect(weeks, hasLength(4));
      expect(weeks.last.volumeKg, 1000);
      expect(weeks.last.sessions, 1);
    });

    test('history is newest first and honours the limit', () async {
      final exercise = bench();
      for (var i = 0; i < 3; i++) {
        now = now.add(const Duration(days: 1));
        await completeSession(
          [(weight: 100, reps: 5)],
          exerciseId: exercise.id,
        );
      }

      final history = repository.history(limit: 2);
      expect(history, hasLength(2));
      expect(
        history.first.startedAt.isAfter(history.last.startedAt),
        isTrue,
      );
    });
  });
}
