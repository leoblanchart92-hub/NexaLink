package com.nexalink.app.network

import android.content.Context
import android.net.Network
import android.net.VpnService
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
    private val engine = Mobile.newEngine(binder)

    override fun start(privateKey: String, guestPublicKey: String, guestAddress: String, port: Int): Int =
        engine.start(privateKey, guestPublicKey, guestAddress, port)

    fun statusJson(): String = engine.statusJSON()
    override fun stop() = engine.stop()
}
