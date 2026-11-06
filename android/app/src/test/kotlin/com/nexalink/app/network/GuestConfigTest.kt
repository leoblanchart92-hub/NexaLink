package com.nexalink.app.network

import com.wireguard.crypto.KeyPair
import org.junit.Assert.*
import org.junit.Test

class GuestConfigTest {
    private val local = KeyPair()
    private val remote = KeyPair()
    private fun build(address: String = "10.77.0.2/32", endpoint: String = "198.51.100.2:51820", dns: String = "1.1.1.1", peer: String = remote.publicKey.toBase64()) =
        GuestConfig.build(local.privateKey.toBase64(), peer, address, endpoint, dns)

    @Test fun buildsWireGuardConfigWithFullIpv4Route() {
        val config = build()
        assertEquals(local.publicKey, config.`interface`.keyPair.publicKey)
        assertEquals(setOf("10.77.0.2/32"), config.`interface`.addresses.map { it.toString() }.toSet())
        assertEquals(setOf("1.1.1.1"), config.`interface`.dnsServers.map { it.hostAddress }.toSet())
        assertEquals(1280, config.`interface`.mtu.get().toInt())
        val peer = config.peers.single()
        assertEquals(remote.publicKey, peer.publicKey)
        assertEquals(setOf("0.0.0.0/0"), peer.allowedIps.map { it.toString() }.toSet())
        assertEquals(25, peer.persistentKeepalive.get().toInt())
        assertEquals(51820, peer.endpoint.get().port)
    }
    @Test fun rejectsUnsafeOrMalformedInputs() {
        val invalid = listOf<() -> Unit>(
            { build(address = "10.77.0.2/24") },
            { build(address = "1.2.3.4/32") },
            { build(address = "fd00::2/128") },
            { build(endpoint = "user@host:51820") },
            { build(endpoint = "host:51820/path") },
            { build(endpoint = "host:0") },
            { build(dns = "example.com") },
            { build(dns = "127.0.0.1") },
            { build(peer = local.publicKey.toBase64()) },
            { build(peer = "invalid") }
        )
        for (attempt in invalid) {
            try { attempt(); fail("Invalid profile was accepted") } catch (_: Exception) { /* expected */ }
        }
    }
}
