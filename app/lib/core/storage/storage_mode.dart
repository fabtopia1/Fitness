import 'package:flutter/foundation.dart';

/// Why local storage could not be opened.
///
/// Each value maps to copy the user can act on. There is no "unknown" case
/// that resolves to a dead end: every reason a device cannot open its own
/// database has a recovery, even if that recovery is destructive.
enum StorageFailureReason {
  /// The boxes are encrypted and the key is gone. The overwhelmingly common
  /// cause is a restore onto a new device: Android Keystore keys are
  /// device-bound and non-exportable, so the data arrives without the key.
  keyUnavailable,

  /// The boxes exist in one encryption mode and this launch resolved the
  /// other. Opening them anyway would fail deep inside Hive with an error
  /// that names nothing.
  encryptionMismatch,

  /// Hive could not read the files at all.
  corrupt,
}

/// Local storage could not be opened. Carries a reason so the recovery screen
/// can say something true rather than "something went wrong".
@immutable
class StorageUnavailable implements Exception {
  const StorageUnavailable(this.reason, {this.cause});

  final StorageFailureReason reason;
  final Object? cause;

  String get headline => switch (reason) {
    StorageFailureReason.keyUnavailable => "Your data can't be unlocked",
    StorageFailureReason.encryptionMismatch => "Your data can't be unlocked",
    StorageFailureReason.corrupt => "Your data can't be read",
  };

  String get detail => switch (reason) {
    StorageFailureReason.keyUnavailable =>
      'LifeDNA encrypts everything it stores with a key that belongs to this '
          'phone and never leaves it. That key is missing, which normally means '
          'this data was restored from another device.',
    StorageFailureReason.encryptionMismatch =>
      'The data on this phone was written in a different security mode from '
          'the one available now. Opening it anyway would corrupt it.',
    StorageFailureReason.corrupt =>
      'The local database could not be read. This usually follows the device '
          'running out of storage while writing.',
  };

  /// What resetting actually costs, said plainly. The two cases differ, and
  /// telling a signed-out user that "everything comes back" would be a lie.
  static const String resetWarningSignedIn =
      'Resetting clears the data on this phone and downloads it again from '
      'your account. Anything logged since your last sync is lost.';

  static const String resetWarningLocal =
      'This build has no account to restore from. Resetting deletes every '
      'meal, workout, measurement and note on this phone permanently.';

  @override
  String toString() => 'StorageUnavailable(${reason.name}, cause: $cause)';
}

/// How this launch will open the boxes.
@immutable
class StorageMode {
  const StorageMode({required this.encrypted, this.keyMaterial});

  /// Whether the boxes on disk are AES-encrypted.
  final bool encrypted;

  /// Base64 key, present only when [encrypted].
  final String? keyMaterial;

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is StorageMode &&
          other.encrypted == encrypted &&
          other.keyMaterial == keyMaterial;

  @override
  int get hashCode => Object.hash(encrypted, keyMaterial);

  @override
  String toString() => 'StorageMode(encrypted: $encrypted)';
}

/// Decides how to open local storage, and refuses to guess.
///
/// This is the whole of C-1's logic, extracted from Hive so it can be tested
/// exhaustively. The rule it enforces has one sentence:
///
/// > **Once boxes exist in a mode, this launch opens them in that mode or it
/// > opens nothing.**
///
/// The bug it replaces caught a secure-storage failure and continued
/// unencrypted, then handed Hive encrypted files and no key. Hive threw, the
/// throw escaped bootstrap, and the user reached a failure screen whose only
/// button re-ran the identical path. Silently switching modes in the other
/// direction is just as fatal and just as easy to write.
abstract final class StorageModeResolver {
  /// [recordedEncrypted] is the marker from a previous launch, or null on a
  /// first run. [readKey] and [writeKey] wrap the platform keystore.
  static Future<StorageMode> resolve({
    required bool? recordedEncrypted,
    required Future<String?> Function() readKey,
    required Future<void> Function(String key) writeKey,
    required String Function() generateKey,
  }) async {
    String? existing;
    var keystoreWorks = true;
    try {
      existing = await readKey();
    } on Object {
      // A keystore that throws is indistinguishable from one that is empty
      // for the purpose of *reading*, but it must not be treated as empty
      // when boxes already exist.
      keystoreWorks = false;
    }

    // ---- boxes already exist, encrypted --------------------------------
    if (recordedEncrypted == true) {
      if (existing == null) {
        // Whether the keystore threw or simply had nothing, the outcome for
        // the user is identical and the recovery is the same.
        throw const StorageUnavailable(StorageFailureReason.keyUnavailable);
      }
      return StorageMode(encrypted: true, keyMaterial: existing);
    }

    // ---- boxes already exist, unencrypted ------------------------------
    if (recordedEncrypted == false) {
      // A key may have appeared since — for instance the keystore was briefly
      // unavailable on the launch that created these boxes. Adopting it now
      // would hand Hive a cipher for plaintext files. Stay where the data is.
      return const StorageMode(encrypted: false);
    }

    // ---- first run ------------------------------------------------------
    if (!keystoreWorks) {
      // Documented degradation: the app runs unencrypted on a device that
      // cannot keep a secret, and Settings says so. Being locked out of your
      // own training log is the worse outcome.
      return const StorageMode(encrypted: false);
    }

    if (existing != null) {
      // A key left behind by a previous install. The boxes are new, so
      // adopting it is safe and keeps a reinstall encrypted.
      return StorageMode(encrypted: true, keyMaterial: existing);
    }

    try {
      final created = generateKey();
      await writeKey(created);
      return StorageMode(encrypted: true, keyMaterial: created);
    } on Object {
      return const StorageMode(encrypted: false);
    }
  }
}
