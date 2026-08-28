import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:lifedna/core/config/env.dart';
import 'package:lifedna/core/providers/providers.dart';
import 'package:lifedna/core/router/app_router.dart';
import 'package:lifedna/core/theme/app_theme.dart';
import 'package:lifedna/features/settings/domain/app_settings.dart';
import 'package:lifedna/features/settings/presentation/settings_providers.dart';

/// The application widget.
///
/// Watches three things that must stay alive for the whole session rather than
/// only while a particular screen is mounted: the sync engine, the settings
/// controller (which applies privacy consent to the Firebase SDKs), and the
/// telemetry user binding.
class LifeDnaApp extends ConsumerWidget {
  const LifeDnaApp({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    // Keeps the outbox draining for as long as the app is running. Without a
    // watch here it would only exist while the shell is on screen.
    ref.watch(syncEngineProvider);

    // Instantiates the controller so stored consent reaches the SDKs at
    // startup, not on first visit to the settings screen.
    ref.watch(settingsControllerProvider);

    ref.listen(currentUidProvider, (_, uid) {
      ref.read(telemetryProvider).setUser(uid);
    });

    final router = ref.watch(routerProvider);
    final theme = ref.watch(currentSettingsProvider).theme;

    return MaterialApp.router(
      title: Env.flavor.appName,
      debugShowCheckedModeBanner: false,
      routerConfig: router,
      theme: AppTheme.light(),
      darkTheme: AppTheme.dark(),
      themeMode: switch (theme) {
        ThemePreference.dark => ThemeMode.dark,
        ThemePreference.light => ThemeMode.light,
        ThemePreference.system => ThemeMode.system,
      },
      localizationsDelegates: const [
        GlobalMaterialLocalizations.delegate,
        GlobalWidgetsLocalizations.delegate,
        GlobalCupertinoLocalizations.delegate,
      ],
      supportedLocales: const [Locale('en')],
      builder: (context, child) {
        // Caps text scaling: the Live Gym layout has fixed-height controls, and
        // beyond this the numbers stop fitting inside them.
        final scale = MediaQuery.textScalerOf(context)
            .clamp(minScaleFactor: 0.85, maxScaleFactor: 1.6);
        return MediaQuery(
          data: MediaQuery.of(context).copyWith(textScaler: scale),
          child: child ?? const SizedBox.shrink(),
        );
      },
    );
  }
}
