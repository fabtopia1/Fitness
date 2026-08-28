import 'dart:math' as math;

/// One day's training load, the unit the load model operates on.
class DailyLoad {
  const DailyLoad({required this.date, required this.load});
  final DateTime date;

  /// `sessionRPE × durationMinutes`. Zero on a rest day.
  final double load;
}

/// Acute and chronic training load, and the ratio between them.
class LoadSummary {
  const LoadSummary({
    required this.acute,
    required this.chronic,
    required this.acwr,
    required this.meanDailyLoad28d,
    required this.hasSufficientHistory,
  });

  final double acute;
  final double chronic;

  /// Acute:chronic workload ratio. Null when chronic load is zero — a new user
  /// has no meaningful ratio, and reporting 0 or infinity would be a lie.
  final double? acwr;

  final double meanDailyLoad28d;

  /// False until there is enough history for the chronic window to mean
  /// anything (14 days). Consumers must degrade rather than trust the number.
  final bool hasSufficientHistory;
}

/// Training-load modelling.
///
/// Specification: docs/12-recovery-engine.md §5. Exponentially weighted rather
/// than a flat rolling mean, so that a session three days ago carries more
/// weight than one from seven days ago — which is how fatigue actually decays.
abstract final class LoadEngine {
  static const String version = 'load-1.0.0';

  static const double acuteHalfLifeDays = 3.5;
  static const double chronicHalfLifeDays = 14.0;
  static const int minDaysForChronic = 14;

  /// Session load from the whole-session RPE and duration.
  ///
  /// Session-RPE × duration is the best-validated field measure of internal
  /// load, and it costs the user exactly one tap at the end of a session.
  static double sessionLoad({
    required int sessionRpe,
    required int durationMinutes,
  }) {
    if (sessionRpe <= 0 || durationMinutes <= 0) return 0;
    return sessionRpe.toDouble() * durationMinutes;
  }

  /// Estimates a session RPE when the user did not provide one.
  ///
  /// Uses the mean set RPE, adjusted by how far the working-set count deviates
  /// from a typical session. Clamped to the valid RPE range.
  static int estimateSessionRpe({
    required double? avgSetRpe,
    required int workingSets,
  }) {
    final base = avgSetRpe ?? 7.5;
    final volumeFactor = ((workingSets - 18) / 12).clamp(-1.0, 1.5);
    final estimate = 5 + (base - 7) * 1.2 + volumeFactor;
    return estimate.clamp(4.0, 10.0).round();
  }

  /// Computes acute (≈7-day) and chronic (≈28-day) load from a daily series.
  ///
  /// [days] must be ordered oldest-first and should include zero-load rest
  /// days — omitting them would overstate both windows.
  static LoadSummary summarize(List<DailyLoad> days) {
    if (days.isEmpty) {
      return const LoadSummary(
        acute: 0,
        chronic: 0,
        acwr: null,
        meanDailyLoad28d: 0,
        hasSufficientHistory: false,
      );
    }

    final acute = _ewma(days, acuteHalfLifeDays);
    final chronic = _ewma(days, chronicHalfLifeDays);

    final window28 = days.length <= 28 ? days : days.sublist(days.length - 28);
    final mean28 = window28.isEmpty
        ? 0.0
        : window28.fold<double>(0, (s, d) => s + d.load) / window28.length;

    final sufficient = days.length >= minDaysForChronic;
    final acwr = (chronic > 0 && sufficient) ? _round3(acute / chronic) : null;

    return LoadSummary(
      acute: _round1(acute),
      chronic: _round1(chronic),
      acwr: acwr,
      meanDailyLoad28d: _round1(mean28),
      hasSufficientHistory: sufficient,
    );
  }

  /// Exponentially weighted moving average over the series, weighting the most
  /// recent day highest. Expressed as a per-day load, comparable across windows.
  static double _ewma(List<DailyLoad> days, double halfLifeDays) {
    if (days.isEmpty) return 0;
    final lambda = math.ln2 / halfLifeDays;

    var weightedSum = 0.0;
    var weightTotal = 0.0;
    final last = days.length - 1;

    for (var i = 0; i < days.length; i++) {
      final ageDays = (last - i).toDouble();
      final weight = math.exp(-lambda * ageDays);
      weightedSum += days[i].load * weight;
      weightTotal += weight;
    }

    if (weightTotal == 0) return 0;

    // Scale the per-day mean to a window total so acute and chronic are on the
    // same footing as the thresholds in docs/12 §5.3.
    final perDay = weightedSum / weightTotal;
    return perDay * 7;
  }

  /// Weekly working-set count per muscle, used against the volume landmarks.
  static Map<String, int> weeklySetsByMuscle(
    Iterable<({String muscle, int sets})> entries,
  ) {
    final result = <String, int>{};
    for (final e in entries) {
      result[e.muscle] = (result[e.muscle] ?? 0) + e.sets;
    }
    return result;
  }

  static double _round1(double v) => (v * 10).roundToDouble() / 10;
  static double _round3(double v) => (v * 1000).roundToDouble() / 1000;
}

/// Volume landmarks per muscle group (docs/12 §5.4).
///
/// MEV = minimum effective volume, MRV = maximum recoverable volume. Weekly
/// working sets outside this band raise an insight, never a score change.
abstract final class VolumeLandmarks {
  static const Map<String, ({int mev, int mavLow, int mavHigh, int mrv})>
  table = {
    'chest': (mev: 8, mavLow: 12, mavHigh: 20, mrv: 22),
    'back': (mev: 10, mavLow: 14, mavHigh: 22, mrv: 25),
    'quads': (mev: 8, mavLow: 12, mavHigh: 18, mrv: 20),
    'hamstrings': (mev: 6, mavLow: 10, mavHigh: 16, mrv: 20),
    'shoulders': (mev: 8, mavLow: 12, mavHigh: 20, mrv: 26),
    'biceps': (mev: 8, mavLow: 14, mavHigh: 20, mrv: 26),
    'triceps': (mev: 6, mavLow: 10, mavHigh: 18, mrv: 24),
    'calves': (mev: 8, mavLow: 12, mavHigh: 16, mrv: 20),
    'glutes': (mev: 4, mavLow: 8, mavHigh: 16, mrv: 20),
    'core': (mev: 6, mavLow: 10, mavHigh: 16, mrv: 20),
  };

  static VolumeVerdict assess(String muscle, int weeklySets) {
    final band = table[muscle];
    if (band == null) return VolumeVerdict.unknown;
    if (weeklySets < band.mev) return VolumeVerdict.belowMev;
    if (weeklySets > band.mrv) return VolumeVerdict.aboveMrv;
    if (weeklySets >= band.mavLow && weeklySets <= band.mavHigh) {
      return VolumeVerdict.optimal;
    }
    return VolumeVerdict.adequate;
  }
}

enum VolumeVerdict {
  belowMev('Below minimum effective volume'),
  adequate('Adequate'),
  optimal('In the productive range'),
  aboveMrv('Above maximum recoverable volume'),
  unknown('Unknown');

  const VolumeVerdict(this.label);
  final String label;
}
