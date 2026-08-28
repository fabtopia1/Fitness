import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';
import 'package:lifedna/core/providers/providers.dart';
import 'package:lifedna/core/theme/app_theme.dart';
import 'package:lifedna/core/theme/ld_spacing.dart';
import 'package:lifedna/core/widgets/ld_widgets.dart';
import 'package:lifedna/features/calendar/domain/calendar_entities.dart';
import 'package:lifedna/features/calendar/presentation/calendar_providers.dart';
import 'package:lifedna/features/calendar/presentation/event_editor_sheet.dart';
import 'package:lifedna/features/calendar/presentation/task_editor_sheet.dart';
import 'package:lifedna/features/reminders/domain/reminder.dart';
import 'package:lifedna/features/reminders/presentation/reminder_editor_sheet.dart';
import 'package:lifedna/features/reminders/presentation/reminder_providers.dart';

class PlanScreen extends ConsumerStatefulWidget {
  const PlanScreen({super.key});

  @override
  ConsumerState<PlanScreen> createState() => _PlanScreenState();
}

class _PlanScreenState extends ConsumerState<PlanScreen> {
  int _tab = 0;
  bool _syncing = false;

  @override
  Widget build(BuildContext context) {
    final repository = ref.watch(calendarRepositoryProvider);

    return Scaffold(
      appBar: AppBar(
        title: const Text('Plan'),
        actions: [
          if (repository.isGoogleConfigured)
            IconButton(
              icon: _syncing
                  ? const SizedBox(
                      width: 18,
                      height: 18,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : const Icon(Icons.sync_rounded),
              tooltip: 'Sync Google Calendar',
              onPressed: _syncing ? null : _syncGoogle,
            ),
        ],
        bottom: PreferredSize(
          preferredSize: const Size.fromHeight(56),
          child: Padding(
            padding: const EdgeInsets.fromLTRB(
              LdSpacing.s4,
              0,
              LdSpacing.s4,
              LdSpacing.s2,
            ),
            child: SegmentedButton<int>(
              segments: const [
                ButtonSegment(value: 0, label: Text('Tasks')),
                ButtonSegment(value: 1, label: Text('Calendar')),
                ButtonSegment(value: 2, label: Text('Reminders')),
              ],
              selected: {_tab},
              onSelectionChanged: (value) =>
                  setState(() => _tab = value.first),
            ),
          ),
        ),
      ),
      body: switch (_tab) {
        0 => const _TasksTab(),
        1 => const _CalendarTab(),
        _ => const _RemindersTab(),
      },
      floatingActionButton: FloatingActionButton.extended(
        onPressed: switch (_tab) {
          0 => _newTask,
          1 => _newEvent,
          _ => _newReminder,
        },
        icon: const Icon(Icons.add_rounded),
        label: Text(switch (_tab) {
          0 => 'Task',
          1 => 'Event',
          _ => 'Reminder',
        }),
      ),
    );
  }

  Future<void> _newTask() => showModalBottomSheet<void>(
        context: context,
        isScrollControlled: true,
        builder: (_) => const TaskEditorSheet(),
      );

  Future<void> _newEvent() => showModalBottomSheet<void>(
        context: context,
        isScrollControlled: true,
        builder: (_) => const EventEditorSheet(),
      );

  Future<void> _newReminder() => ReminderEditorSheet.show(
        context,
        ref.read(reminderRepositoryProvider).draft(),
      );

  Future<void> _syncGoogle() async {
    setState(() => _syncing = true);
    final repository = ref.read(calendarRepositoryProvider);

    if (!await repository.isGoogleConnected) {
      final connect = await repository.connectGoogle();
      if (!mounted) return;
      final failure = connect.failureOrNull;
      if (failure != null) {
        setState(() => _syncing = false);
        showFailureSnack(context, failure);
        return;
      }
    }

    final result = await repository.syncGoogle();
    if (!mounted) return;
    setState(() => _syncing = false);
    result.when(
      ok: (count) => showSuccessSnack(context, 'Synced $count events'),
      err: (failure) => showFailureSnack(context, failure),
    );
  }
}

class _TasksTab extends ConsumerWidget {
  const _TasksTab();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final c = context.ldColors;
    final type = context.ldType;
    final async = ref.watch(tasksProvider);

    return LdAsyncView(
      value: async,
      onRetry: () => ref.invalidate(tasksProvider),
      errorContext: 'Tasks',
      isEmpty: (list) => list.where((t) => !t.isDone).isEmpty,
      empty: const LdEmptyState(
        icon: Icons.checklist_rounded,
        headline: 'Nothing to do',
        body: 'Add a task and it will show on your dashboard.',
      ),
      data: (_) {
        final open = ref.watch(openTasksProvider);
        final now = ref.watch(clockProvider)();

        return ListView(
          padding: const EdgeInsets.fromLTRB(
            LdSpacing.s4,
            LdSpacing.s3,
            LdSpacing.s4,
            LdSpacing.scrollBottom,
          ),
          children: [
            for (final task in open)
              Dismissible(
                key: ValueKey(task.id),
                direction: DismissDirection.endToStart,
                background: Container(
                  alignment: Alignment.centerRight,
                  padding: const EdgeInsets.only(right: LdSpacing.s4),
                  child: Icon(Icons.delete_outline_rounded, color: c.danger),
                ),
                onDismissed: (_) => ref
                    .read(calendarRepositoryProvider)
                    .deleteTask(task.id),
                child: ListTile(
                  contentPadding: EdgeInsets.zero,
                  leading: Checkbox(
                    value: task.isDone,
                    onChanged: (_) => ref
                        .read(calendarRepositoryProvider)
                        .toggleTask(task),
                  ),
                  title: Text(
                    task.title,
                    style: type.titleM.copyWith(color: c.textPrimary),
                  ),
                  subtitle: Text(
                    [
                      task.category.label,
                      task.priority.label,
                      if (task.dueAt != null)
                        DateFormat('d MMM HH:mm')
                            .format(task.dueAt!.toLocal()),
                    ].join(' · '),
                    style: type.bodyS.copyWith(
                      color: task.isOverdue(now) ? c.danger : c.textTertiary,
                    ),
                  ),
                  onTap: () => showModalBottomSheet<void>(
                    context: context,
                    isScrollControlled: true,
                    builder: (_) => TaskEditorSheet(existing: task),
                  ),
                ),
              ),
          ],
        );
      },
    );
  }
}

class _CalendarTab extends ConsumerWidget {
  const _CalendarTab();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final c = context.ldColors;
    final type = context.ldType;
    final async = ref.watch(calendarEventsProvider);
    final selected = ref.watch(selectedDayProvider);
    final today = ref.watch(todayProvider);
    final repository = ref.watch(calendarRepositoryProvider);

    return LdAsyncView(
      value: async,
      onRetry: () => ref.invalidate(calendarEventsProvider),
      errorContext: 'Calendar',
      data: (_) {
        final events = ref.watch(eventsOnSelectedDayProvider);
        final tasksDue = repository.tasksDueOn(selected);

        return Column(
          children: [
            SizedBox(
              height: 76,
              child: ListView.builder(
                scrollDirection: Axis.horizontal,
                padding: const EdgeInsets.symmetric(horizontal: LdSpacing.s4),
                itemCount: 21,
                itemBuilder: (context, index) {
                  final day = today.add(Duration(days: index - 3));
                  final isSelected = day.year == selected.year &&
                      day.month == selected.month &&
                      day.day == selected.day;
                  return GestureDetector(
                    onTap: () => ref
                        .read(selectedDayProvider.notifier)
                        .state = day,
                    child: Container(
                      width: 52,
                      margin: const EdgeInsets.symmetric(horizontal: 3),
                      decoration: BoxDecoration(
                        color: isSelected ? c.primaryMuted : c.surface,
                        borderRadius: BorderRadius.circular(LdRadius.m),
                        border: Border.all(
                          color: isSelected ? c.primary : c.border,
                        ),
                      ),
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Text(
                            DateFormat('E').format(day).toUpperCase(),
                            style: type.caption.copyWith(
                              color: isSelected ? c.primary : c.textTertiary,
                            ),
                          ),
                          const SizedBox(height: 2),
                          Text(
                            '${day.day}',
                            style: type.titleM.copyWith(
                              color: isSelected ? c.primary : c.textPrimary,
                            ),
                          ),
                        ],
                      ),
                    ),
                  );
                },
              ),
            ),
            Expanded(
              child: events.isEmpty && tasksDue.isEmpty
                  ? LdEmptyState(
                      icon: Icons.event_available_rounded,
                      headline: 'Nothing scheduled',
                      body: repository.isGoogleConfigured
                          ? 'Add an event, or sync your Google Calendar from '
                              'the toolbar.'
                          : 'Add an event to plan this day.',
                    )
                  : ListView(
                      padding: const EdgeInsets.fromLTRB(
                        LdSpacing.s4,
                        LdSpacing.s3,
                        LdSpacing.s4,
                        LdSpacing.scrollBottom,
                      ),
                      children: [
                        for (final event in events)
                          _EventTile(event: event),
                        if (tasksDue.isNotEmpty) ...[
                          const LdSectionHeader(title: 'Tasks due'),
                          for (final task in tasksDue)
                            ListTile(
                              contentPadding: EdgeInsets.zero,
                              leading: Icon(
                                task.isDone
                                    ? Icons.check_circle_rounded
                                    : Icons.circle_outlined,
                                color:
                                    task.isDone ? c.success : c.textTertiary,
                              ),
                              title: Text(
                                task.title,
                                style: type.bodyM
                                    .copyWith(color: c.textPrimary),
                              ),
                            ),
                        ],
                      ],
                    ),
            ),
          ],
        );
      },
    );
  }
}

class _EventTile extends ConsumerWidget {
  const _EventTile({required this.event});
  final CalendarEvent event;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final c = context.ldColors;
    final type = context.ldType;

    return Padding(
      padding: const EdgeInsets.only(bottom: LdSpacing.s2),
      child: LdCard(
        padding: const EdgeInsets.all(LdSpacing.s3),
        onTap: event.isReadOnly
            ? null
            : () => showModalBottomSheet<void>(
                  context: context,
                  isScrollControlled: true,
                  builder: (_) => EventEditorSheet(existing: event),
                ),
        child: Row(
          children: [
            Container(
              width: 3,
              height: 36,
              decoration: BoxDecoration(
                color: event.isReadOnly ? c.info : c.primary,
                borderRadius: BorderRadius.circular(LdRadius.full),
              ),
            ),
            const SizedBox(width: LdSpacing.s3),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    event.title,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: type.titleM.copyWith(color: c.textPrimary),
                  ),
                  Text(
                    event.isAllDay
                        ? 'All day'
                        : '${DateFormat('HH:mm').format(event.startAt.toLocal())}'
                            ' – '
                            '${DateFormat('HH:mm').format(event.endAt.toLocal())}',
                    style: type.bodyS.copyWith(color: c.textTertiary),
                  ),
                ],
              ),
            ),
            if (event.isReadOnly)
              Tooltip(
                message: 'From Google Calendar — read only',
                child: Icon(Icons.lock_outline_rounded,
                    size: 16, color: c.textTertiary),
              ),
          ],
        ),
      ),
    );
  }
}

/// Reminders the user wrote themselves, as opposed to the ones attached to a
/// supplement or a task.
class _RemindersTab extends ConsumerWidget {
  const _RemindersTab();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final reminders = ref.watch(remindersProvider);

    return LdAsyncView<List<Reminder>>(
      value: reminders,
      onRetry: () => ref.invalidate(remindersProvider),
      errorContext: 'reminders',
      isEmpty: (items) => items.isEmpty,
      empty: LdEmptyState(
        icon: Icons.alarm_rounded,
        headline: 'No reminders yet',
        body: 'Set one for anything the app does not already track — weigh in, '
            'stretch, book a session.',
        actionLabel: 'Add a reminder',
        onAction: () => ReminderEditorSheet.show(
          context,
          ref.read(reminderRepositoryProvider).draft(),
        ),
      ),
      data: (items) => ListView.builder(
        padding: const EdgeInsets.fromLTRB(
          LdSpacing.screenH,
          LdSpacing.s4,
          LdSpacing.screenH,
          LdSpacing.scrollBottom,
        ),
        itemCount: items.length,
        itemBuilder: (context, index) => _ReminderTile(reminder: items[index]),
      ),
    );
  }
}

class _ReminderTile extends ConsumerWidget {
  const _ReminderTile({required this.reminder});
  final Reminder reminder;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final c = context.ldColors;
    final type = context.ldType;

    return Padding(
      padding: const EdgeInsets.only(bottom: LdSpacing.cardGap),
      child: LdCard(
        onTap: () => ReminderEditorSheet.show(context, reminder),
        child: Row(
          children: [
            Text(
              reminder.timeLabel,
              style: type.titleL.copyWith(
                color: reminder.enabled ? c.primary : c.textDisabled,
              ),
            ),
            const SizedBox(width: LdSpacing.s4),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    reminder.title,
                    style: type.titleM.copyWith(
                      color: reminder.enabled ? c.textPrimary : c.textTertiary,
                    ),
                  ),
                  if (reminder.note != null)
                    Text(
                      reminder.note!,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: type.bodyS.copyWith(color: c.textTertiary),
                    ),
                ],
              ),
            ),
            Switch(
              value: reminder.enabled,
              onChanged: (value) => ref
                  .read(reminderRepositoryProvider)
                  .setEnabled(reminder, on: value),
            ),
          ],
        ),
      ),
    );
  }
}
