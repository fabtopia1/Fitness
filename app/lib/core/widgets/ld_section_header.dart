import 'package:flutter/material.dart';
import 'package:lifedna/core/theme/app_theme.dart';
import 'package:lifedna/core/theme/ld_spacing.dart';

/// A section title with an optional trailing action.
class LdSectionHeader extends StatelessWidget {
  const LdSectionHeader({
    required this.title,
    super.key,
    this.actionLabel,
    this.onAction,
    this.trailing,
  });

  final String title;
  final String? actionLabel;
  final VoidCallback? onAction;
  final Widget? trailing;

  @override
  Widget build(BuildContext context) {
    final c = context.ldColors;
    final type = context.ldType;

    return Padding(
      padding: const EdgeInsets.only(
        top: LdSpacing.s6,
        bottom: LdSpacing.s3,
      ),
      child: Row(
        children: [
          Expanded(
            child: Text(
              title.toUpperCase(),
              style: type.labelMono.copyWith(color: c.textTertiary),
            ),
          ),
          if (trailing != null)
            trailing!
          else if (actionLabel != null && onAction != null)
            GestureDetector(
              onTap: onAction,
              behavior: HitTestBehavior.opaque,
              child: Padding(
                padding: const EdgeInsets.symmetric(vertical: LdSpacing.s2),
                child: Row(
                  children: [
                    Text(
                      actionLabel!,
                      style: type.bodyS.copyWith(color: c.primary),
                    ),
                    Icon(Icons.chevron_right_rounded, size: 16, color: c.primary),
                  ],
                ),
              ),
            ),
        ],
      ),
    );
  }
}
