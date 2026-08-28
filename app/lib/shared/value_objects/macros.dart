import 'dart:math' as math;

/// An immutable macronutrient quantity. The atomic unit of the nutrition module.
///
/// All values are canonical metric: kcal and grams. Conversion to a display unit
/// happens only in the presentation layer.
class Macros {
  const Macros({
    this.kcal = 0,
    this.proteinG = 0,
    this.carbsG = 0,
    this.fatG = 0,
  });

  static const Macros zero = Macros();

  final double kcal;
  final double proteinG;
  final double carbsG;
  final double fatG;

  Macros operator +(Macros other) => Macros(
    kcal: kcal + other.kcal,
    proteinG: proteinG + other.proteinG,
    carbsG: carbsG + other.carbsG,
    fatG: fatG + other.fatG,
  );

  Macros operator -(Macros other) => Macros(
    kcal: kcal - other.kcal,
    proteinG: proteinG - other.proteinG,
    carbsG: carbsG - other.carbsG,
    fatG: fatG - other.fatG,
  );

  /// Scales every component. Used to convert per-100 g values to a portion.
  Macros scaled(double factor) => Macros(
    kcal: kcal * factor,
    proteinG: proteinG * factor,
    carbsG: carbsG * factor,
    fatG: fatG * factor,
  );

  /// Energy reconstructed from the macronutrients using Atwater factors.
  ///
  /// Used to sanity-check imported foods: a large divergence from [kcal]
  /// indicates bad source data, which we surface rather than silently trust.
  double get derivedKcal => proteinG * 4 + carbsG * 4 + fatG * 9;

  /// True when the stated energy and the reconstructed energy disagree by more
  /// than [tolerancePct]. Community food data frequently fails this.
  bool isEnergyInconsistent({double tolerancePct = 15}) {
    if (kcal <= 0) return false;
    final divergence = (derivedKcal - kcal).abs() / kcal * 100;
    return divergence > tolerancePct;
  }

  /// Percentage of energy from each macronutrient. Returns zeros when empty.
  ({double protein, double carbs, double fat}) get energySplit {
    final total = derivedKcal;
    if (total <= 0) return (protein: 0, carbs: 0, fat: 0);
    return (
      protein: proteinG * 4 / total * 100,
      carbs: carbsG * 4 / total * 100,
      fat: fatG * 9 / total * 100,
    );
  }

  Macros rounded() => Macros(
    kcal: kcal.roundToDouble(),
    proteinG: (proteinG * 10).roundToDouble() / 10,
    carbsG: (carbsG * 10).roundToDouble() / 10,
    fatG: (fatG * 10).roundToDouble() / 10,
  );

  Macros copyWith({
    double? kcal,
    double? proteinG,
    double? carbsG,
    double? fatG,
  }) => Macros(
    kcal: kcal ?? this.kcal,
    proteinG: proteinG ?? this.proteinG,
    carbsG: carbsG ?? this.carbsG,
    fatG: fatG ?? this.fatG,
  );

  Map<String, dynamic> toJson() => {
    'kcal': kcal,
    'proteinG': proteinG,
    'carbsG': carbsG,
    'fatG': fatG,
  };

  factory Macros.fromJson(Map<String, dynamic> json) => Macros(
    kcal: (json['kcal'] as num?)?.toDouble() ?? 0,
    proteinG: (json['proteinG'] as num?)?.toDouble() ?? 0,
    carbsG: (json['carbsG'] as num?)?.toDouble() ?? 0,
    fatG: (json['fatG'] as num?)?.toDouble() ?? 0,
  );

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is Macros &&
          other.kcal == kcal &&
          other.proteinG == proteinG &&
          other.carbsG == carbsG &&
          other.fatG == fatG;

  @override
  int get hashCode => Object.hash(kcal, proteinG, carbsG, fatG);

  @override
  String toString() =>
      'Macros(${kcal.round()} kcal, P${proteinG.round()} C${carbsG.round()} '
      'F${fatG.round()})';
}

/// A day's macro targets, plus the protein floor which is deliberately separate
/// from the protein target (docs/01 §6.2 NUTR-09).
///
/// The distinction matters: the *target* is what the plan asks for; the *floor*
/// is the absolute minimum below which lean mass is at risk in a deficit. They
/// are usually equal, but the floor never moves when calories are adjusted.
class MacroTargets {
  const MacroTargets({
    required this.kcal,
    required this.proteinG,
    required this.carbsG,
    required this.fatG,
    required this.proteinFloorG,
  });

  final double kcal;
  final double proteinG;
  final double carbsG;
  final double fatG;
  final double proteinFloorG;

  Macros get asMacros =>
      Macros(kcal: kcal, proteinG: proteinG, carbsG: carbsG, fatG: fatG);

  /// What remains against these targets given [consumed]. Components clamp at
  /// zero — "you are 62 kcal over" is expressed as a separate surplus, not as a
  /// negative remaining value.
  Macros remaining(Macros consumed) => Macros(
    kcal: math.max(0.0, kcal - consumed.kcal),
    proteinG: math.max(0.0, proteinG - consumed.proteinG),
    carbsG: math.max(0.0, carbsG - consumed.carbsG),
    fatG: math.max(0.0, fatG - consumed.fatG),
  );

  /// Grams of protein still owed against the *floor*. This is the number the
  /// dashboard's Next Action card reports.
  double proteinDebt(Macros consumed) =>
      math.max(0.0, proteinFloorG - consumed.proteinG);

  /// Fraction of each target achieved. May exceed 1.0.
  ({double kcal, double protein, double carbs, double fat}) progress(
    Macros consumed,
  ) => (
    kcal: kcal <= 0 ? 0 : consumed.kcal / kcal,
    protein: proteinG <= 0 ? 0 : consumed.proteinG / proteinG,
    carbs: carbsG <= 0 ? 0 : consumed.carbsG / carbsG,
    fat: fatG <= 0 ? 0 : consumed.fatG / fatG,
  );

  /// Adherence as a percentage, where being *at* target scores 100 and
  /// deviation in either direction reduces the score symmetrically.
  double adherencePct(Macros consumed) {
    if (kcal <= 0) return 0;
    final deviation = (consumed.kcal - kcal).abs() / kcal;
    return math.max(0.0, (1 - deviation) * 100);
  }

  MacroTargets copyWith({
    double? kcal,
    double? proteinG,
    double? carbsG,
    double? fatG,
    double? proteinFloorG,
  }) => MacroTargets(
    kcal: kcal ?? this.kcal,
    proteinG: proteinG ?? this.proteinG,
    carbsG: carbsG ?? this.carbsG,
    fatG: fatG ?? this.fatG,
    proteinFloorG: proteinFloorG ?? this.proteinFloorG,
  );

  Map<String, dynamic> toJson() => {
    'kcal': kcal,
    'proteinG': proteinG,
    'carbsG': carbsG,
    'fatG': fatG,
    'proteinFloorG': proteinFloorG,
  };

  factory MacroTargets.fromJson(Map<String, dynamic> json) => MacroTargets(
    kcal: (json['kcal'] as num?)?.toDouble() ?? 0,
    proteinG: (json['proteinG'] as num?)?.toDouble() ?? 0,
    carbsG: (json['carbsG'] as num?)?.toDouble() ?? 0,
    fatG: (json['fatG'] as num?)?.toDouble() ?? 0,
    proteinFloorG: (json['proteinFloorG'] as num?)?.toDouble() ?? 0,
  );

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is MacroTargets &&
          other.kcal == kcal &&
          other.proteinG == proteinG &&
          other.carbsG == carbsG &&
          other.fatG == fatG &&
          other.proteinFloorG == proteinFloorG;

  @override
  int get hashCode => Object.hash(kcal, proteinG, carbsG, fatG, proteinFloorG);
}
