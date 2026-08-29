import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:lifedna/core/result/result.dart';
import 'package:lifedna/core/sync/outbox.dart';
import 'package:lifedna/features/body/data/body_repository.dart';
import 'package:lifedna/features/body/data/photo_store.dart';

import '../../../support/test_harness.dart';

/// H-3 regression suite.
///
/// The defect: `ImagePicker` returns a file in the app's **cache** directory,
/// and that path was stored verbatim on the measurement. Android reclaims the
/// cache under storage pressure and every "phone cleaner" empties it, so a
/// progress photo could become a broken-image placeholder weeks later with
/// nothing to point at. The same absolute path was then replicated to
/// Firestore, where it is meaningless on any other device and leaks the
/// package name and Android user id.
///
/// These use the real filesystem, because the property under test is that
/// files survive.
void main() {
  late TestEnvironment env;
  late PhotoStore photos;
  late Directory cache;

  setUp(() async {
    env = await TestEnvironment.create();
    photos = env.photos;
    cache = Directory('${env.directory.path}/fake_cache')
      ..createSync(recursive: true);
  });
  tearDown(() async => env.dispose());

  File pickerFile(String name, {String bytes = 'jpeg-bytes'}) =>
      File('${cache.path}/$name')..writeAsStringSync(bytes);

  group('adopting a picked photo', () {
    test('copies it out of the cache directory', () async {
      final picked = pickerFile('image_picker_123.jpg');

      final reference = await photos.adopt(picked);

      // The original is untouched — copy, not rename: ImagePicker's file can
      // sit on a different filesystem, where a rename fails at runtime.
      expect(picked.existsSync(), isTrue);
      expect(File(photos.resolve(reference)).readAsStringSync(), 'jpeg-bytes');
    });

    test('survives the cache being wiped, which is the whole point', () async {
      final picked = pickerFile('image_picker_123.jpg');
      final reference = await photos.adopt(picked);

      cache.deleteSync(recursive: true);

      expect(photos.exists(reference), isTrue);
    });

    test('returns a bare file name, never a path', () async {
      // This value is written to Firestore. A device path there is wrong on
      // every other device and leaks the package and Android user id.
      final reference = await photos.adopt(pickerFile('image_picker_1.jpg'));

      expect(reference, isNot(contains('/')));
      expect(reference, endsWith('.jpg'));
    });

    test('two photos never collide, even with the same source name', () async {
      final first = await photos.adopt(pickerFile('image.jpg', bytes: 'one'));
      final second = await photos.adopt(pickerFile('image.jpg', bytes: 'two'));

      expect(first, isNot(second));
      expect(File(photos.resolve(first)).readAsStringSync(), 'one');
      expect(File(photos.resolve(second)).readAsStringSync(), 'two');
    });

    test('keeps a known extension and normalises anything else', () async {
      // The extension comes from another process and ends up in a file name.
      expect(await photos.adopt(pickerFile('a.PNG')), endsWith('.png'));
      expect(await photos.adopt(pickerFile('b.heic')), endsWith('.heic'));
      expect(await photos.adopt(pickerFile('c.exe')), endsWith('.jpg'));
      expect(await photos.adopt(pickerFile('d')), endsWith('.jpg'));
    });

    test('recreates the directory if something deleted it', () async {
      photos.directory.deleteSync(recursive: true);

      final reference = await photos.adopt(pickerFile('image.jpg'));

      expect(photos.exists(reference), isTrue);
    });
  });

  group('resolving', () {
    test('a file name becomes a path inside the store', () async {
      final reference = await photos.adopt(pickerFile('image.jpg'));

      expect(photos.resolve(reference), startsWith(photos.directory.path));
    });

    test('a legacy absolute path is passed through unchanged', () {
      // Measurements written before this existed hold one. Rewriting them
      // would be a migration that could only guess at files already gone.
      const legacy = '/data/user/0/os.lifedna.lifedna/cache/old.jpg';

      expect(photos.resolve(legacy), legacy);
    });

    test('a reference to a file that is gone reports absence', () {
      expect(photos.exists('never-existed.jpg'), isFalse);
    });
  });

  group('deleting', () {
    test('removes an adopted photo', () async {
      final reference = await photos.adopt(pickerFile('image.jpg'));

      await photos.delete(reference);

      expect(photos.exists(reference), isFalse);
    });

    test('deleting twice is harmless', () async {
      final reference = await photos.adopt(pickerFile('image.jpg'));

      await photos.delete(reference);

      expect(photos.delete(reference), completes);
    });

    test('never deletes through a legacy absolute path', () async {
      // Those point outside this store — at a cache file another app owns, or
      // at a path that means something entirely different on this device.
      final outside = pickerFile('not-ours.jpg');

      await photos.delete(outside.path);

      expect(outside.existsSync(), isTrue);
    });
  });

  group('through BodyRepository — photos do not outlive their measurement', () {
    BodyRepository build() => BodyRepository(
      store: env.store,
      outbox: Outbox(env.store),
      photos: photos,
    );

    test('deleting a measurement deletes its photo', () async {
      // Photos are the largest thing this app writes. An orphan left behind on
      // every delete grows for the life of the install with nothing referencing
      // it and no way for the user to find it.
      final repository = build();
      final reference = await photos.adopt(pickerFile('image.jpg'));
      final measurement = repository.create(weightKg: 80, photoPath: reference);
      await repository.save(measurement);

      await repository.delete(measurement.id);

      expect(photos.exists(reference), isFalse);
    });

    test('deleting a measurement with no photo is fine', () async {
      final repository = build();
      final measurement = repository.create(weightKg: 80);
      await repository.save(measurement);

      expect(await repository.delete(measurement.id), isA<Ok<void>>());
    });

    test('a legacy absolute path is left alone on delete', () async {
      final repository = build();
      final outside = pickerFile('legacy.jpg');
      final measurement = repository.create(
        weightKg: 80,
        photoPath: outside.path,
      );
      await repository.save(measurement);

      await repository.delete(measurement.id);

      expect(outside.existsSync(), isTrue);
    });
  });
}
