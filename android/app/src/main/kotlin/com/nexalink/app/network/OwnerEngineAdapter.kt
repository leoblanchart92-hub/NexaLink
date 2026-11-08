package com.nexalink.app.network

import android.content.Context
import android.net.Network
import android.net.VpnService
import android.util.Log
import mobile.Mobile
import mobile.SocketBinder

/**
 * Experimental owner bridge. Not registered with Flutter or started by the app.
 * A future lifecycle owner must provide an authorized VpnService and a validated
 * cellular Network, stop on network loss/revoke and authenticate the peer first.
 * Starting is blocking: always invoke on a background thread.
 */
internal class OwnerEngineAdapter(context: Context, vpn: VpnService, network: Network) : LocalOwnerEngine {
    private val egress = CellularEgress(context)
    private val binder = object : SocketBinder {
        override fun bindSocket(fd: Int): Boolean = egress.protectAndBindFd(network, vpn, fd)
    }
    private val engine = run {
        check(NativeRuntimeGuard.reserve(NativeRuntimeGuard.Kind.OWNER)) { "A different Go runtime is already loaded" }
        Mobile.newEngine(binder)
    }

    override fun start(privateKey: String, guestPublicKey: String, guestAddress: String, port: Int): Int =
        try { engine.start(privateKey, guestPublicKey, guestAddress, port) } catch (failure: Exception) {
            // Only fixed, non-secret engine errors may be classified for diagnostics.
            val known = setOf("invalid WireGuard key", "invalid private key", "peer key matches local key",
                "private guest IPv4 required", "invalid port", "engine already running",
                "could not start protected WireGuard endpoint", "invalid WireGuard configuration",
                "could not read WireGuard state", "WireGuard port unavailable")
            val reason = if (failure.message in known) failure.message else "unclassified"
            Log.e("NexaLinkOwner", "Native start rejected: $reason")
            throw failure
        }

    fun statusJson(): String = engine.statusJSON()
    override fun stop() = engine.stop()
}
