import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lifedna/core/sync/outbox.dart';
import 'package:lifedna/core/theme/ld_spacing.dart';
import 'package:lifedna/core/widgets/ld_widgets.dart';
import 'package:lifedna/features/auth/data/auth_repository.dart';
import 'package:lifedna/features/auth/data/profile_repository.dart';
import 'package:lifedna/features/workout/data/workout_repository.dart';
import 'package:lifedna/features/workout/domain/workout_entities.dart';
import 'package:lifedna/features/workout/presentation/exercise_library_screen.dart';
import 'package:lifedna/features/workout/presentation/exercise_picker.dart';
import 'package:lifedna/features/workout/presentation/live_workout_screen.dart';
import 'package:lifedna/features/workout/presentation/workout_screen.dart';
import 'package:lifedna/shared/enums/enums.dart';

import '../../support/pump.dart';
import '../../support/test_harness.dart';

void main() {
  late TestEnvironment env;

  setUp(() async => env = await TestEnvironment.create());
  tearDown(() async => env.dispose());

  Outbox outbox() => Outbox(env.store);
  WorkoutRepository workouts() =>
      WorkoutRepository(store: env.store, outbox: outbox());

  Future<void> signIn() async {
    final auth = AuthRepository(store: env.store);
    final session = (await auth.continueWithoutAccount()).valueOrNull!;
    await ProfileRepository(store: env.store, outbox: outbox()).save(
      auth
          .initialProfile(session)
          .copyWith(
            dateOfBirth: DateTime(1998, 4, 12),
            sex: Sex.male,
            heightCm: 180,
            weightKg: 82,
            onboardingCompletedAt: DateTime.utc(2026),
          ),
    );
  }

  /// A program with one exercise, plus a live session on it.
  Future<WorkoutSession> startPlannedSession() async {
    final repository = workouts();
    final exercise = repository.createExercise(
      name: 'Bench press',
      muscleGroup: MuscleGroup.chest,
      equipment: Equipment.barbell,
      restSeconds: 3,
    );
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
          restSeconds: 3,
        ),
      ],
      updatedAt: DateTime.now(),
    );
    await repository.saveWorkout(workout);
    return (await repository.startSession(workout: workout)).valueOrNull!;
  }

  group('with no session in progress', () {
    testWidgets('the screen explains where a workout starts', (tester) async {
      await signIn();
      await pumpScreen(tester, env, const LiveWorkoutScreen());
      await pumpFrames(tester);

      expect(find.text('No workout in progress'), findsOneWidget);
      expect(find.text('Go to Train'), findsOneWidget);
    });
  });

  group('Live Gym Mode', () {
    testWidgets('opens on the planned exercise with the set counter', (
      tester,
    ) async {
      await signIn();
      await startPlannedSession();
      await pumpScreen(tester, env, const LiveWorkoutScreen());
      await pumpFrames(tester);

      expect(find.text('Push A'), findsOneWidget);
      // The panel headline is uppercased for legibility at arm's length.
      expect(find.text('BENCH PRESS'), findsOneWidget);
      expect(find.textContaining('Set 1 of 3'), findsOneWidget);
      expect(find.text('COMPLETE SET'), findsOneWidget);
    });

    testWidgets('the primary action meets the one-handed size floor', (
      tester,
    ) async {
      // Live Gym Mode is operated mid-set, at arm's length, one-handed.
      await signIn();
      await startPlannedSession();
      await pumpScreen(tester, env, const LiveWorkoutScreen());
      await pumpFrames(tester);

      final button = tester.widget<LdPrimaryButton>(
        find.widgetWithText(LdPrimaryButton, 'COMPLETE SET'),
      );
      expect(button.size, LdButtonSize.xl);
      expect(button.size.height, greaterThanOrEqualTo(LdTouch.gym));
    });

    testWidgets('the steppers change the load and the reps', (tester) async {
      await signIn();
      await startPlannedSession();
      await pumpScreen(tester, env, const LiveWorkoutScreen());
      await pumpFrames(tester);

      // Default load with no history is 20 kg, and the increment is the
      // exercise's own.
      expect(find.text('20'), findsOneWidget);

      await tester.tap(find.byIcon(Icons.add_rounded).first);
      await pumpFrames(tester);
      expect(find.text('22.5'), findsOneWidget);

      await tester.tap(find.byIcon(Icons.remove_rounded).last);
      await pumpFrames(tester);
      expect(find.text('5'), findsOneWidget);
    });

    testWidgets('completing a set logs it and starts the rest timer', (
      tester,
    ) async {
      await signIn();
      await startPlannedSession();
      await pumpScreen(tester, env, const LiveWorkoutScreen());
      await pumpFrames(tester);

      await tester.tap(find.text('COMPLETE SET'));
      await pumpFrames(tester);

      final session = workouts().activeSession()!;
      expect(session.sets, hasLength(1));
      expect(session.sets.single.weightKg, 20);

      // The rest overlay owns the screen while it runs.
      expect(find.text('Skip'), findsOneWidget);
      expect(find.text('+ 15s'), findsOneWidget);
    });

    testWidgets('a rest period can be extended and skipped', (tester) async {
      await signIn();
      await startPlannedSession();
      await pumpScreen(tester, env, const LiveWorkoutScreen());
      await pumpFrames(tester);

      await tester.tap(find.text('COMPLETE SET'));
      await pumpFrames(
        tester,
        frames: 2,
        step: const Duration(milliseconds: 10),
      );

      await tester.tap(find.text('+ 15s'));
      await tester.pump();
      await tester.tap(find.text('− 15s'));
      await tester.pump();

      await tester.tap(find.text('Skip'));
      await pumpFrames(tester);
      expect(find.text('Skip'), findsNothing);
    });

    testWidgets('the rest timer fires a notification when it runs out', (
      tester,
    ) async {
      // Most people switch apps mid-rest, so the alert has to leave the app.
      await signIn();
      await startPlannedSession();
      await pumpScreen(tester, env, const LiveWorkoutScreen());
      await pumpFrames(tester);

      await tester.tap(find.text('COMPLETE SET'));
      await pumpFrames(tester, frames: 6, step: const Duration(seconds: 1));

      expect(env.notifications.shown, isNotEmpty);
      expect(env.notifications.shown.last.title, 'Rest finished');
    });

    testWidgets('the first working set of an exercise is announced as a PR', (
      tester,
    ) async {
      await signIn();
      await startPlannedSession();
      await pumpScreen(tester, env, const LiveWorkoutScreen());
      await pumpFrames(tester);

      await tester.tap(find.text('COMPLETE SET'));
      await pumpFrames(tester);

      expect(find.textContaining('🏆'), findsWidgets);
    });

    testWidgets('an RPE can be attached to the set', (tester) async {
      await signIn();
      await startPlannedSession();
      await pumpScreen(tester, env, const LiveWorkoutScreen());
      await pumpFrames(tester);

      await tester.tap(find.text('8'));
      await pumpFrames(tester);
      await tester.tap(find.text('COMPLETE SET'));
      await pumpFrames(tester);

      expect(workouts().activeSession()!.sets.single.rpe, 8);
    });

    testWidgets('a logged set is prefilled from the last performance', (
      tester,
    ) async {
      await signIn();
      final repository = workouts();
      final exercise = repository.createExercise(
        name: 'Bench press',
        muscleGroup: MuscleGroup.chest,
        equipment: Equipment.barbell,
      );
      await repository.saveExercise(exercise);

      // A completed session in history at 100 kg × 5.
      var previous = (await repository.startSession()).valueOrNull!;
      previous = (await repository.addSet(
        session: previous,
        exerciseId: exercise.id,
        exerciseName: exercise.name,
        weightKg: 100,
        reps: 5,
      )).valueOrNull!;
      await repository.finishSession(previous);

      await repository.saveWorkout(
        Workout(
          id: 'w1',
          name: 'Push A',
          exercises: [
            WorkoutExercise(
              exerciseId: exercise.id,
              exerciseName: exercise.name,
              targetSets: 3,
              repMin: 6,
              repMax: 8,
              restSeconds: 3,
            ),
          ],
          updatedAt: DateTime.now(),
        ),
      );
      await repository.startSession(workout: repository.workoutById('w1'));

      await pumpScreen(tester, env, const LiveWorkoutScreen());
      await pumpFrames(tester);

      // Typing the same numbers again every session is the friction that
      // stops people logging at all.
      expect(find.text('100'), findsOneWidget);
      expect(find.textContaining('Last time'), findsOneWidget);
    });

    testWidgets('finishing an empty session offers to discard it', (
      tester,
    ) async {
      await signIn();
      await startPlannedSession();
      await pumpScreen(tester, env, const LiveWorkoutScreen());
      await pumpFrames(tester);

      await tester.tap(find.text('Finish'));
      await pumpFrames(tester);

      expect(find.text('Discard workout?'), findsOneWidget);
      await tester.tap(find.text('Keep going'));
      await pumpFrames(tester);
      expect(workouts().activeSession(), isNotNull);
    });

    testWidgets('discarding an empty session removes it', (tester) async {
      await signIn();
      await startPlannedSession();
      await pumpScreen(tester, env, const LiveWorkoutScreen());
      await pumpFrames(tester);

      await tester.tap(find.text('Finish'));
      await pumpFrames(tester);
      await tester.tap(find.text('Discard'));
      await pumpFrames(tester);

      expect(workouts().activeSession(), isNull);
    });

    testWidgets('finishing a logged session shows a summary before saving', (
      tester,
    ) async {
      await signIn();
      await startPlannedSession();
      await pumpScreen(tester, env, const LiveWorkoutScreen());
      await pumpFrames(tester);

      await tester.tap(find.text('COMPLETE SET'));
      await pumpFrames(tester);
      await tester.tap(find.text('Skip'));
      await pumpFrames(tester);

      await tester.tap(find.text('Finish'));
      await pumpFrames(tester);

      expect(find.text('VOLUME KG'), findsOneWidget);
      expect(find.text('SETS'), findsOneWidget);
      expect(find.text('PRs'), findsOneWidget);

      await tester.tap(find.widgetWithText(LdPrimaryButton, 'Save workout'));
      await pumpFrames(tester, frames: 10);

      expect(workouts().activeSession(), isNull);
      expect(workouts().history(), hasLength(1));
    });

    testWidgets('"Keep going" from the summary leaves the session open', (
      tester,
    ) async {
      await signIn();
      await startPlannedSession();
      await pumpScreen(tester, env, const LiveWorkoutScreen());
      await pumpFrames(tester);

      await tester.tap(find.text('COMPLETE SET'));
      await pumpFrames(tester);
      await tester.tap(find.text('Skip'));
      await pumpFrames(tester);
      await tester.tap(find.text('Finish'));
      await pumpFrames(tester);
      await tester.tap(find.widgetWithText(LdPrimaryButton, 'Keep going'));
      await pumpFrames(tester);

      expect(workouts().activeSession(), isNotNull);
    });

    testWidgets('a freeform session prompts for the first exercise', (
      tester,
    ) async {
      await signIn();
      await workouts().startSession();
      await pumpScreen(tester, env, const LiveWorkoutScreen());
      await pumpFrames(tester);

      expect(find.text('Freeform workout'), findsOneWidget);
      expect(find.text('Add exercise'), findsWidgets);
    });

    testWidgets('an exercise can be added mid-session from the picker', (
      tester,
    ) async {
      await signIn();
      final repository = workouts();
      await repository.saveExercise(
        repository.createExercise(
          name: 'Lat pulldown',
          muscleGroup: MuscleGroup.back,
          equipment: Equipment.cable,
        ),
      );
      await repository.startSession();

      await pumpScreen(tester, env, const LiveWorkoutScreen());
      await pumpFrames(tester);

      await tester.tap(find.text('Add exercise').first);
      await pumpFrames(tester);
      expect(find.byType(ExercisePicker), findsOneWidget);

      await tester.tap(find.text('Lat pulldown'));
      await pumpFrames(tester);

      expect(repository.activeSession()!.plan, hasLength(1));
      expect(find.text('COMPLETE SET'), findsOneWidget);
    });
  });

  group('WorkoutScreen', () {
    testWidgets('an in-progress session offers to resume', (tester) async {
      await signIn();
      await startPlannedSession();
      await pumpScreen(tester, env, const WorkoutScreen());
      await pumpFrames(tester);

      expect(find.text('Resume workout'), findsOneWidget);
    });

    testWidgets('with no session it offers to start an empty one', (
      tester,
    ) async {
      await signIn();
      await pumpScreen(tester, env, const WorkoutScreen());
      await pumpFrames(tester);

      expect(find.text('Start empty workout'), findsOneWidget);
      expect(find.text('No programs yet'), findsOneWidget);
    });

    testWidgets('starting an empty workout opens the live screen', (
      tester,
    ) async {
      await signIn();
      await pumpScreen(tester, env, const WorkoutScreen());
      await pumpFrames(tester);

      await tester.tap(find.text('Start empty workout'));
      await pumpFrames(tester, frames: 10);

      expect(workouts().activeSession(), isNotNull);
    });

    testWidgets('a saved program is listed with its volume estimate', (
      tester,
    ) async {
      await signIn();
      final repository = workouts();
      final exercise = repository.createExercise(
        name: 'Squat',
        muscleGroup: MuscleGroup.quads,
        equipment: Equipment.barbell,
      );
      await repository.saveExercise(exercise);
      await repository.saveWorkout(
        Workout(
          id: 'w1',
          name: 'Legs',
          exercises: [
            WorkoutExercise(
              exerciseId: exercise.id,
              exerciseName: exercise.name,
              targetSets: 5,
              repMin: 5,
              repMax: 5,
              restSeconds: 180,
            ),
          ],
          updatedAt: DateTime.now(),
        ),
      );

      await pumpScreen(tester, env, const WorkoutScreen());
      await pumpFrames(tester);

      expect(find.text('Legs'), findsOneWidget);
    });
  });

  group('ExerciseLibraryScreen', () {
    testWidgets('lists every exercise with its muscle group', (tester) async {
      await signIn();
      final repository = workouts();
      for (final name in ['Bench press', 'Squat', 'Deadlift']) {
        await repository.saveExercise(
          repository.createExercise(
            name: name,
            muscleGroup: MuscleGroup.fullBody,
            equipment: Equipment.barbell,
          ),
        );
      }

      await pumpScreen(tester, env, const ExerciseLibraryScreen());
      await pumpFrames(tester);

      expect(find.text('Squat'), findsOneWidget);
      expect(find.text('Deadlift'), findsOneWidget);
      expect(find.text('Bench press'), findsOneWidget);
    });

    testWidgets('an empty library names what to do about it', (tester) async {
      await signIn();
      await pumpScreen(tester, env, const ExerciseLibraryScreen());
      await pumpFrames(tester);

      expect(find.byType(LdEmptyState), findsOneWidget);
    });
  });

  group('ExercisePicker', () {
    testWidgets('search narrows the list', (tester) async {
      await signIn();
      final repository = workouts();
      for (final name in ['Bench press', 'Squat', 'Deadlift']) {
        await repository.saveExercise(
          repository.createExercise(
            name: name,
            muscleGroup: MuscleGroup.fullBody,
            equipment: Equipment.barbell,
          ),
        );
      }

      await pumpSheet(tester, env, const ExercisePicker());
      expect(find.text('Squat'), findsOneWidget);

      await tester.enterText(find.byType(TextField).first, 'dead');
      await pumpFrames(tester);

      expect(find.text('Squat'), findsNothing);
      expect(find.text('Deadlift'), findsOneWidget);
    });
  });
}
