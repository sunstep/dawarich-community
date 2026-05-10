# Build Flavors

Dawarich supports two build flavors for different distribution channels.

## Flavors

### GMS (Google Mobile Services)
- **Target**: Play Store
- **Location Provider**: Google Fused Location Provider
- **Pros**: Best battery optimization, fastest location acquisition

### FOSS (Fully Open Source Software)
- **Target**: F-Droid, direct APK distribution
- **Location Provider**: Android Location Manager (AOSP)
- **Pros**: No proprietary dependencies, fully open source

## Building

### GMS Build

```bash
flutter run --flavor gms
flutter build apk --flavor gms
flutter build appbundle --flavor gms
```

### FOSS Build

```bash
flutter run --flavor foss
flutter build apk --flavor foss
```

## How It Works

### Gradle Configuration

```groovy
android {
    flavorDimensions = ["distribution"]
    productFlavors {
        gms {
            dimension "distribution"
            buildConfigField "String", "FLAVOR_DISTRIBUTION", '"gms"'
        }
        foss {
            dimension "distribution"
            buildConfigField "String", "FLAVOR_DISTRIBUTION", '"foss"'
        }
    }
    buildFeatures {
        buildConfig true
    }
}

// Exclude Google Play Services from FOSS builds
configurations.matching { it.name.toLowerCase().contains("foss") }.configureEach {
    exclude group: "com.google.android.gms"
}
```

### Native Method Channel

The `FLAVOR_DISTRIBUTION` is exposed to Dart via a method channel in `MainActivity.kt`:

```kotlin
MethodChannel(flutterEngine.dartExecutor.binaryMessenger, "com.sunstep.travel/build_config")
    .setMethodCallHandler { call, result ->
        when (call.method) {
            "getFlavor" -> result.success(BuildConfig.FLAVOR_DISTRIBUTION)
            else -> result.notImplemented()
        }
    }
```

### Dart Provider

The flavor is accessed via a Riverpod provider:

```dart
final distributionFlavorProvider = FutureProvider<DistributionFlavor>((ref) async {
  final flavor = await BuildConfigChannel.getFlavor();
  return flavor == 'foss' ? DistributionFlavor.foss : DistributionFlavor.gms;
});
```

### Location Provider Selection

```dart
final locationProviderProvider = FutureProvider<ILocationProvider>((ref) async {
  final flavor = await ref.watch(distributionFlavorProvider.future);
  
  if (flavor == DistributionFlavor.foss) {
    return AospLocationProvider();
  }
  return LocationProvider();
});
```

This approach:
- Uses Gradle as the single source of truth
- Provides a true compile-time constant via `BuildConfig`
- Exposes it cleanly to Dart via method channel
- Allows for custom location provider implementations per flavor





