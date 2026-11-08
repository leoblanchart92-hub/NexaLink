package com.nexalink.app.network

import android.content.Context
import android.net.ConnectivityManager
import android.net.Network
import android.net.NetworkCapabilities
import android.net.VpnService
import android.os.ParcelFileDescriptor
import java.io.IOException
import java.net.DatagramSocket
import java.net.Socket

// Pure policy: testable without Android, but capability reporting and socket
// binding still require real-device tests.
internal fun isAllowedCellular(cellular: Boolean, wifi: Boolean, vpn: Boolean, internet: Boolean, validated: Boolean): Boolean =
    cellular && !wifi && !vpn && internet && validated

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
        isAllowed(caps)
    }

    private fun isAllowed(caps: NetworkCapabilities?): Boolean = caps != null && isAllowedCellular(
        caps.hasTransport(NetworkCapabilities.TRANSPORT_CELLULAR),
        caps.hasTransport(NetworkCapabilities.TRANSPORT_WIFI),
        caps.hasTransport(NetworkCapabilities.TRANSPORT_VPN),
        caps.hasCapability(NetworkCapabilities.NET_CAPABILITY_INTERNET),
        caps.hasCapability(NetworkCapabilities.NET_CAPABILITY_VALIDATED),
    )

    internal fun isUsable(network: Network): Boolean = isAllowed(manager.getNetworkCapabilities(network))

    private fun checkNetwork(network: Network) {
        if (!isUsable(network)) throw IOException("Cellular network unavailable or unvalidated")
    }

    /**
     * Go owns fd. fromFd duplicates it; only the duplicate is closed here.
     * This must run synchronously before Go connects/sends on the socket.
     */
    fun protectAndBindFd(network: Network, vpn: VpnService, fd: Int): Boolean {
        if (fd < 0) return false
        return try {
            checkNetwork(network)
            if (!vpn.protect(fd)) return false
            ParcelFileDescriptor.fromFd(fd).use { duplicate -> network.bindSocket(duplicate.fileDescriptor) }
            true
        } catch (_: IOException) { false } catch (_: SecurityException) { false }
    }

    /** Protect first, then bind while unconnected. Caller owns and must close socket. */
    fun tcpSocket(network: Network, vpn: VpnService): Socket {
        val socket = Socket()
        try {
            checkNetwork(network)
            if (!vpn.protect(socket)) throw IOException("VPN socket protection failed")
            network.bindSocket(socket)
            return socket
        } catch (e: Exception) { socket.close(); throw e }
    }

    fun udpSocket(network: Network, vpn: VpnService): DatagramSocket {
        val socket = DatagramSocket(null)
        try {
            checkNetwork(network)
            if (!vpn.protect(socket)) throw IOException("VPN socket protection failed")
            network.bindSocket(socket)
            return socket
        } catch (e: Exception) { socket.close(); throw e }
    }
}
