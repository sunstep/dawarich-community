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
import 'package:dawarich/features/tracking/application/usecases/notifications/initialize_tracker_notification_usecase.dart';
import 'package:dawarich/main.dart';
import 'package:dawarich_android_user_module/dawarich_android_user_module.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:option_result/option_result.dart';

final class StartupService {
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

      try {
        final pointAutomationService =
        await container.read(pointAutomationServiceProvider.future);

        final resumeResult =
        await pointAutomationService.resumeTrackingIfEnabled(
          refreshedSessionUser.id,
        );

        if (resumeResult case Err(value: final message)) {
          debugPrint('[StartupService] $message');
        }
      } catch (error, stackTrace) {
        // Tracking restoration must not prevent the application from opening.
        debugPrint(
          '[StartupService] Unable to restore tracking runtime: $error',
        );

        if (kDebugMode) {
          debugPrint('$stackTrace');
        }
      }

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

      final refreshServerCompatibility =
          await container.read(refreshServerCompatibilityUseCaseProvider.future);
      await refreshServerCompatibility();

      // Register the lifecycle observer so stats auto-refresh on app resume.
      final lifecycleController = AppLifecycleController(container);
      WidgetsBinding.instance.addObserver(lifecycleController);

      // Register WorkManager periodic task for background stats refresh.
      await initializeAndRegisterStatsWorker();

      // Register periodic batch upload worker (handles both threshold
      // and expiration uploads when the foreground service isn't running).
      await registerBatchUploadWorker();


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
