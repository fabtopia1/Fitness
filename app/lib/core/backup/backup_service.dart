import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:lifedna/core/storage/hive_store.dart';
import 'package:lifedna/core/storage/photo_store.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:path_provider/path_provider.dart';

/// What a backup file contains, without opening it fully.
@immutable
class BackupSummary {
  const BackupSummary({
    required this.file,
    required this.createdAt,
    required this.records,
    required this.appVersion,
  });

  final File file;
  final DateTime createdAt;
  final int records;
  final String appVersion;

  String get fileName => file.uri.pathSegments.last;
  int get sizeBytes => file.existsSync() ? file.lengthSync() : 0;
}

/// A backup file that cannot be read.
class BackupInvalid implements Exception {
  const BackupInvalid(this.reason);
  final String reason;
  @override
  String toString() => 'BackupInvalid($reason)';
}

/// Whole-database export and restore, to a plain JSON file.
///
/// This exists because personal use has no cloud behind it. With Firebase
/// unconfigured — the supported and recommended setup for one person on one
/// phone — Hive is not the source of truth, it is the ONLY truth. A lost
/// phone, a factory reset, or an uninstall is total loss, and no amount of
/// care inside the app prevents any of them.
///
/// Deliberately plain JSON, not an encrypted archive: a backup you cannot open
/// on a laptop three years from now is not a backup. The file lives in the
/// app's own external directory, which needs no permission and is reachable
/// over USB, so getting it off the phone is a drag-and-drop.
class BackupService {
  BackupService({
    required HiveStore store,
    required this.directory,
    required this.appVersion,
    PhotoStore? photos,
    DateTime Function()? clock,
  }) : _store = store,
       _photos = photos,
       _clock = clock ?? DateTime.now;

  final HiveStore _store;

  /// Progress photos are files, not Hive records, so exporting the boxes alone
  /// restores measurements whose photos are gone.
  final PhotoStore? _photos;
  final DateTime Function() _clock;

  /// Where backups are written. Shown in the UI, because a backup nobody can
  /// find is not a backup.
  final Directory directory;
  final String appVersion;

  /// Resolves the backup directory and builds a service, or null when the
  /// platform gives no external storage.
  ///
  /// `getExternalStorageDirectory()` is the app's OWN folder on shared
  /// storage: no permission is needed, nothing else can read it, uninstalling
  /// removes it — and, crucially, it is visible over USB at
  /// `Android/data/<package>/files/backups/`. A backup the owner cannot copy
  /// off the phone is not a backup.
  static Future<BackupService?> open({
    required HiveStore store,
    PhotoStore? photos,
    DateTime Function()? clock,
  }) async {
    try {
      final base = await getExternalStorageDirectory();
      if (base == null) return null;
      final directory = Directory('${base.path}/backups');
      if (!directory.existsSync()) await directory.create(recursive: true);

      var version = 'unknown';
      try {
        final info = await PackageInfo.fromPlatform();
        version = '${info.version}+${info.buildNumber}';
      } on Object {
        // Only used as a label inside the file.
      }

      return BackupService(
        store: store,
        directory: directory,
        appVersion: version,
        photos: photos,
        clock: clock,
      );
    } on Object catch (error) {
      debugPrint('BackupService: unavailable — $error');
      return null;
    }
  }

  /// Where copies of progress photos live, shared by every backup.
  ///
  /// One pool rather than a folder per snapshot: photos are written once and
  /// never edited, so seven daily snapshots would otherwise hold seven copies
  /// of the same image.
  static const String photoFolder = 'photos';

  static const String formatTag = 'lifedna-backup';
  static const int formatVersion = 1;

  /// How many automatic snapshots to keep. Seven days of daily snapshots is
  /// long enough to notice something went wrong and short enough that the
  /// files never matter for space.
  static const int keepSnapshots = 7;

  static const Duration snapshotInterval = Duration(hours: 20);

  // ------------------------------------------------------------------ export

  /// Writes every box to a single JSON file and returns it.
  Future<File> export({String prefix = 'lifedna'}) async {
    if (!directory.existsSync()) {
      await directory.create(recursive: true);
    }

    final now = _clock();
    final boxes = <String, Map<String, dynamic>>{};
    var records = 0;

    for (final name in HiveStore.allBoxes) {
      // The outbox is queued cloud writes, not user data. Restoring it would
      // replay work against whatever account is signed in now.
      if (name == HiveStore.boxOutbox) continue;

      final entries = <String, dynamic>{};
      for (final record in _store.readAll(name)) {
        final id = record['id'];
        if (id is String && id.isNotEmpty) entries[id] = record;
      }
      if (entries.isEmpty) continue;
      boxes[name] = entries;
      records += entries.length;
    }

    final payload = <String, dynamic>{
      'format': formatTag,
      'version': formatVersion,
      'createdAt': now.toUtc().toIso8601String(),
      'appVersion': appVersion,
      'records': records,
      'boxes': boxes,
    };

    // Photos travel with the boxes. Without this, restoring gives back
    // measurements whose photoPath names a file that no longer exists — and
    // progress photos are the one thing in here nobody can re-enter by hand.
    payload['photos'] = await _copyPhotosOut(boxes);

    final file = File('${directory.path}/$prefix-${_stamp(now)}.json');
    // Written whole, then moved into place, so a backup interrupted halfway
    // cannot leave a half-file that looks restorable.
    final temporary = File('${file.path}.part');
    await temporary.writeAsString(
      const JsonEncoder.withIndent('  ').convert(payload),
      flush: true,
    );
    await temporary.rename(file.path);
    return file;
  }

  // ------------------------------------------------------------------ import

  /// Reads a backup's header without applying it.
  Future<BackupSummary> inspect(File file) async {
    final decoded = await _decode(file);
    return BackupSummary(
      file: file,
      createdAt:
          DateTime.tryParse('${decoded['createdAt']}')?.toLocal() ??
          file.lastModifiedSync(),
      records: decoded['records'] is int ? decoded['records'] as int : 0,
      appVersion: '${decoded['appVersion'] ?? 'unknown'}',
    );
  }

  /// Replaces local data with the contents of [file] and returns the number of
  /// records restored.
  ///
  /// A safety snapshot is taken first, unconditionally. Restoring the wrong
  /// file is the one mistake this whole class could otherwise cause, and it
  /// would be irreversible.
  Future<int> restore(File file) async {
    final decoded = await _decode(file);
    final boxes = decoded['boxes'];
    if (boxes is! Map) {
      throw const BackupInvalid('no boxes in this file');
    }

    await export(prefix: 'before-restore');

    var restored = 0;
    for (final entry in boxes.entries) {
      final name = '${entry.key}';
      if (!HiveStore.allBoxes.contains(name)) {
        // A box from a newer build. Skipped rather than fatal: a partial
        // restore of everything recognised beats refusing the whole file.
        debugPrint('BackupService: skipping unknown box "$name"');
        continue;
      }
      final records = entry.value;
      if (records is! Map) continue;

      final values = <String, Map<String, dynamic>>{};
      for (final record in records.entries) {
        final value = record.value;
        if (value is Map) {
          values['${record.key}'] = Map<String, dynamic>.from(value);
        }
      }
      if (values.isEmpty) continue;

      await _store.clearBox(name);
      await _store.writeAll(name, values);
      restored += values.length;
    }

    await _copyPhotosBack(decoded['photos']);
    return restored;
  }

  /// Copies every referenced photo into the shared pool and returns their
  /// names, so a restore knows what to look for.
  Future<List<String>> _copyPhotosOut(
    Map<String, Map<String, dynamic>> boxes,
  ) async {
    final photos = _photos;
    if (photos == null) return const [];

    final pool = Directory('${directory.path}/$photoFolder');
    final names = <String>[];

    for (final record in boxes.values.expand((box) => box.values)) {
      if (record is! Map) continue;
      final reference = record['photoPath'];
      // Legacy absolute paths point outside the photo store and may already be
      // gone; there is nothing dependable to copy.
      if (reference is! String || reference.isEmpty) continue;
      if (reference.startsWith('/')) continue;

      names.add(reference);
      final destination = File('${pool.path}/$reference');
      if (destination.existsSync()) continue;

      final source = File(photos.resolve(reference));
      if (!source.existsSync()) continue;
      try {
        if (!pool.existsSync()) await pool.create(recursive: true);
        await source.copy(destination.path);
      } on Object catch (error) {
        debugPrint('BackupService: could not copy photo $reference — $error');
      }
    }
    return names;
  }

  Future<void> _copyPhotosBack(Object? names) async {
    final photos = _photos;
    if (photos == null || names is! List) return;

    final pool = Directory('${directory.path}/$photoFolder');
    if (!pool.existsSync()) return;

    for (final entry in names) {
      if (entry is! String || entry.isEmpty || entry.contains('/')) continue;
      final source = File('${pool.path}/$entry');
      if (!source.existsSync()) continue;
      final destination = File(photos.resolve(entry));
      if (destination.existsSync()) continue;
      try {
        if (!photos.directory.existsSync()) {
          await photos.directory.create(recursive: true);
        }
        await source.copy(destination.path);
      } on Object catch (error) {
        debugPrint('BackupService: could not restore photo $entry — $error');
      }
    }
  }

  // ------------------------------------------------------------- maintenance

  /// Backups on disk, newest first.
  List<File> available() {
    if (!directory.existsSync()) return const [];
    final files =
        directory
            .listSync()
            .whereType<File>()
            .where((f) => f.path.endsWith('.json'))
            .toList()
          ..sort((a, b) => takenAt(b).compareTo(takenAt(a)));
    return files;
  }

  /// When a backup was taken, read from the name the app itself wrote.
  ///
  /// NOT the file's modified time. That is rewritten by a USB copy, a file
  /// manager, or a restore from a computer — all of which are exactly what
  /// someone does with a backup — and a bogus mtime would either suppress the
  /// next snapshot or trigger one on every launch.
  DateTime takenAt(File file) {
    final name = file.uri.pathSegments.last;
    final match = RegExp(r'(\d{4})(\d{2})(\d{2})-(\d{2})(\d{2})(\d{2})')
        .firstMatch(name);
    if (match != null) {
      final parsed = DateTime(
        int.parse(match.group(1)!),
        int.parse(match.group(2)!),
        int.parse(match.group(3)!),
        int.parse(match.group(4)!),
        int.parse(match.group(5)!),
        int.parse(match.group(6)!),
      );
      return parsed;
    }
    return file.existsSync() ? file.lastModifiedSync() : DateTime(1970);
  }

  /// Takes a snapshot if the newest one is older than [snapshotInterval], then
  /// prunes to [keepSnapshots].
  ///
  /// Called at startup. This is what makes "data loss under normal operation"
  /// actually unlikely rather than merely discouraged: it does not depend on
  /// the user remembering.
  Future<File?> autoSnapshot() async {
    try {
      final existing = available()
          .where((f) => f.uri.pathSegments.last.startsWith('auto-'))
          .toList();

      if (existing.isNotEmpty) {
        final age = _clock().difference(takenAt(existing.first));
        if (age < snapshotInterval) return null;
      }

      final file = await export(prefix: 'auto');
      if (_isEmpty(file)) {
        // Nothing logged yet. An empty snapshot would sit at the top of the
        // list saying "last backup just now" and suppress the real one for
        // the next twenty hours.
        await file.delete();
        return null;
      }

      for (final stale in existing.skip(keepSnapshots - 1)) {
        try {
          await stale.delete();
        } on Object catch (error) {
          debugPrint('BackupService: could not prune ${stale.path} — $error');
        }
      }
      return file;
    } on Object catch (error) {
      // A snapshot that fails must never stop the app starting.
      debugPrint('BackupService: snapshot failed — $error');
      return null;
    }
  }

  static bool _isEmpty(File file) {
    try {
      final decoded = jsonDecode(file.readAsStringSync());
      return decoded is Map && decoded['records'] == 0;
    } on Object {
      return false;
    }
  }

  Future<Map<String, dynamic>> _decode(File file) async {
    if (!file.existsSync()) throw const BackupInvalid('file not found');
    final Object? decoded;
    try {
      decoded = jsonDecode(await file.readAsString());
    } on Object {
      throw const BackupInvalid('not a readable JSON file');
    }
    if (decoded is! Map<String, dynamic>) {
      throw const BackupInvalid('not a LifeDNA backup');
    }
    if (decoded['format'] != formatTag) {
      throw const BackupInvalid('not a LifeDNA backup');
    }
    final version = decoded['version'];
    if (version is! int || version > formatVersion) {
      throw BackupInvalid('written by a newer version of LifeDNA ($version)');
    }
    return decoded;
  }

  static String _stamp(DateTime when) {
    final t = when.toLocal();
    String two(int v) => v.toString().padLeft(2, '0');
    return '${t.year}${two(t.month)}${two(t.day)}-${two(t.hour)}${two(t.minute)}${two(t.second)}';
  }
}
