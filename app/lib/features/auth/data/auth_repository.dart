import 'dart:async';

import 'package:firebase_auth/firebase_auth.dart' as fb;
import 'package:google_sign_in/google_sign_in.dart';
import 'package:lifedna/core/config/env.dart';
import 'package:lifedna/core/data/synced_entity.dart';
import 'package:lifedna/core/error/failure.dart';
import 'package:lifedna/core/error/failure_mapper.dart';
import 'package:lifedna/core/result/result.dart';
import 'package:lifedna/core/storage/hive_store.dart';
import 'package:lifedna/features/auth/domain/user_profile.dart';
import 'package:uuid/uuid.dart';

/// The signed-in identity, independent of which backend produced it.
class AuthSession {
  const AuthSession({
    required this.uid,
    required this.email,
    required this.displayName,
    this.photoUrl,
    this.isLocalOnly = false,
    this.emailVerified = false,
  });

  final String uid;
  final String email;
  final String displayName;
  final String? photoUrl;

  /// True when this session exists only on this device because Firebase is not
  /// configured. Everything works; nothing replicates.
  final bool isLocalOnly;

  final bool emailVerified;
}

/// Authentication.
///
/// Supports three paths: email/password, Google, and — when Firebase is not
/// configured in this build — a device-local session so the app is still fully
/// usable and testable. The local path is a real supported mode, not a stub:
/// Hive is the source of truth in every mode, so nothing about the app's
/// behaviour changes except whether data leaves the device.
class AuthRepository {
  AuthRepository({
    required HiveStore store,
    fb.FirebaseAuth? firebaseAuth,
    GoogleSignIn? googleSignIn,
    Uuid uuid = const Uuid(),
  })  : _store = store,
        _auth = firebaseAuth,
        _googleSignIn = googleSignIn,
        _uuid = uuid;

  final HiveStore _store;
  final fb.FirebaseAuth? _auth;
  final GoogleSignIn? _googleSignIn;
  final Uuid _uuid;

  static const _localSessionKey = 'local_session';

  bool get isCloudBacked => _auth != null;

  /// Emits the current session, and again on every sign-in / sign-out.
  Stream<AuthSession?> authStateChanges() {
    final auth = _auth;
    if (auth == null) {
      // Local mode: the session lives in Hive, so watch that instead.
      return _store
          .watchOne(HiveStore.boxMeta, _localSessionKey)
          .map((json) => json == null ? null : _sessionFromJson(json));
    }
    return auth.authStateChanges().map(
          (user) => user == null ? null : _sessionFromFirebase(user),
        );
  }

  AuthSession? get currentSession {
    final auth = _auth;
    if (auth == null) {
      final json = _store.read(HiveStore.boxMeta, _localSessionKey);
      return json == null ? null : _sessionFromJson(json);
    }
    final user = auth.currentUser;
    return user == null ? null : _sessionFromFirebase(user);
  }

  // ------------------------------------------------------------ email/password

  Future<Result<AuthSession>> signUpWithEmail({
    required String email,
    required String password,
    required String displayName,
  }) async {
    final validation = _validateCredentials(email, password, displayName);
    if (validation != null) return Err(validation);

    final auth = _auth;
    if (auth == null) {
      return _startLocalSession(email: email, displayName: displayName);
    }

    try {
      final credential = await auth
          .createUserWithEmailAndPassword(email: email.trim(), password: password)
          .timeout(Env.networkTimeout);

      await credential.user?.updateDisplayName(displayName.trim());
      // Verification is sent but NOT enforced. Blocking a new user from their
      // own data behind an email they may not receive is a needless funnel
      // cut; the app gates nothing on it.
      unawaited(credential.user?.sendEmailVerification());
      await credential.user?.reload();

      final user = auth.currentUser;
      if (user == null) {
        return const Err(AuthFailure('sign_up_failed'));
      }
      return Ok(_sessionFromFirebase(user, fallbackName: displayName));
    } on Object catch (error, stackTrace) {
      return Err(FailureMapper.from(error, stackTrace));
    }
  }

  Future<Result<AuthSession>> signInWithEmail({
    required String email,
    required String password,
  }) async {
    if (!_isValidEmail(email)) {
      return const Err(ValidationFailure('email_invalid', field: 'email'));
    }
    if (password.isEmpty) {
      return const Err(ValidationFailure('required', field: 'password'));
    }

    final auth = _auth;
    if (auth == null) {
      return _startLocalSession(
        email: email,
        displayName: email.split('@').first,
      );
    }

    try {
      final credential = await auth
          .signInWithEmailAndPassword(email: email.trim(), password: password)
          .timeout(Env.networkTimeout);
      final user = credential.user;
      if (user == null) return const Err(AuthFailure('sign_in_failed'));
      return Ok(_sessionFromFirebase(user));
    } on Object catch (error, stackTrace) {
      return Err(FailureMapper.from(error, stackTrace));
    }
  }

  Future<Result<void>> sendPasswordReset(String email) async {
    if (!_isValidEmail(email)) {
      return const Err(ValidationFailure('email_invalid', field: 'email'));
    }
    final auth = _auth;
    if (auth == null) {
      return const Err(ServerFailure('firebase_unavailable'));
    }
    try {
      await auth
          .sendPasswordResetEmail(email: email.trim())
          .timeout(Env.networkTimeout);
      return const Ok(null);
    } on Object catch (error, stackTrace) {
      return Err(FailureMapper.from(error, stackTrace));
    }
  }

  // ------------------------------------------------------------------- Google

  Future<Result<AuthSession>> signInWithGoogle() async {
    final auth = _auth;
    final google = _googleSignIn;
    if (auth == null || google == null) {
      return const Err(ServerFailure('firebase_unavailable'));
    }

    try {
      final account = await google.signIn();
      if (account == null) {
        // The user backed out. Not an error — but the caller needs to know
        // nothing happened, so it is still a failure result.
        return const Err(AuthFailure('sign_in_canceled'));
      }

      final tokens = await account.authentication;
      final credential = fb.GoogleAuthProvider.credential(
        accessToken: tokens.accessToken,
        idToken: tokens.idToken,
      );

      final result =
          await auth.signInWithCredential(credential).timeout(Env.networkTimeout);
      final user = result.user;
      if (user == null) return const Err(AuthFailure('sign_in_failed'));
      return Ok(_sessionFromFirebase(user));
    } on Object catch (error, stackTrace) {
      return Err(FailureMapper.from(error, stackTrace));
    }
  }

  // ------------------------------------------------------------------ session

  /// Signs out and wipes every local box.
  ///
  /// Wiping is not optional: on a shared device, leaving one account's
  /// training log in Hive for the next person to read would be a serious
  /// privacy failure.
  Future<Result<void>> signOut() async {
    try {
      await _googleSignIn?.signOut();
      await _auth?.signOut();
      await _store.delete(HiveStore.boxMeta, _localSessionKey);
      await _store.clearAll();
      return const Ok(null);
    } on Object catch (error, stackTrace) {
      return Err(FailureMapper.from(error, stackTrace));
    }
  }

  /// Deletes the account and all local data.
  ///
  /// Firestore documents are removed by the caller before this runs; this
  /// method ends the identity itself.
  Future<Result<void>> deleteAccount() async {
    final auth = _auth;
    try {
      if (auth != null) {
        final user = auth.currentUser;
        if (user == null) return const Err(AuthFailure('no_current_user'));
        await user.delete().timeout(Env.networkTimeout);
      }
      await _store.delete(HiveStore.boxMeta, _localSessionKey);
      await _store.clearAll();
      return const Ok(null);
    } on Object catch (error, stackTrace) {
      return Err(FailureMapper.from(error, stackTrace));
    }
  }

  // -------------------------------------------------------------- local mode

  Future<Result<AuthSession>> _startLocalSession({
    required String email,
    required String displayName,
  }) async {
    final existing = _store.read(HiveStore.boxMeta, _localSessionKey);
    final uid = existing == null
        ? 'local_${_uuid.v4()}'
        : Json.string(existing['uid']);

    final session = AuthSession(
      uid: uid,
      email: email.trim(),
      displayName: displayName.trim(),
      isLocalOnly: true,
    );
    await _store.write(HiveStore.boxMeta, _localSessionKey, {
      'uid': session.uid,
      'email': session.email,
      'displayName': session.displayName,
      'isLocalOnly': true,
    });
    return Ok(session);
  }

  /// Starts a session with no credentials at all, for local mode.
  Future<Result<AuthSession>> continueWithoutAccount() =>
      _startLocalSession(email: 'local@device', displayName: 'Athlete');

  // -------------------------------------------------------------- validation

  static bool _isValidEmail(String email) =>
      RegExp(r'^[\w.+-]+@[\w-]+\.[\w.-]+$').hasMatch(email.trim());

  static Failure? _validateCredentials(
    String email,
    String password,
    String displayName,
  ) {
    if (displayName.trim().isEmpty) {
      return const ValidationFailure('name_required', field: 'displayName');
    }
    if (!_isValidEmail(email)) {
      return const ValidationFailure('email_invalid', field: 'email');
    }
    if (password.length < 10) {
      return const ValidationFailure('password_too_short', field: 'password');
    }
    return null;
  }

  AuthSession _sessionFromFirebase(fb.User user, {String? fallbackName}) =>
      AuthSession(
        uid: user.uid,
        email: user.email ?? '',
        displayName: user.displayName?.isNotEmpty ?? false
            ? user.displayName!
            : (fallbackName ?? user.email?.split('@').first ?? 'Athlete'),
        photoUrl: user.photoURL,
        emailVerified: user.emailVerified,
      );

  AuthSession _sessionFromJson(Map<String, dynamic> json) => AuthSession(
        uid: Json.string(json['uid']),
        email: Json.string(json['email']),
        displayName: Json.string(json['displayName'], 'Athlete'),
        isLocalOnly: Json.boolean(json['isLocalOnly'], true),
      );

  /// Builds the initial profile written on first sign-in.
  UserProfile initialProfile(AuthSession session) => UserProfile.initial(
        uid: session.uid,
        email: session.email,
        displayName: session.displayName,
        photoUrl: session.photoUrl,
      );
}
