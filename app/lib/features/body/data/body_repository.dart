import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:lifedna/core/data/synced_collection.dart';
import 'package:lifedna/core/data/synced_entity.dart';
import 'package:lifedna/core/error/failure.dart';
import 'package:lifedna/core/result/result.dart';
import 'package:lifedna/core/storage/hive_store.dart';
import 'package:lifedna/core/sync/outbox.dart';
import 'package:lifedna/core/storage/photo_store.dart';
import 'package:lifedna/features/body/domain/body_entities.dart';
import 'package:uuid/uuid.dart';

class BodyRepository {
  BodyRepository({
    required HiveStore store,
    required Outbox outbox,
    PhotoStore? photos,
    FirebaseFirestore? firestore,
    String? uid,
    Uuid uuid = const Uuid(),
    DateTime Function()? clock,
  }) : _uuid = uuid,
       _clock = clock ?? DateTime.now,
       _photos = photos,
       measurements = SyncedCollection<BodyMeasurement>(
         store: store,
         outbox: outbox,
         boxName: HiveStore.boxBodyMeasurements,
         collection: 'body_measurements',
         fromJson: BodyMeasurement.fromJson,
         firestore: firestore,
         uid: uid,
       );

  final Uuid _uuid;
  final DateTime Function() _clock;
  final PhotoStore? _photos;
  final SyncedCollection<BodyMeasurement> measurements;

  Stream<List<BodyMeasurement>> watchAll() => measurements.watchAll();

  /// Oldest first, which is the order every chart wants.
  List<BodyMeasurement> chronological() {
    final all = measurements.readAll()
      ..sort((a, b) => a.measuredAt.compareTo(b.measuredAt));
    return all;
  }

  BodyMeasurement? latest() {
    final all = chronological();
    return all.isEmpty ? null : all.last;
  }

  double? latestWeightKg() {
    for (final measurement in chronological().reversed) {
      if (measurement.weightKg != null) return measurement.weightKg;
    }
    return null;
  }

  BodyMeasurement create({
    DateTime? measuredAt,
    double? weightKg,
    double? bodyFatPct,
    double? waistCm,
    double? chestCm,
    double? leftArmCm,
    double? rightArmCm,
    double? leftLegCm,
    double? rightLegCm,
    double? neckCm,
    double? hipsCm,
    String? photoPath,
    String? notes,
  }) {
    final when = measuredAt ?? _clock();
    return BodyMeasurement(
      id: _uuid.v4(),
      measuredAt: when.toUtc(),
      localDate: Json.localDate(when),
      weightKg: weightKg,
      bodyFatPct: bodyFatPct,
      waistCm: waistCm,
      chestCm: chestCm,
      leftArmCm: leftArmCm,
      rightArmCm: rightArmCm,
      leftLegCm: leftLegCm,
      rightLegCm: rightLegCm,
      neckCm: neckCm,
      hipsCm: hipsCm,
      photoPath: photoPath,
      notes: notes,
      updatedAt: when.toUtc(),
    );
  }

  Future<Result<BodyMeasurement>> save(BodyMeasurement measurement) async {
    if (!measurement.hasAnyValue) {
      return const Err(ValidationFailure('required', field: 'measurement'));
    }
    final weight = measurement.weightKg;
    if (weight != null && (weight < 20 || weight > 400)) {
      return const Err(ValidationFailure('body_weight_out_of_range'));
    }
    final fat = measurement.bodyFatPct;
    if (fat != null && (fat < 1 || fat > 70)) {
      return const Err(ValidationFailure('measurement_out_of_range'));
    }
    for (final value in [
      measurement.waistCm,
      measurement.chestCm,
      measurement.leftArmCm,
      measurement.rightArmCm,
      measurement.leftLegCm,
      measurement.rightLegCm,
      measurement.neckCm,
      measurement.hipsCm,
    ]) {
      if (value != null && (value < 1 || value > 300)) {
        return const Err(ValidationFailure('measurement_out_of_range'));
      }
    }
    if (measurement.measuredAt.isAfter(
      _clock().toUtc().add(const Duration(minutes: 5)),
    )) {
      return const Err(ValidationFailure('date_in_future'));
    }

    return measurements.put(measurement);
  }

  Future<Result<void>> delete(String id) async {
    // Read the photo reference before the tombstone hides the measurement,
    // otherwise the file is orphaned in the documents directory for the life
    // of the install — photos are the largest thing this app writes.
    final photo = measurements.readOne(id)?.photoPath;

    final result = await measurements.remove(
      id,
      tombstone: (m) => m.copyWith(deletedAt: _clock().toUtc()),
    );

    if (result.isOk && photo != null) {
      await _photos?.delete(photo);
    }
    return result;
  }

  /// Series for one metric, oldest first.
  BodyTrend trendFor(BodyMetric metric, {int days = 90, DateTime? now}) {
    final cutoff = (now ?? _clock()).subtract(Duration(days: days));
    final points = <({DateTime at, double value})>[];

    for (final measurement in chronological()) {
      if (measurement.measuredAt.isBefore(cutoff)) continue;
      final value = measurement.values[metric];
      if (value != null) {
        points.add((at: measurement.measuredAt, value: value));
      }
    }
    return BodyTrend(metric: metric, points: points);
  }

  /// Metrics the user has actually recorded, so the chart selector offers only
  /// what has data behind it.
  List<BodyMetric> availableMetrics() {
    final present = <BodyMetric>{};
    for (final measurement in measurements.readAll()) {
      present.addAll(measurement.values.keys);
    }
    return BodyMetric.values.where(present.contains).toList();
  }

  List<BodyMeasurement> withPhotos() => chronological()
      .where((m) => m.photoPath != null)
      .toList()
      .reversed
      .toList();

  Future<Result<int>> pullAll() => measurements.pull();
}
