import 'package:lifedna/core/engines/e1rm_calculator.dart';
import 'package:lifedna/core/errors/failure.dart';
import 'package:lifedna/core/result/result.dart';
import 'package:lifedna/features/workout/domain/entities/workout.dart';

/// What the user last did on an exercise, used to pre-fill a session so the
/// user never has to remember or do arithmetic at the rack (WORK-07).
class LastPerformance {
  const LastPerformance({
    required this.weightKg,
    required this.reps,
    required this.performedAt,
    this.rpe,
  });

  final double weightKg;
  final int reps;
  final DateTime performedAt;
  final int? rpe;

  String get label => '${_fmt(weightKg)} kg × $reps'
      '${rpe == null ? '' : ' · RPE $rpe'}';

  static String _fmt(double v) =>
      v == v.roundToDouble() ? v.round().toString() : v.toStringAsFixed(1);
}

abstract interface class WorkoutRepository {
  List<WorkoutTemplate> templates();
  WorkoutTemplate? templateById(String id);

  /// Today's scheduled template from the active program, or null on a rest day.
  ({String label, WorkoutTemplate? template, bool optional}) todaysPlan(
    DateTime date,
  );

  Stream<WorkoutSession?> watchActiveSession();

  Future<Result<WorkoutSession, Failure>> startSession({
    WorkoutTemplate? template,
    String? name,
  });

  /// Appends a completed set. This is the product's most important write: it
  /// must succeed offline, in under 50 ms, and never be lost (LIVE-02, LIVE-13).
  Future<Result<WorkoutSet, Failure>> completeSet({
    required String exerciseId,
    required String exerciseName,
    required double weightKg,
    required int reps,
    int? rpe,
    bool toFailure = false,
  });

  Future<Result<void, Failure>> skipSet({required String exerciseId});

  Future<Result<WorkoutSession, Failure>> finishSession({
    required int sessionRpe,
    String? note,
  });

  Future<Result<void, Failure>> discardSession();

  /// Prior bests, for PR detection.
  ExerciseBests bestsFor(String exerciseId);

  LastPerformance? lastPerformance(String exerciseId);

  List<WorkoutSession> recentSessions({int limit = 10});
}
