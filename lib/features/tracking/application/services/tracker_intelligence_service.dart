import 'dart:math' as math;

import 'package:dawarich/features/tracking/domain/enum/auto_tracking_runtime_mode.dart';
import 'package:dawarich/features/tracking/domain/enum/battery_state.dart';
import 'package:dawarich/features/tracking/domain/enum/connectivity_kind.dart';
import 'package:dawarich/features/tracking/domain/models/location_fix.dart';
import 'package:flutter/foundation.dart';
import 'package:geolocator/geolocator.dart';


final class TrackerIntelligenceService {
  AutoTrackingRuntimeMode _currentMode = AutoTrackingRuntimeMode.active;
  DateTime? _lastMeaningfulMovementTime;
  LocationFix? _lastObservedFix;

  DateTime? _monitorEnteredTime;
  bool _isOnWifi = false;
  bool _wasCharging = false;

  // Active → monitor after this long without meaningful movement.
  static const Duration activeToMonitorStillness = Duration(minutes: 2);

  // Monitor → passive after this long without confirmed movement.
  static const Duration monitorIdleTimeout = Duration(minutes: 3);

  static const double passiveWakeDistanceMeters = 80;
  static const double passiveWakeSpeedMps = 0.5;

  // Vehicle-level speed that bypasses monitor and goes straight to active.
  static const double passiveDirectActiveSpeedMps = 5.0;

  // Net speed in monitor mode to promote to active. Roughly a slow walk.
  static const double monitorPromoteSpeedMps = 0.8;

  // GPS displacement fallback for monitor → active when speedMps is unreported.
  static const double monitorPromoteDistanceMeters = 150.0;

  // Minimum net speed to keep the active-mode stillness counter from ticking.
  static const double activeKeepSpeedMps = 0.5;

  // Minimum displacement between consecutive active fixes to count as real movement.
  static const double activeKeepDistanceMeters = 20.0;

  int _consecutiveZeroSpeedFixes = 0;

  AutoTrackingRuntimeMode get currentMode => _currentMode;
  DateTime? get lastMeaningfulMovementTime => _lastMeaningfulMovementTime;

  void reset() {
    _currentMode = AutoTrackingRuntimeMode.active;
    _lastMeaningfulMovementTime = null;
    _lastObservedFix = null;
    _monitorEnteredTime = null;
    _consecutiveZeroSpeedFixes = 0;
    _isOnWifi = false;
    _wasCharging = false;
  }

  AutoTrackingRuntimeMode notifyMotionTransitionDetected() {
    if (kDebugMode) {
      debugPrint(
        '[TrackerIntelligence] Motion transition event received '
        '(current mode: $_currentMode)',
      );
    }

    if (_currentMode == AutoTrackingRuntimeMode.passive) {
      _lastMeaningfulMovementTime = null;
      _lastObservedFix = null;
      _setMode(AutoTrackingRuntimeMode.monitor);

      if (kDebugMode) {
        debugPrint('[TrackerIntelligence] Motion transition: passive → monitor');
      }
    } else {
      if (kDebugMode) {
        debugPrint(
          '[TrackerIntelligence] Motion transition ignored in $_currentMode '
          '(GPS manages keep-alive)',
        );
      }
    }

    return _currentMode;
  }

  /// Records the initial connectivity state without triggering a mode change.
  ///
  /// Must be called once at startup before [notifyConnectivityChanged] so that
  /// subsequent Wi-Fi drop/connect events have a correct baseline to compare
  /// against. connectivity_plus fires the current state synchronously on
  /// subscription; that first event should call this instead of
  /// [notifyConnectivityChanged] to avoid a spurious mode change on startup.
  void seedConnectivity(ConnectivityKind kind) {
    _isOnWifi = kind == ConnectivityKind.wifi;
    if (kDebugMode) {
      debugPrint(
        '[TrackerIntelligence] Connectivity baseline seeded: $kind '
        '(isOnWifi=$_isOnWifi)',
      );
    }
  }

  AutoTrackingRuntimeMode notifyConnectivityChanged(ConnectivityKind kind) {
    final wasOnWifi = _isOnWifi;
    _isOnWifi = kind == ConnectivityKind.wifi;

    if (_isOnWifi && !wasOnWifi) {
      if (_currentMode == AutoTrackingRuntimeMode.active) {
        _lastMeaningfulMovementTime = null;
        _lastObservedFix = null;
        _setMode(AutoTrackingRuntimeMode.monitor);
      }
    } else if (!_isOnWifi && wasOnWifi) {
      // WiFi dropped: may mean we left a known location. Wake from passive only.
      if (_currentMode == AutoTrackingRuntimeMode.passive) {
        _lastMeaningfulMovementTime = null;
        _lastObservedFix = null;
        _setMode(AutoTrackingRuntimeMode.monitor);
      }
    }

    return _currentMode;
  }

  AutoTrackingRuntimeMode notifyBatteryStateChanged(BatteryState state) {
    final wasCharging = _wasCharging;
    _wasCharging = state == BatteryState.charging ||
        state == BatteryState.full ||
        state == BatteryState.connectedNotCharging;

    final justUnplugged = wasCharging && state == BatteryState.discharging;

    if (justUnplugged && _currentMode == AutoTrackingRuntimeMode.passive) {
      _lastMeaningfulMovementTime = null;
      _lastObservedFix = null;
      _setMode(AutoTrackingRuntimeMode.monitor);
    }

    return _currentMode;
  }

  AutoTrackingRuntimeMode evaluateFix(LocationFix fix) {
    final lastFix = _lastObservedFix;
    double distanceMeters = 0;

    if (lastFix != null) {
      distanceMeters = Geolocator.distanceBetween(
        lastFix.latitude,
        lastFix.longitude,
        fix.latitude,
        fix.longitude,
      );
    }

    final clampedSpeedAccuracy = math.max(0.0, fix.speedAccuracyMps);
    final netSpeedMps = math.max(0.0, fix.speedMps - clampedSpeedAccuracy);
    final combinedAccuracyMeters =
        (lastFix?.hAccuracyMeters ?? 0.0) + fix.hAccuracyMeters;

    _lastObservedFix = fix;

    switch (_currentMode) {
      case AutoTrackingRuntimeMode.passive:
        return _evaluatePassive(fix, distanceMeters, netSpeedMps);
      case AutoTrackingRuntimeMode.monitor:
        return _evaluateMonitor(fix, distanceMeters, netSpeedMps, combinedAccuracyMeters);
      case AutoTrackingRuntimeMode.active:
        return _evaluateActive(fix, distanceMeters, netSpeedMps, combinedAccuracyMeters);
    }
  }

  AutoTrackingRuntimeMode _evaluatePassive(
    LocationFix fix,
    double distanceMeters,
    double netSpeedMps,
  ) {
    if (netSpeedMps >= passiveDirectActiveSpeedMps) {
      if (kDebugMode) {
        debugPrint(
          '[TrackerIntelligence] Passive → active (vehicle speed: '
          '${netSpeedMps.toStringAsFixed(1)} m/s)',
        );
      }
      _lastMeaningfulMovementTime = fix.timestampUtc;
      _setMode(AutoTrackingRuntimeMode.active);
      return _currentMode;
    }

    final isSpeedSignificant = netSpeedMps >= passiveWakeSpeedMps;
    final isDistanceSignificant = distanceMeters >= passiveWakeDistanceMeters;

    if (isSpeedSignificant || isDistanceSignificant) {
      if (kDebugMode) {
        debugPrint(
          '[TrackerIntelligence] Passive → monitor (fix fallback: '
          'speed=${netSpeedMps.toStringAsFixed(1)} m/s, '
          'distance=${distanceMeters.toStringAsFixed(0)} m)',
        );
      }
      _lastMeaningfulMovementTime = fix.timestampUtc;
      _setMode(AutoTrackingRuntimeMode.monitor);
    }

    return _currentMode;
  }

  AutoTrackingRuntimeMode _evaluateMonitor(
    LocationFix fix,
    double distanceMeters,
    double netSpeedMps,
    double combinedAccuracy,
  ) {
    if (fix.speedMps <= 0.0) {
      _consecutiveZeroSpeedFixes++;
    } else {
      _consecutiveZeroSpeedFixes = 0;
    }

    if (kDebugMode && _consecutiveZeroSpeedFixes > 0) {
      debugPrint(
        '[TrackerIntelligence] Monitor: $_consecutiveZeroSpeedFixes consecutive '
        'zero-speed fixes',
      );
    }

    if (netSpeedMps >= monitorPromoteSpeedMps) {
      if (kDebugMode) {
        debugPrint(
          '[TrackerIntelligence] Monitor → active (speed: '
          '${netSpeedMps.toStringAsFixed(1)} m/s)',
        );
      }
      _consecutiveZeroSpeedFixes = 0;
      _lastMeaningfulMovementTime = fix.timestampUtc;
      _setMode(AutoTrackingRuntimeMode.active);
      return _currentMode;
    }

    // Speed was unreported; check displacement as a fallback.
    if (distanceMeters >= monitorPromoteDistanceMeters) {
      if (kDebugMode) {
        debugPrint(
          '[TrackerIntelligence] Monitor → active (displacement fallback: '
          '${distanceMeters.toStringAsFixed(0)} m)',
        );
      }
      _consecutiveZeroSpeedFixes = 0;
      _lastMeaningfulMovementTime = fix.timestampUtc;
      _setMode(AutoTrackingRuntimeMode.active);
      return _currentMode;
    }

    // Safety net in case the external idle timer is delayed by doze mode.
    final enteredTime = _monitorEnteredTime;
    if (enteredTime != null) {
      final timeInMonitor = fix.timestampUtc.difference(enteredTime);
      if (timeInMonitor >= monitorIdleTimeout) {
        _setMode(AutoTrackingRuntimeMode.passive);
        return _currentMode;
      }
    }

    return _currentMode;
  }

  AutoTrackingRuntimeMode _evaluateActive(
    LocationFix fix,
    double distanceMeters,
    double netSpeedMps,
    double combinedAccuracy,
  ) {
    // Only count movement if displacement exceeds combined position uncertainty.
    final effectiveDistanceThreshold =
        math.max(activeKeepDistanceMeters, combinedAccuracy * 1.0);
    final isDistanceConfident = distanceMeters >= effectiveDistanceThreshold;
    final isSpeedConfident = netSpeedMps >= activeKeepSpeedMps;

    if (isDistanceConfident || isSpeedConfident) {
      _lastMeaningfulMovementTime = fix.timestampUtc;
      return _currentMode;
    }

    final lastMovementTime = _lastMeaningfulMovementTime;
    if (lastMovementTime == null) {
      _lastMeaningfulMovementTime = fix.timestampUtc;
      return _currentMode;
    }

    final stillFor = fix.timestampUtc.difference(lastMovementTime);
    if (stillFor >= activeToMonitorStillness) {
      _setMode(AutoTrackingRuntimeMode.monitor);
    }

    return _currentMode;
  }

  void forceMode(AutoTrackingRuntimeMode mode) {
    _setMode(mode);
    _lastObservedFix = null;
  }

  void _setMode(AutoTrackingRuntimeMode mode) {
    if (_currentMode == mode) {
      return;
    }
    _currentMode = mode;

    if (mode == AutoTrackingRuntimeMode.monitor) {
      _monitorEnteredTime = DateTime.now().toUtc();
      _consecutiveZeroSpeedFixes = 0;
    } else {
      _monitorEnteredTime = null;
      _consecutiveZeroSpeedFixes = 0;
    }
  }
}