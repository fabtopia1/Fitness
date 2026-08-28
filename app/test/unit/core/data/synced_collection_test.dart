import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lifedna/core/data/synced_collection.dart';
import 'package:lifedna/core/data/synced_entity.dart';
import 'package:lifedna/core/error/failure.dart';
import 'package:lifedna/core/storage/hive_store.dart';
import 'package:lifedna/core/sync/outbox.dart';

import '../../../support/test_harness.dart';

/// A minimal entity, so the test exercises [SyncedCollection] rather than a
/// particular feature's schema.
class _Note implements SyncedEntity {
  const _Note({
    required this.id,
    required this.text,
    required this.updatedAt,
    this.deletedAt,
  });

  @override
  final String id;
  final String text;
  @override
  final DateTime updatedAt;
  @override
  final DateTime? deletedAt;

  _Note copyWith({String? text, DateTime? updatedAt, DateTime? deletedAt}) =>
      _Note(
        id: id,
        text: text ?? this.text,
        updatedAt: updatedAt ?? this.updatedAt,
        deletedAt: deletedAt ?? this.deletedAt,
      );

  @override
  Map<String, dynamic> toJson() => {
    'id': id,
    'text': text,
    'updatedAt': updatedAt.toIso8601String(),
    'deletedAt': deletedAt?.toIso8601String(),
  };

  static _Note fromJson(Map<String, dynamic> json) => _Note(
    id: Json.string(json['id']),
    text: Json.string(json['text']),
    updatedAt: Json.date(json['updatedAt'], fallback: DateTime(2026)),
    deletedAt: Json.dateOrNull(json['deletedAt']),
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

  SyncedCollection<_Note> build({
    FakeFirebaseFirestore? firestore,
    String? uid,
  }) => SyncedCollection<_Note>(
    store: env.store,
    outbox: outbox,
    boxName: HiveStore.boxMeta,
    collection: 'notes',
    fromJson: _Note.fromJson,
    firestore: firestore,
    uid: uid,
  );

  _Note note(String id, {String text = 'hello', DateTime? at}) =>
      _Note(id: id, text: text, updatedAt: at ?? DateTime.utc(2026, 1, 1));

  group('local mode', () {
    test('canSync is false without both a firestore and a uid', () {
      expect(build().canSync, isFalse);
      expect(build(firestore: FakeFirebaseFirestore()).canSync, isFalse);
      expect(build(uid: 'u1').canSync, isFalse);
      expect(
        build(firestore: FakeFirebaseFirestore(), uid: 'u1').canSync,
        isTrue,
      );
    });

    test('put commits locally and still queues for a later sync', () async {
      final collection = build();
      final result = await collection.put(note('a'));

      expect(result.isOk, isTrue);
      expect(collection.readOne('a')?.text, 'hello');
      // The queue is the promise that this reaches the cloud once an account
      // exists. Dropping it here is how a local-mode user loses their history
      // the moment they sign in.
      expect(outbox.length, 1);
    });

    test('pull reports firebase_unavailable instead of pretending', () async {
      final result = await build().pull();
      expect(result.failureOrNull, isA<ServerFailure>());
    });
  });

  group('reads', () {
    test('readAll hides tombstones', () async {
      final collection = build();
      await collection.put(note('a'));
      await collection.put(note('b'));
      await collection.remove(
        'b',
        tombstone: (value) => value.copyWith(deletedAt: DateTime.utc(2026, 2)),
      );

      expect(collection.readAll().map((n) => n.id), ['a']);
      expect(collection.readOne('b'), isNull);
    });

    test('readAll is newest first', () async {
      final collection = build();
      await collection.put(note('old', at: DateTime.utc(2026, 1, 1)));
      await collection.put(note('new', at: DateTime.utc(2026, 3, 1)));

      expect(collection.readAll().map((n) => n.id), ['new', 'old']);
    });

    test('watchAll emits the current contents and each change', () async {
      final collection = build();
      final seen = <List<String>>[];
      final sub = collection.watchAll().listen(
        (notes) => seen.add(notes.map((n) => n.id).toList()),
      );

      await Future<void>.delayed(Duration.zero);
      await collection.put(note('a'));
      await Future<void>.delayed(Duration.zero);

      await sub.cancel();
      expect(seen.last, ['a']);
    });

    test('removing something that was never there is a NotFound', () async {
      final result = await build().remove('ghost', tombstone: (value) => value);
      expect(result.failureOrNull, isA<NotFoundFailure>());
    });
  });

  group('cloud mode', () {
    late FakeFirebaseFirestore firestore;

    setUp(() => firestore = FakeFirebaseFirestore());

    test(
      'put replicates to users/{uid}/{collection}/{id} and clears the queue',
      () async {
        final collection = build(firestore: firestore, uid: 'u1');
        await collection.put(note('a', text: 'synced'));
        // The push is fire-and-forget, so give the microtask queue a turn.
        await Future<void>.delayed(const Duration(milliseconds: 20));

        final doc = await firestore
            .collection('users')
            .doc('u1')
            .collection('notes')
            .doc('a')
            .get();

        expect(doc.exists, isTrue);
        expect(doc.data()?['text'], 'synced');
        expect(outbox.length, 0);
      },
    );

    test('a tombstone replicates so other devices converge', () async {
      final collection = build(firestore: firestore, uid: 'u1');
      await collection.put(note('a'));
      await collection.remove(
        'a',
        tombstone: (value) => value.copyWith(deletedAt: DateTime.utc(2026, 2)),
      );
      await Future<void>.delayed(const Duration(milliseconds: 20));

      final doc = await firestore
          .collection('users')
          .doc('u1')
          .collection('notes')
          .doc('a')
          .get();

      // The document still exists remotely, carrying its deletion marker. A
      // hard delete would be resurrected by the other device's next pull.
      expect(doc.data()?['deletedAt'], isNotNull);
    });

    test('pull writes remote documents into Hive', () async {
      await firestore
          .collection('users')
          .doc('u1')
          .collection('notes')
          .doc('remote')
          .set(note('remote', text: 'from cloud').toJson());

      final collection = build(firestore: firestore, uid: 'u1');
      final result = await collection.pull();

      expect(result.valueOrNull, 1);
      expect(collection.readOne('remote')?.text, 'from cloud');
    });

    test('pull never overwrites a strictly newer local record', () async {
      final collection = build(firestore: firestore, uid: 'u1');
      await collection.put(
        note('a', text: 'typed 30 seconds ago', at: DateTime.utc(2026, 6, 1)),
      );

      await firestore
          .collection('users')
          .doc('u1')
          .collection('notes')
          .doc('a')
          .set(note('a', text: 'stale', at: DateTime.utc(2026, 1, 1)).toJson());

      await collection.pull();

      expect(collection.readOne('a')?.text, 'typed 30 seconds ago');
    });

    test('pull applies a strictly newer remote record', () async {
      final collection = build(firestore: firestore, uid: 'u1');
      await collection.put(
        note('a', text: 'old', at: DateTime.utc(2026, 1, 1)),
      );

      await firestore
          .collection('users')
          .doc('u1')
          .collection('notes')
          .doc('a')
          .set(note('a', text: 'newer', at: DateTime.utc(2026, 6, 1)).toJson());

      await collection.pull();

      expect(collection.readOne('a')?.text, 'newer');
    });
  });
}
