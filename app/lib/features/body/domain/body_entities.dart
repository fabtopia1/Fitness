import 'package:lifedna/core/data/synced_entity.dart';

/// A body measurement. Firestore: `users/{uid}/body_measurements/{id}`.
///
/// Every field except weight is optional: a user who only ever steps on a
/// scale must not be blocked by a form demanding seven circumferences.
class BodyMeasurement implements SyncedEntity {
  const BodyMeasurement({
    required this.id,
    required this.measuredAt,
    required this.localDate,
    required this.updatedAt,
    this.weightKg,
    this.bodyFatPct,
    this.waistCm,
    this.chestCm,
    this.leftArmCm,
    this.rightArmCm,
    this.leftLegCm,
    this.rightLegCm,
    this.neckCm,
    this.hipsCm,
    this.photoPath,
    this.notes,
    this.deletedAt,
  });

  @override
  final String id;
  final DateTime measuredAt;
  final String localDate;

  final double? weightKg;
  final double? bodyFatPct;
  final double? waistCm;
  final double? chestCm;
  final double? leftArmCm;
  final double? rightArmCm;
  final double? leftLegCm;
  final double? rightLegCm;
  final double? neckCm;
  final double? hipsCm;

  /// Local file path. Progress photos stay ON DEVICE in the MVP: uploading
  /// them adds a large privacy surface (docs/security) for no MVP benefit,
  /// and a photo the user cannot delete from a server is a liability.
  final String? photoPath;

  final String? notes;

  @override
  final DateTime updatedAt;
  @override
  final DateTime? deletedAt;

  bool get hasAnyValue =>
      weightKg != null ||
      bodyFatPct != null ||
      waistCm != null ||
      chestCm != null ||
      leftArmCm != null ||
      rightArmCm != null ||
      leftLegCm != null ||
      rightLegCm != null ||
      neckCm != null ||
      hipsCm != null ||
      photoPath != null;

  /// Named metrics present on this record, for chart selection.
  Map<BodyMetric, double> get values => {
    if (weightKg != null) BodyMetric.weight: weightKg!,
    if (bodyFatPct != null) BodyMetric.bodyFat: bodyFatPct!,
    if (waistCm != null) BodyMetric.waist: waistCm!,
    if (chestCm != null) BodyMetric.chest: chestCm!,
    if (leftArmCm != null) BodyMetric.leftArm: leftArmCm!,
    if (rightArmCm != null) BodyMetric.rightArm: rightArmCm!,
    if (leftLegCm != null) BodyMetric.leftLeg: leftLegCm!,
    if (rightLegCm != null) BodyMetric.rightLeg: rightLegCm!,
    if (neckCm != null) BodyMetric.neck: neckCm!,
    if (hipsCm != null) BodyMetric.hips: hipsCm!,
  };

  BodyMeasurement copyWith({
    double? weightKg,
    double? bodyFatPct,
    double? waistCm,
    double? chestCm,
    double? leftArmCm,
    double? rightArmCm,
    double? leftLegCm,
    double? rightLegCm,
    double? neckCm,
    double? hipsCm,
    String? photoPath,
    String? notes,
    DateTime? updatedAt,
    DateTime? deletedAt,
  }) => BodyMeasurement(
    id: id,
    measuredAt: measuredAt,
    localDate: localDate,
    weightKg: weightKg ?? this.weightKg,
    bodyFatPct: bodyFatPct ?? this.bodyFatPct,
    waistCm: waistCm ?? this.waistCm,
    chestCm: chestCm ?? this.chestCm,
    leftArmCm: leftArmCm ?? this.leftArmCm,
    rightArmCm: rightArmCm ?? this.rightArmCm,
    leftLegCm: leftLegCm ?? this.leftLegCm,
    rightLegCm: rightLegCm ?? this.rightLegCm,
    neckCm: neckCm ?? this.neckCm,
    hipsCm: hipsCm ?? this.hipsCm,
    photoPath: photoPath ?? this.photoPath,
    notes: notes ?? this.notes,
    updatedAt: updatedAt ?? DateTime.now().toUtc(),
    deletedAt: deletedAt ?? this.deletedAt,
  );

  @override
  Map<String, dynamic> toJson() => {
    'id': id,
    'measuredAt': measuredAt.toIso8601String(),
    'localDate': localDate,
    'weightKg': weightKg,
    'bodyFatPct': bodyFatPct,
    'waistCm': waistCm,
    'chestCm': chestCm,
    'leftArmCm': leftArmCm,
    'rightArmCm': rightArmCm,
    'leftLegCm': leftLegCm,
    'rightLegCm': rightLegCm,
    'neckCm': neckCm,
    'hipsCm': hipsCm,
    'photoPath': photoPath,
    'notes': notes,
    'updatedAt': updatedAt.toIso8601String(),
    'deletedAt': deletedAt?.toIso8601String(),
  };

  factory BodyMeasurement.fromJson(Map<String, dynamic> json) =>
      BodyMeasurement(
        id: Json.string(json['id']),
        measuredAt: Json.date(json['measuredAt'], fallback: DateTime.now()),
        localDate: Json.string(json['localDate']),
        weightKg: (json['weightKg'] as num?)?.toDouble(),
        bodyFatPct: (json['bodyFatPct'] as num?)?.toDouble(),
        waistCm: (json['waistCm'] as num?)?.toDouble(),
        chestCm: (json['chestCm'] as num?)?.toDouble(),
        leftArmCm: (json['leftArmCm'] as num?)?.toDouble(),
        rightArmCm: (json['rightArmCm'] as num?)?.toDouble(),
        leftLegCm: (json['leftLegCm'] as num?)?.toDouble(),
        rightLegCm: (json['rightLegCm'] as num?)?.toDouble(),
        neckCm: (json['neckCm'] as num?)?.toDouble(),
        hipsCm: (json['hipsCm'] as num?)?.toDouble(),
        photoPath: json['photoPath'] as String?,
        notes: json['notes'] as String?,
        updatedAt: Json.date(json['updatedAt'], fallback: DateTime.now()),
        deletedAt: Json.dateOrNull(json['deletedAt']),
      );
}

enum BodyMetric {
  weight('Weight', 'kg', true),
  bodyFat('Body fat', '%', true),
  waist('Waist', 'cm', true),
  chest('Chest', 'cm', false),
  leftArm('Left arm', 'cm', false),
  rightArm('Right arm', 'cm', false),
  leftLeg('Left leg', 'cm', false),
  rightLeg('Right leg', 'cm', false),
  neck('Neck', 'cm', false),
  hips('Hips', 'cm', false);

  const BodyMetric(this.label, this.unit, this.lowerIsBetter);
  final String label;
  final String unit;

  /// Direction semantics. A falling waist is progress; a falling arm is not.
  /// The UI must not infer this from the sign of a delta.
  final bool lowerIsBetter;
}

/// A trend over a series of measurements. Derived.
class BodyTrend {
  const BodyTrend({required this.metric, required this.points});

  final BodyMetric metric;

  /// Oldest first.
  final List<({DateTime at, double value})> points;

  bool get hasData => points.isNotEmpty;
  bool get hasTrend => points.length >= 2;

  double? get latest => points.isEmpty ? null : points.last.value;
  double? get first => points.isEmpty ? null : points.first.value;

  double? get change =>
      hasTrend ? points.last.value - points.first.value : null;

  /// Exponentially weighted average, which is the honest line to draw through
  /// daily bodyweight: raw scale readings swing by more than a week of real
  /// change, and plotting them as-is invites bad decisions.
  List<double> get ewma {
    if (points.isEmpty) return const [];
    const alpha = 0.25;
    final out = <double>[points.first.value];
    for (var i = 1; i < points.length; i++) {
      out.add(alpha * points[i].value + (1 - alpha) * out[i - 1]);
    }
    return out;
  }

  double? get smoothedLatest => ewma.isEmpty ? null : ewma.last;

  /// Change per week over the measured window.
  double? get weeklyRate {
    if (!hasTrend) return null;
    final days = points.last.at.difference(points.first.at).inMinutes / 1440;
    if (days < 1) return null;
    final smoothed = ewma;
    return (smoothed.last - smoothed.first) / days * 7;
  }

  /// True when the change is in the direction the user wants.
  bool? get isImproving {
    final delta = change;
    if (delta == null || delta == 0) return null;
    return metric.lowerIsBetter ? delta < 0 : delta > 0;
  }
}
