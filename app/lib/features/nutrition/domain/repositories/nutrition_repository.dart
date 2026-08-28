import 'package:lifedna/core/errors/failure.dart';
import 'package:lifedna/core/result/result.dart';
import 'package:lifedna/features/nutrition/domain/entities/food.dart';
import 'package:lifedna/shared/enums/enums.dart';
import 'package:lifedna/shared/value_objects/macros.dart';

/// A day's nutrition, as the presentation layer consumes it.
class DailyNutrition {
  const DailyNutrition({
    required this.date,
    required this.entries,
    required this.waterMl,
    required this.dayType,
  });

  final DateTime date;
  final List<NutritionEntry> entries;
  final int waterMl;
  final DayType dayType;

  Macros get totals =>
      entries.fold(Macros.zero, (sum, e) => sum + e.macros);

  List<NutritionEntry> forSlot(MealSlot slot) =>
      [for (final e in entries) if (e.mealSlot == slot) e];

  Macros totalsForSlot(MealSlot slot) =>
      forSlot(slot).fold(Macros.zero, (sum, e) => sum + e.macros);

  Set<MealSlot> get loggedSlots => {for (final e in entries) e.mealSlot};
}

/// The nutrition contract. Pure domain — the implementation chooses between
/// local cache, Firestore and the callable API without the caller knowing.
abstract interface class NutritionRepository {
  Stream<DailyNutrition> watchDay(DateTime date);

  Future<Result<NutritionEntry, Failure>> logEntry({
    required Food food,
    required double quantity,
    required PortionUnit unit,
    required MealSlot slot,
    DateTime? at,
  });

  Future<Result<void, Failure>> deleteEntry(String entryId);

  Future<Result<void, Failure>> logWater(int ml, {DateTime? at});

  Future<List<Food>> searchFoods(String query);

  Future<Food?> lookupBarcode(String barcode);

  /// The user's most recently logged distinct foods, newest first.
  Future<List<Food>> recentFoods({int limit = 20});
}
