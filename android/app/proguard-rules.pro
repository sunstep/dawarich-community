-keep class com.ikolvi.tracelet.flutter.TraceletStartupProvider { *; }
-keep class com.ikolvi.tracelet.flutter.** { *; }
-keep class com.ikolvi.tracelet.** { *; }

-keep class io.flutter.plugins.cronet_http.** { *; }
-keep class com.github.dart_lang.jni.** { *; }
-keep class org.chromium.net.** { *; }

-keepclassmembers class com.ikolvi.tracelet.** { *; }
-dontwarn com.ikolvi.tracelet.**

-keep class androidx.window.** { *; }
-dontwarn androidx.window.**