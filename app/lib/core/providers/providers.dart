import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:lifedna/core/config/app_bootstrap.dart';
import 'package:lifedna/core/data/synced_entity.dart';
import 'package:lifedna/core/firebase/firebase_service.dart';
import 'package:lifedna/core/firebase/telemetry_service.dart';
import 'package:lifedna/core/network/connectivity_service.dart';
import 'package:lifedna/core/notifications/notification_service.dart';
import 'package:lifedna/core/storage/hive_store.dart';
import 'package:lifedna/core/sync/outbox.dart';
import 'package:lifedna/core/sync/sync_engine.dart';
import 'package:lifedna/features/auth/data/auth_repository.dart';
import 'package:lifedna/features/auth/data/profile_repository.dart';
import 'package:lifedna/features/auth/domain/user_profile.dart';
import 'package:lifedna/features/body/data/body_repository.dart';
import 'package:lifedna/features/calendar/data/calendar_repository.dart';
import 'package:lifedna/features/calendar/data/google_calendar_service.dart';
import 'package:lifedna/features/health_sync/data/health_sync_service.dart';
import 'package:lifedna/features/nutrition/data/nutrition_repository.dart';
import 'package:lifedna/features/supplements/data/supplement_repository.dart';
import 'package:lifedna/features/workout/data/workout_repository.dart';

/// Injected in `main` via a ProviderScope override. Reading it before that
/// override exists is a programming error, so it throws rather than returning
/// a half-built object.
final bootstrapProvider = Provider<AppBootstrap>(
  (ref) => throw UnimplementedError(
    'bootstrapProvider must be overridden in main() with AppBootstrap.initialize()',
  ),
);

// ------------------------------------------------------------------ services --

final hiveStoreProvider =
    Provider<HiveStore>((ref) => ref.watch(bootstrapProvider).store);

final firebaseServiceProvider =
    Provider<FirebaseService>((ref) => ref.watch(bootstrapProvider).firebase);

final telemetryProvider =
    Provider<TelemetryService>((ref) => ref.watch(bootstrapProvider).telemetry);

final notificationServiceProvider = Provider<NotificationService>(
  (ref) => ref.watch(bootstrapProvider).notifications,
);

final connectivityProvider = Provider<ConnectivityService>(
  (ref) => ref.watch(bootstrapProvider).connectivity,
);

final isOnlineProvider = StreamProvider<bool>((ref) {
  final connectivity = ref.watch(connectivityProvider);
  return connectivity.onStatusChange;
});

final outboxProvider =
    Provider<Outbox>((ref) => Outbox(ref.watch(hiveStoreProvider)));

/// "Now", overridable in tests so time-dependent behaviour is deterministic.
final clockProvider = Provider<DateTime Function()>((ref) => DateTime.now);

final todayProvider = Provider<DateTime>((ref) {
  final now = ref.watch(clockProvider)();
  return DateTime(now.year, now.month, now.day);
});

final todayLocalDateProvider =
    Provider<String>((ref) => Json.localDate(ref.watch(todayProvider)));

// ---------------------------------------------------------------------- auth --

final authRepositoryProvider = Provider<AuthRepository>((ref) {
  final bootstrap = ref.watch(bootstrapProvider);
  return AuthRepository(
    store: bootstrap.store,
    firebaseAuth: bootstrap.auth,
    googleSignIn: bootstrap.googleSignIn,
  );
});

final authSessionProvider = StreamProvider<AuthSession?>((ref) {
  return ref.watch(authRepositoryProvider).authStateChanges();
});

/// The signed-in uid, or null. Every user-scoped repository depends on this,
/// so a sign-out tears down and rebuilds the whole data layer automatically.
final currentUidProvider = Provider<String?>((ref) {
  return ref.watch(authSessionProvider).valueOrNull?.uid;
});

final profileRepositoryProvider = Provider<ProfileRepository>((ref) {
  final bootstrap = ref.watch(bootstrapProvider);
  return ProfileRepository(
    store: bootstrap.store,
    outbox: ref.watch(outboxProvider),
    firestore: bootstrap.firestore,
    uid: ref.watch(currentUidProvider),
  );
});

final profileProvider = StreamProvider<UserProfile?>((ref) {
  return ref.watch(profileRepositoryProvider).watch();
});

// ------------------------------------------------------------------- sync ----

final syncEngineProvider = Provider<SyncEngine>((ref) {
  final bootstrap = ref.watch(bootstrapProvider);
  final engine = SyncEngine(
    outbox: ref.watch(outboxProvider),
    connectivity: bootstrap.connectivity,
    firestore: bootstrap.firestore,
    uid: ref.watch(currentUidProvider),
  );
  engine.start();
  ref.onDispose(() => unawaited(engine.dispose()));
  return engine;
});

final syncStateProvider = StreamProvider<SyncState>((ref) {
  final engine = ref.watch(syncEngineProvider);
  return engine.stream;
});

// ----------------------------------------------------------- repositories ----

final nutritionRepositoryProvider = Provider<NutritionRepository>((ref) {
  final bootstrap = ref.watch(bootstrapProvider);
  return NutritionRepository(
    store: bootstrap.store,
    outbox: ref.watch(outboxProvider),
    firestore: bootstrap.firestore,
    uid: ref.watch(currentUidProvider),
    clock: ref.watch(clockProvider),
  );
});

final supplementRepositoryProvider = Provider<SupplementRepository>((ref) {
  final bootstrap = ref.watch(bootstrapProvider);
  return SupplementRepository(
    store: bootstrap.store,
    outbox: ref.watch(outboxProvider),
    notifications: bootstrap.notifications,
    firestore: bootstrap.firestore,
    uid: ref.watch(currentUidProvider),
    clock: ref.watch(clockProvider),
  );
});

final workoutRepositoryProvider = Provider<WorkoutRepository>((ref) {
  final bootstrap = ref.watch(bootstrapProvider);
  return WorkoutRepository(
    store: bootstrap.store,
    outbox: ref.watch(outboxProvider),
    firestore: bootstrap.firestore,
    uid: ref.watch(currentUidProvider),
    clock: ref.watch(clockProvider),
  );
});

final bodyRepositoryProvider = Provider<BodyRepository>((ref) {
  final bootstrap = ref.watch(bootstrapProvider);
  return BodyRepository(
    store: bootstrap.store,
    outbox: ref.watch(outboxProvider),
    firestore: bootstrap.firestore,
    uid: ref.watch(currentUidProvider),
    clock: ref.watch(clockProvider),
  );
});

final googleCalendarServiceProvider =
    Provider<GoogleCalendarService>((ref) => GoogleCalendarService());

final calendarRepositoryProvider = Provider<CalendarRepository>((ref) {
  final bootstrap = ref.watch(bootstrapProvider);
  return CalendarRepository(
    store: bootstrap.store,
    outbox: ref.watch(outboxProvider),
    notifications: bootstrap.notifications,
    google: ref.watch(googleCalendarServiceProvider),
    firestore: bootstrap.firestore,
    uid: ref.watch(currentUidProvider),
    clock: ref.watch(clockProvider),
  );
});

final healthSyncServiceProvider =
    Provider<HealthSyncService>((ref) => HealthSyncService());
