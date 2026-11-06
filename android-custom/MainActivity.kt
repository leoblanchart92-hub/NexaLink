package com.nexalink.app

import android.app.Activity
import android.content.Intent
import android.net.VpnService
import android.os.Build
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel

class MainActivity : FlutterActivity() {
    private val CHANNEL = "com.nexalink.app/vpn"
    private var vpnReady = false

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, CHANNEL).setMethodCallHandler { call, result ->
            when (call.method) {
                "prepareVpn" -> {
                    val intent = VpnService.prepare(this)
                    if (intent != null) {
                        startActivityForResult(intent, 100)
                        result.success(false)
                    } else {
                        vpnReady = true
                        result.success(true)
                    }
                }
                "startVpn" -> {
                    try {
                        val intent = Intent(this, NexaLinkVpnService::class.java)
                        intent.action = NexaLinkVpnService.ACTION_START
                        
                        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
                            startForegroundService(intent)
                        } else {
                            startService(intent)
                        }
                        
                        result.success(true)
                    } catch (e: Exception) {
                        result.error("VPN_ERROR", e.message, null)
                    }
                }
                "stopVpn" -> {
                    try {
                        val intent = Intent(this, NexaLinkVpnService::class.java)
                        intent.action = NexaLinkVpnService.ACTION_STOP
                        startService(intent)
                        result.success(true)
                    } catch (e: Exception) {
                        result.error("VPN_ERROR", e.message, null)
                    }
                }
                "isVpnRunning" -> {
                    result.success(NexaLinkVpnService.isRunning)
                }
                else -> result.notImplemented()
            }
        }
    }

    override fun onActivityResult(requestCode: Int, resultCode: Int, data: Intent?) {
        super.onActivityResult(requestCode, resultCode, data)
        if (requestCode == 100 && resultCode == Activity.RESULT_OK) {
            vpnReady = true
        }
    }
}
