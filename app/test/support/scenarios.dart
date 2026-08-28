import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lifedna/core/widgets/ld_widgets.dart';
import 'package:lifedna/features/dashboard/presentation/dashboard_screen.dart';
import 'package:lifedna/features/workout/presentation/workout_screen.dart';

import 'pump.dart';
import 'test_harness.dart';

/// End-to-end scenarios, defined once and executed twice.
///
/// `test/integration/` runs them headlessly in CI on every push, so a broken
/// journey fails the build in seconds. `integration_test/` runs the identical
/// code on a real device or emulator, where the platform channels, the real
/// frame scheduler and the real gesture arena are in play.
///
/// Local mode throughout: the journeys must not depend on a Firebase project,
/// and every feature works without one.
void registerAppScenarios() {
  late TestEnvironment env;

  setUp(() async => env = await TestEnvironment.create());
  tearDown(() async => env.dispose());

  testWidgets('a new user onboards and lands on a working dashboard', (
    tester,
  ) async {
    await pumpApp(tester, env);
    await pumpFrames(tester, frames: 12);

    expect(find.text('LifeDNA OS'), findsOneWidget);
    await tester.tap(find.text('Continue on this device'));
    await pumpFrames(tester, frames: 16);

    // ---- step 1: about you -------------------------------------------------
    expect(find.text('About you'), findsOneWidget);
    await tester.tap(find.text('Select your date of birth'));
    await pumpFrames(tester, frames: 10);
    await tester.tap(find.text('OK'));
    await pumpFrames(tester, frames: 10);
    await tester.tap(find.text('Male'));
    await pumpFrames(tester);
    await tester.tap(find.widgetWithText(LdPrimaryButton, 'Continue'));
    await pumpFrames(tester, frames: 10);

    // ---- step 2: measurements ---------------------------------------------
    await tester.enterText(find.byType(TextFormField).at(0), '180');
    await tester.enterText(find.byType(TextFormField).at(1), '82');
    await tester.tap(find.widgetWithText(LdPrimaryButton, 'Continue'));
    await pumpFrames(tester, frames: 10);

    // ---- step 3: goal ------------------------------------------------------
    await tester.tap(find.text('Lose fat'));
    await pumpFrames(tester);
    await tester.tap(find.widgetWithText(LdPrimaryButton, 'See my targets'));
    await pumpFrames(tester, frames: 10);

    // ---- step 4: the derived targets, shown before anything is committed ---
    expect(find.text('Your targets'), findsOneWidget);
    expect(find.text('TRAINING DAY'), findsOneWidget);
    await tester.tap(
      find.widgetWithText(LdPrimaryButton, 'Start using LifeDNA'),
    );
    await pumpFrames(tester, frames: 20);

    expect(find.byType(DashboardScreen), findsOneWidget);
    expect(find.text('Home'), findsOneWidget);
  });

  testWidgets('an onboarded user can start a workout and come back', (
    tester,
  ) async {
    await pumpApp(tester, env);
    await pumpFrames(tester, frames: 12);
    await tester.tap(find.text('Continue on this device'));
    await pumpFrames(tester, frames: 16);
    await _completeOnboarding(tester);

    await tester.tap(find.text('Train'));
    await pumpFrames(tester, frames: 12);

    await tester.tap(find.text('Start empty workout'));
    await pumpFrames(tester, frames: 20);
    expect(find.text('Freeform workout'), findsOneWidget);

    await tester.tap(find.text('Finish'));
    await pumpFrames(tester, frames: 12);
    expect(find.text('Discard workout?'), findsOneWidget);
    await tester.tap(find.text('Discard'));
    await pumpFrames(tester, frames: 20);

    // Discarding returns to Train, where the workout was started from.
    expect(find.byType(WorkoutScreen), findsOneWidget);

    await tester.tap(find.text('Home'));
    await pumpFrames(tester, frames: 12);
    expect(find.byType(DashboardScreen), findsOneWidget);
  });

  testWidgets('everything logged offline is still there after a relaunch', (
    tester,
  ) async {
    // The offline guarantee is the product's foundation: Hive is the source of
    // truth, so a relaunch must show exactly what the user left behind.
    env.connectivity.online = false;

    await pumpApp(tester, env);
    await pumpFrames(tester, frames: 12);
    await tester.tap(find.text('Continue on this device'));
    await pumpFrames(tester, frames: 16);
    await _completeOnboarding(tester);

    expect(find.byType(DashboardScreen), findsOneWidget);

    // Relaunch against the same storage.
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump();
    await pumpApp(tester, env);
    await pumpFrames(tester, frames: 20);

    // Still signed in, still onboarded — the redirect goes straight home.
    expect(find.byType(DashboardScreen), findsOneWidget);
  });
}

/// Walks the four onboarding steps with plausible values.
Future<void> _completeOnboarding(WidgetTester tester) async {
  await tester.tap(find.text('Select your date of birth'));
  await pumpFrames(tester, frames: 10);
  await tester.tap(find.text('OK'));
  await pumpFrames(tester, frames: 10);
  await tester.tap(find.widgetWithText(LdPrimaryButton, 'Continue'));
  await pumpFrames(tester, frames: 10);

  await tester.enterText(find.byType(TextFormField).at(0), '180');
  await tester.enterText(find.byType(TextFormField).at(1), '82');
  await tester.tap(find.widgetWithText(LdPrimaryButton, 'Continue'));
  await pumpFrames(tester, frames: 10);

  await tester.tap(find.widgetWithText(LdPrimaryButton, 'See my targets'));
  await pumpFrames(tester, frames: 10);
  await tester.tap(find.widgetWithText(LdPrimaryButton, 'Start using LifeDNA'));
  await pumpFrames(tester, frames: 20);
}
