package com.sunstep.travel

import android.content.Intent
import android.os.Bundle
import android.os.Handler
import android.os.Looper
import android.util.Log
import id.flutter.flutter_background_service.BackgroundService
import id.flutter.flutter_background_service.WatchdogReceiver
import io.flutter.embedding.android.FlutterFragmentActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.embedding.engine.renderer.FlutterUiDisplayListener

class MainActivity : FlutterFragmentActivity() {

    companion object {
        private const val TAG = "MainActivity"

        /** How long to wait for Flutter's first frame before intervening. */
        private const val WATCHDOG_MS = 5_000L

        /**
         * Tracks recovery attempts across Activity recreations within the
         * same OS process. Reset to 0 once Flutter successfully renders.
         */
        private var recoveryAttempts = 0
    }

    private val handler = Handler(Looper.getMainLooper())
    private var flutterUiReady = false

    // Flutter-frame listener
    private val flutterUiDisplayListener = object : FlutterUiDisplayListener {
        override fun onFlutterUiDisplayed() {
            flutterUiReady = true
            recoveryAttempts = 0
            cancelWatchdog()
            Log.d(TAG, "Flutter UI displayed, recovery counter reset, watchdog cancelled")
        }

        override fun onFlutterUiNoLongerDisplayed() {
            // No-op: we only care about the first display.
        }
    }

    // Startup watchdog
    //
    // When the background service keeps the OS process alive between user
    // sessions, its FlutterEngine holds shared native resources (Dart VM
    // isolate slots, JNI locks, FlutterLoader state, SQLCipher file-lock).
    // A second FlutterEngine, created by this Activity, can deadlock on
    // those resources, preventing the first frame from ever rendering.
    //
    // Recovery strategy (two stages, 5 s each):
    //
    //  Stage 1 - SOFT  (recoveryAttempts == 0)
    //      Stop the background service (releasing its engine), then
    //      recreate() this Activity so a fresh FlutterEngine starts in
    //      a now-contention-free process. The user sees the splash
    //      briefly restart, no crash, no manual relaunch.
    //
    //  Stage 2 - HARD  (recoveryAttempts >= 1)
    //      The recreated engine still couldn't render. Kill the process
    //      so the next user-initiated launch is completely clean.
    //
    // The Dart-side StartupService restarts background tracking
    // automatically once it detects the service is not running.
    //
    private val startupWatchdog = Runnable {
        if (flutterUiReady) return@Runnable

        recoveryAttempts++

        if (recoveryAttempts == 1) {
            // Stage 1: stop BG service + recreate Activity
            Log.w(TAG, "Flutter UI not ready after ${WATCHDOG_MS}ms, "
                    + "soft recovery: stopping background service + recreating Activity")

            markServiceManuallyStopped()
            try {
                stopService(Intent(this@MainActivity, BackgroundService::class.java))
            } catch (e: Exception) {
                Log.w(TAG, "stopService failed: ${e.message}")
            }

            // recreate() destroys the current (stuck) FlutterEngine and
            // creates a brand-new one. Because the BG service is being
            // torn down concurrently, the fresh engine starts without
            // native resource contention.
            recreate()
        } else {
            // Stage 2: kill the process
            Log.e(TAG, "Flutter UI still not ready after Activity recreate, "
                    + "killing process for clean restart (attempt $recoveryAttempts)")

            markServiceManuallyStopped()
            android.os.Process.killProcess(android.os.Process.myPid())
        }
    }

    override fun onCreate(savedInstanceState: Bundle?) {
        Log.d(TAG, "onCreate (recoveryAttempts=$recoveryAttempts)")

        // Pass null to avoid restoring potentially stale/incompatible
        // parcelled state from a previous Activity incarnation.
        super.onCreate(null)

        Log.d(TAG, "super.onCreate(null) complete")

        // Watchdog is armed on every launch unconditionally, not just when the
        // background service is detected. getRunningServices() can under-report
        // own-package services on some OEM ROMs (API 26+ deprecation side-effects),
        // so using it as a gate could leave the watchdog disarmed when it's needed.
        //
        // If Flutter renders normally (< 2 s on a clean launch) the display
        // listener fires, flutterUiReady is set, and the watchdog is cancelled
        // before it expires, zero cost in the happy path.
        Log.d(TAG, "Arming startup watchdog (recoveryAttempts=$recoveryAttempts)")
        handler.postDelayed(startupWatchdog, WATCHDOG_MS)
    }

    override fun onDestroy() {
        cancelWatchdog()
        flutterEngine?.renderer?.removeIsDisplayingFlutterUiListener(flutterUiDisplayListener)
        super.onDestroy()
    }

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        Log.d(TAG, "configureFlutterEngine")

        // Listen for the first Flutter frame so we can cancel the startup watchdog.
        flutterEngine.renderer.addIsDisplayingFlutterUiListener(flutterUiDisplayListener)

        SystemSettingsChannel.register(flutterEngine, this)
        BuildConfigChannel.register(flutterEngine)
    }

    // Helpers

    private fun cancelWatchdog() {
        handler.removeCallbacks(startupWatchdog)
    }

    /**
     * Cancel the plugin's pending watchdog alarm and persist the
     * manually-stopped flag so [WatchdogReceiver] skips the respawn
     * when [BackgroundService.onDestroy] re-enqueues the alarm.
     */
    private fun markServiceManuallyStopped() {
        try { WatchdogReceiver.remove(this) } catch (_: Exception) {}
        try {
            @Suppress("ApplySharedPref")
            getSharedPreferences("id.flutter.background_service", MODE_PRIVATE)
                .edit()
                .putBoolean("is_manually_stopped", true)
                .commit()
        } catch (_: Exception) {}
    }

}