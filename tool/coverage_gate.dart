// Coverage reporter and CI gate.
//
// Reads `app/coverage/lcov.info`, prints per-directory and per-file coverage,
// and exits non-zero when the total falls below the threshold. Written in Dart
// so CI needs nothing beyond the Flutter SDK it already has.
//
// Files are excluded ONLY when executing them would require a device or a real
// Firebase project — generated bindings, the platform entry point, and the
// thin adapters whose entire body is a plugin call. Excluding anything else
// would make the number a decoration.
//
// Usage:
//   cd app && flutter test --coverage
//   dart ../tool/coverage_gate.dart            # default threshold
//   dart ../tool/coverage_gate.dart --min 80   # explicit threshold
//   dart ../tool/coverage_gate.dart --report   # per-file table, no gate

import 'dart:io';

/// Paths excluded from the measurement, each with the reason it cannot be
/// exercised in a host-side test.
const Map<String, String> excluded = {
  'lib/main.dart': 'process entry point; runs the real bootstrap',
  'lib/core/config/app_bootstrap.dart': 'initialises Firebase and the keystore',
  'lib/core/config/firebase_config.dart': 'compile-time --dart-define values',
  'lib/core/firebase/firebase_service.dart': 'calls Firebase.initializeApp',
  'lib/core/network/connectivity_service.dart': 'wraps the connectivity plugin',
  'lib/core/notifications/notification_service.dart':
      'wraps the notifications plugin; behaviour is covered through its fake',
  'lib/features/calendar/data/google_calendar_service.dart':
      'requires a real Google OAuth session',
};

class _FileCoverage {
  _FileCoverage(this.path);
  final String path;
  int found = 0;
  int hit = 0;
  double get percent => found == 0 ? 100 : hit / found * 100;
}

void main(List<String> args) {
  final reportOnly = args.contains('--report');
  final minIndex = args.indexOf('--min');
  final threshold = minIndex >= 0 && minIndex + 1 < args.length
      ? double.parse(args[minIndex + 1])
      : 80.0;

  final lcov = File('coverage/lcov.info').existsSync()
      ? File('coverage/lcov.info')
      : File('app/coverage/lcov.info');

  if (!lcov.existsSync()) {
    stderr.writeln(
      'No lcov.info found. Run `flutter test --coverage` in app/ first.',
    );
    exit(2);
  }

  final files = <String, _FileCoverage>{};
  _FileCoverage? current;

  for (final line in lcov.readAsLinesSync()) {
    if (line.startsWith('SF:')) {
      final path = line.substring(3).replaceAll('\\', '/');
      final normalised =
          path.contains('/lib/') ? 'lib/${path.split('/lib/').last}' : path;
      current = files.putIfAbsent(normalised, () => _FileCoverage(normalised));
    } else if (line.startsWith('DA:') && current != null) {
      final parts = line.substring(3).split(',');
      current.found++;
      if (int.parse(parts[1]) > 0) current.hit++;
    }
  }

  final measured = <_FileCoverage>[];
  final skipped = <_FileCoverage>[];
  for (final file in files.values) {
    (excluded.containsKey(file.path) ? skipped : measured).add(file);
  }
  measured.sort((a, b) => a.percent.compareTo(b.percent));

  var found = 0;
  var hit = 0;
  for (final file in measured) {
    found += file.found;
    hit += file.hit;
  }
  final total = found == 0 ? 0.0 : hit / found * 100;

  stdout.writeln('LifeDNA coverage');
  stdout.writeln('=' * 72);

  final byArea = <String, _FileCoverage>{};
  for (final file in measured) {
    final segments = file.path.split('/');
    final area = segments.length >= 3
        ? '${segments[1]}/${segments[2]}'
        : segments.take(2).join('/');
    final bucket = byArea.putIfAbsent(area, () => _FileCoverage(area));
    bucket.found += file.found;
    bucket.hit += file.hit;
  }

  final areas = byArea.values.toList()
    ..sort((a, b) => a.percent.compareTo(b.percent));
  for (final area in areas) {
    stdout.writeln(
      '${area.percent.toStringAsFixed(1).padLeft(6)} %  '
      '${area.hit.toString().padLeft(5)}/${area.found.toString().padRight(6)} '
      '${area.path}',
    );
  }

  if (reportOnly) {
    stdout.writeln('\nLowest-covered files');
    stdout.writeln('-' * 72);
    for (final file in measured.take(20)) {
      stdout.writeln(
        '${file.percent.toStringAsFixed(1).padLeft(6)} %  '
        '${file.hit.toString().padLeft(5)}/${file.found.toString().padRight(6)} '
        '${file.path}',
      );
    }
  }

  if (skipped.isNotEmpty) {
    stdout.writeln('\nExcluded (device- or backend-bound)');
    stdout.writeln('-' * 72);
    for (final file in skipped) {
      stdout.writeln('        ${file.path} — ${excluded[file.path]}');
    }
  }

  stdout.writeln('=' * 72);
  stdout.writeln(
    'TOTAL ${total.toStringAsFixed(2)} % of $found measured lines '
    '(threshold ${threshold.toStringAsFixed(0)} %)',
  );

  if (reportOnly) return;
  if (total + 0.005 < threshold) {
    stderr.writeln(
      'FAIL: coverage ${total.toStringAsFixed(2)} % is below '
      '${threshold.toStringAsFixed(0)} %.',
    );
    exit(1);
  }
  stdout.writeln('PASS');
}
