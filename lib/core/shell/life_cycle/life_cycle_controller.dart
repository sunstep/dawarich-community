
import 'package:dawarich/core/di/providers/session_providers.dart';
import 'package:dawarich/core/di/providers/settings_providers.dart';
import 'package:dawarich/core/routing/app_router.dart';
import 'package:dawarich/features/biometric_lock/domain/app_lock_timestamp_tracker.dart';
import 'package:dawarich/features/stats/presentation/coordinators/stats_auto_refresh_coordinator.dart';
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
}