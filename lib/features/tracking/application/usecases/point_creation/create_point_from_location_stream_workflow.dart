import 'dart:async';
import 'dart:math' as math;
import 'package:dawarich/features/tracking/application/repositories/location_provider_interface.dart';
import 'package:dawarich/features/tracking/application/usecases/point_creation/create_point_usecase.dart';
import 'package:dawarich/features/tracking/application/usecases/settings/get_tracker_settings_usecase.dart';
import 'package:dawarich/features/tracking/domain/enum/auto_tracking_runtime_mode.dart';
import 'package:dawarich/features/tracking/domain/enum/location_precision.dart';
import 'package:dawarich/features/tracking/domain/models/location_fix.dart';
import 'package:dawarich/features/tracking/domain/models/location_request.dart';
import 'package:dawarich/features/tracking/domain/models/tracker_settings.dart';
import 'package:dawarich/features/tracking/domain/models/tracking_sample.dart';
import 'package:flutter/foundation.dart';
import 'package:geolocator/geolocator.dart';
import 'package:option_result/result.dart';

/// Produces a stream of [TrackingSample]s for either:
///
/// - Auto mode (trackingFrequency == 0): event-driven GPS stream whose
///   precision, distance filter and interval depend on the current
///   [AutoTrackingRuntimeMode]:
///     - passive:  powerSave (PRIORITY_NO_POWER, piggybacks other apps, zero cost)
///     - monitor:  high accuracy (real GPS, 15 s interval — short-lived transition
///                 mode; bounded cost ~12 fixes before idle timeout)
///     - active:   user-configured precision from tracker settings
///
/// - Timer mode (trackingFrequency > 0): fixed-interval recording using
///   a cached location updated by a background stream.
final class CreatePointFromLocationStreamWorkflow {
  final GetTrackerSettingsUseCase _getTrackerSettings;
  final ILocationProvider _locationProvider;
  final CreatePointUseCase _createPointFromLocationFix;

  CreatePointFromLocationStreamWorkflow(
    this._getTrackerSettings,
    this._locationProvider,
    this._createPointFromLocationFix,
  );

  /// Entry point. Reads user settings, then delegates to the appropriate
  /// sub-stream.
  ///
  /// [runtimeMode] is only used in auto mode to select the GPS precision
  /// and polling parameters. In timer mode it is ignored.
  Stream<TrackingSample> getTrackingSampleStream(
    int userId, {
    AutoTrackingRuntimeMode runtimeMode = AutoTrackingRuntimeMode.active,
  }) async* {
    if (kDebugMode) {
      debugPrint('[LocationStream] Starting location stream for user $userId');
    }

    final TrackerSettings settings = await _getTrackerSettings(userId);
    final bool isAutoMode = settings.trackingFrequency == 0;

    if (kDebugMode) {
      debugPrint(
        '[LocationStream] Settings: precision=${settings.locationPrecision}, '
        'frequency=${settings.trackingFrequency}s, '
        'minDistance=${settings.minimumPointDistance}m, '
        'autoMode=$isAutoMode, runtimeMode=$runtimeMode',
      );
    }

    if (isAutoMode) {
      yield* _autoModeStream(userId, settings, runtimeMode);
    } else {
      yield* _timerModeStream(userId, settings);
    }

    if (kDebugMode) {
      debugPrint('[LocationStream] Location stream ended');
    }
  }

  // Auto mode

  /// Auto mode stream. Emits a sample whenever the device moves enough to
  /// pass the point-recording threshold, or at most once per interval.
  ///
  /// GPS precision and polling are determined by runtimeMode:
  ///   - passive:  powerSave, 120 s interval, 150 m record distance
  ///   - monitor:  high accuracy (real GPS), no OS filter, 15 s interval, 30 m record distance
  ///   - active:   user-configured precision with standard filters
  Stream<TrackingSample> _autoModeStream(
    int userId,
    TrackerSettings settings,
    AutoTrackingRuntimeMode runtimeMode,
  ) async* {
    // Safety guard removed: passive mode now uses a PRIORITY_NO_POWER fallback stream.

    final precision = _precisionForMode(runtimeMode, settings.locationPrecision);
    final minDistance = settings.minimumPointDistance;
    final distanceFilter = _distanceFilterForMode(runtimeMode, precision, minDistance);
    final recordDistance = _recordDistanceForMode(runtimeMode, precision, minDistance);
    final interval = _intervalForMode(runtimeMode, precision, minDistance);

    final request = LocationRequest(
      precision: precision,
      distanceFilterMeters: distanceFilter,
      timeLimit: null,
      intervalDuration: interval,
    );

    if (kDebugMode) {
      debugPrint(
        '[LocationStream] Auto ($runtimeMode): precision=$precision, '
        'distanceFilter=${distanceFilter}m, recordDistance=${recordDistance}m, '
        'interval=${interval.inSeconds}s',
      );
    }

    LocationFix? lastRecordedFix;
    bool isFirstPoint = true;

    try {
      await for (final fix in _locationProvider.getLocationStream(request)) {
        // Use recordDistance (not distanceFilter) to avoid spamming low-quality
        // points on every periodic poll in passive/monitor modes.
        final bool shouldRecord =
            isFirstPoint || _shouldRecordPoint(lastRecordedFix, fix, recordDistance);

        final wasFirst = isFirstPoint;
        if (isFirstPoint) isFirstPoint = false;

        if (shouldRecord) {
          if (kDebugMode) {
            debugPrint(
              wasFirst
                  ? '[LocationStream] Auto: Recording initial fix'
                  : '[LocationStream] Auto: Recording new fix',
            );
          }

          final result = await _createPointFromLocationFix(
            fix,
            DateTime.now().toUtc(),
            userId,
          );

          if (result case Ok()) {
            lastRecordedFix = fix;
          } else if (result case Err(value: final err)) {
            if (kDebugMode) {
              debugPrint('[LocationStream] Point creation failed: $err');
            }
          }

          yield TrackingSample(fix: fix, pointResult: result);
        } else {
          if (kDebugMode) {
            debugPrint('[LocationStream] Auto: Skipping similar location');
          }
          yield TrackingSample(fix: fix, pointResult: null);
        }
      }
    } catch (e, s) {
      if (kDebugMode) debugPrint('[LocationStream] Auto mode error: $e\n$s');
    }
  }

  // Mode-aware GPS parameters

  LocationPrecision _precisionForMode(
    AutoTrackingRuntimeMode mode,
    LocationPrecision userPrecision,
  ) {
    return switch (mode) {
      AutoTrackingRuntimeMode.passive => LocationPrecision.powerSave,
      AutoTrackingRuntimeMode.monitor => LocationPrecision.high,
      AutoTrackingRuntimeMode.active => userPrecision,
    };
  }

  int _distanceFilterForMode(
    AutoTrackingRuntimeMode mode,
    LocationPrecision precision,
    int minDistance,
  ) {
    return switch (mode) {
      AutoTrackingRuntimeMode.passive => 0,
      AutoTrackingRuntimeMode.monitor => 0,
      AutoTrackingRuntimeMode.active => _distanceFilter(precision, minDistance),
    };
  }

  Duration _intervalForMode(
    AutoTrackingRuntimeMode mode,
    LocationPrecision precision,
    int minDistance,
  ) {
    return switch (mode) {
      AutoTrackingRuntimeMode.passive => const Duration(seconds: 120), // unused
      AutoTrackingRuntimeMode.monitor => const Duration(seconds: 15),
      AutoTrackingRuntimeMode.active => _interval(precision, minDistance),
    };
  }

  int _recordDistanceForMode(
    AutoTrackingRuntimeMode mode,
    LocationPrecision precision,
    int minDistance,
  ) {
    return switch (mode) {
      AutoTrackingRuntimeMode.passive => math.max(minDistance, 150),
      AutoTrackingRuntimeMode.monitor => math.max(minDistance, 30),
      AutoTrackingRuntimeMode.active => _distanceFilter(precision, minDistance),
    };
  }

  /// Distance filter (metres) for active mode.
  int _distanceFilter(LocationPrecision precision, int minDistance) {
    if (minDistance > 0) return minDistance;
    return switch (precision) {
      LocationPrecision.best => 10,
      LocationPrecision.high => 10,
      LocationPrecision.balanced => 25,
      LocationPrecision.lowPower => 50,
      LocationPrecision.powerSave => 150,
    };
  }

  /// Minimum OS-level delivery interval for active mode.
  Duration _interval(LocationPrecision precision, int minDistance) {    if (minDistance >= 100) return const Duration(seconds: 30);
    return switch (precision) {
      LocationPrecision.best => const Duration(seconds: 10),
      LocationPrecision.high => const Duration(seconds: 10),
      LocationPrecision.balanced => const Duration(seconds: 15),
      LocationPrecision.lowPower => const Duration(seconds: 30),
      LocationPrecision.powerSave => const Duration(seconds: 90),
    };
  }

  // Timer mode

  /// Timer mode: records a point at a fixed [frequencySeconds] interval,
  /// using the most recent location cached by a background stream.
  Stream<TrackingSample> _timerModeStream(
    int userId,
    TrackerSettings settings,
  ) async* {
    final precision = settings.locationPrecision;
    final minDistance = settings.minimumPointDistance;
    final frequencySeconds = settings.trackingFrequency;

    LocationFix? latestFix;
    StreamSubscription<LocationFix>? locationSub;
    Timer? periodicTimer;
    final controller = StreamController<TrackingSample>();

    // Cache stream runs at half the record interval so the fix is always reasonably fresh.
    final cacheInterval = Duration(
      seconds: (frequencySeconds / 2).ceil().clamp(1, frequencySeconds),
    );
    final staleMax = _staleMax(frequencySeconds);

    final request = LocationRequest(
      precision: precision,
      distanceFilterMeters: minDistance,
      timeLimit: null,
      intervalDuration: cacheInterval,
    );

    try {
      locationSub = _locationProvider.getLocationStream(request).listen(
        (fix) {
          latestFix = fix;
          if (kDebugMode) {
            debugPrint('[LocationStream] Cache updated: ${fix.latitude}, ${fix.longitude}');
          }
        },
        onError: (e) {
          if (kDebugMode) debugPrint('[LocationStream] Cache stream error: $e');
        },
      );

      // Seed the cache immediately so the first timer tick always has data.
      final initialResult = await _locationProvider.getCurrent(request);
      if (initialResult case Ok(value: final fix)) {
        latestFix = fix;
        final result = await _createPointFromLocationFix(
          fix,
          DateTime.now().toUtc(),
          userId,
        );
        if (result case Err(value: final err)) {
          if (kDebugMode) debugPrint('[LocationStream] Initial point creation failed: $err');
        }
        controller.add(TrackingSample(fix: fix, pointResult: result));
      }

      if (kDebugMode) {
        debugPrint(
          '[LocationStream] Timer mode: interval=${frequencySeconds}s, '
          'staleMax=${staleMax.inSeconds}s',
        );
      }

      periodicTimer = Timer.periodic(Duration(seconds: frequencySeconds), (timer) async {
        if (controller.isClosed) {
          timer.cancel();
          return;
        }

        final fix = latestFix;
        if (fix == null) {
          if (kDebugMode) debugPrint('[LocationStream] No cached fix yet, skipping tick');
          return;
        }

        final age = DateTime.now().toUtc().difference(fix.timestampUtc);
        if (age < Duration.zero || age > staleMax) {
          if (kDebugMode) {
            debugPrint(
              '[LocationStream] Cached fix too stale '
              '(age: ${age.inSeconds}s, max: ${staleMax.inSeconds}s)',
            );
          }
          controller.add(TrackingSample(
            fix: fix,
            pointResult: Err('Cached location too stale (age: ${age.inSeconds}s)'),
          ));
          return;
        }

        try {
          final result = await _createPointFromLocationFix(
            fix,
            DateTime.now().toUtc(),
            userId,
          );
          if (result case Err(value: final err)) {
            if (kDebugMode) debugPrint('[LocationStream] Point validation failed: $err');
          }
          controller.add(TrackingSample(fix: fix, pointResult: result));
        } catch (e) {
          if (kDebugMode) debugPrint('[LocationStream] Error creating point: $e');
          controller.add(TrackingSample(
            fix: fix,
            pointResult: Err('Failed to create point: $e'),
          ));
        }
      });

      yield* controller.stream;
    } catch (e, s) {
      if (kDebugMode) debugPrint('[LocationStream] Timer mode error: $e\n$s');
    } finally {
      periodicTimer?.cancel();
      await locationSub?.cancel();
      await controller.close();
    }
  }

  /// Maximum acceptable age for a cached fix before it is considered stale.
  Duration _staleMax(int frequencySeconds) =>
      Duration(seconds: (frequencySeconds * 2).clamp(30, 300));

  // Shared helpers

  /// Returns `true` if [current] is far enough or old enough from [last] to
  /// justify recording a new point.
  bool _shouldRecordPoint(
    LocationFix? last,
    LocationFix current,
    int minDistMeters,
  ) {
    if (last == null) {
      return true;
    }

    final dist = Geolocator.distanceBetween(
      last.latitude, last.longitude,
      current.latitude, current.longitude,
    );

    if (dist >= minDistMeters) {
      return true;
    }

    return current.timestampUtc.difference(last.timestampUtc).inSeconds > 60;
  }
}
