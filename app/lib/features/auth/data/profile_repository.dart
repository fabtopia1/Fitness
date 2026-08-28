import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:lifedna/core/config/env.dart';
import 'package:lifedna/core/error/failure.dart';
import 'package:lifedna/core/error/failure_mapper.dart';
import 'package:lifedna/core/result/result.dart';
import 'package:lifedna/core/storage/hive_store.dart';
import 'package:lifedna/core/sync/outbox.dart';
import 'package:lifedna/features/auth/domain/user_profile.dart';

/// The user's own profile document.
///
/// Not a [SyncedCollection] because it is a single document rather than a
/// collection, and it lives at `users/{uid}` rather than under it.
class ProfileRepository {
  ProfileRepository({
    required HiveStore store,
    required Outbox outbox,
    FirebaseFirestore? firestore,
    String? uid,
  })  : _store = store,
        _outbox = outbox,
        _firestore = firestore,
        _uid = uid;

  final HiveStore _store;
  final Outbox _outbox;
  final FirebaseFirestore? _firestore;
  final String? _uid;

  static const _key = 'me';

  Stream<UserProfile?> watch() =>
      _store.watchOne(HiveStore.boxProfile, _key).map(
            (json) => json == null ? null : UserProfile.fromJson(json),
          );

  UserProfile? read() {
    final json = _store.read(HiveStore.boxProfile, _key);
    return json == null ? null : UserProfile.fromJson(json);
  }

  Future<Result<UserProfile>> save(UserProfile profile) async {
    final json = profile.toJson();
    try {
      await _store.write(HiveStore.boxProfile, _key, json);
    } on Object catch (error) {
      return Err(StorageFailure(debugMessage: error.toString(), cause: error));
    }

    await _outbox.enqueue(
      op: OutboxOp.upsert,
      collection: '__profile__',
      docId: profile.id,
      payload: json,
    );

    final firestore = _firestore;
    final uid = _uid;
    if (firestore != null && uid != null) {
      try {
        await firestore
            .collection('users')
            .doc(uid)
            .set(json, SetOptions(merge: true))
            .timeout(Env.networkTimeout);
        await _outbox.complete(
          OutboxEntry(
            id: profile.id,
            op: OutboxOp.upsert,
            collection: '__profile__',
            docId: profile.id,
            payload: json,
            createdAt: DateTime.now(),
          ),
        );
      } on Object {
        // Stays queued; the sync engine owns retry.
      }
    }
    return Ok(profile);
  }

  /// Pulls the remote profile if it is newer than the local copy.
  Future<Result<UserProfile?>> pull() async {
    final firestore = _firestore;
    final uid = _uid;
    if (firestore == null || uid == null) {
      return const Err(ServerFailure('firebase_unavailable'));
    }
    try {
      final snapshot = await firestore
          .collection('users')
          .doc(uid)
          .get()
          .timeout(Env.networkTimeout);

      final data = snapshot.data();
      if (data == null) return const Ok(null);

      final remote = UserProfile.fromJson(data);
      final local = read();
      if (local != null && !remote.updatedAt.isAfter(local.updatedAt)) {
        return Ok(local);
      }
      await _store.write(HiveStore.boxProfile, _key, remote.toJson());
      return Ok(remote);
    } on Object catch (error, stackTrace) {
      return Err(FailureMapper.from(error, stackTrace));
    }
  }
}
