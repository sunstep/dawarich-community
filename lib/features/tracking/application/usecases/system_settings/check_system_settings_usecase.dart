import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:permission_handler/permission_handler.dart';

final class CheckSystemSettingsUseCase {

  static const MethodChannel _channel = MethodChannel('dev.abralabs.travel/system_settings');

  /// On Android: returns `true` if battery optimization is still enabled.
  /// On iOS: returns `true` if “Always” location permission is denied.
  ///
  /// If the native channel isn't available (e.g. during debug/hot-restart or
  /// missing platform wiring), this returns a safe default instead of throwing.
  Future<bool> call() async {
    try {
      if (Platform.isAndroid) {
        final bool enabled =
            await _channel.invokeMethod<bool>('isBatteryOptimizationEnabled') ?? false;
        return enabled;
      } else if (Platform.isIOS) {
        final status = await Permission.locationAlways.status;
        return !status.isGranted;
      }

      return false;
    } on MissingPluginException catch (e) {
      if (kDebugMode) {
        debugPrint('[CheckSystemSettingsUseCase] Missing plugin: $e');
      }
      return false;
    } on PlatformException catch (e) {
      if (kDebugMode) {
        debugPrint('[CheckSystemSettingsUseCase] PlatformException: ${e.code} ${e.message}');
      }
      return false;
    }
  }

}