import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:lifedna/core/data/synced_collection.dart';
import 'package:lifedna/core/data/synced_entity.dart';
import 'package:lifedna/core/error/failure.dart';
import 'package:lifedna/core/notifications/notification_service.dart';
import 'package:lifedna/core/result/result.dart';
import 'package:lifedna/core/storage/hive_store.dart';
import 'package:lifedna/core/sync/outbox.dart';
import 'package:lifedna/features/supplements/domain/supplement_entities.dart';
import 'package:uuid/uuid.dart';

class SupplementRepository {
  SupplementRepository({
    required HiveStore store,
    required Outbox outbox,
    required NotificationService notifications,
    FirebaseFirestore? firestore,
    String? uid,
    Uuid uuid = const Uuid(),
    DateTime Function()? clock,
  }) : _notifications = notifications,
       _uuid = uuid,
       _clock = clock ?? DateTime.now,
       supplements = SyncedCollection<Supplement>(
         store: store,
         outbox: outbox,
         boxName: HiveStore.boxSupplements,
         collection: 'supplements',
         fromJson: Supplement.fromJson,
         firestore: firestore,
         uid: uid,
       ),
       logs = SyncedCollection<SupplementLog>(
         store: store,
         outbox: outbox,
         boxName: HiveStore.boxSupplementLogs,
         collection: 'supplement_logs',
         fromJson: SupplementLog.fromJson,
         firestore: firestore,
         uid: uid,
       );

  final NotificationService _notifications;
  final Uuid _uuid;
  final DateTime Function() _clock;

  final SyncedCollection<Supplement> supplements;
  final SyncedCollection<SupplementLog> logs;

  Stream<List<Supplement>> watchSupplements() => supplements.watchAll();
  Stream<List<SupplementLog>> watchLogs() => logs.watchAll();

  List<Supplement> readSupplements() => supplements.readAll();

  /// Supplements due on [date], with whether each has been taken.
  List<({Supplement supplement, bool taken})> scheduleFor(
    DateTime date, {
    required bool isTrainingDay,
  }) {
    final localDate = Json.localDate(date);
    final takenIds = logs
        .readAll()
        .where((l) => l.localDate == localDate)
        .map((l) => l.supplementId)
        .toSet();

    final due =
        supplements
            .readAll()
            .where((s) => s.isScheduledOn(date, isTrainingDay: isTrainingDay))
            .toList()
          ..sort(
            (a, b) => (a.reminderHour * 60 + a.reminderMinute).compareTo(
              b.reminderHour * 60 + b.reminderMinute,
            ),
          );

    return [
      for (final s in due) (supplement: s, taken: takenIds.contains(s.id)),
    ];
  }

  Supplement create({
    required String name,
    required double dose,
    required String unit,
    SupplementFrequency frequency = SupplementFrequency.daily,
    List<int> weekdays = const [1, 2, 3, 4, 5, 6, 7],
    int reminderHour = 9,
    int reminderMinute = 0,
    bool reminderEnabled = true,
    String? notes,
  }) => Supplement(
    id: _uuid.v4(),
    name: name.trim(),
    dose: dose,
    unit: unit.trim(),
    frequency: frequency,
    weekdays: weekdays,
    reminderHour: reminderHour,
    reminderMinute: reminderMinute,
    reminderEnabled: reminderEnabled,
    notes: notes,
    updatedAt: _clock().toUtc(),
  );

  Future<Result<Supplement>> save(Supplement supplement) async {
    if (supplement.name.trim().isEmpty) {
      return const Err(ValidationFailure('required', field: 'name'));
    }
    if (supplement.dose <= 0) {
      return const Err(ValidationFailure('quantity_must_be_positive'));
    }

    final result = await supplements.put(supplement);
    if (result.isOk) await _syncReminder(supplement);
    return result;
  }

  Future<Result<void>> delete(String id) async {
    final existing = supplements.readOne(id);
    if (existing != null) {
      await _notifications.cancel(existing.notificationId);
    }
    return supplements.remove(
      id,
      tombstone: (s) => s.copyWith(deletedAt: _clock().toUtc()),
    );
  }

  /// Records a dose.
  ///
  /// The document id is deterministic (`supplementId_localDate`), so tapping
  /// "taken" twice — or acting on the notification and then in the app —
  /// records one dose, not two.
  Future<Result<SupplementLog>> logDose(
    Supplement supplement, {
    DateTime? at,
  }) async {
    final when = at ?? _clock();
    final localDate = Json.localDate(when);
    final log = SupplementLog(
      id: SupplementLog.idFor(supplement.id, localDate),
      supplementId: supplement.id,
      supplementName: supplement.name,
      takenAt: when.toUtc(),
      localDate: localDate,
      updatedAt: when.toUtc(),
    );
    return logs.put(log);
  }

  Future<Result<void>> undoDose(String supplementId, {DateTime? at}) {
    final localDate = Json.localDate(at ?? _clock());
    return logs.remove(
      SupplementLog.idFor(supplementId, localDate),
      tombstone: (l) => l.copyWith(deletedAt: _clock().toUtc()),
    );
  }

  /// Adherence over the trailing [days] days.
  ///
  /// Scheduled doses are recomputed from each supplement's own schedule rather
  /// than assumed to be one per day, so a training-days-only supplement is not
  /// penalised for rest days.
  SupplementCompliance compliance({
    int days = 30,
    DateTime? now,
    bool Function(DateTime)? isTrainingDay,
  }) {
    final end = now ?? _clock();
    final all = supplements.readAll();
    final logsByDate = <String, Set<String>>{};
    for (final log in logs.readAll()) {
      logsByDate.putIfAbsent(log.localDate, () => {}).add(log.supplementId);
    }

    var scheduled = 0;
    var taken = 0;
    for (var i = 0; i < days; i++) {
      final day = end.subtract(Duration(days: i));
      final localDate = Json.localDate(day);
      final training = isTrainingDay?.call(day) ?? false;
      for (final supplement in all) {
        if (!supplement.isScheduledOn(day, isTrainingDay: training)) continue;
        scheduled++;
        if (logsByDate[localDate]?.contains(supplement.id) ?? false) taken++;
      }
    }
    return SupplementCompliance(taken: taken, scheduled: scheduled, days: days);
  }

  /// Re-arms every reminder. Called after sign-in and on app resume, because
  /// Android clears scheduled alarms on reboot and after a force-stop.
  Future<void> rescheduleAll() async {
    for (final supplement in supplements.readAll()) {
      await _syncReminder(supplement);
    }
  }

  Future<void> _syncReminder(Supplement supplement) async {
    await _notifications.cancel(supplement.notificationId);
    if (!supplement.reminderEnabled || !supplement.active) return;
    if (supplement.deletedAt != null) return;

    await _notifications.scheduleDaily(
      id: supplement.notificationId,
      channel: NotificationChannelId.supplement,
      title: 'Time for ${supplement.name}',
      body: supplement.doseLabel,
      hour: supplement.reminderHour,
      minute: supplement.reminderMinute,
      payload: 'supplement:${supplement.id}',
    );
  }

  /// Seeds the four supplements the product supports out of the box.
  Future<void> seedStarterStack() async {
    if (supplements.readAll().isNotEmpty) return;
    for (final item in Supplement.starterCatalog) {
      await save(
        create(
          name: item.name,
          dose: item.dose,
          unit: item.unit,
          reminderHour: item.hour,
        ),
      );
    }
  }

  Future<Result<int>> pullAll() async {
    final results = await Future.wait([supplements.pull(), logs.pull()]);
    var total = 0;
    for (final result in results) {
      if (result.isErr) return result;
      total += result.valueOrNull ?? 0;
    }
    return Ok(total);
  }
}
