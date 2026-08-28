import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:lifedna/core/providers/providers.dart';
import 'package:lifedna/features/reminders/presentation/reminder_providers.dart';
import 'package:lifedna/features/settings/presentation/settings_providers.dart';

/// Pulls every collection the user owns.
///
/// A composition root for replication, in the same way the dashboard is one
/// for display: it is the single place that knows the full list of things a
/// device has to download. A repository added without a line here would push
/// its data up and never pull it back — which looks to the user like data that
/// vanished when they changed phones.
class RemotePull {
  RemotePull(this._ref);

  final Ref _ref;

  /// True when there is a cloud to pull from at all.
  bool get canPull =>
      _ref.read(firebaseServiceProvider).isAvailable &&
      _ref.read(currentUidProvider) != null;

  /// Pulls everything, in parallel, and reports how many records were applied.
  ///
  /// Never throws and never blocks anything: local data is already correct, so
  /// a failed pull is a missed opportunity rather than an error the user has
  /// to act on.
  Future<int> everything() async {
    if (!canPull) return 0;

    final results = await Future.wait([
      _ref.read(nutritionRepositoryProvider).pullAll(),
      _ref.read(workoutRepositoryProvider).pullAll(),
      _ref.read(supplementRepositoryProvider).pullAll(),
      _ref.read(bodyRepositoryProvider).pullAll(),
      _ref.read(calendarRepositoryProvider).pullAll(),
      _ref.read(reminderRepositoryProvider).pullAll(),
      _ref.read(settingsRepositoryProvider).pullAll(),
      _ref
          .read(profileRepositoryProvider)
          .pull()
          .then((result) => result.map((profile) => profile == null ? 0 : 1)),
    ]);

    var applied = 0;
    for (final result in results) {
      applied += result.valueOrNull ?? 0;
    }
    return applied;
  }

  /// Drains anything queued, then pulls. The order matters: pushing first
  /// means a local edit made offline wins over an older remote copy instead of
  /// being overwritten by it.
  Future<int> refresh() async {
    await _ref.read(syncEngineProvider).drain();
    return everything();
  }
}

final remotePullProvider = Provider<RemotePull>(RemotePull.new);
