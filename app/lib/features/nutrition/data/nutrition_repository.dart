import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:lifedna/core/data/synced_collection.dart';
import 'package:lifedna/core/data/synced_entity.dart';
import 'package:lifedna/core/error/failure.dart';
import 'package:lifedna/core/result/result.dart';
import 'package:lifedna/core/storage/hive_store.dart';
import 'package:lifedna/core/sync/outbox.dart';
import 'package:lifedna/features/nutrition/domain/nutrition_entities.dart';
import 'package:lifedna/shared/enums/enums.dart';
import 'package:lifedna/shared/value_objects/macros.dart';
import 'package:uuid/uuid.dart';

class NutritionRepository {
  NutritionRepository({
    required HiveStore store,
    required Outbox outbox,
    FirebaseFirestore? firestore,
    String? uid,
    Uuid uuid = const Uuid(),
    DateTime Function()? clock,
  })  : _uuid = uuid,
        _clock = clock ?? DateTime.now,
        foods = SyncedCollection<FoodItem>(
          store: store,
          outbox: outbox,
          boxName: HiveStore.boxFoods,
          collection: 'foods',
          fromJson: FoodItem.fromJson,
          firestore: firestore,
          uid: uid,
        ),
        meals = SyncedCollection<Meal>(
          store: store,
          outbox: outbox,
          boxName: HiveStore.boxMeals,
          collection: 'meals',
          fromJson: Meal.fromJson,
          firestore: firestore,
          uid: uid,
        ),
        logs = SyncedCollection<NutritionLog>(
          store: store,
          outbox: outbox,
          boxName: HiveStore.boxNutritionLogs,
          collection: 'nutrition_logs',
          fromJson: NutritionLog.fromJson,
          firestore: firestore,
          uid: uid,
        );

  final Uuid _uuid;
  final DateTime Function() _clock;

  final SyncedCollection<FoodItem> foods;
  final SyncedCollection<Meal> meals;
  final SyncedCollection<NutritionLog> logs;

  // ------------------------------------------------------------------ foods --

  Stream<List<FoodItem>> watchFoods() => foods.watchAll();

  /// Ranked local search. Exact prefix beats a contained match, and a food the
  /// user actually eats beats one they do not.
  List<FoodItem> searchFoods(String query, {int limit = 40}) {
    final q = query.trim().toLowerCase();
    final all = foods.readAll();
    if (q.isEmpty) {
      all.sort((a, b) {
        if (a.isFavorite != b.isFavorite) return a.isFavorite ? -1 : 1;
        return b.useCount.compareTo(a.useCount);
      });
      return all.take(limit).toList();
    }

    final scored = <({FoodItem food, int score})>[];
    for (final food in all) {
      final name = food.name.toLowerCase();
      final brand = food.brand?.toLowerCase() ?? '';
      int score;
      if (name.startsWith(q)) {
        score = 1000;
      } else if (name.contains(q)) {
        score = 600;
      } else if (brand.contains(q)) {
        score = 400;
      } else if (name.split(RegExp(r'[\s,]+')).any((t) => t.startsWith(q))) {
        score = 300;
      } else {
        continue;
      }
      scored.add((food: food, score: score + food.useCount));
    }
    scored.sort((a, b) => b.score.compareTo(a.score));
    return [for (final s in scored.take(limit)) s.food];
  }

  Future<Result<FoodItem>> saveFood(FoodItem food) => foods.put(food);

  Future<Result<void>> deleteFood(String id) => foods.remove(
        id,
        tombstone: (f) => f.copyWith(deletedAt: _clock().toUtc()),
      );

  FoodItem createFood({
    required String name,
    required Macros per100g,
    String? brand,
    String? servingLabel,
    double? servingGrams,
  }) =>
      FoodItem(
        id: _uuid.v4(),
        name: name.trim(),
        brand: brand?.trim().isEmpty ?? true ? null : brand!.trim(),
        per100g: per100g,
        servingLabel: servingLabel,
        servingGrams: servingGrams,
        updatedAt: _clock().toUtc(),
      );

  // ------------------------------------------------------------------ meals --

  Stream<List<Meal>> watchMeals() => meals.watchAll();

  Future<Result<Meal>> saveMeal(Meal meal) => meals.put(meal);

  Future<Result<void>> deleteMeal(String id) => meals.remove(
        id,
        tombstone: (m) => m.copyWith(deletedAt: _clock().toUtc()),
      );

  // ------------------------------------------------------------------- logs --

  Stream<List<NutritionLog>> watchLogs() => logs.watchAll();

  List<NutritionLog> logsForDate(String localDate) => logs
      .readAll()
      .where((log) => log.localDate == localDate)
      .toList()
    ..sort((a, b) => a.loggedAt.compareTo(b.loggedAt));

  /// Logs a food portion. Validates before writing so an impossible entry can
  /// never reach storage and corrupt a day's totals.
  Future<Result<NutritionLog>> logFood({
    required FoodItem food,
    required double quantity,
    required PortionUnit unit,
    required MealSlot slot,
    DateTime? at,
  }) async {
    if (quantity <= 0) {
      return const Err(ValidationFailure('quantity_must_be_positive'));
    }
    final grams = food.gramsFor(quantity, unit);
    if (grams > 5000) {
      return const Err(ValidationFailure('quantity_implausible'));
    }

    final when = at ?? _clock();
    final entry = NutritionLog(
      id: _uuid.v4(),
      type: NutritionEntryType.food,
      foodId: food.id,
      foodName: food.displayName,
      grams: grams,
      quantity: quantity,
      unit: unit,
      macros: food.macrosForGrams(grams),
      slot: slot,
      loggedAt: when.toUtc(),
      localDate: Json.localDate(when),
      updatedAt: when.toUtc(),
    );

    final result = await logs.put(entry);
    if (result.isOk) {
      // Usage count drives search ranking, so the foods a user actually eats
      // surface first without them having to favourite anything.
      await foods.put(food.copyWith(useCount: food.useCount + 1));
    }
    return result;
  }

  /// Applies a saved meal, writing one entry per item.
  Future<Result<int>> logMeal({
    required Meal meal,
    required MealSlot slot,
    DateTime? at,
  }) async {
    if (meal.items.isEmpty) {
      return const Err(ValidationFailure('required', field: 'items'));
    }
    final when = at ?? _clock();
    var written = 0;

    for (final item in meal.items) {
      final entry = NutritionLog(
        id: _uuid.v4(),
        type: NutritionEntryType.food,
        foodId: item.foodId,
        foodName: item.foodName,
        grams: item.grams,
        quantity: item.grams,
        macros: item.macros,
        slot: slot,
        mealId: meal.id,
        loggedAt: when.toUtc(),
        localDate: Json.localDate(when),
        updatedAt: when.toUtc(),
      );
      final result = await logs.put(entry);
      if (result.isOk) written++;
    }

    await meals.put(meal.copyWith(useCount: meal.useCount + 1));
    return Ok(written);
  }

  Future<Result<NutritionLog>> logWater(int ml, {DateTime? at}) async {
    if (ml <= 0) {
      return const Err(ValidationFailure('quantity_must_be_positive'));
    }
    final when = at ?? _clock();
    final entry = NutritionLog(
      id: _uuid.v4(),
      type: NutritionEntryType.water,
      waterMl: ml,
      loggedAt: when.toUtc(),
      localDate: Json.localDate(when),
      updatedAt: when.toUtc(),
    );
    return logs.put(entry);
  }

  Future<Result<void>> deleteLog(String id) => logs.remove(
        id,
        tombstone: (l) => l.copyWith(deletedAt: _clock().toUtc()),
      );

  Future<Result<int>> pullAll() async {
    final results = await Future.wait([
      foods.pull(),
      meals.pull(),
      logs.pull(),
    ]);
    var total = 0;
    for (final result in results) {
      if (result.isErr) return result;
      total += result.valueOrNull ?? 0;
    }
    return Ok(total);
  }
}
