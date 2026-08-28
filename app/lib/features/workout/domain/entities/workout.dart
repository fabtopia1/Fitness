import 'package:lifedna/core/engines/e1rm_calculator.dart';
import 'package:lifedna/shared/enums/enums.dart';

/// A catalogue exercise.
class Exercise {
  const Exercise({
    required this.id,
    required this.name,
    required this.muscleGroup,
    required this.equipment,
    this.secondaryMuscles = const [],
    this.isCompound = true,
    this.defaultRestSeconds = 120,
    this.defaultIncrementKg = 2.5,
    this.instructions = const [],
  });

  final String id;
  final String name;
  final MuscleGroup muscleGroup;
  final List<MuscleGroup> secondaryMuscles;
  final Equipment equipment;
  final bool isCompound;
  final int defaultRestSeconds;
  final double defaultIncrementKg;
  final List<String> instructions;

  String get subtitle =>
      '${muscleGroup.label} · ${equipment.label} · '
      '${isCompound ? 'Compound' : 'Isolation'}';
}

/// One exercise as it appears in a template: the prescription, not the result.
class TemplateExercise {
  const TemplateExercise({
    required this.exerciseId,
    required this.exerciseName,
    required this.targetSets,
    required this.repMin,
    required this.repMax,
    required this.restSeconds,
    this.targetRpe = 8,
    this.groupId,
    this.note,
  });

  final String exerciseId;
  final String exerciseName;
  final int targetSets;
  final int repMin;
  final int repMax;
  final int restSeconds;
  final int targetRpe;

  /// Non-null means this exercise is part of a superset or circuit — rest fires
  /// only after the last member of the group.
  final String? groupId;
  final String? note;

  String get repRangeLabel =>
      repMin == repMax ? '$repMin' : '$repMin–$repMax';
}

class WorkoutTemplate {
  const WorkoutTemplate({
    required this.id,
    required this.name,
    required this.exercises,
    this.dayLabel,
    this.estimatedMinutes = 60,
  });

  final String id;
  final String name;
  final String? dayLabel;
  final List<TemplateExercise> exercises;
  final int estimatedMinutes;

  int get totalWorkingSets =>
      exercises.fold(0, (sum, e) => sum + e.targetSets);
}

/// One performed set. Additive and immutable once written — the authoritative
/// record of what actually happened.
class WorkoutSet {
  const WorkoutSet({
    required this.id,
    required this.exerciseId,
    required this.exerciseName,
    required this.setIndex,
    required this.weightKg,
    required this.reps,
    required this.performedAt,
    this.setType = SetType.working,
    this.rpe,
    this.toFailure = false,
    this.skipped = false,
    this.isPr = false,
    this.prLabels = const [],
    this.previousWeightKg,
    this.previousReps,
    this.note,
  });

  final String id;
  final String exerciseId;
  final String exerciseName;
  final int setIndex;
  final double weightKg;
  final int reps;
  final DateTime performedAt;
  final SetType setType;
  final int? rpe;
  final bool toFailure;
  final bool skipped;
  final bool isPr;
  final List<String> prLabels;

  /// What was shown to the user as "last time". Stored so the history screen
  /// can show the comparison the user was actually working against.
  final double? previousWeightKg;
  final int? previousReps;
  final String? note;

  double get volumeKg =>
      setType.countsTowardVolume && !skipped ? weightKg * reps : 0;

  double get e1rm => E1rmCalculator.epley(weightKg, reps);

  WorkoutSet copyWith({
    double? weightKg,
    int? reps,
    int? rpe,
    bool? toFailure,
    bool? skipped,
    bool? isPr,
    List<String>? prLabels,
    String? note,
  }) =>
      WorkoutSet(
        id: id,
        exerciseId: exerciseId,
        exerciseName: exerciseName,
        setIndex: setIndex,
        weightKg: weightKg ?? this.weightKg,
        reps: reps ?? this.reps,
        performedAt: performedAt,
        setType: setType,
        rpe: rpe ?? this.rpe,
        toFailure: toFailure ?? this.toFailure,
        skipped: skipped ?? this.skipped,
        isPr: isPr ?? this.isPr,
        prLabels: prLabels ?? this.prLabels,
        previousWeightKg: previousWeightKg,
        previousReps: previousReps,
        note: note ?? this.note,
      );
}

/// One executed session.
class WorkoutSession {
  const WorkoutSession({
    required this.id,
    required this.name,
    required this.startedAt,
    required this.exercises,
    required this.sets,
    this.templateId,
    this.finishedAt,
    this.status = SessionStatus.inProgress,
    this.sessionRpe,
    this.note,
  });

  final String id;
  final String? templateId;
  final String name;
  final DateTime startedAt;
  final DateTime? finishedAt;
  final SessionStatus status;
  final List<TemplateExercise> exercises;
  final List<WorkoutSet> sets;
  final int? sessionRpe;
  final String? note;

  Duration get duration =>
      (finishedAt ?? DateTime.now()).difference(startedAt);

  double get volumeKg => sets.fold(0, (sum, s) => sum + s.volumeKg);

  int get completedSets => sets.where((s) => !s.skipped).length;

  int get totalPlannedSets =>
      exercises.fold(0, (sum, e) => sum + e.targetSets);

  int get prCount => sets.where((s) => s.isPr).length;

  /// Volume per muscle group, for the session summary and weekly analytics.
  Map<MuscleGroup, double> volumeByMuscle(Map<String, Exercise> catalogue) {
    final result = <MuscleGroup, double>{};
    for (final set in sets) {
      final exercise = catalogue[set.exerciseId];
      if (exercise == null) continue;
      result[exercise.muscleGroup] =
          (result[exercise.muscleGroup] ?? 0) + set.volumeKg;
    }
    return result;
  }

  int setsCompletedFor(String exerciseId) =>
      sets.where((s) => s.exerciseId == exerciseId && !s.skipped).length;

  WorkoutSession copyWith({
    List<WorkoutSet>? sets,
    List<TemplateExercise>? exercises,
    DateTime? finishedAt,
    SessionStatus? status,
    int? sessionRpe,
    String? note,
  }) =>
      WorkoutSession(
        id: id,
        templateId: templateId,
        name: name,
        startedAt: startedAt,
        finishedAt: finishedAt ?? this.finishedAt,
        status: status ?? this.status,
        exercises: exercises ?? this.exercises,
        sets: sets ?? this.sets,
        sessionRpe: sessionRpe ?? this.sessionRpe,
        note: note ?? this.note,
      );
}
