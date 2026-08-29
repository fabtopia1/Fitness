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

    final queued = await outbox.enqueue(
      op: OutboxOp.upsert,
      collection: collection,
      docId: entity.id,
      payload: json,
    );

    unawaited(_pushOne(queued));
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

    final queued = await outbox.enqueue(
      op: OutboxOp.upsert,
      collection: collection,
      docId: id,
      payload: marked,
    );
    unawaited(_pushOne(queued));
    return const Ok(null);
  }

  /// Best-effort immediate replication of a queued entry.
  ///
  /// Takes the entry rather than a payload so that completion can be
  /// conditional: a second write to the same document while this one is in
  /// flight replaces the queued entry, and [Outbox.complete] must then leave
  /// the newer one alone. Fabricating an entry here — which the first version
  /// did — made that check impossible and silently dropped the newer write.
  Future<void> _pushOne(OutboxEntry entry) async {
    final remote = _remote;
    if (remote == null) return;
    try {
      await remote
          .doc(entry.docId)
          .set(entry.payload, SetOptions(merge: true))
          .timeout(Env.networkTimeout);
      await outbox.complete(entry);
    } on Object {
      // Left in the outbox on purpose. The sync engine owns retry and backoff;
      // duplicating that logic here is how writes get lost twice.
    }
  }

  // ------------------------------------------------------------------ pull --

  /// Pulls remote changes into Hive, paging until the collection is drained.
  ///
  /// Last-write-wins on `updatedAt`, and a local record that is strictly newer
  /// is never overwritten — otherwise a slow pull could undo something the
  /// user typed thirty seconds ago.
  ///
  /// Paging matters: a user restoring onto a new device has years of history,
  /// and a single 500-document page would silently hand them a truncated
  /// training log. [maxPages] bounds the work so one call cannot run forever
  /// on a very large account.
  Future<Result<int>> pull({
    DateTime? since,
    int pageSize = 500,
    int maxPages = 40,
  }) async {
    final remote = _remote;
    if (remote == null) {
      return const Err(ServerFailure('firebase_unavailable'));
    }

    try {
      var applied = 0;
      DocumentSnapshot<Map<String, dynamic>>? cursor;

      for (var page = 0; page < maxPages; page++) {
        // Ascending by updatedAt so the cursor walks forward through history
        // rather than stopping at the newest page.
        Query<Map<String, dynamic>> query = remote.orderBy('updatedAt');
        if (since != null) {
          query = query.where(
            'updatedAt',
            isGreaterThan: since.toUtc().toIso8601String(),
          );
        }
        if (cursor != null) query = query.startAfterDocument(cursor);

        final snapshot = await query
            .limit(pageSize)
            .get()
            .timeout(Env.networkTimeout);

        if (snapshot.docs.isEmpty) break;

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

        cursor = snapshot.docs.last;
        if (snapshot.docs.length < pageSize) break;
      }

      return Ok(applied);
    } on Object catch (error, stackTrace) {
      return Err(FailureMapper.from(error, stackTrace));
    }
  }
}
