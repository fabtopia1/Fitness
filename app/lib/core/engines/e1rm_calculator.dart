import 'dart:math' as math;

/// An estimated one-rep-max with an honest confidence label.
class E1rmEstimate {
  const E1rmEstimate({
    required this.value,
    required this.epley,
    required this.brzycki,
    required this.confidence,
    required this.divergencePct,
  });

  /// The reported estimate, in kg.
  final double value;
  final double epley;
  final double brzycki;
  final E1rmConfidence confidence;

  /// How far the two formulas disagree, as a percentage. High divergence is the
  /// signal that the rep count is outside the range either formula models well.
  final double divergencePct;
}

enum E1rmConfidence {
  /// 1–5 reps: both formulas are well validated here.
  high,

  /// 6–12 reps: usable; the formulas begin to diverge.
  moderate,

  /// >12 reps: reported, but flagged. Endurance sets are not a strength test.
  low,
}

/// Estimated one-rep-max and personal-record detection.
///
/// Specification: docs/01-prd.md §6.4 (WORK-09, WORK-10). Mirrored in
/// TypeScript at `functions/src/engines/load/`; validated against the shared
/// fixtures in `test/fixtures/engines/e1rm/`.
abstract final class E1rmCalculator {
  static const String version = 'e1rm-1.0.0';

  /// Epley: `w × (1 + r/30)`. The primary estimate.
  static double epley(double weightKg, int reps) {
    if (reps <= 0 || weightKg <= 0) return 0;
    if (reps == 1) return weightKg;
    return weightKg * (1 + reps / 30);
  }

  /// Brzycki: `w × 36 / (37 − r)`. Used as a cross-check.
  ///
  /// The formula breaks down at 37 reps (division by zero) and behaves
  /// unreasonably as it approaches that, so it is not evaluated above 36.
  static double brzycki(double weightKg, int reps) {
    if (reps <= 0 || weightKg <= 0) return 0;
    if (reps == 1) return weightKg;
    if (reps >= 37) return 0;
    return weightKg * 36 / (37 - reps);
  }

  /// The estimate the app reports, with its confidence.
  ///
  /// Epley is used as the reported value so that the number is stable and
  /// comparable across a user's history; Brzycki informs confidence only.
  static E1rmEstimate estimate(double weightKg, int reps) {
    if (weightKg <= 0 || reps <= 0) {
      return const E1rmEstimate(
        value: 0,
        epley: 0,
        brzycki: 0,
        confidence: E1rmConfidence.low,
        divergencePct: 0,
      );
    }

    final e = epley(weightKg, reps);
    final b = brzycki(weightKg, reps);
    final divergence = b > 0 ? (e - b).abs() / ((e + b) / 2) * 100 : 100.0;

    final confidence = switch (reps) {
      <= 5 => E1rmConfidence.high,
      <= 12 => E1rmConfidence.moderate,
      _ => E1rmConfidence.low,
    };

    return E1rmEstimate(
      value: _round1(e),
      epley: _round1(e),
      brzycki: _round1(b),
      confidence: confidence,
      divergencePct: _round1(divergence),
    );
  }

  /// The load that should produce [targetReps] at the given estimated max.
  /// Used by the plate calculator and by load-scheme prescriptions.
  static double weightForReps(double e1rm, int targetReps) {
    if (e1rm <= 0 || targetReps <= 0) return 0;
    if (targetReps == 1) return e1rm;
    return _round1(e1rm / (1 + targetReps / 30));
  }

  /// Rounds a load to the nearest achievable increment for the equipment.
  static double roundToIncrement(double weightKg, double incrementKg) {
    if (incrementKg <= 0) return weightKg;
    return (weightKg / incrementKg).round() * incrementKg;
  }

  static double _round1(double v) => (v * 10).roundToDouble() / 10;
}

/// The kinds of record LifeDNA detects automatically (docs/01 WORK-10).
enum PrType {
  heaviestWeight('heaviest_weight', 'Heaviest weight'),
  bestE1rm('best_e1rm', 'Best estimated 1RM'),
  maxReps('max_reps', 'Most reps at this load'),
  maxVolume('max_volume', 'Most volume in a session');

  const PrType(this.wire, this.label);
  final String wire;
  final String label;
}

/// A detected personal record, with the previous value so the UI can state the
/// improvement rather than just celebrating a number.
class PersonalRecord {
  const PersonalRecord({
    required this.type,
    required this.exerciseId,
    required this.value,
    required this.unit,
    required this.weightKg,
    required this.reps,
    required this.previousValue,
  });

  final PrType type;
  final String exerciseId;
  final double value;
  final String unit;
  final double weightKg;
  final int reps;
  final double? previousValue;

  double get improvementPct {
    final prev = previousValue;
    if (prev == null || prev <= 0) return 0;
    return ((value - prev) / prev * 100 * 100).roundToDouble() / 100;
  }

  /// The in-session toast copy. Non-blocking, factual, one line.
  String get headline => previousValue == null
      ? '${type.label}: ${_fmt(value)} $unit'
      : '${type.label}: ${_fmt(value)} $unit  ▲ ${improvementPct.toStringAsFixed(1)} %';

  static String _fmt(double v) =>
      v == v.roundToDouble() ? v.toStringAsFixed(0) : v.toStringAsFixed(1);
}

/// The prior bests for one exercise, against which a new set is compared.
class ExerciseBests {
  const ExerciseBests({
    this.heaviestWeightKg,
    this.bestE1rm,
    this.repsAtWeight = const {},
    this.maxSessionVolumeKg,
  });

  final double? heaviestWeightKg;
  final double? bestE1rm;

  /// Best rep count achieved at each load. Keyed by weight in kg.
  final Map<double, int> repsAtWeight;
  final double? maxSessionVolumeKg;
}

/// Detects records produced by a single completed set.
///
/// Warm-up sets never produce records. A set that ties a previous best does not
/// produce a record — only a strict improvement does, so the celebration keeps
/// its meaning.
abstract final class PrDetector {
  static List<PersonalRecord> forSet({
    required String exerciseId,
    required double weightKg,
    required int reps,
    required bool isWarmup,
    required ExerciseBests bests,
  }) {
    if (isWarmup || weightKg <= 0 || reps <= 0) return const [];

    final records = <PersonalRecord>[];

    // 1. Heaviest weight moved for any rep count.
    final prevHeaviest = bests.heaviestWeightKg;
    if (prevHeaviest == null || weightKg > prevHeaviest) {
      records.add(
        PersonalRecord(
          type: PrType.heaviestWeight,
          exerciseId: exerciseId,
          value: weightKg,
          unit: 'kg',
          weightKg: weightKg,
          reps: reps,
          previousValue: prevHeaviest,
        ),
      );
    }

    // 2. Best estimated 1RM.
    final e1rm = E1rmCalculator.estimate(weightKg, reps);
    final prevE1rm = bests.bestE1rm;
    if (e1rm.value > 0 && (prevE1rm == null || e1rm.value > prevE1rm)) {
      records.add(
        PersonalRecord(
          type: PrType.bestE1rm,
          exerciseId: exerciseId,
          value: e1rm.value,
          unit: 'kg',
          weightKg: weightKg,
          reps: reps,
          previousValue: prevE1rm,
        ),
      );
    }

    // 3. Most reps at this exact load.
    final prevReps = bests.repsAtWeight[weightKg];
    if (prevReps != null && reps > prevReps) {
      records.add(
        PersonalRecord(
          type: PrType.maxReps,
          exerciseId: exerciseId,
          value: reps.toDouble(),
          unit: 'reps',
          weightKg: weightKg,
          reps: reps,
          previousValue: prevReps.toDouble(),
        ),
      );
    }

    return records;
  }

  /// Session-level volume record, evaluated once when a session is finalized.
  static PersonalRecord? forSessionVolume({
    required String exerciseId,
    required double sessionVolumeKg,
    required double? previousMax,
  }) {
    if (sessionVolumeKg <= 0) return null;
    if (previousMax != null && sessionVolumeKg <= previousMax) return null;
    return PersonalRecord(
      type: PrType.maxVolume,
      exerciseId: exerciseId,
      value: sessionVolumeKg.roundToDouble(),
      unit: 'kg',
      weightKg: 0,
      reps: 0,
      previousValue: previousMax,
    );
  }
}

/// Progressive-overload readiness (docs/13 rule `PROGRESSIVE_OVERLOAD_READY`).
///
/// Kept here rather than in the insight engine because the Live Gym screen uses
/// it directly to suggest the next load while the user is still at the rack.
abstract final class OverloadAdvisor {
  /// Returns the suggested load increase in kg, or null when the user should
  /// repeat the current load.
  ///
  /// The rule: every target rep completed at RPE ≤ 8 across the last two
  /// sessions means the load is no longer a sufficient stimulus.
  static double? suggestedIncrease({
    required List<SessionPerformance> lastTwoSessions,
    required int targetRepsMin,
    required double incrementKg,
  }) {
    if (lastTwoSessions.length < 2) return null;

    final qualifies = lastTwoSessions.every(
      (s) =>
          s.workingSets.isNotEmpty &&
          s.workingSets.every((set) => set.reps >= targetRepsMin) &&
          s.workingSets.every((set) => (set.rpe ?? 10) <= 8),
    );

    return qualifies ? incrementKg : null;
  }
}

/// A compact view of one session's working sets for a single exercise.
class SessionPerformance {
  const SessionPerformance({required this.workingSets, required this.date});
  final List<({double weightKg, int reps, int? rpe})> workingSets;
  final DateTime date;

  double get volumeKg => workingSets.fold(
        0,
        (sum, s) => sum + s.weightKg * s.reps,
      );

  double get bestE1rm => workingSets.isEmpty
      ? 0
      : workingSets
          .map((s) => E1rmCalculator.epley(s.weightKg, s.reps))
          .reduce(math.max);
}
