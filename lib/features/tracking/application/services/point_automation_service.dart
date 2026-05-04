import 'dart:math' as math;
import 'dart:async';
import 'package:dawarich/core/data/repositories/local_point_repository_interfaces.dart';
import 'package:dawarich/features/batch/application/usecases/batch_upload_workflow_usecase.dart';
import 'package:dawarich/features/batch/application/usecases/get_current_batch_usecase.dart';
import 'package:dawarich/features/tracking/application/repositories/hardware_repository_interfaces.dart';
import 'package:dawarich/features/tracking/application/repositories/location_provider_interface.dart';
import 'package:dawarich/features/tracking/application/services/tracker_intelligence_service.dart';
import 'package:dawarich/features/tracking/application/usecases/get_batch_point_count_usecase.dart';
import 'package:dawarich/features/tracking/application/usecases/notifications/show_tracker_notification_usecase.dart';
import 'package:dawarich/features/tracking/application/usecases/point_creation/create_point_from_location_stream_workflow.dart';
import 'package:dawarich/features/tracking/application/usecases/point_creation/store_point_usecase.dart';
import 'package:dawarich/features/tracking/application/usecases/settings/watch_tracker_settings_usecase.dart';
import 'package:dawarich/features/tracking/domain/enum/auto_tracking_runtime_mode.dart';
import 'package:dawarich/features/tracking/domain/models/tracker_settings.dart';
import 'package:dawarich/features/tracking/domain/models/tracking_sample.dart';
import 'package:flutter/foundation.dart';
import 'package:option_result/option_result.dart';

final class PointAutomationService {
  bool _isTracking = false;
  bool _uploadBusy = false;
  bool _isRestartingStream = false;
  int? _currentUserId;
  StreamSubscription<void>? _locationStreamSub;
  StreamSubscription<TrackerSettings>? _settingsWatchSub;
  StreamSubscription<int>? _batchCountSub;
  StreamSubscription<void>? _connectivitySub;
  StreamSubscription<void>? _batterySub;
  StreamSubscription<void>? _motionTransitionSub;
  TrackerSettings? _currentSettings;
  Timer? _heartbeatTimer;
  Timer? _activeSilenceTimer;

  // Fallback timer for monitor → passive. With a distance filter active,
  // a stationary device produces no fixes so evaluateFix() never runs.
  // This timer is the safety net.
  Timer? _monitorIdleTimer;
  DateTime? _lastPointTime;
  int _lastKnownBatchCount = 0;
  int _recoveryAttempt = 0;

  // Skips the first connectivity event emitted on subscription.
  // connectivity_plus fires the current state immediately, but we always want
  // the tracker to start in active mode. Events after that still apply normally.
  bool _startupConnectivityGuard = true;

  // Max consecutive recovery attempts before giving up.
  // The 15-min WorkManager watchdog will restart the service with a clean state.
  static const _maxRecoveryAttempts = 10;

  // Heartbeat interval to re-post the notification so aggressive OEMs
  // don't kill the foreground service.
  static const _heartbeatInterval = Duration(seconds: 60);

  AutoTrackingRuntimeMode get autoTrackingRuntimeMode =>
      _autoTrackingRuntimeMode;

  AutoTrackingRuntimeMode _autoTrackingRuntimeMode =
      AutoTrackingRuntimeMode.active;

  final CreatePointFromLocationStreamWorkflow _createPointFromLocationStream;
  final StorePointUseCase _storePoint;
  final GetBatchPointCountUseCase _getBatchPointCount;
  final ShowTrackerNotificationUseCase _showTrackerNotification;
  final GetCurrentBatchUseCase _getCurrentBatch;
  final BatchUploadWorkflowUseCase _batchUploadWorkflow;
  final WatchTrackerSettingsUseCase _watchTrackerSettings;
  final IPointLocalRepository _localPointRepository;
  final TrackerIntelligenceService _trackerIntelligenceService;
  final IHardwareRepository _hardwareRepository;
  final ILocationProvider _locationProvider;


  PointAutomationService(
      this._createPointFromLocationStream,
      this._storePoint,
      this._getBatchPointCount,
      this._showTrackerNotification,
      this._getCurrentBatch,
      this._batchUploadWorkflow,
      this._watchTrackerSettings,
      this._localPointRepository,
      this._trackerIntelligenceService,
      this._hardwareRepository,
      this._locationProvider,
  );

  /// Whether automatic tracking is currently active
  bool get isTracking => _isTracking;

  Future<void> startTracking(int userId) async {

    if (_isTracking) {
      return;
    }

    if (kDebugMode) {
      debugPrint("[PointAutomation] Starting automatic tracking with location stream...");
    }

    _isTracking = true;
    _currentUserId = userId;
    _lastPointTime = null;
    _recoveryAttempt = 0;
    _startupConnectivityGuard = true;
    await _refreshNotification(userId);

    _trackerIntelligenceService.reset();
    _setAutoTrackingRuntimeMode(_trackerIntelligenceService.currentMode);

    _startHeartbeatTimer();
    _startSettingsWatch(userId);
    _startConnectivityWatch(userId);
    _startBatteryWatch(userId);
    _startMotionTransitionWatch(userId);
    _startLocationStream(userId);
    _startBatchCountWatch(userId);
  }

  // Heartbeat

  void _startHeartbeatTimer() {
    _heartbeatTimer?.cancel();
    _heartbeatTimer = Timer.periodic(
      _heartbeatInterval,
      (_) {
        if (kDebugMode) {
          final hasStream = _locationStreamSub != null;
          debugPrint(
            '[PointAutomation] Heartbeat — mode: $_autoTrackingRuntimeMode, '
            'stream: ${hasStream ? "active" : "none"}, '
            'lastPoint: ${_lastPointTime?.toLocal() ?? "never"}',
          );
        }
        _refreshNotificationWithCount(_lastKnownBatchCount);
      },
    );
  }

  // Notification

  Future<void> _refreshNotification(int userId) async {
    try {
      final batchCount = await _getBatchPointCount(userId);
      _refreshNotificationWithCount(batchCount);
    } catch (e, s) {
      debugPrint("[PointAutomation] Notification refresh error: $e\n$s");
    }
  }

  void _refreshNotificationWithCount(int batchCount) {
    try {

      String body;
      if (_lastPointTime != null) {
        final lastTime = _lastPointTime!.toLocal();
        final lastTimeStr = '${lastTime.hour.toString().padLeft(2, '0')}:'
            '${lastTime.minute.toString().padLeft(2, '0')}:'
            '${lastTime.second.toString().padLeft(2, '0')}';
        if (kDebugMode) {
          final modeLabel = switch (_autoTrackingRuntimeMode) {
            AutoTrackingRuntimeMode.active => 'ACTIVE',
            AutoTrackingRuntimeMode.monitor => 'MONITOR',
            AutoTrackingRuntimeMode.passive => 'PASSIVE',
          };
          body = '[$modeLabel] Last point: $lastTimeStr • $batchCount in batch';
        } else {
          body = 'Last point: $lastTimeStr • $batchCount in batch';
        }
      } else {
        if (kDebugMode) {
          final modeLabel = switch (_autoTrackingRuntimeMode) {
            AutoTrackingRuntimeMode.active => 'ACTIVE',
            AutoTrackingRuntimeMode.monitor => 'MONITOR',
            AutoTrackingRuntimeMode.passive => 'PASSIVE',
          };
          body = '[$modeLabel] Monitoring location... • $batchCount in batch';
        } else {
          body = 'Monitoring location... • $batchCount in batch';
        }
      }

      _showTrackerNotification(
        title: 'Tracking active',
        body: body,
      );
    } catch (e, s) {
      debugPrint("[PointAutomation] Notification refresh error: $e\n$s");
    }
  }

  // Batch count watch -> threshold upload

  void _startBatchCountWatch(int userId) {
    _batchCountSub?.cancel();

    final stream = _localPointRepository.watchBatchPointCount(userId);

    _batchCountSub = stream.listen(
      (count) async {
        _lastKnownBatchCount = count;
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

  // Upload helper

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

  // Settings watch

  void _startSettingsWatch(int userId) {
    _settingsWatchSub?.cancel();

    if (kDebugMode) {
      debugPrint("[PointAutomation] Starting settings watch for userId: $userId");
    }

    _settingsWatchSub = _watchTrackerSettings(userId).listen(
      (settings) async {
        final old = _currentSettings;
        _currentSettings = settings;

        if (_isTracking && settings.trackingFrequency == 0) {
          if (_autoTrackingRuntimeMode == AutoTrackingRuntimeMode.active) {
            _startOrResetActiveSilenceTimer(userId);
          } else {
            _cancelActiveSilenceTimer();
          }
        }

        if (old != null && _settingsRequireRestart(old, settings)) {
          if (kDebugMode) {
            debugPrint("[PointAutomation] Settings changed (${old.trackingFrequency}s -> ${settings.trackingFrequency}s), restarting location stream...");
          }
          await _restartLocationStream(userId);
        }
      },
      onError: (e) {
        debugPrint("[PointAutomation] Settings watch error: $e");
      },
    );
  }

  bool _settingsRequireRestart(TrackerSettings old, TrackerSettings current) {
    return old.trackingFrequency != current.trackingFrequency ||
           old.locationPrecision != current.locationPrecision ||
           old.minimumPointDistance != current.minimumPointDistance;
  }

  // Connectivity watch

  void _startConnectivityWatch(int userId) {
    _connectivitySub?.cancel();

    _connectivitySub = _hardwareRepository.watchConnectivity().listen(
      (kind) async {
        if (!_isTracking || _currentUserId != userId) return;

        // Skip the first event — connectivity_plus emits the current state
        // immediately on subscribe. We always want to start in active mode.
        if (_startupConnectivityGuard) {
          _startupConnectivityGuard = false;
          if (kDebugMode) {
            debugPrint(
              '[PointAutomation] Connectivity startup event suppressed ($kind)',
            );
          }
          return;
        }

        final previousMode = _autoTrackingRuntimeMode;
        final nextMode = _trackerIntelligenceService.notifyConnectivityChanged(kind);

        if (kDebugMode) {
          debugPrint('[PointAutomation] Connectivity changed: $kind → mode $nextMode');
        }

        final settings = _currentSettings;
        final isAutoMode = settings?.trackingFrequency == 0;

        if (isAutoMode && previousMode != nextMode) {
          _setAutoTrackingRuntimeMode(nextMode);
          await _restartLocationStream(userId);
        }
      },
      onError: (e) {
        debugPrint('[PointAutomation] Connectivity watch error: $e');
      },
    );
  }

  // Battery watch

  /// Subscribes to battery state changes. Charger unplugged while in passive
  /// mode wakes the tracker to monitor so low-power GPS can check if we're leaving.
  void _startBatteryWatch(int userId) {
    _batterySub?.cancel();

    _batterySub = _hardwareRepository.watchBatteryState().listen(
      (state) async {
        if (!_isTracking || _currentUserId != userId) return;

        final previousMode = _autoTrackingRuntimeMode;
        final nextMode = _trackerIntelligenceService.notifyBatteryStateChanged(state);

        if (kDebugMode) {
          debugPrint('[PointAutomation] Battery state changed: $state → mode $nextMode');
        }

        final settings = _currentSettings;
        final isAutoMode = settings?.trackingFrequency == 0;

        if (isAutoMode && previousMode != nextMode) {
          _setAutoTrackingRuntimeMode(nextMode);
          await _restartLocationStream(userId);
        }
      },
      onError: (e) {
        debugPrint('[PointAutomation] Battery watch error: $e');
      },
    );
  }

  // Motion transition watch

  /// Subscribes to locomotion transition events from the OS.
  ///
  /// When passive, wakes to monitor so the cell+WiFi stream can confirm
  /// real movement before committing to full GPS. Already in monitor or
  /// active — ignored, evaluateFix() handles it from there.
  void _startMotionTransitionWatch(int userId) {
    _motionTransitionSub?.cancel();

    debugPrint(
      '[PointAutomation] Setting up motion transition watch for user $userId',
    );

    _motionTransitionSub = _hardwareRepository.watchMotionTransitions().listen(
      (_) async {
        debugPrint(
          '[PointAutomation] *** Motion transition EVENT received in listener ***  '
          'isTracking=$_isTracking, userId=$_currentUserId, mode=$_autoTrackingRuntimeMode',
        );
        if (!_isTracking || _currentUserId != userId) return;

        final previousMode = _autoTrackingRuntimeMode;
        var nextMode = _trackerIntelligenceService.notifyMotionTransitionDetected();

        if (kDebugMode) {
          debugPrint(
            '[PointAutomation] Motion transition detected → mode $nextMode',
          );
        }

        // If we just woke from passive to monitor, do a free one-shot check
        // on the last known location. Vehicle-level speed skips monitor and
        // goes straight to active. getLastKnown() is zero-cost (OS cache).
        if (previousMode == AutoTrackingRuntimeMode.passive &&
            nextMode == AutoTrackingRuntimeMode.monitor) {
          final lastKnownOption = await _locationProvider.getLastKnown();
          if (lastKnownOption case Some(value: final fix)) {
            final promoted = _trackerIntelligenceService.evaluateFix(fix);
            if (promoted != nextMode) {
              if (kDebugMode) {
                debugPrint(
                  '[PointAutomation] Last-known fix promoted tracker: '
                  'monitor → $promoted '
                  '(speed=${fix.speedMps.toStringAsFixed(1)} m/s)',
                );
              }
              nextMode = promoted;
            }
          } else if (kDebugMode) {
            debugPrint('[PointAutomation] No last-known fix available, staying in monitor.');
          }
        }

        final settings = _currentSettings;
        final isAutoMode = settings?.trackingFrequency == 0;

        if (isAutoMode == true && previousMode != nextMode) {
          _setAutoTrackingRuntimeMode(nextMode);
          await _restartLocationStream(userId);
        }
      },
      onError: (e) {
        debugPrint('[PointAutomation] Motion transition watch error: $e');
      },
    );
  }

  // Location stream

  void _startLocationStream(int userId) {
    _locationStreamSub?.cancel();
    _locationStreamSub = null;

    final settings = _currentSettings;
    final isAutoMode = settings?.trackingFrequency == 0;

    // In auto mode, passive runs a PRIORITY_NO_POWER piggyback stream as a
    // free point recorder alongside activity recognition. Fixes from this
    // stream are stored if they show enough displacement, but they don't drive
    // mode transitions — evaluateFix() is skipped for passive fixes.
    if (isAutoMode == true &&
        _autoTrackingRuntimeMode == AutoTrackingRuntimeMode.passive) {
      if (kDebugMode) {
        debugPrint(
          '[PointAutomation] Passive mode — starting PRIORITY_NO_POWER fallback '
          'stream alongside activity recognition.',
        );
      }
      // Fall through to start the stream with powerSave precision.
    }

    final Stream<TrackingSample> pointStream =
        _createPointFromLocationStream.getTrackingSampleStream(
          userId,
          runtimeMode: _autoTrackingRuntimeMode,
        );

    _locationStreamSub = pointStream
        .asyncMap((result) => _handleLocationUpdate(result, userId))
        .listen(
          (_) {},
          onError: (error, stackTrace) {
            debugPrint('[PointAutomation] Stream error: $error\n$stackTrace');
            unawaited(_scheduleLocationStreamRecovery(userId, 'stream error'));
          },
          onDone: () {
            if (kDebugMode) {
              debugPrint('[PointAutomation] Location stream completed');
            }
            unawaited(_scheduleLocationStreamRecovery(userId, 'stream completed'));
          },
          cancelOnError: false,
        );
  }

  Future<void> _scheduleLocationStreamRecovery(int userId, String reason) async {
    if (!_isTracking || _currentUserId != userId) {
      if (kDebugMode) {
        debugPrint("[PointAutomation] Stream recovery skipped: tracking no longer active.");
      }
      return;
    }

    if (_isRestartingStream) {
      if (kDebugMode) {
        debugPrint("[PointAutomation] Stream recovery skipped: restart already in progress.");
      }
      return;
    }

    _recoveryAttempt++;

    if (_recoveryAttempt > _maxRecoveryAttempts) {
      debugPrint(
        "[PointAutomation] Stream recovery exhausted ($_maxRecoveryAttempts attempts). "
        "Giving up — watchdog will restart the service.",
      );
      return;
    }

    // Exponential backoff: 2s, 4s, 8s, ... capped at 5 min.
    final delaySec = math.min(math.pow(2, _recoveryAttempt).toInt(), 300);

    try {
      if (kDebugMode) {
        debugPrint(
          "[PointAutomation] Scheduling stream recovery (attempt $_recoveryAttempt) "
          "due to: $reason — waiting ${delaySec}s",
        );
      }

      await Future<void>.delayed(Duration(seconds: delaySec));

      if (!_isTracking || _currentUserId != userId) {
        if (kDebugMode) {
          debugPrint("[PointAutomation] Stream recovery aborted: tracking no longer active.");
        }
        return;
      }

      await _restartLocationStream(userId);
    } catch (e, s) {
      debugPrint("[PointAutomation] Stream recovery failed: $e\n$s");
    }
  }

  Future<void> _restartLocationStream(int userId) async {
    try {
      if (_isRestartingStream) {
        return;
      }

      _isRestartingStream = true;

      final oldSub = _locationStreamSub;
      _locationStreamSub = null;

      if (oldSub != null) {
        try {
          await oldSub.cancel();
        } catch (e) {
          debugPrint("[PointAutomation] Cancel error (ignored): $e");
        }
      }

      _startLocationStream(userId);

      if (kDebugMode) {
        debugPrint("[PointAutomation] Location stream restarted");
      }
    } catch (e, s) {
      debugPrint("[PointAutomation] ERROR in _restartLocationStream: $e\n$s");
    } finally {
      _isRestartingStream = false;
    }
  }

  // Lifecycle

  Future<void> stopTracking() async {
    if (!_isTracking) return;

    if (kDebugMode) {
      debugPrint("[PointAutomation] Stopping automatic tracking...");
    }

    _isTracking = false;
    _isRestartingStream = false;
    _currentUserId = null;
    _currentSettings = null;
    _lastPointTime = null;
    _lastKnownBatchCount = 0;
    _recoveryAttempt = 0;
    _startupConnectivityGuard = true;
    _heartbeatTimer?.cancel();
    _heartbeatTimer = null;
    _cancelActiveSilenceTimer();
    _cancelMonitorIdleTimer();
    _trackerIntelligenceService.reset();
    _setAutoTrackingRuntimeMode(_trackerIntelligenceService.currentMode);
    await _batchCountSub?.cancel();
    _batchCountSub = null;
    await _settingsWatchSub?.cancel();
    _settingsWatchSub = null;
    await _connectivitySub?.cancel();
    _connectivitySub = null;
    await _batterySub?.cancel();
    _batterySub = null;
    await _motionTransitionSub?.cancel();
    _motionTransitionSub = null;
    await _locationStreamSub?.cancel();
    _locationStreamSub = null;

  }

  Future<void> restartTracking() async {
    if (!_isTracking || _currentUserId == null) return;

    final userId = _currentUserId!;

    if (kDebugMode) {
      debugPrint("[PointAutomation] Restarting tracking to apply new settings...");
    }

    await stopTracking();
    await startTracking(userId);
  }

  // Location update handler

  Future<void> _handleLocationUpdate(TrackingSample sample, int userId) async {
    // A location update arrived — the stream is healthy. Reset the backoff
    // counter so the next failure starts from a short delay again.
    _recoveryAttempt = 0;

    try {
      final previousMode = _autoTrackingRuntimeMode;
      final settings = _currentSettings;
      final isAutoMode = settings?.trackingFrequency == 0;

      // In passive mode the stream is a PRIORITY_NO_POWER piggyback that
      // records opportunistic points. It must not drive mode transitions —
      // that's activity recognition's job.
      final nextMode = (isAutoMode == true &&
              previousMode == AutoTrackingRuntimeMode.passive)
          ? previousMode
          : _trackerIntelligenceService.evaluateFix(sample.fix);

      final didModeValueChange = previousMode != nextMode;
      final shouldRestartForModeChange = isAutoMode == true && didModeValueChange;

      if (shouldRestartForModeChange) {
        if (kDebugMode) {
          debugPrint(
            '[PointAutomation] Auto tracking mode changed '
                '($previousMode -> $nextMode), restarting location stream...',
          );
        }

        _setAutoTrackingRuntimeMode(nextMode);

        // Passive mode has no stream — cancel and wait for a motion event.
        if (nextMode == AutoTrackingRuntimeMode.passive) {
          await _locationStreamSub?.cancel();
          _locationStreamSub = null;
          if (kDebugMode) {
            debugPrint(
              '[PointAutomation] Stream cancelled — passive mode, '
              'waiting for OS motion event.',
            );
          }
        } else {
          await _restartLocationStream(userId);
        }
      } else if (didModeValueChange) {
        _setAutoTrackingRuntimeMode(nextMode);
      }

      if (isAutoMode == true) {
        if (nextMode == AutoTrackingRuntimeMode.active) {
          _startOrResetActiveSilenceTimer(userId);
        } else {
          _cancelActiveSilenceTimer();
        }
      }

      final pointResult = sample.pointResult;
      if (pointResult == null) {
        if (kDebugMode) {
          debugPrint('[PointAutomation] No point created for this tracking sample.');
        }

        _refreshNotificationWithCount(_lastKnownBatchCount);
        return;
      }

      if (pointResult case Ok(value: final point)) {
        if (kDebugMode) {
          debugPrint('[PointAutomation] Storing point from location stream');
        }

        final storeResult = await _storePoint(point);

        if (storeResult case Ok()) {
          _lastPointTime = DateTime.now();
        } else if (storeResult case Err(value: final err)) {
          debugPrint('[PointAutomation] Failed to store point: $err');
        }

        _refreshNotificationWithCount(_lastKnownBatchCount);
        return;
      }

      if (pointResult case Err(value: final err)) {
        debugPrint('[PointAutomation] Point creation error: $err');
      }

      _refreshNotificationWithCount(_lastKnownBatchCount);
    } catch (e, s) {
      debugPrint('[PointAutomation] Error handling location update: $e\n$s');
    }
  }

  // Tracking intelligence

  void _setAutoTrackingRuntimeMode(AutoTrackingRuntimeMode mode) {
    if (_autoTrackingRuntimeMode == mode) {
      return;
    }

    _autoTrackingRuntimeMode = mode;
    _refreshNotificationWithCount(_lastKnownBatchCount);

    // Manage timers centrally so they're correct regardless of which
    // code path triggered the mode change.
    final userId = _currentUserId;
    switch (mode) {
      case AutoTrackingRuntimeMode.active:
        _cancelMonitorIdleTimer();
        if (userId != null) _startOrResetActiveSilenceTimer(userId);
      case AutoTrackingRuntimeMode.monitor:
        _cancelActiveSilenceTimer();
        if (userId != null) _startMonitorIdleTimer(userId);
      case AutoTrackingRuntimeMode.passive:
        _cancelActiveSilenceTimer();
        _cancelMonitorIdleTimer();
    }

    if (kDebugMode) {
      debugPrint(
        '[PointAutomation] Auto tracking runtime mode -> $mode',
      );
    }
  }

  void _cancelActiveSilenceTimer() {
    _activeSilenceTimer?.cancel();
    _activeSilenceTimer = null;
  }

  void _startOrResetActiveSilenceTimer(int userId) {
    _cancelActiveSilenceTimer();

    final settings = _currentSettings;
    final isAutoMode = settings?.trackingFrequency == 0;

    if (isAutoMode != true) {
      return;
    }

    if (_autoTrackingRuntimeMode != AutoTrackingRuntimeMode.active) {
      return;
    }

    _activeSilenceTimer = Timer(
      TrackerIntelligenceService.activeToMonitorStillness,
          () async {
        if (!_isTracking || _currentUserId != userId) {
          return;
        }

        final latestSettings = _currentSettings;
        final isStillAutoMode = latestSettings?.trackingFrequency == 0;

        if (isStillAutoMode != true) {
          return;
        }

        if (_autoTrackingRuntimeMode != AutoTrackingRuntimeMode.active) {
          return;
        }

        final now = DateTime.now().toUtc();

        final lastMovementTime =
            _trackerIntelligenceService.lastMeaningfulMovementTime ?? now.subtract(TrackerIntelligenceService.activeToMonitorStillness);

        final stillFor = now.difference(lastMovementTime);

        if (stillFor < TrackerIntelligenceService.activeToMonitorStillness) {
          if (kDebugMode) {
            debugPrint(
              '[PointAutomation] Silence timer elapsed, but movement was seen '
                  '${stillFor.inSeconds}s ago. Staying active.',
            );
          }
          _startOrResetActiveSilenceTimer(userId);
          return;
        }

        if (kDebugMode) {
          debugPrint(
            '[PointAutomation] No meaningful movement for '
                '${stillFor.inSeconds}s while active, switching to monitor...',
          );
        }

        // Sync TrackerIntelligenceService before changing _autoTrackingRuntimeMode
        // so the first fix from the new stream is evaluated in the right branch.
        // Without this, the service still thinks it's in active, evaluates the
        // first low-power fix as active-mode movement and immediately bounces back.
        _trackerIntelligenceService.forceMode(AutoTrackingRuntimeMode.monitor);
        _setAutoTrackingRuntimeMode(AutoTrackingRuntimeMode.monitor);
        await _restartLocationStream(userId);
      },
    );
  }

  // Monitor idle timer

  /// Fallback timer for monitor -> passive.
  ///
  /// With a distance filter in monitor mode, a stationary device produces
  /// no fixes so evaluateFix() never runs. If we're still in monitor after
  /// monitorIdleTimeout with no confirmed movement, we drop to passive.
  ///
  /// If evaluateFix() transitions the mode first, _setAutoTrackingRuntimeMode
  /// cancels this timer before it fires, so the two paths don't conflict.
  void _startMonitorIdleTimer(int userId) {
    _cancelMonitorIdleTimer();

    _monitorIdleTimer = Timer(
      TrackerIntelligenceService.monitorIdleTimeout,
      () async {
        if (!_isTracking || _currentUserId != userId) return;
        if (_autoTrackingRuntimeMode != AutoTrackingRuntimeMode.monitor) return;

        final settings = _currentSettings;
        final isAutoMode = settings?.trackingFrequency == 0;
        if (isAutoMode != true) return;

        if (kDebugMode) {
          debugPrint(
            '[PointAutomation] Monitor idle timeout — no movement confirmed, '
            'switching to passive...',
          );
        }

        // Sync TrackerIntelligenceService first (same reason as above).
        _trackerIntelligenceService.forceMode(AutoTrackingRuntimeMode.passive);
        _setAutoTrackingRuntimeMode(AutoTrackingRuntimeMode.passive);
        await _restartLocationStream(userId);
      },
    );
  }

  void _cancelMonitorIdleTimer() {
    _monitorIdleTimer?.cancel();
    _monitorIdleTimer = null;
  }


}
