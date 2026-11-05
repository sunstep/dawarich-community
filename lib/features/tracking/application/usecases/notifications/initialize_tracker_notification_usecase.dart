import 'package:dawarich/core/routing/app_router.dart';
import 'package:dawarich/features/tracking/application/services/tracking_notification_service.dart';
import 'package:dawarich/main.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';

final class InitializeTrackerNotificationServiceUseCase {
  final TrackerNotificationService _service;

  InitializeTrackerNotificationServiceUseCase(this._service);

  static String? pendingNotificationRoute;

  Future<void> call() async {
    await _service.init(
      onTap: (NotificationResponse response) {
        final payload = response.payload;
        if (payload == null) {
          return;
        }

    const androidSettings =
        AndroidInitializationSettings('ic_bg_service_small');
    const iosSettings = DarwinInitializationSettings(
      requestAlertPermission: true,
      requestBadgePermission: true,
      requestSoundPermission: true,
    );

    const InitializationSettings initializationSettings =
        InitializationSettings(
      android: androidSettings,
      iOS: iosSettings,
    );

    await _notificationsPlugin.initialize(initializationSettings,
        onDidReceiveNotificationResponse: _onNotificationTapped);

    final launchDetails =
        await _notificationsPlugin.getNotificationAppLaunchDetails();
    if (launchDetails?.didNotificationLaunchApp == true) {
      final payload = launchDetails?.notificationResponse?.payload;
      if (payload != null) {
        if (kDebugMode) {
          debugPrint(
              '[NotificationService] App launched from notification with payload: $payload');
        }
        pendingNotificationRoute = payload;
      }
    }
  }

  static void _onNotificationTapped(NotificationResponse response) {
    final String? payload = response.payload;
    if (payload != null) {
      if (kDebugMode) {
        debugPrint(
            '[NotificationService] Notification tapped with payload: $payload');
      }
      final route = AppRouter.routeFromPath(payload);
      appRouter.push(route);
    }
  }

  /// Clear the pending route (call after navigation is handled)
  static void clearPendingRoute() {
    pendingNotificationRoute = null;
  }
}
