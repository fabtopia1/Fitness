import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:lifedna/core/providers/providers.dart';
import 'package:lifedna/core/router/shell_scaffold.dart';
import 'package:lifedna/features/ai_hub/presentation/ai_hub_screen.dart';
import 'package:lifedna/features/auth/presentation/onboarding_screen.dart';
import 'package:lifedna/features/auth/presentation/sign_in_screen.dart';
import 'package:lifedna/features/auth/presentation/sign_up_screen.dart';
import 'package:lifedna/features/auth/presentation/welcome_screen.dart';
import 'package:lifedna/features/body/presentation/body_screen.dart';
import 'package:lifedna/features/calendar/presentation/plan_screen.dart';
import 'package:lifedna/features/dashboard/presentation/dashboard_screen.dart';
import 'package:lifedna/features/health_sync/presentation/health_sync_screen.dart';
import 'package:lifedna/features/nutrition/presentation/add_food_screen.dart';
import 'package:lifedna/features/nutrition/presentation/nutrition_screen.dart';
import 'package:lifedna/features/settings/presentation/settings_screen.dart';
import 'package:lifedna/features/supplements/presentation/supplements_screen.dart';
import 'package:lifedna/features/workout/presentation/exercise_library_screen.dart';
import 'package:lifedna/features/workout/presentation/live_workout_screen.dart';
import 'package:lifedna/features/workout/presentation/workout_editor_screen.dart';
import 'package:lifedna/features/workout/presentation/workout_screen.dart';

abstract final class Routes {
  static const splash = '/';
  static const welcome = '/welcome';
  static const signIn = '/sign-in';
  static const signUp = '/sign-up';
  static const onboarding = '/onboarding';

  static const home = '/home';
  static const nutrition = '/nutrition';
  static const train = '/train';
  static const body = '/body';
  static const me = '/me';

  static const addFood = '/nutrition/add';
  static const supplements = '/supplements';
  static const liveWorkout = '/train/live';
  static const workoutEditor = '/train/editor';
  static const exerciseLibrary = '/train/exercises';
  static const plan = '/plan';
  static const aiHub = '/ai';
  static const healthSync = '/health';
  static const settings = '/settings';
}

final _rootKey = GlobalKey<NavigatorState>();
final _shellKey = GlobalKey<NavigatorState>();

/// Bridges a Riverpod stream to GoRouter's [Listenable] refresh mechanism, so
/// signing in or out re-evaluates the redirect immediately rather than on the
/// next navigation.
class _RouterRefresh extends ChangeNotifier {
  _RouterRefresh(Ref ref) {
    _sub = ref.listen(
      authSessionProvider,
      (_, __) => notifyListeners(),
      fireImmediately: false,
    );
    _profileSub = ref.listen(
      profileProvider,
      (_, __) => notifyListeners(),
      fireImmediately: false,
    );
  }

  late final ProviderSubscription<dynamic> _sub;
  late final ProviderSubscription<dynamic> _profileSub;

  @override
  void dispose() {
    _sub.close();
    _profileSub.close();
    super.dispose();
  }
}

final routerProvider = Provider<GoRouter>((ref) {
  final refresh = _RouterRefresh(ref);
  ref.onDispose(refresh.dispose);

  return GoRouter(
    navigatorKey: _rootKey,
    initialLocation: Routes.splash,
    refreshListenable: refresh,
    redirect: (context, state) {
      final session = ref.read(authSessionProvider);
      final location = state.matchedLocation;

      // Auth state is still resolving: hold on the splash screen rather than
      // flashing the sign-in page at a user who is already signed in.
      if (session.isLoading) {
        return location == Routes.splash ? null : Routes.splash;
      }

      final signedIn = session.valueOrNull != null;
      final onAuthRoute = location == Routes.welcome ||
          location == Routes.signIn ||
          location == Routes.signUp ||
          location == Routes.splash;

      if (!signedIn) {
        return onAuthRoute && location != Routes.splash
            ? null
            : Routes.welcome;
      }

      final profile = ref.read(profileProvider).valueOrNull;
      final needsOnboarding = profile == null || !profile.isOnboarded;

      if (needsOnboarding) {
        return location == Routes.onboarding ? null : Routes.onboarding;
      }
      if (onAuthRoute || location == Routes.onboarding) return Routes.home;
      return null;
    },
    routes: [
      GoRoute(path: Routes.splash, builder: (_, __) => const _SplashScreen()),
      GoRoute(path: Routes.welcome, builder: (_, __) => const WelcomeScreen()),
      GoRoute(path: Routes.signIn, builder: (_, __) => const SignInScreen()),
      GoRoute(path: Routes.signUp, builder: (_, __) => const SignUpScreen()),
      GoRoute(
        path: Routes.onboarding,
        builder: (_, __) => const OnboardingScreen(),
      ),

      ShellRoute(
        navigatorKey: _shellKey,
        builder: (context, state, child) =>
            ShellScaffold(location: state.matchedLocation, child: child),
        routes: [
          GoRoute(path: Routes.home, builder: (_, __) => const DashboardScreen()),
          GoRoute(
            path: Routes.nutrition,
            builder: (_, __) => const NutritionScreen(),
          ),
          GoRoute(path: Routes.train, builder: (_, __) => const WorkoutScreen()),
          GoRoute(path: Routes.body, builder: (_, __) => const BodyScreen()),
          GoRoute(path: Routes.me, builder: (_, __) => const SettingsScreen()),
        ],
      ),

      // Full-screen routes: focused tasks where a bottom bar is an invitation
      // to abandon what you started.
      GoRoute(
        path: Routes.addFood,
        builder: (_, state) =>
            AddFoodScreen(slotWire: state.uri.queryParameters['slot']),
      ),
      GoRoute(
        path: Routes.supplements,
        builder: (_, __) => const SupplementsScreen(),
      ),
      GoRoute(
        path: Routes.liveWorkout,
        builder: (_, __) => const LiveWorkoutScreen(),
      ),
      GoRoute(
        path: Routes.workoutEditor,
        builder: (_, state) =>
            WorkoutEditorScreen(workoutId: state.uri.queryParameters['id']),
      ),
      GoRoute(
        path: Routes.exerciseLibrary,
        builder: (_, __) => const ExerciseLibraryScreen(),
      ),
      GoRoute(path: Routes.plan, builder: (_, __) => const PlanScreen()),
      GoRoute(path: Routes.aiHub, builder: (_, __) => const AiHubScreen()),
      GoRoute(
        path: Routes.healthSync,
        builder: (_, __) => const HealthSyncScreen(),
      ),
      GoRoute(
        path: Routes.settings,
        builder: (_, __) => const SettingsScreen(),
      ),
    ],
    errorBuilder: (context, state) => _RouteErrorScreen(
      location: state.matchedLocation,
    ),
  );
});

class _SplashScreen extends StatelessWidget {
  const _SplashScreen();

  @override
  Widget build(BuildContext context) =>
      const Scaffold(body: Center(child: CircularProgressIndicator()));
}

class _RouteErrorScreen extends StatelessWidget {
  const _RouteErrorScreen({required this.location});
  final String location;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Not found')),
      body: Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(Icons.explore_off_rounded, size: 48),
              const SizedBox(height: 16),
              Text('No screen at $location'),
              const SizedBox(height: 16),
              FilledButton(
                onPressed: () => context.go(Routes.home),
                child: const Text('Go home'),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
