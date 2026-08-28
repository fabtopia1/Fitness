import 'package:flutter/foundation.dart';

/// The closed set of failures the app can produce.
///
/// Every failure carries a machine-readable [code]. The UI switches on the
/// code; it never parses [debugMessage], which exists only for logs.
@immutable
sealed class Failure {
  const Failure({required this.code, this.debugMessage, this.cause});

  final String code;
  final String? debugMessage;
  final Object? cause;

  /// Whether retrying the same operation could plausibly succeed.
  bool get isRetryable => switch (this) {
    NetworkFailure() => true,
    TimeoutFailure() => true,
    ServerFailure() => true,
    StorageFailure() => true,
    ValidationFailure() => false,
    AuthFailure() => false,
    PermissionFailure() => false,
    NotFoundFailure() => false,
    UnknownFailure() => true,
  };

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is Failure &&
          other.runtimeType == runtimeType &&
          other.code == code);

  @override
  int get hashCode => Object.hash(runtimeType, code);

  @override
  String toString() => '$runtimeType($code)';
}

/// Input violated a domain rule. Never retryable — the input must change.
final class ValidationFailure extends Failure {
  const ValidationFailure(String code, {this.field, super.debugMessage})
    : super(code: code);
  final String? field;
}

/// The device is offline, or the request could not reach the server.
/// User writes still succeed locally, so this is informational.
final class NetworkFailure extends Failure {
  const NetworkFailure({super.debugMessage, super.cause})
    : super(code: 'network_unavailable');
}

final class TimeoutFailure extends Failure {
  const TimeoutFailure({super.debugMessage}) : super(code: 'network_timeout');
}

/// Firestore or a Cloud Function returned an error.
final class ServerFailure extends Failure {
  const ServerFailure(String code, {super.debugMessage, super.cause})
    : super(code: code);
}

final class AuthFailure extends Failure {
  const AuthFailure(String code, {super.debugMessage, super.cause})
    : super(code: code);
}

/// A required OS permission was denied.
final class PermissionFailure extends Failure {
  const PermissionFailure(this.permission, {super.debugMessage})
    : super(code: 'permission_denied');
  final String permission;
}

final class NotFoundFailure extends Failure {
  const NotFoundFailure({super.debugMessage}) : super(code: 'not_found');
}

/// Local (Hive) persistence failed. Serious: the offline guarantee depends on
/// this layer, so it is surfaced rather than swallowed.
final class StorageFailure extends Failure {
  const StorageFailure({super.debugMessage, super.cause})
    : super(code: 'storage_error');
}

final class UnknownFailure extends Failure {
  const UnknownFailure({super.debugMessage, super.cause})
    : super(code: 'unknown');
}
