import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:lifedna/core/data/reference_catalog.dart';
import 'package:lifedna/core/providers/app_providers.dart';
import 'package:lifedna/core/theme/app_theme.dart';
import 'package:lifedna/core/theme/ld_spacing.dart';
import 'package:lifedna/core/widgets/ld_widgets.dart';
import 'package:lifedna/features/workout/domain/entities/workout.dart';

/// Live Gym Mode (docs/06 Screen 06).
///
/// The success criterion is taps-per-set and glanceability at arm's length,
/// not feature count. Three constraints drive every layout decision here:
///
///   1. One tap completes a set when weight and reps are unchanged.
///   2. Every interactive element sits in the bottom 60 % of the viewport,
///      because the phone is held one-handed between sets.
///   3. The write commits locally before anything else happens, so the whole
///      screen works in a basement with no signal.
class LiveGymScreen extends ConsumerStatefulWidget {
  const LiveGymScreen({super.key});

  @override
  ConsumerState<LiveGymScreen> createState() => _LiveGymScreenState();
}

class _LiveGymScreenState extends ConsumerState<LiveGymScreen> {
  int _exerciseIndex = 0;
  double? _weightKg;
  int? _reps;
  int _rpe = 8;

  int _restRemaining = 0;
  Timer? _restTimer;
  Timer? _tick;

  @override
  void initState() {
    super.initState();
    // Drives the elapsed-time display. In production this is accompanied by a
    // wakelock and a foreground service (LIVE-01, FIT3-08).
    _tick = Timer.periodic(const Duration(seconds: 1), (_) {
      if (mounted) setState(() {});
    });
  }

  @override
  void dispose() {
    _restTimer?.cancel();
    _tick?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final c = context.ldColors;
    final session = ref.watch(activeSessionProvider).valueOrNull;

    if (session == null) {
      return Scaffold(
        appBar: AppBar(title: const Text('Live Gym')),
        body: LdEmptyState(
          icon: Icons.bolt_rounded,
          headline: 'No session in progress',
          body: 'Start one from the Train tab and it opens here.',
          actionLabel: 'Go to Train',
          onAction: () => context.go('/train'),
        ),
      );
    }

    if (session.exercises.isEmpty) {
      return Scaffold(
        appBar: AppBar(title: Text(session.name)),
        body: const LdEmptyState(
          icon: Icons.add_rounded,
          headline: 'Freeform session',
          body: 'Adding exercises mid-session lands in Sprint 6 (LIVE-16).',
        ),
      );
    }

    final index = _exerciseIndex.clamp(0, session.exercises.length - 1).toInt();
    final exercise = session.exercises[index];
    final catalogue = ReferenceCatalog.exerciseById(exercise.exerciseId);
    final increment = catalogue?.defaultIncrementKg ?? 2.5;
    final last = ref
        .read(workoutRepositoryProvider)
        .lastPerformance(exercise.exerciseId);

    // Prefill from the last performance, so the user never has to remember
    // what they lifted or do arithmetic at the rack (WORK-07).
    //
    // Derived as locals rather than written back to state: mutating a field
    // during build is invisible to the framework and desynchronises on rebuild.
    final weightKg = _weightKg ?? last?.weightKg ?? 20;
    final reps = _reps ?? last?.reps ?? exercise.repMin;

    final done = session.setsCompletedFor(exercise.exerciseId);
    final next = index + 1 < session.exercises.length
        ? session.exercises[index + 1]
        : null;

    return Scaffold(
      backgroundColor: c.bg,
      body: SafeArea(
        child: Stack(
          children: [
            Column(
              children: [
                _Header(session: session, onFinish: () => _finish(session)),
                Expanded(
                  child: SingleChildScrollView(
                    padding: const EdgeInsets.symmetric(
                      horizontal: LdSpacing.s4,
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const SizedBox(height: LdSpacing.s5),
                        Text(
                          exercise.exerciseName.toUpperCase(),
                          style: context.ldType.headlineL
                              .copyWith(color: c.textPrimary),
                        ),
                        const SizedBox(height: LdSpacing.s2),
                        Text(
                          'Set ${done + 1} of ${exercise.targetSets} · '
                          'target ${exercise.repRangeLabel} @ RPE '
                          '${exercise.targetRpe}',
                          style: context.ldType.bodyM
                              .copyWith(color: c.textSecondary),
                        ),
                        const SizedBox(height: LdSpacing.s6),
                        Row(
                          children: [
                            Expanded(
                              child: _ValueStepper(
                                value: _fmtWeight(weightKg),
                                unit: 'KG',
                                onDecrement: () => setState(
                                  () => _weightKg = (weightKg - increment)
                                      .clamp(0.0, 500.0)
                                      .toDouble(),
                                ),
                                onIncrement: () => setState(
                                  () => _weightKg = (weightKg + increment)
                                      .clamp(0.0, 500.0)
                                      .toDouble(),
                                ),
                              ),
                            ),
                            const SizedBox(width: LdSpacing.s3),
                            Expanded(
                              child: _ValueStepper(
                                value: '$reps',
                                unit: 'REPS',
                                onDecrement: () => setState(
                                  () => _reps = (reps - 1).clamp(1, 100).toInt(),
                                ),
                                onIncrement: () => setState(
                                  () => _reps = (reps + 1).clamp(1, 100).toInt(),
                                ),
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: LdSpacing.s4),
                        if (last != null)
                          Text(
                            'Last time: ${last.label}',
                            style: context.ldType.bodyS
                                .copyWith(color: c.textTertiary),
                          ),
                        const SizedBox(height: LdSpacing.s5),
                        _RpeSelector(
                          value: _rpe,
                          onChanged: (v) => setState(() => _rpe = v),
                        ),
                        const SizedBox(height: LdSpacing.s5),
                        _CompletedSets(
                          session: session,
                          exerciseId: exercise.exerciseId,
                        ),
                      ],
                    ),
                  ),
                ),
                // The action zone: everything the thumb touches lives here.
                Padding(
                  padding: const EdgeInsets.fromLTRB(
                    LdSpacing.s4,
                    LdSpacing.s3,
                    LdSpacing.s4,
                    LdSpacing.s4,
                  ),
                  child: Column(
                    children: [
                      LdPrimaryButton(
                        label: 'COMPLETE SET',
                        size: LdButtonSize.xl,
                        onPressed: () => _completeSet(
                          exercise,
                          weightKg: weightKg,
                          reps: reps,
                        ),
                      ),
                      const SizedBox(height: LdSpacing.s3),
                      Row(
                        children: [
                          Expanded(
                            child: LdPrimaryButton(
                              label: 'Skip',
                              variant: LdButtonVariant.ghost,
                              onPressed: () => _skip(exercise),
                            ),
                          ),
                          const SizedBox(width: LdSpacing.s3),
                          Expanded(
                            child: LdPrimaryButton(
                              label: done >= exercise.targetSets
                                  ? 'Next exercise'
                                  : 'Next',
                              variant: LdButtonVariant.secondary,
                              onPressed: next == null && done < exercise.targetSets
                                  ? null
                                  : _advance,
                            ),
                          ),
                        ],
                      ),
                      if (next != null) ...[
                        const SizedBox(height: LdSpacing.s3),
                        Text(
                          'NEXT   ${next.exerciseName} · '
                          '${next.targetSets} × ${next.repRangeLabel}',
                          style: context.ldType.labelMono
                              .copyWith(color: c.textTertiary),
                        ),
                      ],
                    ],
                  ),
                ),
              ],
            ),
            if (_restRemaining > 0)
              _RestOverlay(
                remaining: _restRemaining,
                total: exercise.restSeconds,
                onAdjust: (delta) => setState(
                  () => _restRemaining =
                      (_restRemaining + delta).clamp(0, 900).toInt(),
                ),
                onSkip: _stopRest,
              ),
          ],
        ),
      ),
    );
  }

  Future<void> _completeSet(
    TemplateExercise exercise, {
    required double weightKg,
    required int reps,
  }) async {
    final result = await ref.read(workoutRepositoryProvider).completeSet(
          exerciseId: exercise.exerciseId,
          exerciseName: exercise.exerciseName,
          weightKg: weightKg,
          reps: reps,
          rpe: _rpe,
        );
    if (!mounted) return;

    result.when(
      ok: (set) {
        HapticFeedback.mediumImpact();
        _startRest(exercise.restSeconds);
        if (set.isPr) {
          HapticFeedback.mediumImpact();
          // A record is announced inline and non-blockingly. It must never
          // interrupt the next set (LIVE-11).
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text('🏆  ${set.prLabels.join(' · ')}'),
              backgroundColor: context.ldColors.accentMuted,
              duration: const Duration(seconds: 3),
            ),
          );
        }
      },
      err: (failure) => ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(_validationCopy(failure.message))),
      ),
    );
  }

  Future<void> _skip(TemplateExercise exercise) async {
    await ref
        .read(workoutRepositoryProvider)
        .skipSet(exerciseId: exercise.exerciseId);
    _stopRest();
  }

  void _advance() {
    final session = ref.read(activeSessionProvider).valueOrNull;
    if (session == null) return;
    setState(() {
      _exerciseIndex = (_exerciseIndex + 1)
          .clamp(0, session.exercises.length - 1)
          .toInt();
      _weightKg = null;
      _reps = null;
    });
    _stopRest();
  }

  void _startRest(int seconds) {
    _restTimer?.cancel();
    setState(() => _restRemaining = seconds);
    _restTimer = Timer.periodic(const Duration(seconds: 1), (t) {
      if (!mounted) return t.cancel();
      setState(() => _restRemaining -= 1);
      if (_restRemaining <= 0) {
        t.cancel();
        HapticFeedback.heavyImpact();
      }
    });
  }

  void _stopRest() {
    _restTimer?.cancel();
    if (mounted) setState(() => _restRemaining = 0);
  }

  Future<void> _finish(WorkoutSession session) async {
    final rpe = await showModalBottomSheet<int>(
      context: context,
      builder: (_) => _FinishSheet(session: session),
    );
    if (rpe == null || !mounted) return;

    await ref.read(workoutRepositoryProvider).finishSession(sessionRpe: rpe);
    if (mounted) context.go('/train');
  }

  static String _fmtWeight(double v) =>
      v == v.roundToDouble() ? v.round().toString() : v.toStringAsFixed(1);

  static String _validationCopy(String code) => switch (code) {
        'weight_out_of_range' => 'Enter a weight between 0 and 500 kg.',
        'reps_out_of_range' => 'Enter between 1 and 100 reps.',
        _ => 'Could not log that set.',
      };
}

class _Header extends StatelessWidget {
  const _Header({required this.session, required this.onFinish});
  final WorkoutSession session;
  final VoidCallback onFinish;

  @override
  Widget build(BuildContext context) {
    final c = context.ldColors;
    final type = context.ldType;
    final d = session.duration;
    final clock = '${d.inHours > 0 ? '${d.inHours}:' : ''}'
        '${d.inMinutes.remainder(60).toString().padLeft(2, '0')}:'
        '${d.inSeconds.remainder(60).toString().padLeft(2, '0')}';

    final total = session.totalPlannedSets;
    final done = session.completedSets;

    return Padding(
      padding: const EdgeInsets.fromLTRB(
        LdSpacing.s4,
        LdSpacing.s2,
        LdSpacing.s2,
        0,
      ),
      child: Column(
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  session.name.split('—').first.trim().toUpperCase(),
                  style: type.labelMono.copyWith(color: c.textTertiary),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
              Text(
                clock,
                style: type.titleM.copyWith(color: c.textPrimary),
              ),
              IconButton(
                onPressed: onFinish,
                icon: const Icon(Icons.stop_circle_outlined),
                tooltip: 'Finish workout',
              ),
            ],
          ),
          const SizedBox(height: LdSpacing.s2),
          ClipRRect(
            borderRadius: BorderRadius.circular(LdRadius.full),
            child: LinearProgressIndicator(
              value: total == 0 ? 0 : done / total,
              minHeight: 4,
              backgroundColor: c.border,
              valueColor: AlwaysStoppedAnimation(c.primary),
            ),
          ),
          const SizedBox(height: LdSpacing.s1),
          Align(
            alignment: Alignment.centerLeft,
            child: Text(
              '$done of $total sets',
              style: type.caption.copyWith(color: c.textTertiary),
            ),
          ),
        ],
      ),
    );
  }
}

/// A large value with 48 dp steppers either side. Sized to be readable at
/// arm's length and operable without looking.
class _ValueStepper extends StatelessWidget {
  const _ValueStepper({
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
      padding: const EdgeInsets.symmetric(vertical: LdSpacing.s4),
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
              style: type.displayXL.copyWith(color: c.textPrimary),
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
          child: Icon(icon, color: c.textPrimary, size: 26),
        ),
      ),
    );
  }
}

class _RpeSelector extends StatelessWidget {
  const _RpeSelector({required this.value, required this.onChanged});
  final int value;
  final ValueChanged<int> onChanged;

  @override
  Widget build(BuildContext context) {
    final c = context.ldColors;
    final type = context.ldType;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text('RPE', style: type.labelMono.copyWith(color: c.textTertiary)),
        const SizedBox(height: LdSpacing.s2),
        Row(
          children: [
            for (final rpe in [6, 7, 8, 9, 10]) ...[
              Expanded(
                child: GestureDetector(
                  onTap: () => onChanged(rpe),
                  child: Container(
                    height: LdTouch.min,
                    alignment: Alignment.center,
                    decoration: BoxDecoration(
                      color: value == rpe ? c.primaryMuted : c.surface,
                      borderRadius: BorderRadius.circular(LdRadius.s),
                      border: Border.all(
                        color: value == rpe ? c.primary : c.border,
                      ),
                    ),
                    child: Text(
                      '$rpe',
                      style: type.titleM.copyWith(
                        color: value == rpe ? c.primary : c.textSecondary,
                      ),
                    ),
                  ),
                ),
              ),
              if (rpe != 10) const SizedBox(width: LdSpacing.s2),
            ],
          ],
        ),
      ],
    );
  }
}

class _CompletedSets extends StatelessWidget {
  const _CompletedSets({required this.session, required this.exerciseId});
  final WorkoutSession session;
  final String exerciseId;

  @override
  Widget build(BuildContext context) {
    final c = context.ldColors;
    final type = context.ldType;
    final sets = [
      for (final s in session.sets)
        if (s.exerciseId == exerciseId) s,
    ];
    if (sets.isEmpty) return const SizedBox.shrink();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'THIS EXERCISE',
          style: type.labelMono.copyWith(color: c.textTertiary),
        ),
        const SizedBox(height: LdSpacing.s2),
        for (final s in sets)
          Padding(
            padding: const EdgeInsets.only(bottom: LdSpacing.s2),
            child: Opacity(
              opacity: 0.6,
              child: Row(
                children: [
                  Icon(
                    s.skipped
                        ? Icons.remove_circle_outline_rounded
                        : Icons.check_circle_rounded,
                    size: 16,
                    color: s.skipped ? c.textTertiary : c.success,
                  ),
                  const SizedBox(width: LdSpacing.s2),
                  Text(
                    s.skipped
                        ? 'Set ${s.setIndex} — skipped'
                        : 'Set ${s.setIndex}   '
                            '${_fmt(s.weightKg)} kg × ${s.reps}'
                            '${s.rpe == null ? '' : '   RPE ${s.rpe}'}',
                    style: type.bodyS.copyWith(color: c.textSecondary),
                  ),
                  if (s.isPr) ...[
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
    final mm = (remaining ~/ 60).toString();
    final ss = (remaining % 60).toString().padLeft(2, '0');

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
            // Legible at a metre — this is read from the bench, not the hand.
            Text(
              '$mm:$ss',
              style: type.displayXL.copyWith(
                color: c.textPrimary,
                fontSize: 72,
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

class _FinishSheet extends StatefulWidget {
  const _FinishSheet({required this.session});
  final WorkoutSession session;

  @override
  State<_FinishSheet> createState() => _FinishSheetState();
}

class _FinishSheetState extends State<_FinishSheet> {
  int _rpe = 8;

  @override
  Widget build(BuildContext context) {
    final c = context.ldColors;
    final type = context.ldType;
    final s = widget.session;
    final d = s.duration;

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
                  value: '${d.inMinutes}',
                  unit: 'MIN',
                  color: c.textPrimary,
                ),
                _Summary(
                  value: '${s.volumeKg.round()}',
                  unit: 'VOLUME KG',
                  color: c.primary,
                ),
                _Summary(
                  value: '${s.completedSets}',
                  unit: 'SETS',
                  color: c.textPrimary,
                ),
                _Summary(
                  value: '${s.prCount}',
                  unit: 'PRs',
                  color: c.accent,
                ),
              ],
            ),
            const SizedBox(height: LdSpacing.s6),
            Text(
              'How hard was that?',
              style: type.titleM.copyWith(color: c.textPrimary),
            ),
            const SizedBox(height: LdSpacing.s3),
            _RpeSelector(value: _rpe, onChanged: (v) => setState(() => _rpe = v)),
            const SizedBox(height: LdSpacing.s2),
            Text(
              'Session RPE drives your training load, which drives tomorrow’s '
              'recovery score.',
              textAlign: TextAlign.center,
              style: type.caption.copyWith(color: c.textTertiary),
            ),
            const SizedBox(height: LdSpacing.s5),
            LdPrimaryButton(
              label: 'Save workout',
              size: LdButtonSize.l,
              onPressed: () => Navigator.of(context).pop(_rpe),
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
