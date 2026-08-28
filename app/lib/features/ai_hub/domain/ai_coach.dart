import 'package:lifedna/shared/value_objects/macros.dart';

/// A structured snapshot of the user's own numbers.
///
/// Assembled locally and shown to the user in full before it goes anywhere.
class CoachContext {
  const CoachContext({
    required this.consumed,
    required this.targets,
    required this.waterMl,
    required this.waterTargetMl,
    required this.trainedToday,
    required this.sessionsThisWeek,
    required this.weeklyVolumeKg,
    required this.supplementsTaken,
    required this.supplementsScheduled,
    this.weightKg,
    this.weightChangeKg,
    this.goalLabel,
    this.lastSessionName,
  });

  final Macros consumed;
  final MacroTargets targets;
  final int waterMl;
  final int waterTargetMl;
  final bool trainedToday;
  final int sessionsThisWeek;
  final double weeklyVolumeKg;
  final int supplementsTaken;
  final int supplementsScheduled;
  final double? weightKg;
  final double? weightChangeKg;
  final String? goalLabel;
  final String? lastSessionName;

  /// A compact, human-readable brief.
  ///
  /// This exact text is what gets copied or handed to an external assistant —
  /// the user sees it first, so there is no hidden payload.
  String toBrief() {
    final lines = <String>[
      'MY NUMBERS TODAY',
      if (goalLabel != null) 'Goal: $goalLabel',
      'Calories: ${consumed.kcal.round()} of ${targets.kcal.round()} kcal',
      'Protein: ${consumed.proteinG.round()} of ${targets.proteinG.round()} g',
      'Carbs: ${consumed.carbsG.round()} of ${targets.carbsG.round()} g',
      'Fat: ${consumed.fatG.round()} of ${targets.fatG.round()} g',
      'Water: $waterMl of $waterTargetMl ml',
      'Supplements: $supplementsTaken of $supplementsScheduled taken',
      trainedToday
          ? 'Trained today: yes${lastSessionName == null ? '' : ' ($lastSessionName)'}'
          : 'Trained today: no',
      'Sessions this week: $sessionsThisWeek',
      'Training volume this week: ${weeklyVolumeKg.round()} kg',
      if (weightKg != null) 'Bodyweight: ${weightKg!.toStringAsFixed(1)} kg',
      if (weightChangeKg != null)
        'Weight change (30 days): ${weightChangeKg! >= 0 ? '+' : ''}'
            '${weightChangeKg!.toStringAsFixed(1)} kg',
    ];
    return lines.join('\n');
  }
}

/// One coaching prompt template.
class CoachPrompt {
  const CoachPrompt({
    required this.id,
    required this.title,
    required this.question,
    required this.category,
  });

  final String id;
  final String title;
  final String question;
  final CoachCategory category;

  /// The full text handed to an external assistant: the user's real numbers
  /// plus the question.
  String compose(CoachContext context) =>
      '${context.toBrief()}\n\nQUESTION\n$question';
}

enum CoachCategory {
  nutrition('Nutrition'),
  training('Training'),
  recovery('Recovery'),
  habits('Habits');

  const CoachCategory(this.label);
  final String label;
}

/// The local coach.
///
/// It is DETERMINISTIC and runs entirely on device. It reads the user's own
/// numbers and returns rule-based guidance — no model, no network, no API key,
/// no invented figures. Every statement it makes cites a number the user can
/// see elsewhere in the app.
///
/// This is the honest version of an "AI coach" for an MVP: shipping a chat box
/// backed by a key we do not have would be a fake integration, and shipping
/// one backed by a key embedded in the APK would be a security incident.
abstract final class LocalCoach {
  static const List<CoachPrompt> prompts = [
    CoachPrompt(
      id: 'protein_gap',
      title: 'How do I hit my protein target?',
      question:
          'Given my numbers above, how should I structure the rest of my day '
          'to reach my protein target without going over on calories?',
      category: CoachCategory.nutrition,
    ),
    CoachPrompt(
      id: 'plateau',
      title: 'My lifts have stalled',
      question:
          'My training volume and bodyweight are above. What is the most '
          'likely reason my lifts have stopped progressing, and what single '
          'change would you make first?',
      category: CoachCategory.training,
    ),
    CoachPrompt(
      id: 'week_review',
      title: 'Review my week',
      question:
          'Review my week from the numbers above. What went well, what is the '
          'weakest link, and what is the one thing to fix next week?',
      category: CoachCategory.habits,
    ),
    CoachPrompt(
      id: 'recovery',
      title: 'Should I train today?',
      question:
          'Based on my training volume and how much I have trained this week, '
          'should I train hard today, train lightly, or rest?',
      category: CoachCategory.recovery,
    ),
    CoachPrompt(
      id: 'meal_ideas',
      title: 'What should I eat next?',
      question:
          'Suggest a meal that fits the calories and macros I have left today, '
          'using ordinary supermarket ingredients.',
      category: CoachCategory.nutrition,
    ),
  ];

  /// Deterministic guidance from the user's own data.
  ///
  /// Ordered by impact so the first card is the thing most worth doing.
  static List<CoachInsight> analyse(CoachContext context) {
    final insights = <CoachInsight>[];

    final proteinGap = context.targets.proteinG - context.consumed.proteinG;
    if (proteinGap > 20) {
      insights.add(
        CoachInsight(
          category: CoachCategory.nutrition,
          headline: 'You are ${proteinGap.round()} g short on protein',
          detail:
              'You have logged ${context.consumed.proteinG.round()} g against a '
              '${context.targets.proteinG.round()} g target. Protein is the '
              'lever that protects muscle, so close this before worrying about '
              'anything else today.',
          evidence: [
            (label: 'Protein logged', value: '${context.consumed.proteinG.round()} g'),
            (label: 'Target', value: '${context.targets.proteinG.round()} g'),
          ],
          impact: 90,
        ),
      );
    }

    final kcalGap = context.targets.kcal - context.consumed.kcal;
    if (kcalGap < -200) {
      insights.add(
        CoachInsight(
          category: CoachCategory.nutrition,
          headline: 'You are ${(-kcalGap).round()} kcal over target',
          detail:
              'One day over will not undo a week. Log the rest honestly and '
              'return to target tomorrow rather than compensating by '
              'under-eating.',
          evidence: [
            (label: 'Logged', value: '${context.consumed.kcal.round()} kcal'),
            (label: 'Target', value: '${context.targets.kcal.round()} kcal'),
          ],
          impact: 60,
        ),
      );
    } else if (kcalGap > 500 && context.consumed.kcal > 0) {
      insights.add(
        CoachInsight(
          category: CoachCategory.nutrition,
          headline: 'You have ${kcalGap.round()} kcal left today',
          detail:
              'There is room for a full meal. Under-eating by this much is not '
              'faster progress — it costs training quality and muscle.',
          evidence: [
            (label: 'Remaining', value: '${kcalGap.round()} kcal'),
          ],
          impact: 55,
        ),
      );
    }

    if (context.waterTargetMl > 0 &&
        context.waterMl < context.waterTargetMl * 0.6) {
      final deficit = context.waterTargetMl - context.waterMl;
      insights.add(
        CoachInsight(
          category: CoachCategory.habits,
          headline: 'You are $deficit ml behind on water',
          detail: 'Hydration is the cheapest performance variable you control.',
          evidence: [
            (label: 'Logged', value: '${context.waterMl} ml'),
            (label: 'Target', value: '${context.waterTargetMl} ml'),
          ],
          impact: 40,
        ),
      );
    }

    if (context.supplementsScheduled > 0 &&
        context.supplementsTaken < context.supplementsScheduled) {
      final missed = context.supplementsScheduled - context.supplementsTaken;
      insights.add(
        CoachInsight(
          category: CoachCategory.habits,
          headline: '$missed supplement${missed == 1 ? '' : 's'} still due',
          detail: 'Consistency is what makes a supplement worth taking at all.',
          evidence: [
            (
              label: 'Taken',
              value: '${context.supplementsTaken} of '
                  '${context.supplementsScheduled}'
            ),
          ],
          impact: 35,
        ),
      );
    }

    if (context.sessionsThisWeek == 0) {
      insights.add(
        const CoachInsight(
          category: CoachCategory.training,
          headline: 'No sessions logged this week',
          detail:
              'One short session beats a perfect one you never start. Pick a '
              'program and log something today.',
          evidence: [(label: 'Sessions', value: '0')],
          impact: 80,
        ),
      );
    } else if (context.sessionsThisWeek >= 5 && !context.trainedToday) {
      insights.add(
        CoachInsight(
          category: CoachCategory.recovery,
          headline: 'You have trained ${context.sessionsThisWeek} times this week',
          detail:
              'That is a full week of work. A rest day now is what lets the '
              'training you already did turn into progress.',
          evidence: [
            (label: 'Sessions', value: '${context.sessionsThisWeek}'),
            (label: 'Volume', value: '${context.weeklyVolumeKg.round()} kg'),
          ],
          impact: 50,
        ),
      );
    }

    final change = context.weightChangeKg;
    if (change != null && change.abs() >= 0.5) {
      insights.add(
        CoachInsight(
          category: CoachCategory.habits,
          headline: 'Bodyweight ${change > 0 ? 'up' : 'down'} '
              '${change.abs().toStringAsFixed(1)} kg over 30 days',
          detail: change > 0
              ? 'Weight is trending up. If that is not the goal, the calorie '
                  'target is the first thing to check.'
              : 'Weight is trending down. Keep protein high so what you lose '
                  'is fat rather than muscle.',
          evidence: [
            (
              label: '30-day change',
              value: '${change > 0 ? '+' : ''}${change.toStringAsFixed(1)} kg'
            ),
          ],
          impact: 45,
        ),
      );
    }

    if (insights.isEmpty) {
      insights.add(
        const CoachInsight(
          category: CoachCategory.habits,
          headline: 'Everything is on track',
          detail:
              'Targets met and training logged. Protect your sleep tonight and '
              'do the same tomorrow.',
          evidence: [],
          impact: 0,
        ),
      );
    }

    insights.sort((a, b) => b.impact.compareTo(a.impact));
    return insights;
  }
}

/// One piece of deterministic guidance, with the numbers that produced it.
class CoachInsight {
  const CoachInsight({
    required this.category,
    required this.headline,
    required this.detail,
    required this.evidence,
    required this.impact,
  });

  final CoachCategory category;
  final String headline;
  final String detail;

  /// The values behind the statement. Never empty for a data-driven insight —
  /// a claim the user cannot check is a claim they should not trust.
  final List<({String label, String value})> evidence;

  /// 0–100, drives ordering.
  final int impact;
}

/// An external assistant the user can hand their brief to.
///
/// These are SHORTCUTS, not integrations: the app composes the text, shows it,
/// and opens the assistant. No API key ships in the binary and no request is
/// made on the user's behalf.
enum ExternalAssistant {
  claude(
    'Claude',
    'https://claude.ai/new',
    'Anthropic',
  ),
  copilot(
    'Microsoft Copilot',
    'https://copilot.microsoft.com',
    'Microsoft',
  );

  const ExternalAssistant(this.label, this.url, this.vendor);
  final String label;
  final String url;
  final String vendor;
}
