import 'package:flutter/material.dart';
import 'package:lifedna/core/theme/app_theme.dart';
import 'package:lifedna/core/theme/ld_spacing.dart';

/// A labelled value with a proportional bar. Used for macro breakdowns,
/// adherence rows and volume-by-muscle displays.
class LdStatRow extends StatelessWidget {
  const LdStatRow({
    required this.label,
    required this.value,
    required this.progress,
    required this.color,
    super.key,
    this.trailing,
    this.trailingDirection,
  });

  final String label;
  final String value;

  /// May exceed 1.0 — the bar renders the overflow in a lighter tint.
  final double progress;
  final Color color;
  final String? trailing;
  final Color? trailingDirection;

  @override
  Widget build(BuildContext context) {
    final c = context.ldColors;
    final type = context.ldType;
    final clamped = progress.clamp(0.0, 1.0).toDouble();
    final overflow = (progress - 1.0).clamp(0.0, 1.0).toDouble();

    return Semantics(
      label: '$label, $value, ${(progress * 100).round()} percent',
      excludeSemantics: true,
      child: Padding(
        padding: const EdgeInsets.only(bottom: LdSpacing.s3),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Expanded(
                  child: Text(
                    label.toUpperCase(),
                    style: type.labelMono.copyWith(color: c.textTertiary),
                  ),
                ),
                Text(value, style: type.bodyS.copyWith(color: c.textPrimary)),
                if (trailing != null) ...[
                  const SizedBox(width: LdSpacing.s2),
                  Text(
                    trailing!,
                    style: type.bodyS.copyWith(
                      color: trailingDirection ?? c.textTertiary,
                    ),
                  ),
                ],
              ],
            ),
            const SizedBox(height: LdSpacing.s2),
            ClipRRect(
              borderRadius: BorderRadius.circular(LdRadius.full),
              child: SizedBox(
                height: 6,
                child: Stack(
                  children: [
                    Container(color: c.border),
                    FractionallySizedBox(
                      widthFactor: clamped,
                      child: Container(color: color),
                    ),
                    if (overflow > 0)
                      FractionallySizedBox(
                        widthFactor: overflow,
                        child: Container(color: c.overTarget(color)),
                      ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
