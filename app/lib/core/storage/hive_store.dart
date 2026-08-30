import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:hive_flutter/hive_flutter.dart';
import 'package:path_provider/path_provider.dart';
import 'package:lifedna/core/storage/storage_mode.dart';

/// Encrypted local persistence.
///
/// Hive is the app's SOURCE OF TRUTH for user data. Every write commits here
/// first and synchronously; Firestore is a replication target, not the primary.
/// That ordering is what makes the whole app work in a gym basement with no
/// signal, and it is why this class is in `core` rather than a feature.
///
/// Values are stored as JSON strings rather than through generated
/// TypeAdapters. That is a deliberate trade-off: one serialisation format
/// serves both Hive and Firestore, there are no generated files to drift, and
/// a schema change cannot corrupt an existing box. The cost is a JSON
/// encode/decode per record, which is immaterial at this data volume.
class HiveStore {
  HiveStore._(this._encryptionKey);

  final HiveAesCipher? _encryptionKey;
  final Map<String, Box<String>> _boxes = {};

  static const _secureKeyName = 'lifedna_hive_key_v1';

  /// Box names. Every user-facing collection has exactly one.
  static const boxProfile = 'profile';
  static const boxSettings = 'settings';
  static const boxFoods = 'foods';
  static const boxMeals = 'meals';
  static const boxNutritionLogs = 'nutrition_logs';
  static const boxWaterLogs = 'water_logs';
  static const boxSupplements = 'supplements';
  static const boxSupplementLogs = 'supplement_logs';
  static const boxExercises = 'exercises';
  static const boxWorkouts = 'workouts';
  static const boxWorkoutSessions = 'workout_sessions';
  static const boxPersonalRecords = 'personal_records';
  static const boxBodyMeasurements = 'body_measurements';
  static const boxTasks = 'tasks';
  static const boxCalendarEvents = 'calendar_events';
  static const boxNotifications = 'notifications';
  static const boxOutbox = 'outbox';
  static const boxMeta = 'meta';

  /// Records which encryption mode the boxes were written in.
  ///
  /// Deliberately UNENCRYPTED and deliberately outside [allBoxes]: it has to be
  /// readable before the key is known, and `clearAll()` on sign-out must not
  /// erase the one fact that tells the next launch how to open the files.
  static const boxStorageState = '__storage_state__';
  static const _encryptedMarkerKey = 'encrypted';

  static const List<String> allBoxes = [
    boxProfile,
    boxSettings,
    boxFoods,
    boxMeals,
    boxNutritionLogs,
    boxWaterLogs,
    boxSupplements,
    boxSupplementLogs,
    boxExercises,
    boxWorkouts,
    boxWorkoutSessions,
    boxPersonalRecords,
    boxBodyMeasurements,
    boxTasks,
    boxCalendarEvents,
    boxNotifications,
    boxOutbox,
    boxMeta,
  ];

  /// Opens every box in the mode the previous launch recorded.
  ///
  /// The key lives in the platform keystore (Android Keystore / iOS Keychain),
  /// never in a box and never in shared preferences. On a device where secure
  /// storage is unavailable at FIRST run the app still starts, unencrypted,
  /// and says so in Settings — being locked out of your own training log is
  /// the worse outcome.
  ///
  /// What it will NOT do is switch modes. Once boxes exist, this either opens
  /// them the way they were written or throws [StorageUnavailable] so the app
  /// can offer a recovery. Handing Hive a cipher for plaintext files — or
  /// plaintext handling for encrypted ones — is unrecoverable, and the failure
  /// surfaces as an error deep inside Hive that names nothing.
  ///
  /// [inMemory] opens Hive's memory backend instead of files. Tests use it so
  /// that no write touches the disk: a `testWidgets` body runs inside a fake
  /// async zone where real file I/O never completes, which turns an ordinary
  /// `clear()` into a test that hangs rather than one that fails.
  /// [directory] overrides where Hive keeps its files. Production passes null
  /// and gets `initFlutter`; tests pass a temp directory, which is the only way
  /// to exercise this method at all — and it went untested for exactly that
  /// reason while the pure resolver beside it had thirteen tests.
  static Future<HiveStore> open({
    FlutterSecureStorage secureStorage = const FlutterSecureStorage(
      aOptions: AndroidOptions(encryptedSharedPreferences: true),
    ),
    bool inMemory = false,
    String? directory,
  }) async {
    if (inMemory) {
      // No files, so no mode to preserve and no key to lose.
      final store = HiveStore._(null);
      await store._openBoxes(null, inMemory: true);
      return store;
    }

    if (directory == null) {
      await Hive.initFlutter('lifedna');
    } else {
      Hive.init(directory);
    }

    // Guarded: this box is opened before anything is known, and an unguarded
    // throw here escapes as a raw HiveError, which `main` cannot tell from any
    // other bootstrap failure — landing the user on a retry-only screen. That
    // is the same permanent lockout C-1 exists to remove, reached by a
    // different door.
    // The marker holds one bool. If its own file is damaged, bricking the app
    // over it would be absurd — it is derived state, and the probe below can
    // re-establish the mode. So it is rebuilt rather than fatal.
    //
    // `crashRecovery: false` here too: the default would truncate silently,
    // which is the behaviour this whole class now exists to avoid.
    Box<bool> state;
    try {
      state = await Hive.openBox<bool>(boxStorageState, crashRecovery: false);
    } on Object catch (error) {
      debugPrint('HiveStore: storage-state marker unreadable — $error');
      try {
        await Hive.deleteBoxFromDisk(boxStorageState);
        state = await Hive.openBox<bool>(boxStorageState);
      } on Object catch (fatal, stackTrace) {
        Error.throwWithStackTrace(
          StorageUnavailable(StorageFailureReason.corrupt, cause: fatal),
          stackTrace,
        );
      }
    }

    final recorded = state.get(_encryptedMarkerKey);
    final mode = await StorageModeResolver.resolve(
      recordedEncrypted: recorded,
      readKey: () => secureStorage.read(key: _secureKeyName),
      writeKey: (key) => secureStorage.write(key: _secureKeyName, value: key),
      generateKey: () => base64UrlEncode(Hive.generateSecureKey()),
    );

    final cipher = mode.encrypted
        ? HiveAesCipher(base64Url.decode(mode.keyMaterial!))
        : null;

    var store = HiveStore._(cipher);
    var effectivelyEncrypted = mode.encrypted;

    try {
      await store._openBoxes(cipher, inMemory: false);
    } on Object catch (error, stackTrace) {
      // Close whatever DID open. Hive caches boxes by name and ignores the
      // cipher argument for an already-open box, so leaving them behind means
      // the next attempt — a retry, or the probe below — silently gets boxes
      // opened under the first cipher.
      await store._closeOpened();

      final migrated = await _probeUnencrypted(recorded: recorded, mode: mode);
      if (migrated == null) {
        Error.throwWithStackTrace(
          StorageUnavailable(
            recorded == null
                ? StorageFailureReason.corrupt
                : StorageFailureReason.encryptionMismatch,
            cause: error,
          ),
          stackTrace,
        );
      }
      store = migrated;
      effectivelyEncrypted = false;
    }

    // Written only after every box opened cleanly, so a half-failed first run
    // cannot record a mode the data does not actually use.
    await state.put(_encryptedMarkerKey, effectivelyEncrypted);
    return store;
  }

  /// The migration path for installs that predate the encryption marker.
  ///
  /// Those boxes carry no record of how they were written. If the keystore now
  /// holds a key — which it does after any launch that created one, including
  /// one that then fell back to plaintext — the resolver correctly picks
  /// encrypted, and opening PLAINTEXT files with a cipher fails.
  ///
  /// Without this probe that failure was classified `corrupt` and the user was
  /// offered a reset: **their data was perfectly readable and the app offered
  /// to destroy it.** Trying the other mode once costs a few milliseconds on a
  /// path that only runs when the first attempt already failed.
  ///
  /// Restricted to `recorded == null` on purpose. Once a mode is recorded,
  /// probing the other one is exactly the silent mode-switch that C-1 forbids:
  /// a recorded mode that will not open is a missing key or real damage, and
  /// guessing cannot help.
  static Future<HiveStore?> _probeUnencrypted({
    required bool? recorded,
    required StorageMode mode,
  }) async {
    // Only the encrypted→plaintext direction is reachable. The reverse needs a
    // key, and if one were available the resolver would already have chosen it.
    if (recorded != null || !mode.encrypted) return null;

    final plain = HiveStore._(null);
    try {
      await plain._openBoxes(null, inMemory: false);
      debugPrint(
        'HiveStore: boxes predate the encryption marker and are plaintext — '
        'adopting unencrypted mode and recording it.',
      );
      return plain;
    } on Object catch (error) {
      debugPrint('HiveStore: plaintext probe also failed — $error');
      await plain._closeOpened();
      return null;
    }
  }

  /// Opens every box, **without Hive's crash recovery**.
  ///
  /// This is the single most important line in this file, and it was missing.
  ///
  /// Hive's default `crashRecovery: true` does not throw when it cannot parse
  /// a box. It treats the file as damaged, truncates it at the first bad
  /// frame, and returns an empty box that reports success. Handing it a
  /// plaintext box with a cipher — or an encrypted box without one — is
  /// therefore not a recoverable error: it is **immediate, silent, total data
  /// destruction at open time**, before any `catch` can run. Measured on a
  /// real box: 49 bytes in, 0 bytes out, no exception, `length == 0`.
  ///
  /// With recovery off, the same mismatch throws `HiveError: Wrong checksum`
  /// and the file is left byte-for-byte intact, so the mode can be re-probed
  /// and the data opened correctly.
  ///
  /// The cost is that a box genuinely damaged by a crash no longer self-heals
  /// by truncation — the user reaches the recovery screen instead. That is the
  /// right trade: truncation loses the same data and says nothing.
  Future<void> _openBoxes(
    HiveAesCipher? cipher, {
    required bool inMemory,
  }) async {
    for (final name in allBoxes) {
      _boxes[name] = await Hive.openBox<String>(
        name,
        encryptionCipher: cipher,
        bytes: inMemory ? Uint8List(0) : null,
        crashRecovery: false,
      );
    }
  }

  /// Closes every box this store managed to open, so the name is free for a
  /// re-open under a different cipher.
  Future<void> _closeOpened() async {
    for (final box in _boxes.values) {
      try {
        await box.close();
      } on Object catch (error) {
        debugPrint('HiveStore: could not close "${box.name}" — $error');
      }
    }
    _boxes.clear();
  }

  /// Deletes every box and the encryption key, so the next launch starts as a
  /// first run.
  ///
  /// This is the recovery action behind [StorageUnavailable]. It is
  /// destructive by necessity: data encrypted with a key that no longer exists
  /// cannot be read by anything, so the only alternative to deleting it is
  /// leaving the user permanently unable to open the app.
  static const String quarantineFolder = 'quarantine';

  static Future<void> resetLocalData({
    FlutterSecureStorage secureStorage = const FlutterSecureStorage(
      aOptions: AndroidOptions(encryptedSharedPreferences: true),
    ),
    String? directory,
    bool quarantine = true,
  }) async {
    await Hive.close();

    final home = directory ?? await _defaultDirectory();
    if (quarantine && home != null) {
      final moved = await _quarantine(Directory(home));
      if (moved) {
        // The key is KEPT. Quarantined encrypted boxes are worthless without
        // it, and the next launch adopts an existing key anyway, so keeping it
        // costs nothing and is the difference between a recoverable support
        // case and a destroyed one.
        return;
      }
    }

    for (final name in [...allBoxes, boxStorageState]) {
      try {
        await Hive.deleteBoxFromDisk(name);
      } on Object catch (error) {
        debugPrint('HiveStore: could not delete "$name" — $error');
      }
    }
    try {
      await secureStorage.delete(key: _secureKeyName);
    } on Object catch (error) {
      debugPrint('HiveStore: could not clear the key — $error');
    }
  }

  /// Moves the box files aside instead of deleting them.
  ///
  /// The recovery reset runs when the app cannot read its own database. In the
  /// cases the migration probe does not catch, the data may still be intact and
  /// only mis-addressed — and a beta tester who taps reset has no way back if
  /// the files are gone. One generation is kept, so this cannot grow: a second
  /// reset replaces the first quarantine.
  ///
  /// This is a support affordance, not a user-visible one. Nothing in the app
  /// reads it, which is why the recovery copy can honestly say the data is gone
  /// from LifeDNA.
  static Future<bool> _quarantine(Directory home) async {
    try {
      if (!home.existsSync()) return false;

      final destination = Directory('${home.path}/$quarantineFolder');
      if (destination.existsSync()) {
        await destination.delete(recursive: true);
      }
      await destination.create(recursive: true);

      var moved = 0;
      for (final entity in home.listSync()) {
        if (entity is! File) continue;
        final name = entity.uri.pathSegments.last;
        if (name.endsWith('.lock')) {
          try {
            await entity.delete();
          } on Object {
            // A held lock is released when the process exits; not fatal.
          }
          continue;
        }
        if (!name.endsWith('.hive')) continue;
        await entity.rename('${destination.path}/$name');
        moved++;
      }
      debugPrint('HiveStore: quarantined $moved box file(s).');
      return moved > 0;
    } on Object catch (error) {
      debugPrint(
        'HiveStore: quarantine failed, falling back to delete — $error',
      );
      return false;
    }
  }

  static Future<String?> _defaultDirectory() async {
    try {
      final base = await getApplicationDocumentsDirectory();
      return '${base.path}/lifedna';
    } on Object catch (error) {
      debugPrint('HiveStore: no documents directory — $error');
      return null;
    }
  }

  bool get isEncrypted => _encryptionKey != null;

  Box<String> box(String name) {
    final box = _boxes[name];
    if (box == null) {
      throw StateError('Box "$name" was not opened. Add it to allBoxes.');
    }
    return box;
  }

  // ------------------------------------------------------------------ reads --

  /// Decoded records, keyed by box then id, each validated against the exact
  /// string it was decoded from.
  ///
  /// Reading a box costs one JSON parse per record, and a heavy user has tens
  /// of thousands: measured at 134 ms for 20 000 records on a desktop, which
  /// is several hundred milliseconds of jank on a phone — on every rebuild of
  /// a screen that watches the box. Comparing the raw string instead turns
  /// that parse into a string comparison.
  ///
  /// Validated against the raw value rather than written through, so a
  /// mutation made through [box] directly can never serve a stale record.
  /// Callers must not mutate the returned map; nothing in this app does,
  /// because every read is immediately handed to a `fromJson`.
  final Map<String, Map<String, _Decoded>> _decoded = {};

  Map<String, _Decoded> _cacheFor(String boxName) =>
      _decoded.putIfAbsent(boxName, () => {});

  Map<String, dynamic> _decode(
    Map<String, _Decoded> cache,
    String id,
    String raw,
  ) {
    final hit = cache[id];
    if (hit != null && hit.raw == raw) return hit.value;
    final value = jsonDecode(raw) as Map<String, dynamic>;
    cache[id] = _Decoded(raw, value);
    return value;
  }

  Map<String, dynamic>? read(String boxName, String id) {
    final raw = box(boxName).get(id);
    if (raw == null) {
      _cacheFor(boxName).remove(id);
      return null;
    }
    return _decode(_cacheFor(boxName), id, raw);
  }

  List<Map<String, dynamic>> readAll(String boxName) {
    final source = box(boxName);
    final cache = _cacheFor(boxName);
    final result = <Map<String, dynamic>>[];
    for (final key in source.keys) {
      final raw = source.get(key);
      if (raw == null) continue;
      result.add(_decode(cache, key as String, raw));
    }
    // Entries removed from the box must not linger in the cache.
    if (cache.length > source.length) {
      cache.removeWhere((id, _) => !source.containsKey(id));
    }
    return result;
  }

  /// Emits the box contents now, and again on every change.
  Stream<List<Map<String, dynamic>>> watchAll(String boxName) async* {
    yield readAll(boxName);
    yield* box(boxName).watch().map((_) => readAll(boxName));
  }

  Stream<Map<String, dynamic>?> watchOne(String boxName, String id) async* {
    yield read(boxName, id);
    yield* box(boxName).watch(key: id).map((_) => read(boxName, id));
  }

  // ----------------------------------------------------------------- writes --

  Future<void> write(String boxName, String id, Map<String, dynamic> value) =>
      box(boxName).put(id, jsonEncode(value));

  Future<void> writeAll(
    String boxName,
    Map<String, Map<String, dynamic>> values,
  ) =>
      box(boxName)
          .putAll(values.map((key, value) => MapEntry(key, jsonEncode(value))));

  Future<void> delete(String boxName, String id) {
    _cacheFor(boxName).remove(id);
    return box(boxName).delete(id);
  }

  Future<void> clearBox(String boxName) {
    _cacheFor(boxName).clear();
    return box(boxName).clear();
  }

  /// Wipes every user box. Used on sign-out and on account deletion so one
  /// user's data can never appear under another account on a shared device.
  Future<void> clearAll() async {
    _decoded.clear();
    for (final name in allBoxes) {
      await box(name).clear();
    }
  }
}

/// One decoded record and the exact string it came from.
class _Decoded {
  const _Decoded(this.raw, this.value);
  final String raw;
  final Map<String, dynamic> value;
}
