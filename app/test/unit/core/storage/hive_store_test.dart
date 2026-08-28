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

  group('the decode cache', () {
    test('a repeated read returns the same content', () async {
      await env.store.write(HiveStore.boxFoods, 'f1', {'id': 'f1', 'n': 1});

      final first = env.store.readAll(HiveStore.boxFoods);
      final second = env.store.readAll(HiveStore.boxFoods);

      expect(second, equals(first));
    });

    test('a write is visible immediately, not on the next frame', () async {
      // The cache is validated against the raw string rather than written
      // through, so it cannot serve a stale record after an update.
      await env.store.write(HiveStore.boxFoods, 'f1', {'id': 'f1', 'n': 1});
      expect(env.store.read(HiveStore.boxFoods, 'f1'), {'id': 'f1', 'n': 1});

      await env.store.write(HiveStore.boxFoods, 'f1', {'id': 'f1', 'n': 2});
      expect(env.store.read(HiveStore.boxFoods, 'f1'), {'id': 'f1', 'n': 2});
    });

    test('a delete is visible immediately', () async {
      await env.store.write(HiveStore.boxFoods, 'f1', {'id': 'f1'});
      env.store.readAll(HiveStore.boxFoods);

      await env.store.delete(HiveStore.boxFoods, 'f1');

      expect(env.store.read(HiveStore.boxFoods, 'f1'), isNull);
      expect(env.store.readAll(HiveStore.boxFoods), isEmpty);
    });

    test('a write made straight through the box is still seen', () async {
      // Nothing in the app does this, but a cache that could go stale under a
      // direct write would be a trap for whoever tries.
      await env.store.write(HiveStore.boxFoods, 'f1', {'id': 'f1', 'n': 1});
      env.store.readAll(HiveStore.boxFoods);

      await env.store.box(HiveStore.boxFoods).put('f1', '{"id":"f1","n":9}');

      expect(env.store.read(HiveStore.boxFoods, 'f1'), {'id': 'f1', 'n': 9});
    });

    test('clearing a box empties its cache too', () async {
      await env.store.write(HiveStore.boxFoods, 'f1', {'id': 'f1'});
      env.store.readAll(HiveStore.boxFoods);

      await env.store.clearBox(HiveStore.boxFoods);

      expect(env.store.readAll(HiveStore.boxFoods), isEmpty);
      expect(env.store.read(HiveStore.boxFoods, 'f1'), isNull);
    });

    test('a large box reads consistently across repeated passes', () async {
      final batch = <String, Map<String, dynamic>>{
        for (var i = 0; i < 2000; i++) 'id$i': {'id': 'id$i', 'v': i},
      };
      await env.store.writeAll(HiveStore.boxNutritionLogs, batch);

      final first = env.store.readAll(HiveStore.boxNutritionLogs);
      await env.store.write(HiveStore.boxNutritionLogs, 'id0', {
        'id': 'id0',
        'v': -1,
      });
      final second = env.store.readAll(HiveStore.boxNutritionLogs);

      expect(first, hasLength(2000));
      expect(second, hasLength(2000));
      expect(second.firstWhere((row) => row['id'] == 'id0')['v'], -1);
    });
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
