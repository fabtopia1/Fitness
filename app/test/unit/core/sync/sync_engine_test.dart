import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lifedna/core/sync/outbox.dart';
import 'package:lifedna/core/sync/sync_engine.dart';

import '../../../support/test_harness.dart';

void main() {
  late TestEnvironment env;
  late Outbox outbox;
  late FakeFirebaseFirestore firestore;

  setUp(() async {
    env = await TestEnvironment.create();
    outbox = Outbox(env.store);
    firestore = FakeFirebaseFirestore();
  });
  tearDown(() async => env.dispose());

  SyncEngine build({bool cloud = true}) => SyncEngine(
        outbox: outbox,
        connectivity: env.connectivity,
        firestore: cloud ? firestore : null,
        uid: cloud ? 'u1' : null,
      );

  Future<void> enqueue(
    String collection,
    String docId, {
    OutboxOp op = OutboxOp.upsert,
  }) =>
      outbox.enqueue(
        op: op,
        collection: collection,
        docId: docId,
        payload: {'id': docId, 'updatedAt': '2026-01-01T00:00:00.000Z'},
      );

  test('local mode reports localOnly and never touches the queue', () async {
    final engine = build(cloud: false);
    await enqueue('tasks', 'a');

    engine.start();
    await engine.drain();

    expect(engine.canSync, isFalse);
    expect(engine.state.phase, SyncPhase.localOnly);
    expect(outbox.length, 1);
    await engine.dispose();
  });

  test('draining uploads every due entry and empties the queue', () async {
    final engine = build();
    await enqueue('tasks', 'a');
    await enqueue('meals', 'b');

    await engine.drain();

    expect(outbox.length, 0);
    expect(engine.state.phase, SyncPhase.idle);
    expect(engine.state.pending, 0);
    expect(engine.state.lastSyncedAt, isNotNull);

    final doc = await firestore
        .collection('users')
        .doc('u1')
        .collection('tasks')
        .doc('a')
        .get();
    expect(doc.exists, isTrue);
    await engine.dispose();
  });

  test('a delete entry removes the remote document', () async {
    await firestore
        .collection('users')
        .doc('u1')
        .collection('tasks')
        .doc('a')
        .set({'id': 'a'});

    final engine = build();
    await enqueue('tasks', 'a', op: OutboxOp.delete);
    await engine.drain();

    final doc = await firestore
        .collection('users')
        .doc('u1')
        .collection('tasks')
        .doc('a')
        .get();
    expect(doc.exists, isFalse);
    await engine.dispose();
  });

  test('the profile entry targets users/{uid}, not a sub-collection', () async {
    // The profile is the one payload that lives AT the user document. Routing
    // it like a sub-collection would strand it in users/{uid}/__profile__.
    final engine = build();
    await outbox.enqueue(
      op: OutboxOp.upsert,
      collection: Outbox.profileCollection,
      docId: 'u1',
      payload: {'id': 'u1', 'displayName': 'Sam'},
    );

    await engine.drain();

    final user = await firestore.collection('users').doc('u1').get();
    expect(user.data()?['displayName'], 'Sam');

    final stray = await firestore
        .collection('users')
        .doc('u1')
        .collection(Outbox.profileCollection)
        .get();
    expect(stray.docs, isEmpty);
    await engine.dispose();
  });

  test('being offline holds the queue rather than dropping it', () async {
    env.connectivity.online = false;
    final engine = build();
    await enqueue('tasks', 'a');

    await engine.drain();

    expect(engine.state.phase, SyncPhase.offline);
    expect(outbox.length, 1);
    await engine.dispose();
  });

  test('start emits the initial state and drains when already online',
      () async {
    final engine = build();
    await enqueue('tasks', 'a');

    engine.start();
    await Future<void>.delayed(const Duration(milliseconds: 50));

    expect(outbox.length, 0);
    await engine.dispose();
  });

  test('the state stream reports what the banner needs', () async {
    final engine = build();
    final phases = <SyncPhase>[];
    final sub = engine.stream.listen((state) => phases.add(state.phase));

    await enqueue('tasks', 'a');
    await engine.drain();
    await Future<void>.delayed(Duration.zero);

    expect(phases, contains(SyncPhase.syncing));
    expect(phases.last, SyncPhase.idle);
    await sub.cancel();
    await engine.dispose();
  });

  test('SyncState reports unsynced work and the condition worth surfacing',
      () {
    const clean = SyncState();
    expect(clean.hasUnsyncedWork, isFalse);
    expect(clean.needsAttention, isFalse);

    const queued = SyncState(pending: 3);
    expect(queued.hasUnsyncedWork, isTrue);
    expect(queued.needsAttention, isFalse);

    // Parked work is the one sync condition a user must be told about.
    const stuck = SyncState(pending: 3, parked: 1);
    expect(stuck.needsAttention, isTrue);
  });
}
