import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';
import 'package:lifedna/core/providers/providers.dart';
import 'package:lifedna/core/router/app_router.dart';
import 'package:lifedna/core/theme/app_theme.dart';
import 'package:lifedna/core/theme/ld_spacing.dart';
import 'package:lifedna/core/widgets/ld_widgets.dart';
import 'package:lifedna/features/ai_hub/presentation/ai_providers.dart';
import 'package:lifedna/features/calendar/presentation/calendar_providers.dart';
import 'package:lifedna/features/nutrition/presentation/nutrition_providers.dart';
import 'package:lifedna/features/supplements/presentation/supplement_providers.dart';
import 'package:lifedna/features/sync/presentation/sync_providers.dart';
import 'package:lifedna/features/workout/presentation/workout_providers.dart';

/// The dashboard.
///
/// Every card answers a question the user actually has right now, and every
/// number on it is live — nothing here is illustrative.
class DashboardScreen extends ConsumerWidget {
  const DashboardScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final c = context.ldColors;
    final type = context.ldType;

    final profile = ref.watch(profileProvider).valueOrNull;
    final nutrition = ref.watch(todayNutritionProvider);
    final targets = ref.watch(macroTargetsProvider);
    final waterTarget = ref.watch(waterTargetProvider);
    final now = ref.watch(clockProvider)();

    return Scaffold(
      body: RefreshIndicator(
        onRefresh: () => _refresh(ref),
        child: ListView(
          padding: const EdgeInsets.fromLTRB(
            LdSpacing.s4,
            LdSpacing.s3,
            LdSpacing.s4,
            LdSpacing.scrollBottom,
          ),
          children: [
            Text(
              '${_greeting(now)}, ${profile?.displayName.split(' ').first ?? 'Athlete'}',
              style: type.headlineL.copyWith(color: c.textPrimary),
            ),
            const SizedBox(height: LdSpacing.s1),
            Text(
              DateFormat('EEEE d MMMM').format(now).toUpperCase(),
              style: type.labelMono.copyWith(color: c.textTertiary),
            ),
            const SizedBox(height: LdSpacing.s5),

            const _CoachCard(),
            const SizedBox(height: LdSpacing.cardGap),

            // ---- Calories and protein ----
            LdCard(
              eyebrow: "Today's fuel",
              onTap: () => context.go(Routes.nutrition),
              trailing: Text(
                '${_int(nutrition.totals.kcal)} / ${_int(targets.kcal)} kcal',
                style: type.bodyS.copyWith(color: c.textSecondary),
              ),
              child: Column(
                children: [
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                    children: [
                      LdProgressRing(
                        value: nutrition.totals.kcal,
                        target: targets.kcal,
                        label: 'kcal',
                        unit: 'kcal',
                        color: c.calories,
                        size: LdRingSize.l,
                      ),
                      LdProgressRing(
                        value: nutrition.totals.proteinG,
                        target: targets.proteinG,
                        label: 'protein',
                        unit: 'g',
                        color: c.protein,
                        size: LdRingSize.l,
                      ),
                    ],
                  ),
                  const SizedBox(height: LdSpacing.s4),
                  LdStatRow(
                    label: 'carbs',
                    value:
                        '${_int(nutrition.totals.carbsG)} / '
                        '${_int(targets.carbsG)} g',
                    progress: targets.carbsG <= 0
                        ? 0
                        : nutrition.totals.carbsG / targets.carbsG,
                    color: c.carbs,
                  ),
                  LdStatRow(
                    label: 'fat',
                    value:
                        '${_int(nutrition.totals.fatG)} / '
                        '${_int(targets.fatG)} g',
                    progress: targets.fatG <= 0
                        ? 0
                        : nutrition.totals.fatG / targets.fatG,
                    color: c.fat,
                  ),
                ],
              ),
            ),
            const SizedBox(height: LdSpacing.cardGap),

            // ---- Water ----
            _WaterCard(consumed: nutrition.waterMl, target: waterTarget),
            const SizedBox(height: LdSpacing.cardGap),

            const _WorkoutCard(),
            const SizedBox(height: LdSpacing.cardGap),

            const _RecoveryCard(),
            const SizedBox(height: LdSpacing.cardGap),

            const _SupplementsCard(),
            const SizedBox(height: LdSpacing.cardGap),

            const _TasksCard(),
            const SizedBox(height: LdSpacing.cardGap),

            const _EventsCard(),
          ],
        ),
      ),
    );
  }

  static Future<void> _refresh(WidgetRef ref) async {
    // Pull-to-refresh pushes what is queued, then pulls every collection.
    // It never blocks the UI on the result — local data is already correct.
    await ref.read(remotePullProvider).refresh();
  }

  static String _greeting(DateTime now) {
    if (now.hour < 12) return 'Good morning';
    if (now.hour < 18) return 'Good afternoon';
    return 'Good evening';
  }

  static String _int(double v) =>
      NumberFormat.decimalPattern().format(v.round());
}

class _CoachCard extends ConsumerWidget {
  const _CoachCard();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final c = context.ldColors;
    final type = context.ldType;
    final insights = ref.watch(coachInsightsProvider);
    if (insights.isEmpty) return const SizedBox.shrink();
    final top = insights.first;

    return LdCard(
      variant: LdCardVariant.elevated,
      eyebrow: 'Coach',
      accentColor: c.primary,
      onTap: () => context.push(Routes.aiHub),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(top.headline, style: type.titleL.copyWith(color: c.textPrimary)),
          const SizedBox(height: LdSpacing.s2),
          Text(top.detail, style: type.bodyS.copyWith(color: c.textSecondary)),
          if (top.evidence.isNotEmpty) ...[
            const SizedBox(height: LdSpacing.s3),
            Wrap(
              spacing: LdSpacing.s2,
              runSpacing: LdSpacing.s2,
              children: [
                for (final item in top.evidence)
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: LdSpacing.s3,
                      vertical: LdSpacing.s1,
                    ),
                    decoration: BoxDecoration(
                      color: c.surfaceHighest,
                      borderRadius: BorderRadius.circular(LdRadius.full),
                    ),
                    child: Text(
                      '${item.label}: ${item.value}',
                      style: type.caption.copyWith(color: c.textSecondary),
                    ),
                  ),
              ],
            ),
          ],
        ],
      ),
    );
  }
}

class _WaterCard extends ConsumerWidget {
  const _WaterCard({required this.consumed, required this.target});
  final int consumed;
  final int target;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final c = context.ldColors;
    return LdCard(
      eyebrow: 'Water',
      accentColor: c.water,
      child: Column(
        children: [
          LdStatRow(
            label: 'hydration',
            value: '$consumed / $target ml',
            progress: target <= 0 ? 0 : consumed / target,
            color: c.water,
          ),
          const SizedBox(height: LdSpacing.s2),
          Row(
            children: [
              for (final ml in [250, 500, 750]) ...[
                Expanded(
                  child: LdPrimaryButton(
                    label: '+$ml',
                    size: LdButtonSize.s,
                    variant: LdButtonVariant.secondary,
                    onPressed: () async {
                      final result = await ref
                          .read(nutritionRepositoryProvider)
                          .logWater(ml);
                      if (!context.mounted) return;
                      final failure = result.failureOrNull;
                      if (failure != null) showFailureSnack(context, failure);
                    },
                  ),
                ),
                if (ml != 750) const SizedBox(width: LdSpacing.s2),
              ],
            ],
          ),
        ],
      ),
    );
  }
}

class _WorkoutCard extends ConsumerWidget {
  const _WorkoutCard();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final c = context.ldColors;
    final type = context.ldType;
    final active = ref.watch(activeSessionProvider).valueOrNull;
    final trainedToday = ref.watch(trainedTodayProvider);
    final sessionsThisWeek = ref.watch(sessionsThisWeekProvider);

    final (title, subtitle, action) = active != null
        ? ('Workout in progress', active.name, 'Resume workout')
        : trainedToday
        ? (
            'Trained today',
            '$sessionsThisWeek session${sessionsThisWeek == 1 ? '' : 's'} '
                'this week',
            'Start another',
          )
        : (
            'No workout logged today',
            '$sessionsThisWeek session${sessionsThisWeek == 1 ? '' : 's'} '
                'this week',
            'Start workout',
          );

    return LdCard(
      eyebrow: 'Training',
      accentColor: c.primary,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(title, style: type.titleL.copyWith(color: c.textPrimary)),
          const SizedBox(height: LdSpacing.s1),
          Text(subtitle, style: type.bodyS.copyWith(color: c.textSecondary)),
          const SizedBox(height: LdSpacing.s4),
          LdPrimaryButton(
            label: action,
            size: LdButtonSize.l,
            onPressed: () => context.push(
              active != null ? Routes.liveWorkout : Routes.train,
            ),
          ),
        ],
      ),
    );
  }
}

/// Recovery overview.
///
/// Deliberately NOT a single invented "recovery score": without sleep or heart
/// rate data there is nothing to compute one from, and a number with no inputs
/// is a lie. This shows the load signals the app genuinely has.
class _RecoveryCard extends ConsumerWidget {
  const _RecoveryCard();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final c = context.ldColors;
    final type = context.ldType;
    final sessions = ref.watch(sessionsThisWeekProvider);
    final volume = ref.watch(weeklyVolumeProvider);
    final thisWeek = volume.isEmpty ? 0.0 : volume.last.volumeKg;
    final lastWeek = volume.length < 2
        ? null
        : volume[volume.length - 2].volumeKg;

    final change = (lastWeek == null || lastWeek == 0)
        ? null
        : (thisWeek - lastWeek) / lastWeek * 100;

    return LdCard(
      eyebrow: 'Recovery',
      accentColor: c.secondary,
      onTap: () => context.push(Routes.healthSync),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: _Stat(label: 'Sessions this week', value: '$sessions'),
              ),
              Expanded(
                child: _Stat(
                  label: 'Volume this week',
                  value: '${(thisWeek / 1000).toStringAsFixed(1)}k kg',
                ),
              ),
            ],
          ),
          if (change != null) ...[
            const SizedBox(height: LdSpacing.s3),
            Text(
              '${change >= 0 ? '+' : ''}${change.round()} % vs last week',
              style: type.bodyS.copyWith(
                color: change.abs() > 40 ? c.warning : c.textSecondary,
              ),
            ),
          ],
          const SizedBox(height: LdSpacing.s3),
          Text(
            'Connect Health Connect to add sleep and heart rate.',
            style: type.caption.copyWith(color: c.textTertiary),
          ),
        ],
      ),
    );
  }
}

class _Stat extends StatelessWidget {
  const _Stat({required this.label, required this.value});
  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    final c = context.ldColors;
    final type = context.ldType;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          label.toUpperCase(),
          style: type.labelMono.copyWith(color: c.textTertiary),
        ),
        const SizedBox(height: LdSpacing.s1),
        Text(value, style: type.displayM.copyWith(color: c.textPrimary)),
      ],
    );
  }
}

class _SupplementsCard extends ConsumerWidget {
  const _SupplementsCard();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final c = context.ldColors;
    final type = context.ldType;
    final today = ref.watch(todaySupplementsProvider);
    if (today.isEmpty) return const SizedBox.shrink();

    final taken = today.where((e) => e.taken).length;

    return LdCard(
      eyebrow: 'Supplements',
      onTap: () => context.push(Routes.supplements),
      trailing: Text(
        '$taken / ${today.length}',
        style: type.bodyS.copyWith(color: c.textSecondary),
      ),
      child: Wrap(
        spacing: LdSpacing.s2,
        runSpacing: LdSpacing.s2,
        children: [
          for (final entry in today)
            Container(
              padding: const EdgeInsets.symmetric(
                horizontal: LdSpacing.s3,
                vertical: LdSpacing.s2,
              ),
              decoration: BoxDecoration(
                color: c.surfaceElevated,
                borderRadius: BorderRadius.circular(LdRadius.full),
                border: Border.all(color: c.border),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(
                    entry.taken
                        ? Icons.check_circle_rounded
                        : Icons.schedule_rounded,
                    size: 14,
                    color: entry.taken ? c.success : c.accent,
                  ),
                  const SizedBox(width: LdSpacing.s2),
                  Text(
                    entry.supplement.name,
                    style: type.bodyS.copyWith(color: c.textSecondary),
                  ),
                ],
              ),
            ),
        ],
      ),
    );
  }
}

class _TasksCard extends ConsumerWidget {
  const _TasksCard();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final c = context.ldColors;
    final type = context.ldType;
    final tasks = ref.watch(openTasksProvider).take(4).toList();
    final overdue = ref.watch(overdueTaskCountProvider);

    return LdCard(
      eyebrow: 'Tasks',
      onTap: () => context.push(Routes.plan),
      trailing: overdue > 0
          ? Text(
              '$overdue overdue',
              style: type.bodyS.copyWith(color: c.danger),
            )
          : null,
      child: tasks.isEmpty
          ? Text(
              'Nothing outstanding.',
              style: type.bodyS.copyWith(color: c.textTertiary),
            )
          : Column(
              children: [
                for (final task in tasks)
                  Padding(
                    padding: const EdgeInsets.only(bottom: LdSpacing.s2),
                    child: Row(
                      children: [
                        Container(
                          width: 3,
                          height: 16,
                          decoration: BoxDecoration(
                            color: task.priority.level <= 2
                                ? c.primary
                                : c.border,
                            borderRadius: BorderRadius.circular(LdRadius.full),
                          ),
                        ),
                        const SizedBox(width: LdSpacing.s3),
                        Expanded(
                          child: Text(
                            task.title,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: type.bodyM.copyWith(color: c.textPrimary),
                          ),
                        ),
                        if (task.dueAt != null)
                          Text(
                            DateFormat('d MMM').format(task.dueAt!.toLocal()),
                            style: type.caption.copyWith(
                              color: task.isOverdue(DateTime.now())
                                  ? c.danger
                                  : c.textTertiary,
                            ),
                          ),
                      ],
                    ),
                  ),
              ],
            ),
    );
  }
}

class _EventsCard extends ConsumerWidget {
  const _EventsCard();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final c = context.ldColors;
    final type = context.ldType;
    final events = ref.watch(upcomingEventsProvider);

    return LdCard(
      eyebrow: 'Upcoming',
      onTap: () => context.push(Routes.plan),
      child: events.isEmpty
          ? Text(
              'No events scheduled.',
              style: type.bodyS.copyWith(color: c.textTertiary),
            )
          : Column(
              children: [
                for (final event in events)
                  Padding(
                    padding: const EdgeInsets.only(bottom: LdSpacing.s2),
                    child: Row(
                      children: [
                        SizedBox(
                          width: 52,
                          child: Text(
                            DateFormat('HH:mm').format(event.startAt.toLocal()),
                            style: type.bodyS.copyWith(color: c.textSecondary),
                          ),
                        ),
                        Expanded(
                          child: Text(
                            event.title,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: type.bodyM.copyWith(color: c.textPrimary),
                          ),
                        ),
                        if (event.isReadOnly)
                          Icon(
                            Icons.event_rounded,
                            size: 14,
                            color: c.textTertiary,
                          ),
                      ],
                    ),
                  ),
              ],
            ),
    );
  }
}
