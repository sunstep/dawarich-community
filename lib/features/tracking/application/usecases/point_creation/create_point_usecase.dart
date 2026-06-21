import 'package:dawarich/core/data/repositories/local_point_repository_interfaces.dart';
import 'package:dawarich/core/domain/models/point/local/local_point.dart';
import 'package:dawarich/core/domain/models/point/local/local_point_geometry.dart';
import 'package:dawarich/core/domain/models/point/local/local_point_properties.dart';
import 'package:dawarich/core/network/repositories/api_point_repository_interfaces.dart';
import 'package:dawarich/features/batch/application/usecases/point_validator.dart';
import 'package:dawarich/features/tracking/application/converters/track_converter.dart';
import 'package:dawarich/features/tracking/application/repositories/hardware_repository_interfaces.dart';
import 'package:dawarich/features/tracking/application/repositories/i_track_repository.dart';
import 'package:dawarich/features/tracking/data/data_transfer_objects/track_dto.dart';
import 'package:dawarich/features/tracking/domain/enum/battery_state.dart';
import 'package:dawarich/features/tracking/domain/enum/tracking_mode.dart';
import 'package:dawarich/features/tracking/domain/models/last_point.dart';
import 'package:dawarich/features/tracking/domain/models/location_fix.dart';
import 'package:dawarich/features/tracking/domain/models/point_context.dart';
import 'package:dawarich/features/tracking/domain/models/track.dart';
import 'package:flutter/foundation.dart';
import 'package:option_result/option_result.dart';

final class CreatePointUseCase {

  final IHardwareRepository _hardwareRepository;
  final IPointLocalRepository _localPointRepository;
  final ITrackRepository _trackRepository;
  final PointValidator _pointValidator;
  final IApiPointRepository _apiPointRepository;

  CreatePointUseCase(
      this._hardwareRepository,
      this._localPointRepository,
      this._trackRepository,
      this._pointValidator,
      this._apiPointRepository,
  );

  /// Creates a full point using a position object.
  Future<Result<LocalPoint, String>> call({
    required LocationFix position,
    required DateTime timestamp,
    required int userId}) async {

    final PointContext context = await _getPointContext(userId);

    LocalPoint point = _constructPoint(
      position,
      context,
      userId,
      timestamp,
    );

    final Option<LastPoint> lastPoint = await _getLastPointWithApiFallback(userId);
    Result<(), String> validationResult = await _pointValidator.validatePoint(point, lastPoint, userId);

    if (validationResult case Err(value: String validationError)) {
      return Err("Point validation did not pass: $validationError");
    }

    return Ok(point);
  }

  /// Gets the last point from local storage, falling back to API if not found.
  Future<Option<LastPoint>> _getLastPointWithApiFallback(int userId) async {
    // First try local
    final localResult = await _localPointRepository.getLastPoint(userId);

    if (localResult case Some()) {
      return localResult;
    }

    // No local point, try fetching from API
    if (kDebugMode) {
      debugPrint("[CreatePoint] No local reference point, fetching from API...");
    }

    try {
      final apiResult = await _apiPointRepository.fetchLastPoint();

      if (apiResult case Some(value: final apiPoint)) {
        // Convert API point to LastPoint for validation
        final lat = double.tryParse(apiPoint.latitude ?? '');
        final lon = double.tryParse(apiPoint.longitude ?? '');
        final ts = apiPoint.timestamp;

        if (lat != null && lon != null && ts != null) {
          final lastPoint = LastPoint(
            latitude: lat,
            longitude: lon,
            timestamp: DateTime.fromMillisecondsSinceEpoch(ts * 1000, isUtc: true),
          );

          if (kDebugMode) {
            debugPrint("[CreatePoint] Got reference point from API");
          }

          return Some(lastPoint);
        }
      }
    } catch (e) {
      if (kDebugMode) {
        debugPrint("[CreatePoint] API fallback failed: $e");
      }
    }

    // No reference point available - first point scenario
    if (kDebugMode) {
      debugPrint("[CreatePoint] No reference point available (first point)");
    }
    return const None();
  }

  LocalPoint _constructPoint(
      LocationFix fix, PointContext context, int userId, DateTime recordTimestamp) {
    final geometry = LocalPointGeometry(
        type: "Point",
        longitude: fix.longitude,
        latitude: fix.latitude
    );

    final properties = LocalPointProperties(
      batteryState: _batteryStateToString(context.batteryState),
      batteryLevel: context.batteryLevel,
      wifi: context.wifi ?? '',
      recordTimestamp: recordTimestamp,
      providerTimestamp: fix.timestampUtc,
      horizontalAccuracy: fix.hAccuracyMeters,
      verticalAccuracy: fix.altitudeAccuracyMeters,
      altitude: fix.altitudeMeters,
      speed: fix.speedMps,
      speedAccuracy: fix.speedAccuracyMps,
      course: fix.headingDegrees,
      courseAccuracy: fix.headingAccuracyDegrees,
      trackId: context.trackId,
      deviceId: context.deviceId,
    );

    return LocalPoint(
        id: 0,
        type: "Feature",
        geometry: geometry,
        properties: properties,
        userId: userId,
        isUploaded: false);
  }

  String _batteryStateToString(BatteryState state) {
    return switch (state) {
      BatteryState.charging => 'charging',
      BatteryState.discharging => 'discharging',
      BatteryState.full => 'full',
      BatteryState.connectedNotCharging => 'connected_not_charging',
      BatteryState.unknown => 'unknown',
    };
  }

  Future<PointContext> _getPointContext(int userId) async {

    final Future<String?> wifiF = _hardwareRepository.getWiFiStatus();
    final Future<BatteryState> batteryStateF = _hardwareRepository.getBatteryState();
    final Future<double> batteryLevelF = _hardwareRepository.getBatteryLevel();
    final Future<String> deviceIdF = _hardwareRepository.getDeviceModel();
    final Future<Option<TrackDto>> trackResultF =
    _trackRepository.getActiveTrack(userId);

    final futureResults = await Future.wait([
      wifiF,
      batteryStateF,
      batteryLevelF,
      deviceIdF,
      trackResultF,
    ]);

    final String? wifi = futureResults[0] as String?;
    final BatteryState batteryState = futureResults[1] as BatteryState;
    final double batteryLevel = futureResults[2] as double;
    final String deviceId = futureResults[3] as String;
    final Option<TrackDto> trackResult = futureResults[4] as Option<TrackDto>;

    String? trackId;
    if (trackResult case Some(value: TrackDto trackDto)) {
      Track track = trackDto.toEntity();
      trackId = track.trackId;
    }

    return PointContext(
      deviceId: deviceId,
      trackId: trackId,
      wifi: wifi,
      batteryState: batteryState,
      batteryLevel: batteryLevel,
    );
  }


}