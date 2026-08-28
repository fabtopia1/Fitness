import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:lifedna/core/providers/providers.dart';
import 'package:lifedna/core/result/result.dart';
import 'package:lifedna/features/settings/data/settings_repository.dart';
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
class SettingsController extends AsyncNotifier<AppSettings> {
  @override
  Future<AppSettings> build() async {
    final settings = ref.watch(currentSettingsProvider);
    await _applyConsent(settings);
    return settings;
  }

  Future<void> _applyConsent(AppSettings settings) => ref
      .read(telemetryProvider)
      .applyConsent(
        analyticsConsent: settings.analyticsConsent,
        crashReportsConsent: settings.crashReportsConsent,
      );

  Future<void> setTheme(ThemePreference theme) =>
      _update((s) => s.copyWith(theme: theme));

  Future<void> setAnalyticsConsent(bool granted) =>
      _update((s) => s.copyWith(analyticsConsent: granted));

  Future<void> setCrashReportsConsent(bool granted) =>
      _update((s) => s.copyWith(crashReportsConsent: granted));

  Future<void> setRemindersEnabled(bool enabled) =>
      _update((s) => s.copyWith(remindersEnabled: enabled));

  Future<void> _update(AppSettings Function(AppSettings) change) async {
    final AppSettings previous =
        state.valueOrNull ?? ref.read(currentSettingsProvider);
    final next = change(previous);
    state = AsyncValue.data(next);

    final result = await ref.read(settingsRepositoryProvider).save(next);
    switch (result) {
      case Err(:final failure):
        // The local write failed, so the switch must go back to where it was.
        state = AsyncValue.error(failure, StackTrace.current);
        return;
      case Ok():
        break;
    }

    await _applyConsent(next);
    if (next.remindersEnabled != previous.remindersEnabled) {
      await _applyReminderSwitch(enabled: next.remindersEnabled);
    }
  }

  /// Turning reminders off cancels what is already in the OS scheduler;
  /// turning them back on rebuilds the schedule from the saved records.
  Future<void> _applyReminderSwitch({required bool enabled}) async {
    final notifications = ref.read(notificationServiceProvider);
    if (!enabled) {
      await notifications.cancelAll();
      return;
    }
    await ref.read(supplementRepositoryProvider).rescheduleAll();
    await ref.read(calendarRepositoryProvider).rescheduleAllReminders();
  }
}

final settingsControllerProvider =
    AsyncNotifierProvider<SettingsController, AppSettings>(
  SettingsController.new,
);
