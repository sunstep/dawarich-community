import 'dart:async';

import 'package:dawarich/core/domain/models/point/api/slim_api_point.dart';
import 'package:dawarich/core/domain/models/point/local/local_point.dart';
import 'package:dawarich/core/domain/models/point/point_pair.dart';
import 'package:dawarich/core/presentation/safe_change_notifier.dart';
import 'package:dawarich/features/batch/application/usecases/watch_current_batch_usecase.dart';
import 'package:dawarich/features/settings/application/usecases/get_timeline_distance_threshold_usecase.dart';
import 'package:dawarich/features/timeline/application/helpers/timeline_points_processor.dart';
import 'package:dawarich/features/timeline/application/usecases/get_default_map_center_usecase.dart';
import 'package:dawarich/features/timeline/application/usecases/load_timeline_usecase.dart';
import 'package:dawarich/features/timeline/domain/models/day_map_data.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_map_animations/flutter_map_animations.dart';
import 'package:geolocator/geolocator.dart';
import 'package:intl/intl.dart';
import 'package:latlong2/latlong.dart';


final class TimelineViewModel extends ChangeNotifier with SafeChangeNotifier {
  final int userId;
  final LoadTimelineUseCase _loadTimelineUseCase;
  final TimelinePointsProcessor _timelinePointsProcessor;
  final GetDefaultMapCenterUseCase _getDefaultMapCenterUseCase;
  final WatchCurrentBatchUseCase _watchCurrentBatch;
  final GetTimelineDistanceThresholdUseCase _getDistanceThreshold;

  AnimatedMapController? animatedMapController;

  TimelineViewModel(
    this.userId,
    this._loadTimelineUseCase,
    this._timelinePointsProcessor,
    this._getDefaultMapCenterUseCase,
    this._watchCurrentBatch,
    this._getDistanceThreshold,
  );

  bool _isLoading = true;
  bool get isLoading => _isLoading;

  int _distanceThreshold = 50;

  LatLng? _currentLocation;
  LatLng? get currentLocation => _currentLocation;

  LatLng? _pendingCenter;
  bool _mapReady = false;
  LatLng? _lastCameraTarget;
  final double _epsilon = 1e-7;
  final double _epsilonMeters = 5.0;

  /// Timestamp (ms since epoch) of the chronologically last API point loaded
  /// for the current day.  Used as the cutoff when rebuilding local points so
  /// batch points that already exist in the API never overlap the orange trail.
  int? _lastApiTimestampMs;

  DateTime _selectedDate = DateTime.now();
  DateTime get selectedDate => _selectedDate;

  StreamSubscription<List<LocalPoint>>? _localPointSubscription;

  /// Tracks the last-seen batch size so we can detect a post-upload cleanup
  /// (large drop) and silently reload the API track.
  int _lastBatchSize = 0;

  List<LatLng> _points = [];
  List<LatLng> get points => _points;

  List<LocalPoint> _lastLocalBatch = const [];

  List<LatLng> _localPoints = [];
  List<LatLng> get localPoints => _localPoints;

  void setIsLoading(bool value) {
    _isLoading = value;
    safeNotifyListeners();
  }

  void setCurrentLocation(LatLng currentLocation) {
    _currentLocation = currentLocation;
    safeNotifyListeners();
  }

  void setSelectedDate(DateTime selectedDate) {
    _selectedDate = selectedDate;
    safeNotifyListeners();
    _rebuildLocalPoints();
  }

  void setPoints(List<LatLng> points) {
    _points = points;
    safeNotifyListeners();
  }

  void addPoints(List<LatLng> points) {
    _points.addAll(points);
    safeNotifyListeners();
  }

  void setLocalPoints(List<LatLng> points) {
    _localPoints = points;
    safeNotifyListeners();
  }

  void addLocalPoints(List<LatLng> points) {
    _localPoints.addAll(points);
    safeNotifyListeners();
  }

  void clearPoints() {
    _points.clear();
    _lastApiTimestampMs = null;
    safeNotifyListeners();
  }

  void markMapReady() {
    if (isDisposed) return;
    _mapReady = true;

    final pending = _pendingCenter;
    if (pending != null) {
      _pendingCenter = null;
      // Clear the target guard so the deferred call in _animateTo isn't
      // blocked by a stale _lastCameraTarget value.
      _lastCameraTarget = null;
      _animateTo(pending);
    }
  }

  void setAnimatedMapController(AnimatedMapController controller) {
    if (isDisposed) return;

    final bool wasNull = animatedMapController == null;
    animatedMapController ??= controller;

    if (!wasNull) {
      return;
    }

    final pendingCenter = _pendingCenter;

    if (_mapReady && pendingCenter != null) {
      _animateTo(pendingCenter);
      _pendingCenter = null;
    }
  }

  bool _sameTarget(LatLng a, LatLng b) =>
      (a.latitude - b.latitude).abs() < _epsilon &&
      (a.longitude - b.longitude).abs() < _epsilon;

  void _animateTo(LatLng dest) {
    // Don't animate if disposed
    if (isDisposed) return;

    if (_lastCameraTarget != null && _sameTarget(_lastCameraTarget!, dest)) {
      return;
    }

    if (!_mapReady || animatedMapController == null) {
      _pendingCenter = dest;
      return;
    }

    // Record the target NOW (before the postFrameCallback) so that rapid
    // consecutive calls (e.g., setPoints → setLocalPoints → animateTo) don't
    // all enqueue duplicate animation frames.
    _lastCameraTarget = dest;

    // Defer the actual camera move until after the current frame's build phase
    // has completed.  notifyListeners() (called just before _animateTo) marks
    // the ListenableBuilder dirty and schedules a rebuild; if we call
    // animateTo() synchronously, FlutterMap.didUpdateWidget fires on the very
    // next frame and can reset / cancel the in-flight animation.
    // addPostFrameCallback guarantees we start moving after that rebuild.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (isDisposed) return;
      final controller = animatedMapController;
      if (controller == null) return;

      try {
        final double zoom = controller.mapController.camera.zoom;
        controller.animateTo(
          dest: dest,
          zoom: zoom,
          curve: Curves.easeInOut,
          duration: const Duration(milliseconds: 500),
        );
      } catch (e) {
        if (kDebugMode) {
          debugPrint('[TimelineViewModel] _animateTo failed: $e');
        }
      }
    });
  }

  Future<void> initialize() async {
    _distanceThreshold = await _getDistanceThreshold(userId);
    _resolveAndSetInitialLocation();
    await loadToday();

    if (isDisposed) {
      return;
    }

    try {
      final batchStream = _watchCurrentBatch(userId);
      _localPointSubscription = batchStream.listen((points) {
        if (isDisposed) {
          return;
        }

        final previousSize = _lastBatchSize;
        final previousBatch = _lastLocalBatch;
        _lastBatchSize = points.length;
        _lastLocalBatch = points;

        _rebuildLocalPoints(cutoffMs: _lastApiTimestampMs);

        // A large drop means the upload workflow just ran its cleanup.
        // Move the uploaded local points directly into the API track so the
        // transition is seamless without any network call.
        final significantDrop =
            previousSize > 5 && points.length < previousSize ~/ 2;

        if (significantDrop && isTodaySelected()) {
          _mergeUploadedLocalPointsIntoApiTrack(previousBatch);
        }
      });
    } catch (e, s) {
      if (kDebugMode) {
        debugPrint("[TimelineViewModel] watchCurrentBatch failed: $e\n$s");
      }
    }
  }


  /// Moves uploaded local points directly into the API track so the blue trail
  /// fills in immediately without a network reload.
  void _mergeUploadedLocalPointsIntoApiTrack(List<LocalPoint> uploadedBatch) {
    final d = DateTime(_selectedDate.year, _selectedDate.month, _selectedDate.day);
    final cutoffMs = _lastApiTimestampMs;

    final toMerge = uploadedBatch.where((p) {
      final ts = p.properties.recordTimestamp;
      final day = DateTime(ts.year, ts.month, ts.day);
      if (day != d) {
        return false;
      }
      if (cutoffMs != null && ts.millisecondsSinceEpoch <= cutoffMs) {
        return false;
      }
      return true;
    }).toList()
      ..sort((a, b) =>
          a.properties.recordTimestamp.compareTo(b.properties.recordTimestamp));

    if (toMerge.isEmpty) {
      return;
    }

    final merged = toMerge
        .map((p) => LatLng(p.geometry.latitude, p.geometry.longitude))
        .toList();

    // Advance the cutoff so these points are excluded from the orange trail.
    _lastApiTimestampMs =
        toMerge.last.properties.recordTimestamp.millisecondsSinceEpoch;

    setPoints([..._points, ...merged]);
    _rebuildLocalPoints(cutoffMs: _lastApiTimestampMs);
  }

  void _rebuildLocalPoints({int? cutoffMs}) {
    final d = DateTime(_selectedDate.year, _selectedDate.month, _selectedDate.day);

    final slim = _lastLocalBatch.where((p) {
      final ts = p.properties.recordTimestamp;
      final day = DateTime(ts.year, ts.month, ts.day);
      if (day != d) {
        return false;
      }

      if (cutoffMs != null && ts.millisecondsSinceEpoch <= cutoffMs) {
        return false;
      }
      return true;
    }).map((p) => SlimApiPoint(
      latitude:  p.geometry.latitude.toString(),
      longitude: p.geometry.longitude.toString(),
      timestamp: p.properties.recordTimestamp.millisecondsSinceEpoch ~/ 1000,
    )).toList();

    slim.sort((a, b) => a.timestamp!.compareTo(b.timestamp!));

    final List<LatLng> local = _timelinePointsProcessor.processPoints(
      slim,
      distanceThresholdMeters: _distanceThreshold,
    );

    List<LatLng> stitched = _stitchToApiPoints(local);


    setLocalPoints(stitched);
  }

  /// Returns [local] prepended with the last API point when the two trails
  /// are more than [_epsilonMeters] apart, bridging any spatial gap.
  List<LatLng> _stitchToApiPoints(List<LatLng> local) {
    if (_points.isEmpty || local.isEmpty) return local;

    final lastApiPoint = _points.last;
    final firstLocalPoint = local.first;

    final distance = PointPair(lastApiPoint, firstLocalPoint).calculateDistance();
    if (distance > _epsilonMeters) {
      return [lastApiPoint, ...local];
    }
    return local;
  }

  @override
  void dispose() {
    if (kDebugMode) {
      debugPrint("[TimelineViewModel] Disposing...");
    }

    _localPointSubscription?.cancel();
    super.dispose();
  }

  Future<void> _resolveAndSetInitialLocation() async {
    final center = await _getDefaultMapCenterUseCase.call();
    if (isDisposed) return;
    setCurrentLocation(center);
  }

  Future<void> getAndSetPoints() async {
    final DayMapData day = await _loadTimelineUseCase(selectedDate, userId);
    if (isDisposed) return;

    // Store the cutoff so the live-batch subscription uses the same boundary.
    _lastApiTimestampMs = day.lastTimestampMs;

    setPoints(day.points);
    _rebuildLocalPoints(cutoffMs: day.lastTimestampMs);

    // Reset so the deduplication guard never blocks an explicit day-load animation.
    _lastCameraTarget = null;

    if (isTodaySelected()) {
      // Today: animate to the most recent point (live local points take priority)
      if (_localPoints.isNotEmpty) {
        _animateTo(_localPoints.last);
      } else if (day.points.isNotEmpty) {
        _animateTo(day.points.last);
      }
    } else {
      // Other days: animate to the first point of the day
      if (day.points.isNotEmpty) {
        _animateTo(day.points.first);
      }
    }
  }

  Future<void> loadPreviousDay() async {
    if (isDisposed) return;
    try {
      setIsLoading(true);
      clearPoints();

      DateTime previousDay = selectedDate.subtract(const Duration(days: 1));
      setSelectedDate(
          DateTime(previousDay.year, previousDay.month, previousDay.day));

      await getAndSetPoints();
    } finally {
      if (!isDisposed) setIsLoading(false);
    }
  }

  Future<void> loadToday() async {
    if (isDisposed) return;
    try {
      setIsLoading(true);
      clearPoints();

      await getAndSetPoints();
    } finally {
      if (!isDisposed) setIsLoading(false);
    }
  }

  Future<void> loadNextDay() async {
    if (isDisposed) return;
    try {
      setIsLoading(true);
      clearPoints();

      DateTime nextDay = selectedDate.add(const Duration(days: 1));
      setSelectedDate(DateTime(nextDay.year, nextDay.month, nextDay.day));

      await getAndSetPoints();
    } finally {
      if (!isDisposed) setIsLoading(false);
    }
  }

  Future<void> processNewDate(DateTime pickedDate) async {
    if (isDisposed) return;
    if (pickedDate == selectedDate) {
      return;
    }

    try {
      setIsLoading(true);
      clearPoints();

      setSelectedDate(pickedDate);

      await getAndSetPoints();
    } finally {
      if (!isDisposed) setIsLoading(false);
    }
  }

  bool isTodaySelected() {
    final today = DateTime.now();
    return selectedDate.year == today.year &&
        selectedDate.month == today.month &&
        selectedDate.day == today.day;
  }

  String displayDate() {
    final DateTime now = DateTime.now();
    final DateTime today = DateTime(now.year, now.month, now.day);
    final DateTime yesterday = today.subtract(const Duration(days: 1));

    if (isTodaySelected()) {
      return "Today";
    } else if (selectedDate == yesterday) {
      return "Yesterday";
    } else {
      return DateFormat('EEE, MMM d yyyy').format(selectedDate);
    }
  }

  Future<void> zoomIn() async {
    if (isDisposed) return;
    await animatedMapController?.animatedZoomIn();
  }

  Future<void> zoomOut() async {
    if (isDisposed) return;
    await animatedMapController?.animatedZoomOut();
  }

  Future<void> centerMap() async {
    if (isDisposed) return;

    if (!_mapReady || animatedMapController == null) {
      return;
    }

    LatLng? userLocation;
    try {
      final last = await Geolocator.getLastKnownPosition();
      if (last != null) {
        userLocation = LatLng(last.latitude, last.longitude);
      }
    } catch (_) {}

    if (isDisposed || userLocation == null) {
      return;
    }

    final controller = animatedMapController;
    if (controller == null) {
      return;
    }

    final double zoom = controller.mapController.camera.zoom;

    controller.animateTo(
      dest: userLocation,
      zoom: zoom,
      curve: Curves.easeInOut,
      duration: const Duration(milliseconds: 500),
    );

    _lastCameraTarget = userLocation;
  }
}
