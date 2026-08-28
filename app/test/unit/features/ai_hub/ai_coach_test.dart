import 'package:flutter_test/flutter_test.dart';
import 'package:lifedna/features/ai_hub/domain/ai_coach.dart';
import 'package:lifedna/shared/value_objects/macros.dart';

void main() {
  const targets = MacroTargets(
    kcal: 2500,
    proteinG: 180,
    carbsG: 280,
    fatG: 75,
    proteinFloorG: 180,
  );

  CoachContext context({
    Macros consumed = const Macros(
      kcal: 2500,
      proteinG: 180,
      carbsG: 280,
      fatG: 75,
    ),
    int waterMl = 3000,
    int waterTargetMl = 3000,
    bool trainedToday = true,
    int sessionsThisWeek = 4,
    int supplementsTaken = 2,
    int supplementsScheduled = 2,
    double? weightChangeKg,
  }) =>
      CoachContext(
        consumed: consumed,
        targets: targets,
        waterMl: waterMl,
        waterTargetMl: waterTargetMl,
        trainedToday: trainedToday,
        sessionsThisWeek: sessionsThisWeek,
        weeklyVolumeKg: 24000,
        supplementsTaken: supplementsTaken,
        supplementsScheduled: supplementsScheduled,
        weightKg: 82.4,
        weightChangeKg: weightChangeKg,
        goalLabel: 'Lose fat',
        lastSessionName: 'Push A',
      );

  group('LocalCoach.analyse', () {
    test('a day that meets every target still says something useful', () {
      // An empty coach screen reads as a broken coach.
      final insights = LocalCoach.analyse(context());
      expect(insights, hasLength(1));
      expect(insights.single.headline, 'Everything is on track');
    });

    test('a protein shortfall outranks everything else', () {
      final insights = LocalCoach.analyse(
        context(
          consumed: const Macros(kcal: 2500, proteinG: 100, carbsG: 280, fatG: 75),
          waterMl: 500,
          supplementsTaken: 0,
        ),
      );

      expect(insights.first.category, CoachCategory.nutrition);
      expect(insights.first.headline, contains('80 g short on protein'));
      // Ordered by impact, so the first card is the thing most worth doing.
      for (var i = 1; i < insights.length; i++) {
        expect(
          insights[i - 1].impact,
          greaterThanOrEqualTo(insights[i].impact),
        );
      }
    });

    test('being over and being under produce different advice', () {
      final over = LocalCoach.analyse(
        context(
          consumed: const Macros(
            kcal: 3200,
            proteinG: 180,
            carbsG: 400,
            fatG: 90,
          ),
        ),
      );
      expect(over.first.headline, contains('over target'));

      final under = LocalCoach.analyse(
        context(
          consumed: const Macros(
            kcal: 1200,
            proteinG: 180,
            carbsG: 100,
            fatG: 40,
          ),
        ),
      );
      expect(
        under.map((i) => i.headline).join(' '),
        contains('kcal left today'),
      );
    });

    test('a day with nothing logged is not reported as under-eating', () {
      // At 07:00 a user has eaten nothing yet. Telling them they are 2500 kcal
      // behind is noise, not coaching.
      final insights = LocalCoach.analyse(
        context(consumed: Macros.zero, sessionsThisWeek: 4),
      );
      expect(
        insights.map((i) => i.headline).join(' '),
        isNot(contains('kcal left today')),
      );
    });

    test('no sessions this week is a high-impact training insight', () {
      final insights = LocalCoach.analyse(
        context(sessionsThisWeek: 0, trainedToday: false),
      );
      expect(insights.first.category, CoachCategory.training);
      expect(insights.first.impact, 80);
    });

    test('a heavy week without training today suggests recovery', () {
      final insights = LocalCoach.analyse(
        context(sessionsThisWeek: 6, trainedToday: false),
      );
      expect(
        insights.map((i) => i.category),
        contains(CoachCategory.recovery),
      );
    });

    test('a weight change smaller than the noise floor is not reported', () {
      expect(
        LocalCoach.analyse(context(weightChangeKg: 0.3))
            .map((i) => i.headline)
            .join(' '),
        isNot(contains('Bodyweight')),
      );
      expect(
        LocalCoach.analyse(context(weightChangeKg: -1.2))
            .map((i) => i.headline)
            .join(' '),
        contains('Bodyweight down 1.2 kg'),
      );
    });

    test('every insight carries the numbers that produced it', () {
      final insights = LocalCoach.analyse(
        context(
          consumed: const Macros(kcal: 1000, proteinG: 60, carbsG: 100, fatG: 30),
          waterMl: 500,
          supplementsTaken: 0,
          sessionsThisWeek: 0,
          trainedToday: false,
        ),
      );

      for (final insight in insights) {
        expect(insight.headline, isNotEmpty);
        expect(insight.detail, isNotEmpty);
        // "Because you logged X against Y" is what separates advice from a
        // horoscope.
        expect(insight.evidence, isNotEmpty, reason: insight.headline);
      }
    });

    test('a zero water target does not divide by zero', () {
      expect(
        () => LocalCoach.analyse(context(waterMl: 0, waterTargetMl: 0)),
        returnsNormally,
      );
    });
  });

  group('the brief that leaves the device', () {
    test('contains only the numbers shown on screen', () {
      final brief = context().toBrief();

      expect(brief, contains('Calories: 2500 of 2500 kcal'));
      expect(brief, contains('Protein: 180 of 180 g'));
      expect(brief, contains('Water: 3000 of 3000 ml'));
      expect(brief, contains('Trained today: yes (Push A)'));
      // No identifiers of any kind travel with it.
      expect(brief.toLowerCase(), isNot(contains('@')));
      expect(brief.toLowerCase(), isNot(contains('uid')));
    });

    test('omits fields the user has not recorded', () {
      const empty = CoachContext(
        consumed: Macros.zero,
        targets: targets,
        waterMl: 0,
        waterTargetMl: 3000,
        trainedToday: false,
        sessionsThisWeek: 0,
        weeklyVolumeKg: 0,
        supplementsTaken: 0,
        supplementsScheduled: 0,
      );
      final brief = empty.toBrief();

      expect(brief, isNot(contains('Bodyweight')));
      expect(brief, isNot(contains('Goal:')));
      expect(brief, contains('Trained today: no'));
    });
  });

  group('prompt templates and assistant shortcuts', () {
    test('every prompt is complete and categorised', () {
      expect(LocalCoach.prompts, isNotEmpty);
      for (final prompt in LocalCoach.prompts) {
        expect(prompt.id, isNotEmpty);
        expect(prompt.title, isNotEmpty);
        expect(prompt.question, isNotEmpty);
      }
    });

    test('prompt ids are unique, so a copy action cannot be ambiguous', () {
      final ids = LocalCoach.prompts.map((p) => p.id).toSet();
      expect(ids, hasLength(LocalCoach.prompts.length));
    });

    test('each assistant is a plain https destination, not an API', () {
      // Nothing here holds a key or calls a model. The shortcut opens the
      // assistant the user already pays for.
      for (final assistant in ExternalAssistant.values) {
        expect(assistant.url, startsWith('https://'));
        expect(assistant.label, isNotEmpty);
        expect(assistant.vendor, isNotEmpty);
        expect(Uri.tryParse(assistant.url), isNotNull);
      }
    });
  });
}
