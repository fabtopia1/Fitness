import 'package:flutter_test/flutter_test.dart';
import 'package:lifedna/core/providers/providers.dart';
import 'package:lifedna/core/sync/outbox.dart';
import 'package:lifedna/features/settings/data/settings_repository.dart';
import 'package:lifedna/features/settings/domain/app_settings.dart';
import 'package:lifedna/features/settings/presentation/settings_providers.dart';
import 'package:lifedna/features/supplements/domain/supplement_entities.dart';

import '../../../support/test_harness.dart';

void main() {
  late TestEnvironment env;

  setUp(() async => env = await TestEnvironment.create());
  tearDown(() async => env.dispose());

  group('AppSettings', () {
    test('the defaults are the privacy-respecting ones', () {
      final settings = AppSettings.defaults();
      expect(settings.theme, ThemePreference.dark);
      expect(settings.remindersEnabled, isTrue);
      // Analytics is opt-IN: a user who never opens this screen is not
      // measured. Crash reports are opt-OUT because they carry no health data
      // and are what makes a beta build fixable.
      expect(settings.analyticsConsent, isFalse);
      expect(settings.crashReportsConsent, isTrue);
    });

    test('survives a JSON round-trip', () {
      final settings = AppSettings.defaults().copyWith(
        theme: ThemePreference.light,
        remindersEnabled: false,
        analyticsConsent: true,
      );
      final restored = AppSettings.fromJson(settings.toJson());

      expect(restored.theme, ThemePreference.light);
      expect(restored.remindersEnabled, isFalse);
      expect(restored.analyticsConsent, isTrue);
      expect(restored.id, AppSettings.docId);
    });

    test('an unknown stored theme falls back to dark', () {
      expect(ThemePreference.fromWire('chartreuse'), ThemePreference.dark);
    });
  });

  group('SettingsRepository', () {
    test('a user who has never changed anything reads the defaults', () {
      final repository = SettingsRepository(
        store: env.store,
        outbox: Outbox(env.store),
      );
      // A missing document is not an error state.
      expect(repository.read().theme, ThemePreference.dark);
    });

    test('a saved change is read back and queued for replication', () async {
      final outbox = Outbox(env.store);
      final repository =
          SettingsRepository(store: env.store, outbox: outbox);

      await repository.save(
        repository.read().copyWith(theme: ThemePreference.light),
      );

      expect(repository.read().theme, ThemePreference.light);
      expect(outbox.pending().single.collection, 'settings');
      expect(outbox.pending().single.docId, AppSettings.docId);
    });
  });

  group('SettingsController', () {
    test('a preference change is stored', () async {
      final container = env.container();
      addTearDown(container.dispose);

      await container.read(settingsControllerProvider.future);
      await container
          .read(settingsControllerProvider.notifier)
          .setTheme(ThemePreference.light);

      expect(
        container.read(settingsRepositoryProvider).read().theme,
        ThemePreference.light,
      );
    });

    test('turning reminders off cancels the OS schedule as well', () async {
      // A preference that is stored but not acted on is the most common way a
      // settings screen lies.
      final container = env.container();
      addTearDown(container.dispose);

      final supplements = container.read(supplementRepositoryProvider);
      await supplements.save(
        supplements.create(name: 'Creatine', dose: 5, unit: 'g'),
      );
      expect(env.notifications.scheduledDaily, hasLength(1));

      await container.read(settingsControllerProvider.future);
      await container
          .read(settingsControllerProvider.notifier)
          .setRemindersEnabled(false);

      expect(env.notifications.scheduledDaily, isEmpty);
      expect(env.notifications.remindersEnabled, isFalse);
    });

    test('turning reminders back on rebuilds the schedule from the records',
        () async {
      final container = env.container();
      addTearDown(container.dispose);

      final supplements = container.read(supplementRepositoryProvider);
      await supplements.save(
        supplements.create(
          name: 'Creatine',
          dose: 5,
          unit: 'g',
          frequency: SupplementFrequency.daily,
        ),
      );

      await container.read(settingsControllerProvider.future);
      final controller = container.read(settingsControllerProvider.notifier);
      await controller.setRemindersEnabled(false);
      await controller.setRemindersEnabled(true);

      expect(env.notifications.scheduledDaily, hasLength(1));
      expect(env.notifications.remindersEnabled, isTrue);
    });

    test('the stored reminder switch is restored on a cold start', () async {
      // The gate lives in memory, so a user who turned reminders off must not
      // be notified again after the next launch.
      final first = env.container();
      await first.read(settingsControllerProvider.future);
      await first
          .read(settingsControllerProvider.notifier)
          .setRemindersEnabled(false);
      first.dispose();

      final second = env.container();
      addTearDown(second.dispose);
      await second.read(settingsControllerProvider.future);

      expect(env.notifications.remindersEnabled, isFalse);
    });

    test('consent changes are applied, not just recorded', () async {
      final container = env.container();
      addTearDown(container.dispose);

      await container.read(settingsControllerProvider.future);
      await container
          .read(settingsControllerProvider.notifier)
          .setAnalyticsConsent(true);

      final settings = container.read(settingsRepositoryProvider).read();
      expect(settings.analyticsConsent, isTrue);
      // In this build there is no Firebase project behind it, so consent alone
      // never turns collection on.
      expect(container.read(telemetryProvider).enabled, isFalse);
    });
  });
}
