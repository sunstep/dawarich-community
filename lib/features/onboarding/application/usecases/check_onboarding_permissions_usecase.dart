import 'dart:io';

import 'package:dawarich/features/onboarding/domain/permission_item.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:permission_handler/permission_handler.dart';

/// Checks the current status of all required permissions and returns a list
/// of [PermissionItem]s with their granted/denied state.
final class CheckOnboardingPermissionsUseCase {
  static const MethodChannel _channel =
      MethodChannel('com.sunstep.travel/system_settings');

  Future<List<PermissionItem>> call() async {
    final notificationGranted = await Permission.notification.isGranted;
    final locationAlwaysGranted = await Permission.locationAlways.isGranted;
    final batteryExcluded = await _isBatteryOptimizationDisabled();

    return [
      PermissionItem(
        id: PermissionIds.notification,
        title: 'Notifications',
        description:
            'Required for tracking status updates and background service alerts.',
        granted: notificationGranted,
      ),
      PermissionItem(
        id: PermissionIds.locationAlways,
        title: 'Location (Always)',
        description:
            'Required so the app can record your location in the background.',
        granted: locationAlwaysGranted,
      ),
      if (Platform.isAndroid)
        PermissionItem(
          id: PermissionIds.batteryOptimization,
          title: 'Battery Optimization',
          description:
              'Disabling battery optimization prevents Android from stopping background tracking.',
          granted: batteryExcluded,
        ),
    ];
  }

  Future<bool> _isBatteryOptimizationDisabled() async {
    if (!Platform.isAndroid) return true;

    try {
      final bool enabled =
          await _channel.invokeMethod<bool>('isBatteryOptimizationEnabled') ??
              false;
      return !enabled; // granted = optimization is OFF
    } on MissingPluginException catch (e) {
      if (kDebugMode) {
        debugPrint('[CheckOnboardingPermissions] Missing plugin: $e');
      }
      return true; // fail open
    } on PlatformException catch (e) {
      if (kDebugMode) {
        debugPrint('[CheckOnboardingPermissions] PlatformException: ${e.code}');
      }
      return true;
    }
  }
}


