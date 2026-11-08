package com.nexalink.app

import android.app.Service
import android.content.Intent
import android.os.Handler
import android.os.IBinder
import android.os.Looper
import android.os.Message
import android.os.Messenger
import mobile.Mobile

/** Read-only Go probe in a dedicated process; never shares Go runtimes with VPN roles. */
class EngineDiagnosticService : Service() {
    private val messenger = Messenger(Handler(Looper.getMainLooper()) { request ->
        if (request.what == 1) {
            val response = Message.obtain(null, 1)
            response.obj = try { Mobile.runtimeVersion() } catch (_: Throwable) { null }
            try { request.replyTo?.send(response) } catch (_: Exception) { }
        }
        true
    })
    override fun onBind(intent: Intent?): IBinder = messenger.binder
}
