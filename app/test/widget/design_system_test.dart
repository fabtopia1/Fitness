import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lifedna/core/theme/app_theme.dart';
import 'package:lifedna/core/widgets/ld_widgets.dart';

/// Wraps a widget in the real app themes so tests exercise the same
/// `ThemeExtension` lookup path production does.
Widget host(Widget child, {Brightness brightness = Brightness.dark, double textScale = 1.0}) {
  return MaterialApp(
    theme: brightness == Brightness.dark ? AppTheme.dark() : AppTheme.light(),
    home: MediaQuery(
      data: MediaQueryData(textScaler: TextScaler.linear(textScale)),
      child: Scaffold(body: SingleChildScrollView(child: child)),
    ),
  );
}

void main() {
  group('LdProgressRing', () {
    testWidgets('renders value, target and label', (tester) async {
      await tester.pumpWidget(
        host(
          const LdProgressRing(
            value: 168,
            target: 200,
            label: 'protein',
            unit: 'g',
            color: Color(0xFF00D1B2),
            animate: false,
          ),
        ),
      );
      expect(find.text('168'), findsOneWidget);
      expect(find.text('/ 200'), findsOneWidget);
      expect(find.text('PROTEIN'), findsOneWidget);
    });

    testWidgets('exposes a screen-reader summary, not just a picture',
        (tester) async {
      await tester.pumpWidget(
        host(
          const LdProgressRing(
            value: 168,
            target: 200,
            label: 'protein',
            unit: 'g',
            color: Color(0xFF00D1B2),
            animate: false,
          ),
        ),
      );
      expect(
        find.bySemanticsLabel('protein, 168 of 200 g, 84 percent'),
        findsOneWidget,
      );
    });

    testWidgets('handles a zero target without dividing by zero',
        (tester) async {
      await tester.pumpWidget(
        host(
          const LdProgressRing(
            value: 50,
            target: 0,
            label: 'x',
            color: Color(0xFF0066FF),
            animate: false,
          ),
        ),
      );
      expect(tester.takeException(), isNull);
    });

    testWidgets('renders over-target values without clipping the label',
        (tester) async {
      await tester.pumpWidget(
        host(
          const LdProgressRing(
            value: 268,
            target: 210,
            label: 'carbs',
            unit: 'g',
            color: Color(0xFFFFB800),
            animate: false,
          ),
        ),
      );
      expect(find.text('268'), findsOneWidget);
      expect(tester.takeException(), isNull);
    });
  });

  group('LdMetricTile', () {
    testWidgets('delta direction is semantic, not arithmetic', (tester) async {
      // Weight falling during a cut is GOOD. The tile must render the caller's
      // stated direction rather than inferring one from the sign.
      await tester.pumpWidget(
        host(
          const LdMetricTile(
            label: 'weight',
            value: '89.4',
            unit: 'kg',
            delta: '−0.7 kg',
            deltaDirection: DeltaDirection.good,
          ),
        ),
      );
      expect(find.text('WEIGHT'), findsOneWidget);
      expect(find.text('89.4'), findsOneWidget);
      // Never colour alone — a glyph carries the same information.
      expect(find.text('▲'), findsOneWidget);
    });

    testWidgets('survives 200 % text scaling', (tester) async {
      await tester.pumpWidget(
        host(
          const SizedBox(
            width: 200,
            child: LdMetricTile(
              label: 'recovery',
              value: '88',
              delta: 'High',
              deltaDirection: DeltaDirection.good,
              footnote: 'Readiness 74',
            ),
          ),
          textScale: 2.0,
        ),
      );
      expect(tester.takeException(), isNull);
      expect(find.text('88'), findsOneWidget);
    });
  });

  group('LdPrimaryButton', () {
    testWidgets('a loading button keeps its label so width does not jump',
        (tester) async {
      await tester.pumpWidget(
        host(
          const LdPrimaryButton(
            label: 'Add to lunch',
            loading: true,
            onPressed: null,
          ),
        ),
      );
      expect(find.text('Add to lunch'), findsOneWidget);
      expect(find.byType(CircularProgressIndicator), findsOneWidget);
    });

    testWidgets('a disabled button does not fire', (tester) async {
      var tapped = false;
      await tester.pumpWidget(
        host(const LdPrimaryButton(label: 'Save', onPressed: null)),
      );
      await tester.tap(find.text('Save'), warnIfMissed: false);
      expect(tapped, isFalse);
    });

    testWidgets('Live Gym size meets the 64 dp one-handed minimum',
        (tester) async {
      await tester.pumpWidget(
        host(
          LdPrimaryButton(
            label: 'COMPLETE SET',
            size: LdButtonSize.xl,
            onPressed: () {},
          ),
        ),
      );
      final box = tester.getSize(find.byType(LdPrimaryButton));
      expect(box.height, greaterThanOrEqualTo(64));
    });
  });

  group('LdEmptyState', () {
    testWidgets('names the value and offers a next action', (tester) async {
      await tester.pumpWidget(
        host(
          LdEmptyState(
            icon: Icons.restaurant_rounded,
            headline: 'Nothing logged yet today.',
            body: 'Your first meal takes about 12 seconds.',
            actionLabel: 'Log breakfast',
            onAction: () {},
          ),
        ),
      );
      expect(find.text('Nothing logged yet today.'), findsOneWidget);
      expect(find.text('Log breakfast'), findsOneWidget);
    });

    testWidgets('shows progress instead of a button when waiting on time',
        (tester) async {
      await tester.pumpWidget(
        host(
          const LdEmptyState(
            icon: Icons.lightbulb_rounded,
            headline: 'No insights yet.',
            body: 'Insights start after 7 days of data.',
            progress: (current: 3, total: 7, label: 'DAY 3 OF 7'),
          ),
        ),
      );
      expect(find.byType(LinearProgressIndicator), findsOneWidget);
      expect(find.text('DAY 3 OF 7'), findsOneWidget);
    });
  });

  group('themes', () {
    testWidgets('both themes resolve the design-system extensions',
        (tester) async {
      for (final brightness in Brightness.values) {
        await tester.pumpWidget(
          host(
            Builder(
              builder: (context) {
                // These throw if the extensions are not registered.
                final colors = context.ldColors;
                final type = context.ldType;
                return Text(
                  'ok',
                  style: type.bodyM.copyWith(color: colors.textPrimary),
                );
              },
            ),
            brightness: brightness,
          ),
        );
        expect(find.text('ok'), findsOneWidget);
      }
    });

    testWidgets('recovery band colours map to the documented thresholds',
        (tester) async {
      late BuildContext ctx;
      await tester.pumpWidget(
        host(Builder(builder: (context) {
          ctx = context;
          return const SizedBox();
        })),
      );
      final c = ctx.ldColors;
      expect(c.recoveryBandColor(20), c.recoveryLow);
      expect(c.recoveryBandColor(33), c.recoveryLow);
      expect(c.recoveryBandColor(34), c.recoveryModerate);
      expect(c.recoveryBandColor(66), c.recoveryModerate);
      expect(c.recoveryBandColor(67), c.recoveryHigh);
      expect(c.recoveryBandColor(100), c.recoveryHigh);
    });
  });
}
