import 'dart:io';

import 'package:flutter/foundation.dart';

import 'package:path_provider/path_provider.dart';
import 'package:uuid/uuid.dart';

/// Durable storage for progress photos.
///
/// `ImagePicker` returns a file in the app's **cache** directory. Android
/// reclaims that directory under storage pressure without warning, and every
/// "phone cleaner" app empties it on demand. Storing the picked path meant a
/// progress photo — the one artefact in a fitness app a user would be upset to
/// lose — could turn into a broken-image placeholder weeks later, with nothing
/// to point at as the cause.
///
/// Two rules follow:
///
///  1. **Copy on capture.** The file is adopted into the documents directory
///     the moment it is picked, not when the measurement is saved. Between
///     those two points the user is typing, which is time the cache has to
///     disappear.
///  2. **Store the file name, never the path.** `BodyMeasurement` replicates
///     to Firestore, and an absolute path is meaningless on another device,
///     changes across reinstalls, and leaks the package and Android user id
///     into the database.
class PhotoStore {
  PhotoStore({required this.directory, Uuid uuid = const Uuid()})
    : _uuid = uuid;

  /// Where adopted photos live. Created if absent.
  final Directory directory;
  final Uuid _uuid;

  static const String folderName = 'photos';

  static Future<PhotoStore> open() async {
    final base = await getApplicationDocumentsDirectory();
    final directory = Directory('${base.path}/$folderName');
    if (!directory.existsSync()) {
      await directory.create(recursive: true);
    }
    return PhotoStore(directory: directory);
  }

  /// Copies [source] into durable storage and returns the reference to store
  /// on the measurement — a bare file name.
  ///
  /// Copy, not rename: `ImagePicker`'s file can sit on a different filesystem
  /// from the documents directory, where a rename fails at runtime rather than
  /// at compile time.
  Future<String> adopt(File source) async {
    if (!directory.existsSync()) {
      await directory.create(recursive: true);
    }
    final extension = _extensionOf(source.path);
    final name = '${_uuid.v4()}$extension';
    await source.copy('${directory.path}/$name');
    return name;
  }

  /// The absolute path for a stored reference.
  ///
  /// Accepts a legacy absolute path unchanged. Measurements written before
  /// this existed hold one, and rewriting them would mean a migration that
  /// could only guess at files that may already be gone.
  String resolve(String reference) =>
      reference.startsWith('/') ? reference : '${directory.path}/$reference';

  bool exists(String reference) => File(resolve(reference)).existsSync();

  /// Removes a photo. Never throws: a photo that is already gone is the
  /// outcome this was asked for.
  Future<void> delete(String reference) async {
    // A legacy absolute path may point anywhere, including at a cache file
    // another app owns. Only delete what this store adopted.
    if (reference.startsWith('/')) return;
    try {
      final file = File(resolve(reference));
      if (file.existsSync()) await file.delete();
    } on Object {
      // Storage that refuses a delete will refuse it again next time; there is
      // nothing here worth surfacing to the user.
    }
  }

  /// Deletes every stored photo.
  ///
  /// Called from the two places that promise a clean device: signing out, and
  /// the C-1 storage reset. Both wipe Hive, and photos living outside Hive
  /// would otherwise survive a "deletes every meal, workout, measurement and
  /// note on this phone permanently" — on a shared device, the previous
  /// account's progress photos would still be on the filesystem.
  Future<void> clear() async {
    try {
      if (directory.existsSync()) await directory.delete(recursive: true);
      await directory.create(recursive: true);
    } on Object catch (error) {
      debugPrint('PhotoStore: could not clear photos — $error');
    }
  }

  /// Wipes the photo directory without an open store, for the reset path that
  /// runs before anything has been constructed.
  static Future<void> clearAll() async {
    try {
      await (await open()).clear();
    } on Object catch (error) {
      debugPrint('PhotoStore: could not resolve the photo directory — $error');
    }
  }

  static String _extensionOf(String path) {
    final dot = path.lastIndexOf('.');
    final slash = path.lastIndexOf('/');
    if (dot <= slash || dot == -1) return '.jpg';
    final extension = path.substring(dot).toLowerCase();
    // Anything unexpected is stored as .jpg rather than trusted: the value
    // comes from another process and ends up in a file name.
    return const {'.jpg', '.jpeg', '.png', '.heic', '.webp'}.contains(extension)
        ? extension
        : '.jpg';
  }
}
