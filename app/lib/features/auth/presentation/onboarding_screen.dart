import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:lifedna/core/engines/macro_calculator.dart';
import 'package:lifedna/core/providers/providers.dart';
import 'package:lifedna/core/theme/app_theme.dart';
import 'package:lifedna/core/theme/ld_spacing.dart';
import 'package:lifedna/core/widgets/ld_widgets.dart';
import 'package:lifedna/features/auth/domain/user_profile.dart';
import 'package:lifedna/features/auth/presentation/auth_controller.dart';
import 'package:lifedna/shared/enums/enums.dart';
import 'package:lifedna/shared/value_objects/macros.dart';

/// Collects the minimum profile data the engines need, then shows the user the
/// numbers those inputs produce before it commits anything.
///
/// The last step is a review rather than a confirmation dialog on purpose: the
/// targets are derived, so the honest thing is to show the derivation and let
/// the user go back and change an input they disagree with.
class OnboardingScreen extends ConsumerStatefulWidget {
  const OnboardingScreen({super.key});

  @override
  ConsumerState<OnboardingScreen> createState() => _OnboardingScreenState();
}

class _OnboardingScreenState extends ConsumerState<OnboardingScreen> {
  static const _stepCount = 4;

  final _bodyFormKey = GlobalKey<FormState>();
  final _heightController = TextEditingController();
  final _weightController = TextEditingController();
  final _targetWeightController = TextEditingController();

  int _step = 0;
  bool _seededFromProfile = false;
  bool _submitting = false;

  DateTime? _dateOfBirth;
  Sex _sex = Sex.unspecified;
  ActivityLevel _activity = ActivityLevel.moderate;
  GoalMode _goal = GoalMode.maintain;
  int _trainingDays = 4;
  double _weeklyRatePct = 0.5;

  @override
  void dispose() {
    _heightController.dispose();
    _weightController.dispose();
    _targetWeightController.dispose();
    super.dispose();
  }

  /// Pre-fills from whatever the profile already holds, so a user who abandons
  /// onboarding and comes back does not retype everything.
  void _seed(UserProfile profile) {
    if (_seededFromProfile) return;
    _seededFromProfile = true;
    _dateOfBirth = profile.dateOfBirth;
    _sex = profile.sex;
    _activity = profile.activityLevel;
    _goal = profile.goalMode;
    _trainingDays = profile.trainingDaysPerWeek;
    _weeklyRatePct = profile.weeklyRateTargetPct;
    if (profile.heightCm > 0) {
      _heightController.text = _trimZero(profile.heightCm);
    }
    if (profile.weightKg > 0) {
      _weightController.text = _trimZero(profile.weightKg);
    }
    final target = profile.targetWeightKg;
    if (target != null && target > 0) {
      _targetWeightController.text = _trimZero(target);
    }
  }

  static String _trimZero(double value) {
    final text = value.toStringAsFixed(1);
    return text.endsWith('.0') ? text.substring(0, text.length - 2) : text;
  }

  double get _heightCm => double.tryParse(_heightController.text.trim()) ?? 0;
  double get _weightKg => double.tryParse(_weightController.text.trim()) ?? 0;
  double? get _targetWeightKg =>
      double.tryParse(_targetWeightController.text.trim());

  /// The profile the user has described so far, used both for the preview and
  /// for the final save — there is only one place these values are assembled.
  UserProfile _draft(UserProfile base) => base.copyWith(
        dateOfBirth: _dateOfBirth,
        sex: _sex,
        heightCm: _heightCm,
        weightKg: _weightKg,
        activityLevel: _activity,
        goalMode: _goal,
        trainingDaysPerWeek: _trainingDays,
        targetWeightKg: _targetWeightKg,
        weeklyRateTargetPct: _weeklyRatePct,
      );

  @override
  Widget build(BuildContext context) {
    final profileValue = ref.watch(profileProvider);

    return Scaffold(
      appBar: AppBar(
        title: Text('Step ${_step + 1} of $_stepCount'),
        leading: _step == 0
            ? null
            : IconButton(
                icon: const Icon(Icons.arrow_back_rounded),
                onPressed: () => setState(() => _step -= 1),
              ),
        bottom: PreferredSize(
          preferredSize: const Size.fromHeight(2),
          child: LinearProgressIndicator(
            value: (_step + 1) / _stepCount,
            minHeight: 2,
          ),
        ),
      ),
      body: SafeArea(
        child: LdAsyncView<UserProfile?>(
          value: profileValue,
          onRetry: () => ref.invalidate(profileProvider),
          errorContext: 'onboarding',
          data: (profile) {
            if (profile == null) {
              // The profile is created immediately after authentication; if it
              // is missing, sign-out is the only honest recovery.
              return LdEmptyState(
                icon: Icons.person_off_rounded,
                headline: 'Profile not found',
                body: 'Sign in again to rebuild your profile on this device.',
                actionLabel: 'Sign out',
                onAction: () =>
                    ref.read(authControllerProvider.notifier).signOut(),
              );
            }
            _seed(profile);
            return _buildStep(profile);
          },
        ),
      ),
    );
  }

  Widget _buildStep(UserProfile profile) => switch (_step) {
        0 => _AboutYouStep(
            dateOfBirth: _dateOfBirth,
            sex: _sex,
            onPickDate: _pickDateOfBirth,
            onSexChanged: (value) => setState(() => _sex = value),
            onNext: _dateOfBirth == null ? null : () => setState(() => _step = 1),
          ),
        1 => Form(
            key: _bodyFormKey,
            child: _BodyStep(
              heightController: _heightController,
              weightController: _weightController,
              onNext: () {
                if (_bodyFormKey.currentState?.validate() ?? false) {
                  setState(() => _step = 2);
                }
              },
            ),
          ),
        2 => _GoalStep(
            goal: _goal,
            activity: _activity,
            trainingDays: _trainingDays,
            weeklyRatePct: _weeklyRatePct,
            targetWeightController: _targetWeightController,
            currentWeightKg: _weightKg,
            onGoalChanged: (value) => setState(() => _goal = value),
            onActivityChanged: (value) => setState(() => _activity = value),
            onTrainingDaysChanged: (value) =>
                setState(() => _trainingDays = value),
            onRateChanged: (value) => setState(() => _weeklyRatePct = value),
            onNext: () => setState(() => _step = 3),
          ),
        _ => _ReviewStep(
            profile: _draft(profile),
            submitting: _submitting,
            onFinish: () => _finish(profile),
          ),
      };

  Future<void> _pickDateOfBirth() async {
    final now = DateTime.now();
    final initial = _dateOfBirth ?? DateTime(now.year - 25, now.month, now.day);
    final picked = await showDatePicker(
      context: context,
      initialDate: initial,
      // 13 is the minimum age this app is offered at; 100 bounds the picker.
      firstDate: DateTime(now.year - 100),
      lastDate: DateTime(now.year - 13, now.month, now.day),
      helpText: 'Date of birth',
    );
    if (picked != null) setState(() => _dateOfBirth = picked);
  }

  Future<void> _finish(UserProfile profile) async {
    setState(() => _submitting = true);
    final failure = await ref
        .read(authControllerProvider.notifier)
        .completeOnboarding(_draft(profile));
    if (!mounted) return;
    setState(() => _submitting = false);
    if (failure != null) showFailureSnack(context, failure);
    // On success the router's redirect moves to the dashboard, because the
    // profile stream now reports isOnboarded.
  }
}

// --------------------------------------------------------------- step one --

class _AboutYouStep extends StatelessWidget {
  const _AboutYouStep({
    required this.dateOfBirth,
    required this.sex,
    required this.onPickDate,
    required this.onSexChanged,
    required this.onNext,
  });

  final DateTime? dateOfBirth;
  final Sex sex;
  final VoidCallback onPickDate;
  final ValueChanged<Sex> onSexChanged;
  final VoidCallback? onNext;

  @override
  Widget build(BuildContext context) {
    final c = context.ldColors;
    final type = context.ldType;

    return _StepScaffold(
      title: 'About you',
      subtitle: 'Age and sex change your energy expenditure. Both are used '
          'only on this device and in your own account.',
      onNext: onNext,
      nextLabel: 'Continue',
      children: [
        LdCard(
          eyebrow: 'Date of birth',
          onTap: onPickDate,
          child: Row(
            children: [
              Icon(Icons.cake_rounded, size: 20, color: c.textTertiary),
              const SizedBox(width: LdSpacing.s3),
              Expanded(
                child: Text(
                  dateOfBirth == null
                      ? 'Select your date of birth'
                      : _formatDate(dateOfBirth!),
                  style: type.titleM.copyWith(
                    color: dateOfBirth == null ? c.textTertiary : c.textPrimary,
                  ),
                ),
              ),
              Icon(Icons.chevron_right_rounded, color: c.textTertiary),
            ],
          ),
        ),
        const SizedBox(height: LdSpacing.cardGap),
        LdCard(
          eyebrow: 'Sex',
          child: Column(
            children: [
              for (final option in Sex.values)
                _ChoiceRow(
                  label: switch (option) {
                    Sex.male => 'Male',
                    Sex.female => 'Female',
                    Sex.unspecified => 'Prefer not to say',
                  },
                  detail: option == Sex.unspecified
                      ? 'Uses the average of both formulas'
                      : null,
                  selected: sex == option,
                  onTap: () => onSexChanged(option),
                ),
            ],
          ),
        ),
      ],
    );
  }

  static String _formatDate(DateTime date) {
    const months = [
      'Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun',
      'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec',
    ];
    return '${date.day} ${months[date.month - 1]} ${date.year}';
  }
}

// --------------------------------------------------------------- step two --

class _BodyStep extends StatelessWidget {
  const _BodyStep({
    required this.heightController,
    required this.weightController,
    required this.onNext,
  });

  final TextEditingController heightController;
  final TextEditingController weightController;
  final VoidCallback onNext;

  @override
  Widget build(BuildContext context) {
    return _StepScaffold(
      title: 'Your measurements',
      subtitle: 'Metric units. You can change your weight any time from the '
          'Body tab — it does not have to be exact today.',
      onNext: onNext,
      nextLabel: 'Continue',
      children: [
        TextFormField(
          controller: heightController,
          keyboardType: const TextInputType.numberWithOptions(decimal: true),
          textInputAction: TextInputAction.next,
          inputFormatters: [_decimalFormatter],
          decoration: const InputDecoration(
            labelText: 'Height',
            suffixText: 'cm',
          ),
          validator: (value) => _rangeError(value, 90, 250, 'height in cm'),
        ),
        const SizedBox(height: LdSpacing.s4),
        TextFormField(
          controller: weightController,
          keyboardType: const TextInputType.numberWithOptions(decimal: true),
          textInputAction: TextInputAction.done,
          inputFormatters: [_decimalFormatter],
          decoration: const InputDecoration(
            labelText: 'Current weight',
            suffixText: 'kg',
          ),
          validator: (value) => _rangeError(value, 30, 300, 'weight in kg'),
        ),
      ],
    );
  }
}

/// Rejects anything that is not a plausible measurement. Bad body data
/// propagates into every target the app computes, so it is stopped at entry.
String? _rangeError(String? value, double min, double max, String what) {
  final parsed = double.tryParse((value ?? '').trim());
  if (parsed == null) return 'Enter your $what';
  if (parsed < min || parsed > max) {
    return 'Enter a $what between ${min.round()} and ${max.round()}';
  }
  return null;
}

final _decimalFormatter =
    FilteringTextInputFormatter.allow(RegExp(r'^\d{0,3}\.?\d{0,2}'));

// ------------------------------------------------------------- step three --

class _GoalStep extends StatelessWidget {
  const _GoalStep({
    required this.goal,
    required this.activity,
    required this.trainingDays,
    required this.weeklyRatePct,
    required this.targetWeightController,
    required this.currentWeightKg,
    required this.onGoalChanged,
    required this.onActivityChanged,
    required this.onTrainingDaysChanged,
    required this.onRateChanged,
    required this.onNext,
  });

  final GoalMode goal;
  final ActivityLevel activity;
  final int trainingDays;
  final double weeklyRatePct;
  final TextEditingController targetWeightController;
  final double currentWeightKg;
  final ValueChanged<GoalMode> onGoalChanged;
  final ValueChanged<ActivityLevel> onActivityChanged;
  final ValueChanged<int> onTrainingDaysChanged;
  final ValueChanged<double> onRateChanged;
  final VoidCallback onNext;

  @override
  Widget build(BuildContext context) {
    final c = context.ldColors;
    final type = context.ldType;
    final wantsRate = goal != GoalMode.maintain;

    return _StepScaffold(
      title: 'Your goal',
      subtitle: 'This sets your daily calorie target and how fast the app '
          'expects your weight to move.',
      onNext: onNext,
      nextLabel: 'See my targets',
      children: [
        LdCard(
          eyebrow: 'Goal',
          child: Column(
            children: [
              for (final option in GoalMode.values)
                _ChoiceRow(
                  label: switch (option) {
                    GoalMode.cut => 'Lose fat',
                    GoalMode.maintain => 'Maintain',
                    GoalMode.bulk => 'Build muscle',
                  },
                  detail: switch (option) {
                    GoalMode.cut => 'Calorie deficit, protein held high',
                    GoalMode.maintain => 'Eat at maintenance',
                    GoalMode.bulk => 'Controlled surplus',
                  },
                  selected: goal == option,
                  onTap: () => onGoalChanged(option),
                ),
            ],
          ),
        ),
        if (wantsRate) ...[
          const SizedBox(height: LdSpacing.cardGap),
          LdCard(
            eyebrow: 'Pace',
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  '${weeklyRatePct.toStringAsFixed(2)} % of bodyweight per week',
                  style: type.titleL.copyWith(color: c.textPrimary),
                ),
                if (currentWeightKg > 0)
                  Text(
                    '≈ ${(currentWeightKg * weeklyRatePct / 100).toStringAsFixed(2)} kg per week',
                    style: type.bodyS.copyWith(color: c.textSecondary),
                  ),
                Slider(
                  value: weeklyRatePct,
                  min: 0.25,
                  // The engine clamps above 1.0 %/week; the control does not
                  // offer a value the engine would refuse.
                  max: 1,
                  divisions: 15,
                  label: '${weeklyRatePct.toStringAsFixed(2)} %',
                  onChanged: onRateChanged,
                ),
                Text(
                  'Faster is not better. Above 1 % per week the app clamps the '
                  'target and tells you it did.',
                  style: type.caption.copyWith(color: c.textTertiary),
                ),
              ],
            ),
          ),
          const SizedBox(height: LdSpacing.cardGap),
          TextFormField(
            controller: targetWeightController,
            keyboardType: const TextInputType.numberWithOptions(decimal: true),
            inputFormatters: [_decimalFormatter],
            decoration: const InputDecoration(
              labelText: 'Target weight (optional)',
              suffixText: 'kg',
            ),
          ),
        ],
        const SizedBox(height: LdSpacing.cardGap),
        LdCard(
          eyebrow: 'Daily activity',
          child: Column(
            children: [
              for (final option in ActivityLevel.values)
                _ChoiceRow(
                  label: switch (option) {
                    ActivityLevel.sedentary => 'Sedentary',
                    ActivityLevel.light => 'Light',
                    ActivityLevel.moderate => 'Moderate',
                    ActivityLevel.active => 'Active',
                    ActivityLevel.veryActive => 'Very active',
                  },
                  detail: option.description,
                  selected: activity == option,
                  onTap: () => onActivityChanged(option),
                ),
            ],
          ),
        ),
        const SizedBox(height: LdSpacing.cardGap),
        LdCard(
          eyebrow: 'Training days per week',
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              for (var days = 0; days <= 7; days++)
                _DayChip(
                  days: days,
                  selected: trainingDays == days,
                  onTap: () => onTrainingDaysChanged(days),
                ),
            ],
          ),
        ),
      ],
    );
  }
}

class _DayChip extends StatelessWidget {
  const _DayChip({
    required this.days,
    required this.selected,
    required this.onTap,
  });

  final int days;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final c = context.ldColors;
    return Semantics(
      button: true,
      selected: selected,
      label: '$days training days per week',
      excludeSemantics: true,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(LdRadius.full),
        child: Container(
          width: 36,
          height: 36,
          alignment: Alignment.center,
          decoration: BoxDecoration(
            color: selected ? c.primary : c.surfaceElevated,
            shape: BoxShape.circle,
            border: Border.all(color: selected ? c.primary : c.border),
          ),
          child: Text(
            '$days',
            style: context.ldType.titleM.copyWith(
              color: selected ? c.textOnPrimary : c.textSecondary,
            ),
          ),
        ),
      ),
    );
  }
}

// -------------------------------------------------------------- step four --

class _ReviewStep extends StatelessWidget {
  const _ReviewStep({
    required this.profile,
    required this.submitting,
    required this.onFinish,
  });

  final UserProfile profile;
  final bool submitting;
  final VoidCallback onFinish;

  @override
  Widget build(BuildContext context) {
    final c = context.ldColors;
    final type = context.ldType;
    final targets = profile.computedTargets;

    return _StepScaffold(
      title: 'Your targets',
      subtitle: 'Calculated from what you entered with the Mifflin-St Jeor '
          'equation. You can change any of it later.',
      onNext: targets == null ? null : onFinish,
      nextLabel: 'Start using LifeDNA',
      nextLoading: submitting,
      children: [
        if (targets == null)
          LdCard(
            child: Text(
              'Go back and complete your date of birth, height and weight — '
              'targets cannot be calculated without them.',
              style: type.bodyM.copyWith(color: c.textSecondary),
            ),
          )
        else ...[
          LdCard(
            eyebrow: 'Training day',
            child: _TargetsBlock(targets: targets.trainingDay),
          ),
          const SizedBox(height: LdSpacing.cardGap),
          LdCard(
            eyebrow: 'Rest day',
            child: _TargetsBlock(targets: targets.restDay),
          ),
          const SizedBox(height: LdSpacing.cardGap),
          LdCard(
            eyebrow: 'How this was calculated',
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                _Line('BMR', '${targets.bmr.round()} kcal'),
                _Line('Maintenance (TDEE)', '${targets.tdee.round()} kcal'),
                _Line('Water target', '${targets.waterMl} ml'),
                _Line(
                  'Projected change',
                  '${targets.projectedWeeklyChangeKg >= 0 ? '+' : ''}'
                      '${targets.projectedWeeklyChangeKg.toStringAsFixed(2)} kg / week',
                ),
              ],
            ),
          ),
          if (targets.clamped) ...[
            const SizedBox(height: LdSpacing.cardGap),
            Container(
              padding: const EdgeInsets.all(LdSpacing.s4),
              decoration: BoxDecoration(
                color: Color.lerp(c.surface, c.warning, 0.16),
                borderRadius: BorderRadius.circular(LdRadius.m),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Icon(Icons.shield_rounded, size: 18, color: c.warning),
                      const SizedBox(width: LdSpacing.s2),
                      Text(
                        'Adjusted for safety',
                        style: type.titleM.copyWith(color: c.textPrimary),
                      ),
                    ],
                  ),
                  const SizedBox(height: LdSpacing.s2),
                  Text(
                    _warningText(targets),
                    style: type.bodyS.copyWith(color: c.textSecondary),
                  ),
                ],
              ),
            ),
          ],
        ],
      ],
    );
  }

  static String _warningText(MacroResult result) => result.warnings
      .map(
        (code) => switch (code) {
          'RATE_CLAMPED_TO_SAFE_MAXIMUM' =>
            'Your requested pace was reduced to 1 % of bodyweight per week.',
          'DEFICIT_CLAMPED_TO_SAFE_MAXIMUM' =>
            'Your deficit was reduced to the safe maximum.',
          'KCAL_RAISED_TO_SAFE_MINIMUM' =>
            'Your calorie target was raised to the safe minimum for your sex.',
          _ => code,
        },
      )
      .join(' ');
}

class _TargetsBlock extends StatelessWidget {
  const _TargetsBlock({required this.targets});
  final MacroTargets targets;

  @override
  Widget build(BuildContext context) {
    final c = context.ldColors;
    final type = context.ldType;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          crossAxisAlignment: CrossAxisAlignment.baseline,
          textBaseline: TextBaseline.alphabetic,
          children: [
            Text(
              '${targets.kcal.round()}',
              style: type.displayM.copyWith(color: c.textPrimary),
            ),
            const SizedBox(width: LdSpacing.s2),
            Text('kcal', style: type.bodyM.copyWith(color: c.textTertiary)),
          ],
        ),
        const SizedBox(height: LdSpacing.s3),
        Row(
          children: [
            _Macro('Protein', targets.proteinG, c.protein),
            _Macro('Carbs', targets.carbsG, c.carbs),
            _Macro('Fat', targets.fatG, c.fat),
          ],
        ),
      ],
    );
  }
}

class _Macro extends StatelessWidget {
  const _Macro(this.label, this.grams, this.color);
  final String label;
  final double grams;
  final Color color;

  @override
  Widget build(BuildContext context) {
    final type = context.ldType;
    return Expanded(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            label.toUpperCase(),
            style: type.labelMono.copyWith(color: color),
          ),
          const SizedBox(height: LdSpacing.s1),
          Text(
            '${grams.round()} g',
            style: type.titleL.copyWith(color: context.ldColors.textPrimary),
          ),
        ],
      ),
    );
  }
}

class _Line extends StatelessWidget {
  const _Line(this.label, this.value);
  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    final c = context.ldColors;
    final type = context.ldType;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: LdSpacing.s1),
      child: Row(
        children: [
          Expanded(
            child: Text(label, style: type.bodyM.copyWith(color: c.textSecondary)),
          ),
          Text(value, style: type.bodyM.copyWith(color: c.textPrimary)),
        ],
      ),
    );
  }
}

// ------------------------------------------------------------------ shared --

class _StepScaffold extends StatelessWidget {
  const _StepScaffold({
    required this.title,
    required this.subtitle,
    required this.children,
    required this.onNext,
    required this.nextLabel,
    this.nextLoading = false,
  });

  final String title;
  final String subtitle;
  final List<Widget> children;
  final VoidCallback? onNext;
  final String nextLabel;
  final bool nextLoading;

  @override
  Widget build(BuildContext context) {
    final c = context.ldColors;
    final type = context.ldType;

    return Column(
      children: [
        Expanded(
          child: ListView(
            padding: const EdgeInsets.fromLTRB(
              LdSpacing.s5,
              LdSpacing.s4,
              LdSpacing.s5,
              LdSpacing.s5,
            ),
            children: [
              Text(title, style: type.displayM.copyWith(color: c.textPrimary)),
              const SizedBox(height: LdSpacing.s2),
              Text(
                subtitle,
                style: type.bodyM.copyWith(color: c.textSecondary),
              ),
              const SizedBox(height: LdSpacing.s6),
              ...children,
            ],
          ),
        ),
        Padding(
          padding: const EdgeInsets.fromLTRB(
            LdSpacing.s5,
            LdSpacing.s2,
            LdSpacing.s5,
            LdSpacing.s5,
          ),
          child: LdPrimaryButton(
            label: nextLabel,
            size: LdButtonSize.l,
            loading: nextLoading,
            onPressed: onNext,
          ),
        ),
      ],
    );
  }
}

class _ChoiceRow extends StatelessWidget {
  const _ChoiceRow({
    required this.label,
    required this.selected,
    required this.onTap,
    this.detail,
  });

  final String label;
  final String? detail;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final c = context.ldColors;
    final type = context.ldType;

    return Semantics(
      button: true,
      selected: selected,
      label: label,
      excludeSemantics: true,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(LdRadius.s),
        child: Container(
          constraints: const BoxConstraints(minHeight: LdTouch.min),
          padding: const EdgeInsets.symmetric(vertical: LdSpacing.s2),
          child: Row(
            children: [
              Icon(
                selected
                    ? Icons.radio_button_checked_rounded
                    : Icons.radio_button_unchecked_rounded,
                size: 20,
                color: selected ? c.primary : c.textTertiary,
              ),
              const SizedBox(width: LdSpacing.s3),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      label,
                      style: type.titleM.copyWith(color: c.textPrimary),
                    ),
                    if (detail != null)
                      Text(
                        detail!,
                        style: type.bodyS.copyWith(color: c.textTertiary),
                      ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
