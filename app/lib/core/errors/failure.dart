/// The closed set of failures the domain layer can produce.
///
/// Presentation never renders `Failure.message` directly — it maps the failure
/// through `FailureMapper` so that user-facing copy is written once, reviewed,
/// and localizable.
sealed class Failure {
  const Failure(this.message, {this.cause, this.stackTrace});

  /// Developer-facing detail. Never shown to a user.
  final String message;
  final Object? cause;
  final StackTrace? stackTrace;

  @override
  String toString() => '$runtimeType($message)';
}

/// The input did not satisfy a domain rule.
final class ValidationFailure extends Failure {
  const ValidationFailure(super.message, {this.field});
  final String? field;
}

/// A local persistence operation failed.
final class StorageFailure extends Failure {
  const StorageFailure(super.message, {super.cause, super.stackTrace});
}

/// The network was unreachable. The write is safe locally; this is informational.
final class NetworkFailure extends Failure {
  const NetworkFailure(super.message, {super.cause});
}

/// The server returned a structured error. [reason] is the stable machine
/// string from docs/09-api-contracts.md §1.2.
final class ServerFailure extends Failure {
  const ServerFailure(super.message, {required this.reason, this.retryAfter});
  final String reason;
  final Duration? retryAfter;
}

/// The user is not authenticated, or their session expired.
final class AuthFailure extends Failure {
  const AuthFailure(super.message, {this.code});
  final String? code;
}

/// A required OS permission was denied.
final class PermissionFailure extends Failure {
  const PermissionFailure(super.message, {required this.permission});
  final String permission;
}

/// The requested resource does not exist.
final class NotFoundFailure extends Failure {
  const NotFoundFailure(super.message);
}

/// A third-party provider (calendar, health, AI) failed.
final class IntegrationFailure extends Failure {
  const IntegrationFailure(
    super.message, {
    required this.provider,
    this.needsReauth = false,
  });
  final String provider;
  final bool needsReauth;
}

/// Anything unclassified. Always reported to Crashlytics.
final class UnknownFailure extends Failure {
  const UnknownFailure(super.message, {super.cause, super.stackTrace});
}
