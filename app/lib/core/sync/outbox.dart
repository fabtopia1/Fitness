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

  Future<void> enqueue({
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
  }

  List<OutboxEntry> pending() =>
      _store.readAll(HiveStore.boxOutbox).map(OutboxEntry.fromJson).toList()
        ..sort((a, b) => a.createdAt.compareTo(b.createdAt));

  List<OutboxEntry> due(DateTime now) =>
      pending().where((e) => e.isDue(now)).toList();

  List<OutboxEntry> parked() => pending().where((e) => e.isParked).toList();

  int get length => _store.box(HiveStore.boxOutbox).length;

  Future<void> complete(OutboxEntry entry) =>
      _store.delete(HiveStore.boxOutbox, '${entry.collection}/${entry.docId}');

  Future<void> recordFailure(OutboxEntry entry, String error, DateTime now) =>
      _store.write(
        HiveStore.boxOutbox,
        '${entry.collection}/${entry.docId}',
        entry.withFailure(error, now).toJson(),
      );

  /// Clears the backoff on parked entries so the user can retry by hand.
  Future<void> retryParked() async {
    for (final entry in parked()) {
      await _store.write(
        HiveStore.boxOutbox,
        '${entry.collection}/${entry.docId}',
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
