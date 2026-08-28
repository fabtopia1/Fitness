import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:lifedna/core/data/synced_collection.dart';
import 'package:lifedna/core/result/result.dart';
import 'package:lifedna/core/storage/hive_store.dart';
import 'package:lifedna/core/sync/outbox.dart';
import 'package:lifedna/features/settings/domain/app_settings.dart';

/// Reads and writes the single settings document.
///
/// A missing document is not an error state: it means the user has never
/// changed anything, and [AppSettings.defaults] describes that exactly.
class SettingsRepository {
  SettingsRepository({
    required HiveStore store,
    required Outbox outbox,
    FirebaseFirestore? firestore,
    String? uid,
  }) : _settings = SyncedCollection<AppSettings>(
         store: store,
         outbox: outbox,
         boxName: HiveStore.boxSettings,
         collection: 'settings',
         fromJson: AppSettings.fromJson,
         firestore: firestore,
         uid: uid,
       );

  final SyncedCollection<AppSettings> _settings;

  Stream<AppSettings> watch() => _settings
      .watchOne(AppSettings.docId)
      .map((value) => value ?? AppSettings.defaults());

  AppSettings read() =>
      _settings.readOne(AppSettings.docId) ?? AppSettings.defaults();

  Future<Result<AppSettings>> save(AppSettings settings) =>
      _settings.put(settings.copyWith(updatedAt: DateTime.now().toUtc()));

  Future<Result<int>> pullAll() => _settings.pull();
}
