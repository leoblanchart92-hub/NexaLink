package com.nexalink.app

import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel
import mobile.Mobile

class MainActivity: FlutterActivity() {
    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, "nexalink/engine").setMethodCallHandler { call, result ->
            when (call.method) {
                // Read-only: this validates JNI loading, not a network connection.
                "runtimeVersion" -> try {
                    result.success(Mobile.runtimeVersion())
                } catch (_: LinkageError) {
                    result.error("engine_unavailable", "Moteur natif indisponible", null)
                } catch (_: Exception) {
                    result.error("engine_unavailable", "Moteur natif indisponible", null)
                }
                else -> result.notImplemented()
            }
        }
    }
}
