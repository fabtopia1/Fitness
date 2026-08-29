import 'package:lifedna/core/storage/hive_store.dart';
import 'package:uuid/uuid.dart';

enum OutboxOp { upsert, delete }

/// One pending replication to Firestore.
///
/// The outbox is what turns "we tried to save it" into "it will be saved".
/// A failed write is never lost and never silently dropped: after the retry
/// budget is exhausted the entry is *parked* and surfaced in Settings, because
/// silently discarding a user's logged workout is the worst failure mode this
/// app has.
class OutboxEntry {
  const OutboxEntry({
    required this.id,
    required this.op,
    required this.collection,
    required this.docId,
    required this.payload,
    required this.createdAt,
    this.attempts = 0,
    this.nextAttemptAt,
    this.lastError,
  });

  final String id;
  final OutboxOp op;

  /// Sub-collection under `users/{uid}`.
  final String collection;
  final String docId;
  final Map<String, dynamic> payload;
  final DateTime createdAt;
  final int attempts;
  final DateTime? nextAttemptAt;
  final String? lastError;

  /// After this many failures the entry is parked for manual retry.
  static const int maxAttempts = 10;

  bool get isParked => attempts >= maxAttempts;

  bool isDue(DateTime now) =>
      !isParked && (nextAttemptAt == null || !nextAttemptAt!.isAfter(now));

  /// Exponential backoff, capped at 15 minutes.
  OutboxEntry withFailure(String error, DateTime now) {
    final next = attempts + 1;
    final delaySeconds = (2 << next.clamp(0, 9)).clamp(2, 900);
    return copyWith(
      attempts: next,
      nextAttemptAt: now.add(Duration(seconds: delaySeconds)),
      lastError: error,
    );
  }

  OutboxEntry copyWith({
    int? attempts,
    DateTime? nextAttemptAt,
    String? lastError,
  }) => OutboxEntry(
    id: id,
    op: op,
    collection: collection,
    docId: docId,
    payload: payload,
    createdAt: createdAt,
    attempts: attempts ?? this.attempts,
    nextAttemptAt: nextAttemptAt ?? this.nextAttemptAt,
    lastError: lastError ?? this.lastError,
  );

  Map<String, dynamic> toJson() => {
    'id': id,
    'op': op.name,
    'collection': collection,
    'docId': docId,
    'payload': payload,
    'createdAt': createdAt.toIso8601String(),
    'attempts': attempts,
    'nextAttemptAt': nextAttemptAt?.toIso8601String(),
    'lastError': lastError,
  };

  factory OutboxEntry.fromJson(Map<String, dynamic> json) => OutboxEntry(
    id: json['id'] as String,
    op: OutboxOp.values.firstWhere(
      (o) => o.name == json['op'],
      orElse: () => OutboxOp.upsert,
    ),
    collection: json['collection'] as String,
    docId: json['docId'] as String,
    payload: Map<String, dynamic>.from(json['payload'] as Map? ?? const {}),
    createdAt: DateTime.parse(json['createdAt'] as String),
    attempts: (json['attempts'] as num?)?.toInt() ?? 0,
    nextAttemptAt: json['nextAttemptAt'] == null
        ? null
        : DateTime.parse(json['nextAttemptAt'] as String),
    lastError: json['lastError'] as String?,
  );
}

class Outbox {
  Outbox(this._store, {this.uuid = const Uuid()});

  /// Sentinel collection for the user's own profile document.
  ///
  /// The profile lives AT `users/{uid}`, not in a sub-collection of it, so the
  /// sync engine has to route it differently. Naming that route here — rather
  /// than letting a magic string travel between two files — is what stops a
  /// profile ending up replicated into a phantom sub-collection.
  static const String profileCollection = '__profile__';

  final HiveStore _store;
  final Uuid uuid;

  /// Queues a write and returns the entry, so the caller can complete exactly
  /// the entry it queued rather than whatever happens to be under the key
  /// later. See [complete].
  Future<OutboxEntry> enqueue({
    required OutboxOp op,
    required String collection,
    required String docId,
    required Map<String, dynamic> payload,
    DateTime? now,
  }) async {
    // Keyed by collection+doc so rapid edits to the same record collapse into
    // one pending write instead of queueing a redundant chain.
    final key = '$collection/$docId';
    final entry = OutboxEntry(
      id: uuid.v4(),
      op: op,
      collection: collection,
      docId: docId,
      payload: payload,
      createdAt: now ?? DateTime.now(),
    );
    await _store.write(HiveStore.boxOutbox, key, entry.toJson());
    return entry;
  }

  List<OutboxEntry> pending() =>
      _store.readAll(HiveStore.boxOutbox).map(OutboxEntry.fromJson).toList()
        ..sort((a, b) => a.createdAt.compareTo(b.createdAt));

  List<OutboxEntry> due(DateTime now) =>
      pending().where((e) => e.isDue(now)).toList();

  List<OutboxEntry> parked() => pending().where((e) => e.isParked).toList();

  int get length => _store.box(HiveStore.boxOutbox).length;

  String _keyFor(OutboxEntry entry) => '${entry.collection}/${entry.docId}';

  /// The entry currently queued for the same document, if any.
  OutboxEntry? current(OutboxEntry entry) {
    final json = _store.read(HiveStore.boxOutbox, _keyFor(entry));
    return json == null ? null : OutboxEntry.fromJson(json);
  }

  /// Removes [entry] — but ONLY if it is still the entry that is queued.
  ///
  /// Entries are keyed by document so that rapid edits collapse, which means a
  /// second write can replace the queued payload while the first is still in
  /// flight. An unconditional delete here would then remove the NEWER payload
  /// on the older push's success: Firestore would keep v1 forever while Hive
  /// held v2, and because last-write-wins hides that locally, the divergence
  /// only surfaces on the user's second device.
  ///
  /// [OutboxEntry.id] is a fresh UUID per enqueue, so comparing it is exactly
  /// the guard needed. Returns whether anything was removed.
  Future<bool> complete(OutboxEntry entry) async {
    final queued = current(entry);
    if (queued == null) return false;
    if (queued.id != entry.id) {
      // A newer write replaced this one while it was uploading. Leave it
      // queued; the sync engine will send it on the next drain.
      return false;
    }
    await _store.delete(HiveStore.boxOutbox, _keyFor(entry));
    return true;
  }

  /// Records a failed attempt against [entry] — but ONLY if it is still the
  /// entry that is queued.
  ///
  /// The unguarded version had the same defect as [complete] in the other
  /// direction: it wrote the STALE entry's payload back over the newer one, so
  /// a failed push could revert a queued write.
  Future<bool> recordFailure(
    OutboxEntry entry,
    String error,
    DateTime now,
  ) async {
    final queued = current(entry);
    if (queued == null || queued.id != entry.id) return false;
    await _store.write(
      HiveStore.boxOutbox,
      _keyFor(entry),
      entry.withFailure(error, now).toJson(),
    );
    return true;
  }

  /// Clears the backoff on parked entries so the user can retry by hand.
  Future<void> retryParked() async {
    for (final entry in parked()) {
      await _store.write(
        HiveStore.boxOutbox,
        _keyFor(entry),
        OutboxEntry(
          id: entry.id,
          op: entry.op,
          collection: entry.collection,
          docId: entry.docId,
          payload: entry.payload,
          createdAt: entry.createdAt,
        ).toJson(),
      );
    }
  }

  Future<void> clear() => _store.clearBox(HiveStore.boxOutbox);
}
