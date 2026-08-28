import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:lifedna/core/providers/providers.dart';
import 'package:lifedna/core/result/result.dart';
import 'package:lifedna/features/settings/data/settings_repository.dart';
import 'package:lifedna/features/supplements/data/supplement_repository.dart';
import 'package:lifedna/core/firebase/telemetry_service.dart';
import 'package:lifedna/core/notifications/notification_service.dart';
import 'package:lifedna/features/calendar/data/calendar_repository.dart';
import 'package:lifedna/features/reminders/data/reminder_repository.dart';
import 'package:lifedna/features/reminders/presentation/reminder_providers.dart';
import 'package:lifedna/features/settings/domain/app_settings.dart';

final settingsRepositoryProvider = Provider<SettingsRepository>((ref) {
  final bootstrap = ref.watch(bootstrapProvider);
  return SettingsRepository(
    store: bootstrap.store,
    outbox: ref.watch(outboxProvider),
    firestore: bootstrap.firestore,
    uid: ref.watch(currentUidProvider),
  );
});

/// The live settings document.
///
/// Seeded with the on-disk value so the very first frame paints in the right
/// theme rather than flashing the default one.
final settingsProvider = StreamProvider<AppSettings>((ref) {
  final repository = ref.watch(settingsRepositoryProvider);
  return repository.watch();
});

/// Settings synchronously, for code that cannot await a stream — the theme at
/// first paint, and the reminder gate inside a repository call.
final currentSettingsProvider = Provider<AppSettings>((ref) {
  return ref.watch(settingsProvider).valueOrNull ??
      ref.watch(settingsRepositoryProvider).read();
});

/// Applies a settings change and the side effects that make it real.
///
/// A preference that is stored but not acted on is the most common way a
/// settings screen lies, so every mutation here carries its consequence with
/// it: consent reaches the Firebase SDKs, and the reminder switch cancels or
/// rebuilds the actual scheduled notifications.
///
/// Every dependency is captured in [build]. Reading a provider *after* an
/// awaited write is what makes a notifier throw when its own write changes a
/// dependency it watches — which is precisely what a settings write does.
class SettingsController extends AsyncNotifier<AppSettings> {
  late SettingsRepository _repository;
  late TelemetryService _telemetry;
  late NotificationService _notifications;
  late SupplementRepository _supplements;
  late CalendarRepository _calendar;
  late ReminderRepository _reminders;

  @override
  Future<AppSettings> build() async {
    _repository = ref.watch(settingsRepositoryProvider);
    _telemetry = ref.watch(telemetryProvider);
    _notifications = ref.watch(notificationServiceProvider);
    _supplements = ref.watch(supplementRepositoryProvider);
    _calendar = ref.watch(calendarRepositoryProvider);
    _reminders = ref.watch(reminderRepositoryProvider);

    final settings = _repository.read();
    await _apply(settings);
    return settings;
  }

  Future<void> setTheme(ThemePreference theme) =>
      _update((s) => s.copyWith(theme: theme));

  Future<void> setAnalyticsConsent(bool granted) =>
      _update((s) => s.copyWith(analyticsConsent: granted));

  Future<void> setCrashReportsConsent(bool granted) =>
      _update((s) => s.copyWith(crashReportsConsent: granted));

  Future<void> setRemindersEnabled(bool enabled) =>
      _update((s) => s.copyWith(remindersEnabled: enabled));

  Future<void> _update(AppSettings Function(AppSettings) change) async {
    final AppSettings previous = state.valueOrNull ?? _repository.read();
    final next = change(previous);
    state = AsyncValue.data(next);

    final result = await _repository.save(next);
    switch (result) {
      case Err(:final failure):
        // The local write failed, so the switch must go back to where it was.
        state = AsyncValue.error(failure, StackTrace.current);
        return;
      case Ok():
        break;
    }

    await _apply(next);
    if (next.remindersEnabled && !previous.remindersEnabled) {
      await _rebuildSchedule();
    }
  }

  /// Pushes the stored choices into the services that enforce them.
  ///
  /// Runs on every launch as well as on every change: the reminder gate and
  /// the SDK consent flags live in memory, so a user who turned something off
  /// would otherwise find it back on after a cold start.
  Future<void> _apply(AppSettings settings) async {
    await _telemetry.applyConsent(
      analyticsConsent: settings.analyticsConsent,
      crashReportsConsent: settings.crashReportsConsent,
    );
    await _notifications.setRemindersEnabled(
      enabled: settings.remindersEnabled,
    );
  }

  /// Re-arms every scheduled reminder from the records that own them.
  Future<void> _rebuildSchedule() async {
    await _supplements.rescheduleAll();
    await _calendar.rescheduleAllReminders();
    await _reminders.rescheduleAll();
  }
}

final settingsControllerProvider =
    AsyncNotifierProvider<SettingsController, AppSettings>(
      SettingsController.new,
    );
