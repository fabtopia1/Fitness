import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:lifedna/core/providers/providers.dart';
import 'package:lifedna/features/reminders/data/reminder_repository.dart';
import 'package:lifedna/features/reminders/domain/reminder.dart';

final reminderRepositoryProvider = Provider<ReminderRepository>((ref) {
  final bootstrap = ref.watch(bootstrapProvider);
  return ReminderRepository(
    store: bootstrap.store,
    outbox: ref.watch(outboxProvider),
    notifications: bootstrap.notifications,
    firestore: bootstrap.firestore,
    uid: ref.watch(currentUidProvider),
    clock: ref.watch(clockProvider),
  );
});

final remindersProvider = StreamProvider<List<Reminder>>(
  (ref) => ref.watch(reminderRepositoryProvider).watchAll(),
);
