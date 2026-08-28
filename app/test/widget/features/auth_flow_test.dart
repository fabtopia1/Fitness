import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lifedna/core/providers/providers.dart';
import 'package:lifedna/core/router/app_router.dart';
import 'package:lifedna/core/sync/outbox.dart';
import 'package:lifedna/core/widgets/ld_widgets.dart';
import 'package:lifedna/features/auth/data/auth_repository.dart';
import 'package:lifedna/features/auth/data/profile_repository.dart';
import 'package:lifedna/features/auth/presentation/auth_controller.dart';
import 'package:lifedna/features/auth/presentation/onboarding_screen.dart';
import 'package:lifedna/features/auth/presentation/sign_in_screen.dart';
import 'package:lifedna/features/auth/presentation/sign_up_screen.dart';
import 'package:lifedna/features/auth/presentation/welcome_screen.dart';

import '../../support/pump.dart';
import '../../support/test_harness.dart';

void main() {
  late TestEnvironment env;

  setUp(() async => env = await TestEnvironment.create());
  tearDown(() async => env.dispose());

  // Read through plain repositories rather than a ProviderContainer: building
  // a container inside a widget test starts stream subscriptions that schedule
  // Riverpod's zero-duration refresh timer, and the test framework fails a
  // test that ends with one pending.
  AuthRepository auth() => AuthRepository(store: env.store);
  ProfileRepository profiles() =>
      ProfileRepository(store: env.store, outbox: Outbox(env.store));

  group('WelcomeScreen', () {
    testWidgets('offers local mode when the build has no Firebase',
        (tester) async {
      // Local mode is a real supported path, so it is offered plainly rather
      // than hidden behind a debug gesture.
      await pumpScreen(tester, env, const WelcomeScreen());

      expect(find.text('LifeDNA OS'), findsOneWidget);
      expect(find.text('Cloud sync not configured'), findsOneWidget);
      expect(find.text('Continue on this device'), findsOneWidget);
    });

    testWidgets('continuing on this device starts a session', (tester) async {
      await pumpScreen(tester, env, const WelcomeScreen());

      await tester.tap(find.text('Continue on this device'));
      await pumpFrames(tester);

      expect(auth().currentSession, isNotNull);
    });

    testWidgets('the account buttons navigate rather than sign in',
        (tester) async {
      await pumpScreen(tester, env, const WelcomeScreen());

      await tester.tap(find.text('Create account'));
      await pumpFrames(tester);

      expect(currentStubRoute(), Routes.signUp);
    });

    testWidgets('states the app is not a medical device', (tester) async {
      await pumpScreen(tester, env, const WelcomeScreen());
      expect(find.textContaining('not a medical device'), findsOneWidget);
    });
  });

  group('SignUpScreen', () {
    testWidgets('refuses an empty name, a bad email and a short password',
        (tester) async {
      await pumpScreen(tester, env, const SignUpScreen());

      await tester.tap(find.widgetWithText(LdPrimaryButton, 'Create account'));
      await pumpFrames(tester);

      expect(find.text('Enter your name'), findsOneWidget);
      expect(find.text('Enter a valid email address'), findsOneWidget);
      expect(find.text('Use at least 10 characters'), findsOneWidget);
    });

    testWidgets('a valid form creates a session', (tester) async {
      await pumpScreen(tester, env, const SignUpScreen());

      await tester.enterText(find.byType(TextFormField).at(0), 'Sam');
      await tester.enterText(
        find.byType(TextFormField).at(1),
        'sam@example.com',
      );
      await tester.enterText(
        find.byType(TextFormField).at(2),
        'longenoughpassword',
      );
      await tester.tap(find.widgetWithText(LdPrimaryButton, 'Create account'));
      await pumpFrames(tester);

      expect(auth().currentSession?.displayName, 'Sam');
    });

    testWidgets('the password can be revealed', (tester) async {
      await pumpScreen(tester, env, const SignUpScreen());

      expect(find.byIcon(Icons.visibility_rounded), findsOneWidget);
      await tester.tap(find.byIcon(Icons.visibility_rounded));
      await tester.pump();
      expect(find.byIcon(Icons.visibility_off_rounded), findsOneWidget);
    });
  });

  group('SignInScreen', () {
    testWidgets('hides Google sign-in when there is no Firebase to use it',
        (tester) async {
      // A button that cannot work is worse than no button.
      await pumpScreen(tester, env, const SignInScreen());
      expect(find.text('Continue with Google'), findsNothing);
    });

    testWidgets('validates before attempting a sign-in', (tester) async {
      await pumpScreen(tester, env, const SignInScreen());

      await tester.tap(find.widgetWithText(LdPrimaryButton, 'Sign in'));
      await pumpFrames(tester);

      expect(find.text('Enter a valid email address'), findsOneWidget);
    });
  });

  group('OnboardingScreen', () {
    Future<void> signIn() async {
      final repository = auth();
      final session =
          (await repository.continueWithoutAccount()).valueOrNull!;
      await profiles().save(repository.initialProfile(session));
    }

    testWidgets('cannot advance past step one without a date of birth',
        (tester) async {
      await signIn();
      await pumpScreen(tester, env, const OnboardingScreen());
      await pumpFrames(tester);

      expect(find.text('About you'), findsOneWidget);
      expect(find.text('Step 1 of 4'), findsOneWidget);

      // The Continue button is disabled until a date of birth is chosen.
      final button = tester.widget<LdPrimaryButton>(
        find.widgetWithText(LdPrimaryButton, 'Continue'),
      );
      expect(button.onPressed, isNull);
    });

    testWidgets('a missing profile offers sign-out rather than a dead screen',
        (tester) async {
      await pumpScreen(tester, env, const OnboardingScreen());
      await pumpFrames(tester);

      expect(find.text('Profile not found'), findsOneWidget);
      expect(find.text('Sign out'), findsOneWidget);
    });

    testWidgets('walking the whole flow completes onboarding', (tester) async {
      await signIn();
      await pumpScreen(tester, env, const OnboardingScreen());
      await pumpFrames(tester);

      // Step 1 — date of birth and sex.
      await tester.tap(find.text('Select your date of birth'));
      await pumpFrames(tester);
      await tester.tap(find.text('OK'));
      await pumpFrames(tester);
      await tester.tap(find.text('Male'));
      await pumpFrames(tester);
      await tester.tap(find.widgetWithText(LdPrimaryButton, 'Continue'));
      await pumpFrames(tester);

      // Step 2 — measurements.
      expect(find.text('Your measurements'), findsOneWidget);
      await tester.enterText(find.byType(TextFormField).at(0), '180');
      await tester.enterText(find.byType(TextFormField).at(1), '82');
      await tester.tap(find.widgetWithText(LdPrimaryButton, 'Continue'));
      await pumpFrames(tester);

      // Step 3 — goal.
      expect(find.text('Your goal'), findsOneWidget);
      await tester.tap(find.text('Lose fat'));
      await pumpFrames(tester);
      await tester.tap(find.widgetWithText(LdPrimaryButton, 'See my targets'));
      await pumpFrames(tester);

      // Step 4 — the derived targets, shown BEFORE anything is committed.
      expect(find.text('Your targets'), findsOneWidget);
      // Card eyebrows render uppercase.
      expect(find.text('TRAINING DAY'), findsOneWidget);
      expect(find.text('HOW THIS WAS CALCULATED'), findsOneWidget);

      await tester.tap(
        find.widgetWithText(LdPrimaryButton, 'Start using LifeDNA'),
      );
      await pumpFrames(tester);

      final profile = profiles().read()!;
      expect(profile.isOnboarded, isTrue);
      expect(profile.heightCm, 180);
      expect(profile.weightKg, 82);
    });

    testWidgets('measurements outside the plausible range are refused',
        (tester) async {
      await signIn();
      await pumpScreen(tester, env, const OnboardingScreen());
      await pumpFrames(tester);

      await tester.tap(find.text('Select your date of birth'));
      await pumpFrames(tester);
      await tester.tap(find.text('OK'));
      await pumpFrames(tester);
      await tester.tap(find.widgetWithText(LdPrimaryButton, 'Continue'));
      await pumpFrames(tester);

      await tester.enterText(find.byType(TextFormField).at(0), '20');
      await tester.enterText(find.byType(TextFormField).at(1), '5');
      await tester.tap(find.widgetWithText(LdPrimaryButton, 'Continue'));
      await pumpFrames(tester);

      expect(find.textContaining('Enter a height in cm'), findsOneWidget);
      expect(find.text('Your measurements'), findsOneWidget);
    });
  });

  group('AuthController', () {
    test('signing out clears the session', () async {
      final container = env.container();
      addTearDown(container.dispose);

      await container.read(authRepositoryProvider).continueWithoutAccount();
      await container.read(authControllerProvider.notifier).signOut();

      expect(container.read(authRepositoryProvider).currentSession, isNull);
    });
  });
}
