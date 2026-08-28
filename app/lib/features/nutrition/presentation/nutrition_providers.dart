import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:lifedna/core/providers/providers.dart';
import 'package:lifedna/features/nutrition/domain/nutrition_entities.dart';
import 'package:lifedna/shared/value_objects/macros.dart';

final foodsProvider = StreamProvider<List<FoodItem>>(
  (ref) => ref.watch(nutritionRepositoryProvider).watchFoods(),
);

final mealsProvider = StreamProvider<List<Meal>>(
  (ref) => ref.watch(nutritionRepositoryProvider).watchMeals(),
);

final nutritionLogsProvider = StreamProvider<List<NutritionLog>>(
  (ref) => ref.watch(nutritionRepositoryProvider).watchLogs(),
);

/// The user's macro targets: their override if set, otherwise the engine's
/// derivation from their profile.
final macroTargetsProvider = Provider<MacroTargets>((ref) {
  final profile = ref.watch(profileProvider).valueOrNull;

  if (profile != null && profile.targetsOverridden) {
    return MacroTargets(
      kcal: profile.overrideKcal ?? 2000,
      proteinG: profile.overrideProteinG ?? 150,
      carbsG: profile.overrideCarbsG ?? 200,
      fatG: profile.overrideFatG ?? 65,
      proteinFloorG: profile.overrideProteinG ?? 150,
    );
  }

  final computed = profile?.computedTargets;
  if (computed == null) {
    // Before onboarding completes there is no body data to derive from.
    // These are visibly generic defaults, not a personalised claim.
    return const MacroTargets(
      kcal: 2000,
      proteinG: 150,
      carbsG: 200,
      fatG: 65,
      proteinFloorG: 150,
    );
  }
  return computed.restDay;
});

final waterTargetProvider = Provider<int>((ref) {
  final profile = ref.watch(profileProvider).valueOrNull;
  return profile?.overrideWaterMl ?? profile?.computedTargets?.waterMl ?? 2500;
});

/// Today's nutrition, derived from the log stream so it can never disagree
/// with the entries it summarises.
final todayNutritionProvider = Provider<DailyNutrition>((ref) {
  ref.watch(nutritionLogsProvider);
  final localDate = ref.watch(todayLocalDateProvider);
  final entries = ref.watch(nutritionRepositoryProvider).logsForDate(localDate);
  return DailyNutrition(
    localDate: localDate,
    entries: entries,
    targets: ref.watch(macroTargetsProvider),
  );
});

/// Days with any logged entry, newest first — the meal history list.
final nutritionHistoryProvider =
    Provider<List<({String localDate, Macros totals, int entries})>>((ref) {
      final logs = ref.watch(nutritionLogsProvider).valueOrNull ?? const [];
      final byDate = <String, ({Macros totals, int entries})>{};

      for (final log in logs) {
        if (!log.isFood) continue;
        final current =
            byDate[log.localDate] ?? (totals: Macros.zero, entries: 0);
        byDate[log.localDate] = (
          totals: current.totals + log.macros,
          entries: current.entries + 1,
        );
      }

      final out =
          byDate.entries
              .map(
                (e) => (
                  localDate: e.key,
                  totals: e.value.totals,
                  entries: e.value.entries,
                ),
              )
              .toList()
            ..sort((a, b) => b.localDate.compareTo(a.localDate));
      return out;
    });
