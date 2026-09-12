import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:permission_handler/permission_handler.dart';

final class CheckSystemSettingsUseCase {

  static const MethodChannel _channel = MethodChannel('com.sunstep.travel/system_settings');

  /// On Android: returns `true` if battery optimization is still enabled.
  /// On iOS: returns `true` if “Always” location permission is denied.
  ///
  /// If the native channel isn't available (e.g. during debug/hot-restart or
  /// missing platform wiring), this returns a safe default instead of throwing.
  Future<bool> call() async {
    try {
      if (Platform.isAndroid) {
        final bool enabled =
            await _channel.invokeMethod<bool>('isBatteryOptimizationEnabled') ??
                false;
        return enabled;
      } else if (Platform.isIOS) {
        try {
          final status = await Permission.locationAlways.status;
          return !status.isGranted;
        } catch (e) {
          // iOS permission check crash workaround
          if (kDebugMode) {
            debugPrint('[CheckSystemSettingsUseCase] iOS permission error: $e');
          }
          return false;
        }
      }

      return false;
    } on MissingPluginException catch (e) {
      if (kDebugMode) {
        debugPrint('[CheckSystemSettingsUseCase] Missing plugin: $e');
      }
      return false;
    } on PlatformException catch (e) {
      if (kDebugMode) {
        debugPrint(
            '[CheckSystemSettingsUseCase] PlatformException: ${e.code} ${e.message}');
      }
      return false;
    } catch (e) {
      // Catch any other errors
      if (kDebugMode) {
        debugPrint('[CheckSystemSettingsUseCase] Unexpected error: $e');
      }
      return false;
    }
  }
}
