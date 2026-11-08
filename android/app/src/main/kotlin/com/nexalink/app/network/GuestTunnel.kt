package com.nexalink.app.network

import android.content.Context
import android.content.Intent
import android.net.VpnService
import android.os.Looper
import com.wireguard.android.backend.GoBackend
import com.wireguard.android.backend.Tunnel
import com.wireguard.config.Config

/**
 * Native guest-side WireGuard adapter. Intentionally not exposed to Flutter while
 * peer authentication, revocation, gateway and relay are missing. A caller must
 * obtain explicit consent with prepareIntent() before start(). Never call on UI thread.
 * UP means only that the local interface started, NOT handshake or Internet access.
 */
class GuestTunnel(context: Context) {
    private val appContext = context.applicationContext
    private val backend = GoBackend(appContext)
    private val tunnel = object : Tunnel {
        override fun getName(): String = "nexalink"
        override fun onStateChange(newState: Tunnel.State) {
            if (newState == Tunnel.State.DOWN) VpnRoleLease.release(this@GuestTunnel)
        }
    }

    fun prepareIntent(): Intent? = VpnService.prepare(appContext)

    @Synchronized
    fun start(config: Config): Tunnel.State {
        requireWorkerThread()
        check(VpnService.prepare(appContext) == null) { "VPN consent is required" }
        check(VpnRoleLease.acquire(this)) { "Another NexaLink VPN role is active" }
        return try {
            backend.setState(tunnel, Tunnel.State.UP, config).also {
                if (it != Tunnel.State.UP) VpnRoleLease.release(this)
            }
        } catch (failure: Exception) {
            VpnRoleLease.release(this)
            throw failure
        }
    }

    @Synchronized
    fun stop(): Tunnel.State {
        requireWorkerThread()
        return backend.setState(tunnel, Tunnel.State.DOWN, null)
    }

    @Synchronized
    fun state(): Tunnel.State = backend.getState(tunnel)

    private fun requireWorkerThread() {
        check(Looper.myLooper() != Looper.getMainLooper()) { "Use a background thread" }
    }
}
