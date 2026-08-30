import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:lifedna/app.dart';
import 'package:lifedna/core/config/app_bootstrap.dart';
import 'package:lifedna/core/firebase/telemetry_service.dart';
import 'package:lifedna/core/providers/providers.dart';
import 'package:lifedna/core/storage/hive_store.dart';
import 'package:lifedna/core/storage/photo_store.dart';
import 'package:lifedna/core/storage/storage_mode.dart';
import 'package:lifedna/core/storage/storage_recovery_screen.dart';
import 'package:lifedna/core/theme/app_theme.dart';

/// Entry point.
///
/// Bootstrap failure is treated as a first-class state rather than a crash:
/// the most likely cause is a device that will not give us a writable
/// application directory, and a user staring at a dead splash screen learns
/// nothing. [_BootstrapFailureApp] says what happened and offers a retry.
Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // Held outside the zone body so the zone's error handler — which runs after
  // the body has returned — can still report through it.
  TelemetryService? telemetry;

  unawaited(
    runZonedGuarded(
      () async {
        final AppBootstrap bootstrap;
        try {
          bootstrap = await AppBootstrap.initialize();
        } on StorageUnavailable catch (failure, stackTrace) {
          // The one failure with a real recovery. Data encrypted with a key
          // this device no longer holds cannot be read by anything, so the app
          // offers to reset rather than looping on a retry that cannot
          // succeed — which is how a device transfer used to brick the install.
          debugPrint('Storage unavailable — $failure');
          debugPrintStack(stackTrace: stackTrace);
          runApp(
            StorageRecoveryApp(
              failure: failure,
              onRetry: main,
              onReset: () async {
                await HiveStore.resetLocalData();
                // Photos live outside Hive, so wiping the boxes alone would
                // leave the previous data's progress photos on disk after a
                // reset whose copy says everything is deleted permanently.
                await PhotoStore.clearAll();
                await main();
              },
            ),
          );
          return;
        } on Object catch (error, stackTrace) {
          // Anything else that stops startup. This screen used to offer only a
          // retry, which made every non-storage bootstrap failure the same
          // permanent lockout C-1 exists to remove — reached through a
          // different door. It now offers the same reset.
          debugPrint('Bootstrap failed — $error');
          debugPrintStack(stackTrace: stackTrace);
          runApp(
            _BootstrapFailureApp(
              error: error,
              onReset: () async {
                await HiveStore.resetLocalData();
                await PhotoStore.clearAll();
                await main();
              },
            ),
          );
          return;
        }

        telemetry = bootstrap.telemetry;

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
        // The last resort, and it used to only print. An uncaught async error
        // that reaches here is by definition one nothing else caught, which
        // makes it the most valuable crash report the app can produce and the
        // one it was silently discarding.
        debugPrint('Uncaught zone error — $error');
        debugPrintStack(stackTrace: stackTrace);
        unawaited(
          telemetry?.recordError(
                error,
                stackTrace,
                context: 'uncaught_zone_error',
                fatal: true,
              ) ??
              Future<void>.value(),
        );
      },
    ),
  );
}

/// Shown when the app cannot start at all.
class _BootstrapFailureApp extends StatelessWidget {
  const _BootstrapFailureApp({required this.error, required this.onReset});

  final Object error;

  /// Clears local data and restarts. Destructive, and behind a confirmation.
  final Future<void> Function() onReset;

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
                const SizedBox(height: 8),
                _ResetButton(onReset: onReset),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// A reset that takes two taps, matching the storage recovery screen.
///
/// One tap must never destroy local data, on either failure screen.
class _ResetButton extends StatefulWidget {
  const _ResetButton({required this.onReset});

  final Future<void> Function() onReset;

  @override
  State<_ResetButton> createState() => _ResetButtonState();
}

class _ResetButtonState extends State<_ResetButton> {
  bool _confirming = false;

  @override
  Widget build(BuildContext context) {
    if (!_confirming) {
      return TextButton(
        onPressed: () => setState(() => _confirming = true),
        child: const Text('Reset this phone’s data'),
      );
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          StorageUnavailable.resetWarningSignedIn,
          style: Theme.of(context).textTheme.bodySmall,
        ),
        const SizedBox(height: 8),
        Row(
          children: [
            FilledButton(
              onPressed: widget.onReset,
              child: const Text('Reset and continue'),
            ),
            const SizedBox(width: 8),
            TextButton(
              onPressed: () => setState(() => _confirming = false),
              child: const Text('Cancel'),
            ),
          ],
        ),
      ],
    );
  }
}
