import 'package:lifedna/features/nutrition/domain/entities/food.dart';
import 'package:lifedna/features/workout/domain/entities/workout.dart';
import 'package:lifedna/shared/enums/enums.dart';
import 'package:lifedna/shared/value_objects/macros.dart';

/// The seeded catalogues that ship with the app.
///
/// In production these are Firestore bundles loaded into Drift on first run
/// (docs/03 §4.5), giving zero-latency, zero-cost local search. Here they are
/// a compiled-in subset so the app is fully operable without a backend.
abstract final class ReferenceCatalog {
  // ------------------------------------------------------------------ foods --

  static const List<Food> foods = [
    Food(
      id: 'fd_chicken_breast_raw',
      name: 'Chicken breast, skinless, raw',
      per100g: Macros(kcal: 165, proteinG: 31, carbsG: 0, fatG: 3.6),
      servings: [
        FoodServing(label: '100 g', grams: 100),
        FoodServing(label: '1 breast (174 g)', grams: 174),
      ],
      popularity: 98230,
    ),
    Food(
      id: 'fd_egg_whole',
      name: 'Egg, whole, boiled',
      per100g: Macros(kcal: 155, proteinG: 12.6, carbsG: 1.1, fatG: 10.6),
      servings: [
        FoodServing(label: '1 egg (50 g)', grams: 50),
        FoodServing(label: '100 g', grams: 100),
      ],
      popularity: 91100,
    ),
    Food(
      id: 'fd_foul_medames',
      name: 'Foul medames',
      per100g: Macros(kcal: 98, proteinG: 6.5, carbsG: 14.2, fatG: 1.6),
      servings: [FoodServing(label: '1 bowl (200 g)', grams: 200)],
      popularity: 44300,
    ),
    Food(
      id: 'fd_baladi_bread',
      name: 'Baladi bread',
      per100g: Macros(kcal: 246, proteinG: 8.2, carbsG: 49.5, fatG: 1.4),
      servings: [FoodServing(label: '1 loaf (37 g)', grams: 37)],
      popularity: 39800,
    ),
    Food(
      id: 'fd_white_rice_cooked',
      name: 'White rice, cooked',
      per100g: Macros(kcal: 130, proteinG: 2.7, carbsG: 28.2, fatG: 0.3),
      servings: [
        FoodServing(label: '100 g', grams: 100),
        FoodServing(label: '1 cup (158 g)', grams: 158),
      ],
      popularity: 88400,
    ),
    Food(
      id: 'fd_greek_yogurt_0',
      name: 'Greek yogurt 0 %',
      brand: 'Juhayna',
      per100g: Macros(kcal: 59, proteinG: 10.2, carbsG: 3.6, fatG: 0.4),
      servings: [FoodServing(label: '1 pot (170 g)', grams: 170)],
      barcodes: ['6221031490014'],
      popularity: 72500,
    ),
    Food(
      id: 'fd_beef_mince_10',
      name: 'Beef mince, 10 % fat',
      per100g: Macros(kcal: 192, proteinG: 20.6, carbsG: 0, fatG: 12),
      servings: [FoodServing(label: '100 g', grams: 100)],
      popularity: 51200,
    ),
    Food(
      id: 'fd_salmon_fillet',
      name: 'Salmon fillet, raw',
      per100g: Macros(kcal: 208, proteinG: 20.4, carbsG: 0, fatG: 13.4),
      servings: [FoodServing(label: '1 fillet (150 g)', grams: 150)],
      popularity: 46900,
    ),
    Food(
      id: 'fd_cottage_cheese',
      name: 'Cottage cheese, low fat',
      per100g: Macros(kcal: 72, proteinG: 12.4, carbsG: 3.4, fatG: 1),
      servings: [FoodServing(label: '1 cup (226 g)', grams: 226)],
      popularity: 38200,
    ),
    Food(
      id: 'fd_whey_isolate',
      name: 'Whey protein isolate',
      per100g: Macros(kcal: 373, proteinG: 86, carbsG: 3, fatG: 1.5),
      servings: [FoodServing(label: '1 scoop (30 g)', grams: 30)],
      popularity: 67300,
    ),
    Food(
      id: 'fd_banana',
      name: 'Banana',
      per100g: Macros(kcal: 89, proteinG: 1.1, carbsG: 22.8, fatG: 0.3),
      servings: [FoodServing(label: '1 medium (118 g)', grams: 118)],
      popularity: 84100,
    ),
    Food(
      id: 'fd_olive_oil',
      name: 'Olive oil',
      per100g: Macros(kcal: 884, proteinG: 0, carbsG: 0, fatG: 100),
      servings: [FoodServing(label: '1 tbsp (13.5 g)', grams: 13.5)],
      popularity: 55600,
    ),
    Food(
      id: 'fd_mixed_salad',
      name: 'Mixed salad vegetables',
      per100g: Macros(kcal: 38, proteinG: 1.5, carbsG: 6.4, fatG: 0.6),
      servings: [FoodServing(label: '1 bowl (150 g)', grams: 150)],
      popularity: 29400,
    ),
    Food(
      id: 'fd_almonds',
      name: 'Almonds',
      per100g: Macros(kcal: 579, proteinG: 21.2, carbsG: 21.6, fatG: 49.9),
      servings: [FoodServing(label: '1 handful (28 g)', grams: 28)],
      popularity: 41000,
    ),
    Food(
      id: 'fd_sweet_potato',
      name: 'Sweet potato, baked',
      per100g: Macros(kcal: 90, proteinG: 2, carbsG: 20.7, fatG: 0.2),
      servings: [FoodServing(label: '1 medium (150 g)', grams: 150)],
      popularity: 35700,
    ),
  ];

  static Food? foodById(String id) {
    for (final f in foods) {
      if (f.id == id) return f;
    }
    return null;
  }

  /// Prefix-and-token search over the local index. In production this is a
  /// Drift FTS query; the ranking rule is the same — exact prefix first, then
  /// token match, then popularity.
  static List<Food> searchFoods(String query) {
    final q = query.trim().toLowerCase();
    if (q.isEmpty) {
      return [...foods]..sort((a, b) => b.popularity.compareTo(a.popularity));
    }

    final scored = <({Food food, int score})>[];
    for (final f in foods) {
      final name = f.name.toLowerCase();
      final brand = f.brand?.toLowerCase() ?? '';
      int score;
      if (name.startsWith(q)) {
        score = 1000;
      } else if (name.contains(q) || brand.contains(q)) {
        score = 500;
      } else if (name.split(RegExp(r'[\s,]+')).any((t) => t.startsWith(q))) {
        score = 250;
      } else {
        continue;
      }
      scored.add((food: f, score: score + (f.popularity ~/ 1000)));
    }
    scored.sort((a, b) => b.score.compareTo(a.score));
    return [for (final s in scored) s.food];
  }

  static Food? foodByBarcode(String barcode) {
    for (final f in foods) {
      if (f.barcodes.contains(barcode)) return f;
    }
    return null;
  }

  // -------------------------------------------------------------- exercises --

  static const List<Exercise> exercises = [
    Exercise(
      id: 'incline-dumbbell-press',
      name: 'Incline Dumbbell Press',
      muscleGroup: MuscleGroup.chest,
      secondaryMuscles: [MuscleGroup.shoulders, MuscleGroup.triceps],
      equipment: Equipment.dumbbell,
      defaultRestSeconds: 120,
      defaultIncrementKg: 2,
      instructions: [
        'Set the bench to about 30 degrees.',
        'Lower under control until the dumbbells are level with the chest.',
        'Press without letting the dumbbells drift toward the face.',
      ],
    ),
    Exercise(
      id: 'barbell-bench-press',
      name: 'Barbell Bench Press',
      muscleGroup: MuscleGroup.chest,
      secondaryMuscles: [MuscleGroup.shoulders, MuscleGroup.triceps],
      equipment: Equipment.barbell,
      defaultRestSeconds: 180,
    ),
    Exercise(
      id: 'cable-fly',
      name: 'Cable Fly',
      muscleGroup: MuscleGroup.chest,
      equipment: Equipment.cable,
      isCompound: false,
      defaultRestSeconds: 90,
      defaultIncrementKg: 2.5,
    ),
    Exercise(
      id: 'overhead-press',
      name: 'Overhead Press',
      muscleGroup: MuscleGroup.shoulders,
      secondaryMuscles: [MuscleGroup.triceps],
      equipment: Equipment.barbell,
      defaultRestSeconds: 150,
    ),
    Exercise(
      id: 'lateral-raise',
      name: 'Lateral Raise',
      muscleGroup: MuscleGroup.shoulders,
      equipment: Equipment.dumbbell,
      isCompound: false,
      defaultRestSeconds: 75,
      defaultIncrementKg: 1,
    ),
    Exercise(
      id: 'triceps-pushdown',
      name: 'Triceps Pushdown',
      muscleGroup: MuscleGroup.triceps,
      equipment: Equipment.cable,
      isCompound: false,
      defaultRestSeconds: 75,
      defaultIncrementKg: 2.5,
    ),
    Exercise(
      id: 'overhead-triceps-extension',
      name: 'Overhead Triceps Extension',
      muscleGroup: MuscleGroup.triceps,
      equipment: Equipment.dumbbell,
      isCompound: false,
      defaultRestSeconds: 75,
    ),
    Exercise(
      id: 'lat-pulldown',
      name: 'Lat Pulldown',
      muscleGroup: MuscleGroup.back,
      secondaryMuscles: [MuscleGroup.biceps],
      equipment: Equipment.cable,
      defaultRestSeconds: 120,
    ),
    Exercise(
      id: 'barbell-row',
      name: 'Barbell Row',
      muscleGroup: MuscleGroup.back,
      secondaryMuscles: [MuscleGroup.biceps],
      equipment: Equipment.barbell,
      defaultRestSeconds: 150,
    ),
    Exercise(
      id: 'seated-cable-row',
      name: 'Seated Cable Row',
      muscleGroup: MuscleGroup.back,
      secondaryMuscles: [MuscleGroup.biceps],
      equipment: Equipment.cable,
      defaultRestSeconds: 120,
    ),
    Exercise(
      id: 'face-pull',
      name: 'Face Pull',
      muscleGroup: MuscleGroup.shoulders,
      equipment: Equipment.cable,
      isCompound: false,
      defaultRestSeconds: 75,
    ),
    Exercise(
      id: 'barbell-curl',
      name: 'Barbell Curl',
      muscleGroup: MuscleGroup.biceps,
      equipment: Equipment.barbell,
      isCompound: false,
      defaultRestSeconds: 90,
      defaultIncrementKg: 2.5,
    ),
    Exercise(
      id: 'hammer-curl',
      name: 'Hammer Curl',
      muscleGroup: MuscleGroup.biceps,
      equipment: Equipment.dumbbell,
      isCompound: false,
      defaultRestSeconds: 75,
    ),
    Exercise(
      id: 'back-squat',
      name: 'Barbell Back Squat',
      muscleGroup: MuscleGroup.quads,
      secondaryMuscles: [MuscleGroup.glutes, MuscleGroup.hamstrings],
      equipment: Equipment.barbell,
      defaultRestSeconds: 210,
      defaultIncrementKg: 5,
    ),
    Exercise(
      id: 'romanian-deadlift',
      name: 'Romanian Deadlift',
      muscleGroup: MuscleGroup.hamstrings,
      secondaryMuscles: [MuscleGroup.glutes, MuscleGroup.back],
      equipment: Equipment.barbell,
      defaultRestSeconds: 180,
      defaultIncrementKg: 5,
    ),
    Exercise(
      id: 'leg-press',
      name: 'Leg Press',
      muscleGroup: MuscleGroup.quads,
      secondaryMuscles: [MuscleGroup.glutes],
      equipment: Equipment.machine,
      defaultRestSeconds: 150,
      defaultIncrementKg: 10,
    ),
    Exercise(
      id: 'leg-curl',
      name: 'Seated Leg Curl',
      muscleGroup: MuscleGroup.hamstrings,
      equipment: Equipment.machine,
      isCompound: false,
      defaultRestSeconds: 90,
    ),
    Exercise(
      id: 'calf-raise',
      name: 'Standing Calf Raise',
      muscleGroup: MuscleGroup.calves,
      equipment: Equipment.machine,
      isCompound: false,
      defaultRestSeconds: 60,
    ),
    Exercise(
      id: 'plank',
      name: 'Plank',
      muscleGroup: MuscleGroup.core,
      equipment: Equipment.bodyweight,
      isCompound: false,
      defaultRestSeconds: 60,
    ),
    Exercise(
      id: 'hanging-leg-raise',
      name: 'Hanging Leg Raise',
      muscleGroup: MuscleGroup.core,
      equipment: Equipment.bodyweight,
      isCompound: false,
      defaultRestSeconds: 75,
    ),
  ];

  static Map<String, Exercise> get exerciseIndex => {
        for (final e in exercises) e.id: e,
      };

  static Exercise? exerciseById(String id) => exerciseIndex[id];

  static List<Exercise> searchExercises(String query, {MuscleGroup? muscle}) {
    final q = query.trim().toLowerCase();
    return [
      for (final e in exercises)
        if ((muscle == null || e.muscleGroup == muscle) &&
            (q.isEmpty || e.name.toLowerCase().contains(q)))
          e,
    ];
  }

  // -------------------------------------------------------------- templates --

  /// The 8-week recomposition program from the reference plan: every muscle
  /// trained twice weekly, 75-minute session ceiling.
  static List<WorkoutTemplate> get templates => [
        const WorkoutTemplate(
          id: 'tpl_push',
          name: 'PUSH — Chest · Shoulders · Triceps',
          dayLabel: 'SAT',
          estimatedMinutes: 75,
          exercises: [
            TemplateExercise(
              exerciseId: 'incline-dumbbell-press',
              exerciseName: 'Incline Dumbbell Press',
              targetSets: 4,
              repMin: 8,
              repMax: 12,
              restSeconds: 120,
              note: 'Bench at 30°. Full range of motion over load.',
            ),
            TemplateExercise(
              exerciseId: 'barbell-bench-press',
              exerciseName: 'Barbell Bench Press',
              targetSets: 4,
              repMin: 6,
              repMax: 10,
              restSeconds: 180,
            ),
            TemplateExercise(
              exerciseId: 'overhead-press',
              exerciseName: 'Overhead Press',
              targetSets: 4,
              repMin: 8,
              repMax: 10,
              restSeconds: 150,
            ),
            TemplateExercise(
              exerciseId: 'cable-fly',
              exerciseName: 'Cable Fly',
              targetSets: 3,
              repMin: 12,
              repMax: 15,
              restSeconds: 90,
            ),
            TemplateExercise(
              exerciseId: 'lateral-raise',
              exerciseName: 'Lateral Raise',
              targetSets: 4,
              repMin: 12,
              repMax: 20,
              restSeconds: 75,
              groupId: 'ss_arms',
            ),
            TemplateExercise(
              exerciseId: 'triceps-pushdown',
              exerciseName: 'Triceps Pushdown',
              targetSets: 3,
              repMin: 10,
              repMax: 15,
              restSeconds: 75,
              groupId: 'ss_arms',
            ),
          ],
        ),
        const WorkoutTemplate(
          id: 'tpl_pull',
          name: 'PULL — Back · Rear delts · Arms',
          dayLabel: 'SUN',
          estimatedMinutes: 75,
          exercises: [
            TemplateExercise(
              exerciseId: 'barbell-row',
              exerciseName: 'Barbell Row',
              targetSets: 4,
              repMin: 6,
              repMax: 10,
              restSeconds: 150,
            ),
            TemplateExercise(
              exerciseId: 'lat-pulldown',
              exerciseName: 'Lat Pulldown',
              targetSets: 4,
              repMin: 8,
              repMax: 12,
              restSeconds: 120,
            ),
            TemplateExercise(
              exerciseId: 'seated-cable-row',
              exerciseName: 'Seated Cable Row',
              targetSets: 3,
              repMin: 10,
              repMax: 12,
              restSeconds: 120,
            ),
            TemplateExercise(
              exerciseId: 'face-pull',
              exerciseName: 'Face Pull',
              targetSets: 3,
              repMin: 15,
              repMax: 20,
              restSeconds: 75,
            ),
            TemplateExercise(
              exerciseId: 'barbell-curl',
              exerciseName: 'Barbell Curl',
              targetSets: 3,
              repMin: 8,
              repMax: 12,
              restSeconds: 90,
            ),
            TemplateExercise(
              exerciseId: 'hammer-curl',
              exerciseName: 'Hammer Curl',
              targetSets: 3,
              repMin: 10,
              repMax: 15,
              restSeconds: 75,
            ),
          ],
        ),
        const WorkoutTemplate(
          id: 'tpl_legs',
          name: 'LEGS — Quads · Hams · Calves · Core',
          dayLabel: 'MON',
          estimatedMinutes: 75,
          exercises: [
            TemplateExercise(
              exerciseId: 'back-squat',
              exerciseName: 'Barbell Back Squat',
              targetSets: 4,
              repMin: 5,
              repMax: 8,
              restSeconds: 210,
            ),
            TemplateExercise(
              exerciseId: 'romanian-deadlift',
              exerciseName: 'Romanian Deadlift',
              targetSets: 4,
              repMin: 8,
              repMax: 10,
              restSeconds: 180,
            ),
            TemplateExercise(
              exerciseId: 'leg-press',
              exerciseName: 'Leg Press',
              targetSets: 3,
              repMin: 10,
              repMax: 15,
              restSeconds: 150,
            ),
            TemplateExercise(
              exerciseId: 'leg-curl',
              exerciseName: 'Seated Leg Curl',
              targetSets: 3,
              repMin: 12,
              repMax: 15,
              restSeconds: 90,
            ),
            TemplateExercise(
              exerciseId: 'calf-raise',
              exerciseName: 'Standing Calf Raise',
              targetSets: 4,
              repMin: 12,
              repMax: 20,
              restSeconds: 60,
            ),
            TemplateExercise(
              exerciseId: 'hanging-leg-raise',
              exerciseName: 'Hanging Leg Raise',
              targetSets: 3,
              repMin: 10,
              repMax: 15,
              restSeconds: 75,
            ),
          ],
        ),
      ];

  static WorkoutTemplate? templateById(String id) {
    for (final t in templates) {
      if (t.id == id) return t;
    }
    return null;
  }

  /// The reference weekly split. Index 1 = Monday … 7 = Sunday.
  static const Map<int, ({String label, String? templateId, bool optional})>
      weeklySplit = {
    DateTime.saturday: (label: 'PUSH', templateId: 'tpl_push', optional: false),
    DateTime.sunday: (label: 'PULL', templateId: 'tpl_pull', optional: false),
    DateTime.monday: (label: 'LEGS', templateId: 'tpl_legs', optional: false),
    DateTime.tuesday: (label: 'FITNESS', templateId: null, optional: true),
    DateTime.wednesday: (label: 'UPPER', templateId: 'tpl_push', optional: false),
    DateTime.thursday: (label: 'LOWER', templateId: 'tpl_legs', optional: false),
    DateTime.friday: (label: 'SWIM', templateId: null, optional: true),
  };
}
