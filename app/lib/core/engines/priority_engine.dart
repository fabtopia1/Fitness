import 'package:lifedna/shared/enums/enums.dart';
import 'package:lifedna/shared/value_objects/macros.dart';

/// The domain of an action, which determines its accent colour and its icon.
enum ActionDomain {
  nutrition,
  hydration,
  training,
  recovery,
  supplement,
  schedule,
  task,
  insight,
  setup,
}

/// One candidate action. Immutable, comparable, and carrying everything the
/// Next Action card needs to render without a further lookup.
class NextAction {
  const NextAction({
    required this.id,
    required this.domain,
    required this.title,
    required this.subtitle,
    required this.actionLabel,
    required this.deeplink,
    required this.priority,
    this.dueAt,
    this.evidence = const [],
  });

  final String id;
  final ActionDomain domain;

  /// The imperative headline. This is the sentence on the card.
  final String title;

  /// One line of context: why now, or what it costs.
  final String subtitle;

  /// The primary button label. Always a verb.
  final String actionLabel;

  final String deeplink;

  /// 0–100. Higher wins.
  final int priority;

  final DateTime? dueAt;

  /// The values that produced this action, for the "Why?" sheet. An action
  /// without evidence is a bug (docs/05 Flow 8).
  final List<({String label, String value})> evidence;
}

/// The state the priority engine reasons over. Assembled once by the dashboard
/// controller from a single `daily_stats` read plus live streams.
class DayState {
  const DayState({
    required this.now,
    required this.dayType,
    required this.consumed,
    required this.targets,
    required this.waterMl,
    required this.waterTargetMl,
    required this.mealSlotsLogged,
    required this.plannedMealSlots,
    required this.workoutStatus,
    required this.workoutStartsAt,
    required this.workoutName,
    required this.workoutSetCount,
    required this.supplementsTaken,
    required this.supplementsScheduled,
    required this.nextSupplementAt,
    required this.nextSupplementName,
    required this.recoveryScore,
    required this.recoveryAction,
    required this.nextEventTitle,
    required this.nextEventAt,
    required this.overdueTaskCount,
    required this.topTaskTitle,
    required this.topTaskDueAt,
    required this.topInsightHeadline,
    required this.topInsightId,
    required this.bedtimeAt,
    required this.hasHealthSource,
  });

  final DateTime now;
  final DayType dayType;
  final Macros consumed;
  final MacroTargets targets;
  final int waterMl;
  final int waterTargetMl;
  final Set<MealSlot> mealSlotsLogged;
  final List<({MealSlot slot, DateTime at, String name, double kcal, double proteinG})>
      plannedMealSlots;

  final WorkoutStatus workoutStatus;
  final DateTime? workoutStartsAt;
  final String? workoutName;
  final int workoutSetCount;

  final int supplementsTaken;
  final int supplementsScheduled;
  final DateTime? nextSupplementAt;
  final String? nextSupplementName;

  final int? recoveryScore;
  final TrainingAction? recoveryAction;

  final String? nextEventTitle;
  final DateTime? nextEventAt;

  final int overdueTaskCount;
  final String? topTaskTitle;
  final DateTime? topTaskDueAt;

  final String? topInsightHeadline;
  final String? topInsightId;

  final DateTime bedtimeAt;
  final bool hasHealthSource;
}

enum WorkoutStatus { scheduled, inProgress, completed, restDay, none }

/// Decides what the user should do next.
///
/// This is the engine behind the single most important surface in the product
/// (docs/01 §6.1 DASH-02). Everything else on the dashboard is reference
/// material; this card is the product's actual output.
///
/// It is deliberately a deterministic rule set rather than a model: the answer
/// must be reproducible, explainable and instant, and must work offline.
abstract final class PriorityEngine {
  static const String version = 'priority-1.0.0';

  /// Returns candidates ordered by priority, highest first.
  static List<NextAction> rank(DayState s) {
    final candidates = <NextAction>[
      ..._sessionInProgress(s),
      ..._setup(s),
      ..._recovery(s),
      ..._workout(s),
      ..._meal(s),
      ..._proteinDebt(s),
      ..._supplement(s),
      ..._meeting(s),
      ..._task(s),
      ..._hydration(s),
      ..._insight(s),
    ];

    candidates.sort((a, b) => b.priority.compareTo(a.priority));
    return candidates;
  }

  /// The single action shown on the Next Action card.
  static NextAction? top(DayState s) {
    final ranked = rank(s);
    return ranked.isEmpty ? null : ranked.first;
  }

  // ------------------------------------------------------------------------
  // Rules, in rough priority order. Each returns zero or one candidate.
  // ------------------------------------------------------------------------

  /// An abandoned live session outranks everything. Losing a workout in
  /// progress is the worst thing that can happen to a training log.
  static List<NextAction> _sessionInProgress(DayState s) {
    if (s.workoutStatus != WorkoutStatus.inProgress) return const [];
    return [
      NextAction(
        id: 'session_in_progress',
        domain: ActionDomain.training,
        title: 'You have a workout in progress',
        subtitle: '${s.workoutName ?? 'Session'} — pick up where you left off',
        actionLabel: 'Resume workout',
        deeplink: '/train',
        priority: 100,
        evidence: [(label: 'Status', value: 'in progress')],
      ),
    ];
  }

  /// Day-zero guidance. A new user with no health source cannot get a recovery
  /// score, and telling them that once is worth more than any other card.
  static List<NextAction> _setup(DayState s) {
    if (s.hasHealthSource) return const [];
    if (s.mealSlotsLogged.isNotEmpty || s.workoutStatus != WorkoutStatus.none) {
      // They are already using the app; don't nag mid-flow.
      return const [];
    }
    return [
      const NextAction(
        id: 'connect_health',
        domain: ActionDomain.setup,
        title: 'Connect a health source',
        subtitle: 'Sleep and activity data unlock your recovery score',
        actionLabel: 'Connect',
        deeplink: '/me/settings/integrations',
        priority: 88,
      ),
    ];
  }

  /// Low recovery on a training day is the highest-value intervention the
  /// product makes — it is the difference between a scaled session and a
  /// missed week.
  static List<NextAction> _recovery(DayState s) {
    final score = s.recoveryScore;
    final action = s.recoveryAction;
    if (score == null || action == null) return const [];
    if (action != TrainingAction.reduce && action != TrainingAction.rest) {
      return const [];
    }
    if (s.workoutStatus == WorkoutStatus.completed) return const [];

    final isRest = action == TrainingAction.rest;
    return [
      NextAction(
        id: 'recovery_${action.wire}',
        domain: ActionDomain.recovery,
        title: isRest
            ? 'Recovery is low ($score). Rest today.'
            : 'Recovery is low ($score). Cut today’s volume by 30 %.',
        subtitle: action.headline,
        actionLabel: isRest ? 'Move session' : 'Apply reduced session',
        deeplink: '/me/recovery',
        priority: 95,
        evidence: [
          (label: 'Recovery score', value: '$score'),
          (label: 'Recommendation', value: action.wire),
        ],
      ),
    ];
  }

  static List<NextAction> _workout(DayState s) {
    if (s.workoutStatus != WorkoutStatus.scheduled) return const [];
    final startsAt = s.workoutStartsAt;
    if (startsAt == null) return const [];

    final minutesUntil = startsAt.difference(s.now).inMinutes;
    if (minutesUntil < -30) return const []; // long past; a nag helps nobody
    if (minutesUntil > 120) return const [];

    final String title;
    if (minutesUntil <= 0) {
      title = 'Your workout is due now';
    } else if (minutesUntil < 60) {
      title = 'Workout starts in $minutesUntil minutes';
    } else {
      final h = (minutesUntil / 60).floor();
      final m = minutesUntil % 60;
      title = 'Workout starts in ${h}h ${m.toString().padLeft(2, '0')}m';
    }

    return [
      NextAction(
        id: 'workout_upcoming',
        domain: ActionDomain.training,
        title: title,
        subtitle:
            '${s.workoutName ?? 'Session'} — ${s.workoutSetCount} working sets',
        actionLabel: minutesUntil <= 15 ? 'Start workout' : 'Preview session',
        deeplink: '/train',
        priority: minutesUntil <= 60 ? 90 : 70,
        dueAt: startsAt,
        evidence: [
          (label: 'Scheduled', value: _hhmm(startsAt)),
          (label: 'Working sets', value: '${s.workoutSetCount}'),
        ],
      ),
    ];
  }

  /// A meal slot whose time has arrived and which has not been logged.
  static List<NextAction> _meal(DayState s) {
    for (final planned in s.plannedMealSlots) {
      if (s.mealSlotsLogged.contains(planned.slot)) continue;
      final minutesLate = s.now.difference(planned.at).inMinutes;
      if (minutesLate < -15) continue; // not yet due
      if (minutesLate > 240) continue; // that meal has passed; don't dwell

      return [
        NextAction(
          id: 'meal_${planned.slot.wire}',
          domain: ActionDomain.nutrition,
          title: 'Time for ${planned.slot.label.toLowerCase()}',
          subtitle: '${planned.name} — ${planned.kcal.round()} kcal · '
              '${planned.proteinG.round()} g protein',
          actionLabel: 'Log it',
          deeplink: '/nutrition/log?slot=${planned.slot.wire}',
          priority: 85,
          dueAt: planned.at,
          evidence: [
            (label: 'Planned for', value: _hhmm(planned.at)),
            (label: 'Slot', value: planned.slot.label),
          ],
        ),
      ];
    }
    return const [];
  }

  /// The reference behaviour from docs/01 §6.1: as bedtime approaches, an
  /// unmet protein floor becomes the most actionable thing left in the day.
  static List<NextAction> _proteinDebt(DayState s) {
    final debt = s.targets.proteinDebt(s.consumed);
    if (debt < 15) return const [];

    final hoursToBed = s.bedtimeAt.difference(s.now).inMinutes / 60;
    if (hoursToBed <= 0) return const [];

    // Only becomes the headline once the day is running out.
    final priority = hoursToBed <= 5 ? 87 : 55;

    final hoursLabel = hoursToBed >= 1
        ? '${hoursToBed.floor()} h until bed'
        : '${(hoursToBed * 60).round()} min until bed';

    return [
      NextAction(
        id: 'protein_debt',
        domain: ActionDomain.nutrition,
        title: 'You are ${debt.round()} g below your protein target',
        subtitle: '$hoursLabel · a ${_snackSize(debt)} g snack closes it',
        actionLabel: 'Log protein',
        deeplink: '/nutrition/log',
        priority: priority,
        evidence: [
          (label: 'Protein today', value: '${s.consumed.proteinG.round()} g'),
          (label: 'Protein floor', value: '${s.targets.proteinFloorG.round()} g'),
          (label: 'Remaining', value: '${debt.round()} g'),
        ],
      ),
    ];
  }

  static List<NextAction> _supplement(DayState s) {
    final at = s.nextSupplementAt;
    final name = s.nextSupplementName;
    if (at == null || name == null) return const [];
    final minutesLate = s.now.difference(at).inMinutes;
    if (minutesLate < -10 || minutesLate > 180) return const [];

    return [
      NextAction(
        id: 'supplement_due',
        domain: ActionDomain.supplement,
        title: 'Time for $name',
        subtitle: 'Scheduled for ${_hhmm(at)} · '
            '${s.supplementsTaken} of ${s.supplementsScheduled} taken today',
        actionLabel: 'Log dose',
        deeplink: '/me/supplements',
        priority: 68,
        dueAt: at,
      ),
    ];
  }

  static List<NextAction> _meeting(DayState s) {
    final at = s.nextEventAt;
    final title = s.nextEventTitle;
    if (at == null || title == null) return const [];
    final minutesUntil = at.difference(s.now).inMinutes;
    if (minutesUntil < 0 || minutesUntil > 15) return const [];

    return [
      NextAction(
        id: 'meeting_soon',
        domain: ActionDomain.schedule,
        title: minutesUntil == 0
            ? '$title is starting'
            : '$title in $minutesUntil minutes',
        subtitle: 'From your calendar',
        actionLabel: 'View',
        deeplink: '/plan',
        priority: 92,
        dueAt: at,
      ),
    ];
  }

  static List<NextAction> _task(DayState s) {
    final title = s.topTaskTitle;
    if (title == null) return const [];
    final due = s.topTaskDueAt;

    if (s.overdueTaskCount > 0) {
      return [
        NextAction(
          id: 'task_overdue',
          domain: ActionDomain.task,
          title: s.overdueTaskCount == 1
              ? '1 task is overdue'
              : '${s.overdueTaskCount} tasks are overdue',
          subtitle: title,
          actionLabel: 'Triage',
          deeplink: '/plan',
          priority: 62,
        ),
      ];
    }

    if (due == null) return const [];
    final minutesUntil = due.difference(s.now).inMinutes;
    if (minutesUntil < 0 || minutesUntil > 120) return const [];

    return [
      NextAction(
        id: 'task_due',
        domain: ActionDomain.task,
        title: title,
        subtitle: 'Due at ${_hhmm(due)}',
        actionLabel: 'Open task',
        deeplink: '/plan',
        priority: 60,
        dueAt: due,
      ),
    ];
  }

  static List<NextAction> _hydration(DayState s) {
    if (s.waterTargetMl <= 0) return const [];
    final ratio = s.waterMl / s.waterTargetMl;
    final hoursToBed = s.bedtimeAt.difference(s.now).inMinutes / 60;
    if (hoursToBed <= 1) return const []; // too late to be useful
    if (ratio >= 0.75) return const [];

    final deficit = s.waterTargetMl - s.waterMl;
    return [
      NextAction(
        id: 'hydration_behind',
        domain: ActionDomain.hydration,
        title: 'You are ${_ml(deficit)} behind on water',
        subtitle: '${_ml(s.waterMl)} of ${_ml(s.waterTargetMl)} today',
        actionLabel: 'Log 250 ml',
        deeplink: '/nutrition',
        priority: 45,
        evidence: [
          (label: 'Consumed', value: '${s.waterMl} ml'),
          (label: 'Target', value: '${s.waterTargetMl} ml'),
        ],
      ),
    ];
  }

  static List<NextAction> _insight(DayState s) {
    final headline = s.topInsightHeadline;
    final id = s.topInsightId;
    if (headline == null || id == null) return const [];
    return [
      NextAction(
        id: 'insight_$id',
        domain: ActionDomain.insight,
        title: headline,
        subtitle: 'From your last 7 days',
        actionLabel: 'See why',
        deeplink: '/insight/$id',
        priority: 50,
      ),
    ];
  }

  /// The card shown when nothing is outstanding — a real state, not a fallback.
  static NextAction allClear(DayState s) => NextAction(
        id: 'all_clear',
        domain: ActionDomain.insight,
        title: 'You’re on track',
        subtitle: s.dayType == DayType.training
            ? 'Training done, targets met. Protect your sleep tonight.'
            : 'Rest day handled. Nothing outstanding.',
        actionLabel: 'View today',
        deeplink: '/nutrition',
        priority: 0,
      );

  /// Rounds a protein gap to a realistic snack size.
  static int _snackSize(double debt) =>
      ((debt / 10).ceil() * 10).clamp(10, 60).toInt();

  /// Millilitres with a thousands separator, per the formatting contract in
  /// docs/04 §10.2.
  static String _ml(int value) {
    final digits = value.toString();
    final buffer = StringBuffer();
    for (var i = 0; i < digits.length; i++) {
      if (i > 0 && (digits.length - i) % 3 == 0) buffer.write(',');
      buffer.write(digits[i]);
    }
    return '$buffer ml';
  }

  static String _hhmm(DateTime t) =>
      '${t.hour.toString().padLeft(2, '0')}:${t.minute.toString().padLeft(2, '0')}';
}
