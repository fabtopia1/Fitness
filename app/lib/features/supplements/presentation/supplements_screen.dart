import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:lifedna/core/providers/providers.dart';
import 'package:lifedna/core/theme/app_theme.dart';
import 'package:lifedna/core/theme/ld_spacing.dart';
import 'package:lifedna/core/widgets/ld_widgets.dart';
import 'package:lifedna/features/supplements/domain/supplement_entities.dart';
import 'package:lifedna/features/supplements/presentation/supplement_editor_sheet.dart';
import 'package:lifedna/features/supplements/presentation/supplement_providers.dart';

class SupplementsScreen extends ConsumerWidget {
  const SupplementsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final c = context.ldColors;
    final type = context.ldType;
    final async = ref.watch(supplementsProvider);

    return Scaffold(
      appBar: AppBar(title: const Text('Supplements')),
      body: LdAsyncView(
        value: async,
        onRetry: () => ref.invalidate(supplementsProvider),
        errorContext: 'Supplements',
        isEmpty: (list) => list.isEmpty,
        empty: LdEmptyState(
          icon: Icons.medication_rounded,
          headline: 'No supplements yet',
          body:
              'Add what you take and LifeDNA will remind you at the right '
              'time each day.',
          actionLabel: 'Add the basics',
          onAction: () =>
              ref.read(supplementRepositoryProvider).seedStarterStack(),
          secondaryActionLabel: 'Add my own',
          onSecondaryAction: () => _edit(context, null),
        ),
        data: (all) {
          final today = ref.watch(todaySupplementsProvider);
          final compliance = ref.watch(supplementComplianceProvider);
          final taken = today.where((e) => e.taken).length;

          return ListView(
            padding: const EdgeInsets.fromLTRB(
              LdSpacing.s4,
              LdSpacing.s3,
              LdSpacing.s4,
              LdSpacing.scrollBottom,
            ),
            children: [
              LdCard(
                eyebrow: 'Today',
                trailing: Text(
                  '$taken of ${today.length}',
                  style: type.titleM.copyWith(color: c.textPrimary),
                ),
                child: Column(
                  children: [
                    LdStatRow(
                      label: 'taken today',
                      value: '$taken / ${today.length}',
                      progress: today.isEmpty ? 0 : taken / today.length,
                      color: c.secondary,
                    ),
                    const SizedBox(height: LdSpacing.s2),
                    LdStatRow(
                      label: '30-day compliance',
                      value: compliance.label,
                      progress: compliance.percent / 100,
                      color: c.primary,
                    ),
                  ],
                ),
              ),
              if (today.isEmpty)
                Padding(
                  padding: const EdgeInsets.only(top: LdSpacing.s4),
                  child: Text(
                    'Nothing scheduled for today.',
                    style: type.bodyS.copyWith(color: c.textTertiary),
                  ),
                ),
              const LdSectionHeader(title: "Today's doses"),
              for (final entry in today)
                _DoseTile(
                  supplement: entry.supplement,
                  taken: entry.taken,
                  onToggle: () async {
                    final repository = ref.read(supplementRepositoryProvider);
                    if (entry.taken) {
                      await repository.undoDose(entry.supplement.id);
                    } else {
                      await repository.logDose(entry.supplement);
                    }
                  },
                  onEdit: () => _edit(context, entry.supplement),
                ),
              const LdSectionHeader(title: 'My stack'),
              for (final supplement in all)
                ListTile(
                  contentPadding: EdgeInsets.zero,
                  title: Text(
                    supplement.name,
                    style: type.titleM.copyWith(color: c.textPrimary),
                  ),
                  subtitle: Text(
                    '${supplement.doseLabel} · ${supplement.frequency.label}'
                    '${supplement.reminderEnabled ? ' · ${supplement.reminderLabel}' : ''}',
                    style: type.bodyS.copyWith(color: c.textTertiary),
                  ),
                  trailing: IconButton(
                    icon: const Icon(Icons.edit_outlined),
                    onPressed: () => _edit(context, supplement),
                  ),
                ),
            ],
          );
        },
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () => _edit(context, null),
        icon: const Icon(Icons.add_rounded),
        label: const Text('Add'),
      ),
    );
  }

  static Future<void> _edit(BuildContext context, Supplement? existing) =>
      showModalBottomSheet<void>(
        context: context,
        isScrollControlled: true,
        builder: (_) => SupplementEditorSheet(existing: existing),
      );
}

class _DoseTile extends StatelessWidget {
  const _DoseTile({
    required this.supplement,
    required this.taken,
    required this.onToggle,
    required this.onEdit,
  });

  final Supplement supplement;
  final bool taken;
  final VoidCallback onToggle;
  final VoidCallback onEdit;

  @override
  Widget build(BuildContext context) {
    final c = context.ldColors;
    final type = context.ldType;

    return Padding(
      padding: const EdgeInsets.only(bottom: LdSpacing.s2),
      child: LdCard(
        padding: const EdgeInsets.all(LdSpacing.s3),
        onTap: onToggle,
        child: Row(
          children: [
            Icon(
              taken
                  ? Icons.check_circle_rounded
                  : Icons.radio_button_unchecked_rounded,
              color: taken ? c.success : c.textTertiary,
            ),
            const SizedBox(width: LdSpacing.s3),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    supplement.name,
                    style: type.titleM.copyWith(
                      color: taken ? c.textSecondary : c.textPrimary,
                      decoration: taken ? TextDecoration.lineThrough : null,
                    ),
                  ),
                  Text(
                    '${supplement.doseLabel} · ${supplement.reminderLabel}',
                    style: type.bodyS.copyWith(color: c.textTertiary),
                  ),
                ],
              ),
            ),
            IconButton(icon: const Icon(Icons.tune_rounded), onPressed: onEdit),
          ],
        ),
      ),
    );
  }
}
