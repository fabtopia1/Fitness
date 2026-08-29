import 'package:flutter_test/flutter_test.dart';
import 'package:lifedna/core/storage/storage_mode.dart';

/// C-1 regression suite.
///
/// The defect: `HiveStore.open()` caught a secure-storage failure, continued
/// with no cipher, and handed Hive encrypted files. Hive threw, the throw
/// escaped bootstrap, and the user reached a failure screen whose only button
/// re-ran the identical path — a permanent lockout recoverable only by
/// uninstalling, which destroyed the data.
///
/// The rule these tests pin: **once boxes exist in a mode, a launch opens them
/// in that mode or it opens nothing.**
void main() {
  const key = 'a-base64-key';

  Future<StorageMode> resolve({
    required bool? recorded,
    String? storedKey,
    bool readThrows = false,
    bool writeThrows = false,
    String generated = 'generated-key',
    void Function(String)? onWrite,
  }) => StorageModeResolver.resolve(
    recordedEncrypted: recorded,
    readKey: () async {
      if (readThrows) throw StateError('keystore unavailable');
      return storedKey;
    },
    writeKey: (value) async {
      if (writeThrows) throw StateError('keystore read-only');
      onWrite?.call(value);
    },
    generateKey: () => generated,
  );

  group('first run', () {
    test('creates a key and records encrypted', () async {
      String? written;
      final mode = await resolve(
        recorded: null,
        generated: key,
        onWrite: (value) => written = value,
      );

      expect(mode.encrypted, isTrue);
      expect(mode.keyMaterial, key);
      expect(written, key);
    });

    test('adopts a key left behind by a previous install', () async {
      // A reinstall keeps the keystore entry. The boxes are new, so adopting
      // it is safe and keeps the reinstall encrypted rather than silently
      // downgrading it.
      final mode = await resolve(recorded: null, storedKey: key);

      expect(mode.encrypted, isTrue);
      expect(mode.keyMaterial, key);
    });

    test(
      'falls back to unencrypted when the keystore cannot be read',
      () async {
        // Documented degradation. Being locked out of your own training log is
        // worse than an unencrypted cache on a device that already cannot keep
        // a secret — and Settings tells the user which mode they are in.
        final mode = await resolve(recorded: null, readThrows: true);

        expect(mode.encrypted, isFalse);
        expect(mode.keyMaterial, isNull);
      },
    );

    test('falls back to unencrypted when the key cannot be written', () async {
      final mode = await resolve(recorded: null, writeThrows: true);
      expect(mode.encrypted, isFalse);
    });
  });

  group('boxes already exist and are encrypted', () {
    test('opens with the stored key', () async {
      final mode = await resolve(recorded: true, storedKey: key);

      expect(mode.encrypted, isTrue);
      expect(mode.keyMaterial, key);
    });

    test('a MISSING key throws instead of opening unencrypted', () async {
      // This is the device-transfer case: Keystore keys are device-bound, so
      // restored boxes arrive without one. Continuing unencrypted is what
      // bricked the app.
      await expectLater(
        resolve(recorded: true),
        throwsA(
          isA<StorageUnavailable>().having(
            (failure) => failure.reason,
            'reason',
            StorageFailureReason.keyUnavailable,
          ),
        ),
      );
    });

    test('a THROWING keystore throws instead of opening unencrypted', () async {
      await expectLater(
        resolve(recorded: true, readThrows: true),
        throwsA(isA<StorageUnavailable>()),
      );
    });

    test('never generates a replacement key over existing data', () async {
      // Writing a fresh key would make the old boxes permanently unreadable
      // AND hide the fact that anything was wrong.
      var wrote = false;
      await expectLater(
        resolve(recorded: true, onWrite: (_) => wrote = true),
        throwsA(isA<StorageUnavailable>()),
      );
      expect(wrote, isFalse);
    });
  });

  group('boxes already exist and are unencrypted', () {
    test('stays unencrypted even when a key is now available', () async {
      // The mirror-image lockout: adopting a key that appeared later would
      // hand Hive a cipher for plaintext files.
      final mode = await resolve(recorded: false, storedKey: key);

      expect(mode.encrypted, isFalse);
      expect(mode.keyMaterial, isNull);
    });

    test('stays unencrypted when the keystore is unavailable', () async {
      final mode = await resolve(recorded: false, readThrows: true);
      expect(mode.encrypted, isFalse);
    });
  });

  group('the failure a user sees', () {
    test('every reason has a headline and an explanation', () {
      for (final reason in StorageFailureReason.values) {
        final failure = StorageUnavailable(reason);
        expect(failure.headline, isNotEmpty, reason: reason.name);
        expect(failure.detail, isNotEmpty, reason: reason.name);
        // No raw exception text ever reaches this copy.
        expect(failure.detail, isNot(contains('Exception')));
      }
    });

    test('the reset warning is honest about what is lost in each case', () {
      // A signed-in user gets their data back; a local-mode user does not,
      // and must be told so before they tap the button.
      expect(StorageUnavailable.resetWarningSignedIn, contains('downloads it'));
      expect(StorageUnavailable.resetWarningLocal, contains('permanently'));
    });

    test('the cause is carried for logging but not for display', () {
      final failure = StorageUnavailable(
        StorageFailureReason.corrupt,
        cause: StateError('box header damaged'),
      );
      expect(failure.cause, isA<StateError>());
      expect(failure.detail, isNot(contains('box header')));
      expect(failure.toString(), contains('corrupt'));
    });
  });
}
