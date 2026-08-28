import 'package:flutter/material.dart';
import 'package:lifedna/core/theme/app_theme.dart';
import 'package:lifedna/core/theme/ld_spacing.dart';

enum LdCardVariant { standard, elevated, interactive, accent }

/// The universal container (docs/04 §8.1).
///
/// In a dark UI, shadows do not read as elevation. Depth is expressed through
/// surface lightness plus a hairline border, and shadow is reserved for layers
/// that genuinely float.
class LdCard extends StatefulWidget {
  const LdCard({
    required this.child,
    super.key,
    this.variant = LdCardVariant.standard,
    this.eyebrow,
    this.trailing,
    this.accentColor,
    this.onTap,
    this.padding = const EdgeInsets.all(LdSpacing.s4),
    this.semanticLabel,
  });

  final Widget child;
  final LdCardVariant variant;

  /// The uppercase technical label at the top of the card.
  final String? eyebrow;

  /// An action or value aligned to the end of the eyebrow row.
  final Widget? trailing;

  /// Colour of the leading accent bar. Implies [LdCardVariant.accent].
  final Color? accentColor;

  final VoidCallback? onTap;
  final EdgeInsets padding;
  final String? semanticLabel;

  @override
  State<LdCard> createState() => _LdCardState();
}

class _LdCardState extends State<LdCard> {
  bool _pressed = false;

  bool get _interactive =>
      widget.onTap != null || widget.variant == LdCardVariant.interactive;

  @override
  Widget build(BuildContext context) {
    final c = context.ldColors;
    final type = context.ldType;

    final isElevated =
        widget.variant == LdCardVariant.elevated || (_pressed && _interactive);

    final accent = widget.accentColor;

    Widget content = Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        if (widget.eyebrow != null || widget.trailing != null) ...[
          Row(
            children: [
              if (widget.eyebrow != null)
                Expanded(
                  child: Text(
                    widget.eyebrow!.toUpperCase(),
                    style: type.labelMono.copyWith(color: c.textTertiary),
                  ),
                )
              else
                const Spacer(),
              if (widget.trailing != null) widget.trailing!,
            ],
          ),
          const SizedBox(height: LdSpacing.s3),
        ],
        widget.child,
      ],
    );

    if (accent != null) {
      // IntrinsicHeight is required, not decorative: a Row with
      // CrossAxisAlignment.stretch inside an unbounded parent — every list
      // item in this app — forces its children to an infinite height and the
      // card fails to lay out at all.
      content = IntrinsicHeight(
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Container(
              width: 3,
              margin: const EdgeInsets.only(right: LdSpacing.s3),
              decoration: BoxDecoration(
                color: accent,
                borderRadius: BorderRadius.circular(LdRadius.full),
              ),
            ),
            Expanded(child: content),
          ],
        ),
      );
    }

    final card = AnimatedContainer(
      duration: LdMotion.instant,
      curve: Curves.easeOut,
      padding: widget.padding,
      decoration: BoxDecoration(
        color: isElevated ? c.surfaceElevated : c.surface,
        borderRadius: BorderRadius.circular(LdRadius.m),
        border: Border.all(color: isElevated ? c.borderStrong : c.border),
      ),
      child: content,
    );

    if (!_interactive) {
      return Semantics(
        label: widget.semanticLabel,
        container: true,
        child: card,
      );
    }

    return Semantics(
      label: widget.semanticLabel,
      button: true,
      container: true,
      child: GestureDetector(
        onTapDown: (_) => setState(() => _pressed = true),
        onTapUp: (_) => setState(() => _pressed = false),
        onTapCancel: () => setState(() => _pressed = false),
        onTap: widget.onTap,
        child: AnimatedScale(
          scale: _pressed ? 0.985 : 1,
          duration: context.reduceMotion ? Duration.zero : LdMotion.instant,
          child: card,
        ),
      ),
    );
  }
}
