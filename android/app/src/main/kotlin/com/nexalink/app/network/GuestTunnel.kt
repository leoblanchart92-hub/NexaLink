package com.nexalink.app.network

import android.app.ActivityManager
import android.content.Context
import android.content.Intent
import android.net.VpnService
import android.os.Looper
import android.os.SystemClock
import com.wireguard.android.backend.GoBackend
import com.wireguard.android.backend.Tunnel
import com.wireguard.android.backend.Statistics
import com.wireguard.config.Config

/**
 * Native guest-side WireGuard adapter. Intentionally not exposed to Flutter while
 * peer authentication, revocation, gateway and relay are missing. A caller must
 * obtain explicit consent with prepareIntent() before start(). Never call on UI thread.
 * UP means only that the local interface started, NOT handshake or Internet access.
 */
class GuestTunnel(context: Context) {
    private val appContext = context.applicationContext
    private val backend = run {
        check(NativeRuntimeGuard.reserve(NativeRuntimeGuard.Kind.GUEST)) { "A different Go runtime is already loaded" }
        GoBackend(appContext)
    }
    private var ownsLease = false
    private val tunnel = object : Tunnel {
        override fun getName(): String = "nexalink"
        // DOWN does not mean Android has completed service destruction.
        override fun onStateChange(newState: Tunnel.State) { }
    }

    fun prepareIntent(): Intent? = VpnService.prepare(appContext)

    @Synchronized
    fun start(config: Config): Tunnel.State {
        requireWorkerThread()
        check(VpnService.prepare(appContext) == null) { "VPN consent is required" }
        check(VpnRoleLease.acquire(this)) { "Another NexaLink VPN role is active" }
        ownsLease = true
        return try {
            backend.setState(tunnel, Tunnel.State.UP, config).also {
                if (it != Tunnel.State.UP) releaseAfterServiceStops()
            }
        } catch (failure: Exception) {
            // If a failed start left a service behind, keep the lease rather than
            // allow a competing VPN. A later stop() can complete cleanup.
            try { releaseAfterServiceStops() } catch (cleanup: Exception) { failure.addSuppressed(cleanup) }
            throw failure
        }
    }

    @Synchronized
    fun stop(): Tunnel.State {
        requireWorkerThread()
        val state = backend.setState(tunnel, Tunnel.State.DOWN, null)
        if (ownsLease) releaseAfterServiceStops()
        return state
    }

    private fun releaseAfterServiceStops() {
        val manager = appContext.getSystemService(Context.ACTIVITY_SERVICE) as ActivityManager
        val deadline = SystemClock.elapsedRealtime() + 10000
        do {
            // Android O+ still lists services belonging to this app.
            @Suppress("DEPRECATION")
            val alive = manager.getRunningServices(100).any {
                it.service.className == GoBackend.VpnService::class.java.name
            }
            if (!alive) {
                VpnRoleLease.release(this)
                ownsLease = false
                return
            }
            Thread.sleep(50)
        } while (SystemClock.elapsedRealtime() < deadline)
        error("WireGuard service did not stop; VPN role remains reserved")
    }

    @Synchronized
    fun state(): Tunnel.State = backend.getState(tunnel)

    // Local encrypted byte totals only; neither a handshake nor Internet proof.
    @Synchronized
    internal fun statistics(): Statistics = backend.getStatistics(tunnel)

    private fun requireWorkerThread() {
        check(Looper.myLooper() != Looper.getMainLooper()) { "Use a background thread" }
    }
}
