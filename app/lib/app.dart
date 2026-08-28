import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:lifedna/core/providers/app_providers.dart';
import 'package:lifedna/core/router/app_router.dart';
import 'package:lifedna/core/theme/app_theme.dart';

/// The application root.
class LifeDnaApp extends ConsumerWidget {
  const LifeDnaApp({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return MaterialApp.router(
      title: 'LifeDNA OS',
      debugShowCheckedModeBanner: false,
      routerConfig: ref.watch(routerProvider),
      // Dark is the ground state. Light is complete, but every design decision
      // is made in dark first (docs/04 §1).
      theme: AppTheme.light(),
      darkTheme: AppTheme.dark(),
      themeMode: ThemeMode.dark,
    );
  }
}
