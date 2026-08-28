import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:lifedna/core/engines/macro_calculator.dart';
import 'package:lifedna/core/engines/recovery_engine.dart';
import 'package:lifedna/shared/enums/enums.dart';

/// ENGINE PARITY.
///
/// The Recovery and Macro engines exist twice — once in Dart on the client so
/// the UI can recompute instantly and offline, once in TypeScript on the
/// server which is authoritative for what gets stored. If they ever disagree,
/// a user sees one recovery score before syncing and a different one after.
/// That is intolerable, so parity is enforced mechanically rather than by
/// convention.
///
/// These fixtures live at the repository root and are executed by BOTH suites:
///   app/test/unit/core/engines/parity_test.dart   (this file)
///   functions/test/engines/parity.test.ts
///
/// A divergence fails both builds. If you change a formula, change it in both
/// implementations and regenerate the fixtures.
void main() {
  final fixtureRoot = Directory('../test/fixtures/engines');

  group('MacroCalculator parity', () {
    final dir = Directory('${fixtureRoot.path}/macro');

    test('fixture directory is present', () {
      expect(
        dir.existsSync(),
        isTrue,
        reason: 'Expected shared fixtures at ${dir.absolute.path}',
      );
      expect(dir.listSync().whereType<File>(), isNotEmpty);
    });

    for (final file in _fixtures(dir)) {
      final fixture =
          json.decode(file.readAsStringSync()) as Map<String, dynamic>;
      final id = fixture['id'] as String;

      test('macro/$id', () {
        final input = fixture['input'] as Map<String, dynamic>;
        final expected = fixture['expected'] as Map<String, dynamic>;

        final result = MacroCalculator.compute(
          MacroInput(
            weightKg: (input['weightKg'] as num).toDouble(),
            heightCm: (input['heightCm'] as num).toDouble(),
            age: input['age'] as int,
            sex: Sex.fromWire(input['sex'] as String),
            activityLevel:
                ActivityLevel.fromWire(input['activityLevel'] as String),
            goalMode: GoalMode.fromWire(input['goalMode'] as String),
            trainingDaysPerWeek: (input['trainingDaysPerWeek'] as int?) ?? 4,
            leanMassKg: (input['leanMassKg'] as num?)?.toDouble(),
            weeklyRateTargetPct:
                (input['weeklyRateTargetPct'] as num?)?.toDouble() ?? 0.75,
          ),
        );

        expect(result.bmr, expected['bmr'], reason: 'bmr');
        expect(result.tdee, expected['tdee'], reason: 'tdee');
        expect(result.proteinFloorG, expected['proteinFloorG'],
            reason: 'proteinFloorG');
        expect(result.waterMl, expected['waterMl'], reason: 'waterMl');
        expect(result.clamped, expected['clamped'], reason: 'clamped');
        expect(
          result.warnings,
          (expected['warnings'] as List).cast<String>(),
          reason: 'warnings',
        );
        expect(
          result.projectedWeeklyChangeKg,
          closeTo((expected['projectedWeeklyChangeKg'] as num).toDouble(), 0.01),
          reason: 'projectedWeeklyChangeKg',
        );

        _expectTargets(
          result.trainingDay,
          expected['trainingDay'] as Map<String, dynamic>,
          'trainingDay',
        );
        _expectTargets(
          result.restDay,
          expected['restDay'] as Map<String, dynamic>,
          'restDay',
        );
      });
    }
  });

  group('RecoveryEngine parity', () {
    final dir = Directory('${fixtureRoot.path}/recovery');

    test('fixture directory is present', () {
      expect(dir.existsSync(), isTrue);
      expect(dir.listSync().whereType<File>(), isNotEmpty);
    });

    for (final file in _fixtures(dir)) {
      final fixture =
          json.decode(file.readAsStringSync()) as Map<String, dynamic>;
      final id = fixture['id'] as String;

      test('recovery/$id', () {
        final input = fixture['input'] as Map<String, dynamic>;
        final expected = fixture['expected'] as Map<String, dynamic>;

        final result = RecoveryEngine.compute(
          sleep: _sleep(input['sleep'] as Map<String, dynamic>?),
          training: _training(input['training'] as Map<String, dynamic>?),
          activity: _activity(input['activity'] as Map<String, dynamic>?),
          physiology: _physiology(input['physiology'] as Map<String, dynamic>?),
          plannedSession:
              _planned(input['plannedSession'] as Map<String, dynamic>?),
        );

        expect(result.recoveryScore, expected['recoveryScore'],
            reason: 'recoveryScore');
        expect(result.band.wire, expected['band'], reason: 'band');
        expect(result.readinessScore, expected['readinessScore'],
            reason: 'readinessScore');
        expect(result.sleepScore, expected['sleepScore'], reason: 'sleepScore');
        expect(result.action?.wire, expected['action'], reason: 'action');
        expect(
          result.missingInputs,
          (expected['missingInputs'] as List).cast<String>(),
          reason: 'missingInputs',
        );

        final expectedComponents =
            (expected['components'] as List).cast<Map<String, dynamic>>();
        expect(result.components.length, expectedComponents.length,
            reason: 'component count');
        for (var i = 0; i < expectedComponents.length; i++) {
          final actual = result.components[i];
          final want = expectedComponents[i];
          expect(actual.name, want['name'], reason: 'component[$i].name');
          expect(actual.score, want['score'], reason: 'component[$i].score');
          expect(actual.weight, closeTo((want['weight'] as num).toDouble(), 0.001),
              reason: 'component[$i].weight');
          expect(
            actual.contribution,
            closeTo((want['contribution'] as num).toDouble(), 0.1),
            reason: 'component[$i].contribution',
          );
          expect(actual.available, want['available'],
              reason: 'component[$i].available');
        }

        if (expected['detail'] != null) {
          expect(result.detail, expected['detail'], reason: 'detail');
        }
      });
    }
  });
}

List<File> _fixtures(Directory dir) {
  if (!dir.existsSync()) return const [];
  return dir
      .listSync()
      .whereType<File>()
      .where((f) => f.path.endsWith('.json'))
      .toList()
    ..sort((a, b) => a.path.compareTo(b.path));
}

void _expectTargets(
  dynamic actual,
  Map<String, dynamic> want,
  String label,
) {
  expect(actual.kcal, want['kcal'], reason: '$label.kcal');
  expect(actual.proteinG, want['proteinG'], reason: '$label.proteinG');
  expect(actual.carbsG, want['carbsG'], reason: '$label.carbsG');
  expect(actual.fatG, want['fatG'], reason: '$label.fatG');
  expect(actual.proteinFloorG, want['proteinFloorG'],
      reason: '$label.proteinFloorG');
}

SleepInput? _sleep(Map<String, dynamic>? j) => j == null
    ? null
    : SleepInput(
        totalMinutes: j['totalMinutes'] as int,
        timeInBedMinutes: j['timeInBedMinutes'] as int,
        goalMinutes: (j['goalMinutes'] as int?) ?? 480,
        deepMinutes: j['deepMinutes'] as int?,
        remMinutes: j['remMinutes'] as int?,
        bedtimeStdDevMinutes:
            (j['bedtimeStdDevMinutes'] as num?)?.toDouble(),
        wakeStdDevMinutes: (j['wakeStdDevMinutes'] as num?)?.toDouble(),
        nightsOfHistory: (j['nightsOfHistory'] as int?) ?? 0,
      );

TrainingInput? _training(Map<String, dynamic>? j) => j == null
    ? null
    : TrainingInput(
        acwr: (j['acwr'] as num?)?.toDouble(),
        yesterdayLoad: (j['yesterdayLoad'] as num).toDouble(),
        meanDailyLoad28d: (j['meanDailyLoad28d'] as num).toDouble(),
        yesterdaySessionRpe: j['yesterdaySessionRpe'] as int?,
        daysSinceLastSession: (j['daysSinceLastSession'] as int?) ?? 0,
      );

ActivityInput? _activity(Map<String, dynamic>? j) => j == null
    ? null
    : ActivityInput(
        steps: j['steps'] as int,
        stepGoal: j['stepGoal'] as int,
        activeMinutes: j['activeMinutes'] as int,
        trainedYesterday: (j['trainedYesterday'] as bool?) ?? false,
      );

PhysiologyInput _physiology(Map<String, dynamic>? j) => j == null
    ? const PhysiologyInput()
    : PhysiologyInput(
        restingHrBpm: j['restingHrBpm'] as int?,
        baselineRestingHrBpm: j['baselineRestingHrBpm'] as int?,
        hrvMs: (j['hrvMs'] as num?)?.toDouble(),
        baselineHrvMs: (j['baselineHrvMs'] as num?)?.toDouble(),
      );

PlannedSession? _planned(Map<String, dynamic>? j) => j == null
    ? null
    : PlannedSession(
        rpe: j['rpe'] as int,
        durationMinutes: j['durationMinutes'] as int,
      );
