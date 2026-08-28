import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:lifedna/app.dart';
import 'package:lifedna/core/config/app_bootstrap.dart';
import 'package:lifedna/core/providers/providers.dart';
import 'package:lifedna/core/theme/app_theme.dart';

/// Entry point.
///
/// Bootstrap failure is treated as a first-class state rather than a crash:
/// the most likely cause is a device that will not give us a writable
/// application directory, and a user staring at a dead splash screen learns
/// nothing. [_BootstrapFailureApp] says what happened and offers a retry.
Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  unawaited(
    runZonedGuarded(
      () async {
        final AppBootstrap bootstrap;
        try {
          bootstrap = await AppBootstrap.initialize();
        } on Object catch (error, stackTrace) {
          debugPrint('Bootstrap failed — $error');
          debugPrintStack(stackTrace: stackTrace);
          runApp(_BootstrapFailureApp(error: error));
          return;
        }

        // Framework errors are reported through the same path as caught ones, so
        // Crashlytics sees a widget build failure as well as a repository throw.
        final originalOnError = FlutterError.onError;
        FlutterError.onError = (details) {
          originalOnError?.call(details);
          unawaited(
            bootstrap.telemetry.recordError(
              details.exception,
              details.stack,
              context: details.context?.toString(),
              fatal: true,
            ),
          );
        };

        PlatformDispatcher.instance.onError = (error, stackTrace) {
          unawaited(
            bootstrap.telemetry.recordError(
              error,
              stackTrace,
              context: 'platform_dispatcher',
              fatal: true,
            ),
          );
          return true;
        };

        runApp(
          ProviderScope(
            overrides: [bootstrapProvider.overrideWithValue(bootstrap)],
            child: const LifeDnaApp(),
          ),
        );
      },
      (error, stackTrace) {
        // Nothing else can report this: the zone handler is the last resort.
        debugPrint('Uncaught zone error — $error');
        debugPrintStack(stackTrace: stackTrace);
      },
    ),
  );
}

/// Shown when the app cannot start at all.
class _BootstrapFailureApp extends StatelessWidget {
  const _BootstrapFailureApp({required this.error});

  final Object error;

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      theme: AppTheme.dark(),
      home: Scaffold(
        body: SafeArea(
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Icon(Icons.error_outline_rounded, size: 48),
                const SizedBox(height: 16),
                Text(
                  'LifeDNA could not start',
                  style: Theme.of(context).textTheme.headlineMedium,
                ),
                const SizedBox(height: 8),
                Text(
                  'The local database could not be opened on this device. '
                  'Restarting usually fixes it. If it keeps happening, free '
                  'up storage space and try again.',
                  style: Theme.of(context).textTheme.bodyMedium,
                ),
                const SizedBox(height: 24),
                if (kDebugMode)
                  Text('$error', style: Theme.of(context).textTheme.bodySmall),
                const SizedBox(height: 24),
                const FilledButton(onPressed: main, child: Text('Try again')),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
