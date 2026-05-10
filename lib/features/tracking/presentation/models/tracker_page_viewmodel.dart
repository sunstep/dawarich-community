import 'dart:async';
import 'dart:io';
import 'package:dawarich/core/background/schedulers/expired_batch_work_scheduler.dart';
import 'package:dawarich/core/presentation/safe_change_notifier.dart';
import 'package:dawarich/features/tracking/application/services/background_tracking_service.dart';
import 'package:dawarich/features/tracking/application/usecases/point_creation/create_point_from_gps_workflow.dart';
import 'package:dawarich/features/tracking/application/usecases/point_creation/store_point_usecase.dart';
import 'package:dawarich/features/tracking/application/usecases/settings/get_device_model_usecase.dart';
import 'package:dawarich/features/tracking/application/usecases/settings/get_tracker_settings_usecase.dart';
import 'package:dawarich/features/tracking/application/usecases/settings/save_tracker_settings_usecase.dart';
import 'package:dawarich/features/tracking/application/usecases/stream_last_point_usecase.dart';
import 'package:dawarich/features/tracking/application/usecases/system_settings/check_system_settings_usecase.dart';
import 'package:dawarich/features/tracking/application/usecases/system_settings/open_system_settings_usecase.dart';
import 'package:dawarich/features/tracking/application/usecases/track/end_track_usecase.dart';
import 'package:dawarich/features/tracking/application/usecases/track/get_active_track_usecase.dart';
import 'package:dawarich/features/tracking/application/usecases/track/start_track_usecase.dart';
import 'package:dawarich/features/tracking/application/usecases/track/watch_batch_point_count_usecase.dart';
import 'package:dawarich/features/tracking/domain/enum/location_precision.dart';
import 'package:dawarich/features/tracking/domain/models/last_point.dart';
import 'package:dawarich/core/domain/models/point/local/local_point.dart';
import 'package:dawarich/features/tracking/domain/models/track.dart';
import 'package:dawarich/features/batch/presentation/converters/local_point_converter.dart';
import 'package:dawarich/features/tracking/domain/models/tracker_settings.dart';
import 'package:dawarich/features/tracking/presentation/converters/last_point_converter.dart';
import 'package:dawarich/features/tracking/presentation/converters/track_converter.dart';
import 'package:dawarich/features/batch/presentation/models/local_point_viewmodel.dart';
import 'package:dawarich/features/tracking/presentation/models/track_viewmodel.dart';
import 'package:flutter/foundation.dart';
import 'package:dawarich/features/tracking/presentation/models/last_point_viewmodel.dart';
import 'package:option_result/option_result.dart';
import 'package:permission_handler/permission_handler.dart';

final class TrackerPageViewModel extends ChangeNotifier with SafeChangeNotifier {

  final int userId;

  LastPointViewModel? _lastPoint;
  LastPointViewModel? get lastPoint => _lastPoint;

  TrackerSettings? _trackerSettings;
  TrackerSettings? get trackerSettings => _trackerSettings;

  final GetTrackerSettingsUseCase _getTrackerSettings;
  final SaveTrackerSettingsUseCase _saveTrackerSettings;
  final GetDeviceModelUseCase _getDeviceModel;
  StreamSubscription<TrackerSettings>? _settingsSub;
  final StreamLastPointUseCase _streamLastPoint;
  final StreamBatchPointCountUseCase _streamBatchPointCount;
  final CreatePointFromGpsWorkflow _createPointFromGps;
  final StorePointUseCase _storePoint;
  final StartTrackUseCase _startTrackUseCase;
  final EndTrackUseCase _endTrackUseCase;
  final GetActiveTrackUseCase _getActiveTrackUseCase;
  final CheckSystemSettingsUseCase _checkSystemSettings;
  final OpenSystemSettingsUseCase _openSystemSettings;

  TrackerPageViewModel(
      this.userId,
      this._getTrackerSettings,
      this._saveTrackerSettings,
      this._getDeviceModel,
      this._streamLastPoint,
      this._streamBatchPointCount,
      this._createPointFromGps,
      this._storePoint,
      this._startTrackUseCase,
      this._endTrackUseCase,
      this._getActiveTrackUseCase,
      this._checkSystemSettings,
      this._openSystemSettings,
    );

  int _batchPointCount = 0;
  int get batchPointCount => _batchPointCount;

  final int minBatch = 1;
  final int maxBatch = 1000;

  bool _hideLastPoint = false;
  bool get hideLastPoint => _hideLastPoint;

  StreamSubscription<Option<LastPoint>>? _lastPointSub;
  StreamSubscription<int>? _batchCountSub;

  TrackViewModel? _currentTrack;
  TrackViewModel? get currentTrack => _currentTrack;

  void setCurrentTrack(TrackViewModel track) {
    _currentTrack = track;
    safeNotifyListeners();
  }

  bool _isRecording = false;
  bool get isRecording => _isRecording;

  void setIsRecording(bool trueOrFalse) {
    _isRecording = trueOrFalse;
    safeNotifyListeners();
  }

  int _trackPointCount = 0;
  int get trackPointCount => _trackPointCount;

  void setTrackPointCount(int count) {
    _trackPointCount = count;
    safeNotifyListeners();
  }

  // Duration _recordDuration = Duration();
  // String get recordDuration {
  //   final hours = _recordDuration.inHours;
  //   final minutes = _recordDuration.inMinutes % 60;
  //   final seconds = _recordDuration.inSeconds % 60;
  //   return '${hours.toString().padLeft(2, '0')}:'
  //       '${minutes.toString().padLeft(2, '0')}:'
  //       '${seconds.toString().padLeft(2, '0')}';
  // }

  int _currentPage = 0;
  int get currentPage => _currentPage;

  // void previousPage() {
  //   if (_currentPage > 0) {
  //     _currentPage--;
  //   } else {
  //     _currentPage = 2;
  //   }
  //
  //   notifyListeners();
  // }

  void setCurrentPage(int index) {
    _currentPage = index;
    safeNotifyListeners();
  }

  void nextPage() {
    if (_currentPage < 2) {
      _currentPage++;
    } else {
      _currentPage = 0;
    }
    safeNotifyListeners();
  }

  String get pageTitle {
    switch (_currentPage) {
      case 0:
        return "Track Recording";
      case 1:
        return "Basic Settings";
      case 2:
        return "Advanced Settings";
      default:
        return "";
    }
  }

  String get toggleButtonText {
    switch (_currentPage) {
      case 0:
        return "Show Basic Settings";
      case 1:
        return "Show Advanced Settings";
      case 2:
        return "Show Recording";
      default:
        return "";
    }
  }

  bool _isRetrievingSettings = true;
  bool get isRetrievingSettings => _isRetrievingSettings;

  bool _isTrackingAutomatically = false;
  bool _isUpdatingTracking = false;
  bool get isTrackingAutomatically => _isTrackingAutomatically;
  bool get isUpdatingTracking => _isUpdatingTracking;
  bool get showDotPulseLoading => _isUpdatingTracking;

  final _consentPromptController = StreamController<String>.broadcast();
  Stream<String> get onConsentPrompt => _consentPromptController.stream;
  Completer<bool>? _consentResponseCompleter;

  bool _isTracking = false;
  bool get isTracking => _isTracking;

  int _maxPointsPerBatch = 50;
  int get maxPointsPerBatch => _maxPointsPerBatch;

  int _trackingFrequency = 10; // in seconds
  int get trackingFrequency => _trackingFrequency;

  LocationPrecision _locationAccuracy =
      Platform.isAndroid ? LocationPrecision.high : LocationPrecision.best;
  LocationPrecision get locationAccuracy => _locationAccuracy;

  int _minimumPointDistance = 0;
  int get minimumPointDistance => _minimumPointDistance;

  String _deviceId = "";
  String get deviceId => _deviceId;

  int? _batchExpirationMinutes;
  int? get batchExpirationMinutes => _batchExpirationMinutes;




  Future<void> initialize() async {

    Stream<Option<LastPoint>> lastPointStream = _streamLastPoint(userId);

    _lastPointSub = lastPointStream.listen((option) {

      if (option case Some(value: LastPoint lastPoint)) {

        if (kDebugMode) {
          debugPrint("[DEBUG] Last point stream received: ${option.unwrap()}");
        }

        LastPointViewModel lastPointViewModel = lastPoint.toViewModel();
        setLastPoint(lastPointViewModel);
      } else {
        setLastPoint(null);
      }
    });

    Stream<int> batchCountStream = _streamBatchPointCount(userId);

    _batchCountSub = batchCountStream.listen((count) {
      if (kDebugMode) {
        debugPrint("[DEBUG] Batch count stream received: $count");
      }
      setBatchPointCount(count);
    });

    // Retrieve settings
    TrackerSettings settings = await _getTrackerSettings(userId);
    _applySettings(settings);
    await _getTrackRecordingStatus();


    setIsRetrievingSettings(false);
  }

  void _applySettings(TrackerSettings s) {
    _trackerSettings = s;

    _isTrackingAutomatically = s.automaticTracking;
    _maxPointsPerBatch = s.pointsPerBatch;
    _trackingFrequency = s.trackingFrequency;
    _locationAccuracy = s.locationPrecision;
    _minimumPointDistance = s.minimumPointDistance;
    _batchExpirationMinutes = s.batchExpirationMinutes;
    _deviceId = s.deviceId;

    safeNotifyListeners();
  }

  Future<void> _getTrackRecordingStatus() async {
    Option<Track> trackResult = await _getActiveTrackUseCase(userId);

    if (trackResult case Some(value: Track track)) {
      TrackViewModel trackVm = track.toViewModel();
      setCurrentTrack(trackVm);
      setIsRecording(true);
    }
  }

  void toggleRecording() async {
    if (isRecording) {
      _endTrackUseCase(userId);
    } else {
      Track track = await _startTrackUseCase(userId);
      TrackViewModel trackVm = track.toViewModel();
      setCurrentTrack(trackVm);
    }

    setIsRecording(!isRecording);
  }

  void setLastPoint(LastPointViewModel? point) {
    _lastPoint = point;
    safeNotifyListeners();
  }

  void setHideLastPoint(bool trueOrFalse) {
    _hideLastPoint = trueOrFalse;
    safeNotifyListeners();
  }

  void setBatchPointCount(int value) {
    _batchPointCount = value;
    safeNotifyListeners();
  }

  void setIsRetrievingSettings(bool trueOrFalse) {
    _isRetrievingSettings = trueOrFalse;
    safeNotifyListeners();
  }

  Future<Result<(), String>> trackPoint() async {
    setIsTracking(true);

    Result<LocalPoint, String> pointResult = await _createPointFromGps(userId);

    if (pointResult case Ok(value: LocalPoint pointEntity)) {
      final storeResult = await _storePoint(pointEntity);

      if (storeResult case Err(value: String storeError)) {
        if (kDebugMode) {
          debugPrint("[DEBUG] Failed to store point: $storeError");
        }
        setIsTracking(false);
        return Err("Failed to store point: $storeError");
      }

      LocalPointViewModel point = pointEntity.toViewModel();

      String timestamp = point.properties.timestamp;
      double longitude = point.geometry.longitude;
      double latitude = point.geometry.latitude;

      LastPointViewModel lastPoint = LastPointViewModel(
          rawTimestamp: timestamp, longitude: longitude, latitude: latitude);

      setLastPoint(lastPoint);

      setIsTracking(false);
      return const Ok(());
    }

    String error = pointResult.unwrapErr();

    if (kDebugMode) {
      debugPrint("[DEBUG] Failed to create point: $error");
    }

    setIsTracking(false);
    return Err("Failed to create point: $error");
  }

  void setIsTracking(bool trueOrFalse) {
    _isTracking = trueOrFalse;
    safeNotifyListeners();
  }

  Future<void> setMaxPointsPerBatch(int? amount) async {
    final trackerSettingsCopy = _trackerSettings;

    if (trackerSettingsCopy == null) {
      return;
    }

    final newValue = (amount ?? 50).clamp(minBatch, maxBatch);

    final updated = trackerSettingsCopy.copyWith(pointsPerBatch: newValue);

    _applySettings(updated);
    await _saveTrackerSettings(updated);
  }

  /// Sets the batch expiration in minutes. Pass `null` to disable.
  Future<void> setBatchExpirationMinutes(int? minutes) async {
    final trackerSettingsCopy = _trackerSettings;
    if (trackerSettingsCopy == null) return;

    final updated = trackerSettingsCopy.copyWith(
      batchExpirationMinutes: () => minutes,
    );

    _applySettings(updated);
    await _saveTrackerSettings(updated);
    await _syncBatchExpirationWorker(updated);
  }

  Future<void> _syncBatchExpirationWorker(TrackerSettings settings) async {
    if (settings.isBatchExpirationEnabled &&
        settings.batchExpirationMinutes != null) {
      await ExpiredBatchWorkScheduler.register(
        settings.batchExpirationMinutes!,
      );
      return;
    }

    await ExpiredBatchWorkScheduler.cancel();
  }


  Future<bool> requestConsentFromUser(String message) {
    _consentResponseCompleter = Completer<bool>();
    _consentPromptController.add(message);
    return _consentResponseCompleter!.future;
  }

  void handleConsentResponse(bool accepted) {
    _consentResponseCompleter?.complete(accepted);
    _consentResponseCompleter = null;
  }

  Future<bool> _requestNotificationPermission() async {
    final status = await Permission.notification.status;

    if (status.isGranted) {
      return true;
    }

    final result = await Permission.notification.request();
    return result.isGranted;
  }

  Future<bool> _shouldShowConsentDialog() async {
    final location = await Permission.locationAlways.status;
    final notifications = await Permission.notification.status;

    final hasLocation = location.isGranted;
    final hasNotifications = notifications.isGranted;

    final batteryExcluded = !await _checkSystemSettings();

    return !hasLocation || !hasNotifications || !batteryExcluded;
  }

  Future<void> setAutomaticTracking(bool enable) async {

    final trackerSettingsCopy = _trackerSettings;

    if (trackerSettingsCopy == null) {
      return;
    }

    final TrackerSettings updated = trackerSettingsCopy.copyWith(
        automaticTracking: enable);

    _applySettings(updated);
    await _saveTrackerSettings(updated);
  }

  void setIsUpdatingTracking(bool trueOrFalse) {
    _isUpdatingTracking = trueOrFalse;
    safeNotifyListeners();
  }

  Future<Result<(), String>> toggleAutomaticTracking(bool enable) async {

    if (_isUpdatingTracking) {
      return Err("Tracking update already in progress.");
    }
    setIsUpdatingTracking(true);
    await Future.delayed(const Duration(milliseconds: 500));
    setAutomaticTracking(enable);

    if (enable) {
      final bool shouldShowConsentDialog = await _shouldShowConsentDialog();
      if (shouldShowConsentDialog) {
        final bool confirmed = await requestConsentFromUser(
            'To enable automatic background tracking, Dawarich needs your permission.\n\n'
                'It will request background location access, notification permission, and system exclusions.'
        );

        if (!confirmed) {
          await setAutomaticTracking(false);
          setIsUpdatingTracking(false);
          return Err("Permission setup cancelled by user.");
        }
      }

      final permissionResult = await _requestTrackingPermissions();
      if (permissionResult case Err(value: final message)) {
        await setAutomaticTracking(false);
        setIsUpdatingTracking(false);
        return Err(message);
      }

      final notificationGranted = await _requestNotificationPermission();
      if (!notificationGranted) {
        await setAutomaticTracking(false);
        setIsUpdatingTracking(false);
        return Err("Notification permission is required.");
      }

      final serviceResult = await BackgroundTrackingService.start();
      await _openSystemSettings();
      await setAutomaticTracking(enable);
      debugPrint("[TrackerPageViewModel] Background start result: $serviceResult");

      final needsFix = await _checkSystemSettings();

      if (serviceResult case Err(value: final message)) {
        if (needsFix) {
          _consentPromptController.add(
              'Some system settings still need your help to enable reliable background tracking.\n\n'
                  'Please check location permission, battery optimization, and notification settings.'
          );
        }

        await setAutomaticTracking(false);
        setIsUpdatingTracking(false);

        return Err("Failed to start background service: $message");
      }

    } else {
      BackgroundTrackingService.stop();
    }

    setIsUpdatingTracking(false);
    return Ok(());
  }

  Future<Result<(), String>> _requestTrackingPermissions() async {

    final locationStatus = await Permission.locationAlways.request();

    if (locationStatus.isPermanentlyDenied) {
      return Err("Permission is permanently denied. Please enable it manually in system settings.");
    }

    if (!locationStatus.isGranted) {
      return Err("Location permission 'Always' is required for background tracking.");
    }

    return const Ok(());
  }

  Future<void> setTrackingFrequency(int? seconds) async {

    final TrackerSettings? copy = _trackerSettings;

    if (copy == null) {
      return;
    }

    final updated = copy.copyWith(trackingFrequency: seconds);
    _applySettings(updated);
    await _saveTrackerSettings(updated);
  }

  Future<void> setLocationAccuracy(LocationPrecision accuracy) async {

    final TrackerSettings? copy = _trackerSettings;

    if (copy == null) {
      return;
    }

    final updated = copy.copyWith(locationPrecision: accuracy);
    _applySettings(updated);
    await _saveTrackerSettings(updated);
  }


  Future<void> setMinimumPointDistance(int meters) async {

    final TrackerSettings? copy = _trackerSettings;

    if (copy == null) {
      return;
    }

    final updated = copy.copyWith(minimumPointDistance: meters);
    _applySettings(updated);
    await _saveTrackerSettings(updated);
  }

  Future<void> setDeviceId(String id) async {

    final TrackerSettings? copy = _trackerSettings;

    if (copy == null) {
      return;
    }

    final updated = copy.copyWith(deviceId: id);
    _applySettings(updated);
    await _saveTrackerSettings(updated);
  }

  Future<void> resetDeviceId() async {

    final TrackerSettings? copy = _trackerSettings;

    if (copy == null) {
      return;
    }

    final String deviceModel = await _getDeviceModel();
    final updated = copy.copyWith(deviceId: deviceModel);
    _applySettings(updated);
    await _saveTrackerSettings(updated);
  }

  List<Map<String, dynamic>> get accuracyOptions {
    if (Platform.isIOS) {
      return [
        {"label": "Low Power", "value": LocationPrecision.lowPower},
        {"label": "Balanced", "value": LocationPrecision.balanced},
        {"label": "High", "value": LocationPrecision.high},
        {"label": "Best", "value": LocationPrecision.best},
      ];
    } else if (Platform.isAndroid) {
      return [
        {"label": "Low Power", "value": LocationPrecision.lowPower},
        {"label": "Balanced", "value": LocationPrecision.balanced},
        {"label": "High", "value": LocationPrecision.high},
        {"label": "Best", "value": LocationPrecision.best},
      ];
    }
    return [];
  }

  @override
  void dispose() {

    if (kDebugMode) {
      debugPrint("[TrackerPageViewModel] Disposing viewmodel...");
    }

    _settingsSub?.cancel();
    _lastPointSub?.cancel();
    _batchCountSub?.cancel();
    _consentPromptController.close();
    super.dispose();
  }
}
