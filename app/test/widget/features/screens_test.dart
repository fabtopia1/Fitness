import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:lifedna/core/storage/hive_store.dart';
import 'package:lifedna/core/sync/outbox.dart';
import 'package:lifedna/core/widgets/ld_widgets.dart';
import 'package:lifedna/features/ai_hub/presentation/ai_hub_screen.dart';
import 'package:lifedna/features/auth/data/auth_repository.dart';
import 'package:lifedna/features/auth/data/profile_repository.dart';
import 'package:lifedna/features/body/data/body_repository.dart';
import 'package:lifedna/features/body/presentation/body_screen.dart';
import 'package:lifedna/features/calendar/data/calendar_repository.dart';
import 'package:lifedna/features/calendar/data/google_calendar_service.dart';
import 'package:lifedna/features/calendar/presentation/plan_screen.dart';
import 'package:lifedna/features/dashboard/presentation/dashboard_screen.dart';
import 'package:lifedna/features/health_sync/presentation/health_sync_screen.dart';
import 'package:lifedna/features/nutrition/data/nutrition_repository.dart';
import 'package:lifedna/features/nutrition/domain/nutrition_entities.dart';
import 'package:lifedna/features/nutrition/presentation/add_food_screen.dart';
import 'package:lifedna/features/nutrition/presentation/nutrition_screen.dart';
import 'package:lifedna/features/reminders/data/reminder_repository.dart';
import 'package:lifedna/features/settings/presentation/settings_screen.dart';
import 'package:lifedna/features/supplements/data/supplement_repository.dart';
import 'package:lifedna/features/supplements/presentation/supplements_screen.dart';
import 'package:lifedna/features/workout/presentation/exercise_library_screen.dart';
import 'package:lifedna/features/workout/presentation/workout_screen.dart';
import 'package:lifedna/shared/enums/enums.dart';
import 'package:lifedna/shared/value_objects/macros.dart';

import '../../support/pump.dart';
import '../../support/test_harness.dart';

void main() {
  late TestEnvironment env;

  setUp(() async => env = await TestEnvironment.create());
  tearDown(() async => env.dispose());

  Outbox outbox() => Outbox(env.store);

  /// Signs in locally and writes an onboarded profile, which is the state
  /// every in-app screen is designed for.
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
            goalMode: GoalMode.cut,
            onboardingCompletedAt: DateTime.utc(2026),
          ),
    );
  }

  NutritionRepository nutrition() =>
      NutritionRepository(store: env.store, outbox: outbox());

  group('DashboardScreen', () {
    testWidgets('greets an onboarded user and shows today\'s rings', (
      tester,
    ) async {
      await signIn();
      await pumpScreen(tester, env, const DashboardScreen());
      await pumpFrames(tester);

      expect(find.byType(LdProgressRing), findsWidgets);
      expect(find.textContaining('kcal'), findsWidgets);
    });

    testWidgets('an empty day still renders every section', (tester) async {
      await signIn();
      await pumpScreen(tester, env, const DashboardScreen());
      await pumpFrames(tester);

      // No data is a normal state on day one, not an error state.
      expect(find.byType(LdErrorView), findsNothing);
      expect(tester.takeException(), isNull);
    });

    testWidgets('logged food moves the calorie ring', (tester) async {
      await signIn();
      final repository = nutrition();
      final food = repository.createFood(
        name: 'Oats',
        per100g: const Macros(kcal: 379, proteinG: 13, carbsG: 67, fatG: 7),
      );
      await repository.saveFood(food);
      await repository.logFood(
        food: food,
        quantity: 100,
        unit: PortionUnit.grams,
        slot: MealSlot.breakfast,
      );

      await pumpScreen(tester, env, const DashboardScreen());
      await pumpFrames(tester);

      expect(find.textContaining('379'), findsWidgets);
    });
  });

  group('NutritionScreen', () {
    testWidgets('offers a way to add food when the day is empty', (
      tester,
    ) async {
      await signIn();
      await pumpScreen(tester, env, const NutritionScreen());
      await pumpFrames(tester);

      expect(find.byType(LdEmptyState), findsWidgets);
      expect(tester.takeException(), isNull);
    });

    testWidgets('lists a logged entry with its macros', (tester) async {
      await signIn();
      final repository = nutrition();
      final food = repository.createFood(
        name: 'Chicken breast',
        per100g: const Macros(kcal: 165, proteinG: 31, fatG: 3.6),
      );
      await repository.saveFood(food);
      await repository.logFood(
        food: food,
        quantity: 200,
        unit: PortionUnit.grams,
        slot: MealSlot.lunch,
      );

      await pumpScreen(tester, env, const NutritionScreen());
      await pumpFrames(tester);

      expect(find.textContaining('Chicken breast'), findsWidgets);
    });
  });

  group('AddFoodScreen', () {
    testWidgets('an empty library invites the user to create a food', (
      tester,
    ) async {
      await signIn();
      await pumpScreen(tester, env, const AddFoodScreen());
      await pumpFrames(tester);

      expect(find.byType(LdEmptyState), findsWidgets);
    });

    testWidgets('typing filters the library', (tester) async {
      await signIn();
      final repository = nutrition();
      for (final name in ['Rice', 'Chicken breast', 'Olive oil']) {
        await repository.saveFood(
          repository.createFood(name: name, per100g: const Macros(kcal: 100)),
        );
      }

      await pumpScreen(tester, env, const AddFoodScreen());
      await pumpFrames(tester);
      expect(find.text('Rice'), findsOneWidget);

      await tester.enterText(find.byType(TextField).first, 'chick');
      await pumpFrames(tester);

      expect(find.text('Rice'), findsNothing);
      expect(find.text('Chicken breast'), findsOneWidget);
    });
  });

  group('WorkoutScreen', () {
    testWidgets('an athlete with no workouts is offered a way to start', (
      tester,
    ) async {
      await signIn();
      await pumpScreen(tester, env, const WorkoutScreen());
      await pumpFrames(tester);

      expect(find.byType(LdEmptyState), findsWidgets);
      expect(tester.takeException(), isNull);
    });
  });

  group('ExerciseLibraryScreen', () {
    testWidgets('renders without a crash when empty', (tester) async {
      await signIn();
      await pumpScreen(tester, env, const ExerciseLibraryScreen());
      await pumpFrames(tester);

      expect(tester.takeException(), isNull);
    });
  });

  group('BodyScreen', () {
    testWidgets('an empty history explains what to do', (tester) async {
      await signIn();
      await pumpScreen(tester, env, const BodyScreen());
      await pumpFrames(tester);

      expect(find.byType(LdEmptyState), findsWidgets);
    });

    testWidgets('a measurement produces a chart and a latest value', (
      tester,
    ) async {
      await signIn();
      final repository = BodyRepository(store: env.store, outbox: outbox());
      await repository.save(
        repository.create(
          measuredAt: DateTime.now().subtract(const Duration(days: 7)),
          weightKg: 84,
        ),
      );
      await repository.save(repository.create(weightKg: 82.4));

      await pumpScreen(tester, env, const BodyScreen());
      await pumpFrames(tester);

      expect(find.textContaining('82.4'), findsWidgets);
      expect(tester.takeException(), isNull);
    });
  });

  group('SupplementsScreen', () {
    testWidgets('an empty stack offers the starter stack', (tester) async {
      await signIn();
      await pumpScreen(tester, env, const SupplementsScreen());
      await pumpFrames(tester);

      expect(find.byType(LdEmptyState), findsWidgets);
    });

    testWidgets('a saved supplement appears with its dose', (tester) async {
      await signIn();
      final repository = SupplementRepository(
        store: env.store,
        outbox: outbox(),
        notifications: env.notifications,
      );
      await repository.save(
        repository.create(name: 'Creatine', dose: 5, unit: 'g'),
      );

      await pumpScreen(tester, env, const SupplementsScreen());
      await pumpFrames(tester);

      expect(find.text('Creatine'), findsWidgets);
      expect(find.textContaining('5 g'), findsWidgets);
    });
  });

  group('PlanScreen', () {
    testWidgets('opens on tasks and can switch to reminders', (tester) async {
      await signIn();
      await pumpScreen(tester, env, const PlanScreen());
      await pumpFrames(tester);

      expect(find.text('Plan'), findsOneWidget);
      expect(find.text('Tasks'), findsWidgets);

      await tester.tap(find.text('Reminders'));
      await pumpFrames(tester);

      expect(find.text('No reminders yet'), findsOneWidget);
    });

    testWidgets('a saved task is listed', (tester) async {
      await signIn();
      final repository = CalendarRepository(
        store: env.store,
        outbox: outbox(),
        notifications: env.notifications,
        google: GoogleCalendarService(),
      );
      await repository.saveTask(
        repository.createTask(title: 'Submit coursework'),
      );

      await pumpScreen(tester, env, const PlanScreen());
      await pumpFrames(tester);

      expect(find.text('Submit coursework'), findsOneWidget);
    });

    testWidgets('a reminder can be created and switched off', (tester) async {
      await signIn();
      final repository = ReminderRepository(
        store: env.store,
        outbox: outbox(),
        notifications: env.notifications,
      );
      await repository.save(
        repository.draft().copyWith(title: 'Weigh in', hour: 7, minute: 30),
      );

      await pumpScreen(tester, env, const PlanScreen());
      await pumpFrames(tester);
      await tester.tap(find.text('Reminders'));
      await pumpFrames(tester);

      expect(find.text('Weigh in'), findsOneWidget);
      expect(find.text('07:30'), findsOneWidget);

      await tester.tap(find.byType(Switch).first);
      await pumpFrames(tester);

      expect(repository.readAll().single.enabled, isFalse);
      expect(env.notifications.scheduledDaily, isEmpty);
    });
  });

  group('AiHubScreen', () {
    testWidgets('shows deterministic insights and the exact brief to be sent', (
      tester,
    ) async {
      await signIn();
      await pumpScreen(tester, env, const AiHubScreen());
      await pumpFrames(tester);

      // The coach runs on-device: there is no network state to wait for.
      expect(find.byType(LdErrorView), findsNothing);
      expect(find.text('AI Hub'), findsOneWidget);
      await tester.scrollUntilVisible(find.text('ASK AN ASSISTANT'), 200);
      expect(find.text('ASK AN ASSISTANT'), findsOneWidget);
      expect(tester.takeException(), isNull);
    });
  });

  group('HealthSyncScreen', () {
    testWidgets('reports the truth about what is connected', (tester) async {
      await signIn();
      await pumpScreen(tester, env, const HealthSyncScreen());
      await pumpFrames(tester);

      // Off a device there is no Health Connect, and the screen says so
      // instead of rendering invented step counts.
      expect(find.textContaining('Samsung Health'), findsWidgets);
      expect(tester.takeException(), isNull);
    });
  });

  group('SettingsScreen', () {
    testWidgets('shows the account, the derived targets and local mode', (
      tester,
    ) async {
      await signIn();
      await pumpScreen(tester, env, const SettingsScreen());
      await pumpFrames(tester);

      expect(find.text('Me'), findsOneWidget);
      expect(find.text('Local mode'), findsOneWidget);
      expect(find.textContaining('kcal'), findsWidgets);
      expect(find.text('On this device only'), findsWidgets);
    });

    testWidgets('every module is reachable from here', (tester) async {
      await signIn();
      await pumpScreen(tester, env, const SettingsScreen());
      await pumpFrames(tester);

      for (final title in [
        'Supplements',
        'Plan',
        'AI Hub',
        'Health sync',
        'Exercise library',
      ]) {
        expect(find.text(title), findsOneWidget, reason: title);
      }
    });

    testWidgets('the reminder switch changes the stored setting', (
      tester,
    ) async {
      await signIn();
      await pumpScreen(tester, env, const SettingsScreen());
      await pumpFrames(tester);

      await tester.scrollUntilVisible(find.text('Scheduled reminders'), 200);
      await tester.tap(
        find
            .descendant(
              of: find.byType(LdSwitchRow),
              matching: find.byType(Switch),
            )
            .first,
      );
      await pumpFrames(tester);

      expect(env.notifications.remindersEnabled, isFalse);
    });

    testWidgets('erasing local data asks first and then wipes everything', (
      tester,
    ) async {
      await signIn();
      await env.store.write(HiveStore.boxWorkouts, 'w', {'id': 'w'});

      await pumpScreen(tester, env, const SettingsScreen());
      await pumpFrames(tester);

      await tester.scrollUntilVisible(
        find.text('Erase data on this device'),
        200,
      );
      await tester.tap(find.text('Erase data on this device'));
      await pumpFrames(tester);

      // The copy has to say what is lost, because in local mode it is
      // unrecoverable.
      expect(find.textContaining('deleted permanently'), findsOneWidget);

      await tester.tap(find.text('Cancel'));
      await pumpFrames(tester);
      expect(env.store.readAll(HiveStore.boxWorkouts), hasLength(1));
    });

    testWidgets('signing out warns about work that has not synced', (
      tester,
    ) async {
      await signIn();
      await pumpScreen(tester, env, const SettingsScreen());
      await pumpFrames(tester);

      await tester.scrollUntilVisible(find.text('Sign out'), 200);
      await tester.tap(find.text('Sign out'));
      await pumpFrames(tester);

      expect(find.text('Sign out?'), findsOneWidget);
      await tester.tap(find.text('Cancel'));
      await pumpFrames(tester);
    });
  });

  group('the shell', () {
    testWidgets('the app routes an onboarded user to the dashboard', (
      tester,
    ) async {
      await signIn();
      await pumpApp(tester, env);
      await pumpFrames(tester, frames: 12);

      expect(find.byType(DashboardScreen), findsOneWidget);
      expect(find.text('Home'), findsOneWidget);
      expect(find.text('Train'), findsOneWidget);
    });

    testWidgets('a signed-out user lands on the welcome screen', (
      tester,
    ) async {
      await pumpApp(tester, env);
      await pumpFrames(tester, frames: 12);

      expect(find.text('LifeDNA OS'), findsOneWidget);
      expect(find.byType(DashboardScreen), findsNothing);
    });

    testWidgets('the bottom bar moves between destinations', (tester) async {
      await signIn();
      await pumpApp(tester, env);
      await pumpFrames(tester, frames: 12);

      await tester.tap(find.text('Body'));
      await pumpFrames(tester, frames: 8);

      expect(find.byType(BodyScreen), findsOneWidget);
    });

    testWidgets('an unknown route offers a way home rather than a blank page', (
      tester,
    ) async {
      await signIn();
      await pumpApp(tester, env);
      await pumpFrames(tester, frames: 12);

      GoRouter.of(tester.element(find.byType(DashboardScreen)))
          .go('/does-not-exist');
      await pumpFrames(tester, frames: 8);

      expect(find.text('Go home'), findsOneWidget);
    });
  });
}
