import 'dart:async';
import 'package:dawarich/features/batch/application/usecases/batch_upload_workflow_usecase.dart';
import 'package:dawarich/features/batch/application/usecases/get_current_batch_usecase.dart';
import 'package:dawarich/features/tracking/application/interfaces/tracker_engine_interface.dart';
import 'package:dawarich/features/tracking/application/usecases/get_batch_point_count_usecase.dart';
import 'package:dawarich/features/tracking/application/usecases/notifications/show_tracker_notification_usecase.dart';
import 'package:dawarich/features/tracking/application/usecases/point_creation/create_point_usecase.dart';
import 'package:dawarich/features/tracking/application/usecases/point_creation/store_point_usecase.dart';
import 'package:dawarich/features/tracking/application/usecases/settings/get_tracker_settings_usecase.dart';
import 'package:dawarich/features/tracking/application/usecases/settings/save_tracker_settings_usecase.dart';
import 'package:dawarich/features/tracking/domain/models/location_fix.dart';
import 'package:dawarich/features/tracking/domain/models/tracker_settings.dart';
import 'package:flutter/foundation.dart';
import 'package:option_result/option_result.dart';

final class PointAutomationService {

  final ITrackerEngine _trackerEngine;
  final CreatePointUseCase _createPoint;
  final StorePointUseCase _storePoint;
  final GetBatchPointCountUseCase _getBatchPointCount;
  final ShowTrackerNotificationUseCase _showTrackerNotification;
  final GetCurrentBatchUseCase _getCurrentBatch;
  final BatchUploadWorkflowUseCase _batchUploadWorkflow;
  final GetTrackerSettingsUseCase _getTrackerSettings;
  final SaveTrackerSettingsUseCase _saveTrackerSettings;

  Future<void> _locationProcessingChain = Future.value();

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
  );

  Future<Result<(), String>> startTracking(int userId) async {

    if (kDebugMode) {
      debugPrint('[PointAutomation] Starting automatic tracking...');
    }

    try {
      final TrackerSettings settings = await _getTrackerSettings(userId);
      final TrackerSettings updatedSettings = settings.copyWith(
        automaticTracking: true,
      );

      await _trackerEngine.configure(updatedSettings);

      _attachLocationFixHandler(userId);
      await _trackerEngine.startTracking(updatedSettings);

      await _persistAutomaticTracking(userId, true);

      unawaited(_refreshNotification(userId));

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

    Object? persistError;
    Object? stopError;
    StackTrace? persistStackTrace;
    StackTrace? stopStackTrace;

    _detachLocationFixHandler();

    try {
      await _persistAutomaticTracking(userId, false);
    } catch (e, st) {
      persistError = e;
      persistStackTrace = st;

      if (kDebugMode) {
        debugPrint('[PointAutomation] Failed to persist tracking disabled: $e');
        debugPrint('$st');
      }
    }

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

    if (persistError != null || stopError != null) {
      if (kDebugMode) {
        if (persistStackTrace != null) debugPrint('$persistStackTrace');
        if (stopStackTrace != null) debugPrint('$stopStackTrace');
      }

      return Err(
        'Tracking stop completed with errors. '
            'persistError=$persistError, stopError=$stopError',
      );
    }

    return const Ok(());
  }

  Future<Result<(), String>> restartTracking(int userId) async {

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
    _detachLocationFixHandler();

    try {
      await _trackerEngine.stopTracking().timeout(
        const Duration(seconds: 10),
      );
    } catch (e, st) {
      if (kDebugMode) {
        debugPrint('[PointAutomation] Failed-start engine cleanup failed: $e');
        debugPrint('$st');
      }
    }
  }

  Future<void> _persistAutomaticTracking(int userId, bool value) async {

    final settings = await _getTrackerSettings(userId);
    final updatedSettings = settings.copyWith(automaticTracking: value);
    await _saveTrackerSettings(updatedSettings);
  }

  void _attachLocationFixHandler(int userId) {
    if (kDebugMode) {
      debugPrint('[PointAutomation] Attaching Tracelet location fix handler.');
    }

    _trackerEngine.setLocationFixHandler(
          (LocationFix locationFix) async {
        await _enqueueLocationFix(
          locationFix: locationFix,
          userId: userId,
        );
      },
    );
  }

  void _detachLocationFixHandler() {
    if (kDebugMode) {
      debugPrint('[PointAutomation] Detaching Tracelet location fix handler.');
    }

    _trackerEngine.setLocationFixHandler(null);
  }

  Future<void> _enqueueLocationFix({
    required LocationFix locationFix,
    required int userId,
  }) {
    _locationProcessingChain = _locationProcessingChain
        .then((_) async {
      await _handleLocationFix(
        locationFix: locationFix,
        userId: userId,
      );
    })
        .catchError((Object error, StackTrace stackTrace) {
      if (kDebugMode) {
        debugPrint('[PointAutomation] Location processing failed: $error');
        debugPrint('$stackTrace');
      }
    });

    return _locationProcessingChain;
  }

  Future<void> _handleLocationFix({
    required LocationFix locationFix,
    required int userId,
  }) async {

    try {
      final pointResult = await _createPoint(
        position: locationFix,
        timestamp: locationFix.timestampUtc,
        userId: userId,
      );

      if (pointResult case Ok(value: final point)) {
        final storeResult = await _storePoint(point);

        if (storeResult case Ok()) {
          final int batchCount = await _getBatchPointCount(userId);
          final TrackerSettings settings = await _getTrackerSettings(userId);

          if (batchCount >= settings.pointsPerBatch) {
            await _uploadCurrentBatch(userId);
          }

          _refreshNotificationWithCount(batchCount: batchCount,
              lastPointTimeUtc: locationFix.timestampUtc);
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
    }
  }

  // ── Notification ───────────────────────────────────────────────────────
  Future<void> _refreshNotification(int userId) async {
    try {
      final batchCount = await _getBatchPointCount(userId);

      _refreshNotificationWithCount(batchCount: batchCount);
    } catch (e, s) {
      debugPrint("[PointAutomation] Notification refresh error: $e\n$s");
    }
  }

  /// Updates the notification using an already-known batch count,
  /// avoiding an extra DB query.
  void _refreshNotificationWithCount({
    required int batchCount,
    DateTime? lastPointTimeUtc,
  }) {
    try {
      String body;

      if (lastPointTimeUtc != null) {
        final lastTime = lastPointTimeUtc.toLocal();
        final lastTimeStr = '${lastTime.hour.toString().padLeft(2, '0')}:'
            '${lastTime.minute.toString().padLeft(2, '0')}:'
            '${lastTime.second.toString().padLeft(2, '0')}';

        body = 'Last point: $lastTimeStr • $batchCount in batch';
      } else {
        body = 'Tracker started, no points tracked yet • $batchCount in batch';
      }

      _showTrackerNotification(
        title: 'Tracking active',
        body: body,
      );
    } catch (e, s) {
      debugPrint('[PointAutomation] Notification refresh error: $e\n$s');
    }
  }

  // ── Upload helper ──────────────────────────────────────────────────────

  /// Fetches the current un-uploaded batch and uploads it.
  Future<void> _uploadCurrentBatch(int userId) async {
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
    }
  }

}
