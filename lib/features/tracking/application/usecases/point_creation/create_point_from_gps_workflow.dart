import 'dart:async';

import 'package:dawarich/core/domain/models/point/local/local_point.dart';
import 'package:dawarich/features/tracking/application/repositories/location_provider_interface.dart';
import 'package:dawarich/features/tracking/application/usecases/point_creation/create_point_usecase.dart';
import 'package:dawarich/features/tracking/application/usecases/settings/get_tracker_settings_usecase.dart';
import 'package:dawarich/features/tracking/domain/enum/location_precision.dart';
import 'package:dawarich/features/tracking/domain/models/location_fix.dart';
import 'package:dawarich/features/tracking/domain/models/location_request.dart';
import 'package:dawarich/features/tracking/domain/models/tracker_settings.dart';
import 'package:option_result/result.dart';

final class CreatePointFromGpsWorkflow {

  final GetTrackerSettingsUseCase _getTrackerPreferences;
  final ILocationProvider _locationProvider;
  final CreatePointUseCase _createPointFromLocationFix;

  CreatePointFromGpsWorkflow(
      this._getTrackerPreferences,
      this._locationProvider,
      this._createPointFromLocationFix
  );

  /// The method that handles manually creating a point or when automatic tracking has not tracked a cached point for too long.
  Future<Result<LocalPoint, String>> call(int userId) async {

    final DateTime pointCreationTimestamp = DateTime.now().toUtc();

    final TrackerSettings settings = await _getTrackerPreferences(userId);
    final bool isTrackingAutomatically = settings.automaticTracking;
    final int currentTrackingFrequency = settings.trackingFrequency;
    final LocationPrecision accuracy = settings.locationPrecision;

    final Duration autoAttemptTimeout = _clampDuration(
      Duration(seconds: currentTrackingFrequency),
      const Duration(seconds: 5),
      const Duration(seconds: 30),
    );

    final Duration autoStaleMax = _clampDuration(
      Duration(seconds: currentTrackingFrequency * 2),
      const Duration(seconds: 5),
      const Duration(seconds: 30),
    );

    const Duration manualTimeout = Duration(seconds: 15);
    const Duration manualStaleMax = Duration(seconds: 90);

    final Duration attemptTimeout = isTrackingAutomatically ? autoAttemptTimeout : manualTimeout;
    final Duration staleMax = isTrackingAutomatically ? autoStaleMax : manualStaleMax;

    Result<LocationFix, String> posResult;

    try {

      final LocationRequest request = LocationRequest(
        precision: accuracy,
        distanceFilterMeters: 0,
        timeLimit: attemptTimeout,
      );

      posResult = await _locationProvider
          .getCurrent(request)
          .timeout(attemptTimeout);
    } on TimeoutException {
      return Err("NO_FIX_TIMEOUT");
    } catch (e) {
      return Err("POSITION_ERROR: $e");
    }

    if (posResult case Err(value: final String error)) {
      return Err(error);
    }

    final LocationFix fix = posResult.unwrap();

    final DateTime nowUtc = DateTime.now().toUtc();
    final DateTime fixTs = fix.timestampUtc;

    final Duration age = nowUtc.difference(fixTs);
    if (age < Duration.zero || age > staleMax) {
      return Err("STALE_FIX: age=${age.inSeconds}s (max=${staleMax.inSeconds}s)");
    }

    final Result<LocalPoint, String> pointResult =
        await _createPointFromLocationFix(position: fix, timestamp: pointCreationTimestamp, userId: userId);

    if (pointResult case Err()) {
      return pointResult;
    }

    return pointResult;
  }

  Duration _clampDuration(Duration v, Duration min, Duration max) {
    if (v < min) {
      return min;
    }
    if (v > max) {
      return max;
    }
    return v;
  }
}