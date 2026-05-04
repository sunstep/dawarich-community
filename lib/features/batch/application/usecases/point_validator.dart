import 'dart:io';

import 'package:dawarich/core/domain/models/point/local/local_point.dart';
import 'package:dawarich/core/domain/models/point/point_pair.dart';
import 'package:dawarich/features/tracking/application/usecases/settings/get_tracker_settings_usecase.dart';
import 'package:dawarich/features/tracking/domain/enum/location_precision.dart';
import 'package:dawarich/features/tracking/domain/models/last_point.dart';
import 'package:dawarich/features/tracking/domain/models/tracker_settings.dart';
import 'package:latlong2/latlong.dart';
import 'package:option_result/option_result.dart';


final class PointValidator {

  final GetTrackerSettingsUseCase _getTrackerSettings;

  PointValidator(this._getTrackerSettings);

  Future<Result<(), String>> validatePoint(
      LocalPoint point,
      Option<LastPoint> lastPointOpt,
      int userId,
      ) async {
    final Future<bool> accurateF = _isPointAccurateEnough(point, userId);

    if (lastPointOpt case None()) {
      final bool isAccurate = await accurateF;

      if (!isAccurate) {
        return const Err("Point does not meet the required accuracy.");
      }

      return const Ok(());
    }

    final LastPoint lastPoint = (lastPointOpt as Some<LastPoint>).value;

    final Future<bool> newerF = _isPointNewerThanLastPoint(point, lastPoint);
    final Future<bool> distanceF =
    _isPointDistanceGreaterThanPreference(point, lastPoint, userId);

    final List<bool> results = await Future.wait<bool>([
      newerF,
      distanceF,
      accurateF,
    ]);

    final bool isNewer = results[0];
    final bool isDistance = results[1];
    final bool isAccurate = results[2];

    if (!isNewer) {
      return const Err("Point is not newer than the last stored point.");
    }

    if (!isDistance) {
      return const Err("Point is not sufficiently distant from the last point.");
    }

    if (!isAccurate) {
      return const Err("Point does not meet the required accuracy.");
    }

    return const Ok(());
  }

  Future<bool> _isPointNewerThanLastPoint(LocalPoint point, LastPoint lastPoint) async {
    // TODO (Future update):
    // Currently this check always passes because `_constructPoint`
    // guarantees monotonically increasing timestamps by falling back
    // to DateTime.now() if the GPS timestamp is stale.
    //
    // When we add support for last-known points (e.g. from Geolocator or
    // other apps), we need a smarter duplicate heuristic instead of just
    // comparing timestamps. Otherwise, valid "older" provider points could
    // be rejected.
    //
    // Future plan:
    // - Introduce providerTimestamp alongside stored timestamp.
    // - Replace this check with a heuristic:
    //     (a) providerTimestamp > last.providerTimestamp OR
    //     (b) significant distance moved OR
    //     (c) better accuracy
    // This will prevent duplicates without dropping legitimate points.
    //
    // For now we keep this method in place, since it does no harm and
    // preserves validation structure.

    DateTime candidateTime = point.properties.recordTimestamp;
    DateTime lastTime = lastPoint.timestamp;

    final bool answer = candidateTime.isAfter(lastTime);

    return answer;
  }

  Future<bool> _isPointDistanceGreaterThanPreference(LocalPoint point, LastPoint lastPoint, int userId) async {
    bool answer = true;
    final TrackerSettings settings = await _getTrackerSettings(userId);
    final int minimumDistance = settings.minimumPointDistance;

    double currentPointLongitude = point.geometry.longitude;
    double currentPointLatitude = point.geometry.latitude;

    LatLng lastPointCoordinates =
    LatLng(lastPoint.latitude, lastPoint.longitude);
    LatLng currentPointCoordinates =
    LatLng(currentPointLatitude, currentPointLongitude);

    PointPair pair = PointPair(lastPointCoordinates, currentPointCoordinates);
    double distance = pair.calculateDistance();

    answer = distance >= minimumDistance;

    return answer;
  }

  Future<bool> _isPointAccurateEnough(LocalPoint candidate, int userId) async {

    bool answer = false;

    final TrackerSettings settings = await _getTrackerSettings(userId);
    final LocationPrecision requiredAccuracy = settings.locationPrecision;

    double requiredAccuracyMeters = _getAccuracyThreshold(requiredAccuracy);

    answer = candidate.properties.horizontalAccuracy < requiredAccuracyMeters;

    return answer;
  }

  double _getAccuracyThreshold(LocationPrecision precision) {
    if (Platform.isIOS) {
      switch (precision) {
        case LocationPrecision.powerSave:
          return 3000; // iOS Lowest accuracy (cell-tower)
        case LocationPrecision.lowPower:
          return 1000; // iOS Low accuracy
        case LocationPrecision.balanced:
          return 100; // iOS Medium accuracy
        case LocationPrecision.high:
          return 10; // iOS High accuracy
        case LocationPrecision.best:
          return 5; // iOS Best accuracy
      }
    } else {
      switch (precision) {
        case LocationPrecision.powerSave:
          return 2000; // Android Lowest power accuracy (cell-tower)
        case LocationPrecision.lowPower:
          return 500; // Android Low power accuracy
        case LocationPrecision.balanced:
          return 100; // Android Balanced power accuracy
        case LocationPrecision.high:
          return 100; // Android High accuracy
        case LocationPrecision.best:
          return 50; // Android Best accuracy
      }
    }
  }

}