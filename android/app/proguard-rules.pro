-keep class com.ikolvi.tracelet.flutter.TraceletStartupProvider { *; }
-keep class com.ikolvi.tracelet.flutter.** { *; }
-keep class com.ikolvi.tracelet.** { *; }

-keepclassmembers class com.ikolvi.tracelet.** { *; }
-dontwarn com.ikolvi.tracelet.**

-keep class androidx.window.** { *; }
-dontwarn androidx.window.**