import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:lifedna/core/error/failure.dart';
import 'package:lifedna/core/error/failure_mapper.dart';
import 'package:lifedna/core/theme/app_theme.dart';
import 'package:lifedna/core/theme/ld_spacing.dart';
import 'package:lifedna/core/widgets/ld_empty_state.dart';
import 'package:lifedna/core/widgets/ld_primary_button.dart';

/// Renders an [AsyncValue] with every state a screen is required to handle:
/// loading, error (with retry), empty, and data.
///
/// Centralised so no screen can forget one. A screen that shows a spinner
/// forever on error, or a blank list with no explanation, is the most common
/// way a well-architected app still feels broken.
class LdAsyncView<T> extends StatelessWidget {
  const LdAsyncView({
    required this.value,
    required this.data,
    required this.onRetry,
    super.key,
    this.loading,
    this.isEmpty,
    this.empty,
    this.errorContext,
  });

  final AsyncValue<T> value;
  final Widget Function(T data) data;

  /// Called by the error state's action, and by pull-to-refresh.
  final VoidCallback onRetry;

  final Widget? loading;

  /// Lets a screen define emptiness for its own type.
  final bool Function(T data)? isEmpty;
  final Widget? empty;

  /// Shown in the error state so a bug report says which screen failed.
  final String? errorContext;

  @override
  Widget build(BuildContext context) {
    return value.when(
      loading: () => loading ?? const LdLoadingView(),
      error: (error, stackTrace) => LdErrorView(
        failure: FailureMapper.from(error, stackTrace),
        onRetry: onRetry,
        context_: errorContext,
      ),
      data: (value) {
        if ((isEmpty?.call(value) ?? false) && empty != null) return empty!;
        return data(value);
      },
    );
  }
}

class LdLoadingView extends StatelessWidget {
  const LdLoadingView({super.key, this.label});
  final String? label;

  @override
  Widget build(BuildContext context) {
    final c = context.ldColors;
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          SizedBox(
            width: 28,
            height: 28,
            child: CircularProgressIndicator(
              strokeWidth: 2.5,
              color: c.primary,
            ),
          ),
          if (label != null) ...[
            const SizedBox(height: LdSpacing.s4),
            Text(
              label!,
              style: context.ldType.bodyM.copyWith(color: c.textSecondary),
            ),
          ],
        ],
      ),
    );
  }
}

/// The error state. Always offers an action — never a dead end.
class LdErrorView extends StatelessWidget {
  const LdErrorView({
    required this.failure,
    required this.onRetry,
    super.key,
    // ignore: no_leading_underscores_for_local_identifiers
    String? context_,
  }) : _context = context_;

  final Failure failure;
  final VoidCallback onRetry;
  final String? _context;

  @override
  Widget build(BuildContext context) {
    final message = FailureMapper.message(failure);
    final c = context.ldColors;

    return LdEmptyState(
      icon: switch (message.severity) {
        FailureSeverity.info => Icons.cloud_off_rounded,
        FailureSeverity.warning => Icons.warning_amber_rounded,
        FailureSeverity.error => Icons.error_outline_rounded,
      },
      headline: message.title,
      body: _context == null ? message.body : '${message.body}\n\n($_context)',
      actionLabel: failure.isRetryable
          ? (message.actionLabel ?? 'Retry')
          : null,
      onAction: failure.isRetryable ? onRetry : null,
      iconColor: switch (message.severity) {
        FailureSeverity.info => c.info,
        FailureSeverity.warning => c.warning,
        FailureSeverity.error => c.danger,
      },
    );
  }
}

/// A persistent banner for the offline / unsynced condition.
///
/// Deliberately not a blocking dialog: being offline never stops the user
/// doing anything in this app, so it must never stop them seeing anything.
class LdOfflineBanner extends StatelessWidget {
  const LdOfflineBanner({
    required this.isOnline,
    super.key,
    this.pendingWrites = 0,
    this.parkedWrites = 0,
    this.onRetry,
  });

  final bool isOnline;
  final int pendingWrites;
  final int parkedWrites;
  final VoidCallback? onRetry;

  @override
  Widget build(BuildContext context) {
    final c = context.ldColors;
    final type = context.ldType;

    if (parkedWrites > 0) {
      return _Banner(
        color: c.danger,
        icon: Icons.sync_problem_rounded,
        text:
            '$parkedWrites change${parkedWrites == 1 ? '' : 's'} '
            "couldn't sync",
        actionLabel: 'Retry',
        onAction: onRetry,
        style: type.bodyS,
      );
    }
    if (!isOnline) {
      return _Banner(
        color: c.warning,
        icon: Icons.cloud_off_rounded,
        text: pendingWrites > 0
            ? "Offline · $pendingWrites change${pendingWrites == 1 ? '' : 's'} "
                  'will sync later'
            : 'Offline · everything still works',
        style: type.bodyS,
      );
    }
    return const SizedBox.shrink();
  }
}

class _Banner extends StatelessWidget {
  const _Banner({
    required this.color,
    required this.icon,
    required this.text,
    required this.style,
    this.actionLabel,
    this.onAction,
  });

  final Color color;
  final IconData icon;
  final String text;
  final TextStyle style;
  final String? actionLabel;
  final VoidCallback? onAction;

  @override
  Widget build(BuildContext context) {
    final c = context.ldColors;
    return Material(
      color: Color.lerp(c.surface, color, 0.16),
      child: Padding(
        // The status-bar inset is added HERE rather than by wrapping the
        // banner in a SafeArea, because the banner is usually absent: a
        // SafeArea around a SizedBox.shrink still reserves the inset and would
        // push every screen down by the status bar height all the time.
        //
        // targetSdk 36 makes edge-to-edge mandatory on Android 15+, so this
        // banner sits at y=0 and would otherwise be drawn under the clock.
        padding: EdgeInsets.only(
          top: MediaQuery.paddingOf(context).top + LdSpacing.s2,
          left: LdSpacing.s4,
          right: LdSpacing.s4,
          bottom: LdSpacing.s2,
        ),
        child: Row(
          children: [
            Icon(icon, size: 16, color: color),
            const SizedBox(width: LdSpacing.s2),
            Expanded(
              child: Text(text, style: style.copyWith(color: c.textSecondary)),
            ),
            if (actionLabel != null && onAction != null)
              LdPrimaryButton(
                label: actionLabel!,
                size: LdButtonSize.s,
                variant: LdButtonVariant.ghost,
                expand: false,
                onPressed: onAction,
              ),
          ],
        ),
      ),
    );
  }
}

/// Shows a failure as a snackbar with an optional retry.
void showFailureSnack(
  BuildContext context,
  Failure failure, {
  VoidCallback? onRetry,
}) {
  final message = FailureMapper.message(failure);
  ScaffoldMessenger.of(context)
    ..hideCurrentSnackBar()
    ..showSnackBar(
      SnackBar(
        content: Text('${message.title} — ${message.body}'),
        duration: const Duration(seconds: 5),
        action: (failure.isRetryable && onRetry != null)
            ? SnackBarAction(
                label: message.actionLabel ?? 'Retry',
                onPressed: onRetry,
              )
            : null,
      ),
    );
}

void showSuccessSnack(BuildContext context, String message) {
  ScaffoldMessenger.of(context)
    ..hideCurrentSnackBar()
    ..showSnackBar(
      SnackBar(content: Text(message), duration: const Duration(seconds: 2)),
    );
}
