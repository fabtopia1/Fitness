import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:lifedna/app.dart';
import 'package:lifedna/core/theme/app_theme.dart';

import 'test_harness.dart';


/// Unmounts the tree at the end of the test.
///
/// Provider subscriptions to Hive boxes must be cancelled BEFORE the boxes are
/// closed: `Hive.close()` does not complete while a watcher is still attached,
/// which shows up as a test that hangs in teardown rather than as a failure.
/// `addTearDown` runs before the enclosing `tearDown`, so this ordering holds
/// without every test having to remember it.
void _unmountBeforeTeardown(WidgetTester tester) {
  addTearDown(() async {
    // Riverpod schedules provider refreshes on a zero-duration timer. A write
    // made by the last action of a test leaves one pending, which the test
    // framework reports as "a Timer is still pending" — so drain them first.
    for (var i = 0; i < 3; i++) {
      await tester.pump(Duration.zero);
    }
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump();
  });
}

/// Pumps a single screen inside the real theme and a router that can be
/// navigated away from.
///
/// The stub destinations exist so a tap that pushes a route resolves to
/// something instead of throwing — the test can then assert on where the user
/// ended up rather than on the absence of a crash.
Future<void> pumpScreen(
  WidgetTester tester,
  TestEnvironment env,
  Widget screen, {
  List<Override> overrides = const [],
  Size surface = const Size(400, 900),
}) async {
  await tester.binding.setSurfaceSize(surface);
  addTearDown(() => tester.binding.setSurfaceSize(null));
  _unmountBeforeTeardown(tester);

  final router = GoRouter(
    initialLocation: '/',
    routes: [
      GoRoute(path: '/', builder: (_, __) => screen),
      GoRoute(
        path: '/:rest(.*)',
        builder: (context, state) => Scaffold(
          body: Center(child: Text('route:${state.matchedLocation}')),
        ),
      ),
    ],
  );
  addTearDown(router.dispose);

  await tester.pumpWidget(
    ProviderScope(
      overrides: [...env.overrides, ...overrides],
      child: MaterialApp.router(
        routerConfig: router,
        theme: AppTheme.dark(),
        debugShowCheckedModeBanner: false,
      ),
    ),
  );
  await tester.pump();
}

/// Pumps the whole application, including its real router and redirects.
Future<void> pumpApp(
  WidgetTester tester,
  TestEnvironment env, {
  List<Override> overrides = const [],
  Size surface = const Size(400, 900),
}) async {
  await tester.binding.setSurfaceSize(surface);
  addTearDown(() => tester.binding.setSurfaceSize(null));
  _unmountBeforeTeardown(tester);

  await tester.pumpWidget(
    ProviderScope(
      overrides: [...env.overrides, ...overrides],
      child: const LifeDnaApp(),
    ),
  );
  await tester.pump();
}

/// Settles without failing on a screen that animates forever.
///
/// A progress ring or a live timer never reaches a quiet frame, so
/// `pumpAndSettle` would time out on exactly the screens most worth testing.
Future<void> pumpFrames(
  WidgetTester tester, {
  int frames = 6,
  Duration step = const Duration(milliseconds: 120),
}) async {
  for (var i = 0; i < frames; i++) {
    await tester.pump(step);
  }
}

/// Where the stub router says we ended up, or null if we never left.
String? currentStubRoute() {
  final finder = find.textContaining('route:');
  if (finder.evaluate().isEmpty) return null;
  return (finder.evaluate().first.widget as Text).data!.substring(6);
}

/// Opens [sheet] as a modal bottom sheet on a host screen.
///
/// Editors are written to pop themselves on save, so they need a route to pop
/// back to. Pumping one as the root screen would make a successful save throw
/// instead of closing.
Future<void> pumpSheet(
  WidgetTester tester,
  TestEnvironment env,
  Widget sheet, {
  List<Override> overrides = const [],
}) async {
  await pumpScreen(tester, env, _SheetHost(sheet: sheet), overrides: overrides);
  await tester.tap(find.byKey(const Key('open-sheet')));
  await pumpFrames(tester);
}

/// True once the sheet under test has closed itself.
bool sheetIsClosed() => find.byKey(const Key('open-sheet')).evaluate().length == 1
    && find.byType(BottomSheet).evaluate().isEmpty;

class _SheetHost extends StatelessWidget {
  const _SheetHost({required this.sheet});
  final Widget sheet;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Center(
        child: Builder(
          builder: (context) => ElevatedButton(
            key: const Key('open-sheet'),
            onPressed: () => showModalBottomSheet<void>(
              context: context,
              isScrollControlled: true,
              builder: (_) => sheet,
            ),
            child: const Text('open'),
          ),
        ),
      ),
    );
  }
}

/// Scrolls a control into view and taps it.
///
/// A bottom sheet taller than the viewport is normal on a phone; tapping a
/// widget that is laid out below the fold hits whatever happens to be at that
/// coordinate instead, which fails in a way that looks like a logic bug.
Future<void> tapVisible(WidgetTester tester, Finder finder) async {
  await tester.ensureVisible(finder);
  await tester.pump();
  await tester.tap(finder);
  await pumpFrames(tester);
}
