/// Contract for anything that replicates between Hive and Firestore.
///
/// [updatedAt] is the conflict-resolution field: for mutable records the later
/// timestamp wins. Append-only records (a logged set, a logged meal) carry a
/// client-generated id and are never overwritten, so the rule never fires for
/// them — which is the point. A user's logged workout cannot be clobbered by a
/// stale server copy.
abstract interface class SyncedEntity {
  String get id;
  DateTime get updatedAt;

  /// Soft-delete marker. Tombstones must replicate, or a delete made offline
  /// would be resurrected by the next pull.
  DateTime? get deletedAt;

  Map<String, dynamic> toJson();
}

/// Helpers for the JSON shape shared by Hive and Firestore.
abstract final class Json {
  static DateTime date(Object? value, {DateTime? fallback}) {
    if (value is String) {
      final parsed = DateTime.tryParse(value);
      if (parsed != null) return parsed.toUtc();
    }
    if (value is int) {
      return DateTime.fromMillisecondsSinceEpoch(value, isUtc: true);
    }
    return (fallback ?? DateTime.fromMillisecondsSinceEpoch(0)).toUtc();
  }

  static DateTime? dateOrNull(Object? value) {
    if (value == null) return null;
    if (value is String) return DateTime.tryParse(value)?.toUtc();
    if (value is int) {
      return DateTime.fromMillisecondsSinceEpoch(value, isUtc: true);
    }
    return null;
  }

  static double number(Object? value, [double fallback = 0]) =>
      (value as num?)?.toDouble() ?? fallback;

  static int integer(Object? value, [int fallback = 0]) =>
      (value as num?)?.toInt() ?? fallback;

  static String string(Object? value, [String fallback = '']) =>
      value as String? ?? fallback;

  static bool boolean(Object? value, [bool fallback = false]) =>
      value as bool? ?? fallback;

  static List<String> stringList(Object? value) =>
      (value as List?)?.whereType<String>().toList() ?? const [];

  static Map<String, dynamic> map(Object? value) =>
      value is Map ? Map<String, dynamic>.from(value) : <String, dynamic>{};

  /// Day bucket in the user's local timezone, `yyyy-MM-dd`.
  ///
  /// Stored alongside the UTC instant so that travelling across timezones
  /// cannot retroactively move a meal into a different day.
  static String localDate(DateTime local) =>
      '${local.year.toString().padLeft(4, '0')}-'
      '${local.month.toString().padLeft(2, '0')}-'
      '${local.day.toString().padLeft(2, '0')}';
}
