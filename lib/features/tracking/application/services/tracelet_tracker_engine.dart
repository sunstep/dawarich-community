
import 'dart:async';

import 'package:dawarich/core/constants/notification.dart';
import 'package:dawarich/features/tracking/application/interfaces/tracker_engine_interface.dart';
import 'package:dawarich/features/tracking/domain/enum/location_precision.dart';
import 'package:dawarich/features/tracking/domain/enum/tracking_mode.dart';
import 'package:dawarich/features/tracking/domain/models/location_fix.dart';
import 'package:dawarich/features/tracking/domain/models/tracker_settings.dart';

import 'package:flutter/foundation.dart';
import 'package:tracelet/tracelet.dart' as tl;

final class TraceletTrackerEngine implements ITrackerEngine {

  late final int _instanceId = identityHashCode(this);
  late String debugPrefix = "[TraceletTrackerEngine#$_instanceId]";

  static const int _streamLocationUpdateIntervalMs = 5000;
  static const int _fastestStreamLocationUpdateIntervalMs = 2500;

  static bool _isTraceletLocationCallbackRegistered = false;
  static bool _isTraceletHeartbeatCallbackRegistered = false;
  static String? _lastLocationUuid;
  static LocationFixHandler? _locationFixHandler;
  static HeartbeatHandler? _heartbeatHandler;

  void _registerTraceletLocationCallbackOnce() {
    if (_isTraceletLocationCallbackRegistered) {
      return;
    }

    _isTraceletLocationCallbackRegistered = true;

    tl.Tracelet.onLocation((tl.Location location) {
      if (kDebugMode) {
        debugPrint(
          '[TraceletTrackerEngine] Tracelet.onLocation fired: '
              'uuid=${location.uuid}, '
              'lat=${location.coords.latitude}, '
              'lon=${location.coords.longitude}, '
              'accuracy=${location.coords.accuracy}, '
              'speed=${location.coords.speed}, '
              'source=${location.locationSource}, '
              'timestamp=${location.timestamp}',
        );
      }

      if (_lastLocationUuid == location.uuid) {
        if (kDebugMode) {
          debugPrint(
            '[TraceletTrackerEngine] Duplicate Tracelet location ignored: '
                '${location.uuid}',
          );
        }

        return;
      }

      _lastLocationUuid = location.uuid;

      final LocationFix locationFix = _mapLocationFix(location);
      final LocationFixHandler? handler = _locationFixHandler;

      if (handler == null) {
        if (kDebugMode) {
          debugPrint(
            '[TraceletTrackerEngine] Dropping Tracelet location because '
                'no app handler is registered.',
          );
        }

        return;
      }

      unawaited(
        handler(locationFix).catchError((Object error, StackTrace stackTrace) {
          if (kDebugMode) {
            debugPrint('[TraceletTrackerEngine] Location handler failed: $error');
            debugPrint('$stackTrace');
          }
        }),
      );
    });
  }

  void _registerTraceletHeartbeatOnce() {

    if (_isTraceletHeartbeatCallbackRegistered) {
      return;
    }

    _isTraceletHeartbeatCallbackRegistered = true;

    tl.Tracelet.onHeartbeat((tl.HeartbeatEvent heartbeat) {
      if (kDebugMode) {
        debugPrint(
          '[TraceletTrackerEngine] Tracelet.onHeartbeat fired: '
        );
      }

      final HeartbeatHandler? handler = _heartbeatHandler;

      if (handler == null) {
        if (kDebugMode) {
          debugPrint(
            '[TraceletTrackerEngine] Dropping Tracelet heartbeat because '
                'no handler is registered.',
          );
        }

        return;
      }

      unawaited(
        handler().catchError((Object error, StackTrace stackTrace) {
          if (kDebugMode) {
            debugPrint('[TraceletTrackerEngine] Heartbeat handler failed: $error');
            debugPrint('$stackTrace');
          }
        }),
      );
    });
  }

  LocationFix _mapLocationFix(tl.Location location) {

    final tl.Coords coords = location.coords;

    return LocationFix(
      latitude: coords.latitude,
      longitude: coords.longitude,
      timestampUtc: _parseTimestampUtc(location.timestamp),
      hAccuracyMeters: coords.accuracy,
      altitudeMeters: coords.altitude,
      altitudeAccuracyMeters: coords.altitudeAccuracy,
      speedMps: coords.speed,
      speedAccuracyMps: coords.speedAccuracy,
      headingDegrees: coords.heading,
      headingAccuracyDegrees: coords.headingAccuracy,
      provider: location.locationSource,
      isMocked: location.isMock,
    );
  }

  DateTime _parseTimestampUtc(String timestamp) {
    return DateTime.tryParse(timestamp)?.toUtc() ?? DateTime.now().toUtc();
  }

  @override
  void setLocationFixHandler(LocationFixHandler? handler) {
    _locationFixHandler = handler;

    if (kDebugMode) {
      debugPrint(
        '[TraceletTrackerEngine] Location stream handler '
            '${handler == null ? 'cleared' : 'registered'}.',
      );
    }
  }

  @override
  void setHeartbeatHandler(HeartbeatHandler? handler) {

    _heartbeatHandler = handler;

    if (kDebugMode) {
      debugPrint(
        '[TraceletTrackerEngine] Heartbeat handler '
            '${handler == null ? 'cleared' : 'registered'}.',
      );
    }
  }

  // Todo: take ownership of the state model
  @override
  Future<tl.State> startTracking(TrackerSettings settings) async {

    if (settings.trackingMode == TrackingMode.timer) {

      if (kDebugMode) {
        debugPrint('$debugPrefix Starting Tracelet periodic mode...');
      }

      return await tl.Tracelet.startPeriodic();
    }

    if (kDebugMode) {
      debugPrint('$debugPrefix Starting Tracelet automatic mode...');
    }

    return await tl.Tracelet.start();
  }

  @override
  Future<tl.State> stopTracking() async {

    return await tl.Tracelet.stop();
  }

  @override
  Future<tl.State> configure(TrackerSettings settings) async {

    final tl.Config config = _buildConfiguration(settings);
    _registerTraceletLocationCallbackOnce();
    _registerTraceletHeartbeatOnce();
    return await tl.Tracelet.ready(config);
  }

  @override
  Future<tl.State> updateConfiguration(TrackerSettings settings) async {

    final tl.Config config = _buildConfiguration(settings);
    return await tl.Tracelet.setConfig(config);
  }

  tl.Config _buildConfiguration(TrackerSettings settings) {

    final bool isAutoMode = settings.trackingMode == TrackingMode.automatic;

    final tl.GeoConfig geoConfig = tl.GeoConfig(
      desiredAccuracy: _mapDesiredAccuracy(settings.locationPrecision),
      distanceFilter:
        settings.minimumPointDistance > 0 ?
        settings.minimumPointDistance.toDouble() :
        20.0,
      stationaryRadius: 25.0,
      locationTimeout: 60,
      disableElasticity: false,
      elasticityMultiplier: 1.0,
      stopAfterElapsedMinutes: -1,
      maxMonitoredGeofences: -1,
      enableTimestampMeta: false,
      enableAdaptiveMode: isAutoMode,
      periodicLocationInterval: _resolvePeriodicLocationInterval(settings),
      periodicDesiredAccuracy: _mapDesiredAccuracy(settings.locationPrecision),
      enableSparseUpdates: false,
      sparseDistanceThreshold: 50.0,
      sparseMaxIdleSeconds: 300,
      batteryBudgetPerHour: 2.0,
      enableDeadReckoning: false,
      deadReckoningActivationDelay: 0,
      deadReckoningMaxDuration: 0,
      filter: const tl.LocationFilter(),
      resolveAddress: false,

    );

    final tl.AppConfig appConfig = tl.AppConfig(
      stopOnTerminate: false,
      startOnBoot: true,
      heartbeatInterval: 30,
      schedule: const <String>[],
    );

    final tl.ForegroundServiceConfig foregroundServiceConfig = tl.ForegroundServiceConfig(
      enabled: true,
      channelId: NotificationConstants.channelId,
      channelName: NotificationConstants.channelName,
      notificationTitle: NotificationConstants.notificationTitle,
      notificationText: NotificationConstants.notificationContent,
      notificationColor: null,
      notificationSmallIcon: NotificationConstants.notificationIcon,
      notificationLargeIcon: NotificationConstants.notificationIcon,
      notificationPriority: tl.NotificationPriority.low,
      notificationOngoing: true,
      showNotificationOnPauseOnly: false,
      actions: const <String>[],

    );

    final tl.AndroidConfig androidConfig = tl.AndroidConfig(
      locationUpdateInterval: _streamLocationUpdateIntervalMs,
      fastestLocationUpdateInterval: _fastestStreamLocationUpdateIntervalMs,
      deferTime: 0,
      allowIdenticalLocations: true,
      geofenceModeHighAccuracy: false,
      periodicUseForegroundService: true,
      periodicUseExactAlarms: false,
      scheduleUseAlarmManager: false,
      releaseWakelockWhenStationary: false,
      foregroundService: foregroundServiceConfig,
    );

    final tl.IosConfig iosConfig = tl.IosConfig(
      activityType: tl.LocationActivityType.other,
      useSignificantChangesOnly: false,
      showsBackgroundLocationIndicator: false,
      pausesLocationUpdatesAutomatically: false,
      locationAuthorizationRequest: tl.LocationAuthorizationRequest.always,
      disableLocationAuthorizationAlert: false,
      preventSuspend: true,
    );


    final tl.LoggerConfig loggerConfig = tl.LoggerConfig(
      logLevel: kDebugMode ? tl.LogLevel.debug : tl.LogLevel.warning,
      logMaxDays: 3,
      debug: kDebugMode
    );

    final tl.MotionConfig motionConfig = tl.MotionConfig();

    final tl.GeofenceConfig geofenceConfig = tl.GeofenceConfig();
    final tl.PersistenceConfig persistenceConfig = tl.PersistenceConfig();
    final tl.AuditConfig auditConfig = tl.AuditConfig();
    final tl.PrivacyZoneConfig privacyZoneConfig = tl.PrivacyZoneConfig();
    final tl.SecurityConfig securityConfig = tl.SecurityConfig();
    final tl.AttestationConfig attestationConfig = tl.AttestationConfig();
    final tl.TelematicsConfig telematicsConfig = tl.TelematicsConfig();
    final tl.ClassifierConfig classifierConfig = tl.ClassifierConfig();
    final tl.ImpactConfig impactConfig = tl.ImpactConfig();

    return tl.Config(
      geo: geoConfig,
      app: appConfig,
      android: androidConfig,
      ios: iosConfig,
      logger: loggerConfig,
      motion: motionConfig,
      geofence: geofenceConfig,
      persistence: persistenceConfig,

      audit: auditConfig,
      privacyZone: privacyZoneConfig,
      security: securityConfig,
      attestation: attestationConfig,
      telematics: telematicsConfig,
      classifier: classifierConfig,
      impact: impactConfig,
    );
  }

  // A small helper to ensure 0 doesn't get passed
  int _resolvePeriodicLocationInterval(TrackerSettings settings) {

    if (settings.trackingMode == TrackingMode.timer) {
      return settings.trackingFrequency;
    }

    return 60;
  }

  tl.DesiredAccuracy _mapDesiredAccuracy(
      LocationPrecision precision,
      ) {
    return switch (precision) {
      LocationPrecision.lowPower => tl.DesiredAccuracy.low,
      LocationPrecision.balanced => tl.DesiredAccuracy.medium,
      LocationPrecision.high => tl.DesiredAccuracy.high,
      LocationPrecision.best => tl.DesiredAccuracy.high,
    };
  }
}