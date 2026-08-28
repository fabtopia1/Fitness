import 'package:flutter/material.dart';
import 'package:lifedna/core/theme/app_theme.dart';
import 'package:lifedna/core/theme/ld_spacing.dart';

/// A labelled switch sized for a thumb.
///
/// Not a [SwitchListTile]: that widget paints its ink on the nearest Material
/// ancestor, and inside an [LdCard] — which is a decorated box, because in a
/// dark UI depth comes from surface lightness rather than shadow — the splash
/// lands behind the card and is never seen. Flutter asserts on exactly this
/// arrangement in debug.
class LdSwitchRow extends StatelessWidget {
  const LdSwitchRow({
    required this.title,
    required this.value,
    required this.onChanged,
    super.key,
    this.subtitle,
  });

  final String title;
  final String? subtitle;
  final bool value;
  final ValueChanged<bool> onChanged;

  @override
  Widget build(BuildContext context) {
    final c = context.ldColors;
    final type = context.ldType;

    return Semantics(
      toggled: value,
      label: title,
      excludeSemantics: true,
      child: Material(
        color: Colors.transparent,
        borderRadius: BorderRadius.circular(LdRadius.s),
        child: InkWell(
          onTap: () => onChanged(!value),
          borderRadius: BorderRadius.circular(LdRadius.s),
          child: Container(
            constraints: const BoxConstraints(minHeight: LdTouch.min),
            padding: const EdgeInsets.symmetric(vertical: LdSpacing.s2),
            child: Row(
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        title,
                        style: type.titleM.copyWith(color: c.textPrimary),
                      ),
                      if (subtitle != null)
                        Text(
                          subtitle!,
                          style: type.bodyS.copyWith(color: c.textSecondary),
                        ),
                    ],
                  ),
                ),
                const SizedBox(width: LdSpacing.s3),
                Switch(value: value, onChanged: onChanged),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
