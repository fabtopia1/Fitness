import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lifedna/core/sync/outbox.dart';
import 'package:lifedna/core/widgets/ld_widgets.dart';
import 'package:lifedna/features/auth/data/auth_repository.dart';
import 'package:lifedna/features/auth/data/profile_repository.dart';
import 'package:lifedna/features/body/data/body_repository.dart';
import 'package:lifedna/features/body/presentation/body_editor_sheet.dart';
import 'package:lifedna/features/calendar/data/calendar_repository.dart';
import 'package:lifedna/features/calendar/data/google_calendar_service.dart';
import 'package:lifedna/features/calendar/presentation/event_editor_sheet.dart';
import 'package:lifedna/features/calendar/presentation/task_editor_sheet.dart';
import 'package:lifedna/features/nutrition/data/nutrition_repository.dart';
import 'package:lifedna/features/nutrition/presentation/create_food_sheet.dart';
import 'package:lifedna/features/reminders/data/reminder_repository.dart';
import 'package:lifedna/features/reminders/presentation/reminder_editor_sheet.dart';
import 'package:lifedna/features/settings/presentation/goals_editor_sheet.dart';
import 'package:lifedna/features/supplements/data/supplement_repository.dart';
import 'package:lifedna/features/supplements/presentation/supplement_editor_sheet.dart';
import 'package:lifedna/features/workout/data/workout_repository.dart';
import 'package:lifedna/features/workout/domain/workout_entities.dart';
import 'package:lifedna/features/workout/presentation/create_exercise_sheet.dart';
import 'package:lifedna/features/workout/presentation/workout_editor_screen.dart';
import 'package:lifedna/shared/enums/enums.dart';

import '../../support/pump.dart';
import '../../support/test_harness.dart';

void main() {
  late TestEnvironment env;

  setUp(() async => env = await TestEnvironment.create());
  tearDown(() async => env.dispose());

  Outbox outbox() => Outbox(env.store);

  Future<void> signIn() async {
    final auth = AuthRepository(store: env.store);
    final session = (await auth.continueWithoutAccount()).valueOrNull!;
    await ProfileRepository(store: env.store, outbox: outbox()).save(
      auth.initialProfile(session).copyWith(
            dateOfBirth: DateTime(1998, 4, 12),
            sex: Sex.male,
            heightCm: 180,
            weightKg: 82,
            onboardingCompletedAt: DateTime.utc(2026),
          ),
    );
  }

  Future<void> enterByLabel(
    WidgetTester tester,
    String label,
    String value,
  ) async {
    await tester.enterText(
      find.ancestor(
        of: find.text(label),
        matching: find.byType(TextFormField),
      ).first,
      value,
    );
  }

  group('CreateFoodSheet', () {
    testWidgets('requires the values a food cannot be used without',
        (tester) async {
      await signIn();
      await pumpSheet(tester, env, const CreateFoodSheet());

      await tester.tap(find.widgetWithText(LdPrimaryButton, 'Save food'));
      await pumpFrames(tester);

      expect(find.text('Enter a name'), findsOneWidget);
      expect(find.text('Required'), findsWidgets);
    });

    testWidgets('warns when the stated energy contradicts the macros',
        (tester) async {
      // Community food data fails this constantly. Saving it silently would
      // poison every daily total computed from it afterwards.
      await signIn();
      await pumpSheet(tester, env, const CreateFoodSheet());

      await enterByLabel(tester, 'Name', 'Suspicious bar');
      await enterByLabel(tester, 'Calories', '100');
      await enterByLabel(tester, 'Protein', '30');
      await enterByLabel(tester, 'Carbs', '30');
      await enterByLabel(tester, 'Fat', '30');
      await pumpFrames(tester);

      expect(find.textContaining('kcal'), findsWidgets);
      expect(tester.takeException(), isNull);
    });

    testWidgets('a valid food is saved and the sheet closes', (tester) async {
      await signIn();
      await pumpSheet(tester, env, const CreateFoodSheet());

      await enterByLabel(tester, 'Name', 'Greek yoghurt');
      await enterByLabel(tester, 'Calories', '59');
      await enterByLabel(tester, 'Protein', '10');
      await enterByLabel(tester, 'Carbs', '3.6');
      await enterByLabel(tester, 'Fat', '0.4');
      await tapVisible(tester, find.widgetWithText(LdPrimaryButton, 'Save food'));
      await pumpFrames(tester, frames: 10);

      final foods =
          NutritionRepository(store: env.store, outbox: outbox()).foods.readAll();
      expect(foods, hasLength(1));
      expect(foods.single.name, 'Greek yoghurt');
      expect(foods.single.per100g.proteinG, 10);
    });
  });

  group('SupplementEditorSheet', () {
    testWidgets('refuses a supplement with no name or dose', (tester) async {
      await signIn();
      await pumpSheet(tester, env, const SupplementEditorSheet());

      await tester.tap(
        find.widgetWithText(LdPrimaryButton, 'Add supplement'),
      );
      await pumpFrames(tester);

      expect(
        SupplementRepository(
          store: env.store,
          outbox: outbox(),
          notifications: env.notifications,
        ).readSupplements(),
        isEmpty,
      );
    });

    testWidgets('saving schedules the reminder it promises', (tester) async {
      await signIn();
      await pumpSheet(tester, env, const SupplementEditorSheet());

      await enterByLabel(tester, 'Name', 'Creatine');
      await enterByLabel(tester, 'Dose', '5');
      await tester.tap(
        find.widgetWithText(LdPrimaryButton, 'Add supplement'),
      );
      await pumpFrames(tester, frames: 10);

      final saved = SupplementRepository(
        store: env.store,
        outbox: outbox(),
        notifications: env.notifications,
      ).readSupplements();
      expect(saved.single.name, 'Creatine');
      expect(env.notifications.scheduledDaily, hasLength(1));
    });

    testWidgets('editing an existing supplement pre-fills it', (tester) async {
      await signIn();
      final repository = SupplementRepository(
        store: env.store,
        outbox: outbox(),
        notifications: env.notifications,
      );
      final existing = repository.create(name: 'Magnesium', dose: 300, unit: 'mg');
      await repository.save(existing);

      await pumpSheet(tester, env, SupplementEditorSheet(existing: existing));

      expect(find.text('Magnesium'), findsOneWidget);
      expect(find.text('300'), findsOneWidget);
    });
  });

  group('BodyEditorSheet', () {
    testWidgets('a sheet with nothing entered saves nothing', (tester) async {
      await signIn();
      await pumpSheet(tester, env, const BodyEditorSheet());

      await tester.tap(find.widgetWithText(LdPrimaryButton, 'Save'));
      await pumpFrames(tester);

      expect(
        BodyRepository(store: env.store, outbox: outbox()).latest(),
        isNull,
      );
    });

    testWidgets('a weight is recorded', (tester) async {
      await signIn();
      await pumpSheet(tester, env, const BodyEditorSheet());

      // Weight is the first field on the sheet.
      await tester.enterText(find.byType(TextField).first, '81.5');
      await tapVisible(tester, find.widgetWithText(LdPrimaryButton, 'Save'));
      await pumpFrames(tester, frames: 10);

      expect(
        BodyRepository(store: env.store, outbox: outbox()).latestWeightKg(),
        81.5,
      );
    });

    testWidgets('the limb measurements are behind a disclosure', (tester) async {
      // Ten fields on one sheet is a form nobody fills in.
      await signIn();
      await pumpSheet(tester, env, const BodyEditorSheet());

      expect(find.text('Left arm'), findsNothing);
      await tester.tap(find.text('Add arms and legs'));
      await pumpFrames(tester);
      expect(find.text('Left arm'), findsOneWidget);
    });
  });

  group('TaskEditorSheet', () {
    testWidgets('a task needs a title', (tester) async {
      await signIn();
      await pumpSheet(tester, env, const TaskEditorSheet());

      await tester.tap(find.widgetWithText(LdPrimaryButton, 'Add task'));
      await pumpFrames(tester);

      expect(
        CalendarRepository(
          store: env.store,
          outbox: outbox(),
          notifications: env.notifications,
          google: GoogleCalendarService(),
        ).openTasks(),
        isEmpty,
      );
    });

    testWidgets('a titled task is saved with its category', (tester) async {
      await signIn();
      await pumpSheet(tester, env, const TaskEditorSheet());

      await tester.enterText(find.byType(TextField).first, 'Write report');
      await tapVisible(tester, find.widgetWithText(LdPrimaryButton, 'Add task'));
      await pumpFrames(tester, frames: 10);

      final tasks = CalendarRepository(
        store: env.store,
        outbox: outbox(),
        notifications: env.notifications,
        google: GoogleCalendarService(),
      ).openTasks();
      expect(tasks.single.title, 'Write report');
      expect(tasks.single.category, TaskCategory.personal);
    });
  });

  group('EventEditorSheet', () {
    testWidgets('an event needs a title', (tester) async {
      await signIn();
      await pumpSheet(tester, env, const EventEditorSheet());

      await tester.tap(find.widgetWithText(LdPrimaryButton, 'Add event'));
      await pumpFrames(tester);

      expect(tester.takeException(), isNull);
    });
  });

  group('ReminderEditorSheet', () {
    testWidgets('a reminder needs a name', (tester) async {
      await signIn();
      final repository = ReminderRepository(
        store: env.store,
        outbox: outbox(),
        notifications: env.notifications,
      );
      await pumpSheet(
        tester,
        env,
        ReminderEditorSheet(reminder: repository.draft()),
      );

      await tester.tap(find.widgetWithText(LdPrimaryButton, 'Save reminder'));
      await pumpFrames(tester);

      expect(find.text('Give the reminder a name'), findsOneWidget);
      expect(repository.readAll(), isEmpty);
    });

    testWidgets('a named reminder is saved and scheduled', (tester) async {
      await signIn();
      final repository = ReminderRepository(
        store: env.store,
        outbox: outbox(),
        notifications: env.notifications,
      );
      await pumpSheet(
        tester,
        env,
        ReminderEditorSheet(reminder: repository.draft()),
      );

      await tester.enterText(find.byType(TextFormField).first, 'Weigh in');
      await tapVisible(
        tester,
        find.widgetWithText(LdPrimaryButton, 'Save reminder'),
      );
      await pumpFrames(tester, frames: 10);

      expect(repository.readAll().single.title, 'Weigh in');
      expect(env.notifications.scheduledDaily, hasLength(1));
    });
  });

  group('GoalsEditorSheet', () {
    testWidgets('shows the targets a change would produce before saving',
        (tester) async {
      await signIn();
      final profile =
          ProfileRepository(store: env.store, outbox: outbox()).read()!;

      await pumpSheet(tester, env, GoalsEditorSheet(profile: profile));

      expect(find.text('Goals and targets'), findsOneWidget);
      expect(find.text('NEW TARGETS'), findsOneWidget);
      expect(find.textContaining('kcal training day'), findsOneWidget);
    });

    testWidgets('saving updates the profile the engines read', (tester) async {
      await signIn();
      final profiles = ProfileRepository(store: env.store, outbox: outbox());
      final before = profiles.read()!.computedTargets!.trainingDay.kcal;

      await pumpSheet(tester, env, GoalsEditorSheet(profile: profiles.read()!));
      await tapVisible(tester, find.text('Build'));
      await tapVisible(tester, find.widgetWithText(LdPrimaryButton, 'Save'));
      await pumpFrames(tester, frames: 10);

      final after = profiles.read()!;
      expect(after.goalMode, GoalMode.bulk);
      expect(after.computedTargets!.trainingDay.kcal, greaterThan(before));
    });
  });

  group('CreateExerciseSheet', () {
    testWidgets('a named exercise is added to the library', (tester) async {
      await signIn();
      await pumpSheet(tester, env, const CreateExerciseSheet());

      await tester.enterText(find.byType(TextFormField).first, 'Incline press');
      await tapVisible(
        tester,
        find.widgetWithText(LdPrimaryButton, 'Save exercise'),
      );
      await pumpFrames(tester, frames: 10);

      final exercises =
          WorkoutRepository(store: env.store, outbox: outbox()).searchExercises('');
      expect(exercises.single.name, 'Incline press');
      expect(exercises.single.isCustom, isTrue);
    });
  });

  group('WorkoutEditorScreen', () {
    testWidgets('a workout with no exercises cannot be saved', (tester) async {
      await signIn();
      await pumpScreen(tester, env, const WorkoutEditorScreen());
      await pumpFrames(tester);

      await tester.enterText(find.byType(TextField).first, 'Push A');
      await tester.tap(find.widgetWithText(LdPrimaryButton, 'Create program'));
      await pumpFrames(tester, frames: 8);

      expect(
        WorkoutRepository(store: env.store, outbox: outbox()).readWorkouts(),
        isEmpty,
      );
    });

    testWidgets('the editor opens on an existing workout', (tester) async {
      await signIn();
      final repository =
          WorkoutRepository(store: env.store, outbox: outbox());
      final exercise = repository.createExercise(
        name: 'Bench press',
        muscleGroup: MuscleGroup.chest,
        equipment: Equipment.barbell,
      );
      await repository.saveExercise(exercise);
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
              restSeconds: 150,
            ),
          ],
          updatedAt: DateTime.now(),
        ),
      );

      await pumpScreen(tester, env, const WorkoutEditorScreen(workoutId: 'w1'));
      await pumpFrames(tester);

      expect(find.text('Push A'), findsWidgets);
      expect(find.text('Bench press'), findsWidgets);
    });
  });
}
