import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:lifedna/core/providers/providers.dart';
import 'package:lifedna/core/theme/app_theme.dart';
import 'package:lifedna/core/theme/ld_spacing.dart';
import 'package:lifedna/core/widgets/ld_widgets.dart';
import 'package:lifedna/features/workout/domain/workout_entities.dart';
import 'package:lifedna/features/workout/presentation/create_exercise_sheet.dart';
import 'package:lifedna/features/workout/presentation/workout_providers.dart';
import 'package:lifedna/shared/enums/enums.dart';

/// Picks an exercise from the library. Returns the chosen [Exercise].
class ExercisePicker extends ConsumerStatefulWidget {
  const ExercisePicker({super.key});

  @override
  ConsumerState<ExercisePicker> createState() => _ExercisePickerState();
}

class _ExercisePickerState extends ConsumerState<ExercisePicker> {
  final _search = TextEditingController();
  MuscleGroup? _muscle;

  @override
  void initState() {
    super.initState();
    _search.addListener(() => setState(() {}));
  }

  @override
  void dispose() {
    _search.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final c = context.ldColors;
    final type = context.ldType;
    ref.watch(exercisesProvider);
    final results = ref
        .watch(workoutRepositoryProvider)
        .searchExercises(_search.text, muscle: _muscle);

    return SafeArea(
      child: Padding(
        padding: EdgeInsets.only(
          bottom: MediaQuery.of(context).viewInsets.bottom,
        ),
        child: SizedBox(
          height: MediaQuery.of(context).size.height * 0.8,
          child: Column(
            children: [
              Padding(
                padding: const EdgeInsets.all(LdSpacing.s4),
                child: TextField(
                  controller: _search,
                  autofocus: true,
                  decoration: const InputDecoration(
                    hintText: 'Search exercises…',
                    prefixIcon: Icon(Icons.search_rounded),
                  ),
                ),
              ),
              SizedBox(
                height: 44,
                child: ListView(
                  scrollDirection: Axis.horizontal,
                  padding:
                      const EdgeInsets.symmetric(horizontal: LdSpacing.s4),
                  children: [
                    ChoiceChip(
                      label: const Text('All'),
                      selected: _muscle == null,
                      onSelected: (_) => setState(() => _muscle = null),
                    ),
                    for (final group in MuscleGroup.values) ...[
                      const SizedBox(width: LdSpacing.s2),
                      ChoiceChip(
                        label: Text(group.label),
                        selected: _muscle == group,
                        onSelected: (_) => setState(() => _muscle = group),
                      ),
                    ],
                  ],
                ),
              ),
              const SizedBox(height: LdSpacing.s2),
              Expanded(
                child: results.isEmpty
                    ? LdEmptyState(
                        icon: Icons.fitness_center_rounded,
                        headline: _search.text.isEmpty
                            ? 'No exercises yet'
                            : 'No match',
                        body: 'Create the exercises you actually do.',
                        actionLabel: 'Create exercise',
                        onAction: _create,
                      )
                    : ListView.separated(
                        itemCount: results.length,
                        separatorBuilder: (_, __) => Divider(
                          color: c.border,
                          height: 1,
                          indent: LdSpacing.s4,
                        ),
                        itemBuilder: (context, index) {
                          final exercise = results[index];
                          return ListTile(
                            title: Text(
                              exercise.name,
                              style: type.titleM
                                  .copyWith(color: c.textPrimary),
                            ),
                            subtitle: Text(
                              exercise.subtitle,
                              style: type.bodyS
                                  .copyWith(color: c.textTertiary),
                            ),
                            onTap: () =>
                                Navigator.of(context).pop(exercise),
                          );
                        },
                      ),
              ),
              Padding(
                padding: const EdgeInsets.all(LdSpacing.s4),
                child: LdPrimaryButton(
                  label: 'Create new exercise',
                  variant: LdButtonVariant.secondary,
                  onPressed: _create,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Future<void> _create() async {
    final created = await showModalBottomSheet<Exercise>(
      context: context,
      isScrollControlled: true,
      builder: (_) => const CreateExerciseSheet(),
    );
    if (created != null && mounted) Navigator.of(context).pop(created);
  }
}
