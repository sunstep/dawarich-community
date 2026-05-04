-keep class androidx.window.** { *; }
-dontwarn androidx.window.**

# Prevent BadParcelableException on process/activity restore in minified builds.
-keepclassmembers class * implements android.os.Parcelable {
  public static final android.os.Parcelable$Creator *;
}


# DawarichApplication — registers Activity Transition API on startup.
-keep class com.sunstep.travel.DawarichApplication { *; }

# ActivityTransitionReceiver — manifest-declared receiver targeted by explicit
# PendingIntent for the Activity Transition API (GMS builds).
-keep class com.sunstep.travel.ActivityTransitionReceiver { *; }

# GMS Activity Recognition / Transition API — used in DawarichApplication and
# ActivityTransitionReceiver. Only present in GMS builds; FOSS builds exclude
# the entire com.google.android.gms group at runtime.
-keep class com.google.android.gms.location.ActivityTransition$Builder { *; }
-keep class com.google.android.gms.location.ActivityTransitionRequest { *; }
-keep class com.google.android.gms.location.ActivityTransitionResult { *; }
-keep class com.google.android.gms.location.ActivityRecognition { *; }
-keep class com.google.android.gms.location.ActivityRecognitionClient { *; }
-keep class com.google.android.gms.location.DetectedActivity { *; }
-dontwarn com.google.android.gms.location.**

# GMS Task API — used by DawarichApplication to attach success/failure
# listeners to the requestActivityTransitionUpdates Task.
-keep class com.google.android.gms.tasks.Task { *; }
-keep interface com.google.android.gms.tasks.OnSuccessListener { *; }
-keep interface com.google.android.gms.tasks.OnFailureListener { *; }
-dontwarn com.google.android.gms.tasks.**
