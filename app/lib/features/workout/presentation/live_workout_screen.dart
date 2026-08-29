import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:lifedna/core/notifications/notification_service.dart';
import 'package:lifedna/core/providers/providers.dart';
import 'package:lifedna/core/theme/app_theme.dart';
import 'package:lifedna/core/theme/ld_spacing.dart';
import 'package:lifedna/core/widgets/ld_widgets.dart';
import 'package:lifedna/features/workout/domain/workout_entities.dart';
import 'package:lifedna/features/workout/presentation/exercise_picker.dart';
import 'package:lifedna/features/workout/presentation/workout_providers.dart';

/// Live Workout Mode.
///
/// Three constraints drive every layout decision here:
///
///  1. One tap logs a set when weight and reps are unchanged.
///  2. Everything interactive sits in the lower half — the phone is held one
///     handed, between sets, often with chalk on it.
///  3. The set is committed to local storage before anything else happens, so
///     the whole screen works with no signal and survives the app being killed.
class LiveWorkoutScreen extends ConsumerStatefulWidget {
  const LiveWorkoutScreen({super.key});

  @override
  ConsumerState<LiveWorkoutScreen> createState() => _LiveWorkoutScreenState();
}

class _LiveWorkoutScreenState extends ConsumerState<LiveWorkoutScreen> {
  int _exerciseIndex = 0;
  double? _weightKg;
  int? _reps;
  int? _rpe;

  /// Seconds left in the rest period, 0 when not resting.
  ///
  /// A notifier rather than state, so the countdown repaints the overlay
  /// alone. `setState` here would rebuild the header, the exercise panel and
  /// the action bar once a second for the length of the rest — see the note on
  /// [_ElapsedClock].
  final _restRemaining = ValueNotifier<int>(0);
  int _restTotal = 0;
  Timer? _restTimer;

  /// `lastPerformance` scans and deserialises every completed session, and the
  /// answer cannot change while this screen is open except when this screen
  /// adds a set. Caching it turns three full history scans per rebuild into
  /// one per exercise per workout.
  final _lastPerformance = <String, LastPerformance?>{};

  @override
  void dispose() {
    _restTimer?.cancel();
    _restRemaining.dispose();
    super.dispose();
  }

  LastPerformance? _lastFor(String exerciseId) => _lastPerformance.putIfAbsent(
    exerciseId,
    () => ref.read(workoutRepositoryProvider).lastPerformance(exerciseId),
  );

  @override
  Widget build(BuildContext context) {
    final c = context.ldColors;
    final session = ref.watch(activeSessionProvider).valueOrNull;

    if (session == null) {
      return Scaffold(
        appBar: AppBar(title: const Text('Live workout')),
        body: LdEmptyState(
          icon: Icons.bolt_rounded,
          headline: 'No workout in progress',
          body: 'Start one from the Train tab and it opens here.',
          actionLabel: 'Go to Train',
          onAction: () => context.go('/train'),
        ),
      );
    }

    final plan = session.plan;
    final hasPlan = plan.isNotEmpty;
    final index = hasPlan
        ? _exerciseIndex.clamp(0, plan.length - 1).toInt()
        : 0;
    final current = hasPlan ? plan[index] : null;

    return PopScope(
      canPop: true,
      child: Scaffold(
        backgroundColor: c.bg,
        appBar: AppBar(
          title: Text(session.name, overflow: TextOverflow.ellipsis),
          actions: [
            TextButton(
              onPressed: () => _finish(session),
              child: const Text('Finish'),
            ),
          ],
        ),
        body: SafeArea(
          child: Stack(
            children: [
              Column(
                children: [
                  _Header(session: session),
                  Expanded(
                    child: SingleChildScrollView(
                      padding: const EdgeInsets.symmetric(
                        horizontal: LdSpacing.s4,
                      ),
                      child: current == null
                          ? _FreeformPrompt(onAdd: () => _addExercise(session))
                          : _ExercisePanel(
                              session: session,
                              exercise: current,
                              last: _lastFor(current.exerciseId),
                              weightKg: _resolvedWeight(current),
                              reps: _resolvedReps(current),
                              rpe: _rpe,
                              onWeight: (v) => setState(() => _weightKg = v),
                              onReps: (v) => setState(() => _reps = v),
                              onRpe: (v) => setState(() => _rpe = v),
                            ),
                    ),
                  ),
                  _ActionBar(
                    session: session,
                    exercise: current,
                    onComplete: current == null
                        ? null
                        : () => _completeSet(session, current),
                    onAddExercise: () => _addExercise(session),
                    onNext: hasPlan && index < plan.length - 1
                        ? () => setState(() {
                            _exerciseIndex = index + 1;
                            _weightKg = null;
                            _reps = null;
                          })
                        : null,
                  ),
                ],
              ),
              ValueListenableBuilder<int>(
                valueListenable: _restRemaining,
                builder: (context, remaining, _) => remaining > 0
                    ? _RestOverlay(
                        remaining: remaining,
                        total: _restTotal,
                        onAdjust: (delta) => _restRemaining.value =
                            (remaining + delta).clamp(0, 900).toInt(),
                        onSkip: _stopRest,
                      )
                    : const SizedBox.shrink(),
              ),
            ],
          ),
        ),
      ),
    );
  }

  double _resolvedWeight(WorkoutExercise exercise) =>
      _weightKg ?? _lastFor(exercise.exerciseId)?.weightKg ?? 20;

  int _resolvedReps(WorkoutExercise exercise) =>
      _reps ?? _lastFor(exercise.exerciseId)?.reps ?? exercise.repMin;

  Future<void> _completeSet(
    WorkoutSession session,
    WorkoutExercise exercise,
  ) async {
    final result = await ref
        .read(workoutRepositoryProvider)
        .addSet(
          session: session,
          exerciseId: exercise.exerciseId,
          exerciseName: exercise.exerciseName,
          weightKg: _resolvedWeight(exercise),
          reps: _resolvedReps(exercise),
          rpe: _rpe,
        );
    if (!mounted) return;

    result.when(
      ok: (updated) {
        // The only way lastPerformance can change while this screen is open.
        _lastPerformance.remove(exercise.exerciseId);
        unawaited(HapticFeedback.mediumImpact());
        _startRest(exercise.restSeconds);

        final latest = updated.sets.last;
        if (latest.isPr) {
          unawaited(HapticFeedback.heavyImpact());
          // Announced inline and non-blockingly: a modal here would interrupt
          // the set that follows.
          showSuccessSnack(context, '🏆 ${latest.prLabels.join(' · ')}');
        }
      },
      err: (failure) => showFailureSnack(context, failure),
    );
  }

  Future<void> _addExercise(WorkoutSession session) async {
    final exercise = await showModalBottomSheet<Exercise>(
      context: context,
      isScrollControlled: true,
      builder: (_) => const ExercisePicker(),
    );
    if (exercise == null || !mounted) return;

    final updated = session.copyWith(
      plan: [
        ...session.plan,
        WorkoutExercise(
          exerciseId: exercise.id,
          exerciseName: exercise.name,
          targetSets: 3,
          repMin: 8,
          repMax: 12,
          restSeconds: exercise.defaultRestSeconds,
        ),
      ],
    );
    await ref.read(workoutRepositoryProvider).sessions.put(updated);
    if (mounted) setState(() => _exerciseIndex = updated.plan.length - 1);
  }

  void _startRest(int seconds) {
    _restTimer?.cancel();
    _restTotal = seconds;
    _restRemaining.value = seconds;
    _restTimer = Timer.periodic(const Duration(seconds: 1), (timer) {
      if (!mounted) {
        timer.cancel();
        return;
      }
      _restRemaining.value -= 1;
      if (_restRemaining.value <= 0) {
        timer.cancel();
        unawaited(HapticFeedback.heavyImpact());
        // Fires even if the user has switched apps mid-rest, which is what
        // most people do.
        unawaited(
          ref
              .read(notificationServiceProvider)
              .showNow(
                id: 90001,
                channel: NotificationChannelId.restTimer,
                title: 'Rest finished',
                body: 'Next set is ready.',
              ),
        );
      }
    });
  }

  void _stopRest() {
    _restTimer?.cancel();
    _restRemaining.value = 0;
  }

  Future<void> _finish(WorkoutSession session) async {
    if (session.sets.isEmpty) {
      final discard = await showDialog<bool>(
        context: context,
        builder: (context) => AlertDialog(
          title: const Text('Discard workout?'),
          content: const Text('No sets were logged.'),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(context).pop(false),
              child: const Text('Keep going'),
            ),
            FilledButton(
              onPressed: () => Navigator.of(context).pop(true),
              child: const Text('Discard'),
            ),
          ],
        ),
      );
      if (discard != true || !mounted) return;
      await ref.read(workoutRepositoryProvider).discardSession(session);
      if (mounted) context.go('/train');
      return;
    }

    final confirmed = await showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      builder: (_) => _SummarySheet(session: session),
    );
    if (confirmed != true || !mounted) return;

    final result = await ref
        .read(workoutRepositoryProvider)
        .finishSession(session);
    if (!mounted) return;
    result.when(
      ok: (_) {
        showSuccessSnack(context, 'Workout saved');
        context.go('/train');
      },
      err: (failure) => showFailureSnack(context, failure),
    );
  }
}

class _Header extends StatelessWidget {
  const _Header({required this.session});
  final WorkoutSession session;

  @override
  Widget build(BuildContext context) {
    final c = context.ldColors;
    final type = context.ldType;

    return Padding(
      padding: const EdgeInsets.fromLTRB(
        LdSpacing.s4,
        0,
        LdSpacing.s4,
        LdSpacing.s3,
      ),
      child: Row(
        children: [
          _ElapsedClock(session: session),
          const SizedBox(width: LdSpacing.s4),
          Text(
            '${session.sets.length} sets · ${session.volumeKg.round()} kg',
            style: type.bodyS.copyWith(color: c.textSecondary),
          ),
        ],
      ),
    );
  }
}

/// The running workout clock, and the only thing on this screen that repaints
/// once a second.
///
/// The timer used to live on the screen state and call `setState(() {})`,
/// which rebuilt the header, the exercise panel and the action bar every
/// second for the length of a workout — 45 to 90 minutes. Each of those
/// rebuilds ran `lastPerformance` three times, and each of those deserialised
/// every completed session out of Hive. Owning the timer here means one Text
/// repaints instead.
class _ElapsedClock extends ConsumerStatefulWidget {
  const _ElapsedClock({required this.session});
  final WorkoutSession session;

  @override
  ConsumerState<_ElapsedClock> createState() => _ElapsedClockState();
}

class _ElapsedClockState extends ConsumerState<_ElapsedClock> {
  Timer? _tick;

  @override
  void initState() {
    super.initState();
    // One second is plenty; anything faster burns battery for no visible
    // benefit, because the display has one-second resolution.
    _tick = Timer.periodic(const Duration(seconds: 1), (_) {
      if (mounted) setState(() {});
    });
  }

  @override
  void dispose() {
    _tick?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    // Through the clock provider, like every other time-dependent thing in
    // the app, so this is deterministic under test.
    final elapsed = widget.session.durationAt(ref.watch(clockProvider)());
    final clock =
        '${elapsed.inHours > 0 ? '${elapsed.inHours}:' : ''}'
        '${elapsed.inMinutes.remainder(60).toString().padLeft(2, '0')}:'
        '${elapsed.inSeconds.remainder(60).toString().padLeft(2, '0')}';

    return Text(
      clock,
      style: context.ldType.titleL.copyWith(
        color: context.ldColors.textPrimary,
      ),
    );
  }
}

class _FreeformPrompt extends StatelessWidget {
  const _FreeformPrompt({required this.onAdd});
  final VoidCallback onAdd;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.only(top: LdSpacing.s8),
    child: LdEmptyState(
      icon: Icons.add_circle_outline_rounded,
      headline: 'Add your first exercise',
      body: 'Pick from your library and start logging sets.',
      actionLabel: 'Add exercise',
      onAction: onAdd,
    ),
  );
}

class _ExercisePanel extends ConsumerWidget {
  const _ExercisePanel({
    required this.session,
    required this.exercise,
    required this.last,
    required this.weightKg,
    required this.reps,
    required this.rpe,
    required this.onWeight,
    required this.onReps,
    required this.onRpe,
  });

  final WorkoutSession session;
  final WorkoutExercise exercise;

  /// Resolved by the screen, which caches it. Reading it here made the panel
  /// scan and deserialise the entire workout history on every rebuild.
  final LastPerformance? last;
  final double weightKg;
  final int reps;
  final int? rpe;
  final ValueChanged<double> onWeight;
  final ValueChanged<int> onReps;
  final ValueChanged<int?> onRpe;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final c = context.ldColors;
    final type = context.ldType;
    final done = session.setsDoneFor(exercise.exerciseId);
    // A local so the null check promotes: a public final field does not.
    final last = this.last;
    final increment =
        ref
            .read(workoutRepositoryProvider)
            .exercises
            .readOne(exercise.exerciseId)
            ?.incrementKg ??
        2.5;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const SizedBox(height: LdSpacing.s3),
        Text(
          exercise.exerciseName.toUpperCase(),
          style: type.headlineM.copyWith(color: c.textPrimary),
        ),
        const SizedBox(height: LdSpacing.s2),
        Text(
          'Set ${done + 1} of ${exercise.targetSets} · '
          'target ${exercise.repRange} reps',
          style: type.bodyM.copyWith(color: c.textSecondary),
        ),
        const SizedBox(height: LdSpacing.s5),
        Row(
          children: [
            Expanded(
              child: _Stepper(
                value: _fmt(weightKg),
                unit: 'KG',
                onDecrement: () => onWeight(
                  (weightKg - increment).clamp(0.0, 500.0).toDouble(),
                ),
                onIncrement: () => onWeight(
                  (weightKg + increment).clamp(0.0, 500.0).toDouble(),
                ),
              ),
            ),
            const SizedBox(width: LdSpacing.s3),
            Expanded(
              child: _Stepper(
                value: '$reps',
                unit: 'REPS',
                onDecrement: () => onReps((reps - 1).clamp(1, 100).toInt()),
                onIncrement: () => onReps((reps + 1).clamp(1, 100).toInt()),
              ),
            ),
          ],
        ),
        if (last != null) ...[
          const SizedBox(height: LdSpacing.s3),
          Text(
            'Last time: ${last.label}',
            style: type.bodyS.copyWith(color: c.textTertiary),
          ),
        ],
        const SizedBox(height: LdSpacing.s4),
        Text('RPE', style: type.labelMono.copyWith(color: c.textTertiary)),
        const SizedBox(height: LdSpacing.s2),
        Row(
          children: [
            for (final value in [6, 7, 8, 9, 10]) ...[
              Expanded(
                child: GestureDetector(
                  onTap: () => onRpe(rpe == value ? null : value),
                  child: Container(
                    height: LdTouch.min,
                    alignment: Alignment.center,
                    decoration: BoxDecoration(
                      color: rpe == value ? c.primaryMuted : c.surface,
                      borderRadius: BorderRadius.circular(LdRadius.s),
                      border: Border.all(
                        color: rpe == value ? c.primary : c.border,
                      ),
                    ),
                    child: Text(
                      '$value',
                      style: type.titleM.copyWith(
                        color: rpe == value ? c.primary : c.textSecondary,
                      ),
                    ),
                  ),
                ),
              ),
              if (value != 10) const SizedBox(width: LdSpacing.s2),
            ],
          ],
        ),
        const SizedBox(height: LdSpacing.s5),
        _CompletedSets(session: session, exerciseId: exercise.exerciseId),
        const SizedBox(height: LdSpacing.s5),
      ],
    );
  }

  static String _fmt(double v) =>
      v == v.roundToDouble() ? v.round().toString() : v.toStringAsFixed(1);
}

class _Stepper extends StatelessWidget {
  const _Stepper({
    required this.value,
    required this.unit,
    required this.onDecrement,
    required this.onIncrement,
  });

  final String value;
  final String unit;
  final VoidCallback onDecrement;
  final VoidCallback onIncrement;

  @override
  Widget build(BuildContext context) {
    final c = context.ldColors;
    final type = context.ldType;

    return Container(
      padding: const EdgeInsets.symmetric(vertical: LdSpacing.s3),
      decoration: BoxDecoration(
        color: c.surface,
        borderRadius: BorderRadius.circular(LdRadius.m),
        border: Border.all(color: c.border),
      ),
      child: Column(
        children: [
          FittedBox(
            child: Text(
              value,
              style: type.displayL.copyWith(color: c.textPrimary),
            ),
          ),
          Text(unit, style: type.labelMono.copyWith(color: c.textTertiary)),
          const SizedBox(height: LdSpacing.s3),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceEvenly,
            children: [
              _SquareButton(icon: Icons.remove_rounded, onTap: onDecrement),
              _SquareButton(icon: Icons.add_rounded, onTap: onIncrement),
            ],
          ),
        ],
      ),
    );
  }
}

class _SquareButton extends StatelessWidget {
  const _SquareButton({required this.icon, required this.onTap});
  final IconData icon;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final c = context.ldColors;
    return Material(
      color: c.surfaceElevated,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(LdRadius.s),
        side: BorderSide(color: c.borderStrong),
      ),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(LdRadius.s),
        child: SizedBox(
          width: 56,
          height: 56,
          child: Icon(icon, size: 24, color: c.textPrimary),
        ),
      ),
    );
  }
}

class _CompletedSets extends ConsumerWidget {
  const _CompletedSets({required this.session, required this.exerciseId});
  final WorkoutSession session;
  final String exerciseId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final c = context.ldColors;
    final type = context.ldType;
    final sets = session.sets.where((s) => s.exerciseId == exerciseId).toList();
    if (sets.isEmpty) return const SizedBox.shrink();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'THIS EXERCISE',
          style: type.labelMono.copyWith(color: c.textTertiary),
        ),
        const SizedBox(height: LdSpacing.s2),
        for (var i = 0; i < sets.length; i++)
          Dismissible(
            key: ValueKey(sets[i].id),
            direction: DismissDirection.endToStart,
            onDismissed: (_) => ref
                .read(workoutRepositoryProvider)
                .removeSet(session: session, setId: sets[i].id),
            background: Container(
              alignment: Alignment.centerRight,
              padding: const EdgeInsets.only(right: LdSpacing.s3),
              child: Icon(Icons.delete_outline_rounded, color: c.danger),
            ),
            child: Padding(
              padding: const EdgeInsets.only(bottom: LdSpacing.s2),
              child: Row(
                children: [
                  Icon(Icons.check_circle_rounded, size: 16, color: c.success),
                  const SizedBox(width: LdSpacing.s2),
                  Expanded(
                    child: Text(
                      'Set ${i + 1}   ${_fmt(sets[i].weightKg)} kg × '
                      '${sets[i].reps}'
                      '${sets[i].rpe == null ? '' : '   RPE ${sets[i].rpe}'}',
                      style: type.bodyS.copyWith(color: c.textSecondary),
                    ),
                  ),
                  if (sets[i].isPr) ...[
                    const SizedBox(width: LdSpacing.s2),
                    Text('🏆', style: type.bodyS),
                  ],
                ],
              ),
            ),
          ),
      ],
    );
  }

  static String _fmt(double v) =>
      v == v.roundToDouble() ? v.round().toString() : v.toStringAsFixed(1);
}

class _ActionBar extends StatelessWidget {
  const _ActionBar({
    required this.session,
    required this.exercise,
    required this.onComplete,
    required this.onAddExercise,
    required this.onNext,
  });

  final WorkoutSession session;
  final WorkoutExercise? exercise;
  final VoidCallback? onComplete;
  final VoidCallback onAddExercise;
  final VoidCallback? onNext;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(
        LdSpacing.s4,
        LdSpacing.s3,
        LdSpacing.s4,
        LdSpacing.s4,
      ),
      child: Column(
        children: [
          if (exercise != null)
            LdPrimaryButton(
              label: 'COMPLETE SET',
              size: LdButtonSize.xl,
              onPressed: onComplete,
            ),
          const SizedBox(height: LdSpacing.s3),
          Row(
            children: [
              Expanded(
                child: LdPrimaryButton(
                  label: 'Add exercise',
                  variant: LdButtonVariant.secondary,
                  onPressed: onAddExercise,
                ),
              ),
              if (onNext != null) ...[
                const SizedBox(width: LdSpacing.s3),
                Expanded(
                  child: LdPrimaryButton(
                    label: 'Next',
                    variant: LdButtonVariant.ghost,
                    onPressed: onNext,
                  ),
                ),
              ],
            ],
          ),
        ],
      ),
    );
  }
}

class _RestOverlay extends StatelessWidget {
  const _RestOverlay({
    required this.remaining,
    required this.total,
    required this.onAdjust,
    required this.onSkip,
  });

  final int remaining;
  final int total;
  final ValueChanged<int> onAdjust;
  final VoidCallback onSkip;

  @override
  Widget build(BuildContext context) {
    final c = context.ldColors;
    final type = context.ldType;

    return Positioned(
      left: 0,
      right: 0,
      bottom: 0,
      child: Container(
        padding: const EdgeInsets.fromLTRB(
          LdSpacing.s4,
          LdSpacing.s5,
          LdSpacing.s4,
          LdSpacing.s5,
        ),
        decoration: BoxDecoration(
          color: c.surfaceElevated,
          borderRadius: const BorderRadius.vertical(
            top: Radius.circular(LdRadius.l),
          ),
          border: Border(top: BorderSide(color: c.borderStrong)),
          boxShadow: [
            BoxShadow(
              color: c.shadow,
              blurRadius: 24,
              offset: const Offset(0, -4),
            ),
          ],
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            // Readable from a bench, not just from the hand.
            Text(
              '${remaining ~/ 60}:'
              '${(remaining % 60).toString().padLeft(2, '0')}',
              style: type.displayXL.copyWith(
                color: c.textPrimary,
                fontSize: 64,
              ),
            ),
            const SizedBox(height: LdSpacing.s3),
            ClipRRect(
              borderRadius: BorderRadius.circular(LdRadius.full),
              child: LinearProgressIndicator(
                value: total == 0 ? 0 : remaining / total,
                minHeight: 6,
                backgroundColor: c.border,
                valueColor: AlwaysStoppedAnimation(c.secondary),
              ),
            ),
            const SizedBox(height: LdSpacing.s4),
            Row(
              children: [
                Expanded(
                  child: LdPrimaryButton(
                    label: '− 15s',
                    variant: LdButtonVariant.secondary,
                    onPressed: () => onAdjust(-15),
                  ),
                ),
                const SizedBox(width: LdSpacing.s3),
                Expanded(
                  child: LdPrimaryButton(label: 'Skip', onPressed: onSkip),
                ),
                const SizedBox(width: LdSpacing.s3),
                Expanded(
                  child: LdPrimaryButton(
                    label: '+ 15s',
                    variant: LdButtonVariant.secondary,
                    onPressed: () => onAdjust(15),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _SummarySheet extends StatelessWidget {
  const _SummarySheet({required this.session});
  final WorkoutSession session;

  @override
  Widget build(BuildContext context) {
    final c = context.ldColors;
    final type = context.ldType;
    final duration = session.durationAt(DateTime.now());

    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(
          LdSpacing.s4,
          0,
          LdSpacing.s4,
          LdSpacing.s5,
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              'WORKOUT COMPLETE',
              style: type.labelMono.copyWith(color: c.textTertiary),
            ),
            const SizedBox(height: LdSpacing.s5),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceEvenly,
              children: [
                _Summary(
                  value: '${duration.inMinutes}',
                  unit: 'MIN',
                  color: c.textPrimary,
                ),
                _Summary(
                  value: '${session.volumeKg.round()}',
                  unit: 'VOLUME KG',
                  color: c.primary,
                ),
                _Summary(
                  value: '${session.workingSetCount}',
                  unit: 'SETS',
                  color: c.textPrimary,
                ),
                _Summary(
                  value: '${session.prCount}',
                  unit: 'PRs',
                  color: c.accent,
                ),
              ],
            ),
            const SizedBox(height: LdSpacing.s6),
            LdPrimaryButton(
              label: 'Save workout',
              size: LdButtonSize.l,
              onPressed: () => Navigator.of(context).pop(true),
            ),
            const SizedBox(height: LdSpacing.s2),
            LdPrimaryButton(
              label: 'Keep going',
              variant: LdButtonVariant.ghost,
              onPressed: () => Navigator.of(context).pop(false),
            ),
          ],
        ),
      ),
    );
  }
}

class _Summary extends StatelessWidget {
  const _Summary({
    required this.value,
    required this.unit,
    required this.color,
  });

  final String value;
  final String unit;
  final Color color;

  @override
  Widget build(BuildContext context) {
    final type = context.ldType;
    return Column(
      children: [
        Text(value, style: type.displayM.copyWith(color: color)),
        const SizedBox(height: LdSpacing.s1),
        Text(
          unit,
          style: type.labelMono.copyWith(color: context.ldColors.textTertiary),
        ),
      ],
    );
  }
}
