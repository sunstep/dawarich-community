import 'dart:async';
import 'dart:io';
import 'package:dawarich/core/constants/notification.dart';
import 'package:dawarich/core/domain/models/user.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_background_service/flutter_background_service.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:geolocator/geolocator.dart';
import 'package:option_result/option_result.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:dawarich/core/di/providers/core_providers.dart';
import 'package:dawarich/core/di/providers/session_providers.dart';
import 'package:dawarich/core/di/providers/usecase_providers.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'background_tracking_entrypoint.dart';
import 'package:dawarich/features/tracking/application/usecases/get_batch_point_count_usecase.dart';
import 'package:dawarich/features/tracking/application/usecases/get_last_point_usecase.dart';

class BackgroundTrackingEntry {
  static ProviderContainer? _container;

  static Future<ProviderContainer> _ensureContainer() async {
    final existing = _container;
    if (existing != null) return existing;

    final container = ProviderContainer();
    // Ensure core deps are ready in background isolate.
    await container.read(coreProvider.future);
    _container = container;
    return container;
  }

  static Future<void> checkBackgroundTracking(
      ServiceInstance backgroundService) async {
    if (kDebugMode) {
      debugPrint('[Background] Injecting background thread dependencies...');
    }

    // Retry container initialization in case of race condition with foreground
    // (e.g., DB locked during migration, session validation fails)
    User? user;
    ProviderContainer? container;

    for (int attempt = 1; attempt <= 3; attempt++) {
      try {
        // Dispose old container and create fresh one on retry
        if (attempt > 1) {
          if (kDebugMode) {
            debugPrint(
                '[Background] Retry attempt $attempt/3 - recreating container...');
          }
          _container?.dispose();
          _container = null;
          await Future.delayed(const Duration(seconds: 2));
        }

        container = await _ensureContainer();
        final session = await container.read(sessionBoxProvider.future);
        user = await session.refreshSession();

        if (user != null) {
          session.setUserId(user.id);
          break;
        }

        if (kDebugMode) {
          debugPrint('[Background] No user in session (attempt $attempt/3)');
        }
      } catch (e, s) {
        if (kDebugMode) {
          debugPrint(
              '[Background] Error during initialization (attempt $attempt/3): $e\n$s');
        }
        // Dispose container on error to ensure clean retry
        _container?.dispose();
        _container = null;
      }
    }

    if (user == null || container == null) {
      if (kDebugMode)
        debugPrint('[Background] No user in session after retries — exiting.');
      await shutdown(backgroundService, 'No user session');
      return;
    }

    try {
      final getSettings =
          await container.read(getTrackerSettingsUseCaseProvider.future);
      final settings = await getSettings(user.id);
      if (!settings.automaticTracking) {
        if (kDebugMode) {
          debugPrint('[Background] Auto tracking OFF → shutting down.');
        }
        await shutdown(backgroundService, 'Auto tracking OFF');
        return;
      }
    } catch (e, s) {
      if (kDebugMode) {
        debugPrint(
            '[Background] Failed to load tracker settings ($e) → shutting down.\n$s');
      }
      await shutdown(backgroundService, 'Settings load failed');
      return;
    }

    await _startBackgroundTracking(backgroundService, container, user.id);
  }

  static Future<void> _startBackgroundTracking(
    ServiceInstance backgroundService,
    ProviderContainer container,
    int userId,
  ) async {
    if (kDebugMode) {
      debugPrint('[Background] Starting background tracking...');
    }

    final automation =
        await container.read(pointAutomationServiceProvider.future);
    await automation.startTracking(userId);

    try {
      final getLastPoint =
          await container.read(getLastPointUseCaseProvider.future);
      final getBatchCount =
          await container.read(getBatchPointCountUseCaseProvider.future);
      await setInitialForegroundNotification(
          getLastPoint, getBatchCount, backgroundService, userId);
    } catch (_) {
      // ignore
    }
  }

  static void registerListeners(ServiceInstance backgroundService) {
    backgroundService.on('stopService').listen((event) async {
      final requestId = event?['requestId'];
      try {
        final container = _container;
        if (container != null) {
          final automation =
              await container.read(pointAutomationServiceProvider.future);
          await automation.stopTracking();
        }
      } catch (e, s) {
        debugPrint('[Background] Error stopping tracking: $e\n$s');
      } finally {
        backgroundService.invoke('stopped', {'requestId': requestId});
        await shutdown(backgroundService, 'stopService event');
      }
    });

    backgroundService.on('restartTracking').listen((event) async {
      debugPrint('[Background] *** restartTracking event received ***');
      try {
        final container = _container;
        if (container != null) {
          final automation = await container.read(pointAutomationServiceProvider.future);
          await automation.restartTracking();
          debugPrint('[Background] Tracking restarted successfully');
        } else {
          debugPrint('[Background] Container is null, cannot restart tracking');
        }
      } catch (e, s) {
        debugPrint('[Background] Error restarting tracking: $e\n$s');
      }
    });
  }

  static Future<void> shutdown(ServiceInstance svc, String reason) async {
    if (kDebugMode) {
      debugPrint('[Background] Shutting down: $reason');
    }
    try {
      _container?.dispose();
    } catch (_) {}
    _container = null;
    svc.stopSelf();
  }

  static Future<void> setInitialForegroundNotification(
    GetLastPointUseCase getLastPoint,
    GetBatchPointCountUseCase getBatchPointsCount,
    ServiceInstance backgroundService,
    int userId,
  ) async {
    final lastPointResult = await getLastPoint(userId);
    final batchPointCount = await getBatchPointsCount(userId);

    if (backgroundService is AndroidServiceInstance) {
      if (lastPointResult case Some(value: final lp)) {
        await backgroundService.setForegroundNotificationInfo(
          title: 'Dawarich Tracking',
          content:
              'Last updated at: ${lp.timestamp.toLocal()}, $batchPointCount points in batch.',
        );
      } else {
        await backgroundService.setForegroundNotificationInfo(
          title: 'Dawarich Tracking',
          content: 'Tracking in the background, no points recorded yet.',
        );
      }
    }
  }
}

@pragma('vm:entry-point')
final class BackgroundTrackingService {
  static bool _configured = false;
  static Completer<void>? _starting;
  static bool _isStopping = false;

  static Future<void> ensureNotificationChannelExists() async {
    const AndroidNotificationChannel channel = AndroidNotificationChannel(
      NotificationConstants.channelId,
      NotificationConstants.channelName,
      description: NotificationConstants.channelDescription,
      importance: Importance.low,
    );

    final FlutterLocalNotificationsPlugin plugin =
        FlutterLocalNotificationsPlugin();

    await plugin
        .resolvePlatformSpecificImplementation<
            AndroidFlutterLocalNotificationsPlugin>()
        ?.createNotificationChannel(channel);
  }

  static Future<void> installConfigurationOnce() async {
    if (_configured) {
      return;
    }

    await ensureNotificationChannelExists();

    await FlutterBackgroundService().configure(
      androidConfiguration: AndroidConfiguration(
        onStart: backgroundTrackingEntry,
        autoStartOnBoot: true,
        isForegroundMode: true,
        foregroundServiceTypes: [AndroidForegroundType.location],
        autoStart: false,
        foregroundServiceNotificationId: NotificationConstants.notificationId,
        notificationChannelId: NotificationConstants.channelId,
      ),
      iosConfiguration: IosConfiguration(
        onForeground: backgroundTrackingEntry,
        onBackground: (_) async => true,
      ),
    );

    _configured = true;
  }

  /// Start (if needed) and configure the background service.
  /// Safe/idempotent across concurrent callers
  static Future<void> configureService({bool force = false}) async {
    // coalesce concurrent calls
    if (_starting != null) {
      return _starting!.future;
    }

    _starting = Completer<void>();

    try {
      await installConfigurationOnce();

      final service = FlutterBackgroundService();

      if (!await service.isRunning()) {
        await service.startService();

        final ready = Completer<void>();
        final sub = service.on('ready').listen((_) {
          if (!ready.isCompleted) ready.complete();
        });
        await ready.future
            .timeout(const Duration(seconds: 5), onTimeout: () {});
        await sub.cancel();
      }

      _starting!.complete();
    } catch (e, s) {
      if (kDebugMode) debugPrint('[Tracker] configureService failed: $e\n$s');
      _starting!.completeError(e, s);
      rethrow;
    } finally {
      _starting = null;
    }
  }

  static Future<Result<(), String>> start() async {
    // On iOS 26+, permission_handler returns wrong notification status
    if (!Platform.isIOS) {
      if (!(await Permission.notification.isGranted)) {
        debugPrint('[BackgroundService] Notification permission missing.');
        return Err("Notification permission is required.");
      }
    }

    try {
      final locEnabled = await Geolocator.isLocationServiceEnabled();
      if (!locEnabled) {
        return Err("Location services are disabled.");
      }

      // Use Geolocator for permission check on iOS (permission_handler returns
      // wrong status on iOS 26+)
      bool hasBgPermission;
      if (Platform.isIOS) {
        final geoPermission = await Geolocator.checkPermission();
        hasBgPermission = geoPermission == LocationPermission.always ||
            geoPermission == LocationPermission.whileInUse;
      } else {
        final always = await Permission.locationAlways.status;
        hasBgPermission = always.isGranted;
      }

      if (!hasBgPermission) {
        return Err("Background location permission is required.");
      }
    } catch (e) {
      debugPrint('[BackgroundService] Error checking permissions: $e');
      return Err("Unable to check location permissions.");
    }

    await installConfigurationOnce();

    final isRunning = await FlutterBackgroundService().isRunning();
    if (isRunning) {
      debugPrint('[BackgroundService] Already running — skipping start.');
      return Ok(());
    }

    final started = await FlutterBackgroundService().startService();
    return started ? Ok(()) : Err("Failed to start background service.");
  }

  static Future<void> stop() async {
    final service = FlutterBackgroundService();

    final isRunning = await service.isRunning();
    if (!isRunning) {
      debugPrint('[BackgroundService] Stop skipped: service not running');
      return;
    }

    if (_isStopping) return;
    _isStopping = true;

    final requestId = DateTime.now().millisecondsSinceEpoch.toString();
    final stopCompleter = Completer<void>();

    final sub = service.on('stopped').listen((event) {
      final eventId = event?['requestId'];
      if (eventId == requestId) {
        debugPrint(
            '[BackgroundService] Stop confirmed for requestId $requestId.');
        stopCompleter.complete();
      } else {
        debugPrint(
            '[BackgroundService] Received unrelated stop event with requestId $eventId.');
      }
    });

    debugPrint(
        '[BackgroundService] Sending stopService request with ID $requestId...');
    service.invoke('stopService', {'requestId': requestId});

    try {
      await stopCompleter.future.timeout(
        const Duration(seconds: 3),
        onTimeout: () {
          debugPrint(
              '[BackgroundService] Stop confirmation timed out for requestId $requestId.');
        },
      );
    } catch (_) {
      debugPrint('[BackgroundService] Stop confirmation failed or timed out.');
    } finally {
      await sub.cancel();
      _isStopping = false;
    }
  }

  /// Restart tracking to apply new settings (e.g., frequency change)
  /// Sends event to background isolate to restart the tracking logic.
  static Future<void> restartTracking() async {
    final service = FlutterBackgroundService();

    final isRunning = await service.isRunning();
    if (!isRunning) {
      debugPrint('[BackgroundService] Restart skipped: service not running');
      return;
    }

    debugPrint('[BackgroundService] Sending restartTracking event to background isolate...');
    service.invoke('restartTracking', {});
  }

}
