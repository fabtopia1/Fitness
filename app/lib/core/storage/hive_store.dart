import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:hive_flutter/hive_flutter.dart';
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
  static Future<HiveStore> open({
    FlutterSecureStorage secureStorage = const FlutterSecureStorage(
      aOptions: AndroidOptions(encryptedSharedPreferences: true),
    ),
    bool inMemory = false,
  }) async {
    if (!inMemory) {
      await Hive.initFlutter('lifedna');
    }

    if (inMemory) {
      // No files, so no mode to preserve and no key to lose.
      final store = HiveStore._(null);
      await store._openBoxes(null, inMemory: true);
      return store;
    }

    final state = await Hive.openBox<bool>(boxStorageState);
    final mode = await StorageModeResolver.resolve(
      recordedEncrypted: state.get(_encryptedMarkerKey),
      readKey: () => secureStorage.read(key: _secureKeyName),
      writeKey: (key) => secureStorage.write(key: _secureKeyName, value: key),
      generateKey: () => base64UrlEncode(Hive.generateSecureKey()),
    );

    final cipher = mode.encrypted
        ? HiveAesCipher(base64Url.decode(mode.keyMaterial!))
        : null;

    final store = HiveStore._(cipher);
    try {
      await store._openBoxes(cipher, inMemory: false);
    } on Object catch (error) {
      // The marker and the files disagree, or the files are damaged. Either
      // way the app must offer a way out rather than a stack trace.
      throw StorageUnavailable(
        state.get(_encryptedMarkerKey) == null
            ? StorageFailureReason.corrupt
            : StorageFailureReason.encryptionMismatch,
        cause: error,
      );
    }

    // Written only after every box opened cleanly, so a half-failed first run
    // cannot record a mode the data does not actually use.
    await state.put(_encryptedMarkerKey, mode.encrypted);
    return store;
  }

  Future<void> _openBoxes(
    HiveAesCipher? cipher, {
    required bool inMemory,
  }) async {
    for (final name in allBoxes) {
      _boxes[name] = await Hive.openBox<String>(
        name,
        encryptionCipher: cipher,
        bytes: inMemory ? Uint8List(0) : null,
      );
    }
  }

  /// Deletes every box and the encryption key, so the next launch starts as a
  /// first run.
  ///
  /// This is the recovery action behind [StorageUnavailable]. It is
  /// destructive by necessity: data encrypted with a key that no longer exists
  /// cannot be read by anything, so the only alternative to deleting it is
  /// leaving the user permanently unable to open the app.
  static Future<void> resetLocalData({
    FlutterSecureStorage secureStorage = const FlutterSecureStorage(
      aOptions: AndroidOptions(encryptedSharedPreferences: true),
    ),
  }) async {
    await Hive.close();
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
