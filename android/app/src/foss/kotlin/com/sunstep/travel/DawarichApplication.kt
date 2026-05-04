package com.sunstep.travel

import android.app.Application
import android.util.Log
import org.json.JSONObject
import java.io.File

/**
 * FOSS build Application class.
 *
 * Uses MotionSensorManager (TYPE_SIGNIFICANT_MOTION + accelerometer validation)
 * as the sole motion detection path. No Google Play Services dependency.
 */
class DawarichApplication : Application() {

    companion object {
        private const val TAG = "DawarichApplication"
    }

    private lateinit var motionSensorManager: MotionSensorManager

    override fun onCreate() {
        super.onCreate()

        motionSensorManager = MotionSensorManager(
            context = this,
            onLocomotionConfirmed = { writeTransitionFile() },
        )
        motionSensorManager.arm()
    }

    private fun writeTransitionFile() {
        try {
            val json = JSONObject().apply {
                put("timestamp", System.currentTimeMillis())
                put("activityType", -1)
            }
            File(filesDir, MotionSensorManager.TRANSITION_FILE).writeText(json.toString())
            Log.d(TAG, "Transition file written")
        } catch (e: Exception) {
            Log.e(TAG, "Failed to write transition file: ${e.message}")
        }
    }
}
