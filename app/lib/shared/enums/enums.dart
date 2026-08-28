/// Shared domain enumerations. Pure Dart — no Flutter, no Firebase.
library;

enum GoalMode {
  cut('cut', -0.18),
  maintain('maintain', 0),
  bulk('bulk', 0.10);

  const GoalMode(this.wire, this.kcalDelta);

  /// The stable string used in storage and on the wire.
  final String wire;

  /// Fractional adjustment applied to TDEE.
  final double kcalDelta;

  static GoalMode fromWire(String value) =>
      values.firstWhere((m) => m.wire == value, orElse: () => GoalMode.maintain);
}

enum Sex {
  male('male'),
  female('female'),
  unspecified('unspecified');

  const Sex(this.wire);
  final String wire;

  static Sex fromWire(String value) =>
      values.firstWhere((s) => s.wire == value, orElse: () => Sex.unspecified);
}

enum ActivityLevel {
  sedentary('sedentary', 1.2, 'Desk work, little movement'),
  light('light', 1.375, 'Light activity 1–3 days a week'),
  moderate('moderate', 1.55, 'Moderate activity 3–5 days a week'),
  active('active', 1.725, 'Hard activity 6–7 days a week'),
  veryActive('very_active', 1.9, 'Physical job or twice-daily training');

  const ActivityLevel(this.wire, this.factor, this.description);
  final String wire;
  final double factor;
  final String description;

  static ActivityLevel fromWire(String value) => values.firstWhere(
        (a) => a.wire == value,
        orElse: () => ActivityLevel.moderate,
      );
}

enum DayType {
  training('training'),
  rest('rest');

  const DayType(this.wire);
  final String wire;
}

enum MealSlot {
  breakfast('breakfast', 'Breakfast', 9, 0),
  lunch('lunch', 'Lunch', 13, 0),
  preWorkout('pre_workout', 'Pre-workout', 16, 30),
  postWorkout('post_workout', 'Post-workout', 19, 30),
  dinner('dinner', 'Dinner', 20, 30),
  beforeBed('before_bed', 'Before bed', 22, 30),
  snack('snack', 'Snack', 0, 0);

  const MealSlot(this.wire, this.label, this.defaultHour, this.defaultMinute);
  final String wire;
  final String label;
  final int defaultHour;
  final int defaultMinute;

  static MealSlot fromWire(String value) =>
      values.firstWhere((s) => s.wire == value, orElse: () => MealSlot.snack);

  /// The slot a log at [time] most likely belongs to. Used to pre-fill the
  /// portion sheet so the user rarely has to choose.
  static MealSlot forTime(DateTime time) {
    final minutes = time.hour * 60 + time.minute;
    if (minutes < 11 * 60) return MealSlot.breakfast;
    if (minutes < 15 * 60) return MealSlot.lunch;
    if (minutes < 18 * 60) return MealSlot.preWorkout;
    if (minutes < 21 * 60) return MealSlot.postWorkout;
    return MealSlot.beforeBed;
  }
}

enum MuscleGroup {
  chest('chest', 'Chest'),
  back('back', 'Back'),
  shoulders('shoulders', 'Shoulders'),
  biceps('biceps', 'Biceps'),
  triceps('triceps', 'Triceps'),
  forearms('forearms', 'Forearms'),
  quads('quads', 'Quads'),
  hamstrings('hamstrings', 'Hamstrings'),
  glutes('glutes', 'Glutes'),
  calves('calves', 'Calves'),
  core('core', 'Core'),
  fullBody('full_body', 'Full body');

  const MuscleGroup(this.wire, this.label);
  final String wire;
  final String label;

  static MuscleGroup fromWire(String value) => values.firstWhere(
        (m) => m.wire == value,
        orElse: () => MuscleGroup.fullBody,
      );
}

enum Equipment {
  barbell('barbell', 'Barbell'),
  dumbbell('dumbbell', 'Dumbbell'),
  machine('machine', 'Machine'),
  cable('cable', 'Cable'),
  bodyweight('bodyweight', 'Bodyweight'),
  kettlebell('kettlebell', 'Kettlebell'),
  band('band', 'Band'),
  smith('smith', 'Smith machine'),
  cardio('cardio', 'Cardio machine');

  const Equipment(this.wire, this.label);
  final String wire;
  final String label;
}

enum SetType {
  warmup('warmup'),
  working('working'),
  dropset('dropset'),
  failure('failure'),
  amrap('amrap');

  const SetType(this.wire);
  final String wire;

  /// Warm-up sets are excluded from volume and PR calculations.
  bool get countsTowardVolume => this != SetType.warmup;
}

enum SessionStatus {
  inProgress('in_progress'),
  completed('completed'),
  abandoned('abandoned');

  const SessionStatus(this.wire);
  final String wire;
}

enum RecoveryBand {
  low('low', 'Low'),
  moderate('moderate', 'Moderate'),
  high('high', 'High'),
  insufficientData('insufficient_data', 'Insufficient data');

  const RecoveryBand(this.wire, this.label);
  final String wire;
  final String label;

  static RecoveryBand forScore(int score) {
    if (score <= 33) return RecoveryBand.low;
    if (score <= 66) return RecoveryBand.moderate;
    return RecoveryBand.high;
  }
}

/// What the engine recommends doing with today's planned session.
enum TrainingAction {
  push('push', 'Green light — go for a PR attempt.'),
  proceed('proceed', 'Train as planned.'),
  reduce('reduce', 'Cut volume by 30 %. Keep the compounds.'),
  rest('rest', 'Take today off or do a light recovery session.');

  const TrainingAction(this.wire, this.headline);
  final String wire;
  final String headline;
}

enum TaskPriority {
  p1(1, 'P1'),
  p2(2, 'P2'),
  p3(3, 'P3'),
  p4(4, 'P4');

  const TaskPriority(this.level, this.label);
  final int level;
  final String label;

  static TaskPriority fromLevel(int level) =>
      values.firstWhere((p) => p.level == level, orElse: () => TaskPriority.p3);
}

enum TaskCategory {
  university('university', 'University'),
  work('work', 'Work'),
  fitness('fitness', 'Fitness'),
  personal('personal', 'Personal'),
  projects('projects', 'Projects');

  const TaskCategory(this.wire, this.label);
  final String wire;
  final String label;
}

enum TaskStatus {
  open('open'),
  inProgress('in_progress'),
  done('done'),
  cancelled('cancelled');

  const TaskStatus(this.wire);
  final String wire;

  bool get isClosed => this == TaskStatus.done || this == TaskStatus.cancelled;
}

enum AssistantId {
  coach('coach', 'Coach'),
  claude('claude', 'Claude'),
  copilot('copilot', 'Copilot');

  const AssistantId(this.wire, this.label);
  final String wire;
  final String label;
}

enum NotificationCategory {
  meeting('meeting', 95),
  workout('workout', 90),
  meal('meal', 85),
  task('task', 80),
  supplement('supplement', 70),
  recovery('recovery', 65),
  insight('insight', 60),
  sleep('sleep', 55),
  hydration('hydration', 40),
  system('system', 30);

  const NotificationCategory(this.wire, this.priority);
  final String wire;

  /// Higher wins when the daily cap forces a drop (docs/14 §7).
  final int priority;

  /// Categories at or above this priority pierce quiet hours.
  bool get piercesQuietHours => priority >= 90;
}
