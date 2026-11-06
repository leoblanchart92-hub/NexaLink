package com.nexalink.app.network

import android.content.Context
import android.net.ConnectivityManager
import android.net.Network
import android.net.NetworkCapabilities
import android.net.VpnService
import java.io.IOException
import java.net.DatagramSocket
import java.net.Socket

/**
 * Preliminary gateway egress primitive. No packets are forwarded by this class.
 * Selects only an existing validated cellular network; never falls back to Wi-Fi.
 * No active network request is made. The network may disappear at any time.
 */
class CellularEgress(context: Context) {
    private val manager = context.applicationContext.getSystemService(Context.CONNECTIVITY_SERVICE) as ConnectivityManager

    @Suppress("DEPRECATION") // allNetworks is available from API 21; active requests have different costs/lifecycle.
    fun validatedCellularNetwork(): Network? = manager.allNetworks.firstOrNull { network ->
        val caps = manager.getNetworkCapabilities(network)
        caps != null && caps.hasTransport(NetworkCapabilities.TRANSPORT_CELLULAR) &&
            !caps.hasTransport(NetworkCapabilities.TRANSPORT_VPN) &&
            caps.hasCapability(NetworkCapabilities.NET_CAPABILITY_INTERNET) &&
            caps.hasCapability(NetworkCapabilities.NET_CAPABILITY_VALIDATED)
    }

    /** Protect first, then bind while unconnected. Caller owns and must close socket. */
    fun tcpSocket(network: Network, vpn: VpnService): Socket {
        val socket = Socket()
        try {
            if (!vpn.protect(socket)) throw IOException("VPN socket protection failed")
            network.bindSocket(socket)
            return socket
        } catch (e: Exception) { socket.close(); throw e }
    }

    fun udpSocket(network: Network, vpn: VpnService): DatagramSocket {
        val socket = DatagramSocket(null)
        try {
            if (!vpn.protect(socket)) throw IOException("VPN socket protection failed")
            network.bindSocket(socket)
            return socket
        } catch (e: Exception) { socket.close(); throw e }
    }
}
