import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:lifedna/core/router/shell_scaffold.dart';
import 'package:lifedna/features/dashboard/presentation/dashboard_screen.dart';
import 'package:lifedna/features/live_gym/presentation/live_gym_screen.dart';
import 'package:lifedna/features/nutrition/presentation/add_food_screen.dart';
import 'package:lifedna/features/nutrition/presentation/nutrition_screen.dart';
import 'package:lifedna/features/workout/presentation/train_screen.dart';

/// Route names, referenced rather than typed as string literals at call sites.
abstract final class Routes {
  static const home = '/home';
  static const nutrition = '/nutrition';
  static const addFood = '/nutrition/log';
  static const train = '/train';
  static const plan = '/plan';
  static const me = '/me';
  static const liveGym = '/live';
}

final _shellKey = GlobalKey<NavigatorState>();

/// The application router.
///
/// Live Gym Mode sits deliberately OUTSIDE the shell: it has no bottom
/// navigation, holds the screen awake, and owns the whole viewport
/// (docs/06 Screen 06).
final routerProvider = Provider<GoRouter>((ref) {
  return GoRouter(
    initialLocation: Routes.home,
    routes: [
      ShellRoute(
        navigatorKey: _shellKey,
        builder: (context, state, child) =>
            ShellScaffold(location: state.uri.path, child: child),
        routes: [
          GoRoute(
            path: Routes.home,
            builder: (_, __) => const DashboardScreen(),
          ),
          GoRoute(
            path: Routes.nutrition,
            builder: (_, __) => const NutritionScreen(),
          ),
          GoRoute(
            path: Routes.train,
            builder: (_, __) => const TrainScreen(),
          ),
          GoRoute(
            path: Routes.plan,
            builder: (_, __) => const _PlaceholderScreen(
              title: 'Plan',
              icon: Icons.calendar_month_rounded,
              body: 'Calendar and tasks land in Sprint 7. The engines and the '
                  'schema they depend on are already specified in docs/03 and '
                  'docs/09.',
            ),
          ),
          GoRoute(
            path: Routes.me,
            builder: (_, __) => const _PlaceholderScreen(
              title: 'Me',
              icon: Icons.person_rounded,
              body: 'Body, recovery detail, supplements, analytics and '
                  'settings. Recovery is computed today — see the dashboard '
                  'card — and its detail screen lands in Sprint 14.',
            ),
          ),
        ],
      ),
      // Full-screen and outside the shell: logging a meal is a focused task,
      // and the bottom bar is an invitation to abandon it.
      GoRoute(
        path: '${Routes.addFood}/:slot',
        builder: (_, state) => AddFoodScreen(
          slotWire: state.pathParameters['slot'] ?? 'snack',
        ),
      ),
      GoRoute(
        path: Routes.liveGym,
        builder: (_, __) => const LiveGymScreen(),
      ),
    ],
  );
});

class _PlaceholderScreen extends StatelessWidget {
  const _PlaceholderScreen({
    required this.title,
    required this.icon,
    required this.body,
  });

  final String title;
  final IconData icon;
  final String body;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text(title)),
      body: Center(
        child: Padding(
          padding: const EdgeInsets.all(32),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(icon, size: 48, color: Theme.of(context).hintColor),
              const SizedBox(height: 16),
              Text(
                body,
                textAlign: TextAlign.center,
                style: Theme.of(context).textTheme.bodyMedium,
              ),
            ],
          ),
        ),
      ),
    );
  }
}
