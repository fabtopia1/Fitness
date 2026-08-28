import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';
import 'package:lifedna/core/providers/app_providers.dart';
import 'package:lifedna/core/router/app_router.dart';
import 'package:lifedna/core/theme/app_theme.dart';
import 'package:lifedna/core/theme/ld_spacing.dart';
import 'package:lifedna/core/widgets/ld_widgets.dart';
import 'package:lifedna/features/workout/domain/entities/workout.dart';
import 'package:lifedna/shared/enums/enums.dart';

/// The Workout Center (docs/06 Screen 05).
class TrainScreen extends ConsumerWidget {
  const TrainScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final plan = ref.watch(todaysPlanProvider);
    final repo = ref.watch(workoutRepositoryProvider);
    final session = ref.watch(activeSessionProvider).valueOrNull;
    final isLive = session?.status == SessionStatus.inProgress;
    final recent = repo.recentSessions(limit: 5);

    return Scaffold(
      appBar: AppBar(title: const Text('Train')),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(
          LdSpacing.s4,
          LdSpacing.s2,
          LdSpacing.s4,
          LdSpacing.scrollBottom,
        ),
        children: [
          _TodayCard(
            plan: plan,
            isLive: isLive,
            onStart: () async {
              if (isLive) {
                context.push(Routes.liveGym);
                return;
              }
              final result = await repo.startSession(template: plan.template);
              if (!context.mounted) return;
              result.when(
                ok: (_) => context.push(Routes.liveGym),
                err: (_) => ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(
                    content: Text('A session is already in progress.'),
                  ),
                ),
              );
            },
          ),
          const LdSectionHeader(title: 'This week'),
          const _WeeklySplit(),
          const LdSectionHeader(title: 'Templates'),
          for (final t in repo.templates())
            Padding(
              padding: const EdgeInsets.only(bottom: LdSpacing.s2),
              child: _TemplateRow(
                template: t,
                onStart: () async {
                  final result = await repo.startSession(template: t);
                  if (!context.mounted) return;
                  result.when(
                    ok: (_) => context.push(Routes.liveGym),
                    err: (_) => ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(
                        content: Text('A session is already in progress.'),
                      ),
                    ),
                  );
                },
              ),
            ),
          const LdSectionHeader(title: 'Recent sessions'),
          if (recent.isEmpty)
            const LdEmptyState(
              icon: Icons.fitness_center_rounded,
              headline: 'No sessions yet.',
              body: "Start from a template and we'll pre-fill everything you "
                  'lifted last time.',
            )
          else
            for (final s in recent) _SessionRow(session: s),
        ],
      ),
    );
  }
}

class _TodayCard extends StatelessWidget {
  const _TodayCard({
    required this.plan,
    required this.isLive,
    required this.onStart,
  });

  final ({String label, WorkoutTemplate? template, bool optional}) plan;
  final bool isLive;
  final VoidCallback onStart;

  @override
  Widget build(BuildContext context) {
    final c = context.ldColors;
    final type = context.ldType;

    return LdCard(
      eyebrow: 'Today',
      accentColor: c.primary,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            plan.template?.name ?? '${plan.label} — optional',
            style: type.titleL.copyWith(color: c.textPrimary),
          ),
          const SizedBox(height: LdSpacing.s2),
          Text(
            plan.template == null
                ? 'No resistance session scheduled. Recovery work only.'
                : '${plan.template!.totalWorkingSets} working sets · '
                    '~${plan.template!.estimatedMinutes} min',
            style: type.bodyS.copyWith(color: c.textSecondary),
          ),
          const SizedBox(height: LdSpacing.s4),
          LdPrimaryButton(
            label: isLive
                ? 'RESUME WORKOUT'
                : plan.template == null
                    ? 'START A SESSION'
                    : 'START WORKOUT',
            size: LdButtonSize.l,
            onPressed: onStart,
          ),
        ],
      ),
    );
  }
}

class _WeeklySplit extends ConsumerWidget {
  const _WeeklySplit();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final c = context.ldColors;
    final type = context.ldType;
    final today = ref.watch(todayProvider);
    final repo = ref.watch(workoutRepositoryProvider);

    // Render Saturday-first, matching the reference program's week.
    const order = [
      DateTime.saturday,
      DateTime.sunday,
      DateTime.monday,
      DateTime.tuesday,
      DateTime.wednesday,
      DateTime.thursday,
      DateTime.friday,
    ];

    return Row(
      children: [
        for (final weekday in order) ...[
          Expanded(
            child: Builder(
              builder: (context) {
                final offset = weekday - today.weekday;
                final date = today.add(Duration(days: offset));
                final plan = repo.todaysPlan(date);
                final isToday = weekday == today.weekday;

                return Column(
                  children: [
                    Text(
                      _dayInitial(weekday),
                      style: type.labelMono.copyWith(color: c.textTertiary),
                    ),
                    const SizedBox(height: LdSpacing.s2),
                    Container(
                      height: 44,
                      alignment: Alignment.center,
                      decoration: BoxDecoration(
                        color: isToday ? c.primaryMuted : c.surface,
                        borderRadius: BorderRadius.circular(LdRadius.s),
                        border: Border.all(
                          color: isToday ? c.primary : c.border,
                        ),
                      ),
                      child: Text(
                        plan.label.substring(0, plan.label.length.clamp(0, 4).toInt()),
                        style: type.caption.copyWith(
                          color: isToday ? c.primary : c.textSecondary,
                          fontWeight:
                              isToday ? FontWeight.w700 : FontWeight.w400,
                        ),
                      ),
                    ),
                  ],
                );
              },
            ),
          ),
          if (weekday != DateTime.friday) const SizedBox(width: LdSpacing.s1),
        ],
      ],
    );
  }

  static String _dayInitial(int weekday) => switch (weekday) {
        DateTime.monday => 'MON',
        DateTime.tuesday => 'TUE',
        DateTime.wednesday => 'WED',
        DateTime.thursday => 'THU',
        DateTime.friday => 'FRI',
        DateTime.saturday => 'SAT',
        _ => 'SUN',
      };
}

class _TemplateRow extends StatelessWidget {
  const _TemplateRow({required this.template, required this.onStart});
  final WorkoutTemplate template;
  final VoidCallback onStart;

  @override
  Widget build(BuildContext context) {
    final c = context.ldColors;
    final type = context.ldType;

    return LdCard(
      onTap: onStart,
      padding: const EdgeInsets.all(LdSpacing.s3),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  template.name,
                  style: type.titleM.copyWith(color: c.textPrimary),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
                const SizedBox(height: LdSpacing.s1),
                Text(
                  '${template.exercises.length} exercises · '
                  '${template.totalWorkingSets} sets · '
                  '~${template.estimatedMinutes} min',
                  style: type.bodyS.copyWith(color: c.textTertiary),
                ),
              ],
            ),
          ),
          Icon(Icons.play_arrow_rounded, color: c.primary),
        ],
      ),
    );
  }
}

class _SessionRow extends StatelessWidget {
  const _SessionRow({required this.session});
  final WorkoutSession session;

  @override
  Widget build(BuildContext context) {
    final c = context.ldColors;
    final type = context.ldType;

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
                    style: type.titleM.copyWith(color: c.textPrimary),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
                Text(
                  DateFormat('d MMM').format(session.startedAt),
                  style: type.bodyS.copyWith(color: c.textTertiary),
                ),
              ],
            ),
            const SizedBox(height: LdSpacing.s2),
            Text(
              '${session.volumeKg.round()} kg · ${session.completedSets} sets · '
              '${session.duration.inMinutes} min'
              '${session.sessionRpe == null ? '' : ' · RPE ${session.sessionRpe}'}',
              style: type.bodyS.copyWith(color: c.textSecondary),
            ),
            if (session.prCount > 0) ...[
              const SizedBox(height: LdSpacing.s1),
              Text(
                '🏆 ${session.prCount} personal record'
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
