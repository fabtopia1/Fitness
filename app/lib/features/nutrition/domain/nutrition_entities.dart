import 'package:lifedna/core/data/synced_entity.dart';
import 'package:lifedna/shared/enums/enums.dart';
import 'package:lifedna/shared/value_objects/macros.dart';

/// A food item. Firestore: `users/{uid}/foods/{id}`.
///
/// Macros are stored per 100 g so any portion is derivable. Storing per-serving
/// values instead would make a portion change a lossy edit.
class FoodItem implements SyncedEntity {
  const FoodItem({
    required this.id,
    required this.name,
    required this.per100g,
    required this.updatedAt,
    this.brand,
    this.servingLabel,
    this.servingGrams,
    this.isFavorite = false,
    this.useCount = 0,
    this.deletedAt,
  });

  @override
  final String id;
  final String name;
  final String? brand;

  /// Canonical macros per 100 g.
  final Macros per100g;

  /// Optional named serving, e.g. "1 scoop" = 30 g.
  final String? servingLabel;
  final double? servingGrams;

  final bool isFavorite;
  final int useCount;

  @override
  final DateTime updatedAt;
  @override
  final DateTime? deletedAt;

  String get displayName =>
      brand == null || brand!.isEmpty ? name : '$name · $brand';

  Macros macrosForGrams(double grams) => per100g.scaled(grams / 100);

  /// Grams for a quantity expressed in [unit].
  double gramsFor(double quantity, PortionUnit unit) => switch (unit) {
    PortionUnit.grams => quantity,
    PortionUnit.millilitres => quantity,
    PortionUnit.serving => quantity * (servingGrams ?? 100),
  };

  /// True when the stated energy disagrees with the Atwater reconstruction.
  /// Surfaced in the UI so a user can correct bad data rather than trust it.
  bool get hasSuspectEnergy => per100g.isEnergyInconsistent();

  FoodItem copyWith({
    String? name,
    String? brand,
    Macros? per100g,
    String? servingLabel,
    double? servingGrams,
    bool? isFavorite,
    int? useCount,
    DateTime? updatedAt,
    DateTime? deletedAt,
  }) => FoodItem(
    id: id,
    name: name ?? this.name,
    brand: brand ?? this.brand,
    per100g: per100g ?? this.per100g,
    servingLabel: servingLabel ?? this.servingLabel,
    servingGrams: servingGrams ?? this.servingGrams,
    isFavorite: isFavorite ?? this.isFavorite,
    useCount: useCount ?? this.useCount,
    updatedAt: updatedAt ?? DateTime.now().toUtc(),
    deletedAt: deletedAt ?? this.deletedAt,
  );

  @override
  Map<String, dynamic> toJson() => {
    'id': id,
    'name': name,
    'brand': brand,
    'per100g': per100g.toJson(),
    'servingLabel': servingLabel,
    'servingGrams': servingGrams,
    'isFavorite': isFavorite,
    'useCount': useCount,
    'updatedAt': updatedAt.toIso8601String(),
    'deletedAt': deletedAt?.toIso8601String(),
  };

  factory FoodItem.fromJson(Map<String, dynamic> json) => FoodItem(
    id: Json.string(json['id']),
    name: Json.string(json['name']),
    brand: json['brand'] as String?,
    per100g: Macros.fromJson(Json.map(json['per100g'])),
    servingLabel: json['servingLabel'] as String?,
    servingGrams: (json['servingGrams'] as num?)?.toDouble(),
    isFavorite: Json.boolean(json['isFavorite']),
    useCount: Json.integer(json['useCount']),
    updatedAt: Json.date(json['updatedAt'], fallback: DateTime.now()),
    deletedAt: Json.dateOrNull(json['deletedAt']),
  );
}

enum PortionUnit {
  grams('g'),
  millilitres('ml'),
  serving('serving');

  const PortionUnit(this.label);
  final String label;

  static PortionUnit fromWire(String value) => values.firstWhere(
    (u) => u.label == value,
    orElse: () => PortionUnit.grams,
  );
}

/// A saved meal: an ordered set of foods logged together in one tap.
/// Firestore: `users/{uid}/meals/{id}`.
class Meal implements SyncedEntity {
  const Meal({
    required this.id,
    required this.name,
    required this.items,
    required this.updatedAt,
    this.slot,
    this.useCount = 0,
    this.deletedAt,
  });

  @override
  final String id;
  final String name;
  final List<MealItem> items;
  final MealSlot? slot;
  final int useCount;

  @override
  final DateTime updatedAt;
  @override
  final DateTime? deletedAt;

  Macros get totals =>
      items.fold(Macros.zero, (sum, item) => sum + item.macros);

  Meal copyWith({
    String? name,
    List<MealItem>? items,
    MealSlot? slot,
    int? useCount,
    DateTime? updatedAt,
    DateTime? deletedAt,
  }) => Meal(
    id: id,
    name: name ?? this.name,
    items: items ?? this.items,
    slot: slot ?? this.slot,
    useCount: useCount ?? this.useCount,
    updatedAt: updatedAt ?? DateTime.now().toUtc(),
    deletedAt: deletedAt ?? this.deletedAt,
  );

  @override
  Map<String, dynamic> toJson() => {
    'id': id,
    'name': name,
    'slot': slot?.wire,
    'items': items.map((i) => i.toJson()).toList(),
    'useCount': useCount,
    'updatedAt': updatedAt.toIso8601String(),
    'deletedAt': deletedAt?.toIso8601String(),
  };

  factory Meal.fromJson(Map<String, dynamic> json) => Meal(
    id: Json.string(json['id']),
    name: Json.string(json['name']),
    slot: json['slot'] == null
        ? null
        : MealSlot.fromWire(Json.string(json['slot'])),
    items: (json['items'] as List? ?? const [])
        .map((e) => MealItem.fromJson(Json.map(e)))
        .toList(),
    useCount: Json.integer(json['useCount']),
    updatedAt: Json.date(json['updatedAt'], fallback: DateTime.now()),
    deletedAt: Json.dateOrNull(json['deletedAt']),
  );
}

/// One food inside a saved meal. Denormalised name and macros so rendering a
/// meal never needs N food lookups, and so a meal stays correct if the
/// underlying food is later edited.
class MealItem {
  const MealItem({
    required this.foodId,
    required this.foodName,
    required this.grams,
    required this.macros,
  });

  final String foodId;
  final String foodName;
  final double grams;
  final Macros macros;

  Map<String, dynamic> toJson() => {
    'foodId': foodId,
    'foodName': foodName,
    'grams': grams,
    'macros': macros.toJson(),
  };

  factory MealItem.fromJson(Map<String, dynamic> json) => MealItem(
    foodId: Json.string(json['foodId']),
    foodName: Json.string(json['foodName']),
    grams: Json.number(json['grams']),
    macros: Macros.fromJson(Json.map(json['macros'])),
  );
}

enum NutritionEntryType { food, water }

/// One logged entry. Firestore: `users/{uid}/nutrition_logs/{id}`.
///
/// Food and water share this collection, discriminated by [type]. One
/// collection means one index and one sync path, and a day's totals come from
/// a single query rather than a join across two.
class NutritionLog implements SyncedEntity {
  const NutritionLog({
    required this.id,
    required this.type,
    required this.loggedAt,
    required this.localDate,
    required this.updatedAt,
    this.foodId,
    this.foodName = '',
    this.grams = 0,
    this.quantity = 0,
    this.unit = PortionUnit.grams,
    this.macros = Macros.zero,
    this.slot = MealSlot.snack,
    this.waterMl = 0,
    this.mealId,
    this.deletedAt,
  });

  @override
  final String id;
  final NutritionEntryType type;

  final String? foodId;
  final String foodName;
  final double grams;
  final double quantity;
  final PortionUnit unit;
  final Macros macros;
  final MealSlot slot;

  /// Set only when [type] is water.
  final int waterMl;

  /// Set when the entry came from applying a saved meal.
  final String? mealId;

  final DateTime loggedAt;

  /// `yyyy-MM-dd` in the user's local timezone at write time. Travelling
  /// across timezones must not move yesterday's dinner into today.
  final String localDate;

  @override
  final DateTime updatedAt;
  @override
  final DateTime? deletedAt;

  bool get isFood => type == NutritionEntryType.food;
  bool get isWater => type == NutritionEntryType.water;

  String get portionLabel => unit == PortionUnit.grams
      ? '${grams.round()} g'
      : '${_trim(quantity)} ${unit.label}';

  static String _trim(double v) =>
      v == v.roundToDouble() ? v.round().toString() : v.toStringAsFixed(1);

  NutritionLog copyWith({
    double? grams,
    double? quantity,
    Macros? macros,
    MealSlot? slot,
    int? waterMl,
    DateTime? updatedAt,
    DateTime? deletedAt,
  }) => NutritionLog(
    id: id,
    type: type,
    foodId: foodId,
    foodName: foodName,
    grams: grams ?? this.grams,
    quantity: quantity ?? this.quantity,
    unit: unit,
    macros: macros ?? this.macros,
    slot: slot ?? this.slot,
    waterMl: waterMl ?? this.waterMl,
    mealId: mealId,
    loggedAt: loggedAt,
    localDate: localDate,
    updatedAt: updatedAt ?? DateTime.now().toUtc(),
    deletedAt: deletedAt ?? this.deletedAt,
  );

  @override
  Map<String, dynamic> toJson() => {
    'id': id,
    'type': type.name,
    'foodId': foodId,
    'foodName': foodName,
    'grams': grams,
    'quantity': quantity,
    'unit': unit.label,
    'macros': macros.toJson(),
    'slot': slot.wire,
    'waterMl': waterMl,
    'mealId': mealId,
    'loggedAt': loggedAt.toIso8601String(),
    'localDate': localDate,
    'updatedAt': updatedAt.toIso8601String(),
    'deletedAt': deletedAt?.toIso8601String(),
  };

  factory NutritionLog.fromJson(Map<String, dynamic> json) => NutritionLog(
    id: Json.string(json['id']),
    type: NutritionEntryType.values.firstWhere(
      (t) => t.name == json['type'],
      orElse: () => NutritionEntryType.food,
    ),
    foodId: json['foodId'] as String?,
    foodName: Json.string(json['foodName']),
    grams: Json.number(json['grams']),
    quantity: Json.number(json['quantity']),
    unit: PortionUnit.fromWire(Json.string(json['unit'], 'g')),
    macros: Macros.fromJson(Json.map(json['macros'])),
    slot: MealSlot.fromWire(Json.string(json['slot'], 'snack')),
    waterMl: Json.integer(json['waterMl']),
    mealId: json['mealId'] as String?,
    loggedAt: Json.date(json['loggedAt'], fallback: DateTime.now()),
    localDate: Json.string(json['localDate']),
    updatedAt: Json.date(json['updatedAt'], fallback: DateTime.now()),
    deletedAt: Json.dateOrNull(json['deletedAt']),
  );
}

/// A day's nutrition, assembled from logs. Not persisted — derived, so it can
/// never disagree with the entries it summarises.
class DailyNutrition {
  const DailyNutrition({
    required this.localDate,
    required this.entries,
    required this.targets,
  });

  final String localDate;
  final List<NutritionLog> entries;
  final MacroTargets targets;

  Iterable<NutritionLog> get foodEntries => entries.where((e) => e.isFood);

  Macros get totals =>
      foodEntries.fold(Macros.zero, (sum, e) => sum + e.macros);

  int get waterMl =>
      entries.where((e) => e.isWater).fold(0, (sum, e) => sum + e.waterMl);

  List<NutritionLog> forSlot(MealSlot slot) =>
      foodEntries.where((e) => e.slot == slot).toList()
        ..sort((a, b) => a.loggedAt.compareTo(b.loggedAt));

  Macros totalsForSlot(MealSlot slot) =>
      forSlot(slot).fold(Macros.zero, (sum, e) => sum + e.macros);

  Set<MealSlot> get loggedSlots => {for (final e in foodEntries) e.slot};

  bool get isEmpty => entries.isEmpty;
}
