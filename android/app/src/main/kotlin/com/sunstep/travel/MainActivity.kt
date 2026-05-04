package com.sunstep.travel

import android.content.Intent
import android.os.Bundle
import android.os.Handler
import android.os.Looper
import android.util.Log
import id.flutter.flutter_background_service.BackgroundService
import io.flutter.embedding.android.FlutterFragmentActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.embedding.engine.renderer.FlutterUiDisplayListener

class MainActivity : FlutterFragmentActivity() {

    companion object {
        private const val TAG = "MainActivity"
        private const val WATCHDOG_MS = 5_000L
        private var recoveryAttempts = 0
    }

    private val handler = Handler(Looper.getMainLooper())
    private var flutterUiReady = false

    private val flutterUiDisplayListener = object : FlutterUiDisplayListener {
        override fun onFlutterUiDisplayed() {
            flutterUiReady = true
            recoveryAttempts = 0
            cancelWatchdog()
            Log.d(TAG, "Flutter UI displayed, watchdog cancelled")
        }

        override fun onFlutterUiNoLongerDisplayed() {}
    }

    // When the background service keeps the OS process alive between sessions,
    // its FlutterEngine holds shared native resources. A second engine started
    // by this Activity can deadlock on those resources and prevent the first
    // frame from rendering. The watchdog detects this and recovers in two stages.
    //
    // Stage 1: stop the background service to release its engine, then recreate
    // this Activity so a fresh engine starts without contention.
    //
    // Stage 2: if the recreated engine still cannot render, kill the process so
    // the next launch is completely clean.
    //
    // StartupService in Dart restarts background tracking after either stage.
    private val startupWatchdog = Runnable {
        if (flutterUiReady) return@Runnable

        recoveryAttempts++

        if (recoveryAttempts == 1) {
            Log.w(TAG, "Flutter UI not ready after ${WATCHDOG_MS}ms, soft recovery")

            try {
                stopService(Intent(this@MainActivity, BackgroundService::class.java))
            } catch (e: Exception) {
                Log.w(TAG, "stopService failed: ${e.message}")
            }

            recreate()
        } else {
            Log.e(TAG, "Flutter UI still not ready, killing process (attempt $recoveryAttempts)")
            android.os.Process.killProcess(android.os.Process.myPid())
        }
    }

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(null)
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
        flutterEngine.renderer.addIsDisplayingFlutterUiListener(flutterUiDisplayListener)
        SystemSettingsChannel.register(flutterEngine, this)
        BuildConfigChannel.register(flutterEngine)
    }

    private fun cancelWatchdog() {
        handler.removeCallbacks(startupWatchdog)
    }

}