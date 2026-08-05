import Flutter
import UIKit

@main
@objc class AppDelegate: FlutterAppDelegate {
  override func application(
    _ application: UIApplication,
    didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?
  ) -> Bool {
    GeneratedPluginRegistrant.register(with: self)
    
    // Setup method channel for system settings check
    if let controller = window?.rootViewController as? FlutterViewController {
      let channel = FlutterMethodChannel(
        name: "com.sunstep.dawarich/system_settings",
        binaryMessenger: controller.binaryMessenger
      )
      
      channel.setMethodCallHandler { (call, result) in
        switch call.method {
        case "isBatteryOptimizationEnabled":
          // iOS doesn't have battery optimization restrictions like Android
          // Always return false (no restrictions)
          result(false)
        default:
          result(FlutterMethodNotImplemented)
        }
      }
    }
    
    return super.application(application, didFinishLaunchingWithOptions: launchOptions)
  }
}
