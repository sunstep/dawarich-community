
import 'package:dawarich/features/tracking/domain/enum/location_precision.dart';
import 'package:dawarich/features/tracking/domain/enum/tracking_mode.dart';

final class TrackerSettings {
  final int userId;
  final bool automaticTracking;
  final int trackingFrequency;
  final LocationPrecision locationPrecision;
  final int minimumPointDistance;
  final int pointsPerBatch;
  final int? batchExpirationMinutes;
  final String deviceId;

  const TrackerSettings({
    required this.userId,
    required this.automaticTracking,
    required this.trackingFrequency,
    required this.locationPrecision,
    required this.minimumPointDistance,
    required this.pointsPerBatch,
    this.batchExpirationMinutes,
    required this.deviceId,
  });

  /// Whether batch expiration is enabled (non-null and > 0).
  bool get isBatchExpirationEnabled =>
      batchExpirationMinutes != null && batchExpirationMinutes! > 0;

  TrackingMode get trackingMode {

    if (trackingFrequency > 0) {
      return TrackingMode.timer;
    }

    return TrackingMode.automatic;
  }

  TrackerSettings copyWith({
    bool? automaticTracking,
    int? trackingFrequency,
    LocationPrecision? locationPrecision,
    int? minimumPointDistance,
    int? pointsPerBatch,
    int? Function()? batchExpirationMinutes,
    String? deviceId,
  }) {
    return TrackerSettings(
      userId: userId,
      automaticTracking: automaticTracking ?? this.automaticTracking,
      trackingFrequency: trackingFrequency ?? this.trackingFrequency,
      locationPrecision: locationPrecision ?? this.locationPrecision,
      minimumPointDistance: minimumPointDistance ?? this.minimumPointDistance,
      pointsPerBatch: pointsPerBatch ?? this.pointsPerBatch,
      batchExpirationMinutes: batchExpirationMinutes != null
          ? batchExpirationMinutes()
          : this.batchExpirationMinutes,
      deviceId: deviceId ?? this.deviceId,
    );
  }
}