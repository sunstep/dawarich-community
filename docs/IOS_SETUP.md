# iOS Build Setup Guide - Dawarich Mobile

Complete guide to set up development environment and build the app for iOS.

## Prerequisites

### 1. Install Development Tools

#### macOS Requirements
- **macOS 13.0+** (Ventura or later recommended)
- **Xcode 15.0+** - Download from Mac App Store
- **Command Line Tools**: After installing Xcode, run:
  ```bash
  xcode-select --install
  ```

#### Install Flutter SDK
```bash
# Using Homebrew (recommended)
brew install --cask flutter

# Or download directly from https://flutter.dev/docs/get-started/install/macos

# Add Flutter to your PATH (if not using Homebrew)
# Add to ~/.zshrc or ~/.bash_profile:
export PATH="$PATH:/path/to/flutter/bin"

# Verify installation
flutter doctor
```

#### Install CocoaPods (iOS dependency manager)
```bash
# CocoaPods is used to manage iOS dependencies
sudo gem install cocoapods

# Or if you have Homebrew:
brew install cocoapods
```

### 2. Verify Your Setup
```bash
flutter doctor -v
```

This should show:
- ✓ Flutter SDK
- ✓ Xcode
- ✓ iOS Simulator
- ✓ CocoaPods

## Project Setup

### 1. Install Flutter Dependencies
```bash
cd /path/to/dawarich-android
flutter pub get
```

### 2. Generate Required Code
```bash
dart run build_runner build --delete-conflicting-outputs
```

## iOS-Specific Configuration

### 1. Update Info.plist

Edit `ios/Runner/Info.plist` and add the following entries **before** the final `</dict>` tag:

```xml
	<!-- Local Network Access (required for connecting to self-hosted servers on local network) -->
	<key>NSLocalNetworkUsageDescription</key>
	<string>Dawarich needs access to your local network to connect to your self-hosted Dawarich server.</string>

	<!-- Bonjour Services (if your server uses mDNS/Bonjour discovery) -->
	<key>NSBonjourServices</key>
	<array>
		<string>_http._tcp</string>
		<string>_https._tcp</string>
	</array>

	<!-- App Transport Security (for HTTPS requirements) -->
	<key>NSAppTransportSecurity</key>
	<dict>
		<!-- If you need to connect to HTTP (not HTTPS) servers, use exception domains -->
		<key>NSExceptionDomains</key>
		<dict>
			<!-- Add your server domain here if using HTTP -->
			<key>localhost</key>
			<dict>
				<key>NSExceptionAllowsInsecureHTTPLoads</key>
				<true/>
				<key>NSIncludesSubdomains</key>
				<true/>
			</dict>
			<!-- Example for local IP addresses (you may need to add specific IPs) -->
			<key>192.168.1.100</key>
			<dict>
				<key>NSExceptionAllowsInsecureHTTPLoads</key>
				<true/>
			</dict>
		</dict>
	</dict>

	<!-- Location Permissions -->
	<key>NSLocationWhenInUseUsageDescription</key>
	<string>Dawarich needs access to your location to track your movements when using the app.</string>

	<key>NSLocationAlwaysAndWhenInUseUsageDescription</key>
	<string>Dawarich needs continuous access to your location to track your movements in the background, even when the app is closed.</string>

	<key>NSLocationAlwaysUsageDescription</key>
	<string>Dawarich needs continuous access to your location to provide location tracking services.</string>

	<!-- Background Modes -->
	<key>UIBackgroundModes</key>
	<array>
		<string>fetch</string>
		<string>location</string>
		<string>processing</string>
	</array>

	<!-- Camera Permission (for QR code scanning) -->
	<key>NSCameraUsageDescription</key>
	<string>Dawarich needs camera access to scan QR codes for quick server connection.</string>

	<!-- Notification Permission -->
	<key>NSUserNotificationsUsageDescription</key>
	<string>Dawarich uses notifications to inform you about location tracking status.</string>

	<!-- Photo Library (if needed for any future features) -->
	<key>NSPhotoLibraryUsageDescription</key>
	<string>Dawarich may need access to save or retrieve images.</string>
```

**Important Notes**:
- `NSLocalNetworkUsageDescription` is required for iOS 14+ to access devices on your local network
- `NSAppTransportSecurity` with `NSExceptionDomains` allows HTTP connections to specific servers
- You'll need to add your actual server IP/hostname to the exception domains if using HTTP
- For HTTPS servers with valid certificates, no exceptions are needed
- `NSBonjourServices` is optional but helps with mDNS/Bonjour server discovery

### 2. Create Podfile

Create `ios/Podfile` with the following content:

```ruby
# Uncomment this line to define a global platform for your project
platform :ios, '13.0'

# CocoaPods analytics sends network stats synchronously affecting flutter build latency.
ENV['COCOAPODS_DISABLE_STATS'] = 'true'

project 'Runner', {
  'Debug' => :debug,
  'Profile' => :release,
  'Release' => :release,
}

def flutter_root
  generated_xcode_build_settings_path = File.expand_path(File.join('..', 'Flutter', 'Generated.xcconfig'), __FILE__)
  unless File.exist?(generated_xcode_build_settings_path)
    raise "#{generated_xcode_build_settings_path} must exist. If you're running pod install manually, make sure flutter pub get is executed first"
  end

  File.foreach(generated_xcode_build_settings_path) do |line|
    matches = line.match(/FLUTTER_ROOT\=(.*)/)
    return matches[1].strip if matches
  end
  raise "FLUTTER_ROOT not found in #{generated_xcode_build_settings_path}. Try deleting Generated.xcconfig, then run flutter pub get"
end

require File.expand_path(File.join('packages', 'flutter_tools', 'bin', 'podhelper'), flutter_root)

flutter_ios_podfile_setup

target 'Runner' do
  use_frameworks!
  use_modular_headers!

  flutter_install_all_ios_pods File.dirname(File.realpath(__FILE__))
  
  # Add SQLCipher pod
  pod 'SQLCipher', '~> 4.5'
end

post_install do |installer|
  installer.pods_project.targets.each do |target|
    flutter_additional_ios_build_settings(target)
    target.build_configurations.each do |config|
      config.build_settings['IPHONEOS_DEPLOYMENT_TARGET'] = '13.0'
      # Enable bitcode if needed
      config.build_settings['ENABLE_BITCODE'] = 'NO'
    end
  end
end
```

### 3. Update AppDelegate.swift

Replace `ios/Runner/AppDelegate.swift` with:

```swift
import Flutter
import UIKit

@main
@objc class AppDelegate: FlutterAppDelegate {
  override func application(
    _ application: UIApplication,
    didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?
  ) -> Bool {
    GeneratedPluginRegistrant.register(with: self)
    
    // Setup method channel for system settings
    if let controller = window?.rootViewController as? FlutterViewController {
      let channel = FlutterMethodChannel(
        name: "com.sunstep.dawarich/system_settings",
        binaryMessenger: controller.binaryMessenger
      )
      
      channel.setMethodCallHandler { (call, result) in
        switch call.method {
        case "isBatteryOptimizationEnabled":
          // iOS doesn't have battery optimization like Android
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
```

### 4. Update SQLCipher Bootstrap for iOS

Edit `lib/core/data/drift/database/crypto/sqlcipher_bootstrap.dart`:

```dart
import 'dart:io' show Platform;

import 'package:sqlite3/open.dart' as sqlite3;
import 'package:sqlcipher_flutter_libs/sqlcipher_flutter_libs.dart';


final class SqlcipherBootstrap {

  static Future<void> ensure() async {

    if (Platform.isAndroid) {
      await applyWorkaroundToOpenSqlCipherOnOldAndroidVersions();
      sqlite3.open.overrideFor(sqlite3.OperatingSystem.android, openCipherOnAndroid);
    } else if (Platform.isIOS) {
      // iOS SQLCipher support
      sqlite3.open.overrideFor(sqlite3.OperatingSystem.iOS, () => DynamicLibrary.process());
    }

  }
}
```

### 5. Install iOS Dependencies
```bash
cd ios
pod install
cd ..
```

This will create `ios/Runner.xcworkspace` - **always use this file** to open the project in Xcode, NOT `Runner.xcodeproj`.

## Building the App

### Option 1: Build for iOS Simulator
```bash
# List available simulators
flutter devices

# Run on simulator
flutter run -d "iPhone 15 Pro"  # or whatever simulator name you choose
```

### Option 2: Build for Physical Device

#### Requirements:
1. **Apple Developer Account** (free account works for development)
2. **Device connected via USB**
3. **Trust certificate on device**

#### Steps:
```bash
# Open Xcode workspace
open ios/Runner.xcworkspace

# In Xcode:
# 1. Select Runner project in left sidebar
# 2. Go to "Signing & Capabilities" tab
# 3. Select your Team
# 4. Change Bundle Identifier if needed (e.g., com.yourname.dawarich)

# Build for device
flutter run -d "Your iPhone Name"
```

### Option 3: Build IPA for Distribution
```bash
# Build release IPA
flutter build ipa --release

# The IPA will be at: build/ios/ipa/dawarich.ipa
```

## Troubleshooting

### Common Issues

#### 1. "Command not found: flutter"
```bash
# Check if Flutter is in PATH
echo $PATH

# Add to ~/.zshrc:
export PATH="$PATH:/path/to/flutter/bin"
source ~/.zshrc
```

#### 2. "CocoaPods not installed"
```bash
sudo gem install cocoapods
```

#### 3. Pod install fails
```bash
cd ios
pod deintegrate
pod install --repo-update
cd ..
```

#### 4. Xcode build errors
```bash
# Clean and rebuild
flutter clean
flutter pub get
cd ios
pod install
cd ..
flutter build ios
```

#### 5. "No such module" errors in Swift
- Make sure you opened `Runner.xcworkspace` not `Runner.xcodeproj`
- Clean build folder in Xcode: Product → Clean Build Folder

#### 6. Code signing errors
- Open `ios/Runner.xcworkspace` in Xcode
- Select your Team in Signing & Capabilities
- Change Bundle Identifier if it conflicts

### Testing Background Location

iOS is very restrictive with background location. To test:

1. Build and install on a physical device
2. Go to Settings → Privacy & Security → Location Services → Dawarich
3. Select "Always" for location permission
4. Toggle "Precise Location" ON
5. Test by walking around with the app in background

**Note**: Background location tracking on iOS works differently than Android:
- iOS may throttle location updates when battery is low
- iOS pauses location updates when device is completely stationary
- iOS terminates background tasks more aggressively than Android

## Verification Checklist

Before submitting to App Store or distributing:

- [ ] All permissions are properly described in Info.plist
- [ ] App Bundle ID is unique and matches your Apple Developer account
- [ ] Code signing is set up correctly
- [ ] App works on physical device with background location
- [ ] Network connections work (both HTTP and HTTPS)
- [ ] QR code scanning works
- [ ] Database encryption works correctly
- [ ] Notifications appear properly
- [ ] Background tracking persists after app update

## Additional Resources

- [Flutter iOS Setup](https://docs.flutter.dev/get-started/install/macos/mobile-ios)
- [iOS App Distribution Guide](https://docs.flutter.dev/deployment/ios)
- [Apple Developer Documentation](https://developer.apple.com/documentation/)
- [CocoaPods](https://cocoapods.org/)

---

**Last Updated**: 2025-02-06
