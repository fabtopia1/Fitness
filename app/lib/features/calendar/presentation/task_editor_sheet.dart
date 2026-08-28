import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';
import 'package:lifedna/core/providers/providers.dart';
import 'package:lifedna/core/theme/app_theme.dart';
import 'package:lifedna/core/theme/ld_spacing.dart';
import 'package:lifedna/core/widgets/ld_widgets.dart';
import 'package:lifedna/features/calendar/domain/calendar_entities.dart';
import 'package:lifedna/shared/enums/enums.dart';

class TaskEditorSheet extends ConsumerStatefulWidget {
  const TaskEditorSheet({super.key, this.existing});
  final Task? existing;

  @override
  ConsumerState<TaskEditorSheet> createState() => _TaskEditorSheetState();
}

class _TaskEditorSheetState extends ConsumerState<TaskEditorSheet> {
  late final TextEditingController _title =
      TextEditingController(text: widget.existing?.title ?? '');
  late TaskCategory _category =
      widget.existing?.category ?? TaskCategory.personal;
  late TaskPriority _priority =
      widget.existing?.priority ?? TaskPriority.p3;
  late DateTime? _dueAt = widget.existing?.dueAt?.toLocal();
  late int? _reminder = widget.existing?.reminderMinutesBefore;
  bool _saving = false;

  @override
  void dispose() {
    _title.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final c = context.ldColors;
    final type = context.ldType;
    final isEdit = widget.existing != null;

    return SafeArea(
      child: Padding(
        padding: EdgeInsets.fromLTRB(
          LdSpacing.s4,
          0,
          LdSpacing.s4,
          MediaQuery.of(context).viewInsets.bottom + LdSpacing.s5,
        ),
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Expanded(
                    child: Text(
                      isEdit ? 'Edit task' : 'New task',
                      style: type.headlineM.copyWith(color: c.textPrimary),
                    ),
                  ),
                  if (isEdit)
                    IconButton(
                      icon: const Icon(Icons.delete_outline_rounded),
                      onPressed: () async {
                        // Captured before the await: the build-scoped context
                        // is not the State's, so `mounted` does not vouch for it.
                        final navigator = Navigator.of(context);
                        await ref
                            .read(calendarRepositoryProvider)
                            .deleteTask(widget.existing!.id);
                        if (mounted) navigator.pop();
                      },
                    ),
                ],
              ),
              const SizedBox(height: LdSpacing.s4),
              TextField(
                controller: _title,
                autofocus: !isEdit,
                textCapitalization: TextCapitalization.sentences,
                decoration: const InputDecoration(labelText: 'Task'),
              ),
              const SizedBox(height: LdSpacing.s4),
              Row(
                children: [
                  Expanded(
                    child: DropdownButtonFormField<TaskCategory>(
                             isExpanded: true,
                      initialValue: _category,
                      decoration:
                          const InputDecoration(labelText: 'Category'),
                      items: [
                        for (final category in TaskCategory.values)
                          DropdownMenuItem(
                            value: category,
                            child: Text(category.label),
                          ),
                      ],
                      onChanged: (value) =>
                          setState(() => _category = value ?? _category),
                    ),
                  ),
                  const SizedBox(width: LdSpacing.s3),
                  Expanded(
                    child: DropdownButtonFormField<TaskPriority>(
                             isExpanded: true,
                      initialValue: _priority,
                      decoration:
                          const InputDecoration(labelText: 'Priority'),
                      items: [
                        for (final priority in TaskPriority.values)
                          DropdownMenuItem(
                            value: priority,
                            child: Text(priority.label),
                          ),
                      ],
                      onChanged: (value) =>
                          setState(() => _priority = value ?? _priority),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: LdSpacing.s4),
              ListTile(
                contentPadding: EdgeInsets.zero,
                leading: const Icon(Icons.event_rounded),
                title: Text(
                  _dueAt == null
                      ? 'No due date'
                      : DateFormat('EEE d MMM, HH:mm').format(_dueAt!),
                ),
                trailing: _dueAt == null
                    ? null
                    : IconButton(
                        icon: const Icon(Icons.close_rounded),
                        onPressed: () => setState(() {
                          _dueAt = null;
                          _reminder = null;
                        }),
                      ),
                onTap: _pickDue,
              ),
              if (_dueAt != null) ...[
                const SizedBox(height: LdSpacing.s2),
                Text(
                  'Remind me',
                  style: type.labelMono.copyWith(color: c.textTertiary),
                ),
                const SizedBox(height: LdSpacing.s2),
                Wrap(
                  spacing: LdSpacing.s2,
                  children: [
                    for (final option in const [
                      (label: 'None', minutes: null),
                      (label: 'At time', minutes: 0),
                      (label: '30 min', minutes: 30),
                      (label: '1 hour', minutes: 60),
                      (label: '1 day', minutes: 1440),
                    ])
                      ChoiceChip(
                        label: Text(option.label),
                        selected: _reminder == option.minutes,
                        onSelected: (_) =>
                            setState(() => _reminder = option.minutes),
                      ),
                  ],
                ),
              ],
              const SizedBox(height: LdSpacing.s5),
              LdPrimaryButton(
                label: isEdit ? 'Save changes' : 'Add task',
                size: LdButtonSize.l,
                loading: _saving,
                onPressed: _save,
              ),
            ],
          ),
        ),
      ),
    );
  }

  Future<void> _pickDue() async {
    final now = DateTime.now();
    final date = await showDatePicker(
      context: context,
      initialDate: _dueAt ?? now,
      firstDate: now.subtract(const Duration(days: 365)),
      lastDate: now.add(const Duration(days: 365 * 3)),
    );
    if (date == null || !mounted) return;

    final time = await showTimePicker(
      context: context,
      initialTime: TimeOfDay.fromDateTime(_dueAt ?? now),
    );
    if (!mounted) return;

    setState(() {
      _dueAt = DateTime(
        date.year,
        date.month,
        date.day,
        time?.hour ?? 9,
        time?.minute ?? 0,
      );
      _reminder ??= 30;
    });
  }

  Future<void> _save() async {
    if (_title.text.trim().isEmpty) {
      showSuccessSnack(context, 'Give the task a title.');
      return;
    }
    setState(() => _saving = true);

    final repository = ref.read(calendarRepositoryProvider);
    final task = widget.existing?.copyWith(
          title: _title.text,
          category: _category,
          priority: _priority,
          dueAt: _dueAt?.toUtc(),
          clearDueAt: _dueAt == null,
          reminderMinutesBefore: _reminder,
        ) ??
        repository.createTask(
          title: _title.text,
          category: _category,
          priority: _priority,
          dueAt: _dueAt,
          reminderMinutesBefore: _reminder,
        );

    if (_reminder != null) {
      await ref.read(notificationServiceProvider).requestPermission();
    }

    final result = await repository.saveTask(task);
    if (!mounted) return;
    result.when(
      ok: (_) => Navigator.of(context).pop(),
      err: (failure) {
        setState(() => _saving = false);
        showFailureSnack(context, failure);
      },
    );
  }
}
