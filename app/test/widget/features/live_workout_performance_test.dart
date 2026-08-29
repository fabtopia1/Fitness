import 'package:flutter_test/flutter_test.dart';
import 'package:lifedna/core/providers/providers.dart';
import 'package:lifedna/core/sync/outbox.dart';
import 'package:lifedna/features/workout/data/workout_repository.dart';
import 'package:lifedna/features/workout/domain/workout_entities.dart';
import 'package:lifedna/features/workout/presentation/live_workout_screen.dart';
import 'package:lifedna/shared/enums/enums.dart';

import '../../support/pump.dart';
import '../../support/test_harness.dart';

/// H-4 regression suite.
///
/// The defect: a `Timer.periodic` on the screen state called
/// `setState(() {})` once a second, rebuilding the header, the exercise panel
/// and the action bar. Each of those rebuilds called `lastPerformance` three
/// times — twice from the resolvers, once from the panel — and each call ran
/// `setsFor`, which deserialises **every completed session** out of Hive and
/// sorts the result.
///
/// So: three full history scans per second, for the 45–90 minutes a workout
/// lasts, on the screen the user is holding one-handed between sets. It gets
/// worse the longer someone uses the app, which is the worst possible shape
/// for a performance bug — the beta testers who like it most hit it hardest.
class _CountingWorkoutRepository extends WorkoutRepository {
  _CountingWorkoutRepository({
    required super.store,
    required super.outbox,
    required super.clock,
  });

  int historyScans = 0;

  @override
  LastPerformance? lastPerformance(String exerciseId) {
    historyScans++;
    return super.lastPerformance(exerciseId);
  }
}

void main() {
  late TestEnvironment env;
  late _CountingWorkoutRepository repository;
  // The screen reads "now" through clockProvider, so a workout's elapsed time
  // is deterministic here rather than tied to how long the test takes.
  var now = DateTime(2026, 5, 1, 18);

  setUp(() async {
    now = DateTime(2026, 5, 1, 18);
    env = await TestEnvironment.create();
    repository = _CountingWorkoutRepository(
      store: env.store,
      outbox: Outbox(env.store),
      clock: () => now,
    );
  });
  tearDown(() async => env.dispose());

  Future<void> startSession() async {
    final exercise = repository.createExercise(
      name: 'Bench press',
      muscleGroup: MuscleGroup.chest,
      equipment: Equipment.barbell,
      restSeconds: 90,
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
          restSeconds: 90,
        ),
      ],
      updatedAt: DateTime.now(),
    );
    await repository.saveWorkout(workout);
    await repository.startSession(workout: workout);
  }

  Future<void> pump(WidgetTester tester) => pumpScreen(
    tester,
    env,
    const LiveWorkoutScreen(),
    overrides: [
      workoutRepositoryProvider.overrideWithValue(repository),
      clockProvider.overrideWithValue(() => now),
    ],
  );

  testWidgets('the running clock does not rescan history every second', (
    tester,
  ) async {
    await startSession();
    await pump(tester);
    await pumpFrames(tester);

    final afterFirstBuild = repository.historyScans;
    expect(
      afterFirstBuild,
      lessThanOrEqualTo(2),
      reason: 'one lookup per exercise on screen, not three per rebuild',
    );

    // Thirty seconds of a workout — a fraction of one rest period.
    for (var i = 0; i < 30; i++) {
      now = now.add(const Duration(seconds: 1));
      await tester.pump(const Duration(seconds: 1));
    }

    expect(
      repository.historyScans,
      afterFirstBuild,
      reason: 'the clock ticking must not re-read the workout history at all',
    );
  });

  testWidgets('the clock still advances — the fix is not a stopped timer', (
    tester,
  ) async {
    await startSession();
    await pump(tester);
    await pumpFrames(tester);

    expect(find.text('00:00'), findsOneWidget);

    now = now.add(const Duration(seconds: 65));
    await tester.pump(const Duration(seconds: 1));

    expect(find.text('01:05'), findsOneWidget);
  });

  testWidgets('resting does not rebuild the rest of the screen', (
    tester,
  ) async {
    await startSession();
    await pump(tester);
    await pumpFrames(tester);

    await tapVisible(tester, find.text('COMPLETE SET'));
    await pumpFrames(tester);

    final duringRest = repository.historyScans;

    // The rest countdown is the second per-second repaint on this screen.
    for (var i = 0; i < 10; i++) {
      now = now.add(const Duration(seconds: 1));
      await tester.pump(const Duration(seconds: 1));
    }

    expect(
      repository.historyScans,
      duringRest,
      reason: 'the countdown repaints the overlay, not the whole screen',
    );

    await tester.pump(const Duration(seconds: 90));
    await pumpFrames(tester);
  });

  testWidgets('a logged set does refresh what "last time" shows', (
    tester,
  ) async {
    // The cache must be invalidated by the one event that can change the
    // answer, or the fix trades a performance bug for a staleness bug.
    await startSession();
    await pump(tester);
    await pumpFrames(tester);

    final before = repository.historyScans;

    await tapVisible(tester, find.text('COMPLETE SET'));
    await pumpFrames(tester);

    expect(
      repository.historyScans,
      greaterThan(before),
      reason: 'adding a set invalidates the cached lookup',
    );

    await tester.pump(const Duration(seconds: 90));
    await pumpFrames(tester);
  });
}
