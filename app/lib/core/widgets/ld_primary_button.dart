import 'package:flutter/material.dart';
import 'package:lifedna/core/theme/app_theme.dart';
import 'package:lifedna/core/theme/ld_spacing.dart';

enum LdButtonSize {
  s(40, LdRadius.s),
  m(52, 12),
  l(LdTouch.gym, LdRadius.m),

  /// Live Gym Mode. Operated one-handed, mid-set, at arm's length.
  xl(LdTouch.gymPrimary, 18);

  const LdButtonSize(this.height, this.radius);
  final double height;
  final double radius;
}

enum LdButtonVariant { primary, secondary, ghost, danger }

/// The primary action control (docs/04 §8.8).
///
/// A loading button never changes width — the label stays and a spinner joins
/// it, so the layout does not jump under the user's thumb.
class LdPrimaryButton extends StatelessWidget {
  const LdPrimaryButton({
    required this.label,
    required this.onPressed,
    super.key,
    this.size = LdButtonSize.m,
    this.variant = LdButtonVariant.primary,
    this.icon,
    this.loading = false,
    this.expand = true,
  });

  final String label;
  final VoidCallback? onPressed;
  final LdButtonSize size;
  final LdButtonVariant variant;
  final IconData? icon;
  final bool loading;
  final bool expand;

  @override
  Widget build(BuildContext context) {
    final c = context.ldColors;
    final type = context.ldType;
    final enabled = onPressed != null && !loading;

    final (bg, fg, border) = switch (variant) {
      LdButtonVariant.primary => (c.primary, c.textOnPrimary, null),
      LdButtonVariant.secondary => (c.surfaceElevated, c.textPrimary, c.borderStrong),
      LdButtonVariant.ghost => (Colors.transparent, c.textSecondary, c.border),
      LdButtonVariant.danger => (c.danger, c.textOnPrimary, null),
    };

    final labelStyle = switch (size) {
      LdButtonSize.s => type.titleM,
      LdButtonSize.m => type.titleM,
      LdButtonSize.l => type.titleL,
      LdButtonSize.xl => type.headlineM,
    };

    final child = Row(
      mainAxisSize: expand ? MainAxisSize.max : MainAxisSize.min,
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        if (loading) ...[
          SizedBox(
            width: 18,
            height: 18,
            child: CircularProgressIndicator(
              strokeWidth: 2,
              valueColor: AlwaysStoppedAnimation(
                enabled ? fg : c.textDisabled,
              ),
            ),
          ),
          const SizedBox(width: LdSpacing.s3),
        ] else if (icon != null) ...[
          Icon(icon, size: 20, color: enabled ? fg : c.textDisabled),
          const SizedBox(width: LdSpacing.s2),
        ],
        Flexible(
          child: Text(
            label,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: labelStyle.copyWith(
              color: enabled ? fg : c.textDisabled,
            ),
          ),
        ),
      ],
    );

    return Semantics(
      button: true,
      enabled: enabled,
      label: label,
      child: SizedBox(
        width: expand ? double.infinity : null,
        height: size.height,
        child: Material(
          color: enabled ? bg : c.surfaceHighest,
          borderRadius: BorderRadius.circular(size.radius),
          child: InkWell(
            onTap: enabled ? onPressed : null,
            borderRadius: BorderRadius.circular(size.radius),
            child: Container(
              padding: EdgeInsets.symmetric(
                horizontal: expand ? LdSpacing.s4 : LdSpacing.s5,
              ),
              decoration: border == null
                  ? null
                  : BoxDecoration(
                      borderRadius: BorderRadius.circular(size.radius),
                      border: Border.all(color: border),
                    ),
              child: child,
            ),
          ),
        ),
      ),
    );
  }
}
