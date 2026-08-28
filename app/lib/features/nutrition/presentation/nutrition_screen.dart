import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';
import 'package:lifedna/core/providers/providers.dart';
import 'package:lifedna/core/router/app_router.dart';
import 'package:lifedna/core/theme/app_theme.dart';
import 'package:lifedna/core/theme/ld_spacing.dart';
import 'package:lifedna/core/widgets/ld_widgets.dart';
import 'package:lifedna/features/nutrition/domain/nutrition_entities.dart';
import 'package:lifedna/features/nutrition/presentation/nutrition_providers.dart';
import 'package:lifedna/shared/enums/enums.dart';
import 'package:lifedna/shared/value_objects/macros.dart';

class NutritionScreen extends ConsumerWidget {
  const NutritionScreen({super.key});

  static const _slots = [
    MealSlot.breakfast,
    MealSlot.lunch,
    MealSlot.dinner,
    MealSlot.snack,
  ];

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final c = context.ldColors;
    final logsAsync = ref.watch(nutritionLogsProvider);

    return Scaffold(
      appBar: AppBar(
        title: const Text('Nutrition'),
        actions: [
          IconButton(
            icon: const Icon(Icons.history_rounded),
            tooltip: 'Meal history',
            onPressed: () => _showHistory(context, ref),
          ),
        ],
      ),
      body: LdAsyncView(
        value: logsAsync,
        onRetry: () => ref.invalidate(nutritionLogsProvider),
        errorContext: 'Nutrition',
        data: (_) {
          final nutrition = ref.watch(todayNutritionProvider);
          final targets = ref.watch(macroTargetsProvider);
          final waterTarget = ref.watch(waterTargetProvider);

          return ListView(
            padding: const EdgeInsets.fromLTRB(
              LdSpacing.s4,
              LdSpacing.s3,
              LdSpacing.s4,
              LdSpacing.scrollBottom,
            ),
            children: [
              LdCard(
                eyebrow: 'Daily goal',
                child: Column(
                  children: [
                    LdStatRow(
                      label: 'calories',
                      value: '${_int(nutrition.totals.kcal)} / '
                          '${_int(targets.kcal)} kcal',
                      progress: targets.kcal <= 0
                          ? 0
                          : nutrition.totals.kcal / targets.kcal,
                      color: c.calories,
                    ),
                    LdStatRow(
                      label: 'protein',
                      value: '${_int(nutrition.totals.proteinG)} / '
                          '${_int(targets.proteinG)} g',
                      progress: targets.proteinG <= 0
                          ? 0
                          : nutrition.totals.proteinG / targets.proteinG,
                      color: c.protein,
                    ),
                    LdStatRow(
                      label: 'carbs',
                      value: '${_int(nutrition.totals.carbsG)} / '
                          '${_int(targets.carbsG)} g',
                      progress: targets.carbsG <= 0
                          ? 0
                          : nutrition.totals.carbsG / targets.carbsG,
                      color: c.carbs,
                    ),
                    LdStatRow(
                      label: 'fat',
                      value: '${_int(nutrition.totals.fatG)} / '
                          '${_int(targets.fatG)} g',
                      progress: targets.fatG <= 0
                          ? 0
                          : nutrition.totals.fatG / targets.fatG,
                      color: c.fat,
                    ),
                    const SizedBox(height: LdSpacing.s2),
                    LdStatRow(
                      label: 'water',
                      value: '${nutrition.waterMl} / $waterTarget ml',
                      progress: waterTarget <= 0
                          ? 0
                          : nutrition.waterMl / waterTarget,
                      color: c.water,
                    ),
                    Row(
                      children: [
                        for (final ml in [250, 500, 750]) ...[
                          Expanded(
                            child: LdPrimaryButton(
                              label: '+$ml',
                              size: LdButtonSize.s,
                              variant: LdButtonVariant.secondary,
                              onPressed: () async {
                                final result = await ref
                                    .read(nutritionRepositoryProvider)
                                    .logWater(ml);
                                if (!context.mounted) return;
                                final failure = result.failureOrNull;
                                if (failure != null) {
                                  showFailureSnack(context, failure);
                                }
                              },
                            ),
                          ),
                          if (ml != 750) const SizedBox(width: LdSpacing.s2),
                        ],
                      ],
                    ),
                  ],
                ),
              ),
              const SizedBox(height: LdSpacing.s2),
              for (final slot in _slots)
                _SlotSection(
                  slot: slot,
                  entries: nutrition.forSlot(slot),
                  totals: nutrition.totalsForSlot(slot),
                ),
              if (nutrition.foodEntries.isEmpty) ...[
                const SizedBox(height: LdSpacing.s5),
                LdEmptyState(
                  icon: Icons.restaurant_rounded,
                  headline: 'Nothing logged yet today',
                  body: 'Add your first meal — it takes about ten seconds.',
                  actionLabel: 'Log breakfast',
                  onAction: () => context.push(
                    '${Routes.addFood}?slot=${MealSlot.breakfast.wire}',
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
          context.push('${Routes.addFood}?slot=${slot.wire}');
        },
        icon: const Icon(Icons.add_rounded),
        label: const Text('Log food'),
      ),
    );
  }

  static void _showHistory(BuildContext context, WidgetRef ref) {
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      builder: (_) => const _HistorySheet(),
    );
  }

  static String _int(double v) =>
      NumberFormat.decimalPattern().format(v.round());
}

class _SlotSection extends ConsumerWidget {
  const _SlotSection({
    required this.slot,
    required this.entries,
    required this.totals,
  });

  final MealSlot slot;
  final List<NutritionLog> entries;
  final Macros totals;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final c = context.ldColors;
    final type = context.ldType;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        LdSectionHeader(
          title: slot.label,
          trailing: Text(
            entries.isEmpty
                ? 'not logged'
                : '${totals.kcal.round()} kcal · '
                    '${totals.proteinG.round()} g P',
            style: type.bodyS.copyWith(
              color: entries.isEmpty ? c.accent : c.textSecondary,
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
            onDismissed: (_) async {
              await ref
                  .read(nutritionRepositoryProvider)
                  .deleteLog(entry.id);
              if (context.mounted) {
                showSuccessSnack(context, '${entry.foodName} removed');
              }
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
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: type.bodyM.copyWith(color: c.textPrimary),
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
        LdPrimaryButton(
          label: '+ Add to ${slot.label.toLowerCase()}',
          size: LdButtonSize.s,
          variant: LdButtonVariant.ghost,
          onPressed: () =>
              context.push('${Routes.addFood}?slot=${slot.wire}'),
        ),
      ],
    );
  }
}

class _HistorySheet extends ConsumerWidget {
  const _HistorySheet();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final c = context.ldColors;
    final type = context.ldType;
    final history = ref.watch(nutritionHistoryProvider);

    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(
          LdSpacing.s4,
          0,
          LdSpacing.s4,
          LdSpacing.s5,
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Meal history',
              style: type.headlineM.copyWith(color: c.textPrimary),
            ),
            const SizedBox(height: LdSpacing.s4),
            if (history.isEmpty)
              Text(
                'Nothing logged yet.',
                style: type.bodyM.copyWith(color: c.textTertiary),
              )
            else
              ConstrainedBox(
                constraints: BoxConstraints(
                  maxHeight: MediaQuery.of(context).size.height * 0.55,
                ),
                child: ListView.builder(
                  shrinkWrap: true,
                  itemCount: history.length,
                  itemBuilder: (context, index) {
                    final day = history[index];
                    return ListTile(
                      contentPadding: EdgeInsets.zero,
                      title: Text(
                        day.localDate,
                        style: type.titleM.copyWith(color: c.textPrimary),
                      ),
                      subtitle: Text(
                        '${day.totals.kcal.round()} kcal · '
                        '${day.totals.proteinG.round()} g protein · '
                        '${day.entries} item${day.entries == 1 ? '' : 's'}',
                        style: type.bodyS.copyWith(color: c.textSecondary),
                      ),
                    );
                  },
                ),
              ),
          ],
        ),
      ),
    );
  }
}
