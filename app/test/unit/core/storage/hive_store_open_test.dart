import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:hive/hive.dart';
import 'package:lifedna/core/storage/hive_store.dart';
import 'package:lifedna/core/storage/storage_mode.dart';

import '../../../support/fake_secure_storage.dart';

/// C-1, the half that was never tested.
///
/// Thirteen tests covered `StorageModeResolver` — a pure function. The code
/// that USES it, `HiveStore.open()`, had none: not the cipher construction, not
/// the box opening, not the marker write, not the failure classification. It
/// could not be tested, because it called `Hive.initFlutter`, which needs
/// path_provider. So it takes a directory now.
///
/// These run on the real filesystem in plain `test()` bodies. A `testWidgets`
/// body could not: it runs inside a fake async zone where real file I/O never
/// completes.
void main() {
  late Directory home;
  late FakeSecureStorage keystore;

  // Hive's box registry is global and keyed by NAME, not by directory. A box
  // left open by one test is handed straight back to the next one — which
  // silently gets a store pointed at the previous test's temp directory, and
  // an assertion that passes for the wrong reason.
  Future<void> closeHive() async {
    try {
      await Hive.close();
    } on Object {
      // A box left in a broken state by a deliberate failure still has to be
      // let go of, or it leaks into the next test.
    }
  }

  setUp(() async {
    await closeHive();
    home = await Directory.systemTemp.createTemp('lifedna_open');
    keystore = FakeSecureStorage();
  });

  tearDown(() async {
    await closeHive();
    if (home.existsSync()) home.deleteSync(recursive: true);
  });

  /// Opens inside a guarded zone.
  ///
  /// Hive reports a failed `openBox` by completing an internal completer with
  /// an error that nothing listens to, so every *expected* open failure here
  /// also surfaces as an unhandled zone error and fails the test regardless of
  /// the assertion. Production absorbs the same error in `main`'s
  /// `runZonedGuarded`, where it is harmless: bootstrap runs before telemetry
  /// is wired, so a migration cannot report itself to Crashlytics as a crash.
  Future<HiveStore> open() {
    final completer = Completer<HiveStore>();
    runZonedGuarded(
      () async {
        try {
          completer.complete(
            await HiveStore.open(secureStorage: keystore, directory: home.path),
          );
        } on Object catch (error, stackTrace) {
          completer.completeError(error, stackTrace);
        }
      },
      (error, _) {
        // Hive's orphaned completer. The real outcome is on `completer`.
      },
    );
    return completer.future;
  }

  /// Writes boxes the way a build BEFORE the encryption marker existed would
  /// have: no marker, and whichever cipher that launch happened to resolve.
  Future<void> seedLegacyBoxes({required bool encrypted}) async {
    Hive.init(home.path);
    final cipher = encrypted
        ? HiveAesCipher(base64Url.decode(keystore.storedKey!))
        : null;
    final box = await Hive.openBox<String>(
      HiveStore.boxMeta,
      encryptionCipher: cipher,
    );
    await box.put('legacy', '{"id":"legacy","note":"three years of training"}');
    await Hive.close();
  }

  group('first run', () {
    test('creates a key, opens encrypted, and records it', () async {
      final store = await open();

      expect(store.isEncrypted, isTrue);
      expect(keystore.storedKey, isNotNull);

      // The marker must survive into the next launch.
      await Hive.close();
      final again = await open();
      expect(again.isEncrypted, isTrue);
    });

    test('a keystore that cannot be read still starts, unencrypted', () async {
      keystore.readThrows = true;

      final store = await open();

      expect(store.isEncrypted, isFalse);
    });
  });

  group('migration — installs that predate the marker', () {
    test('PLAINTEXT boxes are adopted, not declared corrupt', () async {
      // The defect this closes. A legacy install could be running plaintext
      // while the keystore still held a key — that is exactly what the old
      // silent fallback produced. On the first launch of the new code the
      // resolver sees a key, picks encrypted, and hands Hive a cipher for
      // plaintext files. Hive throws.
      //
      // That throw used to be classified `corrupt`, which put the user on
      // the recovery screen and offered to reset. Their data was perfectly
      // readable. The app offered to destroy it.
      keystore.storedKey = base64UrlEncode(Hive.generateSecureKey());
      await seedLegacyBoxes(encrypted: false);

      final store = await open();

      expect(store.isEncrypted, isFalse, reason: 'adopted the real mode');
      expect(
        store.read(HiveStore.boxMeta, 'legacy'),
        isNotNull,
        reason: 'three years of training is still there',
      );
    });

    test('the adopted mode is recorded, so the probe runs once', () async {
      keystore.storedKey = base64UrlEncode(Hive.generateSecureKey());
      await seedLegacyBoxes(encrypted: false);

      await open();
      await Hive.close();

      // Second launch: the marker now says unencrypted, so the resolver picks
      // unencrypted directly and never probes.
      final second = await open();
      expect(second.isEncrypted, isFalse);
      expect(second.read(HiveStore.boxMeta, 'legacy'), isNotNull);
    });

    test('ENCRYPTED legacy boxes keep working with their key', () async {
      keystore.storedKey = base64UrlEncode(Hive.generateSecureKey());
      await seedLegacyBoxes(encrypted: true);

      final store = await open();

      expect(store.isEncrypted, isTrue);
      expect(store.read(HiveStore.boxMeta, 'legacy'), isNotNull);
    });
  });

  group('a recorded mode is never second-guessed', () {
    test('encrypted boxes with no key throw rather than probing', () async {
      keystore.storedKey = base64UrlEncode(Hive.generateSecureKey());
      final first = await open();
      await first.write(HiveStore.boxMeta, 'k', {'id': 'k'});
      await Hive.close();

      // The device transfer: the boxes came across, the Keystore key did not.
      keystore.storedKey = null;

      await expectLater(
        open(),
        throwsA(
          isA<StorageUnavailable>().having(
            (f) => f.reason,
            'reason',
            StorageFailureReason.keyUnavailable,
          ),
        ),
      );
    });

    test(
      'a recorded mode that will not open is a mismatch, not a guess',
      () async {
        // Recorded encrypted, key present but WRONG. Probing plaintext here
        // would be the silent mode switch C-1 forbids.
        keystore.storedKey = base64UrlEncode(Hive.generateSecureKey());
        final first = await open();
        // Data matters. An EMPTY box carries no checksum to disagree with, so
        // it opens under any key — the mismatch only becomes detectable once a
        // frame exists, which is also the only point at which it matters.
        await first.write(HiveStore.boxMeta, 'k', {'id': 'k'});
        await Hive.close();
        keystore.storedKey = base64UrlEncode(Hive.generateSecureKey());

        await expectLater(
          open(),
          throwsA(
            isA<StorageUnavailable>().having(
              (f) => f.reason,
              'reason',
              StorageFailureReason.encryptionMismatch,
            ),
          ),
        );
      },
    );

    test('a failed open leaves no box behind for the retry to reuse', () async {
      // Hive caches boxes by name and IGNORES the cipher for one already open.
      // A partial open left behind means the retry silently gets boxes on the
      // first cipher — a store in two modes at once.
      keystore.storedKey = base64UrlEncode(Hive.generateSecureKey());
      final first = await open();
      await first.write(HiveStore.boxMeta, 'k', {'id': 'k'});
      await Hive.close();
      keystore.storedKey = base64UrlEncode(Hive.generateSecureKey());

      await expectLater(open(), throwsA(isA<StorageUnavailable>()));
      expect(Hive.isBoxOpen(HiveStore.boxMeta), isFalse);
    });
  });

  group('reset', () {
    test('quarantines the boxes rather than destroying them', () async {
      final store = await open();
      await store.write(HiveStore.boxMeta, 'k', {'id': 'k'});

      await HiveStore.resetLocalData(
        secureStorage: keystore,
        directory: home.path,
      );

      final quarantined = Directory(
        '${home.path}/${HiveStore.quarantineFolder}',
      );
      expect(quarantined.existsSync(), isTrue);
      expect(quarantined.listSync(), isNotEmpty);
      // Nothing readable is left where the app looks.
      expect(
        File('${home.path}/${HiveStore.boxMeta}.hive').existsSync(),
        isFalse,
      );
    });

    test('the app starts clean afterwards', () async {
      final store = await open();
      await store.write(HiveStore.boxMeta, 'k', {'id': 'k'});
      await HiveStore.resetLocalData(
        secureStorage: keystore,
        directory: home.path,
      );

      final fresh = await open();

      expect(fresh.read(HiveStore.boxMeta, 'k'), isNull);
    });

    test(
      'a second reset replaces the first quarantine, not stacks it',
      () async {
        // Otherwise every reset doubles the app's disk usage forever.
        await (await open()).write(HiveStore.boxMeta, 'a', {'id': 'a'});
        await HiveStore.resetLocalData(
          secureStorage: keystore,
          directory: home.path,
        );
        await (await open()).write(HiveStore.boxMeta, 'b', {'id': 'b'});
        await HiveStore.resetLocalData(
          secureStorage: keystore,
          directory: home.path,
        );

        final quarantined = Directory(
          '${home.path}/${HiveStore.quarantineFolder}',
        );
        expect(
          quarantined.listSync().whereType<Directory>(),
          isEmpty,
          reason: 'one generation, flat — no nested quarantines',
        );
      },
    );

    test('purging deletes outright and clears the key', () async {
      await (await open()).write(HiveStore.boxMeta, 'k', {'id': 'k'});

      await HiveStore.resetLocalData(
        secureStorage: keystore,
        directory: home.path,
        quarantine: false,
      );

      expect(
        Directory('${home.path}/${HiveStore.quarantineFolder}').existsSync(),
        isFalse,
      );
      expect(keystore.storedKey, isNull);
    });
  });
}
