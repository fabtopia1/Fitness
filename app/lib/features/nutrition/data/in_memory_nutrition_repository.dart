import 'dart:async';

import 'package:lifedna/core/data/reference_catalog.dart';
import 'package:lifedna/core/errors/failure.dart';
import 'package:lifedna/core/result/result.dart';
import 'package:lifedna/core/utils/id_generator.dart';
import 'package:lifedna/features/nutrition/domain/entities/food.dart';
import 'package:lifedna/features/nutrition/domain/repositories/nutrition_repository.dart';
import 'package:lifedna/shared/enums/enums.dart';

/// Local-authoritative nutrition store.
///
/// This is the reference implementation of the offline-first write path from
/// docs/02 §7: the write commits locally and synchronously, the UI updates
/// immediately, and remote replication is a later concern. Substituting Drift
/// for the maps below and adding an outbox enqueue is the whole production
/// change — the contract above it does not move.
class InMemoryNutritionRepository implements NutritionRepository {
  InMemoryNutritionRepository({DateTime Function()? clock, IdGenerator? ids})
      : _clock = clock ?? DateTime.now,
        _ids = ids ?? const IdGenerator();

  final DateTime Function() _clock;
  final IdGenerator _ids;

  final Map<String, List<NutritionEntry>> _entriesByDate = {};
  final Map<String, int> _waterByDate = {};
  final List<String> _recentFoodIds = [];
  final _controller = StreamController<DailyNutrition>.broadcast();

  DateTime? _watching;

  static String _key(DateTime d) =>
      '${d.year}-${d.month.toString().padLeft(2, '0')}-'
      '${d.day.toString().padLeft(2, '0')}';

  @override
  Stream<DailyNutrition> watchDay(DateTime date) {
    _watching = date;
    // Emit the current value immediately — a screen must never wait on the
    // network to show data it already has.
    scheduleMicrotask(() => _emit(date));
    return _controller.stream.where((d) => _key(d.date) == _key(date));
  }

  void _emit(DateTime date) {
    if (_controller.isClosed) return;
    _controller.add(_snapshot(date));
  }

  DailyNutrition _snapshot(DateTime date) {
    final key = _key(date);
    return DailyNutrition(
      date: date,
      entries: List.unmodifiable(_entriesByDate[key] ?? const []),
      waterMl: _waterByDate[key] ?? 0,
      dayType: _dayTypeFor(date),
    );
  }

  /// Day type follows the active program's weekly split, not a manual toggle.
  static DayType _dayTypeFor(DateTime date) {
    final slot = ReferenceCatalog.weeklySplit[date.weekday];
    return slot == null || slot.templateId == null
        ? DayType.rest
        : DayType.training;
  }

  DailyNutrition snapshot(DateTime date) => _snapshot(date);

  @override
  Future<Result<NutritionEntry, Failure>> logEntry({
    required Food food,
    required double quantity,
    required PortionUnit unit,
    required MealSlot slot,
    DateTime? at,
  }) async {
    if (quantity <= 0) {
      return const Err(ValidationFailure('quantity_must_be_positive'));
    }
    final grams = food.toGrams(quantity, unit);
    if (grams > 5000) {
      return const Err(ValidationFailure('quantity_implausible'));
    }

    final loggedAt = at ?? _clock();
    final entry = NutritionEntry(
      id: _ids.v7(),
      foodId: food.id,
      foodName: food.name,
      brand: food.brand,
      quantity: quantity,
      unit: unit,
      gramsEquivalent: grams,
      macros: food.macrosFor(quantity, unit),
      mealSlot: slot,
      loggedAt: loggedAt,
    );

    final key = _key(loggedAt);
    (_entriesByDate[key] ??= []).add(entry);

    _recentFoodIds
      ..remove(food.id)
      ..insert(0, food.id);

    _emit(_watching ?? loggedAt);
    return Ok(entry);
  }

  @override
  Future<Result<void, Failure>> deleteEntry(String entryId) async {
    for (final entry in _entriesByDate.entries) {
      final removed = entry.value.indexWhere((e) => e.id == entryId);
      if (removed >= 0) {
        entry.value.removeAt(removed);
        _emit(_watching ?? _clock());
        return const Ok(null);
      }
    }
    return const Err(NotFoundFailure('entry_not_found'));
  }

  @override
  Future<Result<void, Failure>> logWater(int ml, {DateTime? at}) async {
    if (ml <= 0) return const Err(ValidationFailure('quantity_must_be_positive'));
    final when = at ?? _clock();
    final key = _key(when);
    _waterByDate[key] = (_waterByDate[key] ?? 0) + ml;
    _emit(_watching ?? when);
    return const Ok(null);
  }

  @override
  Future<List<Food>> searchFoods(String query) async =>
      ReferenceCatalog.searchFoods(query);

  @override
  Future<Food?> lookupBarcode(String barcode) async =>
      ReferenceCatalog.foodByBarcode(barcode);

  @override
  Future<List<Food>> recentFoods({int limit = 20}) async => [
        for (final id in _recentFoodIds.take(limit))
          if (ReferenceCatalog.foodById(id) case final f?) f,
      ];

  void dispose() => _controller.close();
}
