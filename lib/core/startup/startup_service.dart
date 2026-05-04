import 'dart:async';

import 'package:dawarich/core/background/schedulers/tracking_watchdog_scheduler.dart';
import 'package:dawarich/core/background/workmanager/stats_refresh_worker.dart';
import 'package:dawarich/core/di/providers/session_providers.dart';
import 'package:dawarich/core/di/providers/usecase_providers.dart';
import 'package:dawarich/core/di/providers/version_check_providers.dart';
import 'package:dawarich/core/domain/models/user.dart';
import 'package:dawarich/core/routing/app_router.dart';
import 'package:dawarich/core/shell/life_cycle/life_cycle_controller.dart';
import 'package:dawarich/core/di/providers/settings_providers.dart';
import 'package:dawarich/features/biometric_lock/domain/app_lock_timestamp_tracker.dart';
import 'package:dawarich/features/onboarding/application/usecases/check_onboarding_permissions_usecase.dart';
import 'package:dawarich/features/tracking/application/services/background_tracking_service.dart';
import 'package:dawarich/features/tracking/application/usecases/notifications/initialize_tracker_notification_usecase.dart';
import 'package:dawarich/main.dart';
import 'package:dawarich_android_user_module/dawarich_android_user_module.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

final class StartupService {
  // Held so we can removeObserver before adding a new one on Activity recreation.
  // Without this, each boot cycle stacks another observer, causing duplicate
  // lifecycle callbacks (multiple stats refreshes, multiple biometric lock checks,
  // multiple onPaused timestamps) on every foreground/background transition.
  static AppLifecycleController? _lifecycleController;

  static Future<void> initializeAppFromContainer(ProviderContainer container) async {
    if (kDebugMode) {
      debugPrint('[StartupService] Initializing app...');
    }

    final initNotif = container.read(initializeTrackerNotificationServiceUseCaseProvider);
    await initNotif();


    final DawarichAndroidUserModule<User> sessionService =
        await container.read(sessionBoxProvider.future);
    final User? refreshedSessionUser = await sessionService.refreshSession();

    if (refreshedSessionUser != null) {
      if (kDebugMode) {
        debugPrint('[StartupService] User session found!');
      }

      sessionService.setUserId(refreshedSessionUser.id);

      // Initialize the lock tracker with persisted auth time for this user.
      final appSettingsRepo =
          await container.read(appSettingsRepositoryProvider.future);
      await AppLockTimestampTracker.instance.initialize(
        appSettingsRepo,
        refreshedSessionUser.id,
      );

      // Load the persisted theme preference.
      final getTheme =
          await container.read(getThemeModeUseCaseProvider.future);
      final savedTheme = await getTheme(refreshedSessionUser.id);
      container.read(themeModeProvider.notifier).set(
          themeModeFromString(savedTheme));
      // Fire-and-forget: purely advisory, fails open, and makes up to 3 serial
      // HTTP requests (server + GitHub x2) each with a 20 s Dio timeout.
      // Awaiting it would block the splash screen for up to 60 s.
      unawaited(() async {
        try {
          final refreshServerCompatibility =
              await container.read(refreshServerCompatibilityUseCaseProvider.future);
          await refreshServerCompatibility();
        } catch (e) {
          if (kDebugMode) {
            debugPrint('[StartupService] Version check failed (non-critical): $e');
          }
        }
      }());

      // Register the lifecycle observer so stats auto-refresh on app resume.
      // Remove any previously registered observer first — the Android Activity
      // can be recreated (config change, task restore) without killing the Dart
      // process, which causes initializeAppFromContainer to run again. Without
      // removal, observers accumulate and fire N times per lifecycle event.
      final previous = _lifecycleController;
      if (previous != null) {
        WidgetsBinding.instance.removeObserver(previous);
      }
      final lifecycleController = AppLifecycleController(container);
      _lifecycleController = lifecycleController;
      WidgetsBinding.instance.addObserver(lifecycleController);

      // Register WorkManager periodic task for background stats refresh.
      await initializeAndRegisterStatsWorker();

      // Register periodic batch upload worker (handles both threshold
      // and expiration uploads when the foreground service isn't running).
      await registerBatchUploadWorker();

      final getSettings =
      await container.read(getTrackerSettingsUseCaseProvider.future);

      final settings = await getSettings(refreshedSessionUser.id);

      if (settings.automaticTracking) {
        if (kDebugMode) {
          debugPrint('[StartupService] Registering tracking watchdog (startup sync).');
        }

        await TrackingWatchdogWorkScheduler.register();

        // If the foreground service is not alive (e.g. the process crashed or
        // was killed by the OEM), restart it immediately instead of waiting up
        // to 15 minutes for the WorkManager watchdog to fire.
        final isRunning = await BackgroundTrackingService.isRunning();
        if (!isRunning) {
          if (kDebugMode) {
            debugPrint('[StartupService] Auto tracking enabled but service not running — restarting now.');
          }
          final result = await BackgroundTrackingService.start();
          if (kDebugMode) {
            debugPrint('[StartupService] Tracking restart result: $result');
          }
        }
      } else {
        if (kDebugMode) {
          debugPrint('[StartupService] Cancelling tracking watchdog (startup sync).');
        }

        await TrackingWatchdogWorkScheduler.cancel();
      }


      final pendingRoute = InitializeTrackerNotificationServiceUseCase.pendingNotificationRoute;
      if (pendingRoute != null) {
        if (kDebugMode) {
          debugPrint('[StartupService] Navigating to pending notification route: $pendingRoute');
        }
        InitializeTrackerNotificationServiceUseCase.clearPendingRoute();

        final route = AppRouter.routeFromPath(pendingRoute);
        appRouter.replaceAll([route]);
        return;
      }

      if (kDebugMode) {
        debugPrint('[StartupService] Navigating to timeline screen...');
      }

      // Check if all onboarding permissions have been granted.
      final permissions = await CheckOnboardingPermissionsUseCase()();
      final allGranted = permissions.every((p) => p.granted);

      if (allGranted) {
        final isEnabled =
            await container.read(isBiometricLockEnabledUseCaseProvider.future);
        final biometricEnabled =
            await isEnabled(refreshedSessionUser.id);
        if (biometricEnabled) {
          final getTimeout =
              await container.read(getLockTimeoutUseCaseProvider.future);
          final timeoutSeconds =
              await getTimeout(refreshedSessionUser.id);
          final shouldLock = AppLockTimestampTracker.instance.shouldLock(
            timeoutSeconds: timeoutSeconds,
          );
          if (shouldLock) {
            appRouter.replaceAll([const BiometricLockRoute()]);
          } else {
            appRouter.replaceAll([const TimelineRoute()]);
          }
        } else {
          appRouter.replaceAll([const TimelineRoute()]);
        }
      } else {
        if (kDebugMode) {
          debugPrint('[StartupService] Missing permissions, navigating to onboarding...');
        }
        appRouter.replaceAll([const PermissionsOnboardingRoute()]);
      }
      return;
    } else {
      if (kDebugMode) {
        debugPrint('[StartupService] No user session found, navigating to auth screen...');
      }
      sessionService.logout();
      appRouter.replaceAll([const AuthRoute()]);
    }
  }
}
