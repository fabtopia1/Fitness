import 'package:lifedna/core/data/synced_entity.dart';
import 'package:lifedna/core/engines/e1rm_calculator.dart';
import 'package:lifedna/shared/enums/enums.dart';

/// An exercise. Firestore: `users/{uid}/exercises/{id}`.
///
/// The seed catalogue ships as an asset and is written into the user's own
/// collection on first run, so a custom exercise and a built-in one are the
/// same kind of object and need no special-casing anywhere downstream.
class Exercise implements SyncedEntity {
  const Exercise({
    required this.id,
    required this.name,
    required this.muscleGroup,
    required this.equipment,
    required this.updatedAt,
    this.isCompound = true,
    this.defaultRestSeconds = 120,
    this.incrementKg = 2.5,
    this.isCustom = false,
    this.deletedAt,
  });

  @override
  final String id;
  final String name;
  final MuscleGroup muscleGroup;
  final Equipment equipment;
  final bool isCompound;
  final int defaultRestSeconds;
  final double incrementKg;
  final bool isCustom;

  @override
  final DateTime updatedAt;
  @override
  final DateTime? deletedAt;

  String get subtitle => '${muscleGroup.label} · ${equipment.label}';

  Exercise copyWith({
    String? name,
    MuscleGroup? muscleGroup,
    Equipment? equipment,
    bool? isCompound,
    int? defaultRestSeconds,
    double? incrementKg,
    DateTime? updatedAt,
    DateTime? deletedAt,
  }) =>
      Exercise(
        id: id,
        name: name ?? this.name,
        muscleGroup: muscleGroup ?? this.muscleGroup,
        equipment: equipment ?? this.equipment,
        isCompound: isCompound ?? this.isCompound,
        defaultRestSeconds: defaultRestSeconds ?? this.defaultRestSeconds,
        incrementKg: incrementKg ?? this.incrementKg,
        isCustom: isCustom,
        updatedAt: updatedAt ?? DateTime.now().toUtc(),
        deletedAt: deletedAt ?? this.deletedAt,
      );

  @override
  Map<String, dynamic> toJson() => {
        'id': id,
        'name': name,
        'muscleGroup': muscleGroup.wire,
        'equipment': equipment.wire,
        'isCompound': isCompound,
        'defaultRestSeconds': defaultRestSeconds,
        'incrementKg': incrementKg,
        'isCustom': isCustom,
        'updatedAt': updatedAt.toIso8601String(),
        'deletedAt': deletedAt?.toIso8601String(),
      };

  factory Exercise.fromJson(Map<String, dynamic> json) => Exercise(
        id: Json.string(json['id']),
        name: Json.string(json['name']),
        muscleGroup:
            MuscleGroup.fromWire(Json.string(json['muscleGroup'], 'full_body')),
        equipment: Equipment.values.firstWhere(
          (e) => e.wire == json['equipment'],
          orElse: () => Equipment.barbell,
        ),
        isCompound: Json.boolean(json['isCompound'], true),
        defaultRestSeconds: Json.integer(json['defaultRestSeconds'], 120),
        incrementKg: Json.number(json['incrementKg'], 2.5),
        isCustom: Json.boolean(json['isCustom']),
        updatedAt: Json.date(json['updatedAt'], fallback: DateTime.now()),
        deletedAt: Json.dateOrNull(json['deletedAt']),
      );
}

/// One prescribed exercise inside a program.
class WorkoutExercise {
  const WorkoutExercise({
    required this.exerciseId,
    required this.exerciseName,
    required this.targetSets,
    required this.repMin,
    required this.repMax,
    required this.restSeconds,
  });

  final String exerciseId;
  final String exerciseName;
  final int targetSets;
  final int repMin;
  final int repMax;
  final int restSeconds;

  String get repRange => repMin == repMax ? '$repMin' : '$repMin–$repMax';

  Map<String, dynamic> toJson() => {
        'exerciseId': exerciseId,
        'exerciseName': exerciseName,
        'targetSets': targetSets,
        'repMin': repMin,
        'repMax': repMax,
        'restSeconds': restSeconds,
      };

  factory WorkoutExercise.fromJson(Map<String, dynamic> json) =>
      WorkoutExercise(
        exerciseId: Json.string(json['exerciseId']),
        exerciseName: Json.string(json['exerciseName']),
        targetSets: Json.integer(json['targetSets'], 3),
        repMin: Json.integer(json['repMin'], 8),
        repMax: Json.integer(json['repMax'], 12),
        restSeconds: Json.integer(json['restSeconds'], 120),
      );
}

/// A workout program. Firestore: `users/{uid}/workouts/{id}`.
class Workout implements SyncedEntity {
  const Workout({
    required this.id,
    required this.name,
    required this.exercises,
    required this.updatedAt,
    this.notes,
    this.useCount = 0,
    this.lastPerformedAt,
    this.deletedAt,
  });

  @override
  final String id;
  final String name;
  final List<WorkoutExercise> exercises;
  final String? notes;
  final int useCount;
  final DateTime? lastPerformedAt;

  @override
  final DateTime updatedAt;
  @override
  final DateTime? deletedAt;

  int get totalSets =>
      exercises.fold(0, (sum, e) => sum + e.targetSets);

  int get estimatedMinutes {
    // Working time plus rest. Deliberately rough — a precise-looking estimate
    // that is wrong is worse than an obviously approximate one.
    final restSeconds =
        exercises.fold(0, (sum, e) => sum + e.restSeconds * e.targetSets);
    return ((restSeconds + totalSets * 45) / 60).round();
  }

  Workout copyWith({
    String? name,
    List<WorkoutExercise>? exercises,
    String? notes,
    int? useCount,
    DateTime? lastPerformedAt,
    DateTime? updatedAt,
    DateTime? deletedAt,
  }) =>
      Workout(
        id: id,
        name: name ?? this.name,
        exercises: exercises ?? this.exercises,
        notes: notes ?? this.notes,
        useCount: useCount ?? this.useCount,
        lastPerformedAt: lastPerformedAt ?? this.lastPerformedAt,
        updatedAt: updatedAt ?? DateTime.now().toUtc(),
        deletedAt: deletedAt ?? this.deletedAt,
      );

  @override
  Map<String, dynamic> toJson() => {
        'id': id,
        'name': name,
        'exercises': exercises.map((e) => e.toJson()).toList(),
        'notes': notes,
        'useCount': useCount,
        'lastPerformedAt': lastPerformedAt?.toIso8601String(),
        'updatedAt': updatedAt.toIso8601String(),
        'deletedAt': deletedAt?.toIso8601String(),
      };

  factory Workout.fromJson(Map<String, dynamic> json) => Workout(
        id: Json.string(json['id']),
        name: Json.string(json['name']),
        exercises: (json['exercises'] as List? ?? const [])
            .map((e) => WorkoutExercise.fromJson(Json.map(e)))
            .toList(),
        notes: json['notes'] as String?,
        useCount: Json.integer(json['useCount']),
        lastPerformedAt: Json.dateOrNull(json['lastPerformedAt']),
        updatedAt: Json.date(json['updatedAt'], fallback: DateTime.now()),
        deletedAt: Json.dateOrNull(json['deletedAt']),
      );
}

/// One performed set. Embedded in its session rather than stored separately:
/// a set is never read without its session, and embedding makes the whole
/// session one atomic local write during a live workout.
class WorkoutSet {
  const WorkoutSet({
    required this.id,
    required this.exerciseId,
    required this.exerciseName,
    required this.weightKg,
    required this.reps,
    required this.performedAt,
    this.rpe,
    this.isWarmup = false,
    this.prLabels = const [],
  });

  final String id;
  final String exerciseId;
  final String exerciseName;
  final double weightKg;
  final int reps;
  final DateTime performedAt;
  final int? rpe;
  final bool isWarmup;

  /// Records achieved by this set, pre-rendered for display.
  final List<String> prLabels;

  bool get isPr => prLabels.isNotEmpty;

  double get volumeKg => isWarmup ? 0 : weightKg * reps;

  double get e1rm => E1rmCalculator.epley(weightKg, reps);

  Map<String, dynamic> toJson() => {
        'id': id,
        'exerciseId': exerciseId,
        'exerciseName': exerciseName,
        'weightKg': weightKg,
        'reps': reps,
        'performedAt': performedAt.toIso8601String(),
        'rpe': rpe,
        'isWarmup': isWarmup,
        'prLabels': prLabels,
      };

  factory WorkoutSet.fromJson(Map<String, dynamic> json) => WorkoutSet(
        id: Json.string(json['id']),
        exerciseId: Json.string(json['exerciseId']),
        exerciseName: Json.string(json['exerciseName']),
        weightKg: Json.number(json['weightKg']),
        reps: Json.integer(json['reps']),
        performedAt: Json.date(json['performedAt'], fallback: DateTime.now()),
        rpe: (json['rpe'] as num?)?.toInt(),
        isWarmup: Json.boolean(json['isWarmup']),
        prLabels: Json.stringList(json['prLabels']),
      );
}

/// A workout session. Firestore: `users/{uid}/workout_sessions/{id}`.
class WorkoutSession implements SyncedEntity {
  const WorkoutSession({
    required this.id,
    required this.name,
    required this.startedAt,
    required this.localDate,
    required this.updatedAt,
    this.workoutId,
    this.plan = const [],
    this.sets = const [],
    this.finishedAt,
    this.status = SessionStatus.inProgress,
    this.notes,
    this.deletedAt,
  });

  @override
  final String id;
  final String? workoutId;
  final String name;
  final List<WorkoutExercise> plan;
  final List<WorkoutSet> sets;
  final DateTime startedAt;
  final DateTime? finishedAt;
  final SessionStatus status;
  final String localDate;
  final String? notes;

  @override
  final DateTime updatedAt;
  @override
  final DateTime? deletedAt;

  bool get isActive => status == SessionStatus.inProgress;

  Duration durationAt(DateTime now) =>
      (finishedAt ?? now).difference(startedAt);

  double get volumeKg => sets.fold(0, (sum, s) => sum + s.volumeKg);

  int get workingSetCount => sets.where((s) => !s.isWarmup).length;

  int get totalReps => sets.fold(0, (sum, s) => sum + s.reps);

  int get prCount => sets.where((s) => s.isPr).length;

  int setsDoneFor(String exerciseId) =>
      sets.where((s) => s.exerciseId == exerciseId).length;

  Map<String, double> volumeByMuscle(Map<String, Exercise> catalogue) {
    final result = <String, double>{};
    for (final set in sets) {
      final group = catalogue[set.exerciseId]?.muscleGroup.label ?? 'Other';
      result[group] = (result[group] ?? 0) + set.volumeKg;
    }
    return result;
  }

  WorkoutSession copyWith({
    List<WorkoutSet>? sets,
    List<WorkoutExercise>? plan,
    DateTime? finishedAt,
    SessionStatus? status,
    String? notes,
    DateTime? updatedAt,
    DateTime? deletedAt,
  }) =>
      WorkoutSession(
        id: id,
        workoutId: workoutId,
        name: name,
        plan: plan ?? this.plan,
        sets: sets ?? this.sets,
        startedAt: startedAt,
        finishedAt: finishedAt ?? this.finishedAt,
        status: status ?? this.status,
        localDate: localDate,
        notes: notes ?? this.notes,
        updatedAt: updatedAt ?? DateTime.now().toUtc(),
        deletedAt: deletedAt ?? this.deletedAt,
      );

  @override
  Map<String, dynamic> toJson() => {
        'id': id,
        'workoutId': workoutId,
        'name': name,
        'plan': plan.map((e) => e.toJson()).toList(),
        'sets': sets.map((s) => s.toJson()).toList(),
        'startedAt': startedAt.toIso8601String(),
        'finishedAt': finishedAt?.toIso8601String(),
        'status': status.wire,
        'localDate': localDate,
        'notes': notes,
        'volumeKg': volumeKg,
        'setCount': sets.length,
        'updatedAt': updatedAt.toIso8601String(),
        'deletedAt': deletedAt?.toIso8601String(),
      };

  factory WorkoutSession.fromJson(Map<String, dynamic> json) => WorkoutSession(
        id: Json.string(json['id']),
        workoutId: json['workoutId'] as String?,
        name: Json.string(json['name']),
        plan: (json['plan'] as List? ?? const [])
            .map((e) => WorkoutExercise.fromJson(Json.map(e)))
            .toList(),
        sets: (json['sets'] as List? ?? const [])
            .map((e) => WorkoutSet.fromJson(Json.map(e)))
            .toList(),
        startedAt: Json.date(json['startedAt'], fallback: DateTime.now()),
        finishedAt: Json.dateOrNull(json['finishedAt']),
        status: SessionStatus.values.firstWhere(
          (s) => s.wire == json['status'],
          orElse: () => SessionStatus.completed,
        ),
        localDate: Json.string(json['localDate']),
        notes: json['notes'] as String?,
        updatedAt: Json.date(json['updatedAt'], fallback: DateTime.now()),
        deletedAt: Json.dateOrNull(json['deletedAt']),
      );
}

/// A personal record.
///
/// DERIVED from sessions and cached locally rather than stored in Firestore.
/// Storing it remotely would duplicate data that sessions already contain and
/// create a second source of truth that can disagree with the first.
class PersonalRecordEntry {
  const PersonalRecordEntry({
    required this.exerciseId,
    required this.exerciseName,
    required this.type,
    required this.value,
    required this.weightKg,
    required this.reps,
    required this.achievedAt,
    required this.sessionId,
  });

  final String exerciseId;
  final String exerciseName;
  final PrType type;
  final double value;
  final double weightKg;
  final int reps;
  final DateTime achievedAt;
  final String sessionId;

  Map<String, dynamic> toJson() => {
        'exerciseId': exerciseId,
        'exerciseName': exerciseName,
        'type': type.wire,
        'value': value,
        'weightKg': weightKg,
        'reps': reps,
        'achievedAt': achievedAt.toIso8601String(),
        'sessionId': sessionId,
      };

  factory PersonalRecordEntry.fromJson(Map<String, dynamic> json) =>
      PersonalRecordEntry(
        exerciseId: Json.string(json['exerciseId']),
        exerciseName: Json.string(json['exerciseName']),
        type: PrType.values.firstWhere(
          (t) => t.wire == json['type'],
          orElse: () => PrType.bestE1rm,
        ),
        value: Json.number(json['value']),
        weightKg: Json.number(json['weightKg']),
        reps: Json.integer(json['reps']),
        achievedAt: Json.date(json['achievedAt'], fallback: DateTime.now()),
        sessionId: Json.string(json['sessionId']),
      );
}

/// What the user last did on an exercise — the value Live Mode pre-fills with,
/// so nobody has to remember or do arithmetic at the rack.
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

  String get label {
    final w = weightKg == weightKg.roundToDouble()
        ? weightKg.round().toString()
        : weightKg.toStringAsFixed(1);
    return '$w kg × $reps${rpe == null ? '' : ' · RPE $rpe'}';
  }
}
