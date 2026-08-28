import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:lifedna/core/providers/providers.dart';
import 'package:lifedna/core/theme/app_theme.dart';
import 'package:lifedna/core/theme/ld_spacing.dart';
import 'package:lifedna/core/widgets/ld_widgets.dart';
import 'package:lifedna/features/auth/domain/user_profile.dart';
import 'package:lifedna/shared/enums/enums.dart';

/// Edits the inputs that drive every calculated target.
///
/// Shows the resulting calorie target live while the user changes an input, so
/// the consequence of a choice is visible before it is saved rather than
/// discovered on the dashboard afterwards.
class GoalsEditorSheet extends ConsumerStatefulWidget {
  const GoalsEditorSheet({required this.profile, super.key});

  final UserProfile profile;

  static Future<void> show(BuildContext context, UserProfile profile) =>
      showModalBottomSheet<void>(
        context: context,
        isScrollControlled: true,
        useSafeArea: true,
        builder: (_) => GoalsEditorSheet(profile: profile),
      );

  @override
  ConsumerState<GoalsEditorSheet> createState() => _GoalsEditorSheetState();
}

class _GoalsEditorSheetState extends ConsumerState<GoalsEditorSheet> {
  final _formKey = GlobalKey<FormState>();
  late final TextEditingController _weight;
  late final TextEditingController _height;

  late GoalMode _goal;
  late ActivityLevel _activity;
  late int _trainingDays;
  late double _ratePct;
  bool _saving = false;

  @override
  void initState() {
    super.initState();
    final profile = widget.profile;
    _weight = TextEditingController(
      text: profile.weightKg > 0 ? _trim(profile.weightKg) : '',
    );
    _height = TextEditingController(
      text: profile.heightCm > 0 ? _trim(profile.heightCm) : '',
    );
    _goal = profile.goalMode;
    _activity = profile.activityLevel;
    _trainingDays = profile.trainingDaysPerWeek;
    _ratePct = profile.weeklyRateTargetPct;
  }

  static String _trim(double value) {
    final text = value.toStringAsFixed(1);
    return text.endsWith('.0') ? text.substring(0, text.length - 2) : text;
  }

  @override
  void dispose() {
    _weight.dispose();
    _height.dispose();
    super.dispose();
  }

  UserProfile get _draft => widget.profile.copyWith(
    weightKg: double.tryParse(_weight.text.trim()) ?? widget.profile.weightKg,
    heightCm: double.tryParse(_height.text.trim()) ?? widget.profile.heightCm,
    goalMode: _goal,
    activityLevel: _activity,
    trainingDaysPerWeek: _trainingDays,
    weeklyRateTargetPct: _ratePct,
  );

  @override
  Widget build(BuildContext context) {
    final c = context.ldColors;
    final type = context.ldType;
    final preview = _draft.computedTargets;

    return Padding(
      padding: EdgeInsets.only(
        bottom: MediaQuery.of(context).viewInsets.bottom,
      ),
      child: Form(
        key: _formKey,
        child: ListView(
          shrinkWrap: true,
          padding: const EdgeInsets.fromLTRB(
            LdSpacing.s5,
            LdSpacing.s2,
            LdSpacing.s5,
            LdSpacing.s5,
          ),
          children: [
            Text(
              'Goals and targets',
              style: type.headlineM.copyWith(color: c.textPrimary),
            ),
            const SizedBox(height: LdSpacing.s5),
            Row(
              children: [
                Expanded(
                  child: TextFormField(
                    controller: _weight,
                    keyboardType: const TextInputType.numberWithOptions(
                      decimal: true,
                    ),
                    inputFormatters: [
                      FilteringTextInputFormatter.allow(
                        RegExp(r'^\d{0,3}\.?\d{0,2}'),
                      ),
                    ],
                    decoration: const InputDecoration(
                      labelText: 'Weight',
                      suffixText: 'kg',
                    ),
                    onChanged: (_) => setState(() {}),
                    validator: (value) =>
                        _range(value, 30, 300, 'weight in kg'),
                  ),
                ),
                const SizedBox(width: LdSpacing.s3),
                Expanded(
                  child: TextFormField(
                    controller: _height,
                    keyboardType: const TextInputType.numberWithOptions(
                      decimal: true,
                    ),
                    inputFormatters: [
                      FilteringTextInputFormatter.allow(
                        RegExp(r'^\d{0,3}\.?\d{0,2}'),
                      ),
                    ],
                    decoration: const InputDecoration(
                      labelText: 'Height',
                      suffixText: 'cm',
                    ),
                    onChanged: (_) => setState(() {}),
                    validator: (value) =>
                        _range(value, 90, 250, 'height in cm'),
                  ),
                ),
              ],
            ),
            const SizedBox(height: LdSpacing.s4),
            _Segmented<GoalMode>(
              label: 'Goal',
              values: GoalMode.values,
              selected: _goal,
              labelOf: (value) => switch (value) {
                GoalMode.cut => 'Lose fat',
                GoalMode.maintain => 'Maintain',
                GoalMode.bulk => 'Build',
              },
              onChanged: (value) => setState(() => _goal = value),
            ),
            const SizedBox(height: LdSpacing.s4),
            _Segmented<ActivityLevel>(
              label: 'Activity',
              values: ActivityLevel.values,
              selected: _activity,
              labelOf: (value) => switch (value) {
                ActivityLevel.sedentary => 'Desk',
                ActivityLevel.light => 'Light',
                ActivityLevel.moderate => 'Moderate',
                ActivityLevel.active => 'Active',
                ActivityLevel.veryActive => 'Very high',
              },
              onChanged: (value) => setState(() => _activity = value),
            ),
            const SizedBox(height: LdSpacing.s4),
            Text(
              'TRAINING DAYS PER WEEK',
              style: type.labelMono.copyWith(color: c.textTertiary),
            ),
            Slider(
              value: _trainingDays.toDouble(),
              max: 7,
              divisions: 7,
              label: '$_trainingDays',
              onChanged: (value) =>
                  setState(() => _trainingDays = value.round()),
            ),
            if (_goal != GoalMode.maintain) ...[
              Text(
                'PACE · ${_ratePct.toStringAsFixed(2)} % OF BODYWEIGHT / WEEK',
                style: type.labelMono.copyWith(color: c.textTertiary),
              ),
              Slider(
                value: _ratePct,
                min: 0.25,
                max: 1,
                divisions: 15,
                label: '${_ratePct.toStringAsFixed(2)} %',
                onChanged: (value) => setState(() => _ratePct = value),
              ),
            ],
            const SizedBox(height: LdSpacing.s3),
            if (preview != null)
              LdCard(
                eyebrow: 'New targets',
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      '${preview.trainingDay.kcal.round()} kcal training day · '
                      '${preview.restDay.kcal.round()} kcal rest day',
                      style: type.titleM.copyWith(color: c.textPrimary),
                    ),
                    const SizedBox(height: LdSpacing.s1),
                    Text(
                      'Protein floor ${preview.proteinFloorG.round()} g · '
                      'water ${preview.waterMl} ml',
                      style: type.bodyS.copyWith(color: c.textSecondary),
                    ),
                    if (preview.clamped) ...[
                      const SizedBox(height: LdSpacing.s2),
                      Text(
                        'Adjusted down to the safe maximum.',
                        style: type.bodyS.copyWith(color: c.warning),
                      ),
                    ],
                  ],
                ),
              ),
            const SizedBox(height: LdSpacing.s5),
            LdPrimaryButton(
              label: 'Save',
              size: LdButtonSize.l,
              loading: _saving,
              onPressed: _save,
            ),
          ],
        ),
      ),
    );
  }

  static String? _range(String? value, double min, double max, String what) {
    final parsed = double.tryParse((value ?? '').trim());
    if (parsed == null) return 'Enter your $what';
    if (parsed < min || parsed > max) {
      return 'Between ${min.round()} and ${max.round()}';
    }
    return null;
  }

  Future<void> _save() async {
    if (!(_formKey.currentState?.validate() ?? false)) return;
    setState(() => _saving = true);

    final navigator = Navigator.of(context);
    final result = await ref.read(profileRepositoryProvider).save(_draft);
    if (!mounted) return;
    setState(() => _saving = false);

    final failure = result.failureOrNull;
    if (failure != null) {
      showFailureSnack(context, failure);
      return;
    }
    navigator.pop();
  }
}

class _Segmented<T> extends StatelessWidget {
  const _Segmented({
    required this.label,
    required this.values,
    required this.selected,
    required this.labelOf,
    required this.onChanged,
  });

  final String label;
  final List<T> values;
  final T selected;
  final String Function(T value) labelOf;
  final ValueChanged<T> onChanged;

  @override
  Widget build(BuildContext context) {
    final c = context.ldColors;
    final type = context.ldType;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          label.toUpperCase(),
          style: type.labelMono.copyWith(color: c.textTertiary),
        ),
        const SizedBox(height: LdSpacing.s2),
        Wrap(
          spacing: LdSpacing.s2,
          runSpacing: LdSpacing.s2,
          children: [
            for (final value in values)
              ChoiceChip(
                label: Text(labelOf(value)),
                selected: value == selected,
                onSelected: (_) => onChanged(value),
              ),
          ],
        ),
      ],
    );
  }
}
