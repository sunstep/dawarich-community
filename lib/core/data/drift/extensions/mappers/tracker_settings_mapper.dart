
import 'package:dawarich/core/data/drift/database/sqlite_client.dart';
import 'package:dawarich/features/tracking/domain/enum/location_precision.dart';
import 'package:dawarich/features/tracking/domain/models/tracker_settings.dart';
import 'package:drift/drift.dart';
import 'package:geolocator/geolocator.dart';

extension TrackerSettingsRowMapper on TrackerSettingsTableData {
  TrackerSettings toDomain({required TrackerSettings defaults}) {
    return TrackerSettings(
      userId: userId,
      automaticTracking: automaticTracking ?? defaults.automaticTracking,
      trackingFrequency: trackingFrequency ?? defaults.trackingFrequency,
      locationPrecision: _precisionFromStoredInt(
        stored: locationAccuracy,
        fallback: defaults.locationPrecision,
      ),
      minimumPointDistance: minimumPointDistance ?? defaults.minimumPointDistance,
      pointsPerBatch: pointsPerBatch ?? defaults.pointsPerBatch,
      deviceId: deviceId ?? defaults.deviceId,
    );
  }
}

extension TrackerSettingsCompanionMapper on TrackerSettings {
  TrackerSettingsTableCompanion toCompanion() {
    return TrackerSettingsTableCompanion(
      userId: Value(userId),
      automaticTracking: Value(automaticTracking),
      trackingFrequency: Value(trackingFrequency),
      locationAccuracy: Value(locationPrecision.code),
      minimumPointDistance: Value(minimumPointDistance),
      pointsPerBatch: Value(pointsPerBatch),
      deviceId: Value(deviceId),
    );
  }
}

LocationPrecision _precisionFromStoredInt({
  required int? stored,
  required LocationPrecision fallback,
}) {
  if (stored == null) {
    return fallback;
  }

  // Backward compatibility:
  // Old versions stored `LocationAccuracy.index`.
  // New versions store `LocationPrecision.code`.
  //
  // Strategy:
  // 1) If `stored` matches one of our new codes -> use it.
  // 2) Otherwise, if `stored` is a valid LocationAccuracy index -> map it.
  // 3) Else fallback.
  final LocationPrecision direct = LocationPrecision.fromCode(stored);
  if (direct.code == stored) {
    return direct;
  }

  final LocationAccuracy? legacy = _tryLocationAccuracyFromIndex(stored);
  if (legacy == null) {
    return fallback;
  }

  return _mapLegacyAccuracyToPrecision(legacy);
}

LocationAccuracy? _tryLocationAccuracyFromIndex(int index) {
  if (index < 0) {
    return null;
  }
  if (index >= LocationAccuracy.values.length) {
    return null;
  }
  return LocationAccuracy.values[index];
}

LocationPrecision _mapLegacyAccuracyToPrecision(LocationAccuracy a) {
  switch (a) {
    case LocationAccuracy.best:
    case LocationAccuracy.bestForNavigation:
      return LocationPrecision.best;
    case LocationAccuracy.high:
      return LocationPrecision.high;
    case LocationAccuracy.medium:
      return LocationPrecision.balanced;
    case LocationAccuracy.low:
      return LocationPrecision.lowPower;
    case LocationAccuracy.lowest:
    case LocationAccuracy.reduced:
      return LocationPrecision.powerSave;
  }
}