import 'package:lifedna/core/data/synced_entity.dart';
import 'package:lifedna/core/engines/macro_calculator.dart';
import 'package:lifedna/shared/enums/enums.dart';

/// The user record. Firestore: `users/{uid}`.
///
/// Targets are DERIVED from the profile by [MacroCalculator] rather than
/// stored as independent truth, so editing a bodyweight cannot leave a stale
/// calorie goal behind. A user who overrides them sets [targetsOverridden],
/// and the derivation stops fighting them.
class UserProfile implements SyncedEntity {
  const UserProfile({
    required this.id,
    required this.email,
    required this.displayName,
    required this.updatedAt,
    required this.createdAt,
    this.photoUrl,
    this.dateOfBirth,
    this.sex = Sex.unspecified,
    this.heightCm = 0,
    this.weightKg = 0,
    this.activityLevel = ActivityLevel.moderate,
    this.goalMode = GoalMode.maintain,
    this.trainingDaysPerWeek = 4,
    this.targetWeightKg,
    this.leanMassKg,
    this.weeklyRateTargetPct = 0.5,
    this.onboardingCompletedAt,
    this.targetsOverridden = false,
    this.overrideKcal,
    this.overrideProteinG,
    this.overrideCarbsG,
    this.overrideFatG,
    this.overrideWaterMl,
    this.deletedAt,
  });

  @override
  final String id;
  final String email;
  final String displayName;
  final String? photoUrl;

  final DateTime? dateOfBirth;
  final Sex sex;
  final double heightCm;
  final double weightKg;
  final ActivityLevel activityLevel;
  final GoalMode goalMode;
  final int trainingDaysPerWeek;
  final double? targetWeightKg;
  final double? leanMassKg;
  final double weeklyRateTargetPct;

  final DateTime? onboardingCompletedAt;

  final bool targetsOverridden;
  final double? overrideKcal;
  final double? overrideProteinG;
  final double? overrideCarbsG;
  final double? overrideFatG;
  final int? overrideWaterMl;

  final DateTime createdAt;
  @override
  final DateTime updatedAt;
  @override
  final DateTime? deletedAt;

  bool get isOnboarded => onboardingCompletedAt != null;

  /// Whether there is enough profile data to compute targets at all.
  bool get hasBodyBasics =>
      heightCm > 0 && weightKg > 0 && dateOfBirth != null;

  int get age {
    final dob = dateOfBirth;
    if (dob == null) return 0;
    final now = DateTime.now();
    var years = now.year - dob.year;
    if (now.month < dob.month ||
        (now.month == dob.month && now.day < dob.day)) {
      years--;
    }
    return years;
  }

  /// Engine-derived targets, or the user's override when they have set one.
  MacroResult? get computedTargets {
    if (!hasBodyBasics) return null;
    return MacroCalculator.compute(
      MacroInput(
        weightKg: weightKg,
        heightCm: heightCm,
        age: age,
        sex: sex,
        activityLevel: activityLevel,
        goalMode: goalMode,
        trainingDaysPerWeek: trainingDaysPerWeek,
        leanMassKg: leanMassKg,
        weeklyRateTargetPct: weeklyRateTargetPct,
      ),
    );
  }

  UserProfile copyWith({
    String? email,
    String? displayName,
    String? photoUrl,
    DateTime? dateOfBirth,
    Sex? sex,
    double? heightCm,
    double? weightKg,
    ActivityLevel? activityLevel,
    GoalMode? goalMode,
    int? trainingDaysPerWeek,
    double? targetWeightKg,
    double? leanMassKg,
    double? weeklyRateTargetPct,
    DateTime? onboardingCompletedAt,
    bool? targetsOverridden,
    double? overrideKcal,
    double? overrideProteinG,
    double? overrideCarbsG,
    double? overrideFatG,
    int? overrideWaterMl,
    DateTime? updatedAt,
    DateTime? deletedAt,
  }) =>
      UserProfile(
        id: id,
        email: email ?? this.email,
        displayName: displayName ?? this.displayName,
        photoUrl: photoUrl ?? this.photoUrl,
        dateOfBirth: dateOfBirth ?? this.dateOfBirth,
        sex: sex ?? this.sex,
        heightCm: heightCm ?? this.heightCm,
        weightKg: weightKg ?? this.weightKg,
        activityLevel: activityLevel ?? this.activityLevel,
        goalMode: goalMode ?? this.goalMode,
        trainingDaysPerWeek: trainingDaysPerWeek ?? this.trainingDaysPerWeek,
        targetWeightKg: targetWeightKg ?? this.targetWeightKg,
        leanMassKg: leanMassKg ?? this.leanMassKg,
        weeklyRateTargetPct: weeklyRateTargetPct ?? this.weeklyRateTargetPct,
        onboardingCompletedAt:
            onboardingCompletedAt ?? this.onboardingCompletedAt,
        targetsOverridden: targetsOverridden ?? this.targetsOverridden,
        overrideKcal: overrideKcal ?? this.overrideKcal,
        overrideProteinG: overrideProteinG ?? this.overrideProteinG,
        overrideCarbsG: overrideCarbsG ?? this.overrideCarbsG,
        overrideFatG: overrideFatG ?? this.overrideFatG,
        overrideWaterMl: overrideWaterMl ?? this.overrideWaterMl,
        createdAt: createdAt,
        updatedAt: updatedAt ?? DateTime.now().toUtc(),
        deletedAt: deletedAt ?? this.deletedAt,
      );

  @override
  Map<String, dynamic> toJson() => {
        'id': id,
        'email': email,
        'displayName': displayName,
        'photoUrl': photoUrl,
        'dateOfBirth': dateOfBirth?.toIso8601String(),
        'sex': sex.wire,
        'heightCm': heightCm,
        'weightKg': weightKg,
        'activityLevel': activityLevel.wire,
        'goalMode': goalMode.wire,
        'trainingDaysPerWeek': trainingDaysPerWeek,
        'targetWeightKg': targetWeightKg,
        'leanMassKg': leanMassKg,
        'weeklyRateTargetPct': weeklyRateTargetPct,
        'onboardingCompletedAt': onboardingCompletedAt?.toIso8601String(),
        'targetsOverridden': targetsOverridden,
        'overrideKcal': overrideKcal,
        'overrideProteinG': overrideProteinG,
        'overrideCarbsG': overrideCarbsG,
        'overrideFatG': overrideFatG,
        'overrideWaterMl': overrideWaterMl,
        'createdAt': createdAt.toIso8601String(),
        'updatedAt': updatedAt.toIso8601String(),
        'deletedAt': deletedAt?.toIso8601String(),
      };

  factory UserProfile.fromJson(Map<String, dynamic> json) => UserProfile(
        id: Json.string(json['id']),
        email: Json.string(json['email']),
        displayName: Json.string(json['displayName']),
        photoUrl: json['photoUrl'] as String?,
        dateOfBirth: Json.dateOrNull(json['dateOfBirth']),
        sex: Sex.fromWire(Json.string(json['sex'], 'unspecified')),
        heightCm: Json.number(json['heightCm']),
        weightKg: Json.number(json['weightKg']),
        activityLevel:
            ActivityLevel.fromWire(Json.string(json['activityLevel'], 'moderate')),
        goalMode: GoalMode.fromWire(Json.string(json['goalMode'], 'maintain')),
        trainingDaysPerWeek: Json.integer(json['trainingDaysPerWeek'], 4),
        targetWeightKg: (json['targetWeightKg'] as num?)?.toDouble(),
        leanMassKg: (json['leanMassKg'] as num?)?.toDouble(),
        weeklyRateTargetPct: Json.number(json['weeklyRateTargetPct'], 0.5),
        onboardingCompletedAt: Json.dateOrNull(json['onboardingCompletedAt']),
        targetsOverridden: Json.boolean(json['targetsOverridden']),
        overrideKcal: (json['overrideKcal'] as num?)?.toDouble(),
        overrideProteinG: (json['overrideProteinG'] as num?)?.toDouble(),
        overrideCarbsG: (json['overrideCarbsG'] as num?)?.toDouble(),
        overrideFatG: (json['overrideFatG'] as num?)?.toDouble(),
        overrideWaterMl: (json['overrideWaterMl'] as num?)?.toInt(),
        createdAt: Json.date(json['createdAt'], fallback: DateTime.now()),
        updatedAt: Json.date(json['updatedAt'], fallback: DateTime.now()),
        deletedAt: Json.dateOrNull(json['deletedAt']),
      );

  /// A fresh profile for a newly authenticated account.
  factory UserProfile.initial({
    required String uid,
    required String email,
    required String displayName,
    String? photoUrl,
    DateTime? now,
  }) {
    final stamp = (now ?? DateTime.now()).toUtc();
    return UserProfile(
      id: uid,
      email: email,
      displayName: displayName,
      photoUrl: photoUrl,
      createdAt: stamp,
      updatedAt: stamp,
    );
  }
}
