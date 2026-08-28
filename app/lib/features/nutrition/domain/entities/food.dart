import 'package:lifedna/shared/enums/enums.dart';
import 'package:lifedna/shared/value_objects/macros.dart';

/// How a portion is expressed. Everything converts to grams for storage, so a
/// food's macros can always be recomputed from a single canonical quantity.
enum PortionUnit {
  grams('g'),
  millilitres('ml'),
  serving('serving'),
  piece('piece');

  const PortionUnit(this.label);
  final String label;
}

/// A named serving, e.g. "1 scoop (30 g)".
class FoodServing {
  const FoodServing({required this.label, required this.grams});
  final String label;
  final double grams;
}

/// Where a food's data came from. Always shown in the UI: community data is
/// frequently wrong, and a user who can see the provenance can correct it.
enum FoodProvider {
  internal('Verified'),
  openFoodFacts('Open Food Facts · community data'),
  userContributed('Your food');

  const FoodProvider(this.label);
  final String label;
}

class Food {
  const Food({
    required this.id,
    required this.name,
    required this.per100g,
    this.brand,
    this.barcodes = const [],
    this.servings = const [],
    this.provider = FoodProvider.internal,
    this.verified = true,
    this.popularity = 0,
  });

  final String id;
  final String name;
  final String? brand;
  final List<String> barcodes;

  /// Canonical macros per 100 g. Every portion derives from this.
  final Macros per100g;
  final List<FoodServing> servings;
  final FoodProvider provider;
  final bool verified;
  final int popularity;

  String get displayName => brand == null ? name : '$name · $brand';

  /// Converts a quantity in [unit] to grams.
  double toGrams(double quantity, PortionUnit unit) => switch (unit) {
        PortionUnit.grams => quantity,
        // 1 ml ≈ 1 g for the aqueous foods this applies to. Foods where this
        // is materially wrong (oils) declare an explicit serving instead.
        PortionUnit.millilitres => quantity,
        PortionUnit.serving =>
          quantity * (servings.isEmpty ? 100 : servings.first.grams),
        PortionUnit.piece =>
          quantity * (servings.isEmpty ? 100 : servings.first.grams),
      };

  /// Macros for a given portion.
  Macros macrosFor(double quantity, PortionUnit unit) =>
      per100g.scaled(toGrams(quantity, unit) / 100);

  /// True when the stated energy disagrees with the Atwater reconstruction.
  bool get hasSuspectData => per100g.isEnergyInconsistent();
}

/// One logged food entry. The additive unit of the nutrition log — never
/// overwritten, only added or removed (docs/02 §7.1).
class NutritionEntry {
  const NutritionEntry({
    required this.id,
    required this.foodId,
    required this.foodName,
    required this.quantity,
    required this.unit,
    required this.gramsEquivalent,
    required this.macros,
    required this.mealSlot,
    required this.loggedAt,
    this.brand,
    this.note,
  });

  final String id;
  final String foodId;
  final String foodName;
  final String? brand;
  final double quantity;
  final PortionUnit unit;
  final double gramsEquivalent;
  final Macros macros;
  final MealSlot mealSlot;
  final DateTime loggedAt;
  final String? note;

  String get portionLabel => unit == PortionUnit.grams
      ? '${quantity.round()} g'
      : '${_trim(quantity)} ${unit.label}';

  static String _trim(double v) =>
      v == v.roundToDouble() ? v.round().toString() : v.toStringAsFixed(1);
}
