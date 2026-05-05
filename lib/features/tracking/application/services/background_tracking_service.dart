import 'dart:async';
import 'package:dawarich/core/constants/notification.dart';
import 'package:dawarich/core/data/drift/database/sqlite_client.dart';
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
      if (kDebugMode) {
        debugPrint('[Background] No user in session after retries — exiting.');
      }
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
      await shutdown(backgroundService, 'Auto tracking OFF');
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

    try {
      final automation =
          await container.read(pointAutomationServiceProvider.future);
      await automation.startTracking(userId);
      backgroundService.invoke('ready');

      automation.fatalFailures.listen((_) async {
        debugPrint(
            '[Background] Automation fatal failure — stopping service for watchdog restart.');
        await shutdown(backgroundService, 'automation fatal failure');
      });
    } catch (e, s) {
      debugPrint(
          '[Background] Failed to start tracking ($e) → shutting down.\n$s');
      await shutdown(backgroundService, 'startTracking failed: $e');
      return;
    }

    try {
      final checkExpiredBatch = await container
          .read(checkAndUploadExpiredBatchUseCaseProvider.future);

      final expirationResult = await checkExpiredBatch(userId);

      if (expirationResult case Ok(value: final didUpload)) {
        if (kDebugMode && didUpload) {
          debugPrint('[Background] Expired batch found and uploaded.');
        }
      } else if (expirationResult case Err(value: final err)) {
        debugPrint('[Background] Expired batch check failed: $err');
      }
    } catch (e, s) {
      debugPrint('[Background] Error during expired batch check: $e\n$s');
    }

    try {
      final getLastPoint =
          await container.read(getLastPointUseCaseProvider.future);
      final getBatchCount =
          await container.read(getBatchPointCountUseCaseProvider.future);
      await setInitialForegroundNotification(
        getLastPoint,
        getBatchCount,
        backgroundService,
        userId,
      );
    } catch (_) {
      // ignore
    }
  }

  static void registerListeners(ServiceInstance backgroundService) {
    backgroundService.on('ping').listen((event) async {
      final requestId = event?['requestId'];
      backgroundService.invoke('pong', {
        'requestId': requestId,
        ...await _buildHealthPayload(),
      });
    });

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
          final automation =
              await container.read(pointAutomationServiceProvider.future);
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

  static Future<Map<String, Object?>> _buildHealthPayload() async {
    final container = _container;
    if (container == null) {
      return {
        'responsive': true,
        'healthy': false,
        'reason': 'container not ready',
      };
    }

    try {
      final automation =
          await container.read(pointAutomationServiceProvider.future);
      return {
        'responsive': true,
        'reason':
            automation.isHealthy ? 'tracking healthy' : 'tracking unhealthy',
        ...automation.healthSnapshot,
      };
    } catch (e) {
      return {
        'responsive': true,
        'healthy': false,
        'reason': 'health check failed: $e',
      };
    }
  }

  static Future<void> shutdown(ServiceInstance svc, String reason) async {
    if (kDebugMode) {
      debugPrint('[Background] Shutting down: $reason');
    }
    try {
      _container?.dispose();
    } catch (_) {}
    _container = null;

    // Remove the stale Drift IsolateNameServer port so the main app's next
    // connectSharedIsolate() doesn't waste time trying to connect to a dead
    // isolate (the 1 s timeout in connectSharedIsolate() adds up otherwise).
    SQLiteClient.resetSharedState();

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

    // FlutterBackgroundService.configure() is a platform-channel call that
    // can deadlock when the service was already started by the platform
    // (autoStartOnBoot). The _configured flag is per-Dart-isolate, so it's
    // always false in a fresh foreground process even when the platform
    // service is alive. Wrapping configure() in a timeout prevents the
    // splash screen from freezing indefinitely in that scenario.
    try {
      await FlutterBackgroundService()
          .configure(
            androidConfiguration: AndroidConfiguration(
              onStart: backgroundTrackingEntry,
              autoStartOnBoot: true,
              isForegroundMode: true,
              foregroundServiceTypes: [AndroidForegroundType.location],
              autoStart: false,
              foregroundServiceNotificationId:
                  NotificationConstants.notificationId,
              notificationChannelId: NotificationConstants.channelId,
            ),
            iosConfiguration: IosConfiguration(
              onForeground: backgroundTrackingEntry,
              onBackground: (_) async => true,
            ),
          )
          .timeout(const Duration(seconds: 8));
    } on TimeoutException {
      debugPrint(
          '[BackgroundService] configure() timed out — likely already running via autoStartOnBoot.');
      // Don't set _configured, a subsequent call can retry.
      return;
    } catch (e) {
      debugPrint('[BackgroundService] configure() failed: $e');
      return;
    }

    _configured = true;
  }

  static Future<Result<(), String>> start() async {
    final service = FlutterBackgroundService();

    if (!(await Permission.notification.isGranted)) {
      debugPrint('[BackgroundService] Notification permission missing.');
      return Err("Notification permission is required.");
    }

    final locEnabled = await Geolocator.isLocationServiceEnabled();
    final always = await Permission.locationAlways.status;
    final hasBgPermission = always.isGranted;

    if (!locEnabled || !hasBgPermission) {
      return Err("Background location permission is required.");
    }

    await installConfigurationOnce();

    if (!_configured) {
      if (!await service.isRunning()) {
        return Err("Background service configuration failed.");
      }

      final health = await _checkServiceHealth();
      if (health.isHealthy) {
        debugPrint(
            '[BackgroundService] Already running and healthy after configure timeout.');
        return Ok(());
      }

      debugPrint(
        '[BackgroundService] Running service is unhealthy after configure timeout '
        '(${health.reason}) — stopping before retry.',
      );
      await _requestServiceStop('unconfigured_unhealthy');
      await installConfigurationOnce();

      if (!_configured) {
        return Err(
            "Background service configuration failed after stopping unhealthy service.");
      }
    }

    if (await service.isRunning()) {
      final health = await _checkServiceHealth();
      if (health.isHealthy) {
        debugPrint(
            '[BackgroundService] Already running and healthy — skipping start.');
        return Ok(());
      }

      debugPrint(
        '[BackgroundService] Unhealthy service detected (${health.reason}) — '
        'stopping for clean restart.',
      );
      await _requestServiceStop('unhealthy_restart');
    }

    final readyCompleter = Completer<void>();
    final readySub = service.on('ready').listen((_) {
      if (!readyCompleter.isCompleted) readyCompleter.complete();
    });

    final started = await service.startService();
    if (!started) {
      await readySub.cancel();
      return Err("Failed to start background service.");
    }

    bool timedOut = false;
    await readyCompleter.future.timeout(
      const Duration(seconds: 20),
      onTimeout: () {
        timedOut = true;
      },
    );
    await readySub.cancel();

    if (timedOut) {
      debugPrint(
          '[BackgroundService] start() timed out waiting for ready — stopping service.');
      await _requestServiceStop('start_timeout');
      return Err(
          "Background service did not confirm readiness within the startup window.");
    }

    return Ok(());
  }

  static Future<bool> isRunning() async {
    return FlutterBackgroundService().isRunning();
  }

  static Future<bool> isHealthy() async {
    if (!await FlutterBackgroundService().isRunning()) {
      return false;
    }
    final health = await _checkServiceHealth();
    return health.isHealthy;
  }

  static Future<_ServiceHealth> _checkServiceHealth() async {
    final requestId = DateTime.now().microsecondsSinceEpoch.toString();
    final completer = Completer<Map<String, dynamic>>();
    final sub = FlutterBackgroundService().on('pong').listen((event) {
      if (event?['requestId'] == requestId && !completer.isCompleted) {
        completer.complete(Map<String, dynamic>.from(event!));
      }
    });
    FlutterBackgroundService().invoke('ping', {'requestId': requestId});

    Map<String, dynamic>? payload;
    try {
      payload = await completer.future.timeout(
        const Duration(seconds: 5),
      );
    } on TimeoutException {
      // handled below
    }
    await sub.cancel();

    if (payload == null) {
      return const _ServiceHealth(
        isHealthy: false,
        reason: 'ping timed out',
      );
    }

    final healthy = payload['healthy'] == true;
    return _ServiceHealth(
      isHealthy: healthy,
      reason: payload['reason'] as String? ??
          (healthy ? 'tracking healthy' : 'tracking unhealthy'),
    );
  }

  static Future<void> _requestServiceStop(String requestId) async {
    final service = FlutterBackgroundService();
    final stopped = Completer<void>();
    final sub = service.on('stopped').listen((event) {
      if (event?['requestId'] == requestId && !stopped.isCompleted) {
        stopped.complete();
      }
    });

    service.invoke('stopService', {'requestId': requestId});

    try {
      await stopped.future.timeout(const Duration(seconds: 3));
    } on TimeoutException {
      debugPrint('[BackgroundService] Stop request $requestId timed out.');
    } finally {
      await sub.cancel();
    }

    await Future<void>.delayed(const Duration(milliseconds: 500));
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

  static Future<void> restartTracking() async {
    final service = FlutterBackgroundService();

    final isRunning = await service.isRunning();
    if (!isRunning) {
      debugPrint('[BackgroundService] Restart skipped: service not running');
      return;
    }

    debugPrint(
        '[BackgroundService] Sending restartTracking event to background isolate...');
    service.invoke('restartTracking', {});
  }
}

final class _ServiceHealth {
  const _ServiceHealth({
    required this.isHealthy,
    required this.reason,
  });

  final bool isHealthy;
  final String reason;
}
