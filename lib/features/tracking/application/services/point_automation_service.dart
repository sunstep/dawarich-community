import 'dart:async';
import 'package:dawarich/core/data/repositories/local_point_repository_interfaces.dart';
import 'package:dawarich/features/batch/application/usecases/batch_upload_workflow_usecase.dart';
import 'package:dawarich/features/batch/application/usecases/get_current_batch_usecase.dart';
import 'package:dawarich/features/tracking/application/interfaces/tracker_engine_interface.dart';
import 'package:dawarich/features/tracking/application/usecases/get_batch_point_count_usecase.dart';
import 'package:dawarich/features/tracking/application/usecases/notifications/show_tracker_notification_usecase.dart';
import 'package:dawarich/features/tracking/application/usecases/point_creation/create_point_usecase.dart';
import 'package:dawarich/features/tracking/application/usecases/point_creation/store_point_usecase.dart';
import 'package:dawarich/features/tracking/application/usecases/settings/get_tracker_settings_usecase.dart';
import 'package:dawarich/features/tracking/application/usecases/settings/watch_tracker_settings_usecase.dart';
import 'package:dawarich/features/tracking/domain/models/location_fix.dart';
import 'package:dawarich/features/tracking/domain/models/tracker_settings.dart';
import 'package:flutter/foundation.dart';
import 'package:option_result/option_result.dart';

final class PointAutomationService {
  bool get isTracking => _isTracking;

  final ITrackerEngine _trackerEngine;
  final CreatePointUseCase _createPoint;
  final StorePointUseCase _storePoint;
  final GetBatchPointCountUseCase _getBatchPointCount;
  final ShowTrackerNotificationUseCase _showTrackerNotification;
  final GetCurrentBatchUseCase _getCurrentBatch;
  final BatchUploadWorkflowUseCase _batchUploadWorkflow;
  final GetTrackerSettingsUseCase _getTrackerSettings;
  final WatchTrackerSettingsUseCase _watchTrackerSettings;
  final IPointLocalRepository _localPointRepository;

  bool _isTracking = false;
  bool _writeBusy = false;
  bool _uploadBusy = false;

  int? _currentUserId;
  TrackerSettings? _currentSettings;

  StreamSubscription<LocationFix>? _locationFixSub;
  StreamSubscription<TrackerSettings>? _settingsWatchSub;
  StreamSubscription<int>? _batchCountSub;

  DateTime? _lastPointTime;
  int _lastKnownBatchCount = 0;

  PointAutomationService(
    this._trackerEngine,
    this._createPoint,
    this._storePoint,
    this._getBatchPointCount,
    this._showTrackerNotification,
    this._getCurrentBatch,
    this._batchUploadWorkflow,
    this._getTrackerSettings,
    this._watchTrackerSettings,
    this._localPointRepository,
  );

  Future<void> startTracking(int userId) async {
    if (_isTracking) {
      return;
    }

    if (kDebugMode) {
      debugPrint('[PointAutomation] Starting automatic tracking...');
    }

    final TrackerSettings settings = await _getTrackerSettings(userId);

    await _trackerEngine.configure(settings);

    _currentUserId = userId;
    _currentSettings = settings;
    _lastPointTime = null;
    _lastKnownBatchCount = 0;

    _startLocationFixWatch(userId);

    await _trackerEngine.startTracking(settings);

    _isTracking = true;

    await _refreshNotification(userId);

    _startSettingsWatch(userId);
    _startBatchCountWatch(userId);
  }

  Future<void> stopTracking() async {
    if (!_isTracking) {
      return;
    }

    if (kDebugMode) {
      debugPrint('[PointAutomation] Stopping automatic tracking...');
    }

    await _trackerEngine.stopTracking();

    _isTracking = false;
    _currentUserId = null;
    _currentSettings = null;
    _lastPointTime = null;
    _lastKnownBatchCount = 0;

    await _locationFixSub?.cancel();
    _locationFixSub = null;

    await _settingsWatchSub?.cancel();
    _settingsWatchSub = null;

    await _batchCountSub?.cancel();
    _batchCountSub = null;
  }

  Future<void> restartTracking() async {
    if (!_isTracking || _currentUserId == null) {
      return;
    }

    final int userId = _currentUserId!;

    if (kDebugMode) {
      debugPrint('[PointAutomation] Restarting tracking...');
    }

    await stopTracking();
    await startTracking(userId);
  }

  void _startLocationFixWatch(int userId) {
    _locationFixSub?.cancel();

    _locationFixSub = _trackerEngine.watchLocations().listen(
      (locationFix) async {
        await _handleLocationFix(
          locationFix: locationFix,
          userId: userId,
        );
      },
      onError: (Object error, StackTrace stackTrace) {
        debugPrint(
          '[PointAutomation] Location fix stream error: '
          '$error\n$stackTrace',
        );
      },
    );
  }

  Future<void> _handleLocationFix({
    required LocationFix locationFix,
    required int userId,
  }) async {
    if (_writeBusy) {
      if (kDebugMode) {
        debugPrint('[PointAutomation] Skipping location fix, write busy.');
      }

      return;
    }

    _writeBusy = true;

    try {
      final pointResult = await _createPoint(
        position: locationFix,
        timestamp: DateTime.now().toUtc(),
        userId: userId,
      );

      if (pointResult case Ok(value: final point)) {
        final storeResult = await _storePoint(point);

        if (storeResult case Ok()) {
          _lastPointTime = DateTime.now().toUtc();
          _refreshNotificationWithCount(_lastKnownBatchCount);
        } else if (storeResult case Err(value: final message)) {
          debugPrint('[PointAutomation] Failed to store point: $message');
        }
      } else if (pointResult case Err(value: final message)) {
        debugPrint('[PointAutomation] Point creation error: $message');
      }
    } catch (error, stackTrace) {
      debugPrint(
        '[PointAutomation] Error handling location fix: '
        '$error\n$stackTrace',
      );
    } finally {
      _writeBusy = false;
    }
  }

  // ── Notification ───────────────────────────────────────────────────────
  Future<void> _refreshNotification(int userId) async {
    try {
      final batchCount = await _getBatchPointCount(userId);
      _refreshNotificationWithCount(batchCount);
    } catch (e, s) {
      debugPrint("[PointAutomation] Notification refresh error: $e\n$s");
    }
  }

  /// Updates the notification using an already-known batch count,
  /// avoiding an extra DB query.
  void _refreshNotificationWithCount(int batchCount) {
    try {
      String body;
      if (_lastPointTime != null) {
        final lastTime = _lastPointTime!.toLocal();
        final lastTimeStr = '${lastTime.hour.toString().padLeft(2, '0')}:'
            '${lastTime.minute.toString().padLeft(2, '0')}:'
            '${lastTime.second.toString().padLeft(2, '0')}';
        body = 'Last point: $lastTimeStr • $batchCount in batch';
      } else {
        body = 'Waiting for location... • $batchCount in batch';
      }

      _showTrackerNotification(
        title: 'Tracking active',
        body: body,
      );
    } catch (e, s) {
      debugPrint("[PointAutomation] Notification refresh error: $e\n$s");
    }
  }

  // ── Reactive batch count → threshold upload ────────────────────────────

  /// Watches the un-uploaded point count via a Drift reactive stream.
  /// Every time the count changes (point stored, upload completed, etc.)
  /// we check if the threshold is met and upload. Also refreshes the
  /// notification so the user always sees the current batch count.
  void _startBatchCountWatch(int userId) {
    _batchCountSub?.cancel();

    final stream = _localPointRepository.watchBatchPointCount(userId);

    _batchCountSub = stream.listen(
      (count) async {
        // Cache for notification updates.
        _lastKnownBatchCount = count;

        // Update notification reactively — only when the count actually changes.
        _refreshNotificationWithCount(count);

        final settings = _currentSettings;
        if (settings == null) return;

        if (count >= settings.pointsPerBatch) {
          if (kDebugMode) {
            debugPrint(
              '[PointAutomation] Batch count $count >= ${settings.pointsPerBatch} '
              '— uploading reactively',
            );
          }
          await _uploadCurrentBatch(userId);
        }
      },
      onError: (e) {
        debugPrint('[PointAutomation] Batch count watch error: $e');
      },
    );
  }

  // ── Upload helper ──────────────────────────────────────────────────────

  /// Fetches the current un-uploaded batch and uploads it.
  /// Guarded by [_uploadBusy] to prevent overlapping uploads.
  Future<void> _uploadCurrentBatch(int userId) async {
    if (_uploadBusy) return;
    _uploadBusy = true;

    try {
      final batch = await _getCurrentBatch(userId);
      if (batch.isEmpty) return;

      final result = await _batchUploadWorkflow(batch, userId);
      if (result case Ok()) {
        if (kDebugMode) {
          debugPrint('[PointAutomation] Batch upload successful.');
        }
      } else if (result case Err(value: final err)) {
        debugPrint('[PointAutomation] Batch upload failed: $err');
      }
    } catch (e, s) {
      debugPrint('[PointAutomation] Upload error: $e\n$s');
    } finally {
      _uploadBusy = false;
    }
  }

  // ── Settings watch ─────────────────────────────────────────────────────

  void _startSettingsWatch(int userId) {
    _settingsWatchSub?.cancel();

    if (kDebugMode) {
      debugPrint(
          '[PointAutomation] Starting settings watch for userId: $userId');
    }

    _settingsWatchSub = _watchTrackerSettings(userId).listen(
      (settings) async {
        final old = _currentSettings;
        _currentSettings = settings;

        if (old != null && _settingsRequireEngineUpdate(old, settings)) {
          if (kDebugMode) {
            debugPrint(
                '[PointAutomation] Settings changed, updating tracker engine...');
          }

          await _trackerEngine.updateConfiguration(settings);

          if (old.trackingMode != settings.trackingMode) {
            await _trackerEngine.stopTracking();
            await _trackerEngine.startTracking(settings);
          }
        }
      },
      onError: (error) {
        debugPrint('[PointAutomation] Settings watch error: $error');
      },
    );
  }

  // trackingMode is derived from trackingFrequency for now,
  // so comparing trackingFrequency also covers mode changes.
  bool _settingsRequireEngineUpdate(
      TrackerSettings old, TrackerSettings current) {
    return old.trackingFrequency != current.trackingFrequency ||
        old.locationPrecision != current.locationPrecision ||
        old.minimumPointDistance != current.minimumPointDistance;
  }
}
