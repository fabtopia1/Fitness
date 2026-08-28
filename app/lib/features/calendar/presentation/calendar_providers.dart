import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:lifedna/core/providers/providers.dart';
import 'package:lifedna/features/calendar/domain/calendar_entities.dart';

final tasksProvider = StreamProvider<List<Task>>(
  (ref) => ref.watch(calendarRepositoryProvider).watchTasks(),
);

final calendarEventsProvider = StreamProvider<List<CalendarEvent>>(
  (ref) => ref.watch(calendarRepositoryProvider).watchEvents(),
);

final openTasksProvider = Provider<List<Task>>((ref) {
  ref.watch(tasksProvider);
  return ref.watch(calendarRepositoryProvider).openTasks();
});

final overdueTaskCountProvider = Provider<int>((ref) {
  ref.watch(tasksProvider);
  return ref.watch(calendarRepositoryProvider).overdueCount();
});

final upcomingEventsProvider = Provider<List<CalendarEvent>>((ref) {
  ref.watch(calendarEventsProvider);
  return ref.watch(calendarRepositoryProvider).upcoming();
});

final selectedDayProvider = StateProvider<DateTime>(
  (ref) => ref.watch(todayProvider),
);

final eventsOnSelectedDayProvider = Provider<List<CalendarEvent>>((ref) {
  ref.watch(calendarEventsProvider);
  return ref
      .watch(calendarRepositoryProvider)
      .eventsOn(ref.watch(selectedDayProvider));
});
