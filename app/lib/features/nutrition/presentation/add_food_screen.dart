import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:lifedna/core/providers/providers.dart';
import 'package:lifedna/core/theme/app_theme.dart';
import 'package:lifedna/core/theme/ld_spacing.dart';
import 'package:lifedna/core/widgets/ld_widgets.dart';
import 'package:lifedna/features/nutrition/domain/nutrition_entities.dart';
import 'package:lifedna/features/nutrition/presentation/create_food_sheet.dart';
import 'package:lifedna/features/nutrition/presentation/nutrition_providers.dart';
import 'package:lifedna/shared/enums/enums.dart';

/// Log a food or a saved meal into a slot.
class AddFoodScreen extends ConsumerStatefulWidget {
  const AddFoodScreen({super.key, this.slotWire});
  final String? slotWire;

  @override
  ConsumerState<AddFoodScreen> createState() => _AddFoodScreenState();
}

class _AddFoodScreenState extends ConsumerState<AddFoodScreen> {
  final _search = TextEditingController();
  late MealSlot _slot = MealSlot.fromWire(
    widget.slotWire ?? MealSlot.snack.wire,
  );
  int _tab = 0;

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
    // Watched so the list rebuilds the moment a food is created or logged.
    ref.watch(foodsProvider);
    ref.watch(mealsProvider);

    final repository = ref.watch(nutritionRepositoryProvider);
    final foods = repository.searchFoods(_search.text);
    final meals = repository.meals.readAll();

    return Scaffold(
      appBar: AppBar(
        title: Text('Add to ${_slot.label.toLowerCase()}'),
        actions: [
          PopupMenuButton<MealSlot>(
            icon: const Icon(Icons.schedule_rounded),
            tooltip: 'Change slot',
            onSelected: (slot) => setState(() => _slot = slot),
            itemBuilder: (context) => [
              for (final slot in MealSlot.values)
                PopupMenuItem(value: slot, child: Text(slot.label)),
            ],
          ),
        ],
      ),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(
              LdSpacing.s4,
              0,
              LdSpacing.s4,
              LdSpacing.s3,
            ),
            child: TextField(
              controller: _search,
              autofocus: true,
              textInputAction: TextInputAction.search,
              decoration: InputDecoration(
                hintText: 'Search your foods…',
                prefixIcon: const Icon(Icons.search_rounded),
                suffixIcon: _search.text.isEmpty
                    ? null
                    : IconButton(
                        icon: const Icon(Icons.clear_rounded),
                        onPressed: _search.clear,
                      ),
              ),
            ),
          ),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: LdSpacing.s4),
            child: SegmentedButton<int>(
              segments: const [
                ButtonSegment(value: 0, label: Text('Foods')),
                ButtonSegment(value: 1, label: Text('Meals')),
              ],
              selected: {_tab},
              onSelectionChanged: (value) => setState(() => _tab = value.first),
            ),
          ),
          const SizedBox(height: LdSpacing.s3),
          Expanded(
            child: _tab == 0
                ? _FoodList(
                    foods: foods,
                    query: _search.text,
                    onPick: _openPortionSheet,
                    onCreate: _createFood,
                  )
                : _MealList(meals: meals, onPick: _logMeal),
          ),
        ],
      ),
      floatingActionButton: _tab == 0
          ? FloatingActionButton.extended(
              onPressed: _createFood,
              icon: const Icon(Icons.add_rounded),
              label: const Text('New food'),
            )
          : null,
      bottomNavigationBar: foods.isEmpty && _search.text.isEmpty && _tab == 0
          ? Padding(
              padding: const EdgeInsets.all(LdSpacing.s4),
              child: Text(
                'Your food list is empty. Create the foods you eat once, then '
                'logging takes a couple of taps.',
                textAlign: TextAlign.center,
                style: type.bodyS.copyWith(color: c.textTertiary),
              ),
            )
          : null,
    );
  }

  Future<void> _createFood() async {
    final created = await showModalBottomSheet<FoodItem>(
      context: context,
      isScrollControlled: true,
      builder: (_) => const CreateFoodSheet(),
    );
    if (created != null && mounted) await _openPortionSheet(created);
  }

  Future<void> _openPortionSheet(FoodItem food) async {
    final logged = await showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      builder: (_) => PortionSheet(food: food, slot: _slot),
    );
    if (logged == true && mounted) Navigator.of(context).pop();
  }

  Future<void> _logMeal(Meal meal) async {
    final result = await ref
        .read(nutritionRepositoryProvider)
        .logMeal(meal: meal, slot: _slot);
    if (!mounted) return;
    result.when(
      ok: (count) {
        showSuccessSnack(context, '${meal.name} logged ($count items)');
        Navigator.of(context).pop();
      },
      err: (failure) => showFailureSnack(context, failure),
    );
  }
}

class _FoodList extends StatelessWidget {
  const _FoodList({
    required this.foods,
    required this.query,
    required this.onPick,
    required this.onCreate,
  });

  final List<FoodItem> foods;
  final String query;
  final void Function(FoodItem) onPick;
  final VoidCallback onCreate;

  @override
  Widget build(BuildContext context) {
    final c = context.ldColors;
    final type = context.ldType;

    if (foods.isEmpty) {
      return LdEmptyState(
        icon: query.isEmpty ? Icons.no_food_rounded : Icons.search_off_rounded,
        headline: query.isEmpty ? 'No foods yet' : 'No match for "$query"',
        body: 'Create it once and it stays in your list forever.',
        actionLabel: 'Create food',
        onAction: onCreate,
      );
    }

    return ListView.separated(
      padding: const EdgeInsets.only(bottom: LdSpacing.scrollBottom),
      itemCount: foods.length,
      separatorBuilder: (_, __) =>
          Divider(color: c.border, height: 1, indent: LdSpacing.s4),
      itemBuilder: (context, index) {
        final food = foods[index];
        return ListTile(
          title: Text(
            food.displayName,
            style: type.titleM.copyWith(color: c.textPrimary),
          ),
          subtitle: Text(
            '${food.per100g.kcal.round()} kcal · '
            '${food.per100g.proteinG.round()} g protein per 100 g'
            '${food.hasSuspectEnergy ? '  ·  check these values' : ''}',
            style: type.bodyS.copyWith(
              color: food.hasSuspectEnergy ? c.warning : c.textTertiary,
            ),
          ),
          trailing: Icon(Icons.add_circle_outline_rounded, color: c.primary),
          onTap: () => onPick(food),
        );
      },
    );
  }
}

class _MealList extends StatelessWidget {
  const _MealList({required this.meals, required this.onPick});
  final List<Meal> meals;
  final void Function(Meal) onPick;

  @override
  Widget build(BuildContext context) {
    final c = context.ldColors;
    final type = context.ldType;

    if (meals.isEmpty) {
      return const LdEmptyState(
        icon: Icons.dinner_dining_rounded,
        headline: 'No saved meals',
        body: 'Save a combination of foods as a meal to log it in one tap.',
      );
    }

    return ListView.separated(
      padding: const EdgeInsets.only(bottom: LdSpacing.scrollBottom),
      itemCount: meals.length,
      separatorBuilder: (_, __) =>
          Divider(color: c.border, height: 1, indent: LdSpacing.s4),
      itemBuilder: (context, index) {
        final meal = meals[index];
        final totals = meal.totals;
        return ListTile(
          title: Text(
            meal.name,
            style: type.titleM.copyWith(color: c.textPrimary),
          ),
          subtitle: Text(
            '${meal.items.length} items · ${totals.kcal.round()} kcal · '
            '${totals.proteinG.round()} g protein',
            style: type.bodyS.copyWith(color: c.textTertiary),
          ),
          trailing: Icon(Icons.add_circle_outline_rounded, color: c.primary),
          onTap: () => onPick(meal),
        );
      },
    );
  }
}
