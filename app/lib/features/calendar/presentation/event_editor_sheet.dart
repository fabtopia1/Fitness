import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';
import 'package:lifedna/core/providers/providers.dart';
import 'package:lifedna/core/theme/app_theme.dart';
import 'package:lifedna/core/theme/ld_spacing.dart';
import 'package:lifedna/core/widgets/ld_widgets.dart';
import 'package:lifedna/features/calendar/domain/calendar_entities.dart';

class EventEditorSheet extends ConsumerStatefulWidget {
  const EventEditorSheet({super.key, this.existing});
  final CalendarEvent? existing;

  @override
  ConsumerState<EventEditorSheet> createState() => _EventEditorSheetState();
}

class _EventEditorSheetState extends ConsumerState<EventEditorSheet> {
  late final TextEditingController _title =
      TextEditingController(text: widget.existing?.title ?? '');
  late final TextEditingController _location =
      TextEditingController(text: widget.existing?.location ?? '');
  late DateTime _start =
      widget.existing?.startAt.toLocal() ?? _defaultStart();
  late DateTime _end = widget.existing?.endAt.toLocal() ??
      _defaultStart().add(const Duration(hours: 1));
  bool _saving = false;

  static DateTime _defaultStart() {
    final now = DateTime.now();
    return DateTime(now.year, now.month, now.day, now.hour + 1);
  }

  @override
  void dispose() {
    _title.dispose();
    _location.dispose();
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
                      isEdit ? 'Edit event' : 'New event',
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
                            .deleteEvent(widget.existing!.id);
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
                decoration: const InputDecoration(labelText: 'Title'),
              ),
              const SizedBox(height: LdSpacing.s3),
              TextField(
                controller: _location,
                decoration:
                    const InputDecoration(labelText: 'Location (optional)'),
              ),
              const SizedBox(height: LdSpacing.s4),
              ListTile(
                contentPadding: EdgeInsets.zero,
                leading: const Icon(Icons.play_arrow_rounded),
                title: const Text('Starts'),
                subtitle: Text(
                  DateFormat('EEE d MMM, HH:mm').format(_start),
                  style: type.bodyS.copyWith(color: c.textSecondary),
                ),
                onTap: () => _pick(isStart: true),
              ),
              ListTile(
                contentPadding: EdgeInsets.zero,
                leading: const Icon(Icons.stop_rounded),
                title: const Text('Ends'),
                subtitle: Text(
                  DateFormat('EEE d MMM, HH:mm').format(_end),
                  style: type.bodyS.copyWith(
                    color: _end.isAfter(_start) ? c.textSecondary : c.danger,
                  ),
                ),
                onTap: () => _pick(isStart: false),
              ),
              const SizedBox(height: LdSpacing.s5),
              LdPrimaryButton(
                label: isEdit ? 'Save changes' : 'Add event',
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

  Future<void> _pick({required bool isStart}) async {
    final initial = isStart ? _start : _end;
    final date = await showDatePicker(
      context: context,
      initialDate: initial,
      firstDate: DateTime.now().subtract(const Duration(days: 365)),
      lastDate: DateTime.now().add(const Duration(days: 365 * 3)),
    );
    if (date == null || !mounted) return;

    final time = await showTimePicker(
      context: context,
      initialTime: TimeOfDay.fromDateTime(initial),
    );
    if (!mounted) return;

    final picked = DateTime(
      date.year,
      date.month,
      date.day,
      time?.hour ?? initial.hour,
      time?.minute ?? initial.minute,
    );

    setState(() {
      if (isStart) {
        final duration = _end.difference(_start);
        _start = picked;
        // Keep the duration rather than letting the end drift behind the
        // start, which would then fail validation for no good reason.
        _end = picked.add(duration.isNegative ? const Duration(hours: 1) : duration);
      } else {
        _end = picked;
      }
    });
  }

  Future<void> _save() async {
    if (_title.text.trim().isEmpty) {
      showSuccessSnack(context, 'Give the event a title.');
      return;
    }
    if (!_end.isAfter(_start)) {
      showSuccessSnack(context, 'The end time must be after the start.');
      return;
    }

    setState(() => _saving = true);
    final repository = ref.read(calendarRepositoryProvider);
    final event = widget.existing?.copyWith(
          title: _title.text,
          location: _location.text,
          startAt: _start.toUtc(),
          endAt: _end.toUtc(),
        ) ??
        repository.createEvent(
          title: _title.text,
          startAt: _start,
          endAt: _end,
          location: _location.text.isEmpty ? null : _location.text,
        );

    final result = await repository.saveEvent(event);
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
