package com.nexalink.app.network

import com.wireguard.config.Config
import com.wireguard.config.InetAddresses
import com.wireguard.config.InetEndpoint
import com.wireguard.config.InetNetwork
import com.wireguard.config.Interface
import com.wireguard.config.Peer
import com.wireguard.crypto.Key
import com.wireguard.crypto.KeyPair
import java.net.Inet4Address
import java.net.URI

/**
 * A limited IPv4-only client profile. This constructs a WireGuard configuration;
 * it does NOT establish a VPN or imply that its peer can forward Internet traffic.
 * Secrets stay in memory and are never logged, persisted, or returned to Flutter.
 */
object GuestConfig {
    fun build(privateKey: String, peerPublicKey: String, guestAddress: String,
              endpoint: String, dnsAddress: String): Config {
        val localKey = KeyPair(Key.fromBase64(privateKey))
        val remoteKey = Key.fromBase64(peerPublicKey)
        require(remoteKey != localKey.publicKey) { "Peer and local public key must differ" }

        val address = InetNetwork.parse(guestAddress)
        val ip = address.address
        require(ip is Inet4Address && address.mask == 32 && isPrivate(ip)) {
            "A private IPv4 /32 guest address is required"
        }
        // Endpoint strings are untrusted; do not accept URI features WireGuard does not need.
        val endpointUri = URI("wg://$endpoint")
        require(endpointUri.host != null && endpointUri.userInfo == null &&
            endpointUri.port in 1..65535 && endpointUri.rawPath.isNullOrEmpty() &&
            endpointUri.rawQuery == null && endpointUri.rawFragment == null) { "Invalid endpoint" }
        val peerEndpoint = InetEndpoint.parse(endpoint)
        val dns = InetAddresses.parse(dnsAddress)
        require(dns is Inet4Address && !dns.isAnyLocalAddress && !dns.isLoopbackAddress &&
            !dns.isMulticastAddress && !dns.isLinkLocalAddress) { "A usable numeric IPv4 DNS address is required" }

        val local = Interface.Builder().setKeyPair(localKey).addAddress(address)
            .addDnsServer(dns).setMtu(1280).build()
        val peer = Peer.Builder().setPublicKey(remoteKey).setEndpoint(peerEndpoint)
            .addAllowedIp(InetNetwork.parse("0.0.0.0/0"))
            .setPersistentKeepalive(25).build()
        return Config.Builder().setInterface(local).addPeer(peer).build()
    }

    private fun isPrivate(ip: Inet4Address): Boolean {
        val b = ip.address.map { it.toInt() and 0xff }
        return b[0] == 10 || (b[0] == 172 && b[1] in 16..31) || (b[0] == 192 && b[1] == 168)
    }
}
