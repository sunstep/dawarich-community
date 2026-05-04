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
    // Timeout prevents the service from hanging indefinitely if the DB
    // isolate can't be reached (e.g. IsolateNameServer race between the
    // foreground and background FlutterEngines). On timeout, the caller's
    // retry loop will dispose this container and create a fresh one.
    await container.read(coreProvider.future).timeout(
      const Duration(seconds: 15),
      onTimeout: () {
        throw TimeoutException(
          'Core provider initialization timed out in background isolate',
        );
      },
    );
    _container = container;
    return container;
  }

  static Future<void> checkBackgroundTracking(ServiceInstance backgroundService) async {
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
            debugPrint('[Background] Retry attempt $attempt/3 - recreating container...');
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
          debugPrint('[Background] Error during initialization (attempt $attempt/3): $e\n$s');
        }
        // Dispose container on error to ensure clean retry
        _container?.dispose();
        _container = null;
      }
    }

    if (user == null || container == null) {
      if (kDebugMode) debugPrint('[Background] No user in session after retries — exiting.');
      await shutdown(backgroundService, 'No user session');
      return;
    }

    try {
      final getSettings = await container.read(getTrackerSettingsUseCaseProvider.future);
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
        debugPrint('[Background] Failed to load tracker settings ($e) → shutting down.\n$s');
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


    // Wrap the critical provider resolution + tracking start in try/catch.
    // Without this, an error in the deep provider chain (e.g. DB isolate
    // timeout, Drift migration failure) propagates out of the unawaited
    // fire-and-forget block in the entrypoint. The outer catch calls
    // shutdown() but in some edge cases the exception bypasses it entirely,
    // leaving the service alive but non-functional (zombie service).
    try {
      final automation = await container.read(pointAutomationServiceProvider.future);
      await automation.startTracking(userId);
    } catch (e, s) {
      debugPrint('[Background] Failed to start tracking ($e) → shutting down.\n$s');
      await shutdown(backgroundService, 'startTracking failed: $e');
      return;
    }

    try {
      final checkExpiredBatch =
      await container.read(checkAndUploadExpiredBatchUseCaseProvider.future);

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
      final getLastPoint = await container.read(getLastPointUseCaseProvider.future);
      final getBatchCount = await container.read(getBatchPointCountUseCaseProvider.future);
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
    backgroundService.on('stopService').listen((event) async {
      final requestId = event?['requestId'];
      try {
        final container = _container;
        if (container != null) {
          final automation = await container.read(pointAutomationServiceProvider.future);
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
          content: 'Last updated at: ${lp.timestamp.toLocal()}, $batchPointCount points in batch.',
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

    final FlutterLocalNotificationsPlugin plugin = FlutterLocalNotificationsPlugin();

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
      ).timeout(const Duration(seconds: 8));
    } on TimeoutException {
      debugPrint('[BackgroundService] configure() timed out — likely already running via autoStartOnBoot.');
      // Don't set _configured, a subsequent call can retry.
      return;
    } catch (e) {
      debugPrint('[BackgroundService] configure() failed: $e');
      return;
    }

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
      final service = FlutterBackgroundService();

      // Check isRunning() before configure() to avoid a platform-channel
      // deadlock when the service was already auto-started on boot.
      if (await service.isRunning()) {
        _starting!.complete();
        return;
      }

      await installConfigurationOnce();

      await service.startService();

      final ready = Completer<void>();
      final sub = service.on('ready').listen((_) {
        if (!ready.isCompleted) ready.complete();
      });
      await ready.future.timeout(const Duration(seconds: 5), onTimeout: () {});
      await sub.cancel();

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

    // Check isRunning() BEFORE installConfigurationOnce().
    // FlutterBackgroundService().configure() is a platform-channel call that
    // can deadlock when the service was already started (e.g. autoStartOnBoot).
    // The _configured flag is per-Dart-isolate, so it's always false in a fresh
    // foreground process even if the platform service is already running.
    // Checking isRunning() first avoids calling configure() entirely when
    // the service is already alive — fixing the splash-screen freeze.
    final isRunning = await FlutterBackgroundService().isRunning();
    if (isRunning) {
      debugPrint('[BackgroundService] Already running — skipping start.');
      return Ok(());
    }

    await installConfigurationOnce();

    final started = await FlutterBackgroundService().startService();
    return started
        ? Ok(())
        : Err("Failed to start background service.");
  }

  /// Starts the background service without performing permission or location-
  /// service checks.
  ///
  /// Use this from contexts where permissions are already known to be granted
  /// (WorkManager watchdog, app-resume check). Those contexts cannot request
  /// permissions and would incorrectly abort the restart if, for example, the
  /// system reports location services as temporarily unavailable.
  static Future<bool> startServiceDirect() async {
    // Check isRunning() first to avoid a potential configure() deadlock
    // when the platform service is already alive (see start() comment).
    final isRunning = await FlutterBackgroundService().isRunning();
    if (isRunning) {
      debugPrint('[BackgroundService] startServiceDirect: already running.');
      return true;
    }

    await installConfigurationOnce();

    debugPrint('[BackgroundService] startServiceDirect: starting service...');
    return FlutterBackgroundService().startService();
  }

  static Future<bool> isRunning() async {
    return FlutterBackgroundService().isRunning();
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
        debugPrint('[BackgroundService] Stop confirmed for requestId $requestId.');
        stopCompleter.complete();
      } else {
        debugPrint('[BackgroundService] Received unrelated stop event with requestId $eventId.');
      }
    });

    debugPrint('[BackgroundService] Sending stopService request with ID $requestId...');
    service.invoke('stopService', {'requestId': requestId});

    try {
      await stopCompleter.future.timeout(
        const Duration(seconds: 3),
        onTimeout: () {
          debugPrint('[BackgroundService] Stop confirmation timed out for requestId $requestId.');
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