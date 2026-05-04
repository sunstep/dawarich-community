
import 'dart:async';

import 'package:dawarich/core/di/providers/session_providers.dart';
import 'package:dawarich/core/di/providers/settings_providers.dart';
import 'package:dawarich/core/di/providers/usecase_providers.dart';
import 'package:dawarich/core/routing/app_router.dart';
import 'package:dawarich/features/biometric_lock/domain/app_lock_timestamp_tracker.dart';
import 'package:dawarich/features/stats/presentation/coordinators/stats_auto_refresh_coordinator.dart';
import 'package:dawarich/features/tracking/application/services/background_tracking_service.dart';
import 'package:dawarich/main.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

final class AppLifecycleController with WidgetsBindingObserver {
  final ProviderContainer _container;

  AppLifecycleController(this._container);

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.paused) {
      AppLockTimestampTracker.instance.onPaused();
    }

    if (state == AppLifecycleState.resumed) {
      _container.read(statsAutoRefreshCoordinatorProvider).onAppResumed();
      _checkBiometricLockOnResume();
      unawaited(_restartTrackerIfNeeded());
    }
  }

  Future<void> _checkBiometricLockOnResume() async {
    try {
      final isEnabled =
          await _container.read(isBiometricLockEnabledUseCaseProvider.future);
      final getTimeout =
          await _container.read(getLockTimeoutUseCaseProvider.future);
      final userId =
          await _container.read(sessionUserIdProvider.future);

      if (userId == null) return;

      final enabled = await isEnabled(userId);
      if (!enabled) return;

      final timeoutSeconds = await getTimeout(userId);
      final shouldLock = AppLockTimestampTracker.instance.shouldLock(
        timeoutSeconds: timeoutSeconds,
      );

      if (shouldLock) {
        // Only navigate to lock if not already on the lock screen.
        final currentRoute = appRouter.current.name;
        if (currentRoute != BiometricLockRoute.name) {
          appRouter.replaceAll([const BiometricLockRoute()]);
        }
      }
    } catch (e) {
      if (kDebugMode) {
        debugPrint('[AppLifecycle] biometric lock check failed: $e');
      }
    }
  }

  /// Checks whether automatic tracking is enabled and the background service
  /// has died, and if so restarts it immediately.
  ///
  /// Called on every [AppLifecycleState.resumed] event so the tracker is
  /// restored the moment the user opens the app rather than waiting up to
  /// 15 minutes for the WorkManager watchdog to fire.
  Future<void> _restartTrackerIfNeeded() async {
    try {
      final userId = await _container.read(sessionUserIdProvider.future);
      if (userId == null) return;

      final getSettings =
          await _container.read(getTrackerSettingsUseCaseProvider.future);
      final settings = await getSettings(userId);

      if (!settings.automaticTracking) return;

      final isRunning = await BackgroundTrackingService.isRunning();
      if (isRunning) return;

      if (kDebugMode) {
        debugPrint('[AppLifecycle] Tracker not running on resume — restarting...');
      }

      // Use startServiceDirect() to skip permission/location-service checks.
      // Permissions are already granted if automaticTracking is enabled.
      final started = await BackgroundTrackingService.startServiceDirect();

      if (kDebugMode) {
        debugPrint('[AppLifecycle] Tracker restart on resume result: $started');
      }
    } catch (e) {
      if (kDebugMode) {
        debugPrint('[AppLifecycle] Tracker restart check failed: $e');
      }
    }
  }
}