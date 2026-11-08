package com.nexalink.app.network

import android.app.Notification
import android.app.NotificationChannel
import android.app.NotificationManager
import android.content.Context
import android.content.Intent
import android.content.pm.ServiceInfo
import android.net.ConnectivityManager
import android.net.Network
import android.net.NetworkCapabilities
import android.net.NetworkRequest
import android.net.VpnService
import android.os.Build
import android.os.ParcelFileDescriptor
import android.system.OsConstants
import android.util.Log
import java.util.concurrent.Executors

/** Never passed in an Intent, persisted, logged, or exposed to Flutter.
 * There is intentionally no product caller until authenticated pairing and
 * routing are reviewed. Holding Strings is not secure erasure. */
internal class OwnerSessionParameters(
    val privateKey: String, val guestPublicKey: String, val guestAddress: String, val port: Int,
)
internal object OwnerSessionRequest {
    private var pending: OwnerSessionParameters? = null
    @Synchronized fun stage(parameters: OwnerSessionParameters): Boolean {
        if (pending != null) return false
        pending = parameters
        return true
    }
    @Synchronized fun take(): OwnerSessionParameters? = pending.also { pending = null }
    @Synchronized fun clear() { pending = null }
}

internal enum class OwnerServiceState { STOPPED, STARTING, RUNNING_LOCAL, STOPPING }
internal object OwnerServiceStateMonitor {
    @Volatile var state: OwnerServiceState = OwnerServiceState.STOPPED
    @Volatile var failure: String? = null
}

/**
 * Owner VPN lifecycle. The Android TUN is only a control interface with no
 * Internet route. It is NOT the input to gVisor. WireGuard receives encrypted
 * UDP and owns an in-memory TUN; its authenticated packets go to gVisor there.
 * This service is not started by the product UI until security/routing are ready.
 */
class OwnerVpnService : VpnService() {
    private val lock = Any()
    private val worker = Executors.newSingleThreadExecutor()
    private var stopping = false
    private var started = false
    private var tun: ParcelFileDescriptor? = null
    private var engine: OwnerEngineAdapter? = null
    private var callback: ConnectivityManager.NetworkCallback? = null
    private val manager by lazy { getSystemService(Context.CONNECTIVITY_SERVICE) as ConnectivityManager }
    private val egress by lazy { CellularEgress(this) }

    override fun onStartCommand(intent: Intent?, flags: Int, startId: Int): Int {
        synchronized(lock) {
            if (started || stopping) return START_NOT_STICKY
            started = true
            OwnerServiceStateMonitor.failure = null
            OwnerServiceStateMonitor.state = OwnerServiceState.STARTING
        }
        val parameters = OwnerSessionRequest.take()
        if (parameters == null || prepare(this) != null || !VpnRoleLease.acquire(this)) {
            requestStop()
            return START_NOT_STICKY
        }
        try {
            showForeground()
            worker.execute { startOnWorker(parameters) }
        } catch (_: Exception) { requestStop() }
        return START_NOT_STICKY
    }

    private fun startOnWorker(parameters: OwnerSessionParameters) {
        var phase = "network"
        try {
            if (isStopping()) return
            val network = egress.validatedCellularNetwork() ?: throw IllegalStateException("No validated cellular network")
            phase = "watcher"
            val watcher = object : ConnectivityManager.NetworkCallback() {
                override fun onLost(lost: Network) { if (lost == network) requestStop() }
                override fun onCapabilitiesChanged(changed: Network, caps: NetworkCapabilities) {
                    if (changed == network && !egress.isUsable(network)) requestStop()
                }
            }
            manager.registerNetworkCallback(NetworkRequest.Builder()
                .addTransportType(NetworkCapabilities.TRANSPORT_CELLULAR).build(), watcher)
            synchronized(lock) {
                if (stopping) { manager.unregisterNetworkCallback(watcher); return }
                callback = watcher
            }
            if (!egress.isUsable(network) || isStopping()) throw IllegalStateException("Cellular network changed")
            phase = "tun"
            val fd = Builder().setSession("NexaLink propriétaire — préparation")
                .addAddress("10.254.254.1", 32)
                // No default routes; do not blackhole unrelated address families.
                .allowFamily(OsConstants.AF_INET).allowFamily(OsConstants.AF_INET6)
                .setUnderlyingNetworks(arrayOf(network)).establish()
                ?: throw IllegalStateException("VPN consent revoked")
            synchronized(lock) {
                if (stopping) { fd.close(); return }
                tun = fd
            }
            if (!egress.isUsable(network) || isStopping()) throw IllegalStateException("Cellular network changed")
            phase = "native-create"
            val local = OwnerEngineAdapter(this, this, network)
            synchronized(lock) {
                if (stopping) return
                engine = local
            }
            phase = "native-start"
            local.start(parameters.privateKey, parameters.guestPublicKey, parameters.guestAddress, parameters.port)
            // Protection/binding also checks this on every new socket. No fallback.
            synchronized(lock) {
                if (!stopping && egress.isUsable(network)) OwnerServiceStateMonitor.state = OwnerServiceState.RUNNING_LOCAL
                else requestStop()
            }
        } catch (failure: Exception) {
            // Class only: native errors and input values may contain secrets.
            OwnerServiceStateMonitor.failure = "$phase:${failure.javaClass.simpleName}"
            Log.e("NexaLinkOwner", "Owner startup failed at $phase: ${failure.javaClass.simpleName}")
            requestStop()
        }
    }

    private fun isStopping(): Boolean = synchronized(lock) { stopping }

    private fun requestStop() {
        val oldTun: ParcelFileDescriptor?
        val oldCallback: ConnectivityManager.NetworkCallback?
        synchronized(lock) {
            if (stopping) return
            stopping = true
            OwnerServiceStateMonitor.state = OwnerServiceState.STOPPING
            oldTun = tun; tun = null
            oldCallback = callback; callback = null
        }
        try { oldTun?.close() } catch (_: Exception) { }
        if (oldCallback != null) try { manager.unregisterNetworkCallback(oldCallback) } catch (_: Exception) { }
        worker.execute {
            // Queued behind any in-flight start; lease held until native stop returns.
            var closed = false
            try { engine?.stop(); closed = true } finally {
                engine = null
                // If cleanup fails, retain the lease rather than permit a competing VPN.
                if (closed) {
                    VpnRoleLease.release(this)
                    OwnerServiceStateMonitor.state = OwnerServiceState.STOPPED
                }
                stopForeground(true)
                stopSelf()
                worker.shutdown()
            }
        }
    }

    override fun onRevoke() { requestStop(); super.onRevoke() }
    override fun onDestroy() { OwnerSessionRequest.clear(); requestStop(); super.onDestroy() }

    private fun showForeground() {
        val id = "nexalink_owner_vpn"
        val nm = getSystemService(Context.NOTIFICATION_SERVICE) as NotificationManager
        if (Build.VERSION.SDK_INT >= 26) nm.createNotificationChannel(NotificationChannel(id, "NexaLink VPN", NotificationManager.IMPORTANCE_LOW))
        @Suppress("DEPRECATION")
        val builder = if (Build.VERSION.SDK_INT >= 26) Notification.Builder(this, id) else Notification.Builder(this)
        val notification = builder.setContentTitle("NexaLink — préparation VPN")
            .setContentText("Service local expérimental, partage non validé")
            .setSmallIcon(android.R.drawable.stat_sys_warning).setOngoing(true).build()
        if (Build.VERSION.SDK_INT >= 34) startForeground(7401, notification, ServiceInfo.FOREGROUND_SERVICE_TYPE_SPECIAL_USE)
        else startForeground(7401, notification)
    }
}
