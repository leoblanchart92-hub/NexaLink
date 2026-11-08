package com.nexalink.app.network

import android.content.BroadcastReceiver
import android.content.Context
import android.content.Intent
import android.util.Log
import java.net.DatagramPacket
import java.net.DatagramSocket
import java.net.InetAddress

/** Real test APK UID sends a single packet to a documentation-only routed IP. */
class VpnProbeReceiver : BroadcastReceiver() {
    override fun onReceive(context: Context, intent: Intent) {
        val result = goAsync()
        Thread {
            try {
                DatagramSocket().use { socket ->
                    val bytes = byteArrayOf(1, 2, 3)
                    socket.send(DatagramPacket(bytes, bytes.size, InetAddress.getByName("198.18.0.1"), 5555))
                }
                Log.i("NexaLinkVPN", "Separate test UID sent routed UDP probe")
            } catch (failure: Exception) {
                Log.w("NexaLinkVPN", "Separate test UID failed: ${failure.javaClass.simpleName}")
            } finally { result.finish() }
        }.start()
    }
}
