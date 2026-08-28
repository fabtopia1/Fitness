import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:lifedna/core/config/env.dart';
import 'package:lifedna/core/data/synced_entity.dart';
import 'package:lifedna/core/error/failure.dart';
import 'package:lifedna/core/error/failure_mapper.dart';
import 'package:lifedna/core/result/result.dart';
import 'package:lifedna/core/storage/hive_store.dart';
import 'package:lifedna/core/sync/outbox.dart';

/// A collection that lives in Hive and replicates to Firestore.
///
/// THE ORDERING IS THE ARCHITECTURE:
///
///   1. write to Hive            — synchronous, always succeeds, is the commit
///   2. enqueue in the outbox    — durable intent to replicate
///   3. attempt Firestore        — best effort; failure is not the user's problem
///
/// Reads always come from Hive, so a screen never waits on a network call and
/// never shows a spinner for data the device already has. Firestore is a
/// replication target and a second device's inbox — it is not the read path.
///
/// Every feature repository composes one of these rather than reimplementing
/// the pattern, so there is exactly one place where the offline guarantee can
/// be got wrong.
class SyncedCollection<T extends SyncedEntity> {
  SyncedCollection({
    required this.store,
    required this.outbox,
    required this.boxName,
    required this.collection,
    required this.fromJson,
    this.firestore,
    this.uid,
  });

  final HiveStore store;
  final Outbox outbox;

  /// Local Hive box name.
  final String boxName;

  /// Sub-collection name under `users/{uid}`.
  final String collection;

  final T Function(Map<String, dynamic> json) fromJson;

  /// Null in local mode. Every remote path is then skipped, not faked.
  final FirebaseFirestore? firestore;
  final String? uid;

  bool get canSync => firestore != null && uid != null;

  CollectionReference<Map<String, dynamic>>? get _remote => canSync
      ? firestore!.collection('users').doc(uid).collection(collection)
      : null;

  // ------------------------------------------------------------------ read --

  /// Live local data, newest write first. Tombstones are filtered out.
  Stream<List<T>> watchAll() =>
      store.watchAll(boxName).map(_decodeAll).distinct(_sameIds);

  List<T> readAll() => _decodeAll(store.readAll(boxName));

  T? readOne(String id) {
    final json = store.read(boxName, id);
    if (json == null) return null;
    final entity = fromJson(json);
    return entity.deletedAt == null ? entity : null;
  }

  Stream<T?> watchOne(String id) => store.watchOne(boxName, id).map((json) {
    if (json == null) return null;
    final entity = fromJson(json);
    return entity.deletedAt == null ? entity : null;
  });

  List<T> _decodeAll(List<Map<String, dynamic>> rows) {
    final items = <T>[];
    for (final row in rows) {
      final entity = fromJson(row);
      if (entity.deletedAt == null) items.add(entity);
    }
    items.sort((a, b) => b.updatedAt.compareTo(a.updatedAt));
    return items;
  }

  static bool _sameIds<E extends SyncedEntity>(List<E> a, List<E> b) {
    if (a.length != b.length) return false;
    for (var i = 0; i < a.length; i++) {
      if (a[i].id != b[i].id || a[i].updatedAt != b[i].updatedAt) return false;
    }
    return true;
  }

  // ----------------------------------------------------------------- write --

  /// Commits locally, then replicates. The returned [Result] reflects the
  /// LOCAL commit: a network failure is not an error the user needs to see,
  /// because the outbox guarantees the write will land.
  Future<Result<T>> put(T entity) async {
    final json = entity.toJson();
    try {
      await store.write(boxName, entity.id, json);
    } on Object catch (error) {
      return Err(StorageFailure(debugMessage: error.toString(), cause: error));
    }

    await outbox.enqueue(
      op: OutboxOp.upsert,
      collection: collection,
      docId: entity.id,
      payload: json,
    );

    unawaited(_pushOne(entity.id, json));
    return Ok(entity);
  }

  /// Soft-deletes. The tombstone replicates so the record does not come back
  /// on another device's next pull.
  Future<Result<void>> remove(
    String id, {
    required T Function(T) tombstone,
  }) async {
    final existing = store.read(boxName, id);
    if (existing == null) return const Err(NotFoundFailure());

    final marked = tombstone(fromJson(existing)).toJson();
    try {
      await store.write(boxName, id, marked);
    } on Object catch (error) {
      return Err(StorageFailure(debugMessage: error.toString(), cause: error));
    }

    await outbox.enqueue(
      op: OutboxOp.upsert,
      collection: collection,
      docId: id,
      payload: marked,
    );
    unawaited(_pushOne(id, marked));
    return const Ok(null);
  }

  Future<void> _pushOne(String id, Map<String, dynamic> json) async {
    final remote = _remote;
    if (remote == null) return;
    try {
      await remote
          .doc(id)
          .set(json, SetOptions(merge: true))
          .timeout(Env.networkTimeout);
      await outbox.complete(
        OutboxEntry(
          id: id,
          op: OutboxOp.upsert,
          collection: collection,
          docId: id,
          payload: json,
          createdAt: DateTime.now(),
        ),
      );
    } on Object {
      // Left in the outbox on purpose. The sync engine owns retry and backoff;
      // duplicating that logic here is how writes get lost twice.
    }
  }

  // ------------------------------------------------------------------ pull --

  /// Pulls remote changes into Hive.
  ///
  /// Last-write-wins on `updatedAt`, and a local record that is strictly newer
  /// is never overwritten — otherwise a slow pull could undo something the
  /// user typed thirty seconds ago.
  Future<Result<int>> pull({DateTime? since, int limit = 500}) async {
    final remote = _remote;
    if (remote == null) {
      return const Err(ServerFailure('firebase_unavailable'));
    }

    try {
      Query<Map<String, dynamic>> query = remote
          .orderBy('updatedAt', descending: true)
          .limit(limit);
      if (since != null) {
        query = remote
            .where('updatedAt', isGreaterThan: since.toUtc().toIso8601String())
            .orderBy('updatedAt', descending: true)
            .limit(limit);
      }

      final snapshot = await query.get().timeout(Env.networkTimeout);

      var applied = 0;
      final updates = <String, Map<String, dynamic>>{};
      for (final doc in snapshot.docs) {
        final remoteJson = doc.data();
        final localJson = store.read(boxName, doc.id);

        if (localJson != null) {
          final localAt = Json.date(localJson['updatedAt']);
          final remoteAt = Json.date(remoteJson['updatedAt']);
          if (!remoteAt.isAfter(localAt)) continue;
        }
        updates[doc.id] = remoteJson;
        applied++;
      }

      if (updates.isNotEmpty) await store.writeAll(boxName, updates);
      return Ok(applied);
    } on Object catch (error, stackTrace) {
      return Err(FailureMapper.from(error, stackTrace));
    }
  }
}
