package com.nexalink.app

import android.app.Activity
import android.content.Intent
import android.net.VpnService
import android.os.Build
import android.os.ParcelFileDescriptor
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel
import java.io.FileDescriptor
import java.net.DatagramSocket
import java.net.InetSocketAddress

class MainActivity : FlutterActivity() {
    private val CHANNEL = "com.nexalink.app/vpn"
    private var vpnTunnel: ParcelFileDescriptor? = null

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, CHANNEL).setMethodCallHandler { call, result ->
            when (call.method) {
                "prepareVpn" -> {
                    val intent = VpnService.prepare(this)
                    if (intent != null) {
                        startActivityForResult(intent, 0)
                        result.success(false)
                    } else {
                        onActivityResult(0, Activity.RESULT_OK, null)
                        result.success(true)
                    }
                }
                "startVpn" -> {
                    try {
                        val config = call.argument<Map<String, Any>>("config")
                        val tunnelAddress = call.argument<String>("tunnelAddress") ?: "10.10.10.1/32"
                        val ownerPublicKey = call.argument<String>("ownerPublicKey") ?: ""
                        val guestPublicKey = call.argument<String>("guestPublicKey") ?: ""
                        val endpoint = call.argument<String>("endpoint") ?: ""
                        val port = call.argument<Int>("port") ?: 51820
                        
                        val builder = VpnService.Builder()
                            .setConfigureIntent(null)
                            .setSession("NexaLink")
                        
                        // Parse tunnel address
                        val address = tunnelAddress.split("/")[0]
                        builder.addAddress(address, 24)
                        builder.addDnsServer("1.1.1.1")
                        builder.addRoute("0.0.0.0", 0)
                        builder.setMtu(1420)
                        
                        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.Q) {
                            builder.setMetered(false)
                        }
                        
                        vpnTunnel = builder.establish()
                        result.success(vpnTunnel != null)
                    } catch (e: Exception) {
                        result.error("VPN_ERROR", "Failed to start VPN: ${e.message}", null)
                    }
                }
                "stopVpn" -> {
                    try {
                        vpnTunnel?.close()
                        vpnTunnel = null
                        result.success(true)
                    } catch (e: Exception) {
                        result.error("VPN_ERROR", "Failed to stop VPN: ${e.message}", null)
                    }
                }
                "isVpnRunning" -> {
                    result.success(vpnTunnel != null)
                }
                "getStats" -> {
                    result.success(mapOf(
                        "rx" to 0L,
                        "tx" to 0L
                    ))
                }
                else -> {
                    result.notImplemented()
                }
            }
        }
    }

    override fun onActivityResult(requestCode: Int, resultCode: Int, data: Intent?) {
        super.onActivityResult(requestCode, resultCode, data)
        if (requestCode == 0 && resultCode == Activity.RESULT_OK) {
            // VPN permission granted
        }
    }

    override fun onDestroy() {
        super.onDestroy()
        vpnTunnel?.close()
        vpnTunnel = null
    }
}
