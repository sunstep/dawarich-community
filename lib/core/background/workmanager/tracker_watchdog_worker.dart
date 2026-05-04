import 'package:dawarich/core/di/providers/core_providers.dart';
import 'package:dawarich/core/di/providers/session_providers.dart';
import 'package:dawarich/core/di/providers/usecase_providers.dart';
import 'package:dawarich/features/tracking/application/services/background_tracking_service.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

final class TrackingWatchdogWorker {
  static const String uniqueWorkName = 'tracking-watchdog';

  /// Executes the watchdog task logic.
  /// Called by [appWorkmanagerCallbackDispatcher] — do NOT call
  /// [Workmanager().initialize] here.
  static Future<void> execute() async {
    ProviderContainer? container;

    try {
      if (kDebugMode) {
        debugPrint('[TrackingWatchdog] Worker started.');
      }

      container = ProviderContainer();
      await container.read(coreProvider.future);

      final session = await container.read(sessionBoxProvider.future);
      final user = await session.refreshSession();

      if (user == null) {
        if (kDebugMode) {
          debugPrint('[TrackingWatchdog] No user session, skipping.');
        }
        return;
      }

      final getSettings =
          await container.read(getTrackerSettingsUseCaseProvider.future);

      final settings = await getSettings(user.id);

      if (!settings.automaticTracking) {
        if (kDebugMode) {
          debugPrint('[TrackingWatchdog] Automatic tracking disabled, skipping.');
        }
        return;
      }

      final isRunning = await BackgroundTrackingService.isRunning();

      if (isRunning) {
        if (kDebugMode) {
          debugPrint('[TrackingWatchdog] Service already running.');
        }
        return;
      }

      if (kDebugMode) {
        debugPrint('[TrackingWatchdog] Service not running, restarting...');
      }

      final result = await BackgroundTrackingService.start();

      if (kDebugMode) {
        debugPrint('[TrackingWatchdog] Restart result: $result');
      }
    } catch (e, s) {
      debugPrint('[TrackingWatchdog] Worker failed: $e\n$s');
    } finally {
      container?.dispose();
    }
  }
}