import 'package:lifedna/core/data/synced_entity.dart';

/// A reminder the user wrote themselves. Firestore: `users/{uid}/notifications`.
///
/// Distinct from supplement and task reminders, which are attached to a record
/// that already exists. This is the "remind me to weigh in at 07:00" case,
/// which otherwise has nowhere to live.
///
/// Repeats daily at a fixed local time. The notification id is derived from the
/// record id so rescheduling replaces rather than stacks, and cancelling works
/// without storing a second key.
class Reminder implements SyncedEntity {
  const Reminder({
    required this.id,
    required this.title,
    required this.hour,
    required this.minute,
    required this.createdAt,
    required this.updatedAt,
    this.note,
    this.enabled = true,
    this.deletedAt,
  });

  @override
  final String id;
  final String title;
  final String? note;

  /// Local wall-clock time, 0–23.
  final int hour;

  /// Local wall-clock time, 0–59.
  final int minute;

  final bool enabled;

  final DateTime createdAt;
  @override
  final DateTime updatedAt;
  @override
  final DateTime? deletedAt;

  int get notificationId => id.hashCode & 0x7FFFFFFF;

  String get timeLabel =>
      '${hour.toString().padLeft(2, '0')}:${minute.toString().padLeft(2, '0')}';

  Reminder copyWith({
    String? title,
    String? note,
    int? hour,
    int? minute,
    bool? enabled,
    DateTime? updatedAt,
    DateTime? deletedAt,
  }) => Reminder(
    id: id,
    title: title ?? this.title,
    note: note ?? this.note,
    hour: hour ?? this.hour,
    minute: minute ?? this.minute,
    enabled: enabled ?? this.enabled,
    createdAt: createdAt,
    updatedAt: updatedAt ?? DateTime.now().toUtc(),
    deletedAt: deletedAt ?? this.deletedAt,
  );

  @override
  Map<String, dynamic> toJson() => {
    'id': id,
    'title': title,
    'note': note,
    'hour': hour,
    'minute': minute,
    'enabled': enabled,
    'createdAt': createdAt.toIso8601String(),
    'updatedAt': updatedAt.toIso8601String(),
    'deletedAt': deletedAt?.toIso8601String(),
  };

  factory Reminder.fromJson(Map<String, dynamic> json) => Reminder(
    id: Json.string(json['id']),
    title: Json.string(json['title']),
    note: json['note'] as String?,
    hour: Json.integer(json['hour']).clamp(0, 23),
    minute: Json.integer(json['minute']).clamp(0, 59),
    enabled: Json.boolean(json['enabled'], true),
    createdAt: Json.date(json['createdAt'], fallback: DateTime.now()),
    updatedAt: Json.date(json['updatedAt'], fallback: DateTime.now()),
    deletedAt: Json.dateOrNull(json['deletedAt']),
  );
}
