import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:lifedna/core/providers/app_providers.dart';
import 'package:lifedna/core/theme/app_theme.dart';
import 'package:lifedna/core/theme/ld_spacing.dart';
import 'package:lifedna/core/widgets/ld_widgets.dart';
import 'package:lifedna/features/nutrition/domain/entities/food.dart';
import 'package:lifedna/shared/enums/enums.dart';
import 'package:lifedna/shared/value_objects/macros.dart';

/// Add Food (docs/06 Screen 03).
///
/// The 12-second target from the PRD is a layout constraint, not an
/// aspiration: search is focused on entry, Recent is the default surface, the
/// slot is pre-filled from context, and the portion sheet never leaves the
/// screen.
class AddFoodScreen extends ConsumerStatefulWidget {
  const AddFoodScreen({required this.slotWire, super.key});
  final String slotWire;

  @override
  ConsumerState<AddFoodScreen> createState() => _AddFoodScreenState();
}

class _AddFoodScreenState extends ConsumerState<AddFoodScreen> {
  final _controller = TextEditingController();
  List<Food> _results = const [];
  bool _loading = true;

  MealSlot get _slot => MealSlot.fromWire(widget.slotWire);

  @override
  void initState() {
    super.initState();
    _search('');
    _controller.addListener(() => _search(_controller.text));
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  Future<void> _search(String query) async {
    final results =
        await ref.read(nutritionRepositoryProvider).searchFoods(query);
    if (!mounted) return;
    setState(() {
      _results = results;
      _loading = false;
    });
  }

  @override
  Widget build(BuildContext context) {
    final c = context.ldColors;
    final type = context.ldType;

    return Scaffold(
      appBar: AppBar(title: Text('Add to ${_slot.label.toLowerCase()}')),
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
              controller: _controller,
              autofocus: true,
              textInputAction: TextInputAction.search,
              decoration: const InputDecoration(
                hintText: 'Search foods…',
                prefixIcon: Icon(Icons.search_rounded),
              ),
            ),
          ),
          if (_loading)
            const Expanded(child: Center(child: CircularProgressIndicator()))
          else if (_results.isEmpty)
            Expanded(
              child: LdEmptyState(
                icon: Icons.search_off_rounded,
                headline: 'No match for "${_controller.text}"',
                body: "Add it once and it's yours forever.",
                actionLabel: 'Create food',
                onAction: () => ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(
                    content: Text('Custom food creation lands in Sprint 4.'),
                  ),
                ),
              ),
            )
          else
            Expanded(
              child: ListView.separated(
                padding: const EdgeInsets.only(
                  bottom: LdSpacing.scrollBottom,
                ),
                itemCount: _results.length,
                separatorBuilder: (_, __) => Divider(
                  color: c.border,
                  height: 1,
                  indent: LdSpacing.s4,
                ),
                itemBuilder: (context, i) {
                  final food = _results[i];
                  return ListTile(
                    title: Text(
                      food.displayName,
                      style: type.titleM.copyWith(color: c.textPrimary),
                    ),
                    subtitle: Text(
                      '${food.per100g.kcal.round()} kcal · '
                      '${food.per100g.proteinG.round()} g P per 100 g'
                      '${food.hasSuspectData ? '  ⚠ check this data' : ''}',
                      style: type.bodyS.copyWith(
                        color: food.hasSuspectData ? c.warning : c.textTertiary,
                      ),
                    ),
                    trailing: IconButton(
                      icon: const Icon(Icons.add_circle_outline_rounded),
                      color: c.primary,
                      onPressed: () => _openPortionSheet(food),
                    ),
                    onTap: () => _openPortionSheet(food),
                  );
                },
              ),
            ),
        ],
      ),
    );
  }

  Future<void> _openPortionSheet(Food food) async {
    final logged = await showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      builder: (_) => _PortionSheet(food: food, slot: _slot),
    );
    if (logged == true && mounted) {
      Navigator.of(context).pop();
    }
  }
}

class _PortionSheet extends ConsumerStatefulWidget {
  const _PortionSheet({required this.food, required this.slot});
  final Food food;
  final MealSlot slot;

  @override
  ConsumerState<_PortionSheet> createState() => _PortionSheetState();
}

class _PortionSheetState extends ConsumerState<_PortionSheet> {
  late double _quantity = widget.food.servings.isEmpty
      ? 100
      : widget.food.servings.first.grams;
  PortionUnit _unit = PortionUnit.grams;
  bool _saving = false;

  Macros get _preview => widget.food.macrosFor(_quantity, _unit);

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
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              widget.food.displayName,
              style: type.titleL.copyWith(color: c.textPrimary),
            ),
            const SizedBox(height: LdSpacing.s1),
            // Provenance is always visible: community data is frequently
            // wrong, and a user who can see the source can correct it.
            Text(
              '${widget.food.provider.label} · per 100 g',
              style: type.labelMono.copyWith(color: c.textTertiary),
            ),
            const SizedBox(height: LdSpacing.s5),
            Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                _StepButton(
                  icon: Icons.remove_rounded,
                  onTap: () => setState(
                    () => _quantity =
                        (_quantity - 10).clamp(1.0, 5000.0).toDouble(),
                  ),
                ),
                const SizedBox(width: LdSpacing.s5),
                SizedBox(
                  width: 110,
                  child: Text(
                    '${_quantity.round()}',
                    textAlign: TextAlign.center,
                    style: type.displayM.copyWith(color: c.textPrimary),
                  ),
                ),
                const SizedBox(width: LdSpacing.s5),
                _StepButton(
                  icon: Icons.add_rounded,
                  onTap: () => setState(
                    () => _quantity =
                        (_quantity + 10).clamp(1.0, 5000.0).toDouble(),
                  ),
                ),
              ],
            ),
            const SizedBox(height: LdSpacing.s4),
            Wrap(
              spacing: LdSpacing.s2,
              children: [
                for (final preset in _presets())
                  ChoiceChip(
                    label: Text(preset.label),
                    selected: (_quantity - preset.grams).abs() < 0.5,
                    onSelected: (_) => setState(() {
                      _quantity = preset.grams;
                      _unit = PortionUnit.grams;
                    }),
                  ),
              ],
            ),
            const SizedBox(height: LdSpacing.s5),
            Container(
              padding: const EdgeInsets.all(LdSpacing.s4),
              decoration: BoxDecoration(
                color: c.surfaceElevated,
                borderRadius: BorderRadius.circular(LdRadius.m),
                border: Border.all(color: c.border),
              ),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  _PreviewValue(
                    value: '${_preview.kcal.round()}',
                    label: 'kcal',
                    color: c.calories,
                  ),
                  _PreviewValue(
                    value: '${_preview.proteinG.round()}',
                    label: 'protein',
                    color: c.protein,
                  ),
                  _PreviewValue(
                    value: '${_preview.carbsG.round()}',
                    label: 'carbs',
                    color: c.carbs,
                  ),
                  _PreviewValue(
                    value: '${_preview.fatG.round()}',
                    label: 'fat',
                    color: c.fat,
                  ),
                ],
              ),
            ),
            const SizedBox(height: LdSpacing.s5),
            LdPrimaryButton(
              label: 'Add to ${widget.slot.label.toLowerCase()}',
              size: LdButtonSize.l,
              loading: _saving,
              onPressed: _save,
            ),
          ],
        ),
      ),
    );
  }

  List<FoodServing> _presets() {
    final servings = widget.food.servings;
    return [
      const FoodServing(label: '100 g', grams: 100),
      if (servings.isNotEmpty && servings.first.grams != 100) servings.first,
      if (servings.length > 1) servings[1],
      const FoodServing(label: '200 g', grams: 200),
    ];
  }

  Future<void> _save() async {
    setState(() => _saving = true);
    final result = await ref.read(nutritionRepositoryProvider).logEntry(
          food: widget.food,
          quantity: _quantity,
          unit: _unit,
          slot: widget.slot,
        );
    if (!mounted) return;

    result.when(
      ok: (_) => Navigator.of(context).pop(true),
      err: (failure) {
        setState(() => _saving = false);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(_message(failure.message))),
        );
      },
    );
  }

  static String _message(String code) => switch (code) {
        'quantity_must_be_positive' => 'Enter a quantity greater than zero.',
        'quantity_implausible' =>
          "That's an unusually large amount. Check the unit.",
        _ => 'Could not add that. Try again.',
      };
}

class _StepButton extends StatelessWidget {
  const _StepButton({required this.icon, required this.onTap});
  final IconData icon;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final c = context.ldColors;
    return Material(
      color: c.surfaceElevated,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(LdRadius.s),
        side: BorderSide(color: c.borderStrong),
      ),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(LdRadius.s),
        child: SizedBox(
          width: LdTouch.min,
          height: LdTouch.min,
          child: Icon(icon, color: c.textPrimary),
        ),
      ),
    );
  }
}

class _PreviewValue extends StatelessWidget {
  const _PreviewValue({
    required this.value,
    required this.label,
    required this.color,
  });
  final String value;
  final String label;
  final Color color;

  @override
  Widget build(BuildContext context) {
    final type = context.ldType;
    return Column(
      children: [
        Text(value, style: type.titleL.copyWith(color: color)),
        const SizedBox(height: LdSpacing.s1),
        Text(
          label.toUpperCase(),
          style: type.labelMono.copyWith(color: context.ldColors.textTertiary),
        ),
      ],
    );
  }
}
