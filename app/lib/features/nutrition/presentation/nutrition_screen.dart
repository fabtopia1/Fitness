import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';
import 'package:lifedna/core/providers/app_providers.dart';
import 'package:lifedna/core/router/app_router.dart';
import 'package:lifedna/core/theme/app_theme.dart';
import 'package:lifedna/core/theme/ld_spacing.dart';
import 'package:lifedna/core/widgets/ld_widgets.dart';
import 'package:lifedna/features/nutrition/domain/entities/food.dart';
import 'package:lifedna/features/nutrition/domain/repositories/nutrition_repository.dart';
import 'package:lifedna/shared/enums/enums.dart';
import 'package:lifedna/shared/value_objects/macros.dart';

/// The Nutrition Center (docs/06 Screen 02).
class NutritionScreen extends ConsumerWidget {
  const NutritionScreen({super.key});

  static const _slots = [
    MealSlot.breakfast,
    MealSlot.lunch,
    MealSlot.preWorkout,
    MealSlot.postWorkout,
    MealSlot.beforeBed,
  ];

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final c = context.ldColors;
    final async = ref.watch(dailyNutritionProvider);

    return Scaffold(
      appBar: AppBar(title: const Text('Nutrition')),
      body: async.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (e, _) => LdEmptyState(
          icon: Icons.cloud_off_rounded,
          headline: "Couldn't load today",
          body: 'Your entries are safe on this device.',
          actionLabel: 'Retry',
          onAction: () => ref.invalidate(dailyNutritionProvider),
        ),
        data: (nutrition) {
          final targets = ref.watch(macroTargetsProvider(nutrition.dayType));
          final totals = nutrition.totals;

          return ListView(
            padding: const EdgeInsets.fromLTRB(
              LdSpacing.s4,
              LdSpacing.s2,
              LdSpacing.s4,
              LdSpacing.scrollBottom,
            ),
            children: [
              _TargetsCard(totals: totals, targets: targets, dayType: nutrition.dayType),
              const SizedBox(height: LdSpacing.s2),
              for (final slot in _slots)
                _MealSlotSection(
                  slot: slot,
                  entries: nutrition.forSlot(slot),
                  totals: nutrition.totalsForSlot(slot),
                  onAdd: () => context.push('${Routes.addFood}/${slot.wire}'),
                  onDelete: (id) => ref
                      .read(nutritionRepositoryProvider)
                      .deleteEntry(id),
                ),
              const SizedBox(height: LdSpacing.s4),
              _WaterCard(waterMl: nutrition.waterMl),
              if (nutrition.entries.isEmpty) ...[
                const SizedBox(height: LdSpacing.s6),
                LdEmptyState(
                  icon: Icons.restaurant_rounded,
                  headline: 'Nothing logged yet today.',
                  body: 'Your first meal takes about 12 seconds.',
                  actionLabel: 'Log breakfast',
                  onAction: () => context.push(
                    '${Routes.addFood}/${MealSlot.breakfast.wire}',
                  ),
                ),
              ],
            ],
          );
        },
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () {
          final slot = MealSlot.forTime(ref.read(clockProvider)());
          context.push('${Routes.addFood}/${slot.wire}');
        },
        backgroundColor: c.primary,
        foregroundColor: c.textOnPrimary,
        icon: const Icon(Icons.add_rounded),
        label: const Text('Log'),
      ),
    );
  }
}

class _TargetsCard extends StatelessWidget {
  const _TargetsCard({
    required this.totals,
    required this.targets,
    required this.dayType,
  });

  final Macros totals;
  final MacroTargets targets;
  final DayType dayType;

  @override
  Widget build(BuildContext context) {
    final c = context.ldColors;
    final type = context.ldType;
    final progress = targets.progress(totals);
    final debt = targets.proteinDebt(totals);

    return LdCard(
      eyebrow: dayType == DayType.training ? 'Training day' : 'Rest day',
      trailing: Text(
        '${_int(totals.kcal)} / ${_int(targets.kcal)} kcal',
        style: type.titleM.copyWith(color: c.textPrimary),
      ),
      child: Column(
        children: [
          LdStatRow(
            label: 'calories',
            value: '${_int(totals.kcal)} / ${_int(targets.kcal)}',
            progress: progress.kcal,
            color: c.calories,
          ),
          LdStatRow(
            label: 'protein',
            value: '${_int(totals.proteinG)} / ${_int(targets.proteinG)} g',
            progress: progress.protein,
            color: c.protein,
            trailing: debt > 0 ? '−${debt.round()}' : null,
            trailingDirection: debt > 0 ? c.danger : c.success,
          ),
          LdStatRow(
            label: 'carbs',
            value: '${_int(totals.carbsG)} / ${_int(targets.carbsG)} g',
            progress: progress.carbs,
            color: c.carbs,
          ),
          LdStatRow(
            label: 'fat',
            value: '${_int(totals.fatG)} / ${_int(targets.fatG)} g',
            progress: progress.fat,
            color: c.fat,
          ),
          if (debt > 0) ...[
            const SizedBox(height: LdSpacing.s2),
            Row(
              children: [
                Icon(Icons.info_outline_rounded, size: 16, color: c.accent),
                const SizedBox(width: LdSpacing.s2),
                Expanded(
                  child: Text(
                    'Protein floor is ${targets.proteinFloorG.round()} g — the '
                    'minimum that protects lean mass in a deficit.',
                    style: type.bodyS.copyWith(color: c.textSecondary),
                  ),
                ),
              ],
            ),
          ],
        ],
      ),
    );
  }

  static String _int(double v) =>
      NumberFormat.decimalPattern().format(v.round());
}

class _MealSlotSection extends StatelessWidget {
  const _MealSlotSection({
    required this.slot,
    required this.entries,
    required this.totals,
    required this.onAdd,
    required this.onDelete,
  });

  final MealSlot slot;
  final List<NutritionEntry> entries;
  final Macros totals;
  final VoidCallback onAdd;
  final void Function(String entryId) onDelete;

  @override
  Widget build(BuildContext context) {
    final c = context.ldColors;
    final type = context.ldType;
    final logged = entries.isNotEmpty;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        LdSectionHeader(
          title: '${slot.label} · '
              '${slot.defaultHour.toString().padLeft(2, '0')}:'
              '${slot.defaultMinute.toString().padLeft(2, '0')}',
          trailing: Text(
            logged
                ? '${totals.kcal.round()} kcal · ${totals.proteinG.round()} g P'
                : 'not logged',
            style: type.bodyS.copyWith(
              color: logged ? c.textSecondary : c.accent,
            ),
          ),
        ),
        for (final entry in entries)
          Dismissible(
            key: ValueKey(entry.id),
            direction: DismissDirection.endToStart,
            background: Container(
              alignment: Alignment.centerRight,
              padding: const EdgeInsets.only(right: LdSpacing.s4),
              decoration: BoxDecoration(
                color: Color.lerp(c.surface, c.danger, 0.25),
                borderRadius: BorderRadius.circular(LdRadius.s),
              ),
              child: Icon(Icons.delete_outline_rounded, color: c.danger),
            ),
            onDismissed: (_) {
              onDelete(entry.id);
              ScaffoldMessenger.of(context).showSnackBar(
                SnackBar(content: Text('${entry.foodName} removed')),
              );
            },
            child: Padding(
              padding: const EdgeInsets.only(bottom: LdSpacing.s2),
              child: Row(
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          entry.foodName,
                          style: type.bodyM.copyWith(color: c.textPrimary),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                        Text(
                          entry.portionLabel,
                          style: type.caption.copyWith(color: c.textTertiary),
                        ),
                      ],
                    ),
                  ),
                  Text(
                    '${entry.macros.kcal.round()} · '
                    '${entry.macros.proteinG.round()} g P',
                    style: type.bodyS.copyWith(color: c.textSecondary),
                  ),
                ],
              ),
            ),
          ),
        const SizedBox(height: LdSpacing.s1),
        LdPrimaryButton(
          label: '+ Add to ${slot.label.toLowerCase()}',
          size: LdButtonSize.s,
          variant: LdButtonVariant.ghost,
          onPressed: onAdd,
        ),
      ],
    );
  }
}

class _WaterCard extends ConsumerWidget {
  const _WaterCard({required this.waterMl});
  final int waterMl;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final c = context.ldColors;
    final target = ref.watch(macroResultProvider).waterMl;
    final repo = ref.read(nutritionRepositoryProvider);

    return LdCard(
      eyebrow: 'Water',
      accentColor: c.water,
      child: Column(
        children: [
          LdStatRow(
            label: 'hydration',
            value: '$waterMl / $target ml',
            progress: target == 0 ? 0 : waterMl / target,
            color: c.water,
          ),
          const SizedBox(height: LdSpacing.s2),
          Row(
            children: [
              for (final ml in [250, 500, 750]) ...[
                Expanded(
                  child: LdPrimaryButton(
                    label: '+$ml',
                    size: LdButtonSize.s,
                    variant: LdButtonVariant.secondary,
                    onPressed: () => repo.logWater(ml),
                  ),
                ),
                if (ml != 750) const SizedBox(width: LdSpacing.s2),
              ],
            ],
          ),
        ],
      ),
    );
  }
}
