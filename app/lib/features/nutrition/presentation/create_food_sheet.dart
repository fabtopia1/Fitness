import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:lifedna/core/providers/providers.dart';
import 'package:lifedna/core/theme/app_theme.dart';
import 'package:lifedna/core/theme/ld_spacing.dart';
import 'package:lifedna/core/widgets/ld_widgets.dart';
import 'package:lifedna/features/nutrition/domain/nutrition_entities.dart';
import 'package:lifedna/shared/enums/enums.dart';
import 'package:lifedna/shared/value_objects/macros.dart';

/// Creates a food item from per-100 g values.
class CreateFoodSheet extends ConsumerStatefulWidget {
  const CreateFoodSheet({super.key});

  @override
  ConsumerState<CreateFoodSheet> createState() => _CreateFoodSheetState();
}

class _CreateFoodSheetState extends ConsumerState<CreateFoodSheet> {
  final _formKey = GlobalKey<FormState>();
  final _name = TextEditingController();
  final _brand = TextEditingController();
  final _kcal = TextEditingController();
  final _protein = TextEditingController();
  final _carbs = TextEditingController();
  final _fat = TextEditingController();
  bool _saving = false;

  @override
  void dispose() {
    for (final controller in [_name, _brand, _kcal, _protein, _carbs, _fat]) {
      controller.dispose();
    }
    super.dispose();
  }

  Macros get _macros => Macros(
        kcal: double.tryParse(_kcal.text) ?? 0,
        proteinG: double.tryParse(_protein.text) ?? 0,
        carbsG: double.tryParse(_carbs.text) ?? 0,
        fatG: double.tryParse(_fat.text) ?? 0,
      );

  @override
  Widget build(BuildContext context) {
    final c = context.ldColors;
    final type = context.ldType;
    final macros = _macros;
    // Atwater cross-check: catches a typo before it poisons every future log.
    final mismatch = macros.kcal > 0 && macros.isEnergyInconsistent();

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
                  'New food',
                  style: type.headlineM.copyWith(color: c.textPrimary),
                ),
                const SizedBox(height: LdSpacing.s1),
                Text(
                  'Enter the values per 100 g, as printed on the label.',
                  style: type.bodyS.copyWith(color: c.textSecondary),
                ),
                const SizedBox(height: LdSpacing.s4),
                TextFormField(
                  controller: _name,
                  textCapitalization: TextCapitalization.sentences,
                  decoration: const InputDecoration(labelText: 'Name'),
                  validator: (v) => (v == null || v.trim().isEmpty)
                      ? 'Enter a name'
                      : null,
                ),
                const SizedBox(height: LdSpacing.s3),
                TextFormField(
                  controller: _brand,
                  textCapitalization: TextCapitalization.words,
                  decoration:
                      const InputDecoration(labelText: 'Brand (optional)'),
                ),
                const SizedBox(height: LdSpacing.s3),
                Row(
                  children: [
                    Expanded(
                      child: _NumberField(
                        controller: _kcal,
                        label: 'Calories',
                        suffix: 'kcal',
                        required: true,
                      ),
                    ),
                    const SizedBox(width: LdSpacing.s3),
                    Expanded(
                      child: _NumberField(
                        controller: _protein,
                        label: 'Protein',
                        suffix: 'g',
                        required: true,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: LdSpacing.s3),
                Row(
                  children: [
                    Expanded(
                      child: _NumberField(
                        controller: _carbs,
                        label: 'Carbs',
                        suffix: 'g',
                        required: true,
                      ),
                    ),
                    const SizedBox(width: LdSpacing.s3),
                    Expanded(
                      child: _NumberField(
                        controller: _fat,
                        label: 'Fat',
                        suffix: 'g',
                        required: true,
                      ),
                    ),
                  ],
                ),
                if (mismatch) ...[
                  const SizedBox(height: LdSpacing.s3),
                  Container(
                    padding: const EdgeInsets.all(LdSpacing.s3),
                    decoration: BoxDecoration(
                      color: Color.lerp(c.surface, c.warning, 0.18),
                      borderRadius: BorderRadius.circular(LdRadius.s),
                    ),
                    child: Row(
                      children: [
                        Icon(Icons.warning_amber_rounded,
                            size: 18, color: c.warning),
                        const SizedBox(width: LdSpacing.s2),
                        Expanded(
                          child: Text(
                            'The macros add up to about '
                            '${macros.derivedKcal.round()} kcal, not '
                            '${macros.kcal.round()}. Double-check the label.',
                            style: type.bodyS
                                .copyWith(color: c.textSecondary),
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
                const SizedBox(height: LdSpacing.s5),
                LdPrimaryButton(
                  label: 'Save food',
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

    final repository = ref.read(nutritionRepositoryProvider);
    final food = repository.createFood(
      name: _name.text,
      brand: _brand.text,
      per100g: _macros,
    );
    final result = await repository.saveFood(food);
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

class _NumberField extends StatelessWidget {
  const _NumberField({
    required this.controller,
    required this.label,
    required this.suffix,
    this.required = false,
  });

  final TextEditingController controller;
  final String label;
  final String suffix;
  // ignore: avoid_positional_boolean_parameters
  final bool required;

  @override
  Widget build(BuildContext context) => TextFormField(
        controller: controller,
        keyboardType: const TextInputType.numberWithOptions(decimal: true),
        inputFormatters: [
          FilteringTextInputFormatter.allow(RegExp(r'^\d*\.?\d{0,2}')),
        ],
        decoration: InputDecoration(labelText: label, suffixText: suffix),
        validator: (value) {
          if (!required) return null;
          final parsed = double.tryParse(value ?? '');
          if (parsed == null) return 'Required';
          if (parsed < 0) return 'Must be positive';
          if (parsed > 2000) return 'Too large';
          return null;
        },
      );
}

/// Chooses a portion and logs it.
class PortionSheet extends ConsumerStatefulWidget {
  const PortionSheet({required this.food, required this.slot, super.key});

  final FoodItem food;
  final MealSlot slot;

  @override
  ConsumerState<PortionSheet> createState() => _PortionSheetState();
}

class _PortionSheetState extends ConsumerState<PortionSheet> {
  late double _grams = widget.food.servingGrams ?? 100;
  bool _saving = false;

  @override
  Widget build(BuildContext context) {
    final c = context.ldColors;
    final type = context.ldType;
    final preview = widget.food.macrosForGrams(_grams);

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
            const SizedBox(height: LdSpacing.s5),
            Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                _StepButton(
                  icon: Icons.remove_rounded,
                  onTap: () => setState(
                    () => _grams = (_grams - 10).clamp(1.0, 5000.0).toDouble(),
                  ),
                ),
                SizedBox(
                  width: 130,
                  child: Text(
                    '${_grams.round()} g',
                    textAlign: TextAlign.center,
                    style: type.displayM.copyWith(color: c.textPrimary),
                  ),
                ),
                _StepButton(
                  icon: Icons.add_rounded,
                  onTap: () => setState(
                    () => _grams = (_grams + 10).clamp(1.0, 5000.0).toDouble(),
                  ),
                ),
              ],
            ),
            const SizedBox(height: LdSpacing.s4),
            Wrap(
              spacing: LdSpacing.s2,
              children: [
                for (final preset in const [50.0, 100.0, 150.0, 200.0, 250.0])
                  ChoiceChip(
                    label: Text('${preset.round()} g'),
                    selected: (_grams - preset).abs() < 0.5,
                    onSelected: (_) => setState(() => _grams = preset),
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
                  _Preview(
                    value: preview.kcal.round().toString(),
                    label: 'kcal',
                    color: c.calories,
                  ),
                  _Preview(
                    value: preview.proteinG.round().toString(),
                    label: 'protein',
                    color: c.protein,
                  ),
                  _Preview(
                    value: preview.carbsG.round().toString(),
                    label: 'carbs',
                    color: c.carbs,
                  ),
                  _Preview(
                    value: preview.fatG.round().toString(),
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

  Future<void> _save() async {
    setState(() => _saving = true);
    final result = await ref.read(nutritionRepositoryProvider).logFood(
          food: widget.food,
          quantity: _grams,
          unit: PortionUnit.grams,
          slot: widget.slot,
        );
    if (!mounted) return;

    result.when(
      ok: (_) => Navigator.of(context).pop(true),
      err: (failure) {
        setState(() => _saving = false);
        showFailureSnack(context, failure);
      },
    );
  }
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

class _Preview extends StatelessWidget {
  const _Preview({
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
