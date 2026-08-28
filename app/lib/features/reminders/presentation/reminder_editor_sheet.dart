import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:lifedna/core/theme/app_theme.dart';
import 'package:lifedna/core/theme/ld_spacing.dart';
import 'package:lifedna/core/widgets/ld_widgets.dart';
import 'package:lifedna/features/reminders/domain/reminder.dart';
import 'package:lifedna/features/reminders/presentation/reminder_providers.dart';

/// Creates or edits a daily reminder.
class ReminderEditorSheet extends ConsumerStatefulWidget {
  const ReminderEditorSheet({required this.reminder, super.key});

  final Reminder reminder;

  static Future<void> show(BuildContext context, Reminder reminder) =>
      showModalBottomSheet<void>(
        context: context,
        isScrollControlled: true,
        useSafeArea: true,
        builder: (_) => ReminderEditorSheet(reminder: reminder),
      );

  @override
  ConsumerState<ReminderEditorSheet> createState() =>
      _ReminderEditorSheetState();
}

class _ReminderEditorSheetState extends ConsumerState<ReminderEditorSheet> {
  final _formKey = GlobalKey<FormState>();
  late final TextEditingController _title;
  late final TextEditingController _note;
  late TimeOfDay _time;
  bool _saving = false;

  bool get _isNew => widget.reminder.title.isEmpty;

  @override
  void initState() {
    super.initState();
    _title = TextEditingController(text: widget.reminder.title);
    _note = TextEditingController(text: widget.reminder.note ?? '');
    _time = TimeOfDay(
      hour: widget.reminder.hour,
      minute: widget.reminder.minute,
    );
  }

  @override
  void dispose() {
    _title.dispose();
    _note.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final c = context.ldColors;
    final type = context.ldType;

    return Padding(
      padding: EdgeInsets.only(
        bottom: MediaQuery.of(context).viewInsets.bottom,
      ),
      child: Form(
        key: _formKey,
        child: ListView(
          shrinkWrap: true,
          padding: const EdgeInsets.fromLTRB(
            LdSpacing.s5,
            LdSpacing.s2,
            LdSpacing.s5,
            LdSpacing.s5,
          ),
          children: [
            Text(
              _isNew ? 'New reminder' : 'Edit reminder',
              style: type.headlineM.copyWith(color: c.textPrimary),
            ),
            const SizedBox(height: LdSpacing.s5),
            TextFormField(
              controller: _title,
              autofocus: _isNew,
              textCapitalization: TextCapitalization.sentences,
              decoration: const InputDecoration(
                labelText: 'Remind me to…',
                hintText: 'Weigh in',
              ),
              validator: (value) => (value == null || value.trim().isEmpty)
                  ? 'Give the reminder a name'
                  : null,
            ),
            const SizedBox(height: LdSpacing.s4),
            TextFormField(
              controller: _note,
              textCapitalization: TextCapitalization.sentences,
              decoration: const InputDecoration(
                labelText: 'Note (optional)',
                helperText: 'Shown in the notification body',
              ),
            ),
            const SizedBox(height: LdSpacing.s4),
            LdCard(
              eyebrow: 'Every day at',
              onTap: _pickTime,
              child: Row(
                children: [
                  Icon(Icons.schedule_rounded, size: 20, color: c.textTertiary),
                  const SizedBox(width: LdSpacing.s3),
                  Expanded(
                    child: Text(
                      _time.format(context),
                      style: type.titleL.copyWith(color: c.textPrimary),
                    ),
                  ),
                  Icon(Icons.chevron_right_rounded, color: c.textTertiary),
                ],
              ),
            ),
            const SizedBox(height: LdSpacing.s5),
            LdPrimaryButton(
              label: 'Save reminder',
              size: LdButtonSize.l,
              loading: _saving,
              onPressed: _save,
            ),
            if (!_isNew) ...[
              const SizedBox(height: LdSpacing.s3),
              LdPrimaryButton(
                label: 'Delete',
                variant: LdButtonVariant.ghost,
                onPressed: _delete,
              ),
            ],
          ],
        ),
      ),
    );
  }

  Future<void> _pickTime() async {
    final picked = await showTimePicker(context: context, initialTime: _time);
    if (picked != null) setState(() => _time = picked);
  }

  Future<void> _save() async {
    if (!(_formKey.currentState?.validate() ?? false)) return;
    setState(() => _saving = true);

    final navigator = Navigator.of(context);
    final note = _note.text.trim();
    final result = await ref
        .read(reminderRepositoryProvider)
        .save(
          widget.reminder.copyWith(
            title: _title.text.trim(),
            note: note.isEmpty ? null : note,
            hour: _time.hour,
            minute: _time.minute,
          ),
        );

    if (!mounted) return;
    setState(() => _saving = false);

    final failure = result.failureOrNull;
    if (failure != null) {
      showFailureSnack(context, failure);
      return;
    }
    navigator.pop();
  }

  Future<void> _delete() async {
    final navigator = Navigator.of(context);
    final result = await ref
        .read(reminderRepositoryProvider)
        .delete(widget.reminder.id);
    if (!mounted) return;

    final failure = result.failureOrNull;
    if (failure != null) {
      showFailureSnack(context, failure);
      return;
    }
    navigator.pop();
  }
}
