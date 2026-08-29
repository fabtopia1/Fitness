import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lifedna/core/data/synced_collection.dart';
import 'package:lifedna/core/data/synced_entity.dart';
import 'package:lifedna/core/storage/hive_store.dart';
import 'package:lifedna/core/sync/outbox.dart';
import 'package:lifedna/core/sync/sync_engine.dart';

import '../../../support/test_harness.dart';

/// C-3 regression suite — the sync queue must never silently drop a write.
///
/// The defect: outbox entries are keyed by `collection/docId` so that rapid
/// edits to one document collapse into a single pending write. `complete()`
/// deleted that key unconditionally, and `_pushOne` handed it a *fabricated*
/// entry, so there was nothing to compare against.
///
///   write v1 → push starts on a slow link
///   write v2 → replaces the queued entry
///   v1's push returns OK → complete() deletes the entry holding **v2**
///
/// Firestore kept v1 forever. Hive kept v2, so last-write-wins hid it locally
/// and the divergence surfaced only on a second device. `recordFailure()` had
/// the same flaw in reverse: it wrote the stale payload back over the newer
/// one, so a failed push could *revert* a queued write.
///
/// The hot path is Live Gym Mode, which rewrites the session document on every
/// set — the highest-frequency write in the app, usually on gym wifi.
class _Note implements SyncedEntity {
  const _Note({required this.id, required this.text, required this.updatedAt});

  @override
  final String id;
  final String text;
  @override
  final DateTime updatedAt;
  @override
  DateTime? get deletedAt => null;

  @override
  Map<String, dynamic> toJson() => {
    'id': id,
    'text': text,
    'updatedAt': updatedAt.toIso8601String(),
  };

  static _Note fromJson(Map<String, dynamic> json) => _Note(
    id: Json.string(json['id']),
    text: Json.string(json['text']),
    updatedAt: Json.date(json['updatedAt'], fallback: DateTime(2026)),
  );
}

void main() {
  late TestEnvironment env;
  late Outbox outbox;

  setUp(() async {
    env = await TestEnvironment.create();
    outbox = Outbox(env.store);
  });
  tearDown(() async => env.dispose());

  Future<OutboxEntry> enqueue(String docId, String payload) => outbox.enqueue(
    op: OutboxOp.upsert,
    collection: 'notes',
    docId: docId,
    payload: {
      'id': docId,
      'text': payload,
      'updatedAt': '2026-01-01T00:00:00Z',
    },
  );

  group('completion is conditional on identity', () {
    test('completing a superseded entry leaves the newer one queued', () async {
      // The exact race. v1 is in flight when v2 replaces it.
      final v1 = await enqueue('a', 'v1');
      final v2 = await enqueue('a', 'v2');

      final removed = await outbox.complete(v1);

      expect(removed, isFalse, reason: 'v1 is no longer the queued entry');
      expect(outbox.length, 1);
      expect(outbox.pending().single.id, v2.id);
      expect(outbox.pending().single.payload['text'], 'v2');
    });

    test('completing the current entry does remove it', () async {
      final entry = await enqueue('a', 'v1');

      expect(await outbox.complete(entry), isTrue);
      expect(outbox.length, 0);
    });

    test('completing twice is harmless', () async {
      final entry = await enqueue('a', 'v1');

      expect(await outbox.complete(entry), isTrue);
      expect(await outbox.complete(entry), isFalse);
    });

    test('each enqueue gets a distinct identity', () async {
      // The whole guard rests on this: same key, different id.
      final first = await enqueue('a', 'v1');
      final second = await enqueue('a', 'v2');

      expect(first.id, isNot(second.id));
      expect(outbox.length, 1);
    });
  });

  group('failure handling is conditional too', () {
    test('a failed push cannot revert a newer queued payload', () async {
      final v1 = await enqueue('a', 'v1');
      final v2 = await enqueue('a', 'v2');

      final recorded = await outbox.recordFailure(v1, 'boom', DateTime.now());

      expect(recorded, isFalse);
      expect(outbox.pending().single.id, v2.id);
      expect(outbox.pending().single.payload['text'], 'v2');
      expect(
        outbox.pending().single.attempts,
        0,
        reason: 'the newer entry has not been attempted',
      );
    });

    test('a failed push on the current entry still backs it off', () async {
      final entry = await enqueue('a', 'v1');
      final now = DateTime(2026, 1, 1, 12);

      expect(await outbox.recordFailure(entry, 'boom', now), isTrue);

      final queued = outbox.pending().single;
      expect(queued.attempts, 1);
      expect(queued.isDue(now), isFalse);
    });

    test('recording against an already-completed entry is a no-op', () async {
      final entry = await enqueue('a', 'v1');
      await outbox.complete(entry);

      expect(
        await outbox.recordFailure(entry, 'boom', DateTime.now()),
        isFalse,
      );
      expect(outbox.length, 0);
    });
  });

  group('through SyncedCollection — the path the app actually uses', () {
    late FakeFirebaseFirestore firestore;

    SyncedCollection<_Note> build() => SyncedCollection<_Note>(
      store: env.store,
      outbox: outbox,
      boxName: HiveStore.boxMeta,
      collection: 'notes',
      fromJson: _Note.fromJson,
      firestore: firestore,
      uid: 'u1',
    );

    setUp(() => firestore = FakeFirebaseFirestore());

    Future<Map<String, dynamic>?> remote(String id) async =>
        (await firestore
                .collection('users')
                .doc('u1')
                .collection('notes')
                .doc(id)
                .get())
            .data();

    test('two writes in flight both reach the cloud', () async {
      final collection = build();

      await collection.put(
        _Note(id: 'a', text: 'v1', updatedAt: DateTime.utc(2026, 1, 1)),
      );
      await collection.put(
        _Note(id: 'a', text: 'v2', updatedAt: DateTime.utc(2026, 1, 2)),
      );
      await Future<void>.delayed(const Duration(milliseconds: 40));

      // Whichever push finished last, the queue must not have been emptied by
      // an older one, and the newest payload must be the one that lands.
      expect(await remote('a'), isNotNull);
      expect((await remote('a'))!['text'], 'v2');
      expect(collection.readOne('a')?.text, 'v2');
    });

    test(
      'a queued write survives a stale completion and drains later',
      () async {
        // Simulates the slow-link case directly: v1 is queued, v2 replaces it,
        // then v1's push reports success.
        final collection = build();
        await collection.put(
          _Note(id: 'a', text: 'v1', updatedAt: DateTime.utc(2026, 1, 1)),
        );
        final v1 = outbox.pending().single;

        await collection.put(
          _Note(id: 'a', text: 'v2', updatedAt: DateTime.utc(2026, 1, 2)),
        );
        await outbox.complete(v1);

        // v2 is still queued, so the engine will send it.
        final engine = SyncEngine(
          outbox: outbox,
          connectivity: env.connectivity,
          firestore: firestore,
          uid: 'u1',
        );
        await engine.drain();
        await engine.dispose();

        expect((await remote('a'))!['text'], 'v2');
        expect(outbox.length, 0);
      },
    );
  });

  group('multi-device convergence', () {
    test('a write made while offline reaches the other device', () async {
      final firestore = FakeFirebaseFirestore();

      // Device A, offline: the write commits locally and queues.
      env.connectivity.online = false;
      final deviceA = SyncedCollection<_Note>(
        store: env.store,
        outbox: outbox,
        boxName: HiveStore.boxMeta,
        collection: 'notes',
        fromJson: _Note.fromJson,
        firestore: firestore,
        uid: 'u1',
      );
      await deviceA.put(
        _Note(
          id: 'a',
          text: 'logged offline',
          updatedAt: DateTime.utc(2026, 5),
        ),
      );

      // Coming back online drains the queue.
      env.connectivity.online = true;
      final engine = SyncEngine(
        outbox: outbox,
        connectivity: env.connectivity,
        firestore: firestore,
        uid: 'u1',
      );
      await engine.drain();
      await engine.dispose();

      // Device B pulls it.
      final other = await TestEnvironment.create();
      addTearDown(other.dispose);
      final deviceB = SyncedCollection<_Note>(
        store: other.store,
        outbox: Outbox(other.store),
        boxName: HiveStore.boxMeta,
        collection: 'notes',
        fromJson: _Note.fromJson,
        firestore: firestore,
        uid: 'u1',
      );
      await deviceB.pull();

      expect(deviceB.readOne('a')?.text, 'logged offline');
    });

    test('a pull never overwrites a write the user just made', () async {
      final firestore = FakeFirebaseFirestore();
      await firestore
          .collection('users')
          .doc('u1')
          .collection('notes')
          .doc('a')
          .set(
            _Note(
              id: 'a',
              text: 'from the other phone',
              updatedAt: DateTime.utc(2026, 1),
            ).toJson(),
          );

      final collection = SyncedCollection<_Note>(
        store: env.store,
        outbox: outbox,
        boxName: HiveStore.boxMeta,
        collection: 'notes',
        fromJson: _Note.fromJson,
        firestore: firestore,
        uid: 'u1',
      );
      await collection.put(
        _Note(
          id: 'a',
          text: 'typed just now',
          updatedAt: DateTime.utc(2026, 6),
        ),
      );

      await collection.pull();

      expect(collection.readOne('a')?.text, 'typed just now');
    });
  });
}
