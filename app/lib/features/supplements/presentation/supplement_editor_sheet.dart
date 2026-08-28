import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:lifedna/core/providers/providers.dart';
import 'package:lifedna/core/theme/app_theme.dart';
import 'package:lifedna/core/theme/ld_spacing.dart';
import 'package:lifedna/core/widgets/ld_widgets.dart';
import 'package:lifedna/features/supplements/domain/supplement_entities.dart';

class SupplementEditorSheet extends ConsumerStatefulWidget {
  const SupplementEditorSheet({super.key, this.existing});
  final Supplement? existing;

  @override
  ConsumerState<SupplementEditorSheet> createState() =>
      _SupplementEditorSheetState();
}

class _SupplementEditorSheetState extends ConsumerState<SupplementEditorSheet> {
  final _formKey = GlobalKey<FormState>();
  late final TextEditingController _name = TextEditingController(
    text: widget.existing?.name ?? '',
  );
  late final TextEditingController _dose = TextEditingController(
    text: widget.existing == null ? '' : _trim(widget.existing!.dose),
  );
  late String _unit = widget.existing?.unit ?? 'g';
  late SupplementFrequency _frequency =
      widget.existing?.frequency ?? SupplementFrequency.daily;
  late final List<int> _weekdays = [
    ...widget.existing?.weekdays ?? const [1, 2, 3, 4, 5, 6, 7],
  ];
  late TimeOfDay _time = TimeOfDay(
    hour: widget.existing?.reminderHour ?? 9,
    minute: widget.existing?.reminderMinute ?? 0,
  );
  late bool _remind = widget.existing?.reminderEnabled ?? true;
  bool _saving = false;

  static const _units = ['g', 'mg', 'IU', 'ml', 'capsule', 'tablet'];

  @override
  void dispose() {
    _name.dispose();
    _dose.dispose();
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
        child: Form(
          key: _formKey,
          child: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Expanded(
                      child: Text(
                        isEdit ? 'Edit supplement' : 'New supplement',
                        style: type.headlineM.copyWith(color: c.textPrimary),
                      ),
                    ),
                    if (isEdit)
                      IconButton(
                        icon: const Icon(Icons.delete_outline_rounded),
                        onPressed: _delete,
                      ),
                  ],
                ),
                const SizedBox(height: LdSpacing.s4),
                TextFormField(
                  controller: _name,
                  textCapitalization: TextCapitalization.sentences,
                  decoration: const InputDecoration(labelText: 'Name'),
                  validator: (v) =>
                      (v == null || v.trim().isEmpty) ? 'Enter a name' : null,
                ),
                const SizedBox(height: LdSpacing.s3),
                Row(
                  children: [
                    Expanded(
                      flex: 2,
                      child: TextFormField(
                        controller: _dose,
                        keyboardType: const TextInputType.numberWithOptions(
                          decimal: true,
                        ),
                        inputFormatters: [
                          FilteringTextInputFormatter.allow(
                            RegExp(r'^\d*\.?\d{0,2}'),
                          ),
                        ],
                        decoration: const InputDecoration(labelText: 'Dose'),
                        validator: (v) {
                          final parsed = double.tryParse(v ?? '');
                          if (parsed == null || parsed <= 0) {
                            return 'Enter a dose';
                          }
                          return null;
                        },
                      ),
                    ),
                    const SizedBox(width: LdSpacing.s3),
                    Expanded(
                      child: DropdownButtonFormField<String>(
                        initialValue: _unit,
                        // Without this the button sizes to its widest item and
                        // overflows the row on a narrow phone.
                        isExpanded: true,
                        decoration: const InputDecoration(labelText: 'Unit'),
                        items: [
                          for (final unit in _units)
                            DropdownMenuItem(value: unit, child: Text(unit)),
                        ],
                        onChanged: (value) =>
                            setState(() => _unit = value ?? _unit),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: LdSpacing.s4),
                DropdownButtonFormField<SupplementFrequency>(
                  initialValue: _frequency,
                  isExpanded: true,
                  decoration: const InputDecoration(labelText: 'Frequency'),
                  items: [
                    for (final frequency in SupplementFrequency.values)
                      DropdownMenuItem(
                        value: frequency,
                        child: Text(frequency.label),
                      ),
                  ],
                  onChanged: (value) =>
                      setState(() => _frequency = value ?? _frequency),
                ),
                if (_frequency == SupplementFrequency.weekdays) ...[
                  const SizedBox(height: LdSpacing.s3),
                  Wrap(
                    spacing: LdSpacing.s2,
                    children: [
                      for (var day = 1; day <= 7; day++)
                        FilterChip(
                          label: Text(_dayLabel(day)),
                          selected: _weekdays.contains(day),
                          onSelected: (selected) => setState(() {
                            if (selected) {
                              _weekdays.add(day);
                            } else {
                              _weekdays.remove(day);
                            }
                          }),
                        ),
                    ],
                  ),
                ],
                const SizedBox(height: LdSpacing.s4),
                SwitchListTile(
                  contentPadding: EdgeInsets.zero,
                  value: _remind,
                  onChanged: (value) => setState(() => _remind = value),
                  title: const Text('Daily reminder'),
                  subtitle: Text(
                    _remind ? 'At ${_time.format(context)}' : 'No reminder',
                    style: type.bodyS.copyWith(color: c.textTertiary),
                  ),
                ),
                if (_remind)
                  LdPrimaryButton(
                    label: 'Change time (${_time.format(context)})',
                    variant: LdButtonVariant.secondary,
                    onPressed: () async {
                      final picked = await showTimePicker(
                        context: context,
                        initialTime: _time,
                      );
                      if (picked != null) setState(() => _time = picked);
                    },
                  ),
                const SizedBox(height: LdSpacing.s5),
                LdPrimaryButton(
                  label: isEdit ? 'Save changes' : 'Add supplement',
                  size: LdButtonSize.l,
                  loading: _saving,
                  onPressed: _save,
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Future<void> _save() async {
    if (!(_formKey.currentState?.validate() ?? false)) return;
    if (_frequency == SupplementFrequency.weekdays && _weekdays.isEmpty) {
      showSuccessSnack(context, 'Pick at least one day.');
      return;
    }

    setState(() => _saving = true);
    final repository = ref.read(supplementRepositoryProvider);
    final dose = double.parse(_dose.text);

    final supplement =
        widget.existing?.copyWith(
          name: _name.text,
          dose: dose,
          unit: _unit,
          frequency: _frequency,
          weekdays: _weekdays,
          reminderHour: _time.hour,
          reminderMinute: _time.minute,
          reminderEnabled: _remind,
        ) ??
        repository.create(
          name: _name.text,
          dose: dose,
          unit: _unit,
          frequency: _frequency,
          weekdays: _weekdays,
          reminderHour: _time.hour,
          reminderMinute: _time.minute,
          reminderEnabled: _remind,
        );

    // Asked for at the moment a reminder would actually help, which is where
    // people say yes.
    if (_remind) {
      await ref.read(notificationServiceProvider).requestPermission();
    }

    final result = await repository.save(supplement);
    if (!mounted) return;
    result.when(
      ok: (_) => Navigator.of(context).pop(),
      err: (failure) {
        setState(() => _saving = false);
        showFailureSnack(context, failure);
      },
    );
  }

  Future<void> _delete() async {
    final existing = widget.existing;
    if (existing == null) return;
    await ref.read(supplementRepositoryProvider).delete(existing.id);
    if (mounted) Navigator.of(context).pop();
  }

  static String _trim(double v) =>
      v == v.roundToDouble() ? v.round().toString() : v.toString();

  static String _dayLabel(int day) =>
      const ['M', 'T', 'W', 'T', 'F', 'S', 'S'][day - 1];
}
