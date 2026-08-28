import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:lifedna/core/providers/providers.dart';
import 'package:lifedna/core/theme/app_theme.dart';
import 'package:lifedna/core/theme/ld_spacing.dart';
import 'package:lifedna/core/widgets/ld_widgets.dart';
import 'package:lifedna/shared/enums/enums.dart';

class CreateExerciseSheet extends ConsumerStatefulWidget {
  const CreateExerciseSheet({super.key});

  @override
  ConsumerState<CreateExerciseSheet> createState() =>
      _CreateExerciseSheetState();
}

class _CreateExerciseSheetState extends ConsumerState<CreateExerciseSheet> {
  final _formKey = GlobalKey<FormState>();
  final _name = TextEditingController();
  MuscleGroup _muscle = MuscleGroup.chest;
  Equipment _equipment = Equipment.barbell;
  int _rest = 120;
  bool _saving = false;

  @override
  void dispose() {
    _name.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final c = context.ldColors;
    final type = context.ldType;

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
                Text(
                  'New exercise',
                  style: type.headlineM.copyWith(color: c.textPrimary),
                ),
                const SizedBox(height: LdSpacing.s4),
                TextFormField(
                  controller: _name,
                  autofocus: true,
                  textCapitalization: TextCapitalization.words,
                  decoration: const InputDecoration(labelText: 'Name'),
                  validator: (v) => (v == null || v.trim().isEmpty)
                      ? 'Enter a name'
                      : null,
                ),
                const SizedBox(height: LdSpacing.s4),
                DropdownButtonFormField<MuscleGroup>(
                  isExpanded: true,
                  initialValue: _muscle,
                  decoration:
                      const InputDecoration(labelText: 'Muscle group'),
                  items: [
                    for (final group in MuscleGroup.values)
                      DropdownMenuItem(
                        value: group,
                        child: Text(group.label),
                      ),
                  ],
                  onChanged: (value) =>
                      setState(() => _muscle = value ?? _muscle),
                ),
                const SizedBox(height: LdSpacing.s4),
                DropdownButtonFormField<Equipment>(
                  isExpanded: true,
                  initialValue: _equipment,
                  decoration: const InputDecoration(labelText: 'Equipment'),
                  items: [
                    for (final item in Equipment.values)
                      DropdownMenuItem(value: item, child: Text(item.label)),
                  ],
                  onChanged: (value) =>
                      setState(() => _equipment = value ?? _equipment),
                ),
                const SizedBox(height: LdSpacing.s4),
                Text(
                  'Rest between sets: ${_rest ~/ 60}:'
                  '${(_rest % 60).toString().padLeft(2, '0')}',
                  style: type.bodyM.copyWith(color: c.textSecondary),
                ),
                Slider(
                  value: _rest.toDouble(),
                  min: 30,
                  max: 300,
                  divisions: 18,
                  onChanged: (value) => setState(() => _rest = value.round()),
                ),
                const SizedBox(height: LdSpacing.s4),
                LdPrimaryButton(
                  label: 'Save exercise',
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
    setState(() => _saving = true);

    final repository = ref.read(workoutRepositoryProvider);
    final exercise = repository.createExercise(
      name: _name.text,
      muscleGroup: _muscle,
      equipment: _equipment,
      restSeconds: _rest,
    );
    final result = await repository.saveExercise(exercise);
    if (!mounted) return;

    result.when(
      ok: (saved) => Navigator.of(context).pop(saved),
      err: (failure) {
        setState(() => _saving = false);
        showFailureSnack(context, failure);
      },
    );
  }
}
