import 'package:flutter_test/flutter_test.dart';
import 'package:lifedna/core/data/synced_entity.dart';
import 'package:lifedna/core/error/failure.dart';
import 'package:lifedna/core/sync/outbox.dart';
import 'package:lifedna/features/nutrition/data/nutrition_repository.dart';
import 'package:lifedna/features/nutrition/domain/nutrition_entities.dart';
import 'package:lifedna/shared/enums/enums.dart';
import 'package:lifedna/shared/value_objects/macros.dart';

import '../../../support/test_harness.dart';

void main() {
  late TestEnvironment env;
  late NutritionRepository repository;

  final now = DateTime(2026, 3, 14, 12, 30);
  final today = Json.localDate(now);

  setUp(() async {
    env = await TestEnvironment.create();
    repository = NutritionRepository(
      store: env.store,
      outbox: Outbox(env.store),
      clock: () => now,
    );
  });
  tearDown(() async => env.dispose());

  FoodItem chicken() => repository.createFood(
        name: 'Chicken breast',
        per100g: const Macros(kcal: 165, proteinG: 31, carbsG: 0, fatG: 3.6),
        brand: 'Tesco',
        servingLabel: 'fillet',
        servingGrams: 150,
      );

  group('foods', () {
    test('createFood trims input and derives a display name', () {
      final food = repository.createFood(
        name: '  Oats  ',
        per100g: const Macros(kcal: 379),
        brand: '   ',
      );
      expect(food.name, 'Oats');
      // A blank brand must not become an empty parenthetical in the UI.
      expect(food.brand, isNull);
      expect(food.displayName, 'Oats');
    });

    test('macros scale with the portion', () {
      final food = chicken();
      expect(food.gramsFor(2, PortionUnit.serving), 300);
      expect(food.macrosForGrams(200).proteinG, closeTo(62, 0.001));
    });

    test('search ranks an exact prefix above a contained match', () async {
      await repository.saveFood(
        repository.createFood(name: 'Rice, white', per100g: const Macros()),
      );
      await repository.saveFood(
        repository.createFood(name: 'Fried rice', per100g: const Macros()),
      );

      final results = repository.searchFoods('rice');
      expect(results.first.name, 'Rice, white');
      expect(results, hasLength(2));
    });

    test('search matches a brand and a mid-name token', () async {
      await repository.saveFood(chicken());
      expect(repository.searchFoods('tesco'), hasLength(1));
      expect(repository.searchFoods('breast'), hasLength(1));
      expect(repository.searchFoods('zzz'), isEmpty);
    });

    test('an empty query returns favourites and frequently used first',
        () async {
      final rare = repository.createFood(name: 'Rare', per100g: const Macros());
      final often = repository
          .createFood(name: 'Often', per100g: const Macros())
          .copyWith(useCount: 20);
      final starred = repository
          .createFood(name: 'Starred', per100g: const Macros())
          .copyWith(isFavorite: true);

      await repository.saveFood(rare);
      await repository.saveFood(often);
      await repository.saveFood(starred);

      final results = repository.searchFoods('');
      expect(results.first.name, 'Starred');
      expect(results[1].name, 'Often');
    });

    test('a deleted food disappears from search', () async {
      final food = chicken();
      await repository.saveFood(food);
      await repository.deleteFood(food.id);
      expect(repository.searchFoods('chicken'), isEmpty);
    });
  });

  group('logging food', () {
    test('a logged portion carries the computed macros and the local date',
        () async {
      final food = chicken();
      await repository.saveFood(food);

      final result = await repository.logFood(
        food: food,
        quantity: 200,
        unit: PortionUnit.grams,
        slot: MealSlot.lunch,
      );

      final log = result.valueOrNull!;
      expect(log.grams, 200);
      expect(log.macros.kcal, closeTo(330, 0.001));
      expect(log.localDate, today);
      expect(log.type, NutritionEntryType.food);
      expect(repository.logsForDate(today), hasLength(1));
    });

    test('logging a food raises its use count so search learns', () async {
      final food = chicken();
      await repository.saveFood(food);

      await repository.logFood(
        food: food,
        quantity: 1,
        unit: PortionUnit.serving,
        slot: MealSlot.lunch,
      );

      expect(repository.foods.readOne(food.id)?.useCount, 1);
    });

    test('a non-positive quantity is rejected before it reaches storage',
        () async {
      final result = await repository.logFood(
        food: chicken(),
        quantity: 0,
        unit: PortionUnit.grams,
        slot: MealSlot.lunch,
      );

      expect(
        result.failureOrNull,
        isA<ValidationFailure>()
            .having((f) => f.code, 'code', 'quantity_must_be_positive'),
      );
      expect(repository.logsForDate(today), isEmpty);
    });

    test('an implausible portion is rejected rather than skewing the day',
        () async {
      // 50 servings of a 150 g fillet is 7.5 kg of chicken. A mistyped
      // quantity that reached storage would poison every derived total.
      final result = await repository.logFood(
        food: chicken(),
        quantity: 50,
        unit: PortionUnit.serving,
        slot: MealSlot.dinner,
      );

      expect(
        result.failureOrNull,
        isA<ValidationFailure>()
            .having((f) => f.code, 'code', 'quantity_implausible'),
      );
    });
  });

  group('logging a saved meal', () {
    test('writes one entry per item and counts the meal as used', () async {
      final food = chicken();
      final meal = Meal(
        id: 'm1',
        name: 'Post-workout',
        items: [
          MealItem(
            foodId: food.id,
            foodName: food.displayName,
            grams: 150,
            macros: food.macrosForGrams(150),
          ),
          MealItem(
            foodId: 'rice',
            foodName: 'Rice',
            grams: 200,
            macros: const Macros(kcal: 260, carbsG: 56),
          ),
        ],
        updatedAt: now,
      );
      await repository.saveMeal(meal);

      final result = await repository.logMeal(
        meal: meal,
        slot: MealSlot.postWorkout,
      );

      expect(result.valueOrNull, 2);
      expect(repository.logsForDate(today), hasLength(2));
      expect(repository.meals.readOne('m1')?.useCount, 1);
    });

    test('an empty meal is a validation failure, not a silent no-op', () async {
      final meal = Meal(id: 'm2', name: 'Empty', items: const [], updatedAt: now);
      final result = await repository.logMeal(meal: meal, slot: MealSlot.snack);
      expect(result.failureOrNull, isA<ValidationFailure>());
    });
  });

  group('water', () {
    test('water is a nutrition log, so a day is one query', () async {
      // Water and food share a collection deliberately: the dashboard reads a
      // day's totals with a single pass rather than joining two sources.
      await repository.logWater(500);
      final logs = repository.logsForDate(today);

      expect(logs, hasLength(1));
      expect(logs.single.type, NutritionEntryType.water);
      expect(logs.single.waterMl, 500);
    });

    test('a non-positive volume is rejected', () async {
      final result = await repository.logWater(0);
      expect(result.failureOrNull, isA<ValidationFailure>());
    });
  });

  group('deleting a log', () {
    test('removes it from the day and leaves a replicating tombstone',
        () async {
      final food = chicken();
      await repository.saveFood(food);
      final log = (await repository.logFood(
        food: food,
        quantity: 100,
        unit: PortionUnit.grams,
        slot: MealSlot.lunch,
      ))
          .valueOrNull!;

      await repository.deleteLog(log.id);

      expect(repository.logsForDate(today), isEmpty);
      expect(env.store.read('nutrition_logs', log.id)?['deletedAt'], isNotNull);
    });
  });

  test('logs for a date are ordered by the time they were logged', () async {
    final food = chicken();
    await repository.saveFood(food);

    await repository.logFood(
      food: food,
      quantity: 100,
      unit: PortionUnit.grams,
      slot: MealSlot.breakfast,
      at: DateTime(2026, 3, 14, 8),
    );
    await repository.logFood(
      food: food,
      quantity: 100,
      unit: PortionUnit.grams,
      slot: MealSlot.dinner,
      at: DateTime(2026, 3, 14, 20),
    );

    final logs = repository.logsForDate(today);
    expect(logs.map((l) => l.slot), [MealSlot.breakfast, MealSlot.dinner]);
  });
}
