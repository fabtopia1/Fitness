import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';
import 'package:lifedna/core/engines/priority_engine.dart';
import 'package:lifedna/core/engines/recovery_engine.dart';
import 'package:lifedna/core/providers/app_providers.dart';
import 'package:lifedna/core/router/app_router.dart';
import 'package:lifedna/core/theme/app_theme.dart';
import 'package:lifedna/core/theme/ld_spacing.dart';
import 'package:lifedna/core/widgets/ld_widgets.dart';
import 'package:lifedna/features/nutrition/domain/repositories/nutrition_repository.dart';
import 'package:lifedna/shared/enums/enums.dart';

/// The dashboard (docs/06 Screen 01).
///
/// Structure follows the One UI split: identity and context in the upper third,
/// everything the thumb touches below. The Next Action card holds the visual
/// apex — anything on this screen that does not help the user decide what to do
/// next is a candidate for deletion.
class DashboardScreen extends ConsumerWidget {
  const DashboardScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final c = context.ldColors;
    final type = context.ldType;
    final nutritionAsync = ref.watch(dailyNutritionProvider);
    final profile = ref.watch(userProfileProvider);
    final now = ref.watch(clockProvider)();

    return Scaffold(
      body: SafeArea(
        bottom: false,
        child: RefreshIndicator(
          onRefresh: () async => ref.invalidate(dailyNutritionProvider),
          child: nutritionAsync.when(
            loading: () => const _DashboardSkeleton(),
            error: (e, _) => LdEmptyState(
              icon: Icons.cloud_off_rounded,
              headline: "Couldn't load today",
              body: 'Your data is safe on this device. Pull down to retry.',
              actionLabel: 'Retry',
              onAction: () => ref.invalidate(dailyNutritionProvider),
            ),
            data: (nutrition) => ListView(
              padding: const EdgeInsets.fromLTRB(
                LdSpacing.s4,
                LdSpacing.s3,
                LdSpacing.s4,
                LdSpacing.scrollBottom,
              ),
              children: [
                _Greeting(name: profile.displayName, now: now, dayType: nutrition.dayType),
                const SizedBox(height: LdSpacing.s5),
                const _NextActionSection(),
                const SizedBox(height: LdSpacing.cardGap),
                _FuelCard(nutrition: nutrition),
                const SizedBox(height: LdSpacing.cardGap),
                const _RecoveryAndSleepRow(),
                const SizedBox(height: LdSpacing.cardGap),
                const _TrainingCard(),
                const SizedBox(height: LdSpacing.cardGap),
                const _SupplementsCard(),
                const SizedBox(height: LdSpacing.s6),
                Center(
                  child: Text(
                    'Recovery ${RecoveryEngine.version} · '
                    'targets ${ref.watch(macroResultProvider).engineVersion}',
                    style: type.labelMono.copyWith(color: c.textTertiary),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _Greeting extends StatelessWidget {
  const _Greeting({
    required this.name,
    required this.now,
    required this.dayType,
  });

  final String name;
  final DateTime now;
  final DayType dayType;

  String get _salutation {
    if (now.hour < 12) return 'Good morning';
    if (now.hour < 18) return 'Good afternoon';
    return 'Good evening';
  }

  @override
  Widget build(BuildContext context) {
    final c = context.ldColors;
    final type = context.ldType;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          '$_salutation, $name',
          style: type.headlineL.copyWith(color: c.textPrimary),
        ),
        const SizedBox(height: LdSpacing.s1),
        Text(
          '${DateFormat('EEEE d MMMM').format(now).toUpperCase()} · '
          '${dayType == DayType.training ? 'TRAINING DAY' : 'REST DAY'}',
          style: type.labelMono.copyWith(color: c.textTertiary),
        ),
      ],
    );
  }
}

class _NextActionSection extends ConsumerWidget {
  const _NextActionSection();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final action = ref.watch(nextActionProvider);
    if (action == null) return const SizedBox.shrink();

    return LdNextActionCard(
      action: action,
      onAct: () {
        // Deep links are resolved by the router, so a notification tap and an
        // in-app tap land in exactly the same place.
        final target = action.deeplink.split('?').first;
        if (action.domain == ActionDomain.nutrition) {
          final slot = Uri.parse(action.deeplink).queryParameters['slot'];
          context.push('${Routes.addFood}/${slot ?? 'snack'}');
        } else if (target.startsWith('/train')) {
          context.go(Routes.train);
        } else {
          context.go(Routes.nutrition);
        }
      },
      onWhy: action.evidence.isEmpty
          ? null
          : () => LdProvenanceSheet.show(
                context,
                title: action.title,
                evidence: action.evidence,
                engineVersion: PriorityEngine.version,
              ),
    );
  }
}

class _FuelCard extends ConsumerWidget {
  const _FuelCard({required this.nutrition});
  final DailyNutrition nutrition;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final c = context.ldColors;
    final type = context.ldType;
    final targets = ref.watch(macroTargetsProvider(nutrition.dayType));
    final waterTarget = ref.watch(macroResultProvider).waterMl;
    final totals = nutrition.totals;

    return LdCard(
      eyebrow: "Today's fuel",
      trailing: Text(
        '${_int(totals.kcal)} / ${_int(targets.kcal)} kcal',
        style: type.bodyS.copyWith(color: c.textSecondary),
      ),
      child: Column(
        children: [
          Center(
            child: LdProgressRing(
              value: totals.kcal,
              target: targets.kcal,
              label: 'kcal',
              unit: 'kcal',
              color: c.calories,
              size: LdRingSize.xl,
            ),
          ),
          const SizedBox(height: LdSpacing.s5),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceEvenly,
            children: [
              LdProgressRing(
                value: totals.proteinG,
                target: targets.proteinG,
                label: 'protein',
                unit: 'g',
                color: c.protein,
              ),
              LdProgressRing(
                value: totals.carbsG,
                target: targets.carbsG,
                label: 'carbs',
                unit: 'g',
                color: c.carbs,
              ),
              LdProgressRing(
                value: totals.fatG,
                target: targets.fatG,
                label: 'fat',
                unit: 'g',
                color: c.fat,
              ),
            ],
          ),
          const SizedBox(height: LdSpacing.s5),
          Divider(color: c.border),
          const SizedBox(height: LdSpacing.s3),
          Row(
            children: [
              Icon(Icons.water_drop_rounded, size: 18, color: c.water),
              const SizedBox(width: LdSpacing.s2),
              Expanded(
                child: Text(
                  '${_int(nutrition.waterMl.toDouble())} / '
                  '${_int(waterTarget.toDouble())} ml',
                  style: type.titleM.copyWith(color: c.textPrimary),
                ),
              ),
              LdPrimaryButton(
                label: '+250 ml',
                size: LdButtonSize.s,
                variant: LdButtonVariant.secondary,
                expand: false,
                onPressed: () => ref
                    .read(nutritionRepositoryProvider)
                    .logWater(250),
              ),
            ],
          ),
        ],
      ),
    );
  }

  static String _int(double v) => NumberFormat.decimalPattern().format(v.round());
}

class _RecoveryAndSleepRow extends ConsumerWidget {
  const _RecoveryAndSleepRow();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final c = context.ldColors;
    final recovery = ref.watch(recoveryProvider);

    if (!recovery.isSufficient) {
      return LdCard(
        eyebrow: 'Recovery',
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('— —', style: context.ldType.displayM.copyWith(color: c.textTertiary)),
            const SizedBox(height: LdSpacing.s2),
            Text(recovery.detail, style: context.ldType.bodyS.copyWith(color: c.textSecondary)),
          ],
        ),
      );
    }

    final score = recovery.recoveryScore!;
    final band = recovery.band;

    return Row(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Expanded(
          child: LdMetricTile(
            label: 'Recovery',
            value: '$score',
            accentColor: c.recoveryBandColor(score),
            delta: band.label,
            deltaDirection: switch (band) {
              RecoveryBand.high => DeltaDirection.good,
              RecoveryBand.moderate => DeltaDirection.neutral,
              _ => DeltaDirection.bad,
            },
            footnote: 'Readiness ${recovery.readinessScore}',
            onTap: () => LdProvenanceSheet.show(
              context,
              title: 'Recovery $score',
              evidence: [
                for (final comp in recovery.components)
                  (
                    label: '${comp.name} (${(comp.weight * 100).round()} %)',
                    value: comp.available ? '${comp.score}' : 'unavailable',
                  ),
                (label: 'Readiness', value: '${recovery.readinessScore}'),
              ],
              engineVersion: recovery.engineVersion,
            ),
          ),
        ),
        const SizedBox(width: LdSpacing.cardGap),
        Expanded(
          child: LdMetricTile(
            label: 'Sleep',
            value: '7h 11m',
            accentColor: c.secondary,
            delta: 'Score ${recovery.sleepScore}',
            deltaDirection: DeltaDirection.neutral,
            footnote: '23:15 → 06:26',
          ),
        ),
      ],
    );
  }
}

class _TrainingCard extends ConsumerWidget {
  const _TrainingCard();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final c = context.ldColors;
    final type = context.ldType;
    final plan = ref.watch(todaysPlanProvider);
    final session = ref.watch(activeSessionProvider).valueOrNull;
    final isLive = session?.status == SessionStatus.inProgress;

    return LdCard(
      eyebrow: "Today's training",
      accentColor: c.primary,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            plan.template?.name ?? '${plan.label} — rest or optional cardio',
            style: type.titleL.copyWith(color: c.textPrimary),
          ),
          const SizedBox(height: LdSpacing.s2),
          Text(
            plan.template == null
                ? 'No resistance session scheduled today.'
                : '${plan.template!.totalWorkingSets} working sets · '
                    '~${plan.template!.estimatedMinutes} min',
            style: type.bodyS.copyWith(color: c.textSecondary),
          ),
          const SizedBox(height: LdSpacing.s4),
          LdPrimaryButton(
            label: isLive
                ? 'Resume workout'
                : plan.template == null
                    ? 'Start a session'
                    : 'Start ${plan.label}',
            size: LdButtonSize.l,
            onPressed: () => context.go(Routes.train),
          ),
        ],
      ),
    );
  }
}

class _SupplementsCard extends StatelessWidget {
  const _SupplementsCard();

  @override
  Widget build(BuildContext context) {
    final c = context.ldColors;
    final type = context.ldType;

    const taken = <String>['Multivitamin', 'Vitamin D3', 'Omega-3', 'Creatine'];
    const pending = 'Magnesium glycinate';

    return LdCard(
      eyebrow: 'Supplements',
      trailing: Text(
        '${taken.length} / ${taken.length + 1}',
        style: type.bodyS.copyWith(color: c.textSecondary),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Wrap(
            spacing: LdSpacing.s2,
            runSpacing: LdSpacing.s2,
            children: [
              for (final s in taken)
                _Pill(label: s, icon: Icons.check_rounded, color: c.success),
              _Pill(
                label: '$pending · 22:30',
                icon: Icons.schedule_rounded,
                color: c.accent,
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _Pill extends StatelessWidget {
  const _Pill({required this.label, required this.icon, required this.color});
  final String label;
  final IconData icon;
  final Color color;

  @override
  Widget build(BuildContext context) {
    final c = context.ldColors;
    return Container(
      padding: const EdgeInsets.symmetric(
        horizontal: LdSpacing.s3,
        vertical: LdSpacing.s2,
      ),
      decoration: BoxDecoration(
        color: c.surfaceElevated,
        borderRadius: BorderRadius.circular(LdRadius.full),
        border: Border.all(color: c.border),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 14, color: color),
          const SizedBox(width: LdSpacing.s2),
          Text(
            label,
            style: context.ldType.bodyS.copyWith(color: c.textSecondary),
          ),
        ],
      ),
    );
  }
}

/// Skeletons match the final layout's heights exactly, so nothing shifts when
/// data arrives (docs/04 §8.9).
class _DashboardSkeleton extends StatelessWidget {
  const _DashboardSkeleton();

  @override
  Widget build(BuildContext context) {
    final c = context.ldColors;
    Widget block(double height) => Container(
          height: height,
          margin: const EdgeInsets.only(bottom: LdSpacing.cardGap),
          decoration: BoxDecoration(
            color: c.surface,
            borderRadius: BorderRadius.circular(LdRadius.m),
            border: Border.all(color: c.border),
          ),
        );

    return ListView(
      padding: const EdgeInsets.all(LdSpacing.s4),
      children: [block(64), block(168), block(360), block(120), block(180)],
    );
  }
}
