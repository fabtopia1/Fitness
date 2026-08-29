import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lifedna/core/storage/storage_mode.dart';
import 'package:lifedna/core/storage/storage_recovery_screen.dart';
import 'package:lifedna/core/widgets/ld_widgets.dart';

/// The screen that replaces the permanent lockout.
///
/// The bug this closes was not the storage failure itself — it was that the
/// only affordance offered was a retry that could never succeed. These tests
/// pin the two properties that make it a recovery rather than a dead end: the
/// destructive action is reachable, and it is never one tap away.
void main() {
  Future<void> pump(
    WidgetTester tester, {
    StorageFailureReason reason = StorageFailureReason.keyUnavailable,
    Future<void> Function()? onReset,
    Future<void> Function()? onRetry,
  }) async {
    await tester.binding.setSurfaceSize(const Size(400, 900));
    addTearDown(() => tester.binding.setSurfaceSize(null));

    await tester.pumpWidget(
      StorageRecoveryApp(
        failure: StorageUnavailable(reason),
        onReset: onReset ?? () async {},
        onRetry: onRetry ?? () async {},
      ),
    );
    await tester.pump();
  }

  testWidgets('names what happened, in words a user can act on', (
    tester,
  ) async {
    await pump(tester);

    expect(find.text("Your data can't be unlocked"), findsOneWidget);
    expect(find.textContaining('restored from another device'), findsOneWidget);
    // Never a stack trace, never an exception type.
    expect(find.textContaining('Exception'), findsNothing);
  });

  testWidgets('offers a retry, because a keystore can be briefly unavailable', (
    tester,
  ) async {
    var retries = 0;
    await pump(tester, onRetry: () async => retries++);

    await tester.tap(find.widgetWithText(LdPrimaryButton, 'Try again'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 50));

    expect(retries, 1);
  });

  testWidgets('resetting is two taps, not one', (tester) async {
    // The action destroys local data. It must be reachable and it must not be
    // possible to trip over.
    var resets = 0;
    await pump(tester, onReset: () async => resets++);

    await tester.tap(
      find.widgetWithText(LdPrimaryButton, 'Reset this phone’s data'),
    );
    await tester.pump();

    expect(resets, 0, reason: 'the first tap only asks');
    expect(find.textContaining('permanently'), findsOneWidget);

    await tester.tap(
      find.widgetWithText(LdPrimaryButton, 'Reset and continue'),
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 50));

    expect(resets, 1);
  });

  testWidgets('the confirmation can be backed out of', (tester) async {
    var resets = 0;
    await pump(tester, onReset: () async => resets++);

    await tester.tap(
      find.widgetWithText(LdPrimaryButton, 'Reset this phone’s data'),
    );
    await tester.pump();
    await tester.tap(find.widgetWithText(LdPrimaryButton, 'Cancel'));
    await tester.pump();

    expect(resets, 0);
    expect(find.widgetWithText(LdPrimaryButton, 'Try again'), findsOneWidget);
  });

  testWidgets('states the cost of resetting before the destructive tap', (
    tester,
  ) async {
    // This build has no Firebase configuration, so there is nothing to restore
    // from and the copy has to say so rather than implying a safety net.
    await pump(tester);
    await tester.tap(
      find.widgetWithText(LdPrimaryButton, 'Reset this phone’s data'),
    );
    await tester.pump();

    expect(find.text(StorageUnavailable.resetWarningLocal), findsOneWidget);
  });

  testWidgets('every failure reason renders without an error', (tester) async {
    for (final reason in StorageFailureReason.values) {
      await pump(tester, reason: reason);

      expect(find.byType(StorageRecoveryScreen), findsOneWidget);
      expect(find.textContaining(reason.name), findsOneWidget);
      expect(tester.takeException(), isNull, reason: reason.name);
    }
  });
}
