# In FOSS builds, geolocator's fused (GMS) implementation is unusable.

-assumenosideeffects class com.baseflow.geolocator.location.FusedLocationClient {
  *;
}

-keep class io.flutter.plugins.cronet_http.** { *; }
-keep class com.github.dart_lang.jni.** { *; }
-keep class org.chromium.net.** { *; }

-dontwarn com.baseflow.geolocator.location.FusedLocationClient
-dontwarn com.baseflow.geolocator.location.**
-dontwarn com.google.android.gms.**
-dontwarn com.google.android.gms.location.**
-dontwarn com.google.android.gms.tasks.**