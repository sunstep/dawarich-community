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
import 'package:dawarich/features/tracking/application/usecases/settings/save_tracker_settings_usecase.dart';
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
  final SaveTrackerSettingsUseCase _saveTrackerSettings;
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
    this._saveTrackerSettings,
    this._watchTrackerSettings,
    this._localPointRepository,
  );

  Future<Result<(), String>> startTracking(int userId) async {
    if (_isTracking) {
      return const Ok(());
    }

    if (kDebugMode) {
      debugPrint('[PointAutomation] Starting automatic tracking...');
    }

    try {
      final TrackerSettings settings = await _getTrackerSettings(userId);
      final TrackerSettings updatedSettings = settings.copyWith(
        automaticTracking: true,
      );

      await _trackerEngine.configure(updatedSettings);

      _currentUserId = userId;
      _currentSettings = updatedSettings;
      _lastPointTime = null;
      _lastKnownBatchCount = 0;

      _startLocationFixWatch(userId);

      await _trackerEngine.startTracking(updatedSettings);

      await _persistAutomaticTracking(userId, true);

      _isTracking = true;

      unawaited(_refreshNotification(userId));

      _startSettingsWatch(userId);
      _startBatchCountWatch(userId);

      return const Ok(());
    } catch (e, st) {
      if (kDebugMode) {
        debugPrint('[PointAutomationService] Failed to start tracking: $e');
        debugPrint('$st');
      }

      await _cleanupAfterFailedStart();

      try {
        await _persistAutomaticTracking(userId, false);
      } catch (rollbackError, rollbackStackTrace) {
        if (kDebugMode) {
          debugPrint(
            '[PointAutomationService] Failed to rollback tracking setting: '
                '$rollbackError',
          );
          debugPrint('$rollbackStackTrace');
        }
      }

      return Err('Failed to start tracking: $e');
    }
  }

  Future<Result<(), String>> stopTracking(int userId) async {
    if (kDebugMode) {
      debugPrint('[PointAutomation] Stopping automatic tracking...');
    }

    Object? stopError;
    StackTrace? stopStackTrace;

    try {

      await _persistAutomaticTracking(userId, false);

      try {
        await _trackerEngine.stopTracking().timeout(
          const Duration(seconds: 10),
        );
      } catch (e, st) {
        stopError = e;
        stopStackTrace = st;

        if (kDebugMode) {
          debugPrint('[PointAutomation] Engine stop failed: $e');
          debugPrint('$st');
        }
      }

      await _locationFixSub?.cancel();
      await _settingsWatchSub?.cancel();
      await _batchCountSub?.cancel();

      _locationFixSub = null;
      _settingsWatchSub = null;
      _batchCountSub = null;

      _isTracking = false;
      _currentUserId = null;
      _currentSettings = null;
      _lastPointTime = null;
      _lastKnownBatchCount = 0;

      if (stopError != null) {
        return Err(
          'Tracking was disabled in settings, but stopping the engine failed: '
              '$stopError',
        );
      }

      return const Ok(());
    } catch (e, st) {
      if (kDebugMode) {
        debugPrint('[PointAutomation] Failed to disable tracking: $e');
        debugPrint('$st');

        if (stopStackTrace != null) {
          debugPrint('$stopStackTrace');
        }
      }

      return Err('Failed to disable tracking: $e');
    }
  }

  Future<Result<(), String>> restartTracking() async {
    final int? userId = _currentUserId;

    if (!_isTracking || userId == null) {
      return const Ok(());
    }

    if (kDebugMode) {
      debugPrint('[PointAutomation] Restarting tracking...');
    }

    final Result<(), String> stopResult = await stopTracking(userId);

    if (stopResult case Err(value: final message)) {
      return Err(message);
    }

    return await startTracking(userId);
  }

  Future<void> _cleanupAfterFailedStart() async {
    await _locationFixSub?.cancel();
    await _settingsWatchSub?.cancel();
    await _batchCountSub?.cancel();

    _locationFixSub = null;
    _settingsWatchSub = null;
    _batchCountSub = null;

    _isTracking = false;
    _currentUserId = null;
    _currentSettings = null;
    _lastPointTime = null;
    _lastKnownBatchCount = 0;
  }

  Future<void> _persistAutomaticTracking(int userId, bool value) async {

    final settings = await _getTrackerSettings(userId);
    final updatedSettings = settings.copyWith(automaticTracking: value);
    await _saveTrackerSettings(updatedSettings);
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
        '[PointAutomation] Starting settings watch for userId: $userId',
      );
    }

    _settingsWatchSub = _watchTrackerSettings(userId).listen(
          (settings) async {
        final TrackerSettings? old = _currentSettings;
        _currentSettings = settings;

        if (old == null) {
          return;
        }

        if (_settingsRequireEngineRestart(old, settings)) {
          if (kDebugMode) {
            debugPrint(
              '[PointAutomation] Scheduler settings changed, restarting tracker engine...',
            );
          }

          await _trackerEngine.stopTracking();
          await _trackerEngine.configure(settings);
          await _trackerEngine.startTracking(settings);

          return;
        }

        if (_settingsRequireEngineUpdate(old, settings)) {
          if (kDebugMode) {
            debugPrint(
              '[PointAutomation] Runtime settings changed, updating tracker engine...',
            );
          }

          await _trackerEngine.updateConfiguration(settings);
        }
      },
      onError: (error) {
        debugPrint('[PointAutomation] Settings watch error: $error');
      },
    );
  }

  bool _settingsRequireEngineRestart(
      TrackerSettings old,
      TrackerSettings current,
      ) {
    return old.trackingFrequency != current.trackingFrequency ||
        old.trackingMode != current.trackingMode;
  }

  bool _settingsRequireEngineUpdate(
      TrackerSettings old,
      TrackerSettings current,
      ) {
    return old.locationPrecision != current.locationPrecision ||
        old.minimumPointDistance != current.minimumPointDistance;
  }
}
