import 'package:lifedna/core/data/synced_entity.dart';
import 'package:lifedna/shared/enums/enums.dart';

/// A task. Firestore: `users/{uid}/tasks/{id}`.
class Task implements SyncedEntity {
  const Task({
    required this.id,
    required this.title,
    required this.updatedAt,
    required this.createdAt,
    this.notes,
    this.category = TaskCategory.personal,
    this.priority = TaskPriority.p3,
    this.status = TaskStatus.open,
    this.dueAt,
    this.reminderMinutesBefore,
    this.completedAt,
    this.deletedAt,
  });

  @override
  final String id;
  final String title;
  final String? notes;
  final TaskCategory category;
  final TaskPriority priority;
  final TaskStatus status;
  final DateTime? dueAt;

  /// Lead time for a local reminder. Null means no reminder.
  final int? reminderMinutesBefore;

  final DateTime? completedAt;
  final DateTime createdAt;

  @override
  final DateTime updatedAt;
  @override
  final DateTime? deletedAt;

  bool get isDone => status == TaskStatus.done;

  bool isOverdue(DateTime now) =>
      !isDone && dueAt != null && dueAt!.isBefore(now);

  bool isDueOn(DateTime day) {
    final due = dueAt;
    if (due == null) return false;
    return due.year == day.year && due.month == day.month && due.day == day.day;
  }

  DateTime? get reminderAt {
    final due = dueAt;
    final lead = reminderMinutesBefore;
    if (due == null || lead == null) return null;
    return due.subtract(Duration(minutes: lead));
  }

  int get notificationId => id.hashCode & 0x7FFFFFFF;

  Task copyWith({
    String? title,
    String? notes,
    TaskCategory? category,
    TaskPriority? priority,
    TaskStatus? status,
    DateTime? dueAt,
    int? reminderMinutesBefore,
    DateTime? completedAt,
    DateTime? updatedAt,
    DateTime? deletedAt,
    bool clearDueAt = false,
  }) => Task(
    id: id,
    title: title ?? this.title,
    notes: notes ?? this.notes,
    category: category ?? this.category,
    priority: priority ?? this.priority,
    status: status ?? this.status,
    dueAt: clearDueAt ? null : (dueAt ?? this.dueAt),
    reminderMinutesBefore: reminderMinutesBefore ?? this.reminderMinutesBefore,
    completedAt: completedAt ?? this.completedAt,
    createdAt: createdAt,
    updatedAt: updatedAt ?? DateTime.now().toUtc(),
    deletedAt: deletedAt ?? this.deletedAt,
  );

  @override
  Map<String, dynamic> toJson() => {
    'id': id,
    'title': title,
    'notes': notes,
    'category': category.wire,
    'priority': priority.level,
    'status': status.wire,
    'dueAt': dueAt?.toIso8601String(),
    'reminderMinutesBefore': reminderMinutesBefore,
    'completedAt': completedAt?.toIso8601String(),
    'createdAt': createdAt.toIso8601String(),
    'updatedAt': updatedAt.toIso8601String(),
    'deletedAt': deletedAt?.toIso8601String(),
  };

  factory Task.fromJson(Map<String, dynamic> json) => Task(
    id: Json.string(json['id']),
    title: Json.string(json['title']),
    notes: json['notes'] as String?,
    category: TaskCategory.values.firstWhere(
      (c) => c.wire == json['category'],
      orElse: () => TaskCategory.personal,
    ),
    priority: TaskPriority.fromLevel(Json.integer(json['priority'], 3)),
    status: TaskStatus.values.firstWhere(
      (s) => s.wire == json['status'],
      orElse: () => TaskStatus.open,
    ),
    dueAt: Json.dateOrNull(json['dueAt']),
    reminderMinutesBefore: (json['reminderMinutesBefore'] as num?)?.toInt(),
    completedAt: Json.dateOrNull(json['completedAt']),
    createdAt: Json.date(json['createdAt'], fallback: DateTime.now()),
    updatedAt: Json.date(json['updatedAt'], fallback: DateTime.now()),
    deletedAt: Json.dateOrNull(json['deletedAt']),
  );
}

/// Where an event came from.
enum EventSource {
  lifedna('lifedna', 'LifeDNA'),
  google('google', 'Google Calendar');

  const EventSource(this.wire, this.label);
  final String wire;
  final String label;
}

/// A calendar event. Firestore: `users/{uid}/calendar_events/{id}`.
///
/// Google events are cached here read-only so the schedule renders offline.
/// Google Calendar remains authoritative for them: LifeDNA never edits an
/// event it did not create.
class CalendarEvent implements SyncedEntity {
  const CalendarEvent({
    required this.id,
    required this.title,
    required this.startAt,
    required this.endAt,
    required this.updatedAt,
    this.source = EventSource.lifedna,
    this.description,
    this.location,
    this.isAllDay = false,
    this.providerEventId,
    this.calendarId,
    this.deletedAt,
  });

  @override
  final String id;
  final String title;
  final String? description;
  final String? location;
  final DateTime startAt;
  final DateTime endAt;
  final bool isAllDay;
  final EventSource source;

  /// Set for events mirrored from Google.
  final String? providerEventId;
  final String? calendarId;

  @override
  final DateTime updatedAt;
  @override
  final DateTime? deletedAt;

  bool get isReadOnly => source == EventSource.google;

  Duration get duration => endAt.difference(startAt);

  bool occursOn(DateTime day) {
    final start = DateTime(day.year, day.month, day.day);
    final end = start.add(const Duration(days: 1));
    return startAt.isBefore(end) && endAt.isAfter(start);
  }

  CalendarEvent copyWith({
    String? title,
    String? description,
    String? location,
    DateTime? startAt,
    DateTime? endAt,
    bool? isAllDay,
    DateTime? updatedAt,
    DateTime? deletedAt,
  }) => CalendarEvent(
    id: id,
    title: title ?? this.title,
    description: description ?? this.description,
    location: location ?? this.location,
    startAt: startAt ?? this.startAt,
    endAt: endAt ?? this.endAt,
    isAllDay: isAllDay ?? this.isAllDay,
    source: source,
    providerEventId: providerEventId,
    calendarId: calendarId,
    updatedAt: updatedAt ?? DateTime.now().toUtc(),
    deletedAt: deletedAt ?? this.deletedAt,
  );

  @override
  Map<String, dynamic> toJson() => {
    'id': id,
    'title': title,
    'description': description,
    'location': location,
    'startAt': startAt.toIso8601String(),
    'endAt': endAt.toIso8601String(),
    'isAllDay': isAllDay,
    'source': source.wire,
    'providerEventId': providerEventId,
    'calendarId': calendarId,
    'updatedAt': updatedAt.toIso8601String(),
    'deletedAt': deletedAt?.toIso8601String(),
  };

  factory CalendarEvent.fromJson(Map<String, dynamic> json) => CalendarEvent(
    id: Json.string(json['id']),
    title: Json.string(json['title']),
    description: json['description'] as String?,
    location: json['location'] as String?,
    startAt: Json.date(json['startAt'], fallback: DateTime.now()),
    endAt: Json.date(json['endAt'], fallback: DateTime.now()),
    isAllDay: Json.boolean(json['isAllDay']),
    source: EventSource.values.firstWhere(
      (s) => s.wire == json['source'],
      orElse: () => EventSource.lifedna,
    ),
    providerEventId: json['providerEventId'] as String?,
    calendarId: json['calendarId'] as String?,
    updatedAt: Json.date(json['updatedAt'], fallback: DateTime.now()),
    deletedAt: Json.dateOrNull(json['deletedAt']),
  );
}
