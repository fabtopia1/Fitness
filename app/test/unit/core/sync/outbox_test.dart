import 'package:flutter_test/flutter_test.dart';
import 'package:lifedna/core/sync/outbox.dart';

import '../../../support/test_harness.dart';

void main() {
  late TestEnvironment env;
  late Outbox outbox;

  setUp(() async {
    env = await TestEnvironment.create();
    outbox = Outbox(env.store);
  });
  tearDown(() async => env.dispose());

  Future<void> enqueue(String collection, String docId, {DateTime? now}) =>
      outbox.enqueue(
        op: OutboxOp.upsert,
        collection: collection,
        docId: docId,
        payload: {'id': docId},
        now: now,
      );

  test('an enqueued entry is pending and due immediately', () async {
    await enqueue('tasks', 'a');
    expect(outbox.length, 1);
    expect(outbox.due(DateTime.now()), hasLength(1));
    expect(outbox.parked(), isEmpty);
  });

  test('repeated edits to one document collapse into a single entry', () async {
    // Otherwise typing in a text field would queue one network write per
    // keystroke, and the outbox would drain long after the user finished.
    await enqueue('tasks', 'a');
    await enqueue('tasks', 'a');
    await enqueue('tasks', 'a');
    expect(outbox.length, 1);
  });

  test('different documents queue separately', () async {
    await enqueue('tasks', 'a');
    await enqueue('tasks', 'b');
    await enqueue('meals', 'a');
    expect(outbox.length, 3);
  });

  test('pending is ordered oldest first', () async {
    final base = DateTime(2026, 1, 1, 12);
    await enqueue('tasks', 'late', now: base.add(const Duration(minutes: 5)));
    await enqueue('tasks', 'early', now: base);

    expect(outbox.pending().map((e) => e.docId), ['early', 'late']);
  });

  test('complete removes the entry', () async {
    await enqueue('tasks', 'a');
    await outbox.complete(outbox.pending().single);
    expect(outbox.length, 0);
  });

  test('a failure backs the entry off instead of retrying immediately',
      () async {
    final now = DateTime(2026, 1, 1, 12);
    await enqueue('tasks', 'a', now: now);

    await outbox.recordFailure(outbox.pending().single, 'boom', now);

    final entry = outbox.pending().single;
    expect(entry.attempts, 1);
    expect(entry.lastError, 'boom');
    expect(entry.isDue(now), isFalse);
    expect(entry.isDue(now.add(const Duration(minutes: 20))), isTrue);
  });

  test('backoff grows with each attempt and is capped', () async {
    final now = DateTime(2026, 1, 1, 12);
    await enqueue('tasks', 'a', now: now);

    Duration delayAfter(int failures) {
      var entry = outbox.pending().single;
      for (var i = 0; i < failures; i++) {
        entry = entry.withFailure('boom', now);
      }
      return entry.nextAttemptAt!.difference(now);
    }

    expect(delayAfter(1) < delayAfter(3), isTrue);
    // Capped so a long-offline device does not schedule a retry hours out.
    expect(delayAfter(9).inSeconds, lessThanOrEqualTo(900));
  });

  test('an entry parks after the retry budget and stops being due', () async {
    final now = DateTime(2026, 1, 1, 12);
    await enqueue('tasks', 'a', now: now);

    for (var i = 0; i < OutboxEntry.maxAttempts; i++) {
      await outbox.recordFailure(outbox.pending().single, 'boom', now);
    }

    final entry = outbox.pending().single;
    expect(entry.isParked, isTrue);
    expect(outbox.parked(), hasLength(1));
    // Parked work is never silently discarded — it is surfaced instead.
    expect(outbox.length, 1);
    expect(outbox.due(now.add(const Duration(days: 1))), isEmpty);
  });

  test('retryParked clears the backoff so the entry runs again', () async {
    final now = DateTime(2026, 1, 1, 12);
    await enqueue('tasks', 'a', now: now);
    for (var i = 0; i < OutboxEntry.maxAttempts; i++) {
      await outbox.recordFailure(outbox.pending().single, 'boom', now);
    }

    await outbox.retryParked();

    expect(outbox.parked(), isEmpty);
    expect(outbox.due(now), hasLength(1));
  });

  test('an entry survives a JSON round-trip with its retry state', () {
    final entry = OutboxEntry(
      id: 'x',
      op: OutboxOp.delete,
      collection: 'tasks',
      docId: 'a',
      payload: const {'id': 'a'},
      createdAt: DateTime(2026, 1, 1, 12),
      attempts: 3,
      nextAttemptAt: DateTime(2026, 1, 1, 12, 5),
      lastError: 'boom',
    );

    final restored = OutboxEntry.fromJson(entry.toJson());
    expect(restored.op, OutboxOp.delete);
    expect(restored.attempts, 3);
    expect(restored.lastError, 'boom');
    expect(restored.nextAttemptAt, entry.nextAttemptAt);
    expect(restored.payload, entry.payload);
  });

  test('clear empties the queue', () async {
    await enqueue('tasks', 'a');
    await outbox.clear();
    expect(outbox.length, 0);
  });
}
