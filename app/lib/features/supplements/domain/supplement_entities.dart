import 'package:lifedna/core/data/synced_entity.dart';

/// How often a supplement is scheduled.
enum SupplementFrequency {
  daily('daily', 'Every day'),
  weekdays('weekdays', 'Specific days'),
  trainingDays('training_days', 'Training days only');

  const SupplementFrequency(this.wire, this.label);
  final String wire;
  final String label;

  static SupplementFrequency fromWire(String value) => values.firstWhere(
    (f) => f.wire == value,
    orElse: () => SupplementFrequency.daily,
  );
}

/// A supplement in the user's stack. Firestore: `users/{uid}/supplements/{id}`.
class Supplement implements SyncedEntity {
  const Supplement({
    required this.id,
    required this.name,
    required this.dose,
    required this.unit,
    required this.updatedAt,
    this.frequency = SupplementFrequency.daily,
    this.weekdays = const [1, 2, 3, 4, 5, 6, 7],
    this.reminderHour = 9,
    this.reminderMinute = 0,
    this.reminderEnabled = true,
    this.notes,
    this.active = true,
    this.deletedAt,
  });

  @override
  final String id;
  final String name;
  final double dose;
  final String unit;

  final SupplementFrequency frequency;

  /// ISO weekdays (Mon = 1 … Sun = 7). Used when [frequency] is weekdays.
  final List<int> weekdays;

  final int reminderHour;
  final int reminderMinute;
  final bool reminderEnabled;
  final String? notes;
  final bool active;

  @override
  final DateTime updatedAt;
  @override
  final DateTime? deletedAt;

  String get doseLabel =>
      '${dose == dose.roundToDouble() ? dose.round() : dose} $unit';

  String get reminderLabel =>
      '${reminderHour.toString().padLeft(2, '0')}:'
      '${reminderMinute.toString().padLeft(2, '0')}';

  /// Whether this supplement is due on [date].
  ///
  /// Training-day scheduling needs to know whether the user trains that day,
  /// which only the caller knows — hence the parameter rather than a hidden
  /// dependency inside the entity.
  bool isScheduledOn(DateTime date, {required bool isTrainingDay}) {
    if (!active) return false;
    return switch (frequency) {
      SupplementFrequency.daily => true,
      SupplementFrequency.weekdays => weekdays.contains(date.weekday),
      SupplementFrequency.trainingDays => isTrainingDay,
    };
  }

  /// A stable notification id derived from the document id.
  ///
  /// Must be deterministic: rescheduling has to replace the previous
  /// notification, not stack a second one on top of it.
  int get notificationId => id.hashCode & 0x7FFFFFFF;

  Supplement copyWith({
    String? name,
    double? dose,
    String? unit,
    SupplementFrequency? frequency,
    List<int>? weekdays,
    int? reminderHour,
    int? reminderMinute,
    bool? reminderEnabled,
    String? notes,
    bool? active,
    DateTime? updatedAt,
    DateTime? deletedAt,
  }) => Supplement(
    id: id,
    name: name ?? this.name,
    dose: dose ?? this.dose,
    unit: unit ?? this.unit,
    frequency: frequency ?? this.frequency,
    weekdays: weekdays ?? this.weekdays,
    reminderHour: reminderHour ?? this.reminderHour,
    reminderMinute: reminderMinute ?? this.reminderMinute,
    reminderEnabled: reminderEnabled ?? this.reminderEnabled,
    notes: notes ?? this.notes,
    active: active ?? this.active,
    updatedAt: updatedAt ?? DateTime.now().toUtc(),
    deletedAt: deletedAt ?? this.deletedAt,
  );

  @override
  Map<String, dynamic> toJson() => {
    'id': id,
    'name': name,
    'dose': dose,
    'unit': unit,
    'frequency': frequency.wire,
    'weekdays': weekdays,
    'reminderHour': reminderHour,
    'reminderMinute': reminderMinute,
    'reminderEnabled': reminderEnabled,
    'notes': notes,
    'active': active,
    'updatedAt': updatedAt.toIso8601String(),
    'deletedAt': deletedAt?.toIso8601String(),
  };

  factory Supplement.fromJson(Map<String, dynamic> json) => Supplement(
    id: Json.string(json['id']),
    name: Json.string(json['name']),
    dose: Json.number(json['dose']),
    unit: Json.string(json['unit'], 'g'),
    frequency: SupplementFrequency.fromWire(
      Json.string(json['frequency'], 'daily'),
    ),
    weekdays: (json['weekdays'] as List? ?? const [1, 2, 3, 4, 5, 6, 7])
        .whereType<num>()
        .map((n) => n.toInt())
        .toList(),
    reminderHour: Json.integer(json['reminderHour'], 9),
    reminderMinute: Json.integer(json['reminderMinute']),
    reminderEnabled: Json.boolean(json['reminderEnabled'], true),
    notes: json['notes'] as String?,
    active: Json.boolean(json['active'], true),
    updatedAt: Json.date(json['updatedAt'], fallback: DateTime.now()),
    deletedAt: Json.dateOrNull(json['deletedAt']),
  );

  /// The starter stack offered at setup. These are the four the product
  /// explicitly supports out of the box.
  static const List<({String name, double dose, String unit, int hour})>
  starterCatalog = [
    (name: 'Creatine monohydrate', dose: 5, unit: 'g', hour: 19),
    (name: 'Vitamin D3', dose: 4000, unit: 'IU', hour: 9),
    (name: 'Omega-3', dose: 1, unit: 'g', hour: 13),
    (name: 'Magnesium glycinate', dose: 400, unit: 'mg', hour: 22),
  ];
}

/// A taken dose. Firestore: `users/{uid}/supplement_logs/{id}`.
class SupplementLog implements SyncedEntity {
  const SupplementLog({
    required this.id,
    required this.supplementId,
    required this.supplementName,
    required this.takenAt,
    required this.localDate,
    required this.updatedAt,
    this.deletedAt,
  });

  @override
  final String id;
  final String supplementId;
  final String supplementName;
  final DateTime takenAt;
  final String localDate;

  @override
  final DateTime updatedAt;
  @override
  final DateTime? deletedAt;

  /// Deterministic id: one dose per supplement per day.
  ///
  /// This makes logging idempotent — a double tap, or the same action arriving
  /// from a notification and the app at once, cannot produce two doses.
  static String idFor(String supplementId, String localDate) =>
      '${supplementId}_$localDate';

  @override
  Map<String, dynamic> toJson() => {
    'id': id,
    'supplementId': supplementId,
    'supplementName': supplementName,
    'takenAt': takenAt.toIso8601String(),
    'localDate': localDate,
    'updatedAt': updatedAt.toIso8601String(),
    'deletedAt': deletedAt?.toIso8601String(),
  };

  factory SupplementLog.fromJson(Map<String, dynamic> json) => SupplementLog(
    id: Json.string(json['id']),
    supplementId: Json.string(json['supplementId']),
    supplementName: Json.string(json['supplementName']),
    takenAt: Json.date(json['takenAt'], fallback: DateTime.now()),
    localDate: Json.string(json['localDate']),
    updatedAt: Json.date(json['updatedAt'], fallback: DateTime.now()),
    deletedAt: Json.dateOrNull(json['deletedAt']),
  );

  SupplementLog copyWith({DateTime? updatedAt, DateTime? deletedAt}) =>
      SupplementLog(
        id: id,
        supplementId: supplementId,
        supplementName: supplementName,
        takenAt: takenAt,
        localDate: localDate,
        updatedAt: updatedAt ?? DateTime.now().toUtc(),
        deletedAt: deletedAt ?? this.deletedAt,
      );
}

/// Adherence over a window. Derived, never stored.
class SupplementCompliance {
  const SupplementCompliance({
    required this.taken,
    required this.scheduled,
    required this.days,
  });

  final int taken;
  final int scheduled;
  final int days;

  double get percent => scheduled == 0 ? 0 : taken / scheduled * 100;

  String get label => '${percent.round()} %';
}
