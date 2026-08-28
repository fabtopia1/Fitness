import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:lifedna/core/providers/app_providers.dart';
import 'package:lifedna/core/router/app_router.dart';
import 'package:lifedna/core/theme/app_theme.dart';
import 'package:lifedna/core/theme/ld_spacing.dart';
import 'package:lifedna/shared/enums/enums.dart';

/// The five-destination shell.
///
/// The Train tab carries a live indicator while a session is in progress, and
/// a resume banner appears on every route — losing a workout in progress is
/// the worst thing that can happen to a training log, so the way back is
/// always one tap away (docs/02 §8).
class ShellScaffold extends ConsumerWidget {
  const ShellScaffold({required this.child, required this.location, super.key});

  final Widget child;
  final String location;

  static const _destinations = <({String path, IconData icon, String label})>[
    (path: Routes.home, icon: Icons.grid_view_rounded, label: 'Home'),
    (path: Routes.nutrition, icon: Icons.restaurant_rounded, label: 'Nutrition'),
    (path: Routes.train, icon: Icons.fitness_center_rounded, label: 'Train'),
    (path: Routes.plan, icon: Icons.calendar_month_rounded, label: 'Plan'),
    (path: Routes.me, icon: Icons.person_rounded, label: 'Me'),
  ];

  int get _index {
    final i = _destinations.indexWhere((d) => location.startsWith(d.path));
    return i < 0 ? 0 : i;
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final c = context.ldColors;
    final session = ref.watch(activeSessionProvider).valueOrNull;
    final isLive = session?.status == SessionStatus.inProgress;

    return Scaffold(
      body: child,
      bottomNavigationBar: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (isLive) _ResumeBanner(elapsed: session!.duration),
          DecoratedBox(
            decoration: BoxDecoration(
              border: Border(top: BorderSide(color: c.border)),
            ),
            child: NavigationBar(
              selectedIndex: _index,
              onDestinationSelected: (i) =>
                  context.go(_destinations[i].path),
              destinations: [
                for (var i = 0; i < _destinations.length; i++)
                  NavigationDestination(
                    icon: _destinations[i].path == Routes.train && isLive
                        ? _LiveIcon(icon: _destinations[i].icon, color: c.primary)
                        : Icon(_destinations[i].icon),
                    label: _destinations[i].label,
                  ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _LiveIcon extends StatelessWidget {
  const _LiveIcon({required this.icon, required this.color});
  final IconData icon;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Stack(
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
}

class _ResumeBanner extends StatelessWidget {
  const _ResumeBanner({required this.elapsed});
  final Duration elapsed;

  @override
  Widget build(BuildContext context) {
    final c = context.ldColors;
    final type = context.ldType;
    final mm = elapsed.inMinutes.remainder(60).toString().padLeft(2, '0');
    final ss = elapsed.inSeconds.remainder(60).toString().padLeft(2, '0');

    return Material(
      color: c.primaryMuted,
      child: InkWell(
        onTap: () => context.push(Routes.liveGym),
        child: Padding(
          padding: const EdgeInsets.symmetric(
            horizontal: LdSpacing.s4,
            vertical: LdSpacing.s3,
          ),
          child: Row(
            children: [
              Icon(Icons.play_circle_fill_rounded, size: 20, color: c.primary),
              const SizedBox(width: LdSpacing.s3),
              Expanded(
                child: Text(
                  'Workout in progress · ${elapsed.inHours > 0 ? '${elapsed.inHours}:' : ''}$mm:$ss',
                  style: type.titleM.copyWith(color: c.textPrimary),
                ),
              ),
              Text('Resume', style: type.titleM.copyWith(color: c.primary)),
              Icon(Icons.chevron_right_rounded, size: 20, color: c.primary),
            ],
          ),
        ),
      ),
    );
  }
}
