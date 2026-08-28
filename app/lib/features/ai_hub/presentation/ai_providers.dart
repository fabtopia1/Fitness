import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:lifedna/core/providers/providers.dart';
import 'package:lifedna/features/ai_hub/domain/ai_coach.dart';
import 'package:lifedna/features/body/presentation/body_providers.dart';
import 'package:lifedna/features/nutrition/presentation/nutrition_providers.dart';
import 'package:lifedna/features/supplements/presentation/supplement_providers.dart';
import 'package:lifedna/features/workout/presentation/workout_providers.dart';

/// Assembles the user's own numbers for the coach.
///
/// Everything here is already visible elsewhere in the app — the coach adds
/// interpretation, not private data.
final coachContextProvider = Provider<CoachContext>((ref) {
  final nutrition = ref.watch(todayNutritionProvider);
  final profile = ref.watch(profileProvider).valueOrNull;
  final supplements = ref.watch(todaySupplementsProvider);
  final volume = ref.watch(weeklyVolumeProvider);
  final history = ref.watch(workoutHistoryProvider);

  return CoachContext(
    consumed: nutrition.totals,
    targets: ref.watch(macroTargetsProvider),
    waterMl: nutrition.waterMl,
    waterTargetMl: ref.watch(waterTargetProvider),
    trainedToday: ref.watch(trainedTodayProvider),
    sessionsThisWeek: ref.watch(sessionsThisWeekProvider),
    weeklyVolumeKg: volume.isEmpty ? 0 : volume.last.volumeKg,
    supplementsTaken: supplements.where((s) => s.taken).length,
    supplementsScheduled: supplements.length,
    weightKg: profile?.weightKg == 0 ? null : profile?.weightKg,
    weightChangeKg: ref.watch(weightChangeProvider),
    goalLabel: profile == null ? null : _goalLabel(profile.goalMode.wire),
    lastSessionName: history.isEmpty ? null : history.first.name,
  );
});

final coachInsightsProvider = Provider<List<CoachInsight>>(
  (ref) => LocalCoach.analyse(ref.watch(coachContextProvider)),
);

String _goalLabel(String mode) => switch (mode) {
  'cut' => 'Lose fat',
  'bulk' => 'Build muscle',
  _ => 'Maintain',
};
