import 'package:lifedna/core/errors/failure.dart';

/// A user-facing rendering of a failure: what happened, and what to do next.
///
/// Every error the user sees offers an action. "No dead ends" (docs/05 §13).
class FailureMessage {
  const FailureMessage({
    required this.title,
    required this.body,
    this.actionLabel,
    this.severity = FailureSeverity.error,
  });

  final String title;
  final String body;
  final String? actionLabel;
  final FailureSeverity severity;
}

enum FailureSeverity { info, warning, error }

/// The single place where a [Failure] becomes copy. Raw exception text never
/// reaches the UI.
abstract final class FailureMapper {
  static FailureMessage map(Failure failure) => switch (failure) {
        NetworkFailure() => const FailureMessage(
            title: "Couldn't reach the server",
            body: 'Your changes are saved on this phone and will sync '
                'automatically when you reconnect.',
            actionLabel: 'Retry',
            severity: FailureSeverity.info,
          ),
        AuthFailure() => const FailureMessage(
            title: 'Session expired',
            body: 'Sign in again to keep your data in sync.',
            actionLabel: 'Sign in',
          ),
        PermissionFailure(:final permission) => FailureMessage(
            title: '${_permissionLabel(permission)} access is off',
            body: 'LifeDNA needs this to ${_permissionPurpose(permission)}. '
                'You can turn it on in settings.',
            actionLabel: 'Open settings',
            severity: FailureSeverity.warning,
          ),
        IntegrationFailure(:final provider, :final needsReauth) =>
          needsReauth
              ? FailureMessage(
                  title: '${_providerLabel(provider)} access expired',
                  body: 'Reconnect to keep your schedule in sync.',
                  actionLabel: 'Reconnect',
                  severity: FailureSeverity.warning,
                )
              : FailureMessage(
                  title: '${_providerLabel(provider)} is unavailable',
                  body: 'This is temporary. Everything else keeps working.',
                  actionLabel: 'Retry',
                  severity: FailureSeverity.warning,
                ),
        ServerFailure(:final reason, :final retryAfter) =>
          _mapServerReason(reason, retryAfter),
        ValidationFailure(:final message) => FailureMessage(
            title: 'Check that value',
            body: _validationCopy(message),
            severity: FailureSeverity.warning,
          ),
        StorageFailure() => const FailureMessage(
            title: "Couldn't save that",
            body: 'Something went wrong writing to this device. '
                'Try again — if it keeps happening, restart the app.',
            actionLabel: 'Retry',
          ),
        NotFoundFailure() => const FailureMessage(
            title: 'Not found',
            body: "That item no longer exists. Pull down to refresh.",
            actionLabel: 'Refresh',
          ),
        UnknownFailure() => const FailureMessage(
            title: 'Something went wrong',
            body: "We've logged it. Try again in a moment.",
            actionLabel: 'Retry',
          ),
      };

  static FailureMessage _mapServerReason(String reason, Duration? retryAfter) {
    return switch (reason) {
      'AI_BUDGET_EXCEEDED' => const FailureMessage(
          title: "You've reached today's AI limit",
          body: 'It resets at midnight. Recovery scores, your daily plan and '
              'insights keep working.',
          severity: FailureSeverity.info,
        ),
      'RATE_LIMITED' => FailureMessage(
          title: 'Slow down a moment',
          body: retryAfter == null
              ? 'Try again shortly.'
              : 'Try again in ${retryAfter.inSeconds} seconds.',
          actionLabel: 'Retry',
          severity: FailureSeverity.info,
        ),
      'SAFETY_BLOCKED' => const FailureMessage(
          title: "I can't help with that",
          body: 'This is outside what LifeDNA can safely advise on. '
              'Please speak to a qualified professional.',
          severity: FailureSeverity.warning,
        ),
      'PROVIDER_AUTH_EXPIRED' => const FailureMessage(
          title: 'Access expired',
          body: 'Reconnect the account to resume syncing.',
          actionLabel: 'Reconnect',
          severity: FailureSeverity.warning,
        ),
      'PAYLOAD_TOO_LARGE' => const FailureMessage(
          title: 'Too much data at once',
          body: "We'll sync this in smaller batches automatically.",
          severity: FailureSeverity.info,
        ),
      _ => const FailureMessage(
          title: 'Something went wrong',
          body: "We've logged it. Try again in a moment.",
          actionLabel: 'Retry',
        ),
    };
  }

  static String _validationCopy(String code) => switch (code) {
        'quantity_must_be_positive' => 'Enter a quantity greater than zero.',
        'quantity_implausible' =>
          "That's an unusually large amount. Check the unit.",
        'weight_out_of_range' => 'Enter a weight between 20 and 300 kg.',
        'reps_out_of_range' => 'Enter between 1 and 100 reps.',
        'rate_exceeds_safe_maximum' =>
          "That rate of loss isn't safe. We've capped it — faster loss costs "
              'muscle.',
        _ => 'That value looks wrong. Check it and try again.',
      };

  static String _permissionLabel(String p) => switch (p) {
        'health' => 'Health data',
        'notifications' => 'Notification',
        'camera' => 'Camera',
        'bluetooth' => 'Bluetooth',
        _ => p,
      };

  static String _permissionPurpose(String p) => switch (p) {
        'health' => 'calculate your recovery score',
        'notifications' => 'remind you about meals, training and supplements',
        'camera' => 'scan barcodes',
        'bluetooth' => 'read heart rate from your band',
        _ => 'work properly',
      };

  static String _providerLabel(String p) => switch (p) {
        'google' => 'Google Calendar',
        'microsoft' => 'Outlook',
        'health_connect' => 'Health Connect',
        'galaxy_fit3' => 'Galaxy Fit 3',
        'anthropic' => 'Coach',
        _ => p,
      };
}
