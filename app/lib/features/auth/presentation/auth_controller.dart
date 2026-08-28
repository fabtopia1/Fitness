import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:lifedna/core/error/failure.dart';
import 'package:lifedna/core/providers/providers.dart';
import 'package:lifedna/core/result/result.dart';
import 'package:lifedna/features/auth/data/auth_repository.dart';
import 'package:lifedna/features/auth/domain/user_profile.dart';

/// Drives the auth screens.
///
/// Exposes an [AsyncValue] so every screen gets loading and error handling
/// from the same place, rather than each one inventing its own boolean.
class AuthController extends AsyncNotifier<void> {
  @override
  Future<void> build() async {}

  AuthRepository get _auth => ref.read(authRepositoryProvider);

  Future<Failure?> signIn({required String email, required String password}) =>
      _run(() => _auth.signInWithEmail(email: email, password: password));

  Future<Failure?> signUp({
    required String email,
    required String password,
    required String displayName,
  }) => _run(
    () => _auth.signUpWithEmail(
      email: email,
      password: password,
      displayName: displayName,
    ),
  );

  Future<Failure?> signInWithGoogle() => _run(_auth.signInWithGoogle);

  Future<Failure?> continueWithoutAccount() =>
      _run(_auth.continueWithoutAccount);

  Future<Failure?> sendPasswordReset(String email) =>
      _run(() => _auth.sendPasswordReset(email));

  Future<Failure?> signOut() async {
    state = const AsyncValue.loading();
    final result = await _auth.signOut();
    state = const AsyncValue.data(null);
    return result.failureOrNull;
  }

  /// Runs an auth action and, on success, makes sure a profile exists.
  ///
  /// Creating the profile here rather than in a Firestore trigger means a user
  /// who signs up on a plane still has a working account when they land.
  Future<Failure?> _run(Future<Result<Object?>> Function() action) async {
    state = const AsyncValue.loading();
    final result = await action();

    switch (result) {
      case Err(:final failure):
        state = AsyncValue.error(failure, StackTrace.current);
        return failure;
      case Ok(:final value):
        if (value is AuthSession) await _ensureProfile(value);
        state = const AsyncValue.data(null);
        return null;
    }
  }

  Future<void> _ensureProfile(AuthSession session) async {
    final repository = ref.read(profileRepositoryProvider);
    final existing = repository.read();
    if (existing != null && existing.id == session.uid) return;

    // A profile may already exist in the cloud from another device.
    final pulled = await repository.pull();
    if (pulled.valueOrNull != null) return;

    await repository.save(_auth.initialProfile(session));
  }

  /// Completes onboarding with the user's body and goal details.
  Future<Failure?> completeOnboarding(UserProfile profile) async {
    state = const AsyncValue.loading();
    final result = await ref
        .read(profileRepositoryProvider)
        .save(profile.copyWith(onboardingCompletedAt: DateTime.now().toUtc()));
    state = const AsyncValue.data(null);
    return result.failureOrNull;
  }
}

final authControllerProvider = AsyncNotifierProvider<AuthController, void>(
  AuthController.new,
);
