import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:hive_flutter/hive_flutter.dart';

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

  /// Opens every box with AES encryption.
  ///
  /// The key lives in the platform keystore (Android Keystore / iOS Keychain),
  /// never in the box itself and never in shared preferences. On a device
  /// where secure storage is unavailable the app still runs, unencrypted, and
  /// says so in Settings rather than failing to start — a user locked out of
  /// their own training log is a worse outcome than an unencrypted cache on a
  /// device that already cannot keep a secret.
  static Future<HiveStore> open({
    FlutterSecureStorage secureStorage = const FlutterSecureStorage(
      aOptions: AndroidOptions(encryptedSharedPreferences: true),
    ),
    bool inMemory = false,
  }) async {
    if (!inMemory) {
      await Hive.initFlutter('lifedna');
    }

    HiveAesCipher? cipher;
    if (!inMemory) {
      try {
        var encoded = await secureStorage.read(key: _secureKeyName);
        if (encoded == null) {
          final key = Hive.generateSecureKey();
          encoded = base64UrlEncode(key);
          await secureStorage.write(key: _secureKeyName, value: encoded);
        }
        cipher = HiveAesCipher(base64Url.decode(encoded));
      } on Object catch (error) {
        debugPrint('HiveStore: secure key unavailable, continuing '
            'unencrypted ($error)');
        cipher = null;
      }
    }

    final store = HiveStore._(cipher);
    for (final name in allBoxes) {
      store._boxes[name] = await Hive.openBox<String>(
        name,
        encryptionCipher: cipher,
      );
    }
    return store;
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

  Map<String, dynamic>? read(String boxName, String id) {
    final raw = box(boxName).get(id);
    if (raw == null) return null;
    return jsonDecode(raw) as Map<String, dynamic>;
  }

  List<Map<String, dynamic>> readAll(String boxName) {
    final result = <Map<String, dynamic>>[];
    for (final raw in box(boxName).values) {
      result.add(jsonDecode(raw) as Map<String, dynamic>);
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
    yield* box(boxName)
        .watch(key: id)
        .map((_) => read(boxName, id));
  }

  // ----------------------------------------------------------------- writes --

  Future<void> write(
    String boxName,
    String id,
    Map<String, dynamic> value,
  ) =>
      box(boxName).put(id, jsonEncode(value));

  Future<void> writeAll(
    String boxName,
    Map<String, Map<String, dynamic>> values,
  ) =>
      box(boxName).putAll(
        values.map((key, value) => MapEntry(key, jsonEncode(value))),
      );

  Future<void> delete(String boxName, String id) => box(boxName).delete(id);

  Future<void> clearBox(String boxName) => box(boxName).clear();

  /// Wipes every user box. Used on sign-out and on account deletion so one
  /// user's data can never appear under another account on a shared device.
  Future<void> clearAll() async {
    for (final name in allBoxes) {
      await box(name).clear();
    }
  }

  Future<void> close() => Hive.close();
}
