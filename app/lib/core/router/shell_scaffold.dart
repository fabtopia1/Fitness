import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:lifedna/core/providers/providers.dart';
import 'package:lifedna/core/router/app_router.dart';
import 'package:lifedna/core/sync/sync_engine.dart';
import 'package:lifedna/core/theme/app_theme.dart';
import 'package:lifedna/core/widgets/ld_async_view.dart';
import 'package:lifedna/features/workout/presentation/workout_providers.dart';

/// The five-destination shell.
///
/// Carries two persistent affordances: the offline/sync banner, and a resume
/// bar when a workout is in progress. Losing a live session is the worst thing
/// that can happen to a training log, so the way back is always one tap away
/// from anywhere in the app.
class ShellScaffold extends ConsumerWidget {
  const ShellScaffold({required this.child, required this.location, super.key});

  final Widget child;
  final String location;

  static const _destinations = <({String path, IconData icon, String label})>[
    (path: Routes.home, icon: Icons.grid_view_rounded, label: 'Home'),
    (path: Routes.nutrition, icon: Icons.restaurant_rounded, label: 'Food'),
    (path: Routes.train, icon: Icons.fitness_center_rounded, label: 'Train'),
    (path: Routes.body, icon: Icons.monitor_weight_rounded, label: 'Body'),
    (path: Routes.me, icon: Icons.person_rounded, label: 'Me'),
  ];

  int get _index {
    final i = _destinations.indexWhere((d) => location.startsWith(d.path));
    return i < 0 ? 0 : i;
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final c = context.ldColors;
    final isOnline = ref.watch(isOnlineProvider).valueOrNull ?? true;
    final sync = ref.watch(syncStateProvider).valueOrNull ?? const SyncState();
    final active = ref.watch(activeSessionProvider).valueOrNull;

    return Scaffold(
      body: Column(
        children: [
          LdOfflineBanner(
            isOnline: isOnline,
            pendingWrites: sync.pending,
            parkedWrites: sync.parked,
            onRetry: () => ref.read(syncEngineProvider).retryParked(),
          ),
          Expanded(child: child),
        ],
      ),
      bottomNavigationBar: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (active != null) _ResumeBar(name: active.name),
          DecoratedBox(
            decoration: BoxDecoration(
              border: Border(top: BorderSide(color: c.border)),
            ),
            child: NavigationBar(
              selectedIndex: _index,
              onDestinationSelected: (i) => context.go(_destinations[i].path),
              destinations: [
                for (final destination in _destinations)
                  NavigationDestination(
                    icon: destination.path == Routes.train && active != null
                        ? _LiveDot(icon: destination.icon, color: c.primary)
                        : Icon(destination.icon),
                    label: destination.label,
                  ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _LiveDot extends StatelessWidget {
  const _LiveDot({required this.icon, required this.color});
  final IconData icon;
  final Color color;

  @override
  Widget build(BuildContext context) => Stack(
    clipBehavior: Clip.none,
    children: [
      Icon(icon),
      Positioned(
        top: -2,
        right: -3,
        child: Container(
          width: 8,
          height: 8,
          decoration: BoxDecoration(color: color, shape: BoxShape.circle),
        ),
      ),
    ],
  );
}

class _ResumeBar extends StatelessWidget {
  const _ResumeBar({required this.name});
  final String name;

  @override
  Widget build(BuildContext context) {
    final c = context.ldColors;
    final type = context.ldType;
    return Material(
      color: c.primaryMuted,
      child: InkWell(
        onTap: () => context.push(Routes.liveWorkout),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
          child: Row(
            children: [
              Icon(Icons.play_circle_fill_rounded, size: 20, color: c.primary),
              const SizedBox(width: 12),
              Expanded(
                child: Text(
                  'Workout in progress · $name',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: type.titleM.copyWith(color: c.textPrimary),
                ),
              ),
              Text('Resume', style: type.titleM.copyWith(color: c.primary)),
            ],
          ),
        ),
      ),
    );
  }
}
