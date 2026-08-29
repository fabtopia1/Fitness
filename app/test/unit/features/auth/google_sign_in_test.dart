import 'package:firebase_auth_mocks/firebase_auth_mocks.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lifedna/core/error/failure.dart';
import 'package:lifedna/core/error/failure_mapper.dart';
import 'package:lifedna/features/auth/data/auth_repository.dart';
import 'package:lifedna/features/auth/data/google_identity.dart';

import '../../../support/test_harness.dart';

/// C-2 regression suite.
///
/// The defect: `GoogleSignIn()` was constructed with no `serverClientId`, and
/// the Gradle plugin that generates the `default_web_client_id` fallback was
/// never applied. The Android plugin therefore never called `requestIdToken`,
/// so consent succeeded and `idToken` came back **null**. That null went
/// straight into `GoogleAuthProvider.credential`, Firebase rejected it, and
/// the user got "Couldn't sign you in. Please try again." on every attempt
/// forever — with nothing in the message distinguishing a build
/// misconfiguration from a bad network.
///
/// `GoogleSignInAccount` has a private constructor, so this case could not be
/// tested at all until the plugin went behind [GoogleIdentitySource].
class _FakeGoogle implements GoogleIdentitySource {
  _FakeGoogle(this._result);

  final GoogleIdentity? _result;
  int signOuts = 0;
  int authentications = 0;

  @override
  Future<GoogleIdentity?> authenticate() async {
    authentications++;
    return _result;
  }

  @override
  Future<void> signOut() async => signOuts++;
}

const _goodIdentity = GoogleIdentity(
  email: 'sam@example.com',
  idToken: 'a.real.jwt',
  accessToken: 'ya29.token',
);

void main() {
  late TestEnvironment env;

  setUp(() async => env = await TestEnvironment.create());
  tearDown(() async => env.dispose());

  AuthRepository build(GoogleIdentitySource google) => AuthRepository(
    store: env.store,
    firebaseAuth: MockFirebaseAuth(),
    google: google,
  );

  group('a sign-in that returns no id token', () {
    test('fails with a code that names the cause', () async {
      final google = _FakeGoogle(
        const GoogleIdentity(
          email: 'sam@example.com',
          idToken: null,
          accessToken: 'ya29.token',
        ),
      );

      final failure = (await build(google).signInWithGoogle()).failureOrNull;

      expect(
        failure,
        isA<AuthFailure>().having(
          (f) => f.code,
          'code',
          'google_id_token_missing',
        ),
      );
    });

    test('an empty token is treated exactly like a missing one', () async {
      // The plugin returns '' in some failure modes rather than null, and the
      // distinction is meaningless to Firebase.
      final google = _FakeGoogle(
        const GoogleIdentity(
          email: 'sam@example.com',
          idToken: '',
          accessToken: 'ya29.token',
        ),
      );

      expect(
        (await build(google).signInWithGoogle()).failureOrNull,
        isA<AuthFailure>().having(
          (f) => f.code,
          'code',
          'google_id_token_missing',
        ),
      );
    });

    test('drops the half-established Google session', () async {
      // Without this, Google keeps the account selected and every retry
      // reproduces the same failure without even showing the picker — which
      // reads to the user as the app being frozen.
      final google = _FakeGoogle(
        const GoogleIdentity(
          email: 'sam@example.com',
          idToken: null,
          accessToken: null,
        ),
      );

      await build(google).signInWithGoogle();

      expect(google.signOuts, 1);
    });

    test('the user is told what is actually wrong', () async {
      final message = FailureMapper.message(
        const AuthFailure('google_id_token_missing'),
      );

      expect(message.title, isNotEmpty);
      expect(message.body, contains('email'));
      // Not the generic "try again", which is what made this unreportable:
      // fifty testers all describing a different symptom.
      expect(message.title, isNot("Couldn't sign you in"));
    });
  });

  group('the paths that must keep working', () {
    test('a complete identity signs in', () async {
      final google = _FakeGoogle(_goodIdentity);

      final result = await build(google).signInWithGoogle();

      expect(result.isOk, isTrue);
      expect(google.signOuts, 0, reason: 'a good sign-in is not undone');
    });

    test('backing out of the picker is a cancellation, not an error', () async {
      final google = _FakeGoogle(null);

      expect(
        (await build(google).signInWithGoogle()).failureOrNull,
        isA<AuthFailure>().having((f) => f.code, 'code', 'sign_in_canceled'),
      );
      expect(google.signOuts, 0);
    });

    test('a build with no Firebase says so instead of opening a picker', () {
      final google = _FakeGoogle(_goodIdentity);
      final auth = AuthRepository(store: env.store, google: google);

      return auth.signInWithGoogle().then((result) {
        expect(
          result.failureOrNull,
          isA<ServerFailure>().having(
            (f) => f.code,
            'code',
            'firebase_unavailable',
          ),
        );
        expect(
          google.authentications,
          0,
          reason: 'never prompt for consent the app cannot use',
        );
      });
    });

    test('signing out ends the Google session too', () async {
      final google = _FakeGoogle(_goodIdentity);
      final auth = build(google);
      await auth.signInWithGoogle();

      await auth.signOut();

      expect(google.signOuts, 1);
    });
  });
}
