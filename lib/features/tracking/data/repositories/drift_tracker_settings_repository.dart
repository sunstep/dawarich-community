import 'package:dawarich/core/data/drift/database/sqlite_client.dart';
import 'package:dawarich/features/tracking/application/repositories/hardware_repository_interfaces.dart';
import 'package:dawarich/features/tracking/application/repositories/tracker_settings_repository.dart';
import 'package:dawarich/features/tracking/domain/enum/location_precision.dart';
import 'package:dawarich/features/tracking/domain/models/tracker_settings.dart';
import 'package:drift/drift.dart';
import 'package:flutter/foundation.dart';

final class DriftTrackerSettingsRepository implements ITrackerSettingsRepository {

  final SQLiteClient _db;
  final IHardwareRepository _hardwareRepository;
  DriftTrackerSettingsRepository(this._db, this._hardwareRepository);

  @override
  Future<TrackerSettings> get({required int userId}) async {

    final row = await _readRow(userId);
    final String? rowDeviceId = row?.deviceId;

    final bool hasDeviceId = rowDeviceId != null && rowDeviceId.trim() != '';

    final String deviceId = hasDeviceId
        ? rowDeviceId.trim()
        : await _hardwareRepository.getDeviceModel();

    final TrackerSettings defaults = TrackerSettings(
      userId: userId,
      automaticTracking: false,
      trackingFrequency: 0,
      locationPrecision: LocationPrecision.high,
      minimumPointDistance: 0,
      pointsPerBatch: 50,
      deviceId: deviceId,
    );

    if (row == null) {
      return defaults;
    }

    return _fromRow(row, defaults: defaults);
  }

  @override
  Future<void> set({required TrackerSettings settings}) async {
    if (kDebugMode) {
      debugPrint("[TrackerSettingsRepo] Saving settings: freq=${settings.trackingFrequency}s, precision=${settings.locationPrecision}");
    }
    final companion = _toCompanion((settings));
    await _db.into(_db.trackerSettingsTable).insertOnConflictUpdate(companion);
    if (kDebugMode) {
      debugPrint("[TrackerSettingsRepo] Settings saved successfully");
    }
  }

  @override
  Stream<TrackerSettings> watch({required int userId}) async * {
    if (kDebugMode) {
      debugPrint("[TrackerSettingsRepo] Setting up watch for userId: $userId");
    }

    final q = (_db.select(_db.trackerSettingsTable)
      ..where((t) => t.userId.equals(userId)));

    final String defaultDeviceId = await _hardwareRepository.getDeviceModel();

    final TrackerSettings defaults = TrackerSettings(
      userId: userId,
      automaticTracking: false,
      trackingFrequency: 0,
      locationPrecision: LocationPrecision.high,
      minimumPointDistance: 0,
      pointsPerBatch: 50,
      deviceId: defaultDeviceId,
    );

    yield * q.watchSingleOrNull().map((row) {
      if (kDebugMode) {
        debugPrint("[TrackerSettingsRepo] Watch received DB update, row: ${row?.trackingFrequency}s");
      }

      if (row == null) {
        if (kDebugMode) {
          debugPrint("[TrackerSettingsRepo] Watch emitting defaults (no row)");
        }
        return defaults;
      }
      final settings = _fromRow(row, defaults: defaults);
      if (kDebugMode) {
        debugPrint("[TrackerSettingsRepo] Watch emitting: freq=${settings.trackingFrequency}s, precision=${settings.locationPrecision}");
      }
      return settings;
    });

  }


  // ---------- Internal helpers ----------

  Future<TrackerSettingsTableData?> _readRow(int userId) {
    return (_db.select(_db.trackerSettingsTable)
      ..where((t) => t.userId.equals(userId)))
        .getSingleOrNull();
  }

  TrackerSettings _fromRow(TrackerSettingsTableData r, {required TrackerSettings defaults}) => TrackerSettings(
    userId: r.userId,
    automaticTracking: r.automaticTracking ?? defaults.automaticTracking,
    trackingFrequency: r.trackingFrequency ?? defaults.trackingFrequency,
    locationPrecision: r.locationAccuracy != null
        ? LocationPrecision.fromCode(r.locationAccuracy!)
        : defaults.locationPrecision,
    minimumPointDistance: r.minimumPointDistance ?? defaults.minimumPointDistance,
    pointsPerBatch: r.pointsPerBatch ?? defaults.pointsPerBatch,
    batchExpirationMinutes: r.batchExpirationMinutes,
    deviceId: r.deviceId ?? defaults.deviceId,
  );

  TrackerSettingsTableCompanion _toCompanion(TrackerSettings s) =>
      TrackerSettingsTableCompanion(
        userId: Value(s.userId),
        automaticTracking: Value(s.automaticTracking),
        trackingFrequency: Value(s.trackingFrequency),
        locationAccuracy: Value(s.locationPrecision.code),
        minimumPointDistance: Value(s.minimumPointDistance),
        pointsPerBatch: Value(s.pointsPerBatch),
        batchExpirationMinutes: Value(s.batchExpirationMinutes),
        deviceId: Value(s.deviceId),
      );
}