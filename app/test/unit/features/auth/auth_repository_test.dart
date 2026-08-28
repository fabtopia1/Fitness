import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:firebase_auth_mocks/firebase_auth_mocks.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lifedna/core/error/failure.dart';
import 'package:lifedna/core/storage/hive_store.dart';
import 'package:lifedna/core/sync/outbox.dart';
import 'package:lifedna/features/auth/data/auth_repository.dart';
import 'package:lifedna/features/auth/data/profile_repository.dart';
import 'package:lifedna/features/auth/domain/user_profile.dart';
import 'package:lifedna/shared/enums/enums.dart';

import '../../../support/test_harness.dart';

void main() {
  late TestEnvironment env;

  setUp(() async => env = await TestEnvironment.create());
  tearDown(() async => env.dispose());

  group('credential validation', () {
    late AuthRepository auth;
    setUp(() => auth = AuthRepository(store: env.store));

    test('sign-up requires a name, a valid email and 10+ characters',
        () async {
      Future<Failure?> attempt(String email, String password, String name) =>
          auth
              .signUpWithEmail(
                email: email,
                password: password,
                displayName: name,
              )
              .then((r) => r.failureOrNull);

      expect(
        await attempt('a@b.com', 'longenough1', '  '),
        isA<ValidationFailure>()
            .having((f) => f.code, 'code', 'name_required'),
      );
      expect(
        await attempt('not-an-email', 'longenough1', 'Sam'),
        isA<ValidationFailure>()
            .having((f) => f.code, 'code', 'email_invalid'),
      );
      expect(
        await attempt('a@b.com', 'short', 'Sam'),
        isA<ValidationFailure>()
            .having((f) => f.code, 'code', 'password_too_short'),
      );
    });

    test('sign-in rejects a malformed email and an empty password', () async {
      expect(
        (await auth.signInWithEmail(email: 'nope', password: 'x'))
            .failureOrNull,
        isA<ValidationFailure>(),
      );
      expect(
        (await auth.signInWithEmail(email: 'a@b.com', password: ''))
            .failureOrNull,
        isA<ValidationFailure>(),
      );
    });
  });

  group('local mode', () {
    late AuthRepository auth;
    setUp(() => auth = AuthRepository(store: env.store));

    test('is not cloud backed and says so on the session', () async {
      expect(auth.isCloudBacked, isFalse);

      final session =
          (await auth.continueWithoutAccount()).valueOrNull!;
      expect(session.isLocalOnly, isTrue);
      expect(session.uid, startsWith('local_'));
    });

    test('the session persists and is emitted by the auth stream', () async {
      final emitted = <AuthSession?>[];
      final sub = auth.authStateChanges().listen(emitted.add);
      await Future<void>.delayed(Duration.zero);

      await auth.continueWithoutAccount();
      await Future<void>.delayed(Duration.zero);

      expect(auth.currentSession, isNotNull);
      expect(emitted.last?.isLocalOnly, isTrue);
      await sub.cancel();
    });

    test('signing in twice keeps the same uid, so data is not orphaned',
        () async {
      final first = (await auth.continueWithoutAccount()).valueOrNull!;
      final second = (await auth.signInWithEmail(
        email: 'sam@example.com',
        password: 'longenough1',
      ))
          .valueOrNull!;

      expect(second.uid, first.uid);
      expect(second.email, 'sam@example.com');
    });

    test('a password reset has nowhere to go and reports that', () async {
      final result = await auth.sendPasswordReset('sam@example.com');
      expect(
        result.failureOrNull,
        isA<ServerFailure>()
            .having((f) => f.code, 'code', 'firebase_unavailable'),
      );
    });

    test('Google sign-in is unavailable rather than silently failing',
        () async {
      expect(
        (await auth.signInWithGoogle()).failureOrNull,
        isA<ServerFailure>(),
      );
    });

    test('signing out wipes every local box', () async {
      // On a shared device, leaving one account's training log behind for the
      // next person would be a serious privacy failure.
      await auth.continueWithoutAccount();
      await env.store.write(HiveStore.boxWorkouts, 'w', {'id': 'w'});

      await auth.signOut();

      expect(auth.currentSession, isNull);
      expect(env.store.readAll(HiveStore.boxWorkouts), isEmpty);
    });
  });

  group('cloud mode', () {
    late MockFirebaseAuth firebaseAuth;
    late AuthRepository auth;

    setUp(() {
      firebaseAuth = MockFirebaseAuth(
        mockUser: MockUser(
          uid: 'u1',
          email: 'sam@example.com',
          displayName: 'Sam',
          isEmailVerified: true,
        ),
      );
      auth = AuthRepository(store: env.store, firebaseAuth: firebaseAuth);
    });

    test('is cloud backed', () => expect(auth.isCloudBacked, isTrue));

    test('a successful sign-in maps the Firebase user onto a session',
        () async {
      final session = (await auth.signInWithEmail(
        email: 'sam@example.com',
        password: 'longenough1',
      ))
          .valueOrNull!;

      expect(session.uid, 'u1');
      expect(session.displayName, 'Sam');
      expect(session.isLocalOnly, isFalse);
      expect(session.emailVerified, isTrue);
    });

    test('the initial profile is built from the session', () async {
      final session = (await auth.signInWithEmail(
        email: 'sam@example.com',
        password: 'longenough1',
      ))
          .valueOrNull!;

      final profile = auth.initialProfile(session);
      expect(profile.id, 'u1');
      expect(profile.email, 'sam@example.com');
      expect(profile.isOnboarded, isFalse);
    });

    test('signing out clears the session and the local boxes', () async {
      await auth.signInWithEmail(
        email: 'sam@example.com',
        password: 'longenough1',
      );
      await env.store.write(HiveStore.boxWorkouts, 'w', {'id': 'w'});

      await auth.signOut();

      expect(auth.currentSession, isNull);
      expect(env.store.readAll(HiveStore.boxWorkouts), isEmpty);
    });
  });

  group('ProfileRepository', () {
    UserProfile profile({DateTime? updatedAt}) => UserProfile.initial(
          uid: 'u1',
          email: 'sam@example.com',
          displayName: 'Sam',
          now: updatedAt ?? DateTime.utc(2026),
        );

    test('saving stores locally and queues replication', () async {
      final repository = ProfileRepository(
        store: env.store,
        outbox: Outbox(env.store),
      );

      await repository.save(profile());

      expect(repository.read()?.displayName, 'Sam');
      expect(Outbox(env.store).length, 1);
    });

    test('the queued entry is routed to the user document', () async {
      final outbox = Outbox(env.store);
      await ProfileRepository(store: env.store, outbox: outbox)
          .save(profile());

      expect(
        outbox.pending().single.collection,
        Outbox.profileCollection,
      );
    });

    test('watch emits the stored profile', () async {
      final repository = ProfileRepository(
        store: env.store,
        outbox: Outbox(env.store),
      );

      final seen = <UserProfile?>[];
      final sub = repository.watch().listen(seen.add);
      await Future<void>.delayed(Duration.zero);
      await repository.save(profile());
      await Future<void>.delayed(Duration.zero);

      expect(seen.first, isNull);
      expect(seen.last?.displayName, 'Sam');
      await sub.cancel();
    });

    test('pull without a backend reports it rather than returning empty',
        () async {
      final result = await ProfileRepository(
        store: env.store,
        outbox: Outbox(env.store),
      ).pull();
      expect(result.failureOrNull, isA<ServerFailure>());
    });

    test('pull applies a newer remote profile and ignores a stale one',
        () async {
      final firestore = FakeFirebaseFirestore();
      final repository = ProfileRepository(
        store: env.store,
        outbox: Outbox(env.store),
        firestore: firestore,
        uid: 'u1',
      );

      await repository.save(
        profile(updatedAt: DateTime.utc(2026, 6)).copyWith(
          displayName: 'Local Sam',
          updatedAt: DateTime.utc(2026, 6),
        ),
      );

      await firestore.collection('users').doc('u1').set(
            profile()
                .copyWith(
                  displayName: 'Stale Sam',
                  updatedAt: DateTime.utc(2026, 1),
                )
                .toJson(),
          );

      await repository.pull();
      expect(repository.read()?.displayName, 'Local Sam');

      await firestore.collection('users').doc('u1').set(
            profile()
                .copyWith(
                  displayName: 'Newer Sam',
                  updatedAt: DateTime.utc(2026, 12),
                )
                .toJson(),
          );

      await repository.pull();
      expect(repository.read()?.displayName, 'Newer Sam');
    });
  });

  group('UserProfile', () {
    test('targets are derived, so editing a bodyweight cannot leave a stale '
        'goal behind', () {
      final profile = UserProfile.initial(
        uid: 'u1',
        email: 'sam@example.com',
        displayName: 'Sam',
      ).copyWith(
        dateOfBirth: DateTime(2000, 1, 1),
        sex: Sex.male,
        heightCm: 180,
        weightKg: 80,
      );

      final before = profile.computedTargets!.trainingDay.kcal;
      final after = profile.copyWith(weightKg: 90).computedTargets!
          .trainingDay
          .kcal;

      expect(after, greaterThan(before));
    });

    test('targets are null until the body basics exist', () {
      final profile = UserProfile.initial(
        uid: 'u1',
        email: 'sam@example.com',
        displayName: 'Sam',
      );
      expect(profile.hasBodyBasics, isFalse);
      expect(profile.computedTargets, isNull);
    });

    test('age accounts for a birthday that has not happened yet', () {
      final profile = UserProfile.initial(
        uid: 'u1',
        email: 'a@b.com',
        displayName: 'Sam',
      ).copyWith(
        dateOfBirth: DateTime(
          DateTime.now().year - 30,
          DateTime.now().month,
          DateTime.now().day,
        ).add(const Duration(days: 1)),
      );
      expect(profile.age, 29);
    });

    test('survives a JSON round-trip', () {
      final profile = UserProfile.initial(
        uid: 'u1',
        email: 'sam@example.com',
        displayName: 'Sam',
      ).copyWith(
        dateOfBirth: DateTime(2000, 5, 4),
        sex: Sex.female,
        heightCm: 165,
        weightKg: 62,
        goalMode: GoalMode.cut,
        activityLevel: ActivityLevel.active,
        onboardingCompletedAt: DateTime.utc(2026, 2, 2),
      );

      final restored = UserProfile.fromJson(profile.toJson());
      expect(restored.sex, Sex.female);
      expect(restored.goalMode, GoalMode.cut);
      expect(restored.activityLevel, ActivityLevel.active);
      expect(restored.isOnboarded, isTrue);
      expect(restored.heightCm, 165);
    });
  });
}
