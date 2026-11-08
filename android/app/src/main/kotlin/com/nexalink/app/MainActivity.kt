package com.nexalink.app

import android.content.ComponentName
import android.content.Context
import android.content.Intent
import android.content.ServiceConnection
import android.os.Handler
import android.os.IBinder
import android.os.Looper
import android.os.Message
import android.os.Messenger
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel

class MainActivity: FlutterActivity() {
    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, "nexalink/engine").setMethodCallHandler { call, result ->
            when (call.method) {
                // The diagnostic process never loads either runtime into the UI/VPN process.
                "runtimeVersion" -> getRuntimeVersion(result)
                else -> result.notImplemented()
            }
        }
    }

    private fun getRuntimeVersion(result: MethodChannel.Result) {
        val handler = Handler(Looper.getMainLooper())
        var finished = false
        var bound = false
        lateinit var connection: ServiceConnection
        fun finish(version: String?) {
            if (finished) return
            finished = true
            if (bound) { bound = false; unbindService(connection) }
            if (version == null) result.error("engine_unavailable", "Moteur natif indisponible", null)
            else result.success(version)
        }
        val replies = Messenger(Handler(Looper.getMainLooper()) { msg ->
            finish(msg.data.getString("version"))
            true
        })
        connection = object : ServiceConnection {
            override fun onServiceConnected(name: ComponentName?, binder: IBinder?) {
                try {
                    val request = Message.obtain(null, 1)
                    request.replyTo = replies
                    Messenger(binder).send(request)
                } catch (_: Exception) { finish(null) }
            }
            override fun onServiceDisconnected(name: ComponentName?) { finish(null) }
            override fun onBindingDied(name: ComponentName?) { finish(null) }
        }
        try {
            bound = bindService(Intent(this, EngineDiagnosticService::class.java), connection, Context.BIND_AUTO_CREATE)
            if (!bound) finish(null) else handler.postDelayed({ finish(null) }, 10000)
        } catch (_: Exception) { finish(null) }
    }
}
