import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:lifedna/features/sync/presentation/sync_providers.dart';

import '../../../support/test_harness.dart';

void main() {
  late TestEnvironment env;

  setUp(() async => env = await TestEnvironment.create());
  tearDown(() async => env.dispose());

  test(
    'local mode has nothing to pull and says so instead of failing',
    () async {
      final container = env.container();
      addTearDown(container.dispose);

      final pull = container.read(remotePullProvider);
      expect(pull.canPull, isFalse);
      expect(await pull.everything(), 0);
    },
  );

  test('a refresh in local mode is a no-op, not an error', () async {
    final container = env.container();
    addTearDown(container.dispose);

    expect(await container.read(remotePullProvider).refresh(), 0);
  });

  test('every collection the app owns is listed in one place', () {
    // A repository added without a line in RemotePull would push its data up
    // and never pull it back — which looks to the user like data that vanished
    // when they changed phones. Asserted against the shipped file rather than
    // a copy of the list, which could drift from it.
    final source = File('lib/features/sync/presentation/sync_providers.dart')
        .readAsStringSync();

    for (final repository in const [
      'nutritionRepositoryProvider',
      'workoutRepositoryProvider',
      'supplementRepositoryProvider',
      'bodyRepositoryProvider',
      'calendarRepositoryProvider',
      'reminderRepositoryProvider',
      'settingsRepositoryProvider',
      'profileRepositoryProvider',
    ]) {
      expect(source, contains(repository), reason: repository);
    }
  });
}
