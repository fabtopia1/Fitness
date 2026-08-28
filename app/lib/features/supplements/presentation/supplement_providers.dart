import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:lifedna/core/providers/providers.dart';
import 'package:lifedna/features/supplements/domain/supplement_entities.dart';
import 'package:lifedna/features/workout/presentation/workout_providers.dart';

final supplementsProvider = StreamProvider<List<Supplement>>(
  (ref) => ref.watch(supplementRepositoryProvider).watchSupplements(),
);

final supplementLogsProvider = StreamProvider<List<SupplementLog>>(
  (ref) => ref.watch(supplementRepositoryProvider).watchLogs(),
);

/// Today's schedule with taken state.
final todaySupplementsProvider =
    Provider<List<({Supplement supplement, bool taken})>>((ref) {
      ref
        ..watch(supplementsProvider)
        ..watch(supplementLogsProvider);
      return ref
          .watch(supplementRepositoryProvider)
          .scheduleFor(
            ref.watch(todayProvider),
            isTrainingDay: ref.watch(trainedTodayProvider),
          );
    });

final supplementComplianceProvider = Provider<SupplementCompliance>((ref) {
  ref
    ..watch(supplementsProvider)
    ..watch(supplementLogsProvider);
  return ref.watch(supplementRepositoryProvider).compliance();
});
