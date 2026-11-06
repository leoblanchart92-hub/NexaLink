package com.nexalink.app

import android.app.Activity
import android.content.Intent
import android.net.VpnService
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel

class MainActivity : FlutterActivity() {
    private val CHANNEL = "com.nexalink.app/vpn"
    private var vpnPermissionGranted = false

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, CHANNEL).setMethodCallHandler { call, result ->
            when (call.method) {
                "prepareVpn" -> {
                    try {
                        val intent = VpnService.prepare(this)
                        if (intent != null) {
                            // Need to request permission
                            startActivityForResult(intent, 0)
                            result.success(false)
                        } else {
                            // Already have permission
                            vpnPermissionGranted = true
                            result.success(true)
                        }
                    } catch (e: Exception) {
                        result.error("VPN_ERROR", "Failed to prepare VPN: ${e.message}", null)
                    }
                }
                "startVpn" -> {
                    try {
                        if (!vpnPermissionGranted) {
                            result.error("PERMISSION_ERROR", "VPN permission not granted", null)
                            return@setMethodCallHandler
                        }
                        
                        val intent = Intent(this, NexaLinkVpnService::class.java)
                        intent.action = NexaLinkVpnService.ACTION_START
                        
                        if (android.os.Build.VERSION.SDK_INT >= android.os.Build.VERSION_CODES.O) {
                            startForegroundService(intent)
                        } else {
                            startService(intent)
                        }
                        
                        // Wait a bit for service to start
                        Thread.sleep(500)
                        result.success(true)
                    } catch (e: Exception) {
                        result.error("VPN_ERROR", "Failed to start VPN: ${e.message}", null)
                    }
                }
                "stopVpn" -> {
                    try {
                        val intent = Intent(this, NexaLinkVpnService::class.java)
                        intent.action = NexaLinkVpnService.ACTION_STOP
                        startService(intent)
                        result.success(true)
                    } catch (e: Exception) {
                        result.error("VPN_ERROR", "Failed to stop VPN: ${e.message}", null)
                    }
                }
                "isVpnRunning" -> {
                    result.success(NexaLinkVpnService.isRunning)
                }
                else -> {
                    result.notImplemented()
                }
            }
        }
    }

    override fun onActivityResult(requestCode: Int, resultCode: Int, data: Intent?) {
        super.onActivityResult(requestCode, resultCode, data)
        if (requestCode == 0) {
            vpnPermissionGranted = (resultCode == Activity.RESULT_OK)
        }
    }
}
