import 'package:flutter/material.dart';
import 'package:lifedna/core/engines/priority_engine.dart';
import 'package:lifedna/core/theme/app_theme.dart';
import 'package:lifedna/core/theme/ld_spacing.dart';
import 'package:lifedna/core/widgets/ld_card.dart';
import 'package:lifedna/core/widgets/ld_primary_button.dart';

/// The most important component in the product (docs/04 §8.5).
///
/// Everything else on the dashboard is reference material. This card is the
/// product's actual output: one imperative action, its reason, and the
/// evidence behind it.
///
/// The "Why?" affordance is not optional. An action the user cannot interrogate
/// is an action they will eventually stop trusting.
class LdNextActionCard extends StatelessWidget {
  const LdNextActionCard({
    required this.action,
    required this.onAct,
    super.key,
    this.onWhy,
  });

  final NextAction action;
  final VoidCallback onAct;
  final VoidCallback? onWhy;

  @override
  Widget build(BuildContext context) {
    final c = context.ldColors;
    final type = context.ldType;
    final accent = _domainColor(context, action.domain);
    final showWhy = action.evidence.isNotEmpty && onWhy != null;

    return LdCard(
      variant: LdCardVariant.elevated,
      eyebrow: 'Next',
      accentColor: accent,
      semanticLabel: 'Next action: ${action.title}. ${action.subtitle}',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Icon(_domainIcon(action.domain), size: 20, color: accent),
              const SizedBox(width: LdSpacing.s2),
              Expanded(
                child: Text(
                  action.title,
                  style: type.titleL.copyWith(color: c.textPrimary),
                  maxLines: 3,
                ),
              ),
            ],
          ),
          const SizedBox(height: LdSpacing.s2),
          Text(
            action.subtitle,
            style: type.bodyS.copyWith(color: c.textSecondary),
            maxLines: 2,
          ),
          const SizedBox(height: LdSpacing.s4),
          Row(
            children: [
              Expanded(
                flex: showWhy ? 3 : 1,
                child: LdPrimaryButton(
                  label: action.actionLabel,
                  onPressed: onAct,
                ),
              ),
              if (showWhy) ...[
                const SizedBox(width: LdSpacing.s3),
                Expanded(
                  flex: 2,
                  child: LdPrimaryButton(
                    label: 'Why?',
                    onPressed: onWhy,
                    variant: LdButtonVariant.ghost,
                  ),
                ),
              ],
            ],
          ),
        ],
      ),
    );
  }

  static Color _domainColor(BuildContext context, ActionDomain d) {
    final c = context.ldColors;
    return switch (d) {
      ActionDomain.nutrition => c.protein,
      ActionDomain.hydration => c.water,
      ActionDomain.training => c.primary,
      ActionDomain.recovery => c.secondary,
      ActionDomain.supplement => c.accent,
      ActionDomain.schedule => c.info,
      ActionDomain.task => c.textSecondary,
      ActionDomain.insight => c.accent,
      ActionDomain.setup => c.primary,
    };
  }

  static IconData _domainIcon(ActionDomain d) => switch (d) {
        ActionDomain.nutrition => Icons.restaurant_rounded,
        ActionDomain.hydration => Icons.water_drop_rounded,
        ActionDomain.training => Icons.fitness_center_rounded,
        ActionDomain.recovery => Icons.favorite_rounded,
        ActionDomain.supplement => Icons.medication_rounded,
        ActionDomain.schedule => Icons.calendar_month_rounded,
        ActionDomain.task => Icons.checklist_rounded,
        ActionDomain.insight => Icons.lightbulb_rounded,
        ActionDomain.setup => Icons.link_rounded,
      };
}

/// Renders the evidence behind an action or an insight (docs/04 §8, docs/05 Flow 8).
///
/// This sheet is what makes "explainable" a property of the product rather than
/// a claim about it.
class LdProvenanceSheet extends StatelessWidget {
  const LdProvenanceSheet({
    required this.title,
    required this.evidence,
    super.key,
    this.rule,
    this.window,
    this.engineVersion,
    this.confidence,
  });

  final String title;
  final List<({String label, String value})> evidence;
  final String? rule;
  final String? window;
  final String? engineVersion;
  final double? confidence;

  static Future<void> show(
    BuildContext context, {
    required String title,
    required List<({String label, String value})> evidence,
    String? rule,
    String? window,
    String? engineVersion,
    double? confidence,
  }) =>
      showModalBottomSheet<void>(
        context: context,
        isScrollControlled: true,
        builder: (_) => LdProvenanceSheet(
          title: title,
          evidence: evidence,
          rule: rule,
          window: window,
          engineVersion: engineVersion,
          confidence: confidence,
        ),
      );

  @override
  Widget build(BuildContext context) {
    final c = context.ldColors;
    final type = context.ldType;

    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(
          LdSpacing.s4,
          0,
          LdSpacing.s4,
          LdSpacing.s6,
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(title, style: type.headlineM.copyWith(color: c.textPrimary)),
            if (confidence != null) ...[
              const SizedBox(height: LdSpacing.s1),
              Text(
                'Confidence ${(confidence! * 100).round()} %',
                style: type.labelMono.copyWith(color: c.textTertiary),
              ),
            ],
            const SizedBox(height: LdSpacing.s5),
            Text(
              'EVIDENCE',
              style: type.labelMono.copyWith(color: c.textTertiary),
            ),
            const SizedBox(height: LdSpacing.s3),
            for (final e in evidence)
              Padding(
                padding: const EdgeInsets.only(bottom: LdSpacing.s3),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Expanded(
                      child: Text(
                        e.label,
                        style: type.bodyM.copyWith(color: c.textSecondary),
                      ),
                    ),
                    const SizedBox(width: LdSpacing.s4),
                    Text(
                      e.value,
                      style: type.titleM.copyWith(color: c.textPrimary),
                    ),
                  ],
                ),
              ),
            if (window != null || rule != null || engineVersion != null) ...[
              const SizedBox(height: LdSpacing.s2),
              Divider(color: c.border),
              const SizedBox(height: LdSpacing.s3),
              if (window != null)
                _MetaRow(label: 'Window', value: window!),
              if (rule != null) _MetaRow(label: 'Rule', value: rule!),
              if (engineVersion != null)
                _MetaRow(label: 'Engine', value: engineVersion!),
            ],
          ],
        ),
      ),
    );
  }
}

class _MetaRow extends StatelessWidget {
  const _MetaRow({required this.label, required this.value});
  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    final c = context.ldColors;
    final type = context.ldType;
    return Padding(
      padding: const EdgeInsets.only(bottom: LdSpacing.s2),
      child: Row(
        children: [
          SizedBox(
            width: 84,
            child: Text(
              label.toLowerCase(),
              style: type.labelMono.copyWith(color: c.textTertiary),
            ),
          ),
          Expanded(
            child: Text(
              value,
              style: type.labelMono.copyWith(color: c.textSecondary),
            ),
          ),
        ],
      ),
    );
  }
}
