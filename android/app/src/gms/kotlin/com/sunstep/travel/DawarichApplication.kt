package com.sunstep.travel

import android.app.Application
import android.app.PendingIntent
import android.content.Intent
import android.os.Build
import android.util.Log
import org.json.JSONObject
import java.io.File

/**
 * GMS build Application class.
 *
 * Base layer: MotionSensorManager provides the same sensor-based locomotion
 * detection as the FOSS build.
 *
 * GMS bonus: the Activity Transition API additionally registers locomotion ENTER
 * events. When Play Services confirm movement they also write the transition file,
 * giving faster detection on top of the sensor layer.
 */
class DawarichApplication : Application() {

    companion object {
        private const val TAG = "DawarichApplication"
        private const val TRANSITION_PENDING_INTENT_CODE = 1001
    }

    private lateinit var motionSensorManager: MotionSensorManager

    override fun onCreate() {
        super.onCreate()

        motionSensorManager = MotionSensorManager(
            context = this,
            onLocomotionConfirmed = { writeTransitionFile(activityType = -1) },
        )
        motionSensorManager.arm()

        registerActivityTransitions()
    }

    private fun writeTransitionFile(activityType: Int) {
        try {
            val json = JSONObject().apply {
                put("timestamp", System.currentTimeMillis())
                put("activityType", activityType)
            }
            File(filesDir, MotionSensorManager.TRANSITION_FILE).writeText(json.toString())
            Log.d(TAG, "Transition file written (activityType=$activityType)")
        } catch (e: Exception) {
            Log.e(TAG, "Failed to write transition file: ${e.message}")
        }
    }

    /**
     * Registers locomotion ENTER transitions with the GMS Activity Transition API.
     * Results are delivered to [ActivityTransitionReceiver] via PendingIntent.
     */
    private fun registerActivityTransitions() {
        try {
            val locomotionTypes = listOf(
                com.google.android.gms.location.DetectedActivity.WALKING,
                com.google.android.gms.location.DetectedActivity.RUNNING,
                com.google.android.gms.location.DetectedActivity.ON_BICYCLE,
                com.google.android.gms.location.DetectedActivity.IN_VEHICLE,
            )

            val transitions = locomotionTypes.map { activityType ->
                com.google.android.gms.location.ActivityTransition.Builder()
                    .setActivityType(activityType)
                    .setActivityTransition(
                        com.google.android.gms.location.ActivityTransition.ACTIVITY_TRANSITION_ENTER
                    )
                    .build()
            }

            val request = com.google.android.gms.location.ActivityTransitionRequest(transitions)

            val intent = Intent(this, ActivityTransitionReceiver::class.java).apply {
                action = "com.sunstep.travel.ACTIVITY_TRANSITION"
            }

            var flags = PendingIntent.FLAG_UPDATE_CURRENT
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.S) {
                flags = flags or PendingIntent.FLAG_MUTABLE
            }

            val pendingIntent = PendingIntent.getBroadcast(
                this, TRANSITION_PENDING_INTENT_CODE, intent, flags
            )

            com.google.android.gms.location.ActivityRecognition.getClient(this)
                .requestActivityTransitionUpdates(request, pendingIntent)
                .addOnSuccessListener {
                    Log.d(TAG, "GMS Activity Transition API registered successfully")
                }
                .addOnFailureListener { e ->
                    Log.w(TAG, "GMS Activity Transition registration failed: ${e.message}")
                }

        } catch (e: Throwable) {
            Log.w(TAG, "GMS Activity Transition registration failed unexpectedly: ${e.message}")
        }
    }
}
