package com.sunstep.travel

import android.content.BroadcastReceiver
import android.content.Context
import android.content.Intent
import android.util.Log
import com.google.android.gms.location.ActivityTransition
import com.google.android.gms.location.ActivityTransitionResult
import com.google.android.gms.location.DetectedActivity
import org.json.JSONObject
import java.io.File

class ActivityTransitionReceiver : BroadcastReceiver() {

    companion object {
        private const val TAG = "ActivityTransitionReceiver"
        private const val ACTION_ACTIVITY_TRANSITION = "com.sunstep.travel.ACTIVITY_TRANSITION"

        private val LOCOMOTION_TYPES = setOf(
            DetectedActivity.WALKING,
            DetectedActivity.RUNNING,
            DetectedActivity.ON_BICYCLE,
            DetectedActivity.IN_VEHICLE,
        )
    }

    override fun onReceive(context: Context, intent: Intent?) {
        if (intent?.action != ACTION_ACTIVITY_TRANSITION) {
            return
        }

        if (!ActivityTransitionResult.hasResult(intent)) {
            Log.d(TAG, "Received activity transition intent without a result")
            return
        }

        val transition = ActivityTransitionResult.extractResult(intent)
            ?.transitionEvents
            ?.lastOrNull { event ->
                event.transitionType == ActivityTransition.ACTIVITY_TRANSITION_ENTER &&
                    LOCOMOTION_TYPES.contains(event.activityType)
            }

        if (transition == null) {
            Log.d(TAG, "No locomotion ENTER transition in result")
            return
        }

        writeTransitionFile(context, transition.activityType)
    }

    private fun writeTransitionFile(context: Context, activityType: Int) {
        try {
            val json = JSONObject().apply {
                put("timestamp", System.currentTimeMillis())
                put("activityType", activityType)
            }
            File(context.filesDir, MotionSensorManager.TRANSITION_FILE).writeText(json.toString())
            Log.d(TAG, "Transition file written (activityType=$activityType)")
        } catch (e: Exception) {
            Log.e(TAG, "Failed to write transition file: ${e.message}")
        }
    }
}
