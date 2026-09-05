package dev.abralabs.travel

import android.content.BroadcastReceiver
import android.content.Context
import android.content.Intent
import android.os.Build
import android.util.Log
import androidx.annotation.RequiresApi
import id.flutter.flutter_background_service.BackgroundService

/**
 * BroadcastReceiver that listens for app updates (MY_PACKAGE_REPLACED).
 * When the app is updated, this receiver starts the background service
 * to resume automatic tracking if it was enabled.
 */
class AppUpdateReceiver : BroadcastReceiver() {

    companion object {
        private const val TAG = "AppUpdateReceiver"
    }

    @RequiresApi(Build.VERSION_CODES.O)
    override fun onReceive(context: Context, intent: Intent) {
        if (intent.action == Intent.ACTION_MY_PACKAGE_REPLACED) {
            Log.d(TAG, "App updated, attempting to restart background service...")

             try {
                 val serviceIntent = Intent(context, BackgroundService::class.java)
                 context.startForegroundService(serviceIntent)
                 Log.d(TAG, "Background service start requested")
             } catch (e: Exception) {
                 Log.e(TAG, "Failed to start background service after update", e)
             }
        }
    }
}
