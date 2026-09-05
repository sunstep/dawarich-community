package dev.abralabs.travel

import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel


object BuildConfigChannel {

    private const val CHANNEL = "dev.abralabs.travel/build_config"

    fun register(engine: FlutterEngine) {
        MethodChannel(engine.dartExecutor.binaryMessenger, CHANNEL)
            .setMethodCallHandler { call, result ->
                when (call.method) {
                    "getFlavor" -> result.success(BuildConfig.FLAVOR)
                    else -> result.notImplemented()
                }
            }
    }
}