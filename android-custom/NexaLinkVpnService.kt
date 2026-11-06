package com.nexalink.app

import android.app.Notification
import android.app.NotificationChannel
import android.app.NotificationManager
import android.content.Intent
import android.net.VpnService
import android.os.Build
import android.os.ParcelFileDescriptor

class NexaLinkVpnService : VpnService() {
    
    companion object {
        const val ACTION_START = "com.nexalink.app.START_VPN"
        const val ACTION_STOP = "com.nexalink.app.STOP_VPN"
        var isRunning = false
    }
    
    private var tunnel: ParcelFileDescriptor? = null
    
    override fun onStartCommand(intent: Intent?, flags: Int, startId: Int): Int {
        when (intent?.action) {
            ACTION_START -> startVpn()
            ACTION_STOP -> stopVpn()
        }
        return START_STICKY
    }
    
    private fun startVpn() {
        try {
            // Create minimal VPN interface
            tunnel = Builder()
                .setSession("NexaLink")
                .addAddress("10.10.10.1", 24)
                .addDnsServer("8.8.8.8")
                .addRoute("0.0.0.0", 0)
                .establish()
            
            if (tunnel != null) {
                isRunning = true
                showNotification()
            }
        } catch (e: Exception) {
            e.printStackTrace()
            stopSelf()
        }
    }
    
    private fun stopVpn() {
        tunnel?.close()
        tunnel = null
        isRunning = false
        stopForeground(true)
        stopSelf()
    }
    
    override fun onRevoke() {
        stopVpn()
    }
    
    override fun onDestroy() {
        stopVpn()
        super.onDestroy()
    }
    
    private fun showNotification() {
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
            val channel = NotificationChannel(
                "nexalink_vpn",
                "NexaLink VPN",
                NotificationManager.IMPORTANCE_LOW
            )
            val manager = getSystemService(NotificationManager::class.java)
            manager.createNotificationChannel(channel)
        }
        
        val notification = Notification.Builder(this, "nexalink_vpn")
            .setContentTitle("NexaLink")
            .setContentText("VPN active")
            .setSmallIcon(android.R.drawable.ic_lock_lock)
            .setOngoing(true)
            .build()
        
        startForeground(1001, notification)
    }
}
