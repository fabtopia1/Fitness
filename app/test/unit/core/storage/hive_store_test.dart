import 'package:flutter_test/flutter_test.dart';
import 'package:lifedna/core/storage/hive_store.dart';

import '../../../support/test_harness.dart';

void main() {
  late TestEnvironment env;

  setUp(() async => env = await TestEnvironment.create());
  tearDown(() async => env.dispose());

  test('every declared box is opened', () {
    for (final name in HiveStore.allBoxes) {
      expect(() => env.store.box(name), returnsNormally, reason: name);
    }
  });

  test('an undeclared box throws instead of being created silently', () {
    // A typo'd box name that quietly created an empty box would look like
    // data loss to the user and like nothing at all to us.
    expect(() => env.store.box('not_a_box'), throwsStateError);
  });

  test('write/read round-trips a JSON map', () async {
    await env.store.write(HiveStore.boxMeta, 'k', {'a': 1, 'b': 'two'});
    expect(env.store.read(HiveStore.boxMeta, 'k'), {'a': 1, 'b': 'two'});
  });

  test('reading a missing key returns null rather than throwing', () {
    expect(env.store.read(HiveStore.boxMeta, 'absent'), isNull);
  });

  test('readAll returns every stored value', () async {
    await env.store.writeAll(HiveStore.boxFoods, {
      '1': {'id': '1'},
      '2': {'id': '2'},
    });
    expect(env.store.readAll(HiveStore.boxFoods), hasLength(2));
  });

  test('watchOne emits the current value and then each change', () async {
    final seen = <Map<String, dynamic>?>[];
    final sub = env.store.watchOne(HiveStore.boxMeta, 'w').listen(seen.add);

    await Future<void>.delayed(Duration.zero);
    await env.store.write(HiveStore.boxMeta, 'w', {'v': 1});
    await Future<void>.delayed(Duration.zero);
    await env.store.write(HiveStore.boxMeta, 'w', {'v': 2});
    await Future<void>.delayed(Duration.zero);

    await sub.cancel();
    expect(seen.first, isNull);
    expect(seen.last, {'v': 2});
  });

  test('watchAll emits after each write', () async {
    final counts = <int>[];
    final sub = env.store
        .watchAll(HiveStore.boxTasks)
        .listen((rows) => counts.add(rows.length));

    await Future<void>.delayed(Duration.zero);
    await env.store.write(HiveStore.boxTasks, 'a', {'id': 'a'});
    await Future<void>.delayed(Duration.zero);
    await env.store.write(HiveStore.boxTasks, 'b', {'id': 'b'});
    await Future<void>.delayed(Duration.zero);

    await sub.cancel();
    expect(counts.last, 2);
  });

  test('delete removes a key and clearBox empties one box only', () async {
    await env.store.write(HiveStore.boxTasks, 'a', {'id': 'a'});
    await env.store.write(HiveStore.boxFoods, 'f', {'id': 'f'});

    await env.store.delete(HiveStore.boxTasks, 'a');
    expect(env.store.read(HiveStore.boxTasks, 'a'), isNull);
    expect(env.store.read(HiveStore.boxFoods, 'f'), isNotNull);

    await env.store.clearBox(HiveStore.boxFoods);
    expect(env.store.readAll(HiveStore.boxFoods), isEmpty);
  });

  test('clearAll empties every box — the erase-data path', () async {
    await env.store.write(HiveStore.boxTasks, 'a', {'id': 'a'});
    await env.store.write(HiveStore.boxWorkouts, 'w', {'id': 'w'});
    await env.store.write(HiveStore.boxProfile, 'me', {'id': 'me'});

    await env.store.clearAll();

    for (final name in HiveStore.allBoxes) {
      expect(env.store.readAll(name), isEmpty, reason: name);
    }
  });
}
