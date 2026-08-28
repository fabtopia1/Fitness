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

class ExerciseLibraryScreen extends ConsumerStatefulWidget {
  const ExerciseLibraryScreen({super.key});

  @override
  ConsumerState<ExerciseLibraryScreen> createState() =>
      _ExerciseLibraryScreenState();
}

class _ExerciseLibraryScreenState
    extends ConsumerState<ExerciseLibraryScreen> {
  MuscleGroup? _muscle;

  @override
  Widget build(BuildContext context) {
    final c = context.ldColors;
    final type = context.ldType;
    final async = ref.watch(exercisesProvider);

    return Scaffold(
      appBar: AppBar(title: const Text('Exercises')),
      body: LdAsyncView(
        value: async,
        onRetry: () => ref.invalidate(exercisesProvider),
        errorContext: 'Exercise library',
        isEmpty: (list) => list.isEmpty,
        empty: LdEmptyState(
          icon: Icons.fitness_center_rounded,
          headline: 'No exercises yet',
          body: 'Add the movements you actually train.',
          actionLabel: 'Create exercise',
          onAction: _create,
        ),
        data: (all) {
          final filtered = _muscle == null
              ? all
              : all.where((e) => e.muscleGroup == _muscle).toList();
          filtered.sort((a, b) => a.name.compareTo(b.name));

          return Column(
            children: [
              SizedBox(
                height: 52,
                child: ListView(
                  scrollDirection: Axis.horizontal,
                  padding:
                      const EdgeInsets.symmetric(horizontal: LdSpacing.s4),
                  children: [
                    Padding(
                      padding: const EdgeInsets.symmetric(vertical: 6),
                      child: ChoiceChip(
                        label: const Text('All'),
                        selected: _muscle == null,
                        onSelected: (_) => setState(() => _muscle = null),
                      ),
                    ),
                    for (final group in MuscleGroup.values) ...[
                      const SizedBox(width: LdSpacing.s2),
                      Padding(
                        padding: const EdgeInsets.symmetric(vertical: 6),
                        child: ChoiceChip(
                          label: Text(group.label),
                          selected: _muscle == group,
                          onSelected: (_) => setState(() => _muscle = group),
                        ),
                      ),
                    ],
                  ],
                ),
              ),
              Expanded(
                child: ListView.separated(
                  padding: const EdgeInsets.only(
                    bottom: LdSpacing.scrollBottom,
                  ),
                  itemCount: filtered.length,
                  separatorBuilder: (_, __) => Divider(
                    color: c.border,
                    height: 1,
                    indent: LdSpacing.s4,
                  ),
                  itemBuilder: (context, index) {
                    final exercise = filtered[index];
                    final best = ref
                        .read(workoutRepositoryProvider)
                        .bestsFor(exercise.id);
                    return ListTile(
                      title: Text(
                        exercise.name,
                        style: type.titleM.copyWith(color: c.textPrimary),
                      ),
                      subtitle: Text(
                        best.bestE1rm == null
                            ? exercise.subtitle
                            : '${exercise.subtitle} · best est. 1RM '
                                '${best.bestE1rm!.toStringAsFixed(1)} kg',
                        style: type.bodyS.copyWith(color: c.textTertiary),
                      ),
                      trailing: exercise.isCustom
                          ? Icon(Icons.person_rounded,
                              size: 16, color: c.textTertiary)
                          : null,
                    );
                  },
                ),
              ),
            ],
          );
        },
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: _create,
        icon: const Icon(Icons.add_rounded),
        label: const Text('New exercise'),
      ),
    );
  }

  Future<void> _create() async {
    await showModalBottomSheet<Exercise>(
      context: context,
      isScrollControlled: true,
      builder: (_) => const CreateExerciseSheet(),
    );
  }
}
