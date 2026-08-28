import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';
import 'package:lifedna/core/providers/providers.dart';
import 'package:lifedna/core/router/app_router.dart';
import 'package:lifedna/core/theme/app_theme.dart';
import 'package:lifedna/core/theme/ld_spacing.dart';
import 'package:lifedna/core/widgets/ld_widgets.dart';
import 'package:lifedna/features/workout/domain/workout_entities.dart';
import 'package:lifedna/features/workout/presentation/workout_providers.dart';

class WorkoutScreen extends ConsumerWidget {
  const WorkoutScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final c = context.ldColors;
    final workoutsAsync = ref.watch(workoutsProvider);
    final active = ref.watch(activeSessionProvider).valueOrNull;

    return Scaffold(
      appBar: AppBar(
        title: const Text('Train'),
        actions: [
          IconButton(
            icon: const Icon(Icons.fitness_center_rounded),
            tooltip: 'Exercise library',
            onPressed: () => context.push(Routes.exerciseLibrary),
          ),
        ],
      ),
      body: LdAsyncView(
        value: workoutsAsync,
        onRetry: () => ref.invalidate(workoutsProvider),
        errorContext: 'Workouts',
        data: (workouts) {
          final history = ref.watch(workoutHistoryProvider);
          final records = ref.watch(personalRecordsProvider);
          final volume = ref.watch(weeklyVolumeProvider);

          return ListView(
            padding: const EdgeInsets.fromLTRB(
              LdSpacing.s4,
              LdSpacing.s3,
              LdSpacing.s4,
              LdSpacing.scrollBottom,
            ),
            children: [
              if (active != null)
                LdCard(
                  variant: LdCardVariant.elevated,
                  eyebrow: 'In progress',
                  accentColor: c.primary,
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        active.name,
                        style: context.ldType.titleL.copyWith(
                          color: c.textPrimary,
                        ),
                      ),
                      const SizedBox(height: LdSpacing.s1),
                      Text(
                        '${active.sets.length} sets logged',
                        style: context.ldType.bodyS.copyWith(
                          color: c.textSecondary,
                        ),
                      ),
                      const SizedBox(height: LdSpacing.s4),
                      LdPrimaryButton(
                        label: 'Resume workout',
                        size: LdButtonSize.l,
                        onPressed: () => context.push(Routes.liveWorkout),
                      ),
                    ],
                  ),
                )
              else
                LdCard(
                  eyebrow: 'Quick start',
                  accentColor: c.primary,
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Start an empty session',
                        style: context.ldType.titleL.copyWith(
                          color: c.textPrimary,
                        ),
                      ),
                      const SizedBox(height: LdSpacing.s1),
                      Text(
                        'Add exercises as you go.',
                        style: context.ldType.bodyS.copyWith(
                          color: c.textSecondary,
                        ),
                      ),
                      const SizedBox(height: LdSpacing.s4),
                      LdPrimaryButton(
                        label: 'Start empty workout',
                        size: LdButtonSize.l,
                        onPressed: () => _start(context, ref, null),
                      ),
                    ],
                  ),
                ),
              if (volume.any((w) => w.volumeKg > 0)) ...[
                const LdSectionHeader(title: 'Weekly volume'),
                _VolumeChart(data: volume),
              ],
              LdSectionHeader(
                title: 'Programs',
                actionLabel: 'New',
                onAction: () => context.push(Routes.workoutEditor),
              ),
              if (workouts.isEmpty)
                LdEmptyState(
                  icon: Icons.list_alt_rounded,
                  headline: 'No programs yet',
                  body: 'Build a program once and start it in one tap.',
                  actionLabel: 'Create program',
                  onAction: () => context.push(Routes.workoutEditor),
                )
              else
                for (final workout in workouts)
                  _WorkoutTile(
                    workout: workout,
                    onStart: () => _start(context, ref, workout),
                    onEdit: () => context.push(
                      '${Routes.workoutEditor}?id=${workout.id}',
                    ),
                  ),
              if (records.isNotEmpty) ...[
                const LdSectionHeader(title: 'Personal records'),
                for (final record in records.take(5))
                  ListTile(
                    contentPadding: EdgeInsets.zero,
                    leading: Icon(Icons.emoji_events_rounded, color: c.accent),
                    title: Text(
                      record.exerciseName,
                      style: context.ldType.titleM.copyWith(
                        color: c.textPrimary,
                      ),
                    ),
                    subtitle: Text(
                      'Est. 1RM ${record.value.toStringAsFixed(1)} kg · '
                      '${_fmt(record.weightKg)} kg × ${record.reps}',
                      style: context.ldType.bodyS.copyWith(
                        color: c.textSecondary,
                      ),
                    ),
                    trailing: Text(
                      DateFormat('d MMM').format(record.achievedAt.toLocal()),
                      style: context.ldType.caption.copyWith(
                        color: c.textTertiary,
                      ),
                    ),
                  ),
              ],
              const LdSectionHeader(title: 'History'),
              if (history.isEmpty)
                Text(
                  'No completed sessions yet.',
                  style: context.ldType.bodyS.copyWith(color: c.textTertiary),
                )
              else
                for (final session in history.take(10))
                  _SessionTile(session: session),
            ],
          );
        },
      ),
    );
  }

  static Future<void> _start(
    BuildContext context,
    WidgetRef ref,
    Workout? workout,
  ) async {
    final result = await ref
        .read(workoutRepositoryProvider)
        .startSession(workout: workout);
    if (!context.mounted) return;
    result.when(
      ok: (_) => context.push(Routes.liveWorkout),
      err: (failure) => showFailureSnack(context, failure),
    );
  }

  static String _fmt(double v) =>
      v == v.roundToDouble() ? v.round().toString() : v.toStringAsFixed(1);
}

class _WorkoutTile extends StatelessWidget {
  const _WorkoutTile({
    required this.workout,
    required this.onStart,
    required this.onEdit,
  });

  final Workout workout;
  final VoidCallback onStart;
  final VoidCallback onEdit;

  @override
  Widget build(BuildContext context) {
    final c = context.ldColors;
    final type = context.ldType;

    return Padding(
      padding: const EdgeInsets.only(bottom: LdSpacing.s2),
      child: LdCard(
        padding: const EdgeInsets.all(LdSpacing.s3),
        onTap: onStart,
        child: Row(
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    workout.name,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: type.titleM.copyWith(color: c.textPrimary),
                  ),
                  const SizedBox(height: LdSpacing.s1),
                  Text(
                    '${workout.exercises.length} exercises · '
                    '${workout.totalSets} sets · ~${workout.estimatedMinutes} min',
                    style: type.bodyS.copyWith(color: c.textTertiary),
                  ),
                ],
              ),
            ),
            IconButton(
              icon: const Icon(Icons.edit_outlined),
              onPressed: onEdit,
              tooltip: 'Edit',
            ),
            Icon(Icons.play_arrow_rounded, color: c.primary),
          ],
        ),
      ),
    );
  }
}

class _SessionTile extends StatelessWidget {
  const _SessionTile({required this.session});
  final WorkoutSession session;

  @override
  Widget build(BuildContext context) {
    final c = context.ldColors;
    final type = context.ldType;
    final duration = session.finishedAt?.difference(session.startedAt);

    return Padding(
      padding: const EdgeInsets.only(bottom: LdSpacing.s2),
      child: LdCard(
        padding: const EdgeInsets.all(LdSpacing.s3),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Expanded(
                  child: Text(
                    session.name,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: type.titleM.copyWith(color: c.textPrimary),
                  ),
                ),
                Text(
                  DateFormat('d MMM').format(session.startedAt.toLocal()),
                  style: type.caption.copyWith(color: c.textTertiary),
                ),
              ],
            ),
            const SizedBox(height: LdSpacing.s2),
            Text(
              '${session.volumeKg.round()} kg · '
              '${session.workingSetCount} sets'
              '${duration == null ? '' : ' · ${duration.inMinutes} min'}',
              style: type.bodyS.copyWith(color: c.textSecondary),
            ),
            if (session.prCount > 0) ...[
              const SizedBox(height: LdSpacing.s1),
              Text(
                '${session.prCount} personal record'
                '${session.prCount == 1 ? '' : 's'}',
                style: type.bodyS.copyWith(color: c.accent),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

/// Weekly training volume. Bars are drawn directly rather than through a chart
/// library — eight values do not justify the dependency weight.
class _VolumeChart extends StatelessWidget {
  const _VolumeChart({required this.data});
  final List<({DateTime weekStart, double volumeKg, int sessions})> data;

  @override
  Widget build(BuildContext context) {
    final c = context.ldColors;
    final type = context.ldType;
    final peak = data.fold<double>(
      0,
      (max, w) => w.volumeKg > max ? w.volumeKg : max,
    );

    return LdCard(
      child: SizedBox(
        height: 128,
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.end,
          children: [
            for (final week in data)
              Expanded(
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 3),
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.end,
                    children: [
                      Text(
                        week.volumeKg == 0
                            ? ''
                            : '${(week.volumeKg / 1000).toStringAsFixed(1)}k',
                        style: type.caption.copyWith(color: c.textTertiary),
                      ),
                      const SizedBox(height: 4),
                      Container(
                        height: peak == 0
                            ? 2
                            : (week.volumeKg / peak * 78).clamp(2.0, 78.0),
                        decoration: BoxDecoration(
                          color: week.volumeKg == 0 ? c.border : c.primary,
                          borderRadius: BorderRadius.circular(4),
                        ),
                      ),
                      const SizedBox(height: 6),
                      Text(
                        DateFormat('d/M').format(week.weekStart),
                        style: type.caption.copyWith(color: c.textTertiary),
                      ),
                    ],
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }
}
