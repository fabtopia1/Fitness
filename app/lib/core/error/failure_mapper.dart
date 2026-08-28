import 'dart:async';
import 'dart:io';

import 'package:firebase_auth/firebase_auth.dart';
import 'package:lifedna/core/error/failure.dart';

/// User-facing rendering of a failure: what happened, and what to do next.
///
/// Every message offers an action. An error screen with nothing to tap is a
/// dead end, and dead ends are what make people uninstall.
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

/// The single place where a [Failure] becomes copy, and the single place where
/// a third-party exception becomes a [Failure].
abstract final class FailureMapper {
  /// Normalises any thrown object into the domain failure hierarchy.
  static Failure from(Object error, [StackTrace? stackTrace]) {
    if (error is Failure) return error;

    if (error is TimeoutException) {
      return TimeoutFailure(debugMessage: error.message);
    }
    if (error is SocketException) {
      return NetworkFailure(debugMessage: error.message, cause: error);
    }

    if (error is FirebaseAuthException) {
      return AuthFailure(error.code, debugMessage: error.message, cause: error);
    }

    if (error is FirebaseException) {
      // Firestore reports offline work as `unavailable`. That is not an error
      // condition for this app — writes are local-first and will sync.
      if (error.code == 'unavailable' || error.code == 'network-request-failed') {
        return NetworkFailure(debugMessage: error.message, cause: error);
      }
      if (error.code == 'deadline-exceeded') {
        return TimeoutFailure(debugMessage: error.message);
      }
      if (error.code == 'not-found') {
        return NotFoundFailure(debugMessage: error.message);
      }
      if (error.code == 'permission-denied') {
        return ServerFailure('permission_denied',
            debugMessage: error.message, cause: error);
      }
      return ServerFailure(error.code,
          debugMessage: error.message, cause: error);
    }

    return UnknownFailure(debugMessage: error.toString(), cause: error);
  }

  static FailureMessage message(Failure failure) => switch (failure) {
        NetworkFailure() => const FailureMessage(
            title: "You're offline",
            body: 'Your changes are saved on this phone and will sync '
                'automatically when you reconnect.',
            actionLabel: 'Retry',
            severity: FailureSeverity.info,
          ),
        TimeoutFailure() => const FailureMessage(
            title: 'That took too long',
            body: 'The connection is slow. Your data is safe on this device.',
            actionLabel: 'Retry',
            severity: FailureSeverity.warning,
          ),
        AuthFailure(:final code) => _auth(code),
        PermissionFailure(:final permission) => FailureMessage(
            title: '${_permissionLabel(permission)} access is off',
            body: 'LifeDNA needs this to ${_permissionPurpose(permission)}. '
                'You can turn it on in Settings.',
            actionLabel: 'Open settings',
            severity: FailureSeverity.warning,
          ),
        ValidationFailure(:final code) => FailureMessage(
            title: 'Check that value',
            body: _validation(code),
            severity: FailureSeverity.warning,
          ),
        ServerFailure(:final code) => _server(code),
        StorageFailure() => const FailureMessage(
            title: "Couldn't save to this device",
            body: 'Storage may be full. Free some space and try again.',
            actionLabel: 'Retry',
          ),
        NotFoundFailure() => const FailureMessage(
            title: 'Not found',
            body: 'That item no longer exists. Pull down to refresh.',
            actionLabel: 'Refresh',
          ),
        UnknownFailure() => const FailureMessage(
            title: 'Something went wrong',
            body: "We've logged it. Try again in a moment.",
            actionLabel: 'Retry',
          ),
      };

  static FailureMessage _auth(String code) => switch (code) {
        'invalid-email' => const FailureMessage(
            title: 'Check your email',
            body: "That doesn't look like a valid email address.",
            severity: FailureSeverity.warning,
          ),
        'user-not-found' || 'wrong-password' || 'invalid-credential' =>
          const FailureMessage(
            title: 'Incorrect email or password',
            body: 'Check both and try again.',
            severity: FailureSeverity.warning,
          ),
        'email-already-in-use' => const FailureMessage(
            title: 'That email is already registered',
            body: 'Sign in instead, or reset your password.',
            actionLabel: 'Sign in',
            severity: FailureSeverity.warning,
          ),
        'weak-password' => const FailureMessage(
            title: 'Choose a stronger password',
            body: 'Use at least 10 characters.',
            severity: FailureSeverity.warning,
          ),
        'too-many-requests' => const FailureMessage(
            title: 'Too many attempts',
            body: 'Wait a minute before trying again.',
            severity: FailureSeverity.warning,
          ),
        'network-request-failed' => const FailureMessage(
            title: "You're offline",
            body: 'Signing in needs a connection.',
            actionLabel: 'Retry',
            severity: FailureSeverity.info,
          ),
        'sign_in_canceled' => const FailureMessage(
            title: 'Sign-in cancelled',
            body: 'No changes were made.',
            severity: FailureSeverity.info,
          ),
        'requires-recent-login' => const FailureMessage(
            title: 'Sign in again to continue',
            body: 'This action needs a fresh sign-in for your security.',
            actionLabel: 'Sign in',
            severity: FailureSeverity.warning,
          ),
        _ => const FailureMessage(
            title: "Couldn't sign you in",
            body: 'Please try again.',
            actionLabel: 'Retry',
          ),
      };

  static FailureMessage _server(String code) => switch (code) {
        'permission_denied' => const FailureMessage(
            title: 'Not allowed',
            body: "You don't have access to that. Try signing in again.",
            actionLabel: 'Sign in',
          ),
        'resource-exhausted' => const FailureMessage(
            title: 'Too many requests',
            body: 'Give it a moment and try again.',
            actionLabel: 'Retry',
            severity: FailureSeverity.warning,
          ),
        'firebase_unavailable' => const FailureMessage(
            title: 'Running in local mode',
            body: 'Cloud sync is not configured on this build. Everything you '
                'log is stored on this device.',
            severity: FailureSeverity.info,
          ),
        _ => const FailureMessage(
            title: 'Server problem',
            body: 'This is on our side. Your data is safe on this device.',
            actionLabel: 'Retry',
          ),
      };

  static String _validation(String code) => switch (code) {
        'required' => 'This field is required.',
        'quantity_must_be_positive' => 'Enter an amount greater than zero.',
        'quantity_implausible' =>
          "That's an unusually large amount. Check the unit.",
        'weight_out_of_range' => 'Enter a weight between 0 and 500 kg.',
        'reps_out_of_range' => 'Enter between 1 and 100 reps.',
        'body_weight_out_of_range' => 'Enter a weight between 20 and 400 kg.',
        'measurement_out_of_range' => 'Enter a value between 1 and 300 cm.',
        'email_invalid' => 'Enter a valid email address.',
        'password_too_short' => 'Use at least 10 characters.',
        'name_required' => 'Enter your name.',
        'height_out_of_range' => 'Enter a height between 100 and 250 cm.',
        'age_out_of_range' => 'You must be 18 or over to use LifeDNA.',
        'date_in_future' => "That date hasn't happened yet.",
        'no_exercises' => 'Add at least one exercise.',
        _ => 'That value looks wrong. Check it and try again.',
      };

  static String _permissionLabel(String p) => switch (p) {
        'notifications' => 'Notification',
        'camera' => 'Camera',
        'photos' => 'Photo',
        'health' => 'Health data',
        'calendar' => 'Calendar',
        _ => p,
      };

  static String _permissionPurpose(String p) => switch (p) {
        'notifications' =>
          'remind you about meals, supplements and workouts',
        'camera' => 'take progress photos',
        'photos' => 'attach progress photos',
        'health' => 'read your steps and sleep',
        'calendar' => 'show your schedule',
        _ => 'work properly',
      };
}
