import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/foundation.dart';
import 'package:lifedna/core/config/env.dart';
import 'package:lifedna/core/network/connectivity_service.dart';
import 'package:lifedna/core/sync/outbox.dart';

enum SyncPhase { idle, syncing, offline, error, localOnly }

@immutable
class SyncState {
  const SyncState({
    this.phase = SyncPhase.idle,
    this.pending = 0,
    this.parked = 0,
    this.lastSyncedAt,
    this.lastError,
  });

  final SyncPhase phase;
  final int pending;
  final int parked;
  final DateTime? lastSyncedAt;
  final String? lastError;

  bool get hasUnsyncedWork => pending > 0;

  /// Parked work is the one sync condition a user must be told about: it means
  /// something they logged is not going to reach the cloud without help.
  bool get needsAttention => parked > 0;

  SyncState copyWith({
    SyncPhase? phase,
    int? pending,
    int? parked,
    DateTime? lastSyncedAt,
    String? lastError,
  }) =>
      SyncState(
        phase: phase ?? this.phase,
        pending: pending ?? this.pending,
        parked: parked ?? this.parked,
        lastSyncedAt: lastSyncedAt ?? this.lastSyncedAt,
        lastError: lastError,
      );

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is SyncState &&
          other.phase == phase &&
          other.pending == pending &&
          other.parked == parked &&
          other.lastSyncedAt == lastSyncedAt &&
          other.lastError == lastError;

  @override
  int get hashCode =>
      Object.hash(phase, pending, parked, lastSyncedAt, lastError);
}

/// Drains the outbox to Firestore.
///
/// Runs on connectivity regain, on app foreground, and on a periodic tick.
/// Nothing in the UI waits on it — it is a background reconciler, and the app
/// is fully usable whether it ever succeeds or not.
class SyncEngine {
  SyncEngine({
    required Outbox outbox,
    required ConnectivityService connectivity,
    FirebaseFirestore? firestore,
    String? uid,
    Duration interval = const Duration(minutes: 5),
  })  : _outbox = outbox,
        _connectivity = connectivity,
        _firestore = firestore,
        _uid = uid,
        _interval = interval;

  final Outbox _outbox;
  final ConnectivityService _connectivity;
  final FirebaseFirestore? _firestore;
  final String? _uid;
  final Duration _interval;

  final _controller = StreamController<SyncState>.broadcast();
  StreamSubscription<bool>? _connectivitySub;
  Timer? _timer;
  bool _running = false;
  SyncState _state = const SyncState();

  Stream<SyncState> get stream => _controller.stream;
  SyncState get state => _state;

  bool get canSync => _firestore != null && _uid != null;

  void start() {
    _emit(_state.copyWith(
      phase: canSync ? SyncPhase.idle : SyncPhase.localOnly,
      pending: _outbox.length,
      parked: _outbox.parked().length,
    ));
    if (!canSync) return;

    _connectivitySub = _connectivity.onStatusChange.listen((online) {
      if (online) {
        unawaited(drain());
      } else {
        _emit(_state.copyWith(phase: SyncPhase.offline));
      }
    });
    _timer = Timer.periodic(_interval, (_) => unawaited(drain()));
    unawaited(drain());
  }

  /// Attempts every due outbox entry once. Safe to call concurrently — a second
  /// call while one is in flight returns immediately rather than double-sending.
  Future<void> drain() async {
    if (_running || !canSync) return;
    _running = true;

    try {
      if (!await _connectivity.isOnline) {
        _emit(_state.copyWith(
          phase: SyncPhase.offline,
          pending: _outbox.length,
          parked: _outbox.parked().length,
        ));
        return;
      }

      _emit(_state.copyWith(phase: SyncPhase.syncing));

      final now = DateTime.now();
      final due = _outbox.due(now);
      String? lastError;

      for (final entry in due) {
        try {
          final doc = _firestore!
              .collection('users')
              .doc(_uid)
              .collection(entry.collection)
              .doc(entry.docId);

          switch (entry.op) {
            case OutboxOp.upsert:
              await doc
                  .set(entry.payload, SetOptions(merge: true))
                  .timeout(Env.networkTimeout);
            case OutboxOp.delete:
              await doc.delete().timeout(Env.networkTimeout);
          }
          await _outbox.complete(entry);
        } on Object catch (error) {
          lastError = error.toString();
          await _outbox.recordFailure(entry, lastError, now);
        }
      }

      final parked = _outbox.parked().length;
      _emit(SyncState(
        phase: lastError == null ? SyncPhase.idle : SyncPhase.error,
        pending: _outbox.length,
        parked: parked,
        lastSyncedAt: lastError == null ? DateTime.now() : _state.lastSyncedAt,
        lastError: lastError,
      ));
    } finally {
      _running = false;
    }
  }

  /// Clears backoff on parked entries and retries immediately.
  Future<void> retryParked() async {
    await _outbox.retryParked();
    await drain();
  }

  void _emit(SyncState next) {
    _state = next;
    if (!_controller.isClosed) _controller.add(next);
  }

  Future<void> dispose() async {
    _timer?.cancel();
    await _connectivitySub?.cancel();
    await _controller.close();
  }
}
