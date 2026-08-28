import 'package:flutter/material.dart';
import 'package:lifedna/core/theme/app_theme.dart';
import 'package:lifedna/core/theme/ld_spacing.dart';
import 'package:lifedna/core/widgets/ld_card.dart';

/// Whether a change is good, bad, or neither.
///
/// Direction is SEMANTIC, not arithmetic. Weight falling during a cut is good;
/// sleep falling is bad. The tile must never infer this from the sign.
enum DeltaDirection { good, bad, neutral }

/// A labelled metric with an optional delta (docs/04 §8.2).
class LdMetricTile extends StatelessWidget {
  const LdMetricTile({
    required this.label,
    required this.value,
    super.key,
    this.unit,
    this.delta,
    this.deltaDirection = DeltaDirection.neutral,
    this.deltaSuffix,
    this.accentColor,
    this.onTap,
    this.footnote,
  });

  final String label;
  final String value;
  final String? unit;
  final String? delta;
  final DeltaDirection deltaDirection;
  final String? deltaSuffix;
  final Color? accentColor;
  final VoidCallback? onTap;
  final String? footnote;

  @override
  Widget build(BuildContext context) {
    final c = context.ldColors;
    final type = context.ldType;

    final deltaColor = switch (deltaDirection) {
      DeltaDirection.good => c.success,
      DeltaDirection.bad => c.danger,
      DeltaDirection.neutral => c.textTertiary,
    };

    // Never colour alone: every delta carries a glyph too (docs/04 §11).
    final deltaGlyph = switch (deltaDirection) {
      DeltaDirection.good => '▲',
      DeltaDirection.bad => '▼',
      DeltaDirection.neutral => '▬',
    };

    return LdCard(
      onTap: onTap,
      accentColor: accentColor,
      semanticLabel: [
        label,
        value,
        if (unit != null) unit,
        if (delta != null) 'change $delta ${deltaDirection.name}',
      ].join(', '),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            label.toUpperCase(),
            style: type.labelMono.copyWith(color: c.textTertiary),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
          const SizedBox(height: LdSpacing.s2),
          Row(
            crossAxisAlignment: CrossAxisAlignment.baseline,
            textBaseline: TextBaseline.alphabetic,
            children: [
              Flexible(
                child: Text(
                  value,
                  style: type.displayM.copyWith(color: c.textPrimary),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
              if (unit != null) ...[
                const SizedBox(width: LdSpacing.s1),
                Text(
                  unit!,
                  style: type.labelMono.copyWith(color: c.textTertiary),
                ),
              ],
            ],
          ),
          if (delta != null) ...[
            const SizedBox(height: LdSpacing.s2),
            Row(
              children: [
                Text(
                  deltaGlyph,
                  style: type.caption.copyWith(color: deltaColor),
                ),
                const SizedBox(width: LdSpacing.s1),
                Flexible(
                  child: Text(
                    deltaSuffix == null ? delta! : '${delta!} $deltaSuffix',
                    style: type.bodyS.copyWith(color: deltaColor),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
              ],
            ),
          ],
          if (footnote != null) ...[
            const SizedBox(height: LdSpacing.s1),
            Text(
              footnote!,
              style: type.caption.copyWith(color: c.textTertiary),
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
            ),
          ],
        ],
      ),
    );
  }
}
