import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:lifedna/core/backup/backup_service.dart';
import 'package:lifedna/core/storage/hive_store.dart';

import '../../../support/test_harness.dart';

/// Backup is the whole safety net for personal use.
///
/// With no Firebase configured — the supported setup for one person on one
/// phone — Hive is not the source of truth, it is the only truth. A lost
/// phone, a factory reset or an uninstall is total loss, and nothing inside
/// the app prevents any of them. These tests treat a restore that silently
/// loses records as the worst possible outcome, because it is.
void main() {
  late TestEnvironment env;
  late Directory directory;
  late BackupService backups;
  var now = DateTime(2026, 8, 30, 9);

  BackupService build() => BackupService(
    store: env.store,
    directory: directory,
    appVersion: '1.0.0+1',
    photos: env.photos,
    clock: () => now,
  );

  setUp(() async {
    now = DateTime(2026, 8, 30, 9);
    env = await TestEnvironment.create();
    directory = Directory('${env.directory.path}/backups_${now.microsecond}')
      ..createSync(recursive: true);
    backups = build();
  });

  tearDown(() async {
    if (directory.existsSync()) directory.deleteSync(recursive: true);
    await env.dispose();
  });

  Future<void> seed({int meals = 2, int workouts = 1}) async {
    for (var i = 0; i < meals; i++) {
      await env.store.write(HiveStore.boxMeals, 'm$i', {
        'id': 'm$i',
        'name': 'Meal $i',
        'updatedAt': '2026-08-01T00:00:00Z',
      });
    }
    for (var i = 0; i < workouts; i++) {
      await env.store.write(HiveStore.boxWorkouts, 'w$i', {
        'id': 'w$i',
        'name': 'Push $i',
        'updatedAt': '2026-08-01T00:00:00Z',
      });
    }
  }

  group('export', () {
    test('captures every box that has data', () async {
      await seed(meals: 3, workouts: 2);

      final file = await backups.export();
      final decoded =
          jsonDecode(await file.readAsString()) as Map<String, dynamic>;

      expect(decoded['format'], BackupService.formatTag);
      expect(decoded['records'], 5);
      final boxes = decoded['boxes'] as Map<String, dynamic>;
      expect((boxes[HiveStore.boxMeals] as Map).length, 3);
      expect((boxes[HiveStore.boxWorkouts] as Map).length, 2);
    });

    test('leaves the outbox out', () async {
      // Queued cloud writes are not user data. Restoring them would replay
      // work against whatever account is signed in at the time.
      await env.store.write(HiveStore.boxOutbox, 'meals/m1', {
        'id': 'meals/m1',
        'collection': 'meals',
      });
      await seed();

      final decoded = jsonDecode(
        await (await backups.export()).readAsString(),
      ) as Map<String, dynamic>;

      expect(
        (decoded['boxes'] as Map).containsKey(HiveStore.boxOutbox),
        isFalse,
      );
    });

    test('is written whole, never half', () async {
      // A backup interrupted mid-write must not leave a file that looks
      // restorable. It is staged as .part and renamed into place.
      await seed();
      final file = await backups.export();

      expect(file.existsSync(), isTrue);
      expect(File('${file.path}.part').existsSync(), isFalse);
      expect(
        directory.listSync().where((f) => f.path.endsWith('.part')),
        isEmpty,
      );
    });

    test('two exports in the same second do not collide', () async {
      await seed();
      final first = await backups.export();
      now = now.add(const Duration(seconds: 1));
      final second = await backups.export();

      expect(first.path, isNot(second.path));
    });
  });

  group('restore', () {
    test('brings every record back', () async {
      await seed(meals: 3, workouts: 2);
      final file = await backups.export();
      await env.store.clearAll();
      expect(env.store.readAll(HiveStore.boxMeals), isEmpty);

      final restored = await backups.restore(file);

      expect(restored, 5);
      expect(env.store.readAll(HiveStore.boxMeals).length, 3);
      expect(env.store.readAll(HiveStore.boxWorkouts).length, 2);
      expect(env.store.read(HiveStore.boxMeals, 'm1')?['name'], 'Meal 1');
    });

    test('replaces rather than merges, so a deletion stays deleted', () async {
      await seed(meals: 3);
      final file = await backups.export();
      await env.store.write(HiveStore.boxMeals, 'stray', {
        'id': 'stray',
        'name': 'Logged after the backup',
      });

      await backups.restore(file);

      expect(env.store.read(HiveStore.boxMeals, 'stray'), isNull);
      expect(env.store.readAll(HiveStore.boxMeals).length, 3);
    });

    test('takes a safety snapshot BEFORE replacing anything', () async {
      // Restoring the wrong file is the one irreversible mistake this class
      // could cause. It must not be irreversible.
      await seed(meals: 3);
      final good = await backups.export();
      await env.store.clearAll();
      await env.store.write(HiveStore.boxMeals, 'current', {
        'id': 'current',
        'name': 'Today',
      });
      now = now.add(const Duration(minutes: 5));

      await backups.restore(good);

      final safety = backups
          .available()
          .where((f) => f.uri.pathSegments.last.startsWith('before-restore'))
          .toList();
      expect(safety, hasLength(1));

      // And it really contains the data that was just replaced.
      final decoded =
          jsonDecode(await safety.first.readAsString()) as Map<String, dynamic>;
      final meals =
          (decoded['boxes'] as Map)[HiveStore.boxMeals] as Map<String, dynamic>;
      expect(meals.containsKey('current'), isTrue);
    });

    test('a round trip through a file preserves the values exactly', () async {
      await env.store.write(HiveStore.boxBodyMeasurements, 'b1', {
        'id': 'b1',
        'weightKg': 82.4,
        'notes': 'félt heavy — 200% effort',
        'measuredAt': '2026-08-01T06:30:00.000Z',
      });
      final file = await backups.export();
      await env.store.clearAll();

      await backups.restore(file);

      final record = env.store.read(HiveStore.boxBodyMeasurements, 'b1')!;
      expect(record['weightKg'], 82.4);
      expect(record['notes'], 'félt heavy — 200% effort');
      expect(record['measuredAt'], '2026-08-01T06:30:00.000Z');
    });
  });

  group('a file that is not a backup', () {
    test('random JSON is refused', () async {
      final file = File('${directory.path}/notes.json')
        ..writeAsStringSync('{"hello":"world"}');

      await expectLater(backups.restore(file), throwsA(isA<BackupInvalid>()));
    });

    test('unparseable text is refused', () async {
      final file = File('${directory.path}/broken.json')
        ..writeAsStringSync('this is not json at all');

      await expectLater(backups.restore(file), throwsA(isA<BackupInvalid>()));
    });

    test('a missing file is refused', () async {
      await expectLater(
        backups.restore(File('${directory.path}/gone.json')),
        throwsA(isA<BackupInvalid>()),
      );
    });

    test('a newer format version is refused, not half-applied', () async {
      final file = File('${directory.path}/future.json')
        ..writeAsStringSync(
          jsonEncode({
            'format': BackupService.formatTag,
            'version': BackupService.formatVersion + 1,
            'boxes': <String, dynamic>{},
          }),
        );

      await expectLater(backups.restore(file), throwsA(isA<BackupInvalid>()));
    });

    test('an unknown box is skipped, not fatal', () async {
      // A file from a later build. Restoring everything recognised beats
      // refusing the whole thing.
      final file = File('${directory.path}/newer.json')
        ..writeAsStringSync(
          jsonEncode({
            'format': BackupService.formatTag,
            'version': BackupService.formatVersion,
            'boxes': {
              'a_box_from_the_future': {
                'x': <String, dynamic>{'id': 'x'},
              },
              HiveStore.boxMeals: {
                'm9': {'id': 'm9', 'name': 'Kept'},
              },
            },
          }),
        );

      expect(await backups.restore(file), 1);
      expect(env.store.read(HiveStore.boxMeals, 'm9')?['name'], 'Kept');
    });

    test('a refused file leaves the current data untouched', () async {
      await seed(meals: 2);
      final bad = File('${directory.path}/bad.json')..writeAsStringSync('nope');

      await expectLater(backups.restore(bad), throwsA(isA<BackupInvalid>()));

      expect(env.store.readAll(HiveStore.boxMeals).length, 2);
    });
  });

  group('automatic snapshots', () {
    test('an empty database is not snapshotted', () async {
      // Otherwise the very first launch parks a zero-record file at the top of
      // the list and suppresses the real snapshot for twenty hours.
      expect(await backups.autoSnapshot(), isNull);
      expect(backups.available(), isEmpty);
    });

    test('the first launch takes one', () async {
      await seed();

      expect(await backups.autoSnapshot(), isNotNull);
      expect(backups.available(), hasLength(1));
    });

    test('a second launch the same day does not', () async {
      await seed();
      await backups.autoSnapshot();

      now = now.add(const Duration(hours: 2));

      expect(await backups.autoSnapshot(), isNull);
      expect(backups.available(), hasLength(1));
    });

    test('a launch the next day does', () async {
      await seed();
      await backups.autoSnapshot();

      now = now.add(const Duration(hours: 21));

      expect(await backups.autoSnapshot(), isNotNull);
      expect(backups.available(), hasLength(2));
    });

    test('old snapshots are pruned, so they cannot fill the phone', () async {
      await seed();
      for (var day = 0; day < 12; day++) {
        now = now.add(const Duration(hours: 21));
        await backups.autoSnapshot();
      }

      final autos = backups
          .available()
          .where((f) => f.uri.pathSegments.last.startsWith('auto-'))
          .toList();
      expect(autos.length, lessThanOrEqualTo(BackupService.keepSnapshots));
    });

    test('a manual backup is never pruned', () async {
      await seed();
      final manual = await backups.export();

      for (var day = 0; day < 12; day++) {
        now = now.add(const Duration(hours: 21));
        await backups.autoSnapshot();
      }

      expect(manual.existsSync(), isTrue);
    });

    test('a snapshot that fails never stops the app starting', () async {
      // The app must open even if the backup directory has gone.
      await seed();
      directory.deleteSync(recursive: true);

      expect(await backups.autoSnapshot(), isNotNull);
    });
  });

  group('inspect', () {
    test('reads the header without applying anything', () async {
      await seed(meals: 4);
      final file = await backups.export();
      await env.store.clearAll();

      final summary = await backups.inspect(file);

      expect(summary.records, 5);
      expect(summary.appVersion, '1.0.0+1');
      expect(summary.fileName, endsWith('.json'));
      expect(summary.sizeBytes, greaterThan(0));
      // Nothing was restored by looking.
      expect(env.store.readAll(HiveStore.boxMeals), isEmpty);
    });
  });

  group('progress photos travel with the boxes', () {
    Future<String> addMeasurementWithPhoto(String id, String bytes) async {
      final source = File('${env.directory.path}/cache-$id.jpg')
        ..writeAsStringSync(bytes);
      final reference = await env.photos.adopt(source);
      await env.store.write(HiveStore.boxBodyMeasurements, id, {
        'id': id,
        'weightKg': 82.0,
        'photoPath': reference,
      });
      return reference;
    }

    test('a restore brings the photo file back, not just the record', () async {
      // Photos are files, not Hive records. Exporting the boxes alone gives
      // back a measurement whose photoPath names a file that no longer
      // exists — a broken thumbnail, and the one thing in here nobody can
      // re-enter by hand.
      final reference = await addMeasurementWithPhoto('b1', 'jpeg-one');
      final file = await backups.export();

      await env.store.clearAll();
      await env.photos.clear();
      expect(env.photos.exists(reference), isFalse);

      await backups.restore(file);

      expect(env.photos.exists(reference), isTrue);
      expect(
        File(env.photos.resolve(reference)).readAsStringSync(),
        'jpeg-one',
      );
      expect(
        env.store.read(HiveStore.boxBodyMeasurements, 'b1')?['photoPath'],
        reference,
      );
    });

    test('the export names the photos it carried', () async {
      final reference = await addMeasurementWithPhoto('b1', 'jpeg-one');

      final decoded = jsonDecode(
        await (await backups.export()).readAsString(),
      ) as Map<String, dynamic>;

      expect(decoded['photos'], contains(reference));
    });

    test('seven snapshots keep one copy of each photo, not seven', () async {
      // A shared pool, because photos are written once and never edited.
      await addMeasurementWithPhoto('b1', 'jpeg-one');
      for (var day = 0; day < 7; day++) {
        now = now.add(const Duration(hours: 21));
        await backups.autoSnapshot();
      }

      final pool = Directory('${directory.path}/${BackupService.photoFolder}');
      expect(pool.listSync().whereType<File>(), hasLength(1));
    });

    test(
      'a photo already on the phone is not overwritten by an older one',
      () async {
        final reference = await addMeasurementWithPhoto('b1', 'original');
        final file = await backups.export();

        await backups.restore(file);

        expect(
          File(env.photos.resolve(reference)).readAsStringSync(),
          'original',
        );
      },
    );

    test('a legacy absolute path is skipped rather than half-copied', () async {
      // Those point outside the photo store and may already be gone.
      await env.store.write(HiveStore.boxBodyMeasurements, 'legacy', {
        'id': 'legacy',
        'photoPath': '/data/user/0/os.lifedna.lifedna/cache/old.jpg',
      });

      final decoded = jsonDecode(
        await (await backups.export()).readAsString(),
      ) as Map<String, dynamic>;

      expect(decoded['photos'], isEmpty);
    });

    test('a missing photo file does not fail the whole backup', () async {
      final reference = await addMeasurementWithPhoto('b1', 'jpeg-one');
      await env.photos.delete(reference);

      final file = await backups.export();

      expect(file.existsSync(), isTrue);
      expect(
        env.store.read(HiveStore.boxBodyMeasurements, 'b1'),
        isNotNull,
        reason: 'the measurement is still worth backing up',
      );
    });
  });
}
