import 'package:flutter_test/flutter_test.dart';
import 'package:lifedna/features/health_sync/domain/health_entities.dart';
import 'package:lifedna/shared/enums/enums.dart';

void main() {
  group('wire round-trips', () {
    test('every enum with a wire value survives storage and a bad value', () {
      // A wire value that no longer parses is how a schema change turns into
      // silent data loss, so every one of these has a defined fallback.
      expect(GoalMode.fromWire('cut'), GoalMode.cut);
      expect(GoalMode.fromWire('nonsense'), GoalMode.maintain);

      expect(Sex.fromWire('female'), Sex.female);
      expect(Sex.fromWire(''), Sex.unspecified);

      expect(ActivityLevel.fromWire('very_active'), ActivityLevel.veryActive);
      expect(ActivityLevel.fromWire('?'), ActivityLevel.moderate);

      expect(MealSlot.fromWire('pre_workout'), MealSlot.preWorkout);
      expect(MealSlot.fromWire('brunch'), MealSlot.snack);

      expect(MuscleGroup.fromWire('hamstrings'), MuscleGroup.hamstrings);
      expect(MuscleGroup.fromWire('tail'), MuscleGroup.fullBody);

      expect(TaskPriority.fromLevel(1), TaskPriority.p1);
      expect(TaskPriority.fromLevel(9), TaskPriority.p3);

      expect(HealthMetric.fromWire('steps'), HealthMetric.steps);
    });

    test('each enum value has a non-empty wire string', () {
      for (final value in GoalMode.values) {
        expect(value.wire, isNotEmpty);
      }
      for (final value in MuscleGroup.values) {
        expect(value.wire, isNotEmpty);
        expect(value.label, isNotEmpty);
      }
      for (final value in Equipment.values) {
        expect(value.wire, isNotEmpty);
        expect(value.label, isNotEmpty);
      }
      for (final value in TaskCategory.values) {
        expect(value.label, isNotEmpty);
      }
    });
  });

  group('behaviour carried by the enum', () {
    test('a warm-up set does not count toward volume or a record', () {
      expect(SetType.warmup.countsTowardVolume, isFalse);
      for (final type in SetType.values.where((t) => t != SetType.warmup)) {
        expect(type.countsTowardVolume, isTrue, reason: type.name);
      }
    });

    test('a meal slot is inferred from the clock', () {
      expect(MealSlot.forTime(DateTime(2026, 1, 1, 8)), MealSlot.breakfast);
      expect(MealSlot.forTime(DateTime(2026, 1, 1, 13)), MealSlot.lunch);
      expect(MealSlot.forTime(DateTime(2026, 1, 1, 17)), MealSlot.preWorkout);
      expect(MealSlot.forTime(DateTime(2026, 1, 1, 19)), MealSlot.postWorkout);
      expect(MealSlot.forTime(DateTime(2026, 1, 1, 23)), MealSlot.beforeBed);
    });

    test('a closed task is done or cancelled, nothing else', () {
      expect(TaskStatus.done.isClosed, isTrue);
      expect(TaskStatus.cancelled.isClosed, isTrue);
      expect(TaskStatus.open.isClosed, isFalse);
      expect(TaskStatus.inProgress.isClosed, isFalse);
    });

    test('recovery bands follow the documented thresholds', () {
      expect(RecoveryBand.forScore(0), RecoveryBand.low);
      expect(RecoveryBand.forScore(33), RecoveryBand.low);
      expect(RecoveryBand.forScore(34), RecoveryBand.moderate);
      expect(RecoveryBand.forScore(66), RecoveryBand.moderate);
      expect(RecoveryBand.forScore(67), RecoveryBand.high);
    });

    test('only the highest-priority categories pierce quiet hours', () {
      // Waking someone at 03:00 for a hydration nudge is how an app gets its
      // notifications turned off for good.
      expect(NotificationCategory.meeting.piercesQuietHours, isTrue);
      expect(NotificationCategory.workout.piercesQuietHours, isTrue);
      expect(NotificationCategory.hydration.piercesQuietHours, isFalse);
      expect(NotificationCategory.insight.piercesQuietHours, isFalse);
    });

    test('every training action carries a headline the UI can show', () {
      for (final action in TrainingAction.values) {
        expect(action.headline, isNotEmpty, reason: action.name);
      }
    });

    test('activity levels rise monotonically', () {
      final factors = ActivityLevel.values.map((a) => a.factor).toList();
      for (var i = 1; i < factors.length; i++) {
        expect(factors[i], greaterThan(factors[i - 1]));
      }
      for (final level in ActivityLevel.values) {
        expect(level.description, isNotEmpty);
      }
    });

    test('health metrics carry a label and a unit for display', () {
      for (final metric in HealthMetric.values) {
        expect(metric.label, isNotEmpty, reason: metric.name);
        expect(metric.unit, isNotEmpty, reason: metric.name);
      }
    });
  });
}
