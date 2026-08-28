/// The metrics LifeDNA can consume from a platform health provider.
enum HealthMetric {
  steps('steps', 'Steps', 'count'),
  activeCalories('active_calories', 'Active calories', 'kcal'),
  distance('distance', 'Distance', 'm'),
  heartRate('heart_rate', 'Heart rate', 'bpm'),
  restingHeartRate('resting_heart_rate', 'Resting heart rate', 'bpm'),
  sleepMinutes('sleep_minutes', 'Sleep', 'min'),
  weight('weight', 'Weight', 'kg');

  const HealthMetric(this.wire, this.label, this.unit);
  final String wire;
  final String label;
  final String unit;

  static HealthMetric? fromWire(String value) {
    for (final metric in values) {
      if (metric.wire == value) return metric;
    }
    return null;
  }
}

/// One reading from a health provider.
class HealthSample {
  const HealthSample({
    required this.metric,
    required this.value,
    required this.start,
    required this.end,
    required this.source,
  });

  final HealthMetric metric;
  final double value;
  final DateTime start;
  final DateTime end;

  /// Originating app or device, e.g. `com.sec.android.app.shealth`.
  final String source;

  /// Deterministic identity, so re-reading the same window cannot create
  /// duplicate records.
  String get idempotencyKey =>
      '$source|${metric.wire}|${start.millisecondsSinceEpoch}|'
      '${end.millisecondsSinceEpoch}';

  Map<String, dynamic> toJson() => {
    'metric': metric.wire,
    'value': value,
    'start': start.toIso8601String(),
    'end': end.toIso8601String(),
    'source': source,
  };

  static HealthSample? fromPlatform(Map<Object?, Object?> raw) {
    final metric = HealthMetric.fromWire(raw['metric'] as String? ?? '');
    final start = DateTime.tryParse(raw['start'] as String? ?? '');
    final end = DateTime.tryParse(raw['end'] as String? ?? '');
    final value = (raw['value'] as num?)?.toDouble();
    if (metric == null || start == null || end == null || value == null) {
      return null;
    }
    return HealthSample(
      metric: metric,
      value: value,
      start: start,
      end: end,
      source: raw['source'] as String? ?? 'unknown',
    );
  }
}

/// Why a health provider is or is not usable.
enum HealthAvailability {
  /// Provider present, permissions granted, ready to read.
  ready,

  /// Provider present but the user has not granted permission yet.
  needsPermission,

  /// Provider app is not installed on this device.
  providerNotInstalled,

  /// This platform has no supported provider (iOS in the current build).
  unsupportedPlatform,

  /// The native integration is not compiled into this build.
  notEnabledInBuild;

  bool get canRequestPermission => this == HealthAvailability.needsPermission;
  bool get isUsable => this == HealthAvailability.ready;

  String get title => switch (this) {
    HealthAvailability.ready => 'Connected',
    HealthAvailability.needsPermission => 'Permission needed',
    HealthAvailability.providerNotInstalled => 'Health Connect not installed',
    HealthAvailability.unsupportedPlatform => 'Not available on this device',
    HealthAvailability.notEnabledInBuild => 'Not enabled in this build',
  };

  String get detail => switch (this) {
    HealthAvailability.ready =>
      'Steps, sleep and heart rate are being read from Health Connect.',
    HealthAvailability.needsPermission =>
      'Grant access to steps, sleep and heart rate to see them here.',
    HealthAvailability.providerNotInstalled =>
      'Samsung Health syncs through Health Connect. Install Health Connect '
          'from the Play Store, then open Samsung Health once to let it '
          'share data.',
    HealthAvailability.unsupportedPlatform =>
      'Health sync is Android-only in this release.',
    HealthAvailability.notEnabledInBuild =>
      'This build was compiled without the native health integration. '
          'Everything else works; nothing is being read.',
  };
}

/// A day's health totals, as LifeDNA consumes them.
class DailyHealthSummary {
  const DailyHealthSummary({
    required this.localDate,
    this.steps,
    this.activeCalories,
    this.distanceMetres,
    this.restingHeartRate,
    this.sleepMinutes,
  });

  final String localDate;
  final int? steps;
  final double? activeCalories;
  final double? distanceMetres;
  final int? restingHeartRate;
  final int? sleepMinutes;

  bool get hasAny =>
      steps != null ||
      activeCalories != null ||
      distanceMetres != null ||
      restingHeartRate != null ||
      sleepMinutes != null;

  String? get sleepLabel {
    final minutes = sleepMinutes;
    if (minutes == null) return null;
    return '${minutes ~/ 60}h ${(minutes % 60).toString().padLeft(2, '0')}m';
  }
}
