import 'package:flutter/foundation.dart';
import 'package:google_sign_in/google_sign_in.dart';
import 'package:lifedna/core/config/google_auth_config.dart';

/// The credentials Google hands back after a successful consent.
@immutable
class GoogleIdentity {
  const GoogleIdentity({
    required this.email,
    required this.idToken,
    required this.accessToken,
  });

  final String email;

  /// The JWT Firebase verifies. **Null is the failure this whole seam exists
  /// to make visible** — see [GoogleIdentitySource].
  final String? idToken;

  final String? accessToken;

  bool get hasIdToken => idToken != null && idToken!.isNotEmpty;
}

/// The Google half of sign-in, behind an interface.
///
/// `GoogleSignInAccount` has a private constructor, so a repository that talks
/// to `GoogleSignIn` directly cannot be tested against the case that actually
/// broke: a consent that succeeds and returns a **null id token**. That is not
/// an exotic edge — before C-2 it was the only outcome an Android build
/// without `google-services.json` could produce, and it surfaced to the user
/// as "Couldn't sign you in. Please try again." forever.
abstract interface class GoogleIdentitySource {
  /// Runs the consent flow. Null means the user backed out.
  Future<GoogleIdentity?> authenticate();

  Future<void> signOut();
}

/// [GoogleIdentitySource] over the real plugin.
class PluginGoogleIdentitySource implements GoogleIdentitySource {
  PluginGoogleIdentitySource({GoogleSignIn? signIn})
    : _signIn =
          signIn ??
          GoogleSignIn(
            // Without this the plugin never calls requestIdToken and every
            // sign-in returns a null token. See GoogleAuthConfig.
            serverClientId: GoogleAuthConfig.serverClientId,
          );

  final GoogleSignIn _signIn;

  @override
  Future<GoogleIdentity?> authenticate() async {
    final account = await _signIn.signIn();
    if (account == null) return null;

    final tokens = await account.authentication;
    return GoogleIdentity(
      email: account.email,
      idToken: tokens.idToken,
      accessToken: tokens.accessToken,
    );
  }

  @override
  Future<void> signOut() => _signIn.signOut();
}
