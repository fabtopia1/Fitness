import 'package:flutter_test/flutter_test.dart';
import 'package:lifedna/core/config/google_auth_config.dart';

/// C-2, the configuration half.
///
/// These run against the ambient build, which supplies no `--dart-define`s, so
/// they pin the *shape* of the contract rather than any project's ids: what an
/// unconfigured build reports, and that nothing here ever hands the plugin an
/// empty string. Whether the real ids are correct is a build-time question,
/// answered by `docs/mvp/18-google-auth-verification.md`.
void main() {
  group('an unconfigured build', () {
    test('reports no explicit client id rather than an empty one', () {
      // Empty and null are not interchangeable at the call site: the plugin
      // checks `isNullOrEmpty`, but GoogleSignIn(serverClientId: '') also
      // suppresses the file-based fallback in the Dart layer. Null is the only
      // value that means "use google-services.json if it is there".
      expect(GoogleAuthConfig.serverClientId, isNull);
      expect(GoogleAuthConfig.isExplicit, isFalse);
    });

    test('is not reported as malformed — absent is not the same as wrong', () {
      expect(GoogleAuthConfig.isMalformed, isFalse);
    });

    test('leaves Calendar locked instead of half-configured', () {
      expect(GoogleAuthConfig.calendarServerClientId, isNull);
    });
  });

  group('malformed detection catches the pastes that produce a null token', () {
    // The runtime symptom of every one of these is identical and silent:
    // requestIdToken is called with something Firebase will not verify, and
    // the user sees a generic retry.
    bool malformed(String id) => !GoogleAuthConfig.looksLikeClientId(id);

    test('a project id is not a client id', () {
      expect(malformed('lifedna-prod'), isTrue);
    });

    test('a sender id is not a client id', () {
      expect(malformed('123456789012'), isTrue);
    });

    test('a truncated paste is rejected', () {
      expect(malformed('.apps.googleusercontent.com'), isTrue);
      expect(malformed('123456789012-abcdef'), isTrue);
    });

    test('a real web client id passes', () {
      expect(
        malformed('123456789012-abc123def456.apps.googleusercontent.com'),
        isFalse,
      );
    });
  });
}
