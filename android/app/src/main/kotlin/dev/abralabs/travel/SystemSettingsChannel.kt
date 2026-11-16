package dev.abralabs.travel

import android.content.Context
import android.os.PowerManager
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel

object SystemSettingsChannel {

    private const val CHANNEL = "dev.abralabs.travel/system_settings"

    fun register(engine: FlutterEngine, context: Context) {
        MethodChannel(engine.dartExecutor.binaryMessenger, CHANNEL)
            .setMethodCallHandler { call, result ->
                when (call.method) {
                    "isBatteryOptimizationEnabled" -> result.success(isBatteryOptimizationEnabled(context))
                    else -> result.notImplemented()
                }
            }
    }

    private fun isBatteryOptimizationEnabled(context: Context): Boolean {
        return try {
            val pm = context.getSystemService(Context.POWER_SERVICE) as PowerManager
            val isIgnoring = pm.isIgnoringBatteryOptimizations(context.packageName)
            isIgnoring.not()
        } catch (_: Throwable) {
            false // safe default
        }
    }
}