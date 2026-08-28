import 'dart:async';

import 'package:lifedna/core/data/reference_catalog.dart';
import 'package:lifedna/core/engines/e1rm_calculator.dart';
import 'package:lifedna/core/errors/failure.dart';
import 'package:lifedna/core/result/result.dart';
import 'package:lifedna/core/utils/id_generator.dart';
import 'package:lifedna/features/workout/domain/entities/workout.dart';
import 'package:lifedna/features/workout/domain/repositories/workout_repository.dart';
import 'package:lifedna/shared/enums/enums.dart';

/// Local-authoritative workout store.
///
/// The design point this implementation exists to demonstrate: while a session
/// is `inProgress`, THIS store is the source of truth, not the server. A set is
/// committed here synchronously the moment the user taps, and only afterwards
/// replicated. That ordering is what makes the gym experience work in a
/// basement with no signal (docs/02 §6.1).
class InMemoryWorkoutRepository implements WorkoutRepository {
  InMemoryWorkoutRepository({DateTime Function()? clock, IdGenerator? ids})
      : _clock = clock ?? DateTime.now,
        _ids = ids ?? const IdGenerator() {
    _seedHistory();
  }

  final DateTime Function() _clock;
  final IdGenerator _ids;

  final _controller = StreamController<WorkoutSession?>.broadcast();
  final List<WorkoutSession> _sessions = [];
  WorkoutSession? _active;

  /// Seeds one completed session so "last time" values exist on first run —
  /// an empty prefill would misrepresent the core experience.
  void _seedHistory() {
    final yesterday = _clock().subtract(const Duration(days: 1));
    final template = ReferenceCatalog.templateById('tpl_push')!;
    final start = DateTime(
      yesterday.year,
      yesterday.month,
      yesterday.day,
      18,
    );

    final sets = <WorkoutSet>[];
    var index = 0;
    void add(String exId, String exName, double kg, int reps, int rpe) {
      sets.add(
        WorkoutSet(
          id: _ids.v7(start.add(Duration(minutes: index))),
          exerciseId: exId,
          exerciseName: exName,
          setIndex: index,
          weightKg: kg,
          reps: reps,
          rpe: rpe,
          performedAt: start.add(Duration(minutes: index * 3)),
        ),
      );
      index++;
    }

    add('incline-dumbbell-press', 'Incline Dumbbell Press', 30, 12, 7);
    add('incline-dumbbell-press', 'Incline Dumbbell Press', 30, 10, 8);
    add('incline-dumbbell-press', 'Incline Dumbbell Press', 30, 10, 9);
    add('incline-dumbbell-press', 'Incline Dumbbell Press', 27.5, 10, 9);
    add('barbell-bench-press', 'Barbell Bench Press', 70, 8, 8);
    add('barbell-bench-press', 'Barbell Bench Press', 70, 7, 9);
    add('overhead-press', 'Overhead Press', 40, 10, 8);
    add('cable-fly', 'Cable Fly', 15, 14, 8);
    add('lateral-raise', 'Lateral Raise', 10, 16, 8);
    add('triceps-pushdown', 'Triceps Pushdown', 30, 12, 8);

    _sessions.add(
      WorkoutSession(
        id: _ids.v7(start),
        templateId: template.id,
        name: template.name,
        startedAt: start,
        finishedAt: start.add(const Duration(minutes: 73)),
        status: SessionStatus.completed,
        exercises: template.exercises,
        sets: sets,
        sessionRpe: 8,
      ),
    );
  }

  @override
  List<WorkoutTemplate> templates() => ReferenceCatalog.templates;

  @override
  WorkoutTemplate? templateById(String id) =>
      ReferenceCatalog.templateById(id);

  @override
  ({String label, WorkoutTemplate? template, bool optional}) todaysPlan(
    DateTime date,
  ) {
    final slot = ReferenceCatalog.weeklySplit[date.weekday];
    if (slot == null) {
      return (label: 'REST', template: null, optional: true);
    }
    return (
      label: slot.label,
      template: slot.templateId == null
          ? null
          : ReferenceCatalog.templateById(slot.templateId!),
      optional: slot.optional,
    );
  }

  @override
  Stream<WorkoutSession?> watchActiveSession() {
    scheduleMicrotask(_emit);
    return _controller.stream;
  }

  void _emit() {
    if (!_controller.isClosed) _controller.add(_active);
  }

  WorkoutSession? get activeSession => _active;

  @override
  Future<Result<WorkoutSession, Failure>> startSession({
    WorkoutTemplate? template,
    String? name,
  }) async {
    if (_active != null) {
      return const Err(ValidationFailure('session_already_in_progress'));
    }
    final session = WorkoutSession(
      id: _ids.v7(),
      templateId: template?.id,
      name: name ?? template?.name ?? 'Freeform session',
      startedAt: _clock(),
      exercises: template?.exercises ?? const [],
      sets: const [],
    );
    _active = session;
    _emit();
    return Ok(session);
  }

  @override
  Future<Result<WorkoutSet, Failure>> completeSet({
    required String exerciseId,
    required String exerciseName,
    required double weightKg,
    required int reps,
    int? rpe,
    bool toFailure = false,
  }) async {
    final session = _active;
    if (session == null) {
      return const Err(ValidationFailure('no_active_session'));
    }
    if (weightKg < 0 || weightKg > 500) {
      return const Err(ValidationFailure('weight_out_of_range'));
    }
    if (reps < 1 || reps > 100) {
      return const Err(ValidationFailure('reps_out_of_range'));
    }

    final previous = lastPerformance(exerciseId);
    final bests = bestsFor(exerciseId);

    final records = PrDetector.forSet(
      exerciseId: exerciseId,
      weightKg: weightKg,
      reps: reps,
      isWarmup: false,
      bests: bests,
    );

    final set = WorkoutSet(
      id: _ids.v7(),
      exerciseId: exerciseId,
      exerciseName: exerciseName,
      setIndex: session.setsCompletedFor(exerciseId) + 1,
      weightKg: weightKg,
      reps: reps,
      rpe: rpe,
      toFailure: toFailure,
      performedAt: _clock(),
      isPr: records.isNotEmpty,
      prLabels: [for (final r in records) r.headline],
      previousWeightKg: previous?.weightKg,
      previousReps: previous?.reps,
    );

    _active = session.copyWith(sets: [...session.sets, set]);
    _emit();
    return Ok(set);
  }

  @override
  Future<Result<void, Failure>> skipSet({required String exerciseId}) async {
    final session = _active;
    if (session == null) {
      return const Err(ValidationFailure('no_active_session'));
    }
    final exercise = ReferenceCatalog.exerciseById(exerciseId);
    final set = WorkoutSet(
      id: _ids.v7(),
      exerciseId: exerciseId,
      exerciseName: exercise?.name ?? exerciseId,
      setIndex: session.setsCompletedFor(exerciseId) + 1,
      weightKg: 0,
      reps: 0,
      performedAt: _clock(),
      skipped: true,
    );
    _active = session.copyWith(sets: [...session.sets, set]);
    _emit();
    return const Ok(null);
  }

  @override
  Future<Result<WorkoutSession, Failure>> finishSession({
    required int sessionRpe,
    String? note,
  }) async {
    final session = _active;
    if (session == null) {
      return const Err(ValidationFailure('no_active_session'));
    }
    final finished = session.copyWith(
      finishedAt: _clock(),
      status: SessionStatus.completed,
      sessionRpe: sessionRpe,
      note: note,
    );
    _sessions.add(finished);
    _active = null;
    _emit();
    return Ok(finished);
  }

  @override
  Future<Result<void, Failure>> discardSession() async {
    _active = null;
    _emit();
    return const Ok(null);
  }

  /// Scans completed history for prior bests. In production this reads a
  /// maintained index rather than scanning (docs/03 §6.5) — the contract is
  /// identical, so swapping the implementation changes nothing above.
  @override
  ExerciseBests bestsFor(String exerciseId) {
    double? heaviest;
    double? bestE1rm;
    double? maxVolume;
    final repsAtWeight = <double, int>{};

    for (final session in _sessions) {
      var sessionVolume = 0.0;
      for (final set in session.sets) {
        if (set.exerciseId != exerciseId || set.skipped) continue;
        sessionVolume += set.volumeKg;

        if (heaviest == null || set.weightKg > heaviest) {
          heaviest = set.weightKg;
        }
        final e1rm = set.e1rm;
        if (bestE1rm == null || e1rm > bestE1rm) bestE1rm = e1rm;

        final prior = repsAtWeight[set.weightKg];
        if (prior == null || set.reps > prior) {
          repsAtWeight[set.weightKg] = set.reps;
        }
      }
      if (sessionVolume > 0 &&
          (maxVolume == null || sessionVolume > maxVolume)) {
        maxVolume = sessionVolume;
      }
    }

    return ExerciseBests(
      heaviestWeightKg: heaviest,
      bestE1rm: bestE1rm == null
          ? null
          : (bestE1rm * 10).roundToDouble() / 10,
      repsAtWeight: repsAtWeight,
      maxSessionVolumeKg: maxVolume,
    );
  }

  @override
  LastPerformance? lastPerformance(String exerciseId) {
    WorkoutSet? latest;
    for (final session in _sessions) {
      for (final set in session.sets) {
        if (set.exerciseId != exerciseId || set.skipped) continue;
        if (latest == null || set.performedAt.isAfter(latest.performedAt)) {
          latest = set;
        }
      }
    }
    if (latest == null) return null;
    return LastPerformance(
      weightKg: latest.weightKg,
      reps: latest.reps,
      rpe: latest.rpe,
      performedAt: latest.performedAt,
    );
  }

  @override
  List<WorkoutSession> recentSessions({int limit = 10}) {
    final sorted = [..._sessions]
      ..sort((a, b) => b.startedAt.compareTo(a.startedAt));
    return sorted.take(limit).toList();
  }

  void dispose() => _controller.close();
}
