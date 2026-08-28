import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:lifedna/core/providers/providers.dart';
import 'package:lifedna/core/theme/app_theme.dart';
import 'package:lifedna/core/theme/ld_spacing.dart';
import 'package:lifedna/core/widgets/ld_widgets.dart';
import 'package:lifedna/features/workout/domain/workout_entities.dart';
import 'package:lifedna/features/workout/presentation/exercise_picker.dart';
import 'package:uuid/uuid.dart';

/// Creates or edits a workout program.
class WorkoutEditorScreen extends ConsumerStatefulWidget {
  const WorkoutEditorScreen({super.key, this.workoutId});
  final String? workoutId;

  @override
  ConsumerState<WorkoutEditorScreen> createState() =>
      _WorkoutEditorScreenState();
}

class _WorkoutEditorScreenState extends ConsumerState<WorkoutEditorScreen> {
  final _name = TextEditingController();
  List<WorkoutExercise> _exercises = [];
  bool _saving = false;
  bool _loaded = false;

  @override
  void dispose() {
    _name.dispose();
    super.dispose();
  }

  void _loadOnce() {
    if (_loaded) return;
    _loaded = true;
    final id = widget.workoutId;
    if (id == null) return;
    final existing = ref.read(workoutRepositoryProvider).workoutById(id);
    if (existing != null) {
      _name.text = existing.name;
      _exercises = [...existing.exercises];
    }
  }

  @override
  Widget build(BuildContext context) {
    _loadOnce();
    final c = context.ldColors;
    final type = context.ldType;
    final isEdit = widget.workoutId != null;

    return Scaffold(
      appBar: AppBar(
        title: Text(isEdit ? 'Edit program' : 'New program'),
        actions: [
          if (isEdit)
            IconButton(
              icon: const Icon(Icons.delete_outline_rounded),
              tooltip: 'Delete',
              onPressed: _delete,
            ),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(
          LdSpacing.s4,
          LdSpacing.s3,
          LdSpacing.s4,
          LdSpacing.scrollBottom,
        ),
        children: [
          TextField(
            controller: _name,
            textCapitalization: TextCapitalization.words,
            decoration: const InputDecoration(
              labelText: 'Program name',
              hintText: 'Push day',
            ),
          ),
          const LdSectionHeader(title: 'Exercises'),
          if (_exercises.isEmpty)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: LdSpacing.s4),
              child: Text(
                'No exercises yet. Add at least one to save the program.',
                style: type.bodyS.copyWith(color: c.textTertiary),
              ),
            )
          else
            ReorderableListView.builder(
              shrinkWrap: true,
              physics: const NeverScrollableScrollPhysics(),
              itemCount: _exercises.length,
              // onReorderItem already accounts for the removed item, so the
              // classic newIndex-1 adjustment must NOT be applied here.
              onReorderItem: (oldIndex, newIndex) => setState(() {
                final moved = _exercises.removeAt(oldIndex);
                _exercises.insert(newIndex, moved);
              }),
              itemBuilder: (context, index) {
                final exercise = _exercises[index];
                return Padding(
                  key: ValueKey('${exercise.exerciseId}_$index'),
                  padding: const EdgeInsets.only(bottom: LdSpacing.s2),
                  child: LdCard(
                    padding: const EdgeInsets.all(LdSpacing.s3),
                    child: Row(
                      children: [
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                exercise.exerciseName,
                                style: type.titleM
                                    .copyWith(color: c.textPrimary),
                              ),
                              const SizedBox(height: LdSpacing.s1),
                              Text(
                                '${exercise.targetSets} × '
                                '${exercise.repRange} · '
                                '${exercise.restSeconds}s rest',
                                style: type.bodyS
                                    .copyWith(color: c.textTertiary),
                              ),
                            ],
                          ),
                        ),
                        IconButton(
                          icon: const Icon(Icons.tune_rounded),
                          onPressed: () => _editExercise(index),
                        ),
                        IconButton(
                          icon: const Icon(Icons.close_rounded),
                          onPressed: () =>
                              setState(() => _exercises.removeAt(index)),
                        ),
                      ],
                    ),
                  ),
                );
              },
            ),
          const SizedBox(height: LdSpacing.s3),
          LdPrimaryButton(
            label: 'Add exercise',
            variant: LdButtonVariant.secondary,
            onPressed: _addExercise,
          ),
          const SizedBox(height: LdSpacing.s5),
          LdPrimaryButton(
            label: isEdit ? 'Save changes' : 'Create program',
            size: LdButtonSize.l,
            loading: _saving,
            onPressed: _save,
          ),
        ],
      ),
    );
  }

  Future<void> _addExercise() async {
    final exercise = await showModalBottomSheet<Exercise>(
      context: context,
      isScrollControlled: true,
      builder: (_) => const ExercisePicker(),
    );
    if (exercise == null || !mounted) return;
    setState(() {
      _exercises.add(
        WorkoutExercise(
          exerciseId: exercise.id,
          exerciseName: exercise.name,
          targetSets: 3,
          repMin: 8,
          repMax: 12,
          restSeconds: exercise.defaultRestSeconds,
        ),
      );
    });
  }

  Future<void> _editExercise(int index) async {
    final updated = await showModalBottomSheet<WorkoutExercise>(
      context: context,
      isScrollControlled: true,
      builder: (_) => _ExerciseParamsSheet(exercise: _exercises[index]),
    );
    if (updated != null && mounted) {
      setState(() => _exercises[index] = updated);
    }
  }

  Future<void> _save() async {
    if (_name.text.trim().isEmpty) {
      showSuccessSnack(context, 'Give the program a name.');
      return;
    }
    if (_exercises.isEmpty) {
      showSuccessSnack(context, 'Add at least one exercise.');
      return;
    }

    setState(() => _saving = true);
    final repository = ref.read(workoutRepositoryProvider);
    final existing = widget.workoutId == null
        ? null
        : repository.workoutById(widget.workoutId!);

    final workout = existing?.copyWith(
          name: _name.text.trim(),
          exercises: _exercises,
        ) ??
        Workout(
          id: const Uuid().v4(),
          name: _name.text.trim(),
          exercises: _exercises,
          updatedAt: DateTime.now().toUtc(),
        );

    final result = await repository.saveWorkout(workout);
    if (!mounted) return;
    result.when(
      ok: (_) {
        showSuccessSnack(context, 'Program saved');
        Navigator.of(context).pop();
      },
      err: (failure) {
        setState(() => _saving = false);
        showFailureSnack(context, failure);
      },
    );
  }

  Future<void> _delete() async {
    final id = widget.workoutId;
    if (id == null) return;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Delete program?'),
        content: const Text('Logged sessions are kept.'),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(context).pop(true),
            child: const Text('Delete'),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;
    await ref.read(workoutRepositoryProvider).deleteWorkout(id);
    if (mounted) Navigator.of(context).pop();
  }
}

class _ExerciseParamsSheet extends StatefulWidget {
  const _ExerciseParamsSheet({required this.exercise});
  final WorkoutExercise exercise;

  @override
  State<_ExerciseParamsSheet> createState() => _ExerciseParamsSheetState();
}

class _ExerciseParamsSheetState extends State<_ExerciseParamsSheet> {
  late int _sets = widget.exercise.targetSets;
  late int _repMin = widget.exercise.repMin;
  late int _repMax = widget.exercise.repMax;
  late int _rest = widget.exercise.restSeconds;

  @override
  Widget build(BuildContext context) {
    final c = context.ldColors;
    final type = context.ldType;

    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(
          LdSpacing.s4,
          0,
          LdSpacing.s4,
          LdSpacing.s5,
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              widget.exercise.exerciseName,
              style: type.headlineM.copyWith(color: c.textPrimary),
            ),
            const SizedBox(height: LdSpacing.s4),
            _Row(
              label: 'Sets',
              value: '$_sets',
              onMinus: () => setState(() => _sets = (_sets - 1).clamp(1, 12)),
              onPlus: () => setState(() => _sets = (_sets + 1).clamp(1, 12)),
            ),
            _Row(
              label: 'Min reps',
              value: '$_repMin',
              onMinus: () =>
                  setState(() => _repMin = (_repMin - 1).clamp(1, 50)),
              onPlus: () => setState(() {
                _repMin = (_repMin + 1).clamp(1, 50);
                if (_repMax < _repMin) _repMax = _repMin;
              }),
            ),
            _Row(
              label: 'Max reps',
              value: '$_repMax',
              onMinus: () => setState(
                () => _repMax = (_repMax - 1).clamp(_repMin, 50),
              ),
              onPlus: () =>
                  setState(() => _repMax = (_repMax + 1).clamp(_repMin, 50)),
            ),
            _Row(
              label: 'Rest (s)',
              value: '$_rest',
              onMinus: () =>
                  setState(() => _rest = (_rest - 15).clamp(15, 600)),
              onPlus: () =>
                  setState(() => _rest = (_rest + 15).clamp(15, 600)),
            ),
            const SizedBox(height: LdSpacing.s5),
            LdPrimaryButton(
              label: 'Done',
              size: LdButtonSize.l,
              onPressed: () => Navigator.of(context).pop(
                WorkoutExercise(
                  exerciseId: widget.exercise.exerciseId,
                  exerciseName: widget.exercise.exerciseName,
                  targetSets: _sets,
                  repMin: _repMin,
                  repMax: _repMax,
                  restSeconds: _rest,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _Row extends StatelessWidget {
  const _Row({
    required this.label,
    required this.value,
    required this.onMinus,
    required this.onPlus,
  });

  final String label;
  final String value;
  final VoidCallback onMinus;
  final VoidCallback onPlus;

  @override
  Widget build(BuildContext context) {
    final c = context.ldColors;
    final type = context.ldType;
    return Padding(
      padding: const EdgeInsets.only(bottom: LdSpacing.s3),
      child: Row(
        children: [
          Expanded(
            child: Text(
              label,
              style: type.bodyM.copyWith(color: c.textSecondary),
            ),
          ),
          IconButton.filledTonal(
            onPressed: onMinus,
            icon: const Icon(Icons.remove_rounded),
          ),
          SizedBox(
            width: 56,
            child: Text(
              value,
              textAlign: TextAlign.center,
              style: type.titleL.copyWith(color: c.textPrimary),
            ),
          ),
          IconButton.filledTonal(
            onPressed: onPlus,
            icon: const Icon(Icons.add_rounded),
          ),
        ],
      ),
    );
  }
}
