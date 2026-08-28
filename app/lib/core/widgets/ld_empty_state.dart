import 'package:flutter/material.dart';
import 'package:lifedna/core/theme/app_theme.dart';
import 'package:lifedna/core/theme/ld_spacing.dart';
import 'package:lifedna/core/widgets/ld_primary_button.dart';

/// An empty state that names the value, not the void (docs/04 §10.3).
///
/// Every empty state offers a next action. "No dead ends" is a product rule,
/// and an empty screen with nothing to tap is the most common dead end there is.
class LdEmptyState extends StatelessWidget {
  const LdEmptyState({
    required this.icon,
    required this.headline,
    required this.body,
    super.key,
    this.actionLabel,
    this.onAction,
    this.secondaryActionLabel,
    this.onSecondaryAction,
    this.progress,
    this.iconColor,
  });

  final IconData icon;
  final String headline;
  final String body;
  final String? actionLabel;
  final VoidCallback? onAction;
  final String? secondaryActionLabel;
  final VoidCallback? onSecondaryAction;

  /// When an empty state is a matter of time rather than of action, show
  /// progress instead of a button.
  final ({int current, int total, String label})? progress;

  /// Overrides the icon tint, so an error state can read as an error.
  final Color? iconColor;

  @override
  Widget build(BuildContext context) {
    final c = context.ldColors;
    final type = context.ldType;

    return Center(
      child: Padding(
        padding: const EdgeInsets.symmetric(
          horizontal: LdSpacing.s7,
          vertical: LdSpacing.s8,
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 48, color: iconColor ?? c.textTertiary),
            const SizedBox(height: LdSpacing.s4),
            Text(
              headline,
              textAlign: TextAlign.center,
              style: type.titleL.copyWith(color: c.textPrimary),
            ),
            const SizedBox(height: LdSpacing.s2),
            Text(
              body,
              textAlign: TextAlign.center,
              style: type.bodyM.copyWith(color: c.textSecondary),
            ),
            if (progress != null) ...[
              const SizedBox(height: LdSpacing.s5),
              ClipRRect(
                borderRadius: BorderRadius.circular(LdRadius.full),
                child: LinearProgressIndicator(
                  value: progress!.total == 0
                      ? 0
                      : progress!.current / progress!.total,
                  minHeight: 6,
                  backgroundColor: c.border,
                  valueColor: AlwaysStoppedAnimation(c.primary),
                ),
              ),
              const SizedBox(height: LdSpacing.s2),
              Text(
                progress!.label,
                style: type.labelMono.copyWith(color: c.textTertiary),
              ),
            ],
            if (actionLabel != null && onAction != null) ...[
              const SizedBox(height: LdSpacing.s6),
              LdPrimaryButton(
                label: actionLabel!,
                onPressed: onAction,
                expand: false,
              ),
            ],
            if (secondaryActionLabel != null && onSecondaryAction != null) ...[
              const SizedBox(height: LdSpacing.s3),
              LdPrimaryButton(
                label: secondaryActionLabel!,
                onPressed: onSecondaryAction,
                variant: LdButtonVariant.ghost,
                expand: false,
              ),
            ],
          ],
        ),
      ),
    );
  }
}
