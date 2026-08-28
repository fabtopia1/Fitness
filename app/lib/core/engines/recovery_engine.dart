import 'dart:math' as math;

import 'package:lifedna/shared/enums/enums.dart';

/// Last night's sleep, as the recovery engine consumes it.
class SleepInput {
  const SleepInput({
    required this.totalMinutes,
    required this.timeInBedMinutes,
    this.goalMinutes = 480,
    this.deepMinutes,
    this.remMinutes,
    this.bedtimeStdDevMinutes,
    this.wakeStdDevMinutes,
    this.nightsOfHistory = 0,
  });

  final int totalMinutes;
  final int timeInBedMinutes;
  final int goalMinutes;
  final int? deepMinutes;
  final int? remMinutes;

  /// Standard deviation of bed/wake times across the last 14 nights. Null when
  /// there is not yet enough history — the consistency component is then simply
  /// unavailable rather than guessed.
  final double? bedtimeStdDevMinutes;
  final double? wakeStdDevMinutes;
  final int nightsOfHistory;
}

class TrainingInput {
  const TrainingInput({
    required this.acwr,
    required this.yesterdayLoad,
    required this.meanDailyLoad28d,
    this.yesterdaySessionRpe,
    this.daysSinceLastSession = 0,
  });

  /// Null when there is not enough history for a meaningful ratio.
  final double? acwr;
  final double yesterdayLoad;
  final double meanDailyLoad28d;
  final int? yesterdaySessionRpe;
  final int daysSinceLastSession;
}

class ActivityInput {
  const ActivityInput({
    required this.steps,
    required this.stepGoal,
    required this.activeMinutes,
    this.trainedYesterday = false,
  });

  final int steps;
  final int stepGoal;
  final int activeMinutes;
  final bool trainedYesterday;
}

/// Optional physiological signals. Present only when a wearable supplies them
/// and at least 14 days of baseline exist.
class PhysiologyInput {
  const PhysiologyInput({
    this.restingHrBpm,
    this.baselineRestingHrBpm,
    this.hrvMs,
    this.baselineHrvMs,
  });

  final int? restingHrBpm;
  final int? baselineRestingHrBpm;
  final double? hrvMs;
  final double? baselineHrvMs;

  bool get hasRestingHr => restingHrBpm != null && baselineRestingHrBpm != null;
  bool get hasHrv =>
      hrvMs != null && baselineHrvMs != null && baselineHrvMs! > 0;
}

/// One weighted component of the composite score, with everything needed to
/// explain it. Every score in LifeDNA is decomposable — see docs/12 §2.
class RecoveryComponent {
  const RecoveryComponent({
    required this.name,
    required this.score,
    required this.weight,
    required this.available,
  });

  final String name;
  final int score;
  final double weight;
  final bool available;

  double get contribution =>
      available ? (score * weight * 10).roundToDouble() / 10 : 0;
}

class RecoveryResult {
  const RecoveryResult({
    required this.recoveryScore,
    required this.band,
    required this.readinessScore,
    required this.components,
    required this.sleepScore,
    required this.missingInputs,
    required this.action,
    required this.detail,
    required this.engineVersion,
  });

  /// Null when fewer than two domains were available.
  final int? recoveryScore;
  final RecoveryBand band;
  final int? readinessScore;
  final List<RecoveryComponent> components;
  final int? sleepScore;
  final List<String> missingInputs;
  final TrainingAction? action;
  final String detail;
  final String engineVersion;

  bool get isSufficient => recoveryScore != null;
}

/// The Recovery Engine.
///
/// Specification: docs/12-recovery-engine.md. This is the client mirror of the
/// authoritative server implementation; both are validated against the shared
/// fixtures in `test/fixtures/engines/recovery/`. The mirror exists so the UI
/// can recompute instantly when the user edits an input, and always agree with
/// what the server will later store.
///
/// It answers exactly one question: **how hard can I train today?**
abstract final class RecoveryEngine {
  static const String version = 'recovery-1.2.0';

  // Default weights. Overridable server-side via Remote Config (RECV-02).
  static const double wSleep = 0.40;
  static const double wTraining = 0.40;
  static const double wActivity = 0.20;

  /// Fewer than two available domains produces no score at all, rather than a
  /// confident-looking guess (RECV-07).
  static const int minimumComponents = 2;

  static RecoveryResult compute({
    SleepInput? sleep,
    TrainingInput? training,
    ActivityInput? activity,
    PhysiologyInput physiology = const PhysiologyInput(),
    PlannedSession? plannedSession,
  }) {
    final missing = <String>[];

    final sleepScore = sleep == null ? null : _sleepScore(sleep);
    final trainingScore = training == null ? null : _trainingScore(training);
    final activityScore = activity == null ? null : _activityScore(activity);

    if (sleepScore == null) missing.add('sleep');
    if (trainingScore == null) missing.add('training');
    if (activityScore == null) missing.add('activity');

    final availableCount = [
      sleepScore,
      trainingScore,
      activityScore,
    ].where((s) => s != null).length;

    final components = <RecoveryComponent>[];

    if (availableCount < minimumComponents) {
      return RecoveryResult(
        recoveryScore: null,
        band: RecoveryBand.insufficientData,
        readinessScore: null,
        components: components,
        sleepScore: sleepScore,
        missingInputs: missing,
        action: null,
        detail: _insufficientDataMessage(missing),
        engineVersion: version,
      );
    }

    // Renormalize the weights over whatever is actually available, so a missing
    // domain does not silently drag the score toward zero.
    var weightTotal = 0.0;
    if (sleepScore != null) weightTotal += wSleep;
    if (trainingScore != null) weightTotal += wTraining;
    if (activityScore != null) weightTotal += wActivity;

    final normSleep = sleepScore != null ? wSleep / weightTotal : 0.0;
    final normTraining = trainingScore != null ? wTraining / weightTotal : 0.0;
    final normActivity = activityScore != null ? wActivity / weightTotal : 0.0;

    components
      ..add(
        RecoveryComponent(
          name: 'sleep',
          score: sleepScore ?? 0,
          weight: _round2(normSleep),
          available: sleepScore != null,
        ),
      )
      ..add(
        RecoveryComponent(
          name: 'training',
          score: trainingScore ?? 0,
          weight: _round2(normTraining),
          available: trainingScore != null,
        ),
      )
      ..add(
        RecoveryComponent(
          name: 'activity',
          score: activityScore ?? 0,
          weight: _round2(normActivity),
          available: activityScore != null,
        ),
      );

    var composite =
        (sleepScore ?? 0) * normSleep +
        (trainingScore ?? 0) * normTraining +
        (activityScore ?? 0) * normActivity;

    composite += _physiologyAdjustment(physiology);

    final recovery = composite.clamp(0.0, 100.0).round();
    final band = RecoveryBand.forScore(recovery);

    final readiness = _readiness(
      recovery: recovery,
      planned: plannedSession,
      meanDailyLoad28d: training?.meanDailyLoad28d ?? 0,
    );

    final action = _action(readiness ?? recovery, training?.acwr);

    return RecoveryResult(
      recoveryScore: recovery,
      band: band,
      readinessScore: readiness,
      components: components,
      sleepScore: sleepScore,
      missingInputs: missing,
      action: action,
      detail: _detail(
        action: action,
        recovery: recovery,
        readiness: readiness,
        sleepScore: sleepScore,
        acwr: training?.acwr,
      ),
      engineVersion: version,
    );
  }

  // ---------------------------------------------------------------- sleep ---

  /// `0.40·duration + 0.25·consistency + 0.20·efficiency + 0.15·stages`,
  /// renormalized over whichever sub-components are available.
  static int _sleepScore(SleepInput s) {
    final duration = _sleepDuration(s);
    final consistency = _sleepConsistency(s);
    final efficiency = _sleepEfficiency(s);
    final stages = _sleepStages(s);

    var sum = 0.0;
    var weight = 0.0;

    sum += duration * 0.40;
    weight += 0.40;

    if (consistency != null) {
      sum += consistency * 0.25;
      weight += 0.25;
    }
    if (efficiency != null) {
      sum += efficiency * 0.20;
      weight += 0.20;
    }
    if (stages != null) {
      sum += stages * 0.15;
      weight += 0.15;
    }

    return (sum / weight).clamp(0.0, 100.0).round();
  }

  /// Under-sleeping is penalized ~2.2× harder than over-sleeping, because the
  /// physiological cost is asymmetric. Long sleep is mildly penalized (it
  /// correlates with poor quality or illness) but never below 60.
  static double _sleepDuration(SleepInput s) {
    if (s.goalMinutes <= 0) return 0;
    final ratio = s.totalMinutes / s.goalMinutes;
    if (ratio >= 0.95 && ratio <= 1.15) return 100;
    if (ratio < 0.95) {
      return math.max(0, 100 - (0.95 - ratio) * 220);
    }
    return math.max(60, 100 - (ratio - 1.15) * 100);
  }

  /// Schedule stability. σ ≤ 20 min scores 100.
  static double? _sleepConsistency(SleepInput s) {
    if (s.nightsOfHistory < 7) return null;
    final bed = s.bedtimeStdDevMinutes;
    final wake = s.wakeStdDevMinutes;
    if (bed == null || wake == null) return null;
    final sigma = (bed + wake) / 2;
    return (100 - (sigma - 20) * 1.6).clamp(0.0, 100.0).toDouble();
  }

  static double? _sleepEfficiency(SleepInput s) {
    if (s.timeInBedMinutes <= 0) return null;
    final pct = s.totalMinutes / s.timeInBedMinutes * 100;
    if (pct >= 90) return 100;
    if (pct >= 60) return (pct - 60) * 3.33;
    return 0;
  }

  /// Ideal bands: deep 13–23 %, REM 20–25 %.
  static double? _sleepStages(SleepInput s) {
    final deep = s.deepMinutes;
    final rem = s.remMinutes;
    if (deep == null || rem == null || s.totalMinutes <= 0) return null;

    final deepPct = deep / s.totalMinutes * 100;
    final remPct = rem / s.totalMinutes * 100;

    final deepScore = (100 - (deepPct - 18).abs() * 5).clamp(0.0, 100.0);
    final remScore = (100 - (remPct - 22.5).abs() * 5).clamp(0.0, 100.0);
    return ((deepScore + remScore) / 2).toDouble();
  }

  // ------------------------------------------------------------- training ---

  /// A plateau, not a peak: a wide productive band with penalties on both sides.
  static int _trainingScore(TrainingInput t) {
    final acwr = t.acwr;

    // Without enough history the ratio is meaningless, so return a neutral
    // score rather than penalizing a new user for having no chronic load.
    var base = 75.0;
    if (acwr != null) {
      if (acwr < 0.60) {
        base = 70;
      } else if (acwr < 0.80) {
        base = 85;
      } else if (acwr < 1.30) {
        base = 100;
      } else if (acwr < 1.50) {
        base = 75;
      } else if (acwr < 1.80) {
        base = 50;
      } else {
        base = 25;
      }
    }

    var adjustment = 0.0;

    // A single unusually heavy session yesterday still costs today, even when
    // the ratio looks healthy.
    if (t.meanDailyLoad28d > 0 && t.yesterdayLoad > 1.5 * t.meanDailyLoad28d) {
      adjustment -= 15;
    }
    if ((t.yesterdaySessionRpe ?? 0) >= 9) {
      adjustment -= 8;
    }
    if (t.daysSinceLastSession >= 2 && (acwr == null || acwr >= 0.8)) {
      adjustment += 10;
    }

    return (base + adjustment).clamp(0.0, 100.0).round();
  }

  // ------------------------------------------------------------- activity ---

  static int _activityScore(ActivityInput a) {
    if (a.stepGoal <= 0) return 0;
    final stepRatio = a.steps / a.stepGoal;

    final double stepScore;
    if (stepRatio >= 1.0) {
      stepScore = 100;
    } else if (stepRatio >= 0.5) {
      stepScore = stepRatio * 100;
    } else {
      stepScore = stepRatio * 80;
    }

    final activeScore = (a.activeMinutes / 45 * 100)
        .clamp(0.0, 100.0)
        .toDouble();
    var score = 0.6 * stepScore + 0.4 * activeScore;

    // A genuinely sedentary day is a recovery signal in its own right.
    if (a.steps < 3000 && !a.trainedYesterday) score -= 10;

    return score.clamp(0.0, 100.0).round();
  }

  // ---------------------------------------------------------- physiology ---

  /// Capped at ±10 points in total so a noisy wearable reading can never
  /// dominate the score.
  static double _physiologyAdjustment(PhysiologyInput p) {
    var adjustment = 0.0;

    if (p.hasRestingHr) {
      final delta = p.restingHrBpm! - p.baselineRestingHrBpm!;
      if (delta <= -3) {
        adjustment += 3;
      } else if (delta >= 3 && delta <= 5) {
        adjustment -= 4;
      } else if (delta > 5) {
        adjustment -= 8;
      }
    }

    if (p.hasHrv) {
      final deltaPct = (p.hrvMs! - p.baselineHrvMs!) / p.baselineHrvMs! * 100;
      if (deltaPct >= 10) {
        adjustment += 4;
      } else if (deltaPct <= -20) {
        adjustment -= 9;
      } else if (deltaPct <= -10) {
        adjustment -= 5;
      }
    }

    return adjustment.clamp(-10.0, 10.0).toDouble();
  }

  // ----------------------------------------------------------- readiness ---

  /// Recovery is backward-looking. Readiness asks the forward question: how
  /// recovered am I *relative to what today actually demands*?
  static int? _readiness({
    required int recovery,
    required PlannedSession? planned,
    required double meanDailyLoad28d,
  }) {
    if (planned == null || meanDailyLoad28d <= 0) return recovery;
    final plannedLoad = planned.rpe * planned.durationMinutes;
    final demand = (plannedLoad / meanDailyLoad28d).clamp(0.0, 2.5);
    return (recovery - (demand - 1.0) * 18).clamp(0.0, 100.0).round();
  }

  static TrainingAction _action(int readiness, double? acwr) {
    if (readiness < 40 || (acwr != null && acwr >= 1.8)) {
      return TrainingAction.rest;
    }
    if (readiness < 65) return TrainingAction.reduce;
    if (readiness >= 80 && (acwr == null || acwr < 1.3)) {
      return TrainingAction.push;
    }
    return TrainingAction.proceed;
  }

  // --------------------------------------------------------------- copy ----

  static String _detail({
    required TrainingAction action,
    required int recovery,
    required int? readiness,
    required int? sleepScore,
    required double? acwr,
  }) {
    final ratio = acwr?.toStringAsFixed(2);
    return switch (action) {
      TrainingAction.push =>
        'Recovery $recovery with a balanced load ratio'
            '${ratio == null ? '' : ' of $ratio'}. '
            'This is the day to attempt a record.',
      TrainingAction.proceed =>
        readiness != null && readiness < recovery
            ? 'Recovery is $recovery, but today’s session is heavier than your '
                  'average, so readiness lands at $readiness. Hit your target reps; '
                  'save the record attempt for a lighter day.'
            : 'Recovery $recovery'
                  '${ratio == null ? '' : ' and a load ratio of $ratio'}. '
                  'Train as planned.',
      TrainingAction.reduce =>
        'Recovery is $recovery${sleepScore == null ? '' : ' with a sleep score '
                      'of $sleepScore'}. Keep the compound work and drop the last set of '
            'each accessory.',
      TrainingAction.rest =>
        'Recovery is $recovery'
            '${ratio == null ? '' : ' and your load ratio is $ratio'}. '
            'Training hard today costs more than it earns.',
    };
  }

  /// Names exactly what is missing. "Insufficient data" without saying what
  /// would fix it is a dead end, and the flow rules forbid dead ends.
  static String _insufficientDataMessage(List<String> missing) {
    if (missing.contains('sleep')) {
      return 'Recovery needs sleep data from at least 2 of the last 3 nights.';
    }
    final names = missing.map(_domainLabel).join(' and ');
    return 'Recovery needs at least two data sources. Still missing: $names.';
  }

  static String _domainLabel(String domain) => switch (domain) {
    'sleep' => 'sleep',
    'training' => 'training history',
    'activity' => 'daily activity',
    _ => domain,
  };

  static double _round2(double v) => (v * 100).roundToDouble() / 100;
}

/// Today's planned session, used to convert recovery into readiness.
class PlannedSession {
  const PlannedSession({required this.rpe, required this.durationMinutes});
  final int rpe;
  final int durationMinutes;
}
