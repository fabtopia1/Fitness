import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lifedna/core/error/failure.dart';
import 'package:lifedna/core/theme/app_theme.dart';
import 'package:lifedna/core/widgets/ld_widgets.dart';

Widget host(Widget child, {ThemeData? theme}) => MaterialApp(
      theme: theme ?? AppTheme.dark(),
      home: Scaffold(body: Center(child: child)),
    );

void main() {
  group('LdAsyncView', () {
    Widget view(AsyncValue<List<String>> value, {VoidCallback? onRetry}) => host(
          LdAsyncView<List<String>>(
            value: value,
            onRetry: onRetry ?? () {},
            errorContext: 'test screen',
            isEmpty: (data) => data.isEmpty,
            empty: const LdEmptyState(
              icon: Icons.inbox_rounded,
              headline: 'Nothing here yet',
              body: 'Add the first one.',
            ),
            data: (data) => Column(children: [for (final s in data) Text(s)]),
          ),
        );

    testWidgets('loading shows a spinner', (tester) async {
      await tester.pumpWidget(view(const AsyncValue.loading()));
      await tester.pump();
      expect(find.byType(CircularProgressIndicator), findsOneWidget);
    });

    testWidgets('data renders the data', (tester) async {
      await tester.pumpWidget(view(const AsyncValue.data(['a', 'b'])));
      await tester.pump();
      expect(find.text('a'), findsOneWidget);
      expect(find.text('b'), findsOneWidget);
    });

    testWidgets('empty renders the empty state, not a blank screen',
        (tester) async {
      await tester.pumpWidget(view(const AsyncValue.data([])));
      await tester.pump();
      expect(find.text('Nothing here yet'), findsOneWidget);
    });

    testWidgets('a retryable error offers the retry and fires it',
        (tester) async {
      var retried = 0;
      await tester.pumpWidget(
        view(
          const AsyncValue.error(NetworkFailure(), StackTrace.empty),
          onRetry: () => retried++,
        ),
      );
      await tester.pump();

      expect(find.textContaining('test screen'), findsOneWidget);
      await tester.tap(find.text('Retry'));
      await tester.pump();
      expect(retried, 1);
    });

    testWidgets('an error the user cannot retry offers no dead button',
        (tester) async {
      await tester.pumpWidget(
        view(const AsyncValue.error(NotFoundFailure(), StackTrace.empty)),
      );
      await tester.pump();

      expect(find.text('Retry'), findsNothing);
      expect(find.byType(LdErrorView), findsOneWidget);
    });

    testWidgets('an unexpected exception is mapped, never shown raw',
        (tester) async {
      await tester.pumpWidget(
        view(
          AsyncValue.error(
            StateError('Null check operator used on a null value'),
            StackTrace.empty,
          ),
        ),
      );
      await tester.pump();

      expect(find.textContaining('Null check'), findsNothing);
      expect(find.byType(LdErrorView), findsOneWidget);
    });
  });

  group('LdOfflineBanner', () {
    testWidgets('says nothing while online and synced', (tester) async {
      await tester.pumpWidget(host(const LdOfflineBanner(isOnline: true)));
      await tester.pump();
      expect(find.byType(Icon), findsNothing);
    });

    testWidgets('offline reassures rather than alarms', (tester) async {
      await tester.pumpWidget(host(const LdOfflineBanner(isOnline: false)));
      await tester.pump();
      expect(find.text('Offline · everything still works'), findsOneWidget);
    });

    testWidgets('offline with queued work says how much', (tester) async {
      await tester.pumpWidget(
        host(const LdOfflineBanner(isOnline: false, pendingWrites: 3)),
      );
      await tester.pump();
      expect(find.textContaining('3 changes will sync later'), findsOneWidget);
    });

    testWidgets('parked work is the one condition that asks for help',
        (tester) async {
      var retried = 0;
      await tester.pumpWidget(
        host(
          LdOfflineBanner(
            isOnline: true,
            pendingWrites: 2,
            parkedWrites: 2,
            onRetry: () => retried++,
          ),
        ),
      );
      await tester.pump();

      expect(find.textContaining("couldn't sync"), findsOneWidget);
      await tester.tap(find.text('Retry'));
      await tester.pump();
      expect(retried, 1);
    });
  });

  group('LdSwitchRow', () {
    testWidgets('tapping the row toggles, not just the switch', (tester) async {
      // A 48 dp switch inside a full-width row is a small target for a thumb.
      var value = false;
      await tester.pumpWidget(
        host(
          StatefulBuilder(
            builder: (context, setState) => LdSwitchRow(
              title: 'Scheduled reminders',
              subtitle: 'Doses and due times',
              value: value,
              onChanged: (next) => setState(() => value = next),
            ),
          ),
        ),
      );
      await tester.pump();

      await tester.tap(find.text('Scheduled reminders'));
      await tester.pump();
      expect(value, isTrue);

      await tester.tap(find.byType(Switch));
      await tester.pump();
      expect(value, isFalse);
    });
  });

  group('LdCard', () {
    testWidgets('an accent card lays out inside an unbounded parent',
        (tester) async {
      // A stretch Row in a list once forced an infinite height here.
      await tester.pumpWidget(
        host(
          ListView(
            children: const [
              LdCard(
                accentColor: Colors.orange,
                eyebrow: 'Next action',
                child: Text('Eat 40 g of protein'),
              ),
            ],
          ),
        ),
      );
      await tester.pump();

      expect(tester.takeException(), isNull);
      expect(find.text('NEXT ACTION'), findsOneWidget);
    });

    testWidgets('an interactive card reports itself as a button', (tester) async {
      var taps = 0;
      await tester.pumpWidget(
        host(
          LdCard(
            semanticLabel: 'Today',
            onTap: () => taps++,
            child: const Text('Tap me'),
          ),
        ),
      );
      await tester.pump();

      await tester.tap(find.text('Tap me'));
      await tester.pump();
      expect(taps, 1);
    });
  });

  group('LdStatRow', () {
    testWidgets('renders a value at, under and over target', (tester) async {
      for (final progress in [0.0, 0.5, 1.0, 1.4]) {
        await tester.pumpWidget(
          host(
            LdStatRow(
              label: 'Protein',
              value: '120 g',
              progress: progress,
              color: Colors.blue,
              trailing: '+12',
            ),
          ),
        );
        await tester.pump();
        expect(find.text('PROTEIN'), findsOneWidget);
        expect(tester.takeException(), isNull);
      }
    });
  });

  group('LdSectionHeader', () {
    testWidgets('an action is offered only when it does something',
        (tester) async {
      var acted = 0;
      await tester.pumpWidget(
        host(
          LdSectionHeader(
            title: 'Today',
            actionLabel: 'See all',
            onAction: () => acted++,
          ),
        ),
      );
      await tester.pump();

      expect(find.text('TODAY'), findsOneWidget);
      await tester.tap(find.text('See all'));
      await tester.pump();
      expect(acted, 1);

      await tester.pumpWidget(host(const LdSectionHeader(title: 'Today')));
      await tester.pump();
      expect(find.text('See all'), findsNothing);
    });
  });

  group('the light theme', () {
    testWidgets('renders the same components without exceptions',
        (tester) async {
      await tester.pumpWidget(
        host(
          const Column(
            children: [
              LdCard(eyebrow: 'Card', child: Text('Body')),
              LdSectionHeader(title: 'Section'),
              LdEmptyState(
                icon: Icons.inbox_rounded,
                headline: 'Empty',
                body: 'Nothing here',
              ),
            ],
          ),
          theme: AppTheme.light(),
        ),
      );
      await tester.pump();
      expect(tester.takeException(), isNull);
    });
  });
}
