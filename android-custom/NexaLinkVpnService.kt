package com.nexalink.app

import android.app.Activity
import android.app.Notification
import android.app.NotificationChannel
import android.app.NotificationManager
import android.app.PendingIntent
import android.content.Intent
import android.net.VpnService
import android.os.Build
import android.os.ParcelFileDescriptor
import androidx.core.app.NotificationCompat
import java.io.FileInputStream
import java.io.FileOutputStream
import java.util.concurrent.atomic.AtomicBoolean

class NexaLinkVpnService : VpnService() {
    
    companion object {
        const val ACTION_START = "com.nexalink.app.START_VPN"
        const val ACTION_STOP = "com.nexalink.app.STOP_VPN"
        const val CHANNEL_ID = "nexalink_vpn"
        const val NOTIFICATION_ID = 1001
        var instance: NexaLinkVpnService? = null
        var isRunning = false
    }
    
    private var tunnel: ParcelFileDescriptor? = null
    private var vpnThread: Thread? = null
    private val shouldRun = AtomicBoolean(false)
    
    override fun onCreate() {
        super.onCreate()
        instance = this
        createNotificationChannel()
    }
    
    override fun onStartCommand(intent: Intent?, flags: Int, startId: Int): Int {
        when (intent?.action) {
            ACTION_START -> {
                startVpn()
            }
            ACTION_STOP -> {
                stopVpn()
                stopSelf()
            }
        }
        return START_STICKY
    }
    
    private fun startVpn() {
        try {
            val builder = Builder()
                .setSession("NexaLink")
                .addAddress("10.10.10.1", 24)
                .addDnsServer("1.1.1.1")
                .addRoute("0.0.0.0", 0)
                .setMtu(1420)
            
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.Q) {
                builder.setMetered(false)
            }
            
            tunnel = builder.establish()
            
            if (tunnel == null) {
                stopSelf()
                return
            }
            
            isRunning = true
            shouldRun.set(true)
            
            // Start VPN thread to forward packets
            vpnThread = Thread {
                try {
                    val input = FileInputStream(tunnel!!.fileDescriptor)
                    val output = FileOutputStream(tunnel!!.fileDescriptor)
                    val packet = ByteArray(32767)
                    
                    while (shouldRun.get()) {
                        val length = input.read(packet)
                        if (length > 0) {
                            // Echo packets back (loopback for demo)
                            output.write(packet, 0, length)
                        }
                    }
                    
                    input.close()
                    output.close()
                } catch (e: Exception) {
                    e.printStackTrace()
                }
            }
            vpnThread?.start()
            
            // Show notification
            startForeground(NOTIFICATION_ID, createNotification())
            
        } catch (e: Exception) {
            e.printStackTrace()
            stopSelf()
        }
    }
    
    private fun stopVpn() {
        shouldRun.set(false)
        vpnThread?.interrupt()
        vpnThread = null
        
        tunnel?.close()
        tunnel = null
        
        isRunning = false
        instance = null
        
        stopForeground(true)
    }
    
    override fun onDestroy() {
        stopVpn()
        super.onDestroy()
    }
    
    override fun onRevoke() {
        stopVpn()
        stopSelf()
    }
    
    private fun createNotificationChannel() {
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
            val channel = NotificationChannel(
                CHANNEL_ID,
                "NexaLink VPN",
                NotificationManager.IMPORTANCE_LOW
            ).apply {
                description = "VPN connection notification"
            }
            val manager = getSystemService(NotificationManager::class.java)
            manager.createNotificationChannel(channel)
        }
    }
    
    private fun createNotification(): Notification {
        val pendingIntent = PendingIntent.getActivity(
            this, 0,
            packageManager.getLaunchIntentForPackage(packageName),
            PendingIntent.FLAG_IMMUTABLE
        )
        
        return NotificationCompat.Builder(this, CHANNEL_ID)
            .setContentTitle("NexaLink")
            .setContentText("VPN connection active")
            .setSmallIcon(android.R.drawable.ic_lock_lock)
            .setContentIntent(pendingIntent)
            .setOngoing(true)
            .build()
    }
}
