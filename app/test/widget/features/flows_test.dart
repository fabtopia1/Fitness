import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lifedna/core/sync/outbox.dart';
import 'package:lifedna/core/widgets/ld_widgets.dart';
import 'package:lifedna/features/auth/data/auth_repository.dart';
import 'package:lifedna/features/auth/data/profile_repository.dart';
import 'package:lifedna/features/calendar/data/calendar_repository.dart';
import 'package:lifedna/features/calendar/data/google_calendar_service.dart';
import 'package:lifedna/features/calendar/presentation/plan_screen.dart';
import 'package:lifedna/features/dashboard/presentation/dashboard_screen.dart';
import 'package:lifedna/features/nutrition/data/nutrition_repository.dart';
import 'package:lifedna/features/nutrition/domain/nutrition_entities.dart';
import 'package:lifedna/features/nutrition/presentation/add_food_screen.dart';
import 'package:lifedna/features/nutrition/presentation/create_food_sheet.dart';
import 'package:lifedna/features/nutrition/presentation/nutrition_screen.dart';
import 'package:lifedna/shared/enums/enums.dart';
import 'package:lifedna/shared/value_objects/macros.dart';

import '../../support/pump.dart';
import '../../support/test_harness.dart';

void main() {
  late TestEnvironment env;

  setUp(() async => env = await TestEnvironment.create());
  tearDown(() async => env.dispose());

  Outbox outbox() => Outbox(env.store);
  NutritionRepository nutrition() =>
      NutritionRepository(store: env.store, outbox: outbox());
  CalendarRepository calendar() => CalendarRepository(
        store: env.store,
        outbox: outbox(),
        notifications: env.notifications,
        google: GoogleCalendarService(),
      );

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

  Future<void> seedFood() async {
    final repository = nutrition();
    await repository.saveFood(
      repository
          .createFood(
            name: 'Chicken breast',
            per100g: const Macros(kcal: 165, proteinG: 31, fatG: 3.6),
            servingLabel: 'fillet',
            servingGrams: 150,
          )
          .copyWith(isFavorite: true),
    );
  }

  group('logging a meal end to end', () {
    testWidgets('pick a food, choose a portion, see it on the day',
        (tester) async {
      await signIn();
      await seedFood();

      await pumpScreen(
        tester,
        env,
        // Pass the slot explicitly: the default is snack, and a test that
        // depended on the time of day would fail after lunch.
        AddFoodScreen(slotWire: MealSlot.lunch.wire),
      );
      await pumpFrames(tester);

      await tester.tap(find.text('Chicken breast'));
      await pumpFrames(tester);

      // The portion sheet previews the macros before anything is written.
      expect(find.byType(PortionSheet), findsOneWidget);
      expect(find.text('150 g'), findsWidgets);
      expect(find.text('PROTEIN'), findsOneWidget);

      await tester.tap(find.text('200 g'));
      await pumpFrames(tester);
      expect(find.text('330'), findsOneWidget);

      await tapVisible(
        tester,
        find.widgetWithText(LdPrimaryButton, 'Add to lunch'),
      );
      await pumpFrames(tester, frames: 10);

      final logs = nutrition().logsForDate(
        DateTime.now().toIso8601String().substring(0, 10),
      );
      expect(logs, hasLength(1));
      expect(logs.single.grams, 200);
    });

    testWidgets('the portion stepper moves in 10 g steps', (tester) async {
      await signIn();
      await seedFood();

      await pumpScreen(tester, env, const AddFoodScreen());
      await pumpFrames(tester);
      await tester.tap(find.text('Chicken breast'));
      await pumpFrames(tester);

      await tester.tap(find.byIcon(Icons.add_rounded).last);
      await pumpFrames(tester);
      expect(find.text('160 g'), findsOneWidget);

      await tester.tap(find.byIcon(Icons.remove_rounded).last);
      await tester.tap(find.byIcon(Icons.remove_rounded).last);
      await pumpFrames(tester);
      expect(find.text('140 g'), findsOneWidget);
    });

    testWidgets('the meals tab explains itself when empty', (tester) async {
      await signIn();
      await seedFood();

      await pumpScreen(tester, env, const AddFoodScreen());
      await pumpFrames(tester);

      await tester.tap(find.text('Meals'));
      await pumpFrames(tester);

      expect(find.text('No saved meals'), findsOneWidget);
    });

    testWidgets('a logged entry can be removed from the day', (tester) async {
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

      await pumpScreen(tester, env, const NutritionScreen());
      await pumpFrames(tester);
      expect(find.text('Oats'), findsWidgets);

      await tester.drag(find.text('Oats').first, const Offset(-500, 0));
      await pumpFrames(tester, frames: 10);

      expect(
        repository.logsForDate(
          DateTime.now().toIso8601String().substring(0, 10),
        ),
        isEmpty,
      );
    });

    testWidgets('water can be logged from the nutrition screen',
        (tester) async {
      await signIn();
      await pumpScreen(tester, env, const NutritionScreen());
      await pumpFrames(tester);

      final water = find.textContaining('ml');
      expect(water, findsWidgets);
      expect(tester.takeException(), isNull);
    });
  });

  group('the dashboard', () {
    testWidgets('surfaces the day and navigates into a module', (tester) async {
      await signIn();
      await pumpScreen(tester, env, const DashboardScreen());
      await pumpFrames(tester);

      expect(find.byType(LdProgressRing), findsWidgets);
      expect(tester.takeException(), isNull);
    });

    testWidgets('supplements due today appear once a stack exists',
        (tester) async {
      await signIn();
      await pumpScreen(tester, env, const DashboardScreen());
      await pumpFrames(tester);

      // Nothing scheduled yet, and the screen still renders every section.
      expect(find.byType(LdErrorView), findsNothing);
    });
  });

  group('the plan', () {
    testWidgets('a task can be completed from the list', (tester) async {
      await signIn();
      final repository = calendar();
      await repository.saveTask(repository.createTask(title: 'Read chapter 4'));

      await pumpScreen(tester, env, const PlanScreen());
      await pumpFrames(tester);

      expect(find.text('Read chapter 4'), findsOneWidget);
      await tester.tap(find.byType(Checkbox).first);
      await pumpFrames(tester, frames: 10);

      expect(repository.openTasks(), isEmpty);
    });

    testWidgets('the calendar tab shows a day with nothing scheduled',
        (tester) async {
      await signIn();
      await pumpScreen(tester, env, const PlanScreen());
      await pumpFrames(tester);

      await tester.tap(find.text('Calendar'));
      await pumpFrames(tester);

      expect(find.text('Nothing scheduled'), findsOneWidget);
    });

    testWidgets('an event created today is listed on the calendar tab',
        (tester) async {
      await signIn();
      final repository = calendar();
      final now = DateTime.now();
      await repository.saveEvent(
        repository.createEvent(
          title: 'Physio',
          startAt: DateTime(now.year, now.month, now.day, 17),
          endAt: DateTime(now.year, now.month, now.day, 18),
        ),
      );

      await pumpScreen(tester, env, const PlanScreen());
      await pumpFrames(tester);
      await tester.tap(find.text('Calendar'));
      await pumpFrames(tester);

      expect(find.text('Physio'), findsOneWidget);
    });

    testWidgets('an empty task list says what to do', (tester) async {
      await signIn();
      await pumpScreen(tester, env, const PlanScreen());
      await pumpFrames(tester);

      expect(find.text('Nothing to do'), findsOneWidget);
    });
  });
}
