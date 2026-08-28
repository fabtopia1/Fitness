import 'dart:async';
import 'dart:io';

import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lifedna/core/error/failure.dart';
import 'package:lifedna/core/error/failure_mapper.dart';
import 'package:lifedna/core/result/result.dart';

void main() {
  group('Failure.isRetryable', () {
    test('transient conditions are retryable', () {
      expect(const NetworkFailure().isRetryable, isTrue);
      expect(const TimeoutFailure().isRetryable, isTrue);
      expect(const ServerFailure('internal').isRetryable, isTrue);
      expect(const StorageFailure().isRetryable, isTrue);
      expect(const UnknownFailure().isRetryable, isTrue);
    });

    test('conditions the user must resolve are not', () {
      // Offering "Retry" on a bad password or a denied permission trains the
      // user to tap a button that can never work.
      expect(const ValidationFailure('too_short').isRetryable, isFalse);
      expect(const AuthFailure('wrong-password').isRetryable, isFalse);
      expect(const PermissionFailure('camera').isRetryable, isFalse);
      expect(const NotFoundFailure().isRetryable, isFalse);
    });
  });

  group('FailureMapper.from', () {
    test('passes a Failure through unchanged', () {
      const original = NotFoundFailure();
      expect(FailureMapper.from(original), same(original));
    });

    test('maps timeouts and socket errors to their own kinds', () {
      expect(
        FailureMapper.from(TimeoutException('slow')),
        isA<TimeoutFailure>(),
      );
      expect(
        FailureMapper.from(const SocketException('no route')),
        isA<NetworkFailure>(),
      );
    });

    test('a Firestore "unavailable" is offline, not a server error', () {
      // This is the single most important mapping in the file: Firestore
      // reports every offline write as `unavailable`, and treating that as an
      // error would put a red banner in front of a user who is simply in a
      // basement.
      final failure = FailureMapper.from(
        FirebaseException(plugin: 'cloud_firestore', code: 'unavailable'),
      );
      expect(failure, isA<NetworkFailure>());
    });

    test('maps the remaining Firestore codes onto domain failures', () {
      FirebaseException fs(String code) =>
          FirebaseException(plugin: 'cloud_firestore', code: code);

      expect(
        FailureMapper.from(fs('deadline-exceeded')),
        isA<TimeoutFailure>(),
      );
      expect(FailureMapper.from(fs('not-found')), isA<NotFoundFailure>());
      expect(
        FailureMapper.from(fs('permission-denied')),
        isA<ServerFailure>().having((f) => f.code, 'code', 'permission_denied'),
      );
      expect(
        FailureMapper.from(fs('aborted')),
        isA<ServerFailure>().having((f) => f.code, 'code', 'aborted'),
      );
    });

    test('auth exceptions keep their code so the copy can be specific', () {
      final failure = FailureMapper.from(
        FirebaseAuthException(code: 'wrong-password'),
      );
      expect(
        failure,
        isA<AuthFailure>().having((f) => f.code, 'code', 'wrong-password'),
      );
    });

    test('anything else becomes an unknown failure rather than escaping', () {
      expect(FailureMapper.from(StateError('boom')), isA<UnknownFailure>());
    });
  });

  group('FailureMapper.message', () {
    test('never returns raw exception text to the user', () {
      final failure = FailureMapper.from(
        StateError('Null check operator used on a null value'),
      );
      final message = FailureMapper.message(failure);
      expect(message.body, isNot(contains('Null check')));
      expect(message.title, isNotEmpty);
    });

    test('offline reads as information, not as an error', () {
      final message = FailureMapper.message(const NetworkFailure());
      expect(message.severity, FailureSeverity.info);
    });

    test('every failure kind produces a non-empty title and body', () {
      const failures = <Failure>[
        NetworkFailure(),
        TimeoutFailure(),
        ServerFailure('internal'),
        AuthFailure('user-not-found'),
        PermissionFailure('notifications'),
        NotFoundFailure(),
        StorageFailure(),
        UnknownFailure(),
        ValidationFailure('required'),
      ];
      for (final failure in failures) {
        final message = FailureMapper.message(failure);
        expect(message.title, isNotEmpty, reason: '${failure.runtimeType}');
        expect(message.body, isNotEmpty, reason: '${failure.runtimeType}');
      }
    });
  });

  group('Result', () {
    test('Ok carries the value and no failure', () {
      const result = Ok<int>(7);
      expect(result.isOk, isTrue);
      expect(result.isErr, isFalse);
      expect(result.valueOrNull, 7);
      expect(result.failureOrNull, isNull);
    });

    test('Err carries the failure and no value', () {
      const result = Err<int>(NotFoundFailure());
      expect(result.isErr, isTrue);
      expect(result.valueOrNull, isNull);
      expect(result.failureOrNull, isA<NotFoundFailure>());
    });

    test('when() is exhaustive over both arms', () {
      expect(const Ok<int>(2).when(ok: (v) => v * 2, err: (_) => -1), 4);
      expect(
        const Err<int>(NetworkFailure()).when(ok: (v) => v, err: (_) => -1),
        -1,
      );
    });

    test('map transforms Ok and passes Err through untouched', () {
      expect(const Ok<int>(3).map((v) => v.toString()), const Ok<String>('3'));
      expect(
        const Err<int>(TimeoutFailure()).map((v) => v.toString()),
        const Err<String>(TimeoutFailure()),
      );
    });

    test('getOrElse supplies a fallback only on Err', () {
      expect(const Ok<int>(5).getOrElse((_) => 0), 5);
      expect(const Err<int>(NetworkFailure()).getOrElse((_) => 0), 0);
    });
  });
}
