package com.sunstep.travel

import android.content.Context
import android.hardware.Sensor
import android.hardware.SensorEvent
import android.hardware.SensorEventListener
import android.hardware.SensorManager
import android.hardware.TriggerEvent
import android.hardware.TriggerEventListener
import android.os.Handler
import android.os.Looper
import android.util.Log
import kotlin.math.sqrt

/**
 * Sensor-based locomotion detector using a two-stage pipeline:
 *
 * Stage 1: TYPE_SIGNIFICANT_MOTION hardware trigger (near-zero battery cost).
 * Stage 2: 8-second accelerometer validation window split into 8 one-second
 * buckets. If at least MIN_ACTIVE_BUCKETS exceed WALKING_VARIANCE_THRESHOLD,
 * locomotion is confirmed. Quick indoor movement (kitchen walk ~4 s) fills
 * only 3-4 buckets and is discarded. Street walking (8+ s continuous) fills
 * 6-8 buckets and is confirmed.
 *
 * Thread-safe: all callbacks are dispatched on the main looper.
 */
class MotionSensorManager(
    private val context: Context,
    private val onLocomotionConfirmed: () -> Unit,
) {
    companion object {
        private const val TAG = "MotionSensorManager"

        const val TRANSITION_FILE = "activity_transition_event.json"

        private const val VALIDATION_WINDOW_MS = 8_000L
        private const val BUCKET_COUNT = 8

        // Walking generates ~0.4-3.0 m²/s² variance; stationary ~0.001 m²/s².
        private const val WALKING_VARIANCE_THRESHOLD = 0.35

        // 6 out of 8 buckets = 75% sustained motion required.
        private const val MIN_ACTIVE_BUCKETS = 6

        // At SENSOR_DELAY_UI (~16 Hz) we expect ~16 samples per bucket.
        private const val MIN_BUCKET_SAMPLES = 4
    }

    private val sensorManager: SensorManager? =
        context.getSystemService(Context.SENSOR_SERVICE) as? SensorManager

    private val handler = Handler(Looper.getMainLooper())

    @Volatile
    private var smdArmed = false

    @Volatile
    private var isValidating = false
    private var validationStartTime = 0L

    private val buckets = Array(BUCKET_COUNT) { mutableListOf<Double>() }

    private val smdListener = object : TriggerEventListener() {
        override fun onTrigger(event: TriggerEvent) {
            Log.d(TAG, "TYPE_SIGNIFICANT_MOTION fired")
            smdArmed = false
            handler.post { onSignificantMotion() }
        }
    }

    private val accelListener = object : SensorEventListener {
        override fun onSensorChanged(event: SensorEvent) {
            if (!isValidating) {
                return
            }

            val elapsed = System.currentTimeMillis() - validationStartTime
            if (elapsed >= VALIDATION_WINDOW_MS) {
                return
            }

            val bucketIdx = ((elapsed * BUCKET_COUNT) / VALIDATION_WINDOW_MS)
                .toInt().coerceIn(0, BUCKET_COUNT - 1)

            val x = event.values[0].toDouble()
            val y = event.values[1].toDouble()
            val z = event.values[2].toDouble()
            buckets[bucketIdx].add(sqrt(x * x + y * y + z * z))
        }

        override fun onAccuracyChanged(sensor: Sensor?, accuracy: Int) = Unit
    }

    /** Arms TYPE_SIGNIFICANT_MOTION. Safe to call multiple times. */
    fun arm() {
        if (smdArmed) {
            return
        }

        val sm = sensorManager ?: run {
            Log.w(TAG, "SensorManager unavailable — sensor-based wake disabled")
            return
        }

        val sensor = sm.getDefaultSensor(Sensor.TYPE_SIGNIFICANT_MOTION) ?: run {
            Log.w(TAG, "TYPE_SIGNIFICANT_MOTION not available on this device")
            return
        }

        sm.requestTriggerSensor(smdListener, sensor)
        smdArmed = true
        arm()
    }

    private fun onSignificantMotion() {
        if (isValidating) {
            Log.d(TAG, "SMD fired during ongoing validation — waiting for window to finish")
            return
        }

        val sm = sensorManager ?: run {
            Log.w(TAG, "Accelerometer unavailable — firing locomotion event directly")
            onLocomotionConfirmed()
            arm()
            return
        }

        val accel = sm.getDefaultSensor(Sensor.TYPE_ACCELEROMETER) ?: run {
            Log.w(TAG, "Accelerometer sensor not found — firing locomotion event directly")
            onLocomotionConfirmed()
            arm()
            return
        }

        sm.registerListener(accelListener, accel, SensorManager.SENSOR_DELAY_UI, handler)
        Log.d(TAG, "Accelerometer validation window started (${VALIDATION_WINDOW_MS} ms)")

        handler.postDelayed({ finishValidation() }, VALIDATION_WINDOW_MS)
    }

    private fun finishValidation() {
        val sm = sensorManager ?: return
        sm.unregisterListener(accelListener)
        isValidating = false

        val activeBuckets = buckets.count { samples ->
            if (samples.size < MIN_BUCKET_SAMPLES) return@count false
            val mean = samples.average()
            val variance = samples.map { v -> (v - mean) * (v - mean) }.average()
            variance > WALKING_VARIANCE_THRESHOLD
        }

        Log.d(TAG, "Validation: $activeBuckets / $BUCKET_COUNT buckets active")

        if (activeBuckets >= MIN_ACTIVE_BUCKETS) {
            Log.d(TAG, "Locomotion confirmed")
            onLocomotionConfirmed()
        } else {
            Log.d(TAG, "Transient motion discarded ($activeBuckets < $MIN_ACTIVE_BUCKETS)")
        }

        // Always re-arm for the next motion cycle.
        arm()
    }
}

